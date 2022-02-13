{ release ? false
, doCheck ? false
, features ? [ ]
, renamePkgTo ? null
, common
}:
let
  inherit (common) pkgs lib packageMetadata desktopFileMetadata cargoPkg mkDesktopFile mkRuntimeLibsOv;

  # Actual package name to use for the derivation.
  pkgName = if isNull renamePkgTo then cargoPkg.name else renamePkgTo;

  # Desktop file to put in the package derivation.
  desktopFile =
    let
      desktopFilePath = common.root + "/${lib.removePrefix "./" desktopFileMetadata}";
    in
    if builtins.isString desktopFileMetadata
    then
      pkgs.runCommandLocal "${pkgName}-desktopFileLink" { } ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else pkgs.makeDesktopItem (common.mkDesktopItemConfig pkgName);

  # Specify --package if we are building in a workspace
  packageOption = lib.optionals (! isNull common.memberName) [ "--package" cargoPkg.name ];
  # Specify --features if we have enabled features other than the default ones
  featuresOption = lib.optionals ((builtins.length features) > 0) ([ "--features" ] ++ features);
  # Member name of the package. Defaults to the crate name in Cargo.toml.
  memberName = if isNull common.memberName then null else cargoPkg.name;
  # Common config.
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
  # Note: this only works for the buildRustPackage builder
  # which is the default in dream2nix now. This should be updated
  # to be able to work for either depending on which builder is chosen.
  baseConfig = {
    inherit memberName;
    inherit (common) root;

    packageOverrides = {
      ${cargoPkg.name} = {
        nci-overrides.overrideAttrs = prev:
          lib.pipe prev [
            (prev: prev // commonConfig // {
              inherit doCheck;
              buildFlags = packageOption;
              buildFeatures = features;
              buildType = if release then "release" else "debug";
            })
            common.crateOverridesCombined
          ];
      };
      "${cargoPkg.name}-deps" = {
        nci-overrides.overrideAttrs = applyOverrides;
      };
    };
  };

  overrideConfig = config:
    config // (common.overrides.build common config);

  config = overrideConfig baseConfig;
in
{
  config = config // {
    inherit release features doCheck;
  };
  package = lib.buildCrate config;
}
