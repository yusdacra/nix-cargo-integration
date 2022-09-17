# Library utilities that depend on a package set.
{
  # an imported nixpkgs package set
  pkgs,
  # the rust toolchain we use
  rustToolchain,
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
    if l.isString key
    then l.foldl' op pkgs attrs
    else key;
  # Resolves a list of string keys to packages.
  resolveToPkgs = l.map resolveToPkg;
  evalPkgs = expr: l.eval expr {inherit pkgs;};
in {
  inherit resolveToPkg resolveToPkgs evalPkgs;

  # Creates crate overrides.
  makeTomlOverrides = rawTomlOverrides:
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

  # dream2nix build crate.
  mkCrateOutputs = dream2nix.realizeProjects;

  wrapDerivation = old: args: script:
    pkgs.runCommand old.name
    (
      {
        inherit (old) pname version meta;
        passthru = old.passthru or {};
      }
      // args
    )
    ''
      cp -r --no-preserve=mode,ownership $out/
      ${script}
    '';
}
