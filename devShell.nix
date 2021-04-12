{ common, override ? (_: _: { }) }:
let
  inherit (common) pkgs nixMetadata;

  cachixMetadata = nixMetadata.cachix or null;
  cachixName = cachixMetadata.name or null;
  cachixKey = cachixMetadata.key or null;

  devshellAttr = nixMetadata.devshell or null;
  devshellConfig = if pkgs.lib.isAttrs devshellAttr then (builtins.removeAttrs devshellAttr [ "imports" ]) else { };
  devshellFilePath = common.root + "/devshell.toml";
  importedDevshell = if (builtins.pathExists devshellFilePath) then (pkgs.devshell.importTOML devshellFilePath) else null;

  baseConfig = {
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
      { name = "LD_LIBRARY_PATH"; eval = "$LD_LIBRARY_PATH:${lib.makeLibraryPath runtimeLibs}"; }
      { name = "LIBRARY_PATH"; eval = "$LIBRARY_PATH:${lib.makeLibraryPath buildInputs}"; }
      { name = "LD_INCLUDE_PATH"; eval = "$LD_INCLUDE_PATH:${lib.makeIncludePath runtimeLibs}"; }
    ] ++ (
      optional (!(isNull cachixName) && !(isNull cachixKey))
        (nameValuePair "NIX_CONFIG" ''
          substituters = https://cache.nixos.org https://${cachixName}.cachix.org
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${cachixKey}
        '')
    ) ++ (mapAttrsToList (n: v: { name = n; eval = v; }) env);
  };

  combineWithBase = config: {
    packages = baseConfig.packages ++ (config.packages or [ ]);
    commands = baseConfig.commands ++ (config.commands or [ ]);
    env = baseConfig.env ++ (config.env or [ ]);
  } // (removeAttrs config [ "packages" "commands" "env" ]);

  resultConfig = {
    configuration =
      let
        c =
          if isNull importedDevshell
          then { config = combineWithBase devshellConfig; }
          else {
            config = combineWithBase importedDevshell.config;
            inherit (importedDevshell) _file imports;
          };
      in
      c // {
        config = c.config // (override common c.config);
      };
  };
in
(pkgs.devshell.eval resultConfig).shell
