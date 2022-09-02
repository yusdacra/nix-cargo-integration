{
  # an imported nixpkgs library
  lib,
}: let
  l = lib // builtins;
  mkDbg = msgPrefix: rec {
    doDbg = (l.getEnv "NCI_DEBUG") == "1";
    dbg = msg: x:
      if doDbg
      then l.trace "${msgPrefix}${msg}" x
      else x;
    dbgX = msg: x: dbgXY msg x x;
    dbgXY = msg: x: y:
      if doDbg
      then
        l.debug.traceSeqN 5
        {
          message = "${msgPrefix}${msg}";
          value = x;
        }
        y
      else y;
  };
in
  l
  // (mkDbg "")
  // rec {
    inherit mkDbg;
    # equal to `nixpkgs` `supportedSystems` and `limitedSupportSystems` https://github.com/NixOS/nixpkgs/blob/master/pkgs/top-level/release.nix#L14
    defaultSystems = [
      "aarch64-linux"
      "x86_64-darwin"
      "x86_64-linux"
      "i686-linux"
      "aarch64-darwin"
    ];
    # Tries to convert a cargo license to nixpkgs license.
    cargoLicenseToNixpkgs = _license: let
      license = l.toLower _license;
      licensesIds =
        l.mapAttrs'
        (
          name: v:
            l.nameValuePair
            (l.toLower (v.spdxId or v.fullName or name))
            name
        )
        l.licenses;
    in
      licensesIds.${license} or "unfree";
    # Get an attrset containing the specified attr from the set if it exists.
    putIfHasAttr = name: attrs: l.optionalAttrs (l.hasAttr name attrs) {${name} = attrs.${name};};
    # Merges two attrsets while concatting lists
    merge = lattrs: rattrs:
      rattrs
      // (
        l.genAttrs
        (l.attrNames lattrs)
        (
          name: let
            lval = lattrs.${name};
            rval = rattrs.${name} or null;
            isType = cond: (cond lval) && (cond rval);
          in
            if isType l.isList
            then l.unique (lval ++ rval)
            else if isType l.isAttrs
            then merge lval rval
            else if rval != null
            then rval
            else lval
        )
      );
    # Computes the result of some overrides for a specific value.
    computeOverridesResult = value: overrides: let
      combined =
        l.foldl'
        (
          acc: el: (
            prev: let
              accApplied = acc prev;
              elApplied = el (merge prev accApplied);
            in
              merge accApplied elApplied
          )
        )
        (_: {})
        overrides;
    in
      combined value;
    applyOverrides = value: overrides:
      merge value (computeOverridesResult value overrides);
    # Concats two lists and removes duplicate values.
    concatLists = list: olist: l.unique (list ++ olist);
    # Concats lists from two attribute sets.
    concatAttrLists = attrs: oattrs: name: concatLists (attrs.${name} or []) (oattrs.${name} or []);
    # Removes `propagatedEnv` attributes from some `crateOverride`s.
    removePropagatedEnv = l.mapAttrs (_: v: (prev: l.removeAttrs (v prev) ["propagatedEnv"]));
    # If the condition is true, evaluates to ifTrue,
    # otherwise evalutes to ifFalse.
    thenOr = cond: ifTrue: ifFalse:
      if cond
      then ifTrue
      else ifFalse;
    # If the condition is true, evaluates to the
    # passed value, otherwise evalutes to null.
    thenOrNull = cond: ifTrue: thenOr cond ifTrue null;
    # evaluate a nix expression with some args
    eval = _expr: args: let
      parsed = l.match ''eval (.*)'' _expr;
      imp = expr: import (l.toFile "expr" expr);
    in
      if parsed != null
      then imp ''args: with args; ${l.elemAt parsed 0}'' args
      else _expr;
    parseDepEntry = entry: let
      split = l.splitString " " entry;
      hasVersion = l.length split > 1;
      hasSource = l.length split > 2;
    in {
      name = l.head split;
      version =
        if hasSource
        then l.elemAt split 1
        else if hasVersion
        then l.last split
        else null;
      source =
        if hasSource
        then l.removePrefix "(" (l.removeSuffix ")" (l.last split))
        else null;
    };
    makeDepsAttrset = lockPackages: let
      makeAttrset = dep: {
        ${dep.name}.${dep.version}.${dep.source or ""} = dep;
      };
    in
      l.foldl' l.recursiveUpdate {} (l.map makeAttrset lockPackages);
    # gets a crate's transitive dependencies
    getTransitiveDependencies = lock: entry:
      _getTransitiveDependencies (getDependencies lock) entry;
    _getTransitiveDependencies = getDeps: entry: let
      deps = getDeps entry;
      _get = _getTransitiveDependencies getDeps;
    in
      (l.flatten (l.map _get deps)) ++ deps;
    # gets a crate's direct dependencies
    getDependencies = lock: entry: let
      p = parseDepEntry entry;
      pkg =
        if p.version == null
        then l.head (l.mapAttrsToList (n: v: l.attrValues v) lock.${p.name})
        else if p.source == null
        then l.head (l.attrValues lock.${p.name}.${p.version})
        else lock.${p.name}.${p.version}.${p.source};
    in
      pkg.dependencies or [];
  }
