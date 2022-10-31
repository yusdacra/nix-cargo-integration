{
  # Overrides to use
  pkgConfig ? (_: {}),
  # the NCI packages set
  pkgsSet,
  # the sources
  sources,
  # Workspace metadata for this package, if it is in one, as a Nix attribute set
  workspaceMetadata ? null,
  ...
} @ topAttrs: let
  pkgConfig =
    if topAttrs.lib.isFunction topAttrs.pkgConfig
    then
      topAttrs.pkgConfig {
        inherit (pkgsSet) pkgs rustToolchain;
        config = workspaceMetadata;

        internal = {
          inherit
            pkgsSet
            sources
            workspaceMetadata
            ;
        };
      }
    else
      throw ''
        `pkgConfig` must be a function that receives one argument.
        Please refer to the documentation.
      '';
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
    packageMetadata =
      l.validatePkgConfig
      (l.dbgX "pkgConfig" (
        l.recursiveUpdate
        (cargoPkg.metadata.nix or {})
        (pkgConfig.${cargoPkg.name} or {})
      ));

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
    crateOverrides = pkgsSet.utils.processOverrides {
      ${cargoPkg.name} = packageMetadata.overrides or {};
      "${cargoPkg.name}-deps" = packageMetadata.depsOverrides or {};
    };

    _cCompiler = workspaceMetadata.cCompiler or packageMetadata.cCompiler;
    cCompiler =
      if _cCompiler.enable
      then {
        package = pkgsSet.utils.resolveToPkg _cCompiler.package;
        useCompilerBintools = _cCompiler.useCompilerBintools;
      }
      else null;

    runtimeLibs = pkgsSet.utils.resolveToPkgs (
      (workspaceMetadata.runtimeLibs or [])
      ++ (packageMetadata.runtimeLibs or [])
    );

    # Create the base config that will be overrided.
    # nativeBuildInputs, buildInputs, and env vars are collected here and they will be used in build / shell.
    baseConfig = {
      inherit (pkgsSet) pkgs rustToolchain;
      inherit cCompiler runtimeLibs;

      # nci private attributes. can change at any time without warning!
      internal =
        {
          lib = l;

          inherit
            pkgsSet
            crateOverrides
            isRootMember
            builder
            root
            memberName
            cargoPkg
            cargoToml
            workspaceMetadata
            packageMetadata
            sources
            cCompiler
            runtimeLibs
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
