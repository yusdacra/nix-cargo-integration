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
      mkCommon = memberName: cargoToml: system: import ./common.nix { inherit memberName cargoToml workspaceMetadata system root overrides sources; };

      rootCommons = if ! isNull rootPkg then libb.genAttrs systems (mkCommon null cargoToml) else null;
      memberCommons' = libb.mapAttrsToList (name: value: libb.genAttrs systems (mkCommon name value)) members;
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
      inherit (common) cargoPkg packageMetadata system bins autobins memberName root;

      pkgSrc = if isNull memberName then "${root}/src" else "${root}/${memberName}/src";

      allBins =
        libb.unique (
          [ null ]
          ++ bins
          ++ (
            libb.optionals
              (autobins && (builtins.pathExists "${pkgSrc}/bin"))
              (libb.genAttrs (builtins.map (libb.removeSuffix ".rs") (builtins.attrNames (builtins.readDir "${pkgSrc}/bin"))) (name: { inherit name; }))
          )
        );

      mkBuild = f: r: c: import ./build.nix {
        inherit common;
        features = f;
        doCheck = c;
        release = r;
      };
      mkApp = bin: n: v:
        let
          ex =
            if isNull bin
            then { exeName = n; name = n; }
            else { exeName = bin.name; name = "${n}-${bin.name}"; };
        in
        {
          name = ex.name;
          value = flakeUtils.mkApp {
            name = ex.name;
            drv =
              if (builtins.length (bin.required-features or [ ])) == 0
              then v.package
              else (mkBuild (bin.required-features or [ ]) v.config.release v.config.doCheck).package;
            exePath = "/bin/${ex.exeName}";
          };
        };

      packagesRaw = {
        ${system} = {
          "${cargoPkg.name}" = mkBuild [ ] true true;
          "${cargoPkg.name}-debug" = mkBuild [ ] false false;
        };
      };
      packages = {
        ${system} = builtins.mapAttrs (_: v: v.package) packagesRaw.${system};
      };
      checks = {
        ${system} = {
          "${cargoPkg.name}-tests" = (mkBuild [ ] false true).package;
        };
      };
      apps = {
        ${system} =
          let in
          libb.foldAttrs libb.recursiveUpdate { }
            (
              builtins.map
                (exe: libb.mapAttrs' (mkApp exe) packagesRaw.${system})
                allBins
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
