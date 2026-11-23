# D-Bus Services {#dbus}

Hjem can manage D-Bus sessiob services on NixOS through the
`hjem.users.<username>.dbus.packages` option, following the same pattern as
NixOS's `systemd.packages`. Packages listed in the option have their D-Bus
service files, taken from `$pkg/share/dbus-1/services/`, linked via
`hjem.users.<username>.xdg.data.files` into `dbus-1/services/` relative to
{option}`hjem.users.<username>.xdg.data.directory` (`$HOME/.local/share` by
default).

## Configuration

Packages shipping D-Bus-activated session services under
`share/dbus-1/services/` are registered for the user without any extra
configuration. Service files from Nixpkgs packages reference their binaries by
absolute store path, so no further setup is needed for D-Bus to activate them.

```nix
{
  hjem.users.alice.dbus.packages = [
    # e.g. playerctl ships 'org.mpris.MediaPlayer2.playerctld.service',
    # which activates playerctld, also shipped by the same package
    pkgs.playerctl
  ];
}
```
