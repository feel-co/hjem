{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    # Sleek, manifest based file handler.
    # Our awesome atomic file linker.
    smfh = {
      url = "github:feel-co/smfh";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Our in-house, super-fast documentation generator.
    ndg = {
      url = "github:feel-co/ndg";
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
    forAllSystems = nixpkgs.lib.genAttrs ["x86_64-linux" "aarch64-linux"];
  in {
    nixosModules = {
      hjem = {
        imports = [
          self.nixosModules.hjem-lib
          ./modules/nixos
        ];
      };
      hjem-lib = {
        lib,
        pkgs,
        ...
      }: {
        _module.args.hjem-lib = import ./lib.nix {inherit lib pkgs;};
      };
      default = self.nixosModules.hjem;
    };

    packages = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      docs = pkgs.callPackage ./docs/package.nix {inherit inputs;};
    in {
      # Expose the 'smfh' instance used by Hjem as a package in the Hjem flake
      # outputs. This allows consuming the exact copy of smfh used by Hjem.
      inherit (inputs.smfh.packages.${system}) smfh;

      # Hjem documentation. 'docs-html' contains the HTML document created by ndg
      # and docs-json contains a standalone 'options.json' that is also fed to ndg
      # for third party consumption.
      docs-html = docs.html;
      docs-json = docs.options.json;
    });

    checks = forAllSystems (system: let
      pkgs = nixpkgs.legacyPackages.${system};

      checkArgs = {
        inherit self inputs pkgs;
      };
    in {
      # Build the 'smfh' package as a part of Hjem's test suite.
      # If 'nix flake check' is ran in the CI, this might inflate build times
      # *a lot*.
      inherit (self.packages.${system}) smfh;

      # Formatting checks to run as a part of 'nix flake check' or manually
      # via 'nix build .#checks.<system>.formatting'.
      formatting =
        pkgs.runCommandLocal "hjem-formatting-check" {
          nativeBuildInputs = [pkgs.alejandra];
        } ''
          alejandra --check ${self}
          touch $out;
        '';

      # Hjem Integration Tests
      hjem-basic = import ./tests/basic.nix checkArgs;
      hjem-special-args = import ./tests/special-args.nix checkArgs;
      hjem-linker = import ./tests/linker.nix checkArgs;
      hjem-xdg = import ./tests/xdg.nix checkArgs;
      hjem-xdg-linker = import ./tests/xdg-linker.nix checkArgs;
    });

    devShells = forAllSystems (system: let
      inherit (builtins) attrValues;
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = attrValues {
          inherit
            (pkgs)
            # formatter
            alejandra
            # cue validator
            cue
            go
            ;
        };
      };
    });

    formatter = forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        pkgs.writeShellApplication {
          name = "nix3-fmt-wrapper";

          runtimeInputs = [
            pkgs.alejandra
            pkgs.fd
          ];

          text = ''
            fd "$@" -t f -e nix -x alejandra -q '{}'
          '';
        }
    );

    hjem-lib = forAllSystems (system:
      import ./lib.nix {
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
      });
  };
}
