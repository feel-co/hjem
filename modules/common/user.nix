# The common module that contains Hjem's per-user options. To ensure Hjem remains
# somewhat compliant with cross-platform paradigms (e.g. NixOS or Darwin.) Platform
# specific options such as nixpkgs module system or nix-darwin module system should
# be avoided here.
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.modules) mkIf mkDefault mkDerivedConfig;
  inherit (lib.options) mkOption mkEnableOption literalExpression;
  inherit (lib.strings) hasPrefix;
  inherit (lib.types) attrsOf bool lines listOf nullOr package path str submodule;

  clobberOpt = config.clobberFiles;

  fileType = relativeTo:
    submodule ({
      name,
      target,
      config,
      options,
      ...
    }: {
      options = {
        enable = mkOption {
          type = bool;
          default = true;
          example = false;
          description = ''
            Whether this file should be generated. If set to `false`, the file will
            not be created.
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
          description = "Text of the file";
        };

        source = mkOption {
          type = nullOr path;
          default = null;
          description = "Path of the source file or directory";
        };

        executable = mkOption {
          type = bool;
          default = false;
          example = true;
          description = ''
            Whether to set the execute bit on the target file.
          '';
        };

        clobber = mkOption {
          type = bool;
          default = clobberOpt;
          defaultText = literalExpression "config.hjem.clobberByDefault";
          description = ''
            Whether to "clobber" existing target paths.

            - If using the **systemd-tmpfiles** hook (Linux only), tmpfile rules
              will be constructed with `L+` (*re*create) instead of `L`
              (create) type while this is set to `true`.
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
        source = mkIf (config.text != null) (mkDerivedConfig options.text (text:
          pkgs.writeTextFile {
            inherit name text;
            inherit (config) executable;
          }));
      };
    });
in {
  imports = [
    # Makes "assertions" option available without having to duplicate the work
    # already done in the Nixpkgs module.
    (pkgs.path + "/nixos/modules/misc/assertions.nix")
  ];

  options = {
    enable = mkEnableOption "Whether to enable home management for this user" // {default = true;};
    user = mkOption {
      type = str;
      description = "The owner of a given home directory.";
    };

    directory = mkOption {
      type = path;
      description = ''
        The home directory for the user, to which files configured in
        {option}`hjem.users.<name>.files` will be relative to by default.
      '';
    };

    clobberFiles = mkOption {
      type = bool;
      example = true;
      description = ''
        The default override behaviour for files managed by Hjem for a
        particular user.

        A top level option exists under the Hjem module option
        {option}`hjem.clobberByDefault`. Per-file behaviour can be modified
        with {option}`hjem.users.<name>.files.<file>.clobber`.
      '';
    };

    files = mkOption {
      default = {};
      type = attrsOf (fileType config.directory);
      example = {".config/foo.txt".source = "Hello World";};
      description = "Files to be managed by Hjem";
    };

    packages = mkOption {
      type = listOf package;
      default = [];
      example = literalExpression "[pkgs.hello]";
      description = "Packages for ${config.user}";
    };
  };

  config = {
    assertions = [
      {
        assertion = config.user != "";
        message = "A user must be configured in 'hjem.users.<user>.name'";
      }
      {
        assertion = config.directory != "";
        message = "A home directory must be configured in 'hjem.users.<user>.directory'";
      }
    ];
  };
}
