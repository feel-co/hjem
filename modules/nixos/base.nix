{
  config,
  hjem-lib,
  lib,
  options,
  pkgs,
  utils,
  ...
}: let
  inherit (builtins) attrNames attrValues concatLists concatMap concatStringsSep filter mapAttrs toJSON typeOf;
  inherit (hjem-lib) fileToJson;
  inherit (lib.attrsets) filterAttrs optionalAttrs;
  inherit (lib.modules) importApply mkDefault mkIf mkMerge;
  inherit (lib.strings) optionalString;
  inherit (lib.trivial) flip pipe;
  inherit (lib.types) submoduleWith;
  inherit (lib.meta) getExe;

  osConfig = config;

  cfg = config.hjem;
  _class = "nixos";

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

  newManifests = let
    writeManifest = username: let
      name = "manifest-${username}.json";
    in
      pkgs.writeTextFile {
        inherit name;
        destination = "/${name}";
        text = toJSON {
          version = 3;
          files = concatMap (
            flip pipe [
              attrValues
              (filter (x: x.enable))
              (map fileToJson)
            ]
          ) (userFiles cfg.users.${username});
        };
        checkPhase = ''
          set -e
          CUE_CACHE_DIR=$(pwd)/.cache
          CUE_CONFIG_DIR=$(pwd)/.config

          ${getExe pkgs.cue} vet -c ${../../manifest/v3.cue} $target
        '';
      };
  in
    pkgs.symlinkJoin
    {
      name = "hjem-manifests";
      paths = map writeManifest (attrNames enabledUsers);
    };

  hjemSubmodule = submoduleWith {
    description = "Hjem submodule for NixOS";
    class = "hjem";
    specialArgs =
      cfg.specialArgs
      // {
        inherit hjem-lib osConfig pkgs utils;
        osOptions = options;
      };
    modules =
      concatLists
      [
        [
          ../common/user.nix
          ./systemd.nix
          ({
            config,
            name,
            ...
          }: let
            user = osConfig.users.users.${name};
          in {
            assertions = [
              {
                assertion = config.enable -> user.enable;
                message = "Enabled Hjem user '${name}' must also be configured and enabled in NixOS.";
              }
            ];

            user = mkDefault user.name;
            directory = mkDefault user.home;
            clobberFiles = mkDefault cfg.clobberByDefault;
          })
        ]
        # Evaluate additional modules under 'hjem.users.<username>' so that
        # module systems built on Hjem are more ergonomic.
        cfg.extraModules
      ];
  };
in {
  inherit _class;

  imports = [
    (importApply ../common/top-level.nix {inherit hjemSubmodule _class;})
  ];

  config = mkMerge [
    # Constructed rule string that consists of the type, target, and source
    # of a tmpfile. Files with 'null' sources are filtered before the rule
    # is constructed.
    (mkIf (cfg.linker == null) {
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
            "hjem-reload@${name}.service"
            "hjem-copy@${name}.service"
          ];
        in
          concatMap requiredUserServices (attrNames enabledUsers)
          ++ ["hjem-cleanup.service"];
      };

      systemd.services = let
        oldManifests = "/var/lib/hjem";
        checkEnabledUsers = ''
          case "$1" in
            ${concatStringsSep "|" (attrNames enabledUsers)}) ;;
            *) echo "User '%i' is not configured for Hjem" >&2; exit 0 ;;
          esac
        '';
      in
        optionalAttrs (enabledUsers != {}) {
          hjem-prepare = {
            description = "Prepare Hjem manifests directory";
            enableStrictShellChecks = true;
            script = "mkdir -p ${oldManifests}";
            serviceConfig.Type = "oneshot";
            unitConfig.RefuseManualStart = true;
          };

          "hjem-activate@" = {
            description = "Link files for %i from their manifest";
            enableStrictShellChecks = true;
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
              new_manifest="${newManifests}/manifest-$1.json"
              old_manifest="${oldManifests}/manifest-$1.json"

              if [ ! -f "$old_manifest" ]; then
                ${linker} ${linkerOpts} activate "$new_manifest"
                exit 0
              fi

              ${linker} ${linkerOpts} diff "$new_manifest" "$old_manifest"
            '';
          };

          "hjem-reload@" = {
            description = "Reload systemd user units for %i after Hjem file activation";
            enableStrictShellChecks = true;
            serviceConfig = {
              User = "%i";
              Type = "oneshot";
            };
            requires = ["hjem-activate@%i.service"];
            after = ["hjem-activate@%i.service"];
            path = [config.systemd.package pkgs.coreutils-full pkgs.jq pkgs.gnugrep];
            scriptArgs = "%i";
            script = ''
              ${checkEnabledUsers}

              # XXX: This assumes that the XDG runtime directory is /run/user/<uid> which is correct
              # *most of the time* but we cannot guarantee it. In the future we should try to infer
              # and respect the existing runtime directory.
              uid=$(id -u)
              XDG_RUNTIME_DIR="/run/user/$uid"
              export XDG_RUNTIME_DIR

              systemd_status=$(systemctl --user is-system-running 2>&1 || true)
              if [ "$systemd_status" != "running" ] && [ "$systemd_status" != "degraded" ]; then
                echo "User systemd for $1 is not running (status: $systemd_status). Skipping."
                exit 0
              fi

              new_manifest="${newManifests}/manifest-$1.json"
              old_manifest="${oldManifests}/manifest-$1.json"

              systemctl --user daemon-reload

              if [ ! -f "$old_manifest" ]; then
                echo "No previous manifest for $1; skipping trigger-based restarts."
                exit 0
              fi

              # Compare trigger values for each individually-linked systemd unit file.
              # Only act on units that existed before; no auto-start for new ones.
              while IFS=$'\t' read -r unit_name new_file; do
                old_file=$(jq -re \
                  --arg name "$unit_name" \
                  '.files[] | select((.type == "symlink") and (.target | endswith("/systemd/user/" + $name))) | .source' \
                  "$old_manifest" 2>/dev/null || true)

                if [ -z "$old_file" ] || [ ! -f "$old_file" ] || [ ! -f "$new_file" ]; then
                  continue
                fi

                # Extract trigger values from old and new unit files (empty string if not present)
                old_restart=$(grep "^X-Restart-Triggers=" "$old_file" 2>/dev/null | cut -d= -f2- || true)
                new_restart=$(grep "^X-Restart-Triggers=" "$new_file" 2>/dev/null | cut -d= -f2- || true)
                old_reload=$(grep "^X-Reload-Triggers=" "$old_file" 2>/dev/null | cut -d= -f2- || true)
                new_reload=$(grep "^X-Reload-Triggers=" "$new_file" 2>/dev/null | cut -d= -f2- || true)

                # Only restart/reload if the trigger values actually changed
                if [ -n "$new_restart" ] && [ "$old_restart" != "$new_restart" ]; then
                  echo "Restarting $unit_name for $1 (restart trigger changed)"
                  systemctl --user try-restart "$unit_name" \
                    || echo "Warning: try-restart of $unit_name failed"
                elif [ -n "$new_reload" ] && [ "$old_reload" != "$new_reload" ]; then
                  echo "Reloading $unit_name for $1 (reload trigger changed)"
                  systemctl --user reload-or-try-restart "$unit_name" \
                    || echo "Warning: reload-or-try-restart of $unit_name failed"
                fi
              done < <(jq -re \
                '.files[] | select(
                  (.type == "symlink") and
                  (.target | test(".+/systemd/user/[^/]+\\.(service|timer|socket)$"))
                ) | [(.target | split("/") | last), .source] | @tsv' \
                "$new_manifest" 2>/dev/null || true)
            '';
          };

          "hjem-copy@" = {
            description = "Copy the manifest into Hjem's state directory for %i";
            enableStrictShellChecks = true;
            serviceConfig.Type = "oneshot";
            after = ["hjem-reload@%i.service"];
            scriptArgs = "%i";
            /*
            TODO: remove the if condition in a while, this is in place because the first iteration of the
            manifest used to simply point /var/lib/hjem to the aggregate symlinkJoin directory. Since
            per-user manifest services have now been implemented, trying to copy singular files into
            /var/lib/hjem will fail if the user was using the previous manifest handling.
            */
            script = ''
              ${checkEnabledUsers}
              new_manifest="${newManifests}/manifest-$1.json"

              if ! cp "$new_manifest" ${oldManifests}; then
                echo "Copying the manifest for $1 failed. This is likely due to using the previous\
                version of the manifest handling. The manifest directory has been recreated and repopulated with\
                %i's manifest. Please re-run the activation services for your other users, if you have ran this one manually."

                rm -rf ${oldManifests}
                mkdir -p ${oldManifests}

                cp "$new_manifest" ${oldManifests}
              fi
            '';
          };

          hjem-cleanup = {
            description = "Cleanup disabled users' manifests";
            enableStrictShellChecks = true;
            serviceConfig.Type = "oneshot";
            after = ["hjem.target"];
            unitConfig.RefuseManualStart = false;
            script = let
              manifestsToDelete =
                map
                (user: "${oldManifests}/manifest-${user}.json")
                (attrNames disabledUsers);
            in
              if disabledUsers != {}
              then "rm -f ${concatStringsSep " " manifestsToDelete}"
              else "true";
          };
        };
    })
  ];
}
