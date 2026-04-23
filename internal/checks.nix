{
  pkgs,
  self ? ../.,
  smfh,
}: let
  hjemTest =
    # The first argument to this function is the test module itself
    test:
      (pkgs.testers.runNixOSTest {
        defaults.documentation.enable = pkgs.lib.mkDefault false;
        imports = [test];
      }).config.result;

  inherit (pkgs.lib.filesystem) packagesFromDirectoryRecursive;

  checks =
    packagesFromDirectoryRecursive {
      callPackage = pkgs.newScope (checks
        // {
          inherit hjemTest;
          hjemModule = (import (self + "/modules/nixos")).default;
        });
      directory = ../tests;
    }
    // {
      # Build the 'smfh' package as a part of Hjem's test suite.
      # If 'nix flake check' is ran in the CI, this might inflate build times
      # *a lot*.
      inherit smfh;

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
