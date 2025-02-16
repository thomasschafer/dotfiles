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
    };
  };

  programs.home-manager.enable = true;
}
