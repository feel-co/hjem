{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) mkOption literalExpression;
  inherit (lib.lists) filter map flatten concatLists;
  inherit (lib.attrsets) filterAttrs mapAttrs' attrValues mapAttrsToList;
  inherit (lib.trivial) flip;
  inherit (lib.types) bool attrsOf submoduleWith listOf raw attrs;

  cfg = config.hjem;

  hjemModule = submoduleWith {
    description = "Hjem NixOS module";
    class = "hjem";
    specialArgs =
      {
        inherit pkgs lib;
        osConfig = config;
      }
      // cfg.specialArgs;
    modules = concatLists [
      [
        ({name, ...}: {
          imports = [../common.nix ./systemd.nix];

          config = {
            user = config.users.users.${name}.name;
            directory = config.users.users.${name}.home;
            clobberFiles = cfg.clobberByDefault;
          };
        })
      ]

      # Evaluate additional modules under 'hjem.users.<name>' so that
      # module systems built on Hjem are more ergonomic.
      cfg.extraModules
    ];
  };
in {
  options.hjem = {
    clobberByDefault = mkOption {
      type = bool;
      default = false;
      description = ''
        The default override behaviour for files managed by Hjem.

        While `true`, existing files will be overriden with new files on rebuild.
        The behaviour may be modified per-user by setting {option}`hjem.users.<name>.clobberFiles`
        to the desired value.
      '';
    };

    users = mkOption {
      default = {};
      type = attrsOf hjemModule;
      description = "Home configurations to be managed";
    };

    extraModules = mkOption {
      type = listOf raw;
      default = [];
      description = ''
        Additional modules to be evaluated as a part of the users module
        inside {option}`config.hjem.users.<name>`. This can be used to
        extend each user configuration with additional options.
      '';
    };

    specialArgs = mkOption {
      type = attrs;
      default = {};
      example = literalExpression "{ inherit inputs; }";
      description = ''
        Additional `specialArgs` are passed to Hjem, allowing extra arguments
        to be passed down to to all imported modules.
      '';
    };
  };

  config = mkMerge [
    {
      users.users = mapAttrs' (name: {packages, ...}: {
        inherit name;
        value.packages = packages;
      }) (filterAttrs (_: u: (u.enable && u.packages != [])) cfg.users);

      systemd.user.tmpfiles.users = mapAttrs' (name: {files, ...}: {
        inherit name;
        value.rules = map (
          file: let
            # L+ will recreate, i.e., clobber existing files.
            mode =
              if file.clobber
              then "L+"
              else "L";
          in
            # Constructed rule string that consists of the type, target, and source
            # of a tmpfile. Files with 'null' sources are filtered before the rule
            # is constructed.
            "${mode} '${file.target}' - - - - ${file.source}"
        ) (filter (f: f.enable && f.source != null) (attrValues files));
      }) (filterAttrs (_: u: (u.enable && u.files != {})) cfg.users);
    }

    (mkIf (cfg.users != {}) {
      warnings = flatten (flip mapAttrsToList cfg.users (user: config:
        flip map config.warnings (
          warning: "${user} profile: ${warning}"
        )));

      assertions = flatten (flip mapAttrsToList cfg.users (user: config:
        flip map config.assertions (assertion: {
          inherit (assertion) assertion;
          message = "${user} profile: ${assertion.message}";
        })));
    })
  ];
}
