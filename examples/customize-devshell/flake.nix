{
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  inputs.nci.url = "github:yusdacra/nix-cargo-integration";
  inputs.nci.inputs.nixpkgs.follows = "nixpkgs";
  inputs.parts.url = "github:hercules-ci/flake-parts";
  inputs.parts.inputs.nixpkgs-lib.follows = "nixpkgs";

  outputs = inputs @ {
    parts,
    nci,
    ...
  }:
    parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];
      imports = [nci.flakeModule];
      perSystem = {
        config,
        pkgs,
        ...
      }: {
        # declare projects
        nci.projects."example-crate".relPath = "";
        # nci devshells are just regular `nixpkgs.mkShell`
        # alternatively you can not use NCI's own devshells and use numtide devshell or devenv etc.
        devShells.default = config.nci.outputs."example-crate".devShell.overrideAttrs (old: {
          packages = (old.packages or []) ++ [pkgs.hello];
          shellHook = ''
            ${old.shellHook or ""}
            echo "Hello world!"
          '';
        });
      };
    };
}
