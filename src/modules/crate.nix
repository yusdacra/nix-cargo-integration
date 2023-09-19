{
  config,
  lib,
  pkgs,
  ...
}: let
  l = lib // builtins;
  t = l.types;
  mkDrvConfig = desc:
    l.mkOption {
      type = t.attrs;
      default = {};
      description = ''
        ${desc}
        Environment variables must be defined under an attrset called `env`.
      '';
      example = l.literalExpression ''
        {
          # inputs and most other stuff will automatically merge
          buildInputs = [pkgs.hello];
          # define env variables and options not defined in standard mkDerivation interface like this
          env = {
            CARGO_TERM_VERBOSE = "true";
            someOtherEnvVar = 1;
          };
        }
      '';
    };
in {
  options = {
    export = l.mkOption {
      type = t.nullOr t.bool;
      default = null;
      example = true;
      description = "Whether to export this all of this crate's outputs (if set will override project-wide setting)";
    };

    profiles = l.mkOption {
      type = t.nullOr (
        t.attrsOf (t.submoduleWith {
          modules = [./profile.nix];
        })
      );
      default = null;
      example = l.literalExpression ''
        {
          dev = {};
          release.runTests = true;
          custom-profile.features = ["some" "features"];
        }
      '';
      description = "Profiles to generate packages for this crate (if set will override project-wide setting)";
    };

    drvConfig = mkDrvConfig "Change main derivation configuration";
    depsDrvConfig = mkDrvConfig "Change dependencies derivation configuration";

    runtimeLibs = l.mkOption {
      type = t.listOf t.package;
      default = [];
      example = l.literalExpression ''
        [pkgs.alsa-lib pkgs.libxkbcommon]
      '';
      description = ''
        Runtime libraries that will be:
        - patched into the binary at build time,
        - present in `LD_LIBRARY_PATH` environment variable in development shell.

        Note that when it's patched in at build time, a separate derivation will
        be created that "wraps" the original derivation to not cause the whole
        crate to recompile when you only change `runtimeLibs`. The original
        derivation can be accessed via `.passthru.unwrapped` attribute.
      '';
    };

    renameTo = l.mkOption {
      type = t.nullOr t.str;
      default = null;
      description = "What to rename this crate's outputs to in `nix flake show`";
    };
  };
}
