{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    devshell = {
      url = "github:numtide/devshell";
      flake = false;
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      flake = false;
    };

    dream2nix = {
      url = "github:nix-community/dream2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.gomod2nix.follows = "nixpkgs";
      inputs.mach-nix.follows = "nixpkgs";
      inputs.node2nix.follows = "nixpkgs";
      inputs.poetry2nix.follows = "nixpkgs";
      inputs.alejandra.follows = "nixpkgs";
      inputs.pre-commit-hooks.follows = "nixpkgs";
      inputs.flake-utils-pre-commit.follows = "nixpkgs";
      inputs.devshell.follows = "devshell";
    };
  };

  outputs = inputs:
    with inputs; let
      preCommitHooks = builtins.fetchGit {
        url = "https://github.com/cachix/pre-commit-hooks.nix.git";
        ref = "master";
        rev = "b6bc0b21e1617e2b07d8205e7fae7224036dfa4b";
      };

      sources = {inherit rust-overlay devshell nixpkgs dream2nix preCommitHooks;};
      lib = import ./src/lib.nix {
        lib = import "${nixpkgs}/lib";
      };
      l = lib;

      makeOutputs = import ./src/makeOutputs.nix {inherit sources lib;};

      cliOutputs = makeOutputs {
        root = ./cli;
        overrides = {
          crates = common: _: {
            nci-cli = prev: {
              NCI_SRC = builtins.toString inputs.self;
              # Make sure the src doesnt get garbage collected
              postInstall = "ln -s $NCI_SRC $out/nci_src";
            };
          };
        };
      };

      mkTestOutputs = builder: let
        testNames = l.remove null (l.mapAttrsToList (name: type:
          if type == "directory"
          then
            if name != "broken"
            then name
            else null
          else null) (builtins.readDir ./tests));
        tests = l.genAttrs testNames (test:
          makeOutputs {
            inherit builder;
            root = ./tests + "/${test}";
          });
        flattenAttrs = attrs:
          l.mapAttrsToList (n: v:
            l.mapAttrs (_:
              l.mapAttrs' (n:
                l.nameValuePair (n
                  + (
                    if l.hasInfix "workspace" n
                    then "-${n}"
                    else ""
                  ))))
            v.${attrs})
          tests;
        checks = builtins.map (l.mapAttrs (n: attrs: builtins.removeAttrs attrs [])) (flattenAttrs "checks");
        packages = builtins.map (l.mapAttrs (n: attrs: builtins.removeAttrs attrs [])) (flattenAttrs "packages");
        shells = l.mapAttrsToList (name: test: l.mapAttrs (_: drv: {"${name}-shell" = drv;}) test.devShell) tests;
      in {
        checks = l.foldAttrs l.recursiveUpdate {} checks;
        packages = l.foldAttrs l.recursiveUpdate {} packages;
        shells = l.foldAttrs l.recursiveUpdate {} shells;
      };

      craneTests = mkTestOutputs "crane";
      brpTests = mkTestOutputs "build-rust-package";

      testsApps = let
        systems = ["x86_64-linux"];
        outputsNames = ["craneTests" "brpTests"];
        _mkTestsApp = system: outputsPath: let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          flakeSrc = "path:${inputs.self.outPath}?narHash=${inputs.self.narHash}";
          script =
            pkgs.writeScript
            "test-${l.replaceStrings ["."] ["-"] outputsPath}.sh"
            ''
              #!${pkgs.stdenv.shell}
              nix build -L --show-trace --keep-failed --keep-going \
              --expr "(builtins.getFlake "${flakeSrc}").${outputsPath}"
            '';
        in {
          type = "app";
          program = toString script;
        };
        mkOutputs = system: let
          mkTestsApp = _mkTestsApp system;
        in
          l.listToAttrs
          (l.flatten (
            l.map
            (
              name: let
                mkApp = tname:
                  l.nameValuePair
                  "run-${name}-${tname}"
                  (mkTestsApp "${name}.${tname}.${system}");
                tnames = ["checks" "shells" "packages"];
              in
                l.map mkApp tnames
            )
            outputsNames
          ));
        outputs = l.genAttrs systems mkOutputs;
      in
        outputs;

      devShell = let
        systems = ["x86_64-linux"];
        mkShell = system: let
          mkShell =
            import
            "${inputs.devshell}/modules"
            inputs.nixpkgs.legacyPackages.${system};
          shell = mkShell {
            configuration =
              import "${inputs.devshell}/nix/importTOML.nix"
              ./devshell.toml
              {lib = l;};
          };
        in
          shell.shell;
      in
        l.genAttrs systems mkShell;

      allApps = l.recursiveUpdate cliOutputs.apps testsApps;
    in {
      lib = {
        inherit makeOutputs;
      };
      inherit craneTests brpTests;
      inherit (cliOutputs) packages defaultPackage;

      apps =
        l.mapAttrs
        (_: apps: apps // {default = apps.nci-cli;})
        allApps;

      devShells =
        l.recursiveUpdate
        (l.mapAttrs (_: d: {default = d;}) devShell)
        (l.mapAttrs (_: d: {cli = d;}) cliOutputs.devShell);

      templates = {
        default = {
          description = "a simple flake using nci";
          path = ./templates/simple;
        };
      };
    };
}
