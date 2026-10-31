#!/bin/bash
# Builds a headless program against the game: tools/build.sh <main.swift> <output binary>
# The game is copied next to the output with its @main removed (the program supplies its own top
# level), so several builds can run at once. GAME_SRC picks another game file (an older version, say).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
main="$1"
out="$2"
dir="$(dirname "$out")"
mkdir -p "$dir"
sed 's/^@main$//' "$PR_GAME" > "$dir/game_copy.swift"
LD_LIBRARY_PATH="$PR_LIBS" "$PR_BIN/swiftc" -Onone "$main" "$dir/game_copy.swift" -I "$PR_SHIM" -L "$PR_SHIM" \
    -lSwiftUI -lAVFoundation -o "$out" 2>&1 | grep -E "error" | head -20
test -x "$out"
