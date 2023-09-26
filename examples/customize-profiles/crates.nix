{...}: {
  perSystem = {
    pkgs,
    config,
    ...
  }: {
    # declare projects
    nci.projects."profiles".path = ./.;
    # configure crates
    nci.crates."customize-profiles" = {
      profiles.release = {
        # configure features
        features = ["default"];
        # set whether to run tests or not
        runTests = true;
        # configure the main derivation for this profile's package
        drvConfig = {
          mkDerivation.preBuild = "echo starting build";
          env.CARGO_TERM_VERBOSE = "true";
        };
        # configure the dependencies derivation for this profile's package
        depsDrvConfig = {};
      };
    };
  };
}
