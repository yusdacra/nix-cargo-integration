{
  # Whether to build this package using a release profile
  release ? false,
  # Whether to run package checks (eg. cargo tests)
  doCheck ? false,
  # Features to enable for this package
  features ? [],
  # If non null, this string will be used as the derivation name
  renamePkgTo ? null,
  # The common we got from `./common.nix` for this package
  common,
}: let
  inherit (common) sources system builder root packageMetadata desktopFileMetadata cargoPkg;
  inherit (common.internal) mkRuntimeLibsScript mkDesktopItemConfig mkRuntimeLibsOv mkDesktopFile;
  inherit (common.internal.nci-pkgs) pkgs utils rustToolchain;

  l = common.internal.lib;

  # Actual package name to use for the derivation.
  pkgName = l.thenOr (renamePkgTo == null) cargoPkg.name renamePkgTo;

  # Desktop file to put in the package derivation.
  desktopFile = let
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
  # Specify --release if release profile is enabled
  releaseFlag = l.optional release "--release";

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
      nativeBuildInputs = l.concatLists (prev.nativeBuildInputs or []) [pkgs.copyDesktopItems];
      desktopItems = l.concatLists (prev.desktopItems or []) [desktopFile];
    };
  # Override that adds dependencies and env from common
  commonDepsOv = prev:
    common.env
    // {
      buildInputs = l.concatAttrLists prev common "buildInputs";
      nativeBuildInputs = l.concatAttrLists prev common "nativeBuildInputs";
    };
  set-toolchain.overrideRustToolchain = _: {inherit (rustToolchain) rustc cargo;};

  # Overrides for the crane builder
  craneOverrides = let
    # Fixup a cargo command for crane
    fixupCargoCommand = isDeps: isTest: let
      subcmd = l.thenOr isTest "test" "build";
      hook = l.thenOr isTest "Check" "Build";

      cmd = l.concatStringsSep " " (
        ["cargo" subcmd]
        ++ releaseFlag
        ++ packageFlag
        ++ featuresFlags
        ++ (l.optionals (!isTest && !isDeps) [
          "--message-format"
          "json-render-diagnostics"
          ">\"$cargoBuildLog\""
        ])
      );
    in ''
      runHook pre${hook}
      echo running: ${l.strings.escapeShellArg cmd}
      ${
        l.optionalString
        (!isTest && !isDeps)
        "cargoBuildLog=$(mktemp cargoBuildLogXXXX.json)"
      }
      ${cmd}
      runHook post${hook}
    '';
    # Build phase for crane drvs
    buildPhase = isDeps: let
      p = fixupCargoCommand false isDeps;
    in
      l.dbgX "${l.optionalString isDeps "deps-"}buildPhase" p;
    # Check phase for crane drvs
    checkPhase = isDeps: let
      p = fixupCargoCommand true isDeps;
    in
      l.dbgX "${l.optionalString isDeps "deps-"}checkPhase" p;

    # Overrides for the dependency only drv
    depsOverride = prev:
      l.computeOverridesResult prev [
        (prev: {
          doCheck = false;
          buildPhase = buildPhase true;
          checkPhase = checkPhase true;
        })
        commonDepsOv
        common.internal.crateOverridesCombined
      ];
    # Overrides for the main drv
    mainOverride = prev:
      l.computeOverridesResult prev [
        (prev: {
          inherit doCheck;
          meta = common.meta;
          dontFixup = !release;
          buildPhase = buildPhase false;
          checkPhase = checkPhase false;
        })
        desktopItemOv
        runtimeLibsOv
        commonDepsOv
        common.internal.mainOverrides
      ];
  in {
    "${cargoPkg.name}-deps" = {
      inherit set-toolchain;
      nci-overrides.overrideAttrs = prev: let
        data = depsOverride prev;
      in
        l.dbgX "overrided deps drv" data;
    };
    ${cargoPkg.name} = {
      inherit set-toolchain;
      nci-overrides.overrideAttrs = prev: let
        data = mainOverride prev;
      in
        l.dbgX "overrided main drv" data;
    };
  };

  # Overrides for the build rust package builder
  brpOverrides = let
    flags = l.concatStringsSep " " (packageFlag ++ featuresFlags);
    profile = l.thenOr release "release" "debug";
    # Overrides for the drv
    overrides = prev:
      l.computeOverridesResult prev [
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
        common.internal.mainOverrides
      ];
  in {
    ${cargoPkg.name} = {
      inherit set-toolchain;
      nci-overrides.overrideAttrs = prev: let
        data = overrides prev;
      in
        l.dbgX "overrided drv" data;
    };
  };

  baseConfig = {
    pname = cargoPkg.name;
    source = root;

    packageOverrides =
      if builder == "crane"
      then craneOverrides
      else if builder == "build-rust-package"
      then brpOverrides
      else throw "unsupported builder";

    settings = [{inherit builder;}];
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
