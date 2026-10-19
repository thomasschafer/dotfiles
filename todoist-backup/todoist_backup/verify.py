"""Checks run on every backup: the written snapshot round-trips, matches live data, and
hasn't lost a suspicious number of tasks or projects since the previous snapshot."""

from __future__ import annotations

from collections.abc import Iterable, Mapping
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any

from . import snapshot
from .config import DELETION_MAX_FRACTION, DELETION_MAX_ITEMS, DELETION_MIN_DROP

SAMPLE = 10


def _sample(ids: Iterable[str]) -> str:
    ids = sorted(ids)
    more = f" and {len(ids) - SAMPLE} more" if len(ids) > SAMPLE else ""
    return ", ".join(ids[:SAMPLE]) + more


def verify_written(data_dir: Path, expected: snapshot.Files) -> list[str]:
    """Re-reads the snapshot from disk; it must parse and equal what was meant to be written."""
    try:
        written = snapshot.read_files(data_dir)
    except ValueError as e:  # json.JSONDecodeError is a ValueError
        return [f"snapshot doesn't parse: {e}"]
    problems = []
    if missing := expected.keys() - written.keys():
        problems.append(f"files not written: {_sample(missing)}")
    if extra := written.keys() - expected.keys():
        problems.append(f"unexpected files: {_sample(extra)}")
    for path in sorted(expected.keys() & written.keys()):
        if written[path] != expected[path]:
            problems.append(f"{path} doesn't match what was fetched")
    return problems


def ids_by_file(files: Mapping[str, Any], prefixes: tuple[str, ...]) -> dict[str, set[str]]:
    return {
        path: {snapshot.identity(item) for item in value}
        for path, value in files.items()
        if path.startswith(prefixes) and isinstance(value, list)
    }


def compare_with_live(written: snapshot.Files, live: snapshot.Files) -> list[str]:
    """Compares counts and ids per resource type between the snapshot and a fresh read."""
    prefixes = ("sync/", "archived/")
    written_ids = ids_by_file(written, prefixes)
    live_ids = ids_by_file(live, prefixes)
    problems = []
    for path in sorted(written_ids.keys() | live_ids.keys()):
        ours, theirs = written_ids.get(path, set()), live_ids.get(path, set())
        if ours == theirs:
            continue
        detail = [f"{path}: {len(ours)} in snapshot, {len(theirs)} live"]
        if theirs - ours:
            detail.append(f"only live: {_sample(theirs - ours)}")
        if ours - theirs:
            detail.append(f"only in snapshot: {_sample(ours - theirs)}")
        problems.append("; ".join(detail))
    return problems


def check_completed(written: snapshot.Files, live_completed: Iterable[Any]) -> list[str]:
    stored = {
        snapshot.completed_key(item)
        for path, value in written.items()
        if path.startswith("completed/")
        for item in value
    }
    missing = {f"{i}@{t}" for i, t in map(snapshot.completed_key, live_completed)} - {
        f"{i}@{t}" for i, t in stored
    }
    return (
        [f"recently completed tasks missing from snapshot: {_sample(missing)}"] if missing else []
    )


def lost_completions(existing: Iterable[Any], files: snapshot.Files) -> str | None:
    """The completed history only ever grows; returns a problem if anything was dropped."""
    stored = set(map(snapshot.completed_key, snapshot.completed_items(files)))
    lost = set(map(snapshot.completed_key, existing)) - stored
    if not lost:
        return None
    return f"{len(lost)} stored completions would be dropped: {_sample(i for i, _ in lost)}"


@dataclass(frozen=True)
class Drop:
    kind: str
    before: int
    missing: frozenset[str]
    baseline: str

    def describe(self) -> str:
        pct = 100 * len(self.missing) / self.before if self.before else 100
        return (
            f"{len(self.missing)} of {self.before} active {self.kind} disappeared ({pct:.0f}%) "
            f"since {self.baseline}"
        )


def is_alarming(before: int, missing: int) -> bool:
    if missing < DELETION_MIN_DROP:
        return False
    return missing > DELETION_MAX_ITEMS or missing > before * DELETION_MAX_FRACTION


ACTIVE_KINDS = (
    ("tasks", ("sync/items.json", "archived/tasks.json")),
    ("projects", ("sync/projects.json", "archived/projects.json")),
)


def detect_deletions(
    baseline: snapshot.Files, current: snapshot.Files, since: datetime, label: str
) -> list[Drop]:
    """Active tasks or projects in `baseline` that are gone from `current`. Archived ones
    count as present, and tasks completed after `since` (the baseline's time) don't count.
    Earlier completions are ignored, so deleting a recurring task still counts."""
    completed_ids = {
        task_id
        for task_id, completed_at in map(snapshot.completed_key, snapshot.completed_items(current))
        if snapshot.parse_time(completed_at) >= since
    }
    drops = []
    for kind, paths in ACTIVE_KINDS:
        before = snapshot.objects_by_id(baseline, paths)
        after = snapshot.objects_by_id(current, paths)
        missing = before.keys() - after.keys()
        if kind == "tasks":
            missing -= completed_ids
        if is_alarming(len(before), len(missing)):
            drops.append(Drop(kind, len(before), frozenset(missing), label))
    return drops
