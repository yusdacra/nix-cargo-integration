{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rustOverlay = {
      url = "github:oxalica/rust-overlay";
      flake = false;
    };

    dream2nix = {
      url = "github:yusdacra/dream2nix/rust/crane-builder";
      inputs.gomod2nix.follows = "nixpkgs";
      inputs.mach-nix.follows = "nixpkgs";
      inputs.node2nix.follows = "nixpkgs";
      inputs.poetry2nix.follows = "nixpkgs";
      inputs.nix-parsec.follows = "nixpkgs";
    };
  };

  outputs = inputs: with inputs;
    let
      preCommitHooks = builtins.fetchGit {
        url = "https://github.com/cachix/pre-commit-hooks.nix.git";
        ref = "master";
        rev = "0398f0649e0a741660ac5e8216760bae5cc78579";
      };

      libb = import "${nixpkgs}/lib/default.nix";
      lib = import ./src/lib.nix {
        sources = { inherit rustOverlay devshell nixpkgs dream2nix preCommitHooks; };
      };

      cliOutputs = lib.makeOutputs {
        root = ./cli;
        overrides = {
          crateOverrides = common: _: {
            nci-cli = prev: {
              NCI_SRC = builtins.toString inputs.self;
              # Make sure the src doesnt get garbage collected
              postInstall = "ln -s $NCI_SRC $out/nci_src";
            };
          };
        };
      };

      tests =
        let
          testNames = libb.remove null (libb.mapAttrsToList (name: type: if type == "directory" then name else null) (builtins.readDir ./tests));
          tests = libb.genAttrs testNames (test: lib.makeOutputs { root = ./tests + "/${test}"; });
          flattenAttrs = attrs: libb.mapAttrsToList (n: v: libb.mapAttrs (_: libb.mapAttrs' (n: libb.nameValuePair (n + (if libb.hasInfix "workspace" n then "-${n}" else "")))) v.${attrs}) tests;
          checks = builtins.map (libb.mapAttrs (n: attrs: builtins.removeAttrs attrs [ ])) (flattenAttrs "checks");
          packages = builtins.map (libb.mapAttrs (n: attrs: builtins.removeAttrs attrs [ ])) (flattenAttrs "packages");
          shells = libb.mapAttrsToList (name: test: libb.mapAttrs (_: drv: { "${name}-shell" = drv; }) test.devShell) tests;
        in
        {
          checks = libb.foldAttrs libb.recursiveUpdate { } checks;
          packages = libb.foldAttrs libb.recursiveUpdate { } packages;
          shells = libb.foldAttrs libb.recursiveUpdate { } shells;
        };
    in
    {
      inherit lib tests;
      inherit (cliOutputs) apps packages defaultApp defaultPackage checks;
    };
}
