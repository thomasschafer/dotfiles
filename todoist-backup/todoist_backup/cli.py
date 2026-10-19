from __future__ import annotations

import argparse
import logging
import logging.handlers
import os
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone

from . import fetch, restore_plan, snapshot
from .api import TodoistClient
from .auth import CredentialsMissing, KeychainTokenSource
from .config import LOG_BACKUPS, LOG_MAX_BYTES, OAUTH_REDIRECT_URI, STALE_AFTER_SECONDS, Config
from .keychain import MacKeychain
from .notify import MacNotifier
from .repo import Repo
from .run import Deps, run
from .state import State

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
    )
    return run(deps)


def cmd_restore_plan(config: Config, args: argparse.Namespace) -> int:
    repo = Repo(config)
    if not repo.exists():
        print(f"No data repo at {config.data_dir}", file=sys.stderr)
        return 1
    ref = repo.commit_before(args.before) if args.before else repo.resolve(args.ref)
    snapshot_time = repo.commit_time(ref)
    snap = repo.read_files_at(ref, ["sync/", "archived/"])
    client = TodoistClient(_tokens(config))
    live = fetch.fetch_live_view(client)
    since = datetime.fromisoformat(snapshot_time) - timedelta(days=1)
    completed = fetch.fetch_completed(client, since, datetime.now(timezone.utc))
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
    state = State.load(config.state_file, time.time()) if config.state_file.exists() else None
    print(f"Data repo:      {config.data_dir}")
    print(f"Logs:           {config.log_file}")
    print(f"launchd agent:  {_launchd_status()}")
    if state is None:
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


def cmd_check_setup(config: Config, args: argparse.Namespace) -> int:
    """Run by setup.sh: reports anything a fresh machine is missing."""
    missing = []
    if MacKeychain().read(config.keychain_service) is None:
        missing.append(
            "Todoist credentials: register an app at "
            "https://app.todoist.com/app/settings/integrations/app-management with OAuth "
            f"redirect URL {OAUTH_REDIRECT_URI}, then run `todoist-backup setup-token`"
        )
    if not config.deploy_key.exists():
        missing.append(
            f"deploy key {config.deploy_key}: create it with `ssh-keygen -t ed25519 -N '' -f "
            f"{config.deploy_key}` and add the .pub as a write deploy key on the data repo"
        )
    for item in missing:
        print(f"Warning: todoist-backup: missing {item}", file=sys.stderr)
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
    sub.add_parser("check-setup", help="warn about missing credentials or deploy key")
    args = parser.parse_args(argv)

    config = Config.default()
    if args.command == "run":
        _setup_logging(config, args.verbose)
    handlers = {
        "run": cmd_run,
        "restore-plan": cmd_restore_plan,
        "status": cmd_status,
        "setup-token": cmd_setup_token,
        "check-setup": cmd_check_setup,
    }
    return handlers[args.command](config, args)


if __name__ == "__main__":
    sys.exit(main())
