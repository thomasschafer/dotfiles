"""Fetches everything the backup stores. Read-only: it only uses TodoistClient."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from . import snapshot
from .api import TodoistClient
from .config import COMPLETED_OVERLAP_DAYS

COMPLETED_PATH = "/api/v1/tasks/completed/by_completion_date"
# The endpoint accepts ranges of up to three months.
COMPLETED_WINDOW = timedelta(days=89)


@dataclass(frozen=True)
class Fetched:
    sync: dict[str, Any]
    archived: dict[str, list[Any]]
    completed_fetched: list[Any]
    files: snapshot.Files


def iso(moment: datetime) -> str:
    return moment.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def fetch_completed(client: TodoistClient, since: datetime, until: datetime) -> list[Any]:
    items: list[Any] = []
    start = since
    while start < until:
        end = min(start + COMPLETED_WINDOW, until)
        items.extend(
            client.get_all(
                COMPLETED_PATH, {"since": iso(start), "until": iso(end)}, results_key="items"
            )
        )
        start = end
    return items


def fetch_archived(client: TodoistClient) -> dict[str, list[Any]]:
    """Archived projects aren't in the sync response, nor is anything inside them."""
    projects = client.get_all("/api/v1/projects/archived")
    sections: list[Any] = []
    tasks: list[Any] = []
    comments: list[Any] = []
    for project in projects:
        project_id = {"project_id": project["id"]}
        sections.extend(client.get_all("/api/v1/sections", project_id))
        project_tasks = client.get_all("/api/v1/tasks", project_id)
        tasks.extend(project_tasks)
        comments.extend(client.get_all("/api/v1/comments", project_id))
        for task in project_tasks:
            if task.get("note_count", 1):
                comments.extend(client.get_all("/api/v1/comments", {"task_id": task["id"]}))
    return {"projects": projects, "sections": sections, "tasks": tasks, "comments": comments}


def joined_at(sync: dict[str, Any]) -> datetime:
    user = sync.get("user")
    if not isinstance(user, dict) or not isinstance(user.get("joined_at"), str):
        raise ValueError("sync response has no user.joined_at")
    return snapshot.parse_time(user["joined_at"])


def completed_since(sync: dict[str, Any], existing: list[Any]) -> datetime:
    """Full history on the first run, then from the newest stored completion minus an overlap."""
    if not existing:
        return joined_at(sync) - timedelta(days=1)
    newest = max(snapshot.parse_time(snapshot.completed_key(i)[1]) for i in existing)
    return newest - timedelta(days=COMPLETED_OVERLAP_DAYS)


def fetch_all(client: TodoistClient, existing: list[Any], now: datetime) -> Fetched:
    """Fetches a full snapshot. `existing` is the completed-task history from the last
    commit, which this run's completions are merged into."""
    sync = client.sync_read()
    archived = fetch_archived(client)
    fetched_completed = fetch_completed(client, completed_since(sync, existing), now)
    files = {
        **snapshot.sync_files(sync),
        **snapshot.archived_files(archived),
        **snapshot.completed_files(snapshot.merge_completed(existing, fetched_completed)),
    }
    return Fetched(sync, archived, fetched_completed, files)


def fetch_live_view(client: TodoistClient) -> snapshot.Files:
    """A fresh read of the sync and archived data, normalised like a snapshot."""
    return {
        **snapshot.sync_files(client.sync_read()),
        **snapshot.archived_files(fetch_archived(client)),
    }
