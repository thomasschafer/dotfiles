# Rex (superlogical.com/rex), alongside the Herdr app. The beta app is installed by hand, as it has no
# cask; until it is, the steps below that need its CLI skip themselves. Its settings are macOS
# defaults, in macos/defaults.toml, apart from its theme, which importThemeIntoRex adds.
{
  config,
  pkgs,
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
  background = import ./background-app.nix { inherit config lib; };
  procinfo = pkgs.writers.writePython3Bin "rex-procinfo" {
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ../rex/procinfo.py);
  # rex/restore.lua, which starts programs again in their panes after the server restarts.
  # It needs a running server, which the app starts, so this waits for one rather than
  # failing every few seconds while there is none.
  restorePrograms = pkgs.writeShellScript "rex-restore" ''
    until [ -x ${lib.escapeShellArg rex} ] && ${lib.escapeShellArg rex} --autostart=false server status >/dev/null 2>&1; do
      sleep 5
    done
    exec ${lib.escapeShellArg rex} --autostart=false do --all ${../rex/restore.lua} \
      snapshot=${lib.escapeShellArg "${background.stateDir "rex-restore"}/programs.json"} \
      procinfo=${procinfo}/bin/rex-procinfo
  '';
  codexConfig = import ./codex-config.nix { inherit pkgs; };
  # The hook `rex skill setup` adds to Codex's hooks.json. If a new Rex changes it,
  # trustRexCodexHook fails until this matches again.
  rexCodexHookCommand = "/bin/sh -c 'rex __internal session-start --agent codex --feature-session-naming=false 2>/dev/null || true'";
  themeName = "Catppuccin Macchiato";
  # Ghostty's copy, which is also what Ghostty itself uses.
  themeFile = "/Applications/Ghostty.app/Contents/Resources/ghostty/themes/${themeName}";
in
{
  home.file.".config/rex/init.lua".source = ../rex/init.lua;

  home.activation = {
    createRexRestoreStateDir = background.createStateDir "rex-restore";

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

    # Codex skips a hook until it's approved, and approving Rex's by hand would need
    # redoing whenever its definition changes.
    trustRexCodexHook = lib.hm.dag.entryAfter [ "setupRexForAgents" ] (ifRexInstalled ''
      $DRY_RUN_CMD ${codexConfig}/bin/codex-config ${
        lib.escapeShellArgs [
          "trust-hook"
          "${config.home.homeDirectory}/.codex/hooks.json"
          "${config.home.homeDirectory}/.codex/config.toml"
          "SessionStart"
          rexCodexHookCommand
        ]
      }
    '');

    # Rex keeps imported themes as its own resolved palettes, so this imports the theme file
    # through the app rather than writing that format. The app has to be open, with Remote
    # Control on (set in macos/defaults.toml), and importing selects the theme.
    importThemeIntoRex = lib.hm.dag.entryAfter [ "writeBoundary" ] (ifRexInstalled ''
      rex_prefs=$(${pkgs.coreutils}/bin/mktemp)
      if /usr/bin/defaults export com.superlogical.rex "$rex_prefs" 2>/dev/null \
        && /usr/libexec/PlistBuddy -c 'Print :Workspace.customThemes' "$rex_prefs" 2>/dev/null \
          | /usr/bin/grep -qF '"name":"${themeName}"'; then
        :
      elif [ ! -f ${lib.escapeShellArg themeFile} ]; then
        echo "Can't import Rex's theme: ${themeFile} doesn't exist (it comes with Ghostty)" >&2
      elif ! rex_app=$(${lib.escapeShellArg rex} --autostart=false client ls --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -er 'first(.clients[] | select(.info.kind == "app" and .principal.transport == "unix") | .client_id)'); then
        echo "Open Rex and re-run setup to import its ${themeName} theme" >&2
      elif ! $DRY_RUN_CMD ${lib.escapeShellArg rex} --autostart=false -C "$rex_app" do client.theme.import path=${lib.escapeShellArg themeFile} >/dev/null; then
        echo "Importing Rex's ${themeName} theme failed (above); if Remote Control is off in Rex's settings, turn it on and re-run setup" >&2
      fi
      ${pkgs.coreutils}/bin/rm -f "$rex_prefs"
    '');
  };

  launchd.agents.rex-restore = background.agent {
    app = "rex-restore";
    log = "rex-restore.log";
    programArguments = [ "${restorePrograms}" ];
    keepAlive = true;
    path = [ ];
  };
}
