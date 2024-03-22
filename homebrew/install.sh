#!/bin/bash

set -e
set -o pipefail

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

touch ~/.zprofile
(echo; echo 'eval "$(/usr/local/bin/brew shellenv)"') >> ~/.zprofile
eval "$(/usr/local/bin/brew shellenv)"

xargs brew install < leaves.txt
xargs brew install --cask < cask.txt

echo "Homebrew configured successfully"
