{lib, ...}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
    features = l.mkOption {
      type = t.listOf t.str;
      default = [];
    };
    runTests = l.mkOption {
      type = t.bool;
      default = false;
    };
  };
}
