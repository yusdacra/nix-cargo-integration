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
        inherit (nixpkgs) lib;
      };
      l = lib;

      makeOutputs = import ./src/makeOutputs.nix {inherit sources lib;};

      cliOutputs = makeOutputs {
        root = ./cli;
        pkgConfig = common: {
          nci-cli.overrides.add-src.overrideAttrs = old: {
            NCI_SRC = builtins.toString inputs.self;
            # Make sure the src doesnt get garbage collected
            postInstall = ''
              ${old.postInstall or ""}
              ln -s $NCI_SRC $out/nci_src
            '';
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
            root = ./tests + "/${test}";
            config = _: {inherit builder;};
          });
        flattenAttrs = attrs:
          l.mapAttrsToList (n: v:
            l.mapAttrs (_:
              l.mapAttrs' (n:
                l.nameValuePair (
                  n
                  + "-${attrs}"
                  + (
                    if l.hasInfix "workspace" n
                    then "-${n}"
                    else ""
                  )
                )))
            v.${attrs})
          tests;
        checks = flattenAttrs "checks";
        packages = flattenAttrs "packages";
        shells = flattenAttrs "devShells";
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
            pkgs.writeShellScript
            "test-${l.replaceStrings ["."] ["-"] outputsPath}.sh"
            ''
              if [ "''${1:-""}" = "" ]; then
                nix build -L --show-trace --keep-failed --keep-going \
                --expr "(builtins.getFlake "${flakeSrc}").${outputsPath}"
              else
                nix build -L --show-trace --keep-failed --keep-going \
                --expr "(builtins.getFlake "${flakeSrc}").${outputsPath}.''${1}"
              fi
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
        nci-lib = lib;
      };
      inherit craneTests brpTests;
      inherit (cliOutputs) packages;

      apps =
        l.mapAttrs
        (_: apps: apps // {default = apps.nci-cli;})
        allApps;

      devShells =
        l.recursiveUpdate
        (l.mapAttrs (_: d: {default = d;}) devShell)
        (l.mapAttrs (_: d: {cli = d.default;}) cliOutputs.devShells);

      templates = let
        simple = {
          description = "a simple flake using nci";
          path = ./templates/simple;
        };
        full = {
          description = "a flake with all options that nci defines";
          path = ./templates/full;
        };
      in {
        inherit simple full;
        default = simple;
      };
    };
}
