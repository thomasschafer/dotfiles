#!/bin/bash

set -e
set -o pipefail

NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

touch $HOME/.zprofile
echo >> $HOME/.zprofile
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"

brew tap homebrew/cask-fonts

xargs brew install < leaves.txt
xargs brew install --cask < cask.txt

echo "Homebrew configured successfully"
