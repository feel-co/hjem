{
  config,
  hjem-lib,
  lib,
  options,
  pkgs,
  ...
}: let
  inherit (builtins) attrNames concatLists concatMap getAttr replaceStrings;
  inherit (lib.attrsets) filterAttrs foldlAttrs;
  inherit (lib.lists) singleton;
  inherit (lib.meta) getExe getExe';
  inherit (lib.modules) importApply mkAfter mkDefault;
  inherit (lib.strings) concatMapAttrsStringSep escapeShellArgs hasPrefix;
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

  # I force the home here. Cause on linux it's home/ but on macos/dariwn, it's Users/
  userHome = u: "/Users/${(getAttr u config.users.users).name}";
  userName = u: (getAttr u config.users.users).name;

  # I convert shorthand target to real path aka normalize
  normalizeTarget = u: t: let
    home = userHome u;
    name = userName u;
  in
    if hasPrefix "~/" t
    then replaceStrings ["~/"] ["${home}/"] t
    else if hasPrefix "/home/${name}/" t
    then replaceStrings ["/home/${name}/"] ["${home}/"] t
    else t;

  mapFiles = username: files:
    foldlAttrs
    (
      accum: _: value:
        if value.enable -> value.source == null
        then accum
        else
          accum
          ++ singleton {
            type = "symlink";
            source = value.source;
            target = normalizeTarget username value.target;
          }
    ) []
    files;

  # Most stuff is the exact same to the nixos module
  # Perhaps they should share a file or something with settings
  # For now, just copy and pasted settings (mostly)
  writeManifest = username: let
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
        ${getExe pkgs.cue} vet -c ${../../manifest/v1.cue} $target
      '';
    };

  newManifests = pkgs.symlinkJoin {
    name = "hjem-manifests";
    paths = map writeManifest (attrNames enabledUsers);
  };

  hjemSubmodule = submoduleWith {
    description = "Hjem submodule for nix-darwin.";
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
        # Evaluate additional modules under 'hjem.users.<name>' so that
        # module systems built on Hjem are more ergonomic.
        cfg.extraModules
      ];
  };

  linkerArgs =
    if builtins.isAttrs cfg.linkerOptions
    then let
      f = pkgs.writeText "smfh-opts.json" (builtins.toJSON cfg.linkerOptions);
    in ["--linker-opts" f]
    else cfg.linkerOptions;

  argsStr = escapeShellArgs linkerArgs;
in {
  imports = [
    (importApply ../common/top-level.nix {inherit hjemSubmodule _class;})
  ];

  config = {
    # Temporary requirement: choose a primary user, pick the first enabled user.
    # This option will be depracated in the future.
    system.primaryUser = mkDefault (builtins.head (attrNames enabledUsers));

    # launchd agent to apply/diff the manifest per logged-in user
    # https://github.com/nix-darwin/nix-darwin/issues/871#issuecomment-2340443820
    launchd.user.agents = {
      hjem-activate = {
        serviceConfig = {
          Program = getExe (pkgs.writeShellApplication {
            name = "hjem-activate";
            # Maybe the kickstart is broken because a runtimeInput is missing?
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
          Program = getExe (pkgs.writeShellApplication {
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
          Label = "org.nix.link-nix-apps";
          RunAtLoad = true;
          StandardOutPath = "/var/tmp/link-nix-apps.out";
          StandardErrorPath = "/var/tmp/link-nix-apps.err";
        };
      };
    };

    system.activationScripts = {
      hjem-activate-kick.text = mkAfter (
        concatMapAttrsStringSep "\n"
        (u: _: ''
          if uid="$(${getExe' pkgs.coreutils-full "id"} -u ${u} 2>/dev/null)"; then
            /bin/launchctl kickstart -k "gui/''${uid}/${config.launchd.user.agents.hjem-activate.Label}" 2>/dev/null || true
          fi
        '')
        enabledUsers
      );

      # Kick the user agent for every configured user at activation.
      applications.text = mkAfter (
        concatMapAttrsStringSep "\n"
        (u: _: ''
          if uid="$(${getExe' pkgs.coreutils-full "id"} -u ${u} 2>/dev/null)"; then
            /bin/launchctl kickstart -k "gui/''${uid}/${config.launchd.user.agents.link-nix-apps.Label}" 2>/dev/null || true
          fi
        '')
        enabledUsers
      );
    };
  };
}
