{
  lib,
  rawShell,
  shellToolchain,
  runtimeLibs,
}: let
  l = lib // builtins;
  inputsNames = ["buildInputs" "nativeBuildInputs" "propagatedBuildInputs" "propagatedNativeBuildInputs"];
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
        _newAttrs =
          attrs
          // {
            nativeBuildInputs =
              (attrs.packages or [])
              ++ (attrs.nativeBuildInputs or [])
              ++ (old.nativeBuildInputs or []);
          };
        newAttrs =
          _newAttrs
          // {
            env = l.filterAttrs (name: _: l.any (oname: name != oname) inputsNames) (_newAttrs.env or {});
            packages = l.unique ((_newAttrs.packages or []) ++ (l.flatten (l.map (name: _newAttrs.${name} or []) inputsNames)));
          };
      in
        newAttrs
    );
  in
    new
    // {
      overrideAttrs = overrideAttrs new;
    };
in
  overrideAttrs base (_: {})
