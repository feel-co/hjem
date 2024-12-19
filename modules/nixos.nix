{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.modules) mkIf mkDefault;
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.strings) hasPrefix concatStringsSep;
  inherit (lib.lists) filter map;
  inherit (lib.attrsets) filterAttrs mapAttrs' attrValues mapAttrsToList;
  inherit (lib.types) bool submodule str path attrsOf nullOr lines;

  usrCfg = config.users.users;

  fileType = relativeTo:
    submodule ({
      name,
      target,
      config,
      ...
    }: {
      options = {
        enable = mkOption {
          type = bool;
          default = true;
          description = ''
            Whether this file should be generated. This option allows specific
            files to be disabled.
          '';
        };
        target = mkOption {
          type = str;
          apply = p:
            if hasPrefix "/" p
            then throw "This option cannot handle absolute paths yet!"
            else "${config.relativeTo}/${p}";
          defaultText = "name";
          description = ''
            Path to target file relative to ${config.relativeTo}.
          '';
        };

        text = mkOption {
          default = null;
          type = nullOr lines;
          description = ''
            Text of the file.
          '';
        };

        source = mkOption {
          type = nullOr path;
          default = null;
          description = ''
            Path of the source file or directory.
          '';
        };

        executable = mkOption {
          type = nullOr bool;
          default = false;
          description = ''
            Whether to set the execute bit on the target file.
          '';
        };

        clobber = mkOption {
          type = bool;
          default = false;
          example = true;
          description = ''
            Whether to "clobber" existing target paths. While `true`, tmpfile rules will be constructed
            with `L+` (*re*create) instead of `L` (create) type.
          '';
        };

        relativeTo = mkOption {
          internal = true;
          type = path;
          default = relativeTo;
          description = "Path to which symlinks will be relative to";
          apply = x:
            assert (hasPrefix "/" x || abort "Relative path ${x} cannot be used for files.<file>.relativeTo"); x;
        };
      };

      config = {
        target = mkDefault name;
        source = mkIf (config.text != null) (mkDefault (pkgs.writeTextFile {
          inherit name;
          inherit (config) text executable;
        }));
      };
    });

  homeOpts = {
    name,
    config,
    ...
  }: {
    options = {
      enable = mkEnableOption "Whether to enable home management for ${name}" // {default = true;};
      user = mkOption {
        type = str;
        default = name;
        description = "The owner of a given home directory.";
        apply = x: assert (builtins.hasAttr x usrCfg || abort "A home has  been configured for ${x}, but the user does not exist"); x;
      };

      directory = mkOption {
        type = path;
        default = usrCfg.${config.user}.home;
        defaultText = "Home directory inherited from {option}`users.users.${name}.home`";
        description = ''
          The home directory for the user, to which files configured in
          {option}`homes.<name>.files` will be relative to by default.
        '';
      };

      files = mkOption {
        default = {};
        type = attrsOf (fileType config.directory);
        description = "Files to be managed, inserted to relevant systemd-tmpfiles rules";
      };

      packages = mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "Packages for ${config.user}";
      };
    };
  };
in {
  options = {
    homes = mkOption {
      default = {};
      type = attrsOf (submodule homeOpts);
      description = "Home configurations to be managed";
    };
  };

  config = {
    users.users = mapAttrs' (name: {packages, ...}: {
      inherit name;
      value.packages = packages;
    }) (filterAttrs (_: u: u.packages != []) config.homes);

    systemd.user.tmpfiles.users = mapAttrs' (name: {files, ...}: {
      inherit name;
      value.rules = map (
        file: let
          # L+ will recrate, i.e., clobber existing files.
          mode =
            if file.clobber
            then "L+"
            else "L";

          # Constructed rule string that consists of the type, target, and source
          # of a tmpfile. Files with 'null' sources are filtered before the rule
          # is constructed.
          ruleString = [mode file.target "- - - -" file.source];
        in
          concatStringsSep " " ruleString
      ) (filter (f: f.enable && f.source != null) (attrValues files));
    }) (filterAttrs (_: u: u.files != {}) config.homes);
    systemd.services = mapAttrs' (name: {files, ...}: {
      name = "hjem-monitor-" + name;
      value.enable = true;
      value.wants = ["systemd-tmpfiles-setup.service" "nix-daemon.socket"];
      value.after = ["nix-daemon.socket"];
      value.wantedBy = ["default.target"];
      value.description = "Monitoring for Hjem files";
      value.serviceConfig = {
        Type = "exec";
        ExecStart = let
          serviceScript = pkgs.writeScript "hjem-monitor-script" ''
            #! ${pkgs.runtimeShell} -e
            code=0
            for var in "$@"
            do
              if [ ! -L "$var" ] ; then
                echo "$var is not controlled by hjem due to a file conflict"
                code=1
              fi
            done
            if [ "$code" -eq "0" ] ; then
              exit 0
            else
              exit 1
            fi
          '';
        in "${serviceScript} ${toString (map (
          file: file.target
        ) (filter (f: f.enable && f.source != null) (attrValues files)))}";
      };
    }) (filterAttrs (_: u: u.files != {}) config.homes);
  };
}
