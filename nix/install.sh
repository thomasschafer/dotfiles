#!/bin/bash

set -euo pipefail

curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
  sh -s -- install

NIX_EXEC=/nix/var/nix/profiles/default/bin/nix
$NIX_EXEC run nix-darwin -- switch --flake .#"$1"

echo "Nix configured successfully"
