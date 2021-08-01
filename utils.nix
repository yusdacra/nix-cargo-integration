attrs:
let
  pkgs = if builtins.isAttrs attrs then attrs.pkgs else attrs;
  lib = if builtins.isAttrs attrs then attrs.lib or pkgs.lib else pkgs.lib;

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

  # Creates a nixpkgs-compatible nix expression that uses `buildRustPackage`.
  createNixpkgsDrv = common: pkgs.writeTextFile {
    name = "${common.cargoPkg.name}.nix";
    text =
      let
        inherit (common) pkgs buildInputs nativeBuildInputs cargoVendorHash;
        inherit (builtins) any map hasAttr baseNameOf concatStringsSep filter length attrNames split isList;
        inherit (lib) optional optionalString cargoLicenseToNixpkgs mapAttrsToList getName init;
        has = i: any (oi: i == oi);

        clang = [ "clang-wrapper" "clang" ];
        gcc = [ "gcc-wrapper" "gcc" ];

        filterUnwanted = filter (n: !(has n (clang ++ gcc ++ [ "pkg-config-wrapper" "binutils-wrapper" ])));
        mapToName = map getName;
        concatForInput = i: concatStringsSep "" (map (p: "\n  ${p},") i);

        bi = filterUnwanted (mapToName buildInputs);
        nbi = (filterUnwanted (mapToName nativeBuildInputs)) ++ (optional common.mkRuntimeLibsOv "makeWrapper");
        runtimeLibs = "\${lib.makeLibraryPath (with pkgs; [ ${concatStringsSep " " (mapToName common.runtimeLibs)} ])}";
        stdenv = if any (n: has n clang) (mapToName nativeBuildInputs) then "clangStdenv" else null;
        putIfStdenv = optionalString (stdenv != null);

        runtimeLibsScript =
          concatStringsSep "\n" (
            map
              (line: "    ${line}")
              (init (
                filter
                  (list: if isList list then (length list) > 0 else true)
                  (split "\n" (common.mkRuntimeLibsScript runtimeLibs))
              ))
          );
      in
      ''
        { lib,
          rustPlatform,${putIfStdenv "\n  ${stdenv},"}
          fetchFromGitHub,${concatForInput bi} ${concatForInput nbi}
        }:
        rustPlatform.buildRustPackage {
          pname = ${common.cargoPkg.name};
          version = ${common.cargoPkg.version};${putIfStdenv "\n\n  stdenv = ${stdenv};"}

          # Change to use whatever source you want
          src = fetchFromGitHub {
            owner = "<enter owner>";
            repo = "${baseNameOf common.root}";
            rev = "<enter revision>";
            sha256 = lib.fakeHash;
          };

          cargoSha256 = ${if cargoVendorHash == lib.fakeHash then "lib.fakeHash" else "${cargoVendorHash}"};${
            optionalString
              ((length (attrNames common.env)) > 0)
              "\n\n${concatStringsSep "\n" (mapAttrsToList (n: v: "  ${n} = \"${toString v}\"") common.env)}"
          }

          buildInputs = [ ${concatStringsSep " " bi} ];
          nativeBuildInputs = [ ${concatStringsSep " " nbi} ];${
            optionalString
              common.mkRuntimeLibsOv
              "\n\n  postFixup = ''\n${runtimeLibsScript}\n  '';"
          }

          meta = with lib; {
            description = "${common.meta.description or "<enter description>"}";
            homepage = "${common.meta.homepage or "<enter homepage>"}";
            license = licenses.${cargoLicenseToNixpkgs (common.cargoPkg.license or "unfree")};
            maintainers = with maintainers; [ ];
          };
        }
      '';
  };

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
    , memberPath ? null
    , cargoVendorHash ? lib.fakeHash
    , ... # pass everything else to buildRustPackage
    }@args:
    let
      inherit (builtins) readFile fromTOML;

      # Find the Cargo.toml of the package we are trying to build.
      tomlPath =
        if isNull memberPath
        then root + "/Cargo.toml"
        else root + "/${memberPath}/Cargo.toml";
      lockFile = root + "/Cargo.lock";

      cargoToml = fromTOML (readFile tomlPath);
    in
    pkgs.rustPlatform.buildRustPackage
      {
        cargoHash = cargoVendorHash;
        pname = cargoToml.package.name;
        version = cargoToml.package.version;
        src = root;
      } // (lib.optionalAttrs (isNull memberPath) {
      # Set sourceRoot to member path if the package we are building is a member.
      sourceRoot = memberPath;
    }) // (builtins.removeAttrs args [ "root" "memberPath" "cargoVendorHash" ]);
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
