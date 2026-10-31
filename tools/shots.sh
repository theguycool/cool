#!/bin/bash
# Renders headless screenshots with the game's own renderer (through the stand-in's rasteriser)
# and saves them as PNG:  tools/shots.sh <weather|power> [output folder]
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
pr_need_toolchain
name="${1:?which shots: $(ls "$PR_TOOLS/shots" | tr '\n' ' ')}"
out="${2:-$PR_BUILD/shots-$name}"
src="$PR_TOOLS/shots/$name/main.swift"
"$PR_TOOLS/build.sh" "$src" "$PR_BUILD/shot-$name/t.bin" || { echo "build failed"; exit 1; }
mkdir -p "$out"
LD_LIBRARY_PATH="$PR_LIBS" "$PR_BUILD/shot-$name/t.bin" "$out"
# the image size is the W and H the shot program declares
size="$(grep -oE 'let W = [0-9]+, H = [0-9]+' "$src" | grep -oE '[0-9]+' | tr '\n' ' ')"
python3 - "$out" $size <<'EOF'
import glob, os, sys
from PIL import Image
folder, w, h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
for f in sorted(glob.glob(os.path.join(folder, "*.rgb"))):
    Image.frombytes("RGB", (w, h), open(f, "rb").read()).save(f[:-4] + ".png")
    os.remove(f)
    print(f[:-4] + ".png")
EOF
