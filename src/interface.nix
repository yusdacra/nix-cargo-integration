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
            build = {
              package = l.mkOption {
                type = t.package;
                description = "The toolchain that will be used when building derivations";
              };
              components = l.mkOption {
                type = t.listOf t.str;
                default = ["rustc" "cargo" "rust-std"];
                example = l.literalExpression ''
                  ["rustc" "cargo"]
                '';
                description = ''
                  Components to add to the build toolchain (unused if package option is set manually).

                  Note that components added here must be also present in `rust-toolchain.toml`.
                  When not using `rust-toolchain.toml`, you can only use components from the `default` `rustup` profile.
                '';
              };
            };
            shell = {
              package = l.mkOption {
                type = t.package;
                description = "The toolchain that will be used in the development shell";
              };
              components = l.mkOption {
                type = t.listOf t.str;
                default = ["rust-src" "rustfmt" "clippy" "rust-analyzer"];
                example = l.literalExpression ''
                  ["rust-src" "rustfmt" "clippy"]
                '';
                description = ''
                  Components to add to the shell toolchain (unused if package option is set manually).
                  These are added on top of the build toolchain components.

                  Note that components added here must be also present in `rust-toolchain.toml`.
                  When not using `rust-toolchain.toml`, you can only use components from the `default` `rustup` profile.
                '';
              };
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
            description = "Each crate's (or project's) outputs";
          };
        };
      });
  };
}
