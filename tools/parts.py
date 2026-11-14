#!/usr/bin/env python3
"""Lays the game's sections out over its part files.

The game is one program spread over PixelRealm1.swift ... PixelRealmN.swift. Each part starts with a
header (what it holds, the paragraph about the parts, the imports) and then whole sections, each
starting with a line `// ===== <name> =====`. This tool reads every section from the parts there are
now and writes the parts again from LAYOUT below: which sections go in which part, in that order.
Swift does not care which file holds what, so moving a section only changes how much each file's
build needs (see tools/buildcost.sh); run tools/typecheck.sh and tools/buildcost.sh after a change.

    python3 tools/parts.py          write the parts from LAYOUT
    python3 tools/parts.py --check  only say whether the parts already match LAYOUT
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Which sections go in which part, and what each part is said to hold.
LAYOUT = [
    ("utilities, tiles, items, recipes, the older creature pictures made in code, world generation, chunks,\n// villages and ruins, and automation (turrets, the remote control, signals).",
     ["p01_util", "p02_tiles", "p03_items", "p04_recipes", "p05a_humanoid", "p05e_newcreatures", "p05b_animals",
      "p05c_bosses", "p06_worldgen", "p07_chunk", "p08a_villages", "p08b_ruins", "p35_automation"]),
    ("the Umbral Realm, the world, light and physics, bodies on vehicles, flowing liquids, the land painter,\n// the hand-drawn pictures kept as text, creatures and their kinds, vehicles, the game state, the player,\n// input and tools.",
     ["p09_umbral", "p10_world", "p11_light", "p12_phys", "p12b_frames", "p12c_fluids", "p24_painter", "a01_artsheet",
      "p13a_mobdefs", "p13b_vehicles", "p14a_game", "p14b_player", "p14c_input", "p14d_tools"]),
    ("creature AI, spawning, combat, damage and bosses, ships, the portal and map, saving, helpers, walls and\n// doors, the vehicle screens' logic, vehicles of every kind (flight, weapons, damage, the assembler, the\n// autopilot), and Sparkworks (power).",
     ["p15a_mobai", "p15b_spawn", "p16a_combat", "p16c_damage", "p16b_bosses", "p17_vehicles_ships", "p18_portal_map",
      "p19_save", "p20_assist", "p21_backdrop", "p22_walls_doors", "p23_fast", "p25_hud", "p26_vehicle_ux",
      "p33_vehicles", "p27_power"]),
    ("the Mod Creator's data, checks and runtime, potions and mutation, infusions, the exosuit, building\n// (furniture, stairs, lifts), block physics, and rails and trains.",
     ["p28_mods", "p29_alchemy", "p30_infusion", "p31_exosuit", "p31b_building", "p31c_blockphys", "p31d_rails"]),
    ("Mod Creator+ (game content changes, ore controls, sprite tools, custom infusions, boss phases and\n// summoning, custom dimensions with their suns, moons and trees, the Logic Studio, rules, weather, machines,\n// vehicles and themes in mods), the HUD and the panels.",
     ["p32_modplus", "u03_hud", "u04_panels"]),
    ("the art store and the player's look, sound, weather, ambient and animal life, the journal and\n// telegraphed attacks, the menus, the receiver panel, and the potion and exosuit screens.",
     ["u01_art", "u05_menu", "u10_automation", "u08_alchemy"]),
    ("drawing the world, the Mod Creator screens, joints and mechs (with their panel), and the app itself.",
     ["u02_render", "u07_mods", "p34_joints", "u06_root"]),
    ("the Mod Creator+ screens (with the sprite editor, the sun and moon editor and the tree designer).",
     ["u09_modplus"]),
]

IMPORTS = "import SwiftUI\nimport AVFoundation\n#if canImport(UIKit)\nimport UIKit\n#endif\n"
MARK = re.compile(r"(?m)^// ===== ([A-Za-z0-9_]+) =====\n")
HEADER_LINE = re.compile(r"^(//.*|import \w+|#if canImport\(\w+\)|#endif|\s*)$")


def part_paths():
    return sorted(glob.glob(os.path.join(ROOT, "PixelRealm[0-9].swift")), key=lambda p: int(re.findall(r"(\d+)\.swift$", p)[0]))


def read_sections():
    """Every section by name, in the order the parts hold them now (marker line included)"""
    order, text = [], {}
    for path in part_paths():
        src = open(path).read()
        marks = list(MARK.finditer(src))
        if not marks:
            sys.exit("%s has no sections" % os.path.basename(path))
        head = src[:marks[0].start()]
        for ln in head.split("\n"):
            if not HEADER_LINE.match(ln):
                sys.exit("%s: code before its first section: %r" % (os.path.basename(path), ln))
        for i, m in enumerate(marks):
            end = marks[i + 1].start() if i + 1 < len(marks) else len(src)
            name = m.group(1)
            if name in text:
                sys.exit("section %s appears twice" % name)
            body = src[m.start():end]
            if not body.endswith("\n"):
                body += "\n"
            order.append(name)
            text[name] = body
    return order, text


def header(k, n, what):
    return ("// PIXEL REALM v2, part %d of %d: %s\n"
            "// The game is %s files that go together in one Swift Playgrounds app: PixelRealm1.swift to\n"
            "// PixelRealm%d.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can\n"
            "// hold part 1). The hand-drawn pictures are kept as text in part %d (a01_artsheet).\n\n"
            % (k, n, what, words(n), n, art_part())) + IMPORTS + "\n"


def words(n):
    return {4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine"}.get(n, str(n))


def art_part():
    for k, (_, secs) in enumerate(LAYOUT):
        if "a01_artsheet" in secs:
            return k + 1
    return 1


def build():
    order, text = read_sections()
    placed = [s for _, secs in LAYOUT for s in secs]
    missing = [s for s in order if s not in placed]
    unknown = [s for s in placed if s not in text]
    twice = sorted(set(s for s in placed if placed.count(s) > 1))
    if missing or unknown or twice:
        sys.exit("layout: missing %s, unknown %s, twice %s" % (missing, unknown, twice))
    n = len(LAYOUT)
    out = {}
    for k, (what, secs) in enumerate(LAYOUT):
        body = "".join(text[s].rstrip("\n") + "\n\n" for s in secs).rstrip("\n") + "\n"
        out[os.path.join(ROOT, "PixelRealm%d.swift" % (k + 1))] = header(k + 1, n, what) + body
    return out, text


def main():
    out, text = build()
    old = {p: open(p).read() for p in part_paths()}
    stale = [p for p in old if p not in out]
    if "--check" in sys.argv:
        same = not stale and all(old.get(p) == s for p, s in out.items())
        print("the parts match the layout" if same else "the parts differ from the layout")
        sys.exit(0 if same else 1)
    for p, s in out.items():
        open(p, "w").write(s)
    for p in stale:
        os.remove(p)
    # every section written once, and nothing lost
    _, again = read_sections()
    if set(again) != set(text) or any(again[k].rstrip("\n") != text[k].rstrip("\n") for k in text):
        sys.exit("a section changed while being moved")
    for p in sorted(out):
        print("%s: %d bytes" % (os.path.basename(p), len(out[p])))


if __name__ == "__main__":
    main()
