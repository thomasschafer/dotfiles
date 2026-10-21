# The `agents-status` command (see tools/agents-status.sh), covering every launchd agent with
# KeepAlive set. Agents that run on a schedule, such as the backups, alert on their own.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  kept = lib.filterAttrs (_: agent: agent.enable && agent.config.KeepAlive != null) (
    config.launchd.agents
  );
  agentsFile = pkgs.writeText "agents" (
    lib.concatStrings (
      lib.mapAttrsToList (
        name: agent: "${name}\t${agent.config.Label}\t${agent.config.StandardOutPath}\n"
      ) kept
    )
  );
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "agents-status" ''
      export AGENTS_FILE=${agentsFile}
      exec ${lib.getExe pkgs.bash} ${../tools/agents-status.sh} "$@"
    '')
  ];
}
