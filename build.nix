{ release ? false
, doCheck ? false
, doDoc ? false
, common
,
}:
let
  inherit (common) pkgs packageMetadata cargoPkg;

  desktopFileMetadata = packageMetadata.desktopFile or null;

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

  package =
    let
      lib = common.pkgs.lib;
      pkgs = common.pkgs;

      library = packageMetadata.library or false;
      app = packageMetadata.app or false;
      packageOption = lib.optionals (! isNull common.memberName) [ "--package" cargoPkg.name ];

      baseConfig = {
        inherit (common) root nativeBuildInputs buildInputs;
        inherit (cargoPkg) name version;
        allRefs = true;
        gitSubmodules = true;
        # WORKAROUND doctests fail to compile (they compile with nightly cargo but then rustdoc fails)
        cargoBuildOptions = def: def ++ packageOption;
        cargoTestOptions = def: def ++ [ "--tests" "--bins" "--examples" ] ++ (lib.optional library "--lib") ++ packageOption;
        override = _: common.env;
        overrideMain =
          let
            runtimeWrapOverride = prev:
              prev // (lib.optionalAttrs app {
                nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.makeWrapper ];
                postInstall = ''
                  ${prev.postInstall or ""}
                  wrapProgram $out/bin/${packageMetadata.executable or cargoPkg.name}\
                    --set LD_LIBRARY_PATH ${lib.makeLibraryPath common.runtimeLibs}
                '';
              });
            desktopOverride = prev: prev // (lib.optionalAttrs (! isNull desktopFileMetadata)
              { nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.copyDesktopItems ]; desktopItems = [ desktopFile ]; });
          in
          prev: runtimeWrapOverride (desktopOverride (prev // common.env // { inherit meta; }));
        copyLibs = library;
        inherit release doCheck doDoc;
      };
    in
    pkgs.naersk.buildPackage (baseConfig // (common.overrides.build common baseConfig));
in
package
