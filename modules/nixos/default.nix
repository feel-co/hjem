{
  config,
  hjem-lib,
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (lib.attrsets) filterAttrs mapAttrsToList;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) literalExpression mkOption;
  inherit (lib.strings) optionalString;
  inherit (lib.trivial) pipe;
  inherit (lib.types) attrs attrsOf bool either listOf nullOr package raw singleLineStr submoduleWith;
  inherit (lib.meta) getExe;
  inherit (builtins) filter attrNames attrValues mapAttrs getAttr concatLists concatStringsSep typeOf toJSON concatMap;

  cfg = config.hjem;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;
  disabledUsers = filterAttrs (_: u: !u.enable) cfg.users;

  userFiles = user: [
    user.files
    user.xdg.cache.files
    user.xdg.config.files
    user.xdg.data.files
    user.xdg.state.files
  ];

  linker = getExe cfg.linker;

  manifests = let
    mapFiles = files:
      lib.attrsets.foldlAttrs (
        accum: _: value:
          if value.enable -> value.source == null
          then accum
          else
            accum
            ++ lib.singleton {
              type = "symlink";
              inherit (value) source target;
            }
      ) []
      files;

    writeManifest = username: let
      name = "manifest-${username}.json";
    in
      pkgs.writeTextFile {
        inherit name;
        destination = "/${name}";
        text = builtins.toJSON {
          clobber_by_default = cfg.users."${username}".clobberFiles;
          version = 1;
          files = concatMap mapFiles (
            userFiles cfg.users."${username}"
          );
        };
        checkPhase = ''
          set -e
          CUE_CACHE_DIR=$(pwd)/.cache
          CUE_CONFIG_DIR=$(pwd)/.config

          ${lib.getExe pkgs.cue} vet -c ${../../manifest/v1.cue} $target
        '';
      };
  in
    pkgs.symlinkJoin
    {
      name = "hjem-manifests";
      paths = map writeManifest (builtins.attrNames enabledUsers);
    };

  hjemModule = submoduleWith {
    description = "Hjem NixOS module";
    class = "hjem";
    specialArgs =
      cfg.specialArgs
      // {
        inherit hjem-lib pkgs;
        osConfig = config;
        osOptions = options;
      };
    modules =
      concatLists
      [
        [
          ../common/user.nix
          ({name, ...}: let
            inherit (lib.modules) mkDefault;
            user = getAttr name config.users.users;
          in {
            user = mkDefault user.name;
            directory = mkDefault user.home;
            clobberFiles = mkDefault cfg.clobberByDefault;
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

  config = mkMerge [
    {
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
          enabledUsers);
    }

    # Constructed rule string that consists of the type, target, and source
    # of a tmpfile. Files with 'null' sources are filtered before the rule
    # is constructed.
    (mkIf (cfg.linker == null) {
      assertions = [
        {
          assertion = pkgs.stdenv.hostPlatform.isLinux;
          message = "The systemd-tmpfiles linker is only supported on Linux; on other platforms, use the manifest linker.";
        }
      ];

      systemd.user.tmpfiles.users =
        mapAttrs (_: u: {
          rules = pipe (userFiles u) [
            (concatMap attrValues)
            (filter (f: f.enable && f.source != null))
            (map (
              file:
              # L+ will recreate, i.e., clobber existing files.
              "L${optionalString file.clobber "+"} '${file.target}' - - - - ${file.source}"
            ))
          ];
        })
        enabledUsers;
    })

    (mkIf (cfg.linker != null) {
      /*
      The different Hjem services expect the manifest to be generated under `/var/lib/hjem/manifest-{user}.json`.
      */
      systemd.targets.hjem = {
        description = "Hjem File Management";
        after = ["local-fs.target"];
        wantedBy = ["sysinit-reactivation.target" "multi-user.target"];
        before = ["sysinit-reactivation.target"];
        requires = let
          requiredUserServices = name: [
            "hjem-activate@${name}.service"
            "hjem-copy@${name}.service"
          ];
        in
          concatMap requiredUserServices (attrNames enabledUsers)
          ++ ["hjem-cleanup.service"];
      };

      systemd.services = let
        manifestsDir = "/var/lib/hjem";
        checkEnabledUsers = ''
          case "$1" in
            ${concatStringsSep "|" (attrNames enabledUsers)}) ;;
            *) echo "User '%i' is not configured for Hjem" >&2; exit 1 ;;
          esac
        '';
      in {
        hjem-prepare = {
          description = "Prepare Hjem manifests directory";
          script = "mkdir -p ${manifestsDir}";
          serviceConfig.Type = "oneshot";
          unitConfig.RefuseManualStart = true;
        };

        "hjem-activate@" = {
          description = "Link files for %i from their manifest";
          serviceConfig = {
            User = "%i";
            Type = "oneshot";
          };
          requires = [
            "hjem-prepare.service"
            "hjem-copy@%i.service"
          ];
          after = ["hjem-prepare.service"];
          scriptArgs = "%i";
          script = let
            linkerOpts =
              if (typeOf cfg.linkerOptions == "set")
              then ''--linker-opts "${toJSON cfg.linkerOptions}"''
              else concatStringsSep " " cfg.linkerOptions;
          in ''
            ${checkEnabledUsers}
            new_manifest=${manifests}/manifest-$1.json

            if [ ! -f ${manifestsDir}/manifest-$1.json ]; then
              ${linker} ${linkerOpts} activate $new_manifest
              exit 0
            fi

            ${linker} ${linkerOpts} diff $new_manifest ${manifestsDir}/manifest-$1.json
          '';
        };

        "hjem-copy@" = {
          description = "Copy the manifest into Hjem's state directory for %i";
          serviceConfig.Type = "oneshot";
          after = ["hjem-activate@%i.service"];
          scriptArgs = "%i";
          /*
          TODO: remove the if condition in a while, this is in place because the first iteration of the
          manifest used to simply point /var/lib/hjem to the aggregate symlinkJoin directory. Since
          per-user manifest services have now been implemented, trying to copy singular files into
          /var/lib/hjem will fail if the user was using the previous manifest handling.
          */
          script = ''
            ${checkEnabledUsers}
            new_manifest=${manifests}/manifest-$1.json

            if ! cp $new_manifest ${manifestsDir}; then
              echo "Copying the manifest for $1 failed. This is likely due to using the previous\
              version of the manifest handling. The manifest directory has been recreated and repopulated with\
              %i's manifest. Please re-run the activation services for your other users, if you have ran this one manually."

              rm -rf ${manifestsDir}
              mkdir -p ${manifestsDir}

              cp $new_manifest ${manifestsDir}
            fi
          '';
        };

        hjem-cleanup = {
          description = "Cleanup disabled users' manifests";
          serviceConfig.Type = "oneshot";
          after = ["hjem.target"];
          unitConfig.RefuseManualStart = false;
          script = let
            manifestsToDelete =
              map
              (user: "${manifestsDir}/manifest-${user}.json")
              (attrNames disabledUsers);
          in
            if disabledUsers != {}
            then "rm ${concatStringsSep " " manifestsToDelete}"
            else "true";
        };
      };
    })
  ];
}
