{ sources }:
let
  libb = import "${sources.nixpkgs}/lib/default.nix";

  lib = libb // {
    isNaersk = platform: platform == "naersk";
    isCrate2Nix = platform: platform == "crate2nix";
    flakeUtils = import sources.flakeUtils;
  };

  makeOutput = common:
    let
      inherit (common) cargoToml cargoPkg packageMetadata system memberName root lib;

      edition = cargoPkg.edition or "2018";
      bins = cargoToml.bin or [ ];
      autobins = cargoPkg.autobins or (edition == "2018");

      pkgSrc = if isNull memberName then "${root}/src" else "${root}/${memberName}/src";

      allBins =
        lib.unique (
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
          value = lib.flakeUtils.mkApp {
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
  # Create an "empty" common with a dummy crate.
  makeEmptyCommon =
    { system
    , overrides ? { }
    , buildPlatform ? "naersk"
    ,
    }:
    let
      # Craft a dummy cargo toml
      cargoToml = {
        package = {
          name = "dummy";
          version = "0.1.0";
          edition = "2018";
        };
      };
      # Craft dummy dependencies.
      dependencies = [{
        name = "dummy";
        version = "0.1.0";
      }];
    in
    import ./common.nix {
      inherit lib dependencies system sources cargoToml buildPlatform overrides;
    };

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
      members = lib.genAttrs (workspaceToml.members or [ ]) (name: importCargoTOML (root + "/${name}"));

      packageMetadata = rootPkg.metadata.nix or null;
      workspaceMetadata = if isNull workspaceToml then packageMetadata else workspaceToml.metadata.nix or null;

      dependencies = cargoLock.package;
      systems = (overrides.systems or (x: x))
        (workspaceMetadata.systems or packageMetadata.systems or lib.flakeUtils.defaultSystems);

      mkCommon = memberName: cargoToml: system: import ./common.nix {
        inherit lib dependencies buildPlatform memberName cargoToml workspaceMetadata system root overrides sources;
      };

      rootCommons = if ! isNull rootPkg then lib.genAttrs systems (mkCommon null cargoToml) else null;
      memberCommons' = lib.mapAttrsToList (name: value: lib.genAttrs systems (mkCommon name value)) members;
      allCommons' = memberCommons' ++ (lib.optional (! isNull rootCommons) rootCommons);

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
          lib.mapAttrs
            (_: import ./devShell.nix)
            (
              lib.mapAttrs
                (_: lib.foldl' updateCommon { })
                (
                  lib.foldl'
                    (acc: ele: lib.mapAttrs (n: v: acc.${n} ++ [ v ]) ele)
                    (lib.genAttrs systems (_: [ ]))
                    allCommons'
                )
            );
      };

      allOutputs' = lib.flatten (builtins.map (lib.mapAttrsToList (_: makeOutput)) allCommons');
    in
    (lib.foldAttrs lib.recursiveUpdate { } allOutputs') // devshellCombined;
}
