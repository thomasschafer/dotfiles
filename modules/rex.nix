# Rex (superlogical.com/rex), alongside herdr. The beta app is installed by hand, as it has no
# cask; until it is, the steps below that need its CLI skip themselves. Its appearance settings
# are macOS defaults, in macos/defaults.toml.
{
  config,
  lib,
  ...
}:

let
  # The app's CLI. Rex terminals have it on PATH (see zsh/.zshrc), but activation doesn't.
  rex = "/Applications/Rex Beta.app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex";
  ifRexInstalled = script: ''
    if [ -x ${lib.escapeShellArg rex} ]; then
      ${script}
    else
      echo "Rex isn't installed at ${rex}, so its setup was skipped" >&2
    fi
  '';
in
{
  home.file.".config/rex/init.lua".source = ../rex/init.lua;

  home.activation = {
    # Rex doesn't watch its config file. --autostart=false leaves a stopped server stopped, as
    # it reads the file when it next starts.
    reloadRexConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] (ifRexInstalled ''
      if ${lib.escapeShellArg rex} --autostart=false server status >/dev/null 2>&1; then
        $DRY_RUN_CMD ${lib.escapeShellArg rex} --autostart=false config reload >/dev/null
      fi
    '');

    # Installs Rex's agent skill and its session-start hook, which does nothing outside Rex.
    # After setClaudeSettings, whose merge keeps the hook Rex adds to Claude Code's settings.
    setupRexForAgents = lib.hm.dag.entryAfter [ "setClaudeSettings" ] (ifRexInstalled ''
      $DRY_RUN_CMD ${lib.escapeShellArg rex} skill setup --agent claude --agent codex --agent opencode >/dev/null
    '');
  };
}
