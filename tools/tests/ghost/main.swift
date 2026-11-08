import SwiftUI
import Foundation
// Ghost terrain: the screen shows each dimension's own land (the pictures the renderer keeps of the
// land never mix dimensions), land let go and made again is the same, and a world that is explored,
// built on, saved, quit and loaded again, over and over and through every kind of dimension, keeps
// exactly its land.

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}

// a scratch folder for the mod store (never the real one)
let scratch: URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prghost-" + String(Int.random(in: 1000...999999)), isDirectory: true)
ModStore.overrideDir = scratch

func painted(_ c: UInt32) -> ModPixels {
    var p = ModPixels(w: 8, h: 8)
    for y in 0..<8 { for x in 0..<8 { p.setARGB(x, y, 0xFF000000 | (((x + y) % 3 == 0) ? shadeRGB(c, 0.85) : c)) } }
    return p
}

/// A mod with one open dimension: flat ground of its own ice and snow at `surface`, pines, no sea
func dimMod(_ id: String, _ surface: Int, _ color: UInt32, weather: Int = 0) -> ModPack {
    var p = ModPack()
    p.id = id; p.name = id
    var ice = ModBlock(); ice.id = "ice"; ice.name = "Ice " + id; ice.art = painted(color)
    p.blocks = [ice]
    var d = ModDimension()
    d.id = "land"; d.name = "Land " + id
    d.cycle = false; d.fixedTime = 0.25; d.light = 1.0; d.weather = weather; d.chill = weather == 4 ? 0.7 : 0
    d.surface = surface; d.hills = 0; d.mountains = 0; d.caves = 0.4; d.islands = 0; d.sea = 0
    d.stone = id + ":ice"
    var z = ModDimZone(); z.name = "Field"; z.biome = Biome.tundra.rawValue; z.ground = id + ":ice"; z.filler = id + ":ice"
    z.trees = 2; z.leaves = ModGround.key(.pineLeaves); z.plant = ""
    d.zones = [z]
    d.returnGate = true
    p.dims = [d]
    _ = ModValidator.check(&p, known: [:])
    return p
}

let modA: ModPack = dimMod("aaa", 150, 0x4A8AD8)
let modB: ModPack = dimMod("bbb", 120, 0xD84A8A)
let packs: [ModPack] = [modA, modB]

func newWorld(_ seed: UInt64, infinite: Bool = true, mode: GameMode = .creative) -> Game {
    ModRuntime.activate(packs, world: nil)
    let g = Game(mode: mode, infinite: infinite, seed: seed, settings: Settings())
    g.modInfo = ModRuntime.shared.worldInfo()
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.godMode = true
    g.settings.weatherOn = false
    g.timeOfDay = 0.25
    return g
}

/// Save, quit and load again, the way the game does it: the save goes through JSON, the world's mods
/// are switched on from what the save remembers, then the world is loaded
func reload(_ g: Game) -> (Game, SaveData) {
    let data: Data = try! JSONEncoder().encode(g.makeSave())
    let back: SaveData = try! JSONDecoder().decode(SaveData.self, from: data)
    ModRuntime.deactivate()
    ModRuntime.activate(packs, world: back.mods)
    let g2: Game = Game.load(back, settings: Settings())
    g2.monstersEnabled = false
    g2.pauseSpawning = true
    g2.godMode = true
    g2.settings.weatherOn = false
    return (g2, back)
}

// ---------------------------------------------------------------- the renderer's pictures
let W = 960, H = 640
func frame(_ g: Game) -> [Double] {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    WorldRenderer.draw(&ctx, CGSize(width: W, height: H), g)
    GraphicsContext.target = nil
    return t.rgb
}
func differing(_ a: [Double], _ b: [Double]) -> Int {
    if a.count != b.count { return max(a.count, b.count) / 3 }
    var n: Int = 0
    var i: Int = 0
    while i + 2 < a.count {
        if abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2]) > 0.03 { n += 1 }
        i += 3
    }
    return n
}
/// Draws `frames` frames as the game would, then compares the last one with the same view drawn
/// from scratch (nothing remembered): the pixels that differ are pictures that are not of this land
func ghostPixels(_ g: Game, frames: Int = 24) -> Int {
    // no shaking and no fade from black after a trip, so the land itself is compared
    g.shake = 0
    g.fadeT = 0
    var last: [Double] = []
    for _ in 0..<frames { last = frame(g) }
    RenderCache.shared.clearAll()
    let fresh: [Double] = frame(g)
    return differing(last, fresh)
}
func dname(_ d: Dimension) -> String {
    switch d {
    case .overworld: return "the Overworld"
    case .umbral: return "the Umbral Realm"
    default: return "custom dimension \(d.customSlot + 1)"
    }
}
func look(_ g: Game, _ x: Double, _ y: Double) {
    g.camX = x
    g.camY = y
    g.world.loadAround(centerX: Int(floor(x)), radius: 5)
}

print("== the renderer keeps each dimension's pictures apart")
do {
    let cache: RenderCache = RenderCache.shared
    var seen: [Int: String] = [:]
    var clash: String = ""
    for d in 0..<dimCount {
        let rows: Int = dimHeight(Dimension(rawValue: d) ?? .overworld) / 16 + 1
        for cx in -40...40 {
            for sy in 0..<rows {
                let k: Int = cache.key(d, cx, sy)
                let me: String = "dim \(d) chunk \(cx) rows \(sy * 16)"
                if let o = seen[k], clash.isEmpty { clash = o + " and " + me }
                seen[k] = me
            }
        }
    }
    check(clash.isEmpty, "every part of every dimension has its own place among the remembered pictures" + (clash.isEmpty ? "" : " (shared by \(clash))"))

    let g = newWorld(7070)
    g.viewW = Double(W); g.viewH = Double(H)
    g.tilePx = 24
    // no darkness over the land, so every block drawn can be seen in the comparison
    g.fullBright = true
    let a0: Double = 6.5
    look(g, a0, 150)
    let same: Int = { () -> Int in RenderCache.shared.clearAll(); let f1 = frame(g); RenderCache.shared.clearAll(); return differing(f1, frame(g)) }()
    check(same == 0, "the same view drawn twice from scratch is the same picture (\(same) pixels apart), so the comparisons below mean something")
    check(ghostPixels(g) == 0, "the Overworld on its own draws only itself")
    // the Overworld 16 rows lower was just drawn; now the first custom dimension at the same place
    look(g, a0, 166)
    _ = frame(g)
    _ = frame(g)
    g.enterCustomDim(ModRuntime.shared.dimSlots[0]!)
    look(g, a0, 150)
    let g1: Int = ghostPixels(g)
    check(g1 == 0, "a custom dimension entered after the Overworld shows only its own land, no Overworld ground or sky in it (\(g1) pixels were not of its land)")
    // back to the Overworld, looking 16 rows lower than where the dimension was drawn
    look(g, a0, 134)
    _ = frame(g)
    g.leaveCustomDim()
    look(g, a0, 150)
    let g2: Int = ghostPixels(g)
    check(g2 == 0, "back in the Overworld, nothing of the custom dimension is drawn there (\(g2) pixels)")
    // the Umbral Realm and the second custom dimension
    g.travelTo(.umbral, arriveX: a0, arriveY: 120, silent: true)
    look(g, a0, 136)
    _ = frame(g)
    _ = frame(g)
    g.enterCustomDim(ModRuntime.shared.dimSlots[1]!)
    look(g, a0, 120)
    let g3: Int = ghostPixels(g)
    check(g3 == 0, "the second custom dimension shows nothing of the Umbral Realm (\(g3) pixels)")
    g.leaveCustomDim()
    g.travelTo(.umbral, arriveX: a0, arriveY: 120, silent: true)
    look(g, a0, 104)
    let g4: Int = ghostPixels(g)
    check(g4 == 0, "and the Umbral Realm nothing of it (\(g4) pixels)")
    // many trips there and back, looking about each time
    var worst: Int = 0
    var dims: [Dimension] = [.overworld, .custom0, .umbral, .custom1]
    for trip in 0..<8 {
        let d: Dimension = dims[trip % dims.count]
        if d.isCustom {
            g.enterCustomDim(ModRuntime.shared.dimRT(d)!)
        } else {
            if g.world.dim.isCustom { g.leaveCustomDim() }
            if g.world.dim != d { g.travelTo(d, arriveX: a0, arriveY: 120, silent: true) }
        }
        for k in 0..<3 {
            look(g, a0 + Double(k * 20 - 20), 110 + Double(trip * 7 % 40) + Double(k * 16))
            for _ in 0..<3 { _ = frame(g) }
        }
        worst = max(worst, ghostPixels(g, frames: 6))
    }
    dims = []
    check(worst == 0, "after eight trips between all four kinds of dimension the screen still shows only the land that is there (worst \(worst) pixels)")
    ModRuntime.deactivate()
}

// ---------------------------------------------------------------- land made again
print("== land let go and made again")
do {
    let g = newWorld(9191)
    var mismatch: [String] = []
    for d in [Dimension.overworld, .umbral, .custom0, .custom1] {
        let first: Chunk = generateChunk(g.gen, d, 3)
        for cx in [-9, 14, 2, 4, -1, 40] { _ = generateChunk(g.gen, d, cx) }
        let again: Chunk = generateChunk(g.gen, d, 3)
        if first.tiles != again.tiles || first.surf != again.surf { mismatch.append(dname(d)) }
    }
    check(mismatch.isEmpty, "a chunk made again after others is block for block the same in every dimension" + (mismatch.isEmpty ? "" : " (not in \(mismatch))"))
    // the world lets go of land far behind the player and makes it again on the way back
    let w: World = g.world
    let x0: Int = Int(g.pb.x)
    g.viewW = 1100; g.viewH = 800
    func walkTo(_ x: Int) {
        g.pb.x = Double(x) + 0.5
        g.camX = g.pb.x
        for _ in 0..<60 { g.updateStreaming() }
    }
    walkTo(x0)
    var before: [Int: [UInt8]] = [:]
    for (cx, c) in w.chunks { before[cx] = c.tiles }
    w.set(x0 + 2, w.surfaceY(x0 + 2) - 1, .brick)
    before[floorDiv(x0 + 2, chunkW)] = w.chunks[floorDiv(x0 + 2, chunkW)]!.tiles
    walkTo(x0 + 600)
    let gone: Bool = w.chunks[floorDiv(x0, chunkW)] == nil
    walkTo(x0)
    var changed: Int = 0
    for (cx, t) in before where w.loadChunk(cx)?.tiles != t { changed += 1 }
    check(gone && changed == 0, "walking 600 blocks away and back, every chunk around the start is as it was, the brick included (\(changed) of \(before.count) changed)")
    ModRuntime.deactivate()
}

// ---------------------------------------------------------------- save, quit, load, again and again
print("== explore, build, save, quit, load, return, repeat")
/// what each explored chunk held when the world was last saved, by dimension and chunk
var truth: [String: [UInt8]] = [:]
func tkey(_ d: Int, _ cx: Int) -> String { return String(d) + ":" + String(cx) }
func record(_ g: Game) {
    let w: World = g.world
    for (cx, c) in w.chunks { truth[tkey(w.dim.rawValue, cx)] = c.tiles }
    for d in 0..<w.parked.count { for (cx, c) in w.parked[d] where !(d == w.dim.rawValue && w.chunks[cx] != nil) { truth[tkey(d, cx)] = c.tiles } }
}
/// Goes through every chunk ever recorded, in its own dimension, and counts those that differ
func verify(_ g: Game) -> (Int, [String]) {
    let w: World = g.world
    let home: Dimension = w.dim
    var n: Int = 0
    var bad: [String] = []
    for d in 0..<dimCount {
        let keys: [Int] = truth.keys.compactMap { (k: String) -> Int? in
            let p = k.split(separator: ":")
            return Int(p[0]) == d ? Int(p[1]) : nil
        }
        if keys.isEmpty { continue }
        let dd: Dimension = Dimension(rawValue: d) ?? .overworld
        w.switchDimension(dd)
        for cx in keys.sorted() {
            guard let c = w.loadChunk(cx) else { bad.append(tkey(d, cx) + " missing"); continue }
            n += 1
            if c.tiles != truth[tkey(d, cx)]! {
                var cells: Int = 0
                for i in 0..<min(c.tiles.count, truth[tkey(d, cx)]!.count) where c.tiles[i] != truth[tkey(d, cx)]![i] { cells += 1 }
                bad.append(tkey(d, cx) + " (\(cells) blocks)")
            }
        }
    }
    w.switchDimension(home)
    w.loadAround(centerX: Int(floor(g.pb.x)), radius: 4)
    return (n, bad)
}
/// Explores around x: the game's own streaming loads the land as the camera comes
func explore(_ g: Game, _ x: Int) {
    g.pb.x = Double(x) + 0.5
    g.camX = g.pb.x
    for _ in 0..<40 { g.updateStreaming() }
}
/// Builds and digs at x: a hole, a brick column, a torch, a chest with things in it; also right on
/// the chunk border nearest to x
func build(_ g: Game, _ x: Int, _ tag: Int) -> ChestKey {
    let w: World = g.world
    let s: Int = w.surfaceY(x)
    for dx in 0..<4 { for dy in 0..<4 { w.set(x + dx, s + dy, .air) } }
    for dy in 1...6 { w.set(x - 3, s - dy, .brick) }
    w.set(x - 4, s - 1, .torch)
    let edge: Int = floorDiv(x, chunkW) * chunkW
    w.set(edge - 1, s - 8, .glass)
    w.set(edge, s - 8, .glass)
    let cy: Int = s - 7
    w.set(x - 3, cy, .chest)
    let k: ChestKey = w.chestKey(x - 3, cy)
    w.chests[k] = [Stack(item: .mat(.coal), count: 10 + tag), Stack(item: .block(.planks), count: 3)]
    return k
}

do {
    var g = newWorld(31337, mode: .survival)
    g.viewW = 1100; g.viewH = 800
    let start: Int = Int(g.pb.x)
    var chests: [ChestKey: Int] = [:]
    var ok: Bool = true
    var lastSave: SaveData? = nil
    for cycle in 0..<4 {
        // the Overworld: new places each time, both ways
        for k in 0..<4 {
            let x: Int = start + (k % 2 == 0 ? 1 : -1) * (cycle * 260 + k * 70 + 5)
            explore(g, x)
            chests[build(g, x, cycle * 10 + k)] = 10 + cycle * 10 + k
        }
        // a few seconds of the world going on as usual (plants, water, whatever runs)
        let px: Int = start + cycle * 260 + 5
        explore(g, px)
        g.pb.y = Double(g.world.surfaceY(px)) - 0.01
        for _ in 0..<180 { g.tick(1.0 / 60.0) }
        // the Umbral Realm and both custom dimensions, the way the game takes the player there
        g.travelTo(.umbral, arriveX: Double(start + cycle * 50), arriveY: 120, silent: true)
        explore(g, start + cycle * 50 + 30)
        chests[build(g, start + cycle * 50 + 30, 100 + cycle)] = 110 + cycle
        g.travelTo(.overworld, arriveX: g.spawnX, arriveY: g.spawnY, silent: true)
        g.enterCustomDim(ModRuntime.shared.dimSlots[0]!)
        explore(g, cycle * 90 - 40)
        chests[build(g, cycle * 90 - 40, 200 + cycle)] = 210 + cycle
        g.leaveCustomDim()
        g.enterCustomDim(ModRuntime.shared.dimSlots[1]!)
        explore(g, 60 - cycle * 90)
        chests[build(g, 60 - cycle * 90, 300 + cycle)] = 310 + cycle
        // half the saves are made inside a custom dimension, half back in the Overworld
        if cycle % 2 == 0 { g.leaveCustomDim() }
        let whereSaved: Dimension = g.world.dim
        record(g)
        let r: (Game, SaveData) = reload(g)
        g = r.0
        lastSave = r.1
        g.viewW = 1100; g.viewH = 800
        let v: (Int, [String]) = verify(g)
        if !v.1.isEmpty { ok = false }
        check(v.1.isEmpty && g.world.dim == whereSaved, "cycle \(cycle + 1): after saving in \(dname(whereSaved)), quitting and loading, all \(v.0) chunks explored so far in four dimensions are block for block as they were" + (v.1.isEmpty ? "" : " (differ: \(v.1.prefix(6)))"))
        var lost: Int = 0
        for (k, n) in chests where (g.world.chests[k]?.first?.count ?? -1) != n { lost += 1 }
        check(lost == 0, "cycle \(cycle + 1): all \(chests.count) chests built so far still hold what was put in them (\(lost) changed)")
    }
    if let s = lastSave {
        var seen: Set<String> = []
        var dup: Int = 0
        for c in s.chunks { if !seen.insert(tkey(c.dim, c.cx)).inserted { dup += 1 } }
        check(dup == 0 && !s.chunks.isEmpty, "the save holds each changed chunk once (\(s.chunks.count) chunks, \(dup) twice)")
        let dims: Set<Int> = Set(s.chunks.map { $0.dim })
        check(dims == Set([0, 1, 2, 3]), "and the changed land of every dimension visited (\(dims.sorted()))")
    }
    // loading makes only the land around the player, nothing it throws away
    if let s = lastSave {
        let before: Int = Perf.shared.chunksGenerated
        ModRuntime.activate(packs, world: s.mods)
        let g2: Game = Game.load(s, settings: Settings())
        let made: Int = Perf.shared.chunksGenerated - before
        check(made <= 9, "loading a world makes only the chunks around the player (\(made) made; the land is not made a second time)")
        _ = g2
    }
    _ = ok
    ModRuntime.deactivate()
}

// a world of fixed width: its edges and its land survive the same cycles
print("== a world of fixed width")
do {
    truth = [:]
    var g = newWorld(4040, infinite: false, mode: .survival)
    g.viewW = 1100; g.viewH = 800
    let wdt: Int = g.gen.width
    var allGood: Bool = true
    for cycle in 0..<3 {
        for x in [6 + cycle * 3, wdt - 12 - cycle * 3, wdt / 2 + cycle * 40] {
            explore(g, x)
            _ = build(g, x, cycle)
        }
        record(g)
        g = reload(g).0
        g.viewW = 1100; g.viewH = 800
        let v: (Int, [String]) = verify(g)
        if !v.1.isEmpty { allGood = false }
        check(v.1.isEmpty, "cycle \(cycle + 1): the \(v.0) chunks explored, edges included, are as they were" + (v.1.isEmpty ? "" : " (differ: \(v.1.prefix(6)))"))
    }
    _ = allGood
    ModRuntime.deactivate()
}

// ---------------------------------------------------------------- weather stays in its dimension
print("== a dimension's weather stays in it")
do {
    let snowy: ModPack = dimMod("ccc", 140, 0xE0E0F0, weather: 4)
    ModRuntime.activate([snowy], world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 5050, settings: Settings())
    g.modInfo = ModRuntime.shared.worldInfo()
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.godMode = true
    g.settings.weatherOn = true
    g.viewW = 1100; g.viewH = 800
    g.weather.cells.removeAll()
    g.enterCustomDim(ModRuntime.shared.dimSlots[0]!)
    for _ in 0..<(60 * 30) { g.tick(1.0 / 60.0) }
    let inDim: Bool = g.weatherAt(g.pb.x, g.pb.y - 2).snow
    var most: Double = 0
    for (_, c) in g.weather.cells { most = max(most, c.snow) }
    check(inDim && most < 0.02, "half a minute in a snowing dimension lays no snow on the Overworld ground the player left (most \(String(format: "%.2f", most)))")
    ModRuntime.deactivate()
}

try? FileManager.default.removeItem(at: scratch)
print("\(passes) passed, \(fails) failed")
print(fails == 0 ? "ALL GHOST TERRAIN TESTS PASSED" : "SOME GHOST TERRAIN TESTS FAILED")
exit(fails == 0 ? 0 : 1)
