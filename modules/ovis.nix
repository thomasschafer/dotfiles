# Ovis (github.com/devswha/ovis), the browser and phone client for herdr, installed as a herdr
# plugin that starts with herdr. It's served over Tailscale like the background apps; with no
# token set, it only lets in requests that Tailscale Serve says come from this Mac's own login.
#
# Setup installs the release pinned below, and reinstalls it whenever the plugin is at another
# commit. To update, check that the release's tag is on main and has a passing release build,
# then change both version and commit. Don't use Update in the app: it takes any tag on the
# repo, unsigned, and runs it in place of the pin, which setup then reports.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;
  herdr = "${home}/.cargo/bin/herdr";
  version = "0.4.13";
  # The commit v${version} tagged, pinned rather than the tag, as tags can be moved.
  commit = "d5a35b7a44ad864ec75581457bfcaa144b22a9e5";
  # The plugin's id and settings' names from before the rename to Ovis, which v0.4.13 predates.
  # Later releases still read these settings, but take the new id, so check it when updating.
  pluginId = "devswha.herdr-web-ui";
  configDir = "${home}/.config/herdr/plugins/config/${pluginId}";
  port = 7317;
  httpsPort = 8445;

  # Settings the running server must have, which ovis-check confirms it got.
  required = {
    HERDR_WEB_TELEMETRY = "0";
    # Says Tailscale Serve is the only way in, so a request through anything else, such as a web
    # page rebound to 127.0.0.1, is refused even while Ovis doesn't know this Mac's login yet,
    # rather than let in while nothing is paired. It also lets my phone in without pairing, as
    # this tailnet has one login and no tagged devices; don't set it if that changes.
    HERDR_WEB_TAILSCALE_SERVE_ONLY = "1";
  };
  requiredLines = lib.mapAttrsToList (name: value: "${name}=${value}") required;
  installCommand = "herdr plugin install devswha/ovis --ref ${commit} --yes";
  # The commit the plugin is installed from, or nothing if it isn't installed.
  installedCommit = ''
    "${herdr}" plugin list --plugin ${pluginId} --json \
      | ${pkgs.jq}/bin/jq -r '.result.plugins[0].source.resolved_commit // empty'
  '';

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
      installed="$(${installedCommit})"
      if [ "$installed" != ${commit} ]; then
        echo "install Ovis v${version}, which the switch couldn't (it has ''${installed:-nothing}): ${installCommand}, then herdr plugin action invoke ${pluginId}.start"
        exit 0
      fi
      if ! curl -fsS --max-time 5 http://127.0.0.1:${toString port}/api/health 2>/dev/null \
          | jq -e '.ok == true' >/dev/null; then
        echo "start Ovis, which isn't answering on port ${toString port}: herdr plugin action invoke ${pluginId}.start (its logs: herdr plugin log list)"
        exit 0
      fi
      # v${version} keeps an in-app update's state per checkout and port, in a directory named
      # after them (updateStateDir in server/update-state.ts), and runs the release it records
      # while the checkout is at the commit that release was built on. Reinstalling gives the
      # plugin a new checkout, so none applies.
      root="$("${herdr}" plugin list --plugin ${pluginId} --json | jq -r '.result.plugins[0].plugin_root')"
      update_dir="$(printf '%s' "$root:${toString port}" | /usr/bin/shasum -a 256 | cut -c1-16)"
      current="${home}/.config/herdr-web-ui/updates/$update_dir/current.json"
      if [ -f "$current" ] \
          && jq -e --arg commit ${commit} '.source_revision == $commit and (.directory | type == "string")' "$current" >/dev/null; then
        echo "Ovis is running an in-app update rather than the pinned v${version}; to go back to the pin: ${installCommand}, then herdr plugin action invoke ${pluginId}.stop, then ${pluginId}.start"
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

  # Read by the plugin (see INSTALL.md in the repo); herdr gives it this config directory.
  home.file."${lib.removePrefix "${home}/" configDir}/env".text = ''
    ${lib.concatLines requiredLines}
    # Honoured whatever the telemetry setting is called, in case a release renames it.
    DO_NOT_TRACK=1
    # Pinned, as Ovis otherwise moves to another port when this one is taken, which Tailscale
    # Serve wouldn't follow.
    PORT=${toString port}
    HERDR_WEB_TAILSCALE_HTTPS_PORT=${toString httpsPort}
    # Files attached from the phone, which otherwise go in a folder in the pane's directory.
    HERDR_WEB_PASTE_DIR=${home}/.local/share/ovis/pastes
  '';

  # Installing builds the plugin and downloads its dependencies, so a failure (such as being
  # offline) only warns, and ovis-check reports it. It runs once the env file is linked and Bun
  # is in the profile, as herdr may start the plugin with its own PATH. Activation has no CA
  # certificates of its own, so git and Bun are given Nix's.
  home.activation.installOvis =
    lib.hm.dag.entryAfter
      [
        "installHerdr"
        "installPackages"
        "linkGeneration"
      ]
      ''
        installed="$(${installedCommit})"
        if [ "$installed" != ${commit} ]; then
          certs=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          if $DRY_RUN_CMD env SSL_CERT_FILE="$certs" NIX_SSL_CERT_FILE="$certs" PATH="${
            lib.makeBinPath [
              pkgs.bun
              pkgs.nodejs
              pkgs.git
              pkgs.curl
            ]
          }:$PATH" "${herdr}" plugin install devswha/ovis --ref ${commit} --yes; then
            # Stops the server the previous checkout started, if any, then starts this one, as
            # herdr otherwise only starts it the next time herdr starts.
            $DRY_RUN_CMD "${herdr}" plugin action invoke ${pluginId}.stop >/dev/null
            $DRY_RUN_CMD "${herdr}" plugin action invoke ${pluginId}.start >/dev/null
          else
            echo "warning: installing Ovis v${version} failed (above); retry with: ${installCommand}" >&2
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
