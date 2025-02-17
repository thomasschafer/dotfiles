{ pkgs, hostConfig, ... }:
{
  environment.systemPackages = with pkgs; [
    # CLI tools
    bat
    fd
    fzf
    nixfmt-rfc-style
    nushell
    p7zip
    ripgrep
    sd
    # Temporarily build from source until https://github.com/sxyazi/yazi/issues/2308 is fixed
    # yazi
    zig
    zls

    # Haskell tooling
    ghc
    cabal-install
    stack
    haskell-language-server
    haskellPackages.hoogle

    # Applications
  ];

  # TODO: use Nixpkgs instead
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = hostConfig.homebrew.cleanup;
    };

    casks = [
      "alacritty"
      "font-jetbrains-mono-nerd-font"
      "ghostty"
      "hammerspoon"
      "karabiner-elements"
      "rectangle"
      "visual-studio-code"
      "zed"
    ];

    brews = [
      "bash-completion"
      "biome"
      "black"
      "delve"
      "deno"
      "derailed/k9s/k9s"
      "ffmpegthumbnailer"
      "git"
      "git-filter-repo"
      "gnu-sed"
      "gnupg"
      "go"
      "golangci-lint"
      "golangci-lint-langserver"
      "gopls"
      "hadolint"
      "jq"
      "kakoune"
      "lazygit"
      "llvm"
      "neovim"
      "node"
      "nvm"
      "pgformatter"
      "pipx"
      "poetry"
      "poppler"
      "pre-commit"
      "pyenv"
      "pyright"
      "qmk/qmk/qmk"
      "rbenv"
      "ruff"
      "ruff-lsp"
      "rust-analyzer"
      "shared-mime-info"
      "shellcheck"
      "sqlfluff"
      "taplo"
      "terraform-docs"
      "tmux"
      "tree"
      "typescript-language-server"
      "unar"
      "virtualenv"
      "watchman"
      "wget"
      "yamllint"
      "yarn"
      "zoxide"
      "zsh-vi-mode"
    ];
  };
}
