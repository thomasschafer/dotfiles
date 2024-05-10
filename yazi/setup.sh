#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/yazi.toml $HOME/.config/yazi/yazi.toml

echo "Yazi configured successfully"
