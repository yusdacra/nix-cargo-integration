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

  resolveToPkg = key:
    let
      attrs = builtins.filter builtins.isString (builtins.split "\\." key);
      op = sum: attr: sum.${attr} or (throw "package \"${key}\" not found");
    in
    builtins.foldl' op pkgs attrs;
  resolveToPkgs = map resolveToPkg;

  baseConfig = {
    inherit pkgs cargoPkg nixMetadata root sources system;

    # Libraries that will be put in $LD_LIBRARY_PATH
    runtimeLibs = resolveToPkgs (nixMetadata.runtimeLibs or [ ]);
    buildInputs = resolveToPkgs (nixMetadata.buildInputs or [ ]);
    nativeBuildInputs = resolveToPkgs (nixMetadata.nativeBuildInputs or [ ]);
    env = nixMetadata.env or { };
  };
in
(baseConfig // (override baseConfig))
