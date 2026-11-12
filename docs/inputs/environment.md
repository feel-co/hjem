# Environment Variables {#environment-variables}

Hjem can manage user environment variables through the
`hjem.users.<username>.environment.sessionVariables` option. Unlike Home
Manager, Hjem does not automatically inject these into your shell; you must
explicitly source them.

This design is a deliberate choice, users are encouraged to handle as they see
fit and document any possible converging solutions here for other users.

## Configuration

Per-user variables come from `environment.sessionVariables` under
`hjem.users.<user>`.

```nix
{
  hjem.users.alice.environment.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
    # Lists are joined with colons (like PATH)
    PATH = [ "$HOME/.local/bin" "$HOME/bin" ];
  };
}
```

This attribute set is used to generate a POSIX-compliant shell script for future
shell integration.

## Shell Integration

The variables are written to a POSIX-compliant script. You must source this
script in your shell configuration:

**Bash** (`~/.bashrc`):

```bash
source ${config.hjem.users.alice.environment.loadEnv}
```

**Zsh** (`~/.zshrc`):

```zsh
source ${config.hjem.users.alice.environment.loadEnv}
```

**Fish** (`~/.config/fish/config.fish`):

```fish
bass source ${config.hjem.users.alice.environment.loadEnv}
```
