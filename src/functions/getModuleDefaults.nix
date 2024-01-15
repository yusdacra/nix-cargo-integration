{
  pkgs,
  lib,
  ...
}: module:
(lib.evalModules {
  specialArgs = {inherit pkgs;};
  modules = [module];
})
.config
