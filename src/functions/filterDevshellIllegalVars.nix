{lib}: let
  l = lib // builtins;
  # illegal env names to be removed and not be added to the devshell
  illegalEnvNames =
    [
      "src"
      "name"
      "pname"
      "version"
      "args"
      "stdenv"
      "builder"
      "outputs"
      "phases"
      "shellHook"
      "patches"
      "doCheck"
      "doInstallCheck"
      # cargo artifact and vendoring derivations
      # we don't need these in the devshell
      "cargoArtifacts"
      "dream2nixVendorDir"
      "cargoVendorDir"
    ]
    ++ (
      l.map (n: "${n}Flags") ["configure" "cmake" "meson"]
    )
    ++ (
      l.map
      (phase: "${phase}Phase")
      ["configure" "build" "check" "install" "fixup" "unpack"]
    )
    ++ l.flatten (
      l.map
      (phase: ["pre${phase}" "post${phase}"])
      ["Configure" "Build" "Check" "Install" "Fixup" "Unpack"]
    );
  isIllegalEnv = name: l.elem name illegalEnvNames;
  filterIllegal = cfg:
  # filter out attrsets, functions and illegal environment vars
    l.filterAttrs
    (name: env: (env != null) && (! isIllegalEnv name))
    (
      l.mapAttrs
      (
        n: v:
          if l.isStringLike v || l.isFloat v || l.isInt v
          then l.toString v
          else null
      )
      cfg
    );
in
  filterIllegal
