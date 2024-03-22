#!/bin/bash

set -e
set -o pipefail

mkdir -p "$HOME/Library/Application Support/Rectangle/"
ln -sfn $(pwd)/config.json "$HOME/Library/Application Support/Rectangle/RectangleConfig.json"

echo "Rectangle configured successfully"
