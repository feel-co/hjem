{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    smfh = {
      url = "github:Gerg-L/smfh";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];
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

      # Build smfh as a part of 'nix flake check'
      smfh = inputs.smfh.packages.${system}.smfh;
    });

    devShells = forAllSystems (system: let
      inherit (builtins) attrValues;
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = attrValues {
          inherit
            (pkgs)
            # cue validator
            cue
            go
            ;
        };
      };
    });

    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
