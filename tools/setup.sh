#!/bin/bash

set -euo pipefail

# Install all .sh files as executables in path, e.g. `fr.sh` can be run as `fr`
LINK_DIR="$HOME/.local/bin"
mkdir -p "$LINK_DIR"

CURRENT_SCRIPT="$(basename "$0" .sh)"

for script in $PWD/*.sh;
do
    script_name=$(basename "$script" .sh)
    if [ "$script_name" == "$CURRENT_SCRIPT" ]; then
        continue
    fi

    echo "Linking $script to $LINK_DIR/$script_name"
    ln -sfn "$script" "$LINK_DIR/$script_name"
done


# Install other tools
cargo install scooter


echo "Tools configured successfully"
