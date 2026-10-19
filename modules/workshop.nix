# Runs Workshop (github.com/thomasschafer/workshop) in dev mode as a launchd agent, so the
# server is always up on the tailnet and rebuilds and restarts as the checkout changes. home.nix
# clones the repo; edits there go live once they build. Its output is in stateDir/dev.log.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  home = config.home.homeDirectory;
  repo = "${home}/Development/Personal/workshop";
  stateDir = "${home}/.local/state/workshop";
  # Workshop runs the model CLIs (in ~/.local/bin), tailscale, and the toolchains solutions are
  # built with, so it needs what a login shell would find. `mise run dev` adds the repo's own
  # tools (Rust, Node, watchexec) in front.
  path = lib.concatStringsSep ":" [
    "${home}/.local/bin"
    "${config.home.profileDirectory}/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/local/bin"
    "/opt/homebrew/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
in
{
  # For dictation, which is more accurate with code than phones' own speech recognition.
  home.packages = [ pkgs.whisper-cpp ];

  home.activation = {
    # launchd can't open its log file if the directory doesn't exist yet.
    createWorkshopStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg stateDir}
    '';
  };

  launchd.agents.workshop = {
    enable = true;
    config = {
      ProgramArguments = [
        (lib.getExe pkgs.mise)
        "run"
        "dev"
      ];
      WorkingDirectory = repo;
      RunAtLoad = true;
      KeepAlive = true;
      ThrottleInterval = 10;
      StandardOutPath = "${stateDir}/dev.log";
      StandardErrorPath = "${stateDir}/dev.log";
      EnvironmentVariables = {
        PATH = path;
        # Keeping the Mac awake is left to herdr's caffeinate plugin.
        WORKSHOP_KEEP_AWAKE = "0";
      };
    };
  };
}
