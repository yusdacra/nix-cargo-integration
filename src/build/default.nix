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
    flagsProfiles = rec {
      cargoBuildFlags = l.concatStringsSep " " featuresFlags;
      cargoTestFlags = cargoBuildFlags;
      cargoBuildProfile = profile;
      cargoTestProfile = cargoBuildProfile;
    };

    # Overrides for the dependency only drv
    depsOverride = prev: flagsProfiles;
    # Overrides for the main drv
    mainOverride = prev:
      flagsProfiles
      // {
        inherit doCheck dontFixup;
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
    brpProfile =
      if profile == "dev"
      then "debug"
      else profile;
    # Overrides for the drv
    overrides = prev: {
      inherit doCheck dontFixup;
      cargoBuildFlags = flags;
      cargoTestFlags = flags;
      # we set this to debug so that `cargoBuildProfileFlag` is not declared
      cargoBuildType = "debug";
      cargoCheckType = "debug";
      cargoBuildProfileFlag = profileFlag;
      cargoCheckProfileFlag = profileFlag;
      dontCargoInstall = true;
      postBuild = ''
        export cargoBuildType="${brpProfile}"
        export cargoCheckType="${brpProfile}"
        runHook cargoInstallPostBuildHook
        ${prev.postBuild or ""}
      '';
      installPhase = ''
        runHook preInstall
        runHook cargoInstallHook
        ${prev.installPhase or ""}
        runHook postInstall
      '';
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
  unwrappedPackage = _outputs.packages.${pkgs.system}.${cargoPkg.name};
  shell = _outputs.devShells.${pkgs.system}.${cargoPkg.name};
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
