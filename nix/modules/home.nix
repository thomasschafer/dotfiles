{
  config,
  pkgs,
  lib,
  ...
}:

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

      ".config/alacritty/catppuccin-macchiato.toml" = {
        source = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/catppuccin/alacritty/f6cb5a5c2b404cdaceaff193b9c52317f62c62f7/catppuccin-macchiato.toml";
          sha256 = "sha256-/Qb5kfR5N6mTMcL6l6qUdsG32wpkpESHu5qjX3GIUHw=";
        };
      };
      ".config/alacritty/alacritty.toml" = {
        source = ../../alacritty/alacritty.toml;
      };
    };

    activation = {
      replaceAlacrittyIcon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD /usr/bin/sudo cp -f ${../../alacritty/alacritty.icns} /Applications/Alacritty.app/Contents/Resources/alacritty.icns
        $DRY_RUN_CMD /usr/bin/sudo touch /Applications/Alacritty.app  # Force Finder to refresh the icon
      '';
    };
  };

  programs.home-manager.enable = true;
}
