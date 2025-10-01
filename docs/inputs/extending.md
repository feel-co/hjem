# Extending Hjem {#extending-hjem}

The core strength of Hjem lies in its simplicity. No more intricate APIs for you
to parse through just to understand some basic feature. This should, however,
not be seen as a weakness of Hjem.

Projects such as Hjem Rum should be seen as proof just how much you may build
upon Hjem, and just how robust it is.

## Writing your own modules {#writing-hjem-modules}

You may freely consume the APIs exposed by Hjem to write your own modules,
primarily to fill the gap between a comprehensive (and clunky) module system
like Home Manager and something as quick and streamlined as Hjem.

To do so, you must write your own Hjem modules. Those modules will be evaluated
by Hjem to make more options, such as `programs.foo` or `services.bar` as you
might be used to from other module systems, once they are imported.

[NixOS Manual]: https://nixos.org/manual/nixos/stable/#sec-writing-modules
[Hjem Rum's FZF module]: https://github.com/snugnug/hjem-rum/blob/0f6b280c6c6073258da1a093d9aeae9368daedce/modules/collection/programs/fzf.nix

The [NixOS Manual] covers _very comprehensively_ how to write your own modules.
For the sake of brevity, we will only cover the basics required to write a valid
Hjem module, and how you may integrate it with Hjem as a separate module system.

The anatomy of a Hjem module is simple. You want to define `options`, and you
want to set `config` based on those options. Here is an example from Hjem Rum's
FZF module:

```nix
{
  lib,
  pkgs,
  config,
  ...
}: let
  inherit (lib.meta) getExe;
  inherit (lib.modules) mkAfter mkIf;
  inherit (lib.options) mkEnableOption mkPackageOption;

  cfg = config.rum.programs.fzf;
in {
  options.rum.programs.fzf = {
    enable = mkEnableOption "fzf";

    package = mkPackageOption pkgs "fzf" {nullable = true;};

    integrations = {
      fish.enable = mkEnableOption "fzf integration with fish";
      zsh.enable = mkEnableOption "fzf integration with zsh";
    };
  };

  config = mkIf cfg.enable {
    packages = mkIf (cfg.package != null) [cfg.package];

    rum.programs.fish.config = mkIf cfg.integrations.fish.enable (
      mkAfter "${getExe cfg.package} --fish | source"
    );
    rum.programs.zsh.initConfig = mkIf cfg.integrations.zsh.enable (
      mkAfter "source <(${getExe cfg.package} --zsh)"
    );
  };
}
```

`options.<namespace>` is the critical component here, as it will make options
such as `rum.programs.fzf` available for user configurations. The other
component, `config`, sets values in Hjem's own `packages` field and Hjem Rum's
`rum.programs.fish` and `rum.programs.zsh` fields which, in turn, set files such
as `.zshrc` and `.zshenv`.

Let's assume you have defined a similar module in `mymodules/fzf.nix` in your
configuration. You may consume it in your NixOS configuration by first importing
Hjem as a NixOS module, and adding it to Hjem's {option}`hjem.extraModules` in
order to be evaluated.

```nix
{
  # flake.nix
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    hjem.url = "github:feel-co/hjem";
  };

  # One example of importing the module into your system configuration
  outputs = {nixpkgs, ...} @ inputs: {
    nixosConfigurations = {
      default = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs;};
        modules = [
          # 1. First import the Hjem module
          inputs.hjem.nixosModules.default

          # 2. Now set `hjem.extraModules`
          ({pkgs, ...}: {
            hjem.extraModules = [
              # 3. We previously made a module in ./modules/fzf.nix. Let's import it
              # so that our new options are available.
              ./modules/fzf.nix # <- has to be a valid module!
            ];

            # 4. Now let's set some of our options, we previously made them available
            # under 'rum.programs.fzf', so let's go with that. The name is arbitrary, and
            # you can set it anything you want; for example 'mymodule.programs.fzf-yay' is
            # perfectly valid too!
            rum.programs.fzf = {
              enable = true;
              package = pkgs.fzf; # or something like pkgs.fzf.override { ... }
            };
          })
        ];
      };
    };
  };
}
```

Once you create and import your module, you are done. It all boils down to
defining a valid module, and consuming it in {option}`hjem.extraModules`. You
may also choose to export your defined modules as `hjemModules` in your
`flake.nix` if you want to allow others to use them too!

```nix
{
  inputs = { /* ... */ };
  outputs = {self, ...}: {
    hjemModules = {
      my-fzf-module = ./modules/fzf.nix; # The name is once again arbitrary.
      default = self.hjemModules.my-fzf-module; # You can set a default.
    };
  };
}
```
