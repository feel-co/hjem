let
  userHome = "/home/alice";
in
  (import ./lib) {
<<<<<<< HEAD
    name = "hjem-linker";
    nodes = {
      node1 = {
        self,
        pkgs,
        inputs,
        ...
      }: {
        imports = [self.nixosModules.hjem];

        users.groups.alice = {};
        users.users.alice = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

        hjem = {
          linker = inputs.smfh.packages.${pkgs.system}.default;
          users = {
            alice = {
              enable = true;
              files.".config/foo" = {
                text = "Hello world!";
              };
            };
          };
        };

        specialisation.fileChangedSystem.configuration = {
          hjem.users.alice.files.".config/foo".text = "Hello new world!";
        };
      };
    };

    testScript = {nodes, ...}: let
      fileChangedSystem = "${nodes.node1.system.build.toplevel}/specialisation/fileChangedSystem";
    in ''
      machine.succeed("loginctl enable-linger alice")

      with subtest("Activation service runs correctly"):
        machine.succeed("/run/current-system/bin/switch-to-configuration test")
        machine.succeed("systemctl show servicename --property=Result --value | grep -q '^success$'")

      with subtest("Manifest gets created"):
        machine.succeed("[ -f /var/lib/hjem/manifest-alice.json ]")

      with subtest("File gets linked"):
        machine.succeed("test -L ${userHome}/.config/foo")
        machine.succeed("grep \"Hello world!\" ${userHome}/.config/foo")

      with subtest("File gets overwritten when changed"):
        machine.succeed("${fileChangedSystem}/bin/switch-to-configuration test")
        machine.succeed("test -L ${userHome}/.config/foo")
        machine.succeed("grep \"Hello new world!\" ${userHome}/.config/foo")
    '';
  }
