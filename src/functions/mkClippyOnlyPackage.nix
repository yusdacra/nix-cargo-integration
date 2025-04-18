pkg: let
  cfg = {
    config,
    lib,
    ...
  }: {
    mkDerivation.buildPhase = ''
      cargo clippy --all-targets --all-features $cargoBuildFlags --profile $cargoBuildProfile --package ${config.name}
    '';
    mkDerivation.checkPhase = ":";
    mkDerivation.installPhase = "env > $out";
  };
in
  (pkg.extendModules {modules = [cfg];}).config.public
