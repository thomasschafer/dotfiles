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

  nix = {
    # Necessary because we are using the Determinate Systems installer
    enable = false;

    settings.experimental-features = "nix-command flakes";

    # Fix for https://github.com/NixOS/nix/issues/2982 - TODO is there a better way of doing this?
    nixPath = [
      "nixpkgs=${pkgs.path}"
      "/nix/var/nix/profiles/per-user/root/channels"
    ];
  };

  # Required for user-specific options like Homebrew and system defaults
  system.primaryUser = hostConfig.username;

  nixpkgs = {
    hostPlatform = "aarch64-darwin";
    config.allowUnfree = true;
  };
}
