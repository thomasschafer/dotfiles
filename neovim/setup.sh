#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/nvim $HOME/.config/nvim

echo "Neovim configured successfully"
