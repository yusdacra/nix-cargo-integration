{ common, override ? (_: _: { }) }:
with common;
let
  cachixMetadata = nixMetadata.cachix or null;
  cachixName = cachixMetadata.name or null;
  cachixKey = cachixMetadata.key or null;

  devshellAttr = nixMetadata.devshell or null;
  devshellConfig = if pkgs.lib.isAttrs devshellAttr then (builtins.removeAttrs devshellAttr [ "imports" ]) else { };
  devshellFilePath = root + "/devshell.toml";
  importedDevshell = if (builtins.pathExists devshellFilePath) then (pkgs.devshell.importTOML devshellFilePath) else null;

  baseConfig = with pkgs; {
    packages = [ rustc ] ++ crateDeps.nativeBuildInputs ++ crateDeps.buildInputs;
    commands =
      let
        pkgCmd = pkg: { package = pkg; };
      in
      [
        (pkgCmd git)
        (pkgCmd nixpkgs-fmt)
      ] ++ (lib.optional (!(isNull cachixName)) (pkgCmd cachix));
    env = with lib; [
      (nameValuePair "LD_LIBRARY_PATH" "$LD_LIBRARY_PATH:${lib.makeLibraryPath runtimeLibs}")
    ] ++ (
      optional (!(isNull cachixName) && !(isNull cachixKey))
        (nameValuePair "NIX_CONFIG" ''
          substituters = https://cache.nixos.org https://${cachixName}.cachix.org
          trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= ${cachixKey}
        '')
    ) ++ (mapAttrsToList nameValuePair env);
  };

  combineWithBase = config: {
    packages = baseConfig.packages ++ (config.packages or [ ]);
    commands = baseConfig.commands ++ (config.commands or [ ]);
    env = baseConfig.env ++ (config.env or [ ]);
  } // (removeAttrs config [ "packages" "commands" "env" ]);

  resultConfig = {
    configuration =
      if isNull importedDevshell
      then { config = combineWithBase devshellConfig; }
      else {
        config = combineWithBase importedDevshell.config;
        inherit (importedDevshell) _file imports;
      };
  };
in
(pkgs.devshell.eval (resultConfig // (override common resultConfig))).shell
