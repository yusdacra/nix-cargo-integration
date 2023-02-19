# nix-cargo-integration

Easily and effortlessly integrate Cargo projects with Nix.

- Uses [dream2nix](https://github.com/nix-community/dream2nix) to build Cargo packages and provide a development shell.
- Has sensible defaults, and strives to be compatible with Cargo.
- Aims to offload work from the user; comes with useful configuration options.
- It's a [flake-parts](https://github.com/hercules-ci/flake-parts) module, so you can easily include it in existing Nix code that also use `flake-parts`.

## Documentation

Documentation for `master` branch is on https://flake.parts/options/nix-cargo-integration.html
(alternatively, read options directly in `src/interface.nix` and `src/modules`)

Important (mostly breaking) changes can be found in [`CHANGELOG.md`](./CHANGELOG.md).

## Usage

Run `nix flake init -t github:yusdacra/nix-cargo-integration` to initialize a simple `flake.nix`.

Run `nix flake show github:yusdacra/nix-cargo-integration` to see more templates.

## Tips and tricks

### Ignoring `Cargo.lock` in Rust libraries

The [official recommendation](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html)
for Rust libraries is to add `Cargo.lock` to the `.gitignore`. This conflicts
with the way paths are evaluated when using a `flake.nix`. Only files tracked
by the version control system (i.e. git) can be accessed during evaluation.
This will manifest in the following warning:
```console
$ nix build
trace: Cargo.lock not found for project at path path/to/project.
Please ensure the lockfile exists for your project.
If you are using a VCS, ensure the lockfile is added to the VCS and not ignored (eg. run `git add path/to/project/Cargo.lock` for git).

This project will be skipped and won't have any outputs generated.
Run `nix run .#generate-lockfiles` to generate lockfiles for projects that don't have one.
```

A neat fix for that is to track the path to `Cargo.lock` without staging it
([thanks to @bew](https://github.com/yusdacra/nix-cargo-integration/issues/46#issuecomment-962589582)).
```console
$ git add --intent-to-add Cargo.lock
```
Add `--force` if your `Cargo.lock` is listed in `.gitignore`.
