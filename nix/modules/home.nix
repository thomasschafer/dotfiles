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

    zsh = {
      enable = true;

      history = {
        size = 100000;
        save = 100000;
        path = "${config.home.homeDirectory}/.zhistory";
        extended = true;
        ignoreDups = true;
        share = true; # This enables INC_APPEND_HISTORY
      };

      initExtra = ''
        # Work-specific config
        if [[ -f $HOME/.zshrc.private ]]; then
            source $HOME/.zshrc.private
        fi

        # Treat / as a word delimiter
        WORDCHARS='*?_-.[]~=&;!#$%^(){}<>'

        # Prompt
        autoload -Uz vcs_info
        precmd() { vcs_info }
        setopt prompt_subst
        zstyle ':vcs_info:git:*' formats '(%F{#91d7e3}%b%f) '
        PROMPT='> %F{#a6da95}%1~%f ''${vcs_info_msg_0_}$ '

        # Helix keymap
        ZHM_CURSOR_NORMAL=$'\e[2 q\e]12;#b8c0e0\a'
        ZHM_CURSOR_INSERT=$'\e[2 q\e]12;#f4dbd6\a'
        ZHM_CURSOR_SELECT=$'\e[2 q\e]12;#f5a97f\a'
        source ${config.home.homeDirectory}/Development/zshelix/zshelix.plugin.zsh
      '';

      shellAliases = {
        nv = "nvim";
        c = "code";
        z = "zed";
        y = "yazi";
        s = "scooter";
        lg = "lazygit";
        ldr = "lazydocker";
        dr = "cd ${config.home.homeDirectory}/Development/dotfiles/nix/ && darwin-rebuild switch --flake .#personal && cd -";
      };

      sessionVariables = {
        EDITOR = "hx";
        VISUAL = "hx";
        PATH = lib.concatStrings [
          "${config.home.homeDirectory}/.local/bin:"
          "$PATH"
        ];
      };

      enableCompletion = true;

      envExtra = ''
        export PATH="/etc/profiles/per-user/${config.home.username}/bin:$PATH"
      '';
    };

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
