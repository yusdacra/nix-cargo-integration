{ release ? false
, doCheck ? false
, doDoc ? false
, features ? [ ]
, renamePkgTo ? null
, common
}:
let
  inherit (common) pkgs lib packageMetadata desktopFileMetadata cargoPkg buildPlatform mkDesktopFile mkRuntimeLibsOv;

  # Actual package name to use for the derivation.
  pkgName = if isNull renamePkgTo then cargoPkg.name else renamePkgTo;

  # Desktop file to put in the package derivation.
  desktopFile =
    let
      desktopFilePath = common.root + "/${lib.removePrefix "./" desktopFileMetadata}";
    in
    if builtins.isString desktopFileMetadata
    then
      pkgs.runCommand "${pkgName}-desktopFileLink" { } ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else pkgs.makeDesktopItem (common.mkDesktopItemConfig pkgName);

  # Whether this package contains a library output or not.
  library = packageMetadata.library or false;
  # Specify --package if we are building in a workspace
  packageOption = lib.optionals (! isNull common.memberName) [ "--package" cargoPkg.name ];
  # Specify --features if we have enabled features other than the default ones
  featuresOption = lib.optionals ((builtins.length features) > 0) ([ "--features" ] ++ features);
  # Whether to build the package with release profile.
  releaseOption = lib.optional release "--release";
  # Member name of the package. Defaults to the crate name in Cargo.toml.
  memberName = if isNull common.memberName then null else cargoPkg.name;
  # Member "path" of the package. This is used to locate the Cargo.toml of the crate.
  memberPath = common.memberName;
  commonConfig = common.env // {
    inherit (common) meta;
    dontFixup = !release;
    # Use no cc stdenv, since we supply our own cc
    stdenv = pkgs.rustPkgs.stdenvNoCC // {
      cc = common.cCompiler;
    };
  };

  # Override that exposes runtimeLibs array as LD_LIBRARY_PATH env variable. 
  runtimeLibsOv = prev:
    prev // {
      postFixup = ''
        ${prev.postFixup or ""}
        ${common.mkRuntimeLibsScript (lib.makeLibraryPath common.runtimeLibs)}
      '';
    };
  # Override that adds the desktop item for this package.
  desktopItemOv = prev:
    prev // {
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.copyDesktopItems ];
      desktopItems = (prev.desktopItems or [ ]) ++ [ desktopFile ];
    };
  # Function to apply overrides for the main package.
  applyOverrides = prev:
    lib.pipe prev [
      (prev: prev // commonConfig)
      (prev: if mkDesktopFile then desktopItemOv prev else prev)
      (prev: if mkRuntimeLibsOv then runtimeLibsOv prev else prev)
      common.mainBuildOverride
    ];
  # Function that overrides cargoBuildHook of buildRustPackage with our toolchain
  overrideBRPHook = prev: prev // {
    nativeBuildInputs =
      let
        cargoHooks = pkgs.rustPkgs.callPackage "${common.sources.nixpkgs}/pkgs/build-support/rust/hooks" {
          # Use our own rust and cargo, and our own C compiler.
          inherit (pkgs.rustPkgs.rustPlatform.rust) rustc cargo;
          stdenv = prev.stdenv;
        };
        notOldHook = pkg:
          pkg != pkgs.rustPkgs.rustPlatform.cargoBuildHook
            && pkg != pkgs.rustPkgs.rustPlatform.cargoSetupHook
            && pkg != pkgs.rustPkgs.rustPlatform.cargoCheckHook
            && pkg != pkgs.rustPkgs.rustPlatform.cargoInstallHook;
      in
      (lib.filter notOldHook prev.nativeBuildInputs) ++ [
        cargoHooks.cargoSetupHook
        cargoHooks.cargoBuildHook
        cargoHooks.cargoCheckHook
        cargoHooks.cargoInstallHook
      ];
  };
  # Base config for dream2nix platform.
  # Note: this only works for the buildRustPackage builder
  # which is the default in dream2nix now. This should be updated
  # to be able to work for either depending on which builder is chosen.
  baseD2NConfig = {
    inherit (common) root;

    packageOverrides = {
      ${cargoPkg.name} = {
        nci-overrides.overrideAttrs = prev:
          lib.pipe prev [
            (prev: prev // {
              inherit doCheck;
              buildFlags = packageOption;
              buildFeatures = features;
              buildType = if release then "release" else "debug";
            })
            common.crateOverridesCombined
            applyOverrides
            overrideBRPHook
          ];
      };
    };
  };

  # Base config for buildRustPackage platform.
  baseBRPConfig = applyOverrides (common.crateOverridesCombined {
    pname = pkgName;
    inherit (cargoPkg) version;
    inherit (common) root cargoVendorHash;
    inherit doCheck memberPath;
    buildFlags = packageOption;
    buildFeatures = features;
    buildType = if release then "release" else "debug";
  });

  # Base config for naersk platform.
  baseNaerskConfig = {
    inherit (common) root;
    inherit (cargoPkg) version;
    name = pkgName;
    allRefs = true;
    gitSubmodules = true;
    cargoBuildOptions = def: def ++ packageOption ++ featuresOption;
    # FIXME: doctests fail to compile (they compile with nightly cargo but then rustdoc fails)
    cargoTestOptions = def:
      def ++ [ "--tests" "--bins" "--examples" ]
      ++ lib.optional library "--lib"
      ++ packageOption ++ featuresOption;
    override = prev: common.crateOverridesCombined (
      prev // (builtins.removeAttrs commonConfig [ "meta" ])
    );
    overrideMain = applyOverrides;
    copyLibs = library;
    inherit release doCheck doDoc;
  };

  # Base config crate2nix platform.
  baseCrate2NixConfig =
    {
      inherit pkgs release;
      runTests = doCheck;
      testCrateFlags = [];
      testInputs = [];
      testPreRun = "";
      testPostRun = "";
      rootFeatures =
        # If we specified features, disable default feature, since it means this is an autobin
        let def = lib.optional (builtins.hasAttr "default" (common.cargoToml.features or { })) "default"; in
        if (builtins.length features) > 0
        then features ++ def
        else def;
      defaultCrateOverrides =
        common.noPropagatedEnvOverrides // {
          ${cargoPkg.name} = applyOverrides;
        };
    };

  overrideConfig = config:
    config // (common.overrides.build common config);
in
if lib.isNaersk buildPlatform then
  let config = overrideConfig baseNaerskConfig; in
  {
    inherit config;
    package = lib.buildCrate config;
  }
else if lib.isCrate2Nix buildPlatform then
  let config = overrideConfig baseCrate2NixConfig; in
  {
    inherit config;
    package =
      let
        pkg = lib.buildCrate
          (
            {
              inherit (common) root;
              # Use member name if it exists, which means we are building a crate in a workspace
              memberName = if isNull memberName then if common.isRootMember then cargoPkg.name else null else memberName;
              # If no features are specified, default to default features to generate Cargo.nix.
              # If there are features specified, turn off default features and use the provided features to generate Cargo.nix.
              additionalCargoNixArgs =
                lib.optionals
                  ((builtins.length config.rootFeatures) > 0)
                  [ "--no-default-features" "--features" (lib.concatStringsSep " " config.rootFeatures) ];
            } // (builtins.removeAttrs config [ "runTests" "testCrateFlags" "testInputs" "testPreRun" "testPostRun" ])
          );
        package = pkg.override { inherit (config) runTests testCrateFlags testInputs testPreRun testPostRun; };
        mkJoin = package:
          let
            joined = pkgs.rustPkgs.symlinkJoin {
              inherit (common) meta;
              name = "${pkgName}-${cargoPkg.version}";
              paths = [ package ];
            };
          in
          joined // {
            overrideAttrsTop = joined.overrideAttrs;
          };
      in
      # This is a workaround so that crate2nix doesnt get built until we actually build
        # otherwise nix will try to build it even if you only run `nix flake show`
        # https://github.com/NixOS/nix/issues/4265
      (mkJoin package) // {
        overrideAttrs = f: mkJoin (package.overrideAttrs f);
        override = attrs: mkJoin (package.override attrs);
      };
  }
else if lib.isBuildRustPackage buildPlatform then
  let config = overrideConfig baseBRPConfig; in
  {
    inherit config;
    package = lib.buildCrate (overrideBRPHook config);
  }
else if lib.isDream2Nix buildPlatform then
  let config = overrideConfig baseD2NConfig; in
  {
    inherit config;
    package = lib.buildCrate config;
  }
else throw "invalid build platform: ${buildPlatform}"
