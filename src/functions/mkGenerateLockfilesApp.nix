{
  pkgs,
  lib,
  projects,
  buildToolchain,
  source,
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
          relPath = l.removePrefix (toString source) (toString project.path);
          trimSlashes = str: l.removePrefix "/" (l.removeSuffix "/" str);
          cargoTomlPath = trimSlashes "${relPath}/Cargo.toml";
          cargoLockPath = trimSlashes "${relPath}/Cargo.lock";
        in ''
          ${buildToolchain}/bin/cargo generate-lockfile --manifest-path ${cargoTomlPath}
          addToGit ${cargoLockPath}
        ''
      )
      (l.attrValues projects)
    }
  ''
