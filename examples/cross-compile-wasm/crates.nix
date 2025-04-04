{...}: {
  perSystem = {
    pkgs,
    config,
    lib,
    ...
  }: let
    crateName = "cross-compile";
  in {
    # declare projects
    nci.projects.${crateName}.path = ./.;
    # configure crates
    nci.crates.${crateName} = {
      targets."wasm32-unknown-unknown" = {
        default = true;
        drvConfig.env = {
          TRUNK_TOOLS_SASS = pkgs.nodePackages.sass.version;
          TRUNK_TOOLS_WASM_BINDGEN = pkgs.wasm-bindgen-cli.version;
          TRUNK_TOOLS_WASM_OPT = "version_${lib.removeSuffix "_b" pkgs.binaryen.version}";
          TRUNK_SKIP_VERSION_CHECK = "true";
        };
        drvConfig.mkDerivation = {
          # add trunk and other dependencies
          nativeBuildInputs = with pkgs; [trunk nodePackages.sass wasm-bindgen-cli binaryen];
          # override build phase to build with trunk instead
          buildPhase = ''
            echo sass is version $TRUNK_TOOLS_SASS
            echo wasm bindgen is version $TRUNK_TOOLS_WASM_BINDGEN
            HOME=$TMPDIR \
              trunk -v build \
              --dist $out \
              --release \
              ''${cargoBuildFlags:-}
          '';
          # disable install phase because trunk will directly output to $out
          dontInstall = true;
        };
      };
      # we can't run WASM tests on native, so disable tests
      profiles.release.runTests = false;
    };
  };
}
