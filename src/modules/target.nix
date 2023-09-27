{lib, ...}: let
  l = lib // builtins;
  t = l.types;
in {
  imports = [../options/drvConfig.nix];
  options = {
    default = l.mkOption {
      type = t.bool;
      default = false;
      example = true;
      description = "Whether or not this target is the default target";
    };
    profiles = l.mkOption {
      type = t.nullOr (t.listOf t.str);
      default = null;
      defaultText = "all profiles";
      example = l.literalExpression ''
        ["dev" "release" "custom-profile"]
      '';
      description = ''
        The profiles to generate packages for this target.
      '';
    };
  };
}
