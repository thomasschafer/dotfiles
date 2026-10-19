"""The only module that talks to Todoist over the network.

Every request goes through `send`, which refuses anything that could change Todoist data
before a connection is made. What it allows:

- GET requests to the read endpoints in READ_GET_PATHS.
- POST /api/v1/sync carrying only `sync_token` and `resource_types`. The Sync API uses
  POST even for reads; a request with `commands` (the only way it writes) is refused.
- POST /oauth/access_token to exchange an authorisation code or refresh token for an
  access token. This issues credentials for this app and doesn't touch Todoist data;
  the token it returns is limited to the read-only `data:read` scope.

Nothing else in the package may import a networking module; tests/test_read_only.py
checks this.
"""

from __future__ import annotations

import json
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterable, Mapping
from dataclasses import dataclass, field
from typing import Any, Protocol

API_HOST = "https://api.todoist.com"
SYNC_PATH = "/api/v1/sync"
OAUTH_TOKEN_PATH = "/oauth/access_token"

READ_GET_PATHS = frozenset(
    {
        "/api/v1/user",
        "/api/v1/tasks",
        "/api/v1/sections",
        "/api/v1/comments",
        "/api/v1/projects/archived",
        "/api/v1/tasks/completed/by_completion_date",
    }
)
SYNC_READ_FIELDS = frozenset({"sync_token", "resource_types"})
OAUTH_GRANT_FIELDS: Mapping[str, frozenset[str]] = {
    "authorization_code": frozenset(
        {"grant_type", "client_id", "client_secret", "code", "redirect_uri"}
    ),
    "refresh_token": frozenset({"grant_type", "client_id", "client_secret", "refresh_token"}),
}

PAGE_LIMIT = 200
TIMEOUT_SECONDS = 60
MAX_ATTEMPTS = 4
MAX_RETRY_WAIT_SECONDS = 60
USER_AGENT = "todoist-backup (read-only; github.com/thomasschafer/dotfiles)"


class ReadOnlyViolation(Exception):
    """A request that could modify Todoist data was attempted. Always a bug."""


class OfflineError(Exception):
    """Todoist couldn't be reached at all, e.g. no network."""


class ApiError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(f"HTTP {status}: {message}")
        self.status = status


class AuthError(ApiError):
    pass


@dataclass(frozen=True)
class HttpRequest:
    method: str
    url: str
    headers: Mapping[str, str]
    body: bytes | None


@dataclass(frozen=True)
class HttpResponse:
    status: int
    body: bytes
    headers: Mapping[str, str] = field(default_factory=dict)


Transport = Callable[[HttpRequest], HttpResponse]


def check_read_only(method: str, path: str, form: Mapping[str, str] | None) -> None:
    """Raises ReadOnlyViolation unless the request is one of the allowed reads."""
    if method == "GET":
        if form is not None:
            raise ReadOnlyViolation(f"GET {path} must not have a body")
        if path not in READ_GET_PATHS:
            raise ReadOnlyViolation(f"GET {path} is not an allowed read endpoint")
        return
    if method == "POST" and path == SYNC_PATH:
        keys = set(form or {})
        if "commands" in keys:
            raise ReadOnlyViolation("sync requests with commands write data")
        if keys != SYNC_READ_FIELDS:
            raise ReadOnlyViolation(f"sync read must send exactly {sorted(SYNC_READ_FIELDS)}")
        return
    if method == "POST" and path == OAUTH_TOKEN_PATH:
        grant = (form or {}).get("grant_type")
        allowed = OAUTH_GRANT_FIELDS.get(grant or "")
        if allowed is None or set(form or {}) != allowed:
            raise ReadOnlyViolation(f"unexpected token request fields for grant {grant!r}")
        return
    raise ReadOnlyViolation(f"{method} {path} is not a read operation")


def urllib_transport(request: HttpRequest) -> HttpResponse:
    req = urllib.request.Request(
        request.url, data=request.body, headers=dict(request.headers), method=request.method
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            return HttpResponse(resp.status, resp.read(), dict(resp.headers))
    except urllib.error.HTTPError as e:
        return HttpResponse(e.code, e.read(), dict(e.headers or {}))
    except (TimeoutError, urllib.error.URLError, ConnectionError) as e:
        raise OfflineError(
            f"could not reach {urllib.parse.urlsplit(request.url).netloc}: {e}"
        ) from e


def redact(text: str, secrets: Iterable[str]) -> str:
    for secret in secrets:
        if secret:
            text = text.replace(secret, "[redacted]")
    return text


def send(
    transport: Transport,
    method: str,
    path: str,
    *,
    query: Mapping[str, str] | None = None,
    form: Mapping[str, str] | None = None,
    bearer: str | None = None,
    sleep: Callable[[float], None] = time.sleep,
) -> Any:
    """Sends one request, retrying rate limits and server errors, and returns the JSON body."""
    check_read_only(method, path, form)

    url = API_HOST + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}
    body = None
    if bearer is not None:
        headers["Authorization"] = f"Bearer {bearer}"
    if form is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        body = urllib.parse.urlencode(form).encode()
    secrets = [bearer or ""] + [
        (form or {}).get(k, "") for k in ("client_secret", "code", "refresh_token")
    ]

    for attempt in range(1, MAX_ATTEMPTS + 1):
        response = transport(HttpRequest(method, url, headers, body))
        if response.status == 429 or response.status >= 500:
            if attempt == MAX_ATTEMPTS:
                break
            sleep(_retry_wait(response, attempt))
            continue
        break

    text = response.body.decode("utf-8", errors="replace")
    if not 200 <= response.status < 300:
        message = redact(f"{method} {path}: {text[:500]}", secrets)
        if response.status in (401, 403):
            raise AuthError(response.status, message)
        raise ApiError(response.status, message)
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise ApiError(response.status, f"{method} {path}: response is not JSON") from e


def _retry_wait(response: HttpResponse, attempt: int) -> float:
    retry_after = {k.lower(): v for k, v in response.headers.items()}.get("retry-after")
    try:
        wait = float(retry_after) if retry_after is not None else 2.0**attempt
    except ValueError:
        wait = 2.0**attempt
    return min(max(wait, 1.0), MAX_RETRY_WAIT_SECONDS)


class TokenSource(Protocol):
    def access_token(self, *, force_refresh: bool = False) -> str: ...


class TodoistClient:
    """Read-only Todoist client. Every method ends up in `send`."""

    def __init__(
        self,
        tokens: TokenSource,
        transport: Transport = urllib_transport,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self._tokens = tokens
        self._transport = transport
        self._sleep = sleep

    def _authed(self, method: str, path: str, **kwargs: Any) -> Any:
        try:
            return send(
                self._transport,
                method,
                path,
                bearer=self._tokens.access_token(),
                sleep=self._sleep,
                **kwargs,
            )
        except AuthError as e:
            if e.status != 401:
                raise
        # The access token may have expired early or been revoked; refresh once.
        return send(
            self._transport,
            method,
            path,
            bearer=self._tokens.access_token(force_refresh=True),
            sleep=self._sleep,
            **kwargs,
        )

    def sync_read(self, resource_types: Iterable[str] = ("all",), sync_token: str = "*") -> dict:
        result = self._authed(
            "POST",
            SYNC_PATH,
            form={"sync_token": sync_token, "resource_types": json.dumps(list(resource_types))},
        )
        if not isinstance(result, dict):
            raise ApiError(200, "sync response is not an object")
        return result

    def get(self, path: str, params: Mapping[str, str] | None = None) -> Any:
        return self._authed("GET", path, query=dict(params or {}))

    def get_all(
        self, path: str, params: Mapping[str, str] | None = None, *, results_key: str = "results"
    ) -> list[dict]:
        """Follows cursor pagination and returns every result."""
        results: list[dict] = []
        cursor: str | None = None
        while True:
            query = {**(params or {}), "limit": str(PAGE_LIMIT)}
            if cursor:
                query["cursor"] = cursor
            page = self.get(path, query)
            if not isinstance(page, dict) or not isinstance(page.get(results_key), list):
                raise ApiError(200, f"GET {path}: page has no {results_key!r} list")
            results.extend(page[results_key])
            cursor = page.get("next_cursor")
            if not cursor:
                return results
