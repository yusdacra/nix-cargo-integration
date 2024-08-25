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
      imports = [nci.flakeModule ./crates.nix];
      perSystem = {config, ...}: let
        # shorthand for accessing outputs
        # you can access crate outputs under `config.nci.outputs.<crate name>` (see documentation)
        outputs = config.nci.outputs;
      in {
        # export the project devshell as the default devshell
        devShells.default = outputs."my-project".devShell;
        # export the release package of the crate as default package
        packages.default = outputs."my-crate".packages.release;
      };
    };
}
