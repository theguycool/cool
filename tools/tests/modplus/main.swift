import SwiftUI
import Foundation
// Mod Creator+: changes to the game's own content, starting from game content, folders, saved versions,
// dependencies and content switched off; ore generation controls and the hardness reference; the sprite
// studio's data; custom infusions; boss phases and summoning; custom dimensions; Logic Studio. The editor
// screens are compile-checked only (they are SwiftUI); what they call is tested here.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double = 0.01) -> Bool { return abs(a - b) <= eps }

// a scratch folder for the mod store (never the real one)
let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prmodplus-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

func painted(_ w: Int, _ h: Int, _ c: UInt32) -> ModPixels {
    var p = ModPixels(w: w, h: h)
    for y in 0..<h { for x in 0..<w { p.setARGB(x, y, 0xFF000000 | c) } }
    return p
}

/// A flat stone floor at row 100, the given mods on, nothing spawning
func arena(_ packs: [ModPack], mode: GameMode = .survival, seed: UInt64 = 6262) -> Game {
    ModRuntime.activate(packs, world: nil)
    let g = Game(mode: mode, infinite: true, seed: seed, settings: Settings())
    g.modInfo = ModRuntime.shared.worldInfo()
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 5)
    for x in x0...(x0 + 80) {
        for y in 40..<100 { w.set(x, y, .air) }
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
func dummy(_ g: Game, _ k: MobKind, _ x: Double) -> Mob {
    let m: Mob = g.addMob(k, x, 100)
    m.persistent = true
    g.mobGrid.rebuild(g.mobs)
    return m
}

func overrideMod() -> ModPack {
    var p = ModPack()
    p.id = "tweak"
    p.name = "Tweaks"
    var stone = ModOverride()
    stone.id = "g1"; stone.kind = .block; stone.tile = Int(Tile.stone.rawValue)
    stone.hardness = 6; stone.light = 7
    var sword = ModOverride()
    sword.id = "g2"; sword.kind = .item; sword.item = .sword(.iron); sword.damage = 20; sword.reach = 4.0
    var zed = ModOverride()
    zed.id = "g3"; zed.kind = .creature; zed.mob = MobKind.zombie.rawValue; zed.hp = 90; zed.mobDamage = 9
    var pick = ModOverride()
    pick.id = "g4"; pick.kind = .item; pick.item = .tool(.pickaxe, .stone); pick.mineSpeed = 8
    var helm = ModOverride()
    helm.id = "g5"; helm.kind = .item; helm.item = .armor(.head, .iron); helm.defense = 5
    var bread = ModOverride()
    bread.id = "g6"; bread.kind = .item; bread.item = .food(.bread); bread.hunger = 15
    var gun = ModOverride()
    gun.id = "g7"; gun.kind = .item; gun.item = .gun(.pistol); gun.damage = 30
    var offOne = ModOverride()
    offOne.id = "g8"; offOne.kind = .block; offOne.tile = Int(Tile.dirt.rawValue); offOne.hardness = 20; offOne.enabled = false
    p.overrides = [stone, sword, zed, pick, helm, bread, gun, offOne]
    return p
}

// ---------------------------------------------------------------- stage 1
print("== changing game content")
do {
    let stone0: Double = Tile.stone.hardness
    let zombie0: Double = mobDef(.zombie).hp
    let sword0: Double = Item.sword(.iron).melee.damage
    let g = arena([overrideMod()])
    check(near(Tile.stone.hardness, 6) && Tile.stone.light == 7, "a mod changes a game block's hardness and light (stone \(stone0) -> \(Tile.stone.hardness))")
    check(near(Tile.dirt.hardness, Tile.makeDef(.dirt).hard), "a change switched off does nothing")
    check(near(mobDef(.zombie).hp, 90) && near(mobDef(.zombie).dmg, 9), "a mod changes a game creature's health and damage")
    let z: Mob = dummy(g, .zombie, g.pb.x + 5)
    check(near(z.maxHP, 90), "a zombie that appears has the new health (\(z.maxHP))")
    check(near(Item.sword(.iron).melee.damage, 20) && near(Item.sword(.iron).melee.reach, 4.0), "a mod changes a game weapon (iron sword damage \(sword0) -> 20)")
    // the sword really hits that hard
    let pig: Mob = dummy(g, .pig, g.pb.x + 1.6)
    pig.maxHP = 500; pig.hp = 500
    g.inv.slots[0] = Stack(item: .sword(.iron), count: 1)
    g.setSel(0)
    aimAt(g, pig.b.x, pig.b.cy)
    g.facing = 1
    g.swingEmpty(.sword(.iron))
    let dealt: Double = 500 - pig.hp
    check(dealt >= 19.5, "the changed sword deals its new damage in a real swing (\(dealt))")
    check(near(g.inv.defense, 0) && { g.inv.armor[0] = Stack(item: .armor(.head, .iron), count: 1); return near(g.inv.defense, 5) }(), "a mod changes a game armour piece's defence")
    // a changed pickaxe really mines faster
    func mineFrames(_ g: Game) -> Int {
        let tx: Int = Int(g.pb.x) + 1
        g.world.set(tx, 99, .dirt)
        hold(g, .tool(.pickaxe, .stone))
        aimAt(g, Double(tx) + 0.5, 99.5)
        var n: Int = 0
        while g.world.tile(tx, 99) == .dirt && n < 900 {
            g.useCD = 0
            g.updateUse(1.0 / 60.0)
            g.useHeld = true
            n += 1
        }
        return n
    }
    // (nothing in the way: a pickaxe pointed at a creature swings at it instead of digging)
    g.mobs.removeAll()
    g.mobGrid.rebuild(g.mobs)
    g.useHeld = true
    let fastN: Int = mineFrames(g)
    // food
    g.hunger = 2
    hold(g, .food(.bread), 2)
    g.useFood(.bread, true)
    check(near(g.hunger, 17), "a mod changes how much a game food fills (bread 6 -> 15)")
    ModRuntime.deactivate()
    check(near(Tile.stone.hardness, stone0) && Tile.stone.light == Tile.makeDef(.stone).light, "switching the mod off puts the block back exactly")
    check(near(mobDef(.zombie).hp, zombie0) && near(Item.sword(.iron).melee.damage, sword0), "and the creature and the weapon")
    let h = arena([])
    h.useHeld = true
    let slowN: Int = mineFrames(h)
    check(fastN < slowN, "the changed pickaxe mined faster in play (\(fastN) vs \(slowN) frames for dirt)")
    // load order: the later mod wins, field by field
    var a = overrideMod()
    var b = ModPack()
    b.id = "tweak2"
    b.name = "More tweaks"
    var st2 = ModOverride()
    st2.id = "x1"; st2.kind = .block; st2.tile = Int(Tile.stone.rawValue); st2.hardness = 2
    b.overrides = [st2]
    a.overrides = [a.overrides[0]]
    _ = arena([a, b])
    check(near(Tile.stone.hardness, 2) && Tile.stone.light == 7, "two mods changing the same block: the later one wins for what it sets, the rest stays")
    ModRuntime.deactivate()
    // checks
    var bad = ModPack()
    bad.id = "bad"
    bad.name = "Bad"
    var o1 = ModOverride(); o1.kind = .item; o1.item = .gadget(.wrench); o1.damage = 5
    var o2 = ModOverride(); o2.kind = .block; o2.tile = Int(Tile.mod05.rawValue); o2.hardness = 1
    var o3 = ModOverride(); o3.kind = .creature; o3.mob = MobKind.zombie.rawValue; o3.hp = 1_000_000; o3.speed = -5
    bad.overrides = [o1, o2, o3]
    let rep: ModReport = ModValidator.check(&bad, known: [:])
    check(bad.overrides.count == 1 && rep.warnings >= 2, "changes to things that can't be changed are left out with a warning")
    check(bad.overrides[0].hp! <= 4000 && bad.overrides[0].speed! >= 0 && !bad.overrides[0].id.isEmpty, "the numbers of a change are kept in their ranges, and it gets an id")
    // saving keeps it all
    var full = overrideMod()
    full.folder = "Balance"
    full.requires = ["othermod"]
    full.off = ["g2"]
    let back: ModPack = try! JSONDecoder().decode(ModPack.self, from: try! JSONEncoder().encode(full))
    check(back == full, "a mod with changes, a folder, needed mods and content switched off survives a JSON round trip")
}

print("== starting from game content")
do {
    let b: ModBlock = ModBlock.fromGame(.iron)
    check(b.art.buf().px == tileBuf(.iron).px && near(b.hardness, Tile.makeDef(.iron).hard) && b.tier == Tile.makeDef(.iron).tier, "a block started from a game block copies its picture and numbers")
    let it: ModItem = ModItem.fromGame(.sword(.diamond))
    check(it.kind == .melee && near(it.damage, Item.sword(.diamond).melee.damage) && it.baseIcon == .sword(.diamond), "an item started from a game weapon copies its kind, look and numbers")
    let tool: ModItem = ModItem.fromGame(.tool(.pickaxe, .iron))
    check(tool.kind == .tool && tool.toolTier == Tier.iron.rawValue && near(tool.toolSpeed, Tier.iron.mineSpeed), "a tool copies its tier and mining speed")
    let m: ModMob = ModMob.fromGame(.wolf)
    check(m.base == MobKind.wolf.rawValue && near(m.hp, mobDef(.wolf).hp) && m.category == .neutral, "a creature started from a game creature copies its look and numbers")
    // and it works in play
    var p = ModPack()
    p.id = "copies"
    p.name = "Copies"
    var cb: ModBlock = ModBlock.fromGame(.amethystBlock)
    cb.id = "ame"
    p.blocks = [cb]
    var cm: ModMob = ModMob.fromGame(.pig)
    cm.id = "pig2"
    p.mobs = [cm]
    let g = arena([p])
    check(ModRuntime.shared.tile("copies:ame") != nil && ModRuntime.shared.mobSlot["copies:pig2"] != nil, "the copies are real content in a world")
    ModRuntime.deactivate()
    _ = g
}

print("== folders, versions, dependencies, switching content off")
do {
    var a = ModPack()
    a.id = "gems"
    a.name = "Gems"
    a.folder = "Ores"
    var gem = ModItem()
    gem.id = "ruby"; gem.name = "Ruby"; gem.kind = .material
    a.items = [gem]
    var bl = ModBlock()
    bl.id = "ruby_block"; bl.name = "Ruby Block"; bl.art = painted(8, 8, 0xC02040)
    a.blocks = [bl]
    _ = ModStore.save(a)
    var b = ModPack()
    b.id = "smith"
    b.name = "Smithing"
    b.folder = "Crafting"
    var rec = ModRecipe()
    rec.id = "r1"; rec.out = .sword(.iron); rec.cost = [ModCost(.custom("gems:ruby"), 2)]
    b.recipes = [rec]
    _ = ModStore.save(b)
    check(ModStore.folders() == ["Crafting", "Ores"], "mods are filed under folders")
    check(ModStore.dependencies(b) == ["gems"], "a mod that uses another mod's item needs that mod (found by itself)")
    // only the dependent mod on: it is told what is missing, and the recipe that needs it is left out
    let rt: ModRuntime = ModRuntime.activate([b], world: nil)
    check(rt.reports.contains { r in r.issues.contains { $0.text.contains("Gems") } }, "a world without the needed mod says which mod is missing")
    check(rt.recipes.isEmpty, "content that uses the missing mod is left out, nothing breaks")
    let rt2: ModRuntime = ModRuntime.activate([a, b], world: nil)
    check(rt2.recipes.count == 1 && !rt2.reports.contains { r in r.issues.contains { $0.text.contains("Needs the mod") } }, "with both on, it works and nothing is reported")
    // switching one piece of content off
    var a2 = a
    a2.off = ["ruby_block"]
    let rt3: ModRuntime = ModRuntime.activate([a2], world: nil)
    check(rt3.tile("gems:ruby_block") == nil && rt3.item("gems:ruby") != nil, "a block switched off is left out of the world; the rest of the mod stays")
    ModRuntime.deactivate()
    // versions
    check(ModStore.saveVersion(a, label: "First"), "a version is saved")
    var a3 = a
    a3.items[0].name = "Changed Ruby"
    _ = ModStore.save(a3)
    _ = ModStore.saveVersion(a3, label: "Second")
    let vs: [ModVersionInfo] = ModStore.versions("gems")
    check(vs.count == 2 && vs[0].label == "Second" && vs[1].label == "First", "the saved versions are listed, newest first")
    let restored: ModPack? = ModStore.restoreVersion("gems", vs[1].file)
    check(restored?.items.first?.name == "Ruby" && ModStore.pack("gems")?.items.first?.name == "Ruby", "going back to an older version puts it back as the mod")
    let vs2: [ModVersionInfo] = ModStore.versions("gems")
    check(vs2.count == 3 && vs2[0].label.contains("Before restoring"), "and the mod as it was just before is kept as a version too")
    for i in 0..<15 { _ = ModStore.saveVersion(a, label: "v" + String(i)) }
    check(ModStore.versions("gems").count == ModStore.maxVersions, "only the last \(ModStore.maxVersions) versions are kept")
    // ids: an imported mod never overwrites another
    guard let u = ModStore.exportPackage(a), let data = try? Data(contentsOf: u) else { check(false, "the mod can be exported"); exit(1) }
    let imp: (ModPack?, String) = ModStore.importPackage(data)
    check(imp.0 != nil && imp.0!.id != "gems" && ModStore.pack("gems")?.name == "Gems", "importing a mod whose id is taken installs a copy under a new id; the original is untouched")
    if let c = imp.0 { check(c.items.count == 1 && ModStore.dependencies(c).isEmpty, "the copy's content keys point at the copy") }
}

print("== mining times")
do {
    let g = arena([])
    // the reference's numbers are the game's: time a real block break
    for (t, k, tr) in [(Tile.stone, ToolType.pickaxe, Tier.stone), (Tile.dirt, ToolType.shovel, Tier.iron), (Tile.iron, ToolType.pickaxe, Tier.stone), (Tile.planks, ToolType.axe, Tier.wood)] {
        let tx: Int = Int(g.pb.x) + 1
        g.world.set(tx, 99, t)
        hold(g, .tool(k, tr))
        aimAt(g, Double(tx) + 0.5, 99.5)
        var n: Int = 0
        while g.world.tile(tx, 99) == t && n < 2000 { g.mineStep(tx, 99, k, tr, 1.0 / 60.0); n += 1 }
        let measured: Double = Double(n) / 60.0
        let said: Double? = miningSeconds(t, k, tr)
        let broke: Bool = g.world.tile(tx, 99) != t
        if let sv = said {
            check(broke && abs(sv - measured) <= 1.0 / 30.0, "\(t.name) with a \(tr.name.lowercased()) \(k.name.lowercased()): the reference says \(secondsText(said)), mining took \(String(format: "%.2f", measured)) s")
        } else {
            check(!broke, "\(t.name) with a \(tr.name.lowercased()) \(k.name.lowercased()): the reference says it can't, and it couldn't")
        }
    }
    check(miningSeconds(.diamond, .pickaxe, .stone) == nil && miningSeconds(.bedrock, .pickaxe, .voidium) == nil, "the reference knows what a tool can't break")
    check(miningSecondsFor(hardness: 3, tier: 4, blockTool: .pickaxe, unbreakable: false, .pickaxe, 5, toolSpeed: 9) != nil && miningSecondsFor(hardness: 3, tier: 4, blockTool: .pickaxe, unbreakable: false, .pickaxe, 3, toolSpeed: 9) == nil,
          "a custom tool's tier decides whether it breaks a custom block")
}

// ---------------------------------------------------------------- stage 2
print("== ore generation")
/// the ore algorithm exactly as it was before the new controls (to prove old ores still come out the same)
func oldOre(_ o: ModOreRT, _ g: WorldGen, _ ch: Chunk) {
    let H: Int = ch.H
    var rng = RNG(hashU(ch.cx, 0x51ED, g.seed &+ o.salt))
    let whole: Int = Int(o.veins)
    let n: Int = min(24, whole + (rng.double() < o.veins - Double(whole) ? 1 : 0))
    let y0: Int = clampI(o.minY, 1, H - 2)
    let y1: Int = clampI(o.maxY, y0, H - 2)
    var v: Int = 0
    while v < n {
        var lx: Int = rng.int(chunkW)
        var y: Int = y0 + rng.int(y1 - y0 + 1)
        var k: Int = 0
        while k < o.size {
            if modOreHost(ch.get(lx, y), o.host) { ch.setLocal(lx, y, o.tile) }
            switch rng.int(4) {
            case 0: lx = min(chunkW - 1, lx + 1)
            case 1: lx = max(0, lx - 1)
            case 2: y = min(y1, y + 1)
            default: y = max(y0, y - 1)
            }
            k += 1
        }
        v += 1
    }
}
func oreCells(_ ch: Chunk, _ t: Tile) -> [(Int, Int)] {
    var out: [(Int, Int)] = []
    for lx in 0..<chunkW { for y in 0..<ch.H where ch.get(lx, y) == t { out.append((lx, y)) } }
    return out
}
do {
    ModRuntime.deactivate()
    let g = WorldGen(seed: 9191, infinite: true, rareChance: 0.28)
    let marker: Tile = .amethystBlock
    let base = ModOreRT(tile: marker, dim: 0, minY: 140, maxY: 400, veins: 3.5, size: 9, host: 0, salt: 777)
    var same: Bool = true
    var total: Int = 0
    for cx in -6...6 {
        let a: Chunk = generateChunk(g, .overworld, cx)
        let b: Chunk = generateChunk(g, .overworld, cx)
        base.place(g, a)
        oldOre(base, g, b)
        if a.tiles != b.tiles { same = false }
        total += oreCells(a, marker).count
    }
    check(same && total > 50, "an ore with the original settings generates exactly the veins it did before the new controls (\(total) blocks in 13 chunks)")
    func gen(_ o: ModOreRT, _ cxs: ClosedRange<Int> = -8...8) -> [(Chunk, [(Int, Int)])] {
        var out: [(Chunk, [(Int, Int)])] = []
        for cx in cxs {
            let ch: Chunk = generateChunk(g, .overworld, cx)
            o.place(g, ch)
            out.append((ch, oreCells(ch, marker)))
        }
        return out
    }
    var cave = base
    cave.place = 1
    cave.veins = 8
    let cv = gen(cave)
    var caveOK: Bool = true
    var caveN: Int = 0
    for (ch, cells) in cv {
        for (lx, y) in cells {
            caveN += 1
            let open: Bool = (lx > 0 && ch.get(lx - 1, y) == .air) || (lx < chunkW - 1 && ch.get(lx + 1, y) == .air) || ch.get(lx, y - 1) == .air || ch.get(lx, y + 1) == .air
            if !open { caveOK = false }
        }
    }
    check(caveOK && caveN > 0, "an ore set to cave walls only forms beside open air (\(caveN) blocks)")
    var surf = base
    surf.place = 2
    surf.host = 4
    let sv = gen(surf)
    var surfOK: Bool = true
    var surfN: Int = 0
    for (ch, cells) in sv { for (lx, y) in cells { surfN += 1; if y > ch.surf[lx] + 8 || y < ch.surf[lx] - 4 { surfOK = false } } }
    check(surfOK && surfN > 0, "an ore set near the surface forms in the top few blocks of the ground (\(surfN) blocks)")
    var biome = base
    biome.biomes = [Biome.desert.rawValue]
    biome.veins = 6
    var biomeOK: Bool = true
    var biomeN: Int = 0
    for (ch, cells) in gen(biome, -40...40) {
        for (lx, _) in cells {
            biomeN += 1
            if g.col(ch.x0 + lx).biome != .desert { biomeOK = false }
        }
    }
    check(biomeOK, "an ore limited to deserts only forms under deserts (\(biomeN) blocks)")
    var rare = base
    rare.rarity = 0.3
    var withOre: Int = 0
    let chunks: Int = 160
    for cx in 0..<chunks {
        let ch: Chunk = generateChunk(g, .overworld, cx)
        rare.place(g, ch)
        if !oreCells(ch, marker).isEmpty { withOre += 1 }
    }
    let frac: Double = Double(withOre) / Double(chunks)
    check(frac > 0.18 && frac < 0.42, "an ore with a 30% chance turns up in about 30% of stretches of ground (\(String(format: "%.2f", frac)))")
    var host = base
    host.hostTiles = [Tile.stone.rawValue]
    var hostOK: Bool = true
    for cx in -4...4 {
        let before: Chunk = generateChunk(g, .overworld, cx)
        let after: Chunk = generateChunk(g, .overworld, cx)
        host.place(g, after)
        for (lx, y) in oreCells(after, marker) where before.get(lx, y) != .stone { hostOK = false }
    }
    check(hostOK, "an ore given exact host blocks only replaces those blocks")
    var nearOre = base
    nearOre.nearTile = .iron
    nearOre.veins = 6
    nearOre.size = 3
    var nearOK: Bool = true
    var nearN: Int = 0
    for (ch, cells) in gen(nearOre) {
        for (lx, y) in cells {
            nearN += 1
            var found: Bool = false
            for dy in -6...6 { for dx in -6...6 where lx + dx >= 0 && lx + dx < chunkW && ch.get(lx + dx, y + dy) == .iron { found = true } }
            if !found { nearOK = false }
        }
    }
    check(nearOK, "an ore set to form near iron is always close to iron (\(nearN) blocks)")
    var scatter = base
    scatter.shape = 2
    scatter.veins = 4
    var lone: Int = 0
    for (ch, cells) in gen(scatter) {
        for (lx, y) in cells {
            var touching: Bool = false
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where lx + dx >= 0 && lx + dx < chunkW && ch.get(lx + dx, y + dy) == marker { touching = true }
            if !touching { lone += 1 }
        }
    }
    check(lone > 10, "a scattered ore leaves single blocks apart from each other (\(lone))")
    // the editor's preview runs the same generator
    var mo = ModOre()
    mo.id = "o1"; mo.minY = 140; mo.maxY = 400; mo.veins = 3; mo.size = 8
    var pk = ModPack()
    pk.id = "prev"
    let pr: (PixelBuf, Int) = ModOrePreview.render(mo, pk)
    check(pr.0.w == ModOrePreview.chunks * chunkW && pr.1 > 0 && pr.0.px.contains { $0 & 0xFFFFFF == 0xFF40FF }, "the generation preview shows where the ore forms (\(pr.1) blocks in the sample)")
    var none = mo
    none.biomes = [Biome.umbral.rawValue]
    check(ModOrePreview.render(none, pk).1 == 0, "and shows none when its rules rule out the sample world")
    // checks and saving
    var bad = ModPack()
    bad.id = "badore"
    var o = ModOre()
    o.id = "o"; o.place = 9; o.shape = -3; o.rarity = 7; o.hosts = ["tile:3", "tile:999", "nope:x"]; o.near = "ghost:ore"; o.biomes = [99, Biome.forest.rawValue]
    bad.ores = [o]
    _ = ModValidator.check(&bad, known: [:])
    let c: ModOre = bad.ores[0]
    check(c.place == 3 && c.shape == 0 && c.rarity == 1 && c.hosts == ["tile:3"] && c.near.isEmpty && c.biomes == [Biome.forest.rawValue], "the new ore settings are kept in range and broken references are cleared")
    let back: ModOre = try! JSONDecoder().decode(ModOre.self, from: try! JSONEncoder().encode(c))
    check(back == c, "the new ore settings survive a JSON round trip")
}

// ---------------------------------------------------------------- stage 3
print("== sprite studio")
do {
    var a = ModPixels(w: 12, h: 9)
    for y in 0..<9 { for x in 0..<12 where (x * 3 + y) % 4 != 0 { a.setARGB(x, y, 0xFF000000 | UInt32(x * 20) << 16 | UInt32(y * 25)) } }
    check(a.flippedH().flippedH() == a && a.flippedV().flippedV() == a, "flipping twice gives the picture back")
    check(a.flippedH().argb(0, 3) == a.argb(11, 3), "flipping mirrors left and right")
    check(a.shifted(5, -2).shifted(-5, 2) == a, "shifting wraps round the edges and loses nothing")
    check(a.rotated().w == 9 && a.rotated().h == 12 && a.rotated().rotated().rotated().rotated() == a, "a quarter turn swaps the sides; four of them give it back")
    let big: ModPixels = a.scaled(24, 18)
    check(big.w == 24 && big.argb(2, 2) == a.argb(1, 1) && big.argb(23, 17) == a.argb(11, 8), "stretching doubles each pixel")
    check(a.resized(16, 16).argb(2, 7) == a.argb(0, 0), "keeping the picture at a bigger size centres it at the bottom")
    // sprite codes
    var o = a
    o.outline = false
    let code: String = o.spriteCode()
    check(ModPixels.fromSpriteCode(code) == o, "a sprite code brings the picture back exactly, outline choice and all")
    check(ModPixels.fromSpriteCode("hello") == nil && ModPixels.fromSpriteCode("PRSPR1:99x99:o:AAAA") == nil && ModPixels.fromSpriteCode("PRSPR1:2x2:o:AAAA") == nil,
          "damaged or made-up codes are refused")
    // pictures from elsewhere, shrunk by averaging
    var bytes: [UInt8] = []
    for y in 0..<4 { for x in 0..<4 { bytes += (x < 2 && y < 2) ? [255, 0, 0, 255] : [0, 0, 0, 0] } }
    let small: ModPixels = ModPixels.fromRGBA(bytes, 4, 4, 2, 2)
    check(small.argb(0, 0) == 0xFFFF0000 && small.argb(1, 1) == 0, "a picture shrunk to the sprite's size keeps its colours and its see-through parts")
    // the clipboard: a code, and a picture
    SpriteClipboard.copy(o)
    check(SpriteClipboard.pasteCode() == o, "a sprite copied to the clipboard pastes back")
    var px: [UInt32] = [UInt32](repeating: 0, count: 8 * 8)
    for i in 0..<64 { px[i] = i % 8 < 4 ? 0xFF2080F0 : 0xFFF0C020 }
    if let cg = makeCGImage(px, 8, 8) {
        UIPasteboard.general.image = UIImage(cgImage: cg)
        let pasted: ModPixels? = SpriteClipboard.pasteImage(4, 4)
        check(pasted != nil && pasted!.argb(0, 0) & 0xFFFFFF == 0x2080F0 && pasted!.argb(3, 0) & 0xFFFFFF == 0xF0C020, "a picture copied from another app is pasted in at the sprite's size")
    } else {
        check(false, "a test picture can be made")
    }
    // drawing helpers
    let line: [(Int, Int)] = PixelEditorView.lineCells((0, 0), (5, 3))
    check(line.first! == (0, 0) && line.last! == (5, 3) && line.count == 6, "a line runs from one end to the other without gaps")
    check(Set(PixelEditorView.boxCells((1, 1), (4, 3)).map { $0.0 * 100 + $0.1 }).count == 10, "a box is drawn along its four sides")
    var fill = ModPixels(w: 6, h: 6)
    for i in 0..<6 { fill.setARGB(3, i, 0xFF000000) }
    PixelEditorView.floodFill(&fill, 0, 0, 0xFFFF0000)
    check(fill.argb(2, 5) == 0xFFFF0000 && fill.argb(4, 0) == 0, "fill stops at a line")
    // the outline switch reaches the game's pictures
    var it = ModItem()
    it.id = "gem"; it.name = "Gem"; it.kind = .material
    it.icon = ModPixels(w: 16, h: 16)
    for y in 5..<11 { for x in 5..<11 { it.icon.setARGB(x, y, 0xFFC02040) } }
    var p = ModPack()
    p.id = "art"
    p.items = [it]
    var m = ModMob()
    m.id = "blob"; m.name = "Blob"; m.customArt = true
    var f = ModPixels(w: 16, h: 16)
    for y in 4..<12 { for x in 4..<12 { f.setARGB(x, y, 0xFF40C060) } }
    f.outline = false
    m.frames = [f]
    p.mobs = [m]
    let rt: ModRuntime = ModRuntime.activate([p], world: nil)
    let withOutline: PixelBuf = rt.itemIconBuf(it)
    var plain = it
    plain.icon.outline = false
    let without: PixelBuf = rt.itemIconBuf(plain)
    check(withOutline.px.contains { $0 & 0xFFFFFF == 0x1A1410 } && !without.px.contains { $0 & 0xFFFFFF == 0x1A1410 }, "an item's icon has an outline or not, as chosen for it")
    let frs: [PixelBuf] = modMobFrames(m).0
    check(!frs[0].px.contains { $0 & 0xFFFFFF == 0x101010 }, "a creature drawn without an outline has none")
    ModRuntime.deactivate()
    let json: String = String(data: try! JSONEncoder().encode(a), encoding: .utf8)!
    check(!json.contains("outline"), "pictures that never chose leave no trace in the file (old mods stay the same)")
    // the library
    var sp = SpriteProject()
    sp.name = "Knight"
    sp.frames = [a, a.flippedH()]
    let saved: SpriteProject = SpriteLibrary.put(sp)
    check(!saved.id.isEmpty && SpriteLibrary.load().first?.name == "Knight" && SpriteLibrary.load().first?.frames.count == 2, "a sprite is kept in the library with its frames")
    let copy: SpriteProject? = SpriteLibrary.duplicate(saved.id)
    check(copy != nil && copy!.id != saved.id && SpriteLibrary.load().count == 2, "library sprites can be copied")
    SpriteLibrary.delete(saved.id)
    check(SpriteLibrary.load().count == 1 && SpriteLibrary.load()[0].name.contains("copy"), "and deleted")
    check(GameSprites.creatureFrames(.zombie).count >= 3 && !GameSprites.items().isEmpty && GameSprites.tiles().contains(.stone), "every game creature, item and block can be picked as a reference")
    check(ModPixels.fitted(GameSprites.creatureFrames(.zombie)[0], 16, 16).w == 16, "a game sprite can be copied in as a sample at any size")
}

// ---------------------------------------------------------------- stage 4
print("== custom infusions")
func infusionMod() -> ModPack {
    var p = ModPack()
    p.id = "infx"
    p.name = "Infusions"
    var fury = ModInfusion()
    fury.id = "fury"; fury.name = "Fury"; fury.classes = [InfuseClass.melee.rawValue]
    fury.damagePct = 50; fury.burn = 3; fury.lifeSteal = 10
    fury.trigger = .onHit; fury.effect = ModEffect(.speed, 25, 6); fury.effectCooldown = 10
    var ward = ModInfusion()
    ward.id = "ward"; ward.name = "Ward"; ward.classes = [InfuseClass.armor.rawValue]
    ward.defense = 3; ward.fireCut = 30; ward.regen = 6; ward.trigger = .whenHurt; ward.effect = ModEffect(.strength, 40, 5)
    var dig = ModInfusion()
    dig.id = "dig"; dig.name = "Dig"; dig.classes = [InfuseClass.tool.rawValue]; dig.miningPct = 100
    var bolt = ModInfusion()
    bolt.id = "bolt"; bolt.name = "Bolt"; bolt.classes = [InfuseClass.ranged.rawValue]; bolt.damageFlat = 4; bolt.poison = 4
    var only = ModInfusion()
    only.id = "only"; only.name = "Only Iron"; only.classes = []; only.items = [.sword(.iron)]; only.damageFlat = 2
    var twice = ModInfusion()
    twice.id = "twice"; twice.name = "Twice"; twice.stack = 2; twice.damageFlat = 1
    var saver = ModInfusion()
    saver.id = "saver"; saver.name = "Saver"; saver.classes = [InfuseClass.suit.rawValue]; saver.energyPct = 50
    var mult = ModInfusion()
    mult.id = "mult"; mult.name = "Mult"; mult.multiply = true; mult.damagePct = 50
    p.infusions = [fury, ward, dig, bolt, only, twice, saver, mult]
    var r = ModRecipe()
    r.id = "furyR"; r.out = .custom("infx:fury"); r.count = 1; r.cost = [ModCost(.mat(.coal), 2)]; r.station = Station.infuser.rawValue
    p.recipes = [r]
    let rep: ModReport = ModValidator.check(&p, known: [:])
    _ = rep
    return p
}
do {
    let pack: ModPack = infusionMod()
    check(pack.infusions.count == 8 && pack.infusions[0].id == "fury" && pack.infusions[4].items == [.sword(.iron)], "a mod of eight infusions passes its checks unchanged")
    let g = arena([pack])
    let rt: ModRuntime = ModRuntime.shared
    let nFury: Int = rt.infusionNumber["infx:fury"] ?? -1
    let nWard: Int = rt.infusionNumber["infx:ward"] ?? -1
    let nDig: Int = rt.infusionNumber["infx:dig"] ?? -1
    let nBolt: Int = rt.infusionNumber["infx:bolt"] ?? -1
    let nOnly: Int = rt.infusionNumber["infx:only"] ?? -1
    let nTwice: Int = rt.infusionNumber["infx:twice"] ?? -1
    let nSaver: Int = rt.infusionNumber["infx:saver"] ?? -1
    let nMult: Int = rt.infusionNumber["infx:mult"] ?? -1
    let all: [Int] = [nFury, nWard, nDig, nBolt, nOnly, nTwice, nSaver, nMult]
    check(Set(all).count == 8 && all.allSatisfy { $0 >= customInfusionBase } && nFury == customInfusionBase, "each infusion gets its own number, apart from the game's own (\(all))")
    check(Item.custom("infx:fury").name == "Fury Compound" && rt.item("infx:fury")?.def.kind == .material, "each infusion has a compound, an item of the mod")
    let icon: PixelBuf = rt.item("infx:fury")!.icon
    check(icon.px.contains { $0 & 0xFFFFFF == 0x60E0FF }, "a compound with no picture of its own is a phial in the infusion's colour")
    check(RecipeBook.all.contains { $0.out == .custom("infx:fury") && $0.station == .infuser }, "a recipe makes the compound at the Infusion Crucible")
    check(rt.infusion(nFury)!.def.blurb.contains("+50% damage") && rt.infusion(nFury)!.def.blurb.contains("sets alight"), "an infusion describes itself in a line (\(rt.infusion(nFury)!.def.blurb))")
    // infusing at the crucible
    g.inv.slots[5] = Stack(item: .sword(.iron), count: 1)
    let need: String = g.infuseCustom(slot: 5, nFury)
    check(need.contains("need") && g.inv.slots[5]?.inf == nil, "without a compound nothing happens (\(need))")
    g.inv.slots[8] = Stack(item: .custom("infx:fury"), count: 2)
    let done: String = g.infuseCustom(slot: 5, nFury)
    check(g.inv.slots[5]?.inf == [nFury] && g.inv.total(.custom("infx:fury")) == 1, "infusing works it into the item and uses one compound (\(done))")
    let again: String = g.infuseCustom(slot: 5, nFury)
    check(g.inv.slots[5]?.inf == [nFury] && g.inv.total(.custom("infx:fury")) == 1, "an item holds an infusion only as many times as it allows (\(again))")
    g.inv.slots[9] = Stack(item: .custom("infx:ward"), count: 1)
    let wrong: String = g.infuseCustom(slot: 5, nWard)
    check(g.inv.slots[5]?.inf == [nFury] && g.inv.total(.custom("infx:ward")) == 1, "an armour infusion doesn't go on a sword, and its compound is kept (\(wrong))")
    check(Stack(item: .sword(.stone), count: 1).customProblem(rt.infusion(nOnly)!) != nil && Stack(item: .sword(.iron), count: 1).customProblem(rt.infusion(nOnly)!) == nil,
          "an infusion for chosen items goes on those and nothing else")
    let mythril = Stack(item: .sword(.mythril), count: 1, extra: 0, inf: [nTwice])
    check(mythril.customProblem(rt.infusion(nTwice)!) == nil && Stack(item: .sword(.mythril), count: 1, extra: 0, inf: [nTwice, nTwice]).customProblem(rt.infusion(nTwice)!) != nil,
          "an infusion allowed twice goes on twice, and no more")
    check(Stack(item: .sword(.stone), count: 1, extra: 0, inf: [Infusion.honed.rawValue]).customProblem(rt.infusion(nFury)!) != nil, "it needs a free slot, shared with the game's own infusions")
    check(Stack(item: .mat(.coal), count: 4).customProblem(rt.infusion(nFury)!) != nil, "materials can't be infused")
    check(Stack(item: .sword(.iron), count: 1, extra: 0, inf: [Infusion.honed.rawValue, nFury]).infusionNames == ["Honed", "Fury"], "the item's description names custom infusions with the game's own")
    _ = g.removeCustomInfusion(slot: 5, nFury)
    check(g.inv.slots[5]?.inf == nil && g.inv.slots[5]?.item == .sword(.iron), "an infusion can be drawn out again, the item unharmed")
    // in a real swing
    let base: MeleeProfile = Item.sword(.iron).melee
    check(near(Game.infuseProfile(base, [nFury]).damage, base.damage * 1.5) && near(Game.infuseProfile(base, [nMult]).damage, base.damage * 1.5), "+50% damage, added or multiplied, on its own")
    check(near(Game.infuseProfile(base, [nFury, nMult]).damage, base.damage * 2.25) && near(Game.infuseProfile(base, [nOnly, nTwice]).damage, base.damage + 3),
          "a multiplying infusion multiplies what the others give; flat damage adds")
    let pig: Mob = dummy(g, .pig, g.pb.x + 1.6)
    pig.maxHP = 500; pig.hp = 500
    g.inv.slots[0] = Stack(item: .sword(.iron), count: 1, extra: 0, inf: [nFury])
    g.setSel(0)
    aimAt(g, pig.b.x, pig.b.cy)
    g.facing = 1
    g.hp = 200
    g.effects.clear()
    check(near(g.infusedMelee(.sword(.iron)).damage, base.damage * 1.5), "the held sword swings with the infusion's numbers")
    g.swingEmpty(.sword(.iron))
    let dealt: Double = 500 - pig.hp
    check(dealt >= base.damage * 1.5 - 0.01, "a real swing hits 50% harder (\(base.damage) -> \(dealt))")
    check(pig.burn >= 2.9, "it sets what it hits alight")
    check(g.hp > 200, "and heals back a share of the blow (\(g.hp - 200))")
    check(near(g.effects.value(.speed), 25), "its effect is given when it hits (speed \(g.effects.value(.speed)))")
    g.effects.clear()
    g.customTrigger(rt.infusion(nFury)!)
    check(near(g.effects.value(.speed), 0), "but no more often than its rest allows")
    g.infTriggerCD[nFury] = g.clock - 11
    g.customTrigger(rt.infusion(nFury)!)
    check(near(g.effects.value(.speed), 25), "and again once the rest is over")
    // armour
    g.inv.armor[0] = Stack(item: .armor(.head, .iron), count: 1)
    let d0: Double = g.totalDefense
    g.inv.armor[0] = Stack(item: .armor(.head, .iron), count: 1, extra: 0, inf: [nWard])
    check(near(g.totalDefense, d0 + 3) && near(g.armorInf.fireCut, 0.3) && near(g.armorInf.regen, 0.1), "worn, it adds defence, fire protection and healing (\(d0) -> \(g.totalDefense))")
    g.hp = 100
    g.invuln = 0
    g.effects.clear()
    var fire = DamageInfo(amount: 10, type: .fire, source: .environment)
    fire.originX = g.pb.x
    _ = g.hurtPlayer(fire)
    check(near(100 - g.hp, 7, 0.05), "fire hurts 30% less (10 -> \(100 - g.hp))")
    check(near(g.effects.value(.strength), 40), "an infusion that answers being hurt gives its effect")
    // tools
    func mineFrames(_ inf: [Int]) -> Int {
        let h = arena([pack])
        let tx: Int = Int(h.pb.x) + 1
        h.world.set(tx, 99, .stone)
        h.inv.slots[0] = Stack(item: .tool(.pickaxe, .stone), count: 1, extra: 0, inf: inf.isEmpty ? nil : inf)
        h.setSel(0)
        aimAt(h, Double(tx) + 0.5, 99.5)
        var n: Int = 0
        while h.world.tile(tx, 99) == .stone && n < 600 { h.mineStep(tx, 99, .pickaxe, .stone, 1.0 / 60.0); n += 1 }
        return n
    }
    let slow: Int = mineFrames([])
    let fast: Int = mineFrames([nDig])
    check(Double(fast) < Double(slow) * 0.6, "a mining infusion mines twice as fast (\(slow) -> \(fast) frames)")
    // shots
    let s = arena([pack])
    s.inv.slots[0] = Stack(item: .gun(.pistol), count: 1, extra: 6, inf: [nBolt])
    s.setSel(0)
    var shot = Projectile(kind: .bullet, x: s.pb.x + 0.6, y: s.pb.y - 1.0, vx: 30, vy: 0, dmg: 10, fromPlayer: true, gravity: 0)
    shot.source = .player
    shot.uid = s.newID()
    s.infuseShot(&shot, .gun(.pistol))
    check(near(shot.dmg, 14) && shot.custom == [nBolt], "a ranged infusion adds to the shot's damage (10 -> \(shot.dmg))")
    // (a pig: the undead shrug off poison)
    let target: Mob = dummy(s, .pig, s.pb.x + 5)
    target.maxHP = 200; target.hp = 200
    shot.y = target.b.cy
    s.projectiles = [shot]
    var n: Int = 0
    while !s.projectiles.isEmpty && n < 120 { s.tick(1.0 / 60.0); n += 1 }
    check(target.hp < 200 && target.poisonT > 0, "the shot lands and poisons what it hits (\(200 - target.hp) damage)")
    // the suit
    check(near(customEnergyMul(Stack(item: .exoCore(.dynamo), count: 1, extra: 0, inf: [nSaver])), 0.5), "an infusion on a suit core halves the energy it uses")
    // saved with the world
    let sv = arena([pack])
    sv.inv.slots[0] = Stack(item: .sword(.iron), count: 1, extra: 0, inf: [nFury, Infusion.keen.rawValue])
    sv.setSel(0)
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(sv.makeSave()))
    check(back.mods?.infusions["infx:fury"] == nFury, "a save remembers each custom infusion's number")
    var other = ModPack()
    other.id = "aaa"; other.name = "Other"
    var o1 = ModInfusion(); o1.id = "x"; o1.name = "X"
    var o2 = ModInfusion(); o2.id = "y"; o2.name = "Y"
    other.infusions = [o1, o2]
    ModRuntime.activate([other, pack], world: back.mods)
    let g2 = Game.load(back, settings: Settings())
    g2.setSel(0)
    let ox: Int = ModRuntime.shared.infusionNumber["aaa:x"] ?? -1
    check(ModRuntime.shared.infusionNumber["infx:fury"] == nFury && !all.contains(ox) && ox >= customInfusionBase, "loaded with another mod added first, the infusion keeps its number (\(nFury)); the new one gets a free one (\(ox))")
    check(g2.inv.slots[0]?.inf == [nFury, Infusion.keen.rawValue] && near(g2.infusedMelee(.sword(.iron)).damage, base.damage * 1.5), "the sword comes back holding it, and it still works")
    ModRuntime.activate([], world: back.mods)
    let g3 = Game.load(back, settings: Settings())
    g3.setSel(0)
    check(g3.inv.slots[0]?.inf == [nFury, Infusion.keen.rawValue] && infusionName(nFury) == "Missing infusion" && near(g3.infusedMelee(.sword(.iron)).damage, base.damage),
          "with the mod missing the item keeps it (marked missing, doing nothing)")
    let resave: SaveData = g3.makeSave()
    check(resave.mods?.infusions["infx:fury"] == nFury, "saving without the mod keeps its number, so nothing is forgotten")
    // switched off
    var offPack: ModPack = pack
    offPack.off = ["fury"]
    _ = arena([offPack])
    check(ModRuntime.shared.infusionNumber["infx:fury"] == nil && ModRuntime.shared.item("infx:fury") == nil && ModRuntime.shared.infusionNumber["infx:ward"] != nil,
          "an infusion switched off is left out, the rest stay")
    ModRuntime.deactivate()
    // checks
    var bad = ModPack()
    bad.id = "badinf"
    var gem = ModItem(); gem.id = "gem"; gem.name = "Gem"; gem.kind = .material
    bad.items = [gem]
    var f = ModInfusion()
    f.id = "gem"; f.name = "  "; f.damagePct = 9999; f.stack = 9; f.classes = [7, 2]; f.items = [.mat(.coal), .sword(.iron)]
    f.burn = 99; f.effectCooldown = 0; f.sparkChance = 5; f.effect = ModEffect(.speed, 900, 9999); f.reach = .infinity
    bad.infusions = [f] + (0..<30).map { i in var x = ModInfusion(); x.id = "n" + String(i); return x }
    _ = ModValidator.check(&bad, known: [:])
    let c: ModInfusion = bad.infusions[0]
    check(bad.infusions.count == 24, "only 24 infusions fit in one mod")
    check(c.id != "gem" && !c.id.isEmpty, "an infusion can't share its id with an item of the same mod (\(c.id))")
    check(c.name == "Infusion" && near(c.damagePct, 100) && c.stack == 3 && c.classes == [2] && c.items == [.sword(.iron)] && near(c.burn, 8) && near(c.effectCooldown, 2) && near(c.sparkChance, 0.4) && near(c.reach, 0),
          "every number is kept in range and broken settings are cleared")
    check(c.effect.amount <= 60 && c.effect.seconds <= ModRange.seconds.hi, "its effect is kept in range too")
    let rt2: ModInfusion = try! JSONDecoder().decode(ModInfusion.self, from: try! JSONEncoder().encode(c))
    check(rt2 == c, "an infusion survives a JSON round trip")
    let json: String = String(data: try! JSONEncoder().encode(c), encoding: .utf8)!.lowercased()
    check(!json.contains("durab"), "infusions have no durability settings (the game has none)")
    let oldMod: ModPack = try! JSONDecoder().decode(ModPack.self, from: "{\"id\":\"old\",\"name\":\"Old\"}".data(using: .utf8)!)
    check(oldMod.infusions.isEmpty, "a mod from before has no infusions and loads as it was")
}

// ---------------------------------------------------------------- stage 5
func bossMod() -> ModPack {
    var p = ModPack()
    p.id = "bossy"
    p.name = "Bosses"
    var totem = ModItem(); totem.id = "totem"; totem.name = "Storm Totem"; totem.kind = .material
    var altar = ModBlock(); altar.id = "altar"; altar.name = "Altar"; altar.art = painted(8, 8, 0xA040C0)
    p.items = [totem]
    p.blocks = [altar]
    var imp = ModMob(); imp.id = "imp"; imp.name = "Imp"; imp.category = .hostile; imp.hp = 10; imp.spawn.enabled = false
    var b = ModMob()
    b.id = "king"; b.name = "Frost King"; b.category = .boss; b.hp = 400; b.damage = 10; b.speed = 2; b.scale = 1.2
    b.behavior.chase = true; b.behavior.attackPlayer = true; b.behavior.wander = false
    b.spawn.enabled = false
    var hit = ModAttack(); hit.kind = .melee; hit.damage = 10; hit.cooldown = 1.0
    var slam = ModAttack(); slam.kind = .stomp; slam.damage = 8; slam.cooldown = 3.0; slam.radius = 3
    b.attacks = [hit, slam]
    var p1 = ModPhase()
    p1.name = "Angry"; p1.when = .health; p1.value = 0.6; p1.speedMul = 1.5; p1.damageMul = 2; p1.cooldownMul = 0.5; p1.attacks = [1]
    p1.defense = 0.5; p1.heal = 0.1; p1.shield = 2; p1.helper = "bossy:imp"; p1.helpers = 2; p1.message = "The king is angry!"; p1.tint = 0xFF2020; p1.tintAmt = 0.5
    var p2 = ModPhase(); p2.name = "Alone"; p2.when = .helpersGone; p2.speedMul = 1.8; p2.damageMul = 2
    var p3 = ModPhase(); p3.name = "Last Stand"; p3.when = .time; p3.value = 20; p3.damageMul = 3
    b.phases = [p1, p2, p3]
    var s1 = ModSummon(); s1.how = .useItem; s1.item = .custom("bossy:totem"); s1.time = 2; s1.message = "The Frost King answers!"
    var s2 = ModSummon(); s2.how = .buildPattern; s2.pattern = ModPattern(w: 3, h: 2)
    s2.pattern.set(0, 0, "air"); s2.pattern.set(1, 0, "bossy:altar"); s2.pattern.set(2, 0, "air")
    for x in 0..<3 { s2.pattern.set(x, 1, ModGround.key(.stone)) }
    b.summons = [s1, s2]
    p.mobs = [imp, b]
    _ = ModValidator.check(&p, known: [:])
    return p
}

print("== boss phases")
do {
    let pack: ModPack = bossMod()
    check(pack.mobs[1].phases.count == 3 && pack.mobs[1].summons.count == 2 && pack.mobs[1].summons.allSatisfy { $0.enabled } && pack.mobs[1].phases[0].helper == "bossy:imp",
          "a boss with three phases and two ways to summon passes its checks unchanged")
    let g = arena([pack])
    let slot: Int = ModRuntime.shared.mobSlot["bossy:king"]!
    let r: ModMobRT = ModRuntime.shared.mob(slot)!
    let king: Mob = g.addCustomMob(slot, g.pb.x + 6, 100)!
    king.persistent = true
    g.mobGrid.rebuild(g.mobs)
    check(king.mphase == 0 && near(king.dmgMul, 1) && near(king.phaseSpeed, 1), "a fresh boss is in no phase yet")
    g.stepPhases(king, r, 1.0 / 60.0)
    check(king.mphase == 0, "at full health nothing happens")
    king.hp = king.maxHP * 0.55
    g.stepPhases(king, r, 1.0 / 60.0)
    check(king.mphase == 1 && near(king.phaseSpeed, 1.5) && near(king.dmgMul, 2) && near(king.phaseCD, 0.5), "below 60% health it enters its first phase: faster and stronger")
    check(near(king.hp, king.maxHP * 0.65, 0.5), "it heals a tenth of its health as the phase begins")
    check(g.helpersAlive(king) == 2 && king.helpersCalled == 2, "and calls its two helpers to its side (\(g.helpersAlive(king)))")
    check(g.message == "The king is angry!", "and says its message")
    var info = DamageInfo(amount: 20, type: .melee, source: .player)
    info.originX = g.pb.x
    let hp0: Double = king.hp
    check(!g.applyMobDamage(king, info) && near(king.hp, hp0), "while it changes, blows glance off")
    king.phaseShield = 0
    _ = g.applyMobDamage(king, info)
    check(near(hp0 - king.hp, 10, 0.6), "afterwards it shrugs off half of every blow (20 -> \(hp0 - king.hp))")
    check(!g.phaseAllows(king, r, 0) && g.phaseAllows(king, r, 1), "in this phase it only uses the attacks chosen for it")
    king.modCD = [0, 0]
    king.b.onGround = true
    var picks: Set<Int> = []
    for _ in 0..<20 { if let k = g.pickCustomAttack(king, r, king.b.x + 1.0, king.b.cy, nil) { picks.insert(k) } }
    check(picks == [1], "so it picks only the stomp, though the swipe is in reach too (\(picks))")
    g.startCustomAttack(king, r, 1, king.b.x + 1, king.b.cy, nil)
    check(near(king.modCD[1], 1.5), "its attacks rest half as long (3 s -> \(king.modCD[1]) s)")
    king.st = 0
    g.refreshBossBar()
    check(g.bossBarName == "Frost King \u{00B7} Angry", "the boss bar names the phase (\(g.bossBarName))")
    _ = Art.shared.customMobSet(slot, 1)
    check(Art.shared.modMobSets[1_000_000 + slot * 16 + 1] != nil, "it is drawn in the phase's colour")
    // helpers beaten: the next phase
    for h in g.mobs where h.helperOf == king.id { g.killMob(h, true) }
    g.stepPhases(king, r, 1.0 / 60.0)
    check(king.mphase == 2 && near(king.phaseSpeed, 1.8), "once its helpers are beaten it enters the next phase")
    // the fight's clock
    king.lastHitByPlayer = g.clock
    king.fightT = 0
    g.stepPhases(king, r, 1.0)
    check(near(king.fightT, 1), "the fight's clock runs while it fights")
    king.fightT = 21
    g.stepPhases(king, r, 1.0 / 60.0)
    check(king.mphase == 3 && near(king.dmgMul, 3), "after 20 seconds of fighting it makes its last stand (damage x3)")
    // a live fight: it comes for the player and hits hard
    king.phaseShield = 0
    g.hp = 400
    var n: Int = 0
    while g.hp >= 400 && n < 900 { frame(g); n += 1 }
    check(g.hp < 400, "in a live fight it reaches the player and hits (\(400 - g.hp) in \(n) frames)")
    // saved mid-fight, a summoned boss comes back in its phase
    king.summoned = true
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    check(back.bosses?.count == 1 && back.bosses?.first?.phase == 3, "a save keeps a summoned boss and its phase")
    ModRuntime.activate([pack], world: back.mods)
    let g2 = Game.load(back, settings: Settings())
    let k2: Mob? = g2.mobs.first { $0.kind == .custom && $0.hp > 0 && ModRuntime.shared.mob($0.cslot)?.key == "bossy:king" }
    check(k2 != nil && k2!.mphase == 3 && near(k2!.dmgMul, 3) && near(k2!.hp, back.bosses!.first!.hp) && k2!.summoned, "and it comes back where it was, in that phase")
    var old: SaveData = back
    old.bosses = nil
    let g3 = Game.load(old, settings: Settings())
    check(!g3.mobs.contains { $0.kind == .custom }, "a save without one loads as before")
    ModRuntime.deactivate()
}

print("== summoning")
do {
    let pack: ModPack = bossMod()
    let g = arena([pack])
    let slot: Int = ModRuntime.shared.mobSlot["bossy:king"]!
    func kings() -> [Mob] { return g.mobs.filter { $0.kind == .custom && $0.cslot == slot && $0.hp > 0 && !$0.removed } }
    func tap(_ x: Double, _ y: Double) {
        aimAt(g, x, y)
        g.usePressedFlag = true
        g.useHeld = true
        g.placeCD = 0
        g.useCD = 0
        g.updateUse(1.0 / 60.0)
        g.useHeld = false
    }
    check(ModRuntime.shared.summons.count == 2, "both ways to summon are ready in play")
    hold(g, .custom("bossy:totem"), 2)
    g.timeOfDay = 0.25
    tap(g.pb.x + 2, 99.5)
    check(kings().isEmpty && g.inv.total(.custom("bossy:totem")) == 2 && (g.message ?? "").contains("only answers at night"), "by day the totem does nothing, and says why (\(g.message ?? ""))")
    g.timeOfDay = 0.75
    tap(g.pb.x + 2, 99.5)
    check(kings().count == 1 && g.inv.total(.custom("bossy:totem")) == 1 && g.message == "The Frost King answers!", "at night it calls the Frost King, and the totem is used up")
    let k: Mob = kings()[0]
    check(k.persistent && k.summoned && k.isBoss, "the summoned boss stays (it never wanders off)")
    g.refreshBossBar()
    check(g.activeBoss === k, "and its health bar shows")
    tap(g.pb.x + 2, 99.5)
    check(kings().count == 1 && g.inv.total(.custom("bossy:totem")) == 1 && (g.message ?? "").contains("already here"), "while it is about, a second can't be called")
    // the player far away: it leaves
    k.b.x = g.pb.x + 300
    check(g.summonedLeaves(k, 5.0) && k.removed, "when the player goes far away, it leaves")
    // building the shape
    let bx: Int = Int(g.pb.x) + 2
    let altar: Tile = ModRuntime.shared.tileForKey["bossy:altar"]!
    for x in bx..<(bx + 3) { g.world.set(x, 99, .stone) }
    hold(g, .block(altar), 1)
    g.timeOfDay = 0.25
    tap(Double(bx + 1) + 0.5, 98.5)
    check(kings().count == 1 && g.world.tile(bx + 1, 98) == .air && g.world.tile(bx, 99) == .air, "placing the last block of the shape calls it, and the shape is used up")
    kings()[0].removed = true
    for x in bx..<(bx + 3) { g.world.set(x, 99, .dirt) }
    hold(g, .block(altar), 1)
    tap(Double(bx + 1) + 0.5, 98.5)
    check(kings().isEmpty && g.world.tile(bx + 1, 98) == altar, "a shape of the wrong blocks calls nothing")
    // the conditions, one at a time
    let base: ModSummon = pack.mobs[1].summons[0]
    func problem(_ f: (inout ModSummon) -> Void) -> String? {
        var d: ModSummon = base
        d.time = 0
        f(&d)
        return g.summonProblem(ModSummonRT(slot: slot, key: "bossy:king", def: d, cells: []), nil)
    }
    let here: Biome = g.biomeAt(g.pb.x)
    let other: Biome = here == .desert ? .forest : .desert
    check(problem { $0.biomes = [here.rawValue] } == nil && problem { $0.biomes = [other.rawValue] }?.contains(other.name) == true, "a biome condition holds only in that biome")
    check(problem { $0.dims = [0] } == nil && problem { $0.dims = [1] } != nil, "a dimension condition holds only there")
    check(problem { $0.place = 1 } == nil && problem { $0.place = 2 }?.contains("underground") == true, "open sky or underground")
    g.settings.weatherOn = false
    check(problem { $0.weather = 3 } == nil, "with the weather switched off, weather conditions are skipped")
    g.settings.weatherOn = true
    if g.weatherAt(g.pb.x, g.pb.y).thunder < 0.2 {
        check(problem { $0.weather = 3 }?.contains("thunderstorm") == true, "otherwise a thunderstorm summoning waits for a storm")
    }
    check(problem { $0.time = 1; $0.biomes = [here.rawValue] } == nil && problem { $0.time = 1; $0.biomes = [other.rawValue] } != nil, "conditions combine: all of them must hold")
    // an item used on the shape
    var onShape: ModSummon = pack.mobs[1].summons[1]
    onShape.how = .itemOnPattern
    onShape.item = .custom("bossy:totem")
    onShape.clearPattern = false
    var cells: [(Int, Int, Tile?)] = [(0, 0, nil), (1, 0, altar), (2, 0, nil)]
    for x in 0..<3 { cells.append((x, 1, .stone)) }
    let rule = ModSummonRT(slot: slot, key: "bossy:king", def: onShape, cells: cells)
    for x in bx..<(bx + 3) { g.world.set(x, 99, .stone) }
    g.world.set(bx + 1, 98, altar)
    check(rule.shapeAt(g.world, bx + 1, 98)! == (bx, 98) && rule.shapeAt(g.world, bx + 2, 99)! == (bx, 98), "a finished shape is found from any of its blocks")
    g.world.set(bx + 2, 98, .dirt)
    check(rule.shapeAt(g.world, bx + 1, 98) == nil, "a cell that must be empty has to be")
    g.world.set(bx + 2, 98, .air)
    ModRuntime.shared.summons = [rule]
    hold(g, .custom("bossy:totem"), 1)
    tap(Double(bx) + 0.5, 99.5)
    check(kings().count == 1 && g.world.tile(bx + 1, 98) == altar && g.inv.total(.custom("bossy:totem")) == 0, "tapping the shape with the item calls it (this shape is kept)")
    ModRuntime.deactivate()
    // checks
    var bad: ModPack = bossMod()
    bad.mobs[1].phases[0].helper = "ghost:thing"
    bad.mobs[1].phases[0].value = 7
    bad.mobs[1].phases[0].damageMul = 99
    bad.mobs[1].phases[0].attacks = [0, 5, -1]
    bad.mobs[1].phases.append(contentsOf: [ModPhase](repeating: ModPhase(), count: 6))
    bad.mobs[1].summons[0].item = .custom("ghost:item")
    bad.mobs[1].summons[1].pattern.set(0, 1, "tile:999")
    bad.mobs[1].summons[1].pattern.set(2, 1, "ghost:block")
    bad.mobs[1].summons[1].time = 9
    bad.mobs[1].summons.append(contentsOf: [ModSummon](repeating: ModSummon(), count: 3))
    _ = ModValidator.check(&bad, known: [:])
    let ph: ModPhase = bad.mobs[1].phases[0]
    check(bad.mobs[1].phases.count == ModLimits.maxPhases && ph.helper.isEmpty && ph.helpers == 0 && near(ph.value, 0.95) && near(ph.damageMul, 3) && ph.attacks == [0],
          "phases are kept in range, and a helper that doesn't exist is cleared")
    let sm: [ModSummon] = bad.mobs[1].summons
    check(sm.count == ModLimits.maxSummons && !sm[0].enabled && sm[0].item == nil, "a summoning item that doesn't exist switches that summoning off")
    check(sm[1].enabled && sm[1].pattern.cell(0, 1).isEmpty && sm[1].pattern.cell(2, 1).isEmpty && sm[1].pattern.cell(1, 1) == ModGround.key(.stone) && sm[1].time == 2,
          "blocks that don't exist leave their cells free; numbers are kept in range")
    let rt2: ModMob = try! JSONDecoder().decode(ModMob.self, from: try! JSONEncoder().encode(pack.mobs[1]))
    check(rt2 == pack.mobs[1], "phases and summonings survive a JSON round trip")
    let oldMob: ModMob = try! JSONDecoder().decode(ModMob.self, from: "{\"id\":\"m\",\"name\":\"Old\"}".data(using: .utf8)!)
    check(oldMob.phases.isEmpty && oldMob.summons.isEmpty, "a creature from before has neither")
    // a copy of the mod under a new id keeps its own references
    let moved: ModPack = ModStore.rekey(pack, from: "bossy", to: "boss2")
    let mk: ModMob = moved.mobs[1]
    check(mk.phases[0].helper == "boss2:imp" && mk.summons[0].item == .custom("boss2:totem") && mk.summons[1].pattern.cell(1, 0) == "boss2:altar" && mk.summons[1].pattern.cell(0, 1) == ModGround.key(.stone),
          "a mod copied under a new id keeps its helpers, items and shapes pointing at its own content")
    var dep = ModPack()
    dep.id = "user"
    var dm = ModMob(); dm.id = "d"; dm.name = "D"
    var ds = ModSummon(); ds.item = .custom("bossy:totem")
    dm.summons = [ds]
    dep.mobs = [dm]
    check(ModStore.dependencies(dep) == ["bossy"], "a summoning item from another mod makes that mod a dependency")
}

// ---------------------------------------------------------------- stage 6
func dimMod() -> ModPack {
    var p = ModPack()
    p.id = "dimz"
    p.name = "Dims"
    var key = ModItem(); key.id = "key"; key.name = "Frost Key"; key.kind = .material
    var gateB = ModBlock(); gateB.id = "gate"; gateB.name = "Frost Gate"; gateB.art = painted(8, 8, 0x80C0FF)
    var ice = ModBlock(); ice.id = "ice"; ice.name = "Blue Ice"; ice.art = painted(8, 8, 0x60A0E0)
    var fore = ModBlock(); fore.id = "fore"; fore.name = "Frost Ore"; fore.art = painted(8, 8, 0xE0F0FF)
    p.items = [key]
    p.blocks = [gateB, ice, fore]
    var yeti = ModMob(); yeti.id = "yeti"; yeti.name = "Yeti"; yeti.category = .passive; yeti.hp = 30; yeti.spawn.enabled = false; yeti.attacks = []
    p.mobs = [yeti]
    var d = ModDimension()
    d.id = "frost"; d.name = "Frostlands"
    d.skyTop = 0x203050; d.skyBottom = 0xA0C8F0; d.light = 0.7; d.cycle = false; d.fixedTime = 0.75
    d.weather = 4; d.chill = 0.6; d.ambient = 2
    d.surface = 140; d.hills = 10; d.caves = 0.5; d.islands = 0.5; d.sea = 0
    d.stone = "dimz:ice"
    var z1 = ModDimZone(); z1.name = "Snowfield"; z1.biome = Biome.tundra.rawValue; z1.ground = ModGround.key(.snow); z1.trees = 2; z1.leaves = ModGround.key(.pineLeaves)
    var z2 = ModDimZone(); z2.name = "Glacier"; z2.biome = Biome.mountain.rawValue; z2.ground = "dimz:ice"; z2.filler = "dimz:ice"; z2.trees = 0; z2.plant = ""
    d.zones = [z1, z2]
    d.zoneWidth = 64
    var sp = ModDimSpawn(); sp.creature = "dimz:yeti"; sp.place = 0; sp.weight = 10
    var sp2 = ModDimSpawn(); sp2.creature = mobDef(.wolf).name; sp2.when = 2; sp2.weight = 4
    d.spawns = [sp, sp2]
    d.entry.how = .itemOnPattern
    d.entry.item = .custom("dimz:key")
    d.entry.consume = false
    d.entry.clearPattern = false
    d.entry.pattern = ModPattern(w: 3, h: 4)
    for y in 0..<4 { for x in 0..<3 { d.entry.pattern.set(x, y, (x == 1 && (y == 1 || y == 2)) ? "air" : "dimz:gate") } }
    d.returnGate = true
    d.gateBlock = "dimz:gate"
    p.dims = [d]
    var ore = ModOre(); ore.id = "o1"; ore.name = "Frost veins"; ore.block = "fore"; ore.dimKey = "frost"; ore.minY = 150; ore.maxY = 300; ore.veins = 6; ore.size = 6; ore.hosts = ["dimz:ice"]
    p.ores = [ore]
    _ = ModValidator.check(&p, known: [:])
    return p
}

print("== custom dimensions")
do {
    let pack: ModPack = dimMod()
    check(pack.dims.count == 1 && pack.dims[0].entry.enabled && pack.dims[0].stone == "dimz:ice" && pack.dims[0].zones.count == 2 && pack.dims[0].spawns.count == 2 && pack.ores[0].dimKey == "frost",
          "a dimension with two regions, two creatures, a gateway and its own ore passes its checks unchanged")
    let g = arena([pack])
    let rt: ModRuntime = ModRuntime.shared
    check(rt.dimSlots[0]?.key == "dimz:frost" && rt.worldInfo().dims["dimz:frost"] == 0, "it takes the world's first dimension slot, remembered with the world's mods")
    let ice: Tile = rt.tileForKey["dimz:ice"]!
    let fore: Tile = rt.tileForKey["dimz:fore"]!
    let gate: Tile = rt.tileForKey["dimz:gate"]!
    // generation
    let c0: Chunk = generateChunk(g.gen, .custom0, 0)
    let c0b: Chunk = generateChunk(g.gen, .custom0, 0)
    check(c0.H == customDimH && c0.tiles == c0b.tiles, "its land is the same every time it is made")
    var iceN: Int = 0
    var oreN: Int = 0
    var snowTop: Int = 0
    var iceTop: Int = 0
    var leaves: Int = 0
    var isles: Int = 0
    var caves: Int = 0
    for cx in -6...6 {
        let ch: Chunk = generateChunk(g.gen, .custom0, cx)
        for lx in 0..<chunkW {
            let surf: Int = ch.surf[lx]
            let top: Tile = ch.get(lx, surf)
            if top == .snow { snowTop += 1 }
            if top == ice { iceTop += 1 }
            for y in 0..<customDimH {
                let t: Tile = ch.get(lx, y)
                if t == ice { iceN += 1 }
                if t == fore { oreN += 1 }
                if t == .pineLeaves { leaves += 1 }
                if y < surf - 26 && (t == ice || t == .snow) { isles += 1 }
                if y > surf + 6 && y < customDimH - 40 && t == .air { caves += 1 }
            }
        }
    }
    check(iceN > 5000 && snowTop > 40 && iceTop > 40, "its rock is the mod's ice, and its two regions have their own ground (snow \(snowTop), ice \(iceTop) columns)")
    check(leaves > 20, "the snowfield grows trees of pine leaves (\(leaves) leaf blocks)")
    check(isles > 50, "floating islands hang in its sky (\(isles) blocks)")
    check(caves > 200, "caves run under its ground (\(caves) open blocks)")
    check(oreN > 0, "the mod's ore forms there (\(oreN) blocks)")
    var leak: Bool = false
    for cx in -3...3 {
        let ch: Chunk = generateChunk(g.gen, .overworld, cx)
        if ch.tiles.contains(fore.rawValue) { leak = true }
    }
    check(!leak, "and not in the Overworld")
    // getting in: build the gateway, tap it with the key
    let bx: Int = Int(g.pb.x) + 2
    for y in 0..<4 { for x in 0..<3 { g.world.set(bx + x, 96 + y, (x == 1 && (y == 1 || y == 2)) ? .air : gate) } }
    hold(g, .custom("dimz:key"), 1)
    func tap(_ x: Double, _ y: Double) {
        aimAt(g, x, y)
        g.usePressedFlag = true
        g.useHeld = true
        g.placeCD = 0
        g.useCD = 0
        g.updateUse(1.0 / 60.0)
        g.useHeld = false
    }
    let fromX: Double = g.pb.x
    tap(Double(bx) + 0.5, 99.5)
    check(g.world.dim == .custom0 && g.customDim?.def.name == "Frostlands", "tapping the gateway with the key takes the player into the dimension")
    check(g.dimReturn?.dim == 0 && near(g.dimReturn!.x, fromX), "remembering where they came from")
    check(g.inv.total(.custom("dimz:key")) == 1 && (g.message ?? "").contains("Frostlands"), "the key is kept (as chosen) and arrival is announced")
    var gateAt: (Int, Int)? = nil
    for dx in -6...6 { for dy in -6...4 where g.world.tile(Int(g.pb.x) + dx, Int(g.pb.y) + dy) == gate { gateAt = (Int(g.pb.x) + dx, Int(g.pb.y) + dy) } }
    check(gateAt != nil, "a gate back stands beside where they arrived")
    // what it is like there
    check(g.isNight && near(g.dayFactor, 0) && g.skyLevel <= 4, "it is always night there, as set (sky light \(g.skyLevel))")
    check(g.weatherAt(g.pb.x, g.pb.y - 2).precip == 0, "with the weather switched off, nothing falls there either")
    g.settings.weatherOn = true
    let w: LocalWeather = g.weatherAt(g.pb.x, g.pb.y - 2)
    check(w.snow && w.precip > 0.5 && w.chill >= 0.55, "snow falls, and it is cold")
    g.settings.weatherOn = false
    let b1: Biome = g.biomeAt(Double(0))
    let b2: Biome = g.biomeAt(Double(64))
    check(Set([b1, b2]) == Set([Biome.tundra, Biome.mountain]), "its regions count as the biomes chosen (\(b1.name), \(b2.name))")
    check(g.world.isSkyExposed(Int(g.pb.x), Int(g.pb.y) - 2) && dimHasSky(.custom0), "it has open sky")
    check(g.customDim!.spawnRules.count == 2, "its creatures become spawning rules")
    // only its own creatures come
    g.monstersEnabled = true
    g.mobs.removeAll()
    var others: [String] = []
    for _ in 0..<500 {
        g.spawnTimer = 0
        g.updateSpawning(0.1)
    }
    let yetiSlot: Int = rt.mobSlot["dimz:yeti"]!
    var yetis: Int = 0
    var wolves: Int = 0
    for m in g.mobs where m.hp > 0 {
        if m.kind == .custom && m.cslot == yetiSlot { yetis += 1 } else if m.kind == .wolf { wolves += 1 } else { others.append(m.def.name) }
    }
    check(yetis + wolves > 0 && others.isEmpty, "only its own creatures appear there (\(yetis) yetis, \(wolves) wolves, others: \(others))")
    g.mobs.removeAll()
    g.mobGrid.rebuild(g.mobs)
    // saved in the dimension
    g.world.set(Int(g.pb.x) - 3, Int(g.pb.y) - 1, .brick)
    let bxIn: Int = Int(g.pb.x) - 3
    let byIn: Int = Int(g.pb.y) - 1
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    check(back.meta.dim == 2 && back.chunks.contains { $0.dim == 2 } && back.dimReturn?.dim == 0 && back.mods?.dims["dimz:frost"] == 0, "a save made there keeps the dimension's land, where the player is, and the way back")
    ModRuntime.activate([pack], world: back.mods)
    let g2 = Game.load(back, settings: Settings())
    check(g2.world.dim == .custom0 && g2.world.tile(bxIn, byIn) == .brick && g2.dimReturn?.dim == 0, "loading it puts the player back in the dimension, with what they built")
    check(ModRuntime.shared.dimSlots[0]?.key == "dimz:frost", "in the same slot")
    ModRuntime.activate([], world: back.mods)
    let g3 = Game.load(back, settings: Settings())
    check(g3.world.dim == .overworld && near(g3.pb.x, back.spawnX, 3) && (g3.message ?? "").contains("missing"), "with its mod missing, the player wakes at the Overworld's spawn and is told why")
    let resave: SaveData = g3.makeSave()
    check(resave.chunks.contains { $0.dim == 2 } && resave.mods?.dims["dimz:frost"] == 0, "and the dimension is kept in the save for when the mod is back")
    ModRuntime.activate([pack], world: back.mods)
    // the way back
    let g4 = Game.load(back, settings: Settings())
    var gate4: (Int, Int)? = nil
    for dx in -40...40 { for dy in -12...12 where g4.world.tile(Int(g4.pb.x) + dx, Int(g4.pb.y) + dy) == gate { gate4 = (Int(g4.pb.x) + dx, Int(g4.pb.y) + dy) } }
    if let gt = gate4 {
        g4.pb.x = Double(gt.0) - 1.5
        g4.pb.y = Double(gt.1) + 1
        aimAt(g4, Double(gt.0) + 0.5, Double(gt.1) + 0.5)
        g4.usePressedFlag = true
        g4.useHeld = true
        g4.inv.slots[g4.sel] = nil
        g4.updateUse(1.0 / 60.0)
    }
    check(gate4 != nil && g4.world.dim == .overworld && near(g4.pb.x, fromX, 4) && g4.dimReturn == nil, "tapping the gate takes the player back to where they came in")
    // the key used inside the dimension also takes them back
    let g5 = Game.load(back, settings: Settings())
    g5.inv.slots[0] = Stack(item: .custom("dimz:key"), count: 1)
    g5.setSel(0)
    aimAt(g5, g5.pb.x + 1, g5.pb.y - 1)
    g5.usePressedFlag = true
    g5.useHeld = true
    g5.updateUse(1.0 / 60.0)
    check(g5.world.dim == .overworld, "so does using the key again inside it")
    // summonings can be limited to the dimension
    var only: ModSummon = ModSummon()
    only.dimKeys = ["dimz:frost"]
    check(g5.conditionsProblem(only, "It", nil) != nil, "a summoning set for the dimension doesn't work in the Overworld")
    let g6 = Game.load(back, settings: Settings())
    check(g6.conditionsProblem(only, "It", nil) == nil, "but does inside it")
    ModRuntime.deactivate()
    // the editor's preview runs the same generator
    let pv: PixelBuf = ModDimPreview.render(pack.dims[0], pack)
    check(pv.w == ModDimPreview.chunks * chunkW && pv.px.contains { $0 & 0xFFFFFF == 0x60A0E0 } && pv.px.contains { $0 & 0xFFFFFF == 0x203050 || $0 & 0xFFFFFF == 0xA0C8F0 },
          "the editor's preview shows the land in the mod's own block colours under its sky")
    // checks
    var bad: ModPack = dimMod()
    var bd: ModDimension = bad.dims[0]
    bd.surface = 999; bd.hills = -5; bd.light = 7; bd.zoneWidth = 1; bd.stone = "ghost:rock"
    bd.zones[0].ground = "tile:999"; bd.zones[0].plant = "ghost:plant"
    bd.spawns.append({ var x = ModDimSpawn(); x.creature = "ghost:thing"; return x }())
    bd.entry.how = .buildPattern
    bd.entry.pattern = ModPattern(w: 2, h: 2)
    bd.returnGate = false
    bad.dims = [bd, bd, bd, bd]
    bad.ores[0].dimKey = "nowhere"
    _ = ModValidator.check(&bad, known: [:])
    let cd: ModDimension = bad.dims[0]
    check(bad.dims.count == 3 && Set(bad.dims.map { $0.id }).count == 3, "only three dimensions fit in a mod, each with its own id")
    check(cd.surface == 260 && near(cd.hills, 0) && near(cd.light, 1) && cd.zoneWidth == 40 && cd.stone == ModGround.key(.stone), "numbers are kept in range and a rock that doesn't exist falls back to stone")
    check(cd.zones[0].ground == ModGround.key(.grass) && cd.zones[0].plant.isEmpty && cd.spawns.count == 2, "broken blocks and creatures are cleared")
    check(!cd.entry.enabled && cd.returnGate, "a way in with nothing to build is switched off, and without a key to use again the gate back is kept")
    check(bad.ores[0].dimKey.isEmpty, "an ore set for a dimension that doesn't exist goes back to the Overworld")
    let rtd: ModDimension = try! JSONDecoder().decode(ModDimension.self, from: try! JSONEncoder().encode(pack.dims[0]))
    check(rtd == pack.dims[0], "a dimension survives a JSON round trip")
    let oldPack: ModPack = try! JSONDecoder().decode(ModPack.self, from: "{\"id\":\"old\",\"name\":\"Old\"}".data(using: .utf8)!)
    check(oldPack.dims.isEmpty, "a mod from before has none")
    let moved: ModPack = ModStore.rekey(pack, from: "dimz", to: "dim2")
    let md: ModDimension = moved.dims[0]
    check(md.stone == "dim2:ice" && md.zones[1].ground == "dim2:ice" && md.spawns[0].creature == "dim2:yeti" && md.spawns[1].creature == mobDef(.wolf).name && md.entry.item == .custom("dim2:key") && md.entry.pattern.cell(0, 0) == "dim2:gate" && md.gateBlock == "dim2:gate",
          "a copy under a new id keeps its dimension pointing at its own blocks, creatures and key")
}

// ---------------------------------------------------------------- stage 7
func node(_ op: LOp, _ f: (inout LNode) -> Void = { _ in }) -> LNode {
    var n = LNode(op)
    f(&n)
    return n
}
func ex(_ v: Double) -> LExpr { return LExpr(v) }
func rep_(_ op: LEOp, _ a: [LExpr] = []) -> LExpr { return LExpr(op: op, args: a) }
func script(_ id: String, _ e: LEvent, _ blocks: [LNode], _ f: (inout ModScript) -> Void = { _ in }) -> ModScript {
    var s = ModScript()
    s.id = id
    s.name = id
    s.event = e
    s.blocks = blocks
    f(&s)
    return s
}
func logicMod() -> ModPack {
    var p = ModPack()
    p.id = "lg"
    p.name = "Logic"
    p.variables = ["score", "count", "ok", "night", "spin", "flag"]
    var pet = ModMob(); pet.id = "pet"; pet.name = "Pet"; pet.category = .passive; pet.hp = 20; pet.spawn.enabled = false; pet.attacks = []
    var wand = ModItem(); wand.id = "wand"; wand.name = "Wand"; wand.kind = .material
    var button = ModBlock(); button.id = "button"; button.name = "Button"; button.art = painted(8, 8, 0xD04040)
    p.mobs = [pet]
    p.items = [wand]
    p.blocks = [button]
    var g1 = script("g1", .group, [node(.changeVar) { $0.s = "score"; $0.args = [rep_(.mul, [LExpr(op: .param, args: []), ex(2)])] }])
    g1.blocks[0].args[0].args[0].v = 1
    g1.params = ["amount"]
    p.scripts = [
        script("start", .worldStart, [node(.say) { $0.s = "Hello" }, node(.setVar) { $0.s = "score"; $0.args = [ex(5)] }, node(.changeVar) { $0.s = "score"; $0.args = [ex(2)] }]),
        script("tick", .every, [node(.changeVar) { $0.s = "score"; $0.args = [ex(1)] }]) { $0.ev = 1 },
        script("boom", .custom, [node(.hurtPlayer) { $0.args = [ex(3)] }, node(.log) { $0.s = "boom went off"; $0.args = [] }]) { $0.evText = "boom" },
        g1,
        script("callg", .worldStart, [node(.runGroup) { $0.s = "lg:g1"; $0.args = [ex(10)] }]),
        script("petIn", .spawned, [node(.say) { $0.s = "pet is here" }, node(.jump) { $0.a = 10 }, node(.wait) { $0.args = [ex(0.5)] }, node(.setVar) { $0.s = "flag"; $0.args = [ex(1)] }]) { $0.target = "lg:pet" },
        script("petOut", .dies, [node(.giveItem) { $0.item = .mat(.coal); $0.a = 3 }]) { $0.target = "lg:pet" },
        script("loops", .worldStart, [
            node(.repeatN) { $0.args = [ex(3)]; $0.body = [node(.changeVar) { $0.s = "count"; $0.args = [ex(1)] }] },
            node(.ifElse) { $0.args = [rep_(.gt, [LExpr(op: .variable), ex(2)])]; $0.args[0].args[0].s = "count"
                $0.body = [node(.setVar) { $0.s = "ok"; $0.args = [ex(1)] }]
                $0.alt = [node(.setVar) { $0.s = "ok"; $0.args = [ex(2)] }] },
            node(.placeBlock) { $0.s = ModGround.key(.brick); $0.a = 2; $0.b = 0 },
        ]),
        script("tap", .blockTapped, [node(.broadcast) { $0.s = "boom" }]) { $0.target = "lg:button" },
        script("use", .itemUsed, [node(.giveEffect) { $0.a = Double(ModEffectKind.speed.rawValue); $0.b = 30; $0.c = 5 }]) { $0.target = "lg:wand" },
        script("dark", .nightFalls, [node(.setVar) { $0.s = "night"; $0.args = [ex(1)] }]),
    ]
    _ = ModValidator.check(&p, known: [:])
    return p
}

print("== logic studio")
do {
    let pack: ModPack = logicMod()
    check(pack.scripts.count == 11 && pack.scripts.allSatisfy { $0.enabled } && pack.variables.count == 6, "a mod of eleven scripts and six variables passes its checks")
    let g = arena([pack])
    let lrt: LogicRT = ModRuntime.shared.logic
    check(lrt.programs.count == 11 && lrt.groups["lg:g1"] != nil && lrt.listeners(.worldStart).count == 3, "the scripts are compiled for the world, the group set apart")
    func v(_ name: String) -> Double { return g.logicVars["lg:" + name] ?? -999 }
    let bx: Int = Int(floor(g.pb.x)) + 2
    let by: Int = Int(floor(g.pb.y - g.pb.h * 0.5))
    g.world.set(bx, by, .air)
    frames(g, 6)
    check(g.message == "Hello", "when the world starts, a script shows its message")
    check(near(v("score"), 27), "variables are set and changed, and a group runs with its input (5 + 2 + 10 x 2 = \(v("score")))")
    check(near(v("count"), 3) && near(v("ok"), 1), "a repeat runs three times, and if/else takes the right branch")
    check(g.world.tile(bx, by) == .brick, "a script places a block beside the player")
    frames(g, 70)
    check(near(v("score"), 28), "a script every second runs once a second (\(v("score")))")
    // a block tapped sends a message; the message hurts the player
    let button: Tile = ModRuntime.shared.tileForKey["lg:button"]!
    let tx: Int = Int(g.pb.x) - 2
    g.world.set(tx, 99, button)
    g.hp = 100
    aimAt(g, Double(tx) + 0.5, 99.5)
    g.inv.slots[g.sel] = nil
    g.usePressedFlag = true
    g.useHeld = true
    g.invuln = 0
    frames(g, 3)
    g.useHeld = false
    check(g.world.tile(tx, 99) == button && g.hp < 100 && g.logic.log.contains { $0.contains("boom went off") }, "tapping the block sends a message, and the script for it runs (the block is kept)")
    // creatures
    let slot: Int = ModRuntime.shared.mobSlot["lg:pet"]!
    let pet: Mob = g.addCustomMob(slot, g.pb.x + 4, 100)!
    pet.persistent = true
    frames(g, 2)
    check(g.message == "pet is here" && pet.b.vy < 0, "when a creature appears its script runs: a message, and it jumps")
    check(near(v("flag"), -999), "a wait holds the script")
    frames(g, 40)
    check(near(v("flag"), 1), "and it carries on after the wait")
    let coal0: Int = g.inv.total(.mat(.coal))
    g.killMob(pet, true)
    frames(g, 2)
    check(g.inv.total(.mat(.coal)) == coal0 + 3, "when it is beaten, its script still runs (3 coal given)")
    // an item
    g.inv.slots[0] = Stack(item: .custom("lg:wand"), count: 1)
    g.setSel(0)
    aimAt(g, g.pb.x + 1, g.pb.y - 1)
    g.usePressedFlag = true
    g.useHeld = true
    g.effects.clear()
    frames(g, 2)
    g.useHeld = false
    check(near(g.effects.value(.speed), 30), "using the item gives its effect")
    // night falls
    g.timeOfDay = 0.75
    frames(g, 2)
    check(near(v("night"), 1), "when night falls, its script runs")
    // the step debugger
    g.fireLogic(.custom, text: "boom")
    g.logicPauseToggle()
    let hp1: Double = g.hp
    g.invuln = 0
    frames(g, 10)
    // (health may tick up meanwhile; the script must not have hurt the player)
    check(g.logic.paused && g.hp >= hp1 - 0.01 && g.logic.threads.count == 1 && g.logic.threads[0].frames[0].pc == 0, "paused, a script waits at its first block")
    let hp2: Double = g.hp
    g.logicStepOnce()
    g.invuln = 0
    check(g.hp < hp2 && g.logic.threads.count == 1 && g.logic.threads[0].frames[0].pc == 1, "STEP runs it one block at a time")
    g.logicPauseToggle()
    frames(g, 2)
    check(g.logic.threads.isEmpty, "and RUN lets it finish")
    // saved with the world
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    check(near(back.logicVars?["lg:score"] ?? 0, v("score")), "the variables are saved with the world")
    ModRuntime.activate([pack], world: back.mods)
    let g2 = Game.load(back, settings: Settings())
    check(near(g2.logicVars["lg:count"] ?? 0, 3), "and come back with it")
    ModRuntime.deactivate()
}

print("== logic studio safety")
do {
    var p = ModPack()
    p.id = "bad"
    p.name = "Bad"
    p.variables = ["spin"]
    let spinner = script("spin", .worldStart, [node(.forever) { $0.body = [node(.changeVar) { $0.s = "spin"; $0.args = [ex(1)] }] }])
    let selfCall = script("deep", .group, [node(.runGroup) { $0.s = "bad:deep" }])
    let caller = script("call", .worldStart, [node(.runGroup) { $0.s = "bad:deep" }])
    let hurt = script("hurt", .custom, [node(.hurtPlayer) { $0.args = [ex(9999)] }]) { $0.evText = "x" }
    p.scripts = [spinner, selfCall, caller, hurt]
    _ = ModValidator.check(&p, known: [:])
    let g = arena([p])
    g.maxHP = 400
    g.hp = 400
    frames(g, 3)
    let t: LThread? = g.logic.threads.first { $0.prog.key == "bad:spin" }
    check(t != nil && t!.steps <= 3 * LLimits.stepsPerThread + 10, "a loop that never waits gets only a slice of each frame (\(t?.steps ?? -1) steps in 3 frames)")
    check(g.logic.log.contains { $0.contains("too deeply") }, "a group that runs itself is stopped at eight deep")
    let start: Double = perfNow()
    frames(g, 660)
    let ms: Double = (perfNow() - start) / 660.0 * 1000.0
    check(!g.logic.threads.contains { $0.prog.key == "bad:spin" } && g.logic.log.contains { $0.contains("without waiting") }, "after 10 seconds without waiting it is stopped, with a reason")
    check(ms < 40, "the game kept running meanwhile (\(String(format: "%.1f", ms)) ms a frame, debug build)")
    g.invuln = 0
    g.fireLogic(.custom, text: "x")
    frames(g, 2)
    check(g.hp >= 400 - 50.5, "a script can't hurt the player more than 50 at once (\(400 - g.hp))")
    ModRuntime.deactivate()
    // checks
    var bad: ModPack = logicMod()
    bad.scripts[0].blocks.append(node(.setVar) { $0.s = "ghost"; $0.args = [ex(1)] })
    bad.scripts[0].blocks.append(node(.runGroup) { $0.s = "lg:nope" })
    bad.scripts[0].blocks.append(node(.jump) { $0.a = 999 })
    bad.scripts[0].blocks.append(node(.say) { $0.a = 99 })
    bad.scripts[0].blocks.append(node(.whileDo) { $0.args = [ex(1)]; $0.body = [node(.log)] })
    bad.scripts[5].target = "lg:ghost"
    bad.scripts.append(contentsOf: (0..<45).map { i in script("x" + String(i), .worldStart, []) })
    _ = ModValidator.check(&bad, known: [:])
    let b0: [LNode] = bad.scripts[0].blocks
    check(bad.scripts.count == LLimits.maxScripts, "only \(LLimits.maxScripts) scripts fit in a mod")
    check(b0[3].s.isEmpty && b0[4].s.isEmpty && near(b0[5].a, 24) && near(b0[6].a, 10), "variables and groups that don't exist are cleared and numbers kept in range")
    check(!bad.scripts[5].enabled, "a script for a creature that doesn't exist is switched off")
    let rp: ModReport = { var q = logicMod(); q.scripts[0].blocks.append(node(.jump)); q.scripts[0].blocks.append(node(.forever) { $0.body = [node(.log)] }); return ModValidator.check(&q, known: [:]) }()
    check(rp.issues.contains { $0.text.contains("needs a creature") } && rp.issues.contains { $0.text.contains("no \u{201C}wait\u{201D}") },
          "the checks say in plain words when a block needs a creature, or a loop never waits")
    let rt: ModScript = try! JSONDecoder().decode(ModScript.self, from: try! JSONEncoder().encode(logicMod().scripts[7]))
    check(rt == logicMod().scripts[7], "a script with blocks inside blocks survives a JSON round trip")
    let old: ModPack = try! JSONDecoder().decode(ModPack.self, from: "{\"id\":\"o\",\"name\":\"O\"}".data(using: .utf8)!)
    check(old.scripts.isEmpty && old.variables.isEmpty, "a mod from before has no scripts")
    let moved: ModPack = ModStore.rekey(logicMod(), from: "lg", to: "lg2")
    check(moved.scripts[4].blocks[0].s == "lg2:g1" && moved.scripts[5].target == "lg2:pet" && moved.scripts[8].target == "lg2:button", "a copy under a new id keeps its scripts pointing at its own content")
    var some = ModPack()
    some.id = "user"
    some.scripts = [script("s", .worldStart, [node(.summon) { $0.s = "lg:pet" }])]
    check(ModStore.dependencies(some) == ["lg"], "a script that calls another mod's creature makes that mod a dependency")
}

print(fails == 0 ? "ALL \(passes) MOD CREATOR+ CHECKS PASSED" : "\(fails) FAILED, \(passes) passed")
try? FileManager.default.removeItem(at: scratch)
exit(fails == 0 ? 0 : 1)
