{
  hjemModule,
  nixpkgs,
  pkgs,
  lib,
}: let
  inherit (builtins) isAttrs;
  inherit (lib.attrsets) isDerivation mapAttrs optionalAttrs;
  inherit (lib.modules) mkForce evalModules;
  inherit (lib.options) mkOption;
  inherit (lib.strings) hasPrefix removePrefix;
  inherit (lib.trivial) pipe;
  inherit (lib.types) anything;

  configJSON =
    (pkgs.nixosOptionsDoc {
      variablelistId = "hjem-options";
      warningsAreErrors = true;

      inherit
        (
          (evalModules {
            modules = [
              hjemModule
              {
                # exclude NixOS options from the documentation
                options = {
                  _module.args = mkOption {
                    internal = true;
                  };
                  users = mkOption {
                    type = anything;
                    internal = true;
                  };
                };
                config = {
                  _module = let
                    # From nixpkgs:
                    #
                    # Recursively replace each derivation in the given attribute set
                    # with the same derivation but with the `outPath` attribute set to
                    # the string `"\${pkgs.attribute.path}"`. This allows the
                    # documentation to refer to derivations through their values without
                    # establishing an actual dependency on the derivation output.
                    #
                    # This is not perfect, but it seems to cover a vast majority of use cases.
                    #
                    # Caveat: even if the package is reached by a different means, the
                    # path above will be shown and not e.g.
                    # `${config.services.foo.package}`.
                    scrubDerivations = namePrefix: pkgSet:
                      mapAttrs (
                        name: value: let
                          wholeName = "${namePrefix}.${name}";
                        in
                          if isAttrs value
                          then
                            scrubDerivations wholeName value
                            // optionalAttrs (isDerivation value) {
                              inherit (value) drvPath;
                              outPath = "\${${wholeName}}";
                            }
                          else value
                      )
                      pkgSet;
                  in {
                    check = false;
                    args = {
                      pkgs = mkForce (scrubDerivations "pkgs" pkgs);
                      utils = import "${nixpkgs}/nixos/lib/utils.nix" {
                        inherit lib;
                        config = {};
                        pkgs = null;
                      };
                    };
                  };

                  # due to how options are documented, `hjem.users.<username>` will try to access `users.users."‹username›"`
                  users.users."‹username›" = {home = "/home/‹username›";};
                };
              }
            ];
          })
        )
        options
        ;

      transformOptions = opt:
        opt
        // {
          declarations =
            map (
              decl:
                if hasPrefix (toString ../.) (toString decl)
                then
                  pipe decl [
                    toString
                    (removePrefix (toString ../.))
                    (removePrefix "/")
                    (x: {
                      url = "https://github.com/feel-co/hjem/blob/main/${x}";
                      name = "<hjem/${x}>";
                    })
                  ]
                else if decl == "lib/modules.nix"
                then {
                  url = "https://github.com/NixOS/nixpkgs/blob/master/${decl}";
                  name = "<nixpkgs/lib/modules.nix>";
                }
                else decl
            )
            opt.declarations;
        };
    })
    .optionsJSON;

  ndgConfig = (pkgs.formats.toml {}).generate "ndg-hjem.toml" {
    title = "Hjem";
    module_options = "${configJSON}/share/doc/nixos/options.json";
    manpage_urls_path = "${nixpkgs}/doc/manpage-urls.json";
    highlight_code = true;
    search.enable = true;
    sidebar.options.depth = 3;
  };

  hjemDocs =
    pkgs.runCommand "hjem-docs" {
      outputs = ["out" "man"];
      nativeBuildInputs = [pkgs.ndg pkgs.gzip];
    } ''
      mkdir -p $out/share/doc
      mkdir -p $man/share/man/man5

      # Copy the markdown sources to be processed by ndg
      cp -rvf ${./inputs} ./inputs

      ndg --verbose \
        --config-file ${ndgConfig} \
        html \
        --jobs $NIX_BUILD_CORES \
        --input-dir ./inputs \
        --output-dir "$out/share/doc"

      ndg --verbose man \
        --module-options ${configJSON}/share/doc/nixos/options.json \
        --title "hjem" \
        --section 5 \
        --output-file hjem.5

      gzip -c hjem.5 > $man/share/man/man5/hjem.5.gz
    '';
in {
  html = hjemDocs;
  man = hjemDocs.man;
  options.json =
    pkgs.runCommand "options.json" {
      meta.description = "List of Hjem options in JSON format.";
    } ''
      mkdir -p $out/{share/doc,nix-support}

      cp -a ${configJSON}/share/doc/nixos $out/share/doc/hjem

      substitute \
        ${configJSON}/nix-support/hydra-build-products \
        $out/nix-support/hydra-build-products \
          --replace '${configJSON}/share/doc/nixos' "$out/share/doc/hjem"
    '';
}
