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

print(fails == 0 ? "ALL \(passes) MOD CREATOR+ CHECKS PASSED" : "\(fails) FAILED, \(passes) passed")
try? FileManager.default.removeItem(at: scratch)
exit(fails == 0 ? 0 : 1)
