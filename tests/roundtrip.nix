{
  lib,
  runCommand,
  tracy,
  zstd,
}:
runCommand "tracy-roundtrip-test-${tracy.version}"
  {
    __structuredAttrs = true;
    # Captures connect to instrumented programs over the loopback network.
    __darwinAllowLocalNetworking = true;
    nativeBuildInputs = [
      (lib.getBin tracy)
      (lib.getBin zstd)
    ];
  }
  ''
    mkdir -p "$out"
    for tracyTool in tracy-csvexport tracy-merge tracy-capture-daemon; do
      "$tracyTool" -V | grep -F ${lib.escapeShellArg tracy.version}
    done

    tracy-import-chrome ${./trace.json} original.tracy
    tracy-csvexport original.tracy | sort > original.csv
    # Chrome timestamps are microseconds; CSV durations are nanoseconds.
    awk -F, '$1 == "outer" && $4 == 1000000 && $6 == 1 { found = 1 } END { exit !found }' original.csv
    awk -F, '$1 == "inner" && $4 == 500000 && $6 == 1 { found = 1 } END { exit !found }' original.csv
    tracy-csvexport -e original.tracy > self.csv
    awk -F, '$1 == "outer" && $4 == 500000 { found = 1 } END { exit !found }' self.csv
    tracy-csvexport --sep ';' --filter pulse -t 90 original.tracy > filtered.csv
    test "$(wc -l < filtered.csv)" -eq 2
    grep '^pulse;' filtered.csv

    zstd -c ${./trace.json} > trace.json.zst
    tracy-import-chrome trace.json.zst compressed.tracy
    tracy-csvexport compressed.tracy | sort > compressed.csv
    diff -u original.csv compressed.csv

    tracy-update -z 3 original.tracy updated.tracy
    tracy-csvexport updated.tracy | sort > updated.csv
    diff -u original.csv updated.csv
    tracy-csvexport -m updated.tracy | grep -F test-message

    tracy-merge -o merged.tracy original.tracy updated.tracy
    tracy-csvexport merged.tracy > merged.csv
    awk -F, '$1 == "outer" && $4 == 2000000 && $6 == 2 { found = 1 } END { exit !found }' merged.csv

    # An independent FXT fixture: magic, 1 GHz clock, thread 1/7, string 1,
    # and a complete event from 1,000,000 to 1,500,000 ticks.
    # https://fuchsia.dev/fuchsia-src/reference/tracing/trace-format
    printf '%b' \
      '\x10\x00\x04\x46\x78\x54\x16\x00' \
      '\x21\x00\x00\x00\x00\x00\x00\x00' \
      '\x00\xca\x9a\x3b\x00\x00\x00\x00' \
      '\x33\x00\x01\x00\x00\x00\x00\x00' \
      '\x01\x00\x00\x00\x00\x00\x00\x00' \
      '\x07\x00\x00\x00\x00\x00\x00\x00' \
      '\x22\x00\x01\x00\x08\x00\x00\x00' \
      'fxt-zone' \
      '\x34\x00\x04\x01\x00\x00\x01\x00' \
      '\x40\x42\x0f\x00\x00\x00\x00\x00' \
      '\x60\xe3\x16\x00\x00\x00\x00\x00' > input.fxt
    tracy-import-fuchsia input.fxt fuchsia.tracy
    tracy-csvexport fuchsia.tracy > fuchsia.csv
    awk -F, '$1 == "fxt-zone" && $4 == 500000 && $6 == 1 { found = 1 } END { exit !found }' fuchsia.csv

    # Exercise the installed client, the wire protocol, capture and both APIs.
    ${tracy.tests.client}/bin/tracy-consumer capture > client.log 2>&1 &
    tracyClientPid=$!
    trap 'kill "$tracyClientPid" 2>/dev/null || true' EXIT
    timeout 30 tracy-capture -a 127.0.0.1 -o live.tracy > capture.log 2>&1 || {
      cat client.log capture.log
      exit 1
    }
    wait "$tracyClientPid"
    trap - EXIT
    tracy-csvexport live.tracy > live.csv
    awk -F, '$1 == "nix-cpp-zone" && $6 == 8 { cpp = 1 } $1 == "nix-c-zone" && $6 == 8 { c = 1 } END { exit !(cpp && c) }' live.csv
    tracy-csvexport -m live.tracy | grep -F nix-capture-complete

    # The update wrapper must supply its external symbolizer even with an empty PATH.
    env PATH= ${lib.getBin tracy}/bin/tracy-update -R -r live.tracy resolved.tracy > resolver.log
    grep -F "Using 'addr2line' found at:" resolver.log
    tracy-csvexport resolved.tracy > resolved.csv
    awk -F, '$1 == "nix-cpp-zone" && $6 == 8 { found = 1 } END { exit !found }' resolved.csv

    # Exercise daemon discovery on loopback, including in a network-isolated sandbox.
    # Broadcast v3: data port 18087, protocol 82, PID 1, uptime 1, then the name.
    tracy-capture-daemon -p 18086 -o daemon --filter-name nix-tracy-daemon \
      --filter-port 18087 > daemon.log 2>&1 &
    tracyDaemonPid=$!
    TRACY_PORT=18087 timeout 30 ${tracy.tests.client}/bin/tracy-pkgconfig-consumer capture > daemon-client.log 2>&1 &
    tracyClientPid=$!
    trap 'kill "$tracyClientPid" 2>/dev/null || true; kill -INT "$tracyDaemonPid" 2>/dev/null || true' EXIT
    for tracyAttempt in $(seq 1 100); do
      kill -0 "$tracyDaemonPid"
      if ! kill -0 "$tracyClientPid" 2>/dev/null; then break; fi
      printf '\x03\x00\xa7\x46\x52\x00\x00\x00\x01\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00nix-tracy-daemon\x00' \
        > /dev/udp/127.0.0.1/18086
      sleep 0.1
    done
    wait "$tracyClientPid" || { cat daemon.log daemon-client.log; exit 1; }
    kill -INT "$tracyDaemonPid"
    wait "$tracyDaemonPid"
    trap - EXIT
    tracy-csvexport daemon/*.tracy > daemon.csv
    awk -F, '$1 == "nix-cpp-zone" && $6 == 8 { found = 1 } END { exit !found }' daemon.csv

    # Validate failure paths without treating a usage exit as success.
    if tracy-csvexport missing.tracy > missing.log 2>&1; then exit 1; fi
    grep -F 'Could not open file' missing.log
    if tracy-import-chrome missing.json missing.tracy > missing.log 2>&1; then exit 1; fi
    grep -F 'Cannot open input file' missing.log
    cp *.csv *.tracy *.log "$out/"
  ''
