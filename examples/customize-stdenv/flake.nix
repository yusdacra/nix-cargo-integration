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
        crateName = "my-crate";
      in {
        # declare projects
        nci.projects.${crateName}.path = ./.;
        # configure crates
        nci.crates.${crateName} = {
          ### override stdenv for both dependencies and main derivation ###
          depsDrvConfig = {
            stdenv = pkgs.clangStdenv;
          };
          drvConfig = {
            stdenv = pkgs.clangStdenv;
          };
          # note: for overriding stdenv for *all* packages in a project
          # you can use `drvConfig` and `depsDrvConfig` under `nci.projects.<name>`
          # instead.
        };
      };
    };
}
