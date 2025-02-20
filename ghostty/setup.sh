#!/bin/bash

set -euo pipefail

mkdir -p $HOME/.config/ghostty

# Strip end-of-line comments starting with ##
sed 's/[[:space:]]*##.*$//' config.template > config

ln -sfn $(PWD)/config $HOME/.config/ghostty/config

