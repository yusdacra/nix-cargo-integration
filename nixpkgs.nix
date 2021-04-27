{ sources
, system
, lib
, toolchainChannel ? "stable"
, buildPlatform ? "naersk"
, override ? (_: _: { })
}:
let
  config = {
    inherit system;
    overlays = [
      (import sources.rustOverlay)
      (final: prev:
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
        } // lib.optionalAttrs (lib.isCrate2Nix buildPlatform) {
          cargo = toolchain;
          clippy = toolchain;
        }
      )
      (import (sources.devshell + "/overlay.nix"))
    ] ++
    (
      if lib.isNaersk buildPlatform
      then [
        (final: prev: {
          naersk = prev.callPackage sources.naersk { };
        })
      ]
      else if lib.isCrate2Nix buildPlatform
      then [
        (final: prev: {
          crate2nixTools = import "${sources.crate2nix}/tools.nix" { pkgs = prev; };
        })
      ]
      else throw "invalid build platform: ${buildPlatform}"
    );
  };
in
import sources.nixpkgs (config // (override
  { inherit sources system toolchainChannel buildPlatform lib; }
  config))
