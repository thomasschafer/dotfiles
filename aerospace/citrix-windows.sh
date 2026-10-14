#!/usr/bin/env bash

# Citrix seamless windows all report the AXDialog subrole, so AeroSpace floats them. They often
# have no title when first detected, so on-window-detected title matchers can't classify them
# reliably. AeroSpace runs this on focus changes: the first time a Citrix window is seen with a
# title, it is routed to its workspace and tiled (unless it's a helper window). Windows are only
# handled once, so manual moves and layout changes afterwards are left alone.

set -Eeuo pipefail

readonly SCRIPT_NAME='Citrix'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

tile() {
    local err
    # 'layout tiling' exits non-zero without output when the window is already tiled
    if ! err=$(aerospace layout --window-id "$1" tiling 2>&1) && [[ -n $err ]]; then
        echo "$err" >&2
        return 1
    fi
}

should_route_window() {
    return 0
}

route_window() {
    local id=$1 title=$2
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
}

route_new_windows 'com.citrix.receiver.icaviewer.mac' citrix
