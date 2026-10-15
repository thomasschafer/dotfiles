#!/usr/bin/env bash

# Zoom meeting and webinar windows are often untitled when first detected, so on-window-detected
# title matchers can't pick them out from the main Zoom window. AeroSpace runs this on focus
# changes: the first time a meeting or webinar window is seen with its title, it is moved to its own
# workspace and focused. Windows are only handled once, so manual moves afterwards are left alone.

set -Eeuo pipefail

readonly SCRIPT_NAME='Zoom'
# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

should_route_window() {
    [[ $1 == 'Zoom Meeting' || $1 == 'Zoom Webinar' ]]
}

route_window() {
    aerospace move-node-to-workspace --focus-follows-window --window-id "$1" Z
}

route_setup 'us.zoom.xos' zoom
route_new_windows
