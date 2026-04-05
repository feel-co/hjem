{
  config,
  hjem-lib,
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

  linker = getExe (
    if cfg.linker == null
    then pkgs.smfh
    else cfg.linker
  );

  newManifests = let
    writeManifest = username: let
      name = "manifest-${username}.json";
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
          ]) (userFiles cfg.users.${username});
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
      paths = map writeManifest (attrNames enabledUsers);
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
    (
      let
        oldManifests = "/var/lib/hjem";
        linkerOpts =
          if typeOf cfg.linkerOptions == "set"
          then ''--linker-opts "${toJSON cfg.linkerOptions}"''
          else concatStringsSep " " cfg.linkerOptions;
      in {
        finit.tasks =
          {
            hjem-prepare = {
              description = "Prepare Hjem manifests directory";
              command = pkgs.writeShellScript "hjem-prepare" ''
                mkdir -p ${oldManifests}
              '';
            };

            hjem-cleanup = {
              description = "Cleanup disabled users' manifests";
              conditions = map (username: "task/hjem-copy-${username}/success") (attrNames enabledUsers);

              command = pkgs.writeShellScript "hjem-cleanup" (
                if disabledUsers != {}
                then "rm -f ${
                  concatStringsSep " " (map (user: "${oldManifests}/manifest-${user}.json") (attrNames disabledUsers))
                }"
                else "true"
              );
            };
          }
          // optionalAttrs (enabledUsers != {}) (
            listToAttrs (
              concatMap (
                username: let
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

                      if [ ! -f "$old_manifest" ]; then
                        exec ${linker} ${linkerOpts} activate "$new_manifest"
                      fi

                      exec ${linker} ${linkerOpts} diff "$new_manifest" "$old_manifest"
                    '';
                  })
                  (nameValuePair copyName {
                    description = "Copy the manifest into Hjem's state directory for ${username}";
                    conditions = ["task/${activateName}/success"];
                    command = pkgs.writeShellScript copyName ''
                      new_manifest="${newManifests}/manifest-${username}.json"

                      if ! cp "$new_manifest" ${oldManifests}; then
                        echo "Copying the manifest for ${username} failed. This is likely due to using the previous version of the manifest handling. The manifest directory has been recreated and repopulated with ${username}'s manifest. Please re-run the activation tasks for your other users."

                        rm -rf ${oldManifests}
                        mkdir -p ${oldManifests}

                        cp "$new_manifest" ${oldManifests}
                      fi
                    '';
                  })
                ]
              ) (attrNames enabledUsers)
            )
          );
      }
    )
  ];
}
