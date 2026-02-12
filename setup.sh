#!/usr/bin/env bash

set -euo pipefail

# Validate args
valid_options=("work" "personal" "nix-server")
options_string=$(IFS=, ; echo "${valid_options[*]}")

if [ $# -eq 0 ]; then
    echo "Error: Please provide an argument ($options_string)"
    exit 1
fi

mode="$1"

valid=false
for option in "${valid_options[@]}"; do
    if [ "$mode" = "$option" ]; then
        valid=true
        break
    fi
done

if [ "$valid" = false ]; then
    echo "Error: Argument must be one of: $options_string"
    exit 1
fi


mkdir -p "$HOME/Development"


# Nix
if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: Install Nix using Determinate Systems installer, then run nix-darwin
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
      sh -s -- install

    nix_exec=/nix/var/nix/profiles/default/bin/nix
    $nix_exec run nix-darwin -- switch --flake .#"$mode"
else
    # NixOS: Nix is already installed, just rebuild
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    hw_config_dest="$script_dir/modules/hosts/$mode/hardware-configuration.nix"

    if [ ! -f "$hw_config_dest" ]; then
        echo "Copying hardware-configuration.nix to repo..."
        mkdir -p "$(dirname "$hw_config_dest")"
        cp /etc/nixos/hardware-configuration.nix "$hw_config_dest"
    fi

    # Get the configured username from host config
    host_config="$script_dir/modules/hosts/$mode/default.nix"
    username=$(grep 'username' "$host_config" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')

    if [ -z "$username" ]; then
        echo "Error: Could not extract username from $host_config"
        exit 1
    fi

    enable_tailscale=$(grep 'enableTailscale' "$host_config" | head -1 | sed 's/.*= *\([a-z]*\).*/\1/')

    run_privileged() {
        if [ "$(id -u)" -eq 0 ]; then
            "$@"
        else
            sudo "$@"
        fi
    }

    get_tailscale_ip() {
        local retries=60
        local delay=2
        local i

        if ! command -v tailscale &>/dev/null; then
            return 1
        fi

        for ((i=1; i<=retries; i++)); do
            if tailscale status &>/dev/null; then
                local ts_ip
                ts_ip=$(tailscale ip -4 2>/dev/null || true)
                if [ -n "$ts_ip" ]; then
                    printf '%s' "$ts_ip"
                    return 0
                fi
            fi
            sleep "$delay"
        done

        return 1
    }

    if [ "$enable_tailscale" = "true" ] && [ ! -f /etc/tailscale/authkey ]; then
        ts_authkey="${TAILSCALE_AUTHKEY:-}"
        if [ -z "$ts_authkey" ]; then
            if [ -t 0 ]; then
                echo ""
                echo "Tailscale is enabled but no auth key found."
                echo "Generate a one-time auth key at: Tailscale admin console → Settings → Keys"
                read -rp "Enter Tailscale auth key: " ts_authkey
            else
                echo "Error: Tailscale auth key missing. Set TAILSCALE_AUTHKEY."
                exit 1
            fi
        fi
        if [ -z "$ts_authkey" ]; then
            echo "Error: Tailscale auth key cannot be empty"
            exit 1
        fi
        run_privileged mkdir -p /etc/tailscale
        printf '%s\n' "$ts_authkey" | run_privileged tee /etc/tailscale/authkey > /dev/null
        run_privileged chmod 600 /etc/tailscale/authkey
    fi

    if [ "$(id -u)" -eq 0 ]; then
        # Running as root (first-time setup)
        nixos-rebuild switch --flake .#"$mode"

        if [ -d /etc/nixos ]; then
            echo "Moving /etc/nixos to /etc/nixos.bak (no longer needed with flake)..."
            [ -e /etc/nixos.bak ] && rm -rf /etc/nixos.bak
            mv /etc/nixos /etc/nixos.bak
        fi

        echo ""
        echo "=========================================="
        echo "NixOS configured. User '$username' created."
        echo ""
        echo "Set a password for sudo access:"
        passwd "$username"

        if [ "$enable_tailscale" = "true" ]; then
            ts_ip=$(get_tailscale_ip) || {
                echo ""
                echo "Error: Tailscale is enabled but not healthy after rebuild."
                echo "Check: systemctl status tailscaled && tailscale status"
                echo "Do not close this session until Tailscale is online."
                exit 1
            }
            echo ""
            echo "Tailscale IP: $ts_ip"
            echo "Use this for all future SSH connections:"
            echo "  ssh $username@$ts_ip"
        else
            echo ""
            echo "You can now SSH in as the non-root user:"
            echo "  ssh $username@<server-ip>"
        fi
        echo "=========================================="
        echo "Setup complete!"
    else
        # Running as non-root user (updates)
        sudo nixos-rebuild switch --flake .#"$mode"

        if [ -d /etc/nixos ]; then
            echo "Moving /etc/nixos to /etc/nixos.bak (no longer needed with flake)..."
            [ -e /etc/nixos.bak ] && sudo rm -rf /etc/nixos.bak
            sudo mv /etc/nixos /etc/nixos.bak
        fi

        if [ "$enable_tailscale" = "true" ]; then
            ts_ip=$(get_tailscale_ip) || {
                echo ""
                echo "Error: Tailscale is enabled but not healthy after rebuild."
                echo "Check: systemctl status tailscaled && tailscale status"
                echo "Do not close this session until Tailscale is online."
                exit 1
            }
            echo ""
            echo "Tailscale IP: $ts_ip"
            echo "Use this for all future SSH connections:"
            echo "  ssh $username@$ts_ip"
        fi

        echo "Setup complete"
    fi
fi
