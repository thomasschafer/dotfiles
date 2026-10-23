# `deploy <app> [ref]` for apps that run from a committed revision rather than their checkout
# (see tools/deploy.sh). Each app's module declares it under deploy.apps and points its launchd
# agents at deploy.apps.<app>.current. The first switch after enabling an app deploys it, before
# its agents load. Each checkout also gets a CLAUDE.local.md telling agents how this machine runs
# the app, which only applies here, so it stays out of the repo.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) mkOption types;
  background = import ./background-app.nix { inherit config lib; };
  deploysDir = "${config.home.homeDirectory}/.local/share/deploys";
  apps = config.deploy.apps;

  appConfig = lib.mapAttrs (name: app: {
    inherit (app) repo;
    build = pkgs.writeShellScript "deploy-build-${name}" ''
      set -euo pipefail
      ${app.build}
    '';
    path = lib.concatStringsSep ":" (app.path ++ background.systemPath);
    labels = map (agent: config.launchd.agents.${agent}.config.Label) app.agents;
  }) apps;

  servedNote =
    name:
    let
      served = config.tailscaleServe.apps.${name};
    in
    lib.optionalString (config.tailscaleServe.apps ? ${name}) ''
      - The dotfiles serve it on the tailnet with Tailscale Serve, on HTTPS port
        ${toString served.httpsPort}. Never change `tailscale serve` yourself, as other apps
        share this Mac's address.
    '';

  agentInstructions =
    name: app:
    pkgs.writeText "${name}-CLAUDE.local.md" ''
      # This machine

      <!-- Written by the dotfiles (modules/deploy.nix), which replace it on every switch. -->

      This Mac runs a deployed copy of ${name} in the background, built from a commit rather than
      from this checkout, as the launchd agents ${
        lib.concatMapStringsSep " and " (label: "`${label}`") appConfig.${name}.labels
      }.

      - After pushing changes to `main`, deploy them with `deploy ${name}`. It builds `main` in its
        own copy and only restarts the agents if the build succeeds; check its output says they
        restarted.
      - To roll back, run `deploy ${name} <commit>` with an earlier commit.
      - Never stop, restart or reconfigure the agents yourself, or use the deployed copy's port or
        data for development. This repo's dev commands run separately.
      - `agents-status` shows whether the agents are running, and where their logs are.
      ${servedNote name}${app.agentNotes}
    '';

  deploy = pkgs.writeShellScriptBin "deploy" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.git
        pkgs.jq
      ]
    }:$PATH"
    export DEPLOY_CONFIG=${pkgs.writeText "deploy-apps.json" (builtins.toJSON appConfig)}
    export DEPLOYS_DIR=${lib.escapeShellArg deploysDir}
    exec ${lib.getExe pkgs.bash} ${../tools/deploy.sh} "$@"
  '';
in
{
  options.deploy.apps = mkOption {
    default = { };
    description = "Apps that `deploy` builds from a commit and restarts.";
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            repo = mkOption {
              type = types.str;
              description = "The checkout to deploy commits from.";
            };
            build = mkOption {
              type = types.lines;
              description = ''
                Builds the app in the release directory, a copy of the commit being deployed.
                DEPLOY_DIR is the app's directory under ${deploysDir}, for caches that should
                outlive a release.
              '';
            };
            path = mkOption {
              type = types.listOf types.str;
              description = "Directories put on PATH for the build, before the system ones.";
            };
            agents = mkOption {
              type = types.listOf types.str;
              description = "The launchd agents (names in launchd.agents) to restart after deploying.";
            };
            after = mkOption {
              type = types.listOf types.str;
              default = [ "writeBoundary" ];
              description = "Activation steps that must run before the first deploy, such as cloning the repo.";
            };
            agentNotes = mkOption {
              type = types.lines;
              default = "";
              description = "More about how this machine runs the app, for the checkout's CLAUDE.local.md.";
            };
            current = mkOption {
              type = types.str;
              readOnly = true;
              default = "${deploysDir}/${name}/current";
              description = "The deployed release, for agents to run from.";
            };
          };
        }
      )
    );
  };

  config = lib.mkIf (apps != { }) {
    home.packages = [ deploy ];

    # A failed first deploy only warns, so it doesn't stop the rest of the switch; the app's
    # agents then fail to start, which setup.sh reports.
    home.activation.deployApps =
      lib.hm.dag.entryBetween [ "setupLaunchAgents" ]
        (lib.concatMap (app: app.after) (lib.attrValues apps))
        (
          lib.concatMapStrings (name: ''
            if [ ! -e ${lib.escapeShellArg apps.${name}.current} ]; then
              $DRY_RUN_CMD ${lib.getExe deploy} ${name} \
                || echo "warning: deploying ${name} failed; fix it, then run: deploy ${name}" >&2
            fi
          '') (lib.attrNames apps)
        );

    # Linked after cloning, as creating the file first would create the checkout's directory and
    # stop the clone. A CLAUDE.local.md written by hand is left alone.
    home.activation.linkAgentInstructions =
      lib.hm.dag.entryAfter (lib.concatMap (app: app.after) (lib.attrValues apps))
        (
          lib.concatStrings (
            lib.mapAttrsToList (name: app: ''
              instructions=${lib.escapeShellArg "${app.repo}/CLAUDE.local.md"}
              if [ -e "$instructions" ] && [ ! -L "$instructions" ]; then
                echo "warning: not replacing $instructions, which isn't from the dotfiles" >&2
              elif [ -d ${lib.escapeShellArg app.repo} ]; then
                $DRY_RUN_CMD ln -sfn ${agentInstructions name app} "$instructions"
              fi
            '') apps
          )
        );
  };
}
