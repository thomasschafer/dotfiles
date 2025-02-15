{
  description = "Example nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nix-darwin, nixpkgs }: {
    # Build flake using `darwin-rebuild build --flake .#simple`
    darwinConfigurations."simple" = nix-darwin.lib.darwinSystem {
      specialArgs = { inherit self; };
      modules = [ ./modules/configuration.nix ];
    };
  };
}
