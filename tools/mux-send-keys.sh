#!/usr/bin/env bash

# Sends a command to the Helix pane that spawned the caller (tagged via
# $HELIX_PANE in tools/mux-new-window.sh), then optionally closes the
# caller's own pane. Called from the lazygit/scooter/yazi configs.
#
# `herdr pane send-text`/`pane run` wrap the text in a bracketed
# paste sequence whenever the target pane has bracketed paste enabled
# (which Helix does), so it lands as literal inserted text instead of
# running as a command. `pane send-keys` sends real per-character key
# events instead, which Helix processes the same as actual typing.
# `rex send` types text without bracketed paste, so Rex needs no
# workaround.

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

if [ -n "$REX_SESSION" ]; then
    # Rex sets REX_BIN_DIR in its terminals, but a command Rex starts gets the
    # login shell's PATH, which leaves it out.
    REX="${REX_BIN_DIR:?REX_SESSION is set without REX_BIN_DIR}/rex"
    "$REX" send -b "${HELIX_PANE:-$REX_BLOCK}" "$TEXT"$'\r' || exit 1
    if [ "$CLOSE_SELF" = true ]; then
        exec "$REX" block close "$REX_BLOCK"
    fi
    exit 0
fi

if [ -z "$HERDR_ENV" ]; then
    echo "mux-send-keys: not running inside herdr or Rex" >&2
    exit 1
fi

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
