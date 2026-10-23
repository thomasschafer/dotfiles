# Runs Almanac (github.com/thomasschafer/almanac) as a launchd agent, from the release deployed
# with `deploy almanac [ref]` (see deploy.nix). home.nix clones the repo. It's served at this
# Mac's bare tailnet address, as it links to the other apps. Its data, in ~/.local/share/almanac,
# isn't backed up.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  background = import ./background-app.nix { inherit config lib; };
  home = config.home.homeDirectory;
  inherit (config.deploy.apps.almanac) current;
  port = 8790;
  binPath = lib.makeBinPath [
    pkgs.nodejs_26
    pkgs.git
  ];
in
{
  home.activation.createAlmanacStateDir = background.createStateDir "almanac";

  deploy.apps.almanac = {
    repo = "${home}/Development/Personal/almanac";
    after = [ "cloneAlmanac" ];
    path = [ binPath ];
    build = ''
      npm ci --no-audit --no-fund
      npm run build
    '';
    agents = [ "almanac" ];
    agentNotes = ''
      - The deployed server listens on 127.0.0.1:${toString port}, with its data in
        `~/.local/share/almanac`. `npm run dev:server` uses 8791, with its data in `.dev-data`,
        and the e2e tests use 8792.
    '';
  };

  tailscaleServe.apps.almanac = {
    httpsPort = 443;
    localPort = port;
  };

  launchd.agents.almanac = background.agent {
    app = "almanac";
    log = "server.log";
    programArguments = [
      (lib.getExe pkgs.nodejs_26)
      "${current}/src/server/main.ts"
    ];
    workingDirectory = current;
    # The server only accepts requests from the Tailscale login it reads at startup, and exits if
    # Tailscale isn't up yet, so it's restarted until it is.
    keepAlive = true;
    path = [ binPath ] ++ background.tailscalePath;
    environment = background.tailscaleEnvironment // {
      ALMANAC_PORT = toString port;
    };
  };
}
