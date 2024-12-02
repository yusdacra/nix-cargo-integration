{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
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

    crane = {
      url = "github:ipetkov/crane/v0.19.0";
      flake = false;
    };

    dream2nix = {
      url = "github:nix-community/dream2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {parts, ...} @ inp: let
    l = inp.nixpkgs.lib // builtins;

    flakeModule = {
      imports = [./src/default.nix];
      config = {
        nci._inputs = {
          inherit (inp) crane dream2nix rust-overlay;
        };
      };
    };
  in
    parts.lib.mkFlake {inputs = inp;} {
      imports = [
        inp.treefmt.flakeModule
        flakeModule
        ./examples/simple-crate/crates.nix
        ./examples/customize-profiles/crates.nix
        ./examples/simple-workspace/crates.nix
      ];
      systems = ["x86_64-linux"];

      flake = {
        inherit flakeModule;
        templates = {
          default = inp.self.templates.simple;
          simple = {
            description = "A simple flake.nix template for getting started";
            path = ./examples/simple;
            welcomeText = ''
              To get started:

              1. edit the project `path` in `flake.nix` to point to your project.
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
          cross-compile-aarch64 = {
            description = "An example showcasing aarch64 cross-compilation";
            path = ./examples/cross-compile-aarch64;
          };
          cross-compile-windows = {
            description = "An example showcasing windows cross-compilation";
            path = ./examples/cross-compile-windows;
          };
          numtide-devshell = {
            description = "Example showcasing using a numtide devshell instead of NCI's own";
            path = ./examples/numtide-devshell;
          };
        };
      };
      perSystem = {config, ...}: let
        profilesOut = config.nci.outputs."customize-profiles";
        simpleOut = config.nci.outputs."my-crate";
        workspaceOut = config.nci.outputs."my-project";
        workspaceCrateOut = config.nci.outputs."my-workspace-crate";
        otherWorkspaceCrateOut = config.nci.outputs."my-other-workspace-crate";
      in {
        treefmt = {
          projectRootFile = "flake.nix";
          programs.alejandra.enable = true;
        };

        nci.projects."simple".export = false;
        nci.projects."profiles".export = false;
        nci.projects."my-project".export = l.mkForce false;

        checks."simple-test" = simpleOut.check;
        checks."simple-clippy" = simpleOut.clippy;
        checks."simple-docs" = simpleOut.docs;
        checks."simple-devshell" = simpleOut.devShell;
        checks."simple-workspace-test" = workspaceCrateOut.check;
        checks."simple-workspace-test-other" = otherWorkspaceCrateOut.check;
        checks."simple-workspace-devshell" = workspaceOut.devShell;
        checks."profiles-test" = profilesOut.packages.release;
      };
    };
}
