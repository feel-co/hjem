let
  userHome = "/home/alice";
in
  (import ./lib) {
    name = "hjem-basic";
    nodes = {
      node1 = {
        self,
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
            files.".config/foo" = {
              text = "Hello world!";
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

      # Test regular files, created by systemd-tmpfiles
      machine.succeed("[ -d ~alice/user_tmpfiles_created ]")
      machine.succeed("[ -d ~alice/only_alice ]")


      # Test user packages functioning
      machine.succeed("su alice --login --command hello")
    '';
  }
