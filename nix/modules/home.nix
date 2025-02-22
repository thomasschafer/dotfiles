{
  config,
  pkgs,
  lib,
  ...
}:

let
  ghosttyConfig = pkgs.runCommand "ghostty-config" { } ''
    ${pkgs.gnused}/bin/sed 's/[[:space:]]*##.*$//' ${../../ghostty/config.template} > $out
  '';

  helixConfig =
    pkgs.runCommand "helix-config"
      {
        nativeBuildInputs = [ pkgs.python3Packages.toml ];
      }
      ''
        cp ${../../helix/process_config.py} process_config.py
        python3 process_config.py ${../../helix/config.template.toml} > $out
      '';

  yaziOld = pkgs.rustPlatform.buildRustPackage rec {
    pname = "yazi";
    version = "0.4.2";
    src = pkgs.fetchFromGitHub {
      owner = "sxyazi";
      repo = "yazi";
      rev = "v${version}";
      hash = "sha256-2fBajVFpmgNHb90NbK59yUeaYLWR7rhQxpce9Tq1uQU=";
    };
    cargoHash = "sha256-fOq8fM7S2caxI/lLWFGidJ7ZlDD5WSR3z3w/g4zRQp4=";
  };
in
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

      # Aerospace
      ".config/aerospace/aerospace.toml".source = ../../aerospace/aerospace.toml;

      # Alacritty
      ".config/alacritty/catppuccin-macchiato.toml".source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/catppuccin/alacritty/main/catppuccin-macchiato.toml";
        sha256 = "sha256-/Qb5kfR5N6mTMcL6l6qUdsG32wpkpESHu5qjX3GIUHw=";
      };
      ".config/alacritty/alacritty.toml".source = ../../alacritty/alacritty.toml;

      # Ghostty
      ".config/ghostty/config".source = ghosttyConfig;

      # Helix
      ".config/helix/config.toml".source = helixConfig;
      ".config/helix/languages.toml".source = ../../helix/languages.toml;
      ".config/helix/ignore".source = ../../helix/ignore;
      ".config/helix/themes".source = ../../helix/themes;

      # k9s
      "Library/Application Support/k9s/config.yaml".source = ../../k9s/config.yaml;

      # Kakoune
      ".config/kak/colors/catppuccin_macchiato.kak".source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/catppuccin/kakoune/main/colors/catppuccin_macchiato.kak";
        sha256 = "sha256-VqcYzb0U5RAS1pJVO/k/V04wMm5EFAh5r4SMKega5M8=";
      };

      # Karabiner Elements
      ".config/karabiner/karabiner.json".source = ../../karabiner-elements/karabiner.json;

      # Lazygit
      "Library/Application Support/lazygit/config.yml".source = ../../lazygit/config.yml;

      # Neovim
      ".config/nvim".source = ../../neovim/nvim;

      # Nushell
      "Library/Application Support/nushell/config.nu".source = ../../nushell/config.nu;

      # VSCode
      "Library/Application Support/Code/User/keybindings.json".source = ../../vscode/keybindings.json;
      "Library/Application Support/Code/User/settings.json".source = ../../vscode/settings.json;

      # Yazi
      ".config/yazi/yazi.toml".source = ../../yazi/yazi.toml;
      ".config/yazi/keymap.toml".source = ../../yazi/keymap.toml;
      ".config/yazi/theme.toml".source = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/catppuccin/yazi/refs/heads/main/themes/macchiato/catppuccin-macchiato-blue.toml";
        sha256 = "sha256-nR48k8uaAO3oQ8GiD8mCLZU3FPc5KSL+DAvt2z5YUmY=";
      };

      # Zed
      ".config/zed/settings.json".source = ../../zed/settings.json;

      # Zshrc
      ".zshrc".source = ../../zsh/.zshrc;
    };

    packages = with pkgs; [
      yaziOld

      (writeShellScriptBin "tmux-sessionizer" (builtins.readFile ../../tmux/tmux-sessionizer.sh))
      (writeShellScriptBin "fr" (builtins.readFile ../../tools/fr.sh))
    ];

    # TODO: replace these scripts with something more idiomatic
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

      linkHelixRuntime = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ln -sfn "${config.home.homeDirectory}/Development/helix/runtime" "${config.home.homeDirectory}/.config/helix/runtime"
      '';
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

    kakoune = {
      enable = true;
      extraConfig = builtins.readFile ../../kakoune/kakrc;
    };

    k9s = {
      enable = true;

      skins = {
        catppuccin.source = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/catppuccin/k9s/refs/heads/main/dist/catppuccin-macchiato-transparent.yaml";
          sha256 = "sha256-mTMv9/6I3UVrGgRzacXMrXtWEQ6GkgQJiuLwlEg3vqY=";
        };
      };
    };

    tmux = {
      enable = true;
      plugins = with pkgs.tmuxPlugins; [
        sensible
        resurrect
      ];
      extraConfig = ''
        ${builtins.readFile ../../tmux/.tmux.conf}
        set -gu default-command
        set -g default-shell "$SHELL"
      '';
    };

    vscode = {
      enable = true;

      extensions = with pkgs.vscode-extensions; [
        catppuccin.catppuccin-vsc
        eamodio.gitlens
        enkia.tokyo-night
        esbenp.prettier-vscode
        golang.go
        hashicorp.terraform
        haskell.haskell
        justusadam.language-haskell
        matangover.mypy
        ms-python.black-formatter
        ms-python.debugpy
        ms-python.python
        ms-python.vscode-pylance
        ms-toolsai.jupyter
        ms-vscode-remote.remote-containers
        ms-vscode.makefile-tools
        redhat.vscode-yaml
        streetsidesoftware.code-spell-checker
        tamasfe.even-better-toml
        usernamehw.errorlens
        vscodevim.vim
      ];
    };
  };
}
