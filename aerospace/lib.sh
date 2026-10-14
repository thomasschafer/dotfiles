# Helpers shared by the scripts AeroSpace runs from its callbacks. Callers run `set -Eeuo pipefail`
# (-E so the ERR trap below also fires inside functions) and set SCRIPT_NAME before sourcing this
# file.

notify_error() {
    osascript -e "display notification \"$1\" with title \"AeroSpace $SCRIPT_NAME script\"" || true
}
trap 'notify_error "Failed at line $LINENO"' ERR

# Sets AEROSPACE_PID, exiting if there isn't exactly one AeroSpace process
require_single_aerospace() {
    local pids
    pids=$(pgrep -ax AeroSpace || true)
    if [[ $(wc -l <<<"$pids") -ne 1 || -z $pids ]]; then
        notify_error "Expected exactly one AeroSpace process, found: ${pids:-none}"
        exit 1
    fi
    readonly AEROSPACE_PID=$pids
}

state_path() {
    echo "${TMPDIR:-/tmp}/aerospace-$1"
}

# Runs a command while holding the named lock. If another run already holds it, does nothing and
# relies on that run to do the work.
run_exclusively() {
    local lock_dir
    lock_dir=$(state_path "$1.lock")
    shift
    if ! mkdir "$lock_dir" 2>/dev/null; then
        # Clear a lock left behind by a run that was killed
        [[ -n $(find "$lock_dir" -maxdepth 0 -mmin +1) ]] || return 0
        rmdir "$lock_dir"
        mkdir "$lock_dir"
    fi
    trap "rmdir $(printf %q "$lock_dir")" EXIT
    "$@"
    rmdir "$lock_dir"
    trap - EXIT
}

# Routes each window of an app the first time it is seen with a title for which
# should_route_window <title> succeeds, by calling route_window <window-id> <title>. Callers define
# both functions. Windows are only routed once, so manual moves afterwards are left alone. Titles
# can be set without a further focus change, so this checks again after short delays.
route_new_windows() {
    local delay
    readonly ROUTE_APP_ID=$1 ROUTE_NAME=$2
    require_single_aerospace
    # Keyed by AeroSpace PID: AeroSpace re-runs on-window-detected for every window on restart, so
    # windows need routing again
    ROUTE_STATE_FILE=$(state_path "$ROUTE_NAME-handled-$AEROSPACE_PID")
    readonly ROUTE_STATE_FILE

    run_exclusively "$ROUTE_NAME" route_unhandled_windows
    for delay in 1 3; do
        sleep "$delay"
        run_exclusively "$ROUTE_NAME" route_unhandled_windows
    done
}

route_unhandled_windows() {
    local windows handled id title
    windows=$(aerospace list-windows --monitor all --app-bundle-id "$ROUTE_APP_ID" --format '%{window-id}%{tab}%{window-title}')
    [[ -n $windows ]] || return 0

    touch "$ROUTE_STATE_FILE"
    # Drop closed windows so the state file only tracks live window IDs
    handled=$(cut -f1 <<<"$windows" | grep -Fx -f "$ROUTE_STATE_FILE" || true)
    if [[ -n $handled ]]; then
        echo "$handled" >"$ROUTE_STATE_FILE"
    else
        : >"$ROUTE_STATE_FILE"
    fi

    # Read from fd 3 because the aerospace CLI reads stdin, which would swallow the list
    while IFS=$'\t' read -r -u 3 id title; do
        [[ $title =~ [^[:space:]] ]] || continue
        if grep -Fxq "$id" <<<"$handled"; then
            continue
        fi
        should_route_window "$title" || continue
        route_window "$id" "$title"
        echo "$id" >>"$ROUTE_STATE_FILE"
    done 3<<<"$windows"
}
