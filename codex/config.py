"""Edits Codex's config.toml, which Codex also rewrites, leaving the rest of it as it was.

Each edit goes through tomlkit, which keeps the file's formatting, and replaces the file
only if nothing has changed it since it was read. An edit that's already in place
leaves the file untouched.

  trust-hook HOOKS_JSON CONFIG_TOML EVENT COMMAND
    Marks one command hook in Codex's hooks.json as trusted. Codex skips a hook until it
    is trusted, which it records as the hook's hash under
    [hooks.state."<hooks.json path>:<event>:<group>:<handler>"]. The hook is the single
    handler for EVENT whose command is exactly COMMAND, so nothing else is trusted, and
    its hash is computed from its current definition, as it stands in HOOKS_JSON.

    The hash follows hook_hash in codex-rs/hooks/src/engine/discovery.rs and
    version_for_toml in codex-rs/config/src/fingerprint.rs (Codex 0.166): the SHA-256 of
    the normalized hook, as JSON with sorted keys and no whitespace. Fields this doesn't
    know how Codex normalizes are rejected rather than guessed at.

  set-feature CONFIG_TOML FEATURE true|false
    Sets [features] FEATURE. This doesn't know which features Codex has, so check that
    Codex reads it (`codex features list`).
"""

import hashlib
import json
import os
import shutil
import sys
import tempfile
from collections.abc import Callable

import tomlkit

# Codex's names for events in state keys and hashes. Others are rejected, as Codex
# normalizes some of their fields differently (see normalize_command_hook).
EVENT_KEYS = {"SessionStart": "session_start"}
DEFAULT_TIMEOUT_SEC = 600
GROUP_FIELDS = {"matcher", "hooks"}
HANDLER_FIELDS = {"type", "command", "timeout", "async", "statusMessage"}


def fail(message: str) -> None:
    sys.exit(f"codex-config: {message}")


def expect(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def find_hook(hooks_path: str, event: str, command: str) -> tuple[str, dict]:
    """Returns the hook's state key and its normalized identity, which Codex hashes."""
    with open(hooks_path) as f:
        hooks_file = json.load(f)
    expect(
        isinstance(hooks_file, dict) and set(hooks_file) <= {"description", "hooks"},
        f"{hooks_path} isn't in a format this knows",
    )
    events = hooks_file.get("hooks", {})
    expect(isinstance(events, dict), f"{hooks_path}: hooks isn't an object")
    groups = events.get(event, [])
    expect(isinstance(groups, list), f"{hooks_path}: hooks.{event} isn't a list")

    matches = []
    for group_index, group in enumerate(groups):
        expect(
            isinstance(group, dict) and set(group) <= GROUP_FIELDS,
            f"{hooks_path}: group {group_index} of {event} isn't in a format this knows",
        )
        handlers = group.get("hooks", [])
        expect(isinstance(handlers, list), f"{hooks_path}: group {group_index} of {event} has no hook list")
        for handler_index, handler in enumerate(handlers):
            if isinstance(handler, dict) and handler.get("command") == command:
                matches.append((group_index, group, handler_index, handler))

    expect(len(matches) > 0, f"{hooks_path} has no {event} hook running {command!r}")
    expect(len(matches) == 1, f"{hooks_path} has {len(matches)} {event} hooks running {command!r}")
    group_index, group, handler_index, handler = matches[0]
    where = f"{hooks_path}: the {event} hook running {command!r}"
    unknown = set(handler) - HANDLER_FIELDS
    expect(not unknown, f"{where} has fields this doesn't know how Codex hashes: {sorted(unknown)}")
    expect(handler.get("type") == "command", f"{where} isn't of type command")

    timeout = handler.get("timeout")
    if timeout is None:
        timeout = DEFAULT_TIMEOUT_SEC
    expect(type(timeout) is int, f"{where} has a timeout that isn't an integer")
    is_async = handler.get("async", False)
    expect(type(is_async) is bool, f"{where} has an async that isn't a boolean")
    status_message = handler.get("statusMessage")
    expect(status_message is None or isinstance(status_message, str), f"{where} has a statusMessage that isn't a string")
    matcher = group.get("matcher")
    expect(matcher is None or isinstance(matcher, str), f"{where} has a matcher that isn't a string")

    normalized_handler = {
        "type": "command",
        "command": command,
        "timeout": max(timeout, 1),
        "async": is_async,
    }
    if status_message is not None:
        normalized_handler["statusMessage"] = status_message
    identity = {"event_name": EVENT_KEYS[event], "hooks": [normalized_handler]}
    if matcher is not None:
        identity["matcher"] = matcher

    key = f"{hooks_path}:{EVENT_KEYS[event]}:{group_index}:{handler_index}"
    return key, identity


def hook_hash(identity: dict) -> str:
    serialized = json.dumps(identity, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return "sha256:" + hashlib.sha256(serialized.encode()).hexdigest()


def table(parent, name: str, path: str):
    if name not in parent:
        parent[name] = tomlkit.table()
    child = parent[name]
    expect(isinstance(child, dict), f"{path} isn't a table")
    return child


def write_atomically(path: str, original: str | None, content: str) -> None:
    """Replaces path with content, unless something else has changed it since it was read."""
    directory = os.path.dirname(path)
    fd, temp_path = tempfile.mkstemp(dir=directory, prefix=".config.toml.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(content)
        try:
            with open(path) as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        expect(current == original, f"{path} changed while this was editing it; run it again")
        if original is not None:
            shutil.copymode(path, temp_path)
        os.replace(temp_path, path)
    except BaseException:
        os.unlink(temp_path)
        raise


def edit_config(config_path: str, edit: Callable[[tomlkit.TOMLDocument], str | None]) -> None:
    """Applies edit to the parsed config. edit returns what it changed, or None when the
    config is already as wanted."""
    config_path = os.path.realpath(config_path)
    try:
        with open(config_path) as f:
            original = f.read()
    except FileNotFoundError:
        original = None
    config = tomlkit.parse(original or "")
    expect(
        tomlkit.dumps(config) == (original or ""),
        f"{config_path} doesn't round-trip through tomlkit, so editing it could change other settings",
    )
    change = edit(config)
    if change is None:
        return
    write_atomically(config_path, original, tomlkit.dumps(config))
    print(change)


def trust_hook(hooks_path: str, config_path: str, event: str, command: str) -> None:
    expect(event in EVENT_KEYS, f"events other than {sorted(EVENT_KEYS)} aren't supported")
    expect(os.path.isabs(hooks_path), "HOOKS_JSON must be an absolute path, as Codex keys hooks by it")
    key, identity = find_hook(hooks_path, event, command)
    trusted_hash = hook_hash(identity)

    def edit(config):
        state = table(table(table(config, "hooks", "hooks"), "state", "hooks.state"), key, f"hooks.state.{key!r}")
        previous = state.get("trusted_hash")
        if previous == trusted_hash:
            return None
        state["trusted_hash"] = trusted_hash
        action = "Trusted" if previous is None else f"Re-trusted (was {previous})"
        return f"{action} Codex's {event} hook {command!r}"

    edit_config(config_path, edit)


def set_feature(config_path: str, feature: str, value: str) -> None:
    expect(value in ("true", "false"), f"a feature is set to true or false, not {value!r}")
    enabled = value == "true"

    def edit(config):
        features = table(config, "features", "features")
        previous = features.get(feature)
        expect(
            previous is None or type(previous) is bool,
            f"features.{feature} is {previous!r}, not a boolean, so this won't replace it",
        )
        if previous is enabled:
            return None
        features[feature] = enabled
        was = "" if previous is None else f" (was {str(previous).lower()})"
        return f"Set Codex's features.{feature} to {value}{was}"

    edit_config(config_path, edit)


COMMANDS = {
    "trust-hook": (trust_hook, "HOOKS_JSON CONFIG_TOML EVENT COMMAND"),
    "set-feature": (set_feature, "CONFIG_TOML FEATURE true|false"),
}


def main() -> None:
    usage = "; ".join(f"{sys.argv[0]} {name} {args}" for name, (_, args) in COMMANDS.items())
    expect(len(sys.argv) >= 2 and sys.argv[1] in COMMANDS, f"usage: {usage}")
    run, args = COMMANDS[sys.argv[1]]
    expect(len(sys.argv) - 2 == len(args.split()), f"usage: {sys.argv[0]} {sys.argv[1]} {args}")
    run(*sys.argv[2:])


if __name__ == "__main__":
    main()
