#!/bin/bash
# Measures what the iPad has to swallow: the game's size, and the time and peak memory of a debug
# build (-Onone -g, the way Swift Playgrounds builds). Takes a few minutes. Compare with another version:
#   GAME_SRC=<old file, or a folder of parts> tools/buildcost.sh
# It measures two ways of building:
#   - every file in one job (the only way a one-file game can be built);
#   - one job per file, as Swift package debug builds do: each job reads every file but type-checks
#     and compiles only its own. If the iPad builds this way, the highest peak of a job is what counts.
# The last version known to start on the iPad (598e07b, one file, tab-indented): 1,587,930 bytes, 63 s,
# 860 MB. The Mod Creator+ version as one file, which did not start there: 1,930,631 bytes, 86 s,
# 1,059 MB (same machine).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
mkdir -p "$PR_BUILD/buildcost"
files=()
while read -r f; do files+=("$f"); done < <(pr_game_files)
bytes=$(cat "${files[@]}" | wc -c)
lines=$(cat "${files[@]}" | wc -l)
echo "game: ${#files[@]} file(s), $bytes bytes, $lines lines"
LD_LIBRARY_PATH="$PR_LIBS" python3 - "$PR_BIN/swift-frontend" "$PR_SHIM" "$PR_BUILD/buildcost" "${files[@]}" <<'EOF'
import os, subprocess, sys, time
fe, shim, out = sys.argv[1:4]
files = sys.argv[4:]
base = [fe, "-c", "-I", shim, "-parse-as-library", "-Onone", "-g", "-module-name", "PixelRealm"]

def run(args):
    """Runs one compiler job; gives its exit code, seconds and peak memory (MB)"""
    t0 = time.time()
    p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    text = p.stdout.read().decode(errors="replace")
    _, status, ru = os.wait4(p.pid, 0)
    p.returncode = os.waitstatus_to_exitcode(status)
    for e in [l for l in text.splitlines() if "error" in l][:10]: print(e)
    return p.returncode, time.time() - t0, ru.ru_maxrss / 1024.0

code, dt, peak = run(base + files + ["-o", os.path.join(out, "game.o")])
print(f"one job for everything: exit {code}, {dt:.0f} s, peak memory {peak:.0f} MB")
worst = peak
if len(files) > 1:
    total = 0.0
    worst = 0.0
    fails = 0
    for i, f in enumerate(files):
        others = [g for g in files if g != f]
        c, t, m = run(base + ["-primary-file", f] + others + ["-o", os.path.join(out, f"part{i + 1}.o")])
        total += t
        worst = max(worst, m)
        fails += 1 if c != 0 else 0
        print(f"  job for {os.path.basename(f)}: exit {c}, {t:.0f} s, peak memory {m:.0f} MB")
    print(f"one job per file: {fails} failed, {total:.0f} s in all, highest peak {worst:.0f} MB")
    code = code or (1 if fails else 0)
if worst > 880:
    print("WARNING: more memory than the last version known to start on the iPad (860 MB)")
sys.exit(code)
EOF
