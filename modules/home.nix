{
  config,
  pkgs,
  lib,
  host,
  hostConfig,
  ...
}:

let
  isDarwin = pkgs.stdenv.isDarwin;
  isServer = hostConfig.isServer or false;

  configHome = if isDarwin then "Library/Application Support" else ".config";

  ghosttyConfig = pkgs.runCommand "ghostty-config" { } ''
    ${pkgs.gnused}/bin/sed 's/[[:space:]]*##.*$//' ${../ghostty/config.template} > $out
  '';

  helixConfig =
    pkgs.runCommand "helix-config"
      {
        nativeBuildInputs = [ pkgs.python3Packages.toml ];
      }
      ''
        cp ${../helix/process_config.py} process_config.py
        python3 process_config.py ${../helix/config.template.toml} > $out
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

  catppuccinMacchiatoTheme = pkgs.fetchurl {
    url = "https://github.com/catppuccin/bat/raw/6810349b28055dce54076712fc05fc68da4b8ec0/themes/Catppuccin%20Macchiato.tmTheme";
    sha256 = "sha256-EQCQ9lW5cOVp2C+zeAwWF2m1m6I0wpDQA5wejEm7WgY=";
  };

  sharedFiles = {
    ".claude/CLAUDE.md".source = ../claude/CLAUDE.md;
    ".cursor/rules/coding-standards.mdc".source = ../claude/CLAUDE.md;

    ".stack/config.yaml".text = ''
      system-ghc: true
      install-ghc: false
      nix:
        enable: true
    '';

    # Helix
    ".config/helix/config.toml".source = helixConfig;
    ".config/helix/languages.toml".source = ../helix/languages.toml;
    ".config/helix/ignore".source = ../helix/ignore;
    ".config/helix/themes".source = ../helix/themes;
    ".config/helix/init.scm".source = ../helix/init.scm;
    ".config/helix/cogs/keymaps.scm".source = ../helix/cogs/keymaps.scm;

    # k9s
    "${configHome}/k9s/config.yaml".source = ../k9s/config.yaml;

    # Kakoune
    ".config/kak/colors/catppuccin_macchiato.kak".source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/catppuccin/kakoune/abb4e7c2939361825a69cf02bec9e6b782adf5cc/colors/catppuccin_macchiato.kak";
      sha256 = "sha256-VqcYzb0U5RAS1pJVO/k/V04wMm5EFAh5r4SMKega5M8=";
    };

    # Lazygit
    "${configHome}/lazygit/config.yml".source = ../lazygit/config.yml;

    # Opencode
    ".config/opencode/config.json".source = ../opencode/config.json;

    # Neovim
    ".config/nvim".source = ../neovim/nvim;

    # Nushell
    "${configHome}/nushell/config.nu".source = ../nushell/config.nu;

    # Scooter
    ".config/scooter/config.toml".source = ../scooter/config.toml;
    ".config/scooter/themes/Catppuccin-Macchiato.tmTheme".source = catppuccinMacchiatoTheme;

    # Yazi
    ".config/yazi/yazi.toml".source = ../yazi/yazi.toml;
    ".config/yazi/theme.toml".source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/catppuccin/yazi/fc69d6472d29b823c4980d23186c9c120a0ad32c/themes/macchiato/catppuccin-macchiato-blue.toml";
      sha256 = "sha256-FboUSmRYx7z+orHnf1xS4EFpJOnvalR7OeivbrJKH4s=";
    };
    ".config/yazi/Catppuccin-macchiato.tmTheme".source = catppuccinMacchiatoTheme;

    # Zshrc
    ".zshrc".source = ../zsh/.zshrc;

    # Direnv
    ".config/direnv/direnv.toml".text = ''
      hide_env_diff = true
    '';
  };

  darwinOnlyFiles = {
    # Aerospace
    ".config/aerospace/aerospace.toml".source = ../aerospace/aerospace.toml;

    # Alacritty
    ".config/alacritty/catppuccin-macchiato.toml".source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/catppuccin/alacritty/f6cb5a5c2b404cdaceaff193b9c52317f62c62f7/catppuccin-macchiato.toml";
      sha256 = "sha256-/Qb5kfR5N6mTMcL6l6qUdsG32wpkpESHu5qjX3GIUHw=";
    };
    ".config/alacritty/alacritty.toml".source = ../alacritty/alacritty.toml;

    # Ghostty
    ".config/ghostty/config".source = ghosttyConfig;

    # Karabiner Elements
    ".config/karabiner/karabiner.json".source = ../karabiner-elements/karabiner.json;

    # VSCode
    "${configHome}/Code/User/keybindings.json".source = ../vscode/keybindings.json;
    "${configHome}/Code/User/settings.json".source = ../vscode/settings.json;

    # Zed
    ".config/zed/settings.json".source = ../zed/settings.json;
  };
in
{
  home = {
    stateVersion = "23.05";

    file = sharedFiles // (if isDarwin && !isServer then darwinOnlyFiles else { });

    packages =
      with pkgs;
      [
        # CLI tools
        biome
        deno
        direnv
        fd
        fzf
        go
        # golangci-lint  # Manually installing v1 for now - see `installGolangciLint`
        golangci-lint-langserver
        gopls
        git
        hadolint
        jless
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
        cargo
        rustc
        rust-analyzer
        # scooter  # Building from source manually
        sd
        taplo
        terraform-docs
        tree
        typescript-language-server
        nodePackages.vscode-langservers-extracted
        yazi
        zellij
        zig
        zls

        # Building from source
        hxUtils

        # Haskell tooling
        ghc
        cabal-install
        stack
        haskell-language-server
        haskellPackages.hoogle

        # Scripts/tools
        (writeShellScriptBin "tmux-sessionizer" (builtins.readFile ../tmux/tmux-sessionizer.sh))
        (writeShellScriptBin "fr" (builtins.readFile ../tools/fr.sh))
      ];

    activation = {
      installHelix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        helix_dir="${config.home.homeDirectory}/Development/helix"
        if [ ! -d "$helix_dir" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/helix.git "$helix_dir"
        fi
        if [ ! -x "${config.home.homeDirectory}/.cargo/bin/hx" ]; then
          cd "$helix_dir"
          export PATH="${pkgs.stdenv.cc}/bin:${pkgs.git}/bin:$PATH"
          export CC="${pkgs.stdenv.cc}/bin/cc"
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install --path helix-term --locked
        fi
      '';

      linkHelixRuntime = lib.hm.dag.entryAfter [ "installHelix" ] ''
        ln -sfn "${config.home.homeDirectory}/Development/helix/runtime" "${config.home.homeDirectory}/.config/helix/runtime"
      '';

      installClaudeCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${config.home.homeDirectory}/.local/bin/claude" ]; then
          export PATH="${pkgs.curl}/bin:${pkgs.perl}/bin:$PATH"
          install_script=$(${pkgs.coreutils}/bin/mktemp)
          ${pkgs.curl}/bin/curl -fsSL https://claude.ai/install.sh -o "$install_script"
          $DRY_RUN_CMD ${pkgs.bash}/bin/bash "$install_script"
          ${pkgs.coreutils}/bin/rm -f "$install_script"
        fi
      '';

      cloneZshelix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d "${config.home.homeDirectory}/Development/zshelix" ]; then
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/zshelix.git \
            "${config.home.homeDirectory}/Development/zshelix"
        fi
      '';
    }
    // lib.optionalAttrs (isDarwin && !isServer) {
      replaceAlacrittyIcon = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -f "/Applications/Alacritty.app/Contents/Resources/alacritty.icns" ] || ! cmp -s "${../alacritty/alacritty.icns}" "/Applications/Alacritty.app/Contents/Resources/alacritty.icns" 2>/dev/null; then
          $DRY_RUN_CMD /usr/bin/sudo cp -f ${../alacritty/alacritty.icns} /Applications/Alacritty.app/Contents/Resources/alacritty.icns || true
          $DRY_RUN_CMD /usr/bin/sudo touch /Applications/Alacritty.app || true
        fi
      '';

      # TODO: currently relies on raco from homebrew, should move to platform-agnostic setup
      installRacketFmt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! $DRY_RUN_CMD /opt/homebrew/bin/raco fmt --help &>/dev/null; then
          $DRY_RUN_CMD /opt/homebrew/bin/raco pkg install --auto fmt
        fi
      '';

      installGolangciLint = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! command -v golangci-lint &>/dev/null || ! golangci-lint version 2>/dev/null | grep -q "1.64"; then
          export CC="/usr/bin/clang"
          export CXX="/usr/bin/clang++"
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
      extraConfig = builtins.readFile ../kakoune/kakrc;
    };

    k9s = {
      enable = true;

      skins = {
        catppuccin.source = pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/catppuccin/k9s/fdbec82284744a1fc2eb3e2d24cb92ef87ffb8b4/dist/catppuccin-macchiato-transparent.yaml";
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
        ${builtins.readFile ../tmux/tmux.conf}
        set -gu default-command
        set -g default-shell "$SHELL"
      '';
    };

    vscode = lib.mkIf (isDarwin && !isServer) {
      enable = true;

      profiles.default.extensions = with pkgs.vscode-extensions; [
        catppuccin.catppuccin-vsc
        # eamodio.gitlens  # Temporarily disabled - build failing in nixpkgs
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
        ms-vscode.makefile-tools
        redhat.vscode-yaml
        rust-lang.rust-analyzer
        streetsidesoftware.code-spell-checker
        tamasfe.even-better-toml
        usernamehw.errorlens
        vscodevim.vim
      ];
    };
  };
}
