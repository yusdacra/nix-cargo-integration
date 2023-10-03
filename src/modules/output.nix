{lib, ...}: let
  l = lib // builtins;
  t = l.types;
  opts = {
    packages = l.mkOption {
      type = t.lazyAttrsOf t.package;
      readOnly = true;
      description = "Packages of this crate mapped to profiles";
    };
    devShell = l.mkOption {
      type = t.package;
      readOnly = true;
      description = "The development shell for this crate";
    };
    check = l.mkOption {
      type = t.package;
      readOnly = true;
      description = "Tests only package for this crate";
    };
  };
in {
  options =
    opts
    // {
      allTargets = l.mkOption {
        type = t.lazyAttrsOf (t.submoduleWith {
          modules = [{options = {inherit (opts) packages;};}];
        });
        readOnly = true;
        description = "All packages for all targets";
      };
    };
}
