{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nix-darwin,
      nixpkgs,
    }:
    {
      # Build flake using either of:
      #  `darwin-rebuild switch --flake .#personal`
      #  `darwin-rebuild switch --flake .#work`
      darwinConfigurations = {
        personal = nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit self;
            hostConfig = import ./modules/hosts/personal.nix;
          };
          modules = [ ./modules/configuration.nix ];
        };

        work = nix-darwin.lib.darwinSystem {
          specialArgs = {
            inherit self;
            hostConfig = import ./modules/hosts/work.nix;
          };
          modules = [ ./modules/configuration.nix ];
        };
      };
    };
}
