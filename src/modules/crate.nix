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
    };

    overrides = l.mkOption {
      type = t.attrsOf t.attrs;
      default = {};
    };
    depsOverrides = l.mkOption {
      type = t.attrsOf t.attrs;
      default = {};
    };

    renameTo = l.mkOption {
      type = t.nullOr t.str;
      default = null;
      description = "What to rename this crate's outputs to in `nix flake show`";
    };
  };
}
