# nix-cargo-integration

Library to easily and effortlessly integrate Cargo projects with Nix.

- Uses [naersk], [crate2nix] or [buildRustPackage] to build Cargo packages and [devshell] to provide a development shell.
Allows changing between "build platforms" by just changing one attribute (see `buildPlatform`).
- Allows configuration from `Cargo.toml` file(s) via `package.metadata.nix` and `workspace.metadata.nix` attributes.
- Has sensible defaults, and strives to be compatible with Cargo (autobins, etc.).
- Aims to offload work from the user; comes with useful configuration options (like `renameOutputs`, `defaultOutputs` etc.)
- Can generate nixpkgs-compatible Nix expressions that captures all your packages dependencies / env vars and so on.
You don't need to maintain a seperate derivation for nixpkgs! (see `Generating a nixpkgs-compatible package expression` in manual)
- [naersk] and [crate2nix] `buildPlatform`s allow building packages directly from `Cargo.lock`. [buildRustPackage] uses the `cargoVendorHash` attribute.
- A CLI tool that let's you compile and run arbitrary Rust repositories directly without messing with any files or setting up overlays (see `Using the nci CLI` in manual)

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

- [Basic flake.nix template with commented fields and overrides](./docs/example_flake.nix)
- [crate2nix build platform crate overrides usage](https://gitlab.com/veloren/veloren/-/blob/master/flake.nix)
- [Modifying cargo build options to build a specific feature and changing outputs based on the feature used](https://github.com/yusdacra/bernbot/blob/master/flake.nix)
- [Flake using a bit of everything](https://github.com/harmony-development/Crust/blob/master/flake.nix)

## Documentation

You can find library API documentation and others at [the manual](./docs/MANUAL.md).

[devshell]: https://github.com/numtide/devshell "devshell"
[naersk]: https://github.com/nmattia/naersk "naersk"
[crate2nix]: https://github.com/kolloch/crate2nix "crate2nix"
[flake-compat]: https://github.com/edolstra/flake-compat "flake-compat"
[buildRustPackage]: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md#compiling-rust-applications-with-cargo-compiling-rust-applications-with-cargo "buildRustPackage"
