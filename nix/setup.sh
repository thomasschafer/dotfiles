#!/bin/bash

set -e
set -o pipefail

# TODO: install via flake
cargo install --git https://github.com/oxalica/nil nil

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install

cd nix-darwin-config
nix run nix-darwin -- switch --flake .#simple

echo "Nix configured successfully"
