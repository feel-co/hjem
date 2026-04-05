{
  hjemModule,
  hjemTest,
  smfh,
  pkgs,
  lib,
}: let
  inherit (lib.meta) getExe';
  user = "alice";
  userHome = "/home/${user}";

  # A oneshot service that stays "active" via RemainAfterExit. Restarting it
  # produces a new ActiveEnterTimestamp, making restarts unambiguously detectable.
  restartSvc = name: triggerSource: {
    description = "Hjem restartTriggers test – ${name}";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${getExe' pkgs.coreutils "true"}";
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
      ExecStart = "${getExe' pkgs.coreutils "sleep"} infinity";
      ExecReload = "${getExe' pkgs.coreutils "true"}";
    };
    reloadTriggers = [triggerSource];
  };

  # Timer with restartTriggers. ActiveEnterTimestamp changes on restart, which
  # makes restarts unambiguously detectable.
  restartTimer = name: triggerSource: {
    description = "Hjem restartTriggers test timer – ${name}";
    timerConfig.OnCalendar = "weekly";
    restartTriggers = [triggerSource];
  };

  # Companion service required by restartTimer so that systemd accepts the timer.
  # The timer refuses to start if its corresponding .service unit is not loaded.
  timerCompanion = {
    description = "Hjem restartTriggers test timer companion";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${getExe' pkgs.coreutils "true"}";
    };
  };

  # A socket with restartTriggers. ActiveEnterTimestamp changes on restart.
  restartSocket = name: triggerSource: {
    description = "Hjem restartTriggers test socket – ${name}";
    socketConfig.ListenStream = "%t/hjem-restart-test.sock";
    restartTriggers = [triggerSource];
  };

  # Companion service required by restartSocket so that systemd accepts the socket.
  # The socket refuses to start if its corresponding .service unit is not loaded.
  socketCompanion = {
    description = "Hjem restartTriggers test socket companion";
    serviceConfig = {
      Type = "simple";
      ExecStart = "${getExe' pkgs.coreutils "sleep"} infinity";
    };
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
            files = {
              ".config/restart-test.conf".text = "version=1";
              ".config/reload-test.conf".text = "version=1";
              ".config/timer-test.conf".text = "version=1";
              ".config/socket-test.conf".text = "version=1";
            };

            systemd = {
              services = {
                restart-test =
                  restartSvc "v1"
                  config.hjem.users.${user}.files.".config/restart-test.conf".source;
                reload-test =
                  reloadSvc "v1"
                  config.hjem.users.${user}.files.".config/reload-test.conf".source;
                restart-test-timer = timerCompanion;
                restart-test-socket = socketCompanion;
              };

              timers.restart-test-timer =
                restartTimer "v1"
                config.hjem.users.${user}.files.".config/timer-test.conf".source;

              sockets.restart-test-socket =
                restartSocket "v1"
                config.hjem.users.${user}.files.".config/socket-test.conf".source;
            };
          };
        };

        v2.configuration = {config, ...}: {
          hjem.users.${user} = {
            files = {
              ".config/restart-test.conf".text = "version=2";
              ".config/reload-test.conf".text = "version=2";
              ".config/timer-test.conf".text = "version=2";
              ".config/socket-test.conf".text = "version=2";
            };

            systemd = {
              services = {
                restart-test =
                  restartSvc "v2"
                  config.hjem.users.${user}.files.".config/restart-test.conf".source;
                reload-test =
                  reloadSvc "v2"
                  config.hjem.users.${user}.files.".config/reload-test.conf".source;
                restart-test-timer = timerCompanion;
                restart-test-socket = socketCompanion;
              };

              timers.restart-test-timer =
                restartTimer "v2"
                config.hjem.users.${user}.files.".config/timer-test.conf".source;

              sockets.restart-test-socket =
                restartSocket "v2"
                config.hjem.users.${user}.files.".config/socket-test.conf".source;
            };
          };
        };

        # v3 changes unit file contents (store paths) but keeps trigger content
        # the same as v2. No unit should restart/reload.
        v3.configuration = {config, ...}: {
          hjem.users.${user} = {
            files = {
              ".config/restart-test.conf".text = "version=2";
              ".config/reload-test.conf".text = "version=2";
              ".config/timer-test.conf".text = "version=2";
              ".config/socket-test.conf".text = "version=2";
            };

            systemd = let
              cfg = config.hjem.users.${user};
            in {
              services = {
                restart-test = {
                  description = "Hjem restartTriggers test – v3";
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true; # FIXME: does ihe test work without this?

                    # Use a different binary to change the store path
                    ExecStart = "${getExe' pkgs.busybox "true"}";
                  };
                  restartTriggers = [cfg.files.".config/restart-test.conf".source];
                };

                reload-test = {
                  description = "Hjem reloadTriggers test – v3";
                  serviceConfig = {
                    Type = "simple";
                    ExecStart = "${pkgs.coreutils}/bin/sleep 1000";
                    ExecReload = "${getExe' pkgs.busybox "true"}";
                  };

                  reloadTriggers = [cfg.files.".config/reload-test.conf".source];
                };

                restart-test-timer = timerCompanion;
                restart-test-socket = socketCompanion;
              };

              timers.restart-test-timer = {
                # Change OnCalendar to produce a different unit file, trigger content is
                # unchanged.
                description = "Hjem restartTriggers test timer – v3";
                timerConfig.OnCalendar = "monthly";
                restartTriggers = [cfg.files.".config/timer-test.conf".source];
              };

              sockets.restart-test-socket = {
                description = "Hjem restartTriggers test socket – v3";
                socketConfig.ListenStream = "%t/hjem-restart-test.sock";
                restartTriggers = [cfg.files.".config/socket-test.conf".source];
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

      with subtest("Deploy v1 and start all units"):
          # FIXME: yeesh, this got ugly fast
          node1.succeed("${specialisations}/v1/bin/switch-to-configuration test")
          alice("systemctl --user start restart-test.service")
          alice("systemctl --user start reload-test.service")
          alice("systemctl --user start restart-test-timer.timer")
          alice("systemctl --user start restart-test-socket.socket")
          alice("systemctl --user is-active restart-test.service")
          alice("systemctl --user is-active reload-test.service")
          alice("systemctl --user is-active restart-test-timer.timer")
          alice("systemctl --user is-active restart-test-socket.socket")

          ts_before        = alice_show("restart-test.service",        "ActiveEnterTimestamp")
          pid_before       = alice_show("reload-test.service",         "MainPID")
          ts_timer_before  = alice_show("restart-test-timer.timer",    "ActiveEnterTimestamp")
          ts_socket_before = alice_show("restart-test-socket.socket",  "ActiveEnterTimestamp")

          assert ts_before        != "",  "restart-test has no ActiveEnterTimestamp; service did not start"
          assert pid_before       != "0", "reload-test MainPID is 0; service did not start"
          assert ts_timer_before  != "",  "restart-test-timer has no ActiveEnterTimestamp; timer did not start"
          assert ts_socket_before != "",  "restart-test-socket has no ActiveEnterTimestamp; socket did not start"

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

      with subtest("restartTriggers: timer is restarted on config change"):
          alice("systemctl --user is-active restart-test-timer.timer")

          ts_timer_after = alice_show("restart-test-timer.timer", "ActiveEnterTimestamp")
          assert ts_timer_before != ts_timer_after, (
              f"restart-test-timer was NOT restarted: timestamps unchanged ({ts_timer_before})"
          )

      with subtest("restartTriggers: socket is restarted on config change"):
          alice("systemctl --user is-active restart-test-socket.socket")

          ts_socket_after = alice_show("restart-test-socket.socket", "ActiveEnterTimestamp")
          assert ts_socket_before != ts_socket_after, (
              f"restart-test-socket was NOT restarted: timestamps unchanged ({ts_socket_before})"
          )

      with subtest("unchanged triggers: no unit restarts when only store paths change"):
          # Record state after v2
          ts_v2        = alice_show("restart-test.service",       "ActiveEnterTimestamp")
          pid_v2       = alice_show("reload-test.service",        "MainPID")
          ts_timer_v2  = alice_show("restart-test-timer.timer",   "ActiveEnterTimestamp")
          ts_socket_v2 = alice_show("restart-test-socket.socket", "ActiveEnterTimestamp")

          # Switch to v3, where unit files change but trigger content stays the same
          node1.succeed("${specialisations}/v3/bin/switch-to-configuration test")
          alice("systemctl --user is-active restart-test.service")
          alice("systemctl --user is-active reload-test.service")
          alice("systemctl --user is-active restart-test-timer.timer")
          alice("systemctl --user is-active restart-test-socket.socket")

          ts_v3        = alice_show("restart-test.service",       "ActiveEnterTimestamp")
          pid_v3       = alice_show("reload-test.service",        "MainPID")
          ts_timer_v3  = alice_show("restart-test-timer.timer",   "ActiveEnterTimestamp")
          ts_socket_v3 = alice_show("restart-test-socket.socket", "ActiveEnterTimestamp")

          # These should be IDENTICAL since trigger content didn't change
          assert ts_v2 == ts_v3, (
              f"restart-test was restarted when it shouldn't be: timestamp changed {ts_v2} -> {ts_v3}"
          )
          assert pid_v2 == pid_v3, (
              f"reload-test changed when it shouldn't have: PID changed {pid_v2} -> {pid_v3}"
          )
          assert ts_timer_v2 == ts_timer_v3, (
              f"restart-test-timer was restarted when it shouldn't be: timestamp changed {ts_timer_v2} -> {ts_timer_v3}"
          )
          assert ts_socket_v2 == ts_socket_v3, (
              f"restart-test-socket was restarted when it shouldn't be: timestamp changed {ts_socket_v2} -> {ts_socket_v3}"
          )
    '';
  }
