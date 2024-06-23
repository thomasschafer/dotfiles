#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/yazi.toml $HOME/.config/yazi/yazi.toml
ln -sfn $(pwd)/keymap.toml $HOME/.config/yazi/keymap.toml

echo "Yazi configured successfully"
