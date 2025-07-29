let
  userHome = "/home/alice";
in
  (import ./lib) {
    name = "hjem-xdg";
    nodes = {
      node1 = {
        self,
        lib,
        pkgs,
        ...
      }: {
        imports = [self.nixosModules.hjem];

        users.groups.alice = {};
        users.users.alice = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

        hjem.users = {
          alice = {
            enable = true;
            files = {
              "foo" = {
                text = "Hello world!";
              };
            };
            xdg = {
              cache = {
                directory = userHome + "/customCacheDirectory";
                files = {
                  "foo" = {
                    text = "Hello world!";
                  };
                };
              };
              config = {
                directory = userHome + "/customConfigDirectory";
                files = {
                  "bar.json" = {
                    generator = lib.generators.toJSON {};
                    value = {bar = "Hello second world!";};
                  };
                };
              };
              data = {
                directory = userHome + "/customDataDirectory";
                files = {
                  "baz.toml" = {
                    generator = (pkgs.formats.toml {}).generate "baz.toml";
                    value = {baz = "Hello third world!";};
                  };
                };
              };
              state = {
                directory = userHome + "/customStateDirectory";
                files = {
                  "foo" = {
                    source = pkgs.writeText "file-bar" "Hello fourth world!";
                  };
                };
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

      # Test XDG files created by Hjem
      with subtest("XDG files created by Hjem"):
        machine.succeed("[ -L ~alice/customCacheDirectory/foo ]")
        machine.succeed("grep \"Hello world!\" ~alice/customCacheDirectory/foo")
        machine.succeed("[ -L ~alice/customConfigDirectory/bar.json ]")
        machine.succeed("grep \"Hello second world!\" ~alice/customConfigDirectory/bar.json")
        machine.succeed("[ -L ~alice/customDataDirectory/baz.toml ]")
        machine.succeed("grep \"Hello third world!\" ~alice/customDataDirectory/baz.toml")
        # Same name as config test file to verify proper merging
        machine.succeed("[ -L ~alice/customStateDirectory/foo ]")
        machine.succeed("grep \"Hello fourth world!\" ~alice/customStateDirectory/foo")

      with subtest("Basic test file for Hjem"):
        machine.succeed("[ -L ~alice/foo ]") # Same name as cache test file to verify proper merging
        machine.succeed("grep \"Hello world!\" ~alice/foo")
        # Test regular files, created by systemd-tmpfiles
        machine.succeed("[ -d ~alice/user_tmpfiles_created ]")
        machine.succeed("[ -d ~alice/only_alice ]")
    '';
  }
