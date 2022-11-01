{
  # whether to run check phase
  doCheck ? false,
  # The profile to use when compiling
  profile ? "debug",
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

  desktopFileMetadata = packageMetadata.desktopFile;
  # Desktop file to put in the package derivation.
  desktopFile = let
    desktopFilePath =
      if l.isPath desktopFileMetadata
      then desktopFileMetadata
      else root + "/${l.removePrefix "./" desktopFileMetadata}";
  in
    if l.isString desktopFileMetadata || l.isPath desktopFileMetadata
    then
      pkgs.runCommandLocal "${pkgName}-desktopFileLink" {} ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else
      pkgs.makeDesktopItem (
        import ./desktopItem.nix {
          inherit desktopFileMetadata pkgName;
          inherit
            (common.internal)
            lib
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
  # Specify the --profile flag to set the profile we will use for compiling
  profileFlag = "--profile ${profile}";
  dontFixup = profile != "release";

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
          profileFlag
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
    buildPhase = isDeps: fixupCargoCommand isDeps false;
    # Check phase for crane drvs
    checkPhase = isDeps: fixupCargoCommand isDeps true;

    # Overrides for the dependency only drv
    depsOverride = prev: {
      buildPhase = buildPhase true;
      checkPhase = checkPhase true;
    };
    # Overrides for the main drv
    mainOverride = prev: {
      inherit doCheck dontFixup;
      buildPhase = buildPhase false;
      checkPhase = checkPhase false;
    };
  in {
    "${cargoPkg.name}-deps" =
      {
        nci-overrides.overrideAttrs = depsOverride;
      }
      // depsOverrides;
    ${cargoPkg.name} =
      {
        nci-overrides.overrideAttrs = mainOverride;
      }
      // pkgOverrides;
  };

  # Overrides for the build rust package builder
  brpOverrides = let
    flags = l.concatStringsSep " " (packageFlag ++ featuresFlags);
    # Overrides for the drv
    overrides = prev: {
      inherit doCheck dontFixup;
      cargoBuildFlags = flags;
      cargoCheckFlags = flags;
      # we set this to debug so that `cargoBuildProfileFlag` is not declared
      cargoBuildType = "debug";
      cargoCheckType = "debug";
      cargoBuildProfileFlag = profileFlag;
    };
  in {
    ${cargoPkg.name} =
      {
        nci-overrides.overrideAttrs = overrides;
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
    else throw "unsupported builder: ${builder}";

  baseConfig = l.dbgX "base d2n config" {
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

    settings = [{inherit builder;}] ++ packageMetadata.dream2nixSettings;
  };

  _outputs = l.dbgX "outputs" (utils.mkCrateOutputs baseConfig);
  unwrappedPackage = _outputs.packages.${cargoPkg.name};
  shell = _outputs.devShells.${cargoPkg.name};
in rec {
  config = baseConfig // {inherit profile features doCheck;};
  package = let
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
      (packageMetadata.wrapper config)
    ];
  in
    wrapped;
}
