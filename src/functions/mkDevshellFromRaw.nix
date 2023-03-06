{
  lib,
  rawShell,
  shellToolchain,
  runtimeLibs,
}: let
  l = lib // builtins;
  runtimeLibsEnv = l.optionalAttrs (l.length runtimeLibs > 0) {
    LD_LIBRARY_PATH = "${l.makeLibraryPath runtimeLibs}";
  };
in
  rawShell.overrideAttrs (old:
    runtimeLibsEnv
    // {
      nativeBuildInputs =
        [(lib.hiPrio shellToolchain)]
        ++ (old.nativeBuildInputs or []);
    })
