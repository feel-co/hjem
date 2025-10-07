{
  inputs,
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
              inputs.self.nixosModules.hjem
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
                      utils = import "${inputs.nixpkgs}/nixos/lib/utils.nix" {
                        inherit lib;
                        config = {};
                        pkgs = null;
                      };
                    };
                  };

                  # due to how options are documented, `hjem.<name>` will try to access `users.users."‹name›"`
                  users.users."‹name›" = {home = "/home/‹name›";};
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

  hjemDocsWeb =
    pkgs.runCommandNoCC "hjem-docs" {
      nativeBuildInputs = [inputs.ndg.packages.${pkgs.hostPlatform.system}.ndg];
    } ''
      mkdir -p $out/share/doc

      # Copy the markdown sources to be processed by ndg
      cp -rvf ${./inputs} ./inputs

      ndg --verbose html \
        --jobs $NIX_BUILD_CORES --title "Hjem" \
        --module-options ${configJSON}/share/doc/nixos/options.json \
        --manpage-urls ${inputs.nixpkgs}/doc/manpage-urls.json \
        --options-depth 3 \
        --generate-search true \
        --highlight-code true \
        --input-dir ./inputs \
        --output-dir "$out/share/doc"
    '';
in {
  html = hjemDocsWeb;
  options.json =
    pkgs.runCommand "options.json" {
      meta.description = "List of Hjem options in JSON format";
    } ''
      mkdir -p $out/{share/doc,nix-support}

      cp -a ${configJSON}/share/doc/nixos $out/share/doc/hjem

      substitute \
        ${configJSON}/nix-support/hydra-build-products \
        $out/nix-support/hydra-build-products \
          --replace '${configJSON}/share/doc/nixos' "$out/share/doc/hjem"
    '';
}
