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
      };
    };

    testScript = ''
      machine.succeed("loginctl enable-linger alice")

      # Test that the activation service runs correctly on rebuild
      machine.succeed("/run/current-system/bin/switch-to-configuration test")

      # Test manifest creation
      machine.succeed("[ -f /var/lib/hjem/manifest-alice.json ]")
    '';
  }
