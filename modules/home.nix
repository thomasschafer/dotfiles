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

  devDir = "${config.home.homeDirectory}/Development/Personal";
  cargoBin = "${config.home.homeDirectory}/.cargo/bin";

  # Clones one of my repos into devDir if it isn't there yet. Existing clones are left
  # alone so local work isn't disturbed.
  cloneRepo =
    {
      repo,
      branch ? null,
    }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${devDir}/${repo}" ]; then
        $DRY_RUN_CMD mkdir -p "${devDir}"
        $DRY_RUN_CMD ${pkgs.git}/bin/git clone ${
          lib.optionalString (branch != null) "--branch ${branch} "
        }https://github.com/thomasschafer/${repo}.git "${devDir}/${repo}"
      fi
    '';

  # Builds and installs a crate from a repo cloned with cloneRepo, if its binary isn't
  # installed yet. preBuild runs first, for build-specific environment and checks.
  cargoInstallFromRepo =
    {
      repo,
      cratePath,
      bin,
      after,
      preBuild ? "",
    }:
    lib.hm.dag.entryAfter after ''
      if [ ! -x "${cargoBin}/${bin}" ]; then
        ${preBuild}
        cd "${devDir}/${repo}"
        $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo clean
        ${cargoBuildEnv ""}
        $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install --path ${cratePath} --locked
      fi
    '';

  # Installs an npm package globally into ~/.local, if its binary isn't installed yet.
  # Later updates are left to the tool's own updater.
  npmInstall =
    { bin, package }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -x "${config.home.homeDirectory}/.local/bin/${bin}" ]; then
        export PATH="${pkgs.nodejs}/bin:$PATH"
        $DRY_RUN_CMD ${pkgs.nodejs}/bin/npm install -g --prefix "${config.home.homeDirectory}/.local" ${package}
      fi
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
    version = "0-unstable-2025-02-05";
    src = pkgs.fetchFromGitHub {
      owner = "thomasschafer";
      repo = "hx-utils";
      rev = "cc7fac12f3c8e8e0fa4c5a47d3237537c32f6148";
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
  imports = [
    ./agents-status.nix
    ./deploy.nix
  ]
  ++ lib.optionals hostConfig.enableDependabotReview [
    ../dependabot-review/nix/home.nix
  ]
  ++ lib.optionals hostConfig.enableHealthTracking [ ./health-tracking.nix ]
  ++ lib.optionals hostConfig.enableWorkshop [ ./workshop.nix ]
  ++ lib.optionals hostConfig.enableTodoistBackup [ ../todoist-backup/nix/home.nix ];

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
        # TODO: drop the override once nixpkgs-unstable includes
        # https://github.com/NixOS/nixpkgs/pull/574509, which it mirrors. In unsandboxed
        # macOS builds the e2e tests' bash sources /etc/bashrc, whose PATH runs the
        # installed atuin rather than the one being built, so the tests fail and there's
        # no cached binary to fall back on.
        (atuin.overrideAttrs (old: {
          env = (old.env or { }) // {
            ATUIN_E2E_BASH = lib.getExe (
              writeShellScriptBin "bash" ''
                NOSYSBASHRC=1 exec ${lib.getExe bashInteractive} "$@"
              ''
            );
          };
        }))
        biome
        delta
        delve
        deno
        direnv
        fd
        ffmpeg
        fzf
        git-filter-repo
        go
        golangci-lint
        golangci-lint-langserver
        gopls
        gh
        git
        hadolint
        jless
        neovim
        nixfmt
        nushell
        jq
        lazygit
        mise
        # Runs the npm-installed CLIs (Codex, OpenCode)
        nodejs
        pgformatter
        poppler-utils
        pre-commit
      ]
      ++ lib.optionals hostConfig.enablePython [
        (python314.withPackages (
          ps: with ps; [
            pip
          ]
        ))
      ]
      ++ [
        _7zz
        ripgrep
        ruff
        # scooter  # Building from source manually
        sd
        shellcheck
        sqlfluff
        taplo
        terraform-docs
        tree
        typescript-language-server
        uv
        vscode-langservers-extracted
        wget
        yamllint
        yazi
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

        # Scripts/tools
        # GNU sed under the Homebrew name, leaving `sed` as the macOS one
        (writeShellScriptBin "gsed" ''exec ${gnused}/bin/sed "$@"'')
        (writeShellScriptBin "fr" (builtins.readFile ../tools/fr.sh))
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

      cloneHelix = cloneRepo {
        repo = "helix";
        branch = "steel-event-system-plus";
      };

      installHelix = cargoInstallFromRepo {
        repo = "helix";
        cratePath = "helix-term";
        bin = "hx";
        after = [ "cloneHelix" ];
      };

      linkHelixRuntime = lib.hm.dag.entryAfter [ "installHelix" ] ''
        ln -sfn "${devDir}/helix/runtime" "${config.home.homeDirectory}/.config/helix/runtime"
      '';

      installCodex = npmInstall {
        bin = "codex";
        package = "@openai/codex";
      };

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

      installOpenCode = npmInstall {
        bin = "opencode";
        package = "opencode-ai";
      };

      cloneZshelix = cloneRepo { repo = "zshelix"; };

      cloneScooter = cloneRepo { repo = "scooter"; };

      installScooter = cargoInstallFromRepo {
        repo = "scooter";
        cratePath = "scooter";
        bin = "scooter";
        after = [ "cloneScooter" ];
      };

      cloneHerdr = cloneRepo { repo = "herdr"; };

      installHerdr = cargoInstallFromRepo {
        repo = "herdr";
        cratePath = ".";
        bin = "herdr";
        after = [ "cloneHerdr" ];
        preBuild = ''
          export ZIG="${zigForHerdr}"
          if [ ! -x "$ZIG" ]; then
            echo "installHerdr: Zig not found at $ZIG" >&2
            exit 1
          fi
        '';
      };

      cloneHerdrKiosk = cloneRepo { repo = "herdr-kiosk"; };

      # Linking runs the plugin's build step, which downloads a release binary
      # (or builds from source), so only link when the plugin is missing.
      linkHerdrKiosk = lib.hm.dag.entryAfter [ "installHerdr" "cloneHerdrKiosk" ] ''
        herdr_bin="${cargoBin}/herdr"
        kiosk_plugins=$("$herdr_bin" plugin list --plugin thomasschafer.herdr-kiosk --json)
        if ! printf '%s' "$kiosk_plugins" | ${pkgs.jq}/bin/jq -e '.result.plugins | length > 0' >/dev/null; then
          export PATH="${pkgs.curl}/bin:${pkgs.gawk}/bin:${pkgs.gnused}/bin:${pkgs.cargo}/bin:$PATH"
          ${cargoBuildEnv ""}
          $DRY_RUN_CMD "$herdr_bin" plugin link "${devDir}/herdr-kiosk" >/dev/null
        fi
      '';

      cloneScooterHx = cloneRepo { repo = "scooter.hx"; };

      cloneSmoothScrollHx = cloneRepo { repo = "smooth-scroll.hx"; };

      installCargoSteelLib = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${cargoBin}/cargo-steel-lib" ]; then
          ${cargoBuildEnv ""}
          $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install cargo-steel-lib
        fi
      '';

      buildScooterHx = lib.hm.dag.entryAfter [ "cloneScooterHx" "installCargoSteelLib" ] ''
        scooter_hx_dir="${devDir}/scooter.hx"
        steel_home="${config.home.homeDirectory}/.steel"
        scooter_hx_lib="$steel_home/native/libscooter_hx.dylib"
        scooter_hx_hash_file="$steel_home/.scooter-hx-cargo-lock-hash"
        current_hash=$(${pkgs.coreutils}/bin/md5sum "$scooter_hx_dir/Cargo.lock" 2>/dev/null | cut -d' ' -f1)
        stored_hash=$(cat "$scooter_hx_hash_file" 2>/dev/null || true)
        if [ -d "$scooter_hx_dir" ] && { [ ! -f "$scooter_hx_lib" ] || [ "$current_hash" != "$stored_hash" ]; }; then
          cd "$scooter_hx_dir"
          ${cargoBuildEnv "${cargoBin}:${pkgs.cargo}/bin"}
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

      # herdr snapshots the manifest and resolved store path when linking, so
      # relink on every switch to pick up changes before old paths are GC'd.
      linkHerdrCaffeinatePlugin = lib.hm.dag.entryAfter [ "installHerdr" ] ''
        $DRY_RUN_CMD "${cargoBin}/herdr" plugin link \
          ${../herdr/plugins/caffeinate} >/dev/null
      '';
    }
    // lib.optionalAttrs hostConfig.enableHealthTracking {
      cloneHealthTracking = cloneRepo { repo = "health-tracking"; };
    }
    // lib.optionalAttrs hostConfig.enableWorkshop {
      cloneWorkshop = cloneRepo { repo = "workshop"; };
      cloneAdventOfCode = cloneRepo { repo = "advent-of-code"; };
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
