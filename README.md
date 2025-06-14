<h1 id="header" align="center">
  Hjem
</h1>

<div align="center">
  A streamlined way to manage your <code>$HOME</code> with Nix.
</div>

<div align="center">
  <br/>
  <a href="#what-is-this">Synopsis</a><br/>
  <a href="#features">Features</a> | <a href="#module-interface">Interface</a><br/>
  <a href="#things-to-do">Future Plans</a>
  <br/>
</div>

## What is this?

[systemd-tmpfiles]: https://www.freedesktop.org/software/systemd/man/latest/systemd-tmpfiles-setup.service.html

**Hjem** ("home" in Danish) is a module system that implements a simple and
streamlined way to manage files in your `$HOME`, such as but not limited to
files in your `~/.config`.

### Features

1. Multi-user by default
2. Small, simple codebase with minimal abstraction
3. Powerful `$HOME` management functionality and potential
4. Systemd-native file management via [systemd-tmpfiles]\*
5. Extensible for 3rd-party use

\*: Alternative linkers are planned for better non-NixOS support

### Implementation

Hjem exposes a very basic interface with multi-tenant capabilities, which you
may use to manage individual users' homes by leveraging the module system.

```nix
{
  hjem.users = {
    alice.files = {
      # Write a text file in `/homes/alice/.config/foo`
      # with the contents bar
      ".config/foo".text = "bar";

      # Alternatively, create the file source using a writer.
      # This can be used to generate config files with various
      # formats expected by different programs.
      ".config/bar".source = pkgs.writeTextFile "file-foo" "file contents";

      # You can also use generators to transform Nix values
      ".config/baz" = {
        # Works with `pkgs.formats` too!
        generator = lib.generators.toJSON { };
        value = {
          some = "contents";
        };
      };
    };
  };
}
```

Each attribute under `hjem.users`, e.g., `hjem.users.alice` or `hjem.users.jane`
represent a user managed via `users.users` in NixOS. If a user does not exist,
then Hjem will refuse to manage their `$HOME` by filtering non-existent users in
file creation.

## Module Interface

The interface for the `homes` module is conceptually very similar to Home
Manager, but it does not act as a collection of modules like Home Manager. We
only implement basic features, and leave abstraction to the user to do as they
see fit.

Below is a live implementation of the module.

```nix
nix-repl> :p nixosConfigurations."nixos".config.hjem.users
{
  alice = {
    directory = "/home/alice";
    enable = true;
    files = {
      ".config/foo" = {
        enable = true;
        executable = false;
        clobber = false;
        source = «derivation /nix/store/prc0c5yrfca63x987f2k9khpfhlfnq15-config-foo.drv»;
        target = ".config/foo";
        text = "bar";
      };
    };
    user = "alice";
  };
}

nix-repl> :p nixosConfigurations."nixos".config.systemd.user.tmpfiles.users
{
  alice = {
    rules = [ "L /home/alice/.config/foo - - - - /nix/store/jfpr2z1z1aykpw2j2gj02lwwvwv6hml4-config-foo" ];
  };
}
```

Instead of relying on a Bash script to link files in place, we utilize
[systemd-tmpfiles] to ensure the files are linked in place.

## Things to do

Hjem is mostly feature-complete, in the sense that it is a clean implementation
of `home.files` in Home Manager: it was never a goal to dive into abstracting
files into modules. Although, some _basic_ features such as managing _Systemd
Services_ or user packages may make their ways into the project in future
iterations.

### Manifest & Cleaning up dangling files

The systemd-tmpfiles module lacks a good way of cleaning up dangling files,
e.g., from files that are no longer linked. To tackle this problem, a _manifest_
of files can be used to diff said manifest during switch and remove files that
are no longer managed.

Relevant: https://github.com/feel-co/hjem/pull/9

### Alternative or/and configurable file linking mechanisms

Hjem currently utilizes systemd-tmpfiles to ensure the files are linked in
place. While this is a safe and powerful way to ensure files are placed in their
desired locations, it is not very robust. We may consider adding an alternative
linker, e.g., in Bash that expands upon systemd-tmpfiles functionality with
additional functionality.

Alternatively, similar to how NixOS handles external bootloaders, we may
consider a rebuild "hook" for allowing alternative linking methods where the
module system exposes the files configuration to a package user provides.

## Attributions

[Nixpkgs]: https://github.com/nixOS/nixpkgs
[Home Manager]: https://github.com/nix-community/home-manager

Special thanks to [Nixpkgs] and [Home Manager]. The interface of the
`hjem.users` module is inspired by Home Manager's `home.file` and Nixpkgs'
`users.users` modules. What is now Hjem started as an experimental module
addition to Nixpkgs' `users.users`. Hjem would not be possible without any of
those projects, thank you!

A project worthy of note is [Hjem Rum](https://github.com/snugnug/hjem-rum), by
[@Lunarnovaa](https://github.com/lunarnovaa) and
[@nezia1](https://github.com/nezia1), which establishes a Home Manager-like
module system for users less comfortable with manually linking files in place.
If you wish to utilize the power of Hjem, but want an easier interface, we
encourage you to take a look at Hjem Rum.

## License

This project is made available under Mozilla Public License (MPL) version 2.0.
See [LICENSE](LICENSE) for more details on the exact conditions. An online copy
is provided [here](https://www.mozilla.org/en-US/MPL/2.0/).
