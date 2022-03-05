# Index

- [Library documentation](#library-documentation)
- [Generating a nixpkgs-compatible package expression](#generating-a-nixpkgs-compatible-package-expression)
- [Using the `nci` CLI](#using-the-nci-cli)
- [Enabling trace](#enabling-trace)
- [Tips and Tricks](#tips-and-tricks)

## Library documentation

**IMPORTANT** public API promises: Any API that is not documented here **IS NOT** counted
as "public" and therefore can be changed without breaking SemVer. This does not mean that
changes will be done without any notice. You are still welcome to create issues / discussions
about them. Upstream projects such as [devshell], [dream2nix] etc. can have breaking changes,
these breakages will be limited to `overrides.shell` and `overrides.build` in the public API,
since these directly modify [devshell] / [dream2nix] builder configs.

### The `common` attribute set

This attribute set is passed to (almost) all overrides. It contains everything you may
need for adding stuff, such as the nixpkgs package set (`common.pkgs`) and other shared
data between build and development shell (`common.buildInputs`, `common.env` etc.). For
more information on what `common` actually exports, please check the bottom of [common.nix](./src/common.nix).

### `makeOutputs`

Generates outputs for all systems specified in `Cargo.toml` (defaults to `defaultSystems` of `nixpkgs`).

#### Arguments

- `enablePreCommitHooks`: whether to enable pre-commit hooks (type: boolean) (default: `false`)
- `root`: directory where `Cargo.lock` and `Cargo.toml` (workspace or package manifest) is in (type: path)
- `overrides`: overrides for devshell, build and common (type: attrset) (default: `{ }`)
    - `overrides.systems`: mutate the list of systems to generate for (type: `def: [ ]`)
    - `overrides.sources`: override for the sources used by common (type: `common: prev: { }`)
    - `overrides.pkgsOverlays`: overlays to apply to the nixpkgs package set (type: list of nixpkgs overlays)
    - `overrides.crateOverrides`: override for crate overrides (type: `common: prev: { }`)
    - `overrides.common`: override for common (type: `prev: { }`)
        - this will override *all* common attribute set(s), refer to [common.nix](./src/common.nix) for more information
    - `overrides.shell`: override for devshell (type: `common: prev: { }`)
        - this will override *all* [devshell] configuration(s), refer to [devshell] for more information
    - `overrides.build`: override for build config (type: `common: prev: { }`)
- `renameOutputs`: which crates to rename in package names and output names (type: attrset) (default: `{ }`)
- `defaultOutputs`: which outputs to set as default (type: attrset) (default: `{ }`)
    - `defaultOutputs.app`: app output name to set as default app (`defaultApp`) output (type: string)
    - `defaultOutputs.package`: package output name to set as default package (`defaultPackage`) output (type: string)

### `package.metadata.nix` and `workspace.metadata.nix` common attributes

- `runtimeLibs`: libraries that will be put in `LD_LIBRARY_PRELOAD` for both dev and build env (type: list)
- `buildInputs`: common build inputs (type: list)
- `nativeBuildInputs`: common native build inputs (type: list)

#### `env` attributes

Key-value pairings that are put here will be exported into the development and build environment.
For example:
```toml
[package.metadata.nix.env]
PROTOC = "protoc"
```

#### `crateOverride` attributes

Key-value pairings that are put here will be used to override crates in build derivation.
Dependencies / environment variables put here will also be exported to the development environment.
For example:
```toml
[package.metadata.nix.crateOverride.xcb]
buildInputs = ["xorg.libxcb"]
env.TEST_ENV = "test"
```

### `package.metadata.nix` attributes

- `build`: whether to enable outputs which build the package (type: boolean) (default: `false`)
- `library`: whether to copy built library to package output (type: boolean) (default: `false`)
- `app`: whether to enable the application output (type: boolean) (default: `false`)
- `longDescription`: a longer description (type: string)

#### `desktopFile` attributes

If this is set to a string specifying a path, the path will be treated as a desktop file and will be used.
The path must start with "./" and specify a path relative ro `root`. 

- `icon`: icon string according to XDG (type: string)
    - strings starting with "./" will be treated as relative to `root`
    - everything else will be put into the desktop file as-is
- `comment`: comment for the desktop file (type: string) (default: `package.description`)
- `name`: desktop name for the desktop file (type: string) (default: `package.name`)
- `genericName`: generic name for the desktop file (type: string)
- `categories`: categories for the desktop file according to XDG specification (type: string)

### `workspace.metadata.nix` attributes

NOTE: If `root` does not point to a workspace, all of the attributes listed here
will be available in `package.metadata.nix`.

- `systems`: systems to enable for the flake (type: list)
    - defaults to `nixpkgs` `supportedSystems` and `limitedSupportSystems` https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/release.nix#L14
- `toolchain`: rust toolchain to use (type: one of "stable", "beta" or "nightly") (default: "stable")
    - if `rust-toolchain` file exists, it will be used instead of this attribute

#### `preCommitHooks` attributes

- `enable`: whether to enable pre commit hooks (type: boolean) (default: `false`)

#### `cachix` attributes

- `name`: name of the cachix cache (type: string)
- `key`: public key of the cachix cache (type: string)

#### `devshell` attributes

Refer to [devshell] documentation.

NOTE: Attributes specified here **will not** be used if a top-level `devshell.toml` file exists.

## Generating a nixpkgs-compatible package expression

`nix-cargo-integration` will generate outputs named `<packageOutputName>-derivation`.
You can `nix build` these, and it will result in a `.nix` text file. After generating one,
be sure to review it and change anything broken, such as source fetching.

## Using the `nci` CLI

This repo has a CLI program that can help you run arbitrary Rust repos. You can use it with:
```bash
alias nci="nix run github:yusdacra/nix-cargo-integration --"
# Show the outputs of this (flake) source
nci show github:owner/repo
# Run the default app of this source
nci run github:owner/repo
# Run a specific app of this source
nci run github:owner/repo app-name
# Build the default package of this source
nci build github:owner/repo
# Build a specific package of this source
nci build github:owner/repo package-name
# Show the flake metadata for this source
nci metadata github:owner/repo
# Update the source
nci update github:owner/repo
```

## Enabling trace

Traces in the library can be enabled by setting the `NCI_DEBUG` environment
variable to `1` and passing `--impure` to `nix`. Example:
```
NCI_DEBUG=1 nix build --impure .
```

## Tips and tricks

### Ignoring `Cargo.lock` in Rust libraries

The [official recommendation](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html) for Rust libraries is to add `Cargo.lock` to the `.gitignore`.
This conflicts with the way paths are evaluated when using a `flake.nix`. Only files
tracked by the version control system (i.e. git) can be accessed during evaluation.
This will manifest in the following error:
```console
$ nix build
error: A Cargo.lock file must be present, please make sure it's at least staged in git.
(use '--show-trace' to show detailed location information)
```

A neat fix for that is to track the path to `Cargo.lock` without staging it
([thanks to @bew](https://github.com/yusdacra/nix-cargo-integration/issues/46#issuecomment-962589582)).
```console
$ git add --intend-to-add Cargo.lock
```
Add `--force` if your `Cargo.lock` is listed in `.gitignore`.

[devshell]: https://github.com/numtide/devshell "devshell"
[flake-compat]: https://github.com/edolstra/flake-compat "flake-compat"
[dream2nix]: https://github.com/nix-community/dream2nix "dream2nix"
