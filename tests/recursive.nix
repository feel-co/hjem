{
  hjemModule,
  hjemTest,
  smfh,
}: let
  user = "alice";
  userHome = "/home/${user}";
in
  hjemTest {
    name = "recursive";
    nodes = {
      node1 = {
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
          users = {
            ${user} = {
              enable = true;
            };
          };
        };

        specialisation = {
          creation.configuration = {
            hjem.users.${user}.systemd.services."test-service" = {
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = "yes";
              };
              wantedBy = ["default.target"];
              script = ''
                echo Test service started
              '';
            };
          };

          deletion.configuration = {};
        };
      };
    };

    testScript = {nodes, ...}: let
      baseSystem = nodes.node1.system.build.toplevel;
      specialisations = "${baseSystem}/specialisation";
    in ''
      node1.succeed("loginctl enable-linger ${user}")

      with subtest("Service is created"):
        node1.succeed("${specialisations}/creation/bin/switch-to-configuration test")
        node1.succeed("test -L ${userHome}/.config/systemd/user/test-service.service")
        node1.succeed("test -L ${userHome}/.config/systemd/user/default.target.wants/test-service.service")

      with subtest("Service is linked recursively"):
        node1.succeed("! realpath ${userHome}/.config/systemd/user | grep '/nix/store'")
        node1.succeed("! realpath ${userHome}/.config/systemd/user/default.target.wants | grep '/nix/store'")

      with subtest("Service is deleted"):
        node1.succeed("${specialisations}/deletion/bin/switch-to-configuration test")
        node1.succeed("! test -L ${userHome}/.config/systemd/user/test-service.service")
        node1.succeed("! test -L ${userHome}/.config/systemd/user/default.target.wants/test-service.service")
    '';
  }
