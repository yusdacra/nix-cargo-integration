# Utility for generating a script to patch binaries with libraries.
{
  # args
  libs,
  # nixpkgs
  lib,
  makeWrapper,
}: ''
  source ${makeWrapper}/nix-support/setup-hook
  for f in $out/bin/*; do
    wrapProgram "$f" --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath libs}"
  done
''
