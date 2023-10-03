pkg: let
  cfg = {lib, ...}: {
    rust-crane.runTests = lib.mkForce true;
    mkDerivation.buildPhase = ":";
    mkDerivation.installPhase = "env > $out";
  };
in (pkg.extendModules {modules = [cfg];}).config.public
