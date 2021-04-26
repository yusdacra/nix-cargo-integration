{ pkgs }:
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
  harmony_rust_sdk = prev:
    let env = { PROTOC = "protoc"; }; in
    {
      buildInputs = (prev.buildInputs or [ ]) ++ [ protobuf ];
      propagatedEnv = env;
    } // env;
}
