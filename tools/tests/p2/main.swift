import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func near(_ a: Double, _ b: Double, _ eps: Double) -> Bool { return abs(a - b) <= eps }

func arena(_ seed: UInt64 = 4242) -> Game {
    let g = Game(mode: .survival, infinite: true, seed: seed, settings: Settings())
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
    g.hp = g.maxHP
    g.light.valid = false
    return g
}
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) { var t = 0.0; while t < secs { g.tick(dt); t += dt } }

/// a standard generated-style tree: trunk of `logT` 6 tall at x, canopy above
func plantTree(_ g: Game, _ x: Int, _ logT: Tile = .log, _ leaf: Tile = .leaves) {
    for k in 1...6 { g.world.set(x, 100 - k, logT) }
    for dy in -3...1 { for dx in -2...2 { if g.world.tile(x + dx, 94 + dy) == .air { g.world.set(x + dx, 94 + dy, leaf) } } }
}

/// walk with the stick held for `secs`, return x travelled
func walk(_ g: Game, _ dir: Double, _ secs: Double) -> Double {
    let x0 = g.pb.x
    var t = 0.0
    while t < secs { g.stick = dir; g.tick(1.0 / 60.0); t += 1.0 / 60.0 }
    g.stick = 0
    return g.pb.x - x0
}

// ---------------------------------------------------------------- 1. tree logs

func giveAll(_ g: Game, _ items: [(Item, Int)]) { for (it, n) in items { _ = g.inv.add(it, n) } }
func recipe(_ out: Item) -> Recipe? { return RecipeBook.all.first { $0.out == out } }
func opaqueCount(_ b: PixelBuf) -> Int { return b.px.filter { ($0 >> 24) != 0 }.count }

// ---------------------------------------------------------------- A. stations & recipes
print("== stations and recipes")
do {
    let g = arena()
    let px = Int(floor(g.pb.x)), py = Int(floor(g.pb.y)) - 1
    g.world.set(px + 2, py, .workbench)
    giveAll(g, [(.mat(.ironBar), 40), (.mat(.stick), 40), (.block(.planks), 40), (.block(.stone), 40), (.mat(.copperBar), 10)])
    let ironPick = recipe(.tool(.pickaxe, .iron))!
    let copperPick = recipe(.tool(.pickaxe, .copper))!
    check(ironPick.station == .anvil && copperPick.station == .bench, "copper tools are made at the workbench, iron tools on an anvil")
    check(g.canCraft(copperPick) && !g.canCraft(ironPick), "with only a workbench nearby: copper pickaxe yes, iron pickaxe no")
    let anvilR = recipe(.block(.anvil))!
    check(g.canCraft(anvilR), "the anvil itself is made at the workbench from iron and stone")
    g.craft(anvilR)
    check(g.inv.total(.block(.anvil)) == 1, "crafting gives an anvil")
    g.world.set(px - 2, py, .anvil)
    check(g.canCraft(ironPick), "with an anvil placed nearby the iron pickaxe can be made")
    check(recipe(.tool(.pickaxe, .ember))!.station == .forge && recipe(.armor(.chest, .voidium))!.station == .forge, "Umbral-metal gear needs the rift forge")
    check(recipe(.part(.engine))!.station == .tinker && recipe(.gadget(.carKit))!.station == .tinker && recipe(.part(.seat))!.station == .bench, "machinery is built at the tinker's bench, wooden parts stay at the workbench")
    var missing: [String] = []
    for t in Tier.allCases {
        if recipe(.spear(t)) == nil { missing.append(t.name + " spear") }
        if recipe(.hammer(t)) == nil { missing.append(t.name + " hammer") }
    }
    for gr in Gear.allCases where recipe(.gear(gr)) == nil { missing.append(gr.name) }
    for st in [Tile.anvil, .tinkerBench, .riftForge] where recipe(.block(st)) == nil { missing.append(st.def.name) }
    check(missing.isEmpty, "every spear, hammer, gear piece and station has a recipe (missing: \(missing))")
    let build = RecipeBook.all.filter { $0.cat == .build }.map { $0.out }
    check(build.contains(.block(.ladder)) && build.contains(.block(.doorClosed)) && build.contains(.block(.chest)) && build.contains(.wall(5)), "the Building tab holds ladders, doors, chests and walls")
    // stations are interactive and open the crafting panel
    g.interact(Double(px - 2) + 0.5, Double(py) + 0.5)
    check(g.showInventory && g.craftStation == .anvil, "tapping an anvil opens crafting at the anvil")
    // the station blocks give themselves back when broken
    check(Tile.anvil.def.drop == nil || Tile.anvil.def.drop == .block(.anvil), "an anvil drops itself")
}

// ---------------------------------------------------------------- B. icons
print("== icons")
do {
    var thin: [String] = []
    var items: [Item] = []
    for t in Tier.allCases { items.append(.spear(t)); items.append(.hammer(t)) }
    for gr in Gear.allCases { items.append(.gear(gr)) }
    for m in [Mat.crystalShard, .relicFragment, .umbralHeart] { items.append(.mat(m)) }
    for t in [Tile.anvil, .tinkerBench, .riftForge, .crystalOre] { items.append(.block(t)) }
    for it in items {
        let n = opaqueCount(itemBuf(it))
        if n < 18 { thin.append("\(it.name)=\(n)") }
    }
    check(thin.isEmpty, "\(items.count) new item icons all have real art (thin: \(thin))")
    check(itemBuf(.spear(.iron)).px != itemBuf(.sword(.iron)).px && itemBuf(.hammer(.iron)).px != itemBuf(.tool(.axe, .iron)).px, "spear and hammer icons differ from the sword and axe")
}

// ---------------------------------------------------------------- C. weapons
print("== spear and hammer")
func lineup(_ g: Game, _ k: MobKind, _ offsets: [Double]) -> [Mob] {
    g.facing = 1; g.swingDir = 1
    let out = offsets.map { (dx: Double) -> Mob in let m = g.addMob(k, g.pb.x + dx, 100); m.b.vx = 0; return m }
    g.mobGrid.rebuild(g.mobs)
    return out
}
do {
    // reach: a target 3.2 blocks out (box edge) is in a spear's reach but beyond a sword's
    for (it, expect) in [(Item.sword(.iron), false), (.spear(.iron), true)] {
        let g = arena()
        let z = lineup(g, .zombie, [3.2 + mobDef(.zombie).w * 0.5])[0]
        let hp0 = z.hp
        g.swingEmpty(it)
        check((z.hp < hp0) == expect, "\(it.name) \(expect ? "reaches" : "does not reach") a zombie 3.2 blocks away (hp \(Int(hp0)) -> \(Int(z.hp)))")
    }
    // pierce: three zombies in a row, a spear hits only the two nearest, a sword all in reach
    do {
        let g = arena()
        let zs = lineup(g, .zombie, [1.2, 2.0, 2.6])
        let before = zs.map { $0.hp }
        g.swingEmpty(.spear(.iron))
        let hit = zip(zs, before).filter { $0.0.hp < $0.1 }.count
        check(hit == 2 && zs[2].hp == before[2], "a spear thrust runs through the two nearest of three zombies (hit \(hit))")
        let g2 = arena()
        let zs2 = lineup(g2, .zombie, [1.2, 2.0, 2.6])
        let b2 = zs2.map { $0.hp }
        g2.swingEmpty(.sword(.iron))
        check(zip(zs2, b2).filter { $0.0.hp < $0.1 }.count == 3, "a sword sweep still hits all three")
    }
    // knockback: hammer throws a zombie much further than a sword
    var kv: [Double] = []
    for it in [Item.sword(.iron), .hammer(.iron)] {
        let g = arena()
        let z = lineup(g, .zombie, [1.4])[0]
        g.swingEmpty(it)
        kv.append(z.b.vx)
    }
    check(kv[1] > kv[0] * 1.6, "a hammer's knockback beats a sword's (vx \(String(format: "%.1f", kv[0])) vs \(String(format: "%.1f", kv[1])))")
    // damage per second: sword, spear, hammer stay in the same band (no weapon is strictly best)
    let dps = [Item.sword(.iron), .spear(.iron), .hammer(.iron)].map { $0.meleeDamage / $0.meleeCooldown }
    check(dps.max()! / dps.min()! < 1.25, "damage per second of sword/spear/hammer within 25% of each other (\(dps.map { String(format: "%.1f", $0) }))")
    // a skeleton's raised shield: a sword is blocked, a hammer breaks the guard
    var dmgs: [Double] = []
    for it in [Item.sword(.iron), .hammer(.iron)] {
        let g = arena()
        let s = lineup(g, .skeleton, [1.5])[0]
        s.dir = -1
        s.blocking = true
        let h0 = s.hp
        g.swingEmpty(it)
        dmgs.append(h0 - s.hp)
        if case .hammer = it { check(!s.blocking, "the hammer knocks the skeleton's shield aside") }
    }
    check(dmgs[1] > dmgs[0] * 5, "a blocked sword does little (\(String(format: "%.1f", dmgs[0]))), a hammer smashes through (\(String(format: "%.1f", dmgs[1])))")
    // using them from the hotbar swings with their own timing
    let g = arena()
    g.inv.slots[0] = Stack(item: .hammer(.iron), count: 1)
    g.sel = 0
    g.aimValid = true
    g.aimX = g.pb.x + 2; g.aimY = g.pb.y - 1
    g.useHeld = true; g.usePressedFlag = true
    g.tick(1.0 / 60.0)
    g.useHeld = false
    check(g.swingT > 0.3 && g.swingDur == Item.hammer(.iron).swingTime && g.useCD > 0.7, "using a hammer starts a slow, heavy swing (swing \(String(format: "%.2f", g.swingDur)), cooldown \(String(format: "%.2f", g.useCD)))")
}

// ---------------------------------------------------------------- D. gear
print("== gear")
do {
    let g = arena()
    g.inv.slots[5] = Stack(item: .gear(.swiftBoots), count: 1)
    g.inv.slots[6] = Stack(item: .gear(.headlamp), count: 1)
    g.inv.slots[7] = Stack(item: .gear(.divingMask), count: 1)
    g.quickEquip(5); g.quickEquip(6)
    check(g.inv.armor.count == 5 && g.wearing(.swiftBoots) && g.wearing(.headlamp) && g.inv.slots[5] == nil, "two gear pieces go into the two gear slots")
    g.quickEquip(7)
    check(g.wearing(.divingMask) && g.inv.slots[7] != nil && g.inv.armor.compactMap { $0 }.count == 2, "a third piece swaps with one already worn")
    // armour and gear only fit their own slots
    g.carry = Stack(item: .gear(.emberCharm), count: 1)
    g.tapArmorSlot(0)
    check(g.carry?.item == .gear(.emberCharm) && g.inv.armor[0] == nil, "gear will not go into the head slot")
    g.carry = Stack(item: .armor(.head, .iron), count: 1)
    g.tapArmorSlot(4)
    check(g.carry?.item == .armor(.head, .iron), "armour will not go into a gear slot")
    g.returnCarried()
    // old inventory JSON with three armour entries
    let old = #"{"slots":[null],"armor":[null,null,null]}"#
    let inv = try! JSONDecoder().decode(Inventory.self, from: old.data(using: .utf8)!)
    check(inv.armor.count == 5 && inv.slots.count == Inventory.size, "an inventory saved before gear slots loads with 5 equipment slots and a full bag")
    let data = try! JSONEncoder().encode(g.inv)
    let back = try! JSONDecoder().decode(Inventory.self, from: data)
    check(back.wearing(.divingMask) && back.armor.count == 5, "worn gear survives save and load")
}
do {
    // swift boots: run speed
    var dist: [Double] = []
    for boots in [false, true] {
        let g = arena()
        if boots { g.inv.armor[3] = Stack(item: .gear(.swiftBoots), count: 1) }
        _ = walk(g, 1, 0.6)
        dist.append(walk(g, 1, 1.0))
    }
    check(dist[1] > dist[0] * 1.12, "swift boots run faster (\(String(format: "%.2f", dist[0])) vs \(String(format: "%.2f", dist[1])) blocks/s)")
    // diving mask: air
    var airLeft: [Double] = []
    for mask in [false, true] {
        let g = arena()
        if mask { g.inv.armor[4] = Stack(item: .gear(.divingMask), count: 1) }
        let px = Int(floor(g.pb.x))
        for x in (px - 3)...(px + 3) { for y in 90..<100 { g.world.set(x, y, .water) } }
        for _ in 0..<180 { g.updateSurvival(1.0 / 60.0, 0) }
        airLeft.append(g.air)
    }
    check(near(airLeft[0], 7, 0.1) && near(airLeft[1], 9, 0.1), "after 3 s under water: \(String(format: "%.1f", airLeft[0])) air without a mask, \(String(format: "%.1f", airLeft[1])) with")
    // ember charm: lava
    var lost: [Double] = []
    for charm in [false, true] {
        let g = arena()
        if charm { g.inv.armor[3] = Stack(item: .gear(.emberCharm), count: 1) }
        let px = Int(floor(g.pb.x))
        for x in (px - 3)...(px + 3) { for y in 97..<100 { g.world.set(x, y, .lava) } }
        let h0 = g.hp
        step(g, 2.0)
        for x in (px - 3)...(px + 3) { for y in 97..<100 { g.world.set(x, y, .air) } }
        step(g, 3.0)
        lost.append(h0 - g.hp)
    }
    check(lost[1] < lost[0] * 0.55, "2 s in lava plus the burn after: \(String(format: "%.0f", lost[0])) hp lost without the ember charm, \(String(format: "%.0f", lost[1])) with")
    // headlamp: light around the player deep underground at night
    var lv: [Int] = []
    for lamp in [false, true] {
        let g = arena()
        g.timeOfDay = 0.75
        if lamp { g.inv.armor[3] = Stack(item: .gear(.headlamp), count: 1) }
        g.sel = 9
        g.inv.slots[9] = nil
        let px = Int(floor(g.pb.x))
        for x in (px - 20)...(px + 20) { for y in 80..<97 { g.world.set(x, y, .stone) } }
        for y in 97..<100 { g.world.set(px - 20, y, .stone); g.world.set(px + 20, y, .stone) }
        g.light.valid = false
        step(g, 0.3)
        lv.append(g.light.level(px + 6, 98).1)
    }
    check(lv[1] > lv[0] + 3, "with empty hands, a headlamp lights a sealed room 6 blocks away (light \(lv[0]) -> \(lv[1]))")
}


/// walks with the real controls, holding jump (a full jump) whenever blocked; returns stuck spots
func walkFar(_ g: Game, _ dir: Double, _ dist: Double, _ maxT: Double) -> (moved: Double, stuck: [String]) {
    // plays like a person heading one way: jumps whatever is in the way, swims up out of water, and if
    // stuck in a hole climbs the nearest ladder
    let x0 = g.pb.x
    var stuck: [String] = []
    var t = 0.0, still = 0.0, lastX = g.pb.x, jumpT = 0.0
    var ladderX: Int? = nil
    var ladderTop = 0
    while abs(g.pb.x - x0) < dist && t < maxT {
        var stick = dir
        if let lx = ladderX {
            // step onto the ladder, climb it to the top, then carry on
            if !g.onLadder() && abs(Double(lx) + 0.5 - g.pb.x) > 0.3 { stick = Double(lx) + 0.5 > g.pb.x ? 1 : -1 } else { stick = 0; jumpT = 0.1 }
            if g.pb.y <= Double(ladderTop) + 0.05 && !g.onLadder() { ladderX = nil }
        }
        g.stick = stick
        if g.pb.hitWall && g.pb.onGround { jumpT = 0.45 }
        if g.pb.inWater { jumpT = 0.1 }
        g.jumpHeld = jumpT > 0
        jumpT -= 1.0 / 60.0
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if abs(g.pb.x - lastX) < 0.02 && ladderX == nil { still += 1.0 / 60.0 } else { still = 0 }
        lastX = g.pb.x
        if still > 1.2 && ladderX == nil {
            // look for a ladder at this level before giving up
            let ix = Int(floor(g.pb.x)), iy = Int(floor(g.pb.y - 0.5))
            for d in 0...10 { for sx in [ix - d, ix + d] where g.world.tile(sx, iy) == .ladder && ladderX == nil { ladderX = sx } }
            if let lx = ladderX {
                var top = iy
                while g.world.tile(lx, top - 1) == .ladder { top -= 1 }
                ladderTop = top
                still = 0
                continue
            }
        }
        if still > 2.0 {
            let ix = Int(floor(g.pb.x))
            var what = ""
            if let L = g.gen.lairAt(ix, radius: 70) { what = " near the \(L.kind) lair" }
                        for r in g.gen.rareSites(overlapping: ix - 40, ix + 40) where abs(r.x - ix) < 40 { what += " at a \(r.kind) ruin" }
            let feetRow = Int(floor(g.pb.y)) - 1
            let blockers = (0..<4).map { "\(g.world.tile(ix + Int(dir), feetRow - $0))" }.joined(separator: ",")
            stuck.append(String(format: "x %.1f y %.2f%@ (in front: %@; at feet %@, water %@)", g.pb.x, g.pb.y, what, blockers, "\(g.world.tile(ix, Int(floor(g.pb.y))))", g.pb.inWater ? "yes" : "no"))
            g.pb.x += dir * 3; still = 0
        }
    }
    g.stick = 0; g.jumpHeld = false
    return (abs(g.pb.x - x0), stuck)
}
// ---------------------------------------------------------------- E. world content
print("== world content")
func sameChunk(_ a: Chunk, _ b: Chunk) -> Bool { return a.tiles == b.tiles && a.walls == b.walls }
let landmarkTiles: Set<Tile> = [.stone, .mossGrass, .snow, .logBlock, .jungleLogBlock, .birchLogBlock, .fossil, .sandstone, .ice, .dirt]
do {
    let g3 = WorldGen(seed: 4242, infinite: true, rareChance: 0.28)
    let g2 = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, genVersion: 2)
    check(g3.hasGrottos && g3.hasMines && g3.hasLandmarks && !g2.hasGrottos && !g2.hasMines && !g2.hasLandmarks, "grottos, mines and landmarks belong to new worlds only (older worlds keep generating as they did)")
    var counts: [Tile: Int] = [:]
    var counts2: [Tile: Int] = [:]
    var tallest = 0, tallAt = ""
    for cx in -260...260 {
        let c = generateChunk(g3, .overworld, cx)
        let c2 = generateChunk(g2, .overworld, cx)
        for lx in 0..<chunkW {
            for y in 40..<200 {
                counts[c.get(lx, y), default: 0] += 1
                counts2[c2.get(lx, y), default: 0] += 1
            }
            // a landmark never stands more than three blocks above the ground it sits on
            let x = cx * chunkW + lx
            if g3.villages(overlapping: x - 2, x + 2).contains(where: { abs($0.x - x) < $0.halfW + 14 }) { continue }
            if g3.rareSites(overlapping: x - 40, x + 40).contains(where: { abs($0.x - x) < 36 }) || g3.lairAt(x, radius: 70) != nil { continue }
            if g3.mineSites(overlapping: x - 4, x + 4).contains(where: { x >= $0.x - 2 && x <= $0.x + 4 }) { continue }
            let h = g3.col(x).h
            var run = 0
            var y = h - 1
            while y > 0 && landmarkTiles.contains(c.get(lx, y)) { run += 1; y -= 1 }
            if run > tallest { tallest = run; tallAt = "x \(x): \(c.get(lx, h - 1))" }
        }
    }
    check((counts[.birchLog] ?? 0) > 200 && (counts[.pineLeaves] ?? 0) > 500 && (counts2[.birchLog] ?? 0) == 0, "new worlds grow birches (\(counts[.birchLog] ?? 0) trunk tiles) and pines (\(counts[.pineLeaves] ?? 0) needle tiles) in 8300 columns; older worlds none")
    let lm = [Tile.fossil, .logBlock, .birchLogBlock, .jungleLogBlock, .ice].map { counts[$0] ?? 0 }
    check(lm.reduce(0, +) > 60, "landmarks dot the land: fossil bones \(lm[0]), fallen logs \(lm[1] + lm[2] + lm[3]), ice \(lm[4])")
    check(tallest <= 3, "no landmark is taller than three blocks, so each can be hopped over (tallest \(tallest), \(tallAt))")
}
func findGrotto(_ g: WorldGen, open: Bool) -> GrottoSite? {
    for c in -40...40 { if let s = g.grottoSite(cell: c), s.open == open, s.passLen > 20 { return s } }
    return nil
}
func findMine(_ g: WorldGen) -> MineSite? {
    for c in -30...30 { if let s = g.mineSite(cell: c), s.levels.count >= 2 { return s } }
    return nil
}
do {
    let gen = WorldGen(seed: 4242, infinite: true, rareChance: 0.28)
    var nG = 0, nOpen = 0, nM = 0
    for c in -40...40 { if let s = gen.grottoSite(cell: c) { nG += 1; if s.open { nOpen += 1 } } }
    for c in -30...30 { if gen.mineSite(cell: c) != nil { nM += 1 } }
    check(nG > 20 && nOpen > 5 && nM > 15, "within ±28 000 blocks: \(nG) crystal grottos (\(nOpen) with a cave mouth) and \(nM) old mines")
    guard let s = findGrotto(gen, open: true) else { check(false, "no open grotto found"); fatalError() }
    let mid = generateChunk(gen, .overworld, floorDiv(s.x, chunkW))
    let lx = s.x - floorDiv(s.x, chunkW) * chunkW
    check(mid.get(lx, s.floorY - 2) == .chest && mid.get(lx, s.floorY - 1) == .mossBrick && (3...(s.ry - 2)).allSatisfy { mid.get(lx, s.floorY - $0) == .air }, "the grotto at \(s.x): a vault \(s.ry) rows high over an altar with a chest")
    var crystals = 0
    for cx in floorDiv(s.x - s.rx - 3, chunkW)...floorDiv(s.x + s.rx + 3, chunkW) {
        let c = generateChunk(gen, .overworld, cx)
        crystals += c.tiles.filter { $0 == Tile.crystalOre.rawValue || $0 == Tile.glowCrystal.rawValue }.count
    }
    check(crystals > 40, "its walls glitter: \(crystals) crystal tiles")
    // seams: the same chunk generated cold and after its neighbours is identical
    var seamOK = true
    for cx in [floorDiv(s.passStartX + s.dir * s.passLen / 2, chunkW), floorDiv(s.x - s.rx, chunkW)] {
        let warm = generateChunk(gen, .overworld, cx)
        let cold = generateChunk(WorldGen(seed: 4242, infinite: true, rareChance: 0.28), .overworld, cx)
        if !sameChunk(warm, cold) { seamOK = false }
    }
    // the world: walk from the altar up the passage and out into daylight, then back down
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.godMode = true; g.monstersEnabled = false
    g.debugTeleport(Double(s.x) + 0.5, Double(s.floorY - 1) - 0.01)
    step(g, 0.5)
    // walk to the mouth (the land beyond is ordinary terrain, cliffs and all)
    let mouthX = s.passStartX + s.dir * s.passLen
    let up = walkFar(g, Double(s.dir), abs(Double(mouthX) + 0.5 - g.pb.x), 160)
    let ix = Int(floor(g.pb.x))
    let sky = g.world.isSkyExposed(ix, Int(floor(g.pb.y)) - 1)
    let out = sky && abs(g.pb.y - Double(gen.col(ix).h)) <= 1.05
    check(up.stuck.isEmpty && out, String(format: "walked from the altar %.0f blocks up the passage and out under open sky (end y %.1f, ground %d)", up.moved, g.pb.y, gen.col(ix).h) + (up.stuck.isEmpty ? "" : " STUCK \(up.stuck.prefix(2))"))
    // step down into the mouth first (a hop from its lip would clear the dip and carry on over the top)
    _ = walk(g, Double(-s.dir), 1.5)
    let down = walkFar(g, Double(-s.dir), abs(g.pb.x - Double(s.x)), 160)
    check(down.stuck.isEmpty && abs(g.pb.y - Double(s.floorY - 1)) < 1.5, String(format: "and back down into the grotto (y %.1f, floor %d, x %.1f, grotto x %d, moved %.0f)", g.pb.y, s.floorY, g.pb.x, s.x, down.moved) + " \(down.stuck.prefix(2))")
    check(seamOK, "grotto chunks are identical whether generated alone or next to their neighbours")
    let loot = g.world.chestItems(s.x, s.floorY - 2)
    check(loot.contains { $0.item == .mat(.crystalShard) }, "the altar chest holds crystal shards (\(loot.map { $0.item.name }))")
    // a sealed one (and in flat worlds) stays below the ground
    if let sealed = findGrotto(gen, open: false) {
        let endX = sealed.passStartX + sealed.dir * sealed.passLen
        let endRoof = sealed.floorY - sealed.passLen - 4
        check(endRoof > gen.col(endX).h + 3, "a passage that cannot come out on clear ground ends sealed \(endRoof - gen.col(endX).h) rows under it")
    }
}
do {
    let gen = WorldGen(seed: 4242, infinite: true, rareChance: 0.28)
    guard let m = findMine(gen) else { check(false, "no mine"); fatalError() }
    let c = generateChunk(gen, .overworld, floorDiv(m.x + 1, chunkW))
    let lx = m.x + 1 - floorDiv(m.x + 1, chunkW) * chunkW
    let ladder = ((m.ground + 1)..<m.bottom).allSatisfy { c.get(lx, $0) == .ladder }
    check(c.get(lx, m.ground) == .platform && ladder, "the mine at \(m.x): a plank cover over a ladder running \(m.bottom - m.ground) rows down")
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.godMode = true; g.monstersEnabled = false
    // walking across the covered shaft never drops the player in
    g.debugTeleport(Double(m.x) - 12.5, Double(m.ground) - 0.01)
    step(g, 0.4)
    var maxY = 0.0
    let tStart = g.clock
    while g.pb.x < Double(m.x) + 14 && g.clock - tStart < 20 {
        g.stick = 1; g.jumpHeld = g.pb.hitWall; g.tick(1.0 / 60.0)
        if g.pb.x >= Double(m.x) && g.pb.x <= Double(m.x + 3) { maxY = max(maxY, g.pb.y) }
    }
    g.stick = 0; g.jumpHeld = false
    check(maxY > 0 && maxY < Double(m.ground) + 0.05, String(format: "walked across the shaft's cover without falling in (lowest y over the shaft %.2f, cover row %d)", maxY, m.ground))
    // from the bottom gallery, climb all the way up and step out
    g.debugTeleport(Double(m.x + 1) + 0.5, Double(m.bottom) - 0.01)
    step(g, 0.3)
    var t = 0.0
    while g.pb.y > Double(m.ground) - 0.05 && t < 60 { g.jumpHeld = true; g.tick(1.0 / 60.0); t += 1.0 / 60.0 }
    g.jumpHeld = false
    check(g.pb.y <= Double(m.ground) + 0.05, String(format: "climbed the ladder from the bottom (%d rows) to the surface in %.0f s", m.bottom - m.ground, t))
    // the mine's chests hold mining loot from the mine tables
    var found: [Stack] = []
    for c in m.plan?.chests ?? [] where g.world.tile(c.x, c.y) == .chest || generateChunk(gen, .overworld, floorDiv(c.x, chunkW)).get(c.x - floorDiv(c.x, chunkW) * chunkW, c.y) == .chest {
        found += generateChestLoot(gen, .overworld, c.x, c.y)
    }
    let mineLoot: Set<Item> = Set((MineLoot.common + MineLoot.useful + MineLoot.exceptional).map { $0.item })
    check(!found.isEmpty && found.allSatisfy { mineLoot.contains($0.item) }, "mine chests hold miners' supplies (\(Set(found.map { $0.item.name }).sorted()))")
    // and the treasure map shows the shaft
    g.mapCache = nil
    let map = g.treasureMap()
    check(map.markers.contains { $0.kind == 5 } || gen.mineSites(overlapping: map.x0, map.x1).isEmpty, "the treasure map marks old mines in its range")
}
do {
    // flat worlds: grottos only with caves on, and their passages stay under the crust
    let off = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, options: WorldOptions(flat: true, trees: true, structures: true, caves: false))
    let on = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, options: WorldOptions(flat: true, trees: true, structures: true, caves: true))
    check(!off.hasGrottos && on.hasGrottos, "flat worlds have grottos only when caves are on")
    var worst = Int.max
    for c in -40...40 {
        guard let s = on.grottoSite(cell: c) else { continue }
        worst = min(worst, s.floorY - s.passLen - 4 - WorldGen.flatSurface)
        if s.open { worst = -999 }
    }
    check(worst >= WorldGen.flatCrust, "every flat-world grotto passage ends below the \(WorldGen.flatCrust)-row crust (closest: \(worst) rows down)")
    // birch logs: chopping gives birch logs, which build solid blocks and make planks
    check(Tile.birchLog.placedForm == .birchLogBlock && Tile.birchLogBlock.solid && !Tile.birchLog.solid && recipe(.block(.planks)) != nil && RecipeBook.all.contains { $0.cost.first?.item == .block(.birchLog) }, "birch logs are passable trunks, build solid blocks, and saw into planks")
}

// ---------------------------------------------------------------- F. enemies
print("== enemies")
func spawnAt(_ g: Game, _ k: MobKind, _ dx: Double) -> Mob {
    let m = g.addMob(k, g.pb.x + dx, 100)
    m.persistent = true
    g.mobGrid.rebuild(g.mobs)
    return m
}
func arenaFight() -> Game {
    let g = arena()
    g.monstersEnabled = true
    g.settings.peaceful = false
    return g
}
do {
    // every new creature draws: frames exist and none is blank
    var bad: [String] = []
    for k in [MobKind.crawler, .golem, .archer, .sentinel, .mimic, .warden] {
        let art = creatureArt(k, 0).0
        if art.isEmpty || art.contains(where: { opaqueCount($0) < 20 }) { bad.append("\(k)") }
    }
    check(bad.isEmpty, "the six new creatures all have full sets of frames (\(bad))")
    // and they render in a scene with their attacks running
    let g = arenaFight()
    g.godMode = true
    for (i, k) in [MobKind.crawler, .golem, .archer, .mimic].enumerated() { _ = spawnAt(g, k, -8 + Double(i) * 5) }
    var ctx = GraphicsContext()
    for _ in 0..<120 { g.tick(1.0 / 60.0); WorldRenderer.draw(&ctx, CGSize(width: 1100, height: 800), g) }
    check(true, "a scene with crawlers, golems, archers and mimics ticks and draws for 2 s")
}
do {
    // the crawler closes fast and pounces
    let g = arenaFight()
    let m = spawnAt(g, .crawler, 7)
    let hp0 = g.hp
    var pounced = false
    var t = 0.0
    while t < 4 { g.tick(1.0 / 60.0); t += 1.0 / 60.0; if m.st == 4 { pounced = true } }
    check(pounced && g.hp < hp0, String(format: "a cave crawler runs in and pounces (hp %.0f -> %.0f)", hp0, g.hp))
}
do {
    // the golem: blades barely scratch it, a hammer cracks it; it barely flinches from a sword
    var per: [Double] = []
    var kb: [Double] = []
    for it in [Item.sword(.iron), .hammer(.iron)] {
        let g = arenaFight()
        let m = spawnAt(g, .golem, 1.6)
        g.facing = 1; g.swingDir = 1
        let h0 = m.hp
        g.swingEmpty(it)
        per.append(h0 - m.hp)
        kb.append(abs(m.b.vx))
    }
    _ = per
    // fixed blows (no random critical hits): a blade's cut against a hammer's crushing blow
    var cut: [Double] = []
    for (amount, heavy) in [(Item.sword(.iron).meleeDamage, false), (Item.hammer(.iron).meleeDamage, true)] {
        let g = arenaFight()
        let m = spawnAt(g, .golem, 1.6)
        let h0 = m.hp
        var info = DamageInfo(amount: amount, type: .melee, source: .player)
        info.heavy = heavy
        _ = g.applyMobDamage(m, info)
        cut.append(h0 - m.hp)
    }
    let swordRatio = cut[0] / Item.sword(.iron).meleeDamage
    check(swordRatio < 0.7 && cut[1] > cut[0] * 2.5, String(format: "a sword does %.1f to a stone golem (%.0f%% of its damage), an iron hammer %.1f", cut[0], swordRatio * 100, cut[1]))
    check(kb[0] < 1.5 && kb[1] > kb[0] * 3, String(format: "a sword hardly moves it (knockback %.1f), a hammer shoves it (%.1f)", kb[0], kb[1]))
    // the slam is telegraphed: standing in the marked ground hurts, stepping out in time does not
    for dodge in [false, true] {
        let g = arenaFight()
        let m = spawnAt(g, .golem, 2.2)
        m.dir = -1
        let hp0 = g.hp
        var warned = false
        var t = 0.0
        while t < 3.0 {
            if !g.dangerZones.isEmpty { warned = true }
            g.stick = (dodge && warned) ? -1 : 0
            g.tick(1.0 / 60.0); t += 1.0 / 60.0
            if m.st == 4 { break }
        }
        g.stick = 0
        step(g, 0.2)
        if dodge {
            check(warned && g.hp == hp0, String(format: "seeing the golem's warning and stepping back avoids the slam (hp %.0f)", g.hp))
        } else {
            check(warned && g.hp < hp0, String(format: "staying in the warned area takes the slam (hp %.0f -> %.0f)", hp0, g.hp))
        }
    }
}
do {
    // the archer keeps its distance and shoots arcs that reach the player
    let g = arenaFight()
    let m = spawnAt(g, .archer, 10)
    let hp0 = g.hp
    var arrows = 0
    var t = 0.0
    while t < 5 {
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        arrows = max(arrows, g.projectiles.filter { $0.kind == .arrow && $0.source.kind != .player }.count)
    }
    check(arrows > 0 && g.hp < hp0, String(format: "a skeleton archer 10 blocks off shoots arrows that land (hp %.0f -> %.0f)", hp0, g.hp))
    // walking up to it makes it back away
    let g2 = arenaFight()
    g2.godMode = true
    let a = spawnAt(g2, .archer, 3.0)
    let d0 = abs(a.b.x - g2.pb.x)
    step(g2, 1.5)
    check(abs(a.b.x - g2.pb.x) > d0 + 1.5, String(format: "an archer the player walks up to backs away (%.1f -> %.1f blocks)", d0, abs(a.b.x - g2.pb.x)))
}
do {
    // mimic: an underground chest in a newer world that wakes when opened
    let g = arenaFight()
    var spot: (Int, Int)? = nil
    // a dug-out room deep underground (mimics only lurk below the surface)
    let px = Int(floor(g.pb.x))
    var deep = 220
    for y in 200...260 where spot == nil { for dx in 2...30 where spot == nil { if hash2(px + dx, y - 1, g.gen.seed &+ 909) < 0.08 { spot = (px + dx, y - 1); deep = y } } }
    g.world.loadAround(centerX: px, radius: 4)
    for x in (px - 4)...(px + 34) { for y in (deep - 4)...(deep - 1) { g.world.set(x, y, .air) }; g.world.set(x, deep, .stone) }
    g.debugTeleport(Double(px) + 0.5, Double(deep) - 0.01)
    if spot == nil {
        // move the arena floor down until a mimic spot turns up near the player
        check(false, "no mimic spot near the arena")
    } else {
        let (cx, cy) = spot!
        g.world.set(cx, cy, .chest)
        g.pb.x = Double(cx) - 1.5
        g.interact(Double(cx) + 0.5, Double(cy) + 0.5)
        let mim = g.mobs.first { $0.kind == .mimic }
        check(mim != nil && g.world.tile(cx, cy) == .air && !(mim?.loot.isEmpty ?? true), "opening an unopened underground chest can wake a mimic, which carries the chest's loot (\(mim?.loot.count ?? 0) stacks)")
        if let mm = mim {
            // a save made while it is loose keeps the chest and the loot
            let save = g.makeSave()
            let key = g.world.chestKey(cx, cy)
            let entry = save.chests.first { $0.key == key }
            let chunk = save.chunks.first { $0.cx == floorDiv(cx, chunkW) }
            let tiles = chunk.map { World.unrle([UInt8]($0.data), chunkW * g.world.H) } ?? []
            let idx = (cx - floorDiv(cx, chunkW) * chunkW) * g.world.H + cy
            check(entry?.items.count == mm.loot.count && idx < tiles.count && tiles[idx] == Tile.chest.rawValue, "saving with the mimic still loose puts its chest and loot back in the save")
            let lootN = mm.loot.count
            let drops0 = g.drops.count
            g.killMob(mm, true)
            check(g.drops.count >= drops0 + lootN, "killing it drops its hoard (\(g.drops.count - drops0) drops)")
        }
        // the same chest, once opened (recorded), never becomes a mimic
        g.world.set(cx, cy, .chest)
        g.world.setChestItems(cx, cy, [])
        g.mobs.removeAll()
        g.interact(Double(cx) + 0.5, Double(cy) + 0.5)
        check(!g.mobs.contains { $0.kind == .mimic } && g.openChest != nil, "a chest the player placed or opened is always just a chest")
    }
}
do {
    // the grotto's guardian
    let gen = WorldGen(seed: 4242, infinite: true, rareChance: 0.28)
    guard let s = findGrotto(gen, open: true) else { fatalError() }
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.godMode = true
    g.debugTeleport(Double(s.x) - 6.5, Double(s.floorY - 1) - 0.01)
    step(g, 0.5)
    guard let sen = g.mobs.first(where: { $0.kind == .sentinel }) else { check(false, "no sentinel woke in the grotto"); fatalError() }
    check(g.activeBoss === sen, "entering a grotto wakes its Crystal Sentinel, with a boss bar")
    var shards = 0, zones = 0
    var t = 0.0
    var attacks: [Int] = []
    var lastSt = 0
    while t < 20 {
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        shards = max(shards, g.projectiles.filter { $0.kind == .shard }.count)
        if t > 2 && sen.hp > sen.maxHP * 0.5 { sen.hp = sen.maxHP * 0.5 }
        zones = max(zones, g.dangerZones.count)
        if sen.st == 1 && lastSt != 1 { attacks.append(sen.atk) }
        lastSt = sen.st
    }
    print("   sentinel attacks: \(attacks)")
    check(shards >= 3 && zones > 0 && sen.phase == 2, "it throws fans of crystal shards and, hurt, marks crystal spikes on the floor (shards \(shards), warnings \(zones))")
    let inRange = abs(sen.b.x - sen.homeX) <= 21
    check(inRange, String(format: "it stays in its grotto (%.1f blocks from the centre)", abs(sen.b.x - sen.homeX)))
    g.killMob(sen, true)
    check(g.defeated.contains(WorldGen.sentinelKey(s.cell)) && g.drops.contains { $0.stack.item == .mat(.crystalShard) }, "defeated, it drops crystal shards and stays defeated")
    step(g, 1.0)
    check(!g.mobs.contains { $0.kind == .sentinel && $0.hp > 0 }, "and no new sentinel appears")
}
do {
    // the Hollow Warden's citadel in the Umbral realm
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.godMode = true
    guard let c = g.gen.citadel else { check(false, "no citadel"); fatalError() }
    let gen2 = WorldGen(seed: 4242, infinite: true, rareChance: 0.28, genVersion: 2)
    check(gen2.citadel == nil, "older worlds have no citadel (their Umbral realm is unchanged)")
    // level floor through the hall
    var floors = Set<Int>()
    for x in (c.x - 48)...(c.x + 48) { floors.insert(g.gen.uFloor(x)) }
    check(floors == [c.floor], "the citadel's floor is level for 97 columns (rows \(floors.sorted()))")
    // walking in from the rift side, through the gate, to the throne
    g.travelTo(.umbral, arriveX: Double(c.x + c.gate * 105) + 0.5, arriveY: Double(g.gen.uFloor(c.x + c.gate * 105)) - 0.5, silent: true)
    g.monstersEnabled = false
    step(g, 0.5)
    let walk1 = walkFar(g, Double(-c.gate), abs(g.pb.x - (Double(c.x) + 0.5)) - 20, 120)
    check(walk1.stuck.isEmpty, String(format: "walked %.0f blocks down the ramp and through the citadel gate", walk1.moved) + (walk1.stuck.isEmpty ? "" : " STUCK \(walk1.stuck.prefix(2))"))
    step(g, 0.5)
    guard let w = g.mobs.first(where: { $0.kind == .warden }) else { check(false, "the Warden did not rise"); fatalError() }
    check(g.activeBoss === w, "the Hollow Warden rises as the player enters its hall")
    var sawSweepWarn = false, bolts = 0, imps = 0, pillars = 0, blinks = 0
    var lastX = w.b.x
    var t = 0.0
    while t < 40 {
        // knock it through the phases
        if t > 10 && w.hp > w.maxHP * 0.6 { w.hp = w.maxHP * 0.6 }
        if t > 22 && w.hp > w.maxHP * 0.3 { w.hp = w.maxHP * 0.3 }
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if w.st == 1 && w.atk == WardenAtk.sweep.rawValue && !g.dangerZones.isEmpty { sawSweepWarn = true }
        bolts = max(bolts, g.projectiles.filter { $0.kind == .bolt }.count)
        imps = max(imps, g.mobs.filter { $0.kind == .imp }.count)
        if w.st == 1 && w.atk == WardenAtk.pillars.rawValue { pillars = max(pillars, g.dangerZones.count) }
        if abs(w.b.x - lastX) > 2.5 { blinks += 1 }
        lastX = w.b.x
    }
    check(sawSweepWarn && bolts > 0, "phase 1: a telegraphed scythe sweep and shadow bolts (\(bolts) in the air at once)")
    check(imps >= 2 && w.phase >= 2, "phase 2: it calls up servants (\(imps) imps)")
    check(w.phase == 3 && pillars >= 3, "phase 3: void pillars are marked before they erupt (\(pillars) warnings)")
    check(blinks > 0, "from phase 2 it blinks to the player's far side (\(blinks) blinks)")
    let leash = abs(w.b.x - w.homeX) <= 38
    check(leash, "it never leaves its hall")
    g.killMob(w, true)
    check(g.defeated.contains(WorldGen.wardenKey) && g.drops.contains { $0.stack.item == .mat(.umbralHeart) }, "defeated, it drops its Umbral heart and stays defeated")
    let sig = recipe(.gear(.wardenSigil))
    check(sig?.station == .forge && sig?.cost.contains { $0.item == .mat(.umbralHeart) } == true, "the heart forges the Warden's Sigil at the rift forge")
    // the sigil: harder hits, softer blows (fixed blows, so a critical hit cannot skew it)
    let ga = arena()
    var dealt: [Double] = []
    var taken: [Double] = []
    for wear in [false, true] {
        ga.inv.armor[3] = wear ? Stack(item: .gear(.wardenSigil), count: 1) : nil
        let z = lineup(ga, .zombie, [1.4])[0]
        let h0 = z.hp
        _ = ga.applyMobDamage(z, DamageInfo(amount: 10, type: .melee, source: .player))
        dealt.append(h0 - z.hp)
        ga.maxHP = 100
        ga.hp = ga.maxHP
        ga.invuln = 0
        var hit = DamageInfo(amount: 20, type: .fire, source: .environment)
        hit.originX = ga.pb.x
        _ = ga.hurtPlayer(hit)
        taken.append(ga.maxHP - ga.hp)
    }
    check(near(dealt[1], dealt[0] * 1.2, 0.01) && near(taken[1], taken[0] * 0.85, 0.01), String(format: "wearing the Warden's Sigil: a 10-point blow deals %.1f instead of %.1f, and 20 damage taken (rounded to whole points) becomes %.1f instead of %.1f", dealt[1], dealt[0], taken[1], taken[0]))
}

// ---------------------------------------------------------------- G. animals
print("== animals")
func animalArena(night: Bool) -> Game {
    let g = arena()
    // a wide, open field so fleeing animals never run into hills
    let cx = Int(floor(g.pb.x))
    g.world.loadAround(centerX: cx, radius: 9)
    for x in (cx - 130)...(cx + 130) {
        for y in 40..<100 { g.world.set(x, y, .air) }
        for y in 100..<106 { g.world.set(x, y, .stone) }
        g.world.set(x, 100, .grass)
    }
    g.timeOfDay = night ? 0.78 : 0.3
    g.godMode = true
    step(g, 0.05)
    return g
}
do {
    // a wolf runs down a pig at night while the player is out of sight
    let g = animalArena(night: true)
    g.pb.x -= 36
    // the wolf comes from the far side, so the pig runs toward the player and stays inside the 72
    // blocks where creatures are updated (a pig that fled past that would simply wait there)
    let pig = g.addMob(.pig, g.pb.x + 52, 100); pig.persistent = true
    let wolf = g.addMob(.wolf, g.pb.x + 62, 100); wolf.persistent = true
    var hunted = false, fled = false
    var t = 0.0
    while t < 30 && pig.hp > 0 {
        g.tick(1.0 / 60.0); t += 1.0 / 60.0
        if wolf.preyID == pig.id { hunted = true }
        if pig.t2 > 0 { fled = true }
    }
    check(hunted && fled && pig.hp <= 0, String(format: "at night a wolf hunts down a pig, which runs (killed after %.0f s)", t))
    step(g, 0.2)
    check(wolf.poseT > 0 || wolf.preyID == 0, "after the kill the wolf rests and lets go of its prey")
    // by day the same wolf leaves it alone
    let g2 = animalArena(night: false)
    g2.pb.x -= 36
    let pig2 = g2.addMob(.pig, g2.pb.x + 60, 100); pig2.persistent = true
    let wolf2 = g2.addMob(.wolf, g2.pb.x + 50, 100); wolf2.persistent = true
    step(g2, 10)
    check(pig2.hp == pig2.maxHP && wolf2.preyID == 0, "by day wolves do not hunt")
}
do {
    // herds drift back together
    let g = animalArena(night: false)
    let a = g.addMob(.cow, g.pb.x - 8, 100); a.persistent = true
    let b = g.addMob(.cow, g.pb.x + 8, 100); b.persistent = true
    let d0 = abs(a.b.x - b.b.x)
    var closest = d0
    var t = 0.0
    while t < 60 { g.tick(1.0 / 60.0); t += 1.0 / 60.0; closest = min(closest, abs(a.b.x - b.b.x)) }
    check(closest < 8, String(format: "two cows %.0f blocks apart (within sight of each other) drift together (closest %.1f)", d0, closest))
    // animals walk to water and drink
    let g2 = animalArena(night: false)
    let px = Int(floor(g2.pb.x))
    for x in (px + 10)...(px + 14) { g2.world.set(x, 100, .water) }
    let cow = g2.addMob(.cow, g2.pb.x + 3, 100); cow.persistent = true
    var drank = false
    t = 0
    while t < 90 && !drank { g2.tick(1.0 / 60.0); t += 1.0 / 60.0; if cow.poseT > 0 && abs(cow.b.x - Double(px + 10)) < 2.5 { drank = true } }
    check(drank, String(format: "a cow near a pond walks to the edge and drinks (after %.0f s)", t))
    // at night farm animals settle down
    var moved: [Double] = []
    for night in [false, true] {
        let gn = animalArena(night: night)
        var pigs: [Mob] = []
        for i in 0..<6 { let p = gn.addMob(.pig, gn.pb.x - 20 + Double(i) * 8, 100); p.persistent = true; pigs.append(p) }
        var travel = 0.0
        for _ in 0..<1800 { gn.tick(1.0 / 60.0); for p in pigs { travel += abs(p.b.vx) / 60.0 } }
        moved.append(travel)
    }
    check(moved[1] < moved[0] * 0.5, String(format: "pigs wander %.0f blocks in 30 s by day, %.0f at night", moved[0], moved[1]))
}

// ---------------------------------------------------------------- H. vehicle parts
print("== vehicle parts")
func carWith(_ g: Game, _ extra: [(Int, Int, PartType)], wheel: PartType = .wheel) -> Vehicle {
    let v = Vehicle(id: g.newID(), first: .frame, x: 0, y: 0)
    v.parts.removeAll()
    for p in kitLayout(.carKit) { v.parts[PartCell(dx: p.dx, dy: p.dy)] = isWheelPart(p.p) ? wheel : p.p }
    for e in extra { v.parts[PartCell(dx: e.0, dy: e.1)] = e.2 }
    v.recompute(keepAnchor: false)
    v.placeBox(left: g.pb.x + 3, bottom: 100)
    v.fuel = v.fuelCapacity
    g.vehicles.append(v)
    return v
}
do {
    let g = arena()
    g.godMode = true
    let layout = kitLayout(.carKit)
    let topY = layout.map { $0.dy }.min()!
    let cargoCell = (layout.map { $0.dx }.min()!, topY - 1)
    let v = carWith(g, [(cargoCell.0, cargoCell.1, .cargo)])
    step(g, 0.5)
    check(v.parts[PartCell(dx: cargoCell.0, dy: cargoCell.1)] == .cargo, "a cargo crate fits on top of a car")
    g.interactVehicle(v, PartCell(dx: cargoCell.0, dy: cargoCell.1))
    guard let k = g.openChest else { check(false, "tapping the crate did not open it"); fatalError() }
    check(g.isCargoSpot(k) && g.showInventory, "tapping the crate opens its storage")
    g.world.setChestItems(k.x, k.y, [Stack(item: .mat(.ironBar), count: 7), Stack(item: .block(.torch), count: 20)])
    g.openChest = nil
    g.showInventory = false
    // drive off: the cargo travels with the vehicle
    g.inVehicle = v; v.rider = true
    for _ in 0..<120 { g.stick = 1; g.tick(1.0 / 60.0) }
    g.stick = 0
    g.inVehicle = nil; v.rider = false
    check(g.world.chestItems(k.x, k.y).count == 2, "the crate's contents travel with the car")
    // saved and loaded with the world
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(back, settings: Settings())
    let v2 = g2.vehicles.first { $0.id == v.id }
    let k2 = v2.map { g2.cargoSpot($0, PartCell(dx: cargoCell.0, dy: cargoCell.1)) }
    check(v2 != nil && k2 == k && g2.world.chestItems(k2!.x, k2!.y).count == 2, "after saving and loading, the crate still holds its cargo")
    // taking the crate off spills its contents
    let drops0 = g.drops.count
    g.removeVehiclePart(v, PartCell(dx: cargoCell.0, dy: cargoCell.1))
    check(g.drops.count >= drops0 + 2 && g.world.chests[g.world.chestKey(k.x, k.y)] == nil, "removing the crate tips its contents out")
}
do {
    // offroad wheels pull a loaded car up a steep slope faster
    var reach: [Double] = []
    for wheel in [PartType.wheel, .offroadWheel] {
        let g = arena()
        g.godMode = true
        let px = Int(floor(g.pb.x))
        // a long slope rising one block every column-and-a-half
        for i in 0..<40 { let h = Int(Double(i) / 1.5); if h > 0 { for y in (100 - h)..<100 { g.world.set(px + 10 + i, y, .stone) } } }
        let v = carWith(g, [(0, 0, .cargo), (3, 0, .cargo), (0, -1, .cargo), (1, -1, .cargo)], wheel: wheel)
        step(g, 0.5)
        g.inVehicle = v; v.rider = true
        var best = 0.0
        for _ in 0..<480 { g.stick = 1; g.tick(1.0 / 60.0); best = max(best, 100 - v.b.y) }
        g.stick = 0
        reach.append(best)
    }
    check(reach[1] > reach[0] * 1.05, String(format: "a car loaded with four crates climbs a 1-in-1.5 slope %.1f blocks in 8 s on ordinary wheels, %.1f on offroad wheels", reach[0], reach[1]))
    // the pull itself: the same loaded car pulling away from a standstill on flat ground
    var pull: [Double] = []
    for wheel in [PartType.wheel, .offroadWheel] {
        let g = arena()
        g.godMode = true
        let v = carWith(g, [(0, 0, .cargo), (3, 0, .cargo), (0, -1, .cargo), (1, -1, .cargo)], wheel: wheel)
        step(g, 0.8)
        g.inVehicle = v; v.rider = true
        let x0 = v.px
        for _ in 0..<45 { g.stick = 1; g.tick(1.0 / 60.0) }
        g.stick = 0
        pull.append(v.px - x0)
    }
    check(pull[1] > pull[0] * 1.3, String(format: "loaded, offroad wheels pull away harder: %.2f blocks in the first 0.75 s against %.2f", pull[1], pull[0]))
    // headlights light the way while driving
    var lv: [Int] = []
    for lamp in [false, true] {
        let g = arena()
        g.godMode = true
        g.timeOfDay = 0.78
        let layout = kitLayout(.carKit)
        let front = layout.map { $0.dx }.max()! + 1
        let midY = layout.filter { $0.dx == front - 1 }.map { $0.dy }.min()!
        let v = carWith(g, lamp ? [(front, midY, .headlight)] : [])
        let px = Int(floor(g.pb.x))
        for x in (px - 30)...(px + 40) { for y in 80..<95 { g.world.set(x, y, .stone) } }
        step(g, 0.5)
        g.inVehicle = v; v.rider = true; v.dir = 1
        g.light.valid = false
        step(g, 0.3)
        let ix = Int(floor(v.b.right)) + 6
        lv.append(g.light.level(ix, Int(floor(v.b.y - 0.8))).1)
    }
    check(lv[1] >= lv[0] + 3, "a headlight lights the ground 6 blocks ahead (light \(lv[0]) -> \(lv[1]))")
    check(drillPower(.voidDrill).0 >= Tile.voidOre.def.tier && drillPower(.voidDrill).1 > drillPower(.diamondDrill).1, "the void drill bores through voidium and digs faster than the diamond drill")
    let recipes: [PartType] = [.offroadWheel, .headlight, .cargo, .voidDrill]
    check(recipes.allSatisfy { recipe(.part($0)) != nil }, "all four new parts can be crafted")
}

// ---------------------------------------------------------------- I. journal
print("== journal")
do {
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.viewW = 1100; g.viewH = 800
    g.godMode = true
    g.monstersEnabled = false
    check(g.journal.places.isEmpty && !g.journalAims()[0].done, "a new world starts with an empty journal and open goals")
    // walking into places writes them down, with their story
    check(g.gen.villages(overlapping: -3000, 3000).isEmpty && g.journalAims().allSatisfy { !$0.title.lowercased().contains("village") }, "a new world has no villages, and no goal asks for one")
    let m = (-30...30).compactMap { g.gen.mineSite(cell: $0) }.first!
    g.debugTeleport(Double(m.x + 1) + 0.5, Double(m.ground) - 0.01)
    step(g, 1.0)
    check(g.journal.has("mine:\(m.cell)") && g.journal.lore.contains("mine"), "standing at a mine's headframe records the old mine")
    let gs = (-40...40).compactMap { g.gen.grottoSite(cell: $0) }.first!
    g.debugTeleport(Double(gs.x) - 3.5, Double(gs.floorY - 1) - 0.01)
    step(g, 1.0)
    check(g.journal.has("grotto:\(gs.cell)"), "entering a grotto records it")
    for mm in g.mobs where mm.kind == .sentinel { mm.removed = true }
    step(g, 0.1)
    // the aims tick off from what has happened
    let aims = g.journalAims()
    check(aims[2].done && aims[3].done && !aims[4].done, "goals: mine and grotto ticked off; Ursavor still open")
    // relic fragments counted as they are picked up
    g.drops.append(DropItem(stack: Stack(item: .mat(.relicFragment), count: 3), x: g.pb.x, y: g.pb.y - 0.5, vx: 0, vy: 0, pickDelay: 0))
    step(g, 0.5)
    check(g.journal.relics == 3, "picking up relic fragments counts them (\(g.journal.relics))")
    // crafting is noted
    g.inv.slots = [Stack?](repeating: nil, count: Inventory.size)
    _ = g.inv.add(.block(.planks), 8)
    g.craft(recipe(.block(.workbench))!)
    check(g.journalAims()[0].done, "crafting a workbench ticks off the first goal")
    // save and load keep it all; a save from before the journal still loads
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(back, settings: Settings())
    check(g2.journal.places.count == g.journal.places.count && g2.journal.relics == 3 && g2.journal.lore == g.journal.lore, "the journal is saved with the world")
    var obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    obj.removeValue(forKey: "journal")
    let oldData = try! JSONSerialization.data(withJSONObject: obj)
    let old = try? JSONDecoder().decode(SaveData.self, from: oldData)
    check(old != nil && Game.load(old!, settings: Settings()).journal.places.isEmpty, "a save from before the journal loads with an empty one")
    // the panel builds its view
    _ = JournalPanel(game: g, hud: g.hud).body
    check(true, "the journal panel builds")
}
// ---------------------------------------------------------------- J. weather, light, settings
print("== weather, light and settings")
do {
    // rain keeps a zombie from burning at dawn and puts out a burning player
    func soak(_ g: Game) {
        g.debugForceWeather(.heavyRain)
        g.weather.precip = 1.0
        g.weather.cover = 1.0
        g.weather.stateDur = 999
    }
    for rain in [false, true] {
        let g = arena()
        g.timeOfDay = 0.3
        if rain { soak(g) }
        let z = g.addMob(.zombie, g.pb.x + 8, 100); z.persistent = true
        g.godMode = true
        step(g, 1.0)
        check(rain ? z.burn <= 0 : z.burn > 0, rain ? "in the rain a zombie does not catch fire by day (rain there \(String(format: "%.2f", g.precipAt(z.b.x))), \(g.biomeHere.name))" : "in sunshine a zombie burns by day")
    }
    let g = arena()
    soak(g)
    g.playerBurn = 3.0
    step(g, 0.2)
    check(g.playerBurn == 0, "standing in the rain puts out a burning player (rain here \(String(format: "%.2f", g.weatherRain)))")
    // deserts stay (nearly) dry under a passing storm
    let gd = arena()
    soak(gd)
    step(gd, 0.2)
    check(gd.biomeHere != .desert || gd.weatherRain < 0.15, "deserts get almost no rain")
    // light: a lone column on flat ground no longer leaves a dark shaft beneath it
    let gl = arena()
    let px = Int(floor(gl.pb.x)) + 6
    for k in 1...4 { gl.world.set(px, 100 - k, .cactus) }
    gl.timeOfDay = 0.3
    gl.light.valid = false
    step(gl, 0.2)
    let under = (101...106).map { gl.light.level(px, $0).0 }
    let beside = (101...106).map { gl.light.level(px + 3, $0).0 }
    check(zip(under, beside).allSatisfy { $0.0 >= $0.1 - 1 }, "under a cactus the ground is lit like the ground beside it (sky light \(under) vs \(beside))")
    // settings saved before sound existed load with sound on (and keep what they had; the look starts
    // afresh, since it was saved before the hair and clothing styles: see the art suite)
    let old = #"{"hair":2,"tilePx":32}"#
    let st = try! JSONDecoder().decode(Settings.self, from: old.data(using: .utf8)!)
    check(st.soundOn && near(st.sfxVolume, 0.7, 0.001) && st.tilePx == 32, "older settings load with sound on at the default volumes")
}
print("")
print(fails == 0 ? "ALL \(passes) TESTS PASSED" : "\(fails) FAILED, \(passes) passed")
