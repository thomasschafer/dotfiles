#!/bin/bash

set -e
set -o pipefail

[ -f $HOME/.zshrc ] && mv $HOME/.zshrc $HOME/.zshrc.bak
ln -sfn $(pwd)/.zshrc $HOME/.zshrc

echo "Zsh configured successfully"
