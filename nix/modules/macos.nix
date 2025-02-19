{ hostConfig, ... }:
{
  security.pam.enableSudoTouchIdAuth = true;

  system.defaults = {
    dock = {
      autohide = hostConfig.autohideDock;
      tilesize = 50;
      minimize-to-application = true;
      show-recents = false;
      static-only = true;
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
}
