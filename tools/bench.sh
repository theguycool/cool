#!/bin/bash
# Times chunk generation, painting, lighting and a busy game tick (debug build, so compare runs
# against each other, not against the iPad):  tools/bench.sh
# To compare with an older version: GAME_SRC=<old file, or folder of parts> tools/bench.sh
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
"$PR_TOOLS/build.sh" "$PR_TOOLS/bench/main.swift" "$PR_BUILD/bench/t.bin" || { echo "build failed"; exit 1; }
LD_LIBRARY_PATH="$PR_LIBS" "$PR_BUILD/bench/t.bin" | tail -8
