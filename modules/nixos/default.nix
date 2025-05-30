{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.attrsets) filterAttrs mapAttrsToList;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) literalExpression mkOption;
  inherit (lib.strings) optionalString;
  inherit (lib.trivial) pipe;
  inherit (lib.types) attrs attrsOf bool listOf nullOr package raw submoduleWith;
  inherit (lib.meta) getExe;
  inherit (builtins) filter attrValues mapAttrs getAttr concatLists;

  cfg = config.hjem;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  linker = getExe cfg.linker;

  manifests = let
    defaultFilePerms = "644";

    mapFiles = username: files:
      lib.attrsets.foldlAttrs (
        accum: _: value:
          if value.enable -> value.source == null
          then accum
          else
            accum
            ++ lib.singleton {
              type = "symlink";
              inherit (value) source target;
              inherit (config.users.users."${username}") uid;
              permissions = defaultFilePerms;
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
          files = mapFiles username cfg.users."${username}".files;
        };
        checkPhase = ''
          set -e
          # This is needed because cue expects HOME and XDG_CACHE_HOME to be set
          HOME="/home/${username}"
          XDG_CACHE_HOME="$HOME/.cache"

          env HOME=$HOME XDG_CACHE_HOME=$XDG_CACHE_HOME ${lib.getExe pkgs.cue} vet -c ${../../manifest/v1.cue} $target
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
        inherit pkgs;
        osConfig = config;
      };
    modules =
      concatLists
      [
        [
          ../common/user.nix
          ({name, ...}: let
            user = getAttr name config.users.users;
          in {
            user = user.name;
            directory = user.home;
            clobberFiles = cfg.clobberByDefault;
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
          rules = pipe u.files [
            attrValues
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

    (
      mkIf (cfg.linker != null)
      {
        systemd.services.hjem-activate = {
          requiredBy = ["sysinit-reactivation.target"];
          before = ["sysinit-reactivation.target"];
          script = ''
            mkdir -p /var/lib/hjem

            for manifest in ${manifests}/*; do
              # This is needed because cue expects HOME and XDG_CACHE_HOME to be set
              user="$(basename $manifest | cut -d'-' -f2 | cut -d'.' -f1)"
              HOME="/home/$user"
              XDG_CACHE_HOME="$HOME/.cache"

              env HOME=$HOME XDG_CACHE_HOME=$XDG_CACHE_HOME ${pkgs.cue}/bin/cue vet -c ${../../manifest/v1.cue} $manifest
            done

            for manifest in ${manifests}/*; do
              if [ ! -f /var/lib/hjem/$(basename $manifest) ]; then
                ${linker} activate $manifest
                continue
              fi

              ${linker} diff $manifest /var/lib/hjem/$(basename $manifest)
            done

            cp -rT ${manifests} /var/lib/hjem
          '';
        };
      }
    )
  ];
}
