{
  rawPkg,
  targets,
  profiles,
  useClippy,
  runtimeLibs,
  pkgs,
}: let
  l = pkgs.lib // builtins;
  makePackage = target: targetConf:
    l.mapAttrs
    (
      profile: profileConf:
        _makePackage profile profileConf target targetConf
    )
    (
      if targetConf.profiles != null
      then
        (
          l.filterAttrs
          (profile: _: l.any (op: profile == op) targetConf.profiles)
          profiles
        )
      else profiles
    );
  _makePackage = profile: profileConf: target: targetConf: let
    flags =
      if profileConf.features == null
      then []
      else if l.length profileConf.features > 0
      then [
        "--no-default-features"
        "--features"
        "${l.concatStringsSep "," profileConf.features}"
      ]
      else ["--no-default-features"];
    checkCommand =
      if useClippy
      then "clippy"
      else "check";
    pkg =
      (rawPkg.extendModules {
        modules = [
          profileConf.drvConfig
          targetConf.drvConfig
          {
            env.CARGO_BUILD_TARGET = target;
            rust-crane = {
              inherit checkCommand;
              buildProfile = profile;
              buildFlags = flags;
              testProfile = profile;
              testFlags = flags;
              runTests = profileConf.runTests;
              depsDrv = l.mkMerge [
                profileConf.depsDrvConfig
                targetConf.depsDrvConfig
                {env.CARGO_BUILD_TARGET = target;}
              ];
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
  l.mapAttrs makePackage targets
