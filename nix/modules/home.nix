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

      ".config/aerospace/aerospace.toml" = {
        source = ../../aerospace/aerospace.toml;
      };

      ".config/karabiner/karabiner.json" = {
        source = ../../karabiner-elements/karabiner.json;
      };

      ".config/nvim" = {
        source = ../../neovim/nvim;
      };

      ".zshrc" = {
        source = ../../zsh/.zshrc;
      };

      "Library/Application Support/Code/User/keybindings.json" = {
        source = ../../vscode/keybindings.json;
      };

      "Library/Application Support/Code/User/settings.json" = {
        source = ../../vscode/settings.json;
      };
    };

    activation = {
      replaceAlacrittyIcon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        $DRY_RUN_CMD /usr/bin/sudo cp -f ${../../alacritty/alacritty.icns} /Applications/Alacritty.app/Contents/Resources/alacritty.icns
        $DRY_RUN_CMD /usr/bin/sudo touch /Applications/Alacritty.app  # Force Finder to refresh the icon
      '';

      cloneZshelix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d "${config.home.homeDirectory}/Development/zshelix" ]; then
          $DRY_RUN_CMD git clone git@github.com:thomasschafer/zshelix.git \
            "${config.home.homeDirectory}/Development/zshelix"
        fi
      '';

      # NOTE: commenting out as this makes rebuilding slow
      #  installVSCodeExtensions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      #    PATH="/Applications/Visual Studio Code.app/Contents/Resources/app/bin:$PATH"
      #    $DRY_RUN_CMD ${../../vscode/install-extensions.sh}
      #  '';
    };
  };

  programs = {
    home-manager.enable = true;

    bat = {
      enable = true;
      config = {
        theme = "Catppuccin Macchiato";
      };
      themes = {
        "Catppuccin Macchiato" = {
          src = pkgs.fetchurl {
            url = "https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Macchiato.tmTheme";
            sha256 = "sha256-zL18U4AXMO8+gBH3T/HDl8e7OYjIRqUdeeb0i4V7kVI=";
          };
        };
      };
    };
  };
}
