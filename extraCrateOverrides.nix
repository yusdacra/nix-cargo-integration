# A set of crate overrides, in the spirit of nixpkgs's `defaultCrateOverrides`.
pkgs:
let
  mkOv = bi: ni: prev: {
    buildInputs = (prev.buildInputs or [ ]) ++ bi;
    nativeBuildInputs = (prev.nativeBuildInputs or [ ]) ++ ni;
  };
  ffmpeg-sys-next = prev:
    let
      inherit (pkgs) ffmpeg llvmPackages pkg-config;
      inherit (llvmPackages) libclang;
      env = {
        LIBCLANG_PATH = "${libclang.lib}/lib";
      };
    in
    (mkOv [ ffmpeg.dev libclang.lib ] [ pkg-config ] prev) // {
      propagatedEnv = env;
    } // env;
in
{
  inherit ffmpeg-sys-next;
  ffmpeg-sys = ffmpeg-sys-next;
  libudev-sys = with pkgs; mkOv [ libudev ] [ pkg-config ];
  alsa-sys = with pkgs; mkOv [ alsaLib ] [ pkg-config ];
  xcb = with pkgs; mkOv [ xorg.libxcb ] [ python3 ];
  xkbcommon-sys = with pkgs; mkOv [ libxkbcommon ] [ pkg-config ];
  expat-sys = with pkgs; mkOv [ expat ] [ cmake ];
  freetype-sys = with pkgs; mkOv [ freetype ] [ cmake ];
  servo-fontconfig-sys = with pkgs; mkOv [ fontconfig ] [ pkg-config ];
  cairo-sys-rs = with pkgs; mkOv [ cairo ] [ pkg-config ];
  pango-sys = with pkgs; mkOv [ pango harfbuzz ] [ pkg-config ];
  glib-sys = with pkgs; mkOv [ glib ] [ pkg-config ];
  gobject-sys = with pkgs; mkOv [ glib ] [ pkg-config ];
  gio-sys = with pkgs; mkOv [ glib ] [ pkg-config ];
  atk-sys = with pkgs; mkOv [ atk ] [ pkg-config ];
  gdk-pixbuf-sys = with pkgs; mkOv [ gdk_pixbuf ] [ pkg-config ];
  gdk-sys = with pkgs; mkOv [ gtk3 ] [ pkg-config ];
  gtk-sys = with pkgs; mkOv [ gtk3 ] [ pkg-config ];
  harmony_rust_sdk = prev:
    let
      env = {
        PROTOC = "${protobuf}/bin/protoc";
        PROTOC_INCLUDE = "${protobuf}/include";
      };
      inherit (pkgs) protobuf nciRust;
      inherit (nciRust) rustfmt;
    in
    {
      buildInputs = (prev.buildInputs or [ ]) ++ [ protobuf rustfmt ];
      propagatedEnv = env;
    } // env;
  rust-nix-templater = prev:
    let
      inherit (pkgs) nixpkgs-fmt nciRust;
      inherit (nciRust) rustc;

      env = {
        TEMPLATER_FMT_BIN = "${nixpkgs-fmt}/bin/nixpkgs-fmt";
        TEMPLATER_CARGO_BIN = "${rustc}/bin/cargo";
      };
    in
    { propagatedEnv = env; } // env;
  shaderc-sys = _:
    let env = { SHADERC_LIB_DIR = "${pkgs.shaderc.lib}/lib"; };
    in { propagatedEnv = env; } // env;
}
