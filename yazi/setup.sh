#!/bin/bash

set -euo pipefail

# Temporarily build from source until https://github.com/sxyazi/yazi/issues/2308 is fixed
git clone https://github.com/sxyazi/yazi.git
cd yazi
git checkout v0.4.2
cargo build --release --locked
sudo mv target/release/yazi target/release/ya /usr/local/bin/
cd ../

mkdir -p $HOME/.config/yazi
ln -sfn $(pwd)/yazi.toml $HOME/.config/yazi/yazi.toml
ln -sfn $(pwd)/keymap.toml $HOME/.config/yazi/keymap.toml
ln -sfn $(pwd)/macchiato.toml $HOME/.config/yazi/theme.toml

echo "Yazi configured successfully"
