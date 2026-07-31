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
    name = "hjem-basic";
    nodes = {
      node1 = {
        imports = [hjemModule];

        users.groups.alice = {};
        users.users.alice = {
          isNormalUser = true;
          home = userHome;
          password = "";
        };

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
                value = {bar = true;};
              };

              ".config/baz.toml" = {
                generator = (formats.toml {}).generate "baz.toml";
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

        specialisation.unrelated.configuration.environment.etc."hjem-gc-test".text = "unrelated generation change";
      };
    };

    testScript = {nodes, ...}: let
      baseSystem = nodes.node1.system.build.toplevel;
      unrelatedSystem = "${baseSystem}/specialisation/unrelated";
    in ''
      machine.succeed("loginctl enable-linger alice")
      machine.wait_until_succeeds("systemctl --user --machine=alice@ is-active systemd-tmpfiles-setup.service")

      # Test file created by Hjem
      machine.succeed("[ -L ~alice/.config/foo ]")
      machine.succeed("[ -L ~alice/.config/bar.json ]")
      machine.succeed("[ -L ~alice/.config/baz.toml ]")

      with subtest("Later generations retain unchanged linked sources across GC"):
          machine.succeed("${unrelatedSystem}/bin/switch-to-configuration test")
          machine.succeed("nix-store --query --requisites ${unrelatedSystem} | grep -Fx \"$(readlink ~alice/.config/foo)\"")
          machine.succeed("nix-collect-garbage")
          machine.succeed("test -e ~alice/.config/foo")
          machine.succeed("grep -qx 'Hello world!' ~alice/.config/foo")

      # Test regular files, created by systemd-tmpfiles
      machine.succeed("[ -d ~alice/user_tmpfiles_created ]")
      machine.succeed("[ -d ~alice/only_alice ]")


      # Test user packages functioning
      machine.succeed("su alice --login --command hello")
    '';
  }
