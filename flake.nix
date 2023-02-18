{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      flake = false;
    };

    parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    mk-naked-shell = {
      url = "github:yusdacra/mk-naked-shell";
      flake = false;
    };

    dream2nix = {
      url = "github:nix-community/dream2nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "parts";

        devshell.follows = "";
        alejandra.follows = "";
        all-cabal-json.follows = "";
        flake-utils-pre-commit.follows = "";
        ghc-utils.follows = "";
        gomod2nix.follows = "";
        mach-nix.follows = "";
        poetry2nix.follows = "";
        pre-commit-hooks.follows = "";
        nix-pypi-fetcher.follows = "";
        pruned-racket-catalog.follows = "";
      };
    };
  };

  outputs = {parts, ...} @ inp: let
    flakeModule = {
      imports = [
        inp.dream2nix.flakeModuleBeta
        ./src/default.nix
      ];
      config = {
        nci._inputs = {
          inherit (inp) rust-overlay;
        };
      };
    };
  in
    parts.lib.mkFlake {inputs = inp;} {
      imports = [flakeModule];

      systems = ["x86_64-linux"];

      flake = {inherit flakeModule;};
      perSystem = {
        config,
        pkgs,
        lib,
        system,
        ...
      }: {
        nci.projects."test-crate" = {
          relPath = "test-crate";
        };

        checks =
          lib.mapAttrs'
          (
            profile: package:
              lib.nameValuePair "test-crate-${profile}" package
          )
          config.nci.outputs."test-crate".packages;

        devShells.default = (pkgs.callPackage inp.mk-naked-shell {}) {
          name = "nci";
          packages = with pkgs; [alejandra treefmt];
        };
      };
    };
}
