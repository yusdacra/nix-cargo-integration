{
  # The root of the Cargo workspace or package
  root,
  # The NCI sources
  sources,
  # The system we want to use
  system,
  # The (nixpkgs) library with NCI specific utilities
  lib,
  # The toolchain channel. This can be:
  # - a string, "stable" / "nightly" / "beta"
  # - a path to a `rust-toolchain.toml`.
  toolchainChannel ? "stable",
  # Overlays to apply to the nixpkgs package set
  overlays ? [],
}: let
  l = lib;

  # pkgs set we will use.
  pkgs =
    if l.length overlays > 0
    then import sources.nixpkgs {inherit system overlays;}
    else sources.nixpkgs.legacyPackages.${system};

  # Rust toolchain we will use.
  rustToolchain = let
    rust-lib = l.fix (l.extends (import sources.rust-overlay) (self: pkgs));
    # Check if the passed toolchainChannel points to a toolchain file
    hasRustToolchainFile =
      if l.hasPrefix "/" toolchainChannel
      then
        if l.pathExists toolchainChannel
        then true
        else l.throw "toolchain file (${toolchainChannel}) does not exist"
      else false;
    # Read and import the toolchain channel file, if we can
    rustToolchainFile =
      l.thenOrNull
      hasRustToolchainFile
      (
        let
          content = l.readFile toolchainChannel;
          legacy = l.match "([^\r\n]+)\r?\n?" content;
        in (l.thenOrNull (legacy == null) (l.fromTOML content).toolchain)
      );
    # Create the base Rust toolchain that we will override to add other components.
    baseToolchain =
      if hasRustToolchainFile
      then rust-lib.rust-bin.fromRustupToolchainFile toolchainChannel
      else rust-lib.rust-bin.${toolchainChannel}.latest.default;
    toolchain = baseToolchain.override {
      extensions =
        l.unique ((rustToolchainFile.components or [])
          ++ ["rust-src" "rustfmt" "clippy"]);
    };
  in {
    rustc = toolchain;
    cargo = toolchain;
    rust-src = toolchain;
    rustfmt = toolchain;
    clippy = toolchain;
  };
in rec {
  inherit rustToolchain pkgs;
  # nci library utilities
  utils = import ./pkgs-lib.nix {inherit pkgs lib sources root;};
  # pre commit hooks
  makePreCommitHooks = let
    tools =
      lib.filterAttrs (k: v: !(l.any (a: k == a) ["override" "overrideDerivation"]))
      (pkgs.callPackage "${sources.preCommitHooks}/nix/tools.nix" {
        inherit (rustToolchain) rustfmt;
        hindent = null;
        cabal-fmt = null;
      });
  in
    pkgs.callPackage "${sources.preCommitHooks}/nix/run.nix" {
      inherit tools pkgs;
      gitignore-nix-src = null;
      isFlakes = true;
    };
}
