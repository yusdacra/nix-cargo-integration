{
  config,
  lib,
  pkgs,
  ...
}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
    export = l.mkOption {
      type = t.bool;
      default = false;
      example = true;
      description = "Whether to export this all of this crate's outputs";
    };

    profiles = l.mkOption {
      type = t.attrsOf (t.submoduleWith {
        modules = [./profile.nix];
      });
      default = {
        dev = {};
        release.runTests = true;
      };
      example = l.literalExpression ''
        {
          dev = {};
          release.runTests = true;
          custom-profile.features = ["some" "features"];
        }
      '';
      description = "Profiles to generate packages for this crate";
    };

    overrides = l.mkOption {
      type = t.attrsOf t.attrs;
      default = {};
      example = l.literalExpression ''
        {
          add-env = {TEST_ENV = 1;};
          add-inputs.overrideAttrs = old: {
            buildInputs = (old.buildInputs or []) ++ [pkgs.hello];
          };
        }
      '';
      description = "Overrides to apply to this crate (see dream2nix Rust docs for crane)";
    };
    depsOverrides = l.mkOption {
      type = t.attrsOf t.attrs;
      default = {};
      example = l.literalExpression ''
        {
          add-env = {TEST_ENV = 1;};
          add-inputs.overrideAttrs = old: {
            buildInputs = (old.buildInputs or []) ++ [pkgs.hello];
          };
        }
      '';
      description = "Overrides to apply to this crate's dependency derivations (see dream2nix Rust docs for crane)";
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
