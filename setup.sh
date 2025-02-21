#!/bin/bash

set -euo pipefail

# Validate args
valid_options=("work" "personal")
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
cd nix

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install

NIX_EXEC=/nix/var/nix/profiles/default/bin/nix
$NIX_EXEC run nix-darwin -- switch --flake .#"$mode"

cd -


# Install Rust toolchain
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    . "$HOME/.cargo/env"
fi


echo "Setup complete"
