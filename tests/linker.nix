let
  userHome = "/home/alice";
in
  (import ./lib) {
    name = "hjem-linker";
    nodes = {
      node1 = {
        self,
        pkgs,
        inputs,
        ...
      }: {
        imports = [self.nixosModules.hjem];

        # ensure nixless deployments work
        nix.enable = false;

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
            };
          };
        };

        specialisation = {
          fileGetsLinked.configuration = {
            hjem.users.alice.files.".config/foo".text = "Hello world!";
          };

          fileGetsOverwritten.configuration = {
            hjem.users.alice.files.".config/foo" = {
              text = "Hello new world!";
              clobber = true;
            };
          };
        };
      };
    };

    testScript = {nodes, ...}: let
      baseSystem = nodes.node1.system.build.toplevel;
      specialisations = "${baseSystem}/specialisation";
    in ''
      node1.succeed("loginctl enable-linger alice")

      with subtest("Activation service runs correctly"):
        node1.succeed("${baseSystem}/bin/switch-to-configuration test")
        node1.succeed("systemctl show servicename --property=Result --value | grep -q '^success$'")

      with subtest("Manifest gets created"):
        node1.succeed("${baseSystem}/bin/switch-to-configuration test")
        node1.succeed("[ -f /var/lib/hjem/manifest-alice.json ]")

      with subtest("File gets linked"):
        node1.succeed("${specialisations}/fileGetsLinked/bin/switch-to-configuration test")
        node1.succeed("test -L ${userHome}/.config/foo")
        node1.succeed("grep \"Hello world!\" ${userHome}/.config/foo")

      with subtest("File gets overwritten when changed"):
        node1.succeed("${specialisations}/fileGetsLinked/bin/switch-to-configuration test")
        node1.succeed("${specialisations}/fileGetsOverwritten/bin/switch-to-configuration test")
        node1.succeed("test -L ${userHome}/.config/foo")
        node1.succeed("grep \"Hello new world!\" ${userHome}/.config/foo")
    '';
  }
