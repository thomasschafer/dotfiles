#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/.tmux.conf $HOME/.tmux.conf

rm -rf $HOME/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm $HOME/.tmux/plugins/tpm

$HOME/.tmux/plugins/tpm/bin/install_plugins

ln -sfn "$(pwd)/tmux-sessionizer.sh" $HOME/.local/bin/tmux-sessionizer

echo "Tmux configured successfully"
