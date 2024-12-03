# nix-cargo-integration

Easily and effortlessly integrate Cargo projects with Nix.

- Uses [dream2nix](https://github.com/nix-community/dream2nix) to build Cargo packages and provide a development shell (dream2nix default, also supports numtide devshell, check examples).
- It's a [flake-parts](https://github.com/hercules-ci/flake-parts) module, so you can easily include it in existing Nix code that also use `flake-parts`.
- Has sensible defaults, and strives to be compatible with Cargo.
- Aims to offload work from the user; comes with useful configuration options.

## Documentation

Documentation for `master` branch is on [flake-parts website](https://flake.parts/options/nix-cargo-integration.html)
(alternatively, read options directly in [`src/interface.nix`](./src/interface.nix) and [`src/modules`](./src/modules)).

Examples can be found at [`examples`](./examples) directory.
Also see the [discussions](https://github.com/yusdacra/nix-cargo-integration/discussions) for answers to possible questions.

Important (mostly breaking) changes can be found in [`CHANGELOG.md`](./CHANGELOG.md).

## Installation

Run `nix flake init -t github:yusdacra/nix-cargo-integration` to initialize a simple `flake.nix`.

You can also run `nix flake init -t github:yusdacra/nix-cargo-integration#simple-crate` to initialize a Cargo crate alongside the `flake.nix`,
or `nix flake init -t github:yusdacra/nix-cargo-integration#simple-workspace` for a Cargo workspace with a `flake.nix`.

If you already have a `flake.nix` with `flake-parts` setup, just add NCI to inputs:

```nix
{
  # ...
  inputs.nci.url = "github:yusdacra/nix-cargo-integration";
  # ...
}
```

and then inside the `mkFlake`:

```nix
{
  imports = [
    inputs.nci.flakeModule
  ];
}
```

## Tips and tricks

### Ignoring `Cargo.lock` in Rust libraries

The [official recommendation](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html)
for Rust libraries *used to* say to add `Cargo.lock` to the `.gitignore`.
[This is now no longer the case](https://blog.rust-lang.org/2023/08/29/committing-lockfiles.html),
however older projects may still do this, which will cause conflicts
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
