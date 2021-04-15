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

  package = with pkgs;
    let
      library = packageMetadata.library or false;
      baseConfig = {
        inherit (common) root nativeBuildInputs buildInputs;
        inherit (cargoPkg) name version;
        src = if isNull common.memberName then common.root else common.root + "/${common.memberName}";
        # WORKAROUND doctests fail to compile (they compile with nightly cargo but then rustdoc fails)
        cargoTestOptions = def: def ++ [ "--tests" "--bins" "--examples" ] ++ (lib.optional library "--lib");
        override = (prev: common.env);
        overrideMain = (prev: common.env // { inherit meta; } // (
          lib.optionalAttrs (!(isNull desktopFileMetadata))
            { nativeBuildInputs = prev.nativeBuildInputs ++ [ copyDesktopItems ]; desktopItems = [ desktopFile ]; }
        ));
        copyLibs = library;
        inherit release doCheck doDoc;
      };
    in
    naersk.buildPackage (baseConfig // (common.overrides.build common baseConfig));
in
package
