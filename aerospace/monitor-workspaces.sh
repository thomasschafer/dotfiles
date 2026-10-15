#!/usr/bin/env bash

# AeroSpace runs this on focus changes. Whenever the set of connected monitors changes, music and
# Zoom workspaces are put on the laptop's display, Q, W and E on the leftmost external monitor, and
# every other workspace on the rightmost external monitor (the same one when there's only one).
# Nothing happens between monitor changes, so workspaces can still be moved manually, which
# workspace-to-monitor-force-assignment would block.
#
# Workspaces holding Citrix windows are only moved once the monitors stop changing (external
# monitors can connect a few seconds apart), and their windows are then resized (see
# citrix-windows.sh). Moving them earlier gains nothing, as they keep their old size until then
# anyway, and each move is slow and jittery. Nothing is moved until then either when external
# monitors go but some remain, as displays waking from sleep reconnect one at a time.
#
# Each move shows the moved workspace on its monitor, so afterwards the workspaces that were showing
# before the change are shown again, keeping the focused one focused.
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
# How long the set of monitors must stay the same before it counts as settled. Needs to cover the
# gap between external monitors connecting, about 3 seconds for a dock with two.
readonly SETTLE_SECONDS=5
CITRIX_SCRIPT="$(dirname "${BASH_SOURCE[0]}")/citrix-windows.sh"
readonly CITRIX_SCRIPT

require_single_aerospace

# Keyed by AeroSpace PID so workspaces are arranged again after a restart
STATE_FILE=$(state_path "monitors-$AEROSPACE_PID")
# Exists while toggle-laptop-only has moved every workspace to the laptop's display
LAPTOP_ONLY_FILE=$(state_path "laptop-only-$AEROSPACE_PID")
# The workspaces showing when the monitors were last settled
VISIBLE_FILE=$(state_path "visible-workspaces-$AEROSPACE_PID")
readonly STATE_FILE LAPTOP_ONLY_FILE VISIBLE_FILE

MONITORS_CHANGED=false

contains() {
    local item=$1 element
    shift
    for element in "$@"; do
        [[ $element == "$item" ]] && return 0
    done
    return 1
}

list_monitors() {
    aerospace list-monitors --format '%{monitor-id}%{tab}%{monitor-name}'
}

# Sets BUILT_IN_MONITOR, LEFT_MONITOR and RIGHT_MONITOR to monitor sequence numbers (counted from the
# left), or to empty strings for monitors that aren't connected. Unlike names, sequence numbers tell
# identical monitors apart. Also sets MONITORS to the output of list_monitors, and MONITOR_NAMES to
# the sorted monitor names, which identify the set of connected monitors.
find_monitors() {
    local id name
    BUILT_IN_MONITOR='' LEFT_MONITOR='' RIGHT_MONITOR=''
    MONITORS=$(list_monitors)
    MONITOR_NAMES=$(cut -f2 <<<"$MONITORS" | sort)
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
    done <<<"$MONITORS"
}

# With only the laptop's display, or only external monitors (lid closed), there's nothing to split
has_split() {
    [[ -n $BUILT_IN_MONITOR && -n $LEFT_MONITOR ]]
}

count_external_monitors() {
    grep -cvi "$BUILT_IN_PATTERN" <<<"$1" || true
}

# Sets CITRIX_WORKSPACES to the workspaces Citrix windows are routed to, and any others holding
# Citrix windows, one per line. Citrix rebuilds its windows when the monitors change, so routed
# workspaces can be briefly empty.
find_citrix_workspaces() {
    CITRIX_WORKSPACES=$({
        printf '%s\n' "$CITRIX_MAIN_WORKSPACE" "$CITRIX_IB_WORKSPACE" "$CITRIX_LAUNCHPAD_WORKSPACE"
        aerospace list-windows --monitor all --app-bundle-id "$CITRIX_APP_ID" --format '%{workspace}'
    } | sort -u)
}

is_citrix_workspace() {
    grep -Fxq "$1" <<<"$CITRIX_WORKSPACES"
}

# Target functions print the monitor a workspace should be on, or nothing to leave it where it is

split_target() {
    if contains "$1" "${LAPTOP_WORKSPACES[@]}"; then
        echo "$BUILT_IN_MONITOR"
    elif contains "$1" "${LEFT_WORKSPACES[@]}"; then
        echo "$LEFT_MONITOR"
    else
        echo "$RIGHT_MONITOR"
    fi
}

non_citrix_split_target() {
    is_citrix_workspace "$1" || split_target "$1"
}

laptop_target() {
    echo "$BUILT_IN_MONITOR"
}

# Records the visible workspaces, unless the monitors haven't settled, the toggle has moved every
# workspace to the laptop's display, or Citrix windows are being resized (which switches workspaces)
record_visible_workspaces() {
    deadline_passed monitors-settle || return 0
    [[ ! -f $LAPTOP_ONLY_FILE && ! -d $(state_path citrix-refresh.lock) ]] || return 0
    aerospace list-workspaces --monitor all --visible >"$VISIBLE_FILE.$$"
    mv -f "$VISIBLE_FILE.$$" "$VISIBLE_FILE"
}

# Shows the recorded visible workspaces again, then focuses the given workspace
restore_visible_workspaces() {
    local focused=$1 workspace
    if [[ -f $VISIBLE_FILE ]]; then
        # Read from fd 3 because the aerospace CLI reads stdin, which would swallow the list
        while read -r -u 3 workspace; do
            aerospace workspace "$workspace"
        done 3<"$VISIBLE_FILE"
    fi
    aerospace workspace "$focused"
    trace "Showed $(tr '\n' ' ' <"$VISIBLE_FILE" 2>/dev/null)again and focused $focused"
}

# Moves each workspace to the monitor printed by <target-function> <workspace>, then restores the
# visible workspaces and focus. Monitors can disconnect one at a time partway through, in which case
# this stops and sets MOVE_INTERRUPTED to true, so the caller can start again with the monitors now
# connected.
move_workspaces() {
    local target_function=$1 focused workspaces workspace monitor target moved=false
    MOVE_INTERRUPTED=false
    focused=$(aerospace list-workspaces --focused)
    workspaces=$(aerospace list-workspaces --all --format '%{workspace}%{tab}%{monitor-id}')
    # Read from fd 3 because the aerospace CLI reads stdin, which would swallow the list
    while IFS=$'\t' read -r -u 3 workspace monitor; do
        target=$("$target_function" "$workspace")
        [[ -n $target && $target != "$monitor" ]] || continue
        if ! aerospace move-workspace-to-monitor --workspace "$workspace" "$target"; then
            if [[ $(list_monitors) == "$MONITORS" ]]; then
                notify_error "Couldn't move workspace $workspace to monitor $target"
                exit 1
            fi
            MOVE_INTERRUPTED=true
            return 0
        fi
        moved=true
    done 3<<<"$workspaces"
    if [[ $moved == true ]]; then
        restore_visible_workspaces "$focused"
    fi
}

# If the set of connected monitors changed since the last run, moves workspaces without Citrix
# windows, sets MONITORS_CHANGED to true and pushes back the deadline for the monitors to settle
update_workspaces() {
    local previous
    for _ in 1 2 3 4 5; do
        find_monitors
        previous=$(cat "$STATE_FILE" 2>/dev/null || true)
        if [[ -f $STATE_FILE && $previous == "$MONITOR_NAMES" ]]; then
            return 0
        fi

        MONITORS_CHANGED=true
        trace "Monitors changed: $(tr '\n' ',' <<<"$MONITOR_NAMES")"
        push_deadline monitors-settle "$SETTLE_SECONDS"
        rm -f "$LAPTOP_ONLY_FILE"
        MOVE_INTERRUPTED=false
        if has_split && (($(count_external_monitors "$MONITOR_NAMES") < $(count_external_monitors "$previous"))); then
            trace "Fewer external monitors, so waiting for the monitors to settle before moving workspaces"
        elif has_split; then
            find_citrix_workspaces
            move_workspaces non_citrix_split_target
        fi
        if [[ $MOVE_INTERRUPTED == false ]]; then
            echo "$MONITOR_NAMES" >"$STATE_FILE"
            return 0
        fi
        sleep 1
    done
    notify_error "Monitors kept changing while arranging workspaces"
    exit 1
}

# Once the monitors have settled, moves the remaining workspaces and resizes Citrix windows
settle_monitors() {
    until deadline_passed monitors-settle; do
        sleep 1
        # Monitors reconnecting don't always cause a focus change, so check for them here too
        run_when_unlocked monitors update_workspaces
    done
    trace "Monitors settled"
    run_when_unlocked monitors move_remaining_workspaces
    # Otherwise the monitors changed again meanwhile, and run_until_deadline calls this again
    if deadline_passed monitors-settle; then
        "$CITRIX_SCRIPT" refresh-window-sizes "$(($(read_deadline monitors-settle) - SETTLE_SECONDS))"
    fi
}

# Moves Citrix workspaces, and any others not moved yet
move_remaining_workspaces() {
    # Picks up monitor changes no focus change has reported yet
    update_workspaces
    deadline_passed monitors-settle || return 0
    has_split || return 0
    # The toggle moves every workspace itself
    [[ ! -f $LAPTOP_ONLY_FILE ]] || return 0

    move_workspaces split_target
    trace "Moved remaining workspaces"
    if [[ $MOVE_INTERRUPTED == true ]]; then
        update_workspaces
    fi
}

toggle_laptop_only() {
    # Picks up a monitor change first, so the next focus change doesn't undo the toggle
    update_workspaces
    if ! has_split; then
        notify_error 'Needs both the laptop display and an external monitor'
        exit 1
    fi

    if [[ -f $LAPTOP_ONLY_FILE ]]; then
        move_workspaces split_target
    else
        move_workspaces laptop_target
    fi

    if [[ $MOVE_INTERRUPTED == true ]]; then
        update_workspaces
    elif [[ -f $LAPTOP_ONLY_FILE ]]; then
        rm "$LAPTOP_ONLY_FILE"
    else
        touch "$LAPTOP_ONLY_FILE"
    fi
}

on_focus_change() {
    update_workspaces
    if [[ $MONITORS_CHANGED == false ]]; then
        record_visible_workspaces
    fi
}

case ${1:-} in
    '') run_exclusively monitors on_focus_change ;;
    toggle-laptop-only) run_when_unlocked monitors toggle_laptop_only ;;
    *)
        notify_error "Unknown argument: $1"
        exit 1
        ;;
esac

if [[ $MONITORS_CHANGED == true ]]; then
    run_until_deadline monitors-settle settle_monitors
fi
