{
  pkgs,
  lib,
  projects,
  buildToolchain,
}: let
  l = lib // builtins;
in
  pkgs.writeScript "generate-lockfiles" ''
    function addToGit {
      if [ -d ".git" ]; then
        git add $1
      fi
    }
    ${
      l.concatMapStringsSep
      "\n"
      (
        project: let
          trimSlashes = str: l.removePrefix "/" (l.removeSuffix "/" str);
          cargoTomlPath = trimSlashes "${project.relPath}/Cargo.toml";
          cargoLockPath = trimSlashes "${project.relPath}/Cargo.lock";
        in ''
          ${buildToolchain}/bin/cargo generate-lockfile --manifest-path ${cargoTomlPath}
          addToGit ${cargoLockPath}
        ''
      )
      (l.attrValues projects)
    }
  ''
