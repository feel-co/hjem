{
  config,
  lib,
  utils,
  ...
}: let
  inherit (builtins) listToAttrs;
  inherit (lib.attrsets) mapAttrsToList nameValuePair;
  inherit (lib.lists) flatten;
  inherit (lib.modules) mkIf;
  inherit (lib.options) mkEnableOption mkOption;
  inherit (lib.trivial) pipe;

  cfg = config.systemd;
  unitTypes = [
    "path"
    "service"
    "slice"
    "socket"
    "target"
    "timer"
  ];
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

      units = mkOption {
        default = {};
        type = utils.systemdUtils.types.units;
        description = "Internal systemd user unit option to handle transformations.";
        internal = true;
      };
    };

  config = mkIf cfg.enable {
    xdg.config.files = listToAttrs (
      flatten (
        mapAttrsToList (name: unit: let
          src = "${utils.systemdUtils.lib.makeUnit name unit}/${name}";
          mkEntry = path: nameValuePair path {source = src;};
        in
          [mkEntry "systemd/user/${name}"]
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
