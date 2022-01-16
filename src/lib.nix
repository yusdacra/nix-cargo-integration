{ sources }:
let
  libb = import "${sources.nixpkgs}/lib/default.nix";

  lib = libb // {
    isNaersk = platform: platform == "naersk";
    isCrate2Nix = platform: platform == "crate2nix";
    isBuildRustPackage = platform: platform == "buildRustPackage";
    isDream2Nix = platform: platform == "dream2nix";
    # equal to `nixpkgs` `supportedSystems` and `limitedSupportSystems` https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/release.nix#L14
    defaultSystems = [ "aarch64-linux" "x86_64-darwin" "x86_64-linux" "i686-linux" "aarch64-darwin" ];
    # Tries to convert a cargo license to nixpkgs license.
    cargoLicenseToNixpkgs = license:
      let
        l = libb.toLower license;
      in
        {
          "gplv3" = "gpl3";
          "gplv2" = "gpl2";
          "gpl-3.0" = "gpl3";
          "gpl-2.0" = "gpl2";
          "mpl-2.0" = "mpl20";
          "mpl-1.0" = "mpl10";
        }."${l}" or l;
    putIfHasAttr = attr: set: libb.optionalAttrs (builtins.hasAttr attr set) { ${attr} = set.${attr}; };
    dbg = msg: x:
      if (builtins.getEnv "NCI_DEBUG") == "1"
      then builtins.trace msg x
      else x;
  };

  # Create an output (packages, apps, etc.) from a common.
  makeOutput = { common, renameOutputs ? { } }:
    let
      inherit (common) cargoToml cargoPkg packageMetadata system memberName root lib;

      # Metadata we will use later. Defaults should be the same as Cargo defaults.
      name = renameOutputs.${cargoPkg.name} or cargoPkg.name;
      edition = cargoPkg.edition or "2018";
      bins = cargoToml.bin or [ ];
      autobins = cargoPkg.autobins or (edition == "2018");

      # Find the package source.
      pkgSrc =
        let
          src =
            if isNull memberName
            then root + "/src"
            else root + "/${memberName}" + "/src";
        in
        lib.dbg "package source for ${name} at: ${src}" src;

      # Emulate autobins behaviour, get all the binaries of this package.
      allBins =
        lib.unique (
          (lib.optional (builtins.pathExists (pkgSrc + "/main.rs")) {
            inherit name;
            exeName = cargoPkg.name;
          })
          ++ bins
          ++ (lib.optionals
            (autobins && (builtins.pathExists (pkgSrc + "/bin")))
            (lib.genAttrs
              (builtins.map
                (lib.removeSuffix ".rs")
                (builtins.attrNames (builtins.readDir (pkgSrc + "/bin")))
                (name: { inherit name; })
              )
            )
          )
        );

      # Helper function to use build.nix
      mkBuild = f: r: c: import ./build.nix {
        inherit common;
        features = f;
        doCheck = c;
        release = r;
        renamePkgTo = name;
      };
      # Helper function to create an app output.
      # This takes one "binary output" of this Cargo package.
      mkApp = bin: n: v:
        let
          ex = {
            exeName = bin.exeName or bin.name;
            name = "${bin.name}${if v.config.release then "" else "-debug"}";
          };
          drv =
            if (builtins.length (bin.required-features or [ ])) < 1
            then v.package
            else (mkBuild (bin.required-features or [ ]) v.config.release v.config.doCheck).package;
          exePath = "/bin/${ex.exeName}";
        in
        {
          name = ex.name;
          value = {
            type = "app";
            program = "${drv}${exePath}";
          };
        };

      # "raw" packages that will be proccesed.
      # It's called so since `build.nix` generates an attrset containing the config and the package.
      packagesRaw = {
        ${system} = {
          "${name}" = mkBuild [ ] true true;
          "${name}-debug" = mkBuild [ ] false false;
        };
      };
      # Packages set to be put in the outputs.
      packages = {
        ${system} = (builtins.mapAttrs (_: v: v.package) packagesRaw.${system}) // {
          "${name}-derivation" = lib.createNixpkgsDrv common;
        };
      };
      # Checks to be put in outputs.
      checks = {
        ${system} = {
          "${name}-tests" = (mkBuild [ ] false true).package;
        };
      };
      # Apps to be put in outputs.
      apps = {
        ${system} =
          # Make apps for all binaries, and recursively combine them.
          lib.foldAttrs lib.recursiveUpdate { }
            (
              builtins.map
                (exe: lib.mapAttrs' (mkApp exe) packagesRaw.${system})
                (lib.dbg "binaries for ${name}: ${lib.concatMapStringsSep ", " (bin: bin.name) allBins}" allBins)
            );
      };
    in
    lib.optionalAttrs (packageMetadata.build or false) ({
      inherit packages checks;
      defaultPackage = {
        ${system} = packages.${system}.${name};
      };
    } // lib.optionalAttrs (packageMetadata.app or false) {
      inherit apps;
      defaultApp = {
        ${system} =
          let
            appName =
              if (lib.length allBins) > 0
              then (lib.head allBins).name
              else name;
          in
          apps.${system}.${appName};
      };
    });
in
{
  inherit makeOutput;

  # Create an "empty" common with a dummy crate.
  makeEmptyCommon =
    { system
    , overrides ? { }
    , buildPlatform ? "naersk"
    }:
    let
      # Craft a dummy cargo toml.
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
    , enablePreCommitHooks ? false
    , renameOutputs ? { }
    , defaultOutputs ? { }
    , cargoVendorHash ? lib.fakeHash
    , useCrate2NixFromPkgs ? false
    }:
    let
      # Helper function to import a Cargo.toml from a root.
      importCargoTOML = root: builtins.fromTOML (builtins.readFile (root + "/Cargo.toml"));

      # Import the "main" Cargo.toml we will use. This Cargo.toml can either be a workspace manifest, or a package manifest.
      cargoToml = importCargoTOML (lib.dbg "root at: ${root}" root);
      # Import the Cargo.lock file.
      cargoLockPath = root + "/Cargo.lock";
      cargoLock =
        if builtins.pathExists cargoLockPath
        then builtins.fromTOML (builtins.readFile cargoLockPath)
        else throw "A Cargo.lock file must be present, please make sure it's at least staged in git.";

      # This is the "root package" that might or might not exist.
      # For example, the manifest might both specify a workspace *and* have a package in it.
      rootPkg = cargoToml.package or null;
      # Get the workspace attributes if it exists.
      workspaceToml = cargoToml.workspace or null;
      # Get the workspace members if they exist.
      workspaceMembers = workspaceToml.members or [ ];
      # Process any globs that might be in workspace members.
      globbedWorkspaceMembers = lib.flatten (builtins.map
        (memberName:
          let
            components = lib.splitString "/" memberName;
            parentDirRel = lib.concatStringsSep "/" (lib.init components);
            parentDir = root + "/${parentDirRel}";
            dirs = builtins.readDir parentDir;
          in
          if lib.last components == "*"
          then
            lib.mapAttrsToList
              (name: _: "${parentDirRel}/${name}")
              (lib.filterAttrs (_: type: type == "directory") dirs)
          else memberName
        )
        workspaceMembers);
      # Get and import the members' Cargo.toml files if we are in a workspace.
      members =
        lib.genAttrs
          (lib.dbg "workspace members: ${lib.concatStringsSep ", " globbedWorkspaceMembers}" globbedWorkspaceMembers)
          (name: importCargoTOML (root + "/${name}"));

      # Get the metadata we will use from the root package attributes if it exists.
      packageMetadata = rootPkg.metadata.nix or null;
      # Get the metadata we will use from the workspace attributes if it exists.
      workspaceMetadata = workspaceToml.metadata.nix or null;

      # Get all the dependencies in Cargo.lock.
      dependencies = cargoLock.package;
      # Decide which systems we will generate outputs for. This can be overrided.
      systems = (overrides.systems or (x: x))
        (workspaceMetadata.systems or packageMetadata.systems or lib.defaultSystems);

      # Helper function to construct a "commons" from a member name, the cargo toml, and the system.
      mkCommon = memberName: cargoToml: isRootMember: system: import ./common.nix {
        inherit
          lib dependencies buildPlatform memberName cargoToml workspaceMetadata
          system root overrides sources enablePreCommitHooks cargoVendorHash
          isRootMember useCrate2NixFromPkgs;
      };

      isRootMember = if (lib.length workspaceMembers) > 0 then true else false;
      # Generate "commons" for the "root package".
      rootCommons = if ! isNull rootPkg then lib.genAttrs systems (mkCommon null cargoToml isRootMember) else null;
      # Generate "commons" for all members.
      memberCommons' = lib.mapAttrsToList (name: value: lib.genAttrs systems (mkCommon name value false)) members;
      # Combine the member "commons" and the "root package" "commons".
      allCommons' = memberCommons' ++ (lib.optional (! isNull rootCommons) rootCommons);

      # Helper function used to "combine" two "commons".
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
      # Recursively go through each "commons", and "combine" them. We will use this for our devshell.
      commonsCombined =
        lib.mapAttrs
          (_: lib.foldl' updateCommon { })
          (
            lib.foldl'
              (acc: ele: lib.mapAttrs (n: v: acc.${n} ++ [ v ]) ele)
              (lib.genAttrs systems (_: [ ]))
              allCommons'
          );

      # Generate outputs from all "commons".
      allOutputs' = lib.flatten (builtins.map (lib.mapAttrsToList (_: common: makeOutput { inherit common renameOutputs; })) allCommons');
      # Recursively combine all outputs we have.
      combinedOutputs = lib.foldAttrs lib.recursiveUpdate { } allOutputs';
      # Create the "final" output set.
      # This also creates the devshell, puts in pre commit checks if the user has enabled it,
      # and changes default outputs according to `defaultOutputs`.
      finalOutputs = combinedOutputs // {
        devShell = lib.mapAttrs (_: import ./devShell.nix) commonsCombined;
        checks = lib.recursiveUpdate (combinedOutputs.checks or { }) (
          lib.mapAttrs
            (_: common: lib.optionalAttrs (builtins.hasAttr "preCommitChecks" common) {
              "preCommitChecks" = common.preCommitChecks;
            })
            commonsCombined
        );
      } // lib.optionalAttrs (builtins.hasAttr "package" defaultOutputs) {
        defaultPackage = lib.mapAttrs (_: system: system.${defaultOutputs.package}) combinedOutputs.packages;
      } // lib.optionalAttrs (builtins.hasAttr "app" defaultOutputs) {
        defaultApp = lib.mapAttrs (_: system: system.${defaultOutputs.app}) combinedOutputs.apps;
      };
      checkedOutputs = lib.warnIf
        (!(builtins.hasAttr "packages" finalOutputs) && !(builtins.hasAttr "apps" finalOutputs))
        "No packages found. Did you add the `package.metadata.nix` section to a `Cargo.toml` and added `build = true` under it?"
        finalOutputs;
    in
    checkedOutputs;
}
