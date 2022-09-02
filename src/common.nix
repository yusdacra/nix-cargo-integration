{
  # System we want to use
  system,
  # NCI sources
  sources,
  # The member name for this package, if it is in a workspace
  memberName ? null,
  # Whether this package declared in the same
  # `Cargo.toml` with the workspace declaration
  isRootMember ? false,
  # `Cargo.toml` of this package, as a Nix attribute set
  cargoToml ? null,
  # Workspace metadata for this package, if it is in one, as a Nix attribute set
  workspaceMetadata ? null,
  # Overrides to use
  overrides ? {},
  # Crate namespaced overrides
  perCrateOverrides ? {},
  # Dependency list taken directly from this package's `Cargo.lock`
  dependencies ? [],
  # nixpkgs overlays to use for the package set
  pkgsOverlays ? [],
  # Whether to enable pre commit hooks
  enablePreCommitHooks ? false,
  ...
} @ attrs: let
  # Extract the metadata we will need.
  cargoPkg = cargoToml.package or (throw "No package field found in the provided Cargo.toml.");
  _packageMetadata = cargoPkg.metadata.nix or {};
  packageMetadata = _packageMetadata // ((perCrateOverrides.${cargoPkg.name}.packageMetadata or (_: {})) _packageMetadata);
  desktopFileMetadata = packageMetadata.desktopFile or null;

  l = attrs.lib // (attrs.lib.mkDbg "${cargoPkg.name}-${cargoPkg.version}: ");

  # The builder we will use
  builder = l.dbgX "using builder" attrs.builder;

  # The root we will use
  root = let
    p = attrs.root or (throw "root must be specified");
  in
    l.dbgX "root is" p;

  overrideData = {
    inherit cargoPkg packageMetadata sources system memberName cargoToml root;
  };

  # The toolchain channel we will use
  toolchainChannel = let
    rustToolchain = "${toString root}/rust-toolchain";
    rustTomlToolchain = "${toString root}/rust-toolchain.toml";
  in
    if l.pathExists rustToolchain
    then rustToolchain
    else if l.pathExists rustTomlToolchain
    then rustTomlToolchain
    else workspaceMetadata.toolchain or packageMetadata.toolchain or "stable";

  # The NCI package set we will use
  nci-pkgs = import ./pkgs-set.nix {
    inherit root system sources toolchainChannel;
    overlays = pkgsOverlays;
    lib = l;
  };

  overrideDataPkgs =
    overrideData
    // {
      inherit (nci-pkgs) pkgs rustToolchain;
    };

  overridedCCompiler = (overrides.cCompiler or (_: {})) overrideDataPkgs;
  # The C compiler that will be put in the env
  cCompiler =
    (
      if overridedCCompiler ? cCompiler
      then overridedCCompiler
      else if overridedCCompiler != {}
      then {cCompiler = overridedCCompiler;}
      else {}
    )
    .cCompiler
    or (nci-pkgs.utils.resolveToPkg (
      workspaceMetadata.cCompiler
      or packageMetadata.cCompiler
      or "gcc"
    ));
  # Whether or not to put the C compiler's bintools in the env
  useCCompilerBintools =
    overridedCCompiler.useCCompilerBintools
    or workspaceMetadata.useCCompilerBintools
    or packageMetadata.useCCompilerBintools
    or true;

  # Libraries that will be put in $LD_LIBRARY_PATH
  runtimeLibs = nci-pkgs.utils.resolveToPkgs (
    l.concatAttrLists workspaceMetadata packageMetadata "runtimeLibs"
  );

  overrideDataCrates = overrideDataPkgs // {inherit cCompiler runtimeLibs root;};

  # Collect crate overrides
  crateOverrides = let
    # Get the names of all our dependencies. This is done so that we can filter out unneeded overrides.
    # TODO: ideally this would only include the deps of the crate we are currently building, not all deps in Cargo.lock
    depNames = (l.map (dep: dep.name) dependencies) ++ ["${cargoPkg.name}-deps"];
    baseRaw = nci-pkgs.utils.makeCrateOverrides {
      inherit cCompiler useCCompilerBintools;
      rawTomlOverrides =
        l.foldl'
        l.recursiveUpdate
        {}
        [(workspaceMetadata.crateOverride or {}) (packageMetadata.crateOverride or {})];
    };
    # Filter out unneeded overrides, using the dep names we got earlier.
    base = l.filterAttrs (n: _: l.any (depName: n == depName) depNames) baseRaw;
  in
    base
    // (
      (overrides.crateOverrides or overrides.crates or (_: _: {}))
      overrideDataCrates
      base
    );
  # "empty" crate overrides; we override an empty attr set to see what values the override changes.
  crateOverridesEmpty = l.mapAttrsToList (_: v: v {}) crateOverrides;
  # Get a field from all overrides in "empty" crate overrides and flatten them.
  # Mainly used to collect (native) build inputs.
  crateOverridesGetFlattenLists = attrName:
    l.unique (
      l.flatten (l.map (v: v.${attrName} or []) crateOverridesEmpty)
    );
  noPropagatedEnvOverrides = l.removePropagatedEnv crateOverrides;
  mainNames =
    l.unique
    (
      [cargoPkg.name]
      ++ (
        l.map
        (toml: toml.package.name)
        (l.attrValues attrs.members)
      )
    );
  # Combine all crate overrides into one big override function, except the main crate override
  crateOverridesCombined = let
    noMainOverrides = l.removeAttrs noPropagatedEnvOverrides mainNames;
    func = prev: l.computeOverridesResult prev (l.attrValues noMainOverrides);
  in
    l.dbgXY "combined overrides diff" (func {}) func;
  # Combine all main dep overrides
  mainOverrides = let
    _mainOverrides = l.getAttrs mainNames noPropagatedEnvOverrides;
    func = prev: l.computeOverridesResult prev (l.attrValues _mainOverrides);
  in
    l.dbgXY "main overrides diff" (func {}) func;

  # TODO: try to convert cargo maintainers to nixpkgs maintainers
  meta =
    {
      platforms = [system];
    }
    // (l.optionalAttrs (l.hasAttr "license" cargoPkg) {
      license = l.licenses."${l.cargoLicenseToNixpkgs cargoPkg.license}";
    })
    // (l.putIfHasAttr "description" cargoPkg)
    // (l.putIfHasAttr "homepage" cargoPkg)
    // (l.putIfHasAttr "longDescription" packageMetadata);

  # Create the base config that will be overrided.
  # nativeBuildInputs, buildInputs, and env vars are collected here and they will be used in build / shell.
  baseConfig = {
    inherit (nci-pkgs) pkgs rustToolchain;
    inherit
      builder
      root
      sources
      system
      memberName
      cargoPkg
      cargoToml
      workspaceMetadata
      packageMetadata
      desktopFileMetadata
      meta
      cCompiler
      runtimeLibs
      ;

    features = packageMetadata.features or {};

    # Collect build inputs.
    buildInputs = nci-pkgs.utils.resolveToPkgs (
      l.concatAttrLists workspaceMetadata packageMetadata "buildInputs"
    );
    # Collect native build inputs.
    nativeBuildInputs = nci-pkgs.utils.resolveToPkgs (
      l.concatAttrLists workspaceMetadata packageMetadata "nativeBuildInputs"
    );

    # Collect the env vars. The priority is as follows:
    # package metadata > workspace metadata
    env = let
      allEnvs = (workspaceMetadata.env or {}) // (packageMetadata.env or {});
    in
      l.mapAttrs (_: value: nci-pkgs.utils.evalPkgs value) allEnvs;

    # Collect override environment vars and (native) build inputs.
    # This is collected seperately because build will already use overrides,
    # using these in build would cause problems because every drv would get a copy
    # of these inputs.
    overrideBuildInputs = crateOverridesGetFlattenLists "buildInputs";
    overrideNativeBuildInputs = crateOverridesGetFlattenLists "nativeBuildInputs";
    overrideEnv = l.foldl' l.recursiveUpdate {} (l.map (v: v.propagatedEnv or {}) crateOverridesEmpty);

    # Put the overrides that other files may use (eg. build.nix, shell.nix).
    overrides = {
      shell = overrides.shell or (_: _: {});
      build = overrides.build or (_: _: {});
    };

    # nci private attributes. can change at any time without warning!
    internal =
      {
        lib = l;

        inherit
          nci-pkgs
          useCCompilerBintools
          crateOverrides
          crateOverridesEmpty
          crateOverridesCombined
          mainOverrides
          noPropagatedEnvOverrides
          isRootMember
          crateOverridesGetFlattenLists
          ;

        # Whether a desktop file should be added to the resulting package.
        mkDesktopFile = desktopFileMetadata != null;
        # Generate a desktop item config using provided package name
        # and information from the package's `Cargo.toml`.
        mkDesktopItemConfig = pkgName:
          {
            name = pkgName;
            exec = packageMetadata.executable or pkgName;
            comment = desktopFileMetadata.comment or meta.description or "";
            desktopName = desktopFileMetadata.name or pkgName;
          }
          // (
            if l.hasAttr "icon" desktopFileMetadata
            then let
              # If icon path starts with relative path prefix, make it absolute using root as base
              # Otherwise treat it as an absolute path
              makeIcon = icon:
                if l.hasPrefix "./" icon
                then "${toString root}/${l.removePrefix "./" icon}"
                else icon;
            in {icon = makeIcon desktopFileMetadata.icon;}
            else {}
          )
          // (l.putIfHasAttr "genericName" desktopFileMetadata)
          // (l.putIfHasAttr "categories" desktopFileMetadata);

        # Whether the binaries should be patched with the libraries inside
        # `runtimeLibs`.
        mkRuntimeLibsOv = (l.length runtimeLibs) > 0;
        # Utility for generating a script to patch binaries with libraries.
        mkRuntimeLibsScript = libs: ''
          for f in $out/bin/*; do
            patchelf --set-rpath "${libs}" "$f"
          done
        '';
      }
      // l.optionalAttrs
      (
        workspaceMetadata.preCommitHooks.enable
        or packageMetadata.preCommitHooks.enable
        or enablePreCommitHooks
      )
      {
        preCommitChecks = nci-pkgs.makePreCommitHooks {
          src = toString root;
          hooks = {
            rustfmt.enable = true;
            alejandra.enable = true;
          };
        };
      };
  };
in (baseConfig // ((overrides.common or (_: {})) baseConfig))
