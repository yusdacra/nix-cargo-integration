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
      ({pkgs, ...}: let
        toolchains = import ./functions/findRustToolchain.nix {
          inherit lib pkgs;
          inherit (inp) rust-overlay;
          path = toString self;
        };
      in {
        options = {
          nci.export = l.mkOption {
            type = t.bool;
            default = false;
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
          };
          nci.toolchains = {
            build = l.mkOption {
              type = t.package;
              default = toolchains.build;
            };
            shell = l.mkOption {
              type = t.package;
              default = toolchains.shell;
            };
          };
          nci.projects = l.mkOption {
            type = t.lazyAttrsOf (t.submoduleWith {
              modules = [./modules/project.nix];
            });
            default = {};
          };
          nci.crates = l.mkOption {
            type = t.lazyAttrsOf (t.submoduleWith {
              modules = [./modules/crate.nix];
              specialArgs = {inherit pkgs;};
            });
            default = {};
          };
          nci.outputs = l.mkOption {
            type = t.lazyAttrsOf (t.submoduleWith {
              modules = [./modules/output.nix];
            });
            readOnly = true;
          };
        };
      });
  };
}
