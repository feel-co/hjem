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

  # Scan one unit directory from a package, returning a flat attrset of
  # relative path -> absolute store path for every regular file and symlink.
  # Subdirectories (e.g., drop-in *.d/, *.requires/, *.upholds/) are recursed one
  # level deep. .wants/ directories are intentionally skipped.
  # NixOS does the same, and handles them via a separate upstreamWants mechanism.
  scanUnitDir = dir:
    lib.optionalAttrs (pathExists dir) (
      let
        entries = filterAttrs (_: t: t != "unknown") (readDir dir);
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
        ) {} (lib.attrNames entries)
    );

  # Collect all unit files exposed by a package, preferring lib/ over etc/
  # (same precedence as NixOS: etc/ is scanned first, then lib/ may overwrite).
  packageUnitFiles = pkg:
    scanUnitDir "${pkg}/etc/systemd/user"
    // scanUnitDir "${pkg}/lib/systemd/user";
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

          Units declared in {option}`systemd.services` and friends take
          precedence over package-provided units with the same name.
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
    xdg.config.files =
      # Package-provided units come first so that user-declared units
      # (merged in with //) can override them.
      lib.foldl' (
        acc: pkg:
          acc
          // mapAttrs'
          (name: path: nameValuePair "systemd/user/${name}" {source = path;})
          (packageUnitFiles pkg)
      ) {}
      cfg.packages
      // listToAttrs (
        flatten (
          mapAttrsToList (name: unit: let
            src = "${utils.systemdUtils.lib.makeUnit name unit}/${name}";
            mkEntry = path: nameValuePair path {source = src;};
          in
            [(mkEntry "systemd/user/${name}")]
            ++ map (w: mkEntry "systemd/user/${w}.wants/${name}") (unit.wantedBy or [])
            ++ map (r: mkEntry "systemd/user/${r}.requires/${name}") (unit.requiredBy or [])
            ++ map (u: mkEntry "systemd/user/${u}.upholds/${name}") (unit.upheldBy or [])
            ++ map (a: nameValuePair "systemd/user/${a}" {source = src;}) (unit.aliases or []))
          cfg.units
        )
      );

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
