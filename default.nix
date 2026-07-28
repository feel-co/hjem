# take `pkgs` as arg to allow injection of other nixpkgs instances, without flakes
{
  pkgs ? import (import ./internal/flake-parse.nix "nixpkgs") {},
  finix ? (import ./npins).finix,
}: rec {
  checks =
    import ./internal/checks.nix {inherit pkgs;}
    // import ./internal/finix-checks.nix {inherit finix pkgs;};
  packages = import ./internal/packages.nix {
    inherit pkgs;
    hjemModule = nixosModules.default;
    nixpkgs = pkgs.path;
  };
  formatter = import ./internal/formatter.nix pkgs;
  nixosModules = import ./modules/nixos;
  darwinModules = import ./modules/nix-darwin;
  finixModules = import ./modules/finix;
  shell = import ./internal/shell.nix pkgs;
}
