#!/bin/bash
# The hand-drawn art (creatures and blocks at 16 pixels a block): see tools/art/README.md.
#   tools/art.sh preview [folder] [names...]  PNG sheets of the drawings, large and at play size
#   tools/art.sh pack                         writes the drawings into the game's source as text
#   tools/art.sh check                        says whether the game's text matches the drawings
#   tools/art.sh game [folder]                the pictures the game itself ends up with, as raw pixels
#   tools/art.sh compare <old dump> <out.png> [mob|tile]
#                                             a before / after sheet against an older dump (made with
#                                             "game" on an older version: GAME_SRC=<folder> tools/art.sh game)
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cmd="${1:-}"
case "$cmd" in
preview)
    out="${2:-$PR_BUILD/art-preview}"
    shift; shift || true
    python3 "$PR_TOOLS/art/build.py" preview "$out" "$@"
    ;;
pack|check)
    python3 "$PR_TOOLS/art/build.py" "$cmd"
    ;;
game)
    pr_need_toolchain
    out="${2:-$PR_BUILD/art-game}"
    "$PR_TOOLS/build.sh" "$PR_TOOLS/art/dump/main.swift" "$PR_BUILD/artdump/t.bin" || { echo "build failed"; exit 1; }
    mkdir -p "$out"
    LD_LIBRARY_PATH="$PR_LIBS" "$PR_BUILD/artdump/t.bin" "$out"
    ;;
compare)
    old="${2:?the older dump folder}"
    out="${3:?the PNG to write}"
    kind="${4:-mob}"
    new="$PR_BUILD/art-new"
    python3 "$PR_TOOLS/art/build.py" dump "$new" >/dev/null
    python3 "$PR_TOOLS/art/sheets.py" compare "$old" "$new" "$out" "$kind" "$([ "$kind" = tile ] && echo 48 || echo 64)"
    ;;
*)
    sed -n '2,10p' "${BASH_SOURCE[0]}"
    ;;
esac
