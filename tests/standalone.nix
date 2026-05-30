{
  hjemModule,
  hjemTest,
  pkgs,
}: let
  user = "alice";
  userHome = "/home/${user}";
  sourceFile = pkgs.writeText "hjem-standalone-source" "Hello standalone!";
  manifest = pkgs.writeText "hjem-standalone-manifest.json" ''
    {
      "version": 3,
      "files": [
        {
          "type": "symlink",
          "source": "${sourceFile}",
          "target": "${userHome}/.config/standalone-test"
        }
      ]
    }
  '';
in
  hjemTest {
    name = "hjem-standalone";
    nodes = {
      node1 = {
        imports = [hjemModule];

        users.groups.${user} = {};
        users.users.${user} = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

        # Standalone should work independently of module-managed users.
        hjem.users = {};

        environment.systemPackages = [
          (pkgs.callPackage ../cli/package.nix {})
        ];

        environment.etc."hjem-standalone.json".source = manifest;
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
    '';
  }
