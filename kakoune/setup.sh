#!/bin/bash

set -e
set -o pipefail

mkdir -p $HOME/.config/kak
ln -sfn $(pwd)/kakrc $HOME/.config/kak/kakrc

mkdir -p ~/.config/kak/colors
curl "https://raw.githubusercontent.com/catppuccin/kakoune/main/colors/catppuccin_macchiato.kak" -o ~/.config/kak/colors/catppuccin_macchiato.kak

echo "Kakoune configured successfully"
