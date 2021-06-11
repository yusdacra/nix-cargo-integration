{ sources
, system
, lib
, overrideData
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
      # Create the base Rust toolchain that we will override to add other components.
      baseRustToolchain =
        if (builtins.isPath toolchainChannel) && (builtins.pathExists toolchainChannel)
        then prev.rust-bin.fromRustupToolchainFile toolchainChannel
        else prev.rust-bin.${toolchainChannel}.latest.default;
      # Override the base toolchain and add some default components.
      toolchain = baseRustToolchain.override {
        extensions = [ "rust-src" "rustfmt" "clippy" ];
      };
    in
    {
      rustc = toolchain;
      rustfmt = toolchain;
      clippy = toolchain;
    } // lib.optionalAttrs (lib.isCrate2Nix buildPlatform) {
      # Only use the toolchain's cargo if we are on crate2nix.
      # naersk *does not* work with stable cargo, so we just use the nixpkgs provided cargo.
      # TODO: if we are on a nightly toolchain, always use the toolchain cargo.
      cargo = toolchain;
    };
  # A package set with just our Rust toolchain overlayed.
  # Build platforms (naersk and crate2nix) will use this, instead of the main package set.
  rustPkgs = import sources.nixpkgs {
    inherit system;
    overlays = [
      rustOverlay
      rustToolchainOverlay
      (final: prev: {
        nciRust = {
          inherit (prev) rustc rustfmt clippy cargo;
        };
      })
    ] ++ (
      # Overlay the build platform itself.
      if lib.isNaersk buildPlatform
      then [
        (final: prev: {
          naersk = rustPkgs.callPackage sources.naersk { };
        })
      ]
      else if lib.isCrate2Nix buildPlatform
      then [
        (final: prev: {
          crate2nixTools = import "${sources.crate2nix}/tools.nix" { pkgs = rustPkgs; };
        })
      ]
      else throw "invalid build platform: ${buildPlatform}"
    ) ++ [
      # Import our utilities here so that they can be utilized.
      (final: prev: {
        nciUtils = import ./utils.nix prev;
      })
    ];
  };

  # Create the config for the *main* package set we will use.
  config = {
    inherit system;
    overlays = [
      rustOverlay
      # Import our Rust toolchain as an `nciRust` attribute to allow users to utilize it.
      (final: prev: {
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
        nciUtils = import ./utils.nix rustPkgs;
      })
    ];
  };
in
import sources.nixpkgs (config // (override overrideData config))
