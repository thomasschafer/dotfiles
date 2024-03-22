#!/bin/bash

set -e
set -o pipefail

mkdir -p "$HOME/Library/Application Support/lazygit"
ln -sfn $(pwd)/config.yml "$HOME/Library/Application Support/lazygit/config.yml"

echo "Lazygit configured successfully"
