{
  config,
  lib,
  utils,
  ...
}: let
  inherit (builtins) listToAttrs match pathExists readDir;
  inherit (lib.attrsets) filterAttrs mapAttrs' mapAttrsToList nameValuePair;
  inherit (lib.lists) flatten;
  inherit (lib.modules) mkIf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.strings) hasSuffix;
  inherit (lib.trivial) pipe;
  inherit (lib.types) enum listOf package;

  cfg = config.systemd;
  unitTypes = [
    "path"
    "service"
    "slice"
    "socket"
    "target"
    "timer"
  ];

  withReplacement = type:
    type.substSubModules (type.getSubModules
      ++ [
        {
          options.overrideStrategy = mkOption {
            type = enum ["asReplacement"];
          };
        }
      ]);

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

  unitDir = "systemd/user";

  # An alias must point within systemd's unit search path, not at the
  # canonical store path where the unit contents live.
  linkToUnit = name: {
    source = "${config.xdg.config.directory}/${unitDir}/${name}";
    followSymlinks = false;
  };

  dropinPath = path:
    if packageFiles ? ${path}
    then dropinPath "${path}.hjem.conf"
    else path;

  templateSource = name: let
    instance = match "([^@]+)@[^@]+(\\.[^.]+)" name;
  in
    if instance == null
    then null
    else packageFiles."${builtins.elemAt instance 0}@${builtins.elemAt instance 1}" or null;

  usesDropin = name: unit:
    unit.enable
    && (
      if unit.overrideStrategy == "asDropinIfExists"
      then packageFiles ? ${name} && pathExists packageFiles.${name}
      else unit.overrideStrategy == "asDropin"
    );

  declaredFiles = listToAttrs (flatten (mapAttrsToList (name: unit: let
    asDropin = usesDropin name unit;
    unitFile = {source = "${unit.unit}/${name}";};
    packagedSource = packageFiles.${name} or (templateSource name);
    dependencyFile =
      if !asDropin
      then unitFile
      else if packagedSource != null && pathExists packagedSource
      then {source = packagedSource;}
      else linkToUnit name;
    dependencyLinks = suffix: targets:
      map (target: nameValuePair "${target}.${suffix}/${name}" dependencyFile) targets;
    unitPath =
      if asDropin
      then dropinPath "${name}.d/overrides.conf"
      else name;
  in
    [(nameValuePair unitPath unitFile)]
    ++ dependencyLinks "wants" unit.wantedBy
    ++ dependencyLinks "requires" unit.requiredBy
    ++ dependencyLinks "upholds" unit.upheldBy
    ++ map (alias: nameValuePair alias (linkToUnit name)) unit.aliases)
  cfg.units));

  vendorFiles = lib.mapAttrs (_: source: {inherit source;}) (filterAttrs (path: _: let
    dropin = match "(.+)\\.d/[^/]+" path;
  in
    dropin == null || (cfg.units.${builtins.head dropin}.overrideStrategy or null) != "asReplacement")
  packageFiles);
in {
  options.systemd =
    pipe unitTypes [
      (map (t:
        nameValuePair "${t}s" (mkOption {
          default = {};
          type = withReplacement utils.systemdUtils.types."${t}s";
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
          package-provided units with the same name using drop-ins by default.
          Set a unit's `overrideStrategy` to `"asReplacement"` to replace its
          package-provided unit file and omit its package-provided drop-ins.
        '';
      };

      units = mkOption {
        type = withReplacement utils.systemdUtils.types.units;
        default = {};
        description = "Internal systemd user unit option to handle transformations.";
        internal = true;
      };
    };

  config = mkIf cfg.enable {
    xdg.config.files = mapAttrs' (name: nameValuePair "${unitDir}/${name}") (vendorFiles // declaredFiles);

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
