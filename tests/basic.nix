let
  userHome = "/home/alice";
in
  (import ./lib) {
    name = "hjem-basic";
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
            packages = [pkgs.hello];
            files = {
              ".config/foo" = {
                text = "Hello world!";
              };

              ".config/bar.json" = {
                generator = lib.generators.toJSON {};
                value = {bar = true;};
              };

              ".config/baz.toml" = {
                generator = (pkgs.formats.toml {}).generate "baz.toml";
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
