{ sources }:
let
  importCargoTOML = root: builtins.fromTOML (builtins.readFile (root + "/Cargo.toml"));
  flakeUtils = import sources.flakeUtils;

  makeOutputs =
    { root
    , overrides ? { } /* This can have overrides for the devshell env, build env or for both. */
    ,
    }:
    let
      cargoPkg = (importCargoTOML root).package;
    in
    with flakeUtils;
    eachSystem (cargoPkg.metadata.nix.systems or defaultSystems) (system: makeOutput { inherit overrides root cargoPkg system; });

  makeOutput = { root, cargoPkg, system, overrides ? { } }:
    let
      mkOverride = name: if (builtins.hasAttr name overrides) then { override = overrides."${name}"; } else { };

      common = import ./common.nix ({ inherit system root sources cargoPkg; } // (mkOverride "common"));
      nixMetadata = common.nixMetadata;
      lib = common.pkgs.lib;

      mkBuild = r: c: import ./build.nix ({
        inherit common;
        doCheck = c;
        release = r;
      } // (mkOverride "build"));
      mkApp = n: v: flakeUtils.mkApp {
        name = n;
        drv = v;
        exePath = "/bin/${nixMetadata.executable or cargoPkg.name}";
      };

      packages = {
        # Compiles slower but has tests and faster executable
        "${cargoPkg.name}" = mkBuild true true;
        # Compiles faster but no tests and slower executable
        "${cargoPkg.name}-debug" = mkBuild false false;
      };
      checks = {
        # Compiles faster but has tests and slower executable
        "${cargoPkg.name}-tests" = mkBuild false true;
      };
      apps = builtins.mapAttrs mkApp packages;
    in
    {
      devShell = import ./devShell.nix ({ inherit common; } // (mkOverride "shell"));
    } // (lib.optionalAttrs (nixMetadata.build or false) ({
      inherit packages checks;
      # Release build is the default package
      defaultPackage = packages."${cargoPkg.name}";
    } // (lib.optionalAttrs (nixMetadata.app or false) {
      inherit apps;
      # Release build is the default app
      defaultApp = apps."${cargoPkg.name}";
    })));
in
{
  inherit importCargoTOML makeOutput makeOutputs;
}
