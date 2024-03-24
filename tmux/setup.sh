#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/.tmux.conf $HOME/.tmux.conf

rm -rf ~/.tmux/plugins/tpm
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

~/.tmux/plugins/tpm/bin/install_plugins

echo "Tmux configured successfully"
