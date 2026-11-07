#!/bin/bash

# Sends a command to the Helix pane that spawned the caller (tagged via
# $HELIX_PANE in tools/mux-new-window.sh), then optionally closes the
# caller's own pane. Called from the lazygit/scooter/yazi configs.
#
# The text has to arrive as typed keys rather than a bracketed paste, which
# Helix would insert as literal text instead of running it as a command.
# `rex send` types text without bracketed paste, so Rex needs no
# workaround. In the Herdr app, `hc send` pastes and `hc keys` only knows
# key names (no `:` or capitals), so the app's own `terminal.type` types
# the text instead.

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

if [ -n "$HC_TERMINAL_ID" ]; then
    REQUEST=$(jq -nc --arg terminal "${HELIX_PANE:-$HC_TERMINAL_ID}" --arg line "$TEXT" \
        '{terminal: $terminal, line: $line}') || exit 1
    if ! REPLY=$(herdr-app "do" terminal.type "$REQUEST"); then
        echo "mux-send-keys: ${REPLY:-herdr-app do terminal.type failed}" >&2
        exit 1
    fi
    if [ "$CLOSE_SELF" = true ]; then
        exec hc kill "$HC_TERMINAL_ID" >/dev/null
    fi
    exit 0
fi

echo "mux-send-keys: not running inside the Herdr app or Rex" >&2
exit 1
