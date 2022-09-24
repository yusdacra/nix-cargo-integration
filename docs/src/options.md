# `Cargo.toml` attributes documentation

The attributes described here go in a `Cargo.toml` file.

- `workspace.metadata.nix` attributes apply to *the whole workspace*.
- `package.metadata.nix` attributes only apply to the package declared
  in the same `Cargo.toml` the attributes were defined in.

These also apply to the Nix attributes `config` and `pkgConfig`.

## `package.metadata.nix` attributes

- `build`: whether to enable outputs which build the package (type: boolean) (default: `false`)
- `app`: whether to enable the application output (type: boolean) (default: `false`)
- `longDescription`: a longer description (type: string)
- `runtimeLibs`: libraries that will be put in `LD_LIBRARY_PRELOAD` environment variable for the dev env (type: list) (default: `[]`)
  - these will also be added to the resulting package when you build it, as a wrapper that adds the env variable.
- `dream2nixSettings`: settings that will be applied to dream2nix. (type: list of attrsets) (default: `[]`)

#### Examples

```toml
[package.metadata.nix]
build = true
app = true
longDescription = "blablabla..."
runtimeLibs = ["vulkan-loader", "ffmpeg"]
dream2nixSettings = [{translator = "cargo-toml"}]
```

```nix
{
  pkgConfig = common: {
    example-crate = {
      build = true;
      app = true;
      longDescription = "blablabla...";
      runtimeLibs = with common.pkgs; [vulkan-loader ffmpeg];
      dream2nixSettings = [{translator = "cargo-toml";}];
    }
  };
}
```

### `overrides` attributes

Key value map used to specify overrides for this package.
Dependencies / environment variables put here will also be exported to the development environment.

#### Examples

```toml
[package.metadata.nix.overrides.add-inputs]
buildInputs = ["xorg.libxcb"]
[package.metadata.nix.overrides.add-env.env]
TEST_ENV = "true"
PROTOC = "eval ''${pkgs.protoc}/bin/protoc''"
```

```nix
{
  pkgConfig = common: {
    example-crate.overrides = {
      add-inputs = {
        buildInputs = old: old ++ [common.pkgs.xorg.libxcb];
      };
      add-env = {
        TEST_ENV = "true";
        PROTOC = "${common.pkgs.protoc}/bin/protoc";
      };
    };
  };
}
```

### `depsOverrides` attributes

Same as `overrides`, but only applicable to the `crane` builder (the default).
Allows you to specify overrides for the dependencies derivation.

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

#### Examples

```toml
[package.metadata.nix.desktopFile]
name = "My App"
comment = "This app is for blabla"
icon = "./resources/myapp.ico"
genericName = "App"
categories = ["Something"]
```

```nix
{
  pkgConfig = common: {
    example-crate.desktopFile = {
      name = "My App";
      comment = "This app is for blabla";
      icon = "./resources/myapp.ico";
      genericName = "App";
      categories = ["Something"];
    };
  };
}
```

### `features` attributes

Allows you to set which Cargo features will be enable while building this crate.

- `release`: features to enable while building release builds (type: list of strings) (default: `[]`)
- `debug`: features to enable while building debug builds (type: list of strings) (default: `[]`)
- `test`: features to enable while building test builds (type: list of strings) (default: `[]`)

#### Examples

```toml
[package.metadata.nix.features]
release = ["default-publish"]
debug = ["default-dev"]
test = ["default-publish", "testing"]
```

```nix
{
  pkgConfig = common: {
    example-crate.features = {
      release = ["default-publish"];
      debug = ["default-dev"];
      test = ["default-publish", "testing"];
    };
  };
}
```

## `workspace.metadata.nix` attributes

NOTE: If `root` does not point to a workspace, all of the attributes listed here
will be available in `package.metadata.nix`.

- `systems`: systems to enable for the flake (type: list)
    - defaults to `nixpkgs` [`supportedSystems` and `limitedSupportSystems`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/release.nix#L14)
- `toolchain`: rust toolchain to use (type: one of "stable", "beta" or "nightly") (default: "stable")
    - if the `rust-toolchain` or `rust-toolchain.toml` file exists at project root, it will be used instead of this attribute
- `renameOutputs`: rename outputs to something else (type: attrset of string values) (default: {})
- `defaultOutputs`: set default outputs in nix outputs (type: `{app = string; package = string;}`)

#### Examples

```toml
[workspace.metadata.nix]
systems = ["x86_64-linux", "aarch64-linux"]
toolchain = "beta"
```

```nix
{
  config = common: {
    systems = ["x86_64-linux", "aarch64-linux"];
    toolchain = "beta";
  };
}
```

### `preCommitHooks` attributes

- `enable`: whether to enable pre commit hooks (type: boolean) (default: `false`)

#### Examples

```toml
[workspace.metadata.nix]
preCommitHooks.enable = true
```

```nix
{
  config = common: {
    preCommitHooks = true;
  };
}
```

### `cachix` attributes

- `name`: name of the cachix cache (type: string)
- `key`: public key of the cachix cache (type: string)

#### Examples

```toml
[workspace.metadata.nix.cachix]
name = "mycachix"
key = "mycachixpublickey"
```

```nix
{
  config = common: {
    cachix = {
      name = "mycachix";
      key = "mycachixpublickey";
    };
  };
}
```

### `shell` attributes

Anything put here will be used to configure the devshell.
Refer to [devshell] documentation for configuration options.

NOTE: Attributes specified here **will not** be used if a top-level `devshell.toml` file exists.

#### Examples

```toml
[workspace.metadata.nix.shell]
name = "myshell"
packages = ["gnumake"]
```

```nix
{
  config = common: {
    shell = {
      name = "myshell";
      packages = [common.pkgs.gnumake];
    };
    # alternatively it can also be a function that takes the previous shell config
    # note that this does exactly the same as above, NCI will automatically merge some options
    shell = prev: {
      name = "myshell";
      packages = prev.packages ++ [common.pkgs.gnumake];
    };
  };
}
```
