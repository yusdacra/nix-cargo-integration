# `Cargo.toml` attributes documentation

The attributes described here go in a `Cargo.toml` file.

- `workspace.metadata.nix` attributes apply to *the whole workspace*.
- `package.metadata.nix` attributes only apply to the package declared
  in the same `Cargo.toml` the attributes were defined in.

## `package.metadata.nix` and `workspace.metadata.nix` shared attributes

- `runtimeLibs`: libraries that will be put in `LD_LIBRARY_PRELOAD` for both dev and build env (type: list)

#### Example

```toml
[package.metadata.nix]
runtimeLibs = ["vulkan-loader", "xorg.libXi"]
```

### `env` attributes

Key-value pairings that are put here will be exported into the development and build environment.

#### Example

```toml
[package.metadata.nix.env]
PROTOC = "protoc"
```

### `crateOverride` attributes

Key-value pairings that are put here will be used to override crates in build derivation.
Dependencies / environment variables put here will also be exported to the development environment.

#### Example

```toml
[package.metadata.nix.crateOverride.xcb]
buildInputs = ["xorg.libxcb"]
env.TEST_ENV = "test"
```

## `package.metadata.nix` attributes

- `build`: whether to enable outputs which build the package (type: boolean) (default: `false`)
- `app`: whether to enable the application output (type: boolean) (default: `false`)
- `longDescription`: a longer description (type: string)

#### Example

```toml
[package.metadata.nix]
build = true
app = true
longDescription = "blablabla..."
```

### `desktopFile` attributes

If this is set to a string specifying a path, the path will be treated as a desktop file and will be used.
The path must start with "./" and specify a path relative ro `root`. 

- `icon`: icon string according to XDG (type: string)
    - strings starting with "./" will be treated as relative to `root`
    - everything else will be put into the desktop file as-is
- `comment`: comment for the desktop file (type: string) (default: `package.description`)
- `name`: desktop name for the desktop file (type: string) (default: `package.name`)
- `genericName`: generic name for the desktop file (type: string)
- `categories`: categories for the desktop file according to XDG specification (type: list of strings)

#### Example

```toml
[package.metadata.nix.desktopFile]
name = "My App"
comment = "This app is for blabla"
icon = "./resources/myapp.ico"
genericName = "App"
categories = ["Something"]
```

## `workspace.metadata.nix` attributes

NOTE: If `root` does not point to a workspace, all of the attributes listed here
will be available in `package.metadata.nix`.

- `systems`: systems to enable for the flake (type: list)
    - defaults to `nixpkgs` [`supportedSystems` and `limitedSupportSystems`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/release.nix#L14)
- `toolchain`: rust toolchain to use (type: one of "stable", "beta" or "nightly") (default: "stable")
    - if the `rust-toolchain` or `rust-toolchain.toml` file exists at project
    root, it will be used instead of this attribute

#### Example

```toml
[workspace.metadata.nix]
systems = ["x86_64-linux", "aarch64-linux"]
toolchain = "beta"
```

### `preCommitHooks` attributes

- `enable`: whether to enable pre commit hooks (type: boolean) (default: `false`)

#### Example

```toml
[workspace.metadata.nix]
preCommitHooks.enable = true
```

### `cachix` attributes

- `name`: name of the cachix cache (type: string)
- `key`: public key of the cachix cache (type: string)

#### Example

```toml
[workspace.metadata.nix.cachix]
name = "mycachix"
key = "mycachixpublickey"
```

### `devshell` attributes

Anything put here will be used to configure the devshell.
Refer to [devshell] documentation for configuration options.

NOTE: Attributes specified here **will not** be used if a top-level `devshell.toml` file exists.

#### Example

```toml
[workspace.metadata.nix.devshell]
name = "myshell"
packages = ["gnumake"]
```
