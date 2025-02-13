{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, nixpkgs }:
  let
    configuration = { pkgs, ... }: {
      # Necessary because we are using the Determinate Systems installer
      nix.enable = false;

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Set Git commit hash for darwin-version.
      system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 6;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";

      # sudo via touch ID
      security.pam.enableSudoTouchIdAuth = true;

      system.defaults = {
        dock = {
          tilesize = 50;
          minimize-to-application = true;
          show-recents = false;
        };

        screensaver = {
          askForPassword = true;
          askForPasswordDelay = 0;
        };

        screencapture.location = "~/Documents/Screenshots";

        NSGlobalDomain = {
          ApplePressAndHoldEnabled = false;
          InitialKeyRepeat = 15;
          KeyRepeat = 2;
          AppleInterfaceStyleSwitchesAutomatically = true;
        };

        menuExtraClock = {
          ShowDayOfMonth = true;
          Show24Hour = true;
        };

        ".GlobalPreferences"."com.apple.mouse.scaling" = 3.0;
      };

      system.activationScripts.postActivation.text = ''
        mkdir -p "$HOME/Documents/Screenshots"

        defaults write com.apple.keyboard.lighting KeyboardBrightness -int 0

        defaults write com.apple.systemuiserver menuExtras -array \
          "/System/Library/CoreServices/Menu Extras/Battery.menu" \
          "/System/Library/CoreServices/Menu Extras/Bluetooth.menu" \
          "/System/Library/CoreServices/Menu Extras/Clock.menu" \
          "/System/Library/CoreServices/Menu Extras/Volume.menu"
      '';
    };
  in
  {
    # Build darwin flake using:
    # $ darwin-rebuild build --flake .#simple
    # TODO: rename "simple" to hostname?
    darwinConfigurations."simple" = nix-darwin.lib.darwinSystem {
      modules = [ configuration ];
    };
  };
}
