common:
let
  inherit (common) pkgs workspaceMetadata lib;

  cachixMetadata = workspaceMetadata.cachix or null;
  cachixName = cachixMetadata.name or null;
  cachixKey = cachixMetadata.key or null;

  devshellAttr = workspaceMetadata.devshell or null;
  devshellConfig = if pkgs.lib.isAttrs devshellAttr then (builtins.removeAttrs devshellAttr [ "imports" ]) else { };
  devshellFilePath = common.root + "/devshell.toml";
  importedDevshell = if (builtins.pathExists devshellFilePath) then (pkgs.devshell.importTOML devshellFilePath) else null;

  baseConfig = {
    language = {
      c = {
        compiler = common.cCompiler;
        libraries = common.buildInputs;
        includes = common.buildInputs;
      };
    };
    packages = [ pkgs.rustc ] ++ common.nativeBuildInputs ++ common.buildInputs;
    commands = with pkgs; [
      {
        package = git;
        category = "vcs";
      }
      {
        package = nixpkgs-fmt;
        category = "tools";
      }
      {
        name = "check";
        category = "flake tools";
        help = "Check flake outputs";
        command = "nix build -L --show-trace --no-link --impure --expr '
            builtins.mapAttrs
              (n: v: if n != \"preCommitChecks\" then builtins.seq v v else builtins.trace \"skipping pre commit checks\" \"\")
              (builtins.getFlake (toString ./.)).checks.\${builtins.currentSystem}
          '";
      }
      {
        name = "fmt";
        category = "flake tools";
        help = "Format the Rust project and top-level Nix files.";
        command = "cargo fmt && nixpkgs-fmt *.nix";
      }
    ] ++ lib.optionals (! isNull cachixName) [
      {
        package = cachix;
        category = "tools";
      }
      {
        name = "build";
        category = "flake tools";
        help = "Build the specified derivation and push results to cachix.";
        command = "cachix watch-exec ${cachixName} nix -- build .#$1";
      }
    ] ++ lib.optional (builtins.hasAttr "preCommitChecks" common) {
      name = "check-pre-commit";
      category = "tools";
      help = "Runs the pre commit checks";
      command = "nix build -L --show-trace --no-link --impure --expr '(builtins.getFlake (toString ./.)).checks.\${builtins.currentSystem}.preCommitChecks'";
    };
    env = with lib; [
      { name = "LD_LIBRARY_PATH"; eval = "$LD_LIBRARY_PATH:${makeLibraryPath common.runtimeLibs}"; }
      { name = "LIBRARY_PATH"; eval = "$DEVSHELL_DIR/lib"; }
    ] ++ (
      optional ((! isNull cachixName) && (! isNull cachixKey))
        (nameValuePair "NIX_CONFIG" ''
          substituters = https://cache.nixos.org https://${cachixName}.cachix.org
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${cachixKey}
        '')
    ) ++ (mapAttrsToList (n: v: { name = n; eval = v; }) common.env);
    devshell.startup.setupPreCommitHooks.text = ''
      echo "pre-commit hooks are disabled."
    '';
  } // lib.optionalAttrs (builtins.hasAttr "preCommitChecks" common) {
    devshell.startup.setupPreCommitHooks.text = ''
      echo "Setting up pre-commit hooks..."
      ${common.preCommitChecks.shellHook}
      echo "Successfully set up pre-commit-hooks!"
    '';
  };

  combineWithBase = config: {
    devshell.startup = lib.recursiveUpdate baseConfig.devshell.startup (config.devshell.startup or { });
    language = lib.recursiveUpdate baseConfig.language (config.language or { });
    packages = baseConfig.packages ++ (config.packages or [ ]);
    commands = baseConfig.commands ++ (config.commands or [ ]);
    env = baseConfig.env ++ (config.env or [ ]);
  } // (removeAttrs config [ "packages" "commands" "env" "language" "startup" ]);

  resultConfig = {
    configuration =
      let
        c =
          if isNull importedDevshell
          then { config = combineWithBase devshellConfig; imports = [ ]; }
          else {
            config = combineWithBase importedDevshell.config;
            inherit (importedDevshell) _file imports;
          };
      in
      c // {
        config = c.config // (common.overrides.shell common c.config);
        imports = c.imports ++ [ "${pkgs.devshell.extraModulesDir}/language/c.nix" ];
      };
  };
in
(pkgs.devshell.eval resultConfig).shell
