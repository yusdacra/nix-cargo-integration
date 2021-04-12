{
  inputs = {
    devshell.url = "github:numtide/devshell";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flakeUtils.url = "github:numtide/flake-utils";
    naersk = {
      url = "github:nmattia/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rustOverlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: with inputs;
    let
      libb = import "${nixpkgs}/lib/default.nix";
      lib = import ./lib.nix {
        sources = { inherit flakeUtils rustOverlay devshell nixpkgs naersk; };
      };
      testNames = libb.remove null (libb.mapAttrsToList (name: type: if type == "directory" then name else null) (builtins.readDir ./tests));
      tests = libb.genAttrs testNames (test: lib.makeOutputs { root = ./tests + "/${test}"; });
      shells = libb.mapAttrsToList (name: test: libb.mapAttrs (_: drv: { "${name}-shell" = drv; }) test.devShell) tests;
    in
    {
      inherit lib;

      checks = libb.foldAttrs libb.recursiveUpdate { } (shells ++ (libb.mapAttrsToList (_: v: v.checks) tests));
    };
}
