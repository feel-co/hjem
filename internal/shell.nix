pkgs:
pkgs.mkShell {
  name = "hjem-dev";
  packages = builtins.attrValues {
    inherit
      (pkgs)
      # formatter
      alejandra
      # cue validator
      cue
      go
      # source management
      npins
      ;
  };
}
