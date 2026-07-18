rec {
  hjem = {
    imports = [
      hjem-lib
      ./base.nix
    ];
  };
  hjem-lib = {
    lib,
    pkgs,
    ...
  }: {
    _module.args.hjem-lib = import ../../lib.nix {inherit lib pkgs;};
    _module.args.hjem-package =
      if pkgs ? hjem
      then pkgs.hjem
      else pkgs.callPackage ../../cli/package.nix {};
  };
  default = hjem;
}
