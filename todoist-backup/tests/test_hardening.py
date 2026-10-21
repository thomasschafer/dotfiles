"""Failure modes found in review: each test pins one down."""

from __future__ import annotations

import http.server
import json
import subprocess
import threading
from datetime import UTC
from pathlib import Path

import pytest
from conftest import TOKEN, Env, completed, git, task

from todoist_backup import api, cli, fetch
from todoist_backup.api import ApiError, ConnectionLost, HttpResponse, TodoistClient
from todoist_backup.auth import Credentials, KeychainTokenSource, ReauthorizeNeeded
from todoist_backup.notify import Alert
from todoist_backup.oauth_setup import SetupError
from todoist_backup.run import run

HOUR = 3600


def _run(env: Env) -> int:
    return run(env.deps())


# State


def test_corrupt_state_file_alerts_and_backs_up_anyway(env):
    env.config.state_dir.mkdir(parents=True)
    env.config.state_file.write_text("{trunc")
    assert _run(env) == 0
    assert env.notifier.kinds() == [Alert.FAILED]
    assert "corrupt" in env.notifier.alerts[0][1]
    assert list(env.config.state_dir.glob("state.json.corrupt-*"))
    assert len(env.remote_log()) == 1


def test_state_with_unknown_fields_is_treated_as_corrupt(env):
    env.config.state_dir.mkdir(parents=True)
    env.config.state_file.write_text(json.dumps({"installed_at": 1, "renamed_field": 2}))
    _run(env)
    assert env.notifier.kinds() == [Alert.FAILED]


# Deletion detector


def test_deleting_tasks_with_completion_history_alerts(env):
    """Recurring tasks keep their id and gain a completion every cycle."""
    env.server.completed += [completed(f"t{i}", "2025-06-01T10:00:00Z") for i in range(1, 11)]
    _run(env)
    env.clock.now += 4 * HOUR
    env.server.sync["items"] = env.server.sync["items"][10:]
    _run(env)
    assert env.notifier.kinds() == [Alert.DELETIONS]


def test_deletions_spread_over_a_day_alert_once(env):
    env.server.sync["items"] = [task(f"t{i}", "x") for i in range(100)]
    _run(env)
    for _ in range(6):
        env.clock.now += 4 * HOUR + 600
        env.server.sync["items"] = env.server.sync["items"][2:]
        _run(env)
    # 12 of 101 gone since a day ago: no single run crossed the threshold, the day did.
    assert env.notifier.kinds() == [Alert.DELETIONS]
    assert "since the snapshot of" in env.notifier.alerts[0][1]
    env.clock.now += 4 * HOUR
    _run(env)
    assert env.notifier.kinds() == [Alert.DELETIONS], "already-reported deletions don't repeat"


def test_alerts_contain_no_task_names(env):
    _run(env)
    env.clock.now += 4 * HOUR
    env.server.sync["items"] = env.server.sync["items"][:20]
    _run(env)
    [(_, message)] = env.notifier.alerts
    assert "Task" not in message


# Completed history


def test_working_tree_edits_cannot_shrink_completed_history(env):
    _run(env)
    (env.config.data_dir / "completed/2025-03.json").unlink()
    env.clock.now += 4 * HOUR
    assert _run(env) == 0
    assert (env.config.data_dir / "completed/2025-03.json").exists()
    assert len(env.remote_log()) == 1


# Network


def test_waits_for_the_network_after_wake(env):
    env.server.offline_requests = 3
    assert _run(env) == 0
    assert len(env.remote_log()) == 1
    assert env.notifier.alerts == []


def test_gives_up_quietly_if_the_network_stays_down(env):
    env.server.offline = True
    start = env.clock.now
    assert _run(env) == 0
    assert env.clock.now - start >= 120
    assert env.notifier.alerts == []


def test_tls_errors_are_failures_not_offline(env):
    env.server.error = api.TransportSecurityError("certificate verify failed")
    assert _run(env) == 1
    assert env.notifier.kinds() == [Alert.FAILED]


def test_redirects_are_not_followed():
    class Redirect(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            self.send_response(302)
            self.send_header("Location", "http://example.invalid/steal")
            self.end_headers()

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), Redirect)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        url = f"http://127.0.0.1:{server.server_port}/api/v1/user"
        response = api.urllib_transport(
            api.HttpRequest("GET", url, {"Authorization": "Bearer x"}, None)
        )
    finally:
        server.shutdown()
    assert response.status == 302


def test_pagination_that_repeats_a_cursor_fails():
    def transport(request):
        return HttpResponse(200, json.dumps({"results": [{}], "next_cursor": "a.b"}).encode())

    client = TodoistClient(_StaticTokens(), transport)
    with pytest.raises(ApiError, match="isn't advancing"):
        client.get_all("/api/v1/projects/archived")


class _StaticTokens:
    def access_token(self, *, force_refresh: bool = False) -> str:
        return TOKEN


# Token refresh


class _Keychain:
    def __init__(self, value):
        self.value = value

    def read(self, service):
        return self.value

    def write(self, service, value):
        self.value = value


class _Clock:
    def __init__(self):
        self.t = 0.0

    def __call__(self):
        return self.t

    def sleep(self, seconds):
        self.t += seconds


def _source(tmp_path, responses):
    """A token source whose stored access token has expired, refreshing via `responses`."""
    clock = _Clock()
    calls = []

    def transport(request):
        calls.append(request)
        clock.t += 1
        outcome = responses.pop(0)
        if isinstance(outcome, Exception):
            raise outcome
        return HttpResponse(outcome[0], json.dumps(outcome[1]).encode())

    keychain = _Keychain(Credentials("cid", "sec", "old", "r1", 0).to_json())
    source = KeychainTokenSource(
        keychain,
        "svc",
        tmp_path / "lock",
        transport,
        clock=lambda: 10_000,
        sleep=clock.sleep,
        monotonic=clock,
    )
    return source, keychain, calls


GOOD = (200, {"access_token": "new", "refresh_token": "r2", "expires_in": 3600})


def test_refresh_retries_a_lost_response_within_the_replay_window(tmp_path):
    source, keychain, calls = _source(tmp_path, [ConnectionLost("reset"), GOOD])
    assert source.access_token() == "new"
    assert Credentials.from_json(keychain.value).refresh_token == "r2"
    assert len(calls) == 2


def test_refresh_gives_up_before_the_replay_window_closes(tmp_path):
    source, _, calls = _source(tmp_path, [ConnectionLost("reset")] * 50)
    with pytest.raises(ReauthorizeNeeded, match="used up"):
        source.access_token()
    # Every attempt is within 60s of the first: Todoist would revoke after that.
    assert len(calls) * (1 + 3) <= 60


def test_refresh_while_offline_leaves_the_token_untouched(tmp_path):
    source, keychain, _ = _source(tmp_path, [api.OfflineError("no network")])
    with pytest.raises(api.OfflineError):
        source.access_token()
    assert Credentials.from_json(keychain.value).refresh_token == "r1"


def test_grace_window_reply_without_refresh_token_needs_reauthorising(tmp_path):
    source, _, _ = _source(
        tmp_path, [ConnectionLost("reset"), (200, {"access_token": "new", "expires_in": 3600})]
    )
    with pytest.raises(ReauthorizeNeeded, match="no new refresh token"):
        source.access_token()


def test_refresh_request_is_the_only_post_besides_sync(tmp_path):
    source, _, calls = _source(tmp_path, [GOOD])
    source.access_token()
    [request] = calls
    assert request.method == "POST" and request.url == api.API_HOST + api.OAUTH_TOKEN_PATH
    assert b"grant_type=refresh_token" in request.body


# Snapshot contents


def test_websocket_url_is_not_stored(env):
    env.server.sync["user"]["websocket_url"] = "wss://ws.todoist.com/ws?token=abc123"
    _run(env)
    user = json.loads((env.config.data_dir / "sync/user.json").read_text())
    assert "websocket_url" not in user


@pytest.mark.parametrize(
    ("resource", "value"),
    [
        ("user", {"id": "u1", "joined_at": "2025-01-10T09:00:00Z", "token": "abc"}),
        (
            "user",
            {
                "id": "u1",
                "joined_at": "2025-01-10T09:00:00Z",
                "avatar": "https://x.test/a.png?api_token=abc",
            },
        ),
    ],
)
def test_credentials_in_account_data_block_the_snapshot(env, resource, value):
    env.server.sync[resource] = value
    assert _run(env) == 1
    assert env.notifier.kinds() == [Alert.FAILED]
    assert git("log", "--all", "--oneline", cwd=env.remote) == ""


def test_links_with_tokens_in_tasks_are_kept(env):
    env.server.sync["items"].append(task("t77", "https://example.test/doc?token=share"))
    assert _run(env) == 0


def test_stray_files_in_the_data_repo_are_not_committed(env):
    _run(env)
    (env.config.data_dir / "notes.txt").write_text("dropped here by something")
    (env.config.data_dir / "sync/.items.json.tmp123").write_text("interrupted write")
    env.clock.now += 4 * HOUR
    env.server.sync["items"].append(task("t99", "New"))
    _run(env)
    files = git("ls-tree", "-r", "--name-only", "main", cwd=env.remote).split()
    assert "notes.txt" not in files and not any("tmp" in f for f in files)
    assert not (env.config.data_dir / "sync/.items.json.tmp123").exists()


# History


def test_remote_reset_to_an_older_commit_is_repaired_and_reported(env):
    _run(env)
    first = git("rev-parse", "main", cwd=env.remote).strip()
    env.clock.now += 4 * HOUR
    env.server.sync["items"].append(task("t99", "New"))
    _run(env)
    git("update-ref", "refs/heads/main", first, cwd=env.remote)
    env.clock.now += 4 * HOUR
    assert _run(env) == 0
    assert env.notifier.kinds() == [Alert.REPAIRED]
    assert len(env.remote_log()) == 2


# Setup


@pytest.fixture
def fake_commands(monkeypatch, tmp_path):
    """Fakes the commands setup runs. Returns the calls; set `gh_add_fails` to break gh."""
    calls: list[list[str]] = []
    options = {"gh_add_fails": False}

    def fake_run(cmd, *args, **kwargs):
        calls.append(cmd)
        if cmd[:3] == ["gh", "auth", "status"]:
            return subprocess.CompletedProcess(cmd, 0, "", "")
        if cmd[0].endswith("scutil"):
            return subprocess.CompletedProcess(cmd, 0, "test-host\n", "")
        if cmd[0] == "ssh-keygen":
            key = Path(cmd[cmd.index("-f") + 1])
            key.write_text("private")
            key.with_name(key.name + ".pub").write_text("public")
            return subprocess.CompletedProcess(cmd, 0)
        if cmd[:4] == ["gh", "repo", "deploy-key", "add"]:
            return subprocess.CompletedProcess(cmd, 1 if options["gh_add_fails"] else 0)
        raise AssertionError(f"unexpected command {cmd}")

    monkeypatch.setattr(cli.subprocess, "run", fake_run)
    monkeypatch.setattr(cli, "_deploy_key_works", lambda config: True)
    return calls, options


def test_failed_deploy_key_upload_removes_the_new_key(env, fake_commands):
    _, options = fake_commands
    options["gh_add_fails"] = True
    with pytest.raises(SetupError):
        cli._setup_deploy_key(env.config)
    assert not env.config.deploy_key.exists()
    assert not env.config.deploy_key.with_name(env.config.deploy_key.name + ".pub").exists()


def test_deploy_key_is_created_and_added(env, fake_commands):
    calls, _ = fake_commands
    cli._setup_deploy_key(env.config)
    assert env.config.deploy_key.exists()
    assert ["gh", "repo", "deploy-key", "add"] == calls[-1][:4]
    assert "--allow-write" in calls[-1]


def test_setup_never_fails_setup_sh(env, monkeypatch, capsys):
    def boom(config):
        raise RuntimeError("keychain exploded")

    class LockedKeychain:
        def read(self, service):
            raise RuntimeError("keychain exploded")

    monkeypatch.setattr(cli, "MacKeychain", LockedKeychain)
    monkeypatch.setattr(cli.Config, "default", classmethod(lambda cls: env.config))
    assert cli.main(["setup"]) == 0
    assert "keychain exploded" in capsys.readouterr().err


# Static guarantees


PACKAGE = Path(api.__file__).resolve().parent


def test_no_other_way_to_reach_todoist():
    for path in PACKAGE.glob("*.py"):
        source = path.read_text()
        if path.name != "api.py":
            assert "api.todoist.com" not in source, path.name
        for tool in ("curl", "wget", "requests", "httpx"):
            assert f'"{tool}"' not in source and f"import {tool}" not in source, path.name


def test_only_setup_uses_the_gh_login():
    for path in PACKAGE.glob("*.py"):
        if path.name != "cli.py":
            assert '"gh"' not in path.read_text(), path.name


def test_restore_plan_reads_are_reads():
    from conftest import FakeTodoist, StaticTokens

    server = FakeTodoist()
    client = TodoistClient(StaticTokens(), server)
    fetch.fetch_live_view(client)
    from datetime import datetime, timedelta

    now = datetime.now(UTC)
    fetch.fetch_completed(client, now - timedelta(days=200), now)
    assert {r.method for r in server.requests} <= {"GET", "POST"}
    assert all(
        r.method == "GET" or (r.url.endswith(api.SYNC_PATH) and b"commands" not in r.body)
        for r in server.requests
    )
