"""Run bookkeeping kept outside the data repo, in the state directory."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass, field, fields
from pathlib import Path


class StateCorrupt(Exception):
    pass


@dataclass
class State:
    installed_at: float
    last_success: float | None = None
    last_attempt: float | None = None
    last_result: str | None = None
    # The last commit known to be on GitHub; if the local clone stops containing it, the
    # local history was rewritten.
    last_pushed: str | None = None
    # Alert kind -> when it was last shown, to rate-limit repeats.
    alerted_at: dict[str, float] = field(default_factory=dict)
    # Ids already reported as deleted -> when, so a deletion is reported once rather than
    # by every later run comparing against an older snapshot.
    alerted_missing: dict[str, float] = field(default_factory=dict)

    @classmethod
    def load(cls, path: Path, now: float) -> State:
        """Raises StateCorrupt if the file exists but can't be read as a State."""
        if not path.exists():
            return cls(installed_at=now)
        try:
            raw = json.loads(path.read_text())
        except (ValueError, OSError) as e:
            raise StateCorrupt(f"{path} is unreadable: {e}") from e
        known = {f.name for f in fields(cls)}
        if not isinstance(raw, dict) or not raw.keys() <= known or "installed_at" not in raw:
            raise StateCorrupt(f"{path} doesn't have the expected fields")
        try:
            return cls(**raw)
        except TypeError as e:
            raise StateCorrupt(f"{path} is invalid: {e}") from e

    @classmethod
    def load_or_reset(cls, path: Path, now: float) -> tuple[State, str | None]:
        """Loads the state, or moves a corrupt file aside and starts afresh. Returns the
        problem found, if any, so the caller can alert."""
        try:
            return cls.load(path, now), None
        except StateCorrupt as e:
            aside = path.with_name(f"{path.name}.corrupt-{int(now)}")
            path.rename(aside)
            return cls(installed_at=now), f"{e}; moved it to {aside.name} and started afresh"

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".state.")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(asdict(self), f, indent=2, sort_keys=True)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp, path)
        except BaseException:
            Path(tmp).unlink(missing_ok=True)
            raise
