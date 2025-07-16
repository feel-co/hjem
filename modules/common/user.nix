# The common module that contains Hjem's per-user options. To ensure Hjem remains
# somewhat compliant with cross-platform paradigms (e.g. NixOS or Darwin.) Platform
# specific options such as nixpkgs module system or nix-darwin module system should
# be avoided here.
{
  config,
  pkgs,
  lib,
  ...
}: let
  inherit (lib.attrsets) attrsToList mapAttrsToList;
  inherit (lib.strings) concatLines concatMapStringsSep;
  inherit (lib.modules) mkDefault mkDerivedConfig mkIf mkMerge;
  inherit (lib.options) literalExpression mkEnableOption mkOption;
  inherit (lib.strings) hasPrefix optionalString;
  inherit (lib.types) addCheck anything attrsOf bool either functionTo int lines listOf nullOr package path str submodule oneOf;
  inherit (builtins) foldl' isList;

  cfg = config;

  fileType = relativeTo:
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
          defaultText = "name";
          description = ''
            Path to target file relative to {option}`hjem.users.<name>.files.<file>.relativeTo`.
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
          default = cfg.clobberFiles;
          defaultText = literalExpression "config.hjem.clobberByDefault";
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
          default = relativeTo;
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

  environmentType = submodule {
    options = {
      value = mkOption {
        type = str;
        default = "";
        description = "Set the value of the environment variable.";
      };

      default = mkOption {
        type = str;
        default = "";
        description = "Set the value of the environment variable if not already set.";
      };

      unset = mkOption {
        type = bool;
        default = false;
        description = "Whether to unset the environment variable.";
      };

      delimiter = mkOption {
        type = str;
        default = ":";
        description = "Delimiter used for environment variables which are lists.";
      };

      prefix = mkOption {
        type = listOf str;
        default = [];
        description = "Prepend value to the environment variable list.";
      };

      suffix = mkOption {
        type = listOf str;
        default = [];
        description = "Append value to the environment variable list.";
      };
    };
  };

  wrapperType = submodule ({ config, ... }: {
    options = {
      basePackage = mkOption {
        type = package;
        description = "Package being wrapped";
      };

      executable = mkOption {
        type = str;
        description = "File to be executed";

        # Assuming for most packages, the executable is the name of the package
        default = config.basePackage.pname;
      };

      finalPackage = mkOption {
        type = package;
        description = "Output derivation containing the wrapper of the package.";
        readOnly = true;
        default =
          pkgs.symlinkJoin {
            name = "${config.basePackage.name}-hjemWrapped";
            paths = [ config.basePackage ] ++ config.extraPackages;
            nativeBuildInputs = [ pkgs.makeWrapper ];
            postBuild =
              let
                envPairs = attrsToList config.environment;

                listToSepString = delimiter: xs: foldl' (a: x: "${a}${delimiter}${x}") "" xs;
                envFlag = n: v:
                  if (v.value != "") then
                    "--set ${n} ${v.value}"
                  else if (v.default != "") then
                    "--set-default ${n} ${v.default}"
                  else if v.unset then
                    "--unset ${n}"
                  else if (v.prefix != []) then
                    "--prefix ${n} ${v.delimiter} ${listToSepString v.delimiter v.prefix}"
                  else if (v.suffix != []) then
                    "--suffix ${n} ${v.delimiter} ${listToSepString v.delimiter v.suffix}"
                  else
                    ""
                  ;
              in
                ''
                  wrapProgram $out/bin/${config.executable} \
                    ${optionalString (config.directory != null) "--chdir ${config.directory}"} \
                    ${foldl' (a: x: "${a} --run ${x}") "" config.run} \
                    ${foldl' (a: x: "${a} --add-flag ${x}") "" config.args.prefix} \
                    ${foldl' (a: x: "${a} --append-flag ${x}") "" config.args.suffix} \
                    ${foldl' (a: x: "${a} ${envFlag x.name x.value}") "" envPairs} \
                '';
          };
      };

      directory = mkOption {
        type = nullOr path;
        default = null;
        description = "Change the directory of the package's environment.";
      };

      extraPackages = mkOption {
        type = listOf package;
        default = [];
        description = "Additional packages needed in the wrapper's environment $PATH.";
      };

      run = mkOption {
        type = listOf str;
        default = [];
        description = "Commands to run before the execution of the program";
      };

      args = {
        prefix = mkOption {
          type = listOf str;
          default = [];
          description = "Arguments to prepend to the beginning of the wrapped program's arguments.";
        };

        suffix = mkOption {
          type = listOf str;
          default = [];
          description = "Arguments to append to the end of the wrapped program's arguments.";
        };
      };

      environment = mkOption {
        type = attrsOf environmentType;
        default = {};
        description = "Manage the wrapper's environment variables.";
      };
    };
  });
in {
  imports = [
    # Makes "assertions" option available without having to duplicate the work
    # already done in the Nixpkgs module.
    (pkgs.path + "/nixos/modules/misc/assertions.nix")
  ];

  options = {
    enable =
      mkEnableOption "home management for this user"
      // {
        default = true;
        example = false;
      };

    user = mkOption {
      type = str;
      description = "The owner of a given home directory.";
    };

    directory = mkOption {
      type = path;
      description = ''
        The home directory for the user, to which files configured in
        {option}`hjem.users.<name>.files` will be relative to by default.
      '';
    };

    clobberFiles = mkOption {
      type = bool;
      example = true;
      description = ''
        The default override behaviour for files managed by Hjem for a
        particular user.

        A top level option exists under the Hjem module option
        {option}`hjem.clobberByDefault`. Per-file behaviour can be modified
        with {option}`hjem.users.<name>.files.<file>.clobber`.
      '';
    };

    files = mkOption {
      default = {};
      type = attrsOf (fileType cfg.directory);
      example = {".config/foo.txt".source = "Hello World";};
      description = "Files to be managed by Hjem";
    };

    packages = mkOption {
      type = listOf package;
      default = [];
      example = literalExpression "[pkgs.hello]";
      description = "Packages to install for this user";
    };

    environment = {
      loadEnv = mkOption {
        type = path;
        readOnly = true;
        description = ''
          A POSIX compliant shell script containing the user session variables needed to bootstrap the session.

          As there is no reliable and agnostic way of setting session variables, Hjem's
          environment module does nothing by itself. Rather, it provides a POSIX compliant shell script
          that needs to be sourced where needed.
        '';
      };
      sessionVariables = mkOption {
        type = attrsOf (oneOf [(listOf (oneOf [int str path])) int str path]);
        default = {};
        example = {
          EDITOR = "nvim";
          VISUAL = "nvim";
        };
        description = ''
          A set of environment variables used in the user environment.
          If a list of strings is used, they will be concatenated with colon
          characters.
        '';
      };
    };

    wrappers = mkOption {
      type = attrsOf wrapperType;
      default = {};
      example = {};
      description = "Wrappers to be managed by Hjem.";
    };
  };

  config = {
    environment.loadEnv = let
      toEnv = env:
        if isList env
        then concatMapStringsSep ":" toString env
        else toString env;
    in
      lib.pipe cfg.environment.sessionVariables [
        (mapAttrsToList (name: value: "export ${name}=\"${toEnv value}\""))
        concatLines
        (pkgs.writeShellScript "load-env")
      ];

    assertions = [
      {
        assertion = cfg.user != "";
        message = "A user must be configured in 'hjem.users.<user>.name'";
      }
      {
        assertion = cfg.directory != "";
        message = "A home directory must be configured in 'hjem.users.<user>.directory'";
      }
    ];
  };
}
