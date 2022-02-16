{ release ? false
, doCheck ? false
, features ? [ ]
, renamePkgTo ? null
, common
}:
let
  inherit (common) pkgs lib packageMetadata desktopFileMetadata cargoPkg mkDesktopFile mkRuntimeLibsOv;

  l = lib // builtins;

  # Actual package name to use for the derivation.
  pkgName = if isNull renamePkgTo then cargoPkg.name else renamePkgTo;

  # Desktop file to put in the package derivation.
  desktopFile =
    let
      desktopFilePath = common.root + "/${l.removePrefix "./" desktopFileMetadata}";
    in
    if l.isString desktopFileMetadata
    then
      pkgs.runCommandLocal "${pkgName}-desktopFileLink" { } ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else pkgs.makeDesktopItem (common.mkDesktopItemConfig pkgName);

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
    prev // {
      postFixup = ''
        ${prev.postFixup or ""}
        ${common.mkRuntimeLibsScript (l.makeLibraryPath common.runtimeLibs)}
      '';
    };
  # Override that adds the desktop item for this package.
  desktopItemOv = prev:
    prev // {
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.copyDesktopItems ];
      desktopItems = (prev.desktopItems or [ ]) ++ [ desktopFile ];
    };
  # Override that adds dependencies and env from common
  commonDepsOv = prev:
    prev // common.env // {
      buildInputs = l.unique ((prev.buildInputs or [ ]) ++ common.buildInputs);
      nativeBuildInputs = l.unique ((prev.nativeBuildInputs or [ ]) ++ common.nativeBuildInputs);
    };
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

  # TODO: support dream2nix builder switching
  baseConfig = {
    inherit memberName;
    inherit (common) root;

    packageOverrides = {
      "${cargoPkg.name}-deps" = {
        nci-overrides.overrideAttrs = prev: l.pipe prev [
          (prev: prev // {
            doCheck = false;
            buildPhase = fixupCargoCommand false;
            checkPhase = fixupCargoCommand true;
          })
          commonDepsOv
          common.crateOverridesCombined
        ];
      };
      ${cargoPkg.name} = {
        nci-overrides.overrideAttrs = prev: l.pipe prev [
          (prev: prev // {
            inherit doCheck meta;
            dontFixup = !release;
            buildPhase = fixupCargoCommand false;
            checkPhase = fixupCargoCommand true;
          })
          (prev: if mkDesktopFile then desktopItemOv prev else prev)
          (prev: if mkRuntimeLibsOv then runtimeLibsOv prev else prev)
          commonDepsOv
          common.mainBuildOverride
        ];
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
