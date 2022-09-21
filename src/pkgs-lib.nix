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
  processOverrides = rawOverrides: let
    makeFromAttrs = crate: prev: let
      envsEvaled =
        l.mapAttrs
        (_: value: evalPkgs value)
        (crate.env or {});
      getInputs = name:
        l.unique (
          (prev.${name} or []) ++ (resolveToPkgs (crate.${name} or []))
        );
    in
      (l.removeAttrs crate ["env"])
      // (
        l.genAttrs
        [
          "buildInputs"
          "nativeBuildInputs"
          "propagatedBuildInputs"
        ]
        getInputs
      )
      // envsEvaled
      // {
        passthru =
          (prev.passthru or {})
          // (crate.passthru or {})
          // {env = envsEvaled;};
      };
  in
    l.mapAttrs
    (
      crateName: overrides:
        l.mapAttrs
        (
          overrideName: override:
            if ! override ? overrideAttrs
            then {overrideAttrs = makeFromAttrs override;}
            else override
        )
        overrides
    )
    (l.dbgX "rawOverrides" rawOverrides);

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
      cp -rs --no-preserve=mode,ownership ${old} $out/
      ${script}
    '';
}
