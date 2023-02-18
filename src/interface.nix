{
  self,
  lib,
  flake-parts-lib,
  ...
} @ args: let
  l = lib // builtins;
  t = l.types;
  inp = args.config.nci._inputs;
in {
  options = {
    nci._inputs = l.mkOption {
      type = t.raw;
      internal = true;
    };
    perSystem =
      flake-parts-lib.mkPerSystemOption
      ({pkgs, ...}: {
        options = {
          nci.export = l.mkOption {
            type = t.bool;
            default = false;
            example = true;
            description = "Whether to export all crates' outputs";
          };
          nci.profiles = l.mkOption {
            type = t.attrsOf (t.submoduleWith {
              modules = [./modules/profile.nix];
            });
            default = {
              dev = {};
              release.runTests = true;
            };
            example = l.literalExpression ''
              {
                dev = {};
                release.runTests = true;
                custom-profile.features = ["some" "features"];
              }
            '';
            description = "Profiles to generate packages for all crates";
          };
          nci.toolchains = {
            build = l.mkOption {
              type = t.package;
              description = "The toolchain that will be used when building derivations";
            };
            shell = l.mkOption {
              type = t.package;
              description = "The toolchain that will be used in the development shell";
            };
          };
          nci.projects = l.mkOption {
            type = t.lazyAttrsOf (t.submoduleWith {
              modules = [./modules/project.nix];
            });
            default = {};
            example = l.literalExpression ''
              {
                my-crate.relPath = "path/to/crate";
                # empty path for projects at flake root
                my-workspace.relPath = "";
              }
            '';
            description = "Projects (workspaces / crates) to generate outputs for";
          };
          nci.crates = l.mkOption {
            type = t.lazyAttrsOf (t.submoduleWith {
              modules = [./modules/crate.nix];
              specialArgs = {inherit pkgs;};
            });
            default = {};
            example = l.literalExpression ''
              {
                my-crate = {
                  export = true;
                  overrides = {/* stuff */};
                };
              }
            '';
            description = "Crate configurations";
          };
          nci.outputs = l.mkOption {
            type = t.lazyAttrsOf (t.submoduleWith {
              modules = [./modules/output.nix];
            });
            readOnly = true;
            description = "Each crate's outputs";
          };
        };
      });
  };
}
