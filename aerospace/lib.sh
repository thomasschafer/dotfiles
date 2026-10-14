# Helpers shared by the scripts AeroSpace runs from its callbacks. Callers set SCRIPT_NAME before
# sourcing this file.

notify_error() {
    osascript -e "display notification \"$1\" with title \"AeroSpace $SCRIPT_NAME script\"" || true
}

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

# Returns 1 if another run holds the lock
acquire_lock() {
    local dir=$1
    if mkdir "$dir" 2>/dev/null; then
        return 0
    fi
    # Clear a lock left behind by a run that was killed
    if [[ -n $(find "$dir" -maxdepth 0 -mmin +1) ]]; then
        rmdir "$dir"
        mkdir "$dir"
        return 0
    fi
    return 1
}
