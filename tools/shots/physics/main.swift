import SwiftUI
import Foundation
// Headless screenshots of the physics overhaul, phase 1, at the size an iPad shows the world: a house of
// planks hanging under a balloon high over a meadow with the player standing inside it and a pig aboard,
// and a flatbed truck at speed with the player, a chicken and a dropped stack riding on its deck.
let W = 1680, H = 960
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/physshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prphysshots-" + String(Int.random(in: 1000...999999)), isDirectory: true)
let dt60: Double = 1.0 / 60.0

func render(_ g: Game, _ name: String) {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    WorldRenderer.draw(&ctx, CGSize(width: W, height: H), g)
    GraphicsContext.target = nil
    t.save(outDir + "/" + name + ".rgb")
    print("rendered", name)
}
func world() -> Game {
    ModRuntime.activate([], world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 4242, settings: Settings(), options: .standard)
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true
    g.settings.weatherOn = false
    g.tilePx = 48
    g.timeOfDay = 0.3
    g.freezeTime = true
    let w = g.world
    let cx = Int(g.pb.x)
    w.loadAround(centerX: cx, radius: 8)
    for x in (cx - 80)...(cx + 80) {
        for y in 30..<100 { w.set(x, y, .air); w.setWall(x, y, 0) }
        for y in 100..<104 { w.set(x, y, .dirt) }
        for y in 104..<130 { w.set(x, y, .stone) }
        w.set(x, 100, .grass)
    }
    g.pb.x = Double(cx) + 0.5; g.pb.y = 100
    return g
}
func vehicle(_ g: Game, _ cells: [(Int, Int, PartType, Tile?)], left: Double, bottom: Double) -> Vehicle {
    let v = Vehicle(id: g.newID(), first: .frame, x: 0, y: 0)
    v.parts.removeAll()
    for c in cells {
        let pc = PartCell(dx: c.0, dy: c.1)
        v.parts[pc] = c.2
        if let t = c.3 { v.blocks[pc] = t }
    }
    v.recompute(keepAnchor: false)
    v.placeBox(left: left, bottom: bottom)
    v.fuel = v.fuelCapacity
    g.vehicles.append(v)
    return v
}
func tree(_ g: Game, _ x: Int, _ h: Int) {
    for y in (100 - h)..<100 { g.world.set(x, y, .log) }
    for dy in -2...1 {
        let r: Int = dy <= -2 ? 1 : 2
        for dx in -r...r { g.world.set(x + dx, 100 - h + dy - 1, .leaves) }
    }
}
func look(_ g: Game, _ x: Double, _ y: Double) {
    g.camX = x; g.camY = y
    g.camTX = x; g.camTY = y
    g.updateLight(1.0 / 60.0)
}

// 1: a house under a balloon, high over the meadow, the player inside
do {
    let g = world()
    let cx = Int(g.pb.x)
    tree(g, cx - 14, 5); tree(g, cx + 12, 6); tree(g, cx + 22, 4)
    var cells: [(Int, Int, PartType, Tile?)] = []
    // the room: plank walls and floor, a window, a roof of shingles
    for x in 0..<9 {
        for y in 0..<6 where x == 0 || x == 8 || y == 0 || y == 5 {
            if y == 0 && x >= 3 && x <= 5 { continue }
            if x == 8 && (y == 2 || y == 3) { cells.append((x, y, .block, .glass)); continue }
            cells.append((x, y, .block, y == 0 ? .shingles : .planks))
        }
    }
    for x in 3...5 { cells.append((x, 0, .burner, nil)) }
    for x in 0..<9 { for y in (-6)..<0 { cells.append((x, y, .envelope, nil)) } }
    cells.append((1, 4, .cockpit, nil)); cells.append((7, 4, .block, .chest)); cells.append((6, 4, .block, .table))
    cells.append((-1, 3, .airProp, nil)); cells.append((-1, 4, .engine, nil)); cells.append((2, 4, .autopilot, nil))
    let v = vehicle(g, cells, left: Double(cx) - 4.0, bottom: 86)
    v.heat = 0.6
    g.pauseVehicles = true
    g.boardFrame(&g.pb, v, 4.5, 5.0)
    g.pb.onGround = true
    g.facing = 1
    let pig = g.addMob(.pig, 0, 0)
    pig.persistent = true
    g.boardFrame(&pig.b, v, 6.0, 5.0)
    pig.b.onGround = true
    pig.dir = -1
    look(g, Double(cx) + 0.5, 82)
    render(g, "01_balloon_house")
}

// 2: a flatbed truck at speed, riders on its deck
do {
    let g = world()
    let cx = Int(g.pb.x)
    tree(g, cx - 16, 5); tree(g, cx + 18, 5)
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<12 { cells.append((x, 0, .frame, nil)) }
    for x in [0, 3, 8, 11] { cells.append((x, 1, .offroadWheel, nil)) }
    cells.append((11, -1, .cockpit, nil)); cells.append((10, -1, .engine, nil)); cells.append((9, -1, .engine, nil))
    cells.append((0, -1, .block, .crate)); cells.append((0, -2, .block, .crate)); cells.append((1, -1, .block, .crate))
    let v = vehicle(g, cells, left: Double(cx) - 6.0, bottom: 100)
    g.pauseVehicles = true
    v.vx = 14
    g.boardFrame(&g.pb, v, 5.0, 0.0)
    g.pb.onGround = true
    g.facing = 1
    let hen = g.addMob(.chicken, 0, 0)
    hen.persistent = true
    g.boardFrame(&hen.b, v, 3.0, 0.0)
    hen.b.onGround = true
    hen.dir = 1
    g.spawnDrop(Stack(item: .mat(.coal), count: 6), 0, 0, 0, 0)
    if !g.drops.isEmpty {
        g.drops[0].ride = v.id; g.drops[0].rlx = 7.5; g.drops[0].rly = 0.0
        let w = v.toWorld(7.5, 0.0)
        g.drops[0].x = w.0; g.drops[0].y = w.1; g.drops[0].onGround = true
    }
    // dust behind the wheels
    for _ in 0..<3 { g.spawnParticles(v.b.left - 0.5, 100.0, 0xB0A890, 4, 2.5, 0.5, 6) }
    look(g, Double(cx) + 0.5, 95.5)
    render(g, "02_truck_deck")
}

// 3 (phase 2): a long deck carried on wheels with a plane parked on it and a crate stack, the player
// walking the deck between them
do {
    let g = world()
    let cx = Int(g.pb.x)
    tree(g, cx - 24, 6); tree(g, cx + 26, 5)
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<30 { cells.append((x, 0, .frame, nil)); cells.append((x, 1, .block, .brick)) }
    for x in [1, 6, 11, 18, 23, 28] { cells.append((x, 2, .offroadWheel, nil)) }
    // a bridge at the front with a window
    for y in -4...(-1) { cells.append((27, y, .block, .planks)); cells.append((29, y, .block, .planks)) }
    cells.append((28, -4, .block, .planks)); cells.append((28, -3, .block, .glass)); cells.append((28, -1, .cockpit, nil))
    cells.append((28, -2, .block, .planks))
    let deck = vehicle(g, cells, left: Double(cx) - 15.0, bottom: 100)
    let plane = Vehicle(id: g.newID(), first: .frame, x: 0, y: 0)
    plane.parts.removeAll()
    for p in kitLayout(.planeKit) { plane.parts[PartCell(dx: p.dx, dy: p.dy)] = p.p }
    plane.recompute(keepAnchor: false)
    let surface: Double = deck.toWorld(0.0, 0.0).1
    plane.placeBox(left: Double(cx) - 12.0, bottom: surface + 0.02)
    g.vehicles.append(plane)
    var crate: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<2 { for y in 0..<2 { crate.append((x, y, .block, .crate)) } }
    _ = vehicle(g, crate, left: Double(cx) + 6.0, bottom: surface)
    g.pauseVehicles = true
    g.boardFrame(&g.pb, deck, 18.5, -0.0)
    g.pb.onGround = true
    g.facing = -1
    look(g, Double(cx) + 0.5, 94.0)
    render(g, "03_deck_plane")
}

// 4 (phase 2): inside a vehicle: back walls, a door, a ladder to an upper floor, a chair, a bed, a
// workbench and a chest, drawn from the vehicle's one picture
do {
    let g = world()
    let cx = Int(g.pb.x)
    var cells: [(Int, Int, PartType, Tile?)] = []
    let w = 16
    for x in 0..<w {
        cells.append((x, 0, .frame, nil))
        cells.append((x, -9, .block, .shingles))
        if x != 6 { cells.append((x, -5, .block, .planks)) }
    }
    cells.append((6, -5, .block, .platform))
    for y in 1...8 {
        if y == 1 || y == 2 { cells.append((w - 1, -y, .block, .doorClosed)) } else { cells.append((w - 1, -y, .block, .planks)) }
        cells.append((0, -y, .block, y == 3 || y == 7 ? .glass : .planks))
    }
    for y in 1...4 { cells.append((6, -y, .block, .ladder)) }
    cells.append((2, -1, .block, .chair)); cells.append((3, -1, .block, .table)); cells.append((9, -1, .block, .workbench))
    cells.append((12, -1, .block, .chest)); cells.append((2, -6, .block, .bedL)); cells.append((3, -6, .block, .bedR))
    cells.append((10, -6, .block, .bookshelf)); cells.append((12, -6, .block, .floorLamp))
    for x in [1, 5, 10, 14] { cells.append((x, 1, .wheel, nil)) }
    cells.append((13, -6, .cockpit, nil)); cells.append((14, -6, .engine, nil))
    let v = vehicle(g, cells, left: Double(cx) - 8.0, bottom: 100)
    for x in 1..<(w - 1) { for y in 1...8 where y != 5 { v.walls[PartCell(dx: x, dy: -y)] = UInt8(blockWallValue(.planks)) } }
    v.recompute(keepAnchor: true)
    g.pauseVehicles = true
    g.boardFrame(&g.pb, v, 6.5, -1.0)
    g.pb.onGround = true
    g.facing = 1
    look(g, Double(cx) + 0.5, 95.0)
    render(g, "04_vehicle_insides")
}
