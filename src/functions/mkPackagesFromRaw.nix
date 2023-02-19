{
  rawPkg,
  profiles,
  runtimeLibs,
  pkgs,
}: let
  l = pkgs.lib // builtins;
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
    pkg = rawPkg.override (
      common
      // {
        cargoArtifacts = rawPkg.passthru.dependencies.override common;
        dontCheck = !conf.runTests;
      }
    );
  in
    if l.length runtimeLibs > 0
    then
      pkgs.runCommand
      pkg.name
      {
        inherit (pkg) pname version;
        meta = pkg.meta or {};
        passthru =
          (pkg.passthru or {})
          // {
            unwrapped = pkg;
          };
      }
      ''
        mkdir -p $out
        cp -r --no-preserve=mode,ownership ${pkg}/* $out/
        for bin in $out/bin/*; do
          ${pkgs.patchelf}/bin/patchelf --set-rpath "${l.makeLibraryPath runtimeLibs}" "$bin"
        done
      ''
    else pkg;
in
  l.mapAttrs makePackage profiles
