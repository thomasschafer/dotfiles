#!/bin/bash

set -euo pipefail

# Validate args
valid_options=("work" "personal")
options_string=$(IFS=, ; echo "${valid_options[*]}")

if [ $# -eq 0 ]; then
    echo "Error: Please provide an argument ($options_string)"
    exit 1
fi

mode="$1"

valid=false
for option in "${valid_options[@]}"; do
    if [ "$mode" = "$option" ]; then
        valid=true
        break
    fi
done

if [ "$valid" = false ]; then
    echo "Error: Argument must be one of: $options_string"
    exit 1
fi


mkdir -p "$HOME/Development"

cd nix
./install.sh $mode
cd ..


# Install Rust toolchain
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    . "$HOME/.cargo/env"
fi


# Run other setup scripts
# TODO: delete when fully migrated to Nix
setup_scripts=$(find $(pwd) -mindepth 2 -type f -name 'setup.sh')
for script in $setup_scripts; do
	echo "Executing ${script/#$HOME/~}..."

	script_dir=$(dirname "$script")
	pushd "$script_dir" >/dev/null
	bash "$(basename "$script")" || exit $?
	popd >/dev/null
done


echo "Setup complete"
