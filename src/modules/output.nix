{lib, ...}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
    packages = l.mkOption {
      type = t.lazyAttrsOf t.package;
      readOnly = true;
    };
    devShell = l.mkOption {
      type = t.package;
      readOnly = true;
    };
  };
}
