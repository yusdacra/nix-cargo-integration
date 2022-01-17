{ sources
, system
, lib
, overrideData
, useCrate2NixFromPkgs ? false
, toolchainChannel ? "stable"
, buildPlatform ? "naersk"
, override ? (_: _: { })
}:
let
  rustOverlay = import sources.rustOverlay;
  # Create an overlay for the Rust toolchain we will use.
  rustToolchainOverlay =
    final: prev:
    let
      inherit (builtins) readFile fromTOML isPath pathExists match;
      inherit (lib) hasInfix unique head;

      # Check if the passed toolchainChannel points to a toolchain file
      hasRustToolchainFile = (isPath toolchainChannel) && (pathExists toolchainChannel);
      # Create the base Rust toolchain that we will override to add other components.
      baseRustToolchain =
        if hasRustToolchainFile
        then prev.rust-bin.fromRustupToolchainFile toolchainChannel
        else prev.rust-bin.${toolchainChannel}.latest.default;
      # Read and import the toolchain channel file, if we can
      rustToolchainFile =
        if hasRustToolchainFile
        then
          let
            content = readFile toolchainChannel;
            legacy = match "([^\r\n]+)\r?\n?" content;
          in
          if legacy != null
          then null
          else (fromTOML content).toolchain
        else null;
      # Whether the toolchain is nightly or not.
      isNightly =
        hasInfix "nightly"
          (if hasRustToolchainFile
          then rustToolchainFile.channel or ""
          else toolchainChannel);
      # Override the base toolchain and add some default components.
      toolchain = baseRustToolchain.override {
        extensions = unique ((rustToolchainFile.components or [ ]) ++ [ "rust-src" "rustfmt" "clippy" ]);
      };
    in
    {
      rustc = toolchain;
      rustfmt = toolchain;
      clippy = toolchain;
    } // lib.optionalAttrs (!(lib.isNaersk buildPlatform) || isNightly) {
      # Only use the toolchain's cargo if we are on crate2nix, or if it's nightly.
      # naersk *does not* work with stable cargo, so we just use the nixpkgs provided cargo.
      cargo = toolchain;
    };
  # A package set with just our Rust toolchain overlayed.
  # Build platforms (naersk and crate2nix) will use this, instead of the main package set.
  rustPkgs = import sources.nixpkgs {
    inherit system;
    overlays = [
      rustOverlay
      rustToolchainOverlay
      # Import the toolchain.
      (_: prev: {
        nciRust = { inherit (prev) rustc rustfmt clippy cargo; };
        rustPlatform = prev.makeRustPlatform { inherit (prev) rustc cargo; };
      })
      # Overlay the build platform itself.
      (if lib.isNaersk buildPlatform
      then (_: prev: { naersk = prev.callPackage sources.naersk { }; })
      else if lib.isCrate2Nix buildPlatform
      then
        (_: prev: {
          # Use crate2nix source from nixpkgs and the original Rust toolchain from nixpkgs if
          # the user wants to use crate2nix from nixpkgs
          crate2nixTools = import "${sources.crate2nix}/tools.nix" {
            inherit useCrate2NixFromPkgs;
            pkgs = if useCrate2NixFromPkgs then import sources.nixpkgs { inherit system; } else prev;
          };
        })
      else if lib.isDream2Nix buildPlatform
      then (_: prev: { dream2nixTools = import "${sources.dream2nix}/src/default.nix" { pkgs = prev; }; })
      else throw "invalid build platform: ${buildPlatform}")
      # Import our utilities here so that they can be utilized.
      (_: prev: { nciUtils = import ./utils.nix { pkgs = prev; inherit lib; }; })
    ];
  };

  # Create the config for the *main* package set we will use.
  #
  # This is different from the "Rust package set". Overlaying rust packages
  # for the main package set can lead to rebuilds that are often not needed (eg. librsvg rebuilds).
  # If the user wants a specific package to be rebuilt, they can do so by overriding it's
  # attributes and use the Rust toolchain provided in `nciRust`.
  config = {
    inherit system;
    overlays = [
      rustOverlay
      # Import our Rust toolchain as an `nciRust` attribute to allow users to utilize it.
      # Also add rustPkgs here, since it can be useful.
      (final: prev: {
        inherit rustPkgs;
        nciRust = rustToolchainOverlay final prev;
      })
      (import (sources.devshell + "/overlay.nix"))
      # Import the pre commit hooks tools. It will use the Rust package set.
      (final: prev: {
        makePreCommitHooks =
          let
            tools =
              lib.filterAttrs (k: v: !(lib.any (a: k == a) [ "override" "overrideDerivation" ]))
                (rustPkgs.callPackage "${sources.preCommitHooks}/nix/tools.nix" {
                  hindent = null;
                  cabal-fmt = null;
                });
          in
          rustPkgs.callPackage "${sources.preCommitHooks}/nix/run.nix" {
            inherit tools;
            pkgs = rustPkgs;
            gitignore-nix-src = null;
            isFlakes = true;
          };
      })
      # Finally import our utilities. They must use the Rust package set, since they contain
      # build platform utilities.
      (final: prev: {
        nciUtils = import ./utils.nix { pkgs = rustPkgs; inherit lib; };
      })
    ];
  };
in
import sources.nixpkgs (config // (override overrideData config))
