#!/bin/bash

set -e
set -o pipefail

mkdir -p $HOME/.config/alacritty
ln -sfn $(pwd)/alacritty.toml $HOME/.config/alacritty/alacritty.toml
curl -LO --output-dir $HOME/.config/alacritty https://github.com/catppuccin/alacritty/raw/main/catppuccin-macchiato.toml

cp ./alacritty.icns /Applications/Alacritty.app/Contents/Resources/alacritty.icns
touch /Applications/Alacritty.app
killall Finder && killall Dock

echo "Alacritty configured successfully"
