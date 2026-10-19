from __future__ import annotations

import json

import pytest
from conftest import completed, task

from todoist_backup import api, restore_plan, snapshot, verify
from todoist_backup.auth import (
    Credentials,
    KeychainTokenSource,
    ReauthorizeNeeded,
    ScopeError,
    credentials_from_token_response,
)

# Deletion detector


@pytest.mark.parametrize(
    ("before", "missing", "alarming"),
    [
        (5, 2, False),  # under the minimum drop
        (5, 3, True),  # 60%
        (100, 10, False),  # exactly 10%: not more than
        (100, 11, True),
        (1000, 20, False),  # 2%, and not more than 20 items
        (1000, 21, True),  # more than 20 items
        (0, 0, False),
    ],
)
def test_deletion_thresholds(before, missing, alarming):
    assert verify.is_alarming(before, missing) is alarming


def _files(items, projects=None, archived_tasks=(), archived_projects=(), done=()):
    files = {
        "sync/items.json": list(items),
        "sync/projects.json": list(projects or [{"id": "p1", "name": "Inbox"}]),
        "archived/tasks.json": list(archived_tasks),
        "archived/projects.json": list(archived_projects),
    }
    if done:
        files["completed/2026-10.json"] = list(done)
    return files


def test_detects_deleted_tasks_with_names():
    before = _files([task(f"t{i}", f"Task {i}") for i in range(10)])
    after = _files([task(f"t{i}", f"Task {i}") for i in range(5)])
    [drop] = verify.detect_deletions(before, after)
    assert drop.kind == "tasks" and drop.missing == {f"t{i}" for i in range(5, 10)}
    assert drop.names == tuple(f"Task {i}" for i in range(5, 10))


def test_archiving_a_project_is_not_a_deletion():
    tasks = [task(f"t{i}", "x", "p2") for i in range(10)]
    projects = [{"id": "p1", "name": "Inbox"}, {"id": "p2", "name": "Big"}]
    before = _files(tasks, projects)
    after = _files([], projects[:1], archived_tasks=tasks, archived_projects=projects[1:])
    assert verify.detect_deletions(before, after) == []


def test_deleted_projects_alert():
    projects = [{"id": f"p{i}", "name": f"P{i}"} for i in range(6)]
    [drop] = verify.detect_deletions(_files([], projects), _files([], projects[:3]))
    assert drop.kind == "projects"


def test_compare_with_live_reports_counts_and_ids():
    written = {"sync/items.json": [task("a", "x"), task("b", "y")], "sync/user.json": {"id": "u"}}
    live = {"sync/items.json": [task("b", "y"), task("c", "z")], "sync/user.json": {"id": "u"}}
    [problem] = verify.compare_with_live(written, live)
    assert "2 in snapshot, 2 live" in problem and "only live: c" in problem
    assert "only in snapshot: a" in problem
    assert verify.compare_with_live(written, written) == []


def test_verify_written_catches_corruption(tmp_path):
    files = {"sync/items.json": [task("a", "x")]}
    snapshot.write_files(tmp_path, files)
    assert verify.verify_written(tmp_path, files) == []
    (tmp_path / "sync/items.json").write_text("{not json")
    assert "doesn't parse" in verify.verify_written(tmp_path, files)[0]


# Snapshot format


def test_snapshot_is_deterministic_and_strips_volatile_data():
    sync = {
        "items": [task("b", "2"), task("a", "1")],
        "sync_token": "x",
        "full_sync": True,
        "user": {"id": "u", "karma": 5, "full_name": "T"},
    }
    files = snapshot.sync_files(sync)
    assert set(files) == {"sync/items.json", "sync/user.json"}
    assert [i["id"] for i in files["sync/items.json"]] == ["a", "b"]
    assert files["sync/user.json"] == {"id": "u", "full_name": "T"}
    assert snapshot.dumps(files["sync/user.json"]) == '{\n  "full_name": "T",\n  "id": "u"\n}\n'


def test_write_files_removes_resources_that_vanished(tmp_path):
    snapshot.write_files(tmp_path, {"sync/a.json": [], "sync/b.json": []})
    snapshot.write_files(tmp_path, {"sync/a.json": []})
    assert sorted(p.name for p in (tmp_path / "sync").iterdir()) == ["a.json"]


def test_write_files_refuses_paths_outside_managed_dirs(tmp_path):
    with pytest.raises(ValueError):
        snapshot.write_files(tmp_path, {"../escape.json": []})
    with pytest.raises(ValueError):
        snapshot.write_files(tmp_path, {"sync/../../escape.json": []})


def test_completed_merge_keeps_recurring_occurrences_and_old_items():
    old = [completed("r", "2026-01-01T10:00:00Z"), completed("gone", "2026-01-02T10:00:00Z")]
    new = [completed("r", "2026-02-01T10:00:00Z"), completed("r", "2026-01-01T10:00:00Z", "edited")]
    merged = snapshot.merge_completed(old, new)
    assert len(merged) == 3
    files = snapshot.completed_files(merged)
    assert set(files) == {"completed/2026-01.json", "completed/2026-02.json"}
    assert files["completed/2026-01.json"][0]["content"] == "edited"


# Credentials


class MemoryKeychain:
    def __init__(self, value=None, fail_writes=0):
        self.value, self.fail_writes, self.writes = value, fail_writes, 0

    def read(self, service):
        return self.value

    def write(self, service, value):
        self.writes += 1
        if self.fail_writes:
            self.fail_writes -= 1
            raise OSError("keychain unavailable")
        self.value = value


def _creds(expires_at, refresh="r1"):
    return Credentials("cid", "csecret", "a1", refresh, expires_at)


def _token_transport(responses, seen):
    def transport(request):
        seen.append(request)
        status, body = responses.pop(0)
        return api.HttpResponse(status, json.dumps(body).encode())

    return transport


def test_fresh_token_is_used_without_refreshing(tmp_path):
    keychain = MemoryKeychain(_creds(10_000).to_json())
    seen = []
    source = KeychainTokenSource(
        keychain, "svc", tmp_path / "lock", _token_transport([], seen), clock=lambda: 0
    )
    assert source.access_token() == "a1"
    assert seen == []


def test_expired_token_is_refreshed_and_rotation_stored(tmp_path):
    keychain = MemoryKeychain(_creds(100).to_json())
    seen = []
    transport = _token_transport(
        [
            (
                200,
                {
                    "access_token": "a2",
                    "refresh_token": "r2",
                    "expires_in": 3600,
                    "token_type": "Bearer",
                    "scope": "data:read",
                },
            )
        ],
        seen,
    )
    source = KeychainTokenSource(keychain, "svc", tmp_path / "lock", transport, clock=lambda: 0)
    assert source.access_token() == "a2"
    stored = Credentials.from_json(keychain.value)
    assert (stored.access_token, stored.refresh_token, stored.expires_at) == ("a2", "r2", 3600)
    assert b"grant_type=refresh_token" in seen[0].body and b"refresh_token=r1" in seen[0].body
    assert source.access_token() == "a2" and len(seen) == 1


def test_failed_keychain_write_after_refresh_is_retried_then_fatal(tmp_path):
    keychain = MemoryKeychain(_creds(0).to_json(), fail_writes=5)
    transport = _token_transport(
        [(200, {"access_token": "a2", "refresh_token": "r2", "expires_in": 3600})], []
    )
    source = KeychainTokenSource(keychain, "svc", tmp_path / "lock", transport, clock=lambda: 0)
    with pytest.raises(ReauthorizeNeeded):
        source.access_token()
    assert keychain.writes == 3


def test_refused_refresh_needs_reauthorisation(tmp_path):
    keychain = MemoryKeychain(_creds(0).to_json())
    transport = _token_transport([(400, {"error": "invalid_grant"})], [])
    source = KeychainTokenSource(keychain, "svc", tmp_path / "lock", transport, clock=lambda: 0)
    with pytest.raises(ReauthorizeNeeded):
        source.access_token()


def test_write_scope_is_refused():
    with pytest.raises(ScopeError):
        credentials_from_token_response(
            {"access_token": "a", "scope": "data:read,data:delete"},
            client_id="c",
            client_secret="s",
            now=0,
        )
    with pytest.raises(ScopeError):
        credentials_from_token_response(
            {"access_token": "a", "scope": "data:read_write"},
            client_id="c",
            client_secret="s",
            now=0,
        )


def test_corrupt_stored_credentials_need_reauthorisation():
    with pytest.raises(ReauthorizeNeeded):
        Credentials.from_json('{"client_id": "x"}')


def test_client_retries_rate_limits_then_succeeds():
    responses = [(429, {}), (503, {}), (200, {"ok": True})]
    seen, waits = [], []
    result = api.send(
        _token_transport(responses, seen), "GET", "/api/v1/user", bearer="t", sleep=waits.append
    )
    assert result == {"ok": True} and len(seen) == 3 and len(waits) == 2


def test_errors_never_include_the_token():
    def transport(request):
        return api.HttpResponse(400, f"bad token {request.headers['Authorization']}".encode())

    with pytest.raises(api.ApiError) as e:
        api.send(transport, "GET", "/api/v1/user", bearer="SECRET-TOKEN-123")
    assert "SECRET-TOKEN-123" not in str(e.value)


# Restore plan


def test_restore_plan_lists_missing_changed_and_completed():
    snap = {
        "sync/projects.json": [{"id": "p1", "name": "Inbox"}, {"id": "p2", "name": "Gone"}],
        "sync/sections.json": [],
        "sync/items.json": [
            task(
                "t1",
                "Deleted task",
                "p1",
                description="details",
                labels=["home"],
                due={"string": "every monday", "is_recurring": True},
            ),
            task("t2", "Edited", "p1"),
            task("t3", "Completed since", "p1"),
            task("t4", "In gone project", "p2"),
        ],
        "sync/labels.json": [{"id": "l1", "name": "home"}],
    }
    live = {
        "sync/projects.json": [{"id": "p1", "name": "Inbox"}],
        "sync/sections.json": [],
        "sync/items.json": [
            task("t2", "Edited!", "p1", child_order=9),
            task("t5", "Brand new", "p1"),
        ],
        "sync/labels.json": [{"id": "l1", "name": "home"}],
    }
    plan = restore_plan.build_plan("abc123", "2026-10-18T10:00:00Z", snap, live, frozenset({"t3"}))
    text = restore_plan.render(plan)
    assert "Missing tasks, deleted or otherwise gone (2):" in text
    assert "  Inbox\n    - 'Deleted task' [id t1]" in text
    assert "due: every monday (recurring)" in text and "labels: home" in text
    assert "  Gone\n    - 'In gone project' [id t4]" in text
    assert "Missing because completed since the snapshot (1)" in text
    assert "content: 'Edited' → 'Edited!'" in text
    assert "child_order" not in text
    assert "Missing projects (1):\n  - 'Gone' [id p2]" in text
    assert "New since the snapshot, tasks (1)" in text
    data = json.loads(restore_plan.to_json(plan))
    assert [t["id"] for t in data["kinds"]["tasks"]["missing"]] == ["t1", "t3", "t4"]


def test_restore_plan_empty_when_identical():
    files = {"sync/items.json": [task("t1", "x")], "sync/projects.json": []}
    plan = restore_plan.build_plan("abc", "t", files, files, frozenset())
    assert plan.is_empty()
    assert "no differences" in restore_plan.render(plan)
