# Nix library documentation

**IMPORTANT** public API promises:
Any API that is not documented here **IS NOT** counted as "public" and therefore can be changed without breaking SemVer.
This does not mean that changes will be done without any notice. You can check `CHANGELOG.md` for breaking changes.
You are still welcome to create issues / discussions about them.
Upstream projects such as [devshell], [dream2nix] etc. can have breaking changes.
These breakages will be limited to `config.shell` and `pkgConfig.crateName.build` in the public API, since these directly modify [devshell] / [dream2nix] builder configs.

## The `common` attribute set

This attribute set is passed to `config` and `pkgConfig`.
It contains attributes you may need for adding stuff to overrides / config, such as the nixpkgs package set (`common.pkgs`).
Not all attributes (for example `common.pkgs`) are available for every option, eg. `common.pkgs` can't be used in `renameOutputs` or `defaultOutputs`.
For more information on what `common` actually exports, please check the bottom of [common.nix](./src/common.nix).

## `makeOutputs`

Generates outputs for all systems specified in `Cargo.toml` (defaults to `defaultSystems` of `nixpkgs`).

### Arguments

- `root`: directory where `Cargo.lock` and `Cargo.toml` (workspace or package manifest) is in (type: path)
- `config`: general configuration, corresponds to `workspace.metadata.nix` OR `package.metadata.nix` if this isn't a workspace (type: `common: {}`)
- `pkgConfig`: namespaced configuration, corresponds to `package.metadata.nix` (type: `common: {}`)

[devshell]: https://github.com/numtide/devshell "devshell"
[dream2nix]: https://github.com/nix-community/dream2nix "dream2nix"
