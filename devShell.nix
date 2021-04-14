common:
let
  inherit (common) pkgs workspaceMetadata;

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
        compiler = pkgs.gcc;
        libraries = common.buildInputs;
        includes = common.buildInputs;
      };
    };
    packages = [ pkgs.rustc ] ++ common.nativeBuildInputs ++ common.buildInputs;
    commands =
      let
        pkgCmd = pkg: { package = pkg; };
      in
      with pkgs; [
        (pkgCmd git)
        (pkgCmd nixpkgs-fmt)
      ] ++ (lib.optional (!(isNull cachixName)) (pkgCmd cachix));
    env = with pkgs.lib; [
      { name = "LD_LIBRARY_PATH"; eval = "$LD_LIBRARY_PATH:${makeLibraryPath common.runtimeLibs}"; }
      { name = "LIBRARY_PATH"; eval = "$DEVSHELL_DIR/lib"; }
    ] ++ (
      optional (!(isNull cachixName) && !(isNull cachixKey))
        (nameValuePair "NIX_CONFIG" ''
          substituters = https://cache.nixos.org https://${cachixName}.cachix.org
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${cachixKey}
        '')
    ) ++ (mapAttrsToList (n: v: { name = n; eval = v; }) common.env);
  };

  combineWithBase = config: {
    language = pkgs.lib.recursiveUpdate baseConfig.language (config.language or { });
    packages = baseConfig.packages ++ (config.packages or [ ]);
    commands = baseConfig.commands ++ (config.commands or [ ]);
    env = baseConfig.env ++ (config.env or [ ]);
  } // (removeAttrs config [ "packages" "commands" "env" "language" ]);

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
