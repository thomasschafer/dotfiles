{ pkgs, hostConfig, ... }:
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

  # The platform the configuration will be used on.
  nixpkgs.hostPlatform = "aarch64-darwin";
}
