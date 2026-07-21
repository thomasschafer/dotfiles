#!/usr/bin/env bash

# Opens a new tmux window or herdr tab, tagging it with $HELIX_PANE so tools
# spawned from it (lazygit, yazi, etc.) can send commands back to the Helix
# pane that launched them. Mirrors tmux's `new-window -e KEY=VAL... <command>`
# argument shape so callers (see helix/config.template.toml) don't need to
# know which multiplexer is running.

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

if [ -n "$TMUX" ]; then
    TMUX_ENV_FLAGS=()
    for kv in "${ENV_ARGS[@]}"; do
        TMUX_ENV_FLAGS+=(-e "$kv")
    done
    exec tmux new-window -e "HELIX_PANE=$TMUX_PANE" "${TMUX_ENV_FLAGS[@]}" "$@"
elif [ -n "$HERDR_ENV" ]; then
    HERDR_ENV_FLAGS=(--env "HELIX_PANE=$HERDR_PANE_ID")
    for kv in "${ENV_ARGS[@]}"; do
        HERDR_ENV_FLAGS+=(--env "$kv")
    done
    # trailing argv after `--` runs directly as the tab's root process (no
    # interactive shell startup), so herdr closes the tab when it exits, same
    # as tmux does for a plain `new-window <command>`. /bin/sh -c re-parses
    # "$*" the same way the custom command keybindings do internally.
    # redirect stdout: `tab create` prints a JSON response on success, and
    # since this runs via helix's `:sh`, any stdout would land in a scratch
    # buffer for you to look at instead of silently succeeding
    exec herdr tab create "${HERDR_ENV_FLAGS[@]}" --focus -- /bin/sh -c "$*" >/dev/null
else
    echo "mux-new-window: not running inside tmux or herdr" >&2
    exit 1
fi
