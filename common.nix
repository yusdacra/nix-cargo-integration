{ memberName ? null
, buildPlatform ? "naersk"
, cargoToml ? null
, workspaceMetadata ? null
, root ? null
, overrides ? { }
, dependencies ? [ ]
, sources
, system
}:
let
  isCrate2Nix = buildPlatform == "crate2nix";
  isNaersk = buildPlatform == "naersk";

  cargoPkg = cargoToml.package;
  packageMetadata = cargoPkg.metadata.nix or null;

  pkgs = import ./nixpkgs.nix {
    inherit system sources buildPlatform isCrate2Nix isNaersk;
    override = overrides.pkgs or (_: _: { });
    toolchainChannel =
      let rustToolchain = root + "/rust-toolchain"; in
      if builtins.pathExists rustToolchain
      then rustToolchain
      else workspaceMetadata.toolchain or packageMetadata.toolchain or "stable";
  };
  lib = pkgs.lib // (import ./utils.nix pkgs);

  crateOverrides =
    let
      baseRaw = lib.makeCrateOverrides {
        crateName = cargoPkg.name;
        rawTomlOverrides =
          lib.recursiveUpdate
            (workspaceMetadata.crateOverride or { })
            (packageMetadata.crateOverride or { });
      };
      depNames = builtins.map (dep: dep.name) dependencies;
      base = lib.filterAttrs (n: _: lib.any (depName: n == depName) depNames) baseRaw;
    in
    base // ((overrides.crateOverrides or (_: _: { })) { inherit pkgs lib; } base);

  crateOverridesEmpty = lib.mapAttrsToList (_: v: v { }) crateOverrides;
  crateOverridesGetFlattenLists = attrName: lib.flatten (builtins.map (v: v.${attrName} or [ ]) crateOverridesEmpty);

  baseConfig = {
    lib = {
      inherit
        crateOverridesGetFlattenLists
        crateOverridesEmpty;
    } // lib;

    inherit
      pkgs
      crateOverrides
      cargoPkg
      cargoToml
      isCrate2Nix
      isNaersk
      buildPlatform
      sources
      system
      root
      memberName
      workspaceMetadata
      packageMetadata;

    # Libraries that will be put in $LD_LIBRARY_PATH
    runtimeLibs = lib.resolveToPkgs ((workspaceMetadata.runtimeLibs or [ ]) ++ (packageMetadata.runtimeLibs or [ ]));

    buildInputs =
      lib.resolveToPkgs
        ((workspaceMetadata.buildInputs or [ ])
        ++ (packageMetadata.buildInputs or [ ]))
      ++ (crateOverridesGetFlattenLists "buildInputs");

    nativeBuildInputs =
      lib.resolveToPkgs
        ((workspaceMetadata.nativeBuildInputs or [ ])
        ++ (packageMetadata.nativeBuildInputs or [ ]))
      ++ (crateOverridesGetFlattenLists "nativeBuildInputs");

    env =
      (workspaceMetadata.env or { })
      // (packageMetadata.env or { })
      // (builtins.foldl'
        pkgs.lib.recursiveUpdate
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
