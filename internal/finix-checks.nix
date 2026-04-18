{
  pkgs,
  self ? ../.,
  finix,
}: let
  testLib = import (finix + "/tests/lib") {
    inherit pkgs;
    lib = pkgs.lib;
  };
  hjemTest = test: testLib.mkTest test;

  inherit (pkgs.lib.filesystem) packagesFromDirectoryRecursive;

  checks = packagesFromDirectoryRecursive {
    callPackage = pkgs.newScope (
      checks
      // {
        inherit hjemTest;
        hjemModule = (import (self + "/modules/finix")).default;
      }
    );
    directory = ../finix-tests;
  };
in
  checks
