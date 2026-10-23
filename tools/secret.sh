#!/usr/bin/env bash
# Reads and stores secrets as generic passwords in the login keychain, one item per service, under
# this macOS account. Values never appear in argv, so other processes can't see them in the
# process list.
#
# Usage: secret get <service>      prints the value, without a trailing newline
#        secret exists <service>   exits 0 if the item exists and 1 if not
#        secret set <service>      reads the value from a hidden prompt, or from stdin when it
#                                  isn't a terminal, and replaces any existing item
#
# Any other failure, such as a locked keychain, exits 2 with a message.

set -euo pipefail

SECURITY=/usr/bin/security
ITEM_NOT_FOUND_EXIT=44

USAGE="Usage: secret get|exists|set <service>"

die() {
    echo "secret: $*" >&2
    exit 2
}

[ $# -eq 2 ] || die "$USAGE"
command="$1"
service="$2"
account="$(id -un)"

# The names are interpolated into a `security -i` command line, so only allow characters that
# need no quoting there.
for name in "$service" "$account"; do
    [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "unsafe service or account name '$name'"
done

# Usage: fail_lookup <exit code>
# Explains why looking the item up failed. Repeats the lookup without -w, so the value isn't
# fetched again, to get the error message.
fail_lookup() {
    local status="$1" error
    error="$("$SECURITY" find-generic-password -s "$service" -a "$account" 2>&1 >/dev/null || true)"
    if [[ "$(tr '[:upper:]' '[:lower:]' <<<"$error")" == *"interaction is not allowed"* ]]; then
        die "the keychain is locked, so '$service' can't be read"
    fi
    die "security exited $status reading '$service': $error"
}

get() {
    local value status=0
    value="$("$SECURITY" find-generic-password -s "$service" -a "$account" -w 2>/dev/null)" || status=$?
    case "$status" in
        0) ;;
        "$ITEM_NOT_FOUND_EXIT") die "no keychain item '$service'" ;;
        *) fail_lookup "$status" ;;
    esac
    [ -n "$value" ] || die "keychain item '$service' is empty"
    printf '%s' "$value"
}

exists() {
    local status=0
    "$SECURITY" find-generic-password -s "$service" -a "$account" >/dev/null 2>&1 || status=$?
    case "$status" in
        0) return 0 ;;
        "$ITEM_NOT_FOUND_EXIT") return 1 ;;
        *) fail_lookup "$status" ;;
    esac
}

read_value() {
    local value again
    if [ -t 0 ]; then
        read -rsp "Value for $service (hidden): " value
        echo >&2
        read -rsp "Again, to confirm: " again
        echo >&2
        [ "$value" = "$again" ] || die "the values didn't match, so nothing was stored"
    else
        value="$(cat)"
    fi
    printf '%s' "$value"
}

set_value() {
    local value hex status=0
    value="$(read_value)"
    [ -n "$value" ] || die "refusing to store an empty value for '$service'"
    # `security find-generic-password -w` prints anything else as hex, which would no longer read
    # back as written.
    LC_ALL=C
    [[ "$value" =~ ^[\ -~]+$ ]] || die "the value for '$service' must be printable ASCII on one line"
    # `security -i` reads its command from stdin rather than argv. Hex encoding sidesteps its
    # quoting rules.
    hex="$(printf '%s' "$value" | od -An -tx1 | tr -d ' \n')"
    printf 'add-generic-password -U -s %s -a %s -X %s\n' "$service" "$account" "$hex" |
        "$SECURITY" -i >/dev/null 2>&1 || status=$?
    [ "$status" -eq 0 ] || die "security exited $status storing '$service'"
    [ "$(get)" = "$value" ] || die "keychain item '$service' didn't read back as written"
}

case "$command" in
    get) get ;;
    exists) exists ;;
    set) set_value ;;
    *) die "$USAGE" ;;
esac
