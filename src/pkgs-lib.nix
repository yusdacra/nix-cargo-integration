# Library utilities that depend on a package set.
{
  # an imported nixpkgs package set
  pkgs,
  # the package set with rust toolchain to use
  pkgsWithRust,
  # an NCI library
  lib,
  # dream2nix tools
  dream2nix,
}: let
  l = lib;

  # Resolves some string key to a package.
  resolveToPkg = key: let
    attrs = l.filter l.isString (l.split "\\." key);
    op = sum: attr: sum.${attr} or (throw "package \"${key}\" not found");
  in
    l.foldl' op pkgs attrs;
  # Resolves a list of string keys to packages.
  resolveToPkgs = l.map resolveToPkg;
  evalPkgs = expr: l.eval expr {inherit pkgs;};
in {
  inherit resolveToPkg resolveToPkgs evalPkgs;

  # Creates crate overrides.
  makeCrateOverrides = {
    rawTomlOverrides ? {},
    cCompiler ? pkgs.gcc,
    useCCompilerBintools ? true,
  }: let
    # base inputs for each crate.
    # this includes settting the stdenv and adding a C compiler
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

    # Overrides from `rawTomlOverrides`
    tomlOverrides =
      l.mapAttrs
      (_: crate: prev: let
        envsEvaled =
          l.mapAttrs
          (_: value: evalPkgs value)
          (crate.env or {});
      in
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
        // envsEvaled
        // {propagatedEnv = envsEvaled;})
      (l.dbgX "rawTomlOverrides" rawTomlOverrides);

    # Our overrides (+ default crate overrides from nixpkgs)
    extraOverrides =
      import ./extra-crate-overrides.nix {inherit pkgs pkgsWithRust lib;};

    collectOverride = acc: el: name: let
      getOverride = x: x.${name} or (_: {});
      accOverride = getOverride acc;
      elOverride = getOverride el;
    in
      attrs:
        l.applyOverrides
        attrs
        [baseConf accOverride elOverride];
  in
    l.foldl'
    (
      acc: el:
        l.genAttrs
        (l.unique ((l.attrNames acc) ++ (l.attrNames el)))
        (collectOverride acc el)
    )
    {}
    [
      (l.dbgX "tomlOverrides" tomlOverrides)
      extraOverrides
    ];

  # dream2nix build crate.
  buildCrate = args: let
    outputs = dream2nix.makeFlakeOutputs args;
  in
    outputs.packages.${pkgs.system}.${args.pname};
}
