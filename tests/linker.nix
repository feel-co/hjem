{inputs}:

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

        environment.systemPackages = [ pkgs.git ];

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
        };

        # needed to rebuild the system
        system.includeBuildDependencies = true;
        system.extraDependencies = [pkgs.grub2];
      };
    };

    testScript = {nodes, ...}: let
      baseSystem = nodes.node1.system.build.toplevel;
      specialisations = "${baseSystem}/specialisation";
      pkgs = nodes.node1.nixpkgs.pkgs;

      configFile =
        pkgs.writeText "configuration.nix" # nix
          ''
            { lib, pkgs, ... }: {
              imports = [
                ./hardware-configuration.nix
                <nixpkgs/nixos/modules/testing/test-instrumentation.nix>
                <nixpkgs/nixos/modules/profiles/base.nix>

                ${inputs.self}/modules/nixos
              ];

              _module.args.hjem-lib = import ${inputs.self}/lib.nix { inherit lib pkgs; };

              boot.loader.grub = {
                enable = true;
                device = "/dev/vda";
                forceInstall = true;
              };

              documentation.enable = false;

              environment.systemPackages = [ pkgs.git ];

              system.switch.enable = true;

              users.groups.alice = {};
              users.users.alice = {
                isNormalUser = true;
                home = ${userHome};
                password = "";
              };

              hjem = {
                linker = ${inputs.smfh.packages.${pkgs.system}.default};
                users = {
                  alice = {
                    enable = true;
                    files.".config/bar" = {
                      text = "Hello again!!";
                      clobber = true;
                    };
                  };
                };
              };
            }
          '';


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

        node1.succeed("nixos-generate-config")
        node1.copy_from_host(
          "${configFile}",
          "/etc/nixos/configuration.nix",
        )
        node1.succeed("nixos-rebuild boot -I nixpkgs=${pkgs.path} -I nixos-config=/etc/nixos/configuration.nix >&2")
        node1.reboot()

        node1.succeed("test -L ${userHome}/.config/bar")
    '';
  }
