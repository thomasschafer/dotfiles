from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import urllib.parse
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from todoist_backup import api  # noqa: E402
from todoist_backup.api import HttpRequest, HttpResponse, TodoistClient  # noqa: E402
from todoist_backup.config import Config  # noqa: E402
from todoist_backup.notify import Alert  # noqa: E402
from todoist_backup.run import Deps  # noqa: E402

TOKEN = "fake-test-token-not-a-real-secret"
NOW = datetime.fromisoformat("2026-10-19T12:00:00+00:00").timestamp()


def task(task_id: str, content: str, project_id: str = "p1", **extra: Any) -> dict[str, Any]:
    return {
        "id": task_id,
        "content": content,
        "project_id": project_id,
        "section_id": None,
        "parent_id": None,
        "description": "",
        "priority": 1,
        "labels": [],
        "due": None,
        "checked": False,
        "is_deleted": False,
        "child_order": 1,
        "note_count": 0,
        **extra,
    }


def completed(task_id: str, completed_at: str, content: str = "done") -> dict[str, Any]:
    return {**task(task_id, content), "checked": True, "completed_at": completed_at}


@dataclass
class FakeTodoist:
    """Serves the read endpoints the backup uses, from in-memory data."""

    sync: dict[str, Any] = field(
        default_factory=lambda: {
            "sync_token": "abc",
            "full_sync": True,
            "full_sync_date_utc": "2026-10-19T12:00:00Z",
            "user": {
                "id": "u1",
                "full_name": "Tom",
                "joined_at": "2025-01-10T09:00:00.000000Z",
                "karma": 100,
            },
            "projects": [
                {"id": "p1", "name": "Inbox", "child_order": 0},
                {"id": "p2", "name": "Work", "child_order": 1},
            ],
            "sections": [{"id": "s1", "name": "Later", "project_id": "p2"}],
            "items": [task(f"t{i}", f"Task {i}") for i in range(1, 31)],
            "labels": [{"id": "l1", "name": "home"}],
            "filters": [],
            "notes": [],
            "project_notes": [],
            "reminders": [],
            "stats": {"days_items": []},
            "live_notifications": [{"id": "n1"}],
        }
    )
    archived_projects: list[dict[str, Any]] = field(
        default_factory=lambda: [{"id": "p9", "name": "Old", "is_archived": True}]
    )
    archived_tasks: dict[str, list[dict[str, Any]]] = field(
        default_factory=lambda: {"p9": [task("t90", "Archived task", "p9", note_count=1)]}
    )
    archived_sections: dict[str, list[dict[str, Any]]] = field(default_factory=dict)
    comments: dict[str, list[dict[str, Any]]] = field(
        default_factory=lambda: {"task:t90": [{"id": "c1", "item_id": "t90", "content": "a note"}]}
    )
    completed: list[dict[str, Any]] = field(
        default_factory=lambda: [
            completed("d1", "2025-03-01T10:00:00.000000Z"),
            completed("d2", "2026-10-18T10:00:00.000000Z"),
        ]
    )
    requests: list[HttpRequest] = field(default_factory=list)
    offline: bool = False
    # Fails this many requests as offline, then recovers.
    offline_requests: int = 0
    error: Exception | None = None
    fail_status: int | None = None
    on_sync: Any = None

    def __call__(self, request: HttpRequest) -> HttpResponse:
        self.requests.append(request)
        if self.offline:
            raise api.OfflineError("no network")
        if self.offline_requests:
            self.offline_requests -= 1
            raise api.OfflineError("no network yet")
        if self.error:
            raise self.error
        if self.fail_status:
            return HttpResponse(self.fail_status, b'{"error": "boom"}')
        if request.headers.get("Authorization") != f"Bearer {TOKEN}":
            return HttpResponse(401, b'{"error": "Unauthorized"}')
        url = urllib.parse.urlsplit(request.url)
        query = dict(urllib.parse.parse_qsl(url.query))
        if request.method == "POST" and url.path == api.SYNC_PATH:
            if self.on_sync:
                self.on_sync(self)
            return self._json(copy.deepcopy(self.sync))
        if request.method != "GET":
            raise AssertionError(f"fake server got a non-read request: {request.method} {url.path}")
        if url.path == "/api/v1/user":
            return self._json(self.sync["user"])
        if url.path == "/api/v1/projects/archived":
            return self._page(self.archived_projects, query)
        if url.path == "/api/v1/tasks":
            return self._page(self.archived_tasks.get(query["project_id"], []), query)
        if url.path == "/api/v1/sections":
            return self._page(self.archived_sections.get(query["project_id"], []), query)
        if url.path == "/api/v1/comments":
            key = (
                f"task:{query['task_id']}"
                if "task_id" in query
                else f"project:{query['project_id']}"
            )
            return self._page(self.comments.get(key, []), query)
        if url.path == "/api/v1/tasks/completed/by_completion_date":
            since, until = (datetime.fromisoformat(query[k]) for k in ("since", "until"))
            if (until - since).days > 92:
                return HttpResponse(400, b'{"error": "range too long"}')
            items = [
                c
                for c in self.completed
                if since <= datetime.fromisoformat(c["completed_at"]) < until
            ]
            return self._page(items, query, key="items")
        raise AssertionError(f"unexpected GET {url.path}")

    @staticmethod
    def _json(value: Any) -> HttpResponse:
        return HttpResponse(200, json.dumps(value).encode())

    def _page(self, items: list[Any], query: dict[str, str], key: str = "results") -> HttpResponse:
        limit = int(query["limit"])
        start = int(query.get("cursor", "0.0").split(".")[0])
        page = items[start : start + limit]
        cursor = f"{start + limit}.x" if start + limit < len(items) else None
        return self._json({key: copy.deepcopy(page), "next_cursor": cursor})


class StaticTokens:
    def __init__(self, token: str = TOKEN):
        self.token = token
        self.forced = 0

    def access_token(self, *, force_refresh: bool = False) -> str:
        if force_refresh:
            self.forced += 1
        return self.token


class RecordingNotifier:
    def __init__(self) -> None:
        self.alerts: list[tuple[Alert, str]] = []

    def notify(self, alert: Alert, message: str) -> None:
        self.alerts.append((alert, message))

    def kinds(self) -> list[Alert]:
        return [a for a, _ in self.alerts]


class Clock:
    def __init__(self, now: float = NOW):
        self.now = now

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


def git(*args: str, cwd: Path) -> str:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
        env={
            "PATH": os.environ["PATH"],
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_AUTHOR_NAME": "t",
            "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t",
            "GIT_COMMITTER_EMAIL": "t@t",
        },
    ).stdout


@dataclass
class Env:
    config: Config
    remote: Path
    server: FakeTodoist
    notifier: RecordingNotifier
    clock: Clock
    tokens: StaticTokens

    def deps(self) -> Deps:
        return Deps(
            config=self.config,
            client=TodoistClient(self.tokens, self.server, sleep=lambda s: None),
            secrets=lambda: [TOKEN],
            notifier=self.notifier,
            clock=self.clock,
            sleep=self.clock.advance,
        )

    def remote_log(self) -> list[str]:
        return git("log", "--format=%s", "main", cwd=self.remote).splitlines()


@pytest.fixture
def env(tmp_path: Path) -> Env:
    remote = tmp_path / "remote.git"
    git("init", "--bare", "--initial-branch=main", str(remote), cwd=tmp_path)
    config = Config(
        data_dir=tmp_path / "data",
        state_dir=tmp_path / "state",
        deploy_key=tmp_path / "no-key",
        known_hosts=tmp_path / "no-hosts",
        remote_url=str(remote),
        keychain_service="todoist-backup-test",
    )
    return Env(config, remote, FakeTodoist(), RecordingNotifier(), Clock(), StaticTokens())
