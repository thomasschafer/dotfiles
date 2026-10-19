"""End-to-end runs against the fake API and a local bare git remote."""

from __future__ import annotations

import json
import logging
import shutil

from conftest import TOKEN, Env, completed, git, task

from todoist_backup.notify import Alert
from todoist_backup.run import run
from todoist_backup.state import State

HOUR = 3600


def _run(env: Env) -> int:
    return run(env.deps())


def _state(env: Env) -> State:
    return State.load(env.config.state_file, 0)


def test_first_run_writes_commits_and_pushes(env):
    assert _run(env) == 0
    data = env.config.data_dir
    items = json.loads((data / "sync/items.json").read_text())
    assert [i["id"] for i in items] == sorted(f"t{i}" for i in range(1, 31))
    assert (data / "archived/tasks.json").exists()
    assert json.loads((data / "archived/comments.json").read_text())[0]["id"] == "c1"
    assert (data / "completed/2025-03.json").exists()
    assert (data / "completed/2026-10.json").exists()
    assert len(env.remote_log()) == 1
    assert env.notifier.alerts == []
    state = _state(env)
    assert state.last_result == "ok" and state.last_success == env.clock.now
    assert state.last_pushed == git("rev-parse", "main", cwd=env.remote).strip()


def test_volatile_fields_are_not_saved(env):
    _run(env)
    data = env.config.data_dir
    for name in ("sync_token", "full_sync", "full_sync_date_utc", "stats", "live_notifications"):
        assert not (data / f"sync/{name}.json").exists()
    assert "karma" not in json.loads((data / "sync/user.json").read_text())


def test_output_is_pretty_and_sorted(env):
    env.server.sync["items"].reverse()
    _run(env)
    text = (env.config.data_dir / "sync/projects.json").read_text()
    assert text == json.dumps(json.loads(text), indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def test_unchanged_data_makes_no_commit(env):
    _run(env)
    env.clock.now += 4 * HOUR
    env.server.sync["sync_token"] = "different"
    env.server.sync["stats"] = {"karma": 5}
    assert _run(env) == 0
    assert len(env.remote_log()) == 1


def test_changes_are_committed(env):
    _run(env)
    env.clock.now += 4 * HOUR
    env.server.sync["items"].append(task("t99", "New task"))
    assert _run(env) == 0
    assert len(env.remote_log()) == 2
    diff = git("show", "--stat", "main", cwd=env.remote)
    assert "sync/items.json" in diff


def test_completed_history_is_paginated_and_incremental(env):
    env.server.completed = [
        completed(f"d{i}", f"2025-{2 + i % 11:02d}-{1 + i % 27:02d}T10:00:00.000000Z")
        for i in range(450)
    ]
    _run(env)
    stored = sum(
        len(json.loads(p.read_text())) for p in (env.config.data_dir / "completed").glob("*.json")
    )
    assert stored == 450

    env.server.requests.clear()
    env.clock.now += 4 * HOUR
    env.server.completed = [completed("new", "2026-10-19T11:00:00.000000Z")]
    _run(env)
    windows = [r.url for r in env.server.requests if "by_completion_date" in r.url]
    # Starts from the newest stored completion minus the overlap, not the join date.
    assert all("since=2025" in w for w in windows[:1])
    assert len(windows) < 10
    stored = sum(
        len(json.loads(p.read_text())) for p in (env.config.data_dir / "completed").glob("*.json")
    )
    assert stored == 451, "older completions must be kept even though they weren't re-fetched"


def test_mass_deletion_commits_and_alerts(env):
    _run(env)
    env.clock.now += 4 * HOUR
    env.server.sync["items"] = env.server.sync["items"][:20]
    assert _run(env) == 0
    assert env.remote_log()[0].startswith("DELETIONS DETECTED: 10 of 31 active tasks")
    assert env.notifier.kinds() == [Alert.DELETIONS]


def test_completing_tasks_is_not_a_deletion(env):
    _run(env)
    env.clock.now += 4 * HOUR
    done = env.server.sync["items"][:15]
    env.server.sync["items"] = env.server.sync["items"][15:]
    env.server.completed += [completed(t["id"], "2026-10-19T11:30:00.000000Z") for t in done]
    _run(env)
    assert env.notifier.alerts == []


def test_offline_runs_skip_quietly(env):
    env.server.offline = True
    assert _run(env) == 0
    assert env.notifier.alerts == []
    assert _state(env).last_result == "offline"
    assert not (env.config.data_dir / "sync").exists()


def test_stale_alert_after_a_day_without_success_and_not_repeated(env):
    _run(env)
    env.server.offline = True
    env.clock.now += 23 * HOUR
    _run(env)
    assert env.notifier.alerts == []
    env.clock.now += 2 * HOUR
    _run(env)
    assert env.notifier.kinds() == [Alert.STALE]
    env.clock.now += 4 * HOUR
    _run(env)
    assert env.notifier.kinds() == [Alert.STALE]
    env.clock.now += 21 * HOUR
    _run(env)
    assert env.notifier.kinds() == [Alert.STALE, Alert.STALE]


def test_api_failure_alerts_without_leaking_the_token(env, caplog):
    caplog.set_level(logging.DEBUG)
    env.server.fail_status = 500
    assert _run(env) == 1
    assert env.notifier.kinds() == [Alert.FAILED]
    assert TOKEN not in caplog.text
    assert TOKEN not in env.config.state_file.read_text()


def test_token_in_data_blocks_the_commit(env):
    env.server.sync["items"].append(task("t77", f"pasted {TOKEN} by mistake"))
    assert _run(env) == 1
    assert env.notifier.kinds() == [Alert.FAILED]
    assert "secret" in env.notifier.alerts[0][1]
    assert git("log", "--all", "--oneline", cwd=env.remote) == ""


def test_rewritten_remote_is_detected_and_not_overwritten(env, tmp_path):
    _run(env)
    other = tmp_path / "other"
    git("clone", str(env.remote), str(other), cwd=tmp_path)
    git("commit", "--amend", "-m", "rewritten", cwd=other)
    git("push", "--force", "origin", "main", cwd=other)
    env.clock.now += 4 * HOUR
    env.server.sync["items"].append(task("t99", "New task"))
    assert _run(env) == 1
    assert Alert.HISTORY in env.notifier.kinds()
    assert env.remote_log() == ["rewritten"]
    assert "New task" in (env.config.data_dir / "sync/items.json").read_text()


def test_deleted_remote_branch_is_restored(env):
    _run(env)
    git("update-ref", "-d", "refs/heads/main", cwd=env.remote)
    env.clock.now += 4 * HOUR
    _run(env)
    assert Alert.HISTORY in env.notifier.kinds()
    assert len(env.remote_log()) == 1


def test_missing_local_repo_is_recloned(env):
    _run(env)
    shutil.rmtree(env.config.data_dir)
    env.clock.now += 4 * HOUR
    env.server.sync["items"].append(task("t99", "New task"))
    _run(env)
    assert env.notifier.kinds() == [Alert.HISTORY]
    assert len(env.remote_log()) == 2


def test_rewritten_local_history_is_not_pushed(env):
    _run(env)
    env.clock.now += 4 * HOUR
    env.server.sync["items"].append(task("t99", "New task"))
    _run(env)
    git("reset", "--hard", "HEAD~1", cwd=env.config.data_dir)
    git("commit", "--allow-empty", "-m", "local rewrite", cwd=env.config.data_dir)
    env.clock.now += 4 * HOUR
    assert _run(env) == 1
    assert Alert.HISTORY in env.notifier.kinds()
    assert "local rewrite" not in env.remote_log()


def test_persistent_mismatch_with_live_data_alerts(env):
    calls = {"n": 0}

    def change_every_sync(server):
        calls["n"] += 1
        server.sync["items"].append(task(f"x{calls['n']}", "edited during run"))

    env.server.on_sync = change_every_sync
    assert _run(env) == 1
    assert env.notifier.kinds() == [Alert.VERIFICATION]
    assert len(env.remote_log()) == 1, "the snapshot is still committed"


def test_one_off_edit_during_run_is_retried(env):
    calls = {"n": 0}

    def change_once(server):
        calls["n"] += 1
        if calls["n"] == 2:
            server.sync["items"].append(task("x", "edited during run"))

    env.server.on_sync = change_once
    assert _run(env) == 0
    assert env.notifier.alerts == []


def test_expired_token_is_refreshed_once(env):
    env.tokens.token = "stale"
    assert _run(env) == 1
    assert env.tokens.forced == 1
    assert env.notifier.kinds() == [Alert.REAUTHORIZE]
