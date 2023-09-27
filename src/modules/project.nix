{
  lib,
  pkgs,
  ...
}: let
  l = lib // builtins;
  t = l.types;
  nixpkgsRustLib = import "${pkgs.path}/pkgs/build-support/rust/lib" {inherit lib;};
in {
  imports = [../options/drvConfig.nix];
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
    targets = l.mkOption {
      type = t.attrsOf (t.submoduleWith {
        modules = [./target.nix];
      });
      default = {
        ${nixpkgsRustLib.toRustTarget pkgs.stdenv.hostPlatform}.default = true;
      };
      defaultText = ''
        {
          <host platform>.default = true;
        }
      '';
      example = l.literalExpression ''
        {
          wasm32-unknown-unknown.profiles = ["release"];
          x86_64-unknown-linux-gnu.default = true;
        }
      '';
      description = ''
        `targets` option that will affect all packages in this project.
        For more information refer to `nci.crates.<name>.targets` option.
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
