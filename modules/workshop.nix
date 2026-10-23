# Runs Workshop (github.com/thomasschafer/workshop) as a launchd agent, so the server is always
# up on the tailnet. It runs the release deployed with `deploy workshop [ref]` (see deploy.nix),
# so edits in the checkout only go live once committed and deployed. home.nix clones the repo,
# and the advent-of-code repo it keeps solutions in. Its output is in
# ~/.local/state/workshop/server.log.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  background = import ./background-app.nix { inherit config lib; };
  home = config.home.homeDirectory;
  inherit (config.deploy.apps.workshop) current;
  port = 7878;
  workshop = pkgs.writeShellScriptBin "workshop" ''
    if [ ! -x ${lib.escapeShellArg "${current}/workshop"} ]; then
      echo "workshop isn't deployed yet; run: deploy workshop" >&2
      exit 1
    fi
    exec ${lib.escapeShellArg "${current}/workshop"} "$@"
  '';
  # Workshop runs the model CLIs (in ~/.local/bin), tailscale, and the toolchains solutions are
  # built with, so it needs what a login shell would find. Builds use mise for the repo's own
  # tools (Rust, Node).
  path = [
    "${home}/.local/bin"
    "${config.home.profileDirectory}/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/local/bin"
    "/opt/homebrew/bin"
  ];
in
{
  home.packages = [
    # For dictation, which is more accurate with code than phones' own speech recognition.
    pkgs.whisper-cpp
    # The deployed CLI, for `workshop doctor`, `workshop run` and so on.
    workshop
  ];

  # Workshop only writes its config on first run, and keeps choices made in the app in
  # settings.json instead, so it can be managed here. Anything not set has Workshop's default
  # (see config.example.toml in its repo).
  home.file."Library/Application Support/workshop/config.toml" = {
    force = true;
    text = ''
      [server]
      bind = "127.0.0.1:${toString port}"

      [solutions]
      dir = "${home}/Development/Personal/advent-of-code"
      commit_after_star = true

      # Some older solutions take a few minutes.
      [run]
      timeout_secs = 300
    '';
    # The server reads its config at startup, so restart it to pick up a change. Before the
    # agent is first loaded, there's nothing to restart.
    onChange = ''
      agent="gui/$(id -u)/org.nix-community.home.workshop"
      if /bin/launchctl print "$agent" >/dev/null 2>&1; then
        /bin/launchctl kickstart -k "$agent"
      fi
    '';
  };

  home.activation.createWorkshopStateDir = background.createStateDir "workshop";

  deploy.apps.workshop = {
    repo = "${home}/Development/Personal/workshop";
    after = [ "cloneWorkshop" ];
    path = [ (lib.makeBinPath [ pkgs.mise ]) ] ++ path;
    # The release binary has the frontend built in. Builds share a target directory, so each
    # deploy only rebuilds what changed. mise only runs tasks from directories it trusts.
    build = ''
      export CARGO_TARGET_DIR="$DEPLOY_DIR/cargo-target"
      export MISE_TRUSTED_CONFIG_PATHS="$PWD"
      mise run build
      cp "$CARGO_TARGET_DIR/release/workshop" workshop
    '';
    agents = [ "workshop" ];
    agentNotes = ''
      - The deployed server listens on 127.0.0.1:${toString port} and keeps its state in
        `~/Library/Application Support/workshop`. `mise run dev` runs a separate copy on 7879, with
        its state in `.dev`.
      - `workshop token --tailscale`, `mise run serve` and `workshop serve --tailscale` without
        `--https-port` serve Workshop on HTTPS port 443, replacing the app the dotfiles serve
        there, so don't run them here. `mise run dev --tailscale` uses its own port.
    '';
  };

  # Rather than `workshop serve --tailscale`, so every app is served the same way.
  tailscaleServe.apps.workshop = {
    httpsPort = 8444;
    localPort = port;
    # The link has the access token.
    pathCommand = "${lib.getExe workshop} token | grep -oE '/\\?token=[^[:space:]]+'";
  };

  launchd.agents.workshop = background.agent {
    app = "workshop";
    log = "server.log";
    programArguments = [
      "${current}/workshop"
      "serve"
    ];
    workingDirectory = current;
    keepAlive = true;
    inherit path;
  };
}
