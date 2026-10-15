#!/usr/bin/env bash

# Citrix seamless windows all report the AXDialog subrole, so AeroSpace floats them. They often
# have no title when first detected, so on-window-detected title matchers can't classify them
# reliably. AeroSpace runs this on focus changes: the first time a Citrix window is seen with a
# title, it is routed to its workspace and tiled (unless it's a helper window). Windows are only
# handled once, so manual moves and layout changes afterwards are left alone.
#
# Citrix applies a new monitor layout a few seconds after the monitors change (and sometimes without
# a change AeroSpace sees, such as after unlocking), rebuilding its windows. It then ignores resizes
# for each window until it is focused and the mouse moves over it, so tiled windows keep their old
# size. Refreshing window sizes waits for Citrix to apply the layout, routes the rebuilt windows,
# then focuses each tiled window and moves the mouse over it, before putting the visible
# workspaces, focus and the mouse back. Each layout is only refreshed for once.
#
# Run with refresh-window-sizes <since> once the monitors have stopped changing, passing the time of
# the last change in seconds since the epoch. Focus changes also refresh window sizes if Citrix has
# applied a layout that hasn't been refreshed for.

set -Eeuo pipefail

readonly SCRIPT_NAME='Citrix'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

readonly CITRIX_LOG_DIR="$HOME/Library/Logs/Citrix Workspace"
# The last layout window sizes were refreshed for, as logged by Citrix
REFRESHED_LAYOUT_FILE=$(state_path citrix-refreshed-layout)
readonly REFRESHED_LAYOUT_FILE

tile() {
    local err
    # 'layout tiling' exits non-zero without output when the window is already tiled. The subshell
    # inherits the ERR trap (set -E), so clear it there to avoid notifying about that expected exit.
    if ! err=$(trap - ERR; aerospace layout --window-id "$1" tiling 2>&1) && [[ -n $err ]]; then
        echo "$err" >&2
        return 1
    fi
}

# Helper windows are left floating
is_tiled_window() {
    [[ $1 != wdmm-Win32Window* && $1 != Launchpad* ]]
}

should_route_window() {
    return 0
}

route_window() {
    local id=$1 title=$2
    if is_tiled_window "$title"; then
        tile "$id"
    fi
    case $title in
        wdmm-Win32Window*) ;;
        Launchpad*) aerospace move-node-to-workspace --window-id "$id" "$CITRIX_LAUNCHPAD_WORKSPACE" ;;
        'IB - '*) aerospace move-node-to-workspace --window-id "$id" "$CITRIX_IB_WORKSPACE" ;;
        *) aerospace move-node-to-workspace --window-id "$id" "$CITRIX_MAIN_WORKSPACE" ;;
    esac
}

list_windows() {
    aerospace list-windows --monitor all --app-bundle-id "$CITRIX_APP_ID" --format '%{window-id}%{tab}%{window-title}'
}

# Sets LAYOUT_STAMP (as logged), LAYOUT_TIME (seconds since the epoch) and LAYOUT_MONITORS for the
# last monitor layout Citrix logged applying, or leaves them empty if there isn't one
read_latest_layout() {
    local log lines last
    LAYOUT_STAMP='' LAYOUT_TIME='' LAYOUT_MONITORS=''
    log=$(ls -t "$CITRIX_LOG_DIR"/CitrixViewer_*.txt 2>/dev/null | head -n 1 || true)
    [[ -n $log ]] || return 0
    lines=$(tail -c 1000000 "$log" | grep -a 'Received new VDA Monitor layout' | tail -n 10 || true)
    [[ -n $lines ]] || return 0

    # One line per monitor in the layout, starting "| 10-15-2026 | 12:26:47.583 |"
    last=$(tail -n 1 <<<"$lines")
    if ! [[ $last =~ ([0-9]{2})-([0-9]{2})-([0-9]{4})\ \|\ ([0-9]{2}:[0-9]{2}:[0-9]{2})\.[0-9]+ ]]; then
        notify_error "Unexpected Citrix log line: $last"
        exit 1
    fi
    LAYOUT_STAMP=${BASH_REMATCH[0]}
    LAYOUT_TIME=$(date -j -f '%m-%d-%Y %H:%M:%S' \
        "${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}" +%s)
    LAYOUT_MONITORS=$(grep -cF "$LAYOUT_STAMP" <<<"$lines" || true)
}

layout_matches_monitors() {
    [[ -n $LAYOUT_STAMP ]] && ((LAYOUT_MONITORS == $(aerospace list-monitors --count)))
}

layout_refreshed() {
    [[ -n $LAYOUT_STAMP && $LAYOUT_STAMP == "$(cat "$REFRESHED_LAYOUT_FILE" 2>/dev/null || true)" ]]
}

# Waits until Citrix has logged applying a monitor layout with as many monitors as are connected, at
# or after <since> (seconds since the epoch)
wait_for_layout() {
    local since=$1 started=$SECONDS
    while ((SECONDS - started < 15)); do
        read_latest_layout
        if layout_matches_monitors && ((LAYOUT_TIME >= since)); then
            trace "Layout $LAYOUT_STAMP with $LAYOUT_MONITORS monitors"
            return 0
        fi
        sleep 0.25
    done
    trace "Timed out waiting for a layout, latest is $LAYOUT_STAMP with $LAYOUT_MONITORS monitors"
    notify_error "Citrix didn't log applying the new monitor layout, so windows may keep their old size"
}

# Waits for Citrix to finish rebuilding its windows, which it does over a second or so after
# applying a layout, by waiting for its window list to stay the same for half a second
wait_for_windows_to_settle() {
    local started=$SECONDS previous='' current unchanged=0
    while ((SECONDS - started < 5)); do
        current=$(list_windows)
        if [[ $current == "$previous" ]]; then
            if ((++unchanged >= 2)); then
                trace "Windows settled: $(tr '\t\n' ': ' <<<"$current")"
                return 0
            fi
        else
            unchanged=0
            previous=$current
        fi
        sleep 0.25
    done
    trace "Timed out waiting for windows to settle: $(tr '\t\n' ': ' <<<"$current")"
}

# Prints the size of the window with the given title as "<width>x<height>", or nothing if there's no
# such window. With a previous size and a timeout in seconds, first waits until the size differs
# from the previous one, or the timeout passes.
window_size() {
    osascript -l JavaScript -e '
        function run(argv) {
            var title = argv[0], previous = argv[1] || "", timeout = Number(argv[2] || 0);
            var process = Application("System Events").processes.whose({bundleIdentifier: argv[3]})[0];
            function size() {
                try {
                    var size = process.windows.whose({name: title})[0].size();
                    return size[0] + "x" + size[1];
                } catch (error) {
                    return "";
                }
            }
            var started = Date.now(), current = size();
            while (current === previous && Date.now() - started < timeout * 1000) {
                delay(0.1);
                current = size();
            }
            return current;
        }' "$1" "${2:-}" "${3:-0}" "$CITRIX_APP_ID"
}

# Prints the mouse position as "<x> <y>" in global display coordinates
mouse_position() {
    osascript -l JavaScript -e \
        'ObjC.import("CoreGraphics"); var p = $.CGEventGetLocation($.CGEventCreate(null)); p.x + " " + p.y'
}

# Moves the mouse to a position in global display coordinates, or to the middle of the focused
# monitor if the position is no longer on a display (its monitor was disconnected)
move_mouse_to() {
    local result
    result=$(osascript -l JavaScript -e '
        function run(argv) {
            ObjC.import("AppKit");
            ObjC.import("CoreGraphics");
            var x = Number(argv[0]), y = Number(argv[1]);
            var screens = $.NSScreen.screens, mainHeight = screens.objectAtIndex(0).frame.size.height;
            for (var i = 0; i < screens.count; i++) {
                // NSScreen frames have a bottom-left origin, global display coordinates a top-left one
                var frame = screens.objectAtIndex(i).frame;
                var top = mainHeight - frame.origin.y - frame.size.height;
                if (x >= frame.origin.x && x < frame.origin.x + frame.size.width && y >= top && y < top + frame.size.height) {
                    $.CGWarpMouseCursorPosition({x: x, y: y});
                    return "moved";
                }
            }
            return "off-screen";
        }' "$1" "$2")
    case $result in
        moved) ;;
        off-screen) aerospace move-mouse monitor-force-center ;;
        *)
            notify_error "Unexpected result moving the mouse: $result"
            exit 1
            ;;
    esac
}

# Focuses each tiled window and moves the mouse over it, then puts the visible workspaces, focus
# and the mouse back
nudge_tiled_windows() {
    local windows id title targets=() visible_workspaces workspace focused_workspace focused_window \
        focused_window_workspace mouse_x mouse_y target size current
    windows=$(list_windows)
    while IFS=$'\t' read -r id title; do
        if [[ $title =~ [^[:space:]] ]] && is_tiled_window "$title"; then
            targets+=("$id"$'\t'"$title")
        fi
    done <<<"$windows"
    ((${#targets[@]} > 0)) || return 0

    # Focusing a window on a hidden workspace shows that workspace in place of the visible one
    visible_workspaces=$(aerospace list-workspaces --monitor all --visible)
    focused_workspace=$(aerospace list-workspaces --focused)
    read -r focused_window focused_window_workspace <<<"$(focused_window_and_workspace)"
    trace "Visible workspaces: $(tr '\n' ' ' <<<"$visible_workspaces")focused: $focused_workspace, window $focused_window on $focused_window_workspace"
    if ! grep -Fxq "$focused_workspace" <<<"$visible_workspaces"; then
        focused_workspace=$(aerospace list-workspaces --monitor focused --visible)
    fi
    if [[ -n $focused_window ]] && ! grep -Fxq "$focused_window_workspace" <<<"$visible_workspaces"; then
        # Monitor changes can leave AeroSpace reporting a focused window or workspace that isn't
        # shown. Keep what's shown instead, rather than jumping to it at the end.
        focused_window=''
        trace "Focused window isn't visible, so restoring workspace $focused_workspace instead"
    fi
    read -r mouse_x mouse_y <<<"$(mouse_position)"

    for target in "${targets[@]}"; do
        IFS=$'\t' read -r id title <<<"$target"
        size=$(window_size "$title")
        aerospace focus --window-id "$id"
        aerospace move-mouse window-force-center
        # Citrix can take half a second or so to resize the window. Windows that already have the
        # right size don't change, so this waits for the whole timeout for those.
        trace "Nudged $id ($title): $size -> $(window_size "$title" "$size" 1.5)"
    done

    # Read from fd 3 because the aerospace CLI reads stdin, which would swallow the list
    while read -r -u 3 workspace; do
        aerospace workspace "$workspace"
    done 3<<<"$visible_workspaces"
    restore_focus "$focused_window" "$focused_workspace"
    move_mouse_to "$mouse_x" "$mouse_y"

    # Citrix can activate a window just after resizing it, taking focus back
    for _ in 1 2 3 4; do
        sleep 0.25
        read -r current _ <<<"$(focused_window_and_workspace)"
        if [[ -n $current && $current != "$focused_window" ]] && cut -f1 <<<"$(list_windows)" | grep -Fxq "$current"; then
            trace "Citrix window $current took focus back, restoring it"
            restore_focus "$focused_window" "$focused_workspace"
        fi
    done
}

# Prints the ID of the focused window and its workspace, or nothing if the focused workspace is empty
focused_window_and_workspace() {
    # The subshell this runs in inherits the ERR trap (set -E), so clear it to avoid notifying about
    # the failure when there's no focused window
    trap - ERR
    aerospace list-windows --focused --format '%{window-id} %{workspace}' 2>/dev/null || true
}

# Focuses the given window, or the given workspace if there's no window
restore_focus() {
    if [[ -n $1 ]]; then
        aerospace focus --window-id "$1"
    else
        aerospace workspace "$2"
    fi
}

refresh_window_sizes() {
    local since=$1
    # Checks for the app rather than its windows, as it has none while rebuilding them
    pgrep -xq 'Citrix Viewer' || return 0
    trace "Refreshing window sizes for a layout since $(date -r "$since" +%T)"
    wait_for_layout "$since"
    if layout_refreshed; then
        trace "Layout already refreshed for"
        return 0
    fi

    wait_for_windows_to_settle
    route_windows_once
    nudge_tiled_windows
    if [[ -n $LAYOUT_STAMP ]]; then
        echo "$LAYOUT_STAMP" >"$REFRESHED_LAYOUT_FILE"
    fi
    trace "Refreshed window sizes"
}

# Starts refreshing window sizes in the background if Citrix has applied a layout matching the
# connected monitors that hasn't been refreshed for, unless a refresh is already running
refresh_window_sizes_if_needed() {
    # A refresh causes focus changes itself
    [[ ! -d $(state_path citrix-refresh.lock) ]] || return 0
    read_latest_layout
    if ! layout_refreshed && layout_matches_monitors; then
        trace "Layout $LAYOUT_STAMP not refreshed for yet"
        "${BASH_SOURCE[0]}" refresh-window-sizes-if-idle "$LAYOUT_TIME" &
    fi
}

require_since_argument() {
    if ! [[ ${1:-} =~ ^[0-9]+$ ]]; then
        notify_error "Expected the time of the last monitor change, got: ${1:-nothing}"
        exit 1
    fi
}

route_setup "$CITRIX_APP_ID" citrix
case ${1:-} in
    '')
        refresh_window_sizes_if_needed
        route_new_windows
        ;;
    refresh-window-sizes)
        require_since_argument "${2:-}"
        run_when_unlocked citrix-refresh refresh_window_sizes "$2"
        ;;
    refresh-window-sizes-if-idle)
        require_since_argument "${2:-}"
        run_exclusively citrix-refresh refresh_window_sizes "$2"
        ;;
    *)
        notify_error "Unknown argument: $1"
        exit 1
        ;;
esac
