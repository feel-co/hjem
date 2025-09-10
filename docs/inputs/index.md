# Preface {#preface}

Welcome to Hjem documentation! This online manual aims to describe how to get
started with, use and at times extend Hjem.

::: {.tip}

We also provide a short option reference. Hjem does not vendor any modules
similar to Home-Manager and Nix-Darwin, but there exists a companion project
that aims to bridge the gap between Hjem and per-program modules. If you are
interested in such a setup, we encourage you to take a look at
[Hjem Rum](https://github.com/snugnug/hjem-rum)

:::

## Installing Hjem

[Nix Flakes]: https://nix.dev/concepts/flakes.html

The primary method of installing Hjem is through [Nix Flakes]. To get started,
you must first Hjem as a flake input in your `flake.nix`.

```nix
# flake.nix
{
  inputs = {
    # ↓  Add here in the 'inputs' section. The name is arbitrary.
    hjem.url = "github:feel-co/hjem";
  };
}
```

Hjem is distributed as a **NixOS module** for the time being, and you must
import it as such. For the sake of brevity, this guide will demonstrate how to
import it from inside the `nixosSystem` call.

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    hjem.url = "github:feel-co/hjem";
  };

  outputs = inputs: {
    nixosConfigurations."<your_hostname>" = inputs.nixpkgs.lib.nixosSystem {
      # ...
      modules = [
        inputs.hjem.nixosModules.default
      ];
      # ...
    };
  };
}
```

## Usage

Hjem achieves both simplicity and robustness by shaving off the unnecessary
complexity and exposing a simple interface used to link files:
{option}`hjem.users.<user>.files`. This is the core of Hjem―file linking.

### `hjem.users`

{option}`hjem.users` is the main entry point used to declare individual users
for Hjem. It contains several sub-options that may be used to control Hjem's
behaviour per user. You may refer to the option documentation for more details
on each bell and whistle. Important options to be aware of are as follows:

- {option}`hjem.users.<name>.enable` allows toggling file linking for individual
  users. Set to `true` by default, but can be used to toggle off file linking
  for individual users on a multi-tenant system.
- {option}`hjem.users.<name>.user` is the name of the user that will be defined.
  This **must** be set in your configuration. To avoid making assumptions, Hjem
  does not infer this from `<name>`.
- {option}`hjem.users.<name>.directory` is your home directory. Files in
  `<name>.files` will always be relative to this directory.
- {option}`hjem.users.<name>.clobberFiles` decides whether Hjem should override
  if a file already exists at a target location. This default to `false`, but
  this can be enabled for all users by setting `hjem.clobberByDefault` to
  `true`.

#### Example

Now, let's go over an example. In this case we have a user named "alice" whose
home directory we want to manage. Alice's home directory is `/home/alice`, so we
should first tell Hjem to look there. Since defined users are enabled by
default, no need to set `enable` explicitly.

Once the user's home is defined, we'll want to give Hjem some files to manage.
Let's go with some example files to demonstrate Hjem's linking capabilities.

1. You can use `files."<path/to/file>".text` to create a file at a given
   location with the `text` as its contents. For example we can set
   `files.".config/foo".text = "Hello World!` to create
   `/home/alice/.config/foo` and it's contents will read "Hello World".
2. Similar to NixOS' `environment.etc`, Hjem supports a `.source` attribute with
   which you can link files from your store. For example we can use Nixpkgs'
   writers to create derivations that will be used as the source. A good example
   would be using `pkgs.writeTextFile`.

   ```nix
   ".config/bar".source = pkgs.writeTextFile "file-foo" "file contents";
   ```
   Note : `.source` also supports directly provided path.
   ```nix
   ".config/bar".source = ./foo;
   ```
   

4. The most recent addition to Hjem's file linking interface is the `generator`
   attribute. It allows feeding a generator by which your values will be
   transformed. Consider the following example:

   ```nix
   ".config/baz" = {
    generator = lib.generators.toJSON {};
      value = {
        some = "contents";
      };
    };
   ```

   The result in `/home/alice/.config/baz` will be the JSON representation of
   the attribute set provided in `value`. This is helpful when you are writing
   files in specific formats expected by your programs. You could, say, use
   `(pkgs.formats.toml { }).generate` to write a TOML configuration file in
   `/home/alice/.config/jj/config.toml`

   ```nix
   ".config/baz" = {
      generator = (pkgs.formats.toTOML {}).generate;
      value = {
        "ui.graph".style = "curved";
        "ui.movement".edit = true;
      };
    };
   ```

   This, of course, works with other formats and generators as well.

#### Bringing it together

Here is a more complete example to give you an idea of the bigger picture. By
using (or abusing, up to you) the `files` submodule you can write files anywhere
in your home directory.

```nix
{
  pkgs,
  lib,
  ...
}: {
  hjem.users.alice = {
    directory = "/home/alice";
    files = {
      # Write a text file in '/homes/alice/.config/foo'
      # with the contents 'bar'
      ".config/foo".text = "bar";

      # Alternatively, create the file source using a writer.
      # This can be used to generate config files with various
      # formats expected by different programs.
      ".config/bar".source = pkgs.writeTextFile "file-foo" "file contents";

      # You can also use generators to transform Nix values
      ".config/baz" = {
        # Works with `pkgs.formats` too!
        generator = lib.generators.toJSON {};
        value = {
          some = "contents";
        };
      };
    };
  };
}
```

#### Using Hjem To Install Packages {#installing-packages}

Hjem exposes an experimental interface for managing packages of individual
users. At its core, `hjem.users.<name>.packages` is identical to
`users.users.<name>.packages` as found in Nixpkgs. In fact, to avoid creating
additional environments Hjem maps your `hjem.users.<name>.packages` to
`users.users.<name>.packages`. This is provided as a convenient alias to manage
users in one place, but **this may be subject to change!**. Please report any
issues.
