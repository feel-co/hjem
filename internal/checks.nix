{
  pkgs,
  self ? ../.,
}: let
  hjemTest =
    # The first argument to this function is the test module itself
    test:
      (pkgs.testers.runNixOSTest {
        defaults.documentation.enable = pkgs.lib.mkDefault false;
        imports = [test];
      }).config.result;

  inherit (pkgs.lib.filesystem) packagesFromDirectoryRecursive;

  prefixAttrs = prefix: pkgs.lib.mapAttrs' (name: pkgs.lib.nameValuePair "${prefix}-${name}");

  checks =
    prefixAttrs "nixos" (packagesFromDirectoryRecursive {
      callPackage = pkgs.newScope (checks
        // {
          inherit hjemTest;
          hjemModule = (import (self + "/modules/nixos")).default;
        });
      directory = ../tests/nixos;
    })
    // {
      # Formatting checks to run as a part of 'nix flake check' or manually
      # via 'nix build .#checks.<system>.formatting'.
      formatting =
        pkgs.runCommandLocal "hjem-formatting-check" {
          nativeBuildInputs = [pkgs.alejandra];
        } ''
          alejandra --check ${self}
          touch $out;
        '';
    };
in
  checks
