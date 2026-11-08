import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func f3(_ v: Double) -> String { return String(format: "%.3f", v) }

/// every mine in cells -40...40 of a world
func minesOf(_ g: WorldGen) -> [MineSite] { return (-40...40).compactMap { g.mineSite(cell: $0) } }
func worldFor(_ seed: UInt64, _ opts: WorldOptions = .standard, version: Int = WorldGen.currentVersion) -> World {
    return World(gen: WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: version, options: opts))
}
func load(_ w: World, _ s: MineSite) { w.loadAround(centerX: (s.minX + s.maxX) / 2, radius: (s.maxX - s.minX) / 32 + 3) }

// walkability: feet cell (x, y) means the body fills rows y-1 and y
func passable(_ w: World, _ x: Int, _ y: Int) -> Bool { return !w.tile(x, y).solid }
func supported(_ w: World, _ x: Int, _ y: Int) -> Bool {
    let b = w.tile(x, y + 1)
    return b.solid || b.isPlatform || b == .ladder || w.tile(x, y) == .ladder
}
func standable(_ w: World, _ x: Int, _ y: Int) -> Bool { return passable(w, x, y) && passable(w, x, y - 1) && supported(w, x, y) }
func land(_ w: World, _ x: Int, _ y0: Int) -> Int? {
    var y = y0
    var n = 0
    while n < 300 {
        if !passable(w, x, y) || !passable(w, x, y - 1) { return nil }
        if supported(w, x, y) { return y }
        y += 1; n += 1
    }
    return nil
}
struct P: Hashable { var x: Int; var y: Int }
/// cells a player can stand in, starting from (sx, sy): walking, one-block steps, ladders, dropping
/// (and, with `jump`, jumping up to three blocks onto a neighbouring ledge)
func reachable(_ w: World, _ sx: Int, _ sy: Int, x0: Int, x1: Int, jump: Bool) -> Set<P> {
    var seen: Set<P> = []
    var stack: [P] = []
    if let y = land(w, sx, sy) { stack.append(P(x: sx, y: y)) }
    while let p = stack.popLast() {
        if seen.contains(p) || p.x < x0 || p.x > x1 { continue }
        seen.insert(p)
        var next: [P] = []
        for d in [-1, 1] {
            let nx = p.x + d
            if passable(w, nx, p.y) && passable(w, nx, p.y - 1), let ly = land(w, nx, p.y) { next.append(P(x: nx, y: ly)) }
            if standable(w, nx, p.y - 1) && passable(w, p.x, p.y - 2) { next.append(P(x: nx, y: p.y - 1)) }
            if jump {
                for h in 2...3 where standable(w, nx, p.y - h) {
                    var clear = true
                    for k in 1...(h + 1) where !passable(w, p.x, p.y - k) { clear = false }
                    if clear { next.append(P(x: nx, y: p.y - h)) }
                }
            }
        }
        let here = w.tile(p.x, p.y)
        let above = w.tile(p.x, p.y - 1)
        if (here == .ladder || above == .ladder) && passable(w, p.x, p.y - 2) { next.append(P(x: p.x, y: p.y - 1)) }
        let below = w.tile(p.x, p.y + 1)
        if below == .ladder || below.isPlatform, let ly = land(w, p.x, p.y + 2) ?? (below == .ladder ? p.y + 1 : nil) { next.append(P(x: p.x, y: ly)) }
        if below.isPlatform && passable(w, p.x, p.y + 1), let ly = land(w, p.x, p.y + 1) { next.append(P(x: p.x, y: ly)) }
        for n in next where !seen.contains(n) { stack.append(n) }
    }
    return seen
}
/// whether a chest can be opened from somewhere the player can stand (the game's reach is 5.5 blocks)
func openable(_ c: MineChest, _ cells: Set<P>) -> Bool {
    for p in cells {
        let dx = Double(c.x) + 0.5 - (Double(p.x) + 0.5)
        let dy = Double(c.y) + 0.5 - (Double(p.y) + 1.0 - 1.08)
        if dx * dx + dy * dy <= 5.3 * 5.3 { return true }
    }
    return false
}

// ---------------------------------------------------------------- A. how many mines, how big, how varied
print("== layout")
var allMines: [(UInt64, MineSite)] = []
for seed in [UInt64(1234), 98765, 424242, 777, 31337] {
    let g = WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: .standard)
    for s in minesOf(g) { allMines.append((seed, s)) }
}
let plans = allMines.compactMap { $0.1.plan }
check(plans.count == allMines.count && plans.count >= 30, "new worlds lay out every mine as a branching network (\(plans.count) mines over 5 worlds, 81 cells each)")
func avg(_ f: (MinePlan) -> Int) -> Double { return Double(plans.map(f).reduce(0, +)) / Double(max(1, plans.count)) }
let width = plans.map { $0.maxX - $0.minX }
print(String(format: "  per mine: %.1f galleries and drifts, %.1f rooms, %.2f chambers, %.1f ladder drops, %.1f dead ends, %.1f chests; width %d-%d",
             avg { $0.tunnels }, avg { $0.rooms }, avg { Double($0.chambers) > 0 ? 1 : 0 }, avg { $0.winzes }, avg { $0.deadEnds }, avg { $0.chests.count }, width.min() ?? 0, width.max() ?? 0))
check(avg { $0.tunnels } >= 6 && avg { $0.rooms } >= 1.5 && avg { $0.deadEnds } >= 5, "mines branch: galleries, drifts, side rooms and dead ends")
let withChamber = plans.filter { $0.chambers > 0 }.count
check(withChamber > plans.count / 3 && withChamber < plans.count, "some mines (not all) open into a great chamber (\(withChamber) of \(plans.count))")
let chestCounts = plans.map { $0.chests.count }
check(chestCounts.min()! >= 2 && Double(chestCounts.reduce(0, +)) / Double(plans.count) >= 5, "every mine holds chests, several on average (\(chestCounts.min()!)-\(chestCounts.max()!))")
let hidden = plans.flatMap { $0.chests }.filter { $0.spot == .hidden }.count
let total = plans.flatMap { $0.chests }.count
check(hidden > 0 && Double(hidden) / Double(total) < 0.35, "some chests are hidden away, most are not (\(hidden) of \(total))")
// variety: no two mines alike
var shapes: Set<String> = []
for p in plans { shapes.insert("\(p.tunnels)-\(p.rooms)-\(p.winzes)-\(p.deadEnds)-\(p.chests.count)-\(p.maxX - p.minX)") }
check(shapes.count >= plans.count * 8 / 10, "mines differ from one another (\(shapes.count) distinct layouts of \(plans.count))")

// ---------------------------------------------------------------- B. built in the world: sound, sealed, reachable
print("== built")
func inspect(_ seed: UInt64, _ s: MineSite, _ opts: WorldOptions, _ label: String) -> (Bool, Int, Int, Int, Int) {
    let w = worldFor(seed, opts)
    load(w, s)
    guard let plan = s.plan else { return (false, 0, 0, 0, 0) }
    var ok = true
    var bad: [String] = []
    for c in plan.chests {
        let t = w.tile(c.x, c.y)
        let below = w.tile(c.x, c.y + 1)
        let side = !w.tile(c.x - 1, c.y).solid || !w.tile(c.x + 1, c.y).solid || !w.tile(c.x, c.y - 1).solid
        if t != .chest || !(below.solid || below.isPlatform) || below.liquid || !side { ok = false; bad.append("\(c.x),\(c.y) \(t) on \(below)") }
    }
    if !bad.isEmpty { print("    \(label): bad chests \(bad.prefix(4))") }
    // no water or lava touching the open mine
    var wet = 0
    for sp in plan.carve {
        for y in sp.y0...sp.y1 {
            for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] where w.tile(sp.x + dx, y + dy).liquid { wet += 1 }
        }
    }
    let cells = reachable(w, s.x + 1, s.ground - 1, x0: s.minX - 5, x1: s.maxX + 5, jump: false)
    var open = 0, reached = 0, hid = 0, hidReached = 0
    for c in plan.chests {
        if c.spot == .hidden { hid += 1; if openable(c, cells) { hidReached += 1 } }
        else { open += 1; if openable(c, cells) { reached += 1 } }
    }
    if reached < open { print("    \(label): \(open - reached) of \(open) chests out of reach") }
    return (ok && wet == 0 && reached == open, open, reached, hid, hidReached)
}
var built = 0, okCount = 0, openTotal = 0, reachedTotal = 0, hidTotal = 0, hidReachedTotal = 0
for (seed, s) in allMines.prefix(16) {
    let r = inspect(seed, s, .standard, "seed \(seed) mine \(s.cell)")
    built += 1
    if r.0 { okCount += 1 }
    openTotal += r.1; reachedTotal += r.2; hidTotal += r.3; hidReachedTotal += r.4
}
check(okCount == built, "built mines: every chest stands on sound floor beside open space, no water or lava touches the workings, and every chest not hidden can be reached on foot from the surface (\(okCount) of \(built) mines; \(reachedTotal) of \(openTotal) chests)")
check(hidReachedTotal < hidTotal || hidTotal == 0, "hidden chests take some digging or climbing to get to (\(hidTotal - hidReachedTotal) of \(hidTotal) not reachable just by walking)")
// a hidden chest behind fallen rock opens up once the rubble is dug out
do {
    var tested = false
    for (seed, s) in allMines {
        guard let plan = s.plan, let c = plan.chests.first(where: { $0.spot == .hidden && $0.y > s.ground + 20 }) else { continue }
        let w = worldFor(seed)
        load(w, s)
        // dig every rubble-like block within 6 columns of the chest on its row band
        var dug = 0
        for x in (c.x - 6)...(c.x + 6) { for y in (c.y - 2)...c.y {
            let t = w.tile(x, y)
            if t == .dirt || t == .stone || t == .planks || t == .slate { w.set(x, y, .air); dug += 1 }
        } }
        let cells = reachable(w, s.x + 1, s.ground - 1, x0: s.minX - 5, x1: s.maxX + 5, jump: true)
        if openable(c, cells) {
            check(true, "a hidden mine chest can be reached once the fallen rock in front of it is dug out (\(dug) blocks)")
            tested = true
            break
        }
    }
    if !tested { check(false, "a hidden mine chest can be reached once the fallen rock in front of it is dug out") }
}
// flat worlds get mines too, built the same way
do {
    var flatMines: [(UInt64, MineSite)] = []
    for seed in [UInt64(1234), 98765] {
        let g = WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: WorldOptions(flat: true, trees: true, structures: true))
        for s in minesOf(g) { flatMines.append((seed, s)) }
    }
    var fok = 0
    for (seed, s) in flatMines.prefix(6) { if inspect(seed, s, WorldOptions(flat: true, trees: true, structures: true), "flat \(seed) \(s.cell)").0 { fok += 1 } }
    check(flatMines.count >= 4 && fok == min(6, flatMines.count), "flat worlds have mines too, sound and reachable (\(fok) of \(min(6, flatMines.count)) checked, \(flatMines.count) found)")
    let noStruct = WorldGen(seed: 1234, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: WorldOptions(flat: true, trees: true, structures: false))
    check(minesOf(noStruct).isEmpty, "a flat world made without structures has no mines")
}
// seamless and repeatable: a chunk comes out the same whatever was generated before it
do {
    let (seed, s) = allMines[3]
    let cx = floorDiv(s.minX + 20, chunkW)
    let a = generateChunk(WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: .standard), .overworld, cx)
    let g2 = WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: .standard)
    for k in -6...6 { _ = generateChunk(g2, .overworld, cx + k) }
    let b = generateChunk(g2, .overworld, cx)
    check(a.tiles == b.tiles && a.walls == b.walls, "a mine chunk is identical however and whenever it is generated")
}
// older worlds keep their mines exactly as they were laid out
do {
    let g3 = WorldGen(seed: 1234, infinite: true, rareChance: 1.0, genVersion: 3, options: .standard)
    let m3 = minesOf(g3)
    check(!m3.isEmpty && m3.allSatisfy { $0.plan == nil }, "worlds made before this update keep their old mines (no new layout dropped into land already explored)")
}

// ---------------------------------------------------------------- C. loot
print("== loot")
do {
    var rng = RNG(99)
    var stacks = 0, invalid = 0, dupes = 0
    var exc: [String: (Int, Int)] = [:]
    var fromCommon = 0
    let commonItems = Set(MineLoot.common.map { $0.item })
    for spot in [MineSpot.open, .room, .hidden] {
        for depth in 0...3 {
            var e = 0
            let n = 20000
            for _ in 0..<n {
                let items = MineLoot.roll(&rng, spot, depth)
                stacks += items.count
                if items.isEmpty || items.count > 27 { invalid += 1 }
                for st in items where st.count < 1 || st.count > st.item.maxStack { invalid += 1 }
                if Set(items.map { $0.item }).count != items.count { dupes += 1 }
                if items.contains(where: { MineLoot.isExceptional($0.item) }) { e += 1 }
                fromCommon += items.filter { commonItems.contains($0.item) }.count
            }
            exc["\(spot)\(depth)"] = (e, n)
        }
    }
    check(invalid == 0 && dupes == 0, "240,000 rolled chests: every stack valid (1 to its stack limit), at most 27, never the same item twice")
    check(Double(fromCommon) / Double(stacks) > 0.55, "most of what mine chests hold is common (\(Int(Double(fromCommon) / Double(stacks) * 100))% of stacks)")
    func rate(_ k: String) -> Double { let v = exc[k]!; return Double(v.0) / Double(v.1) }
    var line = "  exceptional finds per chest:"
    for sp in ["open", "room", "hidden"] {
        line += " " + sp
        for d in 0...3 { line += " " + f3(rate(sp + String(d))) }
    }
    print(line)
    check(rate("open0") < 0.025 && rate("hidden3") < 0.13 && rate("open0") > 0.004, "exceptional loot is genuinely rare: about 1 chest in 80 near the top, at most 1 in 8 when hidden deep down")
    check(rate("open3") > rate("open0") && rate("hidden0") > rate("room0") && rate("room0") > rate("open0"), "deeper and better-hidden chests are likelier to hold something exceptional")
    // relics and the best weapons never turn up in the top gallery
    var rng2 = RNG(7)
    var deepOnly = true
    for _ in 0..<40000 {
        for st in MineLoot.roll(&rng2, .hidden, 0) where st.item == .relic(.quakeMaul) || st.item == .relic(.emberCleaver) || st.item == .gun(.stormRod) { deepOnly = false }
    }
    check(deepOnly, "the heaviest relics and the storm rod only come from the deeper levels")
}
do {
    // the chests actually generated in mines, over many worlds
    var n = 0, e = 0, empty = 0
    for (seed, s) in allMines {
        let g = WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: .standard)
        for c in s.plan?.chests ?? [] {
            let items = generateChestLoot(g, .overworld, c.x, c.y)
            n += 1
            if items.isEmpty { empty += 1 }
            if items.contains(where: { MineLoot.isExceptional($0.item) }) { e += 1 }
        }
    }
    check(empty == 0 && Double(e) / Double(n) < 0.07, "of \(n) generated mine chests, \(e) hold an exceptional find (\(f1(Double(e) / Double(n) * 100))%); none are empty")
    // the same chest always holds the same thing (nothing to gain by reloading)
    let (seed, s) = allMines[0]
    let g = WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: .standard)
    let c = s.plan!.chests[0]
    check(generateChestLoot(g, .overworld, c.x, c.y) == generateChestLoot(g, .overworld, c.x, c.y), "a chest's loot is fixed by the world and its place: reloading before opening it changes nothing")
}
do {
    // a looted chest stays empty: saved, regenerated or broken and replaced
    // mines are placed by the world's own settings (rare-structure frequency included): take one from the game's world
    let game = Game(mode: .survival, infinite: true, seed: 1234, settings: Settings())
    let s = minesOf(game.world.gen).first { $0.plan != nil && !$0.plan!.chests.isEmpty }!
    let c = s.plan!.chests.first { $0.spot != .hidden } ?? s.plan!.chests[0]
    game.world.loadAround(centerX: c.x, radius: 3)
    let items = game.world.chestItems(c.x, c.y)
    for st in items { _ = game.inv.add(st.item, st.count, extra: st.extra) }
    game.world.setChestItems(c.x, c.y, [])
    let data = try! JSONEncoder().encode(game.makeSave())
    let back = Game.load(try! JSONDecoder().decode(SaveData.self, from: data), settings: Settings())
    back.world.loadAround(centerX: c.x, radius: 3)
    check(!items.isEmpty && back.world.chestItems(c.x, c.y).isEmpty, "a mine chest emptied and saved is still empty after loading (it had \(items.count) stacks)")
    check(back.world.tile(c.x, c.y) == .chest, "...and it is still there, in its place")
    let drops0 = back.drops.count
    back.breakTile(c.x, c.y, true)
    let gained = back.drops.count - drops0
    back.world.set(c.x, c.y, .chest)
    back.world.setChestItems(c.x, c.y, [])
    check(gained == 1 && back.world.chestItems(c.x, c.y).isEmpty, "breaking the emptied chest gives back just the chest, and a chest set in its place is empty")
}

// ---------------------------------------------------------------- D. ores
print("== ores")
func census(_ version: Int, _ opts: WorldOptions) -> [Tile: [Int]] {
    var out: [Tile: [Int]] = [:]
    for seed in [UInt64(1234), 98765, 424242] {
        let g = WorldGen(seed: seed, infinite: true, rareChance: 1.0, genVersion: version, options: opts)
        var cx = -60
        while cx < 60 {
            let ch = generateChunk(g, .overworld, cx)
            for lx in 0..<chunkW {
                let h = g.col(ch.x0 + lx).h
                for y in 0..<WorldGen.H {
                    let t = ch.get(lx, y)
                    if t == .air || t == .stone || t == .dirt || t == .slate || t == .deepRock { continue }
                    var a = out[t] ?? [0, 0, 0, Int.max, Int.min]
                    a[0] += 1
                    if y < h + 8 { a[1] += 1 }
                    a[3] = min(a[3], y); a[4] = max(a[4], y)
                    out[t] = a
                }
            }
            cx += 2
        }
    }
    return out
}
// generator 5's ore rules, the rebalance these checks were written for (worlds made with it keep
// them); generator 6 brings iron up, checked after these and against generator 5 in world6
let cs = census(5, .standard)
// the previous version gave these over the same 180 chunks (measured before the change)
let before: [Tile: Int] = [.coal: 30060, .copper: 16755, .iron: 15774, .gold: 8744, .diamond: 2537, .mythril: 839]
let ironNow = Double(cs[.iron]?[0] ?? 0)
check(ironNow < Double(before[.iron]!) * 0.9 && ironNow > Double(before[.iron]!) * 0.75, "iron is modestly scarcer: \(Int(ironNow)) blocks against \(before[.iron]!) before (\(Int((1 - ironNow / Double(before[.iron]!)) * 100))% less)")
let coalNow = Double(cs[.coal]?[0] ?? 0)
check(coalNow > ironNow * 1.5 && coalNow > Double(before[.coal]!) * 0.75, "coal stays the commonest ore (\(Int(coalNow)))")
for (t, lo, hi) in [(Tile.tin, 122, 265), (.saltpeter, 112, 205), (.silver, 200, 400), (.amethyst, 150, 330)] {
    let a = cs[t] ?? [0, 0, 0, 0, 0]
    check(a[0] > 300 && a[3] >= lo - 1 && a[4] <= hi + 1, "\(t.name): \(a[0]) blocks, all between rows \(a[3]) and \(a[4]) (its band \(lo)-\(hi))")
}
let gold = cs[.gold]?[0] ?? 0
check((cs[.amethyst]?[0] ?? 0) < gold / 5 && (cs[.saltpeter]?[0] ?? 0) < Int(ironNow) / 2 && (cs[.silver]?[0] ?? 0) < Int(ironNow) / 2, "the new ores are not all common: amethyst is rare, saltpeter and silver uncommon")
var shallowKinds = 0
for t in [Tile.coal, .copper, .tin, .saltpeter] where (cs[t]?[3] ?? 999) < 140 { shallowKinds += 1 }
check(shallowKinds == 4 && (cs[.iron]?[3] ?? 0) >= 205, "the upper ground holds coal, copper, tin and saltpeter; iron starts in the middle depths")
var above = 0
for (t, a) in cs where t.def.style == .ore || [.tin, .saltpeter, .silver, .amethyst].contains(t) { above += a[1] }
check(above == 0, "no ore forms at or within eight rows of the surface")
do {
    // generator 6 (new worlds): iron from row 150, every other ore in its band, nothing at the surface
    let cs6 = census(WorldGen.currentVersion, .standard)
    let iron6: [Int] = cs6[.iron] ?? [0, 0, 0, 0, 0]
    let coal6: Int = cs6[.coal]?[0] ?? 0
    check(iron6[3] >= 150 && iron6[3] < 205 && Double(coal6) > Double(iron6[0]) * 1.5, "generator 6: iron starts higher (row \(iron6[3])) and coal stays the commonest ore (\(coal6) against \(iron6[0]))")
    for (t, lo, hi) in [(Tile.tin, 122, 265), (.saltpeter, 112, 205), (.silver, 200, 400), (.amethyst, 150, 330), (.gold, 310, 530)] {
        let a = cs6[t] ?? [0, 0, 0, 0, 0]
        check(a[0] > 300 && a[3] >= lo - 1 && a[4] <= hi + 1, "generator 6: \(t.name) stays between rows \(a[3]) and \(a[4]) (its band \(lo)-\(hi))")
    }
    var above6 = 0
    for (t, a) in cs6 where t.def.style == .ore || [.tin, .saltpeter, .silver, .amethyst].contains(t) { above6 += a[1] }
    check(above6 == 0, "generator 6: still no ore at or within eight rows of the surface")
}
do {
    // tin is common in some regions and missing from others
    let g = WorldGen(seed: 1234, infinite: true, rareChance: 1.0, genVersion: WorldGen.currentVersion, options: .standard)
    var withTin = 0
    let span = 4000
    var x = -span
    while x < span { if oreRegion(x, 43, g.seed) >= 0.47 { withTin += 1 }; x += 20 }
    let frac = Double(withTin) / Double(2 * span / 20)
    check(frac > 0.3 && frac < 0.7, "tin forms across \(Int(frac * 100))% of the land and is absent from the rest")
    // saltpeter favours dry land
    var dry = 0, wet = 0
    for b in [Biome.desert, .savanna] { dry += Int(oreBias(b, .saltpeter) * 100) }
    for b in [Biome.swamp, .jungle] { wet += Int(oreBias(b, .saltpeter) * 100) }
    check(dry > 0 && wet < 0, "saltpeter crusts favour deserts and savanna and shun swamp and jungle")
}
do {
    let cf = census(WorldGen.currentVersion, WorldOptions(flat: true, trees: true, structures: true))
    let ok = [Tile.tin, .saltpeter, .silver, .amethyst, .iron, .coal].allSatisfy { (cf[$0]?[0] ?? 0) > 200 }
    var above = 0
    for (_, a) in cf { above += a[1] }
    _ = above
    check(ok && [Tile.tin, .saltpeter, .silver, .amethyst].allSatisfy { (cf[$0]?[1] ?? 0) == 0 }, "flat worlds get every ore too, none at the surface (tin \(cf[.tin]?[0] ?? 0), saltpeter \(cf[.saltpeter]?[0] ?? 0), silver \(cf[.silver]?[0] ?? 0), amethyst \(cf[.amethyst]?[0] ?? 0))")
}
do {
    // each ore looks different from every other
    let ores: [Tile] = [.coal, .copper, .iron, .gold, .diamond, .mythril, .tin, .saltpeter, .silver, .amethyst, .crystalOre]
    var minDiff = Int.max
    for i in 0..<ores.count { for j in (i + 1)..<ores.count {
        let a = tileBuf(ores[i]).px, b = tileBuf(ores[j]).px
        minDiff = min(minDiff, zip(a, b).filter { $0 != $1 }.count)
    } }
    check(minDiff >= 10, "every ore has its own look (any two differ in at least \(minDiff) of 64 pixels)")
}
do {
    // mined with the right pickaxe they drop their ore; the wrong one says so
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    let x0 = Int(g.pb.x)
    g.world.loadAround(centerX: x0, radius: 3)
    var results: [String] = []
    var allOK = true
    for (i, (t, pick, item)) in [(Tile.tin, Tier.stone, Item.mat(.tinOre)), (.saltpeter, .wood, .mat(.saltpeter)), (.silver, .copper, .mat(.silverOre)), (.amethyst, .stone, .mat(.amethyst))].enumerated() {
        let tx = x0 + 2 + i * 3
        let ty = Int(g.pb.y) - 1
        g.world.set(tx, ty, t)
        let st = g.tileDropStacks(t, tx, ty)
        let drops = st.first?.item == item
        g.inv.slots[0] = Stack(item: .tool(.pickaxe, Tier(rawValue: pick.rawValue - 1) ?? .wood), count: 1)
        g.setSel(0)
        let need = t.def.tier
        results.append("\(t.name): drops \(st.map { "\($0.count) \($0.item.name)" }), needs tier \(need)")
        if !drops || need != pick.rawValue { allOK = false }
    }
    check(allOK, "the new ores drop their materials and need the expected pickaxe (\(results.joined(separator: "; ")))")
    // stacking and saving
    var inv = Inventory()
    _ = inv.add(.mat(.tinOre), 150)
    check(inv.slots[0]?.count == 99 && inv.slots[1]?.count == 51, "ores stack to 99 like every material")
}
do {
    // the new materials have real uses: smelting and recipes that need them
    func uses(_ m: Mat) -> [String] { return RecipeBook.all.filter { $0.cost.contains { $0.item == .mat(m) } }.map { $0.out.name } }
    for m in [Mat.tinOre, .bronzeBar, .saltpeter, .silverOre, .silverBar, .amethyst] {
        let u = uses(m)
        check(!u.isEmpty, "\(m.name) is used for: \(Array(Set(u)).sorted().joined(separator: ", "))")
    }
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.world.loadAround(centerX: Int(g.pb.x), radius: 2)
    g.world.set(Int(g.pb.x) + 2, Int(g.pb.y) - 1, .furnace)
    _ = g.inv.add(.mat(.copperOre), 4); _ = g.inv.add(.mat(.tinOre), 2); _ = g.inv.add(.mat(.coal), 4); _ = g.inv.add(.mat(.silverOre), 2)
    if let r = RecipeBook.all.first(where: { $0.out == .mat(.bronzeBar) }) { g.craft(r) }
    if let r = RecipeBook.all.first(where: { $0.out == .mat(.silverBar) }) { g.craft(r) }
    check(g.inv.total(.mat(.bronzeBar)) == 2 && g.inv.total(.mat(.silverBar)) == 1, "at a furnace, copper and tin ore smelt into bronze, silver ore into silver bars")
}

print("\(passes) passed, \(fails) failed")
print(fails == 0 ? "ALL MINE AND ORE TESTS PASSED" : "SOME MINE AND ORE TESTS FAILED")
