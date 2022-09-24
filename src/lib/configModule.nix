{lib, ...}: let
  inherit
    (lib)
    types
    mkOption
    mkEnableOption
    ;
  cCompilerOptions = {
    options = {
      package = mkOption {
        type = types.package;
        description = "The C compiler package.";
        example = ''
          ```
          pkgs.clang
          ```
        '';
      };
      useCCompilerBintools = mkOption {
        type = types.bool;
        default = true;
        example = false;
        description = "Whether to use the bintools from the C compiler or not.";
      };
    };
  };
in {
  options = {
    cCompiler = mkOption {
      type = types.oneOf [
        types.str
        types.package
        (
          types.submoduleWith {
            modules = [cCompilerOptions];
          }
        )
      ];
      default = "gcc";
      description = "The C compiler that will be used.";
      example = ''
        ''\nSet via specifying compiler attr name:
        ```nix
        {
          cCompiler = "clang";
        }
        ```
        Set via specifying compiler package:
        ```nix
        {
          cCompiler = pkgs.clang;
        }
        ```
        Set via specifying attrset:
        ```nix
        {
          cCompiler = {
            package = pkgs.clang;
            useCCompilerBintools = false;
          };
        }
        ```
      '';
    };
    preCommitHooks.enable = mkEnableOption "pre-commit hooks";
    builder = mkOption {
      type = types.enum ["crane" "build-rust-package"];
      default = "crane";
      example = ''
        ```
        build-rust-package
        ```
      '';
      description = "The dream2nix builder that will be used for building packages.";
    };
    pkgsOverlays = mkOption {
      type = types.listOf (
        types.either
        types.path
        (types.functionTo (types.functionTo types.attrs))
      );
      default = [];
      description = "Overlays to use for the nixpkgs package set.";
    };
    outputs = {
      rename = mkOption {
        type = types.attrsOf types.str;
        default = {};
        example = ''
          ```nix
          {
            "helix-term" = "helix";
          }
          ```
        '';
        description = "Which package outputs to rename to what.";
      };
      defaults = mkOption {
        type = types.attrsOf types.str;
        default = {};
        example = ''
          ```nix
          {
            app = "helix";
            package = "helix";
          }
          ```
        '';
        description = "Default outputs to set in outputs.";
      };
    };
    shell = mkOption {
      type = types.either types.attrs (types.functionTo types.attrs);
      default = {};
      description = "Development shell configuration.";
    };
    runtimeLibs = mkOption {
      type = types.listOf (types.either types.str types.package);
      default = [];
      example = ''
        ''\nSet via specifying package attr names:
        ```nix
        {
          runtimeLibs = ["ffmpeg"];
        }
        ```
        Set via specifying packages:
        ```nix
        {
          runtimeLibs = [pkgs.ffmpeg];
        }
        ```
      '';
      description = ''
        Libraries that will be put in `LD_LIBRARY_PRELOAD` environment variable for the dev env.
        These will also be added to the resulting package when you build it, as a wrapper that adds the env variable.
      '';
    };
    cachix = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Name of the cachix cache.";
      };
      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Public key of the cachix cache.";
      };
    };
  };
}
