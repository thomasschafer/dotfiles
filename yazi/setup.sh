#!/bin/bash

set -e
set -o pipefail

mkdir -p $HOME/.config/yazi
ln -sfn $(pwd)/yazi.toml $HOME/.config/yazi/yazi.toml
ln -sfn $(pwd)/keymap.toml $HOME/.config/yazi/keymap.toml
ln -sfn $(pwd)/macchiato.toml $HOME/.config/yazi/theme.toml

echo "Yazi configured successfully"
