#!/bin/bash

set -e
set -o pipefail

ln -sfn $PWD/config.toml $HOME/.config/helix/config.toml
ln -sfn $PWD/themes $HOME/.config/helix/themes
ln -sfn $PWD/languages.toml $HOME/.config/helix/languages.toml
ln -sfn $PWD/ignore $HOME/.config/helix/ignore

# Install fork
HELIX_REPO_DIR="helix"

if [ -d "$HELIX_REPO_DIR" ]; then
	cd "$HELIX_REPO_DIR"

	current_branch=$(git branch --show-current)
	if [ "$current_branch" != "master" ]; then
		echo "Error: expected branch master, found '$current_branch'."
		exit 1
	fi

	git pull origin master
else
	git clone "git@github.com:thomasschafer/helix.git"
	cd "$HELIX_REPO_DIR"
fi

## Install rustup + cargo if required
if ! command -v cargo &>/dev/null; then
	curl https://sh.rustup.rs -sSf | sh
	. "$HOME/.cargo/env"
fi
cargo install --path helix-term --locked

ln -sfn $PWD/runtime ~/.config/helix/runtime
cd ..

# NOTE: may need to run `rustup component add rust-analyzer` if the homebrew installation of rust-analyzer causes issues

# Install utils
HX_UTILS_DIR="hx-utils"

if [ -d "$HX_UTILS_DIR" ]; then
	cd "$HX_UTILS_DIR"

	current_branch=$(git branch --show-current)
	if [ "$current_branch" != "main" ]; then
		echo "Error: expected branch main, found '$current_branch'."
		exit 1
	fi

	git pull origin main
else
	git clone "git@github.com:thomasschafer/hx-utils.git"
	cd "$HX_UTILS_DIR"
fi

stack install hx-utils
ln -sfn $(which hx-utils) ~/.local/bin/u

ln -sfn "$(pwd)/helix" ~/Development/helix

echo "Helix configured successfully"
