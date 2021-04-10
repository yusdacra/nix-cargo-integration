# nix-cargo-integration

Utility to integrate Cargo projects with Nix.

- Uses [naersk] to build Cargo packages and [devshell] to provide development shell.
- Allows configuration from `Cargo.toml` via `package.metadata.nix` attribute.

## Usage

### With flakes

Add:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixCargoIntegration = {
      url = "github:yusdacra/nix-cargo-integration";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = inputs: inputs.nixCargoIntegration.lib.makeOutputsForSystems src;
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
      sources = { inherit flakeUtils rustOverlay devshell naersk nixpkgs; };
  };
  outputs = nixCargoIntegration.makeOutputsForSystems src;
in
```

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
[flake-compat]: https://github.com/edolstra/flake-compat "flake-compat"