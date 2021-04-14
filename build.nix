{ release ? false
, doCheck ? false
, doDoc ? false
, common
,
}:
let
  inherit (common) pkgs nixMetadata cargoPkg;

  xdgMetadata = nixMetadata.xdg or null;
  makeDesktopFile = xdgMetadata.enable or false;

  cargoLicenseToNixpkgs = license:
    let
      l = pkgs.lib.toLower license;
    in
      {
        "gplv3" = "gpl3";
        "gplv2" = "gpl2";
      }."${l}" or l;

  meta = with pkgs.lib; ({
    description = cargoPkg.description or "${cargoPkg.name} is a Rust project.";
  } // (optionalAttrs (builtins.hasAttr "license" cargoPkg) { license = licenses."${cargoLicenseToNixpkgs cargoPkg.license}"; })
  // (optionalAttrs (builtins.hasAttr "homepage" cargoPkg) { inherit (cargoPkg) homepage; })
  // (optionalAttrs (builtins.hasAttr "longDescription" nixMetadata) { inherit (nixMetadata) longDescription; }));

  desktopFile =
    with pkgs.lib;
    let
      name = cargoPkg.name;
      makeIcon = icon:
        if (hasPrefix "./" icon)
        then (common.root + "/" + (removePrefix "./" icon))
        else icon;
    in
    ((pkgs.makeDesktopItem {
      inherit name;
      exec = nixMetadata.executable or name;
      comment = xdgMetadata.comment or meta.description;
      desktopName = xdgMetadata.name or name;
    }) // (optionalAttrs (builtins.hasAttr "icon" xdgMetadata) { icon = makeIcon xdgMetadata.icon; })
    // (optionalAttrs (builtins.hasAttr "genericName" xdgMetadata) { inherit (xdgMetadata) genericName; })
    // (optionalAttrs (builtins.hasAttr "categories" xdgMetadata) { inherit (xdgMetadata) categories; }));

  package = with pkgs;
    let
      library = nixMetadata.library or false;
      baseConfig = {
        inherit (common) root nativeBuildInputs buildInputs;
        inherit (cargoPkg) name version;
        src = if common.isRootPkg then common.root else common.root + "/${cargoPkg.name}";
        # WORKAROUND doctests fail to compile (they compile with nightly cargo but then rustdoc fails)
        cargoTestOptions = def: def ++ [ "--tests" "--bins" "--examples" ] ++ (lib.optional library "--lib");
        override = (prev: common.env);
        overrideMain = (prev: common.env // { inherit meta; } // (
          lib.optionalAttrs makeDesktopFile
            { nativeBuildInputs = prev.nativeBuildInputs ++ [ copyDesktopItems ]; desktopItems = [ desktopFile ]; }
        ));
        copyLibs = library;
        inherit release doCheck doDoc;
      };
    in
    naersk.buildPackage (baseConfig // (common.overrides.build common baseConfig));
in
package
