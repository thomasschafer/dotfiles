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

  # Shell snippet to set up CC, SDKROOT, and PATH for cargo builds. Run it in a subshell:
  # activation steps share one shell, and later ones (setupLaunchAgents) need GNU tools
  # ahead of /usr/bin on PATH.
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

  # setup.sh reads and writes these too, so keep the paths in step with it.
  stateDir = "${config.home.homeDirectory}/.local/state/dotfiles";
  # Present while `dp --no-pull` runs, to skip pulling.
  skipPullFile = "${stateDir}/skip-pull";
  # Why checkouts weren't pulled, one per line, which setup.sh shows after the switch.
  pullWarningsFile = "${stateDir}/pull-warnings";

  pullRepoScript = pkgs.writeShellScript "pull-repo" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.git
        pkgs.coreutils
      ]
    }:$PATH"
    exec ${lib.getExe pkgs.bash} ${../tools/pull-repo.sh} "$@"
  '';

  # Clones one of my repos into devDir if it isn't there yet. With pull, an existing clone
  # is fast-forwarded to its upstream (see tools/pull-repo.sh, which leaves local work
  # alone), so the build steps after it pick up new commits. Other clones are left alone.
  cloneRepo =
    {
      repo,
      branch ? null,
      submodules ? false,
      pull ? false,
    }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] (
      ''
        if [ ! -d "${devDir}/${repo}" ]; then
          $DRY_RUN_CMD mkdir -p "${devDir}"
          $DRY_RUN_CMD ${pkgs.git}/bin/git clone ${
            lib.optionalString (branch != null) "--branch ${branch} "
          }${lib.optionalString submodules "--recurse-submodules "}https://github.com/thomasschafer/${repo}.git "${devDir}/${repo}"
      ''
      + lib.optionalString pull ''
        elif [ -e "${skipPullFile}" ]; then
          echo "Not pulling ${repo} (dp --no-pull)"
        else
          $DRY_RUN_CMD ${pullRepoScript} "${devDir}/${repo}" ${
            lib.escapeShellArg (if branch == null then "" else branch)
          } ${if submodules then "1" else "0"} "${pullWarningsFile}"
      ''
      + ''
        fi
      ''
    );

  # Builds a repo cloned with cloneRepo, if what it installs (installedPath) is missing or
  # the clone's HEAD has moved since the last build, so pulling a repo and re-running setup
  # installs the matching build. Uncommitted changes don't trigger a rebuild. preBuild runs
  # first, for build-specific environment and checks; build runs in the repo with
  # cargoBuildEnv set up (with extraPath ahead on PATH), and afterBuild once the build is
  # recorded.
  buildFromRepo =
    {
      repo,
      name,
      installedPath,
      after,
      build,
      preBuild ? "",
      afterBuild ? "",
      extraPath ? "",
    }:
    let
      repoDir = "${devDir}/${repo}";
      builtCommitFile = "${stateDir}/built-commits/${name}";
    in
    lib.hm.dag.entryAfter after ''
      if [ ! -d "${repoDir}" ]; then
        if [ -n "$DRY_RUN_CMD" ]; then
          echo "Would build ${name} once ${repoDir} is cloned"
        else
          echo "Can't build ${name}: ${repoDir} doesn't exist" >&2
          exit 1
        fi
      else
        head_commit=$(${pkgs.git}/bin/git -C "${repoDir}" rev-parse HEAD)
        built_commit=$(cat "${builtCommitFile}" 2>/dev/null || true)
        if [ ! -e "${installedPath}" ] || [ "$head_commit" != "$built_commit" ]; then
          # A subshell, so the build's cd and environment don't leak into later activation
          # steps (setupLaunchAgents needs GNU readlink first on PATH).
          (
            ${preBuild}
            cd "${repoDir}"
            ${cargoBuildEnv extraPath}
            ${build}
            if [ -z "$DRY_RUN_CMD" ]; then
              mkdir -p "$(dirname "${builtCommitFile}")"
              echo "$head_commit" > "${builtCommitFile}"
              echo "Built ${name} from ${repo} at $head_commit; anything already running ${name} keeps the old build until restarted"
              ${afterBuild}
            fi
          )
        fi
      fi
    '';

  # Builds and installs a crate from a repo cloned with cloneRepo with `cargo install` (see
  # buildFromRepo for when).
  cargoInstallFromRepo =
    {
      repo,
      cratePath,
      bin,
      after,
      preBuild ? "",
      afterBuild ? "",
    }:
    buildFromRepo {
      inherit
        repo
        after
        preBuild
        afterBuild
        ;
      name = bin;
      installedPath = "${cargoBin}/${bin}";
      build = ''
        $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo clean
        # Pin rustc to the one cargo comes with: a rustup proxy earlier on PATH would
        # pick a toolchain per directory, from the repo's rust-toolchain.toml or the
        # default, so one build would mix rustc versions.
        $DRY_RUN_CMD env RUSTC="${pkgs.rustc}/bin/rustc" \
          ${pkgs.cargo}/bin/cargo install --path ${cratePath} --locked
      '';
    };

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

  # Merges overrides into a JSON settings file rather than owning the whole file, so the
  # rest stays writable by the app that owns it. jqFilter combines `[existing, overrides]`
  # (read with `jq -s`); the existing file is `{}` on first run.
  mergeJsonSettings =
    {
      target,
      overrides,
      jqFilter,
    }:
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings_file="${target}"
      $DRY_RUN_CMD mkdir -p "$(dirname "$settings_file")"
      base=$(${pkgs.coreutils}/bin/mktemp)
      if [ -f "$settings_file" ]; then
        ${pkgs.coreutils}/bin/cat "$settings_file" > "$base"
      else
        echo '{}' > "$base"
      fi
      merged=$(${pkgs.coreutils}/bin/mktemp)
      ${pkgs.jq}/bin/jq -s ${jqFilter} "$base" ${overrides} > "$merged"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$merged" "$settings_file"
      ${pkgs.coreutils}/bin/rm -f "$base"
    '';

  # herdr's vendored libghostty-vt needs an exact Zig toolchain version (see
  # crates/ghostty-vt/build.rs in herdr). nixpkgs' Zig can't link against the
  # macOS SDK outside the Nix sandbox, so use Homebrew's versioned formula, or
  # the release unpacked into ~/.local/share/zig where Homebrew's isn't
  # installed, matching the ZIG export in zsh/.zshrc.
  zigForHerdrCandidates = [
    "/opt/homebrew/opt/zig@0.16/bin/zig"
    "${config.home.homeDirectory}/.local/share/zig/0.16.0/zig"
  ];

  # Exports ZIG for the herdr builds (herdr, herdr-core and the Herdr app all vendor
  # libghostty-vt).
  exportZigForHerdr = name: ''
    ZIG=""
    for candidate in ${lib.escapeShellArgs zigForHerdrCandidates}; do
      if [ -x "$candidate" ]; then
        ZIG="$candidate"
        break
      fi
    done
    if [ -z "$ZIG" ]; then
      echo "${name}: Zig 0.16 not found at any of: ${lib.concatStringsSep " " zigForHerdrCandidates}" >&2
      exit 1
    fi
    export ZIG
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

  secret = pkgs.callPackage ../tools/secret.nix { };

  # rclone reads its config's encryption password from the keychain item rclone-config, so the
  # OAuth tokens in the config aren't stored in plain text. setup.sh checks the config is
  # encrypted.
  rcloneWithKeychain = pkgs.symlinkJoin {
    name = "rclone-with-keychain";
    paths = [ pkgs.rclone ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/rclone \
        --set-default RCLONE_PASSWORD_COMMAND "${lib.getExe secret} get rclone-config"
    '';
  };

  catppuccin = builtins.fromTOML (builtins.readFile ../catppuccin.toml);
  catppuccinMacchiatoTheme = pkgs.fetchurl catppuccin.tmtheme;

  files = {
    ".claude/CLAUDE.md".source = ../agents/shared.md;
    ".codex/AGENTS.md".source = ../agents/shared.md;
    ".claude/skills/review-loop".source = ../skills/review-loop;
    ".codex/skills/review-loop".source = ../skills/review-loop;
    ".claude/keybindings.json".source = ../claude/keybindings.json;

    # Atuin
    ".config/atuin/config.toml".source = ../atuin/config.toml;

    # Bat
    ".config/bat/config".source = ../bat/config;

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

    # herdr-core
    ".config/herdr-core/config.toml".source = ../herdr-core/config.toml;

    # Herdr app (settings.json is merged by setHerdrAppSettings, as the app writes to it)
    ".config/herdr-app/keys.json".source = ../herdr-app/keys.json;
    ".config/herdr-app/layouts/compact.json".source = ../herdr-app/layouts/compact.json;
    ".config/herdr-app/themes/catppuccin-macchiato.json".source =
      ../herdr-app/themes/catppuccin-macchiato.json;
    # Linked from the checkout rather than the store: the mod finds kiosk's binary beside
    # it, and the app writes typings into mod folders.
    ".config/herdr-app/mods/kiosk".source =
      config.lib.file.mkOutOfStoreSymlink "${devDir}/herdr-kiosk/herdr-app/kiosk";
    # The same config as the herdr plugin's below.
    ".config/herdr-kiosk/config.toml".source = ../herdr/config/thomasschafer.herdr-kiosk/config.toml;

    # Herdr
    ".config/herdr/config.toml".source = ../herdr/config.toml;
    ".config/herdr/plugins/config/thomasschafer.herdr-kiosk/config.toml".source =
      ../herdr/config/thomasschafer.herdr-kiosk/config.toml;

    # Lazygit
    "${configHome}/lazygit/config.yml".source = ../lazygit/config.yml;

    # Opencode
    ".config/opencode/config.json".source = ../opencode/config.json;
    ".config/opencode/tui.json".source = ../opencode/tui.json;

    # Neovim
    ".config/nvim".source = ../neovim/nvim;

    # Scooter
    ".config/scooter/config.toml".source = ../scooter/config.toml;
    ".config/scooter/themes/Catppuccin-Macchiato.tmTheme".source = catppuccinMacchiatoTheme;

    # Yazi
    ".config/yazi/yazi.toml".source = ../yazi/yazi.toml;
    ".config/yazi/theme.toml".source = pkgs.fetchurl catppuccin.yazi;
    ".config/yazi/Catppuccin-macchiato.tmTheme".source = catppuccinMacchiatoTheme;

    # Zshrc
    ".zshrc".source = ../zsh/.zshrc;

    # npm globals: keep CLI self-updates in ~/.local (dotfiles-managed path precedence)
    ".npmrc".text = ''
      prefix=${config.home.homeDirectory}/.local
    '';

    # Git
    ".config/git/ignore".source = ../git/ignore;

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
    ./caffeinate.nix
    ./deploy.nix
    ./rex.nix
    ./tailscale-serve.nix
  ]
  ++ lib.optionals hostConfig.enableDependabotReview [
    ../dependabot-review/nix/home.nix
  ]
  ++ lib.optionals hostConfig.enableHealthTracking [ ./health-tracking.nix ]
  ++ lib.optionals hostConfig.enableWorkshop [ ./workshop.nix ]
  ++ lib.optionals hostConfig.enableAlmanac [ ./almanac.nix ]
  ++ lib.optionals hostConfig.enableOvis [ ./ovis.nix ]
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
        colima
        delta
        delve
        direnv
        docker-client
        # Lets Docker use the keychain for registry logins (credsStore in ~/.docker/config.json)
        docker-credential-helpers
        fd
        ffmpeg
        fzf
        git-filter-repo
        go
        golangci-lint
        golangci-lint-langserver
        gopls
        gh
        hadolint
        jless
        neovim
        nixfmt
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
        rcloneWithKeychain
        ripgrep
        ruff
        # scooter  # Building from source manually
        sd
        shellcheck
        sqlfluff
        taplo
        # herdr's system notifications use it when present, so clicking one focuses the terminal
        terminal-notifier
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

        # Haskell, for Advent of Code solutions in Workshop
        ghc
        cabal-install
        haskell-language-server

        # Scripts/tools
        # GNU sed under the Homebrew name, leaving `sed` as the macOS one
        (writeShellScriptBin "gsed" ''exec ${gnused}/bin/sed "$@"'')
        (writeShellScriptBin "fr" (builtins.readFile ../tools/fr.sh))
        (writeShellScriptBin "mux-new-window" (builtins.readFile ../tools/mux-new-window.sh))
        (writeShellScriptBin "mux-send-keys" (builtins.readFile ../tools/mux-send-keys.sh))
        secret
      ];

    activation = {
      # Home Manager's LaunchAgents activation uses GNU-only `readlink -m`.
      # Ensure it resolves Nix's GNU tools rather than macOS's BSD utilities.
      ensureGnuLaunchdTools = lib.hm.dag.entryBefore [ "setupLaunchAgents" ] ''
        export PATH="${pkgs.coreutils}/bin:${pkgs.findutils}/bin:$PATH"
        hash -r
      '';

      # Activation runs without the CA certificates a login shell gets from Nix's profile, so
      # Nix's git, curl, cargo and npm can't verify HTTPS servers. Every step that downloads
      # anything runs after writeBoundary, so this gives them all Nix's bundle.
      exportCaCertificates = lib.hm.dag.entryBefore [ "writeBoundary" ] ''
        export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
        export NIX_SSL_CERT_FILE="$SSL_CERT_FILE"
      '';

      installTy = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${config.home.homeDirectory}/.local/bin/ty" ]; then
          $DRY_RUN_CMD ${pkgs.uv}/bin/uv tool install ty@latest
        fi
      '';

      cloneHelix = cloneRepo {
        repo = "helix";
        branch = "steel-event-system-plus";
        pull = true;
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

      # The desired keys live in claude/settings-overrides.json, and
      # claude/merge-settings.jq says how they combine.
      setClaudeSettings = mergeJsonSettings {
        target = "${config.home.homeDirectory}/.claude/settings.json";
        overrides = ../claude/settings-overrides.json;
        jqFilter = "-f ${../claude/merge-settings.jq}";
      };

      installOpenCode = npmInstall {
        bin = "opencode";
        package = "opencode-ai";
      };

      cloneZshelix = cloneRepo { repo = "zshelix"; };

      cloneScooter = cloneRepo {
        repo = "scooter";
        pull = true;
      };

      installScooter = cargoInstallFromRepo {
        repo = "scooter";
        cratePath = "scooter";
        bin = "scooter";
        after = [ "cloneScooter" ];
      };

      cloneHerdr = cloneRepo {
        repo = "herdr";
        pull = true;
      };

      installHerdr = cargoInstallFromRepo {
        repo = "herdr";
        cratePath = ".";
        bin = "herdr";
        after = [ "cloneHerdr" ];
        preBuild = exportZigForHerdr "installHerdr";
      };

      cloneHerdrCore = cloneRepo {
        repo = "herdr-core";
        submodules = true;
        pull = true;
      };

      # The Herdr app finds hc in ~/.cargo/bin. A running core keeps the old build until
      # `hc server restart`, which keeps its terminals running; it isn't restarted here as
      # it would inherit this activation's environment.
      installHerdrCore = cargoInstallFromRepo {
        repo = "herdr-core";
        cratePath = "crates/herdr-core";
        bin = "herdr-core";
        after = [ "cloneHerdrCore" ];
        preBuild = exportZigForHerdr "installHerdrCore";
        afterBuild = ''
          ln -sfn herdr-core "${cargoBin}/hc"
        '';
      };

      cloneHerdrApp = cloneRepo {
        repo = "herdr-app";
        submodules = true;
        pull = true;
      };

      # The repo's installer builds ~/Applications/Herdr.app and links
      # ~/.local/bin/herdr-app to it. The app's Info.plist gets the PATH it runs with.
      installHerdrApp = buildFromRepo {
        repo = "herdr-app";
        name = "herdr-app";
        installedPath = "${config.home.homeDirectory}/Applications/Herdr.app/Contents/MacOS/Herdr";
        after = [ "cloneHerdrApp" ];
        preBuild = exportZigForHerdr "installHerdrApp";
        build = ''
          $DRY_RUN_CMD env RUSTC="${pkgs.rustc}/bin/rustc" \
            PATH="${pkgs.cargo}/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
            /bin/bash scripts/install-macos
        '';
      };

      setHerdrAppSettings = mergeJsonSettings {
        target = "${config.home.homeDirectory}/.config/herdr-app/settings.json";
        overrides = ../herdr-app/settings-overrides.json;
        jqFilter = "'.[0] * .[1]'";
      };

      # Defaults for the app's shared state on first run: skip the welcome and show the
      # compact layout. Anything the app has already set wins, so switching layout sticks.
      setHerdrAppSharedDefaults = mergeJsonSettings {
        target = "${config.home.homeDirectory}/.config/herdr-app/shared.json";
        overrides = ../herdr-app/shared-defaults.json;
        jqFilter = "'.[1] * .[0]'";
      };

      cloneHerdrKiosk = cloneRepo {
        repo = "herdr-kiosk";
        pull = true;
      };

      # Both the herdr plugin and the Herdr app's mod run the checkout's release build.
      buildHerdrKiosk = buildFromRepo {
        repo = "herdr-kiosk";
        name = "herdr-kiosk";
        installedPath = "${devDir}/herdr-kiosk/target/release/herdr-kiosk";
        after = [ "cloneHerdrKiosk" ];
        build = ''
          $DRY_RUN_CMD env RUSTC="${pkgs.rustc}/bin/rustc" \
            ${pkgs.cargo}/bin/cargo build --release --locked
        '';
      };

      # Linking runs the plugin's build step, which downloads a release binary
      # (or builds from source), so only link when the plugin is missing.
      linkHerdrKiosk = lib.hm.dag.entryAfter [ "installHerdr" "buildHerdrKiosk" ] ''
        herdr_bin="${cargoBin}/herdr"
        kiosk_plugins=$("$herdr_bin" plugin list --plugin thomasschafer.herdr-kiosk --json)
        if ! printf '%s' "$kiosk_plugins" | ${pkgs.jq}/bin/jq -e '.result.plugins | length > 0' >/dev/null; then
          (
            export PATH="${pkgs.curl}/bin:${pkgs.gawk}/bin:${pkgs.gnused}/bin:${pkgs.cargo}/bin:$PATH"
            ${cargoBuildEnv ""}
            $DRY_RUN_CMD "$herdr_bin" plugin link "${devDir}/herdr-kiosk" >/dev/null
          )
        fi
      '';

      cloneScooterHx = cloneRepo {
        repo = "scooter.hx";
        pull = true;
      };

      cloneSmoothScrollHx = cloneRepo {
        repo = "smooth-scroll.hx";
        pull = true;
      };

      cloneHerdrSessionHx = cloneRepo {
        repo = "herdr-session.hx";
        pull = true;
      };

      installCargoSteelLib = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [ ! -x "${cargoBin}/cargo-steel-lib" ]; then
          (
            ${cargoBuildEnv ""}
            $DRY_RUN_CMD ${pkgs.cargo}/bin/cargo install cargo-steel-lib
          )
        fi
      '';

      # mise's Rust backend uses ~/.cargo/bin as its bin directory, so once a repo pins Rust
      # (as Workshop does) mise shims everything cargo installs there, and `mise activate` puts
      # those shims ahead of the real binaries on PATH. This excludes all but rustup's proxies
      # (cargo, rustc and so on, which are links to rustup), as mise needs those to pick a
      # toolchain. Anything installed with cargo by hand is excluded at the next switch.
      excludeCargoBinsFromMiseShims =
        lib.hm.dag.entryAfter
          [
            "installHelix"
            "installScooter"
            "installHerdr"
            "installHerdrCore"
            "installCargoSteelLib"
          ]
          ''
            mise_conf="${config.home.homeDirectory}/.config/mise/conf.d/cargo-bin-shims.toml"
            excluded=()
            for bin in "${cargoBin}"/*; do
              [ -f "$bin" ] && [ -x "$bin" ] || continue
              [ "$bin" -ef "${cargoBin}/rustup" ] || excluded+=("$(basename "$bin")")
            done
            if [ -z "$DRY_RUN_CMD" ]; then
              mkdir -p "$(dirname "$mise_conf")"
              {
                echo "# Written by excludeCargoBinsFromMiseShims in the dotfiles' modules/home.nix on every switch."
                echo "[settings]"
                printf 'shims.exclude = %s\n' \
                  "$(printf '%s\n' ''${excluded[@]+"''${excluded[@]}"} | ${pkgs.jq}/bin/jq -Rsc 'split("\n") | map(select(. != ""))')"
              } > "$mise_conf.new"
              mv "$mise_conf.new" "$mise_conf"
              ${pkgs.mise}/bin/mise reshim
            else
              echo "Would exclude from mise's shims: ''${excluded[*]-}"
            fi
          '';

      buildScooterHx =
        let
          steelHome = "${config.home.homeDirectory}/.local/share/steel";
        in
        buildFromRepo {
          repo = "scooter.hx";
          name = "scooter.hx";
          installedPath = "${steelHome}/native/libscooter_hx.dylib";
          after = [
            "cloneScooterHx"
            "installCargoSteelLib"
          ];
          extraPath = "${cargoBin}:${pkgs.cargo}/bin";
          build = ''
            # cargo steel-lib copies the library into native/, but doesn't create it.
            $DRY_RUN_CMD mkdir -p "${steelHome}/native"
            $DRY_RUN_CMD env STEEL_HOME="${steelHome}" ${pkgs.cargo}/bin/cargo steel-lib
          '';
        };

      # TODO: currently relies on raco from homebrew, should move to Nix
      installRacketFmt = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if ! $DRY_RUN_CMD /opt/homebrew/bin/raco fmt --help &>/dev/null; then
          $DRY_RUN_CMD /opt/homebrew/bin/raco pkg install --auto fmt
        fi
      '';

      # caffeinate used to run from this herdr plugin, before caffeinate.nix ran it for Rex
      # too. TODO: remove once every machine has switched.
      unlinkHerdrCaffeinatePlugin = lib.hm.dag.entryAfter [ "installHerdr" ] ''
        if ! caffeinate_plugins=$("${cargoBin}/herdr" plugin list --plugin local.caffeinate --json); then
          echo "Couldn't list herdr's plugins, so the old caffeinate plugin may still be linked" >&2
        elif printf '%s' "$caffeinate_plugins" | ${pkgs.jq}/bin/jq -e '.result.plugins | length > 0' >/dev/null; then
          $DRY_RUN_CMD "${cargoBin}/herdr" plugin unlink local.caffeinate >/dev/null
        fi
      '';
    }
    // lib.optionalAttrs hostConfig.enableHealthTracking {
      cloneHealthTracking = cloneRepo { repo = "health-tracking"; };
    }
    // lib.optionalAttrs hostConfig.enableWorkshop {
      cloneWorkshop = cloneRepo { repo = "workshop"; };
      cloneAdventOfCode = cloneRepo { repo = "advent-of-code"; };
    }
    // lib.optionalAttrs hostConfig.enableAlmanac {
      cloneAlmanac = cloneRepo { repo = "almanac"; };
    };
  };

  programs = {
    home-manager.enable = true;

    # Written to ~/.config/git/config, leaving ~/.gitconfig to tools that set things with
    # `git config --global`, such as `gh auth setup-git`. Git reads both.
    git = {
      enable = true;
      includes = [
        { path = ../git/shared.gitconfig; }
        { path = ../git/identity.gitconfig; }
      ];
      signing = {
        format = "ssh";
        key = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
        signByDefault = true;
      };
      settings = {
        gpg.ssh.allowedSignersFile = "${config.home.homeDirectory}/.ssh/allowed_signers";
      };
    };

    bat = {
      enable = true;
      themes = {
        "Catppuccin Macchiato" = {
          src = catppuccinMacchiatoTheme;
        };
      };
    };

  };
}
