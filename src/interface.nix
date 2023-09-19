{
  self,
  lib,
  flake-parts-lib,
  ...
}: let
  l = lib // builtins;
  t = l.types;
in {
  options = {
    nci._inputs = l.mkOption {
      type = t.raw;
      internal = true;
    };
    nci.source = l.mkOption {
      type = t.path;
      default = self;
      defaultText = "self";
      description = ''
        The source path that will be used as the 'flake root'.
        By default this points to the directory 'flake.nix' is in.
      '';
    };
    perSystem =
      flake-parts-lib.mkPerSystemOption
      ({pkgs, ...}: {
        options = {
          nci.toolchainConfig = l.mkOption {
            type = t.nullOr (t.either t.path t.attrs);
            default = null;
            description = "The toolchain configuration that will be used";
            example = l.literalExpression "./rust-subproject/rust-toolchain.toml";
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
                # define the absolute path to the project
                my-project.path = ./.;
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
            description = "Each crate's (or project's) outputs";
          };
        };
      });
  };
}
