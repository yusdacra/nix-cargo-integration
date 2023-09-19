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
            dirs = l.readDir "${projectRoot}/${parentDirRel}";
          in
            l.mapAttrsToList
            (name: _: "${parentDirRel}/${name}")
            (l.filterAttrs (_: t: t == "directory") dirs)
          else memberName
      )
      (manifest.workspace.members or [])
    );
  allPackages =
    (
      l.optional
      (manifest ? package)
      {
        inherit (manifest.package) name version;
        path = "";
      }
    )
    ++ (
      l.map
      (relPath: let
        manifestPath = "${projectRoot}/${relPath}/Cargo.toml";
        manifest = l.fromTOML (l.readFile manifestPath);
      in {
        inherit (manifest.package) name version;
        path = relPath;
      })
      workspaceMembers
    );
in
  l.unique allPackages
