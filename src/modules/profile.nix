{lib, ...}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
    features = l.mkOption {
      type = t.listOf t.str;
      default = [];
      example = l.literalExpression ''
        ["tracing" "publish"]
      '';
      description = "Features to enable for this profile";
    };
    runTests = l.mkOption {
      type = t.bool;
      default = false;
      example = true;
      description = "Whether to run tests for this profile";
    };
  };
}
