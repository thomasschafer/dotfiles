"""macOS notifications. Banners via terminal-notifier; deletion alerts also open a modal
dialog that stays until dismissed."""

from __future__ import annotations

import logging
import shutil
import subprocess
from enum import Enum
from typing import Protocol

log = logging.getLogger(__name__)

TITLE = "Todoist backup"


class Alert(Enum):
    FAILED = "failed"
    VERIFICATION = "verification"
    DELETIONS = "deletions"
    STALE = "stale"
    HISTORY = "history"
    REPAIRED = "repaired"
    REAUTHORIZE = "reauthorize"

    @property
    def modal(self) -> bool:
        return self in (Alert.DELETIONS, Alert.HISTORY)

    @property
    def rate_limited(self) -> bool:
        """Deletion alerts are about a specific snapshot, so they always fire."""
        return self is not Alert.DELETIONS


class Notifier(Protocol):
    def notify(self, alert: Alert, message: str) -> None: ...


def _applescript_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


class MacNotifier:
    def notify(self, alert: Alert, message: str) -> None:
        notifier = shutil.which("terminal-notifier")
        if notifier is None:
            log.error("terminal-notifier not found; falling back to osascript")
            subprocess.run(
                [
                    "/usr/bin/osascript",
                    "-e",
                    f"display notification {_applescript_string(message)} "
                    f"with title {_applescript_string(TITLE)}",
                ],
                check=False,
                capture_output=True,
            )
        else:
            subprocess.run(
                [
                    notifier,
                    "-title",
                    TITLE,
                    "-subtitle",
                    alert.value,
                    "-message",
                    message,
                    "-group",
                    f"todoist-backup-{alert.value}",
                    "-sound",
                    "default",
                ],
                check=False,
                capture_output=True,
            )
        if alert.modal:
            # Not waited on, so the run finishes while the dialog stays up.
            subprocess.Popen(
                [
                    "/usr/bin/osascript",
                    "-e",
                    f"display alert {_applescript_string(TITLE + ': ' + alert.value)} "
                    f"message {_applescript_string(message)} as critical",
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
