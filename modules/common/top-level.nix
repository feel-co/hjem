{
  hjemSubmodule,
  _class,
}: {
  lib,
  pkgs,
  hjem-package,
  config,
  ...
}: let
  inherit (builtins) concatLists mapAttrs;
  inherit (lib.attrsets) filterAttrs mapAttrsToList;
  inherit (lib.lists) optional;
  inherit (lib.options) literalExpression mkOption;
  inherit (lib.types) attrs attrsWith bool deferredModule either listOf nullOr package singleLineStr;

  cfg = config.hjem;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;
in {
  inherit _class;

  options.hjem = {
    clobberByDefault = mkOption {
      type = bool;
      default = false;
      description = ''
        The default override behaviour for files managed by Hjem.

        While `true`, existing files will be overriden with new files on rebuild.
        The behaviour may be modified per-user by setting {option}`hjem.users.<username>.clobberFiles`
        to the desired value.
      '';
    };

    users = mkOption {
      default = {};
      type = attrsWith {
        elemType = hjemSubmodule;
        placeholder = "username";
      };
      description = "Hjem-managed user configurations.";
    };

    extraModules = mkOption {
      type = listOf deferredModule;
      default = [];
      description = ''
        Additional modules to be evaluated as a part of the users module
        inside {option}`config.hjem.users.<username>`. This can be used to
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
      type = nullOr package;
      default = hjem-package;
      defaultText = literalExpression "hjem-package";
      description = ''
        Package to use to link files.

        By default, Hjem uses its own standalone CLI linker.

        Setting this to `null` will use `systemd-tmpfiles`,
        which is only supported on Linux.

        Specifying a non-null package uses an external linker that is invoked
        with Hjem-managed manifests.
      '';
    };

    linkerOptions = mkOption {
      type = either (listOf singleLineStr) attrs;
      default = [];
      description = ''
        Additional linker configuration.

        When using Hjem's built-in standalone linker, only `prefix` is consumed
        from an attribute set.

        ::: {.note}

        When using an external linker package, list values are forwarded as
        linker arguments and attribute-set values are forwarded as
        `--linker-opts <json-file>`.

        :::
      '';
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
          message = "${config.user} profile: ${message}";
        })
        config.assertions)
      enabledUsers)
      ++ [
        {
          assertion = cfg.linker == null -> pkgs.stdenv.hostPlatform.isLinux;
          message = "The systemd-tmpfiles linker is only supported on Linux; on other platforms, use the manifest linker.";
        }
      ];

    warnings =
      concatLists
      (mapAttrsToList (
          user: v:
            map (
              warning: "${v.user} profile: ${warning}"
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
