{
  lib,
  stdenv,
  cmake,
  ninja,
  src,
  version,
}:
stdenv.mkDerivation {
  pname = "tracy-embed";
  inherit version src;

  nativeBuildInputs = [
    cmake
    ninja
  ];
  __structuredAttrs = true;
  strictDeps = true;
  cmakeDir = "../profiler/helpers";

  # Upstream installs this build-time executable directly in the prefix.
  postInstall = ''
    mkdir -p "$out/bin"
    mv "$out/embed" "$out/bin/"
  '';

  meta = {
    description = "Build-time resource compiler for Tracy";
    license = lib.licenses.bsd3;
    mainProgram = "embed";
    platforms = lib.platforms.unix;
  };
}
