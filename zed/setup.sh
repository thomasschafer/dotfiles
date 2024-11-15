#!/bin/bash

set -e
set -o pipefail

mkdir -p $HOME/.config/zed
ln -sfn $(pwd)/settings.json $HOME/.config/zed/settings.json

echo "Zed configured successfully"
