#!/bin/bash

set -eo pipefail

ln -sfn "$PWD/config.nu" "$HOME/Library/Application Support/nushell/config.nu"

echo "Nushell configured successfully"
