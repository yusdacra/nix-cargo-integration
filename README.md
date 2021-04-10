# nix-cargo-integration

Utilities to integrate Cargo projects with Nix. Uses [naersk] to build Cargo packages.

## Usage

- With flakes:
    - Add `nixCargoIntegration.url = "github:yusdacra/nix-cargo-integration";` to your `inputs`.
    - Use it with `outputs = inputs: inputs.nixCargoIntegration.lib.makeFlakeOutputs src;`.
- Without flakes:
    - Fetch this repository `nixCargoIntegrationSrc = builtins.fetchGit { ... };`.
    - Import it `nixCargoIntegration = import nixCargoIntegrationSrc { sources = { inherit rustOverlay devshell naersk nixpkgs; }; }`.
    - Use it with `outputs = nixCargoIntegration.makeFlakeOutputs src;`.

## `package.metadata.nix` attributes

- `systems`: systems to enable for the flake (type: list)
    - defaults to `defaultSystems` of `nixpkgs`
- `executable`: executable name of the build binary (type: string)
- `build`: whether to enable outputs which build the package (type: boolean)
    - defaults to `false` if not specified
- `library`: whether to copy built library to package output (type: boolean)
    - defaults to `false` if not specified
- `app`: whether to enable the application output (type: boolean)
    - defaults to `false` if not specified
- `toolchain`: rust toolchain to use (type: one of "stable", "beta" or "nightly")
    - if not specified, `rust-toolchain` file will be used
- `longDescription`: a longer description (type: string)

### `package.metadata.nix.cachix` attributes

- `name`: name of the cachix cache (type: string)
- `key`: public key of the cachix cache (type: string)

### `package.metadata.nix.xdg` attributes

- `enable`: whether to enable desktop file generation (type: boolean)
- `icon`: icon string according to XDG (type: string)
    - strings starting with "./" will be treated as relative to project directory
    - everything else will be put into the desktop file as-is
- `comment`: comment for the desktop file (type: string)
    - defaults to `package.description` if not specified
- `name`: desktop name for the desktop file (type: string)
    - defaults to `package.name` if not specified
- `genericName`: generic name for the desktop file (type: string)
- `categories`: categories for the desktop file according to XDG specification (type: string)

### `package.metadata.nix.devshell` attributes

Refer to [devshell] documentation.

NOTE: Attributes specified here **will not** be used if a top-level `devshell.toml` file exists.

[devshell]: https://github.com/numtide/devshell "devshell"
[naersk]: https://github.com/nmattia/naersk "naersk"