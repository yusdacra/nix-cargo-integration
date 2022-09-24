{
  # args
  configDocs,
  pkgConfigDocs,
  # nixpkgs
  mdbook,
  stdenv,
  writeText,
  ...
}: let
  configDesc = ''
    These are options that can be set under `workspace.metadata.nix` or `package.metadata.nix`.
    They can also be set under `config` under `nci.lib.makeOutputs`:
    ```nix
    {
      config = common: { /* options go here */ };
    }
    ```
  '';
  configMd = writeText "config-options.md" "${configDesc}";
  pkgConfigDesc = ''
    These are options that can be set under `package.metadata.nix`. They are package specific.
    They can also be set under `pkgConfig` under `nci.lib.makeOutputs`:
    ```nix
    {
      pkgConfig = common: {
        example-package = { /* options go here */ };
      };
    }
    ```
  '';
  pkgConfigMd = writeText "pkg-config-options.md" "${pkgConfigDesc}";
in
  stdenv.mkDerivation {
    name = "nci-docs";
    buildInputs = [mdbook];
    src = ./src;

    buildPhase = ''
      cat ${configMd} ${configDocs} > config-options.md
      cat ${pkgConfigMd} ${pkgConfigDocs} > pkg-config-options.md
      cp ${../CHANGELOG.md} CHANGELOG.md
      mdbook build
    '';

    installPhase = ''
      mv book $out
    '';
  }
