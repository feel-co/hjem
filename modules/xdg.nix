{
  lib,
  config,
  ...
}: let
  inherit (lib.options) mkOption mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.xdg;
in {
  options.xdg = {
    enable = mkEnableOption "xdg";
    cacheDirectory = mkOption {
      default = "${config.directory}/.cache";
    };
    stateDirectory = mkOption {
      default = "${config.directory}/.local/state";
    };
    dataDirectory = mkOption {
      default = "${config.directory}/.local/share";
    };
    configDirectory = mkOption {
      default = "${config.directory}/.config";
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
