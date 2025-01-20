#!/bin/bash

set -e
set -o pipefail

HELIX_CONFIG_DIR="$HOME/.config/helix"
HELIX_REPO_DIR="$HOME/Development/helix"
HX_UTILS_DIR="$HOME/Development/hx-utils"

if [ ! -d env ]; then
    python3 -m venv env
fi
./process_config.sh --install

mkdir -p "$HELIX_CONFIG_DIR"
ln -sfn "$PWD/config.toml" "$HELIX_CONFIG_DIR/config.toml"
ln -sfn "$PWD/themes" "$HELIX_CONFIG_DIR/themes"
ln -sfn "$PWD/languages.toml" "$HELIX_CONFIG_DIR/languages.toml"
ln -sfn "$PWD/ignore" "$HELIX_CONFIG_DIR/ignore"

install_helix() {
    if [ -d "$HELIX_REPO_DIR" ]; then
        cd "$HELIX_REPO_DIR"
        
        local current_branch
        current_branch=$(git branch --show-current)
        if [ "$current_branch" != "master" ]; then
            echo "Error: expected branch master, found '$current_branch'."
            exit 1
        fi
        
        git pull origin master
    else
        git clone "git@github.com:thomasschafer/helix.git" "$HELIX_REPO_DIR"
        cd "$HELIX_REPO_DIR"
    fi

    cargo install --path helix-term --locked
    ln -sfn "$PWD/runtime" "$HELIX_CONFIG_DIR/runtime"
}

install_rust() {
    if ! command -v cargo &>/dev/null; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
        . "$HOME/.cargo/env"
    fi
}

install_hx_utils() {
    if [ -d "$HX_UTILS_DIR" ]; then
        cd "$HX_UTILS_DIR"
        
        local current_branch
        current_branch=$(git branch --show-current)
        if [ "$current_branch" != "main" ]; then
            echo "Error: expected branch main, found '$current_branch'."
            exit 1
        fi
        
        git pull origin main
    else
        git clone "git@github.com:thomasschafer/hx-utils.git" "$HX_UTILS_DIR"
        cd "$HX_UTILS_DIR"
    fi

    stack install hx-utils
    ln -sfn "$(which hx-utils)" "$HOME/.local/bin/u"
}

install_rust
install_helix
install_hx_utils

pipx install "python-lsp-server[all]"
pipx inject python-lsp-server pylsp-mypy

echo "Helix configured successfully"
