{ sources
, system
, lib
, toolchainChannel ? "stable"
, buildPlatform ? "naersk"
, override ? (_: _: { })
}:
let
  rustOverlay = import sources.rustOverlay;
  rustToolchainOverlay =
    final: prev:
    let
      baseRustToolchain =
        if (builtins.isPath toolchainChannel) && (builtins.pathExists toolchainChannel)
        then prev.rust-bin.fromRustupToolchainFile toolchainChannel
        else prev.rust-bin.${toolchainChannel}.latest.default;
      toolchain = baseRustToolchain.override {
        extensions = [ "rust-src" "rustfmt" "clippy" ];
      };
    in
    {
      rustc = toolchain;
      rustfmt = toolchain;
      clippy = toolchain;
    } // lib.optionalAttrs (lib.isCrate2Nix buildPlatform) {
      cargo = toolchain;
    };
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
      (final: prev: {
        nciUtils = import ./utils.nix prev;
      })
    ];
  };

  config = {
    inherit system;
    overlays = [
      rustOverlay
      (final: prev: {
        nciRust = rustToolchainOverlay final prev;
      })
      (import (sources.devshell + "/overlay.nix"))
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
      (final: prev: {
        nciUtils = import ./utils.nix rustPkgs;
      })
    ];
  };
in
import sources.nixpkgs (config // (override
  { inherit sources system toolchainChannel buildPlatform lib; }
  config))
