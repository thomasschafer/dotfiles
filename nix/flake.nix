{
  description = "Example nix-darwin system flake";

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
      mkDarwinSystem =
        host:
        let
          hostConfig = import ./modules/hosts/${host}.nix;
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit self hostConfig;
          };
          modules = [
            ./modules/configuration.nix
            home-manager.darwinModules.home-manager
            {
              users.users.${hostConfig.username}.home = /Users/${hostConfig.username};

              home-manager.backupFileExtension = "bak";
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.${hostConfig.username} = import ./modules/home.nix;
            }
          ];
        };
    in
    {
      darwinConfigurations = {
        personal = mkDarwinSystem "personal";
        work = mkDarwinSystem "work";
      };
    };
}
