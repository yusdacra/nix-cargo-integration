{
  inputs = {
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
      preCommitHooks = builtins.fetchGit {
        url = "https://github.com/cachix/pre-commit-hooks.nix.git";
        ref = "master";
        rev = "0398f0649e0a741660ac5e8216760bae5cc78579";
      };
      dream2nix = builtins.fetchGit {
        url = "https://github.com/nix-community/dream2nix.git";
        ref = "main";
        rev = "49416753cf42bd3383b7244ba49e1bee602605cb";
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
