#!/bin/bash

set -e
set -o pipefail

cd nix
./install.sh
cd ..

mkdir -p "$HOME/Development"

install_rust() {
    if ! command -v cargo &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        . "$HOME/.cargo/env"
    fi
}
install_rust

setup_scripts=$(find $(pwd) -mindepth 2 -type f -name 'setup.sh')
for script in $setup_scripts; do
	echo "Executing ${script/#$HOME/~}..."

	script_dir=$(dirname "$script")
	pushd "$script_dir" >/dev/null
	bash "$(basename "$script")" || exit $?
	popd >/dev/null
done

echo "Setup complete"
