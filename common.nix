{ cargoPkg, sources, system, root, override ? (_: { }) }:
let
  nixMetadata = cargoPkg.metadata.nix;
  rustOverlay = import sources.rustOverlay;
  devshellOverlay = import (sources.devshell + "/overlay.nix");

  pkgs = import sources.nixpkgs {
    inherit system;
    overlays = [
      rustOverlay
      devshellOverlay
      (final: prev:
        let
          baseRustToolchain =
            if (isNull (nixMetadata.toolchain or null))
            then (prev.rust-bin.fromRustupToolchainFile (root + "/rust-toolchain"))
            else prev.rust-bin."${nixMetadata.toolchain}".latest.default;
        in
        {
          rustc = baseRustToolchain.override {
            extensions = [ "rust-src" ];
          };
        }
      )
      (final: prev: {
        naersk = prev.callPackage sources.naersk { };
      })
    ];
  };

  baseConfig = {
    inherit pkgs cargoPkg nixMetadata root sources system;

    # Libraries that will be put in $LD_LIBRARY_PATH
    runtimeLibs = nixMetadata.runtimeLibs or [ ];
    buildInputs = nixMetadata.buildInputs or [ ];
    nativeBuildInputs = nixMetadata.nativeBuildInputs or [ ];
    env = nixMetadata.env or { };
  };
in
(baseConfig // (override baseConfig))
