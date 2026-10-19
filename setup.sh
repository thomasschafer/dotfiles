#!/usr/bin/env bash
# Installs Nix if needed, then switches to the nix-darwin configuration for the given
# host. Safe to re-run; `dp` runs it after the first install.

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hosts_dir="$script_dir/modules/hosts"
host_dirs=("$hosts_dir"/*/)
host_dirs=("${host_dirs[@]%/}")
available_hosts=$(IFS=, ; echo "${host_dirs[*]##*/}")

if [ $# -ne 1 ]; then
    echo "Usage: $0 <host> (one of: $available_hosts)" >&2
    exit 1
fi

host="$1"

if [ ! -d "$hosts_dir/$host" ]; then
    echo "Error: unknown host '$host' (one of: $available_hosts)" >&2
    exit 1
fi

if [ "$(uname)" != "Darwin" ]; then
    echo "Error: only macOS is supported" >&2
    exit 1
fi

mkdir -p "$HOME/Development/Personal"

nix_exec=/nix/var/nix/profiles/default/bin/nix
if [ ! -x "$nix_exec" ]; then
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
      sh -s -- install
fi

flake="$script_dir#$host"
if command -v darwin-rebuild &>/dev/null; then
    sudo darwin-rebuild switch --flake "$flake"
else
    sudo "$nix_exec" run nix-darwin/master#darwin-rebuild -- switch --flake "$flake"
fi

if [ "$("$nix_exec" eval --json "$script_dir#hostConfigs.$host.enableDependabotReview")" = true ]; then
    "$script_dir/dependabot-review/setup-secrets"
fi

if [ "$("$nix_exec" eval --json "$script_dir#hostConfigs.$host.enableTodoistBackup")" = true ]; then
    "/etc/profiles/per-user/$USER/bin/todoist-backup" setup
fi

if [ "$("$nix_exec" eval --json "$script_dir#hostConfigs.$host.enableHealthTracking")" = true ]; then
    "$HOME/Development/Personal/health-tracking/scripts/setup-machine.sh"
fi

if [ "$("$nix_exec" eval --json "$script_dir#hostConfigs.$host.enableWorkshop")" = true ]; then
    # Built by the Workshop agent on its first run, so it may not be there yet.
    workshop="$HOME/Development/Personal/workshop/target/debug/workshop"
    if [ -x "$workshop" ]; then
        url="$("$workshop" token --tailscale | grep -o 'https://[^ ]*token=[^ ]*')"
        printf '\nworkshop: open %s on your phone\n' "$url"
    else
        printf '\nworkshop: still building; the link will be in ~/.local/state/workshop/dev.log\n'
    fi
fi

# Uninstalling a formula leaves its `brew services` plist behind, so launchd keeps trying to
# start a program that no longer exists. Warns about any such plist rather than removing it.
for plist in "$HOME"/Library/LaunchAgents/homebrew.mxcl.*.plist /Library/LaunchDaemons/homebrew.mxcl.*.plist; do
    [ -e "$plist" ] || continue
    label="$(basename "$plist" .plist)"
    program="$(plutil -extract ProgramArguments.0 raw "$plist" 2>/dev/null \
        || plutil -extract Program raw "$plist" 2>/dev/null || true)"
    if [ -z "$program" ]; then
        printf 'warning: could not read the program %s runs\n' "$plist" >&2
    elif [ ! -x "$program" ]; then
        case "$plist" in
            /Library/*) domain=system sudo='sudo ' ;;
            *) domain="gui/$(id -u)" sudo='' ;;
        esac
        printf 'warning: %s runs %s, which is not installed; to remove it:\n' "$plist" "$program" >&2
        printf '    %slaunchctl bootout %s/%s; %srm %s\n' "$sudo" "$domain" "$label" "$sudo" "$plist" >&2
    fi
done

# Reports on each agent that should keep running, so one that has stopped doesn't go unnoticed.
username="$("$nix_exec" eval --raw "$script_dir#hostConfigs.$host.username")"
# One line per agent: its name, launchd label and log file.
# shellcheck disable=SC2016 # Nix, not shell, interpolation
list_agents='agents:
  let
    kept = builtins.filter (name: agents.${name}.enable && agents.${name}.config.KeepAlive != null)
      (builtins.attrNames agents);
    line = name: with agents.${name}.config; "${name}\t${Label}\t${StandardOutPath}\n";
  in
  builtins.concatStringsSep "" (map line kept)'
agents="$("$nix_exec" eval --raw "$script_dir#darwinConfigurations.$host.config.home-manager.users.$username.launchd.agents" --apply "$list_agents")"
stopped=0
home_dir="~"
while IFS=$'\t' read -r name label log; do
    [ -n "$name" ] || continue
    info="$(launchctl print "gui/$(id -u)/$label" 2>/dev/null || true)"
    if grep -q '^\s*state = running' <<<"$info"; then
        printf '%s: running · log %s\n' "$name" "${log/#"$HOME"/$home_dir}"
    else
        stopped=1
        exit_code="$(grep -m1 'last exit code' <<<"$info" | sed 's/.*= //' || true)"
        printf '%s: not running (last exit code %s); the end of %s:\n' "$name" "${exit_code:-unknown}" "${log/#"$HOME"/$home_dir}" >&2
        tail -n 10 "$log" 2>/dev/null | sed 's/^/    /' >&2 || true
    fi
done <<<"$agents"
[ "$stopped" = 0 ] || exit 1
