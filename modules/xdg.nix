{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf;
  inherit (lib.types) str;

  cfg = config.xdg;
in {
  options.xdg = {
    enable = mkEnableOption "xdg";
    cacheDirectory = mkOption {
      type = str;
      default = "${config.directory}/.cache";
      description = ''
        Folder for application cache, creates a folder and sets the `XDG_CACHE_HOME` environment variable.
      '';
    };
    stateDirectory = mkOption {
      type = str;
      default = "${config.directory}/.local/state";
      description = ''
        Folder for application state, creates a folder and sets the `XDG_STATE_HOME` environment variable.
      '';
    };
    dataDirectory = mkOption {
      type = str;
      default = "${config.directory}/.local/share";
      description = ''
        Folder for application data, creates a folder and sets the `XDG_DATA_HOME` environment variable.
      '';
    };
    configDirectory = mkOption {
      type = str;
      default = "${config.directory}/.config";
      description = ''
        Folder for application configuration, creates a folder and sets the `XDG_CONFIG_HOME` environment variable.
      '';
    };
  };
  config = mkIf cfg.enable {
    files = {
      "${cfg.cacheDirectory}".type = "directory";
      "${cfg.stateDirectory}".type = "directory";
      "${cfg.dataDirectory}".type = "directory";
      "${cfg.configDirectory}".type = "directory";
    };

    environment.sessionVariables = {
      XDG_CACHE_HOME = cfg.cacheDirectory;
      XDG_CONFIG_HOME = cfg.configDirectory;
      XDG_DATA_HOME = cfg.dataDirectory;
      XDG_STATE_HOME = cfg.stateDirectory;
    };
  };
}
