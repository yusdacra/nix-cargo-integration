{
  lib,
  path,
}: let
  l = lib // builtins;
  virtualManifestPath = "${path}/Cargo.toml";
  manifest = l.fromTOML (l.readFile virtualManifestPath);
  projectRoot = l.dirOf virtualManifestPath;
  # get all workspace members
  workspaceMembers =
    l.flatten
    (
      l.map
      (
        memberName: let
          components = l.splitString "/" memberName;
        in
          # Resolve globs if there are any
          if l.last components == "*"
          then let
            parentDirRel = l.concatStringsSep "/" (l.init components);
            dirs = l.readDir projectRoot;
          in
            l.mapAttrsToList
            (name: _: "${parentDirRel}/${name}")
            dirs
          else memberName
      )
      (manifest.workspace.members or [])
    );
  allPackageManifests =
    (l.optional (manifest ? package) manifest)
    ++ (
      l.map
      (relPath: l.fromTOML (l.readFile "${projectRoot}/${relPath}/Cargo.toml"))
      workspaceMembers
    );
in
  l.unique (l.map (manifest: manifest.package.name) allPackageManifests)
