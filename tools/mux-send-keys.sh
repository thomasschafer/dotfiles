#!/usr/bin/env bash

# Sends a command to the Helix pane that spawned the caller (tagged via
# $HELIX_PANE in tools/mux-new-window.sh), then optionally closes the
# caller's own pane. Mirrors tmux's `send-keys <target> <text> Enter` so
# callers (see lazygit/scooter/yazi configs) don't need to know which
# multiplexer is running.
#
# Under herdr, `pane send-text`/`pane run` wrap the text in a bracketed
# paste sequence whenever the target pane has bracketed paste enabled
# (which Helix does), so it lands as literal inserted text instead of
# running as a command. `pane send-keys` sends real per-character key
# events instead, which Helix processes the same as actual typing.

USAGE="Usage: $(basename "$0") [--close-self] <text>"

CLOSE_SELF=false
if [ "$1" = "--close-self" ]; then
    CLOSE_SELF=true
    shift
fi

if [ "$#" -ne 1 ]; then
    echo "$USAGE" >&2
    exit 1
fi

TEXT="$1"

if [ -n "$TMUX" ]; then
    TARGET="${HELIX_PANE:-$TMUX_PANE}"
    tmux send-keys -t "$TARGET" "$TEXT" Enter
    if [ "$CLOSE_SELF" = true ]; then
        tmux kill-pane -t "$TMUX_PANE"
    fi
elif [ -n "$HERDR_ENV" ]; then
    TARGET="${HELIX_PANE:-$HERDR_PANE_ID}"
    CHARS=()
    for (( i = 0; i < ${#TEXT}; i++ )); do
        CH="${TEXT:i:1}"
        # herdr trims each key token before parsing, so a literal " " key
        # collapses to empty and fails; use the named alias instead.
        if [ "$CH" = " " ]; then
            CH="space"
        fi
        CHARS+=("$CH")
    done
    if [ "$CLOSE_SELF" = true ]; then
        # Run concurrently: these target different panes (the Helix pane vs
        # our own) with no ordering dependency, and each `herdr` invocation
        # has a fixed process-spawn/socket cost, so sequencing them doubles
        # the latency for no reason.
        herdr pane send-keys "$TARGET" "${CHARS[@]}" enter &
        herdr pane close "$HERDR_PANE_ID" &
        wait
    else
        herdr pane send-keys "$TARGET" "${CHARS[@]}" enter
    fi
else
    echo "mux-send-keys: not running inside tmux or herdr" >&2
    exit 1
fi
