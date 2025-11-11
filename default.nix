# take `pkgs` as arg to allow injection of other nixpkgs instances, without flakes
{
  pkgs ? import (import ./internal/flake-parse.nix "nixpkgs") {},
  smfh ? pkgs.callPackage (import ./internal/flake-parse.nix "smfh" + "/package.nix") {},
}: rec {
  checks = import ./internal/checks.nix {inherit smfh pkgs;};
  packages = import ./internal/packages.nix {
    inherit pkgs smfh;
    hjemModule = nixosModules.default;
    nixpkgs = pkgs.path;
  };
  formatter = import ./internal/formatter.nix pkgs;
  nixosModules = import ./modules/nixos;
  darwinModules = import ./modules/nix-darwin;
  shell = import ./internal/shell.nix pkgs;
}
