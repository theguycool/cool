import SwiftUI
import Foundation
// Headless screenshots of phase 3's building: a furnished house with walls put up from blocks,
// wooden stairs to its upper floor and a lift beside it; a blast throwing blocks; and a beam under
// strain with structural physics on.
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/buildingshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
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
    let g = Game(mode: .creative, infinite: true, seed: 4242, settings: Settings())
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true; g.godMode = true
    g.settings.weatherOn = false
    g.tilePx = 24
    g.timeOfDay = 0.3
    let x0 = Int(g.pb.x) - 40
    g.world.loadAround(centerX: Int(g.pb.x), radius: 6)
    for x in x0...(x0 + 80) {
        for y in 40..<100 { g.world.set(x, y, .air); g.world.setWall(x, y, 0) }
        g.world.set(x, 100, .grass)
        for y in 101..<106 { g.world.set(x, y, .dirt) }
    }
    return g
}
func b(_ g: Game, _ x: Int, _ y: Int, _ t: Tile) { g.world.set(x, y, t); g.world.setBuilt(x, y, true) }

// 1: a house: brick walls behind (blocks put up as walls), a floor, furniture, stairs, a lift
do {
    let g = world()
    let x0 = Int(g.pb.x) - 12
    for x in x0...(x0 + 16) { for y in 88...99 { g.world.setWall(x, y, blockWallValue(y < 94 ? .planks : .brick)) } }
    for y in 88...99 { b(g, x0, y, .logBlock); b(g, x0 + 16, y, .logBlock) }
    for x in x0...(x0 + 16) { b(g, x, 87, .planks); if x < x0 + 9 || x > x0 + 11 { b(g, x, 93, .planks) } }
    // downstairs
    b(g, x0 + 2, 99, .bookshelf); b(g, x0 + 3, 99, .floorLamp); b(g, x0 + 4, 99, .sofa); b(g, x0 + 5, 99, .sofa)
    b(g, x0 + 7, 99, .chair); b(g, x0 + 8, 99, .table); b(g, x0 + 9, 99, .chair)
    // the stairs up to the first floor
    for k in 0..<6 { b(g, x0 + 10 + k, 99 - k, .stairWoodR) }
    // upstairs
    b(g, x0 + 2, 92, .bedL); b(g, x0 + 3, 92, .bedR); b(g, x0 + 5, 92, .wardrobe); b(g, x0 + 6, 92, .cabinet)
    b(g, x0 + 7, 90, .shelf)
    // the lift beside the house
    let sx = x0 + 20
    for y in 80...99 { b(g, sx, y, .liftRail) }
    b(g, sx - 2, 99, .liftButton); b(g, sx - 2, 92, .liftButton)
    let l = Lift(id: 1, x: sx, y: 93)
    g.lifts.append(l)
    g.pb.x = Double(x0 + 7) + 0.5; g.pb.y = 100
    g.seat = IntPair(x: x0 + 7, y: 99)
    g.camX = Double(x0 + 12); g.camY = 92
    g.light.valid = false
    for _ in 0..<3 { g.tick(1.0 / 60.0) }
    g.camX = Double(x0 + 12); g.camY = 92
    render(g, "01_house")
}

// 2: a bomb in a plank shed: blocks thrown, turning in the air
do {
    let g = world()
    let x0 = Int(g.pb.x) + 4
    for x in x0...(x0 + 8) { b(g, x, 93, .planks) }
    for y in 94...99 { b(g, x0, y, .planks); b(g, x0 + 8, y, .brick) }
    g.explode(Double(x0 + 4) + 0.5, 98.0, radius: 3.4, power: 26, source: .environment, breakBlocks: true)
    for _ in 0..<14 { g.tick(1.0 / 60.0) }
    g.camX = Double(x0 + 4); g.camY = 94
    g.shake = 0
    render(g, "02_blast")
}

// 3: structural physics: a plank beam at the end of its reach, cracked; brick stairs
do {
    let g = world()
    g.settings.structural = true
    g.tick(1.0 / 60.0)
    let x0 = Int(g.pb.x) - 6
    for y in 93...99 { b(g, x0, y, .planks) }
    for x in (x0 + 1)...(x0 + 4) { b(g, x, 93, .planks) }
    for k in 0..<4 { b(g, x0 + 7 + k, 99 - k, .stairBrickR) }
    for k in 0..<4 { b(g, x0 + 13 + k, 96 + k, .stairStoneL) }
    _ = g.settleStructure(x0, 99, maxFalls: 0)
    g.camX = Double(x0 + 6); g.camY = 95
    for _ in 0..<2 { g.tick(1.0 / 60.0) }
    g.camX = Double(x0 + 6); g.camY = 95
    render(g, "03_structure")
}
