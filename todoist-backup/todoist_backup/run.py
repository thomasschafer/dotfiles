"""One backup run: fetch, write, verify, detect deletions, commit and push."""

from __future__ import annotations

import fcntl
import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from . import fetch, snapshot, verify
from .api import ApiError, AuthError, OfflineError, TodoistClient
from .auth import CredentialsMissing, ReauthorizeNeeded, ScopeError
from .config import ALERT_REPEAT_SECONDS, STALE_AFTER_SECONDS, Config
from .keychain import KeychainLocked
from .notify import Alert, Notifier
from .repo import GitOffline, RemoteState, Repo
from .state import State

log = logging.getLogger(__name__)

LIVE_CHECK_ATTEMPTS = 2
RECENT_COMPLETED = timedelta(days=7)


class VerificationError(Exception):
    pass


@dataclass
class Deps:
    config: Config
    client: TodoistClient
    secrets: Callable[[], list[str]]
    notifier: Notifier
    clock: Callable[[], float]


@dataclass
class Report:
    """What a run found worth alerting on, beyond outright failure."""

    history: list[str] = field(default_factory=list)
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
        state = State.load(config.state_file, deps.clock())
        state.last_attempt = deps.clock()
        code = 1
        try:
            report = backup(deps, state)
            code = _conclude(deps, state, report)
        except (OfflineError, GitOffline, KeychainLocked) as e:
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


def _conclude(deps: Deps, state: State, report: Report) -> int:
    for problem in report.history:
        alert(deps, state, Alert.HISTORY, problem)
    for drop in report.drops:
        sample = "; ".join(drop.names[:5])
        alert(
            deps,
            state,
            Alert.DELETIONS,
            f"{drop.describe()} since the last snapshot. Examples: {sample}. "
            "Run `todoist-backup restore-plan --ref HEAD~1` to see what's gone.",
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
            report.history.append(
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

    remote = repo.fetch_remote()
    if remote is RemoteState.EMPTY and state.last_pushed:
        report.history.append("The branch on GitHub was missing; restoring it from the local copy.")
    elif remote is RemoteState.AHEAD:
        if repo.head() is None:
            repo.fast_forward()
        else:
            report.history.append(
                "GitHub has commits this job didn't make. Not pushing; check the repo."
            )
            push_allowed = False
    elif remote is RemoteState.DIVERGED:
        report.history.append(
            "GitHub history differs from the local copy: one was rewritten. Not pushing; "
            "the local clone still has the full history."
        )
        push_allowed = False
    return push_allowed


def _commit_message(files: snapshot.Files, drops: list[verify.Drop], now: datetime) -> str:
    counts = ", ".join(
        f"{path.removeprefix('sync/').removesuffix('.json')}={len(value)}"
        for path, value in sorted(files.items())
        if path
        in (
            "sync/items.json",
            "sync/projects.json",
            "sync/sections.json",
            "sync/labels.json",
            "sync/notes.json",
        )
    )
    completed = sum(len(v) for p, v in files.items() if p.startswith("completed/"))
    subject = f"Snapshot {now.strftime('%Y-%m-%d %H:%M')} UTC"
    if drops:
        subject = "DELETIONS DETECTED: " + "; ".join(d.describe() for d in drops)
    return f"{subject}\n\n{counts}, completed={completed}\n"


def backup(deps: Deps, state: State) -> Report:
    config, client = deps.config, deps.client
    report = Report()
    repo = Repo(config)
    push_allowed = _prepare_repo(repo, state, report)
    previous = repo.read_files_at("HEAD", ["sync/", "archived/"]) if repo.head() else {}

    for attempt in range(1, LIVE_CHECK_ATTEMPTS + 1):
        now = datetime.fromtimestamp(deps.clock(), timezone.utc)
        fetched = fetch.fetch_all(client, config.data_dir, now)
        snapshot.write_files(config.data_dir, fetched.files)
        if problems := verify.verify_written(config.data_dir, fetched.files):
            raise VerificationError("; ".join(problems))

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

    report.drops = verify.detect_deletions(previous, fetched.files) if previous else []
    report.committed = repo.commit_if_changed(
        _commit_message(fetched.files, report.drops, now), deps.secrets()
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
