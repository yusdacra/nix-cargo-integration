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
    };
    features = l.mkOption {
      type = t.nullOr (t.listOf t.str);
      default = null;
      defaultText = ''["default"]'';
      example = l.literalExpression ''
        ["tracing" "publish"]
      '';
      description = ''
        Features to enable for this target. Set to 'null' to enable default features only (this is the default).
        If set to a list of features then '--no-default-features' will be passed to Cargo.
        If you want to also enable default features you can add 'default' feature to the list of features.
      '';
    };
  };
}
