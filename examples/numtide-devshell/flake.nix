{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.nci.url = "github:yusdacra/nix-cargo-integration";
  inputs.nci.inputs.nixpkgs.follows = "nixpkgs";
  inputs.parts.url = "github:hercules-ci/flake-parts";
  inputs.parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  inputs.devshell.url = "github:numtide/devshell";
  inputs.devshell.inputs.nixpkgs.follows = "nixpkgs";

  outputs = inputs:
    inputs.parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [
        inputs.nci.flakeModule
        inputs.devshell.flakeModule
      ];

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
        };

        # Conveniently configure additional things in your devshell
        devshells.default.env = [
          {
            name = "SOME_EXTRA_ENV_VARIABLE";
            value = "true";
          }
        ];
      };
    };
}
