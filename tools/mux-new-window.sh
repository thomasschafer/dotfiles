#!/usr/bin/env bash

# Opens a new herdr or Rex tab, tagging it with $HELIX_PANE so tools spawned
# from it (lazygit, yazi, etc.) can send commands back to the Helix pane that
# launched them. Called from the Helix keybindings in helix/config.template.toml.

USAGE="Usage: $(basename "$0") [-e KEY=VALUE]... <command>"

ENV_ARGS=()
while [ "$1" = "-e" ]; do
    ENV_ARGS+=("$2")
    shift 2
done

if [ "$#" -eq 0 ]; then
    echo "$USAGE"
    exit 1
fi

if [ -n "$REX_SESSION" ]; then
    # Rex sets REX_BIN_DIR in its terminals, but a command Rex starts gets the
    # login shell's PATH, which leaves it out.
    REX="${REX_BIN_DIR:?REX_SESSION is set without REX_BIN_DIR}/rex"
    # rex run has no flag for the environment, so env sets it. Rex closes the
    # tab when the command exits. Its stdout is dropped for the same reason as
    # herdr's below.
    exec "$REX" run -- env "HELIX_PANE=$REX_BLOCK" "${ENV_ARGS[@]}" /bin/sh -c "$*" >/dev/null
fi

if [ -z "$HERDR_ENV" ]; then
    echo "mux-new-window: not running inside herdr or Rex" >&2
    exit 1
fi

HERDR_ENV_FLAGS=(--env "HELIX_PANE=$HERDR_PANE_ID")
for kv in "${ENV_ARGS[@]}"; do
    HERDR_ENV_FLAGS+=(--env "$kv")
done
# trailing argv after `--` runs directly as the tab's root process (no
# interactive shell startup), so herdr closes the tab when it exits.
# /bin/sh -c re-parses "$*" the same way the custom command keybindings do
# internally.
# redirect stdout: `tab create` prints a JSON response on success, and
# since this runs via helix's `:sh`, any stdout would land in a scratch
# buffer for you to look at instead of silently succeeding
exec herdr tab create "${HERDR_ENV_FLAGS[@]}" --focus -- /bin/sh -c "$*" >/dev/null
