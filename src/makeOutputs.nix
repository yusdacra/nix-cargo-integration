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
  # All overrides
  overrides ? {},
  # All crate namespaced overrides
  perCrateOverrides ? {},
  # Rename outputs in flake structure
  renameOutputs ? {},
  # Default output for apps / packages
  defaultOutputs ? {},
  # Any valid dream2nix builder for Rust
  builder ? "crane",
  # Whether to enable pre commit hooks
  enablePreCommitHooks ? false,
  # Systems to generate outputs for
  systems ? lib.defaultSystems,
  # nixpkgs overlays to use for the package set
  pkgsOverlays ? [],
  ...
} @ attrs: let
  l = lib // builtins;

  # Helper function to import a Cargo.toml from a root.
  importCargoTOML = root: l.fromTOML (l.readFile "${toString root}/Cargo.toml");

  # Import the "main" Cargo.toml we will use. This Cargo.toml can either be a workspace manifest, or a package manifest.
  cargoToml = importCargoTOML (l.dbg "root at: ${toString root}" root);
  # Import the Cargo.lock file.
  cargoLockPath = "${toString root}/Cargo.lock";
  cargoLock =
    if l.pathExists cargoLockPath
    then l.fromTOML (l.readFile cargoLockPath)
    else throw "A Cargo.lock file must be present, please make sure it's at least staged in git.";

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
  packageMetadata = rootPkg.metadata.nix or null;
  # Get the metadata we will use from the workspace attributes if it exists.
  workspaceMetadata = workspaceToml.metadata.nix or null;

  # Get all the dependencies in Cargo.lock.
  dependencies = cargoLock.package;
  # Decide which systems we will generate outputs for. This can be overrided.
  systems =
    attrs.systems
    or workspaceMetadata.systems
    or packageMetadata.systems
    or l.defaultSystems;

  # Helper function to construct a "commons" from a member name, the cargo toml, and the system.
  mkCommon = memberName: cargoToml: isRootMember: system:
    import ./common.nix {
      inherit
        lib
        dependencies
        memberName
        members
        cargoToml
        workspaceMetadata
        system
        root
        overrides
        perCrateOverrides
        sources
        enablePreCommitHooks
        isRootMember
        builder
        pkgsOverlays
        ;
    };

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

  # Helper function used to "combine" two "commons".
  updateCommon = prev: final: let
    combinedLists =
      l.genAttrs
      [
        "runtimeLibs"
        "buildInputs"
        "nativeBuildInputs"
        "overrideBuildInputs"
        "overrideNativeBuildInputs"
      ]
      (name: l.concatAttrLists prev final name);
  in
    prev
    // final
    // combinedLists
    // {
      env = (prev.env or {}) // final.env;
      overrideEnv = (prev.overrideEnv or {}) // final.overrideEnv;
      overrides = {
        shell = common: prevShell: let
          overrides = [
            ((prev.overrides.shell or (_: _: {})) common)
            ((final.overrides.shell or (_: _: {})) common)
          ];
        in
          l.applyOverrides prevShell overrides;
      };
    };
  # Recursively go through each "commons", and "combine" them. We will use this for our devshell.
  commonsCombined =
    l.mapAttrs
    (_: l.foldl' updateCommon {})
    (
      l.foldl'
      (acc: ele: l.mapAttrs (n: v: acc.${n} ++ [v]) ele)
      (l.genAttrs systems (_: []))
      allCommons'
    );

  # Generate outputs from all "commons".
  allOutputs' = l.flatten (
    l.map
    (
      l.mapAttrsToList
      (_: common: import ./makeOutput.nix {inherit common renameOutputs;})
    )
    allCommons'
  );
  # Recursively combine all outputs we have.
  combinedOutputs = l.foldAttrs lib.recursiveUpdate {} allOutputs';
  # Create the "final" output set.
  # This also creates the devshell, puts in pre commit checks if the user has enabled it,
  # and changes default outputs according to `defaultOutputs`.
  finalOutputs =
    combinedOutputs
    // {
      devShell = l.mapAttrs (_: import ./shell.nix) commonsCombined;
      checks = l.recursiveUpdate (combinedOutputs.checks or {}) (
        l.mapAttrs
        (
          _: common:
            l.optionalAttrs (l.hasAttr "preCommitChecks" common) {
              "preCommitChecks" = common.preCommitChecks;
            }
        )
        commonsCombined
      );
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
