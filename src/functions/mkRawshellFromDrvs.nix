{
  # args
  name,
  drvs,
  # nixpkgs
  lib,
  mkShell,
  ...
}: let
  l = lib // builtins;

  filterIllegal = import ./filterDevshellIllegalVars.nix {inherit lib;};
  inputsNames = ["buildInputs" "nativeBuildInputs" "propagatedBuildInputs" "propagatedNativeBuildInputs"];
  getEnvs = drv: [
    (filterIllegal drv.config.env)
    (filterIllegal drv.config.rust-crane.depsDrv.env)
  ];
  getMkDerivations = drv: [
    (filterIllegal drv.config.mkDerivation)
    (filterIllegal drv.config.rust-crane.depsDrv.mkDerivation)
  ];
  combine = envs:
    l.foldl'
    (
      all: el: let
        mergeList = name: l.unique ((all.${name} or []) ++ (el.${name} or []));
      in
        all // el // (
          l.mapAttrs (name: _: mergeList name) (l.filterAttrs (_: l.isList) el)
        )
    )
    {}
    envs;
  _shellEnv = combine (l.flatten (l.map getEnvs drvs));
  _shellInputs = combine (l.flatten (l.map getMkDerivations drvs));
  shellAttrs =
    _shellEnv
    // _shellInputs
    // {
      inherit name;
      passthru.env = _shellEnv;
      passthru.packages = l.unique (l.flatten (l.map (name: _shellInputs.${name} or []) inputsNames));
    };
  final = (mkShell.override {stdenv = (lib.head drvs).out.stdenv;}) shellAttrs;
in
  final
