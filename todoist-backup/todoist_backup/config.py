"""Paths and settings. Everything that differs between tests and real runs lives here."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

PACKAGE_DIR = Path(__file__).resolve().parent
SOURCE_DIR = PACKAGE_DIR.parent

KEYCHAIN_SERVICE = "todoist-backup"
REMOTE_URL = "git@github.com:thomasschafer/todoist-backup.git"
BRANCH = "main"

# Must match a redirect URL registered on the Todoist app (see README).
OAUTH_REDIRECT_PORT = 8723
OAUTH_REDIRECT_URI = f"http://localhost:{OAUTH_REDIRECT_PORT}/callback"
OAUTH_SCOPE = "data:read"

STALE_AFTER_SECONDS = 24 * 3600
# Alerts other than deletions repeat at most this often, so a long outage doesn't
# notify on every run.
ALERT_REPEAT_SECONDS = 24 * 3600

# Re-fetch this much completed-task history on each run, so late-arriving or edited
# completions are picked up.
COMPLETED_OVERLAP_DAYS = 14

# A drop in active tasks or projects is alarming if it exceeds either threshold, and
# is at least DELETION_MIN_DROP so small lists don't alert on everyday tidying.
DELETION_MAX_FRACTION = 0.10
DELETION_MAX_ITEMS = 20
DELETION_MIN_DROP = 3

LOG_MAX_BYTES = 1_000_000
LOG_BACKUPS = 5


@dataclass(frozen=True)
class Config:
    data_dir: Path
    state_dir: Path
    deploy_key: Path
    known_hosts: Path
    remote_url: str = REMOTE_URL
    keychain_service: str = KEYCHAIN_SERVICE

    @property
    def log_file(self) -> Path:
        return self.state_dir / "todoist-backup.log"

    @property
    def launchd_log(self) -> Path:
        return self.state_dir / "launchd.log"

    @property
    def state_file(self) -> Path:
        return self.state_dir / "state.json"

    @property
    def run_lock(self) -> Path:
        return self.state_dir / "run.lock"

    @property
    def token_lock(self) -> Path:
        return self.state_dir / "token.lock"

    @classmethod
    def default(cls) -> Config:
        home = Path.home()
        xdg_data = Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share")
        xdg_state = Path(os.environ.get("XDG_STATE_HOME") or home / ".local/state")
        return cls(
            data_dir=xdg_data / "todoist-backup",
            state_dir=xdg_state / "todoist-backup",
            deploy_key=home / ".ssh/todoist-backup_ed25519",
            known_hosts=SOURCE_DIR / "github_known_hosts",
        )
