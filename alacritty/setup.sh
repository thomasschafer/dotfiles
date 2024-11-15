#!/bin/bash

set -e
set -o pipefail

mkdir -p $HOME/.config/alacritty
ln -sfn $(pwd)/alacritty.toml $HOME/.config/alacritty/alacritty.toml
curl -LO --output-dir $HOME/.config/alacritty https://github.com/catppuccin/alacritty/raw/main/catppuccin-macchiato.toml

echo "Alacritty configured successfully"

