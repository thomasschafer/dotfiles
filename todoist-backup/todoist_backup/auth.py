"""OAuth credentials for the backup's own Todoist app, stored as one Keychain item.

Access tokens from newly registered Todoist apps last an hour and come with a refresh
token that rotates on every refresh. Presenting a used refresh token more than 60s later
revokes every token for the app, so refreshes are serialised with a file lock and the
rotated credentials are written back to the Keychain straight away.
"""

from __future__ import annotations

import fcntl
import json
import time
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

from . import api
from .config import OAUTH_SCOPE
from .keychain import Keychain

REFRESH_MARGIN_SECONDS = 300
STORE_ATTEMPTS = 3


class CredentialsMissing(Exception):
    pass


class ReauthorizeNeeded(Exception):
    """The stored credentials can't be refreshed; run `todoist-backup setup-token`."""


class ScopeError(Exception):
    """Todoist granted a different scope from the read-only one requested."""


@dataclass(frozen=True)
class Credentials:
    client_id: str
    client_secret: str
    access_token: str
    refresh_token: str | None
    # None for legacy long-lived tokens.
    expires_at: float | None

    def to_json(self) -> str:
        return json.dumps(asdict(self), sort_keys=True, separators=(",", ":"))

    @classmethod
    def from_json(cls, text: str) -> Credentials:
        try:
            raw = json.loads(text)
        except json.JSONDecodeError as e:
            raise ReauthorizeNeeded("stored credentials are not valid JSON") from e
        if not isinstance(raw, dict) or set(raw) != {f for f in cls.__dataclass_fields__}:
            raise ReauthorizeNeeded("stored credentials have unexpected fields")
        for key in ("client_id", "client_secret", "access_token"):
            if not isinstance(raw[key], str) or not raw[key]:
                raise ReauthorizeNeeded(f"stored credentials have no {key}")
        if raw["refresh_token"] is not None and not isinstance(raw["refresh_token"], str):
            raise ReauthorizeNeeded("stored refresh_token is not a string")
        if raw["expires_at"] is not None and not isinstance(raw["expires_at"], (int, float)):
            raise ReauthorizeNeeded("stored expires_at is not a number")
        return cls(**raw)

    def secrets(self) -> list[str]:
        return [s for s in (self.client_secret, self.access_token, self.refresh_token) if s]


def credentials_from_token_response(
    response: Any, *, client_id: str, client_secret: str, now: float
) -> Credentials:
    if not isinstance(response, dict):
        raise api.ApiError(200, "token response is not an object")
    access_token = response.get("access_token")
    if not isinstance(access_token, str) or not access_token:
        raise api.ApiError(200, "token response has no access_token")
    if response.get("token_type", "Bearer") != "Bearer":
        raise api.ApiError(200, f"unexpected token_type {response.get('token_type')!r}")
    scope = response.get("scope")
    if scope is not None and set(scope.replace(" ", ",").split(",")) - {""} != {OAUTH_SCOPE}:
        raise ScopeError(f"Todoist granted scope {scope!r}, expected only {OAUTH_SCOPE!r}")
    expires_in = response.get("expires_in")
    if expires_in is not None and not isinstance(expires_in, int):
        raise api.ApiError(200, "token response expires_in is not an integer")
    refresh_token = response.get("refresh_token")
    if refresh_token is not None and not isinstance(refresh_token, str):
        raise api.ApiError(200, "token response refresh_token is not a string")
    return Credentials(
        client_id=client_id,
        client_secret=client_secret,
        access_token=access_token,
        refresh_token=refresh_token,
        expires_at=None if expires_in is None else now + expires_in,
    )


@contextmanager
def file_lock(path: Path) -> Iterator[None]:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


class KeychainTokenSource:
    def __init__(
        self,
        keychain: Keychain,
        service: str,
        lock_path: Path,
        transport: api.Transport = api.urllib_transport,
        clock: Callable[[], float] = time.time,
    ):
        self._keychain = keychain
        self._service = service
        self._lock_path = lock_path
        self._transport = transport
        self._clock = clock
        self._cached: Credentials | None = None

    def load(self) -> Credentials:
        text = self._keychain.read(self._service)
        if text is None:
            raise CredentialsMissing(
                f"no keychain item '{self._service}'; run `todoist-backup setup-token`"
            )
        return Credentials.from_json(text)

    def store(self, credentials: Credentials) -> None:
        last_error: Exception | None = None
        for _ in range(STORE_ATTEMPTS):
            try:
                self._keychain.write(self._service, credentials.to_json())
                self._cached = credentials
                return
            except Exception as e:  # noqa: BLE001 - retried, then re-raised
                last_error = e
        raise ReauthorizeNeeded(
            "refreshed the token but couldn't save it to the keychain, so the stored refresh "
            "token is now used up"
        ) from last_error

    def secrets(self) -> list[str]:
        return self._cached.secrets() if self._cached else []

    def _fresh(self, credentials: Credentials) -> bool:
        return (
            credentials.expires_at is None
            or credentials.expires_at - self._clock() > REFRESH_MARGIN_SECONDS
        )

    def access_token(self, *, force_refresh: bool = False) -> str:
        if self._cached is not None and not force_refresh and self._fresh(self._cached):
            return self._cached.access_token
        with file_lock(self._lock_path):
            stored = self.load()
            # Another process may have refreshed since this one last looked.
            refreshed_elsewhere = (
                self._cached is not None and stored.access_token != self._cached.access_token
            )
            if self._fresh(stored) and (not force_refresh or refreshed_elsewhere):
                self._cached = stored
                return stored.access_token
            if stored.refresh_token is None:
                raise ReauthorizeNeeded(
                    "access token rejected or expired and there's no refresh token"
                )
            try:
                response = api.send(
                    self._transport,
                    "POST",
                    api.OAUTH_TOKEN_PATH,
                    form={
                        "grant_type": "refresh_token",
                        "client_id": stored.client_id,
                        "client_secret": stored.client_secret,
                        "refresh_token": stored.refresh_token,
                    },
                )
            except api.ApiError as e:
                if 400 <= e.status < 500:
                    raise ReauthorizeNeeded(f"token refresh refused: {e}") from e
                raise
            new = credentials_from_token_response(
                response,
                client_id=stored.client_id,
                client_secret=stored.client_secret,
                now=self._clock(),
            )
            if new.refresh_token is None:
                raise ReauthorizeNeeded("token refresh returned no new refresh token")
            self.store(new)
            return new.access_token
