#!/bin/bash

ln -sfn $(pwd)/alacritty.toml $HOME/.config/alacritty/alacritty.toml
curl -LO --output-dir ~/.config/alacritty https://github.com/catppuccin/alacritty/raw/main/catppuccin-macchiato.toml

echo "Alacritty configured successfully"

