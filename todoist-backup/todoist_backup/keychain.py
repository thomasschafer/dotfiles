"""macOS Keychain access through /usr/bin/security. Secrets never appear in argv."""

from __future__ import annotations

import getpass
import re
import subprocess
from typing import Protocol

SECURITY = "/usr/bin/security"
ITEM_NOT_FOUND_EXIT = 44


class KeychainError(Exception):
    pass


class KeychainLocked(KeychainError):
    """The login keychain is locked, e.g. a run fired before login completed."""


class Keychain(Protocol):
    def read(self, service: str) -> str | None: ...
    def write(self, service: str, value: str) -> None: ...


class MacKeychain:
    def read(self, service: str) -> str | None:
        result = subprocess.run(
            [SECURITY, "find-generic-password", "-s", service, "-w"],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0:
            return result.stdout.rstrip("\n")
        if result.returncode == ITEM_NOT_FOUND_EXIT:
            return None
        if "interaction is not allowed" in result.stderr.lower():
            raise KeychainLocked(f"keychain locked reading '{service}'")
        raise KeychainError(
            f"security exited {result.returncode} reading '{service}': {result.stderr.strip()}"
        )

    def write(self, service: str, value: str) -> None:
        """Creates or updates the item, then reads it back to confirm."""
        account = getpass.getuser()
        for name in (service, account):
            if not re.fullmatch(r"[A-Za-z0-9._-]+", name):
                raise KeychainError(f"unsafe keychain service or account name {name!r}")
        # `security -i` reads commands from stdin, keeping the value out of the process
        # list. Hex encoding avoids its quoting rules.
        command = f"add-generic-password -U -s {service} -a {account} -X {value.encode().hex()}\n"
        result = subprocess.run(
            [SECURITY, "-i"], input=command, capture_output=True, text=True, check=False
        )
        if result.returncode != 0:
            raise KeychainError(f"security exited {result.returncode} writing '{service}'")
        if self.read(service) != value:
            raise KeychainError(f"keychain item '{service}' didn't read back as written")
