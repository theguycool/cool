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

// 5 (phase 3): water poured from a ledge falls, spreads over the floor and fills a stone basin, half
// way through; lava meeting the water has set into obsidian
do {
    let g = world()
    let cx = Int(g.pb.x)
    let w = g.world
    // a cliff with a ledge on the left, a basin below
    for x in (cx - 14)...(cx - 8) { for y in 88..<100 { w.set(x, y, .stone) } }
    for x in (cx - 8)...(cx + 10) { w.set(x, 100, .stone) }
    for y in 92...99 { w.set(cx + 10, y, .stone) }
    w.flowQ.removeAll(); w.flowSet.removeAll()
    // a pool of lava at the far end
    for x in (cx + 6)...(cx + 9) { w.setLiquidLevel(x, 99, .lava, 255) }
    // poured off the ledge's edge: a falling stream, a pool spreading below
    var k = 0
    while k < 90 {
        if k % 2 == 0 { w.setLiquidLevel(cx - 7, 87, .water, 255) }
        w.stepFlow(Liquids.budget)
        k += 1
    }
    g.pb.x = Double(cx) - 11.5; g.pb.y = 88
    g.facing = 1
    look(g, Double(cx) + 0.5, 92.0)
    render(g, "05_flowing_water")
}

// 6 (phase 3): a submarine under the sea, its cabin dry, the player standing inside
do {
    let g = world()
    let cx = Int(g.pb.x)
    let w = g.world
    for x in (cx - 40)...(cx + 40) {
        for y in 86..<104 { w.set(x, y, .water) }
        for y in 104..<110 { w.set(x, y, .sand) }
    }
    w.flowQ.removeAll(); w.flowSet.removeAll()
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<12 {
        cells.append((x, 5, .block, .stone))
        cells.append((x, 0, .block, .planks))
    }
    for y in 1...4 { cells.append((0, y, .block, .planks)); cells.append((11, y, .block, y == 2 ? .glass : .planks)) }
    for x in 1...10 { cells.append((x, 4, .ballast, nil)) }
    cells.append((9, 3, .cockpit, nil)); cells.append((-1, 2, .propeller, nil)); cells.append((-1, 3, .engine, nil))
    cells.append((3, 3, .block, .chest)); cells.append((5, 3, .block, .chair))
    let v = vehicle(g, cells, left: Double(cx) - 6.0, bottom: 99)
    for x in 1...10 { for y in 1...3 { v.walls[PartCell(dx: x, dy: y)] = UInt8(blockWallValue(.planks)) } }
    v.recompute(keepAnchor: true)
    v.ballast = 1
    g.updateHullAir(v, 1.0)
    g.pauseVehicles = true
    g.boardFrame(&g.pb, v, 7.5, 4.0)
    g.pb.onGround = true
    g.facing = 1
    look(g, Double(cx) + 0.5, 94.0)
    render(g, "06_submarine")
}

// 7 (phase 4): a train on rails: an engine pulling two ore carts, coupled, over a track built in steps
do {
    let g = world()
    let cx = Int(g.pb.x)
    let w = g.world
    tree(g, cx - 22, 6); tree(g, cx + 24, 5)
    for x in (cx - 30)...(cx - 2) { w.set(x, 99, .rail) }
    // a step down, then on
    for x in (cx - 1)...(cx + 30) { w.set(x, 99, .air); w.set(x, 100, .rail); w.set(x, 101, .dirt) }
    var loco: [(Int, Int, PartType, Tile?)] = [(0, 0, .block, .planks), (1, 0, .engine, nil), (2, 0, .engine, nil), (0, -1, .cockpit, nil), (1, -1, .block, .planks), (2, -1, .fuelTank, nil), (0, 1, .railWheel, nil), (2, 1, .railWheel, nil), (1, 1, .railWheel, nil), (-1, 0, .coupler, nil)]
    loco.append((1, -2, .block, .planks)); loco.append((0, -2, .block, .planks))
    let engine = vehicle(g, loco, left: Double(cx) + 3.4, bottom: 101)
    let c1 = vehicle(g, [(0, 0, .cargo, nil), (1, 0, .cargo, nil), (0, 1, .railWheel, nil), (1, 1, .railWheel, nil), (-1, 0, .coupler, nil), (2, 0, .coupler, nil)], left: Double(cx) - 1.0, bottom: 101)
    let c2 = vehicle(g, [(0, 0, .cargo, nil), (1, 0, .cargo, nil), (0, 1, .railWheel, nil), (1, 1, .railWheel, nil), (-1, 0, .coupler, nil), (2, 0, .coupler, nil)], left: Double(cx) - 5.4, bottom: 100)
    // coupled end to end: the engine's back to the first cart's front, that cart's back to the second's
    engine.links = [VLink(cell: PartCell(dx: -1, dy: 0), other: c1.id, oc: PartCell(dx: 2, dy: 0), len: 1.2)]
    c1.links = [VLink(cell: PartCell(dx: 2, dy: 0), other: engine.id, oc: PartCell(dx: -1, dy: 0), len: 1.2), VLink(cell: PartCell(dx: -1, dy: 0), other: c2.id, oc: PartCell(dx: 2, dy: 0), len: 1.2)]
    c2.links = [VLink(cell: PartCell(dx: 2, dy: 0), other: c1.id, oc: PartCell(dx: -1, dy: 0), len: 1.2)]
    c1.angle = 0.0
    g.pauseVehicles = true
    g.boardFrame(&g.pb, c1, 1.0, 0.0)
    g.pb.onGround = true
    g.facing = 1
    look(g, Double(cx) + 0.5, 95.0)
    render(g, "07_train")
}

// 8 (phase 4): a truck on big wheels climbing a step two blocks high, a small-wheeled car stopped at it
do {
    let g = world()
    let cx = Int(g.pb.x)
    let w = g.world
    for x in (cx + 2)...(cx + 30) { w.set(x, 99, .stone); w.set(x, 98, .stone) }
    var cells: [(Int, Int, PartType, Tile?)] = []
    for x in 0..<6 { cells.append((x, 0, .frame, nil)) }
    cells.append((4, -1, .cockpit, nil)); cells.append((3, -1, .engine, nil)); cells.append((2, -1, .engine, nil)); cells.append((5, -1, .block, .glass))
    let truck = vehicle(g, cells, left: Double(cx) - 7.0, bottom: 97)
    for mid in [PartCell(dx: 0, dy: 2), PartCell(dx: 5, dy: 2)] {
        for dy in -1...1 { for dx in -1...1 { let k = PartCell(dx: mid.dx + dx, dy: mid.dy + dy); truck.parts[k] = .bigWheel; truck.spanOf[k] = mid } }
    }
    truck.recompute(keepAnchor: false)
    truck.placeBox(left: Double(cx) - 4.6, bottom: 100)
    truck.wheelRot = 0.6
    let car = vehicle(g, [(0, 0, .frame, nil), (1, 0, .frame, nil), (2, 0, .frame, nil), (0, 1, .wheel, nil), (2, 1, .wheel, nil), (0, -1, .seat, nil), (1, -1, .steering, nil), (2, -1, .engine, nil)], left: Double(cx) - 16.0, bottom: 100)
    _ = car
    g.pauseVehicles = true
    g.pb.x = Double(cx) - 20.5; g.pb.y = 100
    look(g, Double(cx) - 2.5, 94.0)
    render(g, "08_big_wheels")
}
