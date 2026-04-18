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
    name = "hjem-basic-finix";
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
                value = {
                  bar = true;
                };
              };

              ".config/baz.toml" = {
                generator = (formats.toml {}).generate "baz.toml";
                value = {
                  baz = true;
                };
              };
            };
          };
        };
      };
    };

    testScript = ''
      machine.wait_until_succeeds("initctl cond get task/hjem-activate-alice/success")

      # Test files created by Hjem
      machine.succeed("[ -L ~alice/.config/foo ]")
      machine.succeed("[ -L ~alice/.config/bar.json ]")
      machine.succeed("[ -L ~alice/.config/baz.toml ]")

      # Test user packages functioning
      machine.succeed("su alice --login --command hello")
    '';
  }
