# A set of crate overrides, in the spirit of nixpkgs's `defaultCrateOverrides`.
{
  pkgs,
  pkgsWithRust,
  lib,
}: let
  l = lib;

  mkOv = bi: ni: prev: {
    buildInputs = (prev.buildInputs or []) ++ bi;
    nativeBuildInputs = (prev.nativeBuildInputs or []) ++ ni;
  };

  ffmpeg-sys-next = prev: let
    inherit (pkgs) ffmpeg llvmPackages pkg-config;
    inherit (llvmPackages) libclang;
    env = {
      LIBCLANG_PATH = "${libclang.lib}/lib";
    };
  in
    (mkOv [ffmpeg.dev libclang.lib] [pkg-config] prev)
    // {
      propagatedEnv = env;
    }
    // env;

  overrides = {
    inherit ffmpeg-sys-next;
    ffmpeg-sys = ffmpeg-sys-next;
    libudev-sys = with pkgs; mkOv [udev] [pkg-config];
    alsa-sys = with pkgs; mkOv [alsa-lib] [pkg-config];
    xcb = with pkgs; mkOv [xorg.libxcb] [python3];
    xkbcommon-sys = with pkgs; mkOv [libxkbcommon] [pkg-config];
    expat-sys = with pkgs; mkOv [expat] [cmake];
    freetype-sys = with pkgs; mkOv [freetype] [cmake];
    servo-fontconfig-sys = with pkgs; mkOv [fontconfig] [pkg-config];
    cairo-sys-rs = with pkgs; mkOv [cairo] [pkg-config];
    pango-sys = with pkgs; mkOv [pango harfbuzz] [pkg-config];
    glib-sys = with pkgs; mkOv [glib] [pkg-config];
    gobject-sys = with pkgs; mkOv [glib] [pkg-config];
    gio-sys = with pkgs; mkOv [glib] [pkg-config];
    atk-sys = with pkgs; mkOv [atk] [pkg-config];
    gdk-pixbuf-sys = with pkgs; mkOv [gdk_pixbuf] [pkg-config];
    gdk-sys = with pkgs; mkOv [gtk3] [pkg-config];
    gtk-sys = with pkgs; mkOv [gtk3] [pkg-config];
    harmony_rust_sdk = prev: let
      inherit (pkgs) protobuf;
      env = {
        PROTOC = "${protobuf}/bin/protoc";
        PROTOC_INCLUDE = "${protobuf}/include";
      };
    in
      {
        buildInputs = [protobuf pkgsWithRust.rustfmt];
        propagatedEnv = env;
      }
      // env;
    shaderc-sys = _: let
      env = {SHADERC_LIB_DIR = "${pkgs.shaderc.lib}/lib";};
    in
      {propagatedEnv = env;} // env;
    prost-build = prev: let
      inherit (pkgs) protobuf;
      env = {
        PROTOC = "${protobuf}/bin/protoc";
        PROTOC_INCLUDE = "${protobuf}/include";
      };
    in
      {
        buildInputs = [protobuf pkgsWithRust.rustfmt];
        propagatedEnv = env;
      }
      // env;
    security-framework-sys = prev: {
      propagatedBuildInputs =
        l.optional
        pkgs.stdenv.isDarwin
        pkgs.darwin.apple_sdk.frameworks.Security;
    };
  };
in
  overrides
  // (
    l.filterAttrs
    (n: _: n != "security-framework-sys")
    pkgs.defaultCrateOverrides
  )
