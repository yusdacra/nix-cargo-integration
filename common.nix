{ memberName ? null, cargoPkg, workspaceMetadata, sources, system, root, overrides ? { } }:
let
  packageMetadata = cargoPkg.metadata.nix or null;

  rustOverlay = import sources.rustOverlay;
  devshellOverlay = import (sources.devshell + "/overlay.nix");

  pkgs = import sources.nixpkgs {
    inherit system;
    overlays = [
      rustOverlay
      devshellOverlay
      (final: prev:
        let
          rustToolchainFile = root + "/rust-toolchain";
          baseRustToolchain =
            if builtins.pathExists rustToolchainFile
            then prev.rust-bin.fromRustupToolchainFile rustToolchainFile
            else prev.rust-bin."${workspaceMetadata.toolchain or "stable"}".latest.default;
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

  # courtesy of devshell
  resolveToPkg = key:
    let
      attrs = builtins.filter builtins.isString (builtins.split "\\." key);
      op = sum: attr: sum.${attr} or (throw "package \"${key}\" not found");
    in
    builtins.foldl' op pkgs attrs;
  resolveToPkgs = map resolveToPkg;

  baseConfig = {
    inherit pkgs cargoPkg workspaceMetadata packageMetadata root sources system memberName;

    # Libraries that will be put in $LD_LIBRARY_PATH
    runtimeLibs = resolveToPkgs ((workspaceMetadata.runtimeLibs or [ ]) ++ (packageMetadata.runtimeLibs or [ ]));
    buildInputs = resolveToPkgs ((workspaceMetadata.buildInputs or [ ]) ++ (packageMetadata.buildInputs or [ ]));
    nativeBuildInputs = resolveToPkgs ((workspaceMetadata.nativeBuildInputs or [ ]) ++ (packageMetadata.nativeBuildInputs or [ ]));
    env = (workspaceMetadata.env or { }) // (packageMetadata.env or { });

    overrides = {
      shell = overrides.shell or (_: _: { });
      build = overrides.build or (_: _: { });
      common = overrides.common or (_: { });
    };
  };
in
(baseConfig // (baseConfig.overrides.common baseConfig))
