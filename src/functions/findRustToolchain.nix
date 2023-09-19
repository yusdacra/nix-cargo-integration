{
  lib,
  pkgs,
  rust-overlay,
  toolchainConfig,
  path,
}: let
  l = lib // builtins;
  rust-lib = l.fix (l.extends (import rust-overlay) (self: pkgs));
  toolchainFile =
    if builtins.isPath toolchainConfig
    then toolchainConfig
    else if toolchainConfig == null
    then let
      # test if toolchain files exist
      legacyFilePath = "${path}/rust-toolchain";
      filePath = "${path}/rust-toolchain.toml";
      file =
        if l.pathExists filePath
        then filePath
        else if l.pathExists legacyFilePath
        then legacyFilePath
        else null;
    in
      file
    else null;
  toolchainAttrs =
    if builtins.isAttrs toolchainConfig
    then toolchainConfig
    else null;
  # Create the base Rust toolchain that we will override to add other components.
  toolchain =
    if toolchainFile != null
    then rust-lib.rust-bin.fromRustupToolchainFile toolchainFile
    else if toolchainAttrs != null
    then rust-lib.rust-bin.fromRustupToolchain toolchainAttrs
    else rust-lib.rust-bin.stable.latest.default;
in {
  build = toolchain;
  shell = toolchain;
}
