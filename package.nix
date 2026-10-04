args@{
  lib,
  stdenv,
  fetchFromGitHub,
  callPackage,
  buildPackages,
  testers,
  cmake,
  ninja,
  pkg-config,
  makeBinaryWrapper,
  versionCheckHook,
  zstd,
  nlohmann_json,
  freetype,
  curl,
  pugixml,
  html-tidy,
  glfw3,
  libglvnd,
  libx11,
  libxrandr,
  libxkbcommon,
  wayland,
  wayland-protocols,
  wayland-scanner,
  dbus,
  xdg-utils,
  binutils-unwrapped,
  which,
  withGui ? true,
  withTools ? true,
  waylandSupport ? stdenv.hostPlatform.isLinux,
  # Opt-in upstream: zone events from every thread then share one lock.
  fiberSupport ? false,
  # Record only while a profiler is connected, instead of buffering from launch.
  onDemand ? false,
  enableShared ? !stdenv.hostPlatform.isStatic,
  enableLto ? true,
}:
let
  withServer = withGui || withTools;
  dependencies = import ./dependencies.nix { inherit fetchFromGitHub; };
  # Keyed by CPM package name.
  sources =
    lib.optionalAttrs withServer {
      inherit (dependencies) capstone PPQSort;
    }
    // lib.optionalAttrs withGui {
      inherit (dependencies)
        ImGui
        nfd
        md4c
        base64
        usearch
        ;
    };
in
assert waylandSupport -> stdenv.hostPlatform.isLinux;
stdenv.mkDerivation (finalAttrs: {
  pname = "tracy" + lib.optionalString (!withGui) (if withTools then "-tools" else "-client");
  version = "0.14.1";

  src = fetchFromGitHub {
    owner = "wolfpld";
    repo = "tracy";
    tag = "v${finalAttrs.version}";
    hash = "sha256-vcLI9jb7eYcR162LgBQ2P4A0oiZuYRfYRQiDhlAk5TI=";
  };

  __structuredAttrs = true;
  strictDeps = true;

  outputs = [ "out" ] ++ lib.optional withServer "lib" ++ [ "dev" ];
  # Keep the profiler and tools out of library consumers' build closures.
  propagatedBuildOutputs = [ (if withServer then "lib" else "out") ];

  patches = [
    ./pkg-config.patch
  ]
  ++ lib.optionals withServer [
    ./build-components.patch
    ./system-libraries.patch
  ]
  ++ lib.optional withGui ./embed-tool.patch
  ++ lib.optional (withGui && stdenv.hostPlatform.isLinux && !waylandSupport) ./glfw-x11.patch;

  postPatch =
    lib.optionalString withServer (
      ''
        # Both the client and server configuration generate the same build-tree file.
        substituteInPlace cmake/config.cmake \
          --replace-fail 'file(GENERATE OUTPUT .gitignore CONTENT "*")' ""

        # Copy the vendored sources, failing early if an update changed their pins.
        # CPM applies Tracy's own patches to these copies while configuring.
        tracyPins=$(awk '$1 == "GIT_TAG" || $1 == "VERSION" { print $2 }' cmake/vendor.cmake)
        mkdir vendor
      ''
      + lib.concatMapAttrsStringSep "" (
        name: source:
        let
          pin = lib.removePrefix "refs/tags/" source.rev;
        in
        ''
          grep -qxF -e ${lib.escapeShellArg pin} -e ${lib.escapeShellArg (lib.removePrefix "v" pin)} <<< "$tracyPins" || {
            echo "cmake/vendor.cmake no longer pins ${name} ${pin}; update dependencies.nix" >&2
            exit 1
          }
          cp -R ${source} vendor/${name}
        ''
      ) sources
      + ''
        chmod -R u+w vendor
        patch -d vendor/PPQSort -p1 < ${./ppqsort-no-install.patch}
      ''
    )
    + lib.optionalString (withGui && waylandSupport) ''
      # Stand in for NFD's wayland-protocols submodule.
      rmdir vendor/nfd/3ps/wayland-protocols
      ln -s ${wayland-protocols}/share/wayland-protocols vendor/nfd/3ps/wayland-protocols
    ''
    + lib.optionalString (withGui && stdenv.hostPlatform.isLinux) ''
      # These libraries are opened by name, so the linker cannot retain their RPATHs.
      substituteInPlace vendor/ImGui/backends/imgui_impl_opengl3_loader.h \
        --replace-fail '"libEGL.so.1"' '"${lib.getLib libglvnd}/lib/libEGL.so.1"' \
        --replace-fail '"libGLX.so.0"' '"${lib.getLib libglvnd}/lib/libGLX.so.0"' \
        --replace-fail '"libOpenGL.so.0"' '"${lib.getLib libglvnd}/lib/libOpenGL.so.0"' \
        --replace-fail '"libGL.so"' '"${lib.getLib libglvnd}/lib/libGL.so"' \
        --replace-fail '"libGL.so.1"' '"${lib.getLib libglvnd}/lib/libGL.so.1"'
    '';

  nativeBuildInputs = [
    cmake
    ninja
  ]
  ++ lib.optional withServer pkg-config
  # CMake archives LTO objects with llvm-ar when the compiler is Clang.
  ++ lib.optional (withServer && enableLto && stdenv.cc.isClang) stdenv.cc.cc.libllvm
  ++ lib.optional (withTools || (withGui && stdenv.hostPlatform.isLinux)) makeBinaryWrapper
  ++ lib.optional (withGui && waylandSupport) wayland-scanner;

  buildInputs =
    lib.optionals withServer [
      zstd
      nlohmann_json
    ]
    ++ lib.optionals withGui [
      freetype
      curl
      pugixml
      html-tidy
    ]
    ++ lib.optional (withGui && !waylandSupport) glfw3
    ++ lib.optionals (withGui && stdenv.hostPlatform.isLinux) [
      dbus
      libglvnd
    ]
    ++ lib.optionals (withGui && waylandSupport) [
      wayland
      libxkbcommon
    ]
    ++ lib.optionals (withGui && stdenv.hostPlatform.isLinux && !waylandSupport) [
      libx11
      libxrandr
    ];

  # The tools use the LFS64 names, which musl only declares on request.
  env = lib.optionalAttrs (withServer && stdenv.hostPlatform.isMusl) {
    NIX_CFLAGS_COMPILE = "-D_LARGEFILE64_SOURCE";
  };
  # musl's fortify-headers cannot inline their always_inline wrappers across LTO.
  hardeningDisable = lib.optional (withServer && enableLto && stdenv.hostPlatform.isMusl) "fortify";

  preConfigure = lib.concatMapAttrsStringSep "" (name: _: ''
    appendToVar cmakeFlags "${lib.cmakeOptionType "path" "CPM_${name}_SOURCE" "$PWD/vendor/${name}"}"
  '') sources;

  cmakeFlags = [
    (lib.cmakeBool "TRACY_ENABLE" true)
    (lib.cmakeBool "TRACY_STATIC" (!enableShared))
    # TRACY_LTO creates an OBJECT library, which is unsuitable for an installed client.
    (lib.cmakeBool "TRACY_LTO" false)
    (lib.cmakeBool "TRACY_FIBERS" fiberSupport)
    (lib.cmakeBool "TRACY_ON_DEMAND" onDemand)
    (lib.cmakeBool "CMAKE_DISABLE_FIND_PACKAGE_rocprofiler-sdk" true)
  ]
  ++ lib.optionals withServer [
    (lib.cmakeBool "TRACY_BUILD_PROFILER" withGui)
    (lib.cmakeBool "TRACY_BUILD_TOOLS" withTools)
    (lib.cmakeBool "NO_ISA_EXTENSIONS" true)
    (lib.cmakeBool "NO_LTO" (!enableLto))
    (lib.cmakeBool "NO_CCACHE" true)
    (lib.cmakeBool "NO_MOLD_LINKER" true)
    # Dependencies without a CPM_<name>_SOURCE override must come from the system.
    (lib.cmakeBool "CPM_LOCAL_PACKAGES_ONLY" true)
    (lib.cmakeFeature "TRACY_GIT_REF" "v${finalAttrs.version}")
  ]
  ++ lib.optionals withGui [
    (lib.cmakeBool "LEGACY" (!waylandSupport))
    (lib.cmakeBool "NFD_WAYLAND" waylandSupport)
    (lib.cmakeBool "NFD_X11" (!waylandSupport))
    (lib.cmakeFeature "TRACY_EMBED_TOOL" (
      lib.getExe (
        buildPackages.callPackage ./embed.nix {
          inherit (finalAttrs) src version;
        }
      )
    ))
  ]
  ++ lib.optional (withGui && waylandSupport) (
    lib.cmakeOptionType "path" "CPM_wayland-protocols_SOURCE"
      "${wayland-protocols}/share/wayland-protocols"
  );

  postInstall = ''
    install -Dm644 ../LICENSE "$out/share/licenses/tracy/LICENSE"
  ''
  + lib.optionalString withGui ''
    install -Dm644 ../manual/tracy.md "$out/share/doc/tracy/tracy.md"
  ''
  + lib.optionalString (withGui && stdenv.hostPlatform.isLinux) ''
    install -Dm644 ../extra/desktop/tracy.desktop -t "$out/share/applications"
    install -Dm644 ../extra/desktop/application-tracy.xml -t "$out/share/mime/packages"
    install -Dm644 ../icon/icon.svg "$out/share/icons/hicolor/scalable/apps/tracy.svg"
    install -Dm644 ../icon/application-tracy.svg -t "$out/share/icons/hicolor/scalable/mimetypes"
    install -Dm644 ../icon/application-tracy.copying -t "$out/share/licenses/tracy"
    wrapProgram "$out/bin/tracy-profiler" --suffix PATH : ${lib.makeBinPath [ xdg-utils ]}
  ''
  + lib.optionalString withTools ''
    wrapProgram "$out/bin/tracy-update" --suffix PATH : ${
      lib.makeBinPath [
        which
        binutils-unwrapped
      ]
    }
  '';

  postFixup = ''
    # CMake hard-codes the original prefix when the export directory is absolute.
    # The headers and CMake files live in dev; the library location stays in lib.
    substituteInPlace "$dev/lib/cmake/Tracy/TracyTargets.cmake" \
      --replace-fail "$out" "$dev"
  ''
  + lib.optionalString withServer ''
    substituteInPlace "$dev/lib/cmake/Tracy/TracyConfig.cmake" \
      --replace-fail "''${out##*/}" "''${dev##*/}"
  '';

  # Library consumers must not pull the profiler or tools into their closures.
  outputChecks = lib.optionalAttrs withServer {
    lib.disallowedReferences = [
      "out"
      "dev"
    ];
    dev.disallowedReferences = [ "out" ];
  };

  doInstallCheck = withServer;
  nativeInstallCheckInputs = [ versionCheckHook ];
  # The profiler would open "--version" as a trace file.
  versionCheckProgramArg = "--help";

  passthru = {
    client =
      (callPackage ./package.nix (
        args
        // {
          withGui = false;
          withTools = false;
        }
      )).overrideAttrs
        { inherit (finalAttrs) src version; };
    tools =
      (callPackage ./package.nix (
        args
        // {
          withGui = false;
          withTools = true;
        }
      )).overrideAttrs
        { inherit (finalAttrs) src version; };
    tests = {
      client = callPackage ./tests/client.nix { tracy = finalAttrs.finalPackage; };
      pkg-config = testers.hasPkgConfigModules {
        package = finalAttrs.finalPackage;
        versionCheck = true;
      };
    }
    // lib.optionalAttrs (withTools && stdenv.buildPlatform.canExecute stdenv.hostPlatform) {
      roundtrip = callPackage ./tests/roundtrip.nix { tracy = finalAttrs.finalPackage; };
    };
  };

  meta = {
    description = "Real-time, nanosecond resolution frame profiler";
    homepage = "https://github.com/wolfpld/tracy";
    changelog = "https://github.com/wolfpld/tracy/blob/v${finalAttrs.version}/NEWS";
    # The MIME type icon is CC-BY-SA artwork derived from the Adwaita icon theme.
    license = [
      lib.licenses.bsd3
    ]
    ++ lib.optional (withGui && stdenv.hostPlatform.isLinux) lib.licenses.cc-by-sa-30;
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
    # The protocol requires little-endian CPUs; the server additionally needs 64 bits,
    # and the profiler loads OpenGL dynamically.
    badPlatforms = [
      lib.systems.inspect.patterns.isBigEndian
    ]
    ++ lib.optional withServer lib.systems.inspect.patterns.is32bit
    ++ lib.optional withGui lib.systems.inspect.platformPatterns.isStatic;
    pkgConfigModules = [ "tracy" ];
    maintainers = [ ];
  }
  // lib.optionalAttrs withServer {
    mainProgram = if withGui then "tracy-profiler" else "tracy-capture";
  };
})
