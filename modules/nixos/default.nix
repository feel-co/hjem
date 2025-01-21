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
  inherit (lib.types) attrs attrsOf bool listOf nullOr package raw submoduleWith;

  cfg = config.hjem;
  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  hjemModule = submoduleWith {
    description = "Hjem NixOS module";
    class = "hjem";
    specialArgs = {inherit pkgs lib;} // cfg.specialArgs;
    modules = concatLists [
      [
        ({name, ...}: {
          imports = [../common.nix];

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
  imports = [
    # This should be removed in the future, since 'homes' is a very vague
    # namespace to occupy. Added 2024-12-27, remove 2025-01-27 to allow
    # sufficient time to migrate.
    (lib.mkRenamedOptionModule ["homes"] ["hjem" "users"])

    # 'extraSpecialArgs' is confusing and obscure. 'hjem.specialArgs' better
    # describes what the option is really for.
    (lib.mkRenamedOptionModule ["hjem" "extraSpecialArgs"] ["hjem" "specialArgs"])
  ];

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

    linker = mkOption {
      default = null;
      description = ''
        Method to use to link files.

        `null` will use `systemd-tmpfiles`, which is only supported on Linux.
        This is the default file linker on Linux, as it is the more mature linker, but it has the downside of leaving
        behind symlinks that may not get invalidated until the next GC, if an entry is removed from {option}`hjem.<user>.files`.

        Specifying a package will use a custom file linker that uses an internally-generated manifest.
        The custom file linker must use this manifest to create or remove links as needed, by comparing the
        manifest of the currently activated system with that of the new system.
        This prevents dangling symlinks when an entry is removed from {option}`hjem.<user>.files`.
        This linker is currently experimental; once it matures, it may become the default in the future.
      '';
      type = nullOr package;
    };
  };

  config = mkMerge [
    {
      users.users = mapAttrs' (name: {packages, ...}: {
        inherit name;
        value.packages = packages;
      }) (filterAttrs (_: u: u.packages != []) enabledUsers);
    }

    (mkIf (cfg.linker == null) {
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
      }) (filterAttrs (_: u: u.files != {}) enabledUsers);
    })

    (mkIf (cfg.linker != null) {
      })

    (mkIf (enabledUsers != {}) {
      warnings = flatten (flip mapAttrsToList enabledUsers (user: config:
        flip map config.warnings (
          warning: "${user} profile: ${warning}"
        )));

      assertions = flatten (flip mapAttrsToList enabledUsers (user: config:
        flip map config.assertions (assertion: {
          inherit (assertion) assertion;
          message = "${user} profile: ${assertion.message}";
        })));
    })
  ];
}
