#!/bin/bash

ln -sfn $(pwd)/.tmux.conf $HOME/.tmux.conf

git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

echo "Tmux configured successfully"
