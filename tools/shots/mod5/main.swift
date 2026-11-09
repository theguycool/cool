import SwiftUI
import Foundation
// Headless screenshots of step 5a through the game's own renderer: a custom dimension's tree designs
// (every shape, made of the mod's own blocks and passed through) under a sun of its own with rays; the
// same land at night under a pictured moon that stays in one place; the Overworld under a mod's sun;
// a cavern dimension lit as brightly as its light is set; and a zombie repainted by a mod. The Mod
// Creator's screens are SwiftUI and are not drawn here.
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/mod5shots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prmod5shots-" + String(Int.random(in: 1000...999999)), isDirectory: true)
func render(_ g: Game, _ name: String) {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    WorldRenderer.draw(&ctx, CGSize(width: W, height: H), g)
    GraphicsContext.target = nil
    t.save(outDir + "/" + name + ".rgb")
    print("rendered", name)
}
func steps(_ g: Game, _ n: Int) { for _ in 0..<n { g.tick(1.0 / 60.0) } }
/// the camera moved to (x, y), with the light worked out for what it sees
func look(_ g: Game, _ x: Double, _ y: Double) {
    g.camX = x; g.camY = y
    g.updateLight(1.0 / 60.0)
}
func painted(_ c: UInt32) -> ModPixels {
    var p = ModPixels(w: 8, h: 8)
    for y in 0..<8 { for x in 0..<8 { p.setARGB(x, y, 0xFF000000 | (((x * 3 + y * 5) % 7 == 0) ? shadeRGB(c, 0.8) : c)) } }
    return p
}
/// a leafy block: holes and two shades, partly see-through at the edges
func leafy(_ c: UInt32) -> ModPixels {
    var p = ModPixels(w: 8, h: 8)
    for y in 0..<8 {
        for x in 0..<8 {
            let h: Double = hash2(x, y, 77)
            if h < 0.12 { continue }
            let col: UInt32 = h < 0.45 ? shadeRGB(c, 0.78) : (h > 0.9 ? mixRGB(c, 0xFFFFFF, 0.3) : c)
            let edge: Bool = x == 0 || y == 0 || x == 7 || y == 7
            p.setARGB(x, y, (edge && h < 0.3 ? 0xA0000000 : 0xFF000000) | col)
        }
    }
    return p
}
/// a round pixel sun with a face
func sunArt() -> ModPixels {
    var p = ModPixels(w: 16, h: 16)
    for y in 0..<16 {
        for x in 0..<16 {
            let dx: Double = Double(x) - 7.5
            let dy: Double = Double(y) - 7.5
            let r: Double = sqrt(dx * dx + dy * dy)
            if r > 7.6 { continue }
            p.setARGB(x, y, r > 6.4 ? 0xFFE87020 : (r > 4.5 ? 0xFFFFB030 : 0xFFFFE070))
        }
    }
    for (x, y) in [(5, 6), (10, 6), (5, 10), (6, 11), (7, 11), (8, 11), (9, 11), (10, 10)] { p.setARGB(x, y, 0xFF7A3A10) }
    return p
}
/// a ringed planet, its ring half see-through
func planetArt() -> ModPixels {
    var p = ModPixels(w: 24, h: 24)
    for y in 0..<24 {
        for x in 0..<24 {
            let dx: Double = Double(x) - 11.5
            let dy: Double = Double(y) - 11.5
            if dx * dx + dy * dy < 49 {
                let band: Bool = Int(floor((dy + 7) / 2.5)) % 2 == 0
                p.setARGB(x, y, band ? 0xFFB070E0 : 0xFF8A50C0)
            }
            let ring: Double = abs(dy * 3.2 - dx * 0.9)
            if ring < 2.2 && abs(dx) < 11.5 && !(dx * dx + dy * dy < 49 && dy < 0.5) { p.setARGB(x, y, 0xB0F0D8A0) }
        }
    }
    return p
}

func woodsMod() -> ModPack {
    var p = ModPack()
    p.id = "woods"; p.name = "Woods"
    var crystal = ModBlock(); crystal.id = "crystal"; crystal.name = "Crystal Wood"; crystal.art = painted(0x7AC8E8)
    var bark = ModBlock(); bark.id = "bark"; bark.name = "Dusk Bark"; bark.art = painted(0x5A3A6A)
    var glow = ModBlock(); glow.id = "glow"; glow.name = "Glow Leaf"; glow.art = leafy(0x50E880); glow.light = 8
    var rose = ModBlock(); rose.id = "rose"; rose.name = "Rose Leaf"; rose.art = leafy(0xE070A8)
    var gold = ModBlock(); gold.id = "gold"; gold.name = "Gold Leaf"; gold.art = leafy(0xE8C040)
    var moss = ModBlock(); moss.id = "moss"; moss.name = "Blue Moss"; moss.art = painted(0x3A70C8)
    p.blocks = [crystal, bark, glow, rose, gold, moss]
    let looks: [(String, String)] = [("woods:bark", "woods:rose"), ("woods:crystal", "woods:glow"), (ModGround.key(.logBlock), "woods:gold"),
                                     ("woods:bark", "woods:gold"), (ModGround.key(.palmLogBlock), "woods:glow"), ("woods:bark", "woods:rose"),
                                     ("woods:crystal", "woods:glow"), ("woods:crystal", ""), ("woods:bark", "woods:rose")]
    var trees: [ModTree] = []
    for (i, sh) in ModTreeShape.allCases.enumerated() {
        var t = ModTree()
        t.id = "t" + String(i); t.name = sh.name; t.shape = sh
        t.trunk = looks[i].0
        t.leaves = looks[i].1.isEmpty ? ModGround.key(.leaves) : looks[i].1
        t.crown = sh == .tall ? 2 : 3
        t.branches = sh == .bare ? 3 : 1
        t.minHeight = sh == .bush ? 3 : 6
        t.maxHeight = sh == .tall ? 11 : 8
        t.thick = sh == .round
        t.density = 0.92
        trees.append(t)
    }
    p.trees = trees
    var d = ModDimension()
    d.id = "grove"; d.name = "The Glimmer Grove"
    d.skyTop = 0x2E5AA8; d.skyBottom = 0xF0C8E0; d.nightTop = 0x0A0820; d.nightBottom = 0x2A1840
    d.light = 0.9; d.cycle = true
    d.surface = 150; d.hills = 3; d.caves = 0.2; d.sea = 0; d.islands = 0; d.mountains = 0
    d.ambient = 3
    var z = ModDimZone(); z.name = "Grove"; z.ground = "woods:moss"; z.trees = 2; z.treeKinds = trees.map { $0.id }; z.plant = ModGround.key(.tallGrass); z.plantChance = 0.2
    d.zones = [z]
    var sun = ModSkyBody(); sun.art = sunArt(); sun.size = 1.4; sun.glow = 0.7; sun.glowColor = 0xFFC060; sun.rays = true; sun.spin = 12; sun.pulse = 0.5
    var moon = ModSkyBody.moon(); moon.art = planetArt(); moon.size = 2.2; moon.path = 1; moon.posX = 0.72; moon.posY = 0.22; moon.glow = 0.3; moon.glowColor = 0xC0A0FF
    d.sunBody = sun
    d.moonBody = moon
    d.entry.enabled = false
    p.dims = [d]
    _ = ModValidator.check(&p, known: [:])
    return p
}

func game(_ packs: [ModPack], tile: Int) -> Game {
    ModRuntime.activate(packs, world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 5150, settings: Settings(), options: .standard)
    g.modInfo = ModRuntime.shared.worldInfo()
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true; g.godMode = true
    g.settings.weatherOn = false
    g.tilePx = tile
    return g
}

/// A row of trees, one of each design given, on flat ground, in the dimension the player is in
func plantRow(_ g: Game, _ designs: [ModTreeRT], _ x0: Int, _ gy: Int, _ moss: Tile) {
    let w = g.world
    w.loadAround(centerX: x0 + 56, radius: 7)
    for x in (x0 - 40)...(x0 + 150) {
        for y in (gy - 40)..<gy { w.set(x, y, .air); w.setWall(x, y, 0) }
        w.set(x, gy, moss)
        for y in (gy + 1)...(gy + 4) { w.set(x, y, .dirt) }
        if hash2(x, 3, 9) < 0.3 { w.set(x, gy - 1, .tallGrass) }
    }
    for (k, tr) in designs.enumerated() {
        let rx: Int = x0 + k * 14
        let h: Int = (tr.def.minHeight + tr.def.maxHeight) / 2
        var n: Int = 0
        for c in TreeShapes.cells(tr.def, h, UInt64(77 + k)) {
            let t: Tile = w.tile(rx + c.dx, gy - c.dy)
            if t == .air || t.isPlant {
                w.set(rx + c.dx, gy - c.dy, tr.tile(c.part))
                n += 1
            }
        }
        print(tr.def.name, "at", rx - x0, ":", n, "cells")
    }
}

// 1 and 2: every tree shape, by day under the mod's sun, then the same land at night under its moon
do {
    let p: ModPack = woodsMod()
    let g = game([p], tile: 15)
    let d: ModDimRT = ModRuntime.shared.dimSlots[0]!
    g.enterCustomDim(d)
    g.fadeT = 0
    let designs: [ModTreeRT] = d.zones[0].designs
    let moss: Tile = ModRuntime.shared.tileForKey["woods:moss"]!
    let gy: Int = 150
    let x0: Int = Int(g.pb.x) - 28
    plantRow(g, designs, x0, gy, moss)
    g.pb.x = Double(x0) + 21.5; g.pb.y = Double(gy)
    g.timeOfDay = 0.21
    g.freezeTime = true
    steps(g, 20)
    look(g, Double(x0) + 28, Double(gy) - 9)
    render(g, "01_tree_designs_a")
    g.pb.x = Double(x0) + 77.5; g.pb.y = Double(gy)
    steps(g, 5)
    look(g, Double(x0) + 84, Double(gy) - 9)
    render(g, "02_tree_designs_b")
    g.timeOfDay = 0.68
    g.pb.x = Double(x0) + 49.5; g.pb.y = Double(gy)
    steps(g, 20)
    look(g, Double(x0) + 49, Double(gy) - 9)
    render(g, "03_night_planet_moon")
}

// 4: the Overworld under a mod's own sun
do {
    var p = ModPack(); p.id = "ows"; p.name = "Red Giant"
    var s = ModSkyBody(); s.size = 2.2; s.color = 0xFF6A3A; s.glow = 0.9; s.glowColor = 0xFF9A5A; s.rays = true; s.bright = 0.8; s.arc = 0.8
    p.skySun = s
    _ = ModValidator.check(&p, known: [:])
    let g = game([p], tile: 20)
    g.timeOfDay = 0.2
    g.freezeTime = true
    steps(g, 20)
    look(g, g.pb.x, g.pb.y - 8)
    render(g, "04_overworld_red_sun")
}

// 5: a cavern dimension at full light: dim but never black
do {
    var p = ModPack(); p.id = "deep"; p.name = "Deep"
    var lamp = ModBlock(); lamp.id = "shroom"; lamp.name = "Glow Cap"; lamp.art = leafy(0x60D0FF); lamp.light = 10; lamp.collision = .none
    p.blocks = [lamp]
    var d = ModDimension()
    d.id = "hollow"; d.name = "The Hollow"; d.ceiling = true; d.light = 1.0
    d.nightTop = 0x10182A; d.nightBottom = 0x2A3A5A
    d.surface = 190; d.hills = 10; d.caves = 0.3
    var z = ModDimZone(); z.name = "Floor"; z.ground = ModGround.key(.mossGrass); z.plant = "deep:shroom"; z.plantChance = 0.08; z.trees = 0
    d.zones = [z]
    d.entry.enabled = false
    p.dims = [d]
    _ = ModValidator.check(&p, known: [:])
    let g = game([p], tile: 20)
    g.enterCustomDim(ModRuntime.shared.dimSlots[0]!)
    g.fadeT = 0
    steps(g, 30)
    render(g, "05_cavern_lit")
}

// 6: a zombie repainted by a mod (its own frames, blue and half see-through at the hands)
do {
    var p = ModPack(); p.id = "paint"; p.name = "Repaint"
    var o = ModOverride(); o.id = "g1"; o.kind = .creature; o.mob = MobKind.zombie.rawValue
    var frames: [ModPixels] = []
    for b in GameSprites.creatureFrames(.zombie).prefix(4) {
        var m = ModPixels(buf: b)
        for y in 0..<m.h {
            for x in 0..<m.w {
                let c: UInt32 = m.argb(x, y)
                if c == 0 { continue }
                let r: UInt32 = (c >> 16) & 0xFF
                let gg: UInt32 = (c >> 8) & 0xFF
                let bl: UInt32 = c & 0xFF
                m.setARGB(x, y, (c & 0xFF000000) | (bl << 16) | (r << 8) | gg)
            }
        }
        frames.append(m)
    }
    o.frames = frames
    p.overrides = [o]
    _ = ModValidator.check(&p, known: [:])
    let g = game([p], tile: 30)
    g.timeOfDay = 0.3
    g.freezeTime = true
    let w = g.world
    let cx = Int(g.pb.x)
    w.loadAround(centerX: cx, radius: 5)
    for x in (cx - 30)...(cx + 30) {
        for y in 60..<100 { w.set(x, y, .air); w.setWall(x, y, 0) }
        for y in 100..<106 { w.set(x, y, .stone) }
        w.set(x, 100, .grass)
    }
    g.pb.x = Double(cx) - 3.5; g.pb.y = 100
    let a: Mob = g.addMob(.zombie, Double(cx) + 2.5, 100)
    a.persistent = true; a.dir = -1
    let b: Mob = g.addMob(.skeleton, Double(cx) + 6.5, 100)
    b.persistent = true; b.dir = -1
    steps(g, 4)
    look(g, Double(cx) + 1, 96)
    render(g, "06_repainted_zombie")
}
