{
  # Overrides to use
  overrides ? (_: {}),
  # the NCI packages set
  pkgsSet,
  # the sources
  sources,
  # Workspace metadata for this package, if it is in one, as a Nix attribute set
  workspaceMetadata ? null,
  ...
} @ topAttrs: let
  overrideData = {
    inherit (pkgsSet) pkgs rustToolchain;
    internal = {
      inherit
        pkgsSet
        sources
        workspaceMetadata
        ;
    };
  };
  allOverrides = overrides overrideData;
in
  {
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

    overrides = allOverrides.${cargoPkg.name} or {};

    packageMetadata =
      l.recursiveUpdate
      (cargoPkg.metadata.nix or {})
      (overrides.config or {});

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

    # Collect crate overrides
    crateOverrides = pkgsSet.utils.processOverrides (
      l.foldl' l.recursiveUpdate {} [
        (workspaceMetadata.crateOverrides or {})
        (packageMetadata.crateOverrides or {})
      ]
    );
    noPropagatedEnvOverrides = l.removePropagatedEnv crateOverrides;

    _cCompiler =
      workspaceMetadata.cCompiler
      or packageMetadata.cCompiler
      or {
        package = pkgsSet.pkgs.gcc;
        useCompilerBintools = true;
      };
    cCompiler =
      if
        l.isString _cCompiler
        || (_cCompiler ? type && _cCompiler.type == "derivation")
      then {
        package = _cCompiler;
        useCompilerBintools = true;
      }
      else if l.isAttrs _cCompiler
      then {
        package = pkgsSet.utils.resolveToPkg _cCompiler.package;
        useCompilerBintools = _cCompiler.useCompilerBintools;
      }
      else null;

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
