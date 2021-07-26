{ release ? false
, doCheck ? false
, doDoc ? false
, features ? [ ]
, renamePkgTo ? null
, common
}:
let
  inherit (common) pkgs lib packageMetadata cargoPkg buildPlatform;

  putIfHasAttr = attr: set: lib.optionalAttrs (builtins.hasAttr attr set) { ${attr} = set.${attr}; };

  desktopFileMetadata = packageMetadata.desktopFile or null;
  mkDesktopFile = ! isNull desktopFileMetadata;

  pkgName = if isNull renamePkgTo then cargoPkg.name else renamePkgTo;

  # TODO: try to convert cargo maintainers to nixpkgs maintainers
  meta = {
    description = cargoPkg.description or "${pkgName} is a Rust project.";
    platforms = [ common.system ];
  } // (lib.optionalAttrs (builtins.hasAttr "license" cargoPkg) { license = lib.licenses."${lib.cargoLicenseToNixpkgs cargoPkg.license}"; })
  // (putIfHasAttr "homepage" cargoPkg)
  // (putIfHasAttr "longDescription" packageMetadata);

  desktopFile =
    let
      # If icon path starts with relative path prefix, make it absolute using root as base
      # Otherwise treat it as an absolute path
      makeIcon = icon:
        if (lib.hasPrefix "./" icon)
        then (common.root + "/${lib.removePrefix "./" icon}")
        else icon;
      desktopFilePath = common.root + "/${lib.removePrefix "./" desktopFileMetadata}";
    in
    if builtins.isString desktopFileMetadata
    then
      pkgs.runCommand "${pkgName}-desktopFileLink" { } ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else
      (pkgs.makeDesktopItem {
        name = pkgName;
        exec = packageMetadata.executable or pkgName;
        comment = desktopFileMetadata.comment or meta.description;
        desktopName = desktopFileMetadata.name or pkgName;
      }) // (putIfHasAttr "icon" desktopFileMetadata)
      // (putIfHasAttr "genericName" desktopFileMetadata)
      // (putIfHasAttr "categories" desktopFileMetadata);

  runtimeLibsOv = prev:
    prev //
    lib.optionalAttrs ((builtins.length common.runtimeLibs) > 0) {
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
      postInstall = ''
        ${prev.postInstall or ""}
        for f in $out/bin/*; do
          wrapProgram "$f" \
            --set LD_LIBRARY_PATH ${lib.makeLibraryPath common.runtimeLibs}
        done
      '';
    };
  desktopItemOv = prev:
    prev //
    lib.optionalAttrs mkDesktopFile {
      nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.copyDesktopItems ];
      desktopItems = (prev.desktopItems or [ ]) ++ [ desktopFile ];
    };
  applyOverrides = prev:
    lib.pipe prev [
      desktopItemOv
      runtimeLibsOv
    ];

  library = packageMetadata.library or false;
  # Specify --package if we are building in a workspace
  packageOption = lib.optionals (! isNull common.memberName) [ "--package" cargoPkg.name ];
  # Specify --features if we have enabled features other than the default ones
  featuresOption = lib.optionals ((builtins.length features) > 0) ([ "--features" ] ++ features);
  releaseOption = lib.optional release "--release";

  baseBRPConfig = applyOverrides ({
    pname = pkgName;
    inherit (cargoPkg) version;
    inherit (common) root buildInputs nativeBuildInputs cargoVendorHash;
    stdenv = pkgs.stdenvNoCC;
    inherit doCheck;
    dontFixup = !release;
    buildFlags = releaseOption ++ packageOption ++ featuresOption;
    checkFlags = releaseOption ++ packageOption ++ featuresOption;
  } // common.env);

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
    override = _: {
      # Use no cc stdenv, since we supply our own cc
      stdenv = pkgs.stdenvNoCC;
    } // common.env;
    overrideMain =
      prev:
      let
        overrode =
          applyOverrides (prev // common.env // {
            inherit meta;
            dontFixup = !release;
            # Use no cc stdenv, since we supply our own cc
            stdenv = pkgs.stdenvNoCC;
          });
      in
      overrode // (common.overrides.mainBuild common overrode);
    copyLibs = library;
    inherit release doCheck doDoc;
  };

  baseCrate2NixConfig =
    let
      # Override that adds stuff like make wrapper, desktop file, common envs and so on.
      overrideMain = prev: applyOverrides ({
        dontFixup = !release;
        nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ common.nativeBuildInputs;
        buildInputs = (prev.buildInputs or [ ]) ++ common.buildInputs;
      } // common.env);
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
              overrode = overrideMain prev;
              # Second override (might contain user provided values)
              overroded = overrode // (crateOverrides.${cargoPkg.name} or (_: { })) overrode;
            in
            # Third override (is entirely user provided)
            overroded // (common.overrides.mainBuild common overrode);
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
              memberName = if isNull common.memberName then null else cargoPkg.name;
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
        # TODO: probably provide a way to override the inner derivation?
      pkgs.symlinkJoin {
        inherit meta;
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
