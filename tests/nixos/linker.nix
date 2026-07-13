{
  hjemModule,
  hjemTest,
  pkgs,
}: let
  user = "alice";
  userHome = "/home/${user}";
  uid = 1000;
in
  hjemTest {
    name = "hjem-linker";
    nodes = let
      node = {
        linker,
        mountHome ? false,
      }: {
        imports = [hjemModule];

        # ensure nixless deployments work
        nix.enable = false;

        users.groups.${user} = {};
        users.users.${user} = {
          isNormalUser = true;
          home = userHome;
          password = "";
          inherit uid;
        };

        systemd.mounts = pkgs.lib.optionals mountHome [
          {
            what = "tmpfs";
            where = "/home";
            type = "tmpfs";
            options = "mode=0755";
          }
        ];

        systemd.tmpfiles.rules = [
          "d /home 0755 root root -"
        ];

        hjem = {
          inherit linker;
          users = {
            ${user} = {
              enable = true;
              files.".config/requires-mounts-for".text = "linked after home.mount";
            };
          };
        };

        specialisation = {
          fileGetsLinked.configuration = {
            hjem.users.${user}.files.".config/foo".text = "Hello world!";
          };

          fileGetsOverwritten.configuration = {
            hjem.users.${user}.files.".config/foo" = {
              text = "Hello new world!";
              clobber = true;
            };
          };

          variousFileTypes.configuration = {
            hjem.users.${user}.files = {
              foo = {
                type = "copy";
                text = ''
                  test content
                '';
                inherit uid;
              };
              bar = {
                type = "delete";
              };
              baz = {
                type = "directory";
              };
              boop = {
                type = "modify";
                permissions = "703";
              };
            };
          };
        };
      };
    in {
      nullLinker = node {linker = null;};
      smfhLinker = node {
        linker = pkgs.smfh;
        mountHome = true;
      };
    };

    testScript = {nodes, ...}: let
      nullBaseSystem = nodes.nullLinker.system.build.toplevel;
      smfhBaseSystem = nodes.smfhLinker.system.build.toplevel;
      smfhSpecialisations = "${smfhBaseSystem}/specialisation";
    in ''
      with subtest("linker = null"):
          nullLinker.succeed("loginctl enable-linger ${user}")
          nullLinker.succeed("${nullBaseSystem}/bin/switch-to-configuration test")
          nullLinker.wait_until_succeeds("systemctl --user --machine=${user}@ is-active systemd-tmpfiles-setup.service")
          nullLinker.succeed("grep 'linked after home.mount' ${userHome}/.config/requires-mounts-for")

      with subtest("linker = pkgs.smfh"):
          smfhLinker.succeed("loginctl enable-linger ${user}")
          smfhLinker.succeed("${smfhBaseSystem}/bin/switch-to-configuration test")
          smfhLinker.succeed("mountpoint -q /home")
          smfhLinker.succeed("grep ' /home ' /proc/self/mountinfo | grep -qw tmpfs")
          smfhLinker.succeed("grep 'linked after home.mount' ${userHome}/.config/requires-mounts-for")
          smfhLinker.succeed("systemctl show servicename --property=Result --value | grep -q '^success$'")
          smfhLinker.succeed("[ -f /var/lib/hjem/manifest-${user}.json ]")

          smfhLinker.succeed("${smfhSpecialisations}/fileGetsLinked/bin/switch-to-configuration test")
          smfhLinker.succeed("test -L ${userHome}/.config/foo")
          smfhLinker.succeed("grep 'Hello world!' ${userHome}/.config/foo")

      with subtest("Same-generation switch repairs broken links"):
          smfhLinker.succeed("rm ${userHome}/.config/foo")
          smfhLinker.succeed("ln -s /nix/store/00000000000000000000000000000000-missing ${userHome}/.config/foo")
          smfhLinker.succeed("${smfhSpecialisations}/fileGetsLinked/bin/switch-to-configuration test")
          smfhLinker.succeed("test -L ${userHome}/.config/foo")
          smfhLinker.succeed("grep 'Hello world!' ${userHome}/.config/foo")

      with subtest("File gets overwritten when changed"):
          smfhLinker.succeed("${smfhSpecialisations}/fileGetsOverwritten/bin/switch-to-configuration test")
          smfhLinker.succeed("test -L ${userHome}/.config/foo")
          smfhLinker.succeed("grep 'Hello new world!' ${userHome}/.config/foo")

      with subtest("Various file type tests"):
          smfhLinker.succeed("touch ${userHome}/{bar,boop}")
          smfhLinker.succeed("chmod 644 ${userHome}/boop")
          smfhLinker.succeed("chown ${user} ${userHome}/{bar,boop}")
          smfhLinker.succeed("${smfhSpecialisations}/variousFileTypes/bin/switch-to-configuration test")
          smfhLinker.succeed("test -f ${userHome}/foo")
          smfhLinker.succeed("grep 'test content' ${userHome}/foo")
          smfhLinker.succeed("! test -f ${userHome}/bar")
          smfhLinker.succeed("test -d ${userHome}/baz")
          smfhLinker.succeed("test -f ${userHome}/boop")
          smfhLinker.succeed("test $(stat -c '%a' ${userHome}/boop) = '703'")
    '';
  }
