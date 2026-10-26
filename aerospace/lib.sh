# shellcheck shell=bash
# shellcheck disable=SC2034  # Variables are used by the scripts that source this.
# Helpers shared by the scripts AeroSpace runs from its callbacks. Callers run `set -Eeuo pipefail`
# (-E so the ERR trap below also fires inside functions) and set SCRIPT_NAME before sourcing this
# file.

readonly CITRIX_APP_ID='com.citrix.receiver.icaviewer.mac'
# Where citrix-windows.sh routes Citrix windows: IB to its own workspace, Launchpad to another and
# everything else to the main one
readonly CITRIX_MAIN_WORKSPACE=Q CITRIX_IB_WORKSPACE=W CITRIX_LAUNCHPAD_WORKSPACE=E

notify_error() {
    osascript -e 'on run {message, title}' -e 'display notification message with title title' -e 'end run' \
        -- "$1" "AeroSpace $SCRIPT_NAME script" || true
}
# Command substitutions inherit the trap (set -E) and a failure in one is reported again by the
# command using it, so only report from the main shell. Bash 3.2 reports the line of the enclosing
# function's declaration for failures inside functions, so include the failing command too.
on_error() {
    ((BASH_SUBSHELL == 0)) || return 0
    notify_error "Failed at line $2: $1"
}
trap 'on_error "$BASH_COMMAND" "$LINENO"' ERR

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

# Deletes state files left by previous AeroSpace processes, which end with their PIDs. Needs
# AEROSPACE_PID (see require_single_aerospace).
remove_stale_state() {
    local file
    for file in "$(state_path '')"*; do
        if [[ -f $file && $file =~ -([0-9]+)$ && ${BASH_REMATCH[1]} != "$AEROSPACE_PID" ]]; then
            rm -f "$file"
        fi
    done
}

# Appends a timestamped line to a trace log, for working out what happened during monitor changes
trace() {
    local file
    file=$(state_path trace.log)
    if [[ -f $file ]] && (($(stat -f %z "$file") > 1000000)); then
        mv -f "$file" "$file.old"
    fi
    printf '%s %s[%s] %s\n' "$(perl -MPOSIX=strftime -MTime::HiRes=time \
        -e '$t = time; print strftime("%H:%M:%S", localtime $t), sprintf(".%03d", ($t - int $t) * 1000)')" \
        "$SCRIPT_NAME" $$ "$*" >>"$file"
}

# Lock directories held by this run, one per line, released when it exits
HELD_LOCKS=''

release_held_locks() {
    local lock_dir
    while read -r lock_dir; do
        if [[ -n $lock_dir ]]; then
            rm -rf "$lock_dir"
        fi
    done <<<"$HELD_LOCKS"
}
trap release_held_locks EXIT

# Takes the named lock, failing if another run holds it
try_lock() {
    local lock_dir pid
    lock_dir=$(state_path "$1.lock")
    if ! mkdir "$lock_dir" 2>/dev/null; then
        # Clear a lock left behind by a run that was killed. A run killed straight after taking the
        # lock won't have written its PID, so fall back on the lock's age.
        pid=$(cat "$lock_dir/pid" 2>/dev/null || true)
        if [[ -n $pid ]]; then
            ! kill -0 "$pid" 2>/dev/null || return 1
        else
            [[ -n $(find "$lock_dir" -maxdepth 0 -mmin +1) ]] || return 1
        fi
        rm -rf "$lock_dir"
        mkdir "$lock_dir" 2>/dev/null || return 1
    fi
    echo $$ >"$lock_dir/pid"
    HELD_LOCKS+=$lock_dir$'\n'
}

release_lock() {
    local lock_dir
    lock_dir=$(state_path "$1.lock")
    rm -rf "$lock_dir"
    HELD_LOCKS=$(grep -Fxv "$lock_dir" <<<"$HELD_LOCKS" || true)
}

# Runs a command while holding the named lock. If another run already holds it, does nothing and
# relies on that run to do the work.
run_exclusively() {
    local name=$1
    shift
    try_lock "$name" || return 0
    "$@"
    release_lock "$name"
}

# Runs a command while holding the named lock, waiting up to 20 seconds for another run to release
# it first
run_when_unlocked() {
    local name=$1 started=$SECONDS
    shift
    while ((SECONDS - started < 20)); do
        if try_lock "$name"; then
            "$@"
            release_lock "$name"
            return 0
        fi
        sleep 0.1
    done
    notify_error "Timed out waiting for the $name lock"
    exit 1
}

# Deadlines let one long-running run absorb later triggers: each trigger pushes the named deadline
# back, and only the run holding the lock of the same name works until it passes (see
# run_until_deadline).

# Pushes the named deadline back to at least <seconds> from now
push_deadline() {
    local file deadline
    file=$(state_path "$1.deadline")
    deadline=$(($(date +%s) + $2))
    if (($(read_deadline "$1") < deadline)); then
        # Written to a temporary file and renamed so concurrent readers never see a partial write
        echo "$deadline" >"$file.$$"
        mv -f "$file.$$" "$file"
    fi
}

read_deadline() {
    local file deadline
    file=$(state_path "$1.deadline")
    deadline=$(cat "$file" 2>/dev/null || echo 0)
    if ! [[ $deadline =~ ^[0-9]+$ ]]; then
        notify_error "Unexpected contents in $file: $deadline"
        exit 1
    fi
    echo "$deadline"
}

deadline_passed() {
    (($(date +%s) >= $(read_deadline "$1")))
}

# Runs a command that works until the named deadline passes, while holding the lock of the same
# name. If another run holds it, relies on that run instead, as it will see the pushed-back deadline.
run_until_deadline() {
    local name=$1
    shift
    while try_lock "$name"; do
        "$@"
        release_lock "$name"
        # A run that pushed the deadline back while this one was finishing found the lock taken and
        # left the work to this one
        ! deadline_passed "$name" || return 0
    done
}

# Seconds to keep checking for a title on a window first seen without one
readonly ROUTE_TITLE_WAIT=60

# Routing handles each window of an app the first time it is seen with a title for which
# should_route_window <title> succeeds, by calling route_window <window-id> <title>. Callers define
# both functions, and call route_setup <app-id> <name> first. Windows are only routed once, so
# manual moves afterwards are left alone.
route_setup() {
    readonly ROUTE_APP_ID=$1 ROUTE_NAME=$2
    require_single_aerospace
    # Keyed by AeroSpace PID: AeroSpace re-runs on-window-detected for every window on restart, so
    # windows need routing again
    ROUTE_STATE_FILE=$(state_path "$ROUTE_NAME-handled-$AEROSPACE_PID")
    # Untitled windows, with the time each was first seen
    ROUTE_UNTITLED_FILE=$(state_path "$ROUTE_NAME-untitled-$AEROSPACE_PID")
    ROUTE_TRIGGER_FILE=$(state_path "$ROUTE_NAME.trigger")
    readonly ROUTE_STATE_FILE ROUTE_UNTITLED_FILE ROUTE_TRIGGER_FILE
}

# Routes windows once, waiting for a check by another run to finish first
route_windows_once() {
    run_when_unlocked "$ROUTE_NAME-check" route_unhandled_windows
}

# Titles can be set without a further focus change (apps such as Citrix can take a while to title
# new windows), so this keeps checking every second for a few seconds after the last trigger, and
# for longer while there are untitled windows first seen less than ROUTE_TITLE_WAIT seconds ago.
# Only one run per app keeps checking at a time.
route_new_windows() {
    push_deadline "$ROUTE_NAME" 4
    # Lets the run checking for windows know to check again straight away (see route_until_deadline)
    echo $$ >"$ROUTE_TRIGGER_FILE"
    run_until_deadline "$ROUTE_NAME" route_until_deadline
}

route_until_deadline() {
    local trigger
    while true; do
        trigger=$(cat "$ROUTE_TRIGGER_FILE" 2>/dev/null || true)
        route_windows_once
        ! deadline_passed "$ROUTE_NAME" || return 0
        # Waits a second before checking again, or less if triggered again meanwhile
        for _ in 1 2 3 4 5; do
            sleep 0.2
            [[ $(cat "$ROUTE_TRIGGER_FILE" 2>/dev/null || true) == "$trigger" ]] || break
        done
    done
}

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
                # Two seconds, as the deadline only has a resolution of one
                push_deadline "$ROUTE_NAME" 2
            fi
            continue
        fi
        should_route_window "$title" || continue
        route_window "$id" "$title"
        echo "$id" >>"$ROUTE_STATE_FILE"
    done 3<<<"$windows"

    printf '%s' "$new_untitled" >"$ROUTE_UNTITLED_FILE"
}
