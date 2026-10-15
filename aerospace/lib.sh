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

# Seconds to keep checking for a title on a window first seen without one
readonly ROUTE_TITLE_WAIT=60

# Routes each window of an app the first time it is seen with a title for which
# should_route_window <title> succeeds, by calling route_window <window-id> <title>. Callers define
# both functions. Windows are only routed once, so manual moves afterwards are left alone. Titles
# can be set without a further focus change (apps such as Citrix can take a while to title new
# windows), so this keeps checking for a few seconds, and for longer while there are untitled
# windows first seen less than ROUTE_TITLE_WAIT seconds ago.
route_new_windows() {
    local started=$SECONDS
    readonly ROUTE_APP_ID=$1 ROUTE_NAME=$2
    require_single_aerospace
    # Keyed by AeroSpace PID: AeroSpace re-runs on-window-detected for every window on restart, so
    # windows need routing again
    ROUTE_STATE_FILE=$(state_path "$ROUTE_NAME-handled-$AEROSPACE_PID")
    # Untitled windows, with the time each was first seen
    ROUTE_UNTITLED_FILE=$(state_path "$ROUTE_NAME-untitled-$AEROSPACE_PID")
    readonly ROUTE_STATE_FILE ROUTE_UNTITLED_FILE

    while true; do
        ROUTE_AWAITING_TITLE=false
        run_exclusively "$ROUTE_NAME" route_unhandled_windows
        if ((SECONDS - started >= 4)) && [[ $ROUTE_AWAITING_TITLE == false ]]; then
            break
        fi
        sleep 1
    done
}

# Sets ROUTE_AWAITING_TITLE to true if any untitled window is still within ROUTE_TITLE_WAIT
route_unhandled_windows() {
    local windows handled untitled new_untitled='' now first_seen id title
    windows=$(aerospace list-windows --monitor all --app-bundle-id "$ROUTE_APP_ID" --format '%{window-id}%{tab}%{window-title}')
    if [[ -z $windows ]]; then
        : >"$ROUTE_UNTITLED_FILE"
        return 0
    fi

    touch "$ROUTE_STATE_FILE" "$ROUTE_UNTITLED_FILE"
    # Drop closed windows so the state file only tracks live window IDs
    handled=$(cut -f1 <<<"$windows" | grep -Fx -f "$ROUTE_STATE_FILE" || true)
    if [[ -n $handled ]]; then
        echo "$handled" >"$ROUTE_STATE_FILE"
    else
        : >"$ROUTE_STATE_FILE"
    fi
    untitled=$(<"$ROUTE_UNTITLED_FILE")
    now=$(date +%s)

    # Read from fd 3 because the aerospace CLI reads stdin, which would swallow the list
    while IFS=$'\t' read -r -u 3 id title; do
        if grep -Fxq "$id" <<<"$handled"; then
            continue
        fi
        if ! [[ $title =~ [^[:space:]] ]]; then
            first_seen=$(awk -F '\t' -v id="$id" '$1 == id { print $2 }' <<<"$untitled")
            first_seen=${first_seen:-$now}
            new_untitled+="$id"$'\t'"$first_seen"$'\n'
            if ((now - first_seen < ROUTE_TITLE_WAIT)); then
                ROUTE_AWAITING_TITLE=true
            fi
            continue
        fi
        should_route_window "$title" || continue
        route_window "$id" "$title"
        echo "$id" >>"$ROUTE_STATE_FILE"
    done 3<<<"$windows"

    printf '%s' "$new_untitled" >"$ROUTE_UNTITLED_FILE"
}
