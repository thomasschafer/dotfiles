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

# The host's settings (see modules/host-options.nix), for deciding which steps to run.
host_config="$("$nix_exec" eval --json "$script_dir#hostConfigs.$host")"
enabled() {
    jq -e --arg option "$1" '.[$option] == true' <<<"$host_config" >/dev/null
}
bin="/etc/profiles/per-user/$USER/bin"

flake="$script_dir#$host"
if command -v darwin-rebuild &>/dev/null; then
    sudo darwin-rebuild switch --flake "$flake"
else
    sudo "$nix_exec" run nix-darwin/master#darwin-rebuild -- switch --flake "$flake"
fi

if enabled enableDependabotReview; then
    # The profile's bin directory, where `secret` is, may not be on PATH yet on a new machine.
    PATH="$bin:$PATH" "$script_dir/dependabot-review/setup-secrets"
fi

if enabled enableTodoistBackup; then
    "$bin/todoist-backup" setup
fi

if enabled enableHealthTracking; then
    "$HOME/Development/Personal/health-tracking/scripts/setup-machine.sh"
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

# Logins and setup a script can check, each with how to fix it. On a fresh machine, these are
# what's left to do by hand; README.md lists what can't be checked from here.
todo=0
to_do() {
    printf 'to do: %s\n' "$1" >&2
    todo=1
}
"$bin/gh" auth status >/dev/null 2>&1 \
    || to_do "log in to GitHub, for cloning and pushing: gh auth login"
"$HOME/.local/bin/claude" auth status --json 2>/dev/null | jq -e '.loggedIn == true' >/dev/null 2>&1 \
    || to_do "log in to Claude Code: run claude"
rclone_config="$("$bin/rclone" config file 2>/dev/null | tail -1)"
if [ -f "$rclone_config" ] && ! grep -q '^RCLONE_ENCRYPT_V0:' "$rclone_config"; then
    to_do "encrypt the rclone config, which holds its OAuth tokens in plain text: openssl rand -base64 32 | secret set rclone-config && rclone config encryption set"
fi
if enabled enableTailscale; then
    tailscale status >/dev/null 2>&1 || to_do "log in to Tailscale in its app"
fi
# Each app served over Tailscale (see modules/tailscale-serve.nix) with its link, or how to serve it.
while IFS=$'\t' read -r kind subject url; do
    case "$kind" in
        link) printf '%s: open %s on your phone\n' "$subject" "$url" ;;
        todo) to_do "$subject" ;;
        *) to_do "fix tailscale-serve check, which printed: $kind" ;;
    esac
done < <("$bin/tailscale-serve" check || printf 'todo\tfix tailscale-serve check, which failed (above)\n')
# The first switch deploys Workshop, but only warns if that fails, which agents-status reports.
if enabled enableWorkshop && "$bin/workshop" token >/dev/null 2>&1; then
    # Shows only what isn't OK, such as the Advent of Code cookie or packages, with its fix.
    # ~/.local/bin, where the model CLIs are, comes first as it does for the agent.
    doctor="$(PATH="$HOME/.local/bin:$PATH" "$bin/workshop" doctor 2>&1)" || todo=1
    problems="$(awk '/^✓/ { show = 0; next } /^[^ ]/ { show = 1 } show { print "    " $0 }' <<<"$doctor")"
    if [ -n "$problems" ]; then
        printf 'workshop doctor:\n%s\n' "$problems" >&2
    fi
fi

stopped=0
"$bin/agents-status" || stopped=1
[ "$stopped" = 0 ] && [ "$todo" = 0 ] || exit 1
