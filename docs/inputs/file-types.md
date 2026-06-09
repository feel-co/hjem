<!--markdownlint-disable MD024-->

# File Types {#file-types}

Hjem supports give different file types, backed by our linker, smfh, for
managing your `$HOME` robustly. Hjem supports five different file types for
managing your `$HOME`. Each type serves a specific purpose and has different
characteristics regarding performance, mutability, and use case.

## Quick Comparison

| Type        | Default? | Mutable? | Use For                        |
| ----------- | -------- | -------- | ------------------------------ |
| `symlink`   | Yes      | No       | Config files, dotfiles         |
| `copy`      | No       | Yes      | Files user might edit          |
| `delete`    | No       | N/A      | Removing old files/directories |
| `directory` | No       | N/A      | Creating empty directories     |
| `modify`    | No       | Depends  | Patching existing files        |

---

## symlink (Default)

Symbolic links are the default and recommended type for most use cases. They
create a pointer from your home directory to the Nix store, making them
space-efficient and atomic.

You may prefer symlinks for:

- Configuration files (dotfiles)
- Static resources that don't change
- Scripts and executables
- Any file that doesn't need user modification

as they are space efficient, atomic, and fast. Which is to say that multiple
users can share the same store path, and changes are instantaneous on rebuild.
However, it is worth noting that symlinks are _immutable_ and cannot be modified
unless your Nix store is mounted as read-write.

### Example

```nix
{
  hjem.users.alice.files = {
    # Simple text file
    ".config/git/config".text = ''
      [user]
        name = "Alice"
        email = "alice@example.com"
    '';

    # Symlink from store path
    ".config/nvim".source = ./nvim-config;

    # Using a generator
    ".config/alacritty/alacritty.toml" = {
      generator = (pkgs.formats.toml {}).generate "alacritty.toml";
      value = {
        font = {
          normal = { family = "FiraCode"; size = 12; };
        };
      };
    };
  };
}
```

> [!TIP]
> Use `clobber = true` to overwrite existing files

---

## copy

The `copy` type creates a physical copy of the file in your home directory.
Unlike symlinks, these files are mutable and can be edited by the user. Copied
files are mutable, and use a little more space compared to symlinks.

You may use this type when users need to modify files temporarily, or when
applications _require_ the configuration file to be a regular file. It might
also make sense for _template_ files, or in cases where immutability is
problematic.

### Constraints

- The `source` must be a **file**, not a directory
- Cannot be used with directories

### Generators with Copy

Generators work with the copy type when they produce a **path/derivation**
(e.g., using `pkgs.formats`). Generators that produce strings will not work
since copy requires a source path.

### Example

```nix
{
  hjem.users.alice.files = {
    # Copy a shell config that user might tweak
    ".bashrc" = {
      type = "copy";
      source = pkgs.writeText "bashrc" ''
        export EDITOR=nvim
        export PATH="$HOME/.local/bin:$PATH"
      '';
    };

    # Copy with specific permissions
    ".ssh/config" = {
      type = "copy";
      permissions = "600";
      source = pkgs.writeText "ssh-config" ''
        Host github.com
          User git
          IdentityFile ~/.ssh/id_ed25519
      '';
    };

    # Generated file as copy
    ".config/personal/settings.json" = {
      type = "copy";
      generator = lib.generators.toJSON {};
      value = {
        theme = "dark";
        notifications = true;
      };
    };
  };
}
```

---

## delete

The `delete` type removes files or directories from the home directory. This is
useful for cleaning up old configurations or removing files that conflict with
your setup.

### Example

```nix
{
  hjem.users.alice.files = {
    # Remove old config file
    ".config/old-app/config".type = "delete";

    # Remove entire directory
    ".local/share/deprecated-app".type = "delete";

    # Remove conflicting file before replacing
    ".bashrc" = {
      type = "delete";
      clobber = true;  # Delete even if it exists
    };
  };
}
```

### Warning

> [!CAUTION]
> The `delete` type permanently removes files. Use with care, especially with
> `clobber = true` which will delete without prompting.

---

## directory

The `directory` type creates empty directories with specified permissions. This
is useful for applications that expect certain directory structures to exist.
You could use it to set up state, i.e., cache/config/data directories with
proper permissions for runtime data or sensitive content. In a sense it is very
much like the `d` argument of systemd-tmpfiles.

The created directories are empty, and can specify `permissions`, `uid` and
`gid`. This mode is idempotent; it is safe to run multiple times.

### Example

```nix
{
  hjem.users.alice.files = {
    # Simple directory
    ".config/myapp".type = "directory";

    # Directory with specific permissions
    ".local/share/myapp" = {
      type = "directory";
      permissions = "700";  # Owner only
    };

    # Directory for sensitive data
    ".ssh" = {
      type = "directory";
      permissions = "700";
      uid = "1000";
      gid = "1000";
    };

    # Cache directory with relaxed permissions
    ".cache/myapp" = {
      type = "directory";
      permissions = "755";
    };
  };
}
```

### Permissions

Permissions are specified in octal notation (e.g., "755", "700"). Common values:

| Value | Meaning                                |
| ----- | -------------------------------------- |
| `700` | Owner: read/write/execute              |
| `755` | Owner: all, Group/Others: read/execute |
| `644` | Owner: read/write, Group/Others: read  |
| `600` | Owner: read/write only                 |

---

## modify

The `modify` type is an advanced feature for patching existing files. It allows
you to modify files that already exist on the system. You might use the modify
argument to "patch" system-provided configurations,, or for modifying files
installed by applications.

### Example

```nix
{
  hjem.users.alice.files = {
    # Modify an existing config file
    ".config/system/config.conf" = {
      type = "modify";
      # Modification logic depends on linker implementation
    };
  };
}
```

> [!WARNING]
> The `modify` type is implementation-dependent and may behave differently
> depending on the linker being used (smfh vs systemd-tmpfiles). Prefer other
> types when possible.

---

## Setting File Type

The file type is set using the `type` attribute:

```nix
{
  hjem.users.alice.files = {
    # Default (symlink)
    ".config/app1/config".text = "...";

    # Explicit symlink
    ".config/app2/config" = {
      type = "symlink";
      source = ./config;
    };

    # Copy
    ".config/app3/config" = {
      type = "copy";
      source = ./config;
    };

    # Delete
    ".config/old-app".type = "delete";

    # Directory
    ".local/share/app4".type = "directory";
  };
}
```

---

## Type-Specific Options

Not all options work with all types:

| Option        | symlink | copy            | delete | directory | modify |
| ------------- | ------- | --------------- | ------ | --------- | ------ |
| `source`      | yes     | yes (required)  | no     | no        | no     |
| `text`        | yes     | no              | no     | no        | no     |
| `generator`   | yes     | yes (path only) | no     | no        | no     |
| `value`       | yes     | yes             | no     | no        | no     |
| `permissions` | no      | yes             | no     | yes       | no     |
| `uid`         | no      | no              | no     | yes       | no     |
| `gid`         | no      | no              | no     | yes       | no     |
| `clobber`     | yes     | yes             | yes    | yes       | yes    |
| `enable`      | yes     | yes             | yes    | yes       | yes    |

> [!IMPORTANT]
> Generators work with both `symlink` and `copy` types, but behave differently:
>
> - If the generator produces a **path/derivation** (e.g.,
>   `pkgs.formats.json {}.generate`), it sets the `source` attribute - works
>   with both symlink and copy
> - If the generator produces a **string**, it sets the `text` attribute - only
>   works with symlink (copy requires a path source)

<!--markdownlint-enable MD024-->
