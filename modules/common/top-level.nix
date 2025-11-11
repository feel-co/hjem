{hjemModule}: {
  lib,
  config,
  ...
}: let
  inherit (builtins) concatLists mapAttrs;
  inherit (lib.attrsets) filterAttrs mapAttrsToList;
  inherit (lib.lists) optional;
  inherit (lib.options) literalExpression mkOption;
  inherit (lib.types) attrs attrsOf bool either listOf nullOr package raw singleLineStr;

  cfg = config.hjem;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;
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
      description = "Hjem-managed user configurations.";
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

        This is the default file linker on Linux, as it is the more mature
        linker, but it has the downside of leaving behind symlinks that may
        not get invalidated until the next GC, if an entry is removed from
        {option}`hjem.<user>.files`.

        Specifying a package will use a custom file linker that uses an
        internally-generated manifest. The custom file linker must use this
        manifest to create or remove links as needed, by comparing the manifest
        of the currently activated system with that of the new system.
        This prevents dangling symlinks when an entry is removed from
        {option}`hjem.<user>.files`.

        :::{.note}
        This linker is currently experimental; once it matures, it may become
        the default in the future.
        :::
      '';
      type = nullOr package;
    };

    linkerOptions = mkOption {
      default = [];
      description = ''
        Additional arguments to pass to the linker.

        This is for external linker modules to set, to allow extending the default set of hjem behaviours.
        It accepts either a list of strings, which will be passed directly as arguments, or an attribute set, which will be
        serialized to JSON and passed as `--linker-opts options.json`.
      '';
      type = either (listOf singleLineStr) attrs;
    };
  };

  config = {
    users.users = (mapAttrs (_: v: {inherit (v) packages;})) enabledUsers;
    assertions =
      concatLists
      (mapAttrsToList (user: config:
        map ({
          assertion,
          message,
          ...
        }: {
          inherit assertion;
          message = "${user} profile: ${message}";
        })
        config.assertions)
      enabledUsers);

    warnings =
      concatLists
      (mapAttrsToList (
          user: v:
            map (
              warning: "${user} profile: ${warning}"
            )
            v.warnings
        )
        enabledUsers)
      ++ optional
      (enabledUsers == {}) ''
        You have imported hjem, but you have not enabled hjem for any users.
      '';
  };
}
