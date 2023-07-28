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

    treefmt = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dream2nix = {
      url = "github:nix-community/dream2nix/legacy";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "parts";

        devshell.follows = "";
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
    l = inp.nixpkgs.lib // builtins;

    flakeModuleNciOnly = {
      imports = [./src/default.nix];
      config = {
        nci._inputs = {
          inherit (inp) rust-overlay dream2nix;
        };
      };
    };
    flakeModule = {
      imports = [
        inp.dream2nix.flakeModuleBeta
        flakeModuleNciOnly
      ];
    };
  in
    parts.lib.mkFlake {inputs = inp;} {
      imports = [
        flakeModule
        inp.treefmt.flakeModule
      ];

      systems = ["x86_64-linux"];

      flake = {
        inherit flakeModule flakeModuleNciOnly;
        templates = {
          default = inp.self.templates.simple;
          simple = {
            description = "A simple flake.nix template for getting started";
            path = ./examples/simple;
            welcomeText = ''
              To get started:

              1. edit the project `relPath` in `flake.nix` to point to your project.
              2. change `my-crate` crate name to your own crate name.
              3. (optionally) add any other crate (or project) you want to configure.

              You're set!
            '';
          };
          simple-crate = {
            description = "A simple template with a Cargo crate pre-initialized";
            path = ./examples/simple-crate;
            welcomeText = ''
              To get started, edit crate name in `flake.nix` and `Cargo.toml` to your liking.
              And you should be good to go!
            '';
          };
          simple-workspace = {
            description = "A simple template with a Cargo workspace pre-initialized";
            path = ./examples/simple-workspace;
            welcomeText = ''
              To get started:

              1. edit crate names in `flake.nix` and `Cargo.toml`s to your liking,
              2. edit project name in `flake.nix`

              You're set!
            '';
          };
          cross-compile-wasm = {
            description = "An example showcasing WASM cross-compilation";
            path = ./examples/cross-compile-wasm;
          };
        };
      };
      perSystem = {
        config,
        pkgs,
        system,
        ...
      }: let
        testOut = config.nci.outputs."test-crate";
      in {
        nci.projects."test-crate-project" = {
          relPath = "test-crate";
        };
        nci.crates."test-crate".runtimeLibs = [pkgs.alsa-lib];

        treefmt = {
          projectRootFile = "flake.nix";
          programs.alejandra.enable = true;
        };

        checks =
          {
            "test-crate-devshell" = testOut.devShell;
            "test-crate-project-devshell" = config.nci.outputs."test-crate-project".devShell;
          }
          // (l.mapAttrs'
            (
              profile: package:
                l.nameValuePair "test-crate-${profile}" package
            )
            testOut.packages);
      };
    };
}
