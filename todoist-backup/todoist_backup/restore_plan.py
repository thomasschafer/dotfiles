"""Compares a snapshot with the live account and reports what's missing or changed. It
only reads: restoring is left to you, following the plan."""

from __future__ import annotations

import json
from collections.abc import Mapping
from dataclasses import dataclass, field
from typing import Any

from . import snapshot

# (kind, files holding it in a snapshot, field naming an object)
KINDS: tuple[tuple[str, tuple[str, ...], str | None], ...] = (
    ("projects", ("sync/projects.json", "archived/projects.json"), "name"),
    ("sections", ("sync/sections.json", "archived/sections.json"), "name"),
    ("tasks", ("sync/items.json", "archived/tasks.json"), "content"),
    (
        "comments",
        ("sync/notes.json", "sync/project_notes.json", "archived/comments.json"),
        "content",
    ),
    ("labels", ("sync/labels.json",), "name"),
    ("filters", ("sync/filters.json",), "name"),
    ("reminders", ("sync/reminders.json",), None),
)
# Ordering and bookkeeping fields that change without anything meaningful changing.
IGNORED_FIELDS = frozenset(
    {
        "child_order",
        "day_order",
        "order_key",
        "section_order",
        "item_order",
        "updated_at",
        "is_collapsed",
        "note_count",
        "default_order",
    }
)
VALUE_WIDTH = 80


@dataclass
class KindDiff:
    kind: str
    missing: list[dict[str, Any]] = field(default_factory=list)
    changed: list[tuple[dict[str, Any], dict[str, tuple[Any, Any]]]] = field(default_factory=list)
    new: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class Plan:
    ref: str
    snapshot_time: str
    diffs: list[KindDiff]
    completed_since: frozenset[str]
    snapshot_files: snapshot.Files

    def is_empty(self) -> bool:
        return not any(d.missing or d.changed for d in self.diffs)


def _other_kinds(files: snapshot.Files) -> list[tuple[str, tuple[str, ...], str | None]]:
    """Any other sync resource that's a list of objects with ids, compared generically."""
    known = {p for _, paths, _ in KINDS for p in paths}
    return [
        (path.removeprefix("sync/").removesuffix(".json"), (path,), None)
        for path, value in sorted(files.items())
        if path.startswith("sync/")
        and path not in known
        and isinstance(value, list)
        and value
        and all(isinstance(v, dict) and "id" in v for v in value)
    ]


def field_changes(old: Mapping[str, Any], new: Mapping[str, Any]) -> dict[str, tuple[Any, Any]]:
    return {
        key: (old.get(key), new.get(key))
        for key in sorted(old.keys() | new.keys())
        if key not in IGNORED_FIELDS and old.get(key) != new.get(key)
    }


def build_plan(
    ref: str,
    snapshot_time: str,
    snap: snapshot.Files,
    live: snapshot.Files,
    completed_since: frozenset[str],
) -> Plan:
    diffs = []
    for kind, paths, _ in (*KINDS, *_other_kinds(snap)):
        before, after = snapshot.objects_by_id(snap, paths), snapshot.objects_by_id(live, paths)
        diff = KindDiff(kind)
        diff.missing = [before[i] for i in sorted(before.keys() - after.keys())]
        diff.new = [after[i] for i in sorted(after.keys() - before.keys())]
        for i in sorted(before.keys() & after.keys()):
            if changes := field_changes(before[i], after[i]):
                diff.changed.append((before[i], changes))
        diffs.append(diff)
    return Plan(ref, snapshot_time, diffs, completed_since, snap)


def _short(value: Any) -> str:
    text = json.dumps(value, ensure_ascii=False) if not isinstance(value, str) else repr(value)
    return text if len(text) <= VALUE_WIDTH else text[: VALUE_WIDTH - 1] + "…"


def _name(kind: str, obj: Mapping[str, Any]) -> str:
    name_field = next((n for k, _, n in KINDS if k == kind), None)
    label = obj.get(name_field) if name_field else None
    return f"{_short(label) if label is not None else '(unnamed)'} [id {obj.get('id')}]"


def _task_location(plan: Plan, task: Mapping[str, Any]) -> str:
    projects = snapshot.objects_by_id(plan.snapshot_files, KINDS[0][1])
    sections = snapshot.objects_by_id(plan.snapshot_files, KINDS[1][1])
    tasks = snapshot.objects_by_id(plan.snapshot_files, KINDS[2][1])
    parts = [str(projects.get(str(task.get("project_id")), {}).get("name", "?"))]
    if section := sections.get(str(task.get("section_id"))):
        parts.append(str(section.get("name")))
    if parent := tasks.get(str(task.get("parent_id"))):
        parts.append(f"subtask of {_short(parent.get('content'))}")
    return " › ".join(parts)


def _task_details(task: Mapping[str, Any]) -> list[str]:
    details = []
    if task.get("description"):
        details.append(f"description: {_short(task['description'])}")
    if isinstance(task.get("due"), dict):
        due = task["due"]
        details.append(
            f"due: {due.get('string') or due.get('date')}"
            + (" (recurring)" if due.get("is_recurring") else "")
        )
    if task.get("deadline"):
        details.append(f"deadline: {task['deadline'].get('date')}")
    if task.get("priority", 1) != 1:
        details.append(f"priority: p{5 - int(task['priority'])}")
    if task.get("labels"):
        details.append(f"labels: {', '.join(task['labels'])}")
    return details


def render(plan: Plan) -> str:
    lines = [
        f"Restore plan: snapshot {plan.ref[:12]} from {plan.snapshot_time} vs live account",
        "",
    ]
    summary = [
        f"  {d.kind}: {len(d.missing)} missing, {len(d.changed)} changed, {len(d.new)} new"
        for d in plan.diffs
        if d.missing or d.changed or d.new
    ]
    lines += ["Summary:", *(summary or ["  no differences"]), ""]

    for diff in plan.diffs:
        if diff.kind == "tasks" and diff.missing:
            completed = [t for t in diff.missing if str(t["id"]) in plan.completed_since]
            gone = [t for t in diff.missing if str(t["id"]) not in plan.completed_since]
            if gone:
                lines.append(f"Missing tasks, deleted or otherwise gone ({len(gone)}):")
                by_location: dict[str, list[dict[str, Any]]] = {}
                for task in gone:
                    by_location.setdefault(_task_location(plan, task), []).append(task)
                for location, tasks in sorted(by_location.items()):
                    lines.append(f"  {location}")
                    for task in tasks:
                        lines.append(f"    - {_name('tasks', task)}")
                        lines += [f"        {d}" for d in _task_details(task)]
                lines.append("")
            if completed:
                lines.append(
                    f"Missing because completed since the snapshot ({len(completed)}), "
                    "usually nothing to do:"
                )
                lines += [f"  - {_name('tasks', t)}" for t in completed]
                lines.append("")
        elif diff.missing:
            lines.append(f"Missing {diff.kind} ({len(diff.missing)}):")
            lines += [f"  - {_name(diff.kind, o)}" for o in diff.missing]
            lines.append("")
        if diff.changed:
            lines.append(f"Changed {diff.kind} ({len(diff.changed)}), snapshot value → live value:")
            for obj, changes in diff.changed:
                lines.append(f"  - {_name(diff.kind, obj)}")
                lines += [
                    f"      {k}: {_short(old)} → {_short(new)}" for k, (old, new) in changes.items()
                ]
            lines.append("")
        if diff.new:
            lines.append(
                f"New since the snapshot, {diff.kind} ({len(diff.new)}), no action needed:"
            )
            lines += [f"  - {_name(diff.kind, o)}" for o in diff.new]
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def to_json(plan: Plan) -> str:
    return snapshot.dumps(
        {
            "snapshot": {"commit": plan.ref, "time": plan.snapshot_time},
            "completed_since_snapshot": sorted(plan.completed_since),
            "kinds": {
                d.kind: {
                    "missing": d.missing,
                    "changed": [
                        {
                            "id": o.get("id"),
                            "snapshot": o,
                            "changes": {k: {"snapshot": a, "live": b} for k, (a, b) in c.items()},
                        }
                        for o, c in d.changed
                    ],
                    "new": d.new,
                }
                for d in plan.diffs
                if d.missing or d.changed or d.new
            },
        }
    )
