{
  rawPkg,
  profiles,
  lib,
}: let
  l = lib // builtins;
  makePackage = profile: conf: let
    flags =
      if l.length conf.features > 0
      then ["--no-default-features" "--features"] ++ conf.features
      else [];
    common = {
      cargoTestProfile = profile;
      cargoBuildProfile = profile;
      cargoTestFlags = flags;
      cargoBuildFlags = flags;
    };
  in
    rawPkg.override (common
      // {
        cargoArtifacts = rawPkg.passthru.dependencies.override common;
        dontCheck = !conf.runTests;
      });
in
  l.mapAttrs makePackage profiles
