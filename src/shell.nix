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
    cCompiler
    ;
  inherit (common.internal.pkgsSet) pkgs;

  l = common.internal.lib;

  # Extract cachix metadata
  cachixMetadata = workspaceMetadata.cachix or packageMetadata.cachix;
  cachixName = cachixMetadata.name;
  cachixKey = cachixMetadata.key;

  # Create a base devshell config
  baseConfig =
    {
      packages =
        runtimeLibs
        ++ (
          l.optional
          cCompiler.useCompilerBintools
          cCompiler.package.bintools
        );
      language.c = {compiler = cCompiler.package;};
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
        [
          {
            name = "LD_LIBRARY_PATH";
            eval = "$DEVSHELL_DIR/lib";
          }
          {
            # On darwin for example enables finding of libiconv
            name = "LIBRARY_PATH";
            # append in case it needs to be modified
            eval = "$DEVSHELL_DIR/lib";
          }
          {
            # some *-sys crates require additional includes
            name = "CFLAGS";
            # append in case it needs to be modified
            eval = "\"-I $DEVSHELL_DIR/include ${l.optionalString pkgs.stdenv.isDarwin "-iframework $DEVSHELL_DIR/Library/Frameworks"}\"";
          }
        ]
        ++ l.optionals pkgs.stdenv.isDarwin [
          {
            # On darwin for example required for some *-sys crate compilation
            name = "RUSTFLAGS";
            # append in case it needs to be modified
            eval = "\"-L framework=$DEVSHELL_DIR/Library/Frameworks\"";
          }
          {
            # rustdoc uses a different set of flags
            name = "RUSTDOCFLAGS";
            # append in case it needs to be modified
            eval = "\"-L framework=$DEVSHELL_DIR/Library/Frameworks\"";
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
    (l.removeAttrs attrs ["imports"]);

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
      language = getOpts "language" {};
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
    };
in
  rawShell.combineWith {passthru.config = finalConfig;}
