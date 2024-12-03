{
  lib,
  fetchFromGitHub,
  runCommand,
  docsPackages,
  derivationName,
  indexCrateName,
  buildCrate,
}: let
  docmerge = buildCrate {
    src = fetchFromGitHub {
      owner = "yusdacra";
      repo = "doc-merge";
      rev = "3c8d7b21e23b36ec4854d599d423e83614447f98";
      hash = "sha256-8uVjGWuw485z2cu3UEDlp6UccbB7jCcRvA0J1cJnQ10=";
    };
  };
  getCrateName = docs: lib.replaceStrings ["-"] ["_"] (lib.removeSuffix "-docs" docs.name);
  mkCopyCrate = docs: "cp -Lrv --no-preserve=mode,ownership ${docs} crates/${getCrateName docs}";
  mkMergeSrcArg = docs: "--src crates/${getCrateName docs}";
  derivationAttrs = {
    passthru.docsPackages = docsPackages;
  };
in
  runCommand derivationName derivationAttrs ''
    mkdir -p $out
    mkdir crates
    ${lib.concatMapStringsSep "\n" mkCopyCrate docsPackages}
    ${docmerge}/bin/doc-merge \
      ${
      if indexCrateName != null
      then "--index-crate ${indexCrateName}"
      else ""
    } \
      ${lib.concatMapStringsSep " " mkMergeSrcArg docsPackages} \
      --dest $out
  ''
