import SwiftUI
import Foundation
// World generation 6 and what goes with it: generator 5 unchanged for the worlds made with it; more
// trees (and a grove round the spawn), iron from higher up, more coal, copper and tin near the top,
// smaller seas; saplings (from leaves, planted on soil, growing into the land's own kind of tree);
// and monsters kept out of lamplight by the game's own light, not by how near a torch is.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func f2(_ v: Double) -> String { return String(format: "%.2f", v) }

let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prworld6-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

// ---------------------------------------------------------------- generator 5 is untouched
print("== worlds made before keep their land")
func fingerprint(_ ver: Int, _ opts: WorldOptions) -> UInt64 {
    var h: UInt64 = 1469598103934665603
    for seed in [UInt64(12345), 777, 9, 4242] {
        let g = WorldGen(seed: seed, infinite: seed != 9, rareChance: 0.28, genVersion: ver, options: opts)
        var cxs: [Int] = [-200, -69, -40, -3, 0, 5, 37, 63, 77, 130, 256]
        cxs.append(floorDiv(g.portalX, chunkW))
        for cx in cxs {
            let c = generateChunk(g, .overworld, cx)
            for b in c.tiles { h = (h ^ UInt64(b)) &* 1099511628211 }
            for b in c.walls { h = (h ^ UInt64(b)) &* 1099511628211 }
        }
        h = (h ^ UInt64(bitPattern: Int64(g.portalX))) &* 1099511628211
    }
    return h
}
var flatOpts = WorldOptions(); flatOpts.flat = true; flatOpts.caves = true; flatOpts.ponds = true
// recorded with the game as it was before generator 6
check(fingerprint(5, .standard) == 17650721157646406198, "a standard world made with generator 5 generates exactly as before")
check(fingerprint(5, flatOpts) == 16071100251917341750, "and so does a flat world")
check(WorldGen.currentVersion == 6, "new worlds use generator 6")
do {
    let g = Game(mode: .survival, infinite: true, seed: 99, settings: Settings())
    var s: SaveData = g.makeSave()
    check(s.meta.genVersion == 6, "a new world is saved as generator 6")
    s.meta.genVersion = 5
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(s))
    let g2 = Game.load(back, settings: Settings())
    check(g2.gen.genVersion == 5, "a world saved with generator 5 goes on generating with it")
}

// ---------------------------------------------------------------- statistics, 5 against 6
struct Stats {
    var cols: Int = 0
    var trees: [Biome: Int] = [:]
    var colsB: [Biome: Int] = [:]
    var spawnCols: Int = 0
    var spawnTrees: Int = 0
    var minGap: Int = 99
    var minJungleGap: Int = 99
    /// ore counts per depth band below the surface: 0-30, 30-60, 60-100, 100-160, 160+
    var ore: [Tile: [Int]] = [:]
    var oceanCols: Int = 0
    var allCols: Int = 0
    var crossings: [Int] = []
    var homeSea: Int = 0
}
func band(_ d: Int) -> Int { return d < 30 ? 0 : (d < 60 ? 1 : (d < 100 ? 2 : (d < 160 ? 3 : 4))) }
func stats(_ ver: Int) -> Stats {
    var s = Stats()
    let trunks: Set<Tile> = [.log, .birchLog, .jungleLog]
    let ores: Set<Tile> = [.coal, .copper, .tin, .iron, .silver, .gold, .diamond]
    for seed: UInt64 in [11, 22, 33, 44, 55, 66] {
        let g = WorldGen(seed: seed, infinite: true, rareChance: 0.28, genVersion: ver)
        var lastTree: Int = Int.min
        var lastJungle: Int = Int.min
        for cx in (-30)...(29) {
            let ch = generateOverworldChunk(g, cx)
            for lx in 0..<chunkW {
                let x: Int = cx * chunkW + lx
                let c: Col = g.col(x)
                if c.biome == .ocean { continue }
                s.cols += 1
                s.colsB[c.biome, default: 0] += 1
                let near: Bool = abs(x - g.spawnX) < 100
                if near { s.spawnCols += 1 }
                let t: Tile = ch.get(lx, c.h - 1)
                if trunks.contains(t) {
                    s.trees[c.biome, default: 0] += 1
                    if near { s.spawnTrees += 1 }
                    if lastTree != Int.min { s.minGap = min(s.minGap, x - lastTree) }
                    lastTree = x
                    if t == .jungleLog {
                        if lastJungle != Int.min { s.minJungleGap = min(s.minJungleGap, x - lastJungle) }
                        lastJungle = x
                    }
                }
                for y in (c.h + 1)..<WorldGen.H {
                    let o: Tile = ch.get(lx, y)
                    if ores.contains(o) { s.ore[o, default: [0, 0, 0, 0, 0]][band(y - c.h)] += 1 }
                }
            }
        }
        var run: Int = 0
        var x: Int = -12000
        while x < 12000 {
            s.allCols += 1
            if g.col(x).biome == .ocean { s.oceanCols += 1; run += 1 } else if run > 0 { s.crossings.append(run * 2); run = 0 }
            x += 2
        }
        let home: WorldGen.Basin = WorldGen.homeBasin(seed, g.spawnX, small: ver >= 6)
        if g.col(home.center).biome == .ocean { s.homeSea += 1 }
    }
    return s
}
func per100(_ n: Int, _ cols: Int) -> Double { return Double(n) * 100.0 / Double(max(1, cols)) }
func treesIn(_ s: Stats, _ bs: [Biome]) -> Double {
    var n: Int = 0
    var c: Int = 0
    for b in bs { n += s.trees[b] ?? 0; c += s.colsB[b] ?? 0 }
    return per100(n, c)
}
func oreBand(_ s: Stats, _ t: Tile, _ bands: [Int]) -> Double {
    var n: Int = 0
    for b in bands { n += (s.ore[t] ?? [0, 0, 0, 0, 0])[b] }
    return per100(n, s.cols)
}

print("== generator 6: trees, ores and seas against generator 5")
let s5: Stats = stats(5)
let s6: Stats = stats(6)
do {
    let open: [Biome] = [.plains, .forest, .savanna, .tundra, .swamp]
    let t5: Double = treesIn(s5, open)
    let t6: Double = treesIn(s6, open)
    check(t6 >= t5 * 1.35, "the open biomes grow about half as many trees again (\(f2(t5)) -> \(f2(t6)) per 100 columns of plains, forest, savanna, tundra and swamp)")
    for b in [Biome.plains, .forest, .tundra, .savanna] where (s6.colsB[b] ?? 0) > 80 && (s5.colsB[b] ?? 0) > 80 {
        let a: Double = per100(s5.trees[b] ?? 0, s5.colsB[b] ?? 1)
        let c: Double = per100(s6.trees[b] ?? 0, s6.colsB[b] ?? 1)
        check(c > a * 1.2, "\(b.name): \(f2(a)) -> \(f2(c)) trees per 100 columns")
    }
    let j5: Double = treesIn(s5, [.jungle])
    let j6: Double = treesIn(s6, [.jungle])
    check(j6 >= j5 * 0.9 && j6 <= j5 * 1.25, "jungles, already thick, stay about as they were (\(f2(j5)) -> \(f2(j6)))")
    let sp5: Double = per100(s5.spawnTrees, s5.spawnCols)
    let sp6: Double = per100(s6.spawnTrees, s6.spawnCols)
    check(sp6 >= sp5 * 1.5 && sp6 >= 8, "around the spawn there is a grove to start on (\(f2(sp5)) -> \(f2(sp6)) per 100 columns within 100 blocks)")
    check(s6.minGap >= 3 && s6.minJungleGap >= 4, "trees still stand apart: at least \(s6.minGap) columns (jungle trees \(s6.minJungleGap)), so forests stay easy to walk through")
}
do {
    let iron5top: Double = oreBand(s5, .iron, [0, 1])
    let iron6top: Double = oreBand(s6, .iron, [0, 1])
    let iron5mid: Double = oreBand(s5, .iron, [2])
    let iron6mid: Double = oreBand(s6, .iron, [2])
    check(iron5top < 1 && iron6top >= 15, "iron now shows from about 35 blocks down (\(f1(iron5top)) -> \(f1(iron6top)) per 100 columns in the top 60 blocks)")
    check(iron6mid >= iron5mid * 3, "and is easy to find 60 to 100 blocks down (\(f1(iron5mid)) -> \(f1(iron6mid)))")
    let deep5: Double = oreBand(s5, .iron, [3, 4])
    let deep6: Double = oreBand(s6, .iron, [3, 4])
    check(abs(deep6 - deep5) <= deep5 * 0.08, "deeper down iron is as it was (\(f1(deep5)) -> \(f1(deep6)))")
    let coal6: Double = oreBand(s6, .coal, [0, 1])
    let copper6: Double = oreBand(s6, .copper, [0, 1])
    check(iron6top < copper6 * 0.5 && iron6top < coal6 * 0.3, "iron is still scarcer than copper and coal near the top (iron \(f1(iron6top)), copper \(f1(copper6)), coal \(f1(coal6)))")
    for t in [Tile.coal, .copper, .tin] {
        let a: Double = oreBand(s5, t, [0, 1])
        let b: Double = oreBand(s6, t, [0, 1])
        check(b >= a * 1.12, "\(t.def.name): more in the top 60 blocks (\(f1(a)) -> \(f1(b)))")
    }
    for t in [Tile.silver, .gold, .diamond] {
        let a: Double = oreBand(s5, t, [0, 1, 2, 3, 4])
        let b: Double = oreBand(s6, t, [0, 1, 2, 3, 4])
        check(abs(b - a) <= max(2.0, a * 0.06), "\(t.def.name) is as rare as before (\(f1(a)) -> \(f1(b)))")
    }
}
do {
    let o5: Double = Double(s5.oceanCols) / Double(s5.allCols)
    let o6: Double = Double(s6.oceanCols) / Double(s6.allCols)
    check(o6 <= o5 * 0.85 && o6 >= o5 * 0.6, "seas cover less of the world, but still plenty (\(f1(o5 * 100))% -> \(f1(o6 * 100))% of columns)")
    let m5: Double = Double(s5.crossings.reduce(0, +)) / Double(max(1, s5.crossings.count))
    let m6: Double = Double(s6.crossings.reduce(0, +)) / Double(max(1, s6.crossings.count))
    let p5: Int = s5.crossings.sorted()[s5.crossings.count * 9 / 10]
    let p6: Int = s6.crossings.sorted()[s6.crossings.count * 9 / 10]
    check(m6 <= m5 * 0.9 && p6 <= p5 * 9 / 10, "crossing a sea is shorter (mean \(Int(m5)) -> \(Int(m6)) blocks, the longest tenth from \(p5) -> \(p6))")
    check(s6.homeSea == 6 && s6.crossings.count >= 20, "every world still has its sea near the spawn, and there are \(s6.crossings.count) seas to cross")
}

// ---------------------------------------------------------------- saplings
/// A flat grass field at row 100 around x, open sky above, solid ground below
func field(_ g: Game, _ x: Int, _ ground: Tile = .grass) {
    let w = g.world
    w.loadAround(centerX: x, radius: 5)
    for xx in (x - 60)...(x + 60) {
        for y in 40..<100 { w.set(xx, y, .air) }
        w.set(xx, 100, ground)
        for y in 101..<106 { w.set(xx, y, .dirt) }
        for y in 106..<230 { w.set(xx, y, .stone) }
    }
}
func countTiles(_ g: Game, _ x: Int, _ ts: Set<Tile>) -> Int {
    var n: Int = 0
    for xx in (x - 6)...(x + 6) { for y in 70..<100 where ts.contains(g.world.tile(xx, y)) { n += 1 } }
    return n
}
let allLeaves: Set<Tile> = [.leaves, .birchLeaves, .pineLeaves, .jungleLeaves]
let allLogs: Set<Tile> = [.log, .birchLog, .jungleLog, .palmLog]

print("== saplings")
do {
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.monstersEnabled = false; g.pauseSpawning = true
    let x0: Int = Int(g.pb.x)
    field(g, x0)
    g.pb.x = Double(x0) + 0.5; g.pb.y = 100
    var got: Int = 0
    for _ in 0..<2000 { for s in g.tileDropStacks(.leaves, x0, 90) where s.item == .block(.sapling) { got += s.count } }
    var gotPine: Int = 0
    for _ in 0..<2000 { for s in g.tileDropStacks(.pineLeaves, x0, 90) where s.item == .block(.sapling) { gotPine += s.count } }
    check(got > 100 && got < 260 && gotPine > 100, "leaves give a sapling about one time in twelve (\(got) and \(gotPine) from 2000 oak and pine leaves)")
    check(allGameItems().contains(.block(.sapling)) && Item.block(.sapling).infoLines.joined().contains("tree"), "saplings are in the creative palette and say what they do")
    check(g.canPlaceAt(x0 + 2, 99, .sapling), "a sapling can be planted on grass")
    g.world.set(x0 + 3, 100, .stone)
    check(!g.canPlaceAt(x0 + 3, 99, .sapling), "but not on stone")
    g.world.set(x0 + 3, 100, .grass)
    // an oak or a birch on the plains, grown into the room above it
    g.world.set(x0 + 2, 99, .sapling)
    let grew: Bool = g.growSapling(x0 + 2, 99)
    let logs: Int = countTiles(g, x0 + 2, allLogs)
    let leaves: Int = countTiles(g, x0 + 2, allLeaves)
    let b: Biome = g.biomeAt(Double(x0 + 2))
    check(grew && logs >= 4 && leaves >= 8 && g.world.tile(x0 + 2, 99) != .sapling, "in \(b.name) a sapling grows into a tree (\(logs) logs, \(leaves) leaves)")
    // too little room: it waits
    g.world.set(x0 + 12, 99, .sapling)
    g.world.set(x0 + 12, 96, .planks)
    check(!g.growSapling(x0 + 12, 99) && g.world.tile(x0 + 12, 99) == .sapling, "under a low roof it waits instead of growing into it")
    g.world.set(x0 + 12, 96, .air)
    check(g.growSapling(x0 + 12, 99), "and grows once the roof is gone")
    // a torch above is never replaced
    g.world.set(x0 + 20, 99, .sapling)
    g.world.set(x0 + 20, 94, .torch)
    _ = g.growSapling(x0 + 20, 99)
    check(g.world.tile(x0 + 20, 94) == .torch, "a tree never grows over a torch")
    // left near the player, saplings come up by themselves in a few minutes of play
    var spots: [Int] = []
    for k in 0..<10 { let xx: Int = x0 - 38 + k * 4; g.world.set(xx, 99, .sapling); spots.append(xx) }
    g.timeOfDay = 0.25
    var t: Int = 0
    while t < 12000 {
        g.tick(1.0 / 60.0)
        g.hp = g.maxHP; g.hunger = 100
        t += 1
    }
    var up: Int = 0
    for xx in spots where g.world.tile(xx, 99) != .sapling && isLogTile(g.world.tile(xx, 99)) { up += 1 }
    check(up >= 6, "of 10 saplings planted near the player, \(up) became trees within 200 seconds of play")
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: try! JSONEncoder().encode(g.makeSave()))
    let g2 = Game.load(back, settings: Settings())
    var same: Int = 0
    for xx in spots + [x0 + 2] where g2.world.tile(xx, 99) == g.world.tile(xx, 99) && g2.world.tile(xx, 96) == g.world.tile(xx, 96) { same += 1 }
    check(isLogTile(g2.world.tile(x0 + 2, 99)) && same == spots.count + 1, "grown trees are kept when the world is saved and loaded (\(same) of \(spots.count + 1) the same)")
}
do {
    // a pine in the snow
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings())
    g.monstersEnabled = false; g.pauseSpawning = true
    var tx: Int = Int.min
    var x: Int = -20000
    while x < 20000 && tx == Int.min {
        if g.gen.col(x).biome == .tundra && g.gen.col(x + 8).biome == .tundra && g.gen.col(x - 8).biome == .tundra { tx = x }
        x += 37
    }
    if tx != Int.min {
        field(g, tx, .snow)
        g.pb.x = Double(tx) + 0.5; g.pb.y = 100
        g.world.set(tx, 99, .sapling)
        let ok: Bool = g.growSapling(tx, 99)
        check(ok && countTiles(g, tx, [.pineLeaves]) >= 6, "in the snowy tundra a sapling grows into a pine (\(countTiles(g, tx, [.pineLeaves])) needles)")
    } else {
        check(false, "a tundra to test in")
    }
}
do {
    // in a custom dimension, the region's own wood
    var p = ModPack()
    p.id = "grove"; p.name = "Grove"
    var d = ModDimension()
    d.id = "wood"; d.name = "Woodland"
    d.cycle = false; d.fixedTime = 0.25; d.light = 1.0; d.weather = 0
    d.surface = 150; d.hills = 0; d.mountains = 0; d.caves = 0; d.islands = 0; d.sea = 0
    var z = ModDimZone(); z.name = "Palms"; z.biome = Biome.plains.rawValue
    z.log = ModGround.key(.palmLog); z.leaves = ModGround.key(.jungleLeaves); z.trees = 0; z.plant = ""
    d.zones = [z]
    p.dims = [d]
    _ = ModValidator.check(&p, known: [:])
    ModRuntime.activate([p], world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 5151, settings: Settings())
    g.modInfo = ModRuntime.shared.worldInfo()
    g.monstersEnabled = false; g.pauseSpawning = true
    g.enterCustomDim(ModRuntime.shared.dimSlots[0]!)
    let cx: Int = Int(g.pb.x) + 4
    let gy: Int = g.world.surfaceY(cx)
    for y in (gy - 14)..<gy { g.world.set(cx, y, .air) }
    g.world.set(cx, gy - 1, .sapling)
    let ok: Bool = g.growSapling(cx, gy - 1)
    check(ok && g.world.tile(cx, gy - 1) == .palmLog && g.world.tile(cx, gy - 2) == .palmLog, "in a custom dimension a sapling grows the region's own log and leaves")
    ModRuntime.deactivate()
}

// ---------------------------------------------------------------- monsters and lamplight
/// Night on a long flat field round the player; tries to spawn many times and notes where the
/// monsters came out (blocks from the player, + right, - left)
func nightField(_ seed: UInt64) -> Game {
    let g = Game(mode: .survival, infinite: true, seed: seed, settings: Settings())
    g.viewW = 1100; g.viewH = 800; g.tilePx = 24
    g.godMode = true
    g.monstersEnabled = true
    g.settings.peaceful = false
    g.settings.weatherOn = false
    g.settings.nightDanger = 2
    let x0: Int = Int(g.pb.x)
    field(g, x0)
    g.world.loadAround(centerX: x0, radius: 6)
    g.pb.x = Double(x0) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.timeOfDay = 0.75
    g.mobs.removeAll()
    return g
}
func spawnSides(_ g: Game, _ tries: Int) -> (Int, Int) {
    var left: Int = 0
    var right: Int = 0
    for _ in 0..<tries {
        g.spawnTimer = 0
        g.monsterSpawnCD = 0
        g.updateSpawning(0.05)
        for m in g.mobs where m.def.hostile && !m.kind.isPredator {
            if m.b.x > g.pb.x { right += 1 } else { left += 1 }
        }
        g.mobs.removeAll()
        g.mobGrid.rebuild(g.mobs)
    }
    return (left, right)
}

print("== monsters keep out of lamplight")
do {
    let g = nightField(4242)
    let px: Int = Int(g.pb.x)
    check(g.isNight, "it is night")
    let dark: (Int, Int) = spawnSides(g, 400)
    check(dark.0 > 5 && dark.1 > 5, "on a dark night monsters come out on both sides (\(dark.0) left, \(dark.1) right)")
    // torches along the right, on the ground, every 6 blocks
    var tx: Int = px + 20
    while tx <= px + 50 { g.world.set(tx, 99, .torch); tx += 6 }
    g.spawnLog.removeAll()
    let lit: (Int, Int) = spawnSides(g, 400)
    check(lit.1 == 0 && lit.0 > 5, "with torches along the right, none come out there (\(lit.1)) and they still do on the dark left (\(lit.0))")
    // the same torches, each sealed in a block of stone: the light doesn't get out, so neither does
    // the protection (a check by distance alone would still have kept them away)
    tx = px + 20
    while tx <= px + 50 {
        for xx in (tx - 4)...(tx + 4) { for y in 91...99 where !(xx == tx && y == 95) { g.world.set(xx, y, .stone) } }
        g.world.set(tx, 99, .stone)
        g.world.set(tx, 95, .torch)
        tx += 12
    }
    let sealed: (Int, Int) = spawnSides(g, 400)
    let glowOut: Int = g.lightForSpawn(px + 25, 100).1
    check(sealed.1 > 5, "with the torches walled in by thick stone, monsters come out on the right again (\(sealed.1); lamplight beside a block \(glowOut))")
    // a lantern hung from a post lights the ground under it
    let g2 = nightField(4242)
    let p2: Int = Int(g2.pb.x)
    for k in 0..<5 {
        let lx: Int = p2 + 22 + k * 7
        for y in 94...99 { g2.world.set(lx, y, .planks) }
        g2.world.set(lx + 1, 94, .lantern)
    }
    let lant: (Int, Int) = spawnSides(g2, 400)
    check(lant.1 == 0 && lant.0 > 5, "lanterns hung over the ground keep it clear too (\(lant.1) on the right, \(lant.0) on the left)")
}
do {
    // a long dark tunnel deep underground
    let g = nightField(777)
    let px: Int = Int(g.pb.x)
    let w = g.world
    // solid rock all round, so the tunnel is the only open ground a creature could come out in
    for x in (px - 60)...(px + 60) {
        for y in 166..<250 { w.set(x, y, .stone) }
        for y in 194..<200 { w.set(x, y, .air) }
    }
    g.pb.x = Double(px) + 0.5; g.pb.y = 200
    g.camX = g.pb.x; g.camY = g.pb.y
    let dark: (Int, Int) = spawnSides(g, 500)
    check(dark.0 > 3 && dark.1 > 3, "in a dark tunnel underground cave creatures come out on both sides (\(dark.0), \(dark.1))")
    var tx: Int = px + 18
    while tx <= px + 52 { w.set(tx, 199, .torch); tx += 7 }
    let lit: (Int, Int) = spawnSides(g, 500)
    check(lit.1 == 0 && lit.0 > 3, "torches along one side of the tunnel keep that side clear (\(lit.1) there, \(lit.0) on the dark side)")
}

try? FileManager.default.removeItem(at: scratch)
print("\(passes) passed, \(fails) failed")
print(fails == 0 ? "ALL WORLD 6 TESTS PASSED" : "SOME WORLD 6 TESTS FAILED")
exit(fails == 0 ? 0 : 1)
