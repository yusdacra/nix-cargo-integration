# nix-cargo-integration

Utility to integrate Cargo projects with Nix.

- Uses [naersk] or [crate2nix] to build Cargo packages and [devshell] to provide development shell.
- Allows configuration from `Cargo.toml` via `package.metadata.nix` and `workspace.metadata.nix` attributes.

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

If you aren't using flakes, you can do:
```nix
let
  nixCargoIntegrationSrc = builtins.fetchGit { url = "https://github.com/yusdacra/nix-cargo-integration.git"; rev = <something>; sha256 = <something>; };
  nixCargoIntegration = import "${nixCargoIntegrationSrc}/lib.nix" {
      sources = { inherit flakeUtils rustOverlay devshell naersk nixpkgs crate2nix preCommitHooks; };
  };
  outputs = nixCargoIntegration.makeOutputs { root = ./.; };
in
```

### Examples

- [Basic flake.nix template with commented fields and overrides](./example_flake.nix)
- [crate2nix build platform crate overrides usage](https://gitlab.com/veloren/veloren/-/blob/master/flake.nix)
- [Modifying cargo build options to build a specific feature and changing outputs based on the feature used](https://github.com/yusdacra/bernbot/blob/master/flake.nix)

## Library documentation

### `makeOutputs`

Runs [makeOutput](#makeOutput) for all systems specified in `Cargo.toml` (defaults to `defaultSystems` of `nixpkgs`).

#### Arguments

- `enablePreCommitHooks`: whether to enable pre-commit hooks (type: boolean) (default: `false`)
- `buildPlatform`: platform to build crates with (type: `"naersk" or "crate2nix"`) (default: `"naersk"`)
- `root`: directory where `Cargo.toml` is in (type: path)
- `overrides`: overrides for devshell, build and common (type: attrset) (default: `{ }`)
    - `overrides.systems`: mutate the list of systems to generate for (type: `def: [ ]`)
    - `overrides.sources`: override for the sources used by common (type: `common: prev: { }`)
    - `overrides.pkgs`: override for the configuration while importing nixpkgs in common (type: `common: prev: { }`)
    - `override.crateOverrides`: override for crate2nix crate overrides (type: `common: prev: { }`)
    - `overrides.common`: override for common (type: `prev: { }`)
        - this will override *all* common attribute set(s), refer to [common.nix](./common.nix) for more information
    - `overrides.shell`: override for devshell (type: `common: prev: { }`)
        - this will override *all* [devshell] configuration(s), refer to [devshell] for more information
    - `overrides.build`: override for build (type: `common: prev: { }`)
        - this will override *all* [naersk]/[crate2nix] build derivation(s), refer to [naersk]/[crate2nix] for more information
    - `overrides.mainBuild`: override for main crate build derivation (type: `common: prev: { }`)
        - this will override *all* [naersk]/[crate2nix] main crate build derivation(s), refer to [naersk]/[crate2nix] for more information

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

#### `crateOverride` attributes (only used for `crate2nix` build platform)

Key-value pairings that are put here will be used to override crates in build derivation.
Dependencies put here will also be exported to the development environment.
For example:
```toml
[package.metadata.nix.crateOverride.xcb]
buildInputs = ["xorg.libxcb"]
env.TEST_ENV = "test"
```

### `package.metadata.nix` attributes

- `build`: whether to enable outputs which build the package (type: boolean)
    - defaults to `false` if not specified
- `library`: whether to copy built library to package output (type: boolean)
    - defaults to `false` if not specified
- `app`: whether to enable the application output (type: boolean)
    - defaults to `false` if not specified
- `longDescription`: a longer description (type: string)

#### `desktopFile` attributes

If this is set to a string specifying a path, the path will be treated as a desktop file and will be used.
The path must start with "./" and specify a path relative ro `root`. 

- `icon`: icon string according to XDG (type: string)
    - strings starting with "./" will be treated as relative to `root`
    - everything else will be put into the desktop file as-is
- `comment`: comment for the desktop file (type: string)
    - defaults to `package.description` if not specified
- `name`: desktop name for the desktop file (type: string)
    - defaults to `package.name` if not specified
- `genericName`: generic name for the desktop file (type: string)
- `categories`: categories for the desktop file according to XDG specification (type: string)

### `workspace.metadata.nix` attributes

NOTE: If `root` does not point to a workspace, all of the attributes listed here
will be available in `package.metadata.nix`.

- `systems`: systems to enable for the flake (type: list)
    - defaults to `defaultSystems` of `nixpkgs`
- `toolchain`: rust toolchain to use (type: one of "stable", "beta" or "nightly")
    - if `rust-toolchain` file exists, it will be used instead of this attribute

#### `preCommitHooks` attributes

- `enable`: whether to enable pre commit hooks (type: boolean)

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
