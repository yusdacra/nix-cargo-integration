{ release ? false
, doCheck ? false
, doDoc ? false
, features ? [ ]
, renamePkgTo ? null
, common
}:
let
  inherit (common) pkgs lib packageMetadata desktopFileMetadata cargoPkg buildPlatform mkDesktopFile mkRuntimeLibsOv;

  pkgName = if isNull renamePkgTo then cargoPkg.name else renamePkgTo;

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
    stdenv = pkgs.stdenvNoCC;
  };

  # Override that exposes runtimeLibs array as LD_LIBRARY_PATH env variable. 
  runtimeLibsOv = prev:
    prev //
    lib.optionalAttrs mkRuntimeLibsOv {
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
      postFixup = ''
        ${prev.postFixup or ""}
        ${common.mkRuntimeLibsScript (lib.makeLibraryPath common.runtimeLibs)}
      '';
    };
  # Override that adds the desktop item for this package.
  desktopItemOv = prev:
    prev //
    lib.optionalAttrs mkDesktopFile {
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.copyDesktopItems ];
      desktopItems = (prev.desktopItems or [ ]) ++ [ desktopFile ];
    };
  mainBuildOv = prev: prev // common.overrides.mainBuild common prev;
  # Function to apply all overrides.
  applyOverrides = prev:
    lib.pipe prev [
      (prev: prev // commonConfig)
      desktopItemOv
      runtimeLibsOv
      mainBuildOv
    ];

  # Base config for buildRustPackage platform.
  baseBRPConfig = applyOverrides {
    pname = pkgName;
    inherit (cargoPkg) version;
    inherit (common) root buildInputs nativeBuildInputs cargoVendorHash;
    inherit doCheck memberPath;
    buildFlags = releaseOption ++ packageOption ++ featuresOption;
    checkFlags = releaseOption ++ packageOption ++ featuresOption;
  };

  # Base config for naersk platform.
  baseNaerskConfig = {
    inherit (common) root nativeBuildInputs buildInputs;
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
    override = _: commonConfig;
    overrideMain = applyOverrides;
    copyLibs = library;
    inherit release doCheck doDoc;
  };

  # Base config crate2nix platform.
  baseCrate2NixConfig =
    let
      # Override that adds stuff like make wrapper, desktop file, common envs and so on.
      overrideMain = prev: applyOverrides (prev // {
        nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ common.nativeBuildInputs;
        buildInputs = (prev.buildInputs or [ ]) ++ common.buildInputs;
      });
    in
    {
      inherit pkgs release;
      runTests = doCheck;
      rootFeatures =
        # If we specified features, disable default feature, since it means this is an autobin
        let def = lib.optional (builtins.hasAttr "default" (common.cargoToml.features or { })) "default"; in
        if (builtins.length features) > 0
        then features ++ def
        else def;
      defaultCrateOverrides =
        let
          # Remove propagated envs from overrides, no longer needed
          crateOverrides =
            builtins.mapAttrs
              (_: v: (prev: builtins.removeAttrs (v prev) [ "propagatedEnv" ]))
              common.crateOverrides;
        in
        crateOverrides // {
          ${cargoPkg.name} = prev:
            let
              # First override
              overrode = (crateOverrides.${cargoPkg.name} or (_: { })) prev;
              # Second override (might contain user provided values)
              overroded = overrideMain overrode;
            in
            overroded;
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
            } // (builtins.removeAttrs config [ "runTests" ])
          );
      in
      # This is a workaround so that crate2nix doesnt get built until we actually build
      # otherwise nix will try to build it even if you only run `nix flake show`
      # https://github.com/NixOS/nix/issues/4265
      # TODO: probably provide a way to override the inner derivation?
      pkgs.symlinkJoin {
        inherit (common) meta;
        name = "${pkgName}-${cargoPkg.version}";
        paths = [
          (pkg.override { inherit (config) runTests; })
        ];
      };
  }
else if lib.isBuildRustPackage buildPlatform then
  let config = overrideConfig baseBRPConfig; in
  {
    inherit config;
    package = lib.buildCrate config;
  }
else throw "invalid build platform: ${buildPlatform}"
