#!/bin/bash

set -e
set -o pipefail

mkdir -p "$(bat --config-dir)/themes"
wget -P "$(bat --config-dir)/themes" https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Macchiato.tmTheme
bat cache --build
ln -sfn $(pwd)/config $(bat --config-file)

echo "bat configured successfully"
