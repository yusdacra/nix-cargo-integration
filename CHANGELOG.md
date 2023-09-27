# Recent important changes

This is a list of important (mostly breaking) changes. The dates are from
most recent to least recent.

`nix:` means that the change was related to the Nix library part of `nci`.
~~`cargo-toml:` means that the change was related to the `Cargo.toml` attribute part of `nci`.~~

## 27-09-2023

- nix: new `nci.projects.<name>.targets` and `nci.crates.<name>.targets` options
  - These allow you to generate separate packages for separate targets, and configure each target separately
  - Please check the option's documentation for more info, and the `cross-compile-wasm` example.

## 26-09-2023

- nix: `drvConfig` and `depsDrvConfig` options were changed to resemble `dream2nix` more
  - `mkDerivation` options now must be defined under `drvConfig.mkDerivation` and `depsDrvConfig.mkDerivation` respectively
- nix: implemented `drvConfig` and `depsDrvConfig` under `nci.crates.<name>.profiles.<profile name>` option
  - This means that now every profile package can be customized separately.
- nix: added a [new example](./examples/customize-profiles) showcasing how to customize profiles

## 19-09-2023

- nix: update internals to use dream2nix v1 API.
- nix: remove `overrides` and `depsOverrides` options from project and crate settings.
  - These are now replaced by `drvConfig` and `depsDrvConfig` respectively. Please check out the updated examples.
- nix: replace project `relPath` setting with `path` setting.
- nix: change default value of `export` in project settings to `true`.
  - This means that all packages and development shells will be exported by default now.
  - You can set `nci.projects."project-name".export = false` to return to old behaviour.
- nix: added new option `nci.toolchainConfig`
  - This allows you to set the toolchain configuration manually.
  - It can point to a `rust-toolchain.toml` or legacy `rust-toolchain` file, or
  - it can point to an attrset containing what the `toolchain` section in a `rust-toolchain.toml` file would contain
    - (so options such as `channel`, `components` and `targets`)

## 19-02-2023

- nix: rewrite in flake-parts! Please look at the readme for new documentation link.
If you have any questions on how to migrate, please ask them here on GitHub Discussions.

## 04-11-2022

- nix: the outputs prefixed with `-debug` are now named with the `-dev` prefix. @ <https://github.com/yusdacra/nix-cargo-integration/pull/97>
  - This was done to have more consistency with Cargo profiles (eg. `profiles.dev` == `-dev` prefix).

## 24-09-2022

- nix and cargo-toml: the whole interface was changed! Please refer to the documentation and the example flake.

## 20-06-2022

- nix: the `rustOverlay` input was changed to `rust-overlay` @ e3b4e564fc689c8e32d4b5e76f3cbbd055cb9830
- nix: `common.pkgsWithRust` is removed, you can now access the Rust toolchain via `common.rustToolchain` @ e3b4e564fc689c8e32d4b5e76f3cbbd055cb9830

## 19-05-2022

- nix: `overrides.pkgsOverlays` and `overrides.systems` were moved to `pkgsOverlays` and `systems` arguments to `makeOutputs` @ 3e733afea5b5533fc57d10bbd1c2d6b14d6ee304
- nix: `systems` now just take a list of strings instead of a function taking default systems @ 3e733afea5b5533fc57d10bbd1c2d6b14d6ee304

## 12-03-2022

- cargo-toml: `library` option in `package.metadata.nix` is removed and will no longer be used @ 11f26a1aa9aeddfb2ca32b3441091d4d8dc4cf0c
- nix: `overrides.crateOverrides` was renamed to `overrides.crates` @ 11f26a1aa9aeddfb2ca32b3441091d4d8dc4cf0c
