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
      mkHomeManagerConfig =
        hostConfig: host:
        {
          home-manager = {
            backupFileExtension = "bak";
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit hostConfig;
              host = host;
            };
            users.${hostConfig.username} = import ./modules/home.nix;
          };
        };

      mkDarwinSystem =
        host:
        let
          hostConfig = import ./modules/hosts/${host}.nix;
        in
        nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit self hostConfig;
            host = host;
          };
          modules = [
            ./modules/darwin.nix
            home-manager.darwinModules.home-manager
            {
              users.users.${hostConfig.username}.home = /Users/${hostConfig.username};
            }
            (mkHomeManagerConfig hostConfig host)
          ];
        };

      mkNixosSystem =
        host:
        let
          hostConfig = import ./modules/hosts/${host}.nix;
        in
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = {
            inherit self hostConfig;
            host = host;
          };
          modules = [
            ./modules/nixos.nix
            home-manager.nixosModules.home-manager
            (mkHomeManagerConfig hostConfig host)
          ];
        };
    in
    {
      darwinConfigurations = {
        personal = mkDarwinSystem "personal";
        work = mkDarwinSystem "work";
      };

      nixosConfigurations = {
        nix-server = mkNixosSystem "nix-server";
      };
    };
}
