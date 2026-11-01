# codex/config.py, which edits Codex's config.toml without disturbing the rest of it.
{ pkgs }:
pkgs.writers.writePython3Bin "codex-config" {
  libraries = [ pkgs.python3Packages.tomlkit ];
  flakeIgnore = [ "E501" ];
} (builtins.readFile ../codex/config.py)
