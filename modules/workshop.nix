# Runs Workshop (github.com/thomasschafer/workshop) in dev mode as a launchd agent, so the
# server is always up on the tailnet and rebuilds and restarts as the checkout changes. home.nix
# clones the repo, and the advent-of-code repo it keeps solutions in; edits to Workshop go live
# once they build. Its output is in ~/.local/state/workshop/dev.log.
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

  # Workshop only writes its config on first run, and keeps choices made in the app in
  # settings.json instead, so it can be managed here. Anything not set has Workshop's default
  # (see config.example.toml in its repo).
  home.file."Library/Application Support/workshop/config.toml" = {
    force = true;
    text = ''
      [solutions]
      dir = "${home}/Development/Personal/advent-of-code"
      commit_after_star = true

      # Some older solutions take a few minutes.
      [run]
      timeout_secs = 300
    '';
    # The server reads its config at startup, so restart it to pick up a change. Before the
    # agent is first loaded, there's nothing to restart.
    onChange = ''
      agent="gui/$(id -u)/org.nix-community.home.workshop"
      if /bin/launchctl print "$agent" >/dev/null 2>&1; then
        /bin/launchctl kickstart -k "$agent"
      fi
    '';
  };

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
