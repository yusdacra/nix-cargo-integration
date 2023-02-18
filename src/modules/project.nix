{
  config,
  lib,
  ...
}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
    relPath = l.mkOption {
      type = t.str;
      default = "";
    };
  };
}
