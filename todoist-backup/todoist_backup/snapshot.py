"""The on-disk snapshot format: one pretty-printed, deterministically sorted JSON file per
resource type, so git diffs show exactly what changed.

Layout (paths relative to the data repo):
  sync/<resource>.json     everything a full sync returns, minus VOLATILE_SYNC_KEYS
  archived/<kind>.json     archived projects, and their sections, tasks and comments
  completed/YYYY-MM.json   completed tasks by completion month (UTC), accumulated over time
"""

from __future__ import annotations

import json
import os
import re
import tempfile
from collections.abc import Iterable, Iterator, Mapping
from datetime import datetime
from pathlib import Path
from typing import Any

MANAGED_DIRS = ("sync", "archived", "completed")

# Sync fields that change without any change to your data, and would otherwise make a
# commit on every run.
VOLATILE_SYNC_KEYS = frozenset(
    {
        "sync_token",
        "full_sync",
        "full_sync_date_utc",
        "live_notifications",
        "live_notifications_last_read",
        "live_notifications_last_read_id",
        "stats",
        "user_plan_limits",
        "day_orders",
        # Sync protocol bookkeeping, not data.
        "sync_status",
        "temp_id_mapping",
        # Todoist's permission matrix: the same every sync but in a random order.
        "role_actions",
    }
)
# Per-object fields with the same problem, by sync resource.
VOLATILE_FIELDS: Mapping[str, frozenset[str]] = {
    "user": frozenset({"karma", "karma_trend", "websocket_url"}),
}

Files = dict[str, Any]

# Fields that hold credentials. A snapshot containing one is refused rather than stripped,
# since it means Todoist's data has changed in a way worth looking at.
SECRET_FIELDS = frozenset(
    {"token", "api_token", "access_token", "refresh_token", "client_secret", "password"}
)
# Account metadata, as opposed to user-written content, where a token in a URL can only be
# a credential. Content files aren't checked, since a pasted link could contain one.
ACCOUNT_FILES = re.compile(
    r"sync/(user|user_settings|collaborators|workspaces?|workspace_users)\.json"
)
URL_TOKEN = re.compile(r"[?&](?:[a-z_]*token|key|secret)=", re.IGNORECASE)


def dumps(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def identity(obj: Any) -> str:
    """Stable identity of a resource object: its id where it has one, else its content."""
    if isinstance(obj, dict) and "id" in obj:
        return str(obj["id"])
    return json.dumps(obj, sort_keys=True, ensure_ascii=False)


def sort_resources(items: list[Any]) -> list[Any]:
    return sorted(items, key=identity)


def _strip(resource: str, value: Any) -> Any:
    fields = VOLATILE_FIELDS.get(resource)
    if not fields:
        return value
    if isinstance(value, dict):
        return {k: v for k, v in value.items() if k not in fields}
    if isinstance(value, list):
        return [_strip(resource, v) for v in value]
    return value


def _walk(value: Any, path: str) -> Iterator[tuple[str, str, Any]]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield path, key, child
            yield from _walk(child, f"{path}.{key}")
    elif isinstance(value, list):
        for i, child in enumerate(value):
            yield from _walk(child, f"{path}[{i}]")


def check_no_secrets(files: Files) -> None:
    """Raises if a snapshot would store something that looks like a credential."""
    for rel, value in files.items():
        for where, key, child in _walk(value, rel):
            if key.lower() in SECRET_FIELDS:
                raise ValueError(f"{where}.{key} looks like a credential; refusing to save it")
            if ACCOUNT_FILES.fullmatch(rel) and isinstance(child, str) and URL_TOKEN.search(child):
                raise ValueError(f"{where}.{key} contains a URL with a token; refusing to save it")


def objects_by_id(files: Mapping[str, Any], paths: Iterable[str]) -> dict[str, dict[str, Any]]:
    """The objects with ids in the given files, keyed by id."""
    objects: dict[str, dict[str, Any]] = {}
    for path in paths:
        for obj in files.get(path, []):
            if isinstance(obj, dict) and "id" in obj:
                objects[str(obj["id"])] = obj
    return objects


def sync_files(sync: Mapping[str, Any]) -> Files:
    files: Files = {}
    for key, value in sync.items():
        if key in VOLATILE_SYNC_KEYS:
            continue
        if not key.replace("_", "").isalnum():
            raise ValueError(f"unexpected sync key {key!r}")
        value = _strip(key, value)
        files[f"sync/{key}.json"] = sort_resources(value) if isinstance(value, list) else value
    return files


def archived_files(archived: Mapping[str, list[Any]]) -> Files:
    return {f"archived/{kind}.json": sort_resources(items) for kind, items in archived.items()}


def completed_key(item: Mapping[str, Any]) -> tuple[str, str]:
    """Recurring tasks complete repeatedly under one id, so the time is part of the key."""
    task_id, completed_at = item.get("id"), item.get("completed_at")
    if not isinstance(task_id, str) or not isinstance(completed_at, str):
        raise ValueError(f"completed task without id or completed_at: {item!r:.200}")
    return task_id, completed_at


def parse_time(value: str) -> datetime:
    parsed = datetime.fromisoformat(value)
    if parsed.tzinfo is None:
        raise ValueError(f"timestamp without a timezone: {value!r}")
    return parsed


def completed_files(items: Iterable[Mapping[str, Any]]) -> Files:
    months: dict[str, list[Any]] = {}
    for item in items:
        completed_at = completed_key(item)[1]
        month = parse_time(completed_at).strftime("%Y-%m")
        months.setdefault(f"completed/{month}.json", []).append(item)
    return {
        path: sorted(month_items, key=lambda i: (i["completed_at"], i["id"]))
        for path, month_items in months.items()
    }


def merge_completed(
    existing: Iterable[Mapping[str, Any]], fetched: Iterable[Mapping[str, Any]]
) -> list[Any]:
    """Union of both, preferring freshly fetched copies. Nothing is ever dropped, so tasks
    deleted after completion stay in the archive."""
    merged = {completed_key(i): i for i in existing}
    merged.update({completed_key(i): i for i in fetched})
    return list(merged.values())


def read_files(data_dir: Path) -> Files:
    """Reads every managed JSON file. Raises on anything unparseable."""
    files: Files = {}
    for directory in MANAGED_DIRS:
        for path in sorted((data_dir / directory).glob("*.json")):
            files[path.relative_to(data_dir).as_posix()] = json.loads(path.read_text())
    return files


def completed_items(files: Mapping[str, Any]) -> list[Any]:
    items: list[Any] = []
    for path, value in files.items():
        if path.startswith("completed/"):
            if not isinstance(value, list):
                raise ValueError(f"{path} is not a list")
            items.extend(value)
    return items


MANAGED_FILE = re.compile(r"(sync|archived|completed)/[A-Za-z0-9_-]+\.json")


def write_files(data_dir: Path, files: Files) -> None:
    """Makes the managed directories hold exactly `files`, and nothing else."""
    for rel in files:
        if not MANAGED_FILE.fullmatch(rel):
            raise ValueError(f"refusing to write outside the managed directories: {rel}")
    check_no_secrets(files)
    for directory in MANAGED_DIRS:
        # Temp files left by an interrupted write.
        for stray in (data_dir / directory).glob(".*"):
            stray.unlink()
    for rel, value in files.items():
        _atomic_write(data_dir / rel, dumps(value))
    for directory in MANAGED_DIRS:
        for path in (data_dir / directory).glob("*.json"):
            if path.relative_to(data_dir).as_posix() not in files:
                path.unlink()


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=f".{path.name}.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise
