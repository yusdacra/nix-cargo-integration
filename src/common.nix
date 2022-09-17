{
  # Overrides to use
  overrides ? {},
  # Crate namespaced overrides
  perCrateOverrides ? {},
  # the NCI packages set
  pkgsSet,
  # the sources
  sources,
  # Workspace metadata for this package, if it is in one, as a Nix attribute set
  workspaceMetadata ? null,
  ...
} @ topAttrs: {
  # The member name for this package, if it is in a workspace
  memberName ? null,
  # Whether this package declared in the same
  # `Cargo.toml` with the workspace declaration
  isRootMember ? false,
  # `Cargo.toml` of this package, as a Nix attribute set
  cargoToml ? null,
  ...
}: let
  # Extract the metadata we will need.
  cargoPkg = cargoToml.package or (throw "No package field found in the provided Cargo.toml.");
  packageMetadata =
    l.recursiveUpdate
    (cargoPkg.metadata.nix or {})
    (perCrateOverrides.${cargoPkg.name}.config or {});

  l = topAttrs.lib // (topAttrs.lib.mkDbg "${cargoPkg.name}-${cargoPkg.version}: ");

  # The builder we will use
  builder = l.dbgX "using builder" (
    workspaceMetadata.builder
    or packageMetadata.builder
    or "crane"
  );

  # The root we will use
  root = let
    p = topAttrs.root or (throw "root must be specified");
  in
    l.dbgX "root is" p;

  overrideData = {
    inherit (pkgsSet) pkgs rustToolchain;
    pname = cargoPkg.name;
    version = cargoPkg.version;
  };

  # Collect crate overrides
  crateOverrides = let
    # Get the names of all our dependencies. This is done so that we can filter out unneeded overrides.
    baseRaw = pkgsSet.utils.makeTomlOverrides (
      l.foldl'
      l.recursiveUpdate
      {}
      [
        (workspaceMetadata.crateOverride or {})
        (packageMetadata.crateOverride or {})
      ]
    );
    userOverrides =
      (overrides.crateOverrides or overrides.crates or (_: _: {}))
      overrideData
      baseRaw;
    base =
      baseRaw
      // (
        l.mapAttrs
        (
          name: ov: (
            prev:
              l.computeOverridesResult
              prev
              [(baseRaw.${name} or (_: {})) ov]
          )
        )
        userOverrides
      );
  in
    base;
  noPropagatedEnvOverrides = l.removePropagatedEnv crateOverrides;

  # Put the overrides that other files may use (eg. build.nix, shell.nix).
  overrides =
    {
      shell = topAttrs.overrides.shell or (_: _: {});
      build = topAttrs.overrides.build or (_: _: {});
    }
    // (perCrateOverrides.${cargoPkg.name} or {});

  __cCompiler =
    workspaceMetadata.cCompiler
    or packageMetadata.cCompiler
    or {
      package = pkgsSet.pkgs.gcc;
      useCompilerBintools = true;
    };
  _cCompiler =
    if __cCompiler == null
    then null
    else if __cCompiler ? type && __cCompiler.type == "derivation"
    then {
      package = __cCompiler;
      useCompilerBintools = true;
    }
    else __cCompiler;
  cCompiler =
    if _cCompiler == null
    then null
    else {
      package = pkgsSet.utils.resolveToPkg _cCompiler.package;
      useCompilerBintools = _cCompiler.useCompilerBintools;
    };

  # Create the base config that will be overrided.
  # nativeBuildInputs, buildInputs, and env vars are collected here and they will be used in build / shell.
  baseConfig = {
    inherit overrides;
    inherit (pkgsSet) pkgs rustToolchain;

    # nci private attributes. can change at any time without warning!
    internal =
      {
        lib = l;

        runtimeLibs = pkgsSet.utils.resolveToPkgs (
          (workspaceMetadata.runtimeLibs or [])
          ++ (packageMetadata.runtimeLibs or [])
        );

        inherit
          pkgsSet
          crateOverrides
          noPropagatedEnvOverrides
          isRootMember
          builder
          root
          memberName
          cargoPkg
          cargoToml
          workspaceMetadata
          packageMetadata
          overrides
          sources
          cCompiler
          ;
      }
      // (
        l.optionalAttrs
        (
          workspaceMetadata.preCommitHooks.enable
          or packageMetadata.preCommitHooks.enable
          or false
        )
        {
          preCommitChecks = pkgsSet.makePreCommitHooks {
            src = toString root;
            hooks = {
              rustfmt.enable = true;
              alejandra.enable = true;
            };
          };
        }
      );
  };
in
  baseConfig
