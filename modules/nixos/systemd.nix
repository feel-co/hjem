{
  lib,
  pkgs,
  osConfig,
  config,
  ...
}: let
  inherit (lib.attrsets) nameValuePair mapAttrs';
  inherit (lib.options) mkOption;

  utils = import "${pkgs.path}/nixos/lib/utils.nix" {
    inherit lib pkgs;
    config = osConfig;
  };

  inherit (utils) systemdUtils;
  inherit (systemdUtils.lib) generateUnits serviceToUnit;

  cfg = config.systemd;
in {
  options.systemd = {
    services = mkOption {
      default = {};
      type = systemdUtils.types.services;
      description = "Definition of systemd per-user service units.";
    };
    units = mkOption {
      description = "Definition of systemd per-user units.";
      default = {};
      type = systemdUtils.types.units;
    };
  };

  config = {
    systemd.units = mapAttrs' (n: v: nameValuePair "${n}.service" (serviceToUnit v)) cfg.services;
    files.".config/systemd/user".source = generateUnits {
      type = "user";
      inherit (cfg) units;
      upstreamUnits = []; # this is already done in the NixOS module
      upstreamWants = []; # same here
      packages = []; # unnecessary, we're using `generateUnits` at user level (no need for hooks or units for now)
      inherit (osConfig.systemd) package;
    };
  };
}
