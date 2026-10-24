# Ovis (github.com/devswha/ovis), the browser and phone client for herdr, installed as a herdr
# plugin that starts with herdr. It's served over Tailscale like the background apps; with no
# token set, it only lets in requests that Tailscale Serve says come from this Mac's own login.
#
# Setup installs the release pinned below, and reinstalls it whenever the plugin is at another
# commit. To update, check that the release's tag is on main and has a passing release build,
# then change version and commit, and set srcHash and cargoHash to lib.fakeHash to get the new
# ones from the build's errors. Don't use Update in the app: it takes any tag on the repo,
# unsigned, and runs it in place of the pin, which setup then reports.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;
  herdr = "${home}/.cargo/bin/herdr";
  version = "0.4.14";
  # The commit v${version} tagged, pinned rather than the tag, as tags can be moved.
  commit = "afc6c93e0d6c20e2f4a798b1b23cae9a7b4411b5";
  srcHash = "sha256-MgqLz0C4Acabo6q3X8/Uwb6coN2PappLo1t+YymlJt8=";
  cargoHash = "sha256-vin5SGninwkDlpWIK4Cc5oO4cZ7DjTXDovUpu0fWwlE=";
  pluginId = "devswha.ovis";
  # The plugin's id before v0.4.14, which installed alongside rather than replacing it.
  legacyPluginId = "devswha.herdr-web-ui";
  configDir = "${home}/.config/herdr/plugins/config/${pluginId}";
  port = 7317;
  httpsPort = 8445;

  # Ovis's Rust PTY host, which every terminal's input and output goes through. Installing the
  # plugin downloads a prebuilt one, checked only against a manifest from the same GitHub release,
  # so the commit pinned above wouldn't cover it; this builds it from that commit instead.
  ptyHost = pkgs.rustPlatform.buildRustPackage rec {
    pname = "ovis-pty-sidecar";
    inherit version cargoHash;
    src = pkgs.fetchFromGitHub {
      owner = "devswha";
      repo = "ovis";
      rev = commit;
      hash = srcHash;
    };
    sourceRoot = "${src.name}/crates/pty-sidecar";
    meta.mainProgram = "ovis-pty-sidecar";
  };

  # Settings the running server must have, which ovis-check confirms it got.
  required = {
    OVIS_TELEMETRY = "0";
    # Says Tailscale Serve is the only way in, so a request through anything else, such as a web
    # page rebound to 127.0.0.1, is refused even while Ovis doesn't know this Mac's login yet,
    # rather than let in while nothing is paired. It also lets my phone in without pairing, as
    # this tailnet has one login and no tagged devices; don't set it if that changes.
    OVIS_TAILSCALE_SERVE_ONLY = "1";
    # Without the downloaded host (see installOvis), Ovis would fall back to its Node one rather
    # than fail, so asking for the Rust host makes it log why it couldn't use this one.
    OVIS_PTY_SIDECAR = "rust";
    OVIS_PTY_SIDECAR_BIN = lib.getExe ptyHost;
  };
  requiredLines = lib.mapAttrsToList (name: value: "${name}=${value}") required;
  installCommand = "herdr plugin install devswha/ovis --ref ${commit} --yes";
  # The commit a plugin is installed from, or nothing if it isn't installed.
  installedCommit = id: ''
    "${herdr}" plugin list --plugin ${id} --json \
      | ${pkgs.jq}/bin/jq -r '.result.plugins[0].source.resolved_commit // empty'
  '';
  pluginRoot = ''
    "${herdr}" plugin list --plugin ${pluginId} --json | ${pkgs.jq}/bin/jq -r '.result.plugins[0].plugin_root'
  '';
  downloadedHost = [
    "bin/ovis-pty-sidecar"
    "bin/ovis-pty-sidecar.json"
  ];

  ovisCheck = pkgs.writeShellApplication {
    name = "ovis-check";
    runtimeInputs = [
      pkgs.curl
      pkgs.gnugrep
      pkgs.jq
    ];
    text = ''
      # Prints anything to fix about Ovis, one per line, for setup.sh.
      if ! "${herdr}" status server 2>/dev/null | grep -qx 'status: running'; then
        echo "start herdr, which runs Ovis, then check Ovis again with: dp"
        exit 0
      fi
      installed="$(${installedCommit pluginId})"
      if [ "$installed" != ${commit} ]; then
        echo "install Ovis v${version}, which the switch couldn't (it has ''${installed:-nothing}): run dp again, or ${installCommand}"
        exit 0
      fi
      if [ -n "$(${installedCommit legacyPluginId})" ]; then
        echo "uninstall the Ovis plugin from before v0.4.14, which the switch couldn't: herdr plugin action invoke ${legacyPluginId}.stop, then herdr plugin uninstall ${legacyPluginId}, then restart Ovis"
      fi
      root="$(${pluginRoot})"
      for file in ${lib.escapeShellArgs downloadedHost}; do
        if [ -e "$root/$file" ]; then
          echo "delete the PTY host the plugin downloaded, which the switch couldn't: rm $root/$file"
        fi
      done
      if ! health="$(curl -fsS --max-time 5 http://127.0.0.1:${toString port}/api/health 2>/dev/null)" \
          || ! jq -e '.ok == true' >/dev/null <<<"$health"; then
        echo "start Ovis, which isn't answering on port ${toString port}: herdr plugin action invoke ${pluginId}.start (its logs: herdr plugin log list)"
        exit 0
      fi
      # The revision the server runs, which an in-app update or a server left over from another
      # checkout would change.
      running="$(jq -r '.web_ui.revision // empty' <<<"$health")"
      if [ "$running" != ${commit} ]; then
        echo "restart Ovis, which is running ''${running:-an unknown revision} rather than the pinned v${version}: herdr plugin action invoke ${pluginId}.stop, then ${pluginId}.start"
        exit 0
      fi
      pid="$(/usr/sbin/lsof -nP -iTCP:${toString port} -sTCP:LISTEN -t | head -1)"
      server_env="$(/bin/ps -E -ww -o command= -p "$pid")"
      for setting in ${lib.escapeShellArgs requiredLines}; do
        if ! grep -q " $setting\( \|$\)" <<<"$server_env"; then
          echo "restart Ovis, which is running without $setting from ${configDir}/env: herdr plugin action invoke ${pluginId}.stop, then ${pluginId}.start"
        fi
      done
    '';
  };
in
{
  # herdr runs the plugin's commands with its own PATH, from the shell that started it.
  home.packages = [
    pkgs.bun
    ovisCheck
  ];

  # Read by the plugin (see INSTALL.md in the repo); herdr gives it this config directory. As it
  # exists before the plugin first starts, the plugin doesn't copy the old id's env file here.
  home.file."${lib.removePrefix "${home}/" configDir}/env".text = ''
    ${lib.concatLines requiredLines}
    # Honoured whatever the telemetry setting is called, in case a release renames it.
    DO_NOT_TRACK=1
    # Pinned, as Ovis otherwise moves to another port when this one is taken, which Tailscale
    # Serve wouldn't follow.
    PORT=${toString port}
    OVIS_TAILSCALE_HTTPS_PORT=${toString httpsPort}
    # Files attached from the phone, which otherwise go in a folder in the pane's directory.
    OVIS_PASTE_DIR=${home}/.local/share/ovis/pastes
  '';

  # Installing builds the plugin and downloads its dependencies, so a failure (such as being
  # offline) only warns, and ovis-check reports it. It runs once the env file is linked and Bun
  # is in the profile, as herdr may start the plugin with its own PATH.
  home.activation.installOvis =
    lib.hm.dag.entryAfter
      [
        "installHerdr"
        "installPackages"
        "linkGeneration"
      ]
      ''
        # Plugin actions are only queued, so this waits for a stopped server to let go of its
        # port, as one still answering there makes the next start do nothing.
        wait_for_ovis_to_stop() {
          for _ in $(seq 30); do
            ${pkgs.curl}/bin/curl -fs --max-time 1 http://127.0.0.1:${toString port}/api/health >/dev/null || return 0
            sleep 1
          done
          echo "warning: Ovis is still answering on port ${toString port} 30 seconds after being stopped" >&2
        }

        restart=0
        if [ "$(${installedCommit pluginId})" != ${commit} ]; then
          if $DRY_RUN_CMD env PATH="${
            lib.makeBinPath [
              pkgs.bun
              pkgs.nodejs
              pkgs.git
              pkgs.curl
            ]
          }:$PATH" "${herdr}" plugin install devswha/ovis --ref ${commit} --yes; then
            restart=1
          else
            echo "warning: installing Ovis v${version} failed (above); retry with: ${installCommand}" >&2
          fi
        fi

        if [ -z "$DRY_RUN_CMD" ] && [ "$(${installedCommit pluginId})" = ${commit} ]; then
          # Stopped before the new server first starts, which moves the old one's state over.
          if [ -n "$(${installedCommit legacyPluginId})" ]; then
            "${herdr}" plugin action invoke ${legacyPluginId}.stop >/dev/null
            wait_for_ovis_to_stop
            "${herdr}" plugin uninstall ${legacyPluginId} \
              || echo "warning: uninstalling ${legacyPluginId} failed (above); retry with: herdr plugin uninstall ${legacyPluginId}" >&2
            restart=1
          fi
          # So the host built above is the only Rust one Ovis can run.
          root="$(${pluginRoot})"
          for file in ${lib.escapeShellArgs downloadedHost}; do
            rm -f "$root/$file"
          done
          if [ "$restart" = 1 ]; then
            # Otherwise the new checkout only starts the next time herdr does.
            "${herdr}" plugin action invoke ${pluginId}.stop >/dev/null
            wait_for_ovis_to_stop
            "${herdr}" plugin action invoke ${pluginId}.start >/dev/null
          fi
        fi
      '';

  tailscaleServe.apps.ovis = {
    inherit httpsPort;
    localPort = port;
    link = {
      name = "Ovis";
      description = "herdr's agents and terminals, from your phone";
    };
  };
}
