{
  hjemModule,
  pkgs,
  lib,
}: let
  trueService = ''
    [Service]
    Type=oneshot
    ExecStart=${pkgs.coreutils}/bin/true
  '';

  package = pkgs.symlinkJoin {
    name = "hjem-test-user-units";
    paths =
      map (name: pkgs.writeTextDir "lib/systemd/user/${name}.service" trueService) [
        "packaged"
        "masked"
        "worker@"
      ]
      ++ [
        (pkgs.writeTextDir "lib/systemd/user/packaged.service.d/10-upstream.conf" ''
          [Service]
          Environment=UPSTREAM=preserved
        '')
      ];
  };

  evaluated = import (pkgs.path + "/nixos/lib/eval-config.nix") {
    inherit pkgs;
    modules = [
      hjemModule
      {
        users.users.alice.isNormalUser = true;
        hjem.users.alice = {
          enable = true;
          systemd = {
            packages = [package];
            services = {
              packaged = {
                wantedBy = ["default.target"];
                requiredBy = ["custom.target"];
                upheldBy = ["custom.target"];
                aliases = ["alias.service"];
                environment.HJEM = "extended";
              };
              masked.enable = false;
              "worker@instance" = {
                overrideStrategy = "asDropin";
                wantedBy = ["default.target"];
                environment.HJEM = "instance";
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
      }
    ];
  };

  files = evaluated.config.hjem.users.alice.xdg.config.files;
  tree = pkgs.linkFarm "hjem-test-user-unit-tree" (
    lib.mapAttrsToList (name: file: {
      name = lib.removePrefix "systemd/user/" name;
      path = file.source;
    })
    files
  );
in
  pkgs.runCommand "hjem-systemd-packages" {
    nativeBuildInputs = [pkgs.systemd];
  } ''
    # Dependency and alias links must resolve to the upstream service, not its
    # generated drop-in (which has no ExecStart).
    for entry in packaged.service alias.service \
      default.target.wants/packaged.service \
      custom.target.requires/packaged.service \
      custom.target.upholds/packaged.service; do
      cmp "${tree}/$entry" "${package}/lib/systemd/user/packaged.service"
    done
    test "$(readlink -f '${tree}/masked.service')" = /dev/null
    cmp '${tree}/packaged.service.d/10-upstream.conf' \
      '${package}/lib/systemd/user/packaged.service.d/10-upstream.conf'
    grep -F 'Environment="HJEM=extended"' '${tree}/packaged.service.d/overrides.conf'
    grep -F 'Environment="HJEM=instance"' '${tree}/worker@instance.service.d/overrides.conf'
    cmp '${tree}/default.target.wants/local.service' '${tree}/local.service'

    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -m 700 "$XDG_RUNTIME_DIR"
    SYSTEMD_UNIT_PATH='${tree}:${pkgs.systemd}/example/systemd/user' \
      systemd-analyze --user verify \
      packaged.service worker@instance.service local.service
    touch "$out"
  ''
