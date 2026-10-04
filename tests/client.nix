{
  lib,
  stdenv,
  cmake,
  ninja,
  pkg-config,
  tracy,
}:
stdenv.mkDerivation {
  pname = "tracy-client-test";
  inherit (tracy) version;
  src = ./client;
  __structuredAttrs = true;
  strictDeps = true;
  nativeBuildInputs = [
    cmake
    ninja
    pkg-config
  ];
  buildInputs = [ tracy ];
  cmakeFlags = [ (lib.cmakeFeature "EXPECTED_TRACY_VERSION" tracy.version) ];
  postBuild = ''
    $PKG_CONFIG --exact-version=${tracy.version} tracy
    $CXX -std=c++11 $($PKG_CONFIG --cflags tracy) ../main.cpp \
      -o tracy-pkgconfig-consumer $($PKG_CONFIG --libs --static tracy)
    for tracyCStandard in c11 c23; do
      $CC -std=$tracyCStandard $($PKG_CONFIG --cflags tracy) ../main.c \
        -o tracy-$tracyCStandard-consumer $($PKG_CONFIG --libs --static tracy)
    done
  '';
  doCheck = true;
  # Instrumented programs listen on, and broadcast to, the loopback network.
  __darwinAllowLocalNetworking = true;
  checkPhase = ''
    runHook preCheck
    timeout 30 ./tracy-consumer
    timeout 30 ./tracy-pkgconfig-consumer
    timeout 30 ./tracy-c11-consumer
    timeout 30 ./tracy-c23-consumer
    runHook postCheck
  '';
  postInstall = ''
    install -m755 tracy-pkgconfig-consumer tracy-c11-consumer tracy-c23-consumer "$out/bin/"
  '';
  meta = {
    inherit (tracy.meta) platforms badPlatforms;
  };
}
