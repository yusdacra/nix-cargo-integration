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
  base = rawShell.overrideAttrs (old:
    runtimeLibsEnv
    // {
      nativeBuildInputs =
        [(lib.hiPrio shellToolchain)]
        ++ (old.nativeBuildInputs or []);
    });
  overrideAttrs = shell: f: let
    new = base.overrideAttrs (
      old: let
        attrs = f old;
      in
        attrs
        // {
          nativeBuildInputs =
            (attrs.packages or [])
            ++ (attrs.nativeBuildInputs or [])
            ++ (old.nativeBuildInputs or []);
        }
    );
  in
    new
    // {
      overrideAttrs = overrideAttrs new;
    };
in
  overrideAttrs base (_: {})
