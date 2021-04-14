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
      members = map (name: importCargoTOML (root + "/${name}")) (workspaceToml.members or [ ]);

      workspaceMetadata = workspaceToml.metadata.nix or null;
      packageMetadata = rootPkg.metadata.nix or null;
      nixMetadata = if isNull workspaceMetadata then (if isNull packageMetadata then { } else packageMetadata) else workspaceMetadata;

      systems = nixMetadata.systems or flakeUtils.defaultSystems;
      mkCommon = cargoPkg: system: import ./common.nix { inherit cargoPkg nixMetadata system root overrides sources; };

      rootOutputs = if !(isNull rootPkg) then makeOutputsFor systems (mkCommon rootPkg) else { };
      rootDevshell = libb.optionalAttrs (builtins.hasAttr "devShell" rootOutputs) { devShell = rootOutputs.devShell; };
      memberOutputs' = map (member: makeOutputsFor systems (mkCommon member.package)) members;
    in
    (libb.foldAttrs libb.recursiveUpdate { } (memberOutputs' ++ [ rootOutputs ])) // rootDevshell;

  makeOutputsFor = systems: mkCommon:
    flakeUtils.eachSystem systems (system: makeOutput (mkCommon system));

  makeOutput = common:
    let
      cargoPkg = common.cargoPkg;
      nixMetadata = common.nixMetadata;

      mkBuild = r: c: import ./build.nix {
        inherit common;
        doCheck = c;
        release = r;
      };
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
    { devShell = import ./devShell.nix common; } //
    (libb.optionalAttrs (cargoPkg.metadata.nix.build or false) ({
      inherit packages checks;
      # Release build is the default package
      defaultPackage = packages."${cargoPkg.name}";
    } // (libb.optionalAttrs (cargoPkg.metadata.nix.app or false) {
      inherit apps;
      # Release build is the default app
      defaultApp = apps."${cargoPkg.name}";
    })));
in
{
  inherit importCargoTOML makeOutput makeOutputs;
}
