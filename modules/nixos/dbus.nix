{
  config,
  lib,
  ...
}: let
  inherit (builtins) pathExists readDir;
  inherit (lib.attrsets) filterAttrs mapAttrs' nameValuePair;
  inherit (lib.lists) foldl';
  inherit (lib.modules) mkIf;
  inherit (lib.options) mkOption;
  inherit (lib.types) listOf package;

  cfg = config.dbus;

  packageServiceFiles = pkg: let
    dir = "${pkg}/share/dbus-1/services";
  in
    if pathExists dir
    then
      mapAttrs'
      (name: _: nameValuePair "dbus-1/services/${name}" {source = "${dir}/${name}";})
      (filterAttrs (_: type: type == "regular" || type == "symlink") (readDir dir))
    else {};
in {
  options.dbus.packages = mkOption {
    type = listOf package;
    default = [];
    example = lib.literalExpression "[pkgs.dbus]";
    description = ''
      Packages containing D-Bus service files to be linked into
      {file}`~/.local/share/dbus-1/services/`. Service files are taken from
      `$pkg/share/dbus-1/services/`.
    '';
  };

  config.xdg.data.files = mkIf (cfg.packages != []) (
    foldl' (acc: pkg: acc // packageServiceFiles pkg) {} cfg.packages
  );
}
