{
  config,
  pkgs,
  lib,
  hostConfig,
  host,
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

  hxUtils = pkgs.rustPlatform.buildRustPackage {
    pname = "hx-utils";
    version = "main";
    src = pkgs.fetchFromGitHub {
      owner = "thomasschafer";
      repo = "hx-utils";
      rev = "main";
      hash = "sha256-KpU9Mxn1Fs3VXlAMTLR1mCQizNuQKrjmePatSjth+/s=";
    };
    cargoHash = "sha256-/9FLbTyHuhEA5BfAXw99pu+482O/s604ehkk1WPC+Hk=";

    postInstall = ''
      ln -s $out/bin/hx-utils $out/bin/u
    '';
  };

  # See https://docs.snyk.io/scm-ide-and-ci-cd-integrations/snyk-ide-plugins-and-extensions/snyk-language-server
  snyk-ls = pkgs.stdenv.mkDerivation rec {
    pname = "snyk-ls";
    protocol_version = "16";
    version = "20241112.105448";

    src = pkgs.fetchurl {
      url = "https://static.snyk.io/snyk-ls/${protocol_version}/snyk-ls_${version}_darwin_${
        if pkgs.stdenv.isAarch64 then "arm64" else "amd64"
      }";
      sha256 = "sha256-WQo1UyO2kM1+U1xeN3F5UQlam3HBsKwztMV8oo59Uso=";
    };

    dontUnpack = true;

    installPhase = ''
      mkdir -p $out/bin
      cp $src $out/bin/snyk-ls
      chmod +x $out/bin/snyk-ls
    '';

    meta = with lib; {
      description = "Snyk Language Server";
      homepage = "https://github.com/snyk/snyk-ls";
      platforms = platforms.darwin;
    };
  };

  yaziFork = pkgs.rustPlatform.buildRustPackage {
    pname = "yazi";
    version = "main";
    src = pkgs.fetchFromGitHub {
      owner = "thomasschafer";
      repo = "yazi";
      rev = "main";
      hash = "sha256-kWMpFq155szLIzTutqtA/AM0bgx43HFz1K/idm+hto4=";
    };
    cargoHash = "sha256-933kOXcY9sVoRqEv9IPwcCbpf6KTsDkSquggxyOVSxc=";
  };

  catppuccinMacchiatoTheme = pkgs.fetchurl {
    url = "https://github.com/catppuccin/bat/raw/main/themes/Catppuccin%20Macchiato.tmTheme";
    sha256 = "sha256-zL18U4AXMO8+gBH3T/HDl8e7OYjIRqUdeeb0i4V7kVI=";
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

      # Aider
      ".aider.conf.yml".source = ../../aider/aider.conf.yml;

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
      ".config/helix/init.scm".source = ../../helix/init.scm;
      ".config/helix/cogs/keymaps.scm".source = ../../helix/cogs/keymaps.scm;

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

      # Scooter
      ".config/scooter/config.toml".source = ../../scooter/config.toml;
      ".config/scooter/themes/Catppuccin-Macchiato.tmTheme".source = catppuccinMacchiatoTheme;

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
      ".config/yazi/Catppuccin-macchiato.tmTheme".source = catppuccinMacchiatoTheme;

      # Zed
      ".config/zed/settings.json".source = ../../zed/settings.json;

      # Zellij
      # ".config/zellij/config.kdl" = ../../zellij/config.kdl; # TODO: uncomment

      # Zshrc
      ".zshrc".source = ../../zsh/.zshrc;
    };

    packages =
      with pkgs;
      [
        # CLI tools
        aider-chat
        deno
        fd
        fzf
        go
        # golangci-lint  # Manually installing v1 for now - see `installGolangciLint`
        golangci-lint-langserver
        gopls
        git
        hadolint
        neovim
        nixfmt-rfc-style
        nushell
        p7zip
        jq
        lazygit
      ]
      ++ lib.optionals (host == "personal") [
        (python3.withPackages (
          ps: with ps; [
            pip
            pylsp-mypy
            python-lsp-server
          ]
        ))
      ]
      ++ [
        ripgrep
        ruff
        rust-analyzer
        # scooter  # Building from source manually
        sd
        snyk-ls
        taplo
        terraform-docs
        tree
        typescript-language-server
        uv
        nodePackages.vscode-langservers-extracted
        # yazi  # Temporarily build from source until https://github.com/sxyazi/yazi/issues/2308 is fixed - see yaziFork
        zellij
        zig
        zls

        # Building from source
        hxUtils
        yaziFork

        # Haskell tooling
        ghc
        cabal-install
        stack
        haskell-language-server
        haskellPackages.hoogle

        # Scripts/tools
        (writeShellScriptBin "tmux-sessionizer" (builtins.readFile ../../tmux/tmux-sessionizer.sh))
        (writeShellScriptBin "fr" (builtins.readFile ../../tools/fr.sh))
      ];

    # TODO: replace these scripts with something more idiomatic
    activation = {
      replaceAlacrittyIcon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "/Applications/Alacritty.app/Contents/Resources/alacritty.icns" ] || ! cmp -s "${../../alacritty/alacritty.icns}" "/Applications/Alacritty.app/Contents/Resources/alacritty.icns" 2>/dev/null; then
          $DRY_RUN_CMD /usr/bin/sudo cp -f ${../../alacritty/alacritty.icns} /Applications/Alacritty.app/Contents/Resources/alacritty.icns || true
          $DRY_RUN_CMD /usr/bin/sudo touch /Applications/Alacritty.app || true  # Force Finder to refresh the icon
        fi
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

      installRacketFmt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! $DRY_RUN_CMD /opt/homebrew/bin/raco fmt --help &>/dev/null; then
          $DRY_RUN_CMD /opt/homebrew/bin/raco pkg install --auto fmt
        fi
      '';

      installGolangciLint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! command -v golangci-lint &>/dev/null || ! golangci-lint version 2>/dev/null | grep -q "1.64"; then
          $DRY_RUN_CMD ${pkgs.go}/bin/go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.64.0
        fi
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
          src = catppuccinMacchiatoTheme;
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

      profiles.default.extensions = with pkgs.vscode-extensions; [
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
        rust-lang.rust-analyzer
        saoudrizwan.claude-dev # Cline
        streetsidesoftware.code-spell-checker
        tamasfe.even-better-toml
        usernamehw.errorlens
        vscodevim.vim
      ];
    };
  };
}
