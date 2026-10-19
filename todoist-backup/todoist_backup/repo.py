"""Git operations on the data repo.

Git runs without your global or system config and pushes over SSH only with the deploy
key, pinned GitHub host keys and no agent. It never force-pushes, so the local clone and
GitHub each hold the full history, and a rewrite of either is detected rather than copied.
"""

from __future__ import annotations

import json
import os
import subprocess
from collections.abc import Iterable, Sequence
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

from . import snapshot
from .config import BRANCH, Config

AUTHOR_NAME = "todoist-backup"
AUTHOR_EMAIL = "todoist-backup@localhost"
OFFLINE_MARKERS = (
    "could not resolve hostname",
    "network is unreachable",
    "operation timed out",
    "connection timed out",
    "no route to host",
    "connection refused",
)
DATA_README = """\
# Todoist backup

Written automatically by the todoist-backup launchd job in my dotfiles. Don't edit by hand:
the job never force-pushes, and alerts if this history and its local clone diverge.

- `sync/`: everything a full sync returns, one file per resource type.
- `archived/`: archived projects, with their sections, tasks and comments.
- `completed/`: completed tasks by completion month (UTC), kept even if later deleted.

See todoist-backup/README.md in the dotfiles for how to read a restore plan.
"""


class GitError(Exception):
    pass


class GitOffline(GitError):
    pass


class RemoteState(Enum):
    IN_SYNC = "in sync"  # remote history is contained in the local history
    EMPTY = "empty"  # no branch on the remote yet
    AHEAD = "ahead"  # remote has commits the local clone doesn't
    DIVERGED = "diverged"  # histories differ: one was rewritten


@dataclass
class Repo:
    config: Config

    @property
    def path(self) -> Path:
        return self.config.data_dir

    def _env(self) -> dict[str, str]:
        ssh = [
            "ssh",
            "-i",
            str(self.config.deploy_key),
            "-o",
            "IdentitiesOnly=yes",
            "-o",
            "IdentityAgent=none",
            "-o",
            "BatchMode=yes",
            "-o",
            "StrictHostKeyChecking=yes",
            "-o",
            f"UserKnownHostsFile={self.config.known_hosts}",
            "-o",
            "ConnectTimeout=20",
            "-F",
            "/dev/null",
        ]
        return {
            "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
            "HOME": os.environ.get("HOME", str(Path.home())),
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_SSH_COMMAND": " ".join(ssh),
            "GIT_AUTHOR_NAME": AUTHOR_NAME,
            "GIT_AUTHOR_EMAIL": AUTHOR_EMAIL,
            "GIT_COMMITTER_NAME": AUTHOR_NAME,
            "GIT_COMMITTER_EMAIL": AUTHOR_EMAIL,
            "LC_ALL": "C",
        }

    def git(
        self, *args: str, cwd: Path | None = None, check: bool = True
    ) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            ["git", *args],
            cwd=cwd or self.path,
            env=self._env(),
            capture_output=True,
            text=True,
            check=False,
        )
        if check and result.returncode != 0:
            message = f"git {args[0]} failed ({result.returncode}): {result.stderr.strip()[:1000]}"
            if any(m in result.stderr.lower() for m in OFFLINE_MARKERS):
                raise GitOffline(message)
            raise GitError(message)
        return result

    def exists(self) -> bool:
        return (self.path / ".git").is_dir()

    def clone(self) -> None:
        if self.path.exists() and any(self.path.iterdir()):
            raise GitError(f"{self.path} exists and isn't a git repo; refusing to clone over it")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.git("clone", "--quiet", self.config.remote_url, str(self.path), cwd=self.path.parent)
        self.git("symbolic-ref", "HEAD", f"refs/heads/{BRANCH}")
        self.configure()

    def configure(self) -> None:
        self.git("config", "commit.gpgsign", "false")
        self.git("config", "core.hooksPath", "/dev/null")
        current = self.git("symbolic-ref", "--short", "HEAD").stdout.strip()
        if current != BRANCH:
            raise GitError(f"data repo is on branch {current!r}, expected {BRANCH!r}")
        readme = self.path / "README.md"
        if not readme.exists():
            readme.write_text(DATA_README)

    def head(self) -> str | None:
        result = self.git("rev-parse", "--verify", "--quiet", "HEAD", check=False)
        return result.stdout.strip() or None

    def fetch_remote(self) -> RemoteState:
        self.git("fetch", "--quiet", "--prune", "origin")
        remote = self.git(
            "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{BRANCH}", check=False
        ).stdout.strip()
        if not remote:
            return RemoteState.EMPTY
        local = self.head()
        if local is None:
            return RemoteState.AHEAD
        if self._is_ancestor(remote, local):
            return RemoteState.IN_SYNC
        if self._is_ancestor(local, remote):
            return RemoteState.AHEAD
        return RemoteState.DIVERGED

    def contains(self, commit: str) -> bool:
        local = self.head()
        return local is not None and self._is_ancestor(commit, local)

    def _is_ancestor(self, ancestor: str, descendant: str) -> bool:
        result = self.git("merge-base", "--is-ancestor", ancestor, descendant, check=False)
        if result.returncode not in (0, 1):
            raise GitError(f"git merge-base failed: {result.stderr.strip()}")
        return result.returncode == 0

    def fast_forward(self) -> None:
        self.git("merge", "--ff-only", "--quiet", f"origin/{BRANCH}")

    def commit_if_changed(self, message: str, secrets: Iterable[str]) -> str | None:
        """Commits all changes and returns the new commit, or None if nothing changed."""
        self.git("add", "--all")
        if self.git("diff", "--cached", "--quiet", check=False).returncode == 0:
            return None
        self._check_no_secrets(secrets)
        self.git("commit", "--quiet", "--no-verify", "-m", message)
        return self.head()

    def _check_no_secrets(self, secrets: Iterable[str]) -> None:
        """Refuses to commit if a credential or private key appears in a staged file."""
        needles = [s for s in secrets if s and len(s) >= 8] + ["PRIVATE KEY-----"]
        staged = self.git("diff", "--cached", "--name-only", "-z", "--diff-filter=d").stdout
        for name in filter(None, staged.split("\0")):
            content = (self.path / name).read_text(errors="replace")
            if any(n in content for n in needles):
                self.git("reset", "--quiet")
                raise GitError(f"refusing to commit: {name} contains a secret")

    def unpushed(self) -> bool:
        remote = self.git(
            "rev-parse", "--verify", "--quiet", f"refs/remotes/origin/{BRANCH}", check=False
        ).stdout.strip()
        local = self.head()
        return local is not None and remote != local

    def push(self) -> None:
        self.git("push", "--quiet", "origin", f"HEAD:refs/heads/{BRANCH}")

    def read_files_at(self, ref: str, prefixes: Sequence[str]) -> snapshot.Files:
        """Reads the managed JSON files at a commit, without touching the working tree."""
        names = self.git("ls-tree", "-r", "--name-only", "-z", ref).stdout.split("\0")
        files: snapshot.Files = {}
        for name in names:
            if name.endswith(".json") and name.startswith(tuple(prefixes)):
                files[name] = json.loads(self.git("show", f"{ref}:{name}").stdout)
        return files

    def resolve(self, ref: str) -> str:
        return self.git("rev-parse", "--verify", f"{ref}^{{commit}}").stdout.strip()

    def commit_before(self, moment: str) -> str:
        result = self.git("rev-list", "-1", f"--before={moment}", "HEAD").stdout.strip()
        if not result:
            raise GitError(f"no snapshot before {moment}")
        return result

    def commit_time(self, ref: str) -> str:
        return self.git("show", "-s", "--format=%cI", ref).stdout.strip()

    def last_commit_summary(self) -> str:
        return self.git("log", "-1", "--format=%h %cI %s", check=False).stdout.strip() or "none"
