{
  rawPkg,
  profiles,
  runtimeLibs,
  pkgs,
}: let
  l = pkgs.lib // builtins;
  makePackage = profile: conf: let
    flags =
      if conf.features == null
      then []
      else if l.length conf.features > 0
      then [
        "--no-default-features"
        "--features"
        "${l.concatStringsSep "," conf.features}"
      ]
      else ["--no-default-features"];
    pkg =
      (rawPkg.extendModules {
        modules = [
          conf.drvConfig
          {
            rust-crane = {
              buildProfile = profile;
              buildFlags = flags;
              testProfile = profile;
              testFlags = flags;
              runTests = conf.runTests;
              depsDrv = conf.depsDrvConfig;
            };
          }
        ];
      })
      .config
      .public;
  in
    if l.length runtimeLibs > 0
    then
      pkgs.runCommand
      pkg.name
      {
        inherit (pkg) name version;
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
          chmod +x "$bin"
          ${pkgs.patchelf}/bin/patchelf --set-rpath "${l.makeLibraryPath runtimeLibs}" "$bin"
        done
      ''
    else pkg;
in
  l.mapAttrs makePackage profiles
