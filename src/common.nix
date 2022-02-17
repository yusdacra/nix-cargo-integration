{ memberName ? null
, isRootMember ? false
, enablePreCommitHooks ? false
, cargoToml ? null
, workspaceMetadata ? null
, overrides ? { }
, dependencies ? [ ]
, sources
, system
, ...
}@attrs:
let
  # Extract the metadata we will need.
  cargoPkg = cargoToml.package or (throw "No package field found in the provided Cargo.toml.");
  _packageMetadata = cargoPkg.metadata.nix or { };
  packageMetadata = _packageMetadata // ((overrides.packageMetadata or (_: { })) _packageMetadata);
  desktopFileMetadata = packageMetadata.desktopFile or null;

  lib = attrs.lib // (attrs.lib.mkDbg "${cargoPkg.name}-${cargoPkg.version}: ");

  # This is named "prevRoot" since we will override it later on.
  prevRoot =
    let p = attrs.root or (throw "root must be specified"); in
    lib.dbgX "prev root was" p;

  overrideData = { inherit cargoPkg packageMetadata sources system memberName cargoToml; root = prevRoot; };

  # Helper function to create a package set; might be useful for users
  makePkgs =
    { toolchainChannel ? "stable"
    , override ? (_: _: { })
    }:
    import ./nixpkgs.nix {
      inherit system sources lib override toolchainChannel;
      overrideData = overrideData // { inherit toolchainChannel; };
    };

  # Create the package set we will use
  pkgs = makePkgs {
    override = overrides.pkgs or (_: _: { });
    toolchainChannel =
      let
        rustToolchain = root + "/rust-toolchain";
        rustTomlToolchain = root + "/rust-toolchain.toml";
      in
      if builtins.pathExists rustToolchain
      then rustToolchain
      else if builtins.pathExists rustTomlToolchain
      then rustTomlToolchain
      else workspaceMetadata.toolchain or packageMetadata.toolchain or "stable";
  };
  _lib = lib // pkgs.nciUtils;
  overrideDataPkgs = overrideData // { inherit pkgs; };

  l = _lib;

  # Override the root here. This is usually useless, but better to provide a way to do it anyways.
  # This *can* causes inconsistencies related to overrides (eg. if a dep is in the new root and not in the old root).
  root =
    let p = (overrides.root or (_: root: root)) overrideDataPkgs prevRoot; in
    l.dbgX "root is" p;

  # The C compiler that will be put in the env, and whether or not to put the C compiler's bintools in the env
  cCompiler = l.resolveToPkg (workspaceMetadata.cCompiler or packageMetadata.cCompiler or "gcc");
  useCCompilerBintools = workspaceMetadata.useCCompilerBintools or packageMetadata.useCCompilerBintools or true;

  # Libraries that will be put in $LD_LIBRARY_PATH
  runtimeLibs = l.resolveToPkgs ((workspaceMetadata.runtimeLibs or [ ]) ++ (packageMetadata.runtimeLibs or [ ]));

  overrideDataCrates = overrideDataPkgs // { inherit cCompiler runtimeLibs root; };

  # Collect crate overrides
  crateOverrides =
    let
      # Get the names of all our dependencies. This is done so that we can filter out unneeded overrides.
      # TODO: ideally this would only include the deps of the crate we are currently building, not all deps in Cargo.lock
      depNames = l.map (dep: dep.name) dependencies;
      baseRaw = l.makeCrateOverrides {
        inherit cCompiler useCCompilerBintools;
        crateName = cargoPkg.name;
        rawTomlOverrides =
          l.foldl'
            l.recursiveUpdate
            (l.genAttrs depNames (name: (_: { })))
            [ (workspaceMetadata.crateOverride or { }) (packageMetadata.crateOverride or { }) ];
      };
      # Filter out unneeded overrides, using the dep names we got earlier.
      base = l.filterAttrs (n: _: l.any (depName: n == depName) depNames) baseRaw;
    in
    base // ((overrides.crateOverrides or (_: _: { })) overrideDataCrates base);
  # "empty" crate overrides; we override an empty attr set to see what values the override changes.
  crateOverridesEmpty = l.mapAttrsToList (_: v: v { }) crateOverrides;
  # Get a field from all overrides in "empty" crate overrides and flatten them. Mainly used to collect (native) build inputs.
  crateOverridesGetFlattenLists = attrName: l.unique (l.flatten (l.map (v: v.${attrName} or [ ]) crateOverridesEmpty));
  noPropagatedEnvOverrides = l.removePropagatedEnv crateOverrides;
  # Combine all crate overrides into one big override function, except the main crate override
  crateOverridesCombined =
    let
      filteredOverrides = l.removeAttrs noPropagatedEnvOverrides [ cargoPkg.name ];
      func = prev: prev // (l.pipe prev (
        l.map
          (ov: (old: old // (ov old)))
          (l.attrValues filteredOverrides)
      ));
    in
    l.dbgXY "combined overrides diff" (func { }) func;
  # The main crate override is taken here
  mainBuildOverride =
    let ov = prev: prev // ((noPropagatedEnvOverrides.${cargoPkg.name} or (_: { })) prev); in
    l.dbgXY "main override diff" (ov { }) ov;

  # TODO: try to convert cargo maintainers to nixpkgs maintainers
  meta = {
    platforms = [ system ];
  } // (l.optionalAttrs (l.hasAttr "license" cargoPkg) {
    license = l.licenses."${l.cargoLicenseToNixpkgs cargoPkg.license}";
  }) // (l.putIfHasAttr "description" cargoPkg)
  // (l.putIfHasAttr "homepage" cargoPkg)
  // (l.putIfHasAttr "longDescription" packageMetadata);

  # Create the base config that will be overrided.
  # nativeBuildInputs, buildInputs, and env vars are collected here and they will be used in naersk and devshell.
  baseConfig = {
    inherit
      meta
      cCompiler
      pkgs
      memberName
      system
      root
      prevRoot
      sources
      cargoPkg
      cargoToml
      workspaceMetadata
      packageMetadata
      desktopFileMetadata
      runtimeLibs;

    # Collect build inputs.
    buildInputs =
      l.resolveToPkgs
        ((workspaceMetadata.buildInputs or [ ])
          ++ (packageMetadata.buildInputs or [ ]));
    # Collect native build inputs.
    nativeBuildInputs =
      l.resolveToPkgs
        ((workspaceMetadata.nativeBuildInputs or [ ])
          ++ (packageMetadata.nativeBuildInputs or [ ]));
    # Collect the env vars. The priority is as follows:
    # package metadata > workspace metadata
    env = (workspaceMetadata.env or { }) // (packageMetadata.env or { });

    # Collect override environment vars and (native) build inputs.
    # This is collected seperately because build will already use overrides,
    # using these in build would cause problems because every drv would get a copy
    # of these inputs.
    overrideBuildInputs = crateOverridesGetFlattenLists "buildInputs";
    overrideNativeBuildInputs = crateOverridesGetFlattenLists "nativeBuildInputs";
    overrideEnv = l.foldl' l.recursiveUpdate { } (l.map (v: v.propagatedEnv or { }) crateOverridesEmpty);

    # Put the overrides that other files may use (eg. build.nix, shell.nix).
    overrides = {
      shell = overrides.shell or (_: _: { });
      build = overrides.build or (_: _: { });
    };

    # nci private attributes. can change at any time!
    internal = {
      lib = l;

      inherit
        useCCompilerBintools
        crateOverrides
        crateOverridesEmpty
        crateOverridesCombined
        noPropagatedEnvOverrides
        isRootMember
        mainBuildOverride
        crateOverridesGetFlattenLists
        makePkgs;

      # Whether a desktop file should be added to the resulting package.
      mkDesktopFile = desktopFileMetadata != null;
      # Generate a desktop item config using provided package name
      # and information from the package's `Cargo.toml`.
      mkDesktopItemConfig = pkgName: {
        name = pkgName;
        exec = packageMetadata.executable or pkgName;
        comment = desktopFileMetadata.comment or meta.description or "";
        desktopName = desktopFileMetadata.name or pkgName;
      } // (
        if l.hasAttr "icon" desktopFileMetadata
        then
          let
            # If icon path starts with relative path prefix, make it absolute using root as base
            # Otherwise treat it as an absolute path
            makeIcon = icon:
              if l.hasPrefix "./" icon
              then root + "/${l.removePrefix "./" icon}"
              else icon;
          in
          { icon = makeIcon desktopFileMetadata.icon; }
        else { }
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
    } // l.optionalAttrs
      (
        workspaceMetadata.preCommitHooks.enable
          or packageMetadata.preCommitHooks.enable
          or enablePreCommitHooks
      )
      {
        preCommitChecks = pkgs.makePreCommitHooks {
          src = root;
          hooks = {
            rustfmt.enable = true;
            nixpkgs-fmt.enable = true;
          };
        };
      };
  };
in
(baseConfig // ((overrides.common or (_: { })) baseConfig))
