#!/usr/bin/env bash

# AeroSpace runs this on focus changes. Whenever the set of connected monitors changes, music and
# Zoom workspaces are put on the laptop's display, Q, W and E on the leftmost external monitor, and
# every other workspace on the rightmost external monitor (the same one when there's only one).
# Nothing happens between monitor changes, so workspaces can still be moved manually, which
# workspace-to-monitor-force-assignment would block.
#
# Run with toggle-laptop-only (bound to a key) to move every workspace to the laptop's display, and
# again to go back to the split above.

set -Eeuo pipefail

readonly SCRIPT_NAME='monitor workspaces'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly LAPTOP_WORKSPACES=(B D M Z)
readonly LEFT_WORKSPACES=(Q W E)
# AeroSpace monitor names, matched case-insensitively
readonly BUILT_IN_PATTERN='built-in'

require_single_aerospace

# Keyed by AeroSpace PID so workspaces are arranged again after a restart
STATE_FILE=$(state_path "monitors-$AEROSPACE_PID")
# Exists while toggle-laptop-only has moved every workspace to the laptop's display
LAPTOP_ONLY_FILE=$(state_path "laptop-only-$AEROSPACE_PID")
readonly STATE_FILE LAPTOP_ONLY_FILE

contains() {
    local item=$1 element
    shift
    for element in "$@"; do
        [[ $element == "$item" ]] && return 0
    done
    return 1
}

# Sets BUILT_IN_MONITOR, LEFT_MONITOR and RIGHT_MONITOR to monitor sequence numbers (counted from the
# left), or to empty strings for monitors that aren't connected. Unlike names, sequence numbers tell
# identical monitors apart.
find_monitors() {
    local monitors id name
    BUILT_IN_MONITOR='' LEFT_MONITOR='' RIGHT_MONITOR=''
    monitors=$(aerospace list-monitors --format '%{monitor-id}%{tab}%{monitor-name}')
    while IFS=$'\t' read -r id name; do
        if ! [[ $id =~ ^[0-9]+$ ]]; then
            notify_error "Unexpected monitor ID: $id"
            exit 1
        fi
        if grep -qi "$BUILT_IN_PATTERN" <<<"$name"; then
            if [[ -n $BUILT_IN_MONITOR ]]; then
                notify_error 'Found more than one built-in display'
                exit 1
            fi
            BUILT_IN_MONITOR=$id
        else
            if [[ -z $LEFT_MONITOR ]] || ((id < LEFT_MONITOR)); then
                LEFT_MONITOR=$id
            fi
            if [[ -z $RIGHT_MONITOR ]] || ((id > RIGHT_MONITOR)); then
                RIGHT_MONITOR=$id
            fi
        fi
    done <<<"$monitors"
}

# With only the laptop's display, or only external monitors (lid closed), there's nothing to split
has_split() {
    [[ -n $BUILT_IN_MONITOR && -n $LEFT_MONITOR ]]
}

split_target() {
    if contains "$1" "${LAPTOP_WORKSPACES[@]}"; then
        echo "$BUILT_IN_MONITOR"
    elif contains "$1" "${LEFT_WORKSPACES[@]}"; then
        echo "$LEFT_MONITOR"
    else
        echo "$RIGHT_MONITOR"
    fi
}

laptop_target() {
    echo "$BUILT_IN_MONITOR"
}

# Moves each workspace to the monitor printed by <target-function> <workspace>, keeping the focused
# workspace focused
move_workspaces() {
    local target_function=$1 focused workspaces workspace monitor target
    focused=$(aerospace list-workspaces --focused)
    workspaces=$(aerospace list-workspaces --all --format '%{workspace}%{tab}%{monitor-id}')
    # Read from fd 3 because the aerospace CLI reads stdin, which would swallow the list
    while IFS=$'\t' read -r -u 3 workspace monitor; do
        target=$("$target_function" "$workspace")
        if [[ $monitor != "$target" ]]; then
            aerospace move-workspace-to-monitor --workspace "$workspace" "$target"
        fi
    done 3<<<"$workspaces"
    aerospace workspace "$focused"
}

update_workspaces() {
    local monitors
    monitors=$(aerospace list-monitors --format '%{monitor-name}' | sort)
    if [[ -f $STATE_FILE && $(<"$STATE_FILE") == "$monitors" ]]; then
        return 0
    fi

    rm -f "$LAPTOP_ONLY_FILE"
    find_monitors
    if has_split; then
        move_workspaces split_target
    fi
    echo "$monitors" >"$STATE_FILE"
}

toggle_laptop_only() {
    # Picks up a monitor change first, so the next focus change doesn't undo the toggle
    update_workspaces
    find_monitors
    if ! has_split; then
        notify_error 'Needs both the laptop display and an external monitor'
        exit 1
    fi

    if [[ -f $LAPTOP_ONLY_FILE ]]; then
        move_workspaces split_target
        rm "$LAPTOP_ONLY_FILE"
    else
        move_workspaces laptop_target
        touch "$LAPTOP_ONLY_FILE"
    fi
}

case ${1:-} in
    '') run_exclusively monitors update_workspaces ;;
    toggle-laptop-only) run_when_unlocked monitors toggle_laptop_only ;;
    *)
        notify_error "Unknown argument: $1"
        exit 1
        ;;
esac
