# Home Manager module for the weekly Dependabot review job: the tools it needs and an
# hourly trigger (launchd on macOS, a systemd user timer on Linux). The scripts run
# from a store copy, so the job uses the code from the last switch rather than
# whatever happens to be checked out.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  isDarwin = pkgs.stdenv.isDarwin;
  src = ./..;
  stateDir = "${config.home.homeDirectory}/.local/state/dependabot-review";
  tools = with pkgs; [
    bash
    colima
    curl
    docker-client
    gh
    git
    jq
    lima
    yq-go
  ];
  path = lib.concatStringsSep ":" [
    (lib.makeBinPath tools)
    "${config.home.homeDirectory}/.local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in
{
  home.packages = tools;

  # launchd can't open its log file if the directory doesn't exist yet.
  home.activation.createDependabotReviewStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg stateDir}
  '';

  # launchd runs a StartInterval job on wake if the interval passed during sleep, and
  # RunAtLoad covers login. The run script decides whether a review is actually due.
  launchd.agents.dependabot-review = lib.mkIf isDarwin {
    enable = true;
    config = {
      ProgramArguments = [ "${src}/run" ];
      StartInterval = 3600;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "${stateDir}/launchd.log";
      StandardErrorPath = "${stateDir}/launchd.log";
      EnvironmentVariables.PATH = path;
    };
  };

  systemd.user.services.dependabot-review = lib.mkIf (!isDarwin) {
    Unit.Description = "Weekly Dependabot PR review";
    Service = {
      Type = "oneshot";
      ExecStart = "${src}/run";
      Environment = [ "PATH=${path}" ];
    };
  };

  systemd.user.timers.dependabot-review = lib.mkIf (!isDarwin) {
    Unit.Description = "Trigger the Dependabot PR review hourly";
    Timer = {
      OnCalendar = "hourly";
      OnStartupSec = "5min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
