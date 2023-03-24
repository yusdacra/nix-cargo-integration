{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.nci.url = "github:yusdacra/nix-cargo-integration";
  inputs.nci.inputs.nixpkgs.follows = "nixpkgs";
  inputs.parts.url = "github:hercules-ci/flake-parts";
  inputs.parts.inputs.nixpkgs-lib.follows = "nixpkgs";

  outputs = inputs @ {
    parts,
    nci,
    ...
  }:
    parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [nci.flakeModule];
      perSystem = {
        pkgs,
        config,
        ...
      }: let
        crateName = "cross-compile";
        # shorthand for accessing this crate's outputs
        # you can access crate outputs under `config.nci.outputs.<crate name>` (see documentation)
        crateOutputs = config.nci.outputs.${crateName};
      in {
        # declare projects
        # relPath is the relative path of a project to the flake root
        nci.projects.${crateName}.relPath = "";
        # configure crates
        nci.crates.${crateName} = {
          # export crate (packages and devshell) in flake outputs
          # alternatively you can access the outputs and export them yourself (see below)
          export = true;
          depsOverrides.set-target = {
            # set build flags to our target (which is wasm) so that dependencies are built correctly
            cargoBuildFlags = ["--target" "wasm32-unknown-unknown"];
          };
          overrides.build-with-trunk.overrideAttrs = old: {
            # add trunk and other dependencies
            nativeBuildInputs =
              (old.nativeBuildInputs or [])
              ++ (with pkgs; [trunk nodePackages.sass wasm-bindgen-cli]);
            # override build phase to build with trunk instead
            buildPhase = ''
              HOME=$TMPDIR \
                trunk -v build \
                --dist $out \
                --release ''${cargoBuildFlags:-}
            '';
            # disable install phase because trunk will directly output to $out
            dontInstall = true;
          };
          # we don't need debug artifacts, so only create release package
          profiles = {release.runTests = false;};
        };
        # export the crate devshell as the default devshell
        devShells.default = crateOutputs.devShell;
        # export the release package of the crate as default package
        packages.default = crateOutputs.packages.release;
      };
    };
}
