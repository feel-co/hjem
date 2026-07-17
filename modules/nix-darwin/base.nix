{
  config,
  hjem-lib,
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (builtins) attrValues concatLists concatMap filter getAttr head isAttrs toJSON;
  inherit (hjem-lib) fileToJson;
  inherit (lib.attrsets) filterAttrs;
  inherit (lib.meta) getExe getExe';
  inherit (lib.modules) importApply mkAfter mkDefault;
  inherit (lib.strings) concatLines concatMapAttrsStringSep escapeShellArgs;
  inherit (lib.trivial) flip pipe;
  inherit (lib.types) submoduleWith;

  cfg = config.hjem;
  _class = "darwin";

  enabledUsers = filterAttrs (_: u: u.enable) cfg.users;

  userFiles = user: [
    user.files
    user.xdg.cache.files
    user.xdg.config.files
    user.xdg.data.files
    user.xdg.state.files
  ];

  linker = getExe cfg.linker;

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
    description = "Hjem submodule for nix-darwin";
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
            user = getAttr name config.users.users;
          in {
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

  linkerArgs =
    if isAttrs cfg.linkerOptions
    then let
      f = pkgs.writeText "smfh-opts.json" (toJSON cfg.linkerOptions);
    in ["--linker-opts" f]
    else cfg.linkerOptions;

  argsStr = escapeShellArgs linkerArgs;
in {
  imports = [
    (importApply ../common/top-level.nix {inherit hjemSubmodule _class;})
  ];

  config = {
    # nix-darwin has no `system.extraDependencies` equivalent. Best we can do is this.
    environment.etc."hjem/extra-dependencies".text = concatLines (
      concatMap (u: map (p: "${p}") u.extraDependencies) (attrValues enabledUsers)
    );

    environment.etc."hjem/activate".source = getExe (pkgs.writeShellApplication {
      name = "hjem-activate";
      runtimeInputs = with pkgs; [coreutils-full bash];
      text = ''
        set -euo pipefail

        USER="$(id -un)"
        NEW="${newManifests}/manifest-''${USER}.json"

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
    });

    environment.etc."hjem/link-nix-apps".source = getExe (pkgs.writeShellApplication {
      name = "link-nix-apps";
      runtimeInputs = with pkgs; [coreutils-full findutils gnugrep nix];
      text = ''
        set -euo pipefail

        USER="$(id -un)"
        GROUP="$(id -gn)"
        DEST="$HOME/Applications/Nix User Apps"
        PROFILE="/etc/profiles/per-user/$USER"

        install -d -m 0755 -o "$USER" -g "$GROUP" "$DEST"

        desired="$(mktemp -t desired-apps.XXXXXX)"
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
    });

    # Force users to set `primaryUser` for now, as Hjem should not automatically set it
    system.primaryUser = mkDefault (throw "Hjem no longer automatically sets `system.primaryUser`; ensure it is set correctly in your configuration.");

    # launchd agent to apply/diff the manifest per logged-in user
    # https://github.com/nix-darwin/nix-darwin/issues/871#issuecomment-2340443820
    #
    # We don't do `getExe (<script>)` here as plist bytes changing
    # will create a "Background items added" notification that the
    # user has to dismiss manually every system rebuild.
    launchd.user.agents = {
      hjem-activate = {
        serviceConfig = {
          Program = "/etc/hjem/activate";
          Label = "org.hjem.activate";
          RunAtLoad = true;
          StandardOutPath = "/var/tmp/hjem-activate.out";
          StandardErrorPath = "/var/tmp/hjem-activate.err";
        };
      };

      # Currently forced upon users, perhaps we should make an option for enabling this behavior?
      # Leaving it be for now.
      link-nix-apps = {
        serviceConfig = {
          Program = "/etc/hjem/link-nix-apps";
          Label = "org.nix.link-nix-apps";
          RunAtLoad = true;
          StandardOutPath = "/var/tmp/link-nix-apps.out";
          StandardErrorPath = "/var/tmp/link-nix-apps.err";
        };
      };
    };

    system.activationScripts.postActivation.text = mkAfter (
      concatMapAttrsStringSep "\n"
      (u: _: ''
        if uid="$(${getExe' pkgs.coreutils-full "id"} -u ${u} 2>/dev/null)"; then
          /bin/launchctl kickstart -k "gui/''${uid}/${config.launchd.user.agents.hjem-activate.serviceConfig.Label}" 2>/dev/null || true
          /bin/launchctl kickstart -k "gui/''${uid}/${config.launchd.user.agents.link-nix-apps.serviceConfig.Label}" 2>/dev/null || true
        fi
      '')
      enabledUsers
    );
  };
}
