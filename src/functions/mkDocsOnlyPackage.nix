pkg: let
  cfg = {
    config,
    lib,
    ...
  }: {
    mkDerivation = {
      buildPhase = lib.mkForce ''
        cargo doc $cargoBuildFlags --no-deps --profile $cargoBuildProfile --package ${config.name}
      '';
      checkPhase = lib.mkForce ":";
      installPhase = lib.mkForce "mv target/$CARGO_BUILD_TARGET/doc $out";
    };
  };
in
  (pkg.extendModules {modules = [cfg];}).config.public
