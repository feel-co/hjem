# take `pkgs` as arg to allow injection of other nixpkgs instances, without flakes
{
  pkgs ? import ./internal/pkgs.nix,
  ndg ? import (import ./internal/flake-parse.nix "ndg" + "/nix").packages.default,
  smfh ? pkgs.callPackage (import ./internal/flake-parse.nix "smfh" + "/package.nix") {},
}: rec {
  checks = import ./internal/checks.nix {inherit smfh pkgs;};
  packages = import ./internal/packages.nix {
    inherit ndg pkgs smfh;
    hjemModule = nixosModules.default;
    nixpkgs = pkgs.path;
  };
  formatter = import ./internal/formatter.nix pkgs;
  nixosModules = import ./modules/nixos;
  shell = import ./internal/shell.nix pkgs;
}
