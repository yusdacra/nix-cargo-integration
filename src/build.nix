{
  release ? false,
  doCheck ? false,
  features ? [],
  renamePkgTo ? null,
  common,
}:
let
  inherit (common) root packageMetadata desktopFileMetadata cargoPkg;
  inherit (common.internal) mkRuntimeLibsScript mkDesktopItemConfig mkRuntimeLibsOv mkDesktopFile;
  inherit (common.internal.nci-pkgs) pkgs utils;

  l = common.internal.lib;

  # Actual package name to use for the derivation.
  pkgName =
    if isNull renamePkgTo
    then cargoPkg.name
    else renamePkgTo;

  # Desktop file to put in the package derivation.
  desktopFile =
    let
      desktopFilePath = root + "/${l.removePrefix "./" desktopFileMetadata}";
    in
      if l.isString desktopFileMetadata
      then
        pkgs.runCommandLocal "${pkgName}-desktopFileLink" {} ''
          mkdir -p $out/share/applications
          ln -sf ${desktopFilePath} $out/share/applications
        ''
      else pkgs.makeDesktopItem (mkDesktopItemConfig pkgName);

  # Specify --package if we are building in a workspace
  packageFlag = l.optional (common.memberName != null) "--package ${cargoPkg.name}";
  # Specify --features if we have enabled features other than the default ones
  featuresFlags = l.optional ((l.length features) > 0) "--features ${(l.concatStringsSep "," features)}";
  # Member name of the package. Defaults to the crate name in Cargo.toml.
  memberName =
    if isNull common.memberName
    then null
    else cargoPkg.name;

  # Override that exposes runtimeLibs array as LD_LIBRARY_PATH env variable.
  runtimeLibsOv = prev:
    l.optionalAttrs mkRuntimeLibsOv {
      postFixup = ''
        ${prev.postFixup or ""}
        ${mkRuntimeLibsScript (l.makeLibraryPath common.runtimeLibs)}
      '';
    };
  # Override that adds the desktop item for this package.
  desktopItemOv = prev:
    l.optionalAttrs mkDesktopFile {
      nativeBuildInputs = (prev.nativeBuildInputs or []) ++ [pkgs.copyDesktopItems];
      desktopItems = (prev.desktopItems or []) ++ [desktopFile];
    };
  # Override that adds dependencies and env from common
  commonDepsOv = prev:
    common.env
    // {
      buildInputs = l.unique ((prev.buildInputs or []) ++ common.buildInputs);
      nativeBuildInputs = l.unique ((prev.nativeBuildInputs or []) ++ common.nativeBuildInputs);
    };

  # Overrides for the build rust package builder
  brpOverrides =
    let
      flags = l.concatStringsSep " " (packageFlag ++ featuresFlags);
      profile =
        if release
        then "release"
        else "debug";
      # Overrides for the drv
      overrides = prev:
        l.applyOverrides prev [
          (prev: {
            inherit doCheck;
            meta = common.meta;
            dontFixup = !release;
            cargoBuildFlags = flags;
            cargoCheckFlags = flags;
            cargoBuildType = profile;
            cargoCheckType = profile;
          })
          desktopItemOv
          runtimeLibsOv
          commonDepsOv
          common.internal.crateOverridesCombined
        ];
    in {
      ${cargoPkg.name} = {
        nci-overrides.overrideAttrs = prev: let
          data = overrides prev;
        in
          l.dbgX "overrided drv" data;
      };
    };

  # TODO: support dream2nix builder switching
  baseConfig = {
    inherit root memberName;
    packageOverrides = brpOverrides;
  };

  overrideConfig = config:
    config // (common.overrides.build common config);

  config = overrideConfig baseConfig;
in {
  config =
    config
    // {
      inherit release features doCheck;
    };
  package = utils.buildCrate config;
}
