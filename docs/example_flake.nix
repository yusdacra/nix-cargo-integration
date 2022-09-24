{
  inputs = {
    nci.url = "github:yusdacra/nix-cargo-integration";
  };

  outputs = inputs:
    inputs.nci.lib.makeOutputs {
      # The workspace / package folder where the `Cargo.toml` resides.
      root = ./.;
      # Change the systems to generate outputs for.
      systems = ["x86_64-linux"];
      config = common: {
        # Which dream2nix builder to use.
        # Usually you don't need mess with this.
        # The default is "crane".
        builder = "crane";
        # Overlays to use for the nixpkgs package set.
        pkgsOverlays = [];
        # Some output related settings.
        outputs = {
          # Which package outputs to rename to what.
          # This renames both their package names and the generated output names.
          # Applies to generated apps too.
          rename = {
            # "test" will be renamed to "example".
            "test" = "example";
          };
          # Default outputs to set.
          defaults = {
            # Set the `defaultPackage` output to the "example` package from `packages`.
            package = "example";
            # Set the `defaultApp` output to the "example` app from `apps`.
            app = "example";
          };
        };
        # Development shell config.
        shell = {
          # Packages to be put in $PATH.
          packages = [common.pkgs.hello];
          # Commands that will be shown in the `menu`. These also get added
          # to packages.
          commands = [
            {package = common.pkgs.git;}
            {
              name = "helloworld";
              command = "echo 'Hello world'";
            }
          ];
          # Environment variables to be exported.
          env = [
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
        # Runtime libraries that will be added to `LD_LIBRARY_PATH`.
        # This applies to both dev env and built packages.
        # Note that you can also specify this per package under `pkgConfig`.
        runtimeLibs = [common.pkgs.ffmpeg];
      };
      # Configuration that is applied per package.
      pkgConfig = common: {
        # We want to apply these config to the package named "test".
        test = {
          # Enable packages outputs.
          build = true;
          # Enable apps outputs.
          app = true;
          # Specify features to use for when building the release, debug or test package.
          features = {
            release = ["default-release"];
            debug = ["default"];
            test = ["default" "testing"];
          };
          # add a desktop file to the package
          desktopFile = ./desktop/file/path.desktop;
          # or define with attrset
          desktopFile = {
            name = "Test";
            comment = "Some example app.";
            icon = ./path/to/icon;
            genericName = "Example";
            categories = ["Example Category"];
          };
          # A longer description of the app.
          longDescription = "Something.";
          # Overrides to be applied to the dependencies derivation of this package.
          # This is the same as overrides, but only makes sense if you are using
          # the `crane` builder, which is the default.
          depsOverrides = {
            # Add some inputs and an env variable.
            example-override-name = {
              buildInputs = old: old ++ [common.pkgs.hello];
              TEST_ENV = "test";
            };
          };
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
