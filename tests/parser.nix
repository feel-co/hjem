{
  lib,
  writers,
  hjemModule,
  hjemTest,
}: let
  userHome = "/home/alice";

  baseJson = writers.writeJSON "base.json" {
    connection.host = "localhost";
    connection.port = 5432;
    logging.level = "info";
  };
in
  hjemTest {
    name = "hjem-parser";
    nodes = {
      node1 = {
        imports = [hjemModule];

        users = {
          groups.alice = {};
          users.alice = {
            isNormalUser = true;
            home = userHome;
            password = "";
          };
        };

        hjem = {
          linker = null;
          users.alice = {
            enable = true;
            files.".config/app.json" = {
              sources = [baseJson];
              parser = lib.importJSON;
              generator = lib.generators.toJSON {};
              value = {
                connection.port = 9999;
                logging.level = "debug";
                extra.key = "added";
              };
            };
          };
        };
      };
    };

    testScript = ''
      machine.succeed("loginctl enable-linger alice")
      machine.wait_until_succeeds("systemctl --user --machine=alice@ is-active systemd-tmpfiles-setup.service")

      machine.succeed("[ -L ~alice/.config/app.json ]")

      content = machine.succeed("cat ~alice/.config/app.json")
      import json
      data = json.loads(content)

      # value overrides win
      assert data["connection"]["port"] == 9999, f"expected port 9999, got {data['connection']['port']}"
      assert data["logging"]["level"] == "debug", f"expected level debug, got {data['logging']['level']}"
      # base key inherited from sources
      assert data["connection"]["host"] == "localhost", f"expected host localhost, got {data['connection']['host']}"
      # new key from value
      assert data["extra"]["key"] == "added", f"expected extra.key=added, got {data['extra']['key']}"
    '';
  }
