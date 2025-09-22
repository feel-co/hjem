{ config
, hjem-lib
, lib
, options
, pkgs
, ...
}:
let
  inherit (lib.attrsets) filterAttrs mapAttrsToList;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) literalExpression mkOption;
  inherit (lib.types) attrs attrsOf bool either listOf nullOr package raw singleLineStr submoduleWith;
  inherit (lib.meta) getExe;
  inherit (builtins) attrNames mapAttrs getAttr concatLists concatStringsSep typeOf toJSON concatMap;

  cfg = config.hjem;

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  userFiles = user: [
    user.files
    user.xdg.cache.files
    user.xdg.config.files
    user.xdg.data.files
    user.xdg.state.files 
  ];

  linker = getExe cfg.linker;

  # I force the home here. Cause on linux it's home/ but on macos/dariwn, it's Users/
  userHome = u: "/Users/${(getAttr u config.users.users).name}";
  userName = u: (getAttr u config.users.users).name;

  # I convert shorthand target to real path aka normalize
  normalizeTarget = u: t:
    let
      home = userHome u;
      name = userName u;
    in
    if lib.hasPrefix "~/" t then
      lib.replaceStrings [ "~/" ] [ "${home}/" ] t
    else if lib.hasPrefix "/home/${name}/" t then
      lib.replaceStrings [ "/home/${name}/" ] [ "${home}/" ] t
    else
      t;

  mapFiles = username: files:
    lib.attrsets.foldlAttrs
      (
        accum: _: value:
          if value.enable -> value.source == null
          then accum
          else
            accum
            ++ lib.singleton {
              type = "symlink";
              source = value.source;
              target = normalizeTarget username value.target;
            }
      ) [ ]
      files;

  # Most stuff is the exact same to the nixos module
  # Perhaps they should share a file or something with settings
  # For now, just copy and pasted settings (mostly)
  writeManifest = username:
    let
      name = "manifest-${username}.json";
    in
    pkgs.writeTextFile {
      inherit name;
      destination = "/${name}";
      text = builtins.toJSON {
        clobber_by_default = cfg.users."${username}".clobberFiles;
        version = 1;
        files = concatMap (mapFiles username) (
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

  manifests =
    pkgs.symlinkJoin {
      name = "hjem-manifests";
      paths = map writeManifest (builtins.attrNames enabledUsers);
    };

  hjemModule = submoduleWith {
    description = "Hjem Darwin module";
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
            ({ name, ... }:
              let
                inherit (lib.modules) mkDefault;
                user = getAttr name config.users.users;
              in
              {
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

  linkerArgs =
    if builtins.isAttrs cfg.linkerOptions then
      let f = pkgs.writeText "smfh-opts.json" (builtins.toJSON cfg.linkerOptions);
      in [ "--linker-opts" f ]
    else
      cfg.linkerOptions;

  argsStr = lib.escapeShellArgs linkerArgs;

in
{
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
      default = { };
      type = attrsOf hjemModule;
      description = "Home configurations to be managed";
    };

    extraModules = mkOption {
      type = listOf raw;
      default = [ ];
      description = ''
        Additional modules to be evaluated as a part of the users module
        inside {option}`config.hjem.users.<name>`. This can be used to
        extend each user configuration with additional options.
      '';
    };

    specialArgs = mkOption {
      type = attrs;
      default = { };
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
      default = [ ];
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
      users.users = (mapAttrs (_: v: { inherit (v) packages; })) enabledUsers;

      assertions =
        concatLists
          (mapAttrsToList
            (user: config:
              map
                ({ assertion
                 , message
                 , ...
                 }: {
                  inherit assertion;
                  message = "${user} profile: ${message}";
                })
                config.assertions)
            enabledUsers);

      warnings =
        concatLists
          (mapAttrsToList
            (
              user: v:
                map
                  (
                    warning: "${user} profile: ${warning}"
                  )
                  v.warnings
            )
            enabledUsers);
    }

    (mkIf (cfg.linker != null) {
      # Temporary requirement: choose a primary user, pick the first enabled user.
      # This option will be depracated in the future.
      system.primaryUser = lib.mkDefault (builtins.head (attrNames enabledUsers));

      # launchd agent to apply/diff the manifest per logged-in user
      # https://github.com/nix-darwin/nix-darwin/issues/871#issuecomment-2340443820
      launchd.user.agents.hjem-activate = {
        serviceConfig = {
          Program = "${pkgs.writeShellApplication {
            name = "hjem-activate";
            # Maybe the kickstart is broken because a runtimeInput is missing?
            runtimeInputs = with pkgs; [ coreutils bash ];
            text = ''
              set -euo pipefail

              USER="$(/usr/bin/id -un)"
              NEW="${manifests}/manifest-''${USER}.json"

              if [ ! -f "$NEW" ]; then
                exit 0
              fi

              STATE_DIR="$HOME/Library/Application Support/Hjem"
              mkdir -p "$STATE_DIR"
              CUR="$STATE_DIR/manifest.json"

              if [ ! -f "$CUR" ]; then
                ${linker} ${argsStr} activate "$NEW"
              else
                ${linker} ${argsStr} diff "$NEW" "$CUR"
              fi

              cp -f "$NEW" "$CUR"
            '';
          }}/bin/hjem-activate";
          Label = "org.hjem.activate";
          RunAtLoad = true;
          StandardOutPath = "/var/tmp/hjem-activate.out";
          StandardErrorPath = "/var/tmp/hjem-activate.err";
        };
      };

      # This kickstart does not work?? No clue why.
      system.activationScripts.hjem-activate-kick.text = lib.mkAfter (lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (u: _: ''
            if uid="$(/usr/bin/id -u ${u} 2>/dev/null)"; then
              /bin/launchctl kickstart -k "gui/''${uid}/org.hjem.activate" 2>/dev/null || true
            fi
          '')
          enabledUsers
      ));
    })

    {
      # Currently forced upon users, perhaps we should make an option for enabling this behavior?
      # Leaving it be for now.
      launchd.user.agents = {
        link-nix-apps = {
          serviceConfig = {
            Program = "${pkgs.writeShellApplication {
              name = "link-nix-apps";
              runtimeInputs = with pkgs; [ coreutils findutils gnugrep bash nix ];
              text = ''
                set -euo pipefail

                USER="$(/usr/bin/id -un)"
                GROUP="$(/usr/bin/id -gn)"
                DEST="$HOME/Applications/Nix User Apps"
                PROFILE="/etc/profiles/per-user/$USER"

                install -d -m 0755 -o "$USER" -g "$GROUP" "$DEST"

                desired="$(/usr/bin/mktemp -t desired-apps.XXXXXX)"
                trap 'rm -f "$desired"' EXIT

                nix-store -qR "$PROFILE" | while IFS= read -r p; do
                  apps="$p/Applications"
                  if [ -d "$apps" ]; then
                    find "$apps" -maxdepth 1 -type d -name "*.app" -print0 \
                    | while IFS= read -r -d "" app; do
                        bname="$(basename "$app")"
                        echo "$bname" >> "$desired"
                        ln -sfn "$app" "$DEST/$bname"
                      done
                  fi
                done

                sort -u "$desired" -o "$desired"

                find "$DEST" -maxdepth 1 -type l -name "*.app" -print0 \
                | while IFS= read -r -d "" link; do
                    name="$(basename "$link")"
                    if ! grep -Fxq "$name" "$desired"; then
                      rm -f "$link"
                    fi
                  done

                # Remove broken links
                find "$DEST" -maxdepth 1 -type l -name "*.app" -print0 \
                  | xargs -0 -I {} bash -c '[[ -e "{}" ]] || rm -f "{}"'
              '';
            }}/bin/link-nix-apps";
            Label = "org.nix.link-nix-apps";
            RunAtLoad = true;
            StandardOutPath = "/var/tmp/link-nix-apps.out";
            StandardErrorPath = "/var/tmp/link-nix-apps.err";
          };
        };
      };

      # Kick the user agent for every configured user at activation.
      # Launchd does not have a After/Require unlike systemd
      # For now we are forced to use system.activationScripts
      system.activationScripts.applications.text = lib.mkAfter (lib.concatStringsSep "\n" (
        lib.mapAttrsToList
          (u: _: ''
            if uid="$(/usr/bin/id -u ${u} 2>/dev/null)"; then
              /bin/launchctl kickstart -k "gui/''${uid}/org.nix.link-nix-apps" 2>/dev/null || true
            fi
          '')
          enabledUsers
      ));
    }
  ];
}
