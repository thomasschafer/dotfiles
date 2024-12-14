#!/bin/bash

set -e
set -o pipefail

# TODO: download Ghostty here - maybe just use brew when public

mkdir -p $HOME/.config/ghostty
ln -sfn $(PWD)/config $HOME/.config/ghostty/config
# ~/.config/ghostty/config

