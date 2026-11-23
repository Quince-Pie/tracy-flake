let
  defaultVersion = "0.15.0";
  defaultSrcHash = "sha256-Jzlw1wXNQ/pYhIK+jN47SGCMPftdH4QoDrmh36++VXE=";

  cmakeBool = name: val: "-D${name}:BOOL=${if val then "TRUE" else "FALSE"}";
  cmakeFeature = name: val: "-D${name}:STRING=${val}";

  mkTracy =
    shared:
    args@{
      lib,
      stdenv,
      fetchFromGitHub,
      callPackage,
      buildPackages,
      symlinkJoin,
      testers,
      cmake,
      ninja,
      pkg-config,
      makeBinaryWrapper,
      versionCheckHook,
      python3,
      pandoc,
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
      gtk3,
      xdg-utils,
      binutils-unwrapped,
      which,
      libunwind,
      elfutils,
      rocmPackages,
      # Component and profiler UI options.
      # TRACY_LTO (creates an uninstalled OBJECT target), TRACY_CLIENT_PYTHON
      # (internal to python/pyproject.toml wheel builds) and TRACY_Fortran
      # (TracyClient.F90 still calls symbols removed in 0.14.0) are omitted.
      withGui ? true,
      withTools ? true,
      waylandSupport ? stdenv.hostPlatform.isLinux,
      withFileSelector ? true,
      withGtkFileSelector ? false,
      selfProfile ? false,
      enableShared ? !stdenv.hostPlatform.isStatic,
      enableLto ? true,
      # Client library options exposed by CMakeLists.txt.
      enableProfiling ? true,
      # Record only while a profiler is connected, instead of buffering from launch.
      onDemand ? false,
      callstackDepth ? null,
      platformHeader ? null,
      noCallstack ? false,
      noCallstackInlines ? false,
      onlyLocalhost ? false,
      noBroadcast ? false,
      onlyIpv4 ? false,
      noCodeTransfer ? false,
      noContextSwitch ? false,
      noExit ? false,
      noSampling ? false,
      noWaitStacks ? false,
      noVerify ? false,
      noVsyncCapture ? false,
      noFrameImage ? false,
      noSystemTracing ? false,
      patchableNopsleds ? false,
      manualLifetime ? false,
      # Opt-in upstream: zone events from every thread then share one lock.
      fiberSupport ? false,
      noCrashHandler ? false,
      timerFallback ? false,
      disallowHwTimer ? false,
      libunwindBacktrace ? false,
      symbolOfflineResolve ? false,
      libbacktraceElfDynloadSupport ? false,
      debuginfodSupport ? false,
      ignoreMemoryFaults ? false,
      openglAutoCalibration ? false,
      verbose ? false,
      noInternalMessage ? false,
      customDemangle ? false,
      rocmSupport ? false,
      rocmCalibration ? false,
    }:
    assert waylandSupport -> stdenv.hostPlatform.isLinux;
    assert withGtkFileSelector -> stdenv.hostPlatform.isLinux && withFileSelector;
    assert disallowHwTimer -> timerFallback;
    assert callstackDepth != null -> builtins.isInt callstackDepth && callstackDepth >= 0;
    assert platformHeader != null -> builtins.isString platformHeader && platformHeader != "";
    assert debuginfodSupport -> stdenv.hostPlatform.isElf;
    assert rocmSupport -> stdenv.hostPlatform.isLinux;
    assert rocmCalibration -> rocmSupport;
    let
      inherit (stdenv) hostPlatform buildPlatform;
      inherit (hostPlatform) isLinux isMusl isStatic;
      withServer = withGui || withTools;
      isCross = buildPlatform != hostPlatform;

      # Reuse the fetched source and dependency thunks across .client, .tools and .override
      # unless the caller replaced fetchFromGitHub.
      cache =
        if shared != null && [ shared.fetchFromGitHub ] == [ fetchFromGitHub ] then
          shared
        else
          {
            inherit fetchFromGitHub;
            src = fetchFromGitHub {
              owner = "wolfpld";
              repo = "tracy";
              tag = "v${defaultVersion}";
              hash = defaultSrcHash;
            };
            dependencies = import ./dependencies.nix { inherit fetchFromGitHub; };
          };

      # Keyed by CPM package name.
      sources =
        if !withServer then
          { }
        else
          {
            inherit (cache.dependencies) capstone PPQSort;
          }
          // lib.optionalAttrs withGui {
            inherit (cache.dependencies)
              ImGui
              md4c
              base64
              usearch
              ;
            ${if withFileSelector then "nfd" else null} = cache.dependencies.nfd;
          };
      sourceNames = builtins.attrNames sources;

      # Evaluate opt-in boolean flags (all default OFF upstream) via a single native
      # dynamic-key attrset instead of ~30 per-flag lib.cmakeBool / list-concat calls.
      enabledOptions = builtins.attrNames {
        ${if onDemand then "TRACY_ON_DEMAND" else null} = null;
        ${if noCallstack then "TRACY_NO_CALLSTACK" else null} = null;
        ${if noCallstackInlines then "TRACY_NO_CALLSTACK_INLINES" else null} = null;
        ${if onlyLocalhost then "TRACY_ONLY_LOCALHOST" else null} = null;
        ${if noBroadcast then "TRACY_NO_BROADCAST" else null} = null;
        ${if onlyIpv4 then "TRACY_ONLY_IPV4" else null} = null;
        ${if noCodeTransfer then "TRACY_NO_CODE_TRANSFER" else null} = null;
        ${if noContextSwitch then "TRACY_NO_CONTEXT_SWITCH" else null} = null;
        ${if noExit then "TRACY_NO_EXIT" else null} = null;
        ${if noSampling then "TRACY_NO_SAMPLING" else null} = null;
        ${if noWaitStacks then "TRACY_NO_WAIT_STACKS" else null} = null;
        ${if noVerify then "TRACY_NO_VERIFY" else null} = null;
        ${if noVsyncCapture then "TRACY_NO_VSYNC_CAPTURE" else null} = null;
        ${if noFrameImage then "TRACY_NO_FRAME_IMAGE" else null} = null;
        ${if noSystemTracing then "TRACY_NO_SYSTEM_TRACING" else null} = null;
        ${if patchableNopsleds then "TRACY_PATCHABLE_NOPSLEDS" else null} = null;
        ${if manualLifetime then "TRACY_MANUAL_LIFETIME" else null} = null;
        ${if fiberSupport then "TRACY_FIBERS" else null} = null;
        ${if noCrashHandler then "TRACY_NO_CRASH_HANDLER" else null} = null;
        ${if timerFallback then "TRACY_TIMER_FALLBACK" else null} = null;
        ${if disallowHwTimer then "TRACY_DISALLOW_HW_TIMER" else null} = null;
        ${if libunwindBacktrace then "TRACY_LIBUNWIND_BACKTRACE" else null} = null;
        ${if symbolOfflineResolve then "TRACY_SYMBOL_OFFLINE_RESOLVE" else null} = null;
        ${if libbacktraceElfDynloadSupport then "TRACY_LIBBACKTRACE_ELF_DYNLOAD_SUPPORT" else null} = null;
        ${if debuginfodSupport then "TRACY_DEBUGINFOD" else null} = null;
        ${if ignoreMemoryFaults then "TRACY_IGNORE_MEMORY_FAULTS" else null} = null;
        ${if openglAutoCalibration then "TRACY_OPENGL_AUTO_CALIBRATION" else null} = null;
        ${if verbose then "TRACY_VERBOSE" else null} = null;
        ${if noInternalMessage then "TRACY_NO_INTERNAL_MESSAGE" else null} = null;
        ${if customDemangle then "TRACY_DEMANGLE" else null} = null;
        ${if rocmCalibration then "TRACY_ROCPROF_CALIBRATION" else null} = null;
      };
    in
    stdenv.mkDerivation (finalAttrs: {
      pname =
        if withGui then
          "tracy"
        else if withTools then
          "tracy-tools"
        else
          "tracy-client";
      version = defaultVersion;

      src =
        if finalAttrs.version == defaultVersion then
          cache.src
        else
          fetchFromGitHub {
            owner = "wolfpld";
            repo = "tracy";
            tag = "v${finalAttrs.version}";
            hash = defaultSrcHash;
          };

      __structuredAttrs = true;
      strictDeps = true;

      outputs =
        if withServer then
          [
            "out"
            "lib"
            "dev"
          ]
        else
          [
            "out"
            "dev"
          ];
      # Keep the profiler and tools out of library consumers' build closures.
      propagatedBuildOutputs = [ (if withServer then "lib" else "out") ];

      patches = builtins.concatLists [
        [ ./pkg-config.patch ]
        (lib.optionals withServer [
          ./build-components.patch
          ./system-libraries.patch
        ])
        (lib.optional withGui ./embed-tool.patch)
        (lib.optional (withGui && isLinux && !waylandSupport) ./glfw-x11.patch)
      ];

      postPatch =
        lib.optionalString withServer (
          ''
            # Copy the vendored sources, failing early if an update changed their pins.
            # CPM applies Tracy's own patches to these copies while configuring.
            tracyPins=$(awk '$1 == "GIT_TAG" || $1 == "VERSION" { print $2 }' cmake/vendor.cmake)
            mkdir vendor
          ''
          + builtins.concatStringsSep "" (
            map (
              name:
              let
                source = sources.${name};
                pin = lib.removePrefix "refs/tags/" source.rev;
              in
              ''
                grep -qxF -e ${lib.escapeShellArg pin} -e ${lib.escapeShellArg (lib.removePrefix "v" pin)} <<< "$tracyPins" || {
                  echo "cmake/vendor.cmake no longer pins ${name} ${pin}; update dependencies.nix" >&2
                  exit 1
                }
                cp -R ${source} vendor/${name}
              ''
            ) sourceNames
          )
          + ''
            chmod -R u+w vendor
          ''
        )
        + lib.optionalString (withGui && withFileSelector && waylandSupport) ''
          # Stand in for NFD's wayland-protocols submodule.
          rmdir vendor/nfd/3ps/wayland-protocols
          ln -s ${wayland-protocols}/share/wayland-protocols vendor/nfd/3ps/wayland-protocols
        ''
        + lib.optionalString (withGui && isLinux) (
          let
            glvndLib = "${lib.getLib libglvnd}/lib";
          in
          ''
            # These libraries are opened by name, so the linker cannot retain their RPATHs.
            substituteInPlace vendor/ImGui/backends/imgui_impl_opengl3_loader.h \
              --replace-fail '"libEGL.so.1"' '"${glvndLib}/libEGL.so.1"' \
              --replace-fail '"libGLX.so.0"' '"${glvndLib}/libGLX.so.0"' \
              --replace-fail '"libOpenGL.so.0"' '"${glvndLib}/libOpenGL.so.0"' \
              --replace-fail '"libGL.so"' '"${glvndLib}/libGL.so"' \
              --replace-fail '"libGL.so.1"' '"${glvndLib}/libGL.so.1"'
          ''
        );

      depsBuildBuild = lib.optional (withGui && isCross) buildPackages.stdenv.cc;

      nativeBuildInputs = builtins.concatLists [
        [
          cmake
          ninja
        ]
        (lib.optional (withServer || libunwindBacktrace || debuginfodSupport) pkg-config)
        # CMake archives LTO objects with llvm-ar when the compiler is Clang.
        (lib.optional (withServer && enableLto && stdenv.cc.isClang) stdenv.cc.cc.libllvm)
        (lib.optional (withTools || (withGui && isLinux)) makeBinaryWrapper)
        (lib.optionals withGui [
          python3
          pandoc
        ])
        (lib.optional (withGui && waylandSupport) wayland-scanner)
      ];

      buildInputs = builtins.concatLists [
        (lib.optionals withServer [
          zstd
          nlohmann_json
        ])
        (lib.optionals withGui [
          freetype
          curl
          pugixml
          html-tidy
        ])
        (lib.optional (withGui && !waylandSupport) glfw3)
        (lib.optional (withGui && isLinux) libglvnd)
        (lib.optional (withGui && isLinux && withFileSelector && !withGtkFileSelector) dbus)
        (lib.optional (withGui && isLinux && withFileSelector && withGtkFileSelector) gtk3)
        (lib.optionals (withGui && waylandSupport) [
          wayland
          wayland-protocols
          libxkbcommon
        ])
        (lib.optionals (withGui && isLinux && !waylandSupport) [
          libx11
          libxrandr
        ])
      ];

      propagatedBuildInputs = builtins.concatLists [
        (lib.optional libunwindBacktrace libunwind)
        (lib.optional debuginfodSupport (elfutils.override { enableDebuginfod = true; }))
        # rocprofiler-sdk-config.cmake checks for both dev headers and out libraries under one prefix.
        (lib.optional rocmSupport (symlinkJoin {
          name = "rocprofiler-sdk-${rocmPackages.rocprofiler-sdk.version}-merged";
          paths = [
            rocmPackages.rocprofiler-sdk
            rocmPackages.rocprofiler-sdk.dev
          ];
        }))
      ];

      # The tools use the LFS64 names, which musl only declares on request.
      env = lib.optionalAttrs (withServer && isMusl) {
        NIX_CFLAGS_COMPILE = "-D_LARGEFILE64_SOURCE";
      };
      # musl's fortify-headers cannot inline their always_inline wrappers across LTO.
      hardeningDisable = lib.optional (withServer && enableLto && isMusl) "fortify";

      preConfigure =
        lib.optionalString withServer (
          builtins.concatStringsSep "" (
            map (name: ''
              appendToVar cmakeFlags "-DCPM_${name}_SOURCE:PATH=$PWD/vendor/${name}"
            '') sourceNames
          )
        )
        + lib.optionalString withGui ''
          "''${CXX_FOR_BUILD:-$CXX}" -std=c++20 -O3 \
            public/common/tracy_lz4.cpp \
            public/common/tracy_lz4hc.cpp \
            profiler/helpers/embed.cpp \
            -o "$TMPDIR/tracy-embed"
          appendToVar cmakeFlags "-DTRACY_EMBED_TOOL:FILEPATH=$TMPDIR/tracy-embed"
        '';

      cmakeFlags = builtins.concatLists [
        [
          (cmakeBool "TRACY_ENABLE" enableProfiling)
          (cmakeBool "TRACY_STATIC" (!enableShared))
          # TRACY_LTO creates an OBJECT library, which is unsuitable for an installed client.
          (cmakeBool "TRACY_LTO" false)
          (cmakeBool "CMAKE_DISABLE_FIND_PACKAGE_rocprofiler-sdk" (!rocmSupport))
        ]
        (map (flag: "-D${flag}:BOOL=TRUE") enabledOptions)
        (lib.optional (callstackDepth != null) (cmakeFeature "TRACY_CALLSTACK" (toString callstackDepth)))
        (lib.optional (platformHeader != null) (cmakeFeature "TRACY_PLATFORM_HEADER" platformHeader))
        (lib.optionals withServer [
          (cmakeBool "TRACY_BUILD_PROFILER" withGui)
          (cmakeBool "TRACY_BUILD_TOOLS" withTools)
          (cmakeBool "NO_ISA_EXTENSIONS" true)
          (cmakeBool "NO_LTO" (!enableLto))
          (cmakeBool "NO_CCACHE" true)
          (cmakeBool "NO_MOLD_LINKER" true)
          # Dependencies without a CPM_<name>_SOURCE override must come from the system.
          (cmakeBool "CPM_LOCAL_PACKAGES_ONLY" true)
          (cmakeFeature "TRACY_GIT_REF" "v${finalAttrs.version}")
        ])
        (lib.optionals withGui [
          (cmakeBool "LEGACY" (!waylandSupport))
          (cmakeBool "NO_FILESELECTOR" (!withFileSelector))
          (cmakeBool "GTK_FILESELECTOR" withGtkFileSelector)
          (cmakeBool "SELF_PROFILE" selfProfile)
        ])
        (lib.optionals (withGui && withFileSelector) [
          (cmakeBool "NFD_WAYLAND" waylandSupport)
          (cmakeBool "NFD_X11" (!waylandSupport))
        ])
      ];

      postInstall = ''
        install -Dm644 ../LICENSE "$out/share/licenses/tracy/LICENSE"
      ''
      + lib.optionalString withGui ''
        install -Dm644 profiler/manual/tracy.md "$out/share/doc/tracy/tracy.md"
      ''
      + lib.optionalString (withGui && isLinux) ''
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
        inherit enableProfiling;
        client = lib.makeOverridable (mkTracy cache) (
          args
          // {
            withGui = false;
            withTools = false;
          }
        );
        tools = lib.makeOverridable (mkTracy cache) (
          args
          // {
            withGui = false;
            withTools = true;
          }
        );
        tests = {
          client = callPackage ./tests/client.nix { tracy = finalAttrs.finalPackage; };
          pkg-config = testers.hasPkgConfigModules {
            package = finalAttrs.finalPackage;
            versionCheck = true;
          };
          ${if withTools && buildPlatform.canExecute hostPlatform then "roundtrip" else null} =
            callPackage ./tests/roundtrip.nix
              { tracy = finalAttrs.finalPackage; };
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
        ++ lib.optional (withGui && isLinux) lib.licenses.cc-by-sa-30;
        platforms = lib.platforms.linux ++ lib.platforms.darwin;
        # The protocol requires little-endian CPUs; the server additionally needs 64 bits,
        # and the profiler loads OpenGL dynamically.
        badPlatforms = builtins.concatLists [
          [ lib.systems.inspect.patterns.isBigEndian ]
          (lib.optional withServer lib.systems.inspect.patterns.is32bit)
          (lib.optional withGui lib.systems.inspect.platformPatterns.isStatic)
        ];
        pkgConfigModules = [ "tracy" ];
        maintainers = [ ];
        ${if withServer then "mainProgram" else null} =
          if withGui then "tracy-profiler" else "tracy-capture";
      };
    });
in
mkTracy null
