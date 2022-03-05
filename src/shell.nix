common: let
  inherit (common) workspaceMetadata packageMetadata;
  inherit (common.internal.nci-pkgs) pkgs pkgsWithRust makeDevshell;

  l = common.internal.lib;

  # Extract cachix metadata
  cachixMetadata = workspaceMetadata.cachix or packageMetadata.cachix or null;
  cachixName = cachixMetadata.name or null;
  cachixKey = cachixMetadata.key or null;

  # Get all the options' name declared immediately under `config.devshell` by
  # devshell's modules.
  devshellOptions =
    l.filterAttrs
    (_: l.isType "option")
    (makeDevshell {configuration = {};}).options.devshell;

  # A helper function moving all options defined in the root of the config
  # (which name matches ones in `devshellOptions`) under a `devshell` attribute
  # set in the resulting config.
  #
  # devshellOptions = { foo = ...; bar = ...; };
  # pushUpDevshellOptions { foo = "foo"; baz = "baz"; }
  # -> { devhsell.foo = "foo"; baz = "baz"; }
  #
  # Issues a warning if it would override an exisiting option:
  #
  # pushUpDevshellOptions { foo = "foo"; devshell.foo = "oof"; }
  # -> { devhsell.foo = "foo"; }
  # trace: warning: Option 'foo' defined twice, both under 'config' and
  #   'config.devshell'. This likely happens when defining both in `Cargo.toml`:
  #   ```toml
  #   [workspace.metadata.nix.devshell]
  #   name = "example"
  #   [workspace.metadata.nix.devshell.devshell]
  #   name = "example"
  #   ```
  pushUpDevshellOptions = config: let
    movedOpts = l.flip l.filterAttrs config (
      name: _:
        l.warnIf
        (l.hasAttr name (config.devshell or {}))
        (l.concatStrings [
          "Option '${name}' defined twice, both under 'config' and "
          "'config.devshell'. This likely happens when defining both in "
          ''
            `Cargo.toml`:
            ```toml
            [workspace.metadata.nix.devshell]
            name = "example"
            [workspace.metadata.nix.devshell.devshell]
            name = "example"
            ```
          ''
        ])
        (l.hasAttr name devshellOptions)
    );
  in
    l.recursiveUpdate
    (l.removeAttrs config (l.attrNames movedOpts))
    {devshell = movedOpts;};

  # Create a base devshell config
  baseConfig =
    {
      language = {
        c = let
          inputs =
            common.buildInputs
            ++ common.overrideBuildInputs
            ++ (with pkgs; l.optionals stdenv.isDarwin [libiconv]);
        in {
          compiler = common.cCompiler;
          libraries = inputs;
          includes = inputs;
        };
      };
      packages =
        common.nativeBuildInputs
        ++ common.buildInputs
        ++ common.overrideNativeBuildInputs
        ++ common.overrideBuildInputs;
      commands = with pkgs;
        [
          {
            package = pkgsWithRust.rustc;
            name = "rustc";
            category = "rust";
            command = "rustc $@";
            help = "The Rust compiler";
          }
          {
            package = pkgsWithRust.cargo;
            name = "cargo";
            category = "rust";
            command = "cargo $@";
            help = "Rust's package manager";
          }
          {
            package = git;
            category = "vcs";
          }
          {
            package = alejandra;
            category = "tools";
          }
          {
            name = "show";
            category = "flake tools";
            help = "Show flake outputs";
            command = "nix flake show";
          }
          {
            name = "check";
            category = "flake tools";
            help = "Check flake outputs";
            command = "
          nix build -L --show-trace --no-link --impure --expr '
            builtins.removeAttrs
              (builtins.getFlake (toString ./.)).checks.${common.system}
              [ \"preCommitChecks\" ]
          '
        ";
          }
          {
            name = "fmt";
            category = "flake tools";
            help = "Format all Nix files";
            command = "alejandra $(pwd)";
          }
          {
            name = "update-input";
            category = "flake tools";
            help = "Alias for `nix flake lock --update-input`";
            command = "nix flake lock --update-input $@";
          }
        ]
        ++ l.optionals (cachixName != null) [
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
        ]
        ++ l.optional (l.hasAttr "preCommitChecks" common.internal) {
          name = "check-pre-commit";
          category = "tools";
          help = "Runs the pre commit checks";
          command = "nix build -L --show-trace --no-link --impure --expr '(builtins.getFlake (toString ./.)).checks.${common.system}.preCommitChecks'";
        };
      env =
        [
          {
            name = "LD_LIBRARY_PATH";
            eval = "$DEVSHELL_DIR/lib:${l.makeLibraryPath common.runtimeLibs}";
          }
          {
            name = "LIBRARY_PATH";
            eval = "$DEVSHELL_DIR/lib";
          }
        ]
        ++ (
          l.optional ((cachixName != null) && (cachixKey != null))
          (l.nameValuePair "NIX_CONFIG" ''
            substituters = https://cache.nixos.org https://${cachixName}.cachix.org
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${cachixKey}
          '')
        )
        ++ (
          l.mapAttrsToList
          (n: v: {
            name = n;
            eval = v;
          })
          (common.env // common.overrideEnv)
        );
      startup.setupPreCommitHooks.text = ''
        echo "pre-commit hooks are disabled."
      '';
    }
    // l.optionalAttrs (l.hasAttr "preCommitChecks" common.internal) {
      startup.setupPreCommitHooks.text = ''
        echo "Setting up pre-commit hooks..."
        ${common.internal.preCommitChecks.shellHook}
        echo "Successfully set up pre-commit-hooks!"
      '';
    };

  # Make devshell configs
  mkDevshellConfig = attrs:
    l.optionalAttrs
    (l.isAttrs attrs)
    (pushUpDevshellOptions (l.removeAttrs attrs ["imports"]));

  # Make configs work workspace and package
  workspaceConfig = mkDevshellConfig (workspaceMetadata.devshell or null);
  packageConfig = mkDevshellConfig (packageMetadata.devshell or null);

  # Import the devshell specified in devshell.toml if it exists
  devshellFilePath = common.prevRoot + "/devshell.toml";
  importedDevshell =
    l.thenOrNull
    (l.pathExists devshellFilePath)
    (import "${common.sources.devshell}/nix/importTOML.nix" devshellFilePath {lib = pkgs.lib;});

  # Helper functions to combine devshell configs without loss
  combineWith = base: config: let
    getOptions = attrs: name: def: attrs.${name} or attrs.devshell.${name} or def;
    getBaseOpts = getOptions base;
    getConfOpts = getOptions config;
    getOpts = name: def:
      if l.isList def
      then l.unique ((getBaseOpts name def) ++ (getConfOpts name def))
      else l.recursiveUpdate (getBaseOpts name def) (getConfOpts name def);

    clearDevshellOptions = attrs: l.removeAttrs attrs ["startup"];
    clearedDevshellOptions =
      l.recursiveUpdate
      (clearDevshellOptions base)
      (clearDevshellOptions config);
  in
    l.recursiveUpdate clearedDevshellOptions {
      devshell.startup = getOpts "startup" {};
      language = getOpts "language" {};
      packages = getOpts "packages" [];
      commands = getOpts "commands" [];
      env = getOpts "env" [];
    };
  combineWithBase = combineWith baseConfig;

  # Workspace and package combined config
  devshellConfig = combineWith workspaceConfig packageConfig;

  # Collect final config
  resultConfig = {
    configuration = let
      c =
        if importedDevshell == null
        then {
          config = combineWithBase devshellConfig;
          imports = [];
        }
        # Add values from the imported devshell if it exists
        else {
          config = combineWithBase importedDevshell.config;
          inherit (importedDevshell) _file imports;
        };
    in
      # Override the config with user provided override
      c
      // {
        config = c.config // (common.overrides.shell common c.config);
        imports = c.imports ++ ["${common.sources.devshell}/extra/language/c.nix"];
      };
  };
in
  (makeDevshell resultConfig).shell
