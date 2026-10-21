"""The backup must never be able to write to Todoist."""

from __future__ import annotations

import ast
import json
from datetime import UTC, datetime
from pathlib import Path

import pytest
from conftest import TOKEN, FakeTodoist, StaticTokens

from todoist_backup import api, fetch
from todoist_backup.api import HttpRequest, ReadOnlyViolation, TodoistClient

PACKAGE = Path(api.__file__).resolve().parent

WRITES = [
    ("POST", "/api/v1/tasks", {"content": "x"}),
    ("POST", "/api/v1/tasks/123", {"content": "x"}),
    ("POST", "/api/v1/tasks/123/close", {}),
    ("POST", "/api/v1/tasks/123/reopen", None),
    ("POST", "/api/v1/projects/123/archive", None),
    ("DELETE", "/api/v1/tasks/123", None),
    ("DELETE", "/api/v1/projects/123", None),
    ("PUT", "/api/v1/notification_setting", {"a": "b"}),
    ("PATCH", "/api/v1/tasks/123", {"content": "x"}),
    ("POST", "/api/v1/sync", {"commands": json.dumps([{"type": "item_delete"}])}),
    (
        "POST",
        "/api/v1/sync",
        {
            "sync_token": "*",
            "resource_types": '["all"]',
            "commands": json.dumps([{"type": "item_delete"}]),
        },
    ),
    ("POST", "/api/v1/sync", {"sync_token": "*", "resource_types": '["all"]', "extra": "1"}),
    ("POST", "/api/v1/sync", {"sync_token": "*"}),
    ("POST", "/api/v1/sync", None),
    ("GET", "/api/v1/sync", None),
    ("GET", "/api/v1/backups/download", None),
    ("GET", "/api/v1/tasks/123", None),
    ("GET", "/api/v1/tasks", {"content": "smuggled body"}),
    (
        "POST",
        "/oauth/access_token",
        {"grant_type": "client_credentials", "client_id": "a", "client_secret": "b"},
    ),
    (
        "POST",
        "/oauth/access_token",
        {
            "grant_type": "refresh_token",
            "client_id": "a",
            "client_secret": "b",
            "refresh_token": "c",
            "x": "y",
        },
    ),
    ("POST", "/oauth/register", {"client_name": "x"}),
    ("POST", "/api/v1/revoke", {"token": "x"}),
    ("POST", "/api/v1/access_tokens/migrate_personal_token", {"personal_token": "x"}),
    ("HEAD", "/api/v1/tasks", None),
    ("get", "/api/v1/tasks", None),
]

READS = [
    ("GET", "/api/v1/tasks", None),
    ("GET", "/api/v1/projects/archived", None),
    ("GET", "/api/v1/tasks/completed/by_completion_date", None),
    ("POST", "/api/v1/sync", {"sync_token": "*", "resource_types": '["all"]'}),
    (
        "POST",
        "/oauth/access_token",
        {
            "grant_type": "refresh_token",
            "client_id": "a",
            "client_secret": "b",
            "refresh_token": "c",
        },
    ),
    (
        "POST",
        "/oauth/access_token",
        {
            "grant_type": "authorization_code",
            "client_id": "a",
            "client_secret": "b",
            "code": "c",
            "redirect_uri": "d",
        },
    ),
]


def _refuse_transport(request: HttpRequest) -> api.HttpResponse:
    raise AssertionError(f"transport must not be reached: {request.method} {request.url}")


@pytest.mark.parametrize(("method", "path", "form"), WRITES)
def test_writes_raise_before_any_network_call(method, path, form):
    with pytest.raises(ReadOnlyViolation):
        api.send(_refuse_transport, method, path, form=form, bearer=TOKEN)


@pytest.mark.parametrize(("method", "path", "form"), READS)
def test_reads_reach_the_transport(method, path, form):
    seen = []

    def transport(request: HttpRequest) -> api.HttpResponse:
        seen.append(request)
        return api.HttpResponse(200, b"{}")

    api.send(transport, method, path, form=form, bearer=TOKEN)
    assert [r.method for r in seen] == [method]


def test_everything_the_backup_does_is_a_read(tmp_path):
    server = FakeTodoist()
    client = TodoistClient(StaticTokens(), server)
    fetch.fetch_all(client, [], datetime.now(UTC))
    fetch.fetch_live_view(client)
    assert server.requests
    for request in server.requests:
        if request.method == "POST":
            assert request.url == api.API_HOST + api.SYNC_PATH
            assert b"commands" not in (request.body or b"")
        else:
            assert request.method == "GET"


NETWORK_MODULES = {
    "urllib",
    "http",
    "socket",
    "ssl",
    "requests",
    "httpx",
    "aiohttp",
    "ftplib",
    "smtplib",
    "xmlrpc",
}
# The setup command listens on localhost for the OAuth redirect; it makes no outbound calls.
ALLOWED = {"api.py": NETWORK_MODULES, "oauth_setup.py": {"http", "socket", "urllib"}}


def _imports(path: Path) -> set[str]:
    names = set()
    for node in ast.walk(ast.parse(path.read_text())):
        if isinstance(node, ast.Import):
            names |= {a.name.split(".")[0] for a in node.names}
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names.add(node.module.split(".")[0])
    return names


def test_only_api_module_can_reach_the_network():
    for path in PACKAGE.glob("*.py"):
        found = _imports(path) & NETWORK_MODULES
        assert found <= ALLOWED.get(path.name, set()), f"{path.name} imports {found}"


def test_oauth_setup_only_uses_urllib_for_parsing():
    tree = ast.parse((PACKAGE / "oauth_setup.py").read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.Attribute) and isinstance(node.value, ast.Attribute):
            if getattr(node.value.value, "id", None) == "urllib":
                assert node.value.attr == "parse", f"urllib.{node.value.attr} used"
        if isinstance(node, ast.Import):
            for alias in node.names:
                assert alias.name in {"http.server", "urllib.parse"} or not alias.name.startswith(
                    ("urllib", "http")
                ), alias.name


def test_send_is_the_only_transport_caller():
    """Nothing outside api.send may call a transport directly, skipping the guard."""
    for path in PACKAGE.glob("*.py"):
        source = path.read_text()
        if path.name == "api.py":
            assert source.count("transport(HttpRequest(") == 1
        else:
            assert "HttpRequest(" not in source, path.name
            assert "urllib_transport(" not in source, path.name
