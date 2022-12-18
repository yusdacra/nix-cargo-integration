# Utility for generating a script to patch binaries with libraries.
{
  # args
  libs,
  # nixpkgs
  lib,
  patchelf,
}: ''
  for f in $out/bin/*; do
    ${patchelf}/bin/patchelf --set-rpath "${lib.makeLibraryPath libs}" "$f"
  done
''
