{
  config,
  lib,
  utils,
  ...
}: let
  inherit (builtins) listToAttrs pathExists readDir;
  inherit (lib.attrsets) filterAttrs mapAttrs' mapAttrsToList nameValuePair;
  inherit (lib.lists) flatten;
  inherit (lib.modules) mkIf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.strings) hasSuffix;
  inherit (lib.trivial) pipe;
  inherit (lib.types) listOf package;

  cfg = config.systemd;
  unitTypes = [
    "path"
    "service"
    "slice"
    "socket"
    "target"
    "timer"
  ];

  # Preserve NixOS package overrides, masks, aliases and dependency links in one
  # generated tree, then expose each entry through Hjem's file management.
  unitTree = utils.systemdUtils.lib.generateUnits {
    type = "user";
    inherit (cfg) units packages;
    upstreamUnits = [];
    upstreamWants = [];
  };

  scanUnitDir = dir: let
    entries = lib.optionalAttrs (pathExists dir) (readDir dir);
  in
    lib.foldl' (
      acc: name: let
        type = entries.${name};
        path = "${dir}/${name}";
      in
        if hasSuffix ".wants" name
        then acc
        else if type == "regular" || type == "symlink"
        then acc // {${name} = path;}
        else if type == "directory"
        then
          acc
          // mapAttrs'
          (sub: _: nameValuePair "${name}/${sub}" "${path}/${sub}")
          (filterAttrs (_: t: t == "regular" || t == "symlink") (readDir path))
        else acc
    ) {} (lib.attrNames entries);

  packageFiles = lib.foldl' (acc: pkg:
    acc
    // scanUnitDir "${pkg}/etc/systemd/user"
    // scanUnitDir "${pkg}/lib/systemd/user") {}
  cfg.packages;

  # Enumerate managed paths without building unitTree during evaluation.
  declaredFiles = flatten (mapAttrsToList (name: unit:
    [
      (
        if
          unit.overrideStrategy
          == "asDropin"
          || (unit.enable && packageFiles ? ${name} && pathExists packageFiles.${name})
        then "${name}.d/overrides.conf"
        else name
      )
    ]
    ++ map (w: "${w}.wants/${name}") unit.wantedBy
    ++ map (r: "${r}.requires/${name}") unit.requiredBy
    ++ map (u: "${u}.upholds/${name}") unit.upheldBy
    ++ unit.aliases)
  cfg.units);
in {
  options.systemd =
    pipe unitTypes [
      (map (t:
        nameValuePair "${t}s" (mkOption {
          default = {};
          type = utils.systemdUtils.types."${t}s";
          description = "Definition of systemd per-user ${t} units.";
        })))
      listToAttrs
    ]
    // {
      enable =
        mkEnableOption "Hjem management of systemd units"
        // {
          default = true;
          example = false;
        };

      packages = mkOption {
        type = listOf package;
        default = [];
        description = ''
          Packages containing systemd user unit files to be linked into
          {file}`~/.config/systemd/user/`. Unit files are taken from
          `$pkg/etc/systemd/user/` and `$pkg/lib/systemd/user/`.

          Units declared in {option}`systemd.services` and friends extend
          package-provided units with the same name using drop-ins.
        '';
      };

      units = mkOption {
        type = utils.systemdUtils.types.units;
        default = {};
        description = "Internal systemd user unit option to handle transformations.";
        internal = true;
      };
    };

  config = mkIf cfg.enable {
    xdg.config.files = listToAttrs (map (name:
      nameValuePair "systemd/user/${name}" {source = "${unitTree}/${name}";})
    (lib.unique (lib.attrNames packageFiles ++ declaredFiles)));

    systemd.units = pipe unitTypes [
      (map
        (t:
          mapAttrsToList
          (n: v: nameValuePair "${n}.${t}" (utils.systemdUtils.lib."${t}ToUnit" v))
          cfg."${t}s"))
      flatten
      listToAttrs
    ];
  };
}
