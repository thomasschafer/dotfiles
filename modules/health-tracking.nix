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
  home = config.home.homeDirectory;
  repo = "${home}/Development/Personal/health-tracking";
  envFile = "${home}/.config/health-tracking/env";
  stateDir = "${home}/.local/state/health-tracking";
  path = lib.concatStringsSep ":" [
    (lib.makeBinPath [
      pkgs.nodejs_26
      pkgs.litestream
      pkgs.git
    ])
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];

  agent =
    { script, log }:
    {
      enable = true;
      config = {
        ProgramArguments = [ "${repo}/scripts/${script}" ];
        RunAtLoad = true;
        # Runs, and restarts after any exit, only while the settings file exists. Nothing
        # starts before setup-machine.sh has restored the database, so an empty database
        # can't be replicated over the backup.
        KeepAlive.PathState.${envFile} = true;
        ThrottleInterval = 10;
        StandardOutPath = "${stateDir}/${log}";
        StandardErrorPath = "${stateDir}/${log}";
        EnvironmentVariables.PATH = path;
      };
    };
in
{
  home.activation = {
    # launchd can't open its log files if the directory doesn't exist yet.
    createHealthTrackingStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg stateDir}
    '';

    # Builds the app after the first clone, before the agents load. Later builds go through
    # the repo's scripts/deploy.sh.
    buildHealthTracking = lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "cloneHealthTracking" ] ''
      if [ ! -f "${repo}/dist/client/index.html" ]; then
        export PATH="${path}:$PATH"
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
