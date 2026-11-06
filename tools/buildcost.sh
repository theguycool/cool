#!/bin/bash
# Measures what the iPad has to swallow: the file's size, and the time and peak memory of a debug build
# (-Onone -g, the way Swift Playgrounds builds). Takes about 100 s. Compare with an older file:
#   GAME_SRC=<old file> tools/buildcost.sh
# The last version known to load on the iPad (598e07b): 1,864,428 bytes, 74 s, 870 MB.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
mkdir -p "$PR_BUILD/buildcost"
bytes=$(wc -c < "$PR_GAME")
lines=$(wc -l < "$PR_GAME")
echo "file: $bytes bytes, $lines lines"
if [ "$bytes" -ge 1950000 ]; then echo "WARNING: the file is close to 2 MB; the iPad may not load it"; fi
LD_LIBRARY_PATH="$PR_LIBS" python3 - "$PR_BIN/swift-frontend" "$PR_SHIM" "$PR_GAME" "$PR_BUILD/buildcost/game.o" <<'EOF'
import resource, subprocess, sys, time
fe, shim, src, out = sys.argv[1:5]
t0 = time.time()
p = subprocess.run([fe, "-c", "-I", shim, "-parse-as-library", "-Onone", "-g", "-module-name", "PixelRealm", src, "-o", out],
                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
dt = time.time() - t0
peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024.0
errs = [l for l in p.stdout.decode(errors="replace").splitlines() if "error" in l][:10]
for e in errs: print(e)
print(f"debug build: exit {p.returncode}, {dt:.0f} s, peak memory {peak:.0f} MB")
sys.exit(p.returncode)
EOF
