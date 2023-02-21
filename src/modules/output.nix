{lib, ...}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
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
  };
}
