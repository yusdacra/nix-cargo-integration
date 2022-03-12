{
  inputs = {
    nixCargoIntegration.url = "github:yusdacra/nix-cargo-integration";
  };

  outputs = inputs:
    inputs.nixCargoIntegration.lib.makeOutputs {
      root = ./.;
      # Which dream2nix builder to use.
      # Usually you don't need mess with this.
      # The default is "crane".
      builder = "crane";
      # Which package outputs to rename to what.
      # This renames both their package names and the generated output names.
      # Applies to generated apps too.
      renameOutputs = {};
      # Default outputs to set.
      defaultOutputs = {
        # Set the `defaultPackage` output to the "example` package from `packages`.
        # package = "example";
        # Set the `defaultApp` output to the "example` app from `apps`.
        # app = "example";
      };
      # Overrides provided here will apply to *every crate*,
      # for *every system*. To selectively override per crate,
      # one can use `common.cargoPkg.name` attribute. To selectively
      # override per system one can use `common.system` attribute.
      overrides = {
        # Override the systems to generate outputs for.
        systems = prev: prev;
        # Overlays to use for the nixpkgs package set.
        pkgsOverlays = [];
        # Override crate overrides.
        #
        # The environment variables and build inputs specified here will
        # also get exported in the development shell.
        crateOverrides = common: prev: {
          # test = old: {
          #   buildInputs = (old.buildInputs or []) ++ [ common.pkgs.hello ];
          #   TEST_ENV = "test";
          # }
        };
        # Development shell overrides.
        shell = common: prev: {
          # Packages to be put in $PATH.
          packages = prev.packages ++ [];
          # Commands that will be shown in the `menu`. These also get added
          # to packages.
          commands =
            prev.commands
            ++ [
              # { package = common.pkgs.git; }
              # { name = "helloworld"; command = "echo 'Hello world'"; }
            ];
          # Environment variables to be exported.
          env =
            prev.env
            ++ [
              # lib.nameValuePair "PROTOC" "protoc"
              # { name = "HOME_DIR"; eval = "$HOME"; }
            ];
        };
      };
    };
}
