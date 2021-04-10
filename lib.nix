{ sources }:
let
  importCargoToml = src: builtins.fromTOML (builtins.readFile (src + "/Cargo.toml"));

  makeFlakeOutputs = src:
    let
      cargoToml = importCargoToml src;
      flakeUtils = import sources.flakeUtils;
    in
    with flakeUtils;
    eachSystem (nixMetadata.systems or defaultSystems) (makeOutputs src);

  makeOutputs = src: system:
    let
      common = import ./common.nix {
        cargoPkg = (importCargoToml src).package;
        inherit system src sources;
      };
      cargoPkg = common.cargoPkg;
      nixMetadata = common.nixMetadata;
      lib = common.pkgs.lib;

      packages = {
        # Compiles slower but has tests and faster executable
        "${cargoPkg.name}" = import ./build.nix {
          inherit common;
          doCheck = true;
          release = true;
        };
        # Compiles faster but no tests and slower executable
        "${cargoPkg.name}-debug" = import ./build.nix { inherit common; };
      };
      checks = {
        # Compiles faster but has tests and slower executable
        "${cargoPkg.name}-tests" = import ./build.nix { inherit common; doCheck = true; };
      };
      mkApp = n: v: mkApp {
        name = n;
        drv = v;
        exePath = "/bin/${nixMetadata.executable or cargoPkg.name}";
      };
      apps = builtins.mapAttrs mkApp packages;
    in
    {
      devShell = import ./devShell.nix { inherit common; };
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
  inherit makeOutputs;
} // (if !(isNull (sources.flakeUtils or null)) then { inherit makeFlakeOutputs; } else { })
