#!/bin/bash
# Builds a headless program against the game: tools/build.sh <main.swift> <output binary>
# The game's parts are copied next to the output with @main removed (the program supplies its own top
# level), so several builds can run at once. GAME_SRC picks another version (see env.sh). It builds as
# one job (-wmo), so four builds at once still fit in memory.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
main="$1"
out="$2"
dir="$(dirname "$out")"
mkdir -p "$dir"
copies=()
n=0
while read -r f; do
    n=$((n + 1))
    sed 's/^@main$//' "$f" > "$dir/game_$n.swift"
    copies+=("$dir/game_$n.swift")
done < <(pr_game_files)
LD_LIBRARY_PATH="$PR_LIBS" "$PR_BIN/swiftc" -Onone -wmo "$main" "${copies[@]}" -I "$PR_SHIM" -L "$PR_SHIM" \
    -lSwiftUI -lAVFoundation -o "$out" 2>&1 | grep -E "error" | head -20
test -x "$out"
