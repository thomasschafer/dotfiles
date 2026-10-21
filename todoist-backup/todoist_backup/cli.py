from __future__ import annotations

import argparse
import logging
import logging.handlers
import os
import subprocess
import sys
import time
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from pathlib import Path

from . import fetch, restore_plan, snapshot
from .api import TodoistClient
from .auth import CredentialsMissing, KeychainTokenSource
from .config import (
    LOG_BACKUPS,
    LOG_MAX_BYTES,
    OAUTH_REDIRECT_URI,
    REPO_SLUG,
    STALE_AFTER_SECONDS,
    Config,
)
from .keychain import MacKeychain
from .notify import MacNotifier
from .oauth_setup import SetupError
from .repo import GitError, GitOffline, Repo
from .run import Deps, run
from .state import State, StateCorrupt

LAUNCHD_LABEL = "org.nix-community.home.todoist-backup"


def _setup_logging(config: Config, verbose: bool) -> None:
    config.state_dir.mkdir(parents=True, exist_ok=True)
    # launchd appends to this forever, so cap it here.
    if config.launchd_log.exists() and config.launchd_log.stat().st_size > LOG_MAX_BYTES:
        config.launchd_log.write_text("")
    handler = logging.handlers.RotatingFileHandler(
        config.log_file, maxBytes=LOG_MAX_BYTES, backupCount=LOG_BACKUPS
    )
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
    root = logging.getLogger()
    root.setLevel(logging.INFO)
    root.addHandler(handler)
    if verbose or sys.stderr.isatty():
        console = logging.StreamHandler()
        console.setFormatter(logging.Formatter("%(levelname)s: %(message)s"))
        root.addHandler(console)


def _tokens(config: Config) -> KeychainTokenSource:
    return KeychainTokenSource(MacKeychain(), config.keychain_service, config.token_lock)


def cmd_run(config: Config, args: argparse.Namespace) -> int:
    tokens = _tokens(config)
    deps = Deps(
        config=config,
        client=TodoistClient(tokens),
        secrets=tokens.secrets,
        notifier=MacNotifier(),
        clock=time.time,
        sleep=time.sleep,
    )
    return run(deps)


def cmd_restore_plan(config: Config, args: argparse.Namespace) -> int:
    repo = Repo(config)
    if not repo.exists():
        print(f"No data repo at {config.data_dir}", file=sys.stderr)
        return 1
    ref = repo.commit_before(args.before) if args.before else repo.resolve(args.ref)
    if ref is None:
        print(f"No snapshot before {args.before}", file=sys.stderr)
        return 1
    snapshot_time = repo.commit_time(ref)
    snap = repo.read_files_at(ref, ["sync/", "archived/"])
    client = TodoistClient(_tokens(config))
    live = fetch.fetch_live_view(client)
    since = datetime.fromisoformat(snapshot_time) - timedelta(days=1)
    completed = fetch.fetch_completed(client, since, datetime.now(UTC))
    plan = restore_plan.build_plan(
        ref,
        snapshot_time,
        snap,
        live,
        frozenset(snapshot.completed_key(i)[0] for i in completed),
    )
    print(restore_plan.to_json(plan) if args.json else restore_plan.render(plan), end="")
    return 0


def _launchd_status() -> str:
    result = subprocess.run(
        ["/bin/launchctl", "print", f"gui/{os.getuid()}/{LAUNCHD_LABEL}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return "not loaded"
    fields = {}
    for line in result.stdout.splitlines():
        key, _, value = line.strip().partition(" = ")
        if key in ("state", "last exit code", "run interval"):
            fields[key] = value
    return ", ".join(f"{k}: {v}" for k, v in fields.items()) or "loaded"


def _ago(timestamp: float | None) -> str:
    if timestamp is None:
        return "never"
    when = datetime.fromtimestamp(timestamp).isoformat(sep=" ", timespec="minutes")
    return f"{when} ({(time.time() - timestamp) / 3600:.1f}h ago)"


def cmd_status(config: Config, args: argparse.Namespace) -> int:
    healthy = True
    print(f"Data repo:      {config.data_dir}")
    print(f"Logs:           {config.log_file}")
    print(f"launchd agent:  {_launchd_status()}")
    try:
        state = State.load(config.state_file, time.time()) if config.state_file.exists() else None
    except StateCorrupt as e:
        print(f"State:          CORRUPT ({e}); the next run resets it")
        state, healthy = None, False
    if state is None:
        if healthy:
            print("State:          no runs yet")
        healthy = False
    else:
        print(f"Last success:   {_ago(state.last_success)}")
        print(f"Last attempt:   {_ago(state.last_attempt)} -> {state.last_result}")
        if state.last_success is None or time.time() - state.last_success > STALE_AFTER_SECONDS:
            healthy = False
    try:
        _tokens(config).load()
        print("Credentials:    present in the keychain")
    except CredentialsMissing:
        print("Credentials:    MISSING, run `todoist-backup setup-token`")
        healthy = False
    repo = Repo(config)
    if repo.exists():
        print(f"Last commit:    {repo.last_commit_summary()}")
        print(f"Unpushed:       {'yes' if repo.unpushed() else 'no'} (as of the last fetch)")
        files = snapshot.read_files(config.data_dir)
        counts = {
            p: len(v)
            for p, v in files.items()
            if isinstance(v, list) and not p.startswith("completed/")
        }
        completed = sum(len(v) for p, v in files.items() if p.startswith("completed/"))
        print("Counts:         " + ", ".join(f"{p}={n}" for p, n in sorted(counts.items()) if n))
        print(f"                completed={completed}")
    else:
        print("Last commit:    no data repo yet")
        healthy = False
    print(f"\nHealthy: {'yes' if healthy else 'NO'}")
    return 0 if healthy else 1


def cmd_setup_token(config: Config, args: argparse.Namespace) -> int:
    from .oauth_setup import setup_token

    setup_token(_tokens(config))
    return 0


def _offer(missing: str, instructions: str) -> bool:
    """Explains what's missing and asks whether to set it up now. Warns instead when
    there's no terminal to prompt in."""
    if not sys.stdin.isatty():
        print(f"Warning: todoist-backup: {missing}; run `todoist-backup setup`", file=sys.stderr)
        return False
    print(f"\ntodoist-backup: {missing}.\n{instructions}")
    if input("Set it up now? [y/N] ").strip().lower() == "y":
        return True
    print(
        "Skipped. Run `todoist-backup setup` later; backups fail until it's done.", file=sys.stderr
    )
    return False


def _deploy_key_works(config: Config) -> bool | None:
    """Whether GitHub accepts the deploy key for the data repo; None if offline."""
    try:
        Repo(config).git("ls-remote", "--heads", config.remote_url, cwd=Path.home())
        return True
    except GitOffline:
        return None
    except GitError:
        return False


def _setup_deploy_key(config: Config) -> None:
    """Creates the deploy key if needed and adds it to the data repo with the gh login."""
    if subprocess.run(["gh", "auth", "status"], capture_output=True, check=False).returncode:
        raise SetupError("gh isn't logged in; run `gh auth login`, then `todoist-backup setup`")
    host = subprocess.run(
        ["/usr/sbin/scutil", "--get", "LocalHostName"], capture_output=True, text=True, check=True
    ).stdout.strip()
    created = False
    if not config.deploy_key.exists():
        config.deploy_key.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        subprocess.run(
            [
                "ssh-keygen",
                "-q",
                "-t",
                "ed25519",
                "-N",
                "",
                "-C",
                f"todoist-backup@{host}",
                "-f",
                str(config.deploy_key),
            ],
            check=True,
        )
        created = True
    title = f"todoist-backup ({host})"
    added = subprocess.run(
        [
            "gh",
            "repo",
            "deploy-key",
            "add",
            f"{config.deploy_key}.pub",
            "-R",
            REPO_SLUG,
            "--allow-write",
            "--title",
            title,
        ],
        check=False,
    )
    if added.returncode:
        if created:
            # Otherwise a re-run would find the key and assume it was added.
            config.deploy_key.unlink()
            config.deploy_key.with_name(config.deploy_key.name + ".pub").unlink()
        raise SetupError("couldn't add the deploy key to GitHub (see gh's error above)")
    if _deploy_key_works(config) is False:
        raise SetupError("added the deploy key, but GitHub still rejects it")
    print(
        f"Added deploy key '{title}'. Remove keys for machines you no longer use with:\n"
        f"  gh repo deploy-key list -R {REPO_SLUG}\n"
        f"  gh repo deploy-key delete <id> -R {REPO_SLUG}"
    )


def _step(name: str, action: Callable[[], object]) -> None:
    """Runs a setup step, warning rather than failing, so setup.sh carries on."""
    try:
        action()
    except (Exception, KeyboardInterrupt) as e:
        print(
            f"Warning: todoist-backup: {name} failed: {e}. Run `todoist-backup setup` to retry.",
            file=sys.stderr,
        )


def cmd_setup(config: Config, args: argparse.Namespace) -> int:
    """Run by setup.sh. Offers to set up whatever this machine is missing; safe to re-run.
    Never exits non-zero, so the rest of setup.sh still runs."""

    def credentials() -> None:
        if MacKeychain().read(config.keychain_service) is None and _offer(
            "Todoist credentials are missing",
            "Open https://app.todoist.com/app/settings/integrations/app-management and use the\n"
            'existing "backup" app (or create one; Todoist rejects names containing "todoist").\n'
            f"Its OAuth redirect URL must be {OAUTH_REDIRECT_URI}. Have its client ID and\n"
            "secret ready.",
        ):
            cmd_setup_token(config, args)

    def deploy_key() -> None:
        if not config.deploy_key.exists():
            missing = f"the deploy key {config.deploy_key} is missing"
        elif _deploy_key_works(config) is False:
            missing = f"GitHub rejects the deploy key {config.deploy_key}"
        else:
            return
        if _offer(missing, f"This adds it to {REPO_SLUG} with your gh login."):
            _setup_deploy_key(config)

    _step("setting up Todoist credentials", credentials)
    _step("setting up the deploy key", deploy_key)
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="todoist-backup", description="Read-only Todoist backup.")
    sub = parser.add_subparsers(dest="command", required=True)
    run_parser = sub.add_parser("run", help="back up now (what the launchd agent runs)")
    run_parser.add_argument("--verbose", action="store_true", help="also log to stderr")
    plan = sub.add_parser("restore-plan", help="compare a snapshot with the live account")
    which = plan.add_mutually_exclusive_group()
    which.add_argument("--ref", default="HEAD", help="snapshot commit (default: latest)")
    which.add_argument("--before", help="latest snapshot before this date, e.g. 2026-10-01")
    plan.add_argument("--json", action="store_true", help="machine-readable output")
    sub.add_parser("status", help="show whether backups are healthy")
    sub.add_parser("setup-token", help="authorise read-only access and store it in the keychain")
    sub.add_parser("setup", help="set up credentials and deploy key on a new machine")
    args = parser.parse_args(argv)

    config = Config.default()
    if args.command == "run":
        _setup_logging(config, args.verbose)
    handlers = {
        "run": cmd_run,
        "restore-plan": cmd_restore_plan,
        "status": cmd_status,
        "setup-token": cmd_setup_token,
        "setup": cmd_setup,
    }
    return handlers[args.command](config, args)


if __name__ == "__main__":
    sys.exit(main())
