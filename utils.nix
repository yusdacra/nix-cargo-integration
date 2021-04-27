pkgs:
let
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

  makeCrateOverrides =
    { rawTomlOverrides ? { }
    , crateName
    ,
    }:
    let
      lib = pkgs.lib;

      commonOverride = {
        ${crateName} = prev: {
          buildInputs = (prev.buildInputs or [ ]) ++ [ pkgs.zlib ];
          nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.binutils ];
        };
      };
      tomlOverrides = builtins.mapAttrs
        (_: crate: prev: {
          nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ (resolveToPkgs (crate.nativeBuildInputs or [ ]));
          buildInputs = (prev.buildInputs or [ ]) ++ (resolveToPkgs (crate.buildInputs or [ ]));
        } // (crate.env or { }) // { propagatedEnv = crate.env or { }; })
        rawTomlOverrides;
      extraOverrides = import ./extraCrateOverrides.nix { inherit pkgs; };
    in
    builtins.foldl'
      (acc: el: lib.genAttrs (lib.unique ((builtins.attrNames acc) ++ (builtins.attrNames el))) (name:
      let
        isEl = builtins.hasAttr name el;
        isAcc = builtins.hasAttr name acc;
      in
      if isAcc && isEl
      then pp: let accPp = acc.${name} pp; in accPp // (el.${name} accPp)
      else if isAcc
      then acc.${name}
      else if isEl
      then el.${name}
      else _: { }
      ))
      pkgs.defaultCrateOverrides
      [ tomlOverrides extraOverrides commonOverride ];
}
