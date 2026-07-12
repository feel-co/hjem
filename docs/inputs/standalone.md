# Standalone CLI {#standalone-cli}

Hjem can manage the current user's home outside of a NixOS, nix-darwin, or Finix
module. Install the `hjem` package from the Hjem flake, then use either
`hjem standalone` or the packaged `hjem-standalone` alias.

```sh
nix profile install github:feel-co/hjem#hjem
hjem standalone --help
```

## Getting started

`hjem standalone init` creates a small configuration in `$XDG_CONFIG_HOME/hjem`,
or `~/.config/hjem` when `XDG_CONFIG_HOME` is unset. It creates `hjem.nix`, a
matching example source under `dotfiles/`, and, unless `--no-flake` is given, a
minimal `flake.nix`.

```sh
hjem standalone init
hjem standalone switch --flake ~/.config/hjem
```

Pass `--switch` to `init` to apply the generated configuration immediately, or
`--dir PATH` to create it elsewhere.

## Manifest sources

`switch` and `build` accept exactly one source:

- `--manifest PATH` reads an already-generated manifest JSON file.
- `--config PATH` evaluates a Nix expression such as `hjem.nix`.
- `--flake REF` evaluates a flake output. By default this is
  `hjemConfigurations."$USER"`; use `--flake-attr` to select another output.

The Nix value may be either the manifest itself or an attribute set containing
`manifest`. A manifest has a version and a list of files, for example:

```nix
{
  version = 3;
  files = [
    {
      type = "symlink";
      source = ./dotfiles/example;
      target = "/home/alice/.config/example";
    }
  ];
}
```

When using `--config` or `--flake`, the same value may also contain `packages`.
Standalone packages are installed into a Hjem-managed profile for the active
generation:

```nix
{
  manifest = {
    version = 3;
    files = [ ];
  };

  packages = [
    pkgs.hello
  ];
}
```

> [!TIP]
> Add the current profile to your login environment to expose package binaries:
>
> ```sh
> export PATH="$XDG_STATE_HOME/hjem/standalone/current-profile/bin:$PATH"
> ```
>
> If `XDG_STATE_HOME` is unset, use
> `$HOME/.local/state/hjem/standalone/current-profile/bin`.

Package support is not available for `--manifest`; manifest JSON remains a
file-linking format and cannot represent Nix derivations.

Use `--impure` only when that Nix evaluation requires impure builtins.

## Generations

Every successful `switch` saves the manifest as a generation before making it
current. State is stored in `$XDG_STATE_HOME/hjem/standalone`, or
`~/.local/state/hjem/standalone` by default. `--state-dir PATH` overrides it for
standalone lifecycle commands.

```sh
# Evaluate and validate without applying; the result is recorded under builds/.
$ hjem standalone build --config ./hjem.nix

# Inspect, roll back, and prune generations.
$ hjem standalone generations
$ hjem standalone rollback
$ hjem standalone rollback --generation generation-1780000000-123456789
$ hjem standalone expire-generations --keep-last 10
$ hjem standalone remove-generations generation-1780000000-123456789
```

> [!NOTE]
> `rollback` and `remove-generations` refuse invalid generation identifiers, and
> the current generation cannot be removed.
