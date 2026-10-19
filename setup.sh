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
