{ memberName ? null
, buildPlatform ? "naersk"
, cargoToml ? null
, workspaceMetadata ? null
, root ? null
, overrides ? { }
, dependencies ? [ ]
, sources
, system
}:
let
  edition = cargoToml.edition or "2018";
  cargoPkg = cargoToml.package;
  features = cargoToml.features or { };
  bins = cargoToml.bin or [ ];
  autobins = cargoPkg.autobins or (edition == "2018");

  isCrate2Nix = buildPlatform == "crate2nix";
  isNaersk = buildPlatform == "naersk";

  packageMetadata = cargoPkg.metadata.nix or null;

  commonAttrs =
    {
      inherit
        system
        cargoPkg
        cargoToml
        features
        bins
        autobins
        packageMetadata
        workspaceMetadata
        root
        memberName
        buildPlatform
        isCrate2Nix
        isNaersk
        dependencies;
    };

  srcs = sources // (
    (overrides.sources or (_: _: { }))
      commonAttrs
      sources
  );

  rustOverlay = import srcs.rustOverlay;
  devshellOverlay = import (srcs.devshell + "/overlay.nix");

  basePkgsConfig = {
    inherit system;
    overlays = [
      rustOverlay
      devshellOverlay
      (final: prev:
        let
          rustToolchainFile = root + "/rust-toolchain";
          baseRustToolchain =
            if builtins.pathExists rustToolchainFile
            then prev.rust-bin.fromRustupToolchainFile rustToolchainFile
            else prev.rust-bin."${workspaceMetadata.toolchain or "stable"}".latest.default;
          toolchain = baseRustToolchain.override {
            extensions = [ "rust-src" "rustfmt" "clippy" ];
          };
        in
        {
          rustc = toolchain;
          rustfmt = toolchain;
        } // (prev.lib.optionalAttrs isCrate2Nix {
          cargo = toolchain;
          clippy = toolchain;
        })
      )
    ] ++ (
      if isNaersk
      then [
        (final: prev: {
          naersk = prev.callPackage srcs.naersk { };
        })
      ]
      else if isCrate2Nix
      then [
        (final: prev: {
          crate2nixTools = import "${srcs.crate2nix}/tools.nix" { pkgs = prev; };
        })
      ]
      else throw "invalid build platform: ${buildPlatform}"
    );
  };
  pkgs = import srcs.nixpkgs (basePkgsConfig // (
    (overrides.pkgs or (_: _: { }))
      (commonAttrs // { sources = srcs; })
      basePkgsConfig
  ));

  # courtesy of devshell
  resolveToPkg = key:
    let
      attrs = builtins.filter builtins.isString (builtins.split "\\." key);
      op = sum: attr: sum.${attr} or (throw "package \"${key}\" not found");
    in
    builtins.foldl' op pkgs attrs;
  resolveToPkgs = map resolveToPkg;

  ccOv = {
    crateOverrides =
      let
        commonOverride = {
          ${cargoPkg.name} = prev: {
            buildInputs = (prev.buildInputs or [ ]) ++ [ pkgs.zlib ];
            nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ [ pkgs.binutils ];
          };
        };
        tomlOverrides = builtins.mapAttrs
          (_: crate: prev: {
            nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ (resolveToPkgs (crate.nativeBuildInputs or [ ]));
            buildInputs = (prev.buildInputs or [ ]) ++ (resolveToPkgs (crate.buildInputs or [ ]));
          } // (crate.env or { }) // { propagatedEnv = crate.env or { }; })
          (pkgs.lib.recursiveUpdate (workspaceMetadata.crateOverride or { }) (packageMetadata.crateOverride or { }));
        extraOverrides = import ./extraCrateOverrides.nix { inherit pkgs; };
        baseRaw =
          builtins.foldl'
            (acc: el: pkgs.lib.genAttrs (pkgs.lib.unique ((builtins.attrNames acc) ++ (builtins.attrNames el))) (name:
              let
                isEl = builtins.hasAttr name el;
                isAcc = builtins.hasAttr name acc;
              in
              if isAcc && isEl
              then pp: let accPp = acc.${name} pp; in accPp // (el.${name} accPp)
              else if isAcc
              then acc.${name}
              else if isEl
              then el.${name}
              else _: { }
            ))
            pkgs.defaultCrateOverrides
            [ tomlOverrides extraOverrides commonOverride ];
        depNames = builtins.map (dep: dep.name) dependencies;
        base = pkgs.lib.filterAttrs (n: _: pkgs.lib.any (depName: n == depName) depNames) baseRaw;
      in
      base // (
        (
          (overrides.crateOverrides or (_: _: { }))
            (commonAttrs // { inherit pkgs; sources = srcs; })
            base
        )
      );
  };

  ccOvEmpty = pkgs.lib.mapAttrsToList (_: v: v { }) (ccOv.crateOverrides or { });
  getListAttrsFromCcOv = attrName: pkgs.lib.flatten (builtins.map (v: v.${attrName} or [ ]) ccOvEmpty);

  baseConfig = {
    sources = srcs;

    # Libraries that will be put in $LD_LIBRARY_PATH
    runtimeLibs = resolveToPkgs ((workspaceMetadata.runtimeLibs or [ ]) ++ (packageMetadata.runtimeLibs or [ ]));
    buildInputs =
      resolveToPkgs
        ((workspaceMetadata.buildInputs or [ ])
          ++ (packageMetadata.buildInputs or [ ]))
      ++ (getListAttrsFromCcOv "buildInputs");
    nativeBuildInputs =
      resolveToPkgs
        ((workspaceMetadata.nativeBuildInputs or [ ])
          ++ (packageMetadata.nativeBuildInputs or [ ]))
      ++ (getListAttrsFromCcOv "nativeBuildInputs");
    env =
      (workspaceMetadata.env or { })
        // (packageMetadata.env or { })
        // (
        (
          builtins.foldl'
            pkgs.lib.recursiveUpdate
            { }
            (builtins.map (v: v.propagatedEnv or { }) ccOvEmpty)
        )
      );

    overrides = {
      shell = overrides.shell or (_: _: { });
      build = overrides.build or (_: _: { });
      mainBuild = overrides.mainBuild or (_: _: { });
    };
  } // ccOv // (commonAttrs // { inherit pkgs; sources = srcs; })
  ;
in
(baseConfig // ((overrides.common or (_: { })) baseConfig))
