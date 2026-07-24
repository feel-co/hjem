# hjem-cli

[smfh]: https://github.com/feel-co/smfh

This is the standalone command-line companion to Hjem, a Nix module system for
managing files in your `$HOME`. It is a small Rust workspace that evaluates Hjem
manifests and applies them atomically via [smfh], and it serves two audiences at
once:

- **Plumbing** for the NixOS, nix-darwin and finix modules, whose activation
  services call into the CLI to validate manifests, link files, and poke Systemd
  user units when their contents change.
- **Porcelain** for machines that are not NixOS at all: `hjem standalone`
  evaluates a `hjem.nix` (or a flake output) and applies it to the current user,
  with NixOS-style generations, rollback, and expiry.

The installed binary is a multicall executable: symlinking it as
`hjem-standalone` or `hjem-internal` selects the corresponding subcommand family
from `argv[0]` (`package.nix` sets this up for you).

## Command surface

[top-level README]: https://github.com/feel-co/hjem/blob/main/README.md

```bash
# Standalone commands for using `hjem` on non-NixOS systems
$ hjem standalone <init|switch|build|generations|rollback|
                 expire-generations|remove-generations>

# Internal activation logic
$ hjem internal   <validate-manifest|activate|reload-actions|
                 update-state|cleanup-state>

# Manifest commands based on smfh's library componenet
$ hjem manifest   <validate|diff>

# Activation
$ hjem activate   --manifest <path> --state <path>
```

`standalone switch` and `standalone build` accept exactly one manifest source:
`--manifest` (pre-generated JSON), `--config` (a `hjem.nix` evaluated with
`nix eval`), or `--flake` (defaulting to `hjemConfigurations."$USER"`). State
lives in `$XDG_STATE_HOME/hjem/standalone`, or `~/.local/state/hjem/standalone`
when unset; `--state-dir` overrides it.

The `internal` commands are the module-facing plumbing and are generally not run
by hand, however, `manifest validate` and `manifest diff` might come handy when
authoring manifests directly. An alternative file linker can be plugged in with
`--external-linker` / `--linker-arg` on the activation commands.

See the [top-level README] for full usage examples and the manifest format.

## Development

`hjem-cli` is built with Rust (obviously) targeting Rust 1.95.0 (for the time
being) and a formatter from nightly edition of Rust to get access to more
formatter rules, and Taplo for TOML formatting. We do not vendor a
`rust-toolchain.toml`; please use the Nix devshell provided by the flake to
acquire a pure and reproducible development environment.

### Building

With Nix, from the repository root:

```sh
# Building with Nix
$ nix build .#hjem        # or: nix-build -A packages.hjem
```

With Cargo, from this directory:

```sh
# Building with Cargo
$ cargo build --release   # binary at target/release/hjem
$ cargo nextest run
```

## License

[LICENSE]: https://github.com/feel-co/hjem/blob/main/LICENSE

`hjem-cli` is licensed under Mozilla Public License (MPL) version 2.0, same as
Hjem. See [LICENSE].
