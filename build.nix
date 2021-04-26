{ release ? false
, doCheck ? false
, doDoc ? false
, features ? [ ]
, common
,
}:
let
  inherit (common) pkgs packageMetadata cargoPkg buildPlatform;

  desktopFileMetadata = packageMetadata.desktopFile or null;
  mkDesktopFile = ! isNull desktopFileMetadata;

  cargoLicenseToNixpkgs = license:
    let
      l = pkgs.lib.toLower license;
    in
      {
        "gplv3" = "gpl3";
        "gplv2" = "gpl2";
        "gpl-3.0" = "gpl3";
        "gpl-2.0" = "gpl2";
      }."${l}" or l;

  # TODO convert cargo maintainers to nixpkgs maintainers
  meta = with pkgs.lib; ({
    description = cargoPkg.description or "${cargoPkg.name} is a Rust project.";
    platforms = [ common.system ];
  } // (optionalAttrs (builtins.hasAttr "license" cargoPkg) { license = licenses."${cargoLicenseToNixpkgs cargoPkg.license}"; })
  // (optionalAttrs (builtins.hasAttr "homepage" cargoPkg) { inherit (cargoPkg) homepage; })
  // (optionalAttrs (builtins.hasAttr "longDescription" packageMetadata) { inherit (packageMetadata) longDescription; }));

  desktopFile =
    with pkgs.lib;
    let
      name = cargoPkg.name;
      makeIcon = icon:
        if (hasPrefix "./" icon)
        then (common.root + "/${removePrefix "./" icon}")
        else icon;
      desktopFilePath = common.root + "/${removePrefix "./" desktopFileMetadata}";
    in
    if builtins.isString desktopFileMetadata
    then
      pkgs.runCommand "${cargoPkg.name}-desktopFileLink" { } ''
        mkdir -p $out/share/applications
        ln -sf ${desktopFilePath} $out/share/applications
      ''
    else
      ((pkgs.makeDesktopItem {
        inherit name;
        exec = packageMetadata.executable or name;
        comment = desktopFileMetadata.comment or meta.description;
        desktopName = desktopFileMetadata.name or name;
      }) // (optionalAttrs (builtins.hasAttr "icon" desktopFileMetadata) { icon = makeIcon desktopFileMetadata.icon; })
      // (optionalAttrs (builtins.hasAttr "genericName" desktopFileMetadata) { inherit (desktopFileMetadata) genericName; })
      // (optionalAttrs (builtins.hasAttr "categories" desktopFileMetadata) { inherit (desktopFileMetadata) categories; }));

  runtimeLibsEnv =
    if (builtins.length common.runtimeLibs) > 0
    then pkgs.lib.makeLibraryPath common.runtimeLibs
    else null;

  baseNaerskConfig =
    let
      lib = common.pkgs.lib;
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
        ++ (lib.optional library "--lib")
        ++ packageOption ++ featuresOption;
      override = _: common.env;
      overrideMain =
        let
          runtimeWrapOverride = prev:
            prev // {
              nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.makeWrapper ];
            } // lib.optionalAttrs (! isNull runtimeLibsEnv) {
              postInstall = ''
                ${prev.postInstall or ""}
                for f in $out/bin/*; do
                  wrapProgram "$f" \
                    --set LD_LIBRARY_PATH ${runtimeLibsEnv}
                done
              '';
            };
          desktopOverride = prev: prev // (lib.optionalAttrs mkDesktopFile
            { nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.copyDesktopItems ]; desktopItems = [ desktopFile ]; });
        in
        prev: runtimeWrapOverride (desktopOverride (prev // common.env // { inherit meta; }));
      copyLibs = library;
      inherit release doCheck doDoc;
    };

  baseCrate2NixConfig =
    let
      lib = common.pkgs.lib;
      overrideMain = prev: {
        nativeBuildInputs =
          (prev.nativeBuildInputs or [ ])
            ++ common.nativeBuildInputs
            ++ [ pkgs.makeWrapper ]
            ++ lib.optional mkDesktopFile pkgs.copyDesktopItems;
        buildInputs = (prev.buildInputs or [ ]) ++ common.buildInputs;
      } // (lib.optionalAttrs (! isNull runtimeLibsEnv) {
        postInstall = ''
          ${prev.postInstall or ""}
          for f in $out/bin/*; do
            wrapProgram "$f" \
              --set LD_LIBRARY_PATH ${runtimeLibsEnv}
          done
        '';
      }) // (lib.optionalAttrs mkDesktopFile {
        desktopItems = [ desktopFile ];
      }) // common.env;
    in
    {
      inherit pkgs release;
      rootFeatures =
        let def = lib.optional (builtins.hasAttr "default" common.features) "default"; in
        if (builtins.length features) > 0
        then features ++ def
        else def;
      defaultCrateOverrides =
        pkgs.defaultCrateOverrides
        // (builtins.mapAttrs (_: v: (prev: lib.filterAttrs (n: _: n != "propagatedEnv") (v prev))) common.crateOverrides) // {
          ${cargoPkg.name} = prev:
            let overrode = overrideMain prev; in overrode // (common.overrides.mainBuild common overrode);
        };
    };

  overrideConfig = config:
    config // (common.overrides.build common config);
in
if buildPlatform == "naersk"
then
  let config = overrideConfig baseNaerskConfig; in
  {
    inherit config;
    package = pkgs.naersk.buildPackage config;
  }
else if buildPlatform == "crate2nix"
then
  let config = overrideConfig baseCrate2NixConfig; in
  {
    inherit config;
    package =
      let
        cargoNix = import
          (pkgs.crate2nixTools.generatedCargoNix {
            name = builtins.baseNameOf common.root;
            src = common.root;
            additionalCargoNixArgs =
              ([ "--no-default-features" ] ++ (
                pkgs.lib.optionals
                  ((builtins.length config.rootFeatures) > 0)
                  [ "--features" (pkgs.lib.concatStringsSep " " config.rootFeatures) ])
              );
          })
          config;
        pkg =
          if ! isNull common.memberName
          then cargoNix.workspaceMembers.${cargoPkg.name}.build
          else cargoNix.rootCrate.build;
      in
      # This is a workaround so that crate2nix doesnt get built until we actually build
        # otherwise nix will try to build it even if you only run `nix flake show`
      pkgs.symlinkJoin {
        inherit meta;
        name = "${cargoPkg.name}-${cargoPkg.version}";
        paths = [
          (pkg.override { runTests = doCheck; })
        ];
      };
  }
else throw "invalid build platform: ${buildPlatform}"
