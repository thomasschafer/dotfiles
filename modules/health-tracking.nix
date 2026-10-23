# Runs the health-tracking app (github.com/thomasschafer/health-tracking) and its Litestream
# replication to Cloudflare R2 as launchd agents, from the release deployed with
# `deploy health-tracking [ref]` (see deploy.nix). home.nix clones the repo, and setup.sh runs
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
  port = 8787;
  inherit (config.deploy.apps.health-tracking) current;
  binPath = lib.makeBinPath [
    pkgs.nodejs_26
    pkgs.litestream
    pkgs.git
  ];

  agent =
    {
      script,
      log,
      environment ? { },
    }:
    background.agent {
      app = "health-tracking";
      inherit log environment;
      # The server only accepts requests from the Tailscale login it reads at startup.
      path = [ binPath ] ++ background.tailscalePath;
      programArguments = [ "${current}/scripts/${script}" ];
      # Runs, and restarts after any exit, only while the settings file exists. Nothing starts
      # before setup-machine.sh has restored the database, so an empty database can't be
      # replicated over the backup.
      keepAlive.PathState.${envFile} = true;
    };
in
{
  home.activation.createHealthTrackingStateDir = background.createStateDir "health-tracking";

  deploy.apps.health-tracking = {
    inherit repo;
    after = [ "cloneHealthTracking" ];
    path = [ binPath ];
    build = ''
      npm ci --no-audit --no-fund
      npm run build
    '';
    agents = [
      "health-tracking-server"
      "health-tracking-litestream"
    ];
    agentNotes = ''
      - `~/.local/share/health-tracking` holds real health data, which Litestream replicates to
        R2. Never write to it; `npm run dev:seed` copies it into `.dev-data` to develop against.
      - The deployed server listens on 127.0.0.1:${toString port}; `npm run dev:server` uses 8789.
    '';
  };

  tailscaleServe.apps.health-tracking = {
    httpsPort = 8443;
    localPort = port;
  };

  launchd.agents = {
    health-tracking-server = agent {
      script = "start-server.sh";
      log = "server.log";
      environment = background.tailscaleEnvironment // {
        HEALTH_PORT = toString port;
      };
    };
    health-tracking-litestream = agent {
      script = "start-litestream.sh";
      log = "litestream.log";
    };
  };
}
