{
  inputs = {
    devshell.url = "github:numtide/devshell";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rustOverlay = {
      url = "github:oxalica/rust-overlay";
      flake = false;
    };
  };

  outputs = inputs: with inputs;
    let
      # these are meant to be updated and checked manually; so they are not specified in flake inputs.
      # specifying them here also makes flake.lock shorter, and allow for lazy eval, so if you dont use preCommitHooks
      # or a buildPlatform, it won't be fetched.
      naersk = builtins.fetchGit {
        url = "https://github.com/yusdacra/naersk.git";
        ref = "feat/cargolock-git-deps";
        rev = "7882e303c4904664194236c921365b4d6b86b9bc";
      };
      crate2nix = builtins.fetchGit {
        url = "https://github.com/yusdacra/crate2nix.git";
        ref = "feat/builtinfetchgit";
        rev = "7b340c5e90bddf9f9fd08df12e7371168c3c607d";
      };
      preCommitHooks = builtins.fetchGit {
        url = "https://github.com/cachix/pre-commit-hooks.nix.git";
        ref = "master";
        rev = "0398f0649e0a741660ac5e8216760bae5cc78579";
      };

      libb = import "${nixpkgs}/lib/default.nix";
      lib = import ./lib.nix {
        sources = { inherit rustOverlay devshell nixpkgs naersk crate2nix preCommitHooks; };
      };
      hashes = {
        basic-bin = "sha256-LvziPSGSAtdUeM4NZcD9qQjyMJ+n7EmutJVc+vcF1tI=";
        basic-bin-clang = "sha256-EPfiuvJ5wy/coHSfD0JHiqaTrgU0mR8ONlQ/U9ba1t4=";
      };
      mkPlatform = buildPlatform:
        let
          testNames = libb.remove null (libb.mapAttrsToList (name: type: if type == "directory" then name else null) (builtins.readDir ./tests));
          tsts = libb.genAttrs testNames (test: lib.makeOutputs {
            inherit buildPlatform;
            root = ./tests + "/${test}";
            cargoVendorHash = hashes.${test} or libb.fakeHash;
          });
          tests = libb.filterAttrs (n: _: if buildPlatform != "buildRustPackage" then true else if builtins.hasAttr n hashes then true else false) tsts;
          flattenAttrs = attrs: libb.mapAttrsToList (n: v: libb.mapAttrs (_: libb.mapAttrs' (n: libb.nameValuePair (n + (if libb.hasInfix "workspace" n then "-${n}" else "") + "-${buildPlatform}"))) v.${attrs}) tests;
          checks = builtins.map (libb.mapAttrs (n: attrs: builtins.removeAttrs attrs [ ])) (flattenAttrs "checks");
          packages = builtins.map (libb.mapAttrs (n: attrs: builtins.removeAttrs attrs [ ])) (flattenAttrs "packages");
          shells = libb.mapAttrsToList (name: test: libb.mapAttrs (_: drv: { "${name}-shell-${buildPlatform}" = drv; }) test.devShell) tests;
        in
        libb.foldAttrs libb.recursiveUpdate { } (shells ++ checks ++ packages);

      naerskPlatform = mkPlatform "naersk";
      crate2nixPlatform = mkPlatform "crate2nix";
      brpPlatform = mkPlatform "buildRustPackage";
    in
    {
      inherit lib;

      checks = libb.recursiveUpdate (libb.recursiveUpdate naerskPlatform crate2nixPlatform) brpPlatform;
      devShell = (lib.makeOutputs { root = ./tests/basic-bin; }).devShell;
    };
}
