pkgs:
let
  lib = pkgs.lib;

  # courtesy of devshell
  resolveToPkg = key:
    let
      attrs = builtins.filter builtins.isString (builtins.split "\\." key);
      op = sum: attr: sum.${attr} or (throw "package \"${key}\" not found");
    in
    builtins.foldl' op pkgs attrs;
  resolveToPkgs = builtins.map resolveToPkg;
in
{
  inherit resolveToPkg resolveToPkgs;

  # Tries to convert a cargo license to nixpkgs license.
  cargoLicenseToNixpkgs = license:
    let
      l = lib.toLower license;
    in
      {
        "gplv3" = "gpl3";
        "gplv2" = "gpl2";
        "gpl-3.0" = "gpl3";
        "gpl-2.0" = "gpl2";
        "mpl-2.0" = "mpl20";
        "mpl-1.0" = "mpl10";
      }."${l}" or l;

  # Creates crate overrides for crate2nix to use.
  # The crate overrides will be "collected" in common.nix for naersk and devshell to use them.
  makeCrateOverrides =
    { rawTomlOverrides ? { }
    , cCompiler ? pkgs.gcc
    , useCCompilerBintools ? true
    , crateName
    }:
    let
      mainOverride = {
        ${crateName} = prev: {
          buildInputs = (prev.buildInputs or [ ]) ++ [ pkgs.zlib ];
        };
      };
      baseConf = prev: {
        # No CC since we provide our own compiler
        stdenv = pkgs.stdenvNoCC;
        nativeBuildInputs = lib.unique ((prev.nativeBuildInputs or [ ]) ++ [ cCompiler ] ++ (lib.optional useCCompilerBintools cCompiler.bintools));
        # Set CC to "cc" to workaround some weird issues (and to not bother with finding exact compiler path)
        CC = "cc";
      };
      tomlOverrides = builtins.mapAttrs
        (_: crate: prev: {
          nativeBuildInputs = lib.unique ((prev.nativeBuildInputs or [ ]) ++ (resolveToPkgs (crate.nativeBuildInputs or [ ])));
          buildInputs = lib.unique ((prev.buildInputs or [ ]) ++ (resolveToPkgs (crate.buildInputs or [ ])));
        } // (crate.env or { }) // { propagatedEnv = crate.env or { }; })
        rawTomlOverrides;
      extraOverrides = import ./extraCrateOverrides.nix pkgs;
      collectOverride = acc: el: name:
        let
          getOverride = x: x.${name} or (_: { });
          accOverride = getOverride acc;
          elOverride = getOverride el;
        in
        attrs:
        let
          overrodedAccBase = accOverride attrs;
          overrodedAcc = overrodedAccBase // (baseConf overrodedAccBase);
        in
        overrodedAcc // (elOverride overrodedAcc);
    in
    builtins.foldl'
      (acc: el: lib.genAttrs (lib.unique ((builtins.attrNames acc) ++ (builtins.attrNames el))) (collectOverride acc el))
      pkgs.defaultCrateOverrides
      [ tomlOverrides extraOverrides mainOverride ];
} // lib.optionalAttrs (builtins.hasAttr "rustPlatform" pkgs) {
  # buildRustPackage build crate.
  buildCrate =
    { root
    , memberName ? null
    , cargoVendorHash ? lib.fakeHash
    , ... # pass everything else to buildRustPackage
    }@args:
    let
      inherit (builtins) readFile fromTOML;

      tomlPath =
        if isNull memberName
        then root + "/Cargo.toml"
        else root + "/${memberName}/Cargo.toml";
      lockFile = root + "/Cargo.lock";

      cargoToml = fromTOML (readFile tomlPath);
    in
    pkgs.rustPlatform.buildRustPackage
      {
        cargoHash = cargoVendorHash;
        pname = cargoToml.package.name;
        version = cargoToml.package.version;
        src = root;
      } // (lib.optionalAttrs (isNull memberName) {
      sourceRoot = memberName;
    }) // (builtins.removeAttrs args [ "root" "memberName" ]);
} // lib.optionalAttrs (builtins.hasAttr "crate2nixTools" pkgs) {
  # crate2nix build crate.
  buildCrate =
    { root
    , memberName ? null
    , additionalCargoNixArgs ? [ ]
    , ... # pass everything else to crate2nix
    }@args:
    let
      generatedCargoNix = pkgs.crate2nixTools.generatedCargoNix {
        name = lib.strings.sanitizeDerivationName (builtins.baseNameOf root);
        src = root;
        inherit additionalCargoNixArgs;
      };
      cargoNix = import generatedCargoNix (
        (builtins.removeAttrs args [ "root" "additionalCargoNixArgs" "memberName" ])
        // { inherit pkgs; }
      );
    in
    if isNull memberName
    then cargoNix.rootCrate.build
    else cargoNix.workspaceMembers.${memberName}.build;
} // lib.optionalAttrs (builtins.hasAttr "naersk" pkgs) {
  # naersk build crate.
  buildCrate = pkgs.naersk.buildPackage;
}
