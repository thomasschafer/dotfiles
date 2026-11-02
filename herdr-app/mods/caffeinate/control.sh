#!/bin/sh
set -eu

# herdr's exec starts this shell directly, so its parent is the GUI, not herdr-core.
app_pid=$PPID
case "$app_pid" in
  ''|*[!0-9]*|0|1) echo "caffeinate: invalid GUI process ID: $app_pid" >&2; exit 1 ;;
esac
pattern="/usr/bin/caffeinate -is -w $app_pid"

# Keep the lock file: unlinking it could let callers lock different inodes.
# lockf shares descriptor 9 with this shell; the OS releases it when the shell exits.
umask 077
lock="${TMPDIR:-/tmp}/herdr-app-caffeinate-$(id -u).lock"
exec 9>"$lock"
/usr/bin/lockf -t 5 9

find_helpers() {
  if helpers=$(/usr/bin/pgrep -f -x "$pattern"); then
    return 0
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      echo "caffeinate: couldn't check running helpers (pgrep exited $status)" >&2
      exit "$status"
    fi
  fi
  helpers=""
}

find_helpers
case "${1:-}" in
  start)
    if [ -z "$helpers" ]; then
      # Close inherited pipes so exec can finish while caffeinate watches the GUI.
      /usr/bin/caffeinate -is -w "$app_pid" 9>&- </dev/null >/dev/null 2>&1 &
      helper_pid=$!
      attempts=0
      while [ -z "$helpers" ]; do
        attempts=$((attempts + 1))
        if [ "$attempts" -gt 20 ] || ! kill -0 "$helper_pid" 2>/dev/null; then
          echo "caffeinate: helper failed to start" >&2
          exit 1
        fi
        sleep 0.05
        find_helpers
      done
    fi
    ;;
  stop)
    for helper in $helpers; do
      kill "$helper"
    done
    attempts=0
    while [ -n "$helpers" ]; do
      attempts=$((attempts + 1))
      if [ "$attempts" -gt 20 ]; then
        echo "caffeinate: helper failed to stop" >&2
        exit 1
      fi
      sleep 0.05
      find_helpers
    done
    ;;
  status) ;;
  *) echo "Usage: control.sh start|stop|status" >&2; exit 2 ;;
esac

if [ -n "$helpers" ]; then
  echo on
else
  echo off
fi
