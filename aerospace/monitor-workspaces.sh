#!/usr/bin/env bash

# AeroSpace runs this on focus changes. Whenever the set of connected monitors changes, music and
# Zoom workspaces are put on the laptop's display and every other workspace on an external monitor.
# Nothing happens between monitor changes, so workspaces can still be moved manually, which
# workspace-to-monitor-force-assignment would block.

set -euo pipefail

readonly SCRIPT_NAME='monitor workspaces'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
trap 'notify_error "Failed at line $LINENO"' ERR

readonly LAPTOP_WORKSPACES=(B D M Z)
# AeroSpace monitor patterns are case-insensitive regexes matched against monitor names
readonly BUILT_IN_PATTERN='built-in'
readonly EXTERNAL_PATTERN='^(?!built-in)'

require_single_aerospace

# Keyed by AeroSpace PID so workspaces are arranged again after a restart
readonly STATE_FILE="${TMPDIR:-/tmp}/aerospace-monitors-$AEROSPACE_PID"
readonly LOCK_DIR="${TMPDIR:-/tmp}/aerospace-monitors.lock"

is_laptop_workspace() {
    local workspace
    for workspace in "${LAPTOP_WORKSPACES[@]}"; do
        [[ $workspace == "$1" ]] && return 0
    done
    return 1
}

arrange_workspaces() {
    local workspace target
    # Read from fd 3 because the aerospace CLI reads stdin, which would swallow the list
    while read -r -u 3 workspace; do
        if is_laptop_workspace "$workspace"; then
            target=$BUILT_IN_PATTERN
        else
            target=$EXTERNAL_PATTERN
        fi
        aerospace move-workspace-to-monitor --workspace "$workspace" "$target"
    done 3< <(aerospace list-workspaces --all)
}

# Another run is in progress and will handle any monitor change
acquire_lock "$LOCK_DIR" || exit 0
trap 'rmdir "$LOCK_DIR"' EXIT

monitors=$(aerospace list-monitors --format '%{monitor-name}' | sort)
if [[ -f $STATE_FILE && $(<"$STATE_FILE") == "$monitors" ]]; then
    exit 0
fi

# With only the laptop's display, or only external monitors (lid closed), there's nothing to split
if grep -qi "$BUILT_IN_PATTERN" <<<"$monitors" && grep -qvi "$BUILT_IN_PATTERN" <<<"$monitors"; then
    arrange_workspaces
fi
echo "$monitors" >"$STATE_FILE"
