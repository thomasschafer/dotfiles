{
  description = "Nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nix-darwin,
      nixpkgs,
      home-manager,
    }:
    let
      inherit (nixpkgs) lib;

      hosts = lib.attrNames (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir ./modules/hosts)
      );

      # Evaluated against the declared options so that a missing, misspelt or
      # wrongly typed setting fails the build rather than falling back to a default.
      loadHostConfig =
        host:
        (lib.evalModules {
          modules = [
            ./modules/host-options.nix
            ./modules/hosts/${host}
          ];
        }).config;

      mkDarwinSystem =
        host:
        let
          hostConfig = loadHostConfig host;
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit self hostConfig;
          };
          modules = [
            ./modules/darwin.nix
            home-manager.darwinModules.home-manager
            { users.users.${hostConfig.username}.home = /Users/${hostConfig.username}; }
            {
              home-manager = {
                backupFileExtension = "bak";
                overwriteBackup = true;
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit hostConfig; };
                users.${hostConfig.username} = import ./modules/home.nix;
              };
            }
          ];
        };
    in
    {
      darwinConfigurations = lib.genAttrs hosts mkDarwinSystem;

      # Read by setup.sh to decide which steps to run outside of Nix.
      hostConfigs = lib.genAttrs hosts loadHostConfig;
    };
}
