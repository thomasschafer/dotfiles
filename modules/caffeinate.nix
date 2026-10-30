# Keeps the Mac awake while idle, and while on power, as a launchd agent. Its output is in
# ~/.local/state/caffeinate/caffeinate.log.
{
  config,
  lib,
  ...
}:

let
  background = import ./background-app.nix { inherit config lib; };
in
{
  home.activation.createCaffeinateStateDir = background.createStateDir "caffeinate";

  launchd.agents.caffeinate = background.agent {
    app = "caffeinate";
    log = "caffeinate.log";
    programArguments = [
      "/usr/bin/caffeinate"
      "-is"
    ];
    keepAlive = true;
    path = [ ];
  };
}
