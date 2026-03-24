{
  hjemModule,
  hjemTest,
  smfh,
  pkgs,
}: let
  user = "alice";
  userHome = "/home/${user}";

  # A oneshot service that stays "active" via RemainAfterExit. Restarting it
  # produces a new ActiveEnterTimestamp, making restarts unambiguously detectable.
  restartSvc = name: triggerSource: {
    description = "Hjem restartTriggers test – ${name}";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/true";
    };
    restartTriggers = [triggerSource];
  };

  # A long-running service with ExecReload. Reloading it keeps the same MainPID;
  # only a full restart would change it. This lets us distinguish reload from
  # restart with certainty.
  reloadSvc = name: triggerSource: {
    description = "Hjem reloadTriggers test – ${name}";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
      ExecReload = "${pkgs.coreutils}/bin/true";
    };
    reloadTriggers = [triggerSource];
  };
in
  hjemTest {
    name = "hjem-systemd-reload";
    nodes.node1 = {
      imports = [hjemModule];

      nix.enable = false;

      users.groups.${user} = {};
      users.users.${user} = {
        isNormalUser = true;
        home = userHome;
        password = "";
      };

      hjem = {
        linker = smfh;
        users.${user}.enable = true;
      };

      specialisation = {
        v1.configuration = {config, ...}: {
          hjem.users.${user} = {
            files.".config/restart-test.conf".text = "version=1";
            files.".config/reload-test.conf".text = "version=1";
            systemd.services = {
              restart-test =
                restartSvc "v1"
                config.hjem.users.${user}.files.".config/restart-test.conf".source;
              reload-test =
                reloadSvc "v1"
                config.hjem.users.${user}.files.".config/reload-test.conf".source;
            };
          };
        };

        v2.configuration = {config, ...}: {
          hjem.users.${user} = {
            files.".config/restart-test.conf".text = "version=2";
            files.".config/reload-test.conf".text = "version=2";
            systemd.services = {
              restart-test =
                restartSvc "v2"
                config.hjem.users.${user}.files.".config/restart-test.conf".source;
              reload-test =
                reloadSvc "v2"
                config.hjem.users.${user}.files.".config/reload-test.conf".source;
            };
          };
        };

        # v3 changes the service config (store paths) but keeps trigger content
        # the same as v2. Services should NOT restart/reload.
        v3.configuration = {config, ...}: {
          hjem.users.${user} = {
            files.".config/restart-test.conf".text = "version=2";
            files.".config/reload-test.conf".text = "version=2";
            systemd.services = {
              restart-test = {
                description = "Hjem restartTriggers test – v3";
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                  # Use a different binary to change the store path
                  ExecStart = "${pkgs.bash}/bin/true";
                };
                restartTriggers = [
                  config.hjem.users.${user}.files.".config/restart-test.conf".source
                ];
              };
              reload-test = {
                description = "Hjem reloadTriggers test – v3";
                serviceConfig = {
                  Type = "simple";
                  # Use a different sleep duration to change the store path
                  ExecStart = "${pkgs.coreutils}/bin/sleep 1000";
                  ExecReload = "${pkgs.bash}/bin/true";
                };
                reloadTriggers = [
                  config.hjem.users.${user}.files.".config/reload-test.conf".source
                ];
              };
            };
          };
        };
      };
    };

    testScript = {nodes, ...}: let
      baseSystem = nodes.node1.system.build.toplevel;
      specialisations = "${baseSystem}/specialisation";
    in ''
      node1.succeed("loginctl enable-linger ${user}")
      uid = node1.succeed("id -u ${user}").strip()
      xdg = f"/run/user/{uid}"
      node1.wait_for_unit(f"user@{uid}.service")

      def alice(cmd):
          return node1.succeed(f"su ${user} -c 'XDG_RUNTIME_DIR={xdg} {cmd}'")

      def alice_show(unit, prop):
          return alice(f"systemctl --user show {unit} --property={prop} --value").strip()

      with subtest("Deploy v1 and start both services"):
          node1.succeed("${specialisations}/v1/bin/switch-to-configuration test")
          alice("systemctl --user start restart-test.service")
          alice("systemctl --user start reload-test.service")
          alice("systemctl --user is-active restart-test.service")
          alice("systemctl --user is-active reload-test.service")

          ts_before  = alice_show("restart-test.service", "ActiveEnterTimestamp")
          pid_before = alice_show("reload-test.service",  "MainPID")

          assert ts_before  != "", "restart-test has no ActiveEnterTimestamp; service did not start"
          assert pid_before != "0", "reload-test MainPID is 0; service did not start"

      with subtest("restartTriggers: service is restarted on config change"):
          node1.succeed("${specialisations}/v2/bin/switch-to-configuration test")
          alice("systemctl --user is-active restart-test.service")

          ts_after = alice_show("restart-test.service", "ActiveEnterTimestamp")
          assert ts_before != ts_after, (
              f"restart-test was NOT restarted: timestamps unchanged ({ts_before})"
          )

      with subtest("reloadTriggers: service is reloaded (same PID) on config change"):
          # switch-to-configuration was already called above for v2; both triggers
          # fire in the same activation.
          alice("systemctl --user is-active reload-test.service")

          pid_after = alice_show("reload-test.service", "MainPID")
          assert pid_before == pid_after, (
              f"reload-test was RESTARTED instead of reloaded: PID changed {pid_before} -> {pid_after}"
          )
          assert pid_after != "0", "reload-test MainPID is 0 after reload; service died"

      with subtest("unchanged triggers: services stay the same when only store paths change"):
          # Record state after v2
          ts_v2 = alice_show("restart-test.service", "ActiveEnterTimestamp")
          pid_v2 = alice_show("reload-test.service", "MainPID")

          # Switch to v3, where unit files change but trigger content stays the same
          node1.succeed("${specialisations}/v3/bin/switch-to-configuration test")
          alice("systemctl --user is-active restart-test.service")
          alice("systemctl --user is-active reload-test.service")

          ts_v3 = alice_show("restart-test.service", "ActiveEnterTimestamp")
          pid_v3 = alice_show("reload-test.service", "MainPID")

          # These should be IDENTICAL since trigger content didn't change
          assert ts_v2 == ts_v3, (
              f"restart-test was restarted when it shouldn't be: timestamp changed {ts_v2} -> {ts_v3}"
          )
          assert pid_v2 == pid_v3, (
              f"reload-test changed when it shouldn't have: PID changed {pid_v2} -> {pid_v3}"
          )
    '';
  }
