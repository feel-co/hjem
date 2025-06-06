# The first argument to this function is the test module itself
test: {
  pkgs,
  self,
  inputs,
}: let
  inherit (pkgs) lib;
  nixos-lib = import (pkgs.path + "/nixos/lib") {};
in
  (nixos-lib.runTest {
    hostPkgs = pkgs;
    defaults.documentation.enable = lib.mkDefault false;

    node.specialArgs = {inherit self inputs;};
    imports = [test];
  })
  .config
  .result
