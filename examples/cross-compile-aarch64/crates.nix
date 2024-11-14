{...}: {
  perSystem = {
    pkgs,
    config,
    lib,
    ...
  }: let
    crateName = "cross-compile-aarch64";
  in {
    # declare projects
    nci.projects.${crateName}.path = ./.;
    # configure crates
    nci.crates.${crateName} = {
      targets."aarch64-unknown-linux-gnu" = let
        targetPkgs = pkgs.pkgsCross.aarch64-multiplatform;
        targetCC = targetPkgs.stdenv.cc;
        targetCargoEnvVarTarget = targetPkgs.hostPlatform.rust.cargoEnvVarTarget;
      in rec {
        default = true;
        depsDrvConfig.mkDerivation = {
          nativeBuildInputs = [targetCC pkgs.pkg-config pkgs.qemu];
          buildInputs = [targetPkgs.openssl];
        };
        depsDrvConfig.env = rec {
          TARGET_CC = "${targetCC.targetPrefix}cc";
          "CARGO_TARGET_${targetCargoEnvVarTarget}_LINKER" = TARGET_CC;
          "CARGO_TARGET_${targetCargoEnvVarTarget}_RUNNER" = "qemu-aarch64";
        };
        drvConfig = depsDrvConfig;
      };
    };
  };
}
