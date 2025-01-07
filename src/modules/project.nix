{
  lib,
  defaultRustcTarget,
  ...
}: let
  l = lib // builtins;
  t = l.types;
  mkOpt = name: attrs:
    l.mkOption (attrs
      // {
        description = ''
          `${name}` option that will affect all packages in this project.
          For more information refer to `nci.crates.<name>.${name}` option.
        '';
      });
in {
  imports = [
    ../options/drvConfig.nix
    ../options/numtideDevshell.nix
  ];
  options = {
    path = l.mkOption {
      type = t.path;
      example = lib.literalExpression "./path/to/project";
      description = "The absolute path of this project";
    };

    export = mkOpt "export" {
      type = t.bool;
      default = true;
      example = false;
    };

    clippyProfile = mkOpt "clippyProfile" {
      type = t.str;
      default = "dev";
      example = "custom-profile";
    };
    checkProfile = mkOpt "checkProfile" {
      type = t.str;
      default = "release";
      example = "custom-profile";
    };
    docsProfile = mkOpt "docsProfile" {
      type = t.str;
      default = "release";
      example = "custom-profile";
    };
    includeInProjectDocs = mkOpt "includeInProjectDocs" {
      type = t.bool;
      default = true;
      example = false;
    };
    docsIndexCrate = l.mkOption {
      type = t.nullOr t.str;
      default = null;
      example = "my-crate";
      description = ''
        The crate to link it's index.html when building project docs.

        The default will be not symlinking any index.html.
      '';
    };

    profiles = mkOpt "profiles" {
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
    };
    targets = mkOpt "targets" {
      type = t.attrsOf (t.submoduleWith {
        modules = [./target.nix];
      });
      default = {
        ${defaultRustcTarget}.default = true;
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
    };

    runtimeLibs = mkOpt "runtimeLibs" {
      type = t.listOf t.package;
      default = [];
      example = l.literalExpression ''
        [pkgs.alsa-lib pkgs.libxkbcommon]
      '';
    };
  };
}
