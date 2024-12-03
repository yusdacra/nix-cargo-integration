{
  self,
  lib,
  flake-parts-lib,
  ...
} @ args: let
  l = lib // builtins;
  t = l.types;
  inputs = args.config.nci._inputs;
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
            mkBuild = l.mkOption {
              type = t.functionTo t.package;
              description = "The function to (given a nixpkgs instance) generate a toolchain that will be used when building derivations";
            };
            mkShell = l.mkOption {
              type = t.functionTo t.package;
              description = "The function to (given a nixpkgs instance) generate a toolchain that will be used in the development shell";
            };
          };
          nci.projects = l.mkOption {
            type = t.lazyAttrsOf (t.submoduleWith {
              modules = [./modules/project.nix];
              specialArgs = {
                defaultRustcTarget = pkgs.stdenv.hostPlatform.rust.rustcTarget;
              };
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
              specialArgs = {inherit pkgs inputs;};
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
          nci.lib = {
            buildCrate = l.mkOption {
              type = t.functionTo t.package;
              readOnly = true;
              description = ''
                A function to build a crate from a provided source (and crate path if workspace) automagically

                The arguments are:
                - `src`: the source for the project (or crate if it's just a crate)
                - `cratePath`: relative path to the provided `src`, used to find the crate if it's a workspace
                - `drvConfig` and `depsDrvConfig`: see `nci.crates.<name>.<drvConfig/depsDrvConfig>` in this documentation (optional)
              '';
            };
          };
        };
      });
  };
}
