{
  hjemModule,
  hjemTest,
  pkgs,
}: let
  user = "alice";
  userHome = "/home/${user}";
  manifestSource = pkgs.writeText "hjem-standalone-source" "Hello standalone!";
  configSource = pkgs.writeText "hjem-standalone-config-source" "Hello config!";
  alternateConfigSource = pkgs.writeText "hjem-standalone-alternate-config-source" "Hello alternate config!";
  flakeSource = pkgs.writeText "hjem-standalone-flake-source" "Hello flake!";
  packageOne = pkgs.writeShellScriptBin "hjem-package-one" ''
    echo package-one
  '';
  packageTwo = pkgs.writeShellScriptBin "hjem-package-two" ''
    echo package-two
  '';
  manifest = (pkgs.formats.json {}).generate "hjem-standalone-manifest.json" {
    version = 3;
    files = [
      {
        type = "symlink";
        source = "${manifestSource}";
        target = "${userHome}/.config/standalone-test";
      }
    ];
  };
  configFile = pkgs.writeText "hjem-standalone.nix" ''
    {
      manifest = {
        version = 3;
        files = [
          {
            type = "symlink";
            source = "${configSource}";
            target = "${userHome}/.config/standalone-test";
          }
        ];
      };

      packages = [ "${packageOne}" ];
    }
  '';
  alternateConfigFile = pkgs.writeText "hjem-standalone-alternate.nix" ''
    {
      manifest = {
        version = 3;
        files = [
          {
            type = "symlink";
            source = "${alternateConfigSource}";
            target = "${userHome}/.config/standalone-test";
          }
        ];
      };

      packages = [ "${packageTwo}" ];
    }
  '';
  flakeDir = pkgs.writeTextDir "flake.nix" ''
    {
      outputs = { self }: {
        hjemConfigurations.${user}.manifest = {
          version = 3;
          files = [
            {
              type = "symlink";
              source = "${flakeSource}";
              target = "${userHome}/.config/standalone-test";
            }
          ];
        };
      };
    }
  '';
in
  hjemTest {
    name = "hjem-standalone";
    nodes = {
      node1 = {
        imports = [hjemModule];
        nix.settings.experimental-features = ["nix-command" "flakes"];
        users = {
          groups.${user} = {};
          users.${user} = {
            isNormalUser = true;
            home = userHome;
            password = "";
          };
        };

        # Standalone should work independently of module-managed users.
        hjem.users = {};

        environment = {
          systemPackages = [
            (pkgs.callPackage ../../cli/package.nix {})
          ];

          etc = {
            "hjem-standalone.json".source = manifest;
            "hjem-standalone.nix".source = configFile;
            "hjem-standalone-alternate.nix".source = alternateConfigFile;
            "hjem-standalone-flake".source = flakeDir;
          };
        };
      };
    };

    testScript = ''
      machine.wait_for_unit("multi-user.target")

      with subtest("Standalone switch applies manifest for user"):
        machine.succeed("su - ${user} -c 'hjem standalone switch --manifest /etc/hjem-standalone.json'")
        machine.succeed("test -L ${userHome}/.config/standalone-test")
        machine.succeed("grep -q 'Hello standalone!' ${userHome}/.config/standalone-test")

      with subtest("Standalone state and generation are created"):
        machine.succeed("su - ${user} -c 'test -f ~/.local/state/hjem/standalone/current/manifest.json'")
        machine.succeed("su - ${user} -c 'hjem standalone generations | grep -q /home/${user}/.local/state/hjem/standalone/generations/'")

      with subtest("Standalone build records build artifact"):
        machine.succeed("su - ${user} -c 'hjem standalone build --manifest /etc/hjem-standalone.json >/tmp/hjem-build-id'")
        machine.succeed("su - ${user} -c 'test -s /tmp/hjem-build-id'")
        machine.succeed("su - ${user} -c 'hjem standalone build --config /etc/hjem-standalone.nix --state-dir ~/.local/state/hjem/build-only >/tmp/hjem-package-build-id'")
        machine.succeed("su - ${user} -c 'test -s /tmp/hjem-package-build-id'")
        machine.fail("su - ${user} -c 'test -e ~/.local/state/hjem/build-only/current-profile'")

      with subtest("Standalone switch evaluates hjem.nix configs"):
        machine.succeed("su - ${user} -c 'hjem standalone switch --config /etc/hjem-standalone.nix'")
        machine.succeed("grep -q 'Hello config!' ${userHome}/.config/standalone-test")
        machine.succeed("su - ${user} -c 'test \"$(~/.local/state/hjem/standalone/current-profile/bin/hjem-package-one)\" = package-one'")
        machine.fail("su - ${user} -c 'test -e ~/.nix-profile/bin/hjem-package-one'")
        machine.fail("su - ${user} -c 'test -e ~/.local/state/nix/profile/bin/hjem-package-one'")

      with subtest("Standalone package generations replace package contents"):
        machine.succeed("su - ${user} -c 'hjem standalone switch --config /etc/hjem-standalone-alternate.nix'")
        machine.succeed("grep -q 'Hello alternate config!' ${userHome}/.config/standalone-test")
        machine.succeed("su - ${user} -c 'test \"$(~/.local/state/hjem/standalone/current-profile/bin/hjem-package-two)\" = package-two'")
        machine.fail("su - ${user} -c 'test -e ~/.local/state/hjem/standalone/current-profile/bin/hjem-package-one'")
        machine.succeed("su - ${user} -c 'hjem standalone rollback'")
        machine.succeed("grep -q 'Hello config!' ${userHome}/.config/standalone-test")
        machine.succeed("su - ${user} -c 'test \"$(~/.local/state/hjem/standalone/current-profile/bin/hjem-package-one)\" = package-one'")
        machine.fail("su - ${user} -c 'test -e ~/.local/state/hjem/standalone/current-profile/bin/hjem-package-two'")

      with subtest("Standalone switch evaluates flakes"):
        machine.succeed("su - ${user} -c 'hjem standalone switch --flake /etc/hjem-standalone-flake'")
        machine.succeed("grep -q 'Hello flake!' ${userHome}/.config/standalone-test")
        machine.fail("su - ${user} -c 'test -e ~/.local/state/hjem/standalone/current-profile'")

      with subtest("Standalone rollback selects the previous generation"):
        machine.succeed("su - ${user} -c 'hjem standalone rollback'")
        machine.succeed("grep -q 'Hello alternate config!' ${userHome}/.config/standalone-test")
        machine.succeed("su - ${user} -c 'test \"$(~/.local/state/hjem/standalone/current-profile/bin/hjem-package-two)\" = package-two'")
        machine.succeed("su - ${user} -c 'hjem standalone switch --rollback'")
        machine.succeed("grep -q 'Hello config!' ${userHome}/.config/standalone-test")
        machine.succeed("su - ${user} -c 'test \"$(~/.local/state/hjem/standalone/current-profile/bin/hjem-package-one)\" = package-one'")
        machine.succeed("su - ${user} -c 'hjem standalone switch --rollback'")
        machine.succeed("grep -q 'Hello standalone!' ${userHome}/.config/standalone-test")
        machine.fail("su - ${user} -c 'test -e ~/.local/state/hjem/standalone/current-profile'")

      with subtest("Standalone generation cleanup protects the current generation"):
        machine.fail("su - ${user} -c 'hjem standalone remove-generations $(cat ~/.local/state/hjem/standalone/current-generation)'")
        machine.succeed("su - ${user} -c 'hjem standalone expire-generations --keep-last 1'")
        machine.succeed("su - ${user} -c 'test -f ~/.local/state/hjem/standalone/generations/$(cat ~/.local/state/hjem/standalone/current-generation)/manifest.json'")

      with subtest("Standalone init creates a switchable example"):
        machine.succeed("su - ${user} -c 'hjem standalone init --dir ~/.config/hjem-init-test --switch --no-flake'")
        machine.succeed("test -L ${userHome}/.config/example")
        machine.succeed("grep -q 'Example Hjem standalone configuration.' ${userHome}/.config/example")
    '';
  }
