#!/bin/bash

set -e
set -o pipefail

[ -f $HOME/.zshrc ] && mv $HOME/.zshrc $HOME/.zshrc.bak
ln -sfn $(pwd)/.zshrc $HOME/.zshrc

git clone git@github.com:thomasschafer/zshelix.git $HOME/Development/zshelix

echo "Zsh configured successfully"
