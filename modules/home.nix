{
  config,
  pkgs,
  lib,
  hostConfig,
  ...
}:

let
  configHome = "Library/Application Support";

  ghosttyConfig =
    pkgs.runCommand "ghostty-config"
      {
        nativeBuildInputs = [ pkgs.gnused ];
      }
      ''
        ${pkgs.bash}/bin/bash ${../ghostty/build-config.sh} ${../ghostty/config.template} > $out
      '';

  # Shell snippet to set up CC, SDKROOT, and PATH for cargo builds.
  # extraPathPrefix: colon-separated paths to prepend before the common entries.
  cargoBuildEnv =
    extraPathPrefix:
    let
      prefix = if extraPathPrefix != "" then "${extraPathPrefix}:" else "";
    in
    ''
      export PATH="${prefix}${pkgs.git}/bin:/usr/bin:$PATH"
      export CC="/usr/bin/cc"
      export SDKROOT="$("/usr/bin/xcrun" --sdk macosx --show-sdk-path)"
    '';

  # herdr's vendored libghostty-vt needs an exact Zig toolchain version (see
  # crates/ghostty-vt/build.rs in herdr). nixpkgs' Zig can't link against the
  # macOS SDK outside the Nix sandbox, so use Homebrew's versioned formula,
  # matching the ZIG export in zsh/.zshrc.
  zigForHerdr = "/opt/homebrew/opt/zig@0.16/bin/zig";

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

  files = {
    ".claude/CLAUDE.md".source = ../agents/shared.md;
    ".codex/AGENTS.md".source = ../agents/shared.md;
    ".claude/skills/review-loop".source = ../skills/review-loop;
    ".codex/skills/review-loop".source = ../skills/review-loop;
    ".claude/keybindings.json".source = ../claude/keybindings.json;
    ".stack/config.yaml".text = ''
      system-ghc: true
      install-ghc: false
      nix:
        enable: true
    '';

    # Atuin
    ".config/atuin/config.toml".source = ../atuin/config.toml;

    # Biome
    ".config/biome/biome.json".source = ../biome/biome.json;

    # Helix
    ".config/helix/config.toml".source = helixConfig;
    ".config/helix/languages.toml".text =
      builtins.replaceStrings [ "\${HOME_DIR}" ] [ config.home.homeDirectory ]
        (builtins.readFile ../helix/languages.toml);
    ".config/helix/ignore".source = ../helix/ignore;
    ".config/helix/themes".source = ../helix/themes;
    ".config/helix/init.scm".source = ../helix/init.scm;
    ".config/helix/cogs/keymaps.scm".source = ../helix/cogs/keymaps.scm;

    # Herdr
    ".config/herdr/config.toml".source = ../herdr/config.toml;
    ".config/herdr/plugins/config/thomasschafer.herdr-kiosk/config.toml".source =
      ../herdr/config/thomasschafer.herdr-kiosk/config.toml;

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
    ".config/opencode/tui.json".source = ../opencode/tui.json;

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

    # npm globals: keep CLI self-updates in ~/.local (dotfiles-managed path precedence)
    ".npmrc".text = ''
      prefix=${config.home.homeDirectory}/.local
    '';

    # Direnv
    ".config/direnv/direnv.toml".text = ''
      hide_env_diff = true
    '';

    # Aerospace
    # Scripts keep their executable bit from git
    ".config/aerospace" = {
      source = ../aerospace;
      recursive = true;
    };

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
  imports = lib.optionals hostConfig.enableDependabotReview [
    ../dependabot-review/nix/home.nix
  ];

  home = {
    stateVersion = "23.05";

    extraActivationPath = [
      pkgs.coreutils
      pkgs.findutils
    ];

    file = files;

    packages =
      with pkgs;
      [
        atuin
        biome
        delta
        deno
        direnv
        fd
        fzf
        go
        # golangci-lint  # Manually installing v1 for now - see `installGolangciLint`
        golangci-lint-langserver
        gopls
        gh
        git
        hadolint
        jless
        neovim
        nixfmt
        nushell
        p7zip
        jq
        lazygit
        mise
      ]
      ++ lib.optionals hostConfig.enablePython [
        (python314.withPackages (
          ps: with ps; [
            pip
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
        vscode-langservers-extracted
        yazi
        zellij
        zig
        zls
      ]
      ++ [
        # Building from source
        hxUtils

        # Haskell tooling
        ghc
        cabal-install
        stack
        haskell-language-server
        haskellPackages.hoogle

        # Scripts/tools
        (writeShellScriptBin "fr" (builtins.readFile ../tools/fr.sh))
        (writeShellScriptBin "golangci-lint-wrapper" (builtins.readFile ../tools/golangci-lint-wrapper.sh))
        (writeShellScriptBin "mux-new-window" (builtins.readFile ../tools/mux-new-window.sh))
        (writeShellScriptBin "mux-send-keys" (builtins.readFile ../tools/mux-send-keys.sh))
      ];

    activation = {
      # Home Manager's LaunchAgents activation uses GNU-only `readlink -m`.
      # Ensure it resolves Nix's GNU tools rather than macOS's BSD utilities.
      ensureGnuLaunchdTools = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
        export PATH="${pkgs.coreutils}/bin:${pkgs.findutils}/bin:$PATH"
        hash -r
      '';

      installTy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${config.home.homeDirectory}/.local/bin/ty" ]; then
          $DRY_RUN_CMD ${pkgs.uv}/bin/uv tool install ty@latest
        fi
      '';

      installHelix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        helix_dir="${config.home.homeDirectory}/Development/Personal/helix"
        if [ ! -d "$helix_dir" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development/Personal"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone --branch steel-event-system-plus https://github.com/thomasschafer/helix.git "$helix_dir"
        fi
        if [ ! -x "${config.home.homeDirectory}/.cargo/bin/hx" ]; then
          cd "$helix_dir"
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo clean
          ${cargoBuildEnv ""}
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install --path helix-term --locked
        fi
      '';

      linkHelixRuntime = lib.hm.dag.entryAfter [ "installHelix" ] ''
        ln -sfn "${config.home.homeDirectory}/Development/Personal/helix/runtime" "${config.home.homeDirectory}/.config/helix/runtime"
      '';

      installCodex = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${config.home.homeDirectory}/.local/bin/codex" ]; then
          export PATH="${pkgs.nodejs_22}/bin:$PATH"
          $DRY_RUN_CMD ${pkgs.nodejs_22}/bin/npm install -g --prefix "${config.home.homeDirectory}/.local" @openai/codex
        fi
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

      # Merge our overrides into settings.json rather than owning the whole
      # file, so the rest stays writable by Claude Code. The desired keys live
      # in claude/settings-overrides.json; the if only picks the base to merge
      # onto (existing file, or an empty object on first run).
      setClaudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        claude_dir="${config.home.homeDirectory}/.claude"
        claude_settings="$claude_dir/settings.json"
        $DRY_RUN_CMD mkdir -p "$claude_dir"
        base=$(${pkgs.coreutils}/bin/mktemp)
        if [ -f "$claude_settings" ]; then
          ${pkgs.coreutils}/bin/cat "$claude_settings" > "$base"
        else
          echo '{}' > "$base"
        fi
        merged=$(${pkgs.coreutils}/bin/mktemp)
        ${pkgs.jq}/bin/jq -s '.[0] * .[1]' "$base" ${../claude/settings-overrides.json} > "$merged"
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$merged" "$claude_settings"
        ${pkgs.coreutils}/bin/rm -f "$base"
      '';

      installOpenCode = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${config.home.homeDirectory}/.local/bin/opencode" ]; then
          export PATH="${pkgs.nodejs_22}/bin:$PATH"
          $DRY_RUN_CMD ${pkgs.nodejs_22}/bin/npm install -g --prefix "${config.home.homeDirectory}/.local" opencode-ai
        fi
      '';

      installGeminiCli = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${config.home.homeDirectory}/.local/bin/gemini" ]; then
          export PATH="${pkgs.nodejs_22}/bin:$PATH"
          $DRY_RUN_CMD ${pkgs.nodejs_22}/bin/npm install -g --prefix "${config.home.homeDirectory}/.local" @google/gemini-cli
        fi
      '';

      cloneZshelix = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -d "${config.home.homeDirectory}/Development/Personal/zshelix" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development/Personal"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/zshelix.git \
            "${config.home.homeDirectory}/Development/Personal/zshelix"
        fi
      '';

      cloneScooter = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        scooter_dir="${config.home.homeDirectory}/Development/Personal/scooter"
        if [ ! -d "$scooter_dir" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development/Personal"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/scooter.git \
            "$scooter_dir"
        fi
      '';

      installScooter = lib.hm.dag.entryAfter [ "cloneScooter" ] ''
        scooter_dir="${config.home.homeDirectory}/Development/Personal/scooter"
        scooter_bin="${config.home.homeDirectory}/.cargo/bin/scooter"
        if [ ! -x "$scooter_bin" ]; then
          cd "$scooter_dir"
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo clean
          ${cargoBuildEnv ""}
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install --path scooter --locked
        fi
      '';

      cloneHerdr = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        herdr_dir="${config.home.homeDirectory}/Development/Personal/herdr"
        if [ ! -d "$herdr_dir" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development/Personal"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/herdr.git \
            "$herdr_dir"
        fi
      '';

      installHerdr = lib.hm.dag.entryAfter [ "cloneHerdr" ] ''
        herdr_dir="${config.home.homeDirectory}/Development/Personal/herdr"
        herdr_bin="${config.home.homeDirectory}/.cargo/bin/herdr"
        if [ ! -x "$herdr_bin" ]; then
          export ZIG="${zigForHerdr}"
          if [ ! -x "$ZIG" ]; then
            echo "installHerdr: Zig not found at $ZIG" >&2
            exit 1
          fi
          cd "$herdr_dir"
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo clean
          ${cargoBuildEnv ""}
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install --path . --locked
        fi
      '';

      cloneHerdrKiosk = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        herdr_kiosk_dir="${config.home.homeDirectory}/Development/Personal/herdr-kiosk"
        if [ ! -d "$herdr_kiosk_dir" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development/Personal"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/herdr-kiosk.git \
            "$herdr_kiosk_dir"
        fi
      '';

      # Linking runs the plugin's build step, which downloads a release binary
      # (or builds from source), so only link when the plugin is missing.
      linkHerdrKiosk = lib.hm.dag.entryAfter [ "installHerdr" "cloneHerdrKiosk" ] ''
        herdr_bin="${config.home.homeDirectory}/.cargo/bin/herdr"
        kiosk_plugins=$("$herdr_bin" plugin list --plugin thomasschafer.herdr-kiosk --json)
        if ! printf '%s' "$kiosk_plugins" | ${pkgs.jq}/bin/jq -e '.result.plugins | length > 0' >/dev/null; then
          export PATH="${pkgs.curl}/bin:${pkgs.gawk}/bin:${pkgs.gnused}/bin:${pkgs.cargo}/bin:$PATH"
          ${cargoBuildEnv ""}
          $DRY_RUN_CMD "$herdr_bin" plugin link \
            "${config.home.homeDirectory}/Development/Personal/herdr-kiosk" >/dev/null
        fi
      '';

      cloneScooterHx = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        scooter_hx_dir="${config.home.homeDirectory}/Development/Personal/scooter.hx"
        if [ ! -d "$scooter_hx_dir" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development/Personal"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/scooter.hx.git \
            "$scooter_hx_dir"
        fi
      '';

      cloneSmoothScrollHx = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        smooth_scroll_dir="${config.home.homeDirectory}/Development/Personal/smooth-scroll.hx"
        if [ ! -d "$smooth_scroll_dir" ]; then
          $DRY_RUN_CMD mkdir -p "${config.home.homeDirectory}/Development/Personal"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone https://github.com/thomasschafer/smooth-scroll.hx.git \
            "$smooth_scroll_dir"
        fi
      '';

      installCargoSteelLib = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${config.home.homeDirectory}/.cargo/bin/cargo-steel-lib" ]; then
          ${cargoBuildEnv ""}
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install cargo-steel-lib
        fi
      '';

      buildScooterHx = lib.hm.dag.entryAfter [ "cloneScooterHx" "installCargoSteelLib" ] ''
        scooter_hx_dir="${config.home.homeDirectory}/Development/Personal/scooter.hx"
        steel_home="${config.home.homeDirectory}/.steel"
        scooter_hx_lib="$steel_home/native/libscooter_hx.dylib"
        scooter_hx_hash_file="$steel_home/.scooter-hx-cargo-lock-hash"
        current_hash=$(${pkgs.coreutils}/bin/md5sum "$scooter_hx_dir/Cargo.lock" 2>/dev/null | cut -d' ' -f1)
        stored_hash=$(cat "$scooter_hx_hash_file" 2>/dev/null || true)
        if [ -d "$scooter_hx_dir" ] && { [ ! -f "$scooter_hx_lib" ] || [ "$current_hash" != "$stored_hash" ]; }; then
          cd "$scooter_hx_dir"
          ${cargoBuildEnv "${config.home.homeDirectory}/.cargo/bin:${pkgs.cargo}/bin"}
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo steel-lib
          echo "$current_hash" > "$scooter_hx_hash_file"
        fi
      '';

      # TODO: currently relies on raco from homebrew, should move to Nix
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

      # herdr snapshots the manifest and resolved store path when linking, so
      # relink on every switch to pick up changes before old paths are GC'd.
      linkHerdrCaffeinatePlugin = lib.hm.dag.entryAfter [ "installHerdr" ] ''
        $DRY_RUN_CMD "${config.home.homeDirectory}/.cargo/bin/herdr" plugin link \
          ${../herdr/plugins/caffeinate} >/dev/null
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
  };
}
