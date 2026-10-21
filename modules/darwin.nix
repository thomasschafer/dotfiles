{
  self,
  lib,
  hostConfig,
  ...
}:
{
  # Determinate Nix manages the daemon and /etc/nix/nix.conf, so nix-darwin's nix.* options
  # (including nix.settings and nix.gc) have no effect. Settings go in nix.custom.conf, which
  # nix.conf includes.
  nix.enable = false;

  environment.etc."nix/nix.custom.conf" = {
    text = ''
      # Collects garbage during builds when free space drops below min-free, until max-free
      # is free. Old generations are still roots; the nix-gc launchd job removes those.
      min-free = ${toString (30 * 1024 * 1024 * 1024)}
      max-free = ${toString (60 * 1024 * 1024 * 1024)}
    '';
    # The empty file the Determinate installer wrote, which nix-darwin may replace.
    knownSha256Hashes = [ "3bd68ef979a42070a44f8d82c205cfd8e8cca425d91253ec2c10a88179bb34aa" ];
  };

  # Deletes generations older than 30 days and the store paths only they used. launchd runs a
  # missed calendar job when the Mac next wakes.
  launchd.daemons.nix-gc = {
    command = "/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 30d";
    serviceConfig = {
      StartCalendarInterval = [
        {
          Weekday = 0;
          Hour = 3;
          Minute = 15;
        }
      ];
      ProcessType = "Background";
      LowPriorityIO = true;
      StandardOutPath = "/var/log/nix-gc.log";
      StandardErrorPath = "/var/log/nix-gc.log";
    };
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
  ''
  + lib.optionalString hostConfig.homebrew.pruneOldVersions ''

    if [ -x "/opt/homebrew/bin/brew" ]; then
      PATH="/opt/homebrew/bin:$PATH" \
        sudo --preserve-env=PATH --user=${hostConfig.username} --set-home env \
        brew cleanup
    fi
  '';

  # Homebrew stores tap trust per user. Declare it before `brew bundle` so
  # third-party casks managed below can be installed and upgraded unattended.
  system.activationScripts.extraActivation.text = ''
    if [ -x "/opt/homebrew/bin/brew" ]; then
      PATH="/opt/homebrew/bin:$PATH" \
        sudo --preserve-env=PATH --user=${hostConfig.username} --set-home env \
        brew trust --tap nikitabobko/tap
    fi
  '';

  homebrew = {
    enable = true;
    # Cleanup is left off here and done via `brew cleanup` in postActivation above.
    # nix-darwin implements it as `brew bundle --force-cleanup`, which deletes
    # ~/.homebrew/trust.json and then exits 1 refusing to load the aerospace cask
    # from nikitabobko/tap, aborting the rebuild. Running `brew cleanup` directly
    # prunes the same old versions and caches without disturbing trust.
    onActivation = {
      autoUpdate = true;
      upgrade = true;
      cleanup = "none";
    };

    taps = [
      "nikitabobko/tap"
    ];

    casks = [
      "font-jetbrains-mono-nerd-font"
      "ghostty"
      "karabiner-elements"
      "nikitabobko/tap/aerospace"
      "zed"
    ]
    ++ lib.optionals hostConfig.enableTailscale [ "tailscale-app" ];

    # CLI tools belong in home.nix; these stay in Homebrew because nixpkgs can't
    # replace them. minimal-racket: nixpkgs' racket-minimal doesn't support macOS.
    # zig@0.16: see zigForHerdr in home.nix.
    brews = [
      "minimal-racket"
      "zig@0.16"
    ];
  };
}
