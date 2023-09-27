{...}: {
  perSystem = {
    pkgs,
    config,
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
        drvConfig.mkDerivation = {
          # add trunk and other dependencies
          nativeBuildInputs = with pkgs; [trunk nodePackages.sass wasm-bindgen-cli];
          # override build phase to build with trunk instead
          buildPhase = ''
            TRUNK_TOOLS_SASS=$(sass --version) \
            TRUNK_TOOLS_WASM_BINDGEN="${pkgs.wasm-bindgen-cli.version}" \
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
