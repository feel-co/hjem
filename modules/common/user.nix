# The common module that contains Hjem's per-user options. To ensure Hjem remains
# somewhat compliant with cross-platform paradigms (e.g. NixOS or Darwin.) Platform
# specific options such as nixpkgs module system or nix-darwin module system should
# be avoided here.
{
  config,
  hjem-lib,
  lib,
  name,
  options,
  pkgs,
  ...
}: let
  inherit (hjem-lib) envVarType toEnv;
  inherit (lib.attrsets) mapAttrsToList;
  inherit (lib.strings) concatLines;
  inherit (lib.modules) mkIf;
  inherit (lib.options) literalExpression mkEnableOption mkOption;
  inherit (lib.types) attrsOf bool listOf package path str;

  cfg = config;
  fileTypeRelativeTo' = rootDir:
    hjem-lib.fileTypeRelativeTo {
      inherit rootDir;
      clobberDefault = cfg.clobberFiles;
      clobberDefaultText = literalExpression "config.hjem.users.${name}.clobberFiles";
    };
in {
  imports = [
    # Makes "assertions" option available without having to duplicate the work
    # already done in the Nixpkgs module.
    (pkgs.path + "/nixos/modules/misc/assertions.nix")
  ];

  options = {
    enable =
      mkEnableOption "home management for this user"
      // {
        default = true;
        example = false;
      };

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
      type = attrsOf (fileTypeRelativeTo' cfg.directory);
      example = {".config/foo.txt".source = "Hello World";};
      description = "Files to be managed by Hjem";
    };

    xdg = {
      cache = {
        directory = mkOption {
          type = path;
          default = "${cfg.directory}/.cache";
          defaultText = "$HOME/.cache";
          description = ''
            The XDG cache directory for the user, to which files configured in
            {option}`hjem.users.<name>.xdg.cache.files` will be relative to by default.

            Adds {env}`XDG_CACHE_HOME` to {option}`environment.sessionVariables` for
            this user if changed.
          '';
        };
        files = mkOption {
          default = {};
          type = attrsOf (fileTypeRelativeTo' cfg.xdg.cache.directory);
          example = {"foo.txt".source = "Hello World";};
          description = "Cache files to be managed by Hjem";
        };
      };

      config = {
        directory = mkOption {
          type = path;
          default = "${cfg.directory}/.config";
          defaultText = "$HOME/.config";
          description = ''
            The XDG config directory for the user, to which files configured in
            {option}`hjem.users.<name>.xdg.config.files` will be relative to by default.

            Adds {env}`XDG_CONFIG_HOME` to {option}`environment.sessionVariables` for
            this user if changed.
          '';
        };
        files = mkOption {
          default = {};
          type = attrsOf (fileTypeRelativeTo' cfg.xdg.config.directory);
          example = {"foo.txt".source = "Hello World";};
          description = "Config files to be managed by Hjem";
        };
      };

      data = {
        directory = mkOption {
          type = path;
          default = "${cfg.directory}/.local/share";
          defaultText = "$HOME/.local/share";
          description = ''
            The XDG data directory for the user, to which files configured in
            {option}`hjem.users.<name>.xdg.data.files` will be relative to by default.

            Adds {env}`XDG_DATA_HOME` to {option}`environment.sessionVariables` for
            this user if changed.
          '';
        };
        files = mkOption {
          default = {};
          type = attrsOf (fileTypeRelativeTo' cfg.xdg.data.directory);
          example = {"foo.txt".source = "Hello World";};
          description = "data files to be managed by Hjem";
        };
      };

      state = {
        directory = mkOption {
          type = path;
          default = "${cfg.directory}/.local/state";
          defaultText = "$HOME/.local/share";
          description = ''
            The XDG state directory for the user, to which files configured in
            {option}`hjem.users.<name>.xdg.state.files` will be relative to by default.

            Adds {env}`XDG_STATE_HOME` to {option}`environment.sessionVariables` for
            this user if changed.
          '';
        };
        files = mkOption {
          default = {};
          type = attrsOf (fileTypeRelativeTo' cfg.xdg.state.directory);
          example = {"foo.txt".source = "Hello World";};
          description = "state files to be managed by Hjem";
        };
      };
    };

    packages = mkOption {
      type = listOf package;
      default = [];
      example = literalExpression "[pkgs.hello]";
      description = "Packages to install for this user";
    };

    environment = {
      loadEnv = mkOption {
        type = path;
        readOnly = true;
        description = ''
          A POSIX compliant shell script containing the user session variables needed to bootstrap the session.

          As there is no reliable and agnostic way of setting session variables, Hjem's
          environment module does nothing by itself. Rather, it provides a POSIX compliant shell script
          that needs to be sourced where needed.
        '';
      };
      sessionVariables = mkOption {
        type = envVarType;
        default = {};
        example = {
          EDITOR = "nvim";
          VISUAL = "nvim";
        };
        description = ''
          A set of environment variables used in the user environment.
          If a list of strings is used, they will be concatenated with colon
          characters.
        '';
      };
    };
  };

  config = {
    environment = {
      sessionVariables = {
        XDG_CACHE_HOME = mkIf (cfg.xdg.cache.directory != options.xdg.cache.directory.default) cfg.xdg.cache.directory;
        XDG_CONFIG_HOME = mkIf (cfg.xdg.config.directory != options.xdg.config.directory.default) cfg.xdg.config.directory;
        XDG_DATA_HOME = mkIf (cfg.xdg.data.directory != options.xdg.data.directory.default) cfg.xdg.data.directory;
        XDG_STATE_HOME = mkIf (cfg.xdg.state.directory != options.xdg.state.directory.default) cfg.xdg.state.directory;
      };
      loadEnv = lib.pipe cfg.environment.sessionVariables [
        (mapAttrsToList (name: value: "export ${name}=\"${toEnv value}\""))
        concatLines
        (pkgs.writeShellScript "load-env")
      ];
    };
    assertions = [
      {
        assertion = cfg.user != "";
        message = "A user must be configured in 'hjem.users.<user>.name'";
      }
      {
        assertion = cfg.directory != "";
        message = "A home directory must be configured in 'hjem.users.<user>.directory'";
      }
    ];
  };
}
