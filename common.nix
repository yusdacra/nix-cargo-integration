{ memberName ? null
, buildPlatform ? "naersk"
, enablePreCommitHooks ? false
, cargoToml ? null
, workspaceMetadata ? null
, overrides ? { }
, dependencies ? [ ]
, lib
, sources
, system
, ...
}@attrs:
let
  # Extract the metadata we will need.
  cargoPkg = cargoToml.package or (throw "No package field found in the provided Cargo.toml.");
  packageMetadata = cargoPkg.metadata.nix or null;

  # This is named "prevRoot" since we will override it later on.
  prevRoot = attrs.root or null;

  overrideData = { inherit cargoPkg packageMetadata sources system memberName buildPlatform cargoToml lib; root = prevRoot; };

  # Helper function to create a package set; might be useful for users
  makePkgs =
    { platform ? buildPlatform
    , toolchainChannel ? "stable"
    , override ? (_: _: { })
    }:
    import ./nixpkgs.nix {
      inherit system sources lib override toolchainChannel;
      overrideData = overrideData // { inherit toolchainChannel; };
      buildPlatform = platform;
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
  libb = lib // pkgs.nciUtils;
  overrideDataPkgs = overrideData // { lib = libb; inherit pkgs; };

  # Override the root here. This is usually useless, but better to provide a way to do it anyways.
  # This *can* causes inconsistencies related to overrides (eg. if a dep is in the new root and not in the old root).
  root = (overrides.root or (_: root: root)) overrideDataPkgs prevRoot;

  # The C compiler that will be put in the env, and whether or not to put the C compiler's bintools in the env
  cCompiler = libb.resolveToPkg (workspaceMetadata.cCompiler or packageMetadata.cCompiler or "gcc");
  useCCompilerBintools = workspaceMetadata.useCCompilerBintools or packageMetadata.useCCompilerBintools or true;

  # Libraries that will be put in $LD_LIBRARY_PATH
  runtimeLibs = libb.resolveToPkgs ((workspaceMetadata.runtimeLibs or [ ]) ++ (packageMetadata.runtimeLibs or [ ]));

  overrideDataCrates = overrideDataPkgs // { inherit cCompiler useCCompilerBintools runtimeLibs root; };

  # Collect crate overrides
  crateOverrides =
    let
      # Get the names of all our dependencies. This is done so that we can filter out unneeded overrides.
      # TODO: ideally this would only include the deps of the crate we are currently building, not all deps in Cargo.lock
      depNames = builtins.map (dep: dep.name) dependencies;
      baseRaw = libb.makeCrateOverrides {
        inherit cCompiler useCCompilerBintools;
        crateName = cargoPkg.name;
        rawTomlOverrides =
          libb.foldl'
            libb.recursiveUpdate
            (libb.genAttrs depNames (name: (_: { })))
            [ (workspaceMetadata.crateOverride or { }) (packageMetadata.crateOverride or { }) ];
      };
      # Filter out unneeded overrides, using the dep names we got earlier.
      base = libb.filterAttrs (n: _: libb.any (depName: n == depName) depNames) baseRaw;
    in
    base // ((overrides.crateOverrides or (_: _: { })) overrideDataCrates base);
  # "empty" crate overrides; we override an empty attr set to see what values the override changes.
  crateOverridesEmpty = libb.mapAttrsToList (_: v: v { }) crateOverrides;
  # Get a field from all overrides in "empty" crate overrides and flatten them. Mainly used to collect (native) build inputs.
  crateOverridesGetFlattenLists = attrName: libb.unique (libb.flatten (builtins.map (v: v.${attrName} or [ ]) crateOverridesEmpty));

  # Create the base config that will be overrided.
  # nativeBuildInputs, buildInputs, and env vars are collected here and they will be used in naersk and devshell.
  baseConfig = {
    # Library for users to utilize.
    lib = {
      inherit
        crateOverridesGetFlattenLists
        crateOverridesEmpty
        makePkgs;
    } // libb;

    inherit
      cCompiler
      useCCompilerBintools
      pkgs
      crateOverrides
      cargoPkg
      cargoToml
      buildPlatform
      sources
      system
      root
      prevRoot
      memberName
      workspaceMetadata
      packageMetadata
      runtimeLibs;

    # Collect build inputs.
    buildInputs =
      libb.resolveToPkgs
        ((workspaceMetadata.buildInputs or [ ])
          ++ (packageMetadata.buildInputs or [ ]))
      ++ (crateOverridesGetFlattenLists "buildInputs");

    # Collect native build inputs.
    nativeBuildInputs =
      libb.resolveToPkgs
        ((workspaceMetadata.nativeBuildInputs or [ ])
          ++ (packageMetadata.nativeBuildInputs or [ ]))
      ++ (crateOverridesGetFlattenLists "nativeBuildInputs");

    # Collect the env vars. The priority is as follows:
    # crate overrides > package metadata > workspace metadata
    env =
      (workspaceMetadata.env or { })
        // (packageMetadata.env or { })
        // (builtins.foldl'
        libb.recursiveUpdate
        { }
        (builtins.map (v: v.propagatedEnv or { }) crateOverridesEmpty)
      );

    # Put the overrides that other files may use (eg. build.nix, devShell.nix).
    overrides = {
      shell = overrides.shell or (_: _: { });
      build = overrides.build or (_: _: { });
      mainBuild = overrides.mainBuild or (_: _: { });
    };
  } // libb.optionalAttrs
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
in
(baseConfig // ((overrides.common or (_: { })) baseConfig))
