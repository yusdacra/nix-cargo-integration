{
  inputs = {
    nci.url = "github:yusdacra/nix-cargo-integration";
  };

  outputs = inputs:
    inputs.nci.lib.makeOutputs {
      # The workspace / package folder where the `Cargo.toml` resides.
      root = ./.;
      config = common: {
        # Which dream2nix builder to use.
        # Usually you don't need mess with this.
        # The default is "crane".
        builder = "crane";
        # Change the systems to generate outputs for.
        systems = ["x86_64-linux"];
        # Overlays to use for the nixpkgs package set.
        pkgsOverlays = [];
        # Which package outputs to rename to what.
        # This renames both their package names and the generated output names.
        # Applies to generated apps too.
        renameOutputs = {
          # "test" will be renamed to "example".
          "test" = "example";
        };
        # Default outputs to set.
        defaultOutputs = {
          # Set the `defaultPackage` output to the "example` package from `packages`.
          package = "example";
          # Set the `defaultApp` output to the "example` app from `apps`.
          app = "example";
        };
        # Development shell overrides.
        shell = prev: {
          # Packages to be put in $PATH.
          packages = prev.packages ++ [common.pkgs.hello];
          # Commands that will be shown in the `menu`. These also get added
          # to packages.
          commands =
            prev.commands
            ++ [
              {package = common.pkgs.git;}
              {
                name = "helloworld";
                command = "echo 'Hello world'";
              }
            ];
          # Environment variables to be exported.
          env =
            prev.env
            ++ [
              {
                name = "PROTOC";
                value = "protoc";
              }
              {
                name = "HOME_DIR";
                eval = "$HOME";
              }
            ];
        };
      };
      # Configuration that is applied per package.
      pkgConfig = common: {
        # We want to apply these config to the package named "test".
        test = {
          # You can set any option that can be set via Cargo.toml `package.metadata.nix` here.
          config = {};
          # Overrides to be applied to this package.
          # These are directly passed to `dream2nix`, so you can specify
          # overrides here in a way `dream2nix` expects them.
          overrides = {
            # Add some inputs and an env variable.
            example-override-name = {
              buildInputs = old: old ++ [common.pkgs.hello];
              TEST_ENV = "test";
            };
          };
          # This option is intended to let you create a wrapper around
          # a derivation, which will be used in the outputs.
          # `buildConfig` is the arguments passed to `dream2nix.lib.makeFlakeOutputs`
          # along with variables like `release`, `doCheck` etc.
          wrapper = buildConfig: old: old;
          # Append to dream2nix settings.
          # This corresponds to `dream2nix`'s `settings` argument.
          dream2nixSettings = [{translator = "cargo-lock";}];
        };
      };
    };
}
