{ sources
, system
, toolchainChannel ? "stable"
, buildPlatform ? "naersk"
, isNaersk ? buildPlatform == "naersk"
, isCrate2Nix ? buildPlatform == "crate2nix"
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
        } // prev.lib.optionalAttrs isCrate2Nix {
          cargo = toolchain;
          clippy = toolchain;
        }
      )
      (import (sources.devshell + "/overlay.nix"))
    ] ++
    (
      if isNaersk
      then [
        (final: prev: {
          naersk = prev.callPackage sources.naersk { };
        })
      ]
      else if isCrate2Nix
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
  { inherit sources system toolchainChannel buildPlatform isNaersk isCrate2Nix; }
  config))
