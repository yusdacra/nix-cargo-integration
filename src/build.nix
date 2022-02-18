{ release ? false
, doCheck ? false
, features ? [ ]
, renamePkgTo ? null
, common
}:
let
  inherit (common) root packageMetadata desktopFileMetadata cargoPkg;
  inherit (common.internal) mkRuntimeLibsScript mkDesktopItemConfig mkRuntimeLibsOv mkDesktopFile;
  inherit (common.internal.nci-pkgs) pkgs utils;

  l = common.internal.lib;

  # Actual package name to use for the derivation.
  pkgName = if isNull renamePkgTo then cargoPkg.name else renamePkgTo;

  # Desktop file to put in the package derivation.
  desktopFile =
    let
      desktopFilePath = root + "/${l.removePrefix "./" desktopFileMetadata}";
    in
    if l.isString desktopFileMetadata
    then
      pkgs.runCommandLocal "${pkgName}-desktopFileLink" { } ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else pkgs.makeDesktopItem (mkDesktopItemConfig pkgName);

  # Specify --package if we are building in a workspace
  packageFlag = l.optional (common.memberName != null) "--package ${cargoPkg.name}";
  # Specify --features if we have enabled features other than the default ones
  featuresFlags = l.optional ((l.length features) > 0) "--features ${(l.concatStringsSep "," features)}";
  # Specify --release if release profile is enabled
  releaseFlag = l.optional release "--release";
  # Member name of the package. Defaults to the crate name in Cargo.toml.
  memberName = if isNull common.memberName then null else cargoPkg.name;

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
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.copyDesktopItems ];
      desktopItems = (prev.desktopItems or [ ]) ++ [ desktopFile ];
    };
  # Override that adds dependencies and env from common
  commonDepsOv = prev:
    common.env // {
      buildInputs = l.unique ((prev.buildInputs or [ ]) ++ common.buildInputs);
      nativeBuildInputs = l.unique ((prev.nativeBuildInputs or [ ]) ++ common.nativeBuildInputs);
    };

  # Overrides for the crane builder
  craneOverrides =
    let
      # Fixup a cargo command for crane
      fixupCargoCommand = isTest:
        let
          cmd = l.concatStringsSep " " (
            [ "cargo" (if isTest then "test" else "build") ]
            ++ releaseFlag ++ packageFlag ++ featuresFlags
          );
        in
        ''
          runHook ${if isTest then "preCheck" else "preBuild"}
          echo running: ${l.strings.escapeShellArg cmd}
          ${cmd}
          runHook ${if isTest then "postCheck" else "postBuild"}
        '';
      # Build phase for crane drvs
      buildPhase =
        let p = fixupCargoCommand false; in
        l.dbgX "buildPhase" p;
      # Check phase for crane drvs
      checkPhase =
        let p = fixupCargoCommand true; in
        l.dbgX "checkPhase" p;

      # Overrides for the dependency only drv
      depsOverride = prev: l.applyOverrides prev [
        (prev: {
          inherit buildPhase checkPhase;
          doCheck = false;
        })
        commonDepsOv
        common.internal.crateOverridesCombined
      ];
      # Overrides for the main drv
      mainOverride = prev: l.applyOverrides prev [
        (prev: {
          inherit doCheck buildPhase checkPhase;
          meta = common.meta;
          dontFixup = !release;
        })
        desktopItemOv
        runtimeLibsOv
        commonDepsOv
        common.internal.mainBuildOverride
      ];
    in
    {
      "${cargoPkg.name}-deps" = {
        nci-overrides.overrideAttrs = prev:
          let data = depsOverride prev; in
          l.dbgX "deps override diff" data;
      };
      ${cargoPkg.name} = {
        nci-overrides.overrideAttrs = prev:
          let data = mainOverride prev; in
          l.dbgX "main override diff" data;
      };
    };

  # TODO: support dream2nix builder switching
  baseConfig = {
    inherit root memberName;
    packageOverrides = craneOverrides;
  };

  overrideConfig = config:
    config // (common.overrides.build common config);

  config = overrideConfig baseConfig;
in
{
  config = config // {
    inherit release features doCheck;
  };
  package = utils.buildCrate config;
}
