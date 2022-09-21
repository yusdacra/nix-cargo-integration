# Nix library documentation

**IMPORTANT** public API promises: Any API that is not documented here **IS NOT** counted
as "public" and therefore can be changed without breaking SemVer. This does not mean that
changes will be done without any notice. You are still welcome to create issues / discussions
about them. Upstream projects such as [devshell], [dream2nix] etc. can have breaking changes,
these breakages will be limited to `overrides.shell` and `overrides.build` in the public API,
since these directly modify [devshell] / [dream2nix] builder configs.

## The `common` attribute set

This attribute set is passed to (almost) all overrides. It contains everything you may
need for adding stuff, such as the nixpkgs package set (`common.pkgs`) and other shared
data between build and development shell (`common.buildInputs`, `common.env` etc.). For
more information on what `common` actually exports, please check the bottom of [common.nix](./src/common.nix).

## `makeOutputs`

Generates outputs for all systems specified in `Cargo.toml` (defaults to `defaultSystems` of `nixpkgs`).

### Arguments

- `root`: directory where `Cargo.lock` and `Cargo.toml` (workspace or package manifest) is in (type: path)
- `pkgsOverlays`: overlays to apply to the nixpkgs package set (type: list of nixpkgs overlays)
- `config`: override that will be applied on the workspace.metadata.nix Cargo.toml config (type: attrset)
    - `crateOverrides`: crate overrides that will be directly passed to dream2nix (type: attrset)
- `overrides.crateName`: overrides that are crate namespaced (type: attrset)
    - `config`: override that will be applied to package.metadata.nix Cargo.toml config (type: attrset)
    - `wrapper`: a function that produces as derivation. this can be used to wrap packages. (type: `buildConfig: package: derivation`)
    - `shell`: override for devshell (type: `prev: { }`)
        - this will override *all* [devshell] configuration(s), refer to [devshell] for more information
    - `build`: override for build config (type: `prev: { }`)
    - `crateOverrides`: crate overrides that will be directly passed to dream2nix (type: attrset)

[devshell]: https://github.com/numtide/devshell "devshell"
[dream2nix]: https://github.com/nix-community/dream2nix "dream2nix"
