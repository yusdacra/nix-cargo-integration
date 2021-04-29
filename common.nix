{ memberName ? null
, buildPlatform ? "naersk"
, cargoToml ? null
, workspaceMetadata ? null
, root ? null
, overrides ? { }
, dependencies ? [ ]
, lib
, sources
, system
}:
let
  cargoPkg = cargoToml.package;
  packageMetadata = cargoPkg.metadata.nix or null;

  makePkgs =
    { platform ? buildPlatform
    , toolchainChannel ? "stable"
    , override ? (_: _: { })
    }:
    import ./nixpkgs.nix {
      inherit system sources lib override toolchainChannel;
      buildPlatform = platform;
    };

  pkgs = makePkgs {
    override = overrides.pkgs or (_: _: { });
    toolchainChannel =
      let rustToolchain = root + "/rust-toolchain"; in
      if builtins.pathExists rustToolchain
      then rustToolchain
      else workspaceMetadata.toolchain or packageMetadata.toolchain or "stable";
  };
  libb = lib // (import ./utils.nix pkgs);

  cCompiler = libb.resolveToPkg (workspaceMetadata.cCompiler or packageMetadata.cCompiler or "gcc");
in
let
  crateOverrides =
    let
      depNames = builtins.map (dep: dep.name) dependencies;
      baseRaw = libb.makeCrateOverrides {
        inherit cCompiler;
        crateName = cargoPkg.name;
        rawTomlOverrides =
          libb.foldl'
            libb.recursiveUpdate
            (libb.genAttrs depNames (name: (_: { })))
            [ (workspaceMetadata.crateOverride or { }) (packageMetadata.crateOverride or { }) ];
      };
      base = libb.filterAttrs (n: _: libb.any (depName: n == depName) depNames) baseRaw;
    in
    base // ((overrides.crateOverrides or (_: _: { })) { inherit pkgs; lib = libb; } base);

  crateOverridesEmpty = libb.mapAttrsToList (_: v: v { }) crateOverrides;
  crateOverridesGetFlattenLists = attrName: libb.flatten (builtins.map (v: v.${attrName} or [ ]) crateOverridesEmpty);

  baseConfig = {
    lib = {
      inherit
        crateOverridesGetFlattenLists
        crateOverridesEmpty
        makePkgs;
    } // libb;

    inherit
      cCompiler
      pkgs
      crateOverrides
      cargoPkg
      cargoToml
      buildPlatform
      sources
      system
      root
      memberName
      workspaceMetadata
      packageMetadata;

    # Libraries that will be put in $LD_LIBRARY_PATH
    runtimeLibs = libb.resolveToPkgs ((workspaceMetadata.runtimeLibs or [ ]) ++ (packageMetadata.runtimeLibs or [ ]));

    buildInputs =
      libb.resolveToPkgs
        ((workspaceMetadata.buildInputs or [ ])
        ++ (packageMetadata.buildInputs or [ ]))
      ++ (crateOverridesGetFlattenLists "buildInputs");

    nativeBuildInputs =
      libb.resolveToPkgs
        ((workspaceMetadata.nativeBuildInputs or [ ])
        ++ (packageMetadata.nativeBuildInputs or [ ]))
      ++ (crateOverridesGetFlattenLists "nativeBuildInputs");

    env =
      (workspaceMetadata.env or { })
      // (packageMetadata.env or { })
      // (builtins.foldl'
        libb.recursiveUpdate
        { }
        (builtins.map (v: v.propagatedEnv or { }) crateOverridesEmpty)
      );

    overrides = {
      shell = overrides.shell or (_: _: { });
      build = overrides.build or (_: _: { });
      mainBuild = overrides.mainBuild or (_: _: { });
    };
  };
in
(baseConfig // ((overrides.common or (_: { })) baseConfig))
