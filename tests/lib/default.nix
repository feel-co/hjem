# The first argument to this function is the test module itself
test: {
  pkgs,
  self,
  inputs,
}:
(pkgs.testers.runNixOSTest {
  node.specialArgs = {inherit self inputs;};
  defaults.documentation.enable = pkgs.lib.mkDefault false;

  imports = [test];
}).config.result
