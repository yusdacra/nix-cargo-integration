{
  common,
  rawShell,
}: let
  inherit
    (common.internal)
    workspaceMetadata
    packageMetadata
    root
    runtimeLibs
    sources
    ;
  inherit (common.internal.pkgsSet) pkgs makeDevshell;

  l = common.internal.lib;

  # Extract cachix metadata
  cachixMetadata = workspaceMetadata.cachix or packageMetadata.cachix;
  cachixName = cachixMetadata.name;
  cachixKey = cachixMetadata.key;

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

  rawInputs =
    (rawShell.buildInputs or [])
    ++ (rawShell.nativeBuildInputs or []);
  rawEnv = rawShell.passthru.env;
  # Create a base devshell config
  baseConfig =
    l.dbgX
    "devshell baseConfig"
    {
      language.c = {
        compiler = common.cCompiler.package;
        libraries = rawInputs;
        includes = rawInputs;
      };
      packages = rawInputs ++ runtimeLibs;
      commands = with pkgs; let
        buildFlakeExpr = nixArgs: expr: ''
          function get { nix flake metadata --json | ${jq}/bin/jq -c -r $1; }
          url="$(get '.locked.url')"
          narhash="$(get '.locked.narHash')"
          nix build -L --show-trace ${nixArgs} --expr "
            let
              b = builtins;
              flake = b.getFlake \"$url?narHash=$narhash\";
            in ${expr}
          "
        '';
      in
        [
          {
            package = alejandra;
            category = "formatting";
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
            command =
              buildFlakeExpr
              "--no-link"
              ''b.removeAttrs flake.checks.\"${pkgs.system}\" [ \"preCommitChecks\" ]'';
          }
          {
            name = "fmt";
            category = "formatting";
            help = ''
              Format all files
              (if treefmt is setup, otherwise fallbacks to just formatting Nix files)
            '';
            command = "treefmt || alejandra $(pwd)";
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
            help = "Build the specified package and push results to cachix.";
            command = "cachix watch-exec ${cachixName} nix -- build .#$1";
          }
          {
            name = "build-all";
            category = "flake tools";
            help = "Build all packages and push results to cachix";
            command = ''
              function build {
                ${buildFlakeExpr "" ''flake.packages.\"${pkgs.system}\"''}
              }
              cachix watch-exec build
            '';
          }
        ]
        ++ l.optionals (cachixName == null) [
          {
            name = "build";
            category = "flake tools";
            help = "Build the specified package";
            command = "nix build .#$1";
          }
          {
            name = "build-all";
            category = "flake tools";
            help = "Build all packages";
            command = buildFlakeExpr "" ''flake.packages.\"${pkgs.system}\"'';
          }
        ]
        ++ l.optional (l.hasAttr "preCommitChecks" common.internal) {
          name = "check-pre-commit";
          category = "tools";
          help = "Runs the pre commit checks";
          command = buildFlakeExpr "" ''flake.checks.\"${system}\".preCommitChecks'';
        };
      env =
        (
          l.mapAttrsToList
          l.nameValuePair
          (
            l.filterAttrs
            (name: value: l.isString value)
            rawEnv
          )
        )
        ++ [
          {
            name = "LD_LIBRARY_PATH";
            eval = "$DEVSHELL_DIR/lib${l.optionalString (rawEnv ? LD_LIBRARY_PATH) ":${rawEnv.LD_LIBRARY_PATH}"}";
          }
          {
            # On darwin for example enables finding of libiconv
            name = "LIBRARY_PATH";
            # append in case it needs to be modified
            eval = "$DEVSHELL_DIR/lib${l.optionalString (rawEnv ? LIBRARY_PATH) ":${rawEnv.LIBRARY_PATH}"}";
          }
          {
            # some *-sys crates require additional includes
            name = "CFLAGS";
            # append in case it needs to be modified
            eval = "\"-I $DEVSHELL_DIR/include${l.optionalString pkgs.stdenv.isDarwin " -iframework $DEVSHELL_DIR/Library/Frameworks"}${l.optionalString (rawEnv ? CFLAGS) " ${rawEnv.CFLAGS}"}\"";
          }
        ]
        ++ l.optionals pkgs.stdenv.isDarwin [
          {
            # On darwin for example required for some *-sys crate compilation
            name = "RUSTFLAGS";
            # append in case it needs to be modified
            eval = "\"-L framework=$DEVSHELL_DIR/Library/Frameworks${l.optionalString (rawEnv ? RUSTFLAGS) " ${rawEnv.RUSTFLAGS}"}\"";
          }
          {
            # rustdoc uses a different set of flags
            name = "RUSTDOCFLAGS";
            # append in case it needs to be modified
            eval = "\"-L framework=$DEVSHELL_DIR/Library/Frameworks${l.optionalString (rawEnv ? RUSTDOCFLAGS) " ${rawEnv.RUSTDOCFLAGS}"}\"";
          }
        ]
        ++ l.optional ((cachixName != null) && (cachixKey != null)) (
          l.nameValuePair "NIX_CONFIG" ''
            substituters = https://cache.nixos.org https://${cachixName}.cachix.org
            trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${cachixKey}
          ''
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
  workspaceConfig = mkDevshellConfig (workspaceMetadata.shell or null);
  packageConfig = mkDevshellConfig (packageMetadata.shell or null);

  # Import the devshell specified in devshell.toml if it exists
  devshellFilePath = "${toString root}/devshell.toml";
  importedDevshell =
    l.thenOrNull
    (l.pathExists devshellFilePath)
    (import "${sources.devshell}/nix/importTOML.nix" devshellFilePath {lib = pkgs.lib;});

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
      language =
        (getOpts "language" {})
        // {
          c = {
            compiler = base.language.c.compiler or config.language.c.compiler or null;
            libraries = l.unique ((base.language.c.libraries or []) ++ (config.language.c.libraries or []));
            includes = l.unique ((base.language.c.includes or []) ++ (config.language.c.includes or []));
          };
        };
      packages = getOpts "packages" [];
      commands = getOpts "commands" [];
      env = getOpts "env" [];
    };
  combineWithBase = combineWith baseConfig;

  # Workspace and package combined config
  devshellConfig = combineWith workspaceConfig packageConfig;

  shellOverride =
    if l.isFunction (workspaceMetadata.shell or null)
    then workspaceMetadata.shell or (_: {})
    else (_: {});

  # Collect final config
  finalConfig = let
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
      config = c.config // (shellOverride c.config);
      imports = c.imports ++ ["${sources.devshell}/extra/language/c.nix"];
    };

  makeShell = configuration:
    (makeDevshell {inherit configuration;}).shell
    // {
      passthru = {inherit configuration;};
      combineWith = otherShell:
        makeShell {
          config = combineWith configuration.config otherShell.passthru.configuration.config;
          imports = configuration.imports ++ otherShell.passthru.configuration.imports;
        };
    };
in
  l.dbgX "final devshell" (makeShell finalConfig)
