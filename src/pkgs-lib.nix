# Library utilities that depend on a package set.
{
  # an imported nixpkgs package set
  pkgs,
  # an NCI library
  lib,
  # dream2nix tools
  dream2nix,
}:
let
  l = lib;

  # Resolves some string key to a package.
  resolveToPkg = key: let
    attrs = l.filter l.isString (l.split "\\." key);
    op = sum: attr: sum.${attr} or (throw "package \"${key}\" not found");
  in
    l.foldl' op pkgs attrs;
  # Resolves a list of string keys to packages.
  resolveToPkgs = l.map resolveToPkg;
in {
  inherit resolveToPkg resolveToPkgs;

  # Creates crate overrides.
  makeCrateOverrides =
    {
      rawTomlOverrides ? {},
      cCompiler ? pkgs.gcc,
      useCCompilerBintools ? true,
      crateName,
    }:
    let
      baseConf = prev: {
        # No CC since we provide our own compiler
        stdenv =
          pkgs.stdenvNoCC
          // {
            cc = cCompiler;
          };
        nativeBuildInputs = l.unique (
          (prev.nativeBuildInputs or [])
          ++ [cCompiler]
          ++ (l.optional useCCompilerBintools cCompiler.bintools)
        );
        # Set CC to "cc" to workaround some weird issues (and to not bother with finding exact compiler path)
        CC = "cc";
      };
      tomlOverrides = l.mapAttrs
      (_: crate: prev:
        {
          nativeBuildInputs = l.unique (
            (prev.nativeBuildInputs or [])
            ++ (resolveToPkgs (crate.nativeBuildInputs or []))
          );
          buildInputs = l.unique (
            (prev.buildInputs or [])
            ++ (resolveToPkgs (crate.buildInputs or []))
          );
        }
        // (crate.env or {})
        // { propagatedEnv = crate.env or {}; })
      (l.dbgX "rawTomlOverrides" rawTomlOverrides);
      extraOverrides = import ./extra-crate-overrides.nix pkgs;
      collectOverride = acc: el: name: let
        getOverride = x: x.${name} or (_: {});
        accOverride = getOverride acc;
        elOverride = getOverride el;
      in
        attrs: l.applyOverrides attrs [baseConf accOverride elOverride];
      finalOverrides =
        l.foldl'
        (acc: el:
          l.genAttrs
          (l.unique ((l.attrNames acc) ++ (l.attrNames el)))
          (collectOverride acc el))
        pkgs.defaultCrateOverrides
        [
          (l.dbgX "tomlOverrides" tomlOverrides)
          extraOverrides
        ];
    in
      finalOverrides;

  # dream2nix build crate.
  buildCrate =
    {
      root,
      memberName ? null,
      ...
      # pass everything else to dream2nix
    }
    @ args:
    let
      attrs =
        {
          source = root;
        }
        // (l.removeAttrs args ["root" "memberName"]);
      outputs = dream2nix.riseAndShine attrs;
    in
      if memberName != null
      then outputs.packages.${pkgs.system}.${memberName}
      else outputs.defaultPackage.${pkgs.system};
}
