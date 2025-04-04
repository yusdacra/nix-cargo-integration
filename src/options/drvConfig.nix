{lib, ...}: let
  l = lib // builtins;
  t = l.types;
  mkDrvConfig = desc:
    l.mkOption {
      type = t.attrsOf t.anything;
      default = {};
      description = ''
        ${desc}
        `mkDerivation` options must be defined under the `mkDerivation` attribute.
        Environment variables and non-mkDerivation options must be defined under the `env` attribute.
        This is passed to `dream2nix` as is, so you could also define any other dream2nix module options here (eg. `rust-crane`).
      '';
      example = l.literalExpression ''
        {
          mkDerivation = {
            # inputs and most other stuff will automatically merge
            buildInputs = [pkgs.hello];
          };
          # define env variables and options not defined in standard mkDerivation interface like this
          env = {
            CARGO_TERM_VERBOSE = "true";
            someOtherEnvVar = 1;
          };
        }
      '';
    };
in {
  options = {
    drvConfig = mkDrvConfig "Change main derivation configuration";
    depsDrvConfig = mkDrvConfig "Change dependencies derivation configuration";
  };
}
