#!/bin/bash

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

xargs brew install < leaves.txt
xargs brew install --cask < cask.txt

