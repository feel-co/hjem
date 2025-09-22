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
        imports = [
          (inputs.nixpkgs + /nixos/modules/testing/test-instrumentation.nix)
          (inputs.nixpkgs + /nixos/modules/profiles/base.nix)
          self.nixosModules.hjem
        ];

        boot.loader.grub = {
          enable = true;
          device = "/dev/vda";
          forceInstall = true;
        };

        environment.systemPackages = [pkgs.git pkgs.grub2];

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
          AAAAA.configuration = {
            # https://github.com/NixOS/nixpkgs/issues/82851
            # https://github.com/NixOS/nixpkgs/blob/master/nixos/tests/installer.nix#L354
            boot.loader.grub.configurationName = "AAAAA";
          };

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
      node1.start(allow_reboot=True)
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

      with subtest("nixos-rebuild boot"):
        node1.fail("test -L ${userHome}/.config/bar")
        node1.succeed("cat /run/booted-system/configuration-name >&2")

        node1.succeed("${specialisations}/AAAAA/bin/switch-to-configuration boot")
        node1.succeed("grub-reboot 1")

        node1.succeed("cat /run/booted-system/configuration-name >&2")
        #assert "AAAAA" in node1.succeed("cat /run/booted-system/configuration-name")

        node1.succeed("test -L ${userHome}/.config/bar")
    '';
  }
