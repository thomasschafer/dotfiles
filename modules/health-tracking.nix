# Runs the health-tracking app (github.com/thomasschafer/health-tracking) and its Litestream
# replication to Cloudflare R2 as launchd agents. home.nix clones the repo, and setup.sh runs
# its scripts/setup-machine.sh, which restores the database and writes the settings file the
# agents wait for. See docs/operations.md in that repo.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  background = import ./background-app.nix { inherit config lib; };
  home = config.home.homeDirectory;
  repo = "${home}/Development/Personal/health-tracking";
  envFile = "${home}/.config/health-tracking/env";
  binPath = lib.makeBinPath [
    pkgs.nodejs_26
    pkgs.litestream
    pkgs.git
  ];

  agent =
    { script, log }:
    background.agent {
      app = "health-tracking";
      inherit log;
      path = [ binPath ];
      programArguments = [ "${repo}/scripts/${script}" ];
      # Runs, and restarts after any exit, only while the settings file exists. Nothing starts
      # before setup-machine.sh has restored the database, so an empty database can't be
      # replicated over the backup.
      keepAlive.PathState.${envFile} = true;
    };
in
{
  home.activation = {
    createHealthTrackingStateDir = background.createStateDir "health-tracking";

    # Builds the app after the first clone, before the agents load. Later builds go through
    # the repo's scripts/deploy.sh.
    buildHealthTracking = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "cloneHealthTracking" ] ''
      if [ ! -f "${repo}/dist/client/index.html" ]; then
        export PATH="${lib.concatStringsSep ":" ([ binPath ] ++ background.systemPath)}:$PATH"
        cd "${repo}"
        $DRY_RUN_CMD npm ci --no-audit --no-fund
        $DRY_RUN_CMD npm run build
      fi
    '';
  };

  launchd.agents = {
    health-tracking-server = agent {
      script = "start-server.sh";
      log = "server.log";
    };
    health-tracking-litestream = agent {
      script = "start-litestream.sh";
      log = "litestream.log";
    };
  };
}
