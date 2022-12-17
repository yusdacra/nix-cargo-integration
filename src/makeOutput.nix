# Create an output (packages, apps, etc.) from a common.
{
  # A common gotten from `./common.nix`
  common,
}: let
  inherit
    (common.internal)
    cargoToml
    cargoPkg
    packageMetadata
    workspaceMetadata
    memberName
    root
    lib
    pkgsSet
    ;

  l = lib;

  system = pkgsSet.pkgs.system;

  features = packageMetadata.features or {};
  profiles = packageMetadata.profiles;
  renameOutputs =
    workspaceMetadata.outputs.rename
    or packageMetadata.outputs.rename
    or {};
  defaultOutputs =
    workspaceMetadata.outputs.defaults
    or packageMetadata.outputs.defaults
    or {};

  # Metadata we will use later. Defaults should be the same as Cargo defaults.
  name = renameOutputs.${cargoPkg.name} or cargoPkg.name;
  edition = cargoPkg.edition or "2018";
  bins = cargoToml.bin or [];
  autobins = cargoPkg.autobins or (edition == "2018");

  # Find the package source.
  pkgSrc = let
    src =
      if memberName == null
      then "${toString root}/src"
      else "${toString root}/${memberName}/src";
  in
    l.dbg "package source for ${name} at: ${src}" src;

  # Emulate autobins behaviour, get all the binaries of this package.
  allBins = l.unique (
    (l.optional (l.pathExists (pkgSrc + "/main.rs")) {
      inherit name;
      exeName = cargoPkg.name;
    })
    ++ bins
    ++ (
      l.optionals
      (autobins && (l.pathExists (pkgSrc + "/bin")))
      (
        l.genAttrs
        (
          l.map
          (l.removeSuffix ".rs")
          (l.attrNames (l.readDir (pkgSrc + "/bin")))
          (name: {inherit name;})
        )
      )
    )
  );

  mkNameSuffix = profile: l.thenOr (profile == "release") "" "-${profile}";
  # Helper function to use build.nix
  mkBuild = f: p: c:
    import ./build {
      inherit common;
      features = f;
      doCheck = c;
      profile = p;
      renamePkgTo = name;
    };
  # Helper function to create an app output.
  # This takes one "binary output" of this Cargo package.
  mkApp = bin: n: v: let
    ex = {
      exeName = bin.exeName or bin.name;
      name = "${bin.name}${mkNameSuffix v.config.profile}";
    };
    drv =
      if (l.length (bin.required-features or [])) < 1
      then v.package
      else (mkBuild (bin.required-features or []) v.config.profile v.config.doCheck).package;
    exePath = "/bin/${ex.exeName}";
  in {
    name = ex.name;
    value = {
      type = "app";
      program = "${drv}${exePath}";
    };
  };
  mkShell = import ./shell.nix;

  # "raw" packages that will be proccesed.
  # It's called so since `build.nix` generates an attrset containing the config and the package.
  packagesRaw = l.listToAttrs (
    l.map
    (
      profile:
        l.nameValuePair
        "${name}${mkNameSuffix profile}"
        (
          mkBuild
          (features.${profile} or [])
          profile
          profiles.${profile}
        )
    )
    (l.attrNames profiles)
  );
  # Packages set to be put in the outputs.
  _packages = l.mapAttrs (_: v: v.package) packagesRaw;
  packages = {
    ${system} =
      _packages
      // (
        l.optionalAttrs
        (defaultOutputs ? package && l.hasAttr defaultOutputs.package _packages)
        {default = _packages.${defaultOutputs.package};}
      );
  };
  # Checks to be put in outputs.
  checks = {
    ${system} = {
      "${name}-tests" = (mkBuild (features.test or []) "release" true).package;
    };
  };
  # Make apps for all binaries, and recursively combine them.
  _apps =
    l.foldAttrs l.recursiveUpdate {}
    (
      l.map
      (exe: l.mapAttrs' (mkApp exe) packagesRaw)
      (l.dbg "binaries for ${name}: ${l.concatMapStringsSep ", " (bin: bin.name) allBins}" allBins)
    );
  # Apps to be put in outputs.
  apps = {
    ${system} =
      _apps
      // (
        l.optionalAttrs
        (defaultOutputs ? app && l.hasAttr defaultOutputs.app _apps)
        {default = _apps.${defaultOutputs.app};}
      );
  };
  devShells = {
    ${system}.${name} = mkShell {
      inherit common;
      rawShell = packages.${system}.${name}.passthru.shell;
    };
  };
in
  l.optionalAttrs (packageMetadata.build or false) (
    {inherit packages checks devShells;}
    // l.optionalAttrs (packageMetadata.app or false) {
      inherit apps;
    }
  )
