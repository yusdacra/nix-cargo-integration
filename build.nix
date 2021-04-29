{ release ? false
, doCheck ? false
, doDoc ? false
, features ? [ ]
, common
,
}:
let
  inherit (common) pkgs lib packageMetadata cargoPkg buildPlatform;

  desktopFileMetadata = packageMetadata.desktopFile or null;
  mkDesktopFile = ! isNull desktopFileMetadata;

  # TODO convert cargo maintainers to nixpkgs maintainers
  meta = with lib; ({
    description = cargoPkg.description or "${cargoPkg.name} is a Rust project.";
    platforms = [ common.system ];
  } // (optionalAttrs (builtins.hasAttr "license" cargoPkg) { license = licenses."${lib.cargoLicenseToNixpkgs cargoPkg.license}"; })
  // (optionalAttrs (builtins.hasAttr "homepage" cargoPkg) { inherit (cargoPkg) homepage; })
  // (optionalAttrs (builtins.hasAttr "longDescription" packageMetadata) { inherit (packageMetadata) longDescription; }));

  desktopFile =
    let
      name = cargoPkg.name;
      makeIcon = icon:
        if (lib.hasPrefix "./" icon)
        then (common.root + "/${lib.removePrefix "./" icon}")
        else icon;
      desktopFilePath = common.root + "/${lib.removePrefix "./" desktopFileMetadata}";
    in
    if builtins.isString desktopFileMetadata
    then
      pkgs.runCommand "${cargoPkg.name}-desktopFileLink" { } ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else with lib;
    ((pkgs.makeDesktopItem {
      inherit name;
      exec = packageMetadata.executable or name;
      comment = desktopFileMetadata.comment or meta.description;
      desktopName = desktopFileMetadata.name or name;
    }) // (optionalAttrs (builtins.hasAttr "icon" desktopFileMetadata) { icon = makeIcon desktopFileMetadata.icon; })
    // (optionalAttrs (builtins.hasAttr "genericName" desktopFileMetadata) { inherit (desktopFileMetadata) genericName; })
    // (optionalAttrs (builtins.hasAttr "categories" desktopFileMetadata) { inherit (desktopFileMetadata) categories; }));

  runtimeLibsEnv = prev:
    lib.optionalAttrs ((builtins.length common.runtimeLibs) > 0) {
      postInstall = ''
        ${prev.postInstall or ""}
        for f in $out/bin/*; do
          wrapProgram "$f" \
            --set LD_LIBRARY_PATH ${lib.makeLibraryPath common.runtimeLibs}
        done
      '';
    };

  baseNaerskConfig =
    let
      library = packageMetadata.library or false;
      packageOption = lib.optionals (! isNull common.memberName) [ "--package" cargoPkg.name ];
      featuresOption = lib.optionals ((builtins.length features) > 0) ([ "--features" ] ++ features);
    in
    {
      inherit (common) root nativeBuildInputs buildInputs;
      inherit (cargoPkg) name version;
      allRefs = true;
      gitSubmodules = true;
      # WORKAROUND doctests fail to compile (they compile with nightly cargo but then rustdoc fails)
      cargoBuildOptions = def: def ++ packageOption ++ featuresOption;
      cargoTestOptions = def:
        def ++ [ "--tests" "--bins" "--examples" ]
        ++ lib.optional library "--lib"
        ++ packageOption ++ featuresOption;
      override = _: {
        stdenv = common.buildStdenv;
      } // common.env;
      overrideMain =
        let
          runtimeWrapOverride = prev:
            prev // {
              nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.makeWrapper ];
            } // runtimeLibsEnv prev;
          desktopOverride = prev: prev // lib.optionalAttrs mkDesktopFile {
            nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.copyDesktopItems ];
            desktopItems = [ desktopFile ];
          };
        in
        prev:
        let
          overrode =
            runtimeWrapOverride
              (desktopOverride (prev // common.env // {
                inherit meta;
                dontFixup = !release;
                stdenv = common.buildStdenv;
              }));
        in
        overrode // (common.overrides.mainBuild common overrode);
      copyLibs = library;
      inherit release doCheck doDoc;
    };

  baseCrate2NixConfig =
    let
      overrideMain = prev: {
        dontFixup = !release;
        nativeBuildInputs =
          (prev.nativeBuildInputs or [ ])
            ++ common.nativeBuildInputs
            ++ [ pkgs.makeWrapper ]
            ++ lib.optional mkDesktopFile pkgs.copyDesktopItems;
        buildInputs = (prev.buildInputs or [ ]) ++ common.buildInputs;
      } // runtimeLibsEnv prev
      // lib.optionalAttrs mkDesktopFile {
        desktopItems = [ desktopFile ];
      }
      // common.env;
    in
    {
      inherit pkgs release;
      runTests = doCheck;
      rootFeatures =
        let def = lib.optional (builtins.hasAttr "default" (common.cargoToml.features or { })) "default"; in
        if (builtins.length features) > 0
        then features ++ def
        else def;
      defaultCrateOverrides =
        let
          crateOverrides =
            builtins.mapAttrs
              (_: v: (prev: builtins.removeAttrs (v prev) [ "propagatedEnv" ]))
              common.crateOverrides;
        in
        crateOverrides // {
          ${cargoPkg.name} = prev:
            let
              overrode = overrideMain prev;
              overroded = overrode // (crateOverrides.${cargoPkg.name} or (_: { })) overrode;
            in
            overroded // (common.overrides.mainBuild common overrode);
        };
    };

  overrideConfig = config:
    config // (common.overrides.build common config);
in
if lib.isNaersk buildPlatform
then
  let config = overrideConfig baseNaerskConfig; in
  {
    inherit config;
    package = lib.buildCrate config;
  }
else if lib.isCrate2Nix buildPlatform
then
  let config = overrideConfig baseCrate2NixConfig; in
  {
    inherit config;
    package =
      let
        pkg = lib.buildCrate
          (
            {
              inherit (common) root;
              memberName = if isNull common.memberName then null else cargoPkg.name;
              additionalCargoNixArgs =
                lib.optionals
                  ((builtins.length config.rootFeatures) > 0)
                  [ "--no-default-features" "--features" (lib.concatStringsSep " " config.rootFeatures) ];
            } // (builtins.removeAttrs config [ "runTests" ])
          );
      in
      # This is a workaround so that crate2nix doesnt get built until we actually build
        # otherwise nix will try to build it even if you only run `nix flake show`
      pkgs.symlinkJoin {
        inherit meta;
        name = "${cargoPkg.name}-${cargoPkg.version}";
        paths = [
          (pkg.override { inherit (config) runTests; })
        ];
      };
  }
else throw "invalid build platform: ${buildPlatform}"
