{
  hostConfig,
  host,
  lib,
  ...
}:
{
  # TODO: use Nixpkgs instead
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = hostConfig.homebrew.cleanup;
    };

    taps = [
      "nikitabobko/tap"
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

    # TODO: move more of these to home.nix
    brews = [
      "bash-completion"
      "biome"
      "black"
      "delve"
      "ffmpegthumbnailer"
      "git-filter-repo"
      "gnu-sed"
      "gnupg"
      "minimal-racket"
      "node"
      "nvm"
      "sst/tap/opencode"
      "pgformatter"
      "poppler"
      "pre-commit"
      "pyenv"
      "pyright"
      "qmk/qmk/qmk"
      "shared-mime-info"
      "shellcheck"
      "snyk"
      "sqlfluff"
      "unar"
      "virtualenv"
      "watchman"
      "wget"
      "yamllint"
    ] ++ lib.optionals (host == "work") [ "python" ];
  };
}
