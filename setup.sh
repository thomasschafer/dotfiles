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
    # TODO: Remove --impure by copying hardware-configuration.nix into the repo
    # (e.g. hosts/nix-server/hardware-configuration.nix) and importing it relatively
    sudo nixos-rebuild switch --flake .#"$mode" --impure
fi


echo "Setup complete"
