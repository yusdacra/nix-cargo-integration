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
  # Rust toolchain we will use.
  rustToolchainOverlay = final: prev: let
    inherit (builtins) readFile fromTOML isPath pathExists match;
    inherit (lib) hasInfix unique head thenOrNull;

    # Check if the passed toolchainChannel points to a toolchain file
    hasRustToolchainFile = (isPath toolchainChannel) && (pathExists toolchainChannel);
    # Create the base Rust toolchain that we will override to add other components.
    baseRustToolchain =
      if hasRustToolchainFile
      then prev.rust-bin.fromRustupToolchainFile toolchainChannel
      else prev.rust-bin.${toolchainChannel}.latest.default;
    # Read and import the toolchain channel file, if we can
    rustToolchainFile =
      thenOrNull
      hasRustToolchainFile
      (
        let
          content = readFile toolchainChannel;
          legacy = match "([^\r\n]+)\r?\n?" content;
        in (thenOrNull (legacy == null) (fromTOML content).toolchain)
      );
    # Whether the toolchain is nightly or not.
    isNightly =
      hasInfix "nightly"
      (
        if hasRustToolchainFile
        then rustToolchainFile.channel or ""
        else toolchainChannel
      );
    # Override the base toolchain and add some default components.
    toolchain = baseRustToolchain.override {
      extensions = unique ((rustToolchainFile.components or []) ++ ["rust-src" "rustfmt" "clippy"]);
    };
  in {
    rustc = toolchain;
    rustfmt = toolchain;
    clippy = toolchain;
    cargo = toolchain;
  };
in rec {
  # pkgs set we will use.
  pkgs = import sources.nixpkgs {
    inherit system overlays;
  };
  # pkgs set with rust toolchain overlaid.
  pkgsWithRust = import sources.nixpkgs {
    inherit system;
    overlays = [
      (import sources.rustOverlay)
      rustToolchainOverlay
      (_: prev: {
        rustPlatform = prev.makeRustPlatform {inherit (prev) rustc cargo;};
      })
    ];
  };
  # dream2nix tools
  dream2nix = sources.dream2nix.lib.init {
    config.projectRoot = root;
    config.disableIfdWarning = true;
    pkgs = pkgsWithRust;
  };
  # devshell
  makeDevshell = import "${sources.devshell}/modules" pkgs;
  # nci library utilities
  utils = import ./pkgs-lib.nix {inherit pkgs pkgsWithRust lib dream2nix;};
  # pre commit hooks
  makePreCommitHooks = let
    tools =
      lib.filterAttrs (k: v: !(lib.any (a: k == a) ["override" "overrideDerivation"]))
      (pkgsWithRust.callPackage "${sources.preCommitHooks}/nix/tools.nix" {
        hindent = null;
        cabal-fmt = null;
      });
  in
    pkgsWithRust.callPackage "${sources.preCommitHooks}/nix/run.nix" {
      inherit tools;
      pkgs = pkgsWithRust;
      gitignore-nix-src = null;
      isFlakes = true;
    };
}
