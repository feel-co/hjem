{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkOption;
  inherit (lib.types) attrsOf listOf oneOf bool int path str;
  inherit (lib.attrsets) attrNames mapAttrsToList;
  inherit (lib.strings) concatStringsSep;
  inherit (lib.lists) elem filter isList;

  envFile = "99-user-env.conf";
  cfg = config.environment;

  toEnv = env:
    if isList env
    then concatStringsSep ":" (map toString env)
    else toString env;

  toConf = attrs:
    concatStringsSep "\n"
    (mapAttrsToList (name: value: "${name}=\"${toEnv value}\"") attrs);
in {
  options.environment = {
    sessionVariables = mkOption {
      type = attrsOf (oneOf [(listOf (oneOf [int str path])) int str path]);
      default = {};
      example = {
        EDITOR = "nvim";
        VISUAL = "nvim";
      };
      description = ''
        A set of environment variables used in the user environment.
        These variables will be set as systemd user environment
        variables, using `environment.d`. The value of each
        variable can be either a string or a list of strings. The
        latter is concatenated, interspersed with colon
        characters.
      '';
    };
    forceOverride = mkOption {
      type = bool;
      default = false;
      example = true;
      description = ''
        Whether to override environment variables that might exist.
        This is useful for variables such as {env}`EDITOR`, which are set by
        default on NixOS.
      '';
    };
  };

  config = {
    files.".config/environment.d/${envFile}".text = toConf cfg.sessionVariables;

    warnings = let
      overlappingVars = filter (x: elem x (attrNames config.environment.sessionVariables)) (attrNames cfg.sessionVariables);
    in
      if
        !cfg.forceOverride
        && overlappingVars != []
      then
        map (name: ''
          The session variable '${name}' is defined in both
          `hjem.users.<name>.environment.sessionVariables` and
          `config.environment.variables`. This may lead to conflicts.

          If you want the one defined in hjem to take precedence, make sure you
          set `forceOverride` to `true`.
        '')
        overlappingVars
      else [];
  };
}
