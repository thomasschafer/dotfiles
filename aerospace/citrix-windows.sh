#!/usr/bin/env bash

# Citrix seamless windows all report the AXDialog subrole, so AeroSpace floats them. They often
# have no title when first detected, so on-window-detected title matchers can't classify them
# reliably. AeroSpace runs this on focus changes: the first time a Citrix window is seen with a
# title, it is routed to its workspace and tiled (unless it's a helper window). Windows are only
# handled once, so manual moves and layout changes afterwards are left alone.

set -euo pipefail

readonly APP_ID='com.citrix.receiver.icaviewer.mac'
readonly RETRY_DELAYS=(1 3)

notify_error() {
    osascript -e "display notification \"$1\" with title \"AeroSpace Citrix script\"" || true
}
trap 'notify_error "Failed at line $LINENO"' ERR

aerospace_pids=$(pgrep -ax AeroSpace || true)
if [[ $(wc -l <<<"$aerospace_pids") -ne 1 || -z $aerospace_pids ]]; then
    notify_error "Expected exactly one AeroSpace process, found: ${aerospace_pids:-none}"
    exit 1
fi

# Keyed by AeroSpace PID: AeroSpace re-runs on-window-detected for every window on restart, so
# windows need handling again
readonly STATE_FILE="${TMPDIR:-/tmp}/aerospace-citrix-handled-$aerospace_pids"
readonly LOCK_DIR="${TMPDIR:-/tmp}/aerospace-citrix.lock"

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        return 0
    fi
    # Clear a lock left behind by a run that was killed
    if [[ -n $(find "$LOCK_DIR" -maxdepth 0 -mmin +1) ]]; then
        rmdir "$LOCK_DIR"
        mkdir "$LOCK_DIR"
        return 0
    fi
    return 1
}

tile() {
    local err
    # 'layout tiling' exits non-zero without output when the window is already tiled
    if ! err=$(aerospace layout --window-id "$1" tiling 2>&1) && [[ -n $err ]]; then
        echo "$err" >&2
        return 1
    fi
}

handle_new_windows() {
    local windows handled id title
    windows=$(aerospace list-windows --monitor all --app-bundle-id "$APP_ID" --format '%{window-id}%{tab}%{window-title}')
    [[ -n $windows ]] || return 0

    touch "$STATE_FILE"
    # Drop closed windows so the state file only tracks live window IDs
    handled=$(cut -f1 <<<"$windows" | grep -Fx -f "$STATE_FILE" || true)
    if [[ -n $handled ]]; then
        echo "$handled" >"$STATE_FILE"
    else
        : >"$STATE_FILE"
    fi

    while IFS=$'\t' read -r id title; do
        [[ $title =~ [^[:space:]] ]] || continue
        if grep -Fxq "$id" <<<"$handled"; then
            continue
        fi
        case $title in
            wdmm-Win32Window*) ;;
            Launchpad*) aerospace move-node-to-workspace --window-id "$id" E ;;
            'IB - '*)
                tile "$id"
                aerospace move-node-to-workspace --window-id "$id" W
                ;;
            *)
                tile "$id"
                aerospace move-node-to-workspace --window-id "$id" Q
                ;;
        esac
        echo "$id" >>"$STATE_FILE"
    done <<<"$windows"
}

run_once() {
    # Another run is in progress and will pick up any new windows
    acquire_lock || return 0
    trap 'rmdir "$LOCK_DIR"' EXIT
    handle_new_windows
    rmdir "$LOCK_DIR"
    trap - EXIT
}

run_once
for delay in "${RETRY_DELAYS[@]}"; do
    sleep "$delay"
    run_once
done
