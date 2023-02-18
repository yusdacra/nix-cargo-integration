{
  lib,
  rawShell,
  shellToolchain,
}:
rawShell.overrideAttrs (old: {
  nativeBuildInputs =
    (old.nativeBuildInputs or [])
    ++ [
      (lib.hiPrio shellToolchain)
    ];
})
