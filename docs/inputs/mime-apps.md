# MIME Applications {#mime-apps}

[freedesktop MIME specification]: https://specifications.freedesktop.org/mime-apps/latest/

Hjem can manage MIME application associations through the `xdg.mime-apps`
options following the [freedesktop MIME specification]. This creates
`~/.config/mimeapps.list` to define default applications for file types.

## Configuration

```nix
{
  hjem.users.alice.xdg.mime-apps = {
    # Set default applications
    default-applications = {
      "text/plain" = [ "nvim.desktop" "gedit.desktop" ];
      "image/png" = [ "firefox.desktop" "gimp.desktop" ];
      "application/pdf" = "firefox.desktop";
    };

    # Add associations
    added-associations = {
      "text/markdown" = [ "nvim.desktop" ];
    };

    # Remove associations
    removed-associations = {
      "text/plain" = "gedit.desktop";
    };
  };
}
```
