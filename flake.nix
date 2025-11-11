{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Sleek, manifest based file handler.
    # Our awesome atomic file linker.
    smfh = {
      url = "github:feel-co/smfh";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    darwin,
    ...
  } @ inputs: let
    # We should only specify the modules Hjem explicitly supports, or we risk
    # allowing not-so-defined behaviour. For example, adding nix-systems should
    # be avoided, because it allows specifying systems Hjem is not tested on.
    forAllLinux = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];
    forAllDarwin = nixpkgs.lib.genAttrs ["x86_64-darwin" "aarch64-darwin"];
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin"];
    pkgsFor = system: nixpkgs.legacyPackages.${system};
  in {
    nixosModules = import ./modules/nixos;
    darwinModules = {
      hjem = {
        imports = [
          self.darwinModules.hjem-lib
          ./modules/nix-darwin
        ];
      };
      hjem-lib = {
        lib,
        pkgs,
        ...
      }: {
        _module.args.hjem-lib = import ./lib.nix {inherit lib pkgs;};
      };
      default = self.darwinModules.hjem;
    };

    packages = forAllSystems (system:
      import ./internal/packages.nix {
        inherit nixpkgs;
        inherit (inputs.smfh.packages.${system}) smfh;
        hjemModule = self.nixosModules.default;
        pkgs = pkgsFor system;
      });

    checks = forAllSystems (system:
      import ./internal/checks.nix {
        inherit self;
        inherit (self.packages.${system}) smfh;
        pkgs = pkgsFor system;
      });

    devShells = forAllSystems (system: {
      default = import ./internal/shell.nix (pkgsFor system);
    });

    formatter =
      forAllSystems (system:
        import ./internal/formatter.nix (pkgsFor system));

    hjem-lib = forAllSystems (system:
      import ./lib.nix {
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
      });
  };
}
