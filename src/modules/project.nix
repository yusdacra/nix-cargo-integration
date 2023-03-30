{lib, ...}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
    relPath = l.mkOption {
      type = t.str;
      default = "";
      example = "path/to/project";
      description = "The path of this project relative to the flake's root";
    };

    export = l.mkOption {
      type = t.bool;
      default = false;
      example = true;
      description = ''
        `export` option that will affect all packages in this project.
        For more information refer to `nci.crates.<name>.export` option.
      '';
    };

    profiles = l.mkOption {
      type = t.attrsOf (t.submoduleWith {
        modules = [./profile.nix];
      });
      default = {
        dev = {};
        release = {
          runTests = true;
        };
      };
      example = l.literalExpression ''
        {
          dev = {};
          release.runTests = true;
          custom-profile.features = ["some" "features"];
        }
      '';
      description = ''
        `profiles` option that will affect all packages in this project.
        For more information refer to `nci.crates.<name>.profiles` option.
      '';
    };

    overrides = l.mkOption {
      type = t.attrsOf t.attrs;
      default = {};
      example = l.literalExpression ''
        {
          add-env = {TEST_ENV = 1;};
          add-inputs.overrideAttrs = old: {
            buildInputs = (old.buildInputs or []) ++ [pkgs.hello];
          };
        }
      '';
      description = ''
        `overrides` option that will affect all packages in this project.
        For more information refer to `nci.crates.<name>.overrides` option.
      '';
    };
    depsOverrides = l.mkOption {
      type = t.attrsOf t.attrs;
      default = {};
      example = l.literalExpression ''
        {
          add-env = {TEST_ENV = 1;};
          add-inputs.overrideAttrs = old: {
            buildInputs = (old.buildInputs or []) ++ [pkgs.hello];
          };
        }
      '';
      description = ''
        `depsOverrides` option that will affect all packages in this project.
        For more information refer to `nci.crates.<name>.depsOverrides` option.
      '';
    };

    runtimeLibs = l.mkOption {
      type = t.listOf t.package;
      default = [];
      example = l.literalExpression ''
        [pkgs.alsa-lib pkgs.libxkbcommon]
      '';
      description = ''
        `runtimeLibs` option that will affect all packages in this project.
        For more information refer to `nci.crates.<name>.runtimeLibs` option.
      '';
    };
  };
}
