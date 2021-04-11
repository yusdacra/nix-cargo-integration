{ release ? false
, doCheck ? false
, doDoc ? false
, override ? (_: _: { })
, common
,
}:
with common;
let
  xdgMetadata = nixMetadata.xdg or null;
  makeDesktopFile = xdgMetadata.enable or false;

  meta = with pkgs.lib; ({
    description = cargoPkg.description or "${cargoPkg.name} is a Rust project.";
  } // (optionalAttrs (builtins.hasAttr "license" cargoPkg) { license = licenses."${toLower cargoPkg.license}"; })
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
        inherit (common) root;
        nativeBuildInputs = crateDeps.nativeBuildInputs;
        buildInputs = crateDeps.buildInputs;
        # WORKAROUND doctests fail to compile (they compile with nightly cargo but then rustdoc fails)
        cargoTestOptions = def: def ++ [ "--tests" "--bins" "--examples" ] ++ (lib.optional library "--lib");
        override = (prev: env);
        overrideMain = (prev: {
          inherit meta;
        } // (
          lib.optionalAttrs makeDesktopFile
            { nativeBuildInputs = prev.nativeBuildInputs ++ [ copyDesktopItems ]; desktopItems = [ desktopFile ]; }
        ));
        copyLibs = library;
        inherit release doCheck doDoc;
      };
    in
    naersk.buildPackage (baseConfig // (override common baseConfig));
in
package
