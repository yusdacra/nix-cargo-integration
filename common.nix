{ cargoPkg, sources, system, root }:
let
  nixMetadata = cargoPkg.metadata.nix;
  rustOverlay = import sources.rustOverlay;
  devshellOverlay = import (sources.devshell + "/overlay.nix");

  pkgz = import sources.nixpkgs { inherit system; overlays = [ rustOverlay ]; };
  baseRustToolchain =
    if (isNull (nixMetadata.toolchain or null))
    then (pkgz.rust-bin.fromRustupToolchainFile (root + "/rust-toolchain"))
    else pkgz.rust-bin."${nixMetadata.toolchain}".latest.rust;
  rust = baseRustToolchain.override {
    extensions = [ "rust-src" ];
  };

  pkgs = import sources.nixpkgs {
    inherit system;
    overlays = [
      rustOverlay
      devshellOverlay
      (final: prev: {
        rustc = rust;
      })
      (final: prev: {
        naersk = prev.callPackage sources.naersk { };
      })
    ];
  };

  mapToPkgs = list: map (pkg: pkgs."${pkg}") list;
in
{
  inherit pkgs cargoPkg nixMetadata root;

  /* You might need this if your application utilizes a GUI. Note that the dependencies
    might change from application to application. The example dependencies provided here
    are for a typical iced application that uses Vulkan underneath.

    For example, it might look like this:

    runtimeLibs = with pkgs; (with xorg; [ libX11 libXcursor libXrandr libXi ])
    ++ [ vulkan-loader wayland wayland-protocols libxkbcommon ];
  */
  runtimeLibs = with pkgs; ([ ] ++ (mapToPkgs (nixMetadata.runtimeLibs or [ ])));

  # Dependencies listed here will be passed to Nix build and development shell
  crateDeps =
    with pkgs;
    {
      buildInputs = [ /* Add runtime dependencies here */ ] ++ (mapToPkgs (nixMetadata.buildInputs or [ ]));
      nativeBuildInputs = [ /* Add compile time dependencies here */ ] ++ (mapToPkgs (nixMetadata.nativeBuildInputs or [ ]));
    };

  /* Put env variables here, like so:

    env = {
    PROTOC = "${pkgs.protobuf}/bin/protoc";
    };

    The variables are not (shell) escaped.
    Variables put here will appear in both dev env and build env.
  */
  env = { } // (nixMetadata.env or { });
}
