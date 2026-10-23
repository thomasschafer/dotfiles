# Serves apps to my other devices with Tailscale Serve, which also gives them the HTTPS that
# phones need for PWAs and the microphone. Each app's module declares it under
# tailscaleServe.apps, and every switch makes `tailscale serve` match (see
# tools/tailscale-serve.sh), only warning if Tailscale isn't set up yet. Each app gets its own
# HTTPS port on this Mac's tailnet address, as separate hostnames (Tailscale Services) need the
# Mac to be a tagged device. setup.sh prints each app's link, and reports any that isn't served.
{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (lib) mkOption types;
  background = import ./background-app.nix { inherit config lib; };
  apps = config.tailscaleServe.apps;

  tailscaleServe = pkgs.writeShellScriptBin "tailscale-serve" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnused
        pkgs.jq
      ]
    }:$PATH"
    export TAILSCALE_SERVE_CONFIG=${pkgs.writeText "tailscale-serve-apps.json" (builtins.toJSON apps)}
    export TAILSCALE_SERVE_STATE=${lib.escapeShellArg "${background.stateDir "tailscale-serve"}/ports"}
    export TAILSCALE_CLIS=${lib.escapeShellArg (lib.concatStringsSep ":" background.tailscaleClis)}
    ${lib.toShellVars background.tailscaleEnvironment}
    export ${lib.concatStringsSep " " (lib.attrNames background.tailscaleEnvironment)}
    exec ${lib.getExe pkgs.bash} ${../tools/tailscale-serve.sh} "$@"
  '';

  duplicates =
    field:
    lib.filterAttrs (_: names: lib.length names > 1) (
      lib.groupBy (name: toString apps.${name}.${field}) (lib.attrNames apps)
    );
  duplicateAssertion = field: {
    assertion = duplicates field == { };
    message = "tailscaleServe.apps share a ${field}: ${
      lib.concatStringsSep "; " (
        lib.mapAttrsToList (port: names: "${port} (${lib.concatStringsSep ", " names})") (duplicates field)
      )
    }";
  };
in
{
  options.tailscaleServe.apps = mkOption {
    default = { };
    description = "Apps served over HTTPS on the tailnet, by name.";
    type = types.attrsOf (
      types.submodule {
        options = {
          httpsPort = mkOption {
            type = types.port;
            description = "The HTTPS port on this Mac's tailnet address; 443 is the bare address.";
          };
          localPort = mkOption {
            type = types.port;
            description = "The port the app listens on, on 127.0.0.1.";
          };
          pathCommand = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              A command printing the path to open on a phone, such as one with an access token, if
              not /. Run by `tailscale-serve check`, with pipefail.
            '';
          };
        };
      }
    );
  };

  config = {
    assertions = [
      (duplicateAssertion "httpsPort")
      (duplicateAssertion "localPort")
    ];

    home.packages = [ tailscaleServe ];

    # Also runs with no apps, to turn off any served before.
    home.activation.tailscaleServe = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${lib.getExe tailscaleServe} apply \
        || echo "warning: serving apps over Tailscale failed; fix it, then run: tailscale-serve apply" >&2
    '';
  };
}
