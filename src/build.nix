{
  release ? false,
  doCheck ? false,
  features ? [],
  renamePkgTo ? null,
  common,
}: let
  inherit (common) sources system builder root packageMetadata desktopFileMetadata cargoPkg;
  inherit (common.internal) mkRuntimeLibsScript mkDesktopItemConfig mkRuntimeLibsOv mkDesktopFile;
  inherit (common.internal.nci-pkgs) pkgs pkgsWithRust utils dream2nix;

  l = common.internal.lib;

  # Actual package name to use for the derivation.
  pkgName =
    if isNull renamePkgTo
    then cargoPkg.name
    else renamePkgTo;

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

  # Overrides for the crane builder
  craneOverrides = let
    # Fixup a cargo command for crane
    fixupCargoCommand = isDeps: isTest: let
      subcmd =
        if isTest
        then "test"
        else "build";
      hook =
        if isTest
        then "Check"
        else "Build";

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
      l.applyOverrides prev [
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
      l.applyOverrides prev [
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
      nci-overrides.overrideAttrs = prev: let
        data = depsOverride prev;
      in
        l.dbgX "overrided deps drv" data;
    };
    ${cargoPkg.name} = {
      nci-overrides.overrideAttrs = prev: let
        data = mainOverride prev;
      in
        l.dbgX "overrided main drv" data;
    };
  };

  # Overrides for the build rust package builder
  brpOverrides = let
    flags = l.concatStringsSep " " (packageFlag ++ featuresFlags);
    profile =
      if release
      then "release"
      else "debug";
    # Function that overrides cargoBuildHook of buildRustPackage with our toolchain
    overrideBRPHook = prev: {
      nativeBuildInputs = let
        pkgs = pkgsWithRust;
        cargoHooks = pkgs.callPackage "${sources.nixpkgs}/pkgs/build-support/rust/hooks" {
          # Use our own rust and cargo, and our own C compiler.
          inherit (pkgs.rustPlatform.rust) rustc cargo;
          stdenv = prev.stdenv;
        };
        notOldHook = pkg:
          pkg
          != pkgs.rustPlatform.cargoBuildHook
          && pkg != pkgs.rustPlatform.cargoSetupHook
          && pkg != pkgs.rustPlatform.cargoCheckHook
          && pkg != pkgs.rustPlatform.cargoInstallHook;
      in
        (l.filter notOldHook prev.nativeBuildInputs)
        ++ [
          cargoHooks.cargoSetupHook
          cargoHooks.cargoBuildHook
          cargoHooks.cargoCheckHook
          cargoHooks.cargoInstallHook
        ];
    };
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
        common.internal.mainOverrides
        overrideBRPHook
      ];
  in {
    ${cargoPkg.name} = {
      nci-overrides.overrideAttrs = prev: let
        data = overrides prev;
      in
        l.dbgX "overrided drv" data;
    };
  };

  baseConfig = {
    inherit root memberName;
    pname = cargoPkg.name;

    builder = dream2nix.builders.${system}.rust.${builder};
    packageOverrides =
      if builder == "crane"
      then craneOverrides
      else if builder == "buildRustPackage"
      then brpOverrides
      else throw "unsupported builder";
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
