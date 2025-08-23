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

        system.switch.enable = true;

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

          variousFileTypes.configuration = {
            hjem.users.alice.files = {
              foo = {
                type = "copy";
                text = ''
                  test content
                '';
              };
              bar = {
                type = "delete";
              };
              baz = {
                type = "directory";
              };
              # TODO: uncomment after https://github.com/feel-co/smfh/issues/20 is fixed
              /*
                boop = {
                type = "modify";
                permissions = "703";
              };
              */
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

      with subtest("Various file type tests"):
        node1.succeed("touch ${userHome}/{bar,boop}")
        node1.succeed("test -f ${userHome}/bar")
        node1.succeed("test -f ${userHome}/boop")
        node1.succeed("chmod 644 ${userHome}/boop")
        node1.succeed("test $(stat -c '%a' ${userHome}/boop) = \"644\"")
        node1.succeed("${specialisations}/variousFileTypes/bin/switch-to-configuration test")
        node1.succeed("test -f ${userHome}/foo")
        node1.succeed("grep \"test content\" ${userHome}/foo")
        node1.succeed("! test -f ${userHome}/bar")
        node1.succeed("test -d ${userHome}/baz")
        node1.succeed("test -f ${userHome}/boop")
        node1.succeed("stat -c '%a' ${userHome}/boop >&2")
        # TODO: uncomment after https://github.com/feel-co/smfh/issues/20 is fixed
        #node1.succeed("test $(stat -c '%a' ${userHome}/boop) = \"703\"")
    '';
  }
