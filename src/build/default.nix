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
  inherit
    (common.internal)
    runtimeLibs
    builder
    root
    cargoPkg
    packageMetadata
    overrides
    memberName
    cCompiler
    crateOverrides
    ;
  inherit (common.internal.pkgsSet) pkgs utils rustToolchain;

  l = common.internal.lib;

  # Actual package name to use for the derivation.
  pkgName = l.thenOr (renamePkgTo == null) cargoPkg.name renamePkgTo;

  pkgOverrides = crateOverrides.${cargoPkg.name} or {};
  depsOverrides = crateOverrides."${cargoPkg.name}-deps" or {};

  desktopFileMetadata = packageMetadata.desktopFile or null;
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
    else
      pkgs.makeDesktopItem (
        pkgs.callPackage ./desktopItem.nix {
          inherit desktopFileMetadata pkgName;
          inherit
            (common.internal)
            root
            cargoPkg
            packageMetadata
            ;
        }
      );

  # Specify --package if we are building in a workspace
  packageFlag = l.optional (memberName != null) "--package ${cargoPkg.name}";
  # Specify --features if we have enabled features other than the default ones
  featuresFlags = l.optional ((l.length features) > 0) "--no-default-features --features ${(l.concatStringsSep "," features)}";
  # Specify --release if release profile is enabled
  releaseFlag = l.optional release "--release";

  # Wrapper that exposes runtimeLibs array as LD_LIBRARY_PATH env variable.
  runtimeLibsWrapper = old:
    if l.length runtimeLibs > 0
    then
      utils.wrapDerivation old {} ''
        ${
          pkgs.callPackage ./runtimeLibs.nix {
            libs = runtimeLibs;
          }
        }
      ''
    else old;
  # Wrapper that adds the desktop item for this package.
  desktopItemWrapper = old:
    if desktopFileMetadata != null
    then
      utils.wrapDerivation old
      {desktopItems = [desktopFile];}
      ''
        source ${pkgs.copyDesktopItems}/nix-support/setup-hook
        copyDesktopItems
      ''
    else old;
  set-toolchain.overrideRustToolchain = _: {inherit (rustToolchain) rustc cargo;};

  # Overrides for the crane builder
  craneOverrides = let
    # Fixup a cargo command for crane
    fixupCargoCommand = isDeps: isTest: let
      subcmd = l.thenOr isTest "test" "build";
      hook = l.thenOr isTest "Check" "Build";

      mkCmd = subcmd:
        l.concatStringsSep " " (l.flatten [
          "cargo"
          subcmd
          releaseFlag
          packageFlag
          featuresFlags
          (
            l.optionals (!isTest && !isDeps) [
              "--message-format"
              "json-render-diagnostics"
              ">\"$cargoBuildLog\""
            ]
          )
        ]);
      cmd = mkCmd subcmd;
    in
      l.concatStringsSep "\n" (l.flatten [
        "runHook pre${hook}"
        (
          l.optional
          (!isTest && !isDeps)
          "cargoBuildLog=$(mktemp cargoBuildLogXXXX.json)"
        )
        (l.optional (!isTest && isDeps) (mkCmd "check"))
        cmd
        "runHook post${hook}"
      ]);
    # Build phase for crane drvs
    buildPhase = isDeps: let
      p = fixupCargoCommand isDeps false;
    in
      l.dbgX "${l.optionalString isDeps "deps-"}buildPhase" p;
    # Check phase for crane drvs
    checkPhase = isDeps: let
      p = fixupCargoCommand isDeps true;
    in
      l.dbgX "${l.optionalString isDeps "deps-"}checkPhase" p;

    # Overrides for the dependency only drv
    depsOverride = prev: {
      buildPhase = buildPhase true;
      checkPhase = checkPhase true;
    };
    # Overrides for the main drv
    mainOverride = prev: {
      inherit doCheck;
      dontFixup = !release;
      buildPhase = buildPhase false;
      checkPhase = checkPhase false;
    };
  in {
    "${cargoPkg.name}-deps" =
      {
        nci-overrides.overrideAttrs = prev: let
          data = depsOverride prev;
        in
          l.dbgX "overrided deps drv" data;
      }
      // depsOverrides;
    ${cargoPkg.name} =
      {
        nci-overrides.overrideAttrs = prev: let
          data = mainOverride prev;
        in
          l.dbgX "overrided main drv" data;
      }
      // pkgOverrides;
  };

  # Overrides for the build rust package builder
  brpOverrides = let
    flags = l.concatStringsSep " " (packageFlag ++ featuresFlags);
    profile = l.thenOr release "release" "debug";
    # Overrides for the drv
    overrides = prev: {
      inherit doCheck;
      dontFixup = !release;
      cargoBuildFlags = flags;
      cargoCheckFlags = flags;
      cargoBuildType = profile;
      cargoCheckType = profile;
    };
  in {
    ${cargoPkg.name} =
      {
        nci-overrides.overrideAttrs = prev: let
          data = overrides prev;
        in
          l.dbgX "overrided drv" data;
      }
      // pkgOverrides
      // (
        l.mapAttrs'
        (n: l.nameValuePair "${n}-deps")
        depsOverrides
      );
  };

  _packageOverrides =
    if builder == "crane"
    then craneOverrides
    else if builder == "build-rust-package"
    then brpOverrides
    else throw "unsupported builder";

  baseConfig = {
    pname = cargoPkg.name;
    source = root;

    packageOverrides =
      _packageOverrides
      // {
        "^.*" = {
          inherit set-toolchain;
          set-stdenv.overrideAttrs = old: {
            CC = "cc";
            stdenv = pkgs.stdenvNoCC;
            nativeBuildInputs = let
              cCompilerPkgs =
                if cCompiler != null
                then
                  [cCompiler.package]
                  ++ (
                    l.optional
                    cCompiler.useCompilerBintools
                    cCompiler.package.bintools
                  )
                else [];
            in
              (old.nativeBuildInputs or []) ++ cCompilerPkgs;
          };
        };
      };

    settings = [{inherit builder;}];
  };

  overrideConfig = config:
    config // ((overrides.build or (_: {})) config);

  _config = overrideConfig baseConfig;
  _outputs = utils.mkCrateOutputs _config;
  unwrappedPackage = _outputs.packages.${cargoPkg.name};
  shell = _outputs.devShells.${cargoPkg.name};
in rec {
  config =
    _config
    // {
      inherit release features doCheck;
    };
  package = let
    userWrapper = overrides.wrapper or (_: old: old);
    wrapped = l.pipe unwrappedPackage [
      (old:
        old
        // {
          passthru =
            (old.passthru or {})
            // {
              inherit shell;
              unwrapped = old;
            };
        })
      desktopItemWrapper
      runtimeLibsWrapper
      (userWrapper config)
    ];
  in
    wrapped;
}
