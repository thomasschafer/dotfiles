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
