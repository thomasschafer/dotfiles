#!/bin/bash

./install-extensions.sh

ln -sfn $(pwd)/keybindings.json "$HOME/Library/Application Support/Code/User/keybindings.json"
ln -sfn $(pwd)/settings.json "$HOME/Library/Application Support/Code/User/settings.json"

echo "VSCode configuration symlinked"
