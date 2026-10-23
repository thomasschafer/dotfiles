# Helpers for modules that run an app in the background as launchd agents, logging to files in
# the app's state directory.
{ config, lib }:

let
  home = config.home.homeDirectory;
in
rec {
  stateDir = app: "${home}/.local/state/${app}";

  # Agents don't get a login shell's PATH; these are the system directories to end it with.
  systemPath = [
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];

  # Where the tailscale CLI can be: in /usr/local/bin if it was installed from the Tailscale
  # app's settings, and always inside the app.
  tailscaleClis = [
    "/usr/local/bin/tailscale"
    "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
  ];

  # For agents that run `tailscale`: its directories for PATH (macOS's filesystem ignores case, so
  # `tailscale` finds the app's binary too), and the environment to run it with. The app's binary
  # only acts as the CLI when it seems to be run from a terminal, unless TAILSCALE_BE_CLI is set,
  # so under launchd it would otherwise try to start the app.
  tailscalePath = map dirOf tailscaleClis;
  tailscaleEnvironment.TAILSCALE_BE_CLI = "1";

  # An activation step creating the state directory, as launchd can't open log files in a
  # directory that doesn't exist yet. It's private, as logs can hold secrets such as Workshop's
  # access link.
  createStateDir =
    app:
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg (stateDir app)}
      $DRY_RUN_CMD chmod 700 ${lib.escapeShellArg (stateDir app)}
    '';

  # An agent that starts at login and is restarted, no more than every 10 seconds, according to
  # keepAlive. Its output goes to `log` in the app's state directory.
  agent =
    {
      app,
      log,
      programArguments,
      path,
      keepAlive,
      workingDirectory ? null,
      environment ? { },
    }:
    {
      enable = true;
      config = {
        ProgramArguments = programArguments;
        RunAtLoad = true;
        KeepAlive = keepAlive;
        ThrottleInterval = 10;
        StandardOutPath = "${stateDir app}/${log}";
        StandardErrorPath = "${stateDir app}/${log}";
        EnvironmentVariables = {
          PATH = lib.concatStringsSep ":" (path ++ systemPath);
        }
        // environment;
      }
      // lib.optionalAttrs (workingDirectory != null) { WorkingDirectory = workingDirectory; };
    };
}
