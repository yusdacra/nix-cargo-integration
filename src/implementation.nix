{
  self,
  lib,
  ...
} @ args: let
  l = lib // builtins;
  inp = args.config.nci._inputs;
in {
  config = {
    perSystem = {
      config,
      pkgs,
      ...
    }: let
      d2n = config.dream2nix;
      nci = config.nci;

      getCrateName = currentName: let
        newName = nci.crates.${currentName}.renameTo or null;
      in
        if newName != null
        then newName
        else currentName;

      outputsToExport =
        l.filterAttrs
        (
          name: out:
            nci.crates.${name}.export or nci.export
        )
        nci.outputs;

      projectsChecked =
        l.mapAttrs
        (name: import ./functions/warnIfNoLock.nix self)
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
        path = toString self;
      };
    in {
      nci.toolchains = {
        build = l.mkDefault toolchains.build;
        shell = l.mkDefault toolchains.shell;
      };

      dream2nix.inputs."nci" = {
        source = self;
        projects =
          l.mapAttrs
          (name: project: {
            inherit (project) relPath;
            subsystem = "rust";
            translator = "cargo-lock";
            builder = "crane";
          })
          projectsWithLock;
        packageOverrides = let
          crateOverridesList =
            l.mapAttrsToList
            (name: crate: [
              (l.nameValuePair name crate.overrides)
              (l.nameValuePair "${name}-deps" crate.depsOverrides)
            ])
            nci.crates;
          crateOverrides =
            l.listToAttrs (l.flatten crateOverridesList);
        in
          crateOverrides
          // {
            "^.*".set-toolchain.overrideRustToolchain = _: {
              cargo = nci.toolchains.build;
              rustc = nci.toolchains.build;
            };
          }
          // l.optionalAttrs (nci.stdenv != null) {
            "^.*".set-stdenv.override = _: {
              stdenv = nci.stdenv;
            };
          };
      };

      nci.outputs = let
        crates = l.filterAttrs (name: attrs: attrs != null) (
          l.mapAttrs
          (
            name: package: let
              runtimeLibs = nci.crates.${name}.runtimeLibs or [];
            in
              if package ? override
              then {
                packages = import ./functions/mkPackagesFromRaw.nix {
                  inherit pkgs runtimeLibs;
                  profiles = nci.crates.${name}.profiles or nci.profiles;
                  rawPkg = package;
                };
                devShell = import ./functions/mkDevshellFromRaw.nix {
                  inherit lib runtimeLibs;
                  rawShell = d2n.outputs."nci".devShells.${name};
                  shellToolchain = nci.toolchains.shell;
                };
              }
              else null
          )
          d2n.outputs."nci".packages
        );
      in
        (
          l.mapAttrs
          (name: project: let
            allCrateNames = import ./functions/getProjectCrates.nix {
              inherit lib;
              path = "${toString self}/${project.relPath}";
            };
          in {
            packages = {};
            devShell = import ./functions/mkDevshellFromRaw.nix {
              inherit lib;
              runtimeLibs = l.flatten (
                l.map
                (name: nci.crates.${name}.runtimeLibs or [])
                allCrateNames
              );
              rawShell = import "${inp.dream2nix}/src/subsystems/rust/builders/devshell.nix" {
                inherit lib;
                inherit (pkgs) libiconv mkShell;
                name = "${name}-devshell";
                drvs =
                  l.map
                  (name: d2n.outputs."nci".packages.${name})
                  allCrateNames;
              };
              shellToolchain = nci.toolchains.shell;
            };
          })
          nci.projects
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
          });
        };
      packages = l.listToAttrs (l.flatten (
        l.mapAttrsToList
        (
          name: out:
            l.mapAttrsToList
            (
              profile: package:
                l.nameValuePair "${getCrateName name}-${profile}" package
            )
            out.packages
        )
        outputsToExport
      ));
      devShells =
        l.mapAttrs'
        (
          name: out:
            l.nameValuePair (getCrateName name) out.devShell
        )
        outputsToExport;
    };
  };
}
