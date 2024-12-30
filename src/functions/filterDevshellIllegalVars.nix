{lib}: let
  l = lib // builtins;
  # illegal env names to be removed and not be added to the devshell
  illegalEnvNames = [
    # cargo artifact and vendoring derivations
    # we don't need these in the devshell
    "cargoArtifacts"
    "dream2nixVendorDir"
    "cargoVendorDir"
  ];
  isIllegalEnv = name: l.elem name illegalEnvNames;
  filterIllegal = cfg:
  # filter out attrsets, functions and illegal environment vars
    l.filterAttrs
    (name: env: (env != null) && (! isIllegalEnv name))
    cfg;
in
  filterIllegal
