# nix-cargo-integration

Library to easily and effortlessly integrate Cargo projects with Nix.

- Uses [naersk], [crate2nix] or [buildRustPackage] to build Cargo packages and [devshell] to provide a development shell.
Allows changing between "build platforms" by just changing one attribute (see `buildPlatform`).
- Allows configuration from `Cargo.toml` file(s) via `package.metadata.nix` and `workspace.metadata.nix` attributes.
- Has sensible defaults, and strives to be compatible with Cargo (autobins, etc.).
- Aims to offload work from the user; comes with useful configuration options (like `renameOutputs`, `defaultOutputs` etc.)
- Can generate nixpkgs-compatible nix expressions, so you don't need to maintain a seperate derivation for nixpkgs! (see `How to generate a nixpkgs-compatible expression`)
- [naersk] and [crate2nix] `buildPlatform`s allow building packages directly from `Cargo.lock`. [buildRustPackage] uses the `cargoVendorHash` attribute.

## Usage

### With flakes

Add:
```nix
{
  inputs = {
    nixCargoIntegration.url = "github:yusdacra/nix-cargo-integration";
  };
  outputs = inputs: inputs.nixCargoIntegration.lib.makeOutputs { root = ./.; };
}
```
to your `flake.nix`.

### Without flakes

You can use [flake-compat] to provide the default outputs of the flake for non-flake users.

If you aren't using flakes, you can do (in your `default.nix` file for example):
```nix
let
  nixCargoIntegrationSrc = fetchTarball {
    url = "https://github.com/yusdacra/nix-cargo-integration/archive/<rev>.tar.gz";
    sha256 = "<hash>";
  };
  nixCargoIntegration = import nixCargoIntegrationSrc;
in nixCargoIntegration.makeOutputs { root = ./.; }
```

You can also couple it with [niv](https://github.com/nmattia/niv):
- First run `niv add yusdacra/nix-cargo-integration`
- Then you can write in your `default.nix` file:
    ```nix
    let
      sources = import ./sources.nix;
      nixCargoIntegration = import sources.nix-cargo-integration;
    in nixCargoIntegration.makeOutputs { root = ./.; }
    ```

### Examples

- [Basic flake.nix template with commented fields and overrides](./example_flake.nix)
- [crate2nix build platform crate overrides usage](https://gitlab.com/veloren/veloren/-/blob/master/flake.nix)
- [Modifying cargo build options to build a specific feature and changing outputs based on the feature used](https://github.com/yusdacra/bernbot/blob/master/flake.nix)

## Library documentation

**IMPORTANT** public API promises: Any API that is not documented here **IS NOT** counted
as "public" and therefore can be changed without breaking SemVer. This does not mean that
changes will be done without any notice. You are still welcome to create issues / discussions
about them. Upstream projects such as [devshell], `nixpkgs` ([buildRustPackage]) etc. can have
breaking changes, these breakages will be limited to `overrides`' `shell` and `build` in the
public API, since these directly modify [devshell] / `buildPlatform` configs.

NOTE: `nix-cargo-integration` does not directly use upstream [naersk] / [crate2nix]. It uses
forks of them which contain additional fixes and features that aren't upstream.

### `makeOutputs`

Generates outputs for all systems specified in `Cargo.toml` (defaults to `defaultSystems` of `nixpkgs`).

#### Arguments

- `enablePreCommitHooks`: whether to enable pre-commit hooks (type: boolean) (default: `false`)
- `buildPlatform`: platform to build crates with (type: `"naersk", "crate2nix" or "buildRustPackage"`) (default: `"naersk"`)
- `root`: directory where `Cargo.lock` and `Cargo.toml` (workspace or pacakge manifest) is in (type: path)
- `cargoVendorHash`: vendor hash feeded into [buildRustPackage]'s `cargoSha256` (type: string) (default: `lib.fakeHash`)
- `overrides`: overrides for devshell, build and common (type: attrset) (default: `{ }`)
    - `overrides.systems`: mutate the list of systems to generate for (type: `def: [ ]`)
    - `overrides.sources`: override for the sources used by common (type: `common: prev: { }`)
    - `overrides.pkgs`: override for the configuration while importing nixpkgs in common (type: `common: prev: { }`)
    - `overrides.crateOverrides`: override for crate2nix crate overrides (type: `common: prev: { }`)
    - `overrides.common`: override for common (type: `prev: { }`)
        - this will override *all* common attribute set(s), refer to [common.nix](./common.nix) for more information
    - `overrides.shell`: override for devshell (type: `common: prev: { }`)
        - this will override *all* [devshell] configuration(s), refer to [devshell] for more information
    - `overrides.build`: override for build config (type: `common: prev: { }`)
        - this will override [naersk]/[crate2nix]/[buildRustPackage] build config, refer to [naersk]/[crate2nix]/[buildRustPackage] for more information
    - `overrides.mainBuild`: override for main crate build derivation (type: `common: prev: { }`)
        - this will override *all* [naersk]/[crate2nix]/[buildRustPackage] main crate build derivation(s), refer to [naersk]/[crate2nix]/[buildRustPackage] for more information
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
overrides.sources: override for the sources used by common (type: common: prev: { })
overrides.pkgs: override for the configuration while importing nixpkgs in common (type: common: prev: { })
overrides.crateOverrides: override for crate2nix crate overrides (type: common: prev: { })
overrides.common: override for common (type: prev: { })
this will override all common attribute set(s), refer to common.nix for more information
overrides.shell: override for devshell (type: common: prev: { })
this will override all devshell configuration(s), refer to devshell for more information
overrides.build: override for build config (type: common: prev: { })
this will override naersk/crate2nix/buildRustPackage build config, refer to n
- `enable`: whether to enable pre commit hooks (type: boolean) (default: `false`)

#### `cachix` attributes

- `name`: name of the cachix cache (type: string)
- `key`: public key of the cachix cache (type: string)

#### `devshell` attributes

Refer to [devshell] documentation.

NOTE: Attributes specified here **will not** be used if a top-level `devshell.toml` file exists.

[devshell]: https://github.com/numtide/devshell "devshell"
[naersk]: https://github.com/nmattia/naersk "naersk"
[crate2nix]: https://github.com/kolloch/crate2nix "crate2nix"
[flake-compat]: https://github.com/edolstra/flake-compat "flake-compat"
[buildRustPackage]: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md#compiling-rust-applications-with-cargo-compiling-rust-applications-with-cargo "buildRustPackage"

### How to generate a nixpkgs-compatible expression

`nix-cargo-integration` will generate outputs named `<packageOutputName>-derivation`.
You can `nix build` these, and it will result in a `.nix` text file. After generating one,
be sure to review it and change anything broken, such as source fetching.