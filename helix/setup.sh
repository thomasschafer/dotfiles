#!/bin/bash

set -euo pipefail

install_helix() {
    local helix_repo_dir="$HOME/Development/helix"

    if [ -d "$helix_repo_dir" ]; then
        cd "$helix_repo_dir"
        
        local current_branch=$(git branch --show-current)
        if [ "$current_branch" != "master" ]; then
            echo "Error: expected branch master, found '$current_branch'."
            exit 1
        fi
        
        git pull origin master
    else
        git clone "git@github.com:thomasschafer/helix.git" "$helix_repo_dir"
        cd "$helix_repo_dir"
    fi

    cargo install --path helix-term --locked

    cd -
}

install_helix

echo "Helix configured successfully"
