{
  config,
  hjem-lib,
  hjem-package,
  lib,
  options,
  pkgs,
  utils,
  ...
}: let
  inherit
    (builtins)
    attrNames
    attrValues
    concatLists
    concatMap
    concatStringsSep
    filter
    listToAttrs
    toJSON
    typeOf
    ;
  inherit (hjem-lib) fileToJson;
  inherit (lib.attrsets) filterAttrs nameValuePair optionalAttrs;
  inherit (lib.meta) getExe;
  inherit
    (lib.modules)
    importApply
    mkDefault
    mkMerge
    ;
  inherit (lib.strings) concatMapStringsSep;
  inherit (lib.trivial) flip pipe;
  inherit (lib.types) submoduleWith;

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
  actualLinker =
    if cfg.linker == null
    then hjemPkg
    else cfg.linker;
  useExternalLinker = actualLinker != hjemPkg;
  linkerExe = getExe actualLinker;
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
          files = concatMap (flip pipe [
            attrValues
            (filter (x: x.enable))
            (map fileToJson)
          ]) (userFiles user);
        };
        checkPhase = ''
          set -e
          CUE_CACHE_DIR=$(pwd)/.cache
          CUE_CONFIG_DIR=$(pwd)/.config

          ${getExe pkgs.cue} vet -c ${../../manifest/v3.cue} $target
        '';
      };
  in
    pkgs.symlinkJoin {
      name = "hjem-manifests";
      paths = map writeManifest (attrValues enabledUsers);
    };

  hjemSubmodule = submoduleWith {
    description = "Hjem submodule for Finix";
    class = "hjem";
    specialArgs =
      cfg.specialArgs
      // {
        inherit
          hjem-lib
          osConfig
          pkgs
          utils
          ;
        osOptions = options;
      };
    modules = concatLists [
      [
        ../common/user.nix
        (
          {
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
          }
        )
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
    (optionalAttrs (options ? system.extraDependencies) {
      system.extraDependencies = concatMap (u: u.extraDependencies) (attrValues enabledUsers);
    })

    {
      finit.tasks = let
        oldManifests = "/var/lib/hjem";
      in
        {
          hjem-prepare = {
            description = "Prepare Hjem manifests directory";
            command = pkgs.writeShellScript "hjem-prepare" ''
              mkdir -p ${oldManifests}
            '';
          };

          hjem-cleanup = {
            description = "Cleanup disabled users' manifests";
            conditions = map (user: "task/hjem-copy-${user.user}/success") (attrValues enabledUsers);
            command = pkgs.writeShellScript "hjem-cleanup" (
              if disabledUsers != {}
              then "rm -f ${
                concatStringsSep " " (map (user: "${oldManifests}/manifest-${user.user}.json") (attrValues disabledUsers))
              }"
              else "true"
            );
          };
        }
        // optionalAttrs (enabledUsers != {}) (
          listToAttrs (
            concatMap (
              user: let
                username = user.user;
                activateName = "hjem-activate-${username}";
                copyName = "hjem-copy-${username}";
              in [
                (nameValuePair activateName {
                  description = "Link files for ${username} from their manifest";
                  user = username;
                  conditions = ["task/hjem-prepare/success"];
                  command = pkgs.writeShellScript activateName ''
                    new_manifest="${newManifests}/manifest-${username}.json"
                    old_manifest="${oldManifests}/manifest-${username}.json"

                    ${hjemCli} internal activate \
                      --manifest "$new_manifest" \
                      --state "$old_manifest" \
                      --skip-state-update \
                      --prefix "${prefix}" \
                      ${externalLinkerFlags} \
                      --json
                  '';
                })
                (nameValuePair copyName {
                  description = "Update Hjem state manifest for ${username}";
                  conditions = ["task/${activateName}/success"];
                  command = pkgs.writeShellScript copyName ''
                    ${hjemCli} internal update-state \
                      --manifest "${newManifests}/manifest-${username}.json" \
                      --state "${oldManifests}/manifest-${username}.json"
                  '';
                })
              ]
            ) (attrValues enabledUsers)
          )
        );
    }
  ];
}
