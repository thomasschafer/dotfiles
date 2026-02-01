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
        sudo cp /etc/nixos/hardware-configuration.nix "$hw_config_dest"
        sudo chown "$(whoami)" "$hw_config_dest"
    fi

    sudo nixos-rebuild switch --flake .#"$mode"

    if [ -d /etc/nixos ]; then
        echo "Moving /etc/nixos to /etc/nixos.bak (no longer needed with flake)..."
        sudo mv /etc/nixos /etc/nixos.bak
    fi
fi


echo "Setup complete"
