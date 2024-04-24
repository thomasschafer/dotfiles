#!/bin/bash

set -e
set -o pipefail

# TODO: add keybindings and extensions
ln -sfn $(pwd)/settings.json "$HOME/.config/zed/settings.json"

echo "Zed configured successfully"
