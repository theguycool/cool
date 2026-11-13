import SwiftUI
import Foundation
// Step 5a of the overhaul: the sprite editor's see-through colours and painting tools, game creatures
// repainted by a mod, light and time in custom dimensions, suns and moons of a mod's own, tree designs
// in custom dimensions (pass-through, whole across chunk edges, saplings), and the new block collision
// types. The editor screens are compile-checked only (they are SwiftUI); what they call is tested here.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.01) -> Bool { return abs(a - b) <= eps }

let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prmod5-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

func painted(_ w: Int, _ h: Int, _ c: UInt32) -> ModPixels {
    var p = ModPixels(w: w, h: h)
    for y in 0..<h { for x in 0..<w { p.setARGB(x, y, 0xFF000000 | c) } }
    return p
}

/// A flat stone floor at row 100, the given mods on, nothing spawning
func arena(_ packs: [ModPack], seed: UInt64 = 5151) -> Game {
    ModRuntime.activate(packs, world: nil)
    let g = Game(mode: .survival, infinite: true, seed: seed, settings: Settings())
    g.modInfo = ModRuntime.shared.worldInfo()
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 5)
    for x in x0...(x0 + 80) {
        for y in 40..<100 { w.set(x, y, .air); w.setWall(x, y, 0) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.maxHP = 400; g.hp = 400
    g.timeOfDay = 0.25
    g.settings.weatherOn = false
    return g
}
func frame(_ g: Game) { g.applyActButton(); g.tick(1.0 / 60.0) }
func frames(_ g: Game, _ n: Int) { for _ in 0..<n { frame(g) } }
func hold(_ g: Game, _ item: Item, _ n: Int = 1) {
    g.inv.slots[0] = Stack(item: item, count: n)
    g.setSel(0)
}
func aimAt(_ g: Game, _ x: Double, _ y: Double) { g.aimX = x; g.aimY = y; g.aimValid = true }
func use(_ g: Game) {
    g.usePressedFlag = true
    g.useHeld = true
    g.placeCD = 0
    g.useCD = 0
    g.updateUse(1.0 / 60.0)
    g.useHeld = false
}

// ---------------------------------------------------------------- see-through colours and tools
print("== sprite colours and tools")
do {
    var px = ModPixels(w: 8, h: 8)
    px.setARGB(1, 1, 0x80FF0000)
    px.setARGB(2, 2, 0x05FFFFFF)
    check(px.argb(1, 1) == 0x80FF0000, "a half see-through pixel keeps its opacity (\(String(px.argb(1, 1), radix: 16)))")
    check(px.argb(2, 2) == 0, "a pixel almost wholly clear counts as clear")
    check(!px.isBlank && ModPixels(w: 8, h: 8).isBlank, "a picture with only faint pixels is not blank")
    let b: PixelBuf = px.buf()
    check((b.px[1 * 8 + 1] >> 24) == 0x80, "the game's picture of it keeps the opacity")
    if let back = ModPixels.fromSpriteCode(px.spriteCode()) {
        check(back.argb(1, 1) == 0x80FF0000 && back.w == 8, "a sprite code carries see-through pixels")
    } else {
        check(false, "a sprite code carries see-through pixels")
    }
    let big = ModPixels(w: 96, h: 96)
    check(big.valid && !ModPixels(w: 97, h: 4).valid, "pictures up to 96 pixels a side")
    let mix: UInt32 = SpritePaint.over(0x80FF0000, 0xFF0000FF)
    let r: UInt32 = (mix >> 16) & 0xFF
    let bl: UInt32 = mix & 0xFF
    check((mix >> 24) == 0xFF && r > 100 && r < 160 && bl > 100 && bl < 160, "blending half red over blue gives an even purple, still solid (\(String(mix, radix: 16)))")
    check(SpritePaint.over(0x80FF0000, 0) == 0x80FF0000, "blending over a clear pixel keeps the colour's own opacity")
    check((SpritePaint.penColor(0xFF00FF00, 0.5) >> 24) == 0x80, "the pen's opacity scales the colour's")
    var e = ModPixels(w: 4, h: 4)
    e.setARGB(0, 0, 0xFF112233)
    SpritePaint.erase(&e, 0, 0, 0.5)
    check((e.argb(0, 0) >> 24) == 0x80 && (e.argb(0, 0) & 0xFFFFFF) == 0x112233, "a half-strength eraser halves the opacity and keeps the colour")
    SpritePaint.erase(&e, 0, 0, 1.0)
    check(e.argb(0, 0) == 0, "a full eraser clears it")
    var s = ModPixels(w: 4, h: 4)
    s.setARGB(1, 1, 0x80808080)
    SpritePaint.shade(&s, 1, 1, true)
    check((s.argb(1, 1) >> 24) == 0x80 && (s.argb(1, 1) & 0xFF) < 0x80, "shading darkens a pixel and keeps its opacity")
    check(SpritePaint.brushCells(4, 4, 4, false).count == 16 && SpritePaint.brushCells(4, 4, 4, true).count == 12 && SpritePaint.brushCells(4, 4, 1, true).count == 1, "brushes: square, round and single-pixel")
    check(SpritePaint.boxCells((0, 0), (3, 2), false).count == 10 && SpritePaint.boxCells((0, 0), (3, 2), true).count == 12, "boxes, outlined and filled")
    let ring: Int = SpritePaint.ellipseCells((0, 0), (8, 8), false).count
    let disc: Int = SpritePaint.ellipseCells((0, 0), (8, 8), true).count
    check(ring > 16 && disc > ring && disc < 81, "circles, outlined (\(ring)) and filled (\(disc))")
    let line: [(Int, Int)] = PixelEditorView.lineCells((0, 0), (5, 3))
    check(line.first! == (0, 0) && line.last! == (5, 3) && line.count == 6, "lines run from end to end with no gaps or doubled pixels")
    var f = ModPixels(w: 6, h: 6)
    for y in 0..<6 { f.setARGB(3, y, 0xFF000000) }
    PixelEditorView.floodFill(&f, 0, 0, 0xFFFF0000)
    var reds: Int = 0
    for y in 0..<6 { for x in 0..<6 where f.argb(x, y) == 0xFFFF0000 { reds += 1 } }
    check(reds == 18 && f.argb(5, 5) == 0, "fill stops at a wall of another colour (\(reds) filled)")
    let stroke: [StrokeCell] = [StrokeCell(x: 0, y: 0, before: 0), StrokeCell(x: 1, y: 0, before: 0)]
    check(SpritePaint.perfectCorner(stroke, 1, 1) && SpritePaint.perfectCorner([StrokeCell(x: 0, y: 0, before: 0), StrokeCell(x: 0, y: 1, before: 0)], 1, 1) && !SpritePaint.perfectCorner(stroke, 2, 0), "pixel-perfect lines take back the corner of an L, and only there")
    var sel = ModPixels(w: 6, h: 6)
    sel.setARGB(1, 1, 0xFF00FF00)
    let part: ModPixels = SpritePaint.cut(sel, SpriteSel.from((1, 1), (2, 2)))
    SpritePaint.drop(&sel, part, 3, 3)
    check(part.w == 2 && part.argb(0, 0) == 0xFF00FF00 && sel.argb(3, 3) == 0xFF00FF00 && sel.argb(1, 1) == 0xFF00FF00, "a selection is copied and pasted elsewhere")
    // a block with half see-through pixels is drawn as such
    var glass = ModBlock(); glass.id = "gl"; glass.name = "Tinted Glass"; glass.art = painted(8, 8, 0x60A0FF)
    for y in 0..<8 { for x in 0..<8 { glass.art.setARGB(x, y, 0x8060A0FF) } }
    var pk = ModPack(); pk.id = "tint"; pk.name = "Tint"; pk.blocks = [glass]
    _ = ModValidator.check(&pk, known: [:])
    ModRuntime.activate([pk], world: nil)
    if let t = ModRuntime.shared.tileForKey["tint:gl"] {
        let raw: Int = Int(t.rawValue)
        check(SectionPainter.shared.tileKind[raw] == 2 && (SectionPainter.shared.tilePx[raw * 4 * tileArtPx * tileArtPx] >> 24) == 0x80, "the land painter draws a half see-through block as see-through")
    } else {
        check(false, "the land painter draws a half see-through block as see-through")
    }
    ModRuntime.activate([], world: nil)
}

// ---------------------------------------------------------------- creatures repainted
print("== game creatures repainted")
do {
    let before: SpriteSet = Art.shared.creaturePreview(.zombie)
    var p = ModPack(); p.id = "paint"; p.name = "Repaint"
    var o = ModOverride(); o.id = "g1"; o.kind = .creature; o.mob = MobKind.zombie.rawValue
    var f0 = painted(30, 30, 0x40C040)
    f0.setARGB(0, 0, 0x8000FF00)
    o.frames = [f0, painted(30, 30, 0x30B030), painted(30, 30, 0x20A020)]
    p.overrides = [o]
    _ = ModValidator.check(&p, known: [:])
    ModRuntime.activate([p], world: nil)
    let art: [PixelBuf]? = OverrideRT.shared.creatureArt(.zombie, 0)
    check(art?.count == 3, "a mod's three frames replace the zombie's sprite")
    let after: SpriteSet = Art.shared.creaturePreview(.zombie)
    check(after.w != before.w || after.h != before.h, "the zombie is drawn from them (\(before.w)x\(before.h) -> \(after.w)x\(after.h))")
    check(OverrideRT.shared.creatureArt(.skeleton, 0) == nil, "other creatures keep their own")
    ModRuntime.activate([], world: nil)
    let back: SpriteSet = Art.shared.creaturePreview(.zombie)
    check(back.w == before.w && back.h == before.h, "switching the mod off brings the game's sprite back")
    var many = ModOverride(); many.kind = .creature; many.mob = MobKind.pig.rawValue
    var list: [ModPixels] = []
    for k in 0..<14 { list.append(painted(k == 3 ? 12 : 20, 20, 0x808080)) }
    many.frames = list
    ModOverrideCheck.clamp(&many, false)
    check(many.frames?.count == 12 && many.frames!.allSatisfy { $0.w == 20 && $0.h == 20 }, "at most 12 frames, all one size")
}

// ---------------------------------------------------------------- light, time, suns and moons
func skyMod(_ cycle: Bool, _ ceiling: Bool, _ light: Double) -> ModPack {
    var p = ModPack(); p.id = "skies"; p.name = "Skies"
    var d = ModDimension(); d.id = "glim"; d.name = "Glimmer"
    d.cycle = cycle; d.fixedTime = 0.75; d.ceiling = ceiling; d.light = light
    d.surface = 150; d.hills = 4; d.caves = 0; d.sea = 0; d.islands = 0
    d.entry.enabled = false
    p.dims = [d]
    _ = ModValidator.check(&p, known: [:])
    return p
}
print("== light and time in custom dimensions")
do {
    let g = arena([skyMod(true, false, 0.8)])
    g.enterCustomDim(ModRuntime.shared.dimRT(.custom0)!)
    g.timeOfDay = 0.2
    let t0: Double = g.timeOfDay
    frames(g, 300)
    check(g.world.dim == .custom0 && g.timeOfDay > t0 + 0.004, "day and night go on in a custom dimension (the clock used to stop there: \(t0) -> \(g.timeOfDay))")
    g.timeOfDay = 0.25
    let noon: Int = g.skyLevel
    g.timeOfDay = 0.75
    let night: Int = g.skyLevel
    check(noon >= 11 && night >= 4 && night < noon, "it is light by day and dim, not black, by night (sky light \(noon) by day, \(night) by night)")
    let g2 = arena([skyMod(false, false, 0.8)])
    g2.enterCustomDim(ModRuntime.shared.dimRT(.custom0)!)
    let before: Double = g2.timeOfDay
    frames(g2, 120)
    check(g2.dayFactor < 0.1 && g2.skyLevel <= 5 && near(g2.timeOfDay, before, 0.0001), "a dimension without a cycle stays at its own time (midnight here)")
    let g3 = arena([skyMod(false, true, 1.0)])
    g3.enterCustomDim(ModRuntime.shared.dimRT(.custom0)!)
    let bright: Double = g3.ambientLight()
    let g4 = arena([skyMod(false, true, 0.0)])
    g4.enterCustomDim(ModRuntime.shared.dimRT(.custom0)!)
    let dark: Double = g4.ambientLight()
    check(g3.skyLevel == 0 && near(bright, 0.34) && near(dark, 0.12), "a cavern dimension glows as brightly as its light is set (\(bright) at full, \(dark) at none)")
}
print("== suns and moons")
do {
    var p = skyMod(true, false, 0.5)
    var sun = ModSkyBody(); sun.bright = 2.0; sun.size = 1.6
    var moon = ModSkyBody.moon(); moon.bright = 0
    p.dims[0].sunBody = sun
    p.dims[0].moonBody = moon
    let g = arena([p])
    g.enterCustomDim(ModRuntime.shared.dimRT(.custom0)!)
    g.timeOfDay = 0.25
    let strong: Int = g.skyLevel
    g.timeOfDay = 0.75
    let moonless: Int = g.skyLevel
    let g2 = arena([skyMod(true, false, 0.5)])
    g2.enterCustomDim(ModRuntime.shared.dimRT(.custom0)!)
    g2.timeOfDay = 0.25
    let plain: Int = g2.skyLevel
    check(strong == 12 && plain == 8 && moonless == 0, "a brighter sun lights the day more, a dark moon leaves the night black (\(strong) against \(plain), night \(moonless))")
    var ow = ModPack(); ow.id = "ows"; ow.name = "Pale Sun"
    var ps = ModSkyBody(); ps.bright = 0.5; ps.color = 0xFF8040
    ow.skySun = ps
    _ = ModValidator.check(&ow, known: [:])
    let g3 = arena([ow])
    g3.timeOfDay = 0.25
    check(ModRuntime.shared.overSun?.color == 0xFF8040 && g3.skyLevel == 11, "a mod can give the Overworld its own sun (sky light \(g3.skyLevel) at noon)")
    let g4 = arena([])
    g4.timeOfDay = 0.25
    check(ModRuntime.shared.overSun == nil && g4.skyLevel == 15, "and without it the Overworld is as it always was")
    var wild = ModSkyBody()
    wild.size = 40; wild.glow = 9; wild.arc = -1; wild.posX = 3; wild.bright = 7; wild.spin = 9999; wild.path = 5
    wild.art = ModPixels(w: 64, h: 64)
    wild.clamp()
    check(wild.size == 3 && wild.glow == 1 && wild.arc == 0.2 && wild.posX == 1 && wild.bright == 2 && wild.spin == 180 && wild.path == 1 && wild.art.w == 16, "a sun's numbers are kept within what the sky can show")
    let data: Data = try! JSONEncoder().encode(p)
    let back: ModPack = try! JSONDecoder().decode(ModPack.self, from: data)
    check(back.dims[0].sunBody?.bright == 2 && back.dims[0].moonBody?.bright == 0 && back.dims[0].sunBody?.size == 1.6, "a mod's suns and moons are saved with it")
    let old: ModPack = try! JSONDecoder().decode(ModPack.self, from: "{\"id\":\"o\",\"name\":\"Old\",\"dims\":[{\"id\":\"d\",\"name\":\"D\"}]}".data(using: .utf8)!)
    check(old.dims.count == 1 && old.dims[0].sunBody == nil && old.skySun == nil && old.trees.isEmpty, "mods made before keep the game's round sun and moon")
}

// ---------------------------------------------------------------- tree designs
func treeMod() -> ModPack {
    var p = ModPack(); p.id = "woods"; p.name = "Woods"
    var crystal = ModBlock(); crystal.id = "crystal"; crystal.name = "Crystal Wood"; crystal.art = painted(8, 8, 0x80E0FF)
    var glow = ModBlock(); glow.id = "glow"; glow.name = "Glow Leaf"; glow.art = painted(8, 8, 0x60FF90); glow.light = 9
    var moss = ModBlock(); moss.id = "moss"; moss.name = "Blue Moss"; moss.art = painted(8, 8, 0x3060C0)
    p.blocks = [crystal, glow, moss]
    var trees: [ModTree] = []
    for (i, sh) in ModTreeShape.allCases.enumerated() {
        var t = ModTree()
        t.id = "t" + String(i)
        t.name = sh.name
        t.shape = sh
        t.trunk = i % 2 == 0 ? "woods:crystal" : ModGround.key(.logBlock)
        t.leaves = i % 3 == 0 ? "woods:glow" : (i % 3 == 1 ? ModGround.key(.stone) : ModGround.key(.leaves))
        t.crown = 2 + i % 3
        t.branches = i % 3
        t.thick = i == 2
        t.minHeight = 4
        t.maxHeight = 8
        trees.append(t)
    }
    trees[4].ground = "woods:moss"
    trees[5].ground = "woods:moss"
    p.trees = trees
    var d = ModDimension(); d.id = "grove"; d.name = "Grove"
    d.surface = 150; d.hills = 6; d.caves = 0.2; d.sea = 0; d.islands = 0; d.mountains = 0
    d.entry.enabled = false
    var za = ModDimZone(); za.name = "Moss"; za.ground = "woods:moss"; za.trees = 2; za.treeKinds = ["t0", "t1", "t2", "t3", "t4"]
    var zb = ModDimZone(); zb.name = "Glade"; zb.trees = 2; zb.treeKinds = ["t5", "t6", "t7", "t8", "nope"]
    var zc = ModDimZone(); zc.name = "Old"; zc.trees = 2; zc.log = "woods:crystal"; zc.leaves = "woods:glow"
    d.zones = [za, zb, zc]
    d.zoneWidth = 64
    p.dims = [d]
    return p
}
print("== tree designs")
do {
    var pack: ModPack = treeMod()
    let rep: ModReport = ModValidator.check(&pack, known: [:])
    check(pack.trees.count == 9 && pack.dims[0].zones[1].treeKinds == ["t5", "t6", "t7", "t8"] && rep.errors == 0, "a mod with a design of every shape passes its checks (a region's unknown design is dropped)")
    let g = arena([pack])
    let rt: ModRuntime = ModRuntime.shared
    let crystal: Tile = rt.tileForKey["woods:crystal"]!
    let moss: Tile = rt.tileForKey["woods:moss"]!
    let cForm: Tile? = rt.tileForKey["woods:crystal#tree"]
    let gForm: Tile? = rt.tileForKey["woods:glow#leaf"]
    let sForm: Tile? = rt.tileForKey[ModGround.key(.stone) + "#leaf"]
    check(cForm != nil && gForm != nil && sForm != nil, "solid blocks used for trees get pass-through tree forms (mod blocks and game blocks alike)")
    check(rt.tileForKey[ModGround.key(.logBlock) + "#tree"] == nil && rt.treeTile(ModGround.key(.logBlock), 1) == .log, "a log block used as a trunk grows as the game's own trunk")
    if let c = cForm, let gl = gForm, let st = sForm {
        check(!c.solid && !c.isPlatform && !c.opaque && c.name == "Crystal Wood", "a trunk form is passed through, like the game's trunks")
        check(!gl.solid && gl.isPlatform && gl.light == 9 && !st.solid && st.isPlatform, "a leaf form can be stood on but not bumped into, and keeps its light")
        check(g.tileDropStacks(c, 0, 0).first?.item == .block(crystal) && g.tileDropStacks(st, 0, 0).first?.item == .block(.stone), "breaking a tree form gives the block it is made of")
        check(!rt.paletteItems().contains(.block(c)), "tree forms are not offered in the creative palette")
    }
    let info: ModWorldInfo = rt.worldInfo()
    check(info.blocks["woods:crystal#tree"] != nil && info.blocks["woods:crystal"]! < info.blocks["woods:crystal#tree"]!, "tree forms are numbered after the mod's blocks and remembered with the world")
    // the land
    var chunks: [Int: Chunk] = [:]
    for cx in -14...14 { chunks[cx] = generateChunk(g.gen, .custom0, cx) }
    func tileAt(_ x: Int, _ y: Int) -> Tile? {
        guard let ch = chunks[floorDiv(x, chunkW)] else { return nil }
        return ch.get(x - ch.x0, y)
    }
    var walls: Int = 0
    var baseCrystal: Int = 0
    var forms: Int = 0
    var logs: Int = 0
    for (_, ch) in chunks {
        for lx in 0..<chunkW {
            let surf: Int = ch.surf[lx]
            for y in 0..<customDimH {
                let t: Tile = ch.get(lx, y)
                if t == crystal { baseCrystal += 1 }
                if t == cForm || t == gForm || t == sForm { forms += 1 }
                if t == .log { logs += 1 }
                if y < surf && t.solid { walls += 1 }
            }
        }
    }
    check(forms > 300 && logs > 30, "the designs grow there (\(forms) blocks of tree forms, \(logs) of log trunk)")
    check(walls == 0 && baseCrystal == 0, "no tree is a wall: nothing above the ground is solid (\(walls)), and the solid crystal block itself is nowhere")
    let d: ModDimRT = rt.dimRT(.custom0)!
    var seen: [String: Int] = [:]
    var roots: [(Int, ModTreeRT, Int, Int)] = []
    for x in (-14 * chunkW + treeReach)..<(15 * chunkW - treeReach) {
        if let at = d.designTreeAt(x, g.gen.seed, true, 0) {
            seen[at.0.def.id, default: 0] += 1
            roots.append((x, at.0, at.1, at.2))
        }
    }
    let grown: [String] = ["t0", "t1", "t2", "t3", "t4", "t6", "t7", "t8"].filter { (seen[$0] ?? 0) > 0 }
    check(grown.count == 8, "every shape grows (\(seen.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: " ")))")
    check(seen["t5"] == nil, "a design that grows only on moss never grows in the region of grass")
    var missing: Int = 0
    var crossing: Int = 0
    for (x, tr, surf, h) in roots {
        let cells: [TreeCell] = TreeShapes.cells(tr.def, h, hashU(x, 47, g.gen.seed &+ d.salt))
        var cks: Set<Int> = []
        for c in cells {
            let cxw: Int = x + c.dx
            let y: Int = surf - c.dy
            cks.insert(floorDiv(cxw, chunkW))
            if y <= 1 || y >= customDimH - 3 { continue }
            if tileAt(cxw, y) == .air { missing += 1 }
        }
        if cks.count > 1 { crossing += 1 }
    }
    check(crossing > 10 && missing == 0, "trees standing across a chunk's edge are whole on both sides (\(crossing) such trees, \(missing) cells missing)")
    let again: Chunk = generateChunk(g.gen, .custom0, 3)
    check(again.tiles == chunks[3]!.tiles, "and the land is the same every time it is made")
    // the old trees of a region without designs are made of tree forms too
    var oldForm: Int = 0
    for (_, ch) in chunks {
        for lx in 0..<chunkW where d.zoneIndex(ch.x0 + lx) == 2 {
            for y in 0..<customDimH where ch.get(lx, y) == cForm { oldForm += 1 }
        }
    }
    check(oldForm > 10, "a region's own simple trees of a solid block are passed through as well (\(oldForm) blocks)")
    // a sapling grows into a design in its region
    g.enterCustomDim(d)
    var sx: Int = Int(g.pb.x)
    for k in 0..<400 {
        let x: Int = Int(g.pb.x) + (k % 2 == 0 ? k / 2 : -(k / 2))
        if d.zoneIndex(x) == 0 { sx = x; break }
    }
    g.world.loadAround(centerX: sx, radius: 3)
    let gy: Int = d.surfaceAt(sx, g.gen.seed)
    for x in (sx - 10)...(sx + 10) { for y in (gy - 30)..<gy { g.world.set(x, y, .air) } }
    for x in (sx - 10)...(sx + 10) { g.world.set(x, gy, moss) }
    check(g.world.isSoil(moss) && g.world.supports(moss, .sapling), "a sapling takes root in a custom dimension's own ground")
    g.world.set(sx, gy - 1, .sapling)
    let grew: Bool = g.growSapling(sx, gy - 1)
    var treeCells: Int = 0
    for x in (sx - 10)...(sx + 10) {
        for y in (gy - 30)..<gy {
            let t: Tile = g.world.tile(x, y)
            if t != .air { treeCells += 1 }
            if t.solid { treeCells = -9999 }
        }
    }
    check(grew && treeCells > 8 && g.world.tile(sx, gy - 1) != .sapling, "and grows into one of the region's designs, never solid (\(treeCells) cells)")
    // an axe fells a tree form's trunk like a game tree's; its leaves wither and give saplings
    if let c = cForm, let gl = gForm {
        check(isLogTile(c) && isLeafTile(gl) && !isLogTile(crystal) && !isLeafTile(moss), "tree forms count as trunks and leaves (and only they do)")
        let fx: Int = sx + 4
        for y in (gy - 6)..<gy { g.world.set(fx, y, c) }
        g.world.set(fx, gy - 7, gl)
        g.fellTree(fx, gy - 1)
        var left: Int = 0
        for y in (gy - 7)..<gy where g.world.tile(fx, y) != .air { left += 1 }
        check(left == 0, "felling the trunk takes it all, and its crown")
        var saplings: Int = 0
        for _ in 0..<400 {
            for st in g.tileDropStacks(gl, 0, 0) where st.item == .block(.sapling) { saplings += 1 }
        }
        check(saplings > 10 && saplings < 80, "leaves of a mod's tree give saplings about as often as the game's (\(saplings) in 400)")
    }
    // keys follow a renamed mod; another mod's block counts as a dependency
    let re: ModPack = ModStore.rekey(pack, from: "woods", to: "forest")
    check(re.trees[0].trunk == "forest:crystal" && re.trees[4].ground == "forest:moss", "renaming the mod renames the blocks its trees use")
    var dep = ModPack(); dep.id = "other"; dep.name = "Other"
    var t = ModTree(); t.id = "x"; t.leaves = "woods:glow"
    dep.trees = [t]
    check(ModStore.dependencies(dep).contains("woods"), "a tree made of another mod's block needs that mod")
    // the checks
    var bad = ModPack(); bad.id = "bad"; bad.name = "Bad"
    var w = ModTree(); w.id = "w"; w.crown = 50; w.minHeight = 0; w.maxHeight = 99; w.density = 5; w.weight = -3; w.branches = 9
    w.trunk = ModGround.key(.water); w.leaves = "nobody:thing"
    w.grid.cells = [1, 2, 3]
    var many: [ModTree] = [w]
    for k in 0..<14 { var e = ModTree(); e.id = "e" + String(k); many.append(e) }
    bad.trees = many
    let br: ModReport = ModValidator.check(&bad, known: [:])
    let c0: ModTree = bad.trees[0]
    check(bad.trees.count == 12 && br.warnings > 0, "at most 12 designs a mod")
    check(c0.crown == 6 && c0.minHeight == 1 && c0.maxHeight == 24 && c0.density == 1 && c0.weight == 0.1 && c0.branches == 4 && c0.grid.valid, "a design's numbers are kept in range")
    check(c0.trunk == ModGround.key(.log) && c0.leaves == ModGround.key(.leaves), "a liquid or a missing block becomes the game's log and leaves")
    // the editor's preview shows the designs
    let pic: PixelBuf = ModDimPreview.render(pack.dims[0], pack)
    var glowPx: Int = 0
    for c in pic.px where (c & 0xFFFFFF) == 0x60FF90 { glowPx += 1 }
    check(glowPx > 5, "the dimension's preview shows its designs (\(glowPx) pixels of glow leaves)")
    let saved: ModPack = try! JSONDecoder().decode(ModPack.self, from: try! JSONEncoder().encode(pack))
    check(saved.trees == pack.trees && saved.dims[0].zones[0].treeKinds == pack.dims[0].zones[0].treeKinds, "designs are saved with the mod")
    var rg = ModTreeGrid()
    rg.cells[rg.w * (rg.h - 1) + rg.w / 2] = 1
    let wider: ModTreeGrid = rg.resized(13, 16)
    check(wider.valid && wider.at(6, 15) == 1, "a painted design keeps its root at the bottom middle when its size changes")
    // a world keeps its tree forms when the mod changes: the crystal made pass-through, the trees dropped
    var changed: ModPack = pack
    changed.blocks[0].collision = .none
    changed.trees = []
    for k in changed.dims[0].zones.indices { changed.dims[0].zones[k].treeKinds = [] }
    changed.dims[0].zones[2].log = ModGround.key(.log)
    _ = ModValidator.check(&changed, known: [:])
    ModRuntime.activate([changed], world: info)
    let kept: Tile? = ModRuntime.shared.tileForKey["woods:crystal#tree"]
    check(kept == cForm && kept.map { !$0.solid && $0.name == "Crystal Wood" } == true, "a world keeps the tree forms it grew, even once its mod no longer needs them")
    ModRuntime.activate([], world: nil)
}

// ---------------------------------------------------------------- collision types
print("== collision types")
do {
    var p = ModPack(); p.id = "bodies"; p.name = "Bodies"
    var vine = ModBlock(); vine.id = "vine"; vine.name = "Vine"; vine.collision = .climbable; vine.art = painted(8, 8, 0x30A030)
    var goo = ModBlock(); goo.id = "goo"; goo.name = "Goo"; goo.collision = .sticky; goo.art = painted(8, 8, 0xC0A020)
    var fern = ModBlock(); fern.id = "fern"; fern.name = "Fern"; fern.collision = .decor; fern.art = painted(8, 8, 0x20C060)
    p.blocks = [vine, goo, fern]
    _ = ModValidator.check(&p, known: [:])
    let g = arena([p])
    let rt: ModRuntime = ModRuntime.shared
    let vt: Tile = rt.tileForKey["bodies:vine"]!
    let gt: Tile = rt.tileForKey["bodies:goo"]!
    let ft: Tile = rt.tileForKey["bodies:fern"]!
    check(!vt.solid && !gt.solid && !ft.solid && ft.isPlant && !vt.isPlant, "climbable, sticky and decoration blocks are all passed through; a decoration counts as a plant")
    // climbing
    let x: Int = Int(g.pb.x)
    for y in 90..<100 { g.world.set(x, y, vt) }
    g.pb.x = Double(x) + 0.5; g.pb.y = 100; g.pb.vy = 0
    frames(g, 2)
    check(g.ladderColumn() == x, "standing in a climbable block the player is on a ladder")
    g.jumpHeld = true
    frames(g, 80)
    g.jumpHeld = false
    check(g.pb.y < 95, "and climbs it (feet at row \(String(format: "%.1f", g.pb.y)))")
    for y in 90..<100 { g.world.set(x, y, .air) }
    // sticking
    for y in 70..<100 { g.world.set(x + 4, y, gt) }
    g.pb.x = Double(x + 4) + 0.5; g.pb.y = 72; g.pb.vy = 0; g.pb.vx = 0
    frames(g, 60)
    let slowY: Double = g.pb.y
    check(slowY > 72.5 && slowY < 76 && g.pb.vy <= 2.3, "a sticky block slows a fall to a crawl (fell \(String(format: "%.1f", slowY - 72)) blocks in a second)")
    for y in 70..<100 { g.world.set(x + 4, y, .air) }
    g.pb.x = Double(x + 4) + 0.5; g.pb.y = 72; g.pb.vy = 0
    frames(g, 60)
    check(g.pb.y > 85, "without it the player falls far further in that second (to row \(String(format: "%.1f", g.pb.y)))")
    // decoration
    g.pb.x = Double(x) + 0.5; g.pb.y = 100; g.pb.vy = 0
    frames(g, 5)
    g.world.set(x + 2, 99, ft)
    hold(g, .block(.planks), 4)
    aimAt(g, Double(x + 2) + 0.5, 99.5)
    use(g)
    check(g.world.tile(x + 2, 99) == .planks, "building where a decoration stands replaces it, as with flowers")
    // (seven since the liquid was appended in the physics overhaul's phase 3)
    check(ModCollision.allCases.count == 7 && ModCollision.allCases.allSatisfy { !$0.help.isEmpty }, "the block editor explains every kind")
}

ModRuntime.activate([], world: nil)
try? FileManager.default.removeItem(at: scratch)
print("mod5: \(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
