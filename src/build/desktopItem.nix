# Generate a desktop item config using provided package name
# and information from the package's `Cargo.toml`.
{
  # args
  root,
  cargoPkg,
  packageMetadata,
  desktopFileMetadata,
  pkgName,
  lib,
  ...
}: let
  l = lib // builtins;
in
  {
    name = pkgName;
    exec = packageMetadata.executable or pkgName;
    comment = desktopFileMetadata.comment or cargoPkg.description or "";
    desktopName = desktopFileMetadata.name or pkgName;
  }
  // (
    if l.hasAttr "icon" desktopFileMetadata
    then let
      # If icon path starts with relative path prefix, make it absolute using root as base
      # Otherwise treat it as an absolute path
      makeIcon = icon:
        if l.hasPrefix "./" icon
        then "${toString root}/${l.removePrefix "./" icon}"
        else icon;
    in {icon = makeIcon desktopFileMetadata.icon;}
    else {}
  )
  // (l.putIfHasAttr "genericName" desktopFileMetadata)
  // (l.putIfHasAttr "categories" desktopFileMetadata)
