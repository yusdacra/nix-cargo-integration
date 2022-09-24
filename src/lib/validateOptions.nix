{lib}: let
  makeValidateFunc = module: config:
    (
      lib.evalModules
      {
        modules = [module {inherit config;}];
        specialArgs = {inherit lib;};
      }
    )
    .config;
in {
  validateConfig = makeValidateFunc ./configModule.nix;
  validatePkgConfig = makeValidateFunc ./pkgConfigModule.nix;
}
