{ config, pkgs, ... }:

{
  home = {
    stateVersion = "23.05";

    file = {
      ".stack/config.yaml".text = ''
        system-ghc: true
        install-ghc: false
        nix:
          enable: true
      '';

      "Library/Application Support/nushell/config.nu" = {
        source = ../../nushell/config.nu;
      };

      "Library/Application Support/lazygit/config.yml" = {
        source = ../../lazygit/config.yml;
      };

      ".config/zed/settings.json" = {
        source = ../../zed/settings.json;
      };
    };
  };

  programs.home-manager.enable = true;
}
