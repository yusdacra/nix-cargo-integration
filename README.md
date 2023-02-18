# nix-cargo-integration

Library to easily and effortlessly integrate Cargo projects with Nix.

- Uses [dream2nix](https://github.com/nix-community/dream2nix) to build Cargo packages and provide a development shell.
- Has sensible defaults, and strives to be compatible with Cargo (autobins, etc.).
- Aims to offload work from the user; comes with useful configuration options

NOTE: `nix-cargo-integration` should work with any Nix version above 2.4+, but
the experience may not be smooth if you aren't using the newest version of Nix.

## Documentation

Documentation for `master` branch is on https://flake.parts/options/nix-cargo-integration.html

Important (mostly breaking) changes can be found in [`CHANGELOG.md`](./CHANGELOG.md).

## Usage

Run `nix flake init -t github:yusdacra/nix-cargo-integration`.

## Tips and tricks

### Ignoring `Cargo.lock` in Rust libraries

The [official recommendation](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html)
for Rust libraries is to add `Cargo.lock` to the `.gitignore`. This conflicts
with the way paths are evaluated when using a `flake.nix`. Only files tracked
by the version control system (i.e. git) can be accessed during evaluation.
This will manifest in the following error:
```console
$ nix build
error: A Cargo.lock file must be present, please make sure it's at least staged in git.
(use '--show-trace' to show detailed location information)
```

A neat fix for that is to track the path to `Cargo.lock` without staging it
([thanks to @bew](https://github.com/yusdacra/nix-cargo-integration/issues/46#issuecomment-962589582)).
```console
$ git add --intent-to-add Cargo.lock
```
Add `--force` if your `Cargo.lock` is listed in `.gitignore`.
