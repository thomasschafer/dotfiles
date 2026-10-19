"""Run bookkeeping kept outside the data repo, in the state directory."""

from __future__ import annotations

import json
import os
import tempfile
from dataclasses import asdict, dataclass, field
from pathlib import Path


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

    @classmethod
    def load(cls, path: Path, now: float) -> State:
        if not path.exists():
            return cls(installed_at=now)
        raw = json.loads(path.read_text())
        if not isinstance(raw, dict):
            raise ValueError(f"{path} is not a JSON object")
        return cls(**raw)

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".state.")
        with os.fdopen(fd, "w") as f:
            json.dump(asdict(self), f, indent=2, sort_keys=True)
        os.replace(tmp, path)
