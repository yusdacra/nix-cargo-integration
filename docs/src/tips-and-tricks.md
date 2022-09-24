# Tips and tricks

## Ignoring `Cargo.lock` in Rust libraries

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

## Enabling trace

Traces in the library can be enabled by setting the `NCI_DEBUG` environment
variable to `1` and passing `--impure` to `nix`. Example:
```
NCI_DEBUG=1 nix build --impure .
```
