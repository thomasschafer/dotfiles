#!/usr/bin/env bash
# Serves the apps declared with tailscaleServe.apps in modules/tailscale-serve.nix over HTTPS on
# the tailnet, each on its own port of this Mac's address.
#
# Usage: tailscale-serve apply   Makes `tailscale serve` match the apps, as every switch does:
#                                serves any that aren't, and turns off ports it served before
#                                that no app uses now. Ports it has never served are left alone.
#        tailscale-serve check   Prints each app's link as "link<tab><app><tab><URL>", and
#                                anything to fix as "todo<tab><what to do>", for setup.sh.
#
# Expects TAILSCALE_SERVE_CONFIG (the apps, as JSON), TAILSCALE_SERVE_STATE (the file recording
# the ports it serves) and TAILSCALE_CLIS (where the tailscale CLI can be, separated by colons) in
# the environment, which the tailscale-serve wrapper sets.

set -euo pipefail

say() {
    echo "tailscale-serve: $*" >&2
}
die() {
    say "$*"
    exit 1
}
usage() {
    echo "Usage: tailscale-serve apply|check" >&2
    exit 1
}

[ -n "${TAILSCALE_SERVE_CONFIG:-}" ] && [ -n "${TAILSCALE_SERVE_STATE:-}" ] && [ -n "${TAILSCALE_CLIS:-}" ] \
    || die "run this through the tailscale-serve command"
[ $# -eq 1 ] || usage
mode="$1"
case "$mode" in
    apply | check) ;;
    *) usage ;;
esac

apps=()
while IFS= read -r app; do
    apps+=("$app")
done < <(jq -r 'keys[]' "$TAILSCALE_SERVE_CONFIG")
field() {
    jq -r --arg app "$1" ".[\$app].$2" "$TAILSCALE_SERVE_CONFIG"
}
names="$(jq -r 'keys | if length > 1 then (.[:-1] | join(", ")) + " and " + .[-1] else join("") end' \
    "$TAILSCALE_SERVE_CONFIG")"

previous=()
if [ -f "$TAILSCALE_SERVE_STATE" ]; then
    while IFS= read -r port; do
        [[ "$port" =~ ^[0-9]+$ ]] || die "$TAILSCALE_SERVE_STATE has '$port', which isn't a port"
        previous+=("$port")
    done <"$TAILSCALE_SERVE_STATE"
fi
[ ${#apps[@]} -gt 0 ] || [ ${#previous[@]} -gt 0 ] || exit 0

# Without Tailscale, as on a new machine, there's nothing to do yet, so this only says so.
unavailable() {
    if [ ${#apps[@]} -eq 0 ]; then
        say "warning: Tailscale $1, so the ports in $TAILSCALE_SERVE_STATE weren't turned off; once it is, run: tailscale-serve apply"
    elif [ "$mode" = apply ]; then
        say "warning: Tailscale $1, so $names can't be served yet; once it is, run: tailscale-serve apply"
    else
        printf 'todo\tserve %s over Tailscale, which %s; once it is, run: tailscale-serve apply\n' "$names" "$1"
    fi
    exit 0
}

cli=""
IFS=: read -ra candidates <<<"$TAILSCALE_CLIS"
for candidate in "${candidates[@]}"; do
    if [ -x "$candidate" ]; then
        cli="$candidate"
        break
    fi
done
[ -n "$cli" ] || unavailable "isn't installed"

# Tailscale can wait for the user, such as to turn Serve on for the tailnet, so this gives up
# rather than holding up a switch.
tailscale() {
    timeout 30 "$cli" "$@" </dev/null
}

status="$(tailscale status --json 2>/dev/null)" || true
[ "$(jq -r '.BackendState // empty' <<<"$status" 2>/dev/null)" = Running ] \
    || unavailable "isn't running or logged in"
host="$(jq -r '.Self.DNSName // empty | rtrimstr(".")' <<<"$status")"
[ -n "$host" ] || die "Tailscale didn't report this Mac's name; are MagicDNS and HTTPS on for the tailnet?"

serve_status="$(tailscale serve status --json)" || die "couldn't read tailscale serve's status (above)"
[ -n "$serve_status" ] || serve_status='{}'

# What the root of this Mac's address on the port proxies to, if anything.
proxied() {
    jq -r --arg site "$host:$1" '.Web[$site].Handlers["/"].Proxy // empty' <<<"$serve_status"
}

url() {
    if [ "$1" = 443 ]; then
        echo "https://$host"
    else
        echo "https://$host:$1"
    fi
}

if [ "$mode" = check ]; then
    for app in "${apps[@]}"; do
        port="$(field "$app" httpsPort)"
        if [ "$(proxied "$port")" != "http://127.0.0.1:$(field "$app" localPort)" ]; then
            printf 'todo\tserve %s over Tailscale on port %s: tailscale-serve apply\n' "$app" "$port"
            continue
        fi
        path=/
        path_command="$(field "$app" pathCommand)"
        if [ "$path_command" != null ]; then
            errors="$(mktemp)"
            if ! path="$(bash -euo pipefail -c "$path_command" 2>"$errors")"; then
                error="$(head -1 "$errors")"
                [ -n "$error" ] || error="couldn't get its link from: $path_command"
                printf 'todo\t%s: %s\n' "$app" "$error"
                rm "$errors"
                continue
            fi
            rm "$errors"
            [[ "$path" =~ ^/[^[:space:]]*$ ]] || die "$app's path command printed '$path', which isn't a path"
        fi
        printf 'link\t%s\t%s\n' "$app" "$(url "$port")$path"
    done
    exit 0
fi

failed=0
served=()
for app in "${apps[@]}"; do
    port="$(field "$app" httpsPort)"
    target="http://127.0.0.1:$(field "$app" localPort)"
    served+=("$port")
    current="$(proxied "$port")"
    [ "$current" != "$target" ] || continue
    if [ -n "$current" ]; then
        say "port $port proxies $current; replacing it with $app"
        if ! output="$(tailscale serve --https="$port" off 2>&1)"; then
            printf '%s\n' "$output" >&2
            say "warning: couldn't turn off port $port (above), so $app isn't served"
            failed=1
            continue
        fi
    fi
    if output="$(tailscale serve --bg --https="$port" "$target" 2>&1)"; then
        say "serving $app at $(url "$port")"
    else
        printf '%s\n' "$output" >&2
        say "warning: couldn't serve $app on port $port (above). If Serve isn't on for the tailnet, the message says how to turn it on."
        failed=1
    fi
done

for port in ${previous[@]+"${previous[@]}"}; do
    [[ " ${served[*]-} " != *" $port "* ]] || continue
    [ -n "$(proxied "$port")" ] || continue
    if output="$(tailscale serve --https="$port" off 2>&1)"; then
        say "turned off port $port, which no app uses now"
    else
        printf '%s\n' "$output" >&2
        say "warning: couldn't turn off port $port (above)"
        served+=("$port")
        failed=1
    fi
done

mkdir -p "$(dirname "$TAILSCALE_SERVE_STATE")"
printf '%s\n' ${served[@]+"${served[@]}"} | sed '/^$/d' | sort -nu >"$TAILSCALE_SERVE_STATE.new"
mv "$TAILSCALE_SERVE_STATE.new" "$TAILSCALE_SERVE_STATE"

[ "$failed" = 0 ] || die "not every app is served; fix the problems above, then run: tailscale-serve apply"
