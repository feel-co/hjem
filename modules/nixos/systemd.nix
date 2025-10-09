{
  config,
  lib,
  osConfig,
  utils,
  ...
}: let
  inherit (builtins) listToAttrs;
  inherit (lib) mkIf;
  inherit (lib.attrsets) mapAttrsToList nameValuePair;
  inherit (lib.lists) flatten;
  inherit (lib.options) mkOption;
  inherit (lib.trivial) pipe;
  inherit (lib.types) bool;

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
      units = mkOption {
        default = {};
        type = utils.systemdUtils.types.units;
        description = "Internal systemd user unit option to handle transformations.";
        internal = true;
      };
    }
    // {
      enable = mkOption {
        default = true;
        type = bool;
        description = "Opt out of Hjem user service management";
      };
    };

  config = {
    xdg.config.files."systemd/user".source = utils.systemdUtils.lib.generateUnits mkIf config.systemd.enable {
      type = "user";
      inherit (cfg) units;
      inherit (osConfig.systemd) package;
      packages = [];
      upstreamUnits = [];
      upstreamWants = [];
    };

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
