"""One backup run: fetch, write, verify, detect deletions, commit and push."""

from __future__ import annotations

import fcntl
import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from . import fetch, snapshot, verify
from .api import ApiError, AuthError, ConnectionLost, OfflineError, TodoistClient
from .auth import CredentialsMissing, ReauthorizeNeeded, ScopeError
from .config import ALERT_REPEAT_SECONDS, STALE_AFTER_SECONDS, Config
from .keychain import KeychainLocked
from .notify import Alert, Notifier
from .repo import GitOffline, RemoteState, Repo
from .state import State

log = logging.getLogger(__name__)

LIVE_CHECK_ATTEMPTS = 2
RECENT_COMPLETED = timedelta(days=7)
# Runs that fire on wake often start before the network is back.
NETWORK_WAIT_SECONDS = 120
NETWORK_RETRY_SECONDS = 15
NETWORK_ERRORS = (OfflineError, ConnectionLost, GitOffline)
# Deletions are compared with the previous snapshot and with the one from a day earlier,
# so deletions spread over several runs are still caught.
DAY_BASELINE = timedelta(hours=24)
ALERTED_MISSING_RETENTION_SECONDS = 7 * 24 * 3600


class VerificationError(Exception):
    pass


@dataclass
class Deps:
    config: Config
    client: TodoistClient
    secrets: Callable[[], list[str]]
    notifier: Notifier
    clock: Callable[[], float]
    sleep: Callable[[float], None]


@dataclass
class Report:
    """What a run found worth alerting on, beyond outright failure."""

    # Problems that stop pushing until someone looks.
    history: list[str] = field(default_factory=list)
    # Problems the run repaired itself.
    repaired: list[str] = field(default_factory=list)
    verification: list[str] = field(default_factory=list)
    drops: list[verify.Drop] = field(default_factory=list)
    committed: str | None = None
    pushed: bool = False


def alert(deps: Deps, state: State, kind: Alert, message: str) -> None:
    log.error("ALERT %s: %s", kind.value, message)
    now = deps.clock()
    last = state.alerted_at.get(kind.value)
    if kind.rate_limited and last is not None and now - last < ALERT_REPEAT_SECONDS:
        log.info("not notifying: a %s alert was shown recently", kind.value)
        return
    deps.notifier.notify(kind, message)
    state.alerted_at[kind.value] = now


def run(deps: Deps) -> int:
    """Entry point for scheduled and manual runs. Returns the process exit code."""
    config = deps.config
    config.state_dir.mkdir(parents=True, exist_ok=True)
    with config.run_lock.open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            log.info("another run is in progress; exiting")
            return 0
        # Replaced below; this keeps the finally block working if loading fails.
        state = State(installed_at=deps.clock())
        code = 1
        try:
            state, problem = State.load_or_reset(config.state_file, deps.clock())
            state.last_attempt = deps.clock()
            if problem:
                alert(deps, state, Alert.FAILED, f"State file was corrupt: {problem}")
            report = _backup_when_online(deps, state)
            code = _conclude(deps, state, report)
        except (*NETWORK_ERRORS, KeychainLocked) as e:
            log.info("skipping run, offline or keychain locked: %s", e)
            state.last_result = "offline"
            code = 0
        except (CredentialsMissing, ReauthorizeNeeded, ScopeError, AuthError) as e:
            state.last_result = f"auth: {e}"
            alert(deps, state, Alert.REAUTHORIZE, f"{e}. Run `todoist-backup setup-token`.")
        except VerificationError as e:
            state.last_result = f"verification: {e}"
            alert(deps, state, Alert.VERIFICATION, f"Snapshot not committed: {e}")
        except Exception as e:
            log.exception("run failed")
            state.last_result = f"failed: {type(e).__name__}: {e}"
            short = str(e) if not isinstance(e, ApiError) else f"Todoist API error {e.status}"
            alert(deps, state, Alert.FAILED, f"Run failed: {short[:200]}")
        finally:
            check_stale(deps, state)
            state.save(config.state_file)
        return code


def _backup_when_online(deps: Deps, state: State) -> Report:
    deadline = deps.clock() + NETWORK_WAIT_SECONDS
    while True:
        try:
            return backup(deps, state)
        except NETWORK_ERRORS as e:
            if deps.clock() >= deadline:
                raise
            log.info("network unavailable (%s); retrying in %ds", e, NETWORK_RETRY_SECONDS)
            deps.sleep(NETWORK_RETRY_SECONDS)


def _conclude(deps: Deps, state: State, report: Report) -> int:
    for problem in report.history:
        alert(deps, state, Alert.HISTORY, problem)
    for note in report.repaired:
        alert(deps, state, Alert.REPAIRED, note)
    for drop in report.drops:
        alert(
            deps,
            state,
            Alert.DELETIONS,
            f"{drop.describe()}. Run `todoist-backup restore-plan --ref HEAD~1` to see what's "
            "gone, or `--before <date>` for an earlier snapshot.",
        )
    if report.verification:
        alert(
            deps,
            state,
            Alert.VERIFICATION,
            f"Snapshot doesn't match live data: {report.verification[0]}",
        )
    ok = not report.history and not report.verification and report.pushed
    state.last_result = "ok" if ok else "completed with problems"
    if ok:
        state.last_success = deps.clock()
        log.info(
            "run succeeded (%s)",
            f"committed {report.committed[:12]}" if report.committed else "no changes",
        )
    return 0 if ok else 1


def check_stale(deps: Deps, state: State) -> None:
    reference = state.last_success or state.installed_at
    if deps.clock() - reference > STALE_AFTER_SECONDS:
        when = (
            datetime.fromtimestamp(state.last_success, timezone.utc).isoformat(timespec="minutes")
            if state.last_success
            else "never"
        )
        alert(deps, state, Alert.STALE, f"No successful backup in over 24 hours (last: {when}).")


def _prepare_repo(repo: Repo, state: State, report: Report) -> bool:
    """Clones or checks the data repo and its remote. Returns whether pushing is safe."""
    if not repo.exists():
        repo.clone()
        if state.last_pushed:
            report.repaired.append(
                "The local data repo was missing and has been re-cloned from GitHub."
            )
    else:
        repo.configure()

    push_allowed = True
    if state.last_pushed and not repo.contains(state.last_pushed):
        report.history.append(
            f"Local history no longer contains the last pushed commit {state.last_pushed[:12]}: "
            "it may have been rewritten. Not pushing; check both copies."
        )
        push_allowed = False

    remote_state = repo.fetch_remote()
    remote = repo.remote_head()
    if remote_state is RemoteState.EMPTY and state.last_pushed:
        report.repaired.append(
            "The branch on GitHub was missing; restoring it from the local copy."
        )
    elif (
        remote_state is RemoteState.IN_SYNC
        and state.last_pushed
        and remote is not None
        and remote != state.last_pushed
        and repo.is_ancestor(remote, state.last_pushed)
    ):
        report.repaired.append(
            "GitHub was reset to an older commit; pushing the full history back."
        )
    elif remote_state is RemoteState.AHEAD:
        if repo.head() is None:
            repo.fast_forward()
        else:
            report.history.append(
                "GitHub has commits this job didn't make. Not pushing; check the repo."
            )
            push_allowed = False
    elif remote_state is RemoteState.DIVERGED:
        report.history.append(
            "GitHub history differs from the local copy: one was rewritten. Not pushing; "
            "the local clone still has the full history."
        )
        push_allowed = False
    return push_allowed


def _commit_message(files: snapshot.Files, drops: list[verify.Drop], now: datetime) -> str:
    counts = ", ".join(
        f"{kind}={len(snapshot.objects_by_id(files, paths))}" for kind, paths in verify.ACTIVE_KINDS
    )
    completed = len(snapshot.completed_items(files))
    subject = f"Snapshot {now.strftime('%Y-%m-%d %H:%M')} UTC"
    if drops:
        subject = "DELETIONS DETECTED: " + "; ".join(d.describe() for d in drops)
    return f"{subject}\n\nactive {counts}, completed={completed}\n"


def _detect_deletions(
    deps: Deps,
    repo: Repo,
    state: State,
    previous: snapshot.Files,
    current: snapshot.Files,
    now: datetime,
) -> list[verify.Drop]:
    """Deletions not already reported, against the last snapshot and a day-old one."""
    head = repo.head()
    if head is None:
        return []
    candidates = verify.detect_deletions(
        previous, current, datetime.fromisoformat(repo.commit_time(head)), "the last snapshot"
    )
    day_old = repo.commit_before(fetch.iso(now - DAY_BASELINE))
    if day_old is not None and day_old != head:
        day_time = datetime.fromisoformat(repo.commit_time(day_old))
        baseline = repo.read_files_at(day_old, ["sync/", "archived/"])
        label = f"the snapshot of {day_time.astimezone(timezone.utc):%Y-%m-%d %H:%M} UTC"
        candidates += verify.detect_deletions(baseline, current, day_time, label)

    timestamp = deps.clock()
    state.alerted_missing = {
        i: t
        for i, t in state.alerted_missing.items()
        if timestamp - t < ALERTED_MISSING_RETENTION_SECONDS
    }
    drops: dict[str, verify.Drop] = {}
    for drop in candidates:
        if not drop.missing - state.alerted_missing.keys():
            log.info("already reported: %s", drop.describe())
            continue
        # One alert per kind: the one covering the most objects.
        if drop.kind not in drops or len(drop.missing) > len(drops[drop.kind].missing):
            drops[drop.kind] = drop
    for drop in drops.values():
        log.warning("%s; ids: %s", drop.describe(), ", ".join(sorted(drop.missing)))
        state.alerted_missing.update({i: timestamp for i in drop.missing})
    return list(drops.values())


def backup(deps: Deps, state: State) -> Report:
    config, client = deps.config, deps.client
    report = Report()
    repo = Repo(config)
    push_allowed = _prepare_repo(repo, state, report)
    previous = (
        repo.read_files_at("HEAD", [f"{d}/" for d in snapshot.MANAGED_DIRS]) if repo.head() else {}
    )
    # From the last commit, not the working tree, so local edits can't shrink the history.
    existing_completed = snapshot.completed_items(previous)

    for attempt in range(1, LIVE_CHECK_ATTEMPTS + 1):
        now = datetime.fromtimestamp(deps.clock(), timezone.utc)
        fetched = fetch.fetch_all(client, existing_completed, now)
        snapshot.write_files(config.data_dir, fetched.files)
        if problems := verify.verify_written(config.data_dir, fetched.files):
            raise VerificationError("; ".join(problems))
        if lost := verify.lost_completions(existing_completed, fetched.files):
            raise VerificationError(lost)

        live = fetch.fetch_live_view(client)
        recent = fetch.fetch_completed(client, now - RECENT_COMPLETED, now)
        report.verification = verify.compare_with_live(
            fetched.files, live
        ) + verify.check_completed(fetched.files, recent)
        if not report.verification:
            break
        log.warning(
            "attempt %d: snapshot differs from live data, probably edits during the run: %s",
            attempt,
            report.verification,
        )

    report.drops = _detect_deletions(deps, repo, state, previous, fetched.files, now)
    report.committed = repo.commit_if_changed(
        _commit_message(fetched.files, report.drops, now), deps.secrets(), now
    )
    if report.committed:
        log.info("committed %s", report.committed)

    if push_allowed:
        if repo.unpushed():
            repo.push()
            log.info("pushed to GitHub")
        report.pushed = True
        state.last_pushed = repo.head()
    return report
