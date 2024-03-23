#!/bin/bash

set -e
set -o pipefail

mkdir -p $HOME/.hammerspoon
ln -sfn $(pwd)/init.lua $HOME/.hammerspoon/init.lua

echo "Hammerspoon configured successfully"
