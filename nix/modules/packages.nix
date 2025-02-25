{ hostConfig, ... }:
{
  # TODO: use Nixpkgs instead
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = hostConfig.homebrew.cleanup;
    };

    taps = [
      "snyk/tap"
    ];

    casks = [
      "alacritty"
      "font-jetbrains-mono-nerd-font"
      "ghostty"
      "karabiner-elements"
      "nikitabobko/tap/aerospace"
      "rancher"
      # TODO: we shouldn't need this - manage using home.nix
      "visual-studio-code"
      "zed"
    ];

    brews = [
      "bash-completion"
      "biome"
      "black"
      "delve"
      "ffmpegthumbnailer"
      "git-filter-repo"
      "gnu-sed"
      "gnupg"
      "go"
      "golangci-lint"
      "golangci-lint-langserver"
      "gopls"
      "hadolint"
      "minimal-racket" # TODO: `raco pkg install --auto fmt`
      "node"
      "nvm"
      "pgformatter"
      "poppler"
      "pre-commit"
      "pyenv"
      "pyright"
      "qmk/qmk/qmk"
      "ruff"
      "ruff-lsp"
      "rust-analyzer"
      "shared-mime-info"
      "snyk"
      "shellcheck"
      "sqlfluff"
      "terraform-docs"
      "typescript-language-server"
      "unar"
      "virtualenv"
      "watchman"
      "wget"
      "yamllint"
    ];
  };
}
