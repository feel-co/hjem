# take `pkgs` as arg to allow injection of other nixpkgs instances, without flakes
{pkgs ? import ./internal/pkgs.nix}: {
  # checks =
  # packages =
  formatter = import ./internal/formatter.nix pkgs;
  nixosModules = import ./modules/nixos;
  shell = import ./internal/shell.nix pkgs;
}
