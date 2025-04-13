{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs = {
    self,
    nixpkgs,
    systems,
    ...
  }: let
    forAllSystems = nixpkgs.lib.genAttrs (import systems);
  in {
    nixosModules = {
      hjem = ./modules/nixos;
      default = self.nixosModules.hjem;
    };

    checks = forAllSystems (system: let
      checkArgs = {
        inherit self;
        pkgs = nixpkgs.legacyPackages.${system};
      };
    in {
      hjem-basic = import ./tests/basic.nix checkArgs;
      hjem-special-args = import ./tests/special-args.nix checkArgs;
    });

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
