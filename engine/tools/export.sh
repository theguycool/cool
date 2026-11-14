#!/bin/bash
# Dumps the Swift game's data and art for the web engine, then packs them into engine/src/data_*.js:
#   engine/tools/export.sh
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/../../tools/env.sh"
pr_need_toolchain
out="${1:-/tmp/prexport-web}"
"$PR_TOOLS/build.sh" "$here/export/main.swift" "$PR_BUILD/webexport/t.bin" || { echo "build failed"; exit 1; }
rm -rf "$out"; mkdir -p "$out"
LD_LIBRARY_PATH="$PR_LIBS" "$PR_BUILD/webexport/t.bin" "$out" || exit 1
[ -f "$here/pack.py" ] && python3 "$here/pack.py" "$out" "$here/../src"
