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
      example = "path/to/project";
      description = "The path of this project relative to the flake's root";
    };
  };
}
