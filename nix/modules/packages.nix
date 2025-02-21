{ pkgs, hostConfig, ... }:
{
  # NOTE: some packages are also managed in `home.nix`
  environment.systemPackages = with pkgs; [
    # CLI tools
    fd
    fzf
    mypy
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
      "karabiner-elements"
      "nikitabobko/tap/aerospace"
      "visual-studio-code"
      "zed"
    ];

    brews = [
      "bash-completion"
      "biome"
      "black"
      "delve"
      "deno"
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
