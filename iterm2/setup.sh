#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/com.googlecode.iterm2.plist $HOME/Library/Preferences/com.googlecode.iterm2.plist

echo "iTerm2 configured successfully"
