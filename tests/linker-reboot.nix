let
  userHome = "/home/alice";
in
  (import ./lib) {
    name = "hjem-linker-reboot";
    nodes = {
      node1 = {
        self,
        pkgs,
        inputs,
        ...
      }: {
        virtualisation.useBootLoader = true;

        imports = [
          self.nixosModules.hjem
        ];

        boot.loader.grub = {
          enable = true;
          device = "/dev/vda";
          forceInstall = true;
        };

        environment.systemPackages = [pkgs.grub2];

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
          hjem-special.configuration = {
            # https://github.com/NixOS/nixpkgs/issues/82851
            # https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/installer.nix#L354
            boot.loader.grub.configurationName = "hjem-special";
            hjem.users.alice.files.".config/bar" = {
              text = "Hello even newer world!";
              clobber = true;
            };
          };
        };
      };
    };

    testScript = _: ''
      node1.start(allow_reboot=True)
      node1.succeed("loginctl enable-linger alice")

      with subtest("nixos-rebuild boot"):
        node1.fail("test -L ${userHome}/.config/bar")
        #node1.succeed("cat /run/booted-system/configuration-name >&2")

        node1.succeed("grub-reboot 1")

        #node1.succeed("cat /run/booted-system/configuration-name >&2")
        #assert "AAAAA" in node1.succeed("cat /run/booted-system/configuration-name")

        node1.wait_for_unit("multi-user.target")
        node1.wait_for_unit("local-fs.target")
        node1.succeed("test -L ${userHome}/.config/bar")
    '';
  }
