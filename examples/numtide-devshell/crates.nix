{
  perSystem = {pkgs, ...}: {
    # declare projects
    nci.projects."my-project" = {
      path = ./.;
      # Configure the numtide devshell to which all packages
      # required for this project and its crates should be added
      numtideDevshell = "default";
    };

    # configure crates
    nci.crates."my-crate" = {
      # If you only want to add requirements for a specific
      # crate to your numtide devshell:
      #numtideDevshell = "default";
      drvConfig.mkDerivation.buildInputs = [pkgs.hello];
      drvConfig.env.FOO = "BAR";
    };

    # Conveniently configure additional things in your devshell
    devshells.default.env = [
      {
        name = "SOME_EXTRA_ENV_VARIABLE";
        value = "true";
      }
    ];
  };
}
