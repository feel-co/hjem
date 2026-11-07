{
  hjemModule,
  pkgs,
  lib,
}: let
  # Keep the fixtures available during evaluation without building packages.
  package = builtins.path {
    name = "hjem-test-user-units";
    path = ./fixture;
  };
  laterPackage = builtins.path {
    name = "hjem-test-later-user-units";
    path = ./fixture-later;
  };
  configHome = "/home/alice/custom-config";

  evaluated = pkgs.nixos {
    imports = [hjemModule];
    users.users.alice.isNormalUser = true;
    hjem.users.alice = {
      enable = true;
      xdg.config.directory = configHome;
      systemd = {
        packages = [package laterPackage];
        services = {
          packaged = {
            wantedBy = ["default.target"];
            requiredBy = ["custom.target"];
            upheldBy = ["custom.target"];
            aliases = ["alias.service"];
            environment.HJEM = "extended";
          };
          masked = {
            enable = false;
            overrideStrategy = "asDropin";
          };
          "worker@instance" = {
            overrideStrategy = "asDropin";
            wantedBy = ["default.target"];
            environment.HJEM = "instance";
          };
          replaced = {
            overrideStrategy = "asReplacement";
            description = "Hjem replacement";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.coreutils}/bin/true";
            };
          };
          local = {
            wantedBy = ["default.target"];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "${pkgs.coreutils}/bin/true";
            };
          };
        };
        targets.custom = {};
      };
    };
  };

  inherit (import ../../../lib.nix {inherit lib pkgs;}) fileToJson;
  files = lib.mapAttrs (_: fileToJson) evaluated.config.hjem.users.alice.xdg.config.files;
  linkCommands = lib.concatStringsSep "\n" (lib.mapAttrsToList (_: file: let
      target = lib.removePrefix "${configHome}/" file.target;
      source = lib.escapeShellArg file.source;
      linkSource =
        if file.follow_symlinks or true
        then ''"$(realpath -e ${source})"''
        else ''"$config_home"/${lib.escapeShellArg (lib.removePrefix "${configHome}/" file.source)}'';
    in ''
      mkdir -p "$config_home"/${lib.escapeShellArg (builtins.dirOf target)}
      ln -s ${linkSource} "$config_home"/${lib.escapeShellArg target}
    '')
    files);
in
  pkgs.runCommand "hjem-systemd-packages" {
    nativeBuildInputs = [pkgs.systemd];
  } ''
    config_home="$TMPDIR/config"
    tree="$config_home/systemd/user"
    ${linkCommands}

    # lib wins within a package, and a later package wins even from etc.
    cmp "$tree/packaged.service" '${package}/lib/systemd/user/packaged.service'
    cmp "$tree/cross-package.service" '${laterPackage}/etc/systemd/user/cross-package.service'
    test "$(readlink "$tree/alias.service")" = "$tree/packaged.service"
    for entry in default.target.wants/packaged.service \
      custom.target.requires/packaged.service \
      custom.target.upholds/packaged.service; do
      cmp "$tree/$entry" "$tree/packaged.service"
    done

    test "$(readlink "$tree/masked.service")" = /dev/null
    test ! -e "$tree/masked.service.d"

    cmp "$tree/packaged.service.d/10-upstream.conf" \
      '${package}/lib/systemd/user/packaged.service.d/10-upstream.conf'
    cmp "$tree/packaged.service.d/overrides.conf" \
      '${package}/lib/systemd/user/packaged.service.d/overrides.conf'
    grep -F 'Environment="HJEM=extended"' "$tree/packaged.service.d/"*.conf

    grep -F 'Environment="HJEM=instance"' "$tree/worker@instance.service.d/"*.conf
    test ! -L "$tree/worker@instance.service"
    cmp "$tree/default.target.wants/worker@instance.service" "$tree/worker@.service"
    cmp "$tree/default.target.wants/local.service" "$tree/local.service"

    grep -Fx 'Description=Hjem replacement' "$tree/replaced.service"
    test ! -e "$tree/replaced.service.d"

    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -m 700 "$XDG_RUNTIME_DIR"
    SYSTEMD_UNIT_PATH="$tree:${pkgs.systemd}/example/systemd/user" \
      systemd-analyze --user verify \
      alias.service packaged.service worker@instance.service local.service replaced.service
    touch "$out"
  ''
