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
  // {
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
    # Apply some overrides in a way nci expects them to be applied.
    applyOverrides = value: overrides: l.pipe value (l.map (ov: (prev: prev // (ov prev))) overrides);
    # Removes `propagatedEnv` attributes from some `crateOverride`s.
    removePropagatedEnv = l.mapAttrs (_: v: (prev: l.removeAttrs (v prev) ["propagatedEnv"]));
  }
