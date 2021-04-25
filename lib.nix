{ sources }:
let
  libb = import "${sources.nixpkgs}/lib/default.nix";

  importCargoTOML = root: builtins.fromTOML (builtins.readFile (root + "/Cargo.toml"));
  flakeUtils = import sources.flakeUtils;

  makeOutputs =
    { root
    , overrides ? { }
    ,
    }:
    let
      cargoToml = importCargoTOML root;
      rootPkg = cargoToml.package or null;
      workspaceToml = cargoToml.workspace or null;
      members = libb.genAttrs (workspaceToml.members or [ ]) (name: importCargoTOML (root + "/${name}"));

      packageMetadata = rootPkg.metadata.nix or null;
      workspaceMetadata = if isNull workspaceToml then packageMetadata else workspaceToml.metadata.nix or null;

      systems = workspaceMetadata.systems or packageMetadata.systems or flakeUtils.defaultSystems;
      mkCommon = memberName: cargoPkg: bins: system: import ./common.nix { inherit memberName cargoPkg bins workspaceMetadata system root overrides sources; };

      rootCommons = if ! isNull rootPkg then libb.genAttrs systems (mkCommon null rootPkg cargoToml.bin) else null;
      memberCommons' = libb.mapAttrsToList (name: value: libb.genAttrs systems (mkCommon name value.package value.bin)) members;
      allCommons' = memberCommons' ++ (libb.optional (! isNull rootCommons) rootCommons);

      updateCommon = prev: final: prev // final // {
        runtimeLibs = (prev.runtimeLibs or [ ]) ++ final.runtimeLibs;
        buildInputs = (prev.buildInputs or [ ]) ++ final.buildInputs;
        nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ final.nativeBuildInputs;
        env = (prev.env or { }) // final.env;

        overrides = {
          shell = common: prevShell:
            ((prev.overrides.shell or (_: _: { })) common prevShell) // (final.overrides.shell common prevShell);
        };
      };
      devshellCombined = {
        devShell =
          libb.mapAttrs
            (_: import ./devShell.nix)
            (
              libb.mapAttrs
                (_: libb.foldl' updateCommon { })
                (
                  libb.foldl'
                    (acc: ele: libb.mapAttrs (n: v: acc.${n} ++ [ v ]) ele)
                    (libb.genAttrs systems (_: [ ]))
                    allCommons'
                )
            );
      };
      allOutputs' = libb.flatten (map (libb.mapAttrsToList (_: makeOutput)) allCommons');

      finalOutputs = (libb.foldAttrs libb.recursiveUpdate { } allOutputs') // devshellCombined;
    in
    finalOutputs;

  makeOutput = common:
    let
      inherit (common) cargoPkg packageMetadata system bins;

      mkBuild = r: c: import ./build.nix {
        inherit common;
        doCheck = c;
        release = r;
      };
      mkApp = exe: n: v:
        let
          ex =
            if isNull exe
            then { exeName = n; name = n; }
            else { exeName = exe; name = "${n}-${exe}"; };
        in
        {
          name = ex.name;
          value = flakeUtils.mkApp {
            name = ex.name;
            drv = v;
            exePath = "/bin/${ex.exeName}";
          };
        };

      packages = {
        ${system} = {
          "${cargoPkg.name}" = mkBuild true true;
          "${cargoPkg.name}-debug" = mkBuild false false;
        };
      };
      checks = {
        ${system} = {
          "${cargoPkg.name}-tests" = mkBuild false true;
        };
      };
      apps = {
        ${system} =
          let bins' = [ null ] ++ (builtins.map (v: v.name) bins); in
          libb.foldAttrs libb.recursiveUpdate { }
            (
              builtins.map
                (exe: libb.mapAttrs' (mkApp exe) packages.${system})
                bins'
            );
      };
    in
    libb.optionalAttrs (packageMetadata.build or false) ({
      inherit packages checks;
      defaultPackage = {
        ${system} = packages.${system}.${cargoPkg.name};
      };
    } // (libb.optionalAttrs (packageMetadata.app or false) {
      inherit apps;
      defaultApp = {
        ${system} = apps.${system}.${cargoPkg.name};
      };
    }));
in
{
  inherit importCargoTOML makeOutput makeOutputs;
}
