{lib, ...} @ args: let
  l = lib // builtins;
  systemlessNci = args.config.nci;
  inp = systemlessNci._inputs;
in {
  config = {
    perSystem = {
      config,
      pkgs,
      ...
    }: let
      nci = config.nci;

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
      cratesToProjects = l.listToAttrs (l.flatten (
        l.mapAttrsToList
        (
          project: crates:
            l.map (crate: l.nameValuePair crate.name project) crates
        )
        projectsToCrates
      ));
      getCrateName = currentName: let
        newName = nci.crates.${currentName}.renameTo or null;
      in
        if newName != null
        then newName
        else currentName;

      outputsToExport =
        l.filterAttrs
        (
          name: out: let
            crateExport = nci.crates.${name}.export or null;
            projectExport = nci.projects.${cratesToProjects.${name} or name}.export;
          in
            if crateExport == null
            then projectExport
            else crateExport
        )
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
      toolchains = import ./functions/findRustToolchain.nix {
        inherit lib pkgs;
        inherit (inp) rust-overlay;
        inherit (nci) toolchainConfig;
        path = toString systemlessNci.source;
      };

      d2nOutputs = l.listToAttrs (l.flatten (
        l.mapAttrsToList
        (
          projName: project:
            l.map
            (crate: {
              name = crate.name;
              value = let
                crateCfg = nci.crates.${crate.name} or {};
              in
                inp.dream2nix.lib.evalModules {
                  packageSets.nixpkgs = pkgs;
                  modules = [
                    inp.dream2nix.modules.dream2nix.rust-cargo-lock
                    inp.dream2nix.modules.dream2nix.rust-crane
                    {
                      paths.projectRoot = project.path;
                      paths.projectRootFile = "flake.nix";
                      paths.package = "/${crate.path}";
                    }
                    project.drvConfig
                    (crateCfg.drvConfig or {})
                    {
                      deps.craneSource = inp.crane;
                      deps.cargo = nci.toolchains.build;

                      name = l.mkForce crate.name;
                      version = l.mkForce crate.version;

                      mkDerivation.src = l.mkForce project.path;

                      rust-crane.depsDrv = l.mkMerge [
                        project.depsDrvConfig
                        (crateCfg.depsDrvConfig or {})
                      ];
                    }
                  ];
                };
            })
            projectsToCrates.${projName}
        )
        projectsWithLock
      ));
    in {
      nci.toolchains = {
        build = l.mkDefault toolchains.build;
        shell = l.mkDefault toolchains.shell;
      };

      nci.outputs = let
        crates = l.filterAttrs (name: attrs: attrs != null) (
          l.mapAttrs
          (
            name: package: let
              project = nci.projects.${cratesToProjects.${name}} or {};
              crate = nci.crates.${name} or {};
              runtimeLibs =
                (project.runtimeLibs or []) ++ (crate.runtimeLibs or []);
              profiles =
                if crate.profiles == null
                then project.profiles
                else crate.profiles;
              targets =
                if crate.targets == null
                then project.targets
                else crate.targets;
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
                rawShell = package.devShell;
                shellToolchain = nci.toolchains.shell;
              };
              check = import ./functions/mkCheckOnlyPackage.nix packages.${crate.checkProfile};
            }
          )
          d2nOutputs
        );
      in
        (
          l.mapAttrs
          (name: project: let
            allCrateNames = l.map (crate: crate.name) projectsToCrates.${name};
          in {
            packages = {};
            devShell = import ./functions/mkDevshellFromRaw.nix {
              inherit lib;
              runtimeLibs =
                project.runtimeLibs
                ++ (
                  l.flatten (
                    l.map
                    (name: nci.crates.${name}.runtimeLibs or [])
                    allCrateNames
                  )
                );
              rawShell = import ./functions/mkDevshellFromDrvs.nix {
                inherit lib;
                inherit (pkgs) libiconv mkShell;
                name = "${name}-devshell";
                drvs =
                  l.map
                  (name: d2nOutputs.${name})
                  allCrateNames;
              };
              shellToolchain = nci.toolchains.shell;
            };
          })
          projectsWithLock
        )
        // crates;

      apps =
        l.optionalAttrs
        (l.length (l.attrNames projectsWithoutLock) > 0)
        {
          generate-lockfiles.program = toString (import ./functions/mkGenerateLockfilesApp.nix {
            inherit pkgs lib;
            projects = projectsWithoutLock;
            buildToolchain = nci.toolchains.build;
            source = systemlessNci.source;
          });
        };
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
    };
  };
}
