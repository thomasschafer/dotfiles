#!/bin/bash

set -eo pipefail

mkdir -p "$HOME/Library/Application Support/nushell"
ln -sfn "$PWD/config.nu" "$HOME/Library/Application Support/nushell/config.nu"

echo "Nushell configured successfully"
