#!/bin/bash

# Opens a new herdr, Herdr app or Rex tab, tagging it with $HELIX_PANE so
# tools spawned from it (lazygit, yazi, etc.) can send commands back to the
# Helix pane that launched them. Called from the Helix keybindings in
# helix/config.template.toml.

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

# What the new tab runs, followed by any KEY=VALUE arguments: one bash that
# exports them, then runs the command as a shell would. One program rather
# than env and then a shell, as every program start costs time (and macOS's
# /bin/sh is itself a launcher that starts another shell).
# shellcheck disable=SC2016 # expanded by the tab's bash, not here
RUN=(/bin/bash -c '(($# > 1)) && export "${@:2}"; eval "$1"' mux-new-window "$*")

if [ -n "$REX_SESSION" ]; then
    # Rex sets REX_BIN_DIR in its terminals, but a command Rex starts gets the
    # login shell's PATH, which leaves it out.
    REX="${REX_BIN_DIR:?REX_SESSION is set without REX_BIN_DIR}/rex"
    # rex run has no flag for the environment, so RUN exports it. Rex closes
    # the tab when the command exits. Its stdout is dropped for the same
    # reason as herdr's below.
    exec "$REX" run -- "${RUN[@]}" "HELIX_PANE=$REX_BLOCK" "${ENV_ARGS[@]}" >/dev/null
fi

if [ -z "$HERDR_ENV" ]; then
    if [ -n "$HC_TERMINAL_ID" ]; then
        # The Herdr app's terminals run in herdr-core, which gives each one its
        # address as $HC_TERMINAL_ID. stay: false runs the argv as given, with
        # no login shell, and closes the tab when it exits. The core's
        # environment comes from wherever it was started (maybe the Dock), so
        # the tab gets this PATH rather than the core's.
        #
        # NUL-separated, as jq would read a `-c` given with --args as its own flag.
        REQUEST=$(printf '%s\0' "${RUN[@]}" "PATH=$PATH" "HELIX_PANE=$HC_TERMINAL_ID" "${ENV_ARGS[@]}" |
            jq -Rsc --arg folder "$PWD" '{folder: $folder, argv: split("\u0000")[:-1], stay: false}') || exit 1
        # `do` prints the new IDs on success, which would land in a Helix
        # scratch buffer (see the herdr case below), and an error on failure.
        if ! REPLY=$(herdr-app "do" tab.new "$REQUEST"); then
            echo "mux-new-window: ${REPLY:-herdr-app do tab.new failed}" >&2
            exit 1
        fi
        exit 0
    fi
    echo "mux-new-window: not running inside herdr, the Herdr app or Rex" >&2
    exit 1
fi

HERDR_ENV_FLAGS=(--env "HELIX_PANE=$HERDR_PANE_ID")
for kv in "${ENV_ARGS[@]}"; do
    HERDR_ENV_FLAGS+=(--env "$kv")
done
# trailing argv after `--` runs directly as the tab's root process (no
# interactive shell startup), so herdr closes the tab when it exits.
# RUN re-parses "$*" the same way the custom command keybindings do
# internally.
# redirect stdout: `tab create` prints a JSON response on success, and
# since this runs via helix's `:sh`, any stdout would land in a scratch
# buffer for you to look at instead of silently succeeding
exec herdr tab create "${HERDR_ENV_FLAGS[@]}" --focus -- "${RUN[@]}" >/dev/null
