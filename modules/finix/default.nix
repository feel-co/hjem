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
  };
  default = hjem;
}
