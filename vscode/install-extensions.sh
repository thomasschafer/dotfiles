#!/bin/bash

set -euo pipefail

pkglist=(
catppuccin.catppuccin-vsc
eamodio.gitlens
enkia.tokyo-night
esbenp.prettier-vscode
golang.go
hashicorp.terraform
haskell.haskell
hoovercj.haskell-linter
inferrinizzard.prettier-sql-vscode
justusadam.language-haskell
matangover.mypy
ms-python.black-formatter
ms-python.debugpy
ms-python.python
ms-python.vscode-pylance
ms-toolsai.jupyter
ms-vscode-remote.remote-containers
ms-vscode.makefile-tools
redhat.vscode-yaml
rubocop.vscode-rubocop
ryuta46.multi-command
shopify.ruby-extensions-pack
shopify.ruby-lsp
sorbet.sorbet-vscode-extension
streetsidesoftware.code-spell-checker
tamasfe.even-better-toml
usernamehw.errorlens
vscodevim.vim
)

for i in ${pkglist[@]}; do
  code --install-extension $i
done
