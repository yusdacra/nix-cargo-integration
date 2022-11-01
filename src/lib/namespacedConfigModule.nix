{lib, ...}: let
  inherit
    (lib)
    types
    mkOption
    mkEnableOption
    ;

  mkStrOption = description: example:
    mkOption {
      type = types.str;
      default = "";
      example = ''
        ```
        ${example}
        ```
      '';
      inherit description;
    };
  desktopFileOptions = {
    name = mkStrOption "The name to show on desktop." "Test App";
    genericName = mkStrOption "A generic name for the app." "App";
    comment = mkStrOption "The description of the app." "An app that does things.";
    icon = mkStrOption "The path to an icon relative to the root." "./resources/icon.ico";
    categories = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ''
        ```nix
        ["Multimedia" "Internet"]
        ```
      '';
      description = "The categories of this app.";
    };
  };
  dream2nixOverridesOption = description:
    mkOption {
      type = types.attrsOf types.attrs;
      default = {};
      example = ''
        ```nix
        {
          add-inputs = {
            buildInputs = [pkgs.hello];
            TEST_ENV = "1";
            overrideAttrs = old: {
              nativeBuildInputs = old.nativeBuildInputs ++ [pkgs.pkg-config];
            };
          };
        }
        ```
      '';
      inherit description;
    };
in {
  options = {
    build = mkEnableOption "package outputs";
    app = mkEnableOption "app outputs";
    longDescription = mkOption {
      type = types.str;
      default = "";
      example = ''
        ```
        A paragraph explaining what this app does.
        ```
      '';
      description = "A longer description that explains what your app does.";
    };
    desktopFile = mkOption {
      type = types.nullOr (
        types.oneOf [
          types.str
          types.path
          (types.submoduleWith {modules = [{options = desktopFileOptions;}];})
        ]
      );
      default = null;
      example = ''
        ''\nSet via a relative path to root:
        ```nix
        {
          desktopFile = "./resources/app.desktop";
        }
        ```
        Set via a path:
        ```nix
        {
          desktopFile = ./resources/app.desktop;
        }
        ```
        Set via an attrset:
        ```nix
        {
          desktopFile = {
            name = "Test app";
            genericName = "App";
            comment = "An app that does stuff";
            icon = "./resources/icon.ico";
            categories = ["Category"];
          };
        }
        ```
      '';
      description = "Desktop file";
    };
    features = mkOption {
      type = types.attrsOf (types.listOf types.str);
      default = [];
      example = ''
        ```nix
        {
          release = ["default" "some-feature"];
          debug = ["default-debug"];
          bench = ["default" "bench"];
        }
        ```
      '';
      description = "Set features to enable when building with a profile.";
    };
    profiles = mkOption {
      type = types.attrsOf types.bool;
      default = {
        release = true;
        debug = false;
      };
      description = ''
        Profiles to generate packages for.
        Set the profile to `true` to enable running tests, `false` to disable.
      '';
      example = ''
        ```nix
        {
          release = true;
          debug = false;
          test = true;
          bench = false;
        }
        ```
      '';
    };
    overrides =
      dream2nixOverridesOption
      "dream2nix overrides for this package.";
    depsOverrides =
      dream2nixOverridesOption
      "dream2nix overrides for the dependency derivation of this package.";
    wrapper = mkOption {
      type = types.functionTo (types.functionTo types.package);
      default = _: old: old;
      description = ''
        This option is intended to let you create a wrapper around
        a derivation, which will be used in the outputs.
        `buildConfig` is the arguments passed to `dream2nix.lib.makeFlakeOutputs`
        along with variables like `release`, `doCheck` etc.
      '';
    };
    dream2nixSettings = mkOption {
      type = types.listOf types.attrs;
      default = [];
      example = ''
        ```nix
        [{translator = "cargo-toml";}]
        ```
      '';
      description = "Settings to pass to dream2nix.";
    };
  };
}
