#!/bin/bash

set -e
set -o pipefail

cd homebrew
./install.sh
cd ..

mkdir -p "$HOME/Development"

setup_scripts=$(find $(pwd) -mindepth 2 -type f -name 'setup.sh')

for script in $setup_scripts; do
	echo "Executing ${script/#$HOME/~}..."

	script_dir=$(dirname "$script")
	# Change to the directory where the script is located
	pushd "$script_dir" >/dev/null
	# Execute the script
	bash "$(basename "$script")" || exit $?
	# Return to the previous directory
	popd >/dev/null
done

echo "Setup complete"
