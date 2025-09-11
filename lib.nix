{
  lib,
  pkgs,
}: let
  inherit (builtins) isList;
  inherit (lib.modules) mkDefault mkDerivedConfig mkIf mkMerge;
  inherit (lib.options) literalExpression mkEnableOption mkOption;
  inherit (lib.strings) concatMapStringsSep hasPrefix;
  inherit (lib.types) addCheck anything attrsOf bool either functionTo int lines listOf nullOr oneOf path str submodule;
in {
  # inlined from https://github.com/NixOS/nixpkgs/tree/master/nixos/modules/config/shells-environment.nix
  # using osOptions precludes using hjem (or this type) standalone
  envVarType = attrsOf (nullOr (oneOf [(listOf (oneOf [int str path])) int str path]));

  fileTypeRelativeTo = {
    rootDir,
    clobberDefault,
    clobberDefaultText,
  }:
    submodule ({
      name,
      target,
      config,
      options,
      ...
    }: {
      options = {
        enable =
          mkEnableOption "creation of this file"
          // {
            default = true;
            example = false;
          };

        target = mkOption {
          type = str;
          apply = p:
            if hasPrefix "/" p
            then throw "This option cannot handle absolute paths yet!"
            else "${config.relativeTo}/${p}";
          defaultText = name;
          description = ''
            Path to target file relative to ${rootDir}.
          '';
        };

        text = mkOption {
          default = null;
          type = nullOr lines;
          description = "Text of the file";
        };

        source = mkOption {
          type = nullOr path;
          default = null;
          description = "Path of the source file or directory";
        };

        generator = lib.mkOption {
          # functionTo doesn't actually check the return type, so do that ourselves
          type = addCheck (nullOr (functionTo (either options.source.type options.text.type))) (x: let
            generatedValue = x config.value;
            generatesDrv = options.source.type.check generatedValue;
            generatesStr = options.text.type.check generatedValue;
          in
            x != null -> (generatesDrv || generatesStr));
          default = null;
          description = ''
            Function that when applied to `value` will create the `source` or `text` of the file.

            Detection is automatic, as we check if the `generator` generates a derivation or a string after applying to `value`.
          '';
          example = literalExpression "lib.generators.toGitINI";
        };

        value = lib.mkOption {
          type = nullOr (attrsOf anything);
          default = null;
          description = "Value passed to the `generator`.";
          example = {
            user.email = "me@example.com";
          };
        };

        executable = mkOption {
          type = bool;
          default = false;
          example = true;
          description = ''
            Whether to set the execute bit on the target file.
          '';
        };

        clobber = mkOption {
          type = bool;
          default = clobberDefault;
          defaultText = clobberDefaultText;
          description = ''
            Whether to "clobber" existing target paths.

            - If using the **systemd-tmpfiles** hook (Linux only), tmpfile rules
              will be constructed with `L+` (*re*create) instead of `L`
              (create) type while this is set to `true`.
          '';
        };

        relativeTo = mkOption {
          internal = true;
          type = path;
          default = rootDir;
          description = "Path to which symlinks will be relative to";
          apply = x:
            assert (hasPrefix "/" x || abort "Relative path ${x} cannot be used for files.<file>.relativeTo"); x;
        };
      };

      config = let
        generatedValue = config.generator config.value;
        hasGenerator = config.generator != null;
        generatesDrv = options.source.type.check generatedValue;
        generatesStr = options.text.type.check generatedValue;
      in
        mkMerge [
          {
            target = mkDefault name;
            source = mkIf (config.text != null) (mkDerivedConfig options.text (text:
              pkgs.writeTextFile {
                inherit name text;
                inherit (config) executable;
              }));
          }

          (lib.mkIf (hasGenerator && generatesDrv) {
            source = mkDefault generatedValue;
          })

          (lib.mkIf (hasGenerator && generatesStr) {
            text = mkDefault generatedValue;
          })
        ];
    });

  toEnv = env:
    if isList env
    then concatMapStringsSep ":" toString env
    else toString env;
}
