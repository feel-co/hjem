<!-- markdownlint-disable MD033 MD041 -->

<div id="doc-begin" align="center">
  <h1 id="header">
    <pre>Hjem [ˈjɛmˀ]</pre>
  </h1>
  <p>
    A streamlined way to manage your <code>$HOME</code> anywhere with Nix.
  </p>
  <br/>
  <a href="#what-is-this">Synopsis</a><br/>
  <a href="#features">Features</a> | <a href="#module-interface">Interface</a><br/>
  <a href="#things-to-do">Future Plans</a>
  <br/>
</div>

## What is this?

[systemd-tmpfiles]: https://www.freedesktop.org/software/systemd/man/latest/systemd-tmpfiles-setup.service.html
[smfh]: https://github.com/feel-co/smfh
[Hjem CLI]: https://github.com/feel-co/hjem/tree/main/cli

**Hjem** (meaning "home" in Danish) is a module system framework that implements
simple, streamlined and polished primitives for managing files in your `$HOME`
such as but not limited to the files that belong in `~/.config`. Hjem aims to
approach the domain as an alternative, easy-to-grasp utility for managing your
`$HOME` purely and safely.

### Features

We have learned from the mistakes made in the ecosystem. Therefore, Hjem is a
lean module system and its super-fast Rust companion with the following features
emphasized:

1. Powerful `$HOME` management functionality and potential extensibility.
2. Small, simple and performant codebase with minimal abstraction.
3. Robust, atomic and _manifest based_ file handling with [smfh] & [Hjem CLI].
4. Multi-user by design, works with any number of users and anywhere Nix runs.
5. Designed for ease of extensibility and integration.

No compromises, only performance and comfort.

### How to use

Hjem features extensive documentation for your convenience, meticulously
describing each component and how to use them in various situations. Please
refer to the rendered documentation at <https://hjem.feel-co.org> for an
overview, usage guides and a NixOS module options reference.

### Implementation

At its core Hjem exposes a streamlined module interface with multi-tenant
capabilities, which you may use to manage individual users' homes by leveraging
the Nix module system.

```nix
{ inputs, lib, pkgs, ... }:
{
  /*
    other NixOS configuration here...
  */

  hjem = {
    users = {
      alice = {
        enable = true;

        files = {
          # Write a text file in `/home/alice/.foo`
          # with the contents bar
          ".foo".text = "bar";

          # Alternatively, create the file source using a writer.
          # This can be used to generate config files with various
          # formats expected by different programs.
          ".bar".source = pkgs.writeText "file-foo" "file contents";

          # You can also use generators to transform Nix values
          ".baz" = {
            # Works with `pkgs.formats` too!
            generator = lib.generators.toJSON { };
            value = {
              some = "contents";
            };
          };
        };

        # this will write into `/home/alice/.config/test/bar.json`
        xdg.config.files."test/bar.json" = {
          generator = lib.generators.toJSON { };
          value = {
            foo = 1;
            bar = "Hello world!";
            baz = false;
          };
          # overwrite existing unmanaged file, if present
          clobber = true;
        };
      };
    };
  };
}
```

> [!NOTE]
> Each attribute under `hjem.users`, e.g., `hjem.users.alice` or
> `hjem.users.jane` represent a user managed via `users.users` in NixOS. If a
> user does not exist, then Hjem will refuse to manage their `$HOME` by
> filtering non-existent users in file creation.

Similar to what you might be used to, Hjem manages both **sources** (i.e. files
you are version-controlling in your configuration repository) and **build-time
generated files** via the generators API. This gives you the option to pick
between traditional dotfile management akin to GNU Stow or the
Nix-for-everything approach where you generate other files (TOML, ini, KDL,
JSON, YAML, etc.) from Nix while building your configuration using generators
from Nixpkgs or even your own.

## Module Interface

[already exists!]: https://github.com/snugnug/hjem-rum

The module interface for the `hjem` module is conceptually very simple, and it
is very similar to prior art (e.g., Home Manager) but unlike Home Manager Hjem
_does not_ act as module collection that must be maintained until the end of
time. Instead, we implement minimal features (mostly around file linking and
service management) and leave application-specific abstractions to the user to
write and maintain as they see fit. This design choice is grounded on the
reality that most users already have their _own_ module system inside their
configurations, which causes an overlap. Of course, the lean design of Hjem does
not mean a module collection cannot exist. We strongly encourage software
authors to ship their own Hjem modules, and build their own module collections.
As a matter of fact, one [already exists!]

Below is a live implementation of the module interface, represented in JSON as
will be written in the manifest:

<!--markdownlint-disable MD013-->

```bash
$ nix eval .#nixosConfigurations.test.config.hjem.users.alice.files.'".foo"' --json | jq
{
  "clobber": false,
  "enable": true,
  "executable": false,
  "generator": null,
  "relativeTo": "/home/alice",
  "source": "/nix/store/22yfhzhk0w5mgaq6c943vimsg6qlr1sh-foo",
  "target": "/home/alice/.foo",
  "text": "bar",
  "value": null
}
```

<!--markdownlint-enable MD013-->

### Linker Implementation

[standalone Rust library]: https://crates.io/crates/smfh

Hjem is powered by the [Hjem CLI], powered by the atomic and reliable file
linking utility [smfh] initially designed by the awesome [Gerg-l]. Hjem utilizes
smfh and Systemd services [^1] to correctly link files into place without any
unwanted side effects, and provides additional observability (and manual
intervention tooling) into what really happens during linking.

[^1]: Which is preferable to hacky activation scripts that may or may not break.
    Systemd services allow for ordered dependency management across all
    services, and easy monitoring of Hjem-related services from the central
    `systemctl` interface.

smfh is developed alongside Hjem as a [standalone Rust library], and the smfh
CLI is provided in Nixpkgs as `pkgs.smfh` if you wish to develop your own linker
or simply utilize smfh for atomic activation. For UX and quality of life
additions, please consider sending a pull request to the Hjem CLI!

### Environment Management

Hjem does **not** manage user environments as one might expect, but it provides
a convenient `environment.sessionVariables` option that you can use to store
your variables. This script will be used to store your environment variables in
a POSIX-compliant script generated by Hjem, which you can source in your shell
configurations.

## Things to do

Hjem is considered _mostly_ feature complete, in the sense that it is a clean,
modular and reliable system for managing your `$HOME` and a clean implementation
of the `home.files` API in Home Manager. It was never a goal to dive into
abstracting files into modules, so the core functionality is entirely complete
with clean linking semantics and Systemd user service management.

There are, however, things that we might be interested in doing. Below is a list
of things that are currently on the agenda.

## Attributions / Prior Art

[Nixpkgs]: https://github.com/nixOS/nixpkgs
[Home Manager]: https://github.com/nix-community/home-manager
[Hjem Rum]: https://github.com/snugnug/hjem-rum
[@Lunarnovaa]: https://github.com/lunarnovaa
[@nezia1]: https://github.com/nezia1
[@GetPsyched]: https://github.com/GetPsyched

Hjem is built on various ideas, projects and goals. First and foremost, our
sincerest thanks to everyone who has used, contributed to or just talked about
Hjem in public spaces. Thank you for the support!

### Prior Art

Secondly, but no less importantly, our sincerest thanks go to [Nixpkgs] and
[Home Manager]. The interface of the `hjem.users` module is inspired by Home
Manager's `home.file` and Nixpkgs' `users.users` modules. What is now Hjem
started as an experimental module addition to Nixpkgs' `users.users`. Hjem would
not be possible without any of those projects, thank you!

We also extend our thanks to [systemd-tmpfiles], which Hjem used previously to
link files in place. This served us well for the short duration that we relied
on them, but we have ultimately decided to go with our in-house file linker and
CLI. The new linker implementation is, of course, infinitely more powerful and
while we are _not_ looking back, we thank systemd-tmpfiles for the excellent
foundation it has provided.

### Hjem-Rum

Last, but not least, a project worthy of note is [Hjem Rum] initially by
[@Lunarnovaa] and [@nezia1] (who have also contributed to Hjem and the
surrounding ecosystem!) and now maintained by the awesome [@GetPsyched].
Hjem-Rum is a project establishes a Home Manager-like module system for users
less comfortable with manually linking files in place. If you wish to utilize
the power of Hjem, but want an easier interface, we encourage you to take a look
at Hjem Rum.

## License

<!--markdownlint-disable MD059-->

This project is made available under Mozilla Public License (MPL) version 2.0.
See [LICENSE](LICENSE) for more details on the exact conditions. An online copy
is [provided here](https://www.mozilla.org/en-US/MPL/2.0/).

<!--markdownlint-enable MD059-->

<div align="right">
  <a href="#doc-begin">Back to the Top</a>
  <br/>
</div>
