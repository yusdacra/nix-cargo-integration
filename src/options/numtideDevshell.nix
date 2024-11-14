{lib, ...}: let
  l = lib // builtins;
in {
  options = {
    numtideDevshell = l.mkOption {
      type = l.types.nullOr l.types.str;
      default = null;
      description = ''
        If set, the given numtide devshell `devshells.<name>` will be populated with
        the required packages and environment variables to build this crate.
      '';
    };
  };
}
