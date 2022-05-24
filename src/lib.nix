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
            then lval // rval
            else if rval != null
            then rval
            else lval
        )
      );
    # Apply some overrides in a way nci expects them to be applied.
    applyOverrides = value: overrides: l.pipe value (l.map (ov: (prev: merge prev (ov prev))) overrides);
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
    eval = _expr: args: let
      parsed = l.match ''eval (.*)'' _expr;
      imp = expr: import (l.toFile "expr" expr);
    in
      if parsed != null
      then imp ''args: with args; ${l.elemAt parsed 0}'' args
      else imp _expr;
  }
