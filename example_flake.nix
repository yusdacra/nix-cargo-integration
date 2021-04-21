{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rustOverlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixCargoIntegration = {
      url = "github:yusdacra/nix-cargo-integration";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rustOverlay.follows = "rustOverlay";
    };
  };

  outputs = inputs: inputs.nixCargoIntegration.lib.makeOutputs {
    root = ./.;
    # Overrides provided here will apply to *every crate*,
    # for *every system*. To selectively override per crate,
    # one can use `common.cargoPkg.name` attribute. To selectively
    # override per system one can use `common.system` attribute.
    overrides =
      let
        lib = inputs.nixpkgs.lib;
      in
      {
        # Override sources used by nixCargoIntegration in common.
        # This can be used to provide sources that are only needed for
        # specific systems or crates.
        sources = common: prev: {
          # rustOverlay = inputs.rustOverlay;
        };
        # Override nixpkgs configuration in common. This can be used 
        # to add overlays for specific systems or crates.
        pkgs = common: prev: {
          # overlays = prev.overlays ++ [ inputs.someInput.someOverlay ];
        };
        # Common attribute overrides.
        common = prev: {
          # Package set used can be overriden here; note that changing
          # the package set here will not change the already set
          # runtimeLibs, buildInputs and nativeBuildInputs.
          pkgs = prev.pkgs;
          # Packages put here will have their libraries exported in
          # $LD_LIBRARY_PATH environment variable.
          runtimeLibs = prev.runtimeLibs ++ [ ];
          # Packages put here will be used as build inputs for build
          # derivation and packages for development shell. For development
          # shell, they will be exported to $LIBRARY_PATH and $PKG_CONFIG_PATH.
          buildInputs = prev.buildInputs ++ [ ];
          # Packages put here will be used as native build inputs
          # for build derivation and packages for development shell.
          nativeBuildInputs = prev.nativeBuildInputs ++ [ ];
          # Key-value pairs put here will be exported as environment
          # variables in build and development shell.
          env = prev.env // {
            # PROTOC_INCLUDE = "${prev.pkgs.protobuf}/include";
          };
        };
        # Development shell overrides.
        shell = common: prev: {
          # Packages to be put in $PATH.
          packages = prev.packages ++ [ ];
          # Commands that will be shown in the `menu`. These also get added
          # to packages.
          commands = prev.commands ++ [
            # { package = common.pkgs.git; }
            # { name = "helloworld"; command = "echo 'Hello world'"; }
          ];
          # Environment variables to be exported.
          env = prev.env ++ [
            # lib.nameValuePair "PROTOC" "protoc"
            # { name = "HOME_DIR"; eval = "$HOME"; }
          ];
        };
        # naersk build derivation overrides.
        build = common: prev: {
          buildInputs = prev.buildInputs ++ [ ];
          nativeBuildInputs = prev.nativeBuildInputs ++ [ ];
          # Overrides for dependency build step.
          override = prevv: (prev.override prevv) // { };
          # Overrides for main crate build step.
          overrideMain = prevv: (prev.overrideMain prevv) // {
            # Build specific env variables can be specified here like so.
            # GIT_LFS_CHECK = false;
          };
          # Arguments to be passed to cargo while building.
          cargoBuildOptions = def: ((prev.cargoBuildOptions or (d: d)) def) ++ [ ];
          # Arguments to be passed to cargo while testing.
          cargoTestOptions = def: ((prev.cargoTestOptions or (d: d)) def) ++ [ ];
        };
      };
  };
}
