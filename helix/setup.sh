#!/bin/bash

# TODO: move to Nix

set -euo pipefail

install_helix() {
    HELIX_REPO_DIR="$HOME/Development/helix"

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
}

install_hx_utils() {
    HX_UTILS_DIR="$HOME/Development/hx-utils"

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

    cargo install --path .

    ln -sfn "$(which hx-utils)" "$HOME/.local/bin/u"
}

install_language_servers() {
    pipx install "python-lsp-server[all]"
    pipx inject python-lsp-server pylsp-mypy
    pipx ensurepath
}

install_helix
install_hx_utils
install_language_servers

echo "Helix configured successfully"
