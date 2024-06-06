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
  git pull origin master
else
  git clone "git@github.com:thomasschafer/helix.git"
  cd "$HELIX_REPO_DIR"
fi

# cargo install --path helix-term --locked
ln -sfn $PWD/runtime ~/.config/helix/runtime
cd ..

# Install utils
HX_UTILS_DIR="hx-utils"

if [ -d "$HX_UTILS_DIR" ]; then
  cd "$HX_UTILS_DIR"
  git pull origin main
else
  git clone "git@github.com:thomasschafer/hx-utils.git"
  cd "$HX_UTILS_DIR"
fi

stack install hx-utils
ln -sfn $(which hx-utils) ~/.local/bin/u

echo "Helix configured successfully"
