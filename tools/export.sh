#!/bin/bash
# Exports the game's pixel art, sound effects and data tables for the Godot version:
#   tools/export.sh [output folder]      (default /tmp/prexport)
# then: python3 tools/godot_assets.py /tmp/prexport godot/PixelRealm
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
out="${1:-/tmp/prexport}"
"$PR_TOOLS/build.sh" "$PR_TOOLS/export/main.swift" "$PR_BUILD/export/t.bin" || { echo "build failed"; exit 1; }
mkdir -p "$out"
LD_LIBRARY_PATH="$PR_LIBS" "$PR_BUILD/export/t.bin" "$out"
