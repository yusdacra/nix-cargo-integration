{lib, ...}: let
  l = lib // builtins;
  t = l.types;

  mkDrvConfig = desc:
    l.mkOption {
      type = t.attrs;
      default = {};
      description = ''
        ${desc}
        Environment variables must be defined under an attrset called `env`.
      '';
    };
in {
  options = {
    path = l.mkOption {
      type = t.path;
      example = "./path/to/project";
      description = "The absolute path of this project";
    };

    export = l.mkOption {
      type = t.bool;
      default = true;
      example = false;
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

    drvConfig = mkDrvConfig "Change main derivation configuration";
    depsDrvConfig = mkDrvConfig "Change dependencies derivation configuration";

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
