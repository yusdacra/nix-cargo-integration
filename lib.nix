{ sources }:
let
  libb = import "${sources.nixpkgs}/lib/default.nix";

  flakeUtils = import sources.flakeUtils;

  makeOutput = common:
    let
      inherit (common) cargoToml cargoPkg packageMetadata system memberName root lib;

      edition = cargoPkg.edition or "2018";
      bins = cargoToml.bin or [ ];
      autobins = cargoPkg.autobins or (edition == "2018");

      pkgSrc = if isNull memberName then "${root}/src" else "${root}/${memberName}/src";

      allBins =
        libb.unique (
          [ null ]
          ++ bins
          ++ (lib.optionals
            (autobins && (builtins.pathExists "${pkgSrc}/bin"))
            (lib.genAttrs
              (builtins.map
                (lib.removeSuffix ".rs")
                (builtins.attrNames (builtins.readDir "${pkgSrc}/bin")))
              (name: { inherit name; })
            )
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
            else {
              exeName = bin.name;
              name = "${bin.name}${if v.config.release then "" else "-debug"}";
            };
        in
        {
          name = ex.name;
          value = flakeUtils.mkApp {
            name = ex.name;
            drv =
              if (builtins.length (bin.required-features or [ ])) < 1
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
          lib.foldAttrs lib.recursiveUpdate { }
            (
              builtins.map
                (exe: lib.mapAttrs' (mkApp exe) packagesRaw.${system})
                allBins
            );
      };
    in
    lib.optionalAttrs (packageMetadata.build or false) ({
      inherit packages checks;
      defaultPackage = {
        ${system} = packages.${system}.${cargoPkg.name};
      };
    } // lib.optionalAttrs (packageMetadata.app or false) {
      inherit apps;
      defaultApp = {
        ${system} = apps.${system}.${cargoPkg.name};
      };
    });
in
{
  # Creates an "empty" platform which has no outputs except a development shell.
  # It uses a placeholder "crate", so this can be used even if no crate exists in `root`.
  makeDummy =
    { root
    , overrides ? { }
    , buildPlatform ? "naersk"
    }:
    let
      # Craft a dummy cargo toml
      dummyToml = {
        package = {
          name = "dummy";
          version = "0.1.0";
          edition = "2018";
        };
      };
      # We make the cargoToml overridable; people might put their own cargoToml
      cargoToml = dummyToml // ((overrides.cargoToml or (_: { })) dummyToml);
      # Craft dummy dependencies.
      dependencies = [{
        name = "dummy";
        version = "0.1.0";
      }];
      # Mutate the systems if a systems function exists.
      systems = (overrides.systems or (x: x)) flakeUtils.defaultSystems;
      mkCommon = system: import ./common.nix { inherit dependencies root system sources cargoToml buildPlatform overrides; };
      devshellCombined = {
        devShell =
          libb.mapAttrs
            (_: import ./devShell.nix)
            (libb.genAttrs systems mkCommon);
      };
    in
    devshellCombined;

  # Creates flake outputs by searching the supplied root for a workspace / package and using
  # Cargo.toml's for configuration.
  makeOutputs =
    { root
    , overrides ? { }
    , buildPlatform ? "naersk"
    ,
    }:
    let
      importCargoTOML = root: builtins.fromTOML (builtins.readFile (root + "/Cargo.toml"));

      cargoToml = importCargoTOML root;
      cargoLock = builtins.fromTOML (builtins.readFile (root + "/Cargo.lock"));

      rootPkg = cargoToml.package or null;
      workspaceToml = cargoToml.workspace or null;
      members = libb.genAttrs (workspaceToml.members or [ ]) (name: importCargoTOML (root + "/${name}"));

      packageMetadata = rootPkg.metadata.nix or null;
      workspaceMetadata = if isNull workspaceToml then packageMetadata else workspaceToml.metadata.nix or null;

      dependencies = cargoLock.package;
      systems = (overrides.systems or (x: x))
        (workspaceMetadata.systems or packageMetadata.systems or flakeUtils.defaultSystems);

      mkCommon = memberName: cargoToml: system: import ./common.nix {
        inherit dependencies buildPlatform memberName cargoToml workspaceMetadata system root overrides sources;
      };

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

      allOutputs' = libb.flatten (builtins.map (libb.mapAttrsToList (_: makeOutput)) allCommons');
    in
    (libb.foldAttrs libb.recursiveUpdate { } allOutputs') // devshellCombined;
}
