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
- `systems`: override the list of systems to generate outputs for (type: `def: [ ]`)
- `builder`: which dream2nix builder to use (type: string) (default: `"crane"`)
- `enablePreCommitHooks`: whether to enable pre-commit hooks (type: boolean) (default: `false`)
- `pkgsOverlays`: overlays to apply to the nixpkgs package set (type: list of nixpkgs overlays)
- `renameOutputs`: which crates to rename in package names and output names (type: attrset) (default: `{ }`)
- `defaultOutputs`: which outputs to set as default (type: attrset) (default: `{ }`)
    - `defaultOutputs.app`: app output name to set as default app (`defaultApp`) output (type: string)
    - `defaultOutputs.package`: package output name to set as default package (`defaultPackage`) output (type: string)
- `overrides`: overrides for devshell, crates, build and common (type: attrset) (default: `{ }`)
    - `overrides.sources`: override for the sources used by common (type: `common: prev: { }`)
    - `overrides.crates`: override for changing crate overrides (type: `common: prev: { }`)
    - `overrides.common`: override for common (type: `prev: { }`)
        - this will override *all* common attribute set(s), refer to [common.nix](./src/common.nix) for more information
    - `overrides.shell`: override for devshell (type: `common: prev: { }`)
        - this will override *all* [devshell] configuration(s), refer to [devshell] for more information
    - `overrides.build`: override for build config (type: `common: prev: { }`)
    - `overrides.cCompiler`: override what C compiler will be used (type: `common: { ... }`)
        - if the returned attribute set has `cCompiler`, this is assumed to be a *package*
        and will be used as the new C compiler.
        - if the returned attribute set has `useCCompilerBintools`, this will be used to decide
        whether or not to add the C compiler's `bintools` to the build environment.
- `perCrateOverrides.crateName`: overrides that are crate namespaced (type: attrset)
    - `wrapper`: a function that produces a derivation. this can be used to wrap packages. (type: `common: buildConfig: package: derivation`)

[devshell]: https://github.com/numtide/devshell "devshell"
[dream2nix]: https://github.com/nix-community/dream2nix "dream2nix"
