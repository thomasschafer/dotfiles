#!/bin/bash

set -e
set -o pipefail

OUT="${XDG_CONFIG_HOME:-$HOME/Library/Application Support}/k9s/skins"
mkdir -p "$OUT"
curl -L https://github.com/catppuccin/k9s/archive/main.tar.gz | tar xz -C "$OUT" --strip-components=2 k9s-main/dist

ln -sfn $(pwd)/config.yaml "$HOME/Library/Application Support/k9s/config.yaml"

echo "k9s configured successfully"
