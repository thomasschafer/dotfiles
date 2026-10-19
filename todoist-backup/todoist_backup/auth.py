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
REFRESH_TIMEOUT_SECONDS = 10
# Todoist treats a repeat of a just-used refresh token within 60s as a retry; later, as
# a replay attack that revokes every token for the app.
REFRESH_RETRY_WINDOW_SECONDS = 35
REFRESH_RETRY_DELAY_SECONDS = 3
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
    if scope is not None and not isinstance(scope, str):
        raise api.ApiError(200, "token response scope is not a string")
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
        sleep: Callable[[float], None] = time.sleep,
        monotonic: Callable[[], float] = time.monotonic,
    ):
        self._keychain = keychain
        self._service = service
        self._lock_path = lock_path
        self._transport = transport
        self._clock = clock
        self._sleep = sleep
        self._monotonic = monotonic
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

    def _refresh(self, stored: Credentials, refresh_token: str) -> Any:
        """Exchanges the refresh token, retrying only within Todoist's 60s replay window.

        If the request may have reached Todoist but no response arrived, the refresh token
        may already be used up. Retrying within the window either succeeds or proves it
        was used; retrying later would revoke every token, so give up and ask for
        re-authorisation instead."""
        form = {
            "grant_type": "refresh_token",
            "client_id": stored.client_id,
            "client_secret": stored.client_secret,
            "refresh_token": refresh_token,
        }
        started = self._monotonic()
        maybe_used = False
        while True:
            try:
                return api.send(
                    self._transport,
                    "POST",
                    api.OAUTH_TOKEN_PATH,
                    form=form,
                    timeout=REFRESH_TIMEOUT_SECONDS,
                    max_attempts=1,
                )
            except api.OfflineError:
                if not maybe_used:
                    raise  # never reached Todoist, so the token is untouched
                error: Exception | None = None
            except api.ConnectionLost as e:
                maybe_used, error = True, e
            except api.ApiError as e:
                if e.status != 429 and e.status < 500:
                    raise ReauthorizeNeeded(f"token refresh refused: {e}") from e
                maybe_used, error = maybe_used or e.status >= 500, e
            if self._monotonic() - started > REFRESH_RETRY_WINDOW_SECONDS:
                if maybe_used:
                    raise ReauthorizeNeeded(
                        "token refresh got no usable response, so the stored refresh token "
                        "may be used up"
                    ) from error
                raise error or api.OfflineError("token refresh failed")
            self._sleep(REFRESH_RETRY_DELAY_SECONDS)

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
            response = self._refresh(stored, stored.refresh_token)
            new = credentials_from_token_response(
                response,
                client_id=stored.client_id,
                client_secret=stored.client_secret,
                now=self._clock(),
            )
            if new.refresh_token is None:
                # Also what Todoist sends when a just-used refresh token is presented again.
                raise ReauthorizeNeeded("token refresh returned no new refresh token")
            self.store(new)
            return new.access_token
