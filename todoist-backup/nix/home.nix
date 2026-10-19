# Home Manager module for the read-only Todoist backup: a `todoist-backup` command and a
# launchd agent that runs it every four hours. Like dependabot-review, it runs from a store
# copy, so the job uses the code from the last switch. The data lives in a separate repo
# in ~/.local/share/todoist-backup, never in the dotfiles.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  src = ./..;
  stateDir = "${config.home.homeDirectory}/.local/state/todoist-backup";
  python = pkgs.python314;
  tools = with pkgs; [
    git
    openssh
    terminal-notifier
    uv
  ];
  path = lib.concatStringsSep ":" [
    (lib.makeBinPath tools)
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];
  todoistBackup = pkgs.writeShellScriptBin "todoist-backup" ''
    export PATH="${path}:$PATH"
    export UV_PYTHON_DOWNLOADS=never
    exec ${lib.getExe pkgs.uv} run --quiet --python ${lib.getExe python} --script \
      ${src}/todoist-backup "$@"
  '';
in
{
  home.packages = [ todoistBackup ];

  # launchd can't open its log file if the directory doesn't exist yet.
  home.activation.createTodoistBackupStateDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg stateDir}
  '';

  # launchd runs a StartInterval job on wake if the interval passed during sleep, and
  # RunAtLoad covers login.
  launchd.agents.todoist-backup = {
    enable = true;
    config = {
      ProgramArguments = [
        (lib.getExe todoistBackup)
        "run"
      ];
      StartInterval = 4 * 3600;
      RunAtLoad = true;
      ProcessType = "Background";
      StandardOutPath = "${stateDir}/launchd.log";
      StandardErrorPath = "${stateDir}/launchd.log";
    };
  };
}
