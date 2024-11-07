#!/bin/bash

set -e
set -o pipefail

ln -sfn $(pwd)/karabiner.json ~/.config/karabiner/karabiner.json

