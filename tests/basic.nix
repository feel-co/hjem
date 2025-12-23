{
  hjemModule,
  hjemTest,
  hello,
  lib,
  formats,
}: let
  userHome = "/home/alice";
in
  hjemTest {
    name = "hjem-basic";
    nodes = {
      node1 = {
        imports = [hjemModule];

        users.groups.alice = {};
        users.users.alice = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

        hjem.linker = null;
        hjem.users = {
          alice = {
            enable = true;
            packages = [hello];
            files = {
              ".config/foo" = {
                text = "Hello world!";
              };

              ".config/bar.json" = {
                generator = lib.generators.toJSON {};
                value = {bar = true;};
              };

              ".config/baz.toml" = {
                generator = (formats.toml {}).generate "baz.toml";
                value = {baz = true;};
              };
            };
          };
        };

        # Also test systemd-tmpfiles internally
        systemd.user.tmpfiles = {
          rules = [
            "d %h/user_tmpfiles_created"
          ];

          users.alice.rules = [
            "d %h/only_alice"
          ];
        };
      };
    };

    testScript = ''
      machine.succeed("loginctl enable-linger alice")
      machine.wait_until_succeeds("systemctl --user --machine=alice@ is-active systemd-tmpfiles-setup.service")

      # Test file created by Hjem
      machine.succeed("[ -L ~alice/.config/foo ]")
      machine.succeed("[ -L ~alice/.config/bar.json ]")
      machine.succeed("[ -L ~alice/.config/baz.toml ]")

      # Test regular files, created by systemd-tmpfiles
      machine.succeed("[ -d ~alice/user_tmpfiles_created ]")
      machine.succeed("[ -d ~alice/only_alice ]")


      # Test user packages functioning
      machine.succeed("su alice --login --command hello")
    '';
  }
