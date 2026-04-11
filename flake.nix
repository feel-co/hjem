{
  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    # We should only specify the modules Hjem explicitly supports, or we risk
    # allowing not-so-defined behaviour. For example, adding nix-systems should
    # be avoided, because it allows specifying systems Hjem is not tested on.
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    pkgsFor = system: nixpkgs.legacyPackages.${system};
    smfhPin = (import ./npins).smfh;
    smfhFor = pkgs: pkgs.callPackage (smfhPin + "/package.nix") {};
  in {
    nixosModules = import ./modules/nixos;
    darwinModules = import ./modules/nix-darwin;

    overlays = [
      (import smfhPin).overlays.default
    ];

    packages = forAllSystems (system:
      import ./internal/packages.nix rec {
        inherit nixpkgs;
        hjemModule = self.nixosModules.default;
        pkgs = pkgsFor system;
        smfh = smfhFor pkgs;
      });

    checks = forAllSystems (system:
      import ./internal/checks.nix rec {
        inherit self;
        pkgs = pkgsFor system;
        smfh = smfhFor pkgs;
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
