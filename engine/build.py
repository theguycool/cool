#!/usr/bin/env python3
"""Builds the game page: engine/src/page.html with every script of ORDER put in at its /*SCRIPT*/ mark.
Writes engine/dist/pixel-engine.html (what is published) and engine/dist/test.html (with a doctype)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
# One shared scope: a file can use anything from the files before it, and functions from any file.
ORDER = [
    "data_gen.js",
    "p01_util.js", "p02_tiles.js",
    "p06_worldgen.js", "p07_chunk.js", "p10_world.js", "p11_light.js", "p12_phys.js", "p03_items.js", "p24_painter.js",
    "gl.js", "s01_sound.js", "p14_game.js", "p14d_tools.js", "u02_render.js", "u03_hud.js", "u04_panels.js", "p19_save.js", "u05_menu.js", "u11_stress.js", "main.js",
]
def main():
    page = open(os.path.join(HERE, "src", "page.html")).read()
    parts = []
    for name in ORDER:
        p = os.path.join(HERE, "src", name)
        if not os.path.exists(p):
            sys.exit("missing " + name)
        parts.append("// ===== %s =====\n%s" % (name, open(p).read().rstrip("\n")))
    script = '"use strict";\n' + "\n\n".join(parts) + "\n"
    assert "/*SCRIPT*/" in page
    out = page.replace("/*SCRIPT*/", script)
    os.makedirs(os.path.join(HERE, "dist"), exist_ok=True)
    open(os.path.join(HERE, "dist", "pixel-engine.html"), "w").write(out)
    open(os.path.join(HERE, "dist", "test.html"), "w").write('<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">\n' + out)
    print("built: %d KB, %d lines of script" % (len(out) // 1024, script.count("\n")))
if __name__ == "__main__":
    main()
