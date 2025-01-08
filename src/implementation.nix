{
  lib,
  flake-parts-lib,
  ...
} @ args: let
  l = lib // builtins;
  systemlessNci = args.config.nci;
  inp = systemlessNci._inputs;
in {
  # Make sure the top-level option devshells exists
  # even when the numtide devshell is not included.
  # We don't want to depend on adding the numtide devshell
  # module and this doesn't interfere with it when it is added.
  options = {
    perSystem = flake-parts-lib.mkPerSystemOption {
      options.devshells = l.mkOption {
        type = l.types.lazyAttrsOf (l.types.submoduleWith {modules = [];});
      };
    };
  };

  config = {
    perSystem = {
      config,
      pkgs,
      ...
    }: let
      getModuleDefaults = import ./functions/getModuleDefaults.nix {inherit lib pkgs;};
      moduleDefaults = {
        crate = getModuleDefaults ./modules/crate.nix;
        project = getModuleDefaults ./modules/project.nix;
      };
      # gets crate option, if null or is not defined then returns the project wide option, if also does not exist then returns module default
      _getCrateOption = crateName: optName: merge: let
        crate = nci.crates.${crateName} or moduleDefaults.crate;
        project = nci.projects.${cratesToProjects.${crateName} or crateName} or moduleDefaults.project;
      in
        if crate.${optName} == null
        then project.${optName} or null
        else if merge && l.isList crate.${optName}
        then project.${optName} ++ crate.${optName}
        else if merge && l.isAttrs crate.${optName}
        then project.${optName} // crate.${optName}
        else crate.${optName};
      getCrateOption = crateName: optName: _getCrateOption crateName optName true;
      getUnmergedCrateOption = crateName: optName: _getCrateOption crateName optName false;

      nci = config.nci;

      # project name -> nci crate cfg
      projectsToCrates =
        l.mapAttrs
        (
          name: project:
            import ./functions/getProjectCrates.nix {
              inherit lib;
              inherit (project) path;
            }
        )
        nci.projects;
      # crate name -> project name
      cratesToProjects = l.listToAttrs (l.flatten (
        l.mapAttrsToList
        (
          project: crates:
            l.map (crate: l.nameValuePair crate.name project) crates
        )
        projectsToCrates
      ));
      getCrateName = currentName: let
        newName = getCrateOption currentName "renameTo";
      in
        if newName != null
        then newName
        else currentName;

      outputsToExport =
        l.filterAttrs
        (name: out: getCrateOption name "export")
        nci.outputs;

      projectsChecked =
        l.mapAttrs
        (name: project:
          import ./functions/warnIfNoLock.nix {
            source = systemlessNci.source;
            inherit project lib;
          })
        nci.projects;
      projectsWithLock =
        l.mapAttrs
        (name: value: value.project)
        (
          l.filterAttrs
          (name: value: value.hasLock)
          projectsChecked
        );
      projectsWithoutLock =
        l.mapAttrs
        (name: value: value.project)
        (
          l.filterAttrs
          (name: value: !value.hasLock)
          projectsChecked
        );

      # get the toolchains we will use
      toolchainsFn = pkgs:
        import ./functions/findRustToolchain.nix {
          inherit lib pkgs;
          inherit (inp) rust-overlay;
          inherit (nci) toolchainConfig;
          path = toString systemlessNci.source;
        };

      _evalCrate = modules:
        inp.dream2nix.lib.evalModules {
          packageSets.nixpkgs = pkgs;
          modules =
            [
              inp.dream2nix.modules.dream2nix.rust-cargo-lock
              inp.dream2nix.modules.dream2nix.rust-cargo-vendor
              inp.dream2nix.modules.dream2nix.rust-crane
            ]
            ++ modules;
        };

      nci-lib = {
        buildCrate = {
          src,
          drvConfig ? {},
          depsDrvConfig ? {},
          cratePath ? "",
          mkRustToolchain ? nci.toolchains.mkBuild,
        }: let
          cargoToml = l.fromTOML (l.readFile (
            if cratePath == ""
            then "${src}/Cargo.toml"
            else "${src}/${cratePath}/Cargo.toml"
          ));
        in (_evalCrate [
          {
            paths.projectRoot = src;
            paths.projectRootFile = "Cargo.lock";
            paths.package = "/${cratePath}";
          }
          drvConfig
          {
            deps.craneSource = inp.crane;
            deps.mkRustToolchain = mkRustToolchain;

            name = l.mkForce cargoToml.package.name;
            version = l.mkForce cargoToml.package.version;

            mkDerivation.src = l.mkForce src;

            rust-crane.depsDrv = depsDrvConfig;
          }
        ]);
      };

      evalCrate = project: crate: let
        crateCfg = nci.crates.${crate.name} or moduleDefaults.crate;
      in
        _evalCrate [
          {
            paths.projectRoot = project.path;
            paths.projectRootFile = "flake.nix";
            paths.package = "/${crate.path}";
          }
          project.drvConfig
          crateCfg.drvConfig
          {
            deps.craneSource = inp.crane;
            deps.mkRustToolchain = nci.toolchains.mkBuild;

            name = l.mkForce crate.name;
            version = l.mkForce crate.version;

            mkDerivation.src = l.mkForce project.path;

            rust-crane.depsDrv = l.mkMerge [
              project.depsDrvConfig
              crateCfg.depsDrvConfig
            ];
          }
        ];
      # eval all crates with d2n
      d2nOutputs = l.listToAttrs (l.flatten (
        l.mapAttrsToList
        (
          projName: project:
            l.map
            (crate: {
              name = crate.name;
              value = evalCrate project crate;
            })
            projectsToCrates.${projName}
        )
        projectsWithLock
      ));

      # make crate outputs
      crateOutputs =
        l.mapAttrs
        (
          name: package: let
            runtimeLibs = getCrateOption name "runtimeLibs";
            profiles = getCrateOption name "profiles";
            targets = getUnmergedCrateOption name "targets";
            clippyProfile = getCrateOption name "clippyProfile";
            checkProfile = getCrateOption name "checkProfile";
            docsProfile = getCrateOption name "docsProfile";
            allTargets = import ./functions/mkPackagesFromRaw.nix {
              inherit pkgs runtimeLibs profiles targets;
              rawPkg = package;
            };
            _defaultTargets = l.attrNames (l.filterAttrs (_: v: v.default) targets);
            defaultTarget =
              if l.length _defaultTargets > 1
              then throw "there can't be more than one default target: ${l.concatStringsSep ", " _defaultTargets}"
              else if l.length _defaultTargets < 1
              then throw "there is no default target defined"
              else l.head _defaultTargets;
            packages = allTargets.${defaultTarget};
          in {
            inherit packages;
            allTargets = l.mapAttrs (_: packages: {inherit packages;}) allTargets;
            devShell = import ./functions/mkDevshellFromRaw.nix {
              inherit lib runtimeLibs;
              rawShell = import ./functions/mkRawshellFromDrvs.nix {
                inherit lib;
                inherit (pkgs) mkShell;
                name = "${name}-devshell";
                drvs = [(packages.dev.unwrapped or packages.dev)];
              };
              shellToolchain = nci.toolchains.mkShell pkgs;
            };
            check = import ./functions/mkCheckOnlyPackage.nix packages.${checkProfile};
            clippy = import ./functions/mkClippyOnlyPackage.nix packages.${clippyProfile};
            docs = import ./functions/mkDocsOnlyPackage.nix packages.${docsProfile};
          }
        )
        d2nOutputs;

      # make project outputs
      projectsOutputs =
        l.mapAttrs
        (name: project: let
          allCrateNames = l.map (crate: crate.name) projectsToCrates.${name};
          rawShell = import ./functions/mkRawshellFromDrvs.nix {
            inherit lib;
            inherit (pkgs) mkShell;
            name = "${name}-devshell";
            drvs = l.map (name: crateOutputs.${name}.packages.dev.unwrapped or crateOutputs.${name}.packages.dev) allCrateNames;
          };
          docs = pkgs.callPackage ./functions/combineDocsPackages.nix {
            inherit (nci-lib) buildCrate;
            derivationName = "${name}-docs";
            indexCrateName = project.docsIndexCrate;
            docsPackages =
              l.map
              (crateName: crateOutputs.${crateName}.docs)
              (
                l.filter
                (
                  crateName:
                    getCrateOption crateName "includeInProjectDocs"
                )
                allCrateNames
              );
          };
          runtimeLibs =
            project.runtimeLibs
            ++ (
              l.flatten (
                l.map
                (name: getCrateOption name "runtimeLibs")
                allCrateNames
              )
            );
        in {
          packages = {};
          devShell = import ./functions/mkDevshellFromRaw.nix {
            inherit lib runtimeLibs rawShell;
            shellToolchain = nci.toolchains.mkShell pkgs;
          };
          inherit docs;
        })
        projectsWithLock;
    in {
      nci.toolchains = {
        mkBuild = l.mkDefault (pkgs: (toolchainsFn pkgs).build);
        mkShell = l.mkDefault (pkgs: (toolchainsFn pkgs).shell);
      };

      nci.outputs =
        # crates will override project outputs if they have the same names
        # TODO: should probably warn the user here if that's the case
        projectsOutputs // (l.filterAttrs (name: attrs: attrs != null) crateOutputs);

      nci.lib = nci-lib;

      apps =
        l.optionalAttrs
        (l.length (l.attrNames projectsWithoutLock) > 0)
        {
          generate-lockfiles.program = toString (import ./functions/mkGenerateLockfilesApp.nix {
            inherit pkgs lib;
            projects = projectsWithoutLock;
            buildToolchain = nci.toolchains.mkBuild pkgs;
            source = systemlessNci.source;
          });
        };

      # export checks, packages and devshells for crates that have `export` set to `true`
      checks = l.filterAttrs (_: out: out != null) (l.listToAttrs (l.flatten (
        l.mapAttrsToList
        (
          name: out:
            if l.hasAttr name projectsWithLock
            then
              # skip this since projects don't define check outputs
              l.nameValuePair
              (getCrateName name)
              null
            else [
              (
                l.nameValuePair
                "${getCrateName name}-tests"
                (l.mkDefault out.check)
              )
              (
                l.nameValuePair
                "${getCrateName name}-clippy"
                (l.mkDefault out.clippy)
              )
            ]
        )
        outputsToExport
      )));
      packages = l.listToAttrs (l.flatten (
        l.mapAttrsToList
        (
          name: out:
            l.mapAttrsToList
            (
              profile: package:
                l.nameValuePair
                "${getCrateName name}-${profile}"
                (l.mkDefault package)
            )
            out.packages
        )
        outputsToExport
      ));
      devShells =
        l.mapAttrs'
        (
          name: out:
            l.nameValuePair
            (getCrateName name)
            (l.mkDefault out.devShell)
        )
        outputsToExport;

      # numtide devshell integration
      devshells = let
        addDevOutputs = xs: lib.concatLists (map (p: [(l.getDev p) p]) xs);
        collectEnv = devShell:
          [
            {
              name = "PKG_CONFIG_PATH";
              prefix = "$DEVSHELL_DIR/lib/pkgconfig";
            }
            {
              name = "LD_LIBRARY_PATH";
              prefix = "$DEVSHELL_DIR/lib";
            }
          ]
          ++ (l.mapAttrsToList (k: v: {
            name = k;
            value = v;
          }) (devShell.env or []));
        shellToolchain = config.nci.toolchains.mkShell pkgs;
        numtideDevshellFor = outputs: name: cfg:
          l.optional (cfg.numtideDevshell != null) {
            ${cfg.numtideDevshell} = {
              packagesFrom = [shellToolchain];
              packages =
                [shellToolchain]
                ++ addDevOutputs (outputs.${name}.devShell.packages or []);
              env = collectEnv outputs.${name}.devShell;
            };
          };
      in
        l.mkMerge (
          l.concatLists (
            l.mapAttrsToList (numtideDevshellFor projectsOutputs) config.nci.projects
            ++ l.mapAttrsToList (numtideDevshellFor crateOutputs) config.nci.crates
          )
        );
    };
  };
}
