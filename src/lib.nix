{ sources }:
let
  lib =
    let
      l = (import "${sources.nixpkgs}/lib/default.nix") // builtins;
      mkDbg = msgPrefix:
        rec {
          doDbg = (l.getEnv "NCI_DEBUG") == "1";
          dbg = msg: x:
            if doDbg
            then l.trace "${msgPrefix}${msg}" x
            else x;
          dbgX = msg: x: dbgXY msg x x;
          dbgXY = msg: x: y:
            if doDbg
            then
              l.debug.traceSeqN 5
                {
                  message = "${msgPrefix}${msg}";
                  value = x;
                }
                y
            else y;
        };
    in
    l // (mkDbg "") // {
      inherit mkDbg;
      # equal to `nixpkgs` `supportedSystems` and `limitedSupportSystems` https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/release.nix#L14
      defaultSystems = [ "aarch64-linux" "x86_64-darwin" "x86_64-linux" "i686-linux" "aarch64-darwin" ];
      # Tries to convert a cargo license to nixpkgs license.
      cargoLicenseToNixpkgs = _license:
        let
          license = l.toLower _license;
          licensesIds =
            l.mapAttrs'
              (name: v:
                l.nameValuePair
                  (l.toLower (v.spdxId or v.fullName or name))
                  name
              )
              l.licenses;
        in
          licensesIds.${license} or "unfree";
      putIfHasAttr = attr: set: l.optionalAttrs (l.hasAttr attr set) { ${attr} = set.${attr}; };
    };

  # Create an output (packages, apps, etc.) from a common.
  makeOutput = { common, renameOutputs ? { } }:
    let
      inherit (common) cargoToml cargoPkg packageMetadata system memberName root;

      l = common.internal.lib;

      # Metadata we will use later. Defaults should be the same as Cargo defaults.
      name = renameOutputs.${cargoPkg.name} or cargoPkg.name;
      edition = cargoPkg.edition or "2018";
      bins = cargoToml.bin or [ ];
      autobins = cargoPkg.autobins or (edition == "2018");

      # Find the package source.
      pkgSrc =
        let
          src =
            if memberName == null
            then root + "/src"
            else root + "/${memberName}" + "/src";
        in
        l.dbg "package source for ${name} at: ${src}" src;

      # Emulate autobins behaviour, get all the binaries of this package.
      allBins =
        l.unique (
          (l.optional (l.pathExists (pkgSrc + "/main.rs")) {
            inherit name;
            exeName = cargoPkg.name;
          })
          ++ bins
          ++ (l.optionals
            (autobins && (l.pathExists (pkgSrc + "/bin")))
            (l.genAttrs
              (l.map
                (l.removeSuffix ".rs")
                (l.attrNames (l.readDir (pkgSrc + "/bin")))
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
            if (l.length (bin.required-features or [ ])) < 1
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
        "${name}" = mkBuild [ ] true true;
        "${name}-debug" = mkBuild [ ] false false;
      };
      # Packages set to be put in the outputs.
      packages = {
        ${system} = (l.mapAttrs (_: v: v.package) packagesRaw) // {
          "${name}-derivation" = l.createNixpkgsDrv common;
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
          l.foldAttrs l.recursiveUpdate { }
            (
              l.map
                (exe: l.mapAttrs' (mkApp exe) packagesRaw)
                (l.dbg "binaries for ${name}: ${l.concatMapStringsSep ", " (bin: bin.name) allBins}" allBins)
            );
      };
    in
    l.optionalAttrs (packageMetadata.build or false) ({
      inherit packages checks;
      defaultPackage = {
        ${system} = packages.${system}.${name};
      };
    } // l.optionalAttrs (packageMetadata.app or false) {
      inherit apps;
      defaultApp = {
        ${system} =
          let
            appName =
              if (l.length allBins) > 0
              then (l.head allBins).name
              else name;
          in
          apps.${system}.${appName};
      };
    });
in
{
  # Creates flake outputs by searching the supplied root for a workspace / package and using
  # Cargo.toml's for configuration.
  makeOutputs =
    { root
    , overrides ? { }
    , enablePreCommitHooks ? false
    , renameOutputs ? { }
    , defaultOutputs ? { }
    , ...
    }:
    let
      l = lib // builtins;

      # Helper function to import a Cargo.toml from a root.
      importCargoTOML = root: l.fromTOML (l.readFile (root + "/Cargo.toml"));

      # Import the "main" Cargo.toml we will use. This Cargo.toml can either be a workspace manifest, or a package manifest.
      cargoToml = importCargoTOML (l.dbg "root at: ${root}" root);
      # Import the Cargo.lock file.
      cargoLockPath = root + "/Cargo.lock";
      cargoLock =
        if l.pathExists cargoLockPath
        then l.fromTOML (l.readFile cargoLockPath)
        else throw "A Cargo.lock file must be present, please make sure it's at least staged in git.";

      # This is the "root package" that might or might not exist.
      # For example, the manifest might both specify a workspace *and* have a package in it.
      rootPkg = cargoToml.package or null;
      # Get the workspace attributes if it exists.
      workspaceToml = cargoToml.workspace or null;
      # Get the workspace members if they exist.
      workspaceMembers = workspaceToml.members or [ ];
      # Process any globs that might be in workspace members.
      globbedWorkspaceMembers = l.flatten (l.map
        (memberName:
          let
            components = l.splitString "/" memberName;
            parentDirRel = l.concatStringsSep "/" (l.init components);
            parentDir = root + "/${parentDirRel}";
            dirs = l.readDir parentDir;
          in
          if l.last components == "*"
          then
            l.mapAttrsToList
              (name: _: "${parentDirRel}/${name}")
              (l.filterAttrs (_: type: type == "directory") dirs)
          else memberName
        )
        workspaceMembers);
      # Get and import the members' Cargo.toml files if we are in a workspace.
      members =
        l.genAttrs
          (l.dbg "workspace members: ${l.concatStringsSep ", " globbedWorkspaceMembers}" globbedWorkspaceMembers)
          (name: importCargoTOML (root + "/${name}"));

      # Get the metadata we will use from the root package attributes if it exists.
      packageMetadata = rootPkg.metadata.nix or null;
      # Get the metadata we will use from the workspace attributes if it exists.
      workspaceMetadata = workspaceToml.metadata.nix or null;

      # Get all the dependencies in Cargo.lock.
      dependencies = cargoLock.package;
      # Decide which systems we will generate outputs for. This can be overrided.
      systems = (overrides.systems or (x: x))
        (workspaceMetadata.systems or packageMetadata.systems or l.defaultSystems);

      # Helper function to construct a "commons" from a member name, the cargo toml, and the system.
      mkCommon = memberName: cargoToml: isRootMember: system: import ./common.nix {
        inherit
          lib dependencies memberName cargoToml workspaceMetadata
          system root overrides sources enablePreCommitHooks isRootMember;
      };

      isRootMember = if (l.length workspaceMembers) > 0 then true else false;
      # Generate "commons" for the "root package".
      rootCommons = if rootPkg != null then l.genAttrs systems (mkCommon null cargoToml isRootMember) else null;
      # Generate "commons" for all members.
      memberCommons' = l.mapAttrsToList (name: value: l.genAttrs systems (mkCommon name value false)) members;
      # Combine the member "commons" and the "root package" "commons".
      allCommons' = memberCommons' ++ (l.optional (rootCommons != null) rootCommons);

      # Helper function used to "combine" two "commons".
      updateCommon = prev: final:
        let
          combineLists = name: l.unique ((prev.${name} or [ ]) ++ final.${name});
          combinedLists =
            l.genAttrs
              [
                "runtimeLibs"
                "buildInputs"
                "nativeBuildInputs"
                "overrideBuildInputs"
                "overrideNativeBuildInputs"
              ]
              combineLists;
        in
        prev // final // combinedLists // {
          env = (prev.env or { }) // final.env;
          overrideEnv = (prev.overrideEnv or { }) // final.overrideEnv;
          overrides = {
            shell = common: prevShell:
              ((prev.overrides.shell or (_: _: { })) common prevShell) // (final.overrides.shell common prevShell);
          };
        };
      # Recursively go through each "commons", and "combine" them. We will use this for our devshell.
      commonsCombined =
        l.mapAttrs
          (_: l.foldl' updateCommon { })
          (
            l.foldl'
              (acc: ele: l.mapAttrs (n: v: acc.${n} ++ [ v ]) ele)
              (l.genAttrs systems (_: [ ]))
              allCommons'
          );

      # Generate outputs from all "commons".
      allOutputs' = l.flatten (l.map (l.mapAttrsToList (_: common: makeOutput { inherit common renameOutputs; })) allCommons');
      # Recursively combine all outputs we have.
      combinedOutputs = l.foldAttrs lib.recursiveUpdate { } allOutputs';
      # Create the "final" output set.
      # This also creates the devshell, puts in pre commit checks if the user has enabled it,
      # and changes default outputs according to `defaultOutputs`.
      finalOutputs = combinedOutputs // {
        devShell = l.mapAttrs (_: import ./shell.nix) commonsCombined;
        checks = l.recursiveUpdate (combinedOutputs.checks or { }) (
          l.mapAttrs
            (_: common: l.optionalAttrs (l.hasAttr "preCommitChecks" common) {
              "preCommitChecks" = common.preCommitChecks;
            })
            commonsCombined
        );
      } // l.optionalAttrs (l.hasAttr "package" defaultOutputs) {
        defaultPackage = lib.mapAttrs (_: system: system.${defaultOutputs.package}) combinedOutputs.packages;
      } // l.optionalAttrs (l.hasAttr "app" defaultOutputs) {
        defaultApp = l.mapAttrs (_: system: system.${defaultOutputs.app}) combinedOutputs.apps;
      };
      checkedOutputs = l.warnIf
        (!(l.hasAttr "packages" finalOutputs) && !(l.hasAttr "apps" finalOutputs))
        "No packages found. Did you add the `package.metadata.nix` section to a `Cargo.toml` and added `build = true` under it?"
        finalOutputs;
    in
    checkedOutputs;
}
