{
  inputs = {
    devshell.url = "github:numtide/devshell";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flakeUtils.url = "github:numtide/flake-utils";
    naersk = {
      url = "github:yusdacra/naersk/feat/cargolock-git-deps";
      flake = false;
    };
    crate2nix = {
      url = "github:yusdacra/crate2nix/feat/builtinfetchgit";
      flake = false;
    };
    rustOverlay = {
      url = "github:oxalica/rust-overlay";
      flake = false;
    };
    preCommitHooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      flake = false;
    };
  };

  outputs = inputs: with inputs;
    let
      libb = import "${nixpkgs}/lib/default.nix";
      lib = import ./lib.nix {
        sources = { inherit flakeUtils rustOverlay devshell nixpkgs naersk crate2nix preCommitHooks; };
      };
      mkPlatform = buildPlatform:
        let
          testNames = libb.remove null (libb.mapAttrsToList (name: type: if type == "directory" then name else null) (builtins.readDir ./tests));
          tests = libb.genAttrs testNames (test: lib.makeOutputs {
            inherit buildPlatform;
            root = ./tests + "/${test}";
          });
          flattenAttrs = attrs: libb.mapAttrsToList (n: v: libb.mapAttrs (_: libb.mapAttrs' (n: libb.nameValuePair (n + (if libb.hasInfix "workspace" n then "-workspace" else "") + "-${buildPlatform}"))) v.${attrs}) tests;
          checks = builtins.map (libb.mapAttrs (n: attrs: builtins.removeAttrs attrs [ ])) (flattenAttrs "checks");
          packages = builtins.map (libb.mapAttrs (n: attrs: builtins.removeAttrs attrs [ ])) (flattenAttrs "packages");
          shells = libb.mapAttrsToList (name: test: libb.mapAttrs (_: drv: { "${name}-shell-${buildPlatform}" = drv; }) test.devShell) tests;
        in
        libb.foldAttrs libb.recursiveUpdate { } (shells ++ checks ++ packages);

      naerskPlatform = mkPlatform "naersk";
      crate2nixPlatform = mkPlatform "crate2nix";
    in
    {
      inherit lib;

      checks = libb.recursiveUpdate naerskPlatform crate2nixPlatform;
      devShell = (lib.makeOutputs { root = ./tests/basic-bin; }).devShell;
    };
}
