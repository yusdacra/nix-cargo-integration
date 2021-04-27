pkgs:
let
  mkOv = bi: ni: prev: {
    buildInputs = (prev.buildInputs or [ ]) ++ bi;
    nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ ni;
  };
in
with pkgs;
{
  libudev-sys = mkOv [ libudev ] [ pkg-config ];
  alsa-sys = mkOv [ alsaLib ] [ pkg-config ];
  xcb = mkOv [ xorg.libxcb ] [ python3 ];
  xkbcommon-sys = mkOv [ libxkbcommon ] [ pkg-config ];
  expat-sys = mkOv [ expat ] [ cmake ];
  freetype-sys = mkOv [ freetype ] [ cmake ];
  servo-fontconfig-sys = mkOv [ fontconfig ] [ pkg-config ];
  cairo-sys-rs = mkOv [ cairo ] [ pkg-config ];
  pango-sys = mkOv [ pango harfbuzz ] [ pkg-config ];
  glib-sys = mkOv [ glib ] [ pkg-config ];
  gobject-sys = mkOv [ glib ] [ pkg-config ];
  gio-sys = mkOv [ glib ] [ pkg-config ];
  atk-sys = mkOv [ atk ] [ pkg-config ];
  gdk-pixbuf-sys = mkOv [ gdk_pixbuf ] [ pkg-config ];
  gdk-sys = mkOv [ gtk3 ] [ pkg-config ];
  gtk-sys = mkOv [ gtk3 ] [ pkg-config ];
  harmony_rust_sdk = prev:
    let
      env = {
        PROTOC = "${protobuf}/bin/protoc";
        PROTOC_INCLUDE = "${protobuf}/include";
      };
    in
    {
      buildInputs = (prev.buildInputs or [ ]) ++ [ protobuf rustfmt ];
      propagatedEnv = env;
    } // env;
}
