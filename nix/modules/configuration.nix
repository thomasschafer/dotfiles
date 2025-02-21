{
  pkgs,
  lib,
  hostConfig,
  ...
}:
{
  imports = [
    ./system.nix
    ./macos.nix
    ./packages.nix
  ];

  # Necessary because we are using the Determinate Systems installer
  nix.enable = false;

  # Necessary for using flakes on this system.
  nix.settings.experimental-features = "nix-command flakes";

  # Fix for https://github.com/NixOS/nix/issues/2982 - TODO is there a better way of doing this?
  nix.nixPath = [
    "nixpkgs=${pkgs.path}"
    "/nix/var/nix/profiles/per-user/root/channels"
  ];

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
  };
}
