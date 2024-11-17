{
  config,
  lib,
  pkgs,
  ...
}: let
  l = lib // builtins;
  t = l.types;
in {
  imports = [
    ../options/drvConfig.nix
    ../options/numtideDevshell.nix
  ];
  options = {
    export = l.mkOption {
      type = t.nullOr t.bool;
      default = null;
      example = true;
      description = "Whether to export this all of this crate's outputs (if set will override project-wide setting)";
    };

    checkProfile = l.mkOption {
      type = t.str;
      default = "release";
      example = "custom-profile";
      description = "Profile to use for the tests only package";
    };
    useClippy = l.mkOption {
      type = t.nullOr t.bool;
      default = null;
      example = true;
      description = "Whether to use 'cargo clippy' or not for the crate's checks, instead of 'cargo check'";
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
    targets = l.mkOption {
      type = t.nullOr (
        t.attrsOf (t.submoduleWith {
          modules = [./target.nix];
        })
      );
      default = null;
      example = l.literalExpression ''
        {
          wasm32-unknown-unknown.profiles = ["release"];
          x86_64-unknown-linux-gnu.default = true;
        }
      '';
      description = "Targets to generate packages for this crate (if set will override project-wide setting)";
    };

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
