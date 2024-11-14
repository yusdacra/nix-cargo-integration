{...}: {
  perSystem = {
    pkgs,
    config,
    lib,
    inputs',
    ...
  }: let
    crateName = "cross-compile-windows";
  in {
    # declare projects
    nci.projects.${crateName}.path = ./.;
    # TODO: fenix works, rust-overlay doesn't, why?
    nci.toolchains.mkBuild = _:
      with inputs'.fenix.packages;
        combine [
          minimal.rustc
          minimal.cargo
          targets.x86_64-pc-windows-gnu.latest.rust-std
        ];
    # configure crates
    nci.crates.${crateName} = {
      targets."x86_64-pc-windows-gnu" = let
        targetPkgs = pkgs.pkgsCross.mingwW64;
        targetCC = targetPkgs.stdenv.cc;
        targetCargoEnvVarTarget = targetPkgs.hostPlatform.rust.cargoEnvVarTarget;
        # we have to wrap wine so that HOME is set to somewhere that exists
        wineWrapped = pkgs.writeScript "wine.sh" ''
          #!${pkgs.stdenv.shell}
          HOME=$TEMPDIR ${pkgs.wineWow64Packages.minimal}/bin/wine $@
        '';
      in rec {
        default = true;
        depsDrvConfig.mkDerivation = {
          nativeBuildInputs = [targetCC pkgs.pkg-config pkgs.wineWow64Packages.minimal];
          buildInputs = with targetPkgs; [openssl windows.pthreads];
        };
        depsDrvConfig.env = rec {
          TARGET_CC = "${targetCC.targetPrefix}cc";
          "CARGO_TARGET_${targetCargoEnvVarTarget}_LINKER" = TARGET_CC;
          "CARGO_TARGET_${targetCargoEnvVarTarget}_RUNNER" = wineWrapped;
        };
        drvConfig = depsDrvConfig;
      };
    };
  };
}
