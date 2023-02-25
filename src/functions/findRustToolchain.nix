{
  lib,
  pkgs,
  rust-overlay,
  path,
  buildComponents,
  shellComponents,
}: let
  l = lib // builtins;
  rust-lib = l.fix (l.extends (import rust-overlay) (self: pkgs));
  # test if toolchain files exist
  legacyFilePath = "${path}/rust-toolchain";
  filePath = "${path}/rust-toolchain.toml";
  file =
    if l.pathExists filePath
    then filePath
    else if l.pathExists legacyFilePath
    then legacyFilePath
    else null;
  # Create the base Rust toolchain that we will override to add other components.
  toolchain =
    if file != null
    then rust-lib.rust-bin.fromRustupToolchainFile file
    else rust-lib.rust-bin.stable.latest.default;
  components = toolchain.passthru.availableComponents;
  mkAggregated = pkgs.callPackage "${rust-overlay}/mk-aggregated.nix" {};
in {
  build = mkAggregated {
    pname = "minimal";
    version = components.rustc.version;
    date = null;
    selectedComponents = l.attrVals buildComponents components;
  };
  shell = mkAggregated {
    pname = "shell";
    version = components.rustc.version;
    date = null;
    selectedComponents = l.attrVals (buildComponents ++ shellComponents) components;
  };
}
