# Settings that vary between machines. Each host in ./hosts sets all of them; none
# have defaults, so adding a setting here means deciding its value for every host.
{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options = {
    username = mkOption {
      type = types.str;
      description = "macOS account that owns the Home Manager configuration.";
    };

    autohideDock = mkOption {
      type = types.bool;
      description = "Whether the Dock hides when not in use.";
    };

    homebrew.pruneOldVersions = mkOption {
      type = types.bool;
      description = ''
        Whether to run `brew cleanup` on activation. This prunes outdated versions and
        caches only: formulae dropped from the Brewfile are not uninstalled, so run
        `brew bundle cleanup --force` by hand for that.
      '';
    };

    enablePython = mkOption {
      type = types.bool;
      description = "Whether to install Python with pip from nixpkgs.";
    };

    enableTailscale = mkOption {
      type = types.bool;
      description = "Whether to install the Tailscale app.";
    };

    enableDependabotReview = mkOption {
      type = types.bool;
      description = "Whether to install the weekly Dependabot review job (see dependabot-review/README.md).";
    };

    enableHealthTracking = mkOption {
      type = types.bool;
      description = "Whether to run the health-tracking app and its backups (see modules/health-tracking.nix).";
    };

    enableWorkshop = mkOption {
      type = types.bool;
      description = "Whether to run the Workshop server in the background (see modules/workshop.nix).";
    };

    enableAlmanac = mkOption {
      type = types.bool;
      description = "Whether to run Almanac in the background (see modules/almanac.nix).";
    };

    enableOvis = mkOption {
      type = types.bool;
      description = "Whether to install Ovis, to use herdr from my phone (see modules/ovis.nix).";
    };

    enableTodoistBackup = mkOption {
      type = types.bool;
      description = "Whether to back up Todoist every few hours (see todoist-backup/README.md).";
    };
  };
}
