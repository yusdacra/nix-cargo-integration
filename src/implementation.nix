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
    in {
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
          };
      };

      nci.outputs = l.filterAttrs (name: attrs: attrs != null) (
        l.mapAttrs
        (
          name: package:
            if package ? override
            then {
              packages = import ./functions/mkPackagesFromRaw.nix {
                inherit lib;
                profiles = nci.crates.${name}.profiles or nci.profiles;
                rawPkg = package;
              };
              devShell = import ./functions/mkDevshellFromRaw.nix {
                inherit lib;
                rawShell = d2n.outputs."nci".devShells.${name};
                shellToolchain = nci.toolchains.shell;
              };
            }
            else null
        )
        d2n.outputs."nci".packages
      );

      apps =
        l.optionalAttrs
        (l.length (l.attrNames projectsWithoutLock) > 0)
        {
          generate-lockfiles.program = toString (pkgs.writeScript "generate-lockfiles" ''
            function addToGit {
              if [ -d ".git" ]; then
                git add $1
              fi
            }
            ${
              l.concatMapStringsSep
              "\n"
              (
                project: ''
                  ${nci.toolchains.build}/bin/cargo generate-lockfile --manifest-path ${project.relPath}/Cargo.toml
                  addToGit ${project.relPath}/Cargo.lock
                ''
              )
              (l.attrValues projectsWithoutLock)
            }
          '');
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
