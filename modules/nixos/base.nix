{
  config,
  hjem-lib,
  lib,
  options,
  pkgs,
  hjem-package,
  utils,
  ...
}: let
  inherit (builtins) attrNames attrValues concatLists concatMap concatStringsSep filter mapAttrs toJSON typeOf;
  inherit (hjem-lib) fileToJson;
  inherit (lib.attrsets) filterAttrs optionalAttrs;
  inherit (lib.modules) importApply mkDefault mkIf mkMerge;
  inherit (lib.strings) concatMapStringsSep optionalString;
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

  hjemCli = getExe hjem-package;
  hjemPkg = hjem-package;
  useExternalLinker = cfg.linker != hjemPkg;
  linkerExe = getExe cfg.linker;
  prefix =
    if (typeOf cfg.linkerOptions == "set") && cfg.linkerOptions ? prefix
    then cfg.linkerOptions.prefix
    else ".backup-";
  linkerArgFlags =
    if !useExternalLinker
    then ""
    else if typeOf cfg.linkerOptions == "set"
    then let
      optsFile = pkgs.writeText "hjem-linker-options.json" (toJSON cfg.linkerOptions);
    in ''--linker-arg --linker-opts --linker-arg ${optsFile}''
    else concatMapStringsSep " " (arg: ''--linker-arg "${arg}"'') cfg.linkerOptions;
  externalLinkerFlags =
    if useExternalLinker
    then ''--external-linker "${linkerExe}" ${linkerArgFlags}''
    else "";

  newManifests = let
    writeManifest = user: let
      name = "manifest-${user.user}.json";
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
          ) (userFiles user);
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
      paths = map writeManifest (attrValues enabledUsers);
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
    {
      system.extraDependencies = concatMap (u: u.extraDependencies) (attrValues enabledUsers);
    }

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
          ];
        in
          concatMap requiredUserServices (map (u: u.user) (attrValues enabledUsers))
          ++ ["hjem-cleanup.service"];
      };

      systemd.services = let
        oldManifests = "/var/lib/hjem";
        checkEnabledUsers = ''
          case "$1" in
            ${concatStringsSep "|" (map (u: u.user) (attrValues enabledUsers))}) ;;
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
            requires = ["hjem-prepare.service"];
            after = ["hjem-prepare.service"];
            scriptArgs = "%i";
            script = ''
              ${checkEnabledUsers}
              new_manifest="${newManifests}/manifest-$1.json"
              old_manifest="${oldManifests}/manifest-$1.json"
              actions_file="${oldManifests}/actions-$1.json"

              ${hjemCli} internal activate \
                --manifest "$new_manifest" \
                --state "$old_manifest" \
                --actions-file "$actions_file" \
                --prefix "${prefix}" \
                ${externalLinkerFlags} \
                --json
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
            path = [config.systemd.package pkgs.coreutils-full];
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

              actions_file="${oldManifests}/actions-$1.json"
              ${hjemCli} internal reload-actions \
                --actions-file "$actions_file" \
                --user "$1" \
                --require-running-systemd
            '';
          };

          hjem-cleanup = {
            description = "Cleanup disabled users' manifests";
            enableStrictShellChecks = true;
            serviceConfig.Type = "oneshot";
            after = ["hjem.target"];
            unitConfig.RefuseManualStart = false;
            script = ''
              ${hjemCli} internal cleanup-state \
                --state-dir ${oldManifests} \
                ${concatMapStringsSep " " (u: ''--enabled-user "${u.user}"'') (attrValues enabledUsers)}
            '';
          };
        };
    })
  ];
}
