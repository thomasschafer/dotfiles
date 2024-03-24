#!/bin/bash

set -e
set -o pipefail

cd homebrew
./install.sh
cd ..

# Install nerd font
curl -fL https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/DejaVuSansMono/Regular/DejaVuSansMNerdFontMono-Regular.ttf -o ~/Library/Fonts/DejaVuSansMNerdFontMono-Regular.ttf

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

# Install Haskell tools
curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh

echo "Setup complete"
