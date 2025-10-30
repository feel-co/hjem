pkgs:
pkgs.mkShell {
  name = "hjem-devshell";
  packages = builtins.attrValues {
    inherit
      (pkgs)
      # formatter
      alejandra
      # cue validator
      cue
      go
      ;
  };
}
