{
  self,
  pkgs,
  lib,
  hostConfig,
  host,
  ...
}:
{
  nix = {
    # Necessary because we are using the Determinate Systems installer
    enable = false;

    settings.experimental-features = "nix-command flakes";

    # Fix for https://github.com/NixOS/nix/issues/2982
    nixPath = [
      "nixpkgs=${pkgs.path}"
      "/nix/var/nix/profiles/per-user/root/channels"
    ];
  };

  # Set Git commit hash for darwin-version
  system.configurationRevision = self.rev or self.dirtyRev or null;

  # Used for backwards compatibility, please read the changelog before changing.
  # $ darwin-rebuild changelog
  system.stateVersion = 6;

  # Required for user-specific options like Homebrew and system defaults
  system.primaryUser = hostConfig.username;

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
  };

  security.pam.services.sudo_local.touchIdAuth = true;

  system.defaults = {
    dock = {
      autohide = hostConfig.autohideDock;
      tilesize = 50;
      minimize-to-application = true;
      show-recents = false;
      static-only = true;
      expose-group-apps = true;
    };

    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };

    screencapture.location = "~/Screenshots";

    NSGlobalDomain = {
      ApplePressAndHoldEnabled = false;
      InitialKeyRepeat = 15;
      KeyRepeat = 2;
      AppleInterfaceStyle = "Dark";
    };

    menuExtraClock = {
      ShowDayOfMonth = true;
      Show24Hour = true;
    };

    ".GlobalPreferences"."com.apple.mouse.scaling" = 3.0;
  };

  system.activationScripts.postActivation.text = ''
    mkdir -p "$HOME/Screenshots"

    defaults write com.apple.keyboard.lighting KeyboardBrightness -int 0

    defaults write com.apple.systemuiserver menuExtras -array \
      "/System/Library/CoreServices/Menu Extras/Battery.menu" \
      "/System/Library/CoreServices/Menu Extras/Bluetooth.menu" \
      "/System/Library/CoreServices/Menu Extras/Clock.menu" \
      "/System/Library/CoreServices/Menu Extras/Volume.menu"
  '';

  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup = hostConfig.homebrew.cleanup;
    };

    taps = [
      "nikitabobko/tap"
      "snyk/tap"
      "sst/tap"
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
      "uv"
      "virtualenv"
      "watchman"
      "wget"
      "yamllint"
    ]
    ++ lib.optionals (host == "work") [ "python" ];
  };
}
