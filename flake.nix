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
    l = inp.nixpkgs.lib // builtins;

    flakeModuleNciOnly = {
      imports = [./src/default.nix];
      config = {
        nci._inputs = {
          inherit (inp) rust-overlay;
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
      imports = [flakeModule];

      systems = ["x86_64-linux"];

      flake = {
        inherit flakeModule flakeModuleNciOnly;
        templates = {
          default = inp.self.templates.simple;
          simple = {
            description = "A simple flake.nix template for getting started";
            path = ./examples/simple;
          };
          simple-crate = {
            description = "A simple template with a Cargo crate pre-initialized";
            path = ./examples/simple-crate;
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
        nci.projects."test-crate" = {
          relPath = "test-crate";
        };
        nci.crates."test-crate".runtimeLibs = [pkgs.alsa-lib];

        apps.format.program = let
          configFile = pkgs.writeText "treefmt.toml" ''
            [formatter.nix]
            command = "${l.getExe pkgs.alejandra}"
            includes = ["*.nix"]
          '';
          script = pkgs.writeScript "format" ''
            ${l.getExe pkgs.treefmt} --config-file ${configFile} --tree-root ''${PRJ_ROOT:-$PWD}
          '';
        in
          toString script;

        checks =
          {"test-crate-devshell" = testOut.devShell;}
          // (
            l.mapAttrs'
            (
              profile: package:
                l.nameValuePair "test-crate-${profile}" package
            )
            testOut.packages
          );

        devShells.default = (pkgs.callPackage inp.mk-naked-shell {}) {
          name = "nci";
          packages = with pkgs; [alejandra treefmt];
        };
      };
    };
}
