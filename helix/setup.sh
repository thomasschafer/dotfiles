#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/config.toml $HOME/.config/helix/config.toml

echo "Helix configured successfully"
