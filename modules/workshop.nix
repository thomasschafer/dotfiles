# Runs Workshop (github.com/thomasschafer/workshop) in dev mode as a launchd agent, so the
# server is always up on the tailnet and rebuilds and restarts as the checkout changes. home.nix
# clones the repo; edits there go live once they build. Its output is in
# ~/.local/state/workshop/dev.log.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  background = import ./background-app.nix { inherit config lib; };
  home = config.home.homeDirectory;
in
{
  # For dictation, which is more accurate with code than phones' own speech recognition.
  home.packages = [ pkgs.whisper-cpp ];

  home.activation.createWorkshopStateDir = background.createStateDir "workshop";

  launchd.agents.workshop = background.agent {
    app = "workshop";
    log = "dev.log";
    programArguments = [
      (lib.getExe pkgs.mise)
      "run"
      "dev"
    ];
    workingDirectory = "${home}/Development/Personal/workshop";
    keepAlive = true;
    # Workshop runs the model CLIs (in ~/.local/bin), tailscale, and the toolchains solutions
    # are built with, so it needs what a login shell would find. `mise run dev` adds the repo's
    # own tools (Rust, Node, watchexec) in front.
    path = [
      "${home}/.local/bin"
      "${config.home.profileDirectory}/bin"
      "/run/current-system/sw/bin"
      "/nix/var/nix/profiles/default/bin"
      "/usr/local/bin"
      "/opt/homebrew/bin"
    ];
    # Keeping the Mac awake is left to herdr's caffeinate plugin.
    environment.WORKSHOP_KEEP_AWAKE = "0";
  };
}
