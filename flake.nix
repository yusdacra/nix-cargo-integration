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
      mkCheck = path: (lib.makeOutputs { root = path; }).checks;
    in
    {
      inherit lib;

      checks = libb.recursiveUpdate (mkCheck ./tests/basic-bin) (mkCheck ./tests/basic-lib);
    };
}
