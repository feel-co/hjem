# XDG Base Directory Support {#xdg}

[XDG Base Directory Specification]: https://specifications.freedesktop.org/basedir-spec/latest/

Hjem provides first-class support for the [XDG Base Directory Specification],
often referred to as the "XDG Spec", which defines standard locations for
configuration, data, cache, and state files.

## Overview

The XDG specification defines four standard directories:

| Directory         | Default Location  | Purpose                     |
| ----------------- | ----------------- | --------------------------- |
| `XDG_CONFIG_HOME` | `~/.config/`      | User-specific configuration |
| `XDG_DATA_HOME`   | `~/.local/share/` | User-specific data files    |
| `XDG_CACHE_HOME`  | `~/.cache/`       | Non-essential cached data   |
| `XDG_STATE_HOME`  | `~/.local/state/` | State data (logs, history)  |

In the light of our goal to provide intuitive file linking primitives, Hjem
provides dedications options each in order to make it easier to manage files in
these directories.

## Using XDG Directories

Instead of writing full paths like `".config/app/config"`, use the XDG
submodules:

```nix
{
  hjem.users.alice = {
    # Instead of this:
    files.".config/myapp/config".text = "...";

    # Do this:
    xdg.config.files."myapp/config".text = "...";
  };
}
```

Do note that Hjem lets you _change_ where XDG options, e.g., `xdg.config` point
to. For example, setting `hjem.users.<username>.xdg.config.directory` to
something like `"$HOME/xdg/config` will cause files from
`hjem.users.<username>.xdg.cache.files` to be placed in `$HOME/xdg` as opposed
to the default value of `$HOME/.config`. See [below](#customizing-xdg-paths) for
more details.

### Example

```nix
{ pkgs, lib, ... }: {
  hjem.users.alice = {
    directory = "/home/alice";

    # Configuration (~/.config/ by default)
    xdg.config.files = {
      "nvim/init.lua".source = ./nvim/init.lua;
      "git/config".text = lib.generators.toGitINI {} {
        user = {
          name = "Alice";
          email = "alice@example.com";
        };
        init.defaultBranch = "main";
      };

      "fish/config.fish".text = ''
        set -x EDITOR nvim
        fish_vi_key_bindings
      '';

      "alacritty/alacritty.toml" = {
        generator = (pkgs.formats.toml {}).generate "alacritty.toml";
        value = {
          font = {
            normal.family = "FiraCode";
            size = 12;
          };
          colors.primary.background = "#1a1b26";
        };
      };

    };

    # Data (~/.local/share/ by default)
    xdg.data.files = {
      "fonts/CustomFont.ttf".source = ./fonts/CustomFont.ttf;

      "applications/myapp.desktop".text = ''
        [Desktop Entry]
        Name=My Application
        Comment=Does something useful
        Exec=myapp
        Type=Application
        Icon=myapp
      '';

      "icons/hicolor/48x48/apps/myapp.png".source = ./icons/48x48.png;
      "icons/hicolor/256x256/apps/myapp.png".source = ./icons/256x256.png;
    };

    # Cache (~/.cache/ by default)
    xdg.cache.files = {
      # App cache directory
      "myapp".type = "directory";

      # Pre-populated cache metadata
      "myapp/metadata.json".text = builtins.toJSON {
        version = "1.0.0";
        lastClear = null;
      };
    };

    # State (~/.local/state/ by default)
    xdg.state.files = {
      # App state
      "myapp/state.json".text = builtins.toJSON {
        runs = 0;
        preferences = { };
      };

      # Log directory
      "myapp/logs".type = "directory";
    };
  };
}
```

## Customizing XDG Paths

You can also customize the paths that XDG directories will refer to.

```nix
{
  hjem.users.alice = {
    # Move config to alternate location
    xdg.config.directory = "/home/alice/dotfiles/config";

    # Move data directory
    xdg.data.directory = "/home/alice/my-data";

    # Cache on tmpfs (RAM)
    xdg.cache.directory = "/tmp/alice-cache";

    # State in persistent storage
    xdg.state.directory = "/persist/alice/state";
  };
}
```

### Automatic Environment Variables

When you customize a directory path, Hjem automatically adds the corresponding
environment variable to `environment.sessionVariables`, which you can load
automatically by sourcing {option}`environment.loadEnv` in your shell.

```nix
{
  hjem.users.alice = {
    xdg.config.directory = "/home/alice/dotfiles";
    # Automatically sets: XDG_CONFIG_HOME=/home/alice/dotfiles

    xdg.cache.directory = "/tmp/cache";
    # Automatically sets: XDG_CACHE_HOME=/tmp/cache
  };
}
```

## Environment Variables

When you customize XDG directories, Hjem automatically sets these environment
variables:

| Variable          | Set When                         |
| ----------------- | -------------------------------- |
| `XDG_CONFIG_HOME` | `xdg.config.directory` ≠ default |
| `XDG_DATA_HOME`   | `xdg.data.directory` ≠ default   |
| `XDG_CACHE_HOME`  | `xdg.cache.directory` ≠ default  |
| `XDG_STATE_HOME`  | `xdg.state.directory` ≠ default  |

Access them in your configuration:

```nix
{
  hjem.users.alice = {
    # Custom config location
    xdg.config.directory = "/home/alice/etc";

    # Use in other files
    files.".bashrc".text = ''
      # XDG_CONFIG_HOME is automatically set to /home/alice/etc
      echo "Config home: $XDG_CONFIG_HOME"
    '';
  };
}
```
