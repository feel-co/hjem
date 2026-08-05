{
  inputs.nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";

  outputs = {
    self,
    nixpkgs,
    ...
  }: let
    # We should only specify the modules Hjem explicitly supports, or we risk
    # allowing not-so-defined behaviour. For example, adding nix-systems should
    # be avoided, because it allows specifying systems Hjem is not tested on.
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    finix = (import ./npins).finix;
    pkgsFor = system: nixpkgs.legacyPackages.${system};
  in {
    nixosModules = import ./modules/nixos;
    darwinModules = import ./modules/nix-darwin;
    finixModules = import ./modules/finix;

    packages = forAllSystems (system:
      import ./internal/packages.nix {
        inherit nixpkgs;
        hjemModule = self.nixosModules.default;
        pkgs = pkgsFor system;
      });

    checks = forAllSystems (system:
      import ./internal/checks.nix {
        inherit self;
        pkgs = pkgsFor system;
      }
      // import ./internal/finix-checks.nix {
        inherit self finix;
        pkgs = pkgsFor system;
      });

    devShells = forAllSystems (system: {
      default = import ./internal/shell.nix (pkgsFor system);
      rust = import ./internal/rust-shell.nix (pkgsFor system);
    });

    formatter =
      forAllSystems (system:
        import ./internal/formatter.nix (pkgsFor system));

    hjem-lib = forAllSystems (system:
      import ./lib.nix {
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
      });
    lib.
      hjemConfig = {
      specialArgs ? {},
      modules,
      pkgs,
    }: let
      inherit (pkgs) lib;
      evaled = lib.evalModules {
        class = "hjem";
        specialArgs =
          specialArgs
          // {
            modulesPath = toString ./modules;
            hjem-lib = import ./lib.nix {inherit lib pkgs;};
            inherit pkgs;
            # TODO, make these error on read
            #osOptions
            #osConfig
            #utils
          };
        modules =
          [
            ./modules/common/user.nix
            ./modules/standalone/default.nix
          ]
          ++ modules;
      };

      failedAssertions = map (x: x.message) (builtins.filter (x: !x.assertion) evaled.config.assertions);
      baseSystemAssertWarn =
        if failedAssertions != []
        then throw "\nFailed assertions:\n${lib.concatMapStrings (x: "- ${x}") failedAssertions}"
        else lib.showWarnings evaled.config.warnings;
    in
      baseSystemAssertWarn evaled.config;
  };
}
