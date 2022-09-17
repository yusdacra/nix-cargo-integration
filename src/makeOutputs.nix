{
  # an NCI library
  lib,
  # NCI flake sources
  sources,
}:
# Creates flake outputs by searching the supplied root for a
# workspace / package and using `Cargo.toml`s for configuration.
{
  # Path to the root of a cargo workspace or crate
  root,
  # Systems to generate outputs for
  systems ? lib.defaultSystems,
  # All overrides
  overrides ? {},
  # All crate namespaced overrides
  perCrateOverrides ? {},
  # nixpkgs overlays to use for the package set
  pkgsOverlays ? [],
  ...
} @ attrs: let
  l = lib // builtins;

  # Helper function to import a Cargo.toml from a root.
  importCargoTOML = root: l.fromTOML (l.readFile "${toString root}/Cargo.toml");

  # Import the "main" Cargo.toml we will use. This Cargo.toml can either be a workspace manifest, or a package manifest.
  cargoToml = importCargoTOML (l.dbg "root at: ${toString root}" root);

  # This is the "root package" that might or might not exist.
  # For example, the manifest might both specify a workspace *and* have a package in it.
  rootPkg = cargoToml.package or null;
  # Get the workspace attributes if it exists.
  workspaceToml = cargoToml.workspace or null;
  # Get the workspace members if they exist.
  workspaceMembers = workspaceToml.members or [];
  # Process any globs that might be in workspace members.
  globbedWorkspaceMembers = l.flatten (
    l.map
    (
      memberName: let
        components = l.splitString "/" memberName;
      in
        if l.last components == "*"
        then let
          parentDirRel = l.concatStringsSep "/" (l.init components);
          parentDir = "${toString root}/${parentDirRel}";
          dirs = l.readDir parentDir;
        in
          l.mapAttrsToList
          (name: _: "${parentDirRel}/${name}")
          (l.filterAttrs (_: type: type == "directory") dirs)
        else memberName
    )
    workspaceMembers
  );
  # Get and import the members' Cargo.toml files if we are in a workspace.
  members =
    l.genAttrs
    (
      l.dbg
      "workspace members: ${l.concatStringsSep ", " globbedWorkspaceMembers}"
      globbedWorkspaceMembers
    )
    (name: importCargoTOML "${toString root}/${name}");

  # Get the metadata we will use from the root package attributes if it exists.
  rootPackageMetadata =
    l.recursiveUpdate
    (rootPkg.metadata.nix or {})
    (perCrateOverrides.${rootPkg.name}.config or {});
  # Get the metadata we will use from the workspace attributes if it exists.
  workspaceMetadata =
    l.recursiveUpdate
    (workspaceToml.metadata.nix or {})
    (overrides.workspaceConfig or {});

  # Decide which systems we will generate outputs for. This can be overrided.
  systems =
    attrs.systems
    or workspaceMetadata.systems
    or rootPackageMetadata.systems
    or l.defaultSystems;

  # helper function to create a packages set for NCI
  mkPkgsSet = system:
    import ./pkgs-set.nix {
      inherit root system sources;
      toolchainChannel = let
        rustToolchain = "${toString root}/rust-toolchain";
        rustTomlToolchain = "${toString root}/rust-toolchain.toml";
      in
        if l.pathExists rustToolchain
        then rustToolchain
        else if l.pathExists rustTomlToolchain
        then rustTomlToolchain
        else workspaceMetadata.toolchain or rootPackageMetadata.toolchain or "stable";
      overlays = pkgsOverlays;
      lib = l;
    };
  # systems mapped to package sets
  pkgsSets = l.genAttrs systems mkPkgsSet;

  # common creation function mapped to systems, we do this to memoize some stuff
  mkCommons =
    l.genAttrs
    systems
    (
      system:
        import ./common.nix {
          pkgsSet = pkgsSets.${system};
          inherit
            lib
            workspaceMetadata
            root
            overrides
            perCrateOverrides
            sources
            ;
        }
    );
  # Helper function to construct a "commons" from a member name, the cargo toml, and the system.
  mkCommon = memberName: cargoToml: isRootMember: system:
    mkCommons.${system} {
      inherit
        memberName
        cargoToml
        isRootMember
        ;
    };

  mergeShells = shellAttrs: let
    shells = l.attrValues shellAttrs;
    baseShell = l.head shells;
    otherShells = l.drop 1 shells;
  in
    l.foldl'
    (all: el: all.combineWith el)
    baseShell
    otherShells;

  # Whether the package is declared in the same `Cargo.toml` as the workspace.
  isRootMember = (l.length workspaceMembers) > 0;
  # Generate "commons" for the "root package".
  rootCommons =
    l.thenOrNull
    (rootPkg != null)
    (l.genAttrs systems (mkCommon null cargoToml isRootMember));
  # Generate "commons" for all members.
  memberCommons' =
    l.mapAttrsToList
    (name: value: l.genAttrs systems (mkCommon name value false))
    members;
  # Combine the member "commons" and the "root package" "commons".
  allCommons' =
    memberCommons' ++ (l.optional (rootCommons != null) rootCommons);

  # Generate outputs from all "commons".
  allOutputs' = l.flatten (
    l.map
    (
      l.mapAttrsToList
      (_: common: import ./makeOutput.nix {inherit common;})
    )
    allCommons'
  );
  # Recursively combine all outputs we have.
  combinedOutputs = l.foldAttrs lib.recursiveUpdate {} allOutputs';
  # Create the "final" output set.
  # This also creates the devshell, puts in pre commit checks if the user has enabled it,
  # and changes default outputs according to `defaultOutputs`.
  defaultOutputs =
    workspaceMetadata.outputs.defaults
    or rootPackageMetadata.outputs.defaults
    or {};
  finalOutputs =
    combinedOutputs
    // {
      devShells =
        l.mapAttrs
        (
          _: devshells:
            devshells // {default = mergeShells devshells;}
        )
        combinedOutputs.devShells;
    }
    // l.optionalAttrs (l.hasAttr "package" defaultOutputs) {
      packages =
        l.mapAttrs
        (
          _: packages:
            packages // {default = packages.${defaultOutputs.package};}
        )
        combinedOutputs.packages;
    }
    // l.optionalAttrs (l.hasAttr "app" defaultOutputs) {
      apps =
        l.mapAttrs
        (
          _: apps:
            apps // {default = apps.${defaultOutputs.app};}
        )
        combinedOutputs.apps;
    };
  checkedOutputs =
    l.warnIf
    (!(l.hasAttr "packages" finalOutputs) && !(l.hasAttr "apps" finalOutputs))
    "No packages found. Did you add the `package.metadata.nix` section to a `Cargo.toml` and added `build = true` under it?"
    finalOutputs;
in
  checkedOutputs
