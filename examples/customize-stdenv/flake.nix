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
      perSystem = {pkgs, config, ...}: let
        crateName = "my-crate";
      in {
        # declare projects
        nci.projects.${crateName}.relPath = "";
        # configure crates
        nci.crates.${crateName} = let
          # the override we'll use for setting the stdenv
          set-stdenv = {
            # in this case we will set it to the clang stdenv
            override = old: {stdenv = pkgs.clangStdenv;};
          };
        in {
          ### override stdenv for both dependencies and main derivation ###
          depsOverrides = {
            inherit set-stdenv;
          };
          overrides = {
            inherit set-stdenv;
          };
        };
      };
    };
}
