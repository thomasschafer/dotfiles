#!/bin/bash

set -euo pipefail

mkdir -p "$HOME/Development"

cd nix
./install.sh
cd ..

# Install Rust toolchain
if ! command -v cargo &>/dev/null; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
    . "$HOME/.cargo/env"
fi

setup_scripts=$(find $(pwd) -mindepth 2 -type f -name 'setup.sh')
for script in $setup_scripts; do
	echo "Executing ${script/#$HOME/~}..."

	script_dir=$(dirname "$script")
	pushd "$script_dir" >/dev/null
	bash "$(basename "$script")" || exit $?
	popd >/dev/null
done

echo "Setup complete"
