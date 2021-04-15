{ sources }:
let
  libb = import "${sources.nixpkgs}/lib/default.nix";

  importCargoTOML = root: builtins.fromTOML (builtins.readFile (root + "/Cargo.toml"));
  flakeUtils = import sources.flakeUtils;

  makeOutputs =
    { root
    , overrides ? { } /* This can have overrides for the devshell env, build env or for both. */
    ,
    }:
    let
      cargoToml = importCargoTOML root;
      rootPkg = cargoToml.package or null;
      workspaceToml = cargoToml.workspace or null;
      members = libb.genAttrs (workspaceToml.members or [ ]) (name: importCargoTOML (root + "/${name}"));

      workspaceMetadata = workspaceToml.metadata.nix or null;
      packageMetadata = rootPkg.metadata.nix or null;

      systems = workspaceMetadata.systems or packageMetadata.systems or flakeUtils.defaultSystems;
      mkCommon = memberName: cargoPkg: system: import ./common.nix { inherit memberName cargoPkg workspaceMetadata system root overrides sources; };

      rootOutputs = if !(isNull rootPkg) then makeOutputsFor systems (mkCommon null rootPkg) else { };
      rootDevshell = libb.optionalAttrs (builtins.hasAttr "devShell" rootOutputs) { devShell = rootOutputs.devShell; };
      memberOutputs' = libb.mapAttrsToList (name: value: makeOutputsFor systems (mkCommon name value.package)) members;
    in
    (libb.foldAttrs libb.recursiveUpdate { } (memberOutputs' ++ [ rootOutputs ])) // rootDevshell;

  makeOutputsFor = systems: mkCommon:
    flakeUtils.eachSystem systems (system: makeOutput (mkCommon system));

  makeOutput = common:
    let
      cargoPkg = common.cargoPkg;
      packageMetadata = common.packageMetadata;

      mkBuild = r: c: import ./build.nix {
        inherit common;
        doCheck = c;
        release = r;
      };
      mkApp = n: v: flakeUtils.mkApp {
        name = n;
        drv = v;
        exePath = "/bin/${packageMetadata.executable or cargoPkg.name}";
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
    { devShell = import ./devShell.nix common; } //
    (libb.optionalAttrs (packageMetadata.build or false) ({
      inherit packages checks;
      # Release build is the default package
      defaultPackage = packages."${cargoPkg.name}";
    } // (libb.optionalAttrs (packageMetadata.app or false) {
      inherit apps;
      # Release build is the default app
      defaultApp = apps."${cargoPkg.name}";
    })));
in
{
  inherit importCargoTOML makeOutput makeOutputs;
}
