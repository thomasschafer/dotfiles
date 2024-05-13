#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/config.toml $HOME/.config/helix/config.toml
ln -sfn $(pwd)/themes $HOME/.config/helix/themes
ln -sfn $(pwd)/languages.toml $HOME/.config/helix/languages.toml
ln -sfn $(pwd)/ignore $HOME/.config/helix/ignore

echo "Helix configured successfully"
