#!/bin/bash

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

    cd -
}

install_helix

echo "Helix configured successfully"
