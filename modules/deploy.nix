# `deploy <app> [ref]` for apps that run from a committed revision rather than their checkout
# (see tools/deploy.sh). Each app's module declares it under deploy.apps and points its launchd
# agents at deploy.apps.<app>.current. The first switch after enabling an app deploys it, before
# its agents load.
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
  };
}
