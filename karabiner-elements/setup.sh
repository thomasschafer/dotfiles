#!/bin/bash

set -e
set -o pipefail

mkdir -p $HOME/.config/karabiner
ln -sfn $(pwd)/karabiner.json $HOME/.config/karabiner/karabiner.json

