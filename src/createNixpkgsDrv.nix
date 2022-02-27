# Creates a nixpkgs-compatible nix expression that uses `buildRustPackage`.
common:
common.pkgs.writeTextFile {
  name = "${common.cargoPkg.name}.nix";
  text = let
    inherit (common) root cargoPkg pkgs buildInputs nativeBuildInputs desktopFileMetadata;
    inherit
      (common.internal.lib)
      any
      map
      hasAttr
      baseNameOf
      concatStringsSep
      filter
      length
      attrNames
      attrValues
      split
      isList
      isString
      stringLength
      elemAt
      optional
      optionalString
      cargoLicenseToNixpkgs
      concatMapStringsSep
      mapAttrsToList
      getName
      init
      filterAttrs
      unique
      splitString
      drop
      hasPrefix
      removePrefix
      strings
      ;
    inherit (strings) sanitizeDerivationName;
    has = i: any (oi: i == oi);

    clang = ["clang-wrapper" "clang"];
    gcc = ["gcc-wrapper" "gcc"];

    filterUnwanted = filter (n: !(has n (clang ++ gcc ++ ["pkg-config-wrapper" "binutils-wrapper"])));
    mapToName = map getName;
    concatForInput = i: concatStringsSep "" (map (p: "\n  ${p},") i);

    bi = filterUnwanted ((mapToName buildInputs) ++ (mapToName common.runtimeLibs));
    nbi =
      (filterUnwanted (mapToName nativeBuildInputs))
      ++ (optional common.internal.mkRuntimeLibsOv "makeWrapper")
      ++ (optional common.internal.mkDesktopFile "copyDesktopItems");
    runtimeLibs = "\${lib.makeLibraryPath ([ ${concatStringsSep " " (mapToName common.runtimeLibs)} ])}";
    stdenv =
      if any (n: has n clang) (mapToName nativeBuildInputs)
      then "clangStdenv"
      else null;
    putIfStdenv = optionalString (stdenv != null);

    runtimeLibsScript =
      concatStringsSep "\n" (
        map
        (line: "    ${line}")
        (init (
          filter
          (list:
            if isList list
            then (length list) > 0
            else true)
          (split "\n" (common.internal.mkRuntimeLibsScript runtimeLibs))
        ))
      );

    desktopItemAttrs = let
      desktopItem = common.internal.mkDesktopItemConfig cargoPkg.name;
      filtered =
        filterAttrs
        (_: v: !(hasPrefix "/nix/store" v) && (toString v) != "")
        desktopItem;
      attrsWithIcon =
        if !(hasAttr "icon" filtered) && (hasAttr "icon" common.desktopFileMetadata)
        then filtered // {icon = "\${src}/${removePrefix "./" common.desktopFileMetadata.icon}";}
        else filtered;
      attrs = mapAttrsToList (n: v: "    ${n} = \"${v}\";") attrsWithIcon;
    in
      concatStringsSep "\n" attrs;
    desktopItems = "\n  desktopItems = [ (makeDesktopItem {\n${desktopItemAttrs}\n  }) ];";
    desktopLink = "\n  desktopItems = [ (pkgs.runCommand \"${cargoPkg.name}-desktopFileLink\" { } ''\n    mkdir -p $out/share/applications\n    ln -sf \${src}/${desktopFileMetadata} $out/share/applications\n  '') ];";

    isGitHub = builtins.pathExists (root + "/.github");
    isGitLab = builtins.pathExists (root + "/.gitlab");

    mkForgeFetch = name: rec {
      fetcher = "fetchFrom${name}";
      fetchCode = let
        version = "v\${version}";
      in ''
        src = ${fetcher} {
          owner = "<enter owner>";
          repo = "${cargoPkg.name}";
          rev = "${version}";
          sha256 = lib.fakeHash;
        };'';
    };

    githubFetcher = mkForgeFetch "GitHub";
    gitlabFetcher = mkForgeFetch "GitLab";

    fetcher =
      if isGitLab
      then gitlabFetcher
      else if isGitHub
      then githubFetcher
      else githubFetcher;

    envToString = value: let
      val = toString value;
    in
      if hasPrefix "/nix/store" value
      then let
        pathSegments = filter (v: (stringLength v) > 0) (splitString "/" val);

        hashName = elemAt pathSegments 2;
        nameSegments = drop 1 (splitString "-" hashName);
        name = concatStringsSep "-" nameSegments;
        drvName = getName (sanitizeDerivationName name);

        relPathSegments = drop 3 pathSegments;
        relPath = concatStringsSep "/" relPathSegments;
      in
        "\${${drvName}}/" + relPath
      else val;
  in ''
    { lib,
      rustPlatform,${putIfStdenv "\n  ${stdenv},"}
      ${fetcher.fetcher},${concatForInput (unique (bi ++ nbi))}
    }:
    rustPlatform.buildRustPackage rec {
      pname = "${cargoPkg.name}";
      version = "${cargoPkg.version}";${putIfStdenv "\n\n  stdenv = ${stdenv};"}

      # Change to use whatever source you want
      ${concatMapStringsSep "\n" (line: "  ${line}") (splitString "\n" fetcher.fetchCode)}

      cargoSha256 = lib.fakeHash;${
      optionalString
      ((length (attrNames common.env)) > 0)
      "\n\n${concatStringsSep "\n" (mapAttrsToList (n: v: "  ${n} = \"${envToString v}\";") common.env)}"
    }

      buildInputs = [ ${concatStringsSep " " bi} ];
      nativeBuildInputs = [ ${concatStringsSep " " nbi} ];${
      optionalString
      common.internal.mkRuntimeLibsOv
      "\n\n  postFixup = ''\n${runtimeLibsScript}\n  '';"
    }${
      optionalString
      common.internal.mkDesktopFile
      (
        if isString desktopFileMetadata
        then desktopLink
        else desktopItems
      )
    }

      cargoBuildFlags = [ "--package" "${cargoPkg.name}" ];
      cargoTestFlags = cargoBuildFlags;

      meta = with lib; {
        description = "${common.meta.description or "<enter description>"}";
        homepage = "${common.meta.homepage or "<enter homepage>"}";
        license = licenses.${cargoLicenseToNixpkgs (cargoPkg.license or "unfree")};
        maintainers = with maintainers; [ ];
      };
    }
  '';
}
