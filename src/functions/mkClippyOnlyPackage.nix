pkg: let
  cfg = {
    config,
    lib,
    ...
  }: {
    mkDerivation.buildPhase = ''
      cargo clippy $cargoBuildFlags --profile $cargoBuildProfile --package ${config.name}
    '';
    mkDerivation.checkPhase = ":";
    mkDerivation.installPhase = "env > $out";
    rust-crane.buildFlags = ["--all-features" "--all-targets"];
  };
in
  (pkg.extendModules {modules = [cfg];}).config.public
