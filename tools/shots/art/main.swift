import SwiftUI
import Foundation
// Headless screenshots of the hand-drawn art in the world, at the pixel size an iPad shows it (48
// screen pixels to a block: three to an art pixel): a meadow by day with the player at rest among farm
// animals and a bear by a small house; the same land at night with zombies, a skeleton and slimes
// closing on the player; a cave with every ore; bears and an elephant side by side; pirates and the
// deep monsters; the three bosses.
let W = 1680, H = 960
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/artshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prartshots-" + String(Int.random(in: 1000...999999)), isDirectory: true)

func render(_ g: Game, _ name: String) {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    WorldRenderer.draw(&ctx, CGSize(width: W, height: H), g)
    GraphicsContext.target = nil
    t.save(outDir + "/" + name + ".rgb")
    print("rendered", name)
}
func look(_ g: Game, _ x: Double, _ y: Double) {
    g.camX = x; g.camY = y
    g.pb.onGround = true
    g.updateLight(1.0 / 60.0)
}
func world(_ time: Double) -> Game {
    ModRuntime.activate([], world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 4242, settings: Settings(), options: .standard)
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true
    g.settings.weatherOn = false
    g.tilePx = 48
    g.timeOfDay = time
    g.freezeTime = true
    let w = g.world
    let cx = Int(g.pb.x)
    w.loadAround(centerX: cx, radius: 6)
    for x in (cx - 60)...(cx + 60) {
        for y in 40..<100 { w.set(x, y, .air); w.setWall(x, y, 0) }
        for y in 100..<104 { w.set(x, y, .dirt) }
        for y in 104..<130 { w.set(x, y, .stone) }
        w.set(x, 100, .grass)
    }
    g.pb.x = Double(cx) + 0.5; g.pb.y = 100
    return g
}
func tree(_ g: Game, _ x: Int, _ h: Int, _ log: Tile = .log, _ leaf: Tile = .leaves) {
    for y in (100 - h)..<100 { g.world.set(x, y, log) }
    for dy in -2...1 {
        let r: Int = dy <= -2 ? 1 : 2
        for dx in -r...r { g.world.set(x + dx, 100 - h + dy - 1, leaf) }
    }
}
func still(_ g: Game, _ m: Mob, dir: Int = 1) {
    m.dir = dir; m.face = dir
    m.b.vx = 0
}

// 1: a meadow by day
do {
    let g = world(0.3)
    let cx = Int(g.pb.x)
    tree(g, cx - 14, 5); tree(g, cx + 15, 6); tree(g, cx - 4, 4, .birchLog, .birchLeaves)
    for x in [cx - 9, cx - 8, cx + 3, cx + 9, cx + 10] { g.world.set(x, 99, .tallGrass) }
    g.world.set(cx - 7, 99, .flowerR); g.world.set(cx + 4, 99, .flowerY)
    // a small house: planks, a brick base, a workbench, a chest and a torch
    for x in (cx + 6)...(cx + 12) {
        g.world.set(x, 95, .planks)
        for y in 96..<100 { g.world.setWall(x, y, blockWallValue(.planks)) }
    }
    for y in 96..<100 { g.world.set(cx + 12, y, .brick) }
    g.world.set(cx + 6, 96, .planks)
    g.world.set(cx + 8, 99, .workbench); g.world.set(cx + 10, 99, .chest); g.world.set(cx + 9, 97, .torch); g.world.set(cx + 11, 99, .furnace)
    still(g, g.addMob(.pig, Double(cx) - 2.5, 100)); still(g, g.addMob(.cow, Double(cx) - 6.5, 100), dir: -1)
    still(g, g.addMob(.chicken, Double(cx) + 2.5, 100), dir: -1); still(g, g.addMob(.chicken, Double(cx) + 4.2, 100))
    still(g, g.addMob(.bear, Double(cx) - 11.5, 100)); still(g, g.addMob(.sheep, Double(cx) + 13.5, 100), dir: -1)
    let crow = g.addMob(.crow, Double(cx) - 1.0, 93.5); still(g, crow)
    g.restT = 3
    // a few seconds of leaves coming down from the canopies
    g.camX = g.pb.x; g.camY = 95.5
    for _ in 0..<600 { g.updateLeafFall(1.0 / 60.0) }
    look(g, g.pb.x, 95.5)
    render(g, "01_meadow")
}

// 2: night at the door
do {
    let g = world(0.78)
    let cx = Int(g.pb.x)
    tree(g, cx - 12, 5)
    g.world.set(cx - 2, 99, .torch); g.world.set(cx + 7, 99, .torch)
    for x in [cx - 7, cx + 4, cx + 11] { g.world.set(x, 99, .tallGrass) }
    g.facing = 1
    g.restT = 0
    let z0 = g.addMob(.zombie, Double(cx) + 3.5, 100); still(g, z0, dir: -1)
    let z1 = g.addMob(.zombie, Double(cx) + 6.0, 100); z1.variant = 1; still(g, z1, dir: -1); z1.anim = 0.3; z1.b.vx = -1
    let z2 = g.addMob(.zombie, Double(cx) + 9.0, 100); z2.variant = 2; still(g, z2, dir: -1); z2.anim = 0.8; z2.b.vx = -1
    let sk = g.addMob(.skeleton, Double(cx) - 4.5, 100); still(g, sk)
    let sk2 = g.addMob(.skeleton, Double(cx) - 8.0, 100); still(g, sk2); sk2.blocking = true
    still(g, g.addMob(.slime, Double(cx) + 12.0, 100), dir: -1)
    look(g, g.pb.x + 1, 95.5)
    render(g, "02_night")
}

// 3: a cave with every ore
do {
    let g = world(0.3)
    let cx = Int(g.pb.x)
    for x in (cx - 20)...(cx + 20) {
        for y in 84..<100 { g.world.set(x, y, .stone) }
        for y in 92..<100 where abs(x - cx) < 16 { g.world.set(x, y, .air); g.world.setWall(x, y, 2) }
    }
    let ores: [Tile] = [.coal, .copper, .iron, .gold, .diamond, .mythril, .tin, .silver]
    for (i, t) in ores.enumerated() {
        g.world.set(cx - 12 + i * 3, 91, t); g.world.set(cx - 11 + i * 3, 91, t); g.world.set(cx - 12 + i * 3, 90, t)
    }
    g.world.set(cx - 3, 99, .torch); g.world.set(cx + 6, 99, .torch); g.world.set(cx - 10, 99, .torch); g.world.set(cx + 12, 99, .torch)
    still(g, g.addMob(.slime, Double(cx) + 4.5, 100), dir: -1)
    still(g, g.addMob(.emberSlime, Double(cx) + 8.5, 100), dir: -1)
    still(g, g.addMob(.skeleton, Double(cx) - 6.5, 100))
    g.restT = 0
    look(g, g.pb.x, 94.5)
    render(g, "03_cave")
}

// 4: the big animals
do {
    let g = world(0.35)
    let cx = Int(g.pb.x)
    for x in (cx - 30)...(cx - 2) { g.world.set(x, 100, .snow); g.world.set(x, 101, .snow) }
    tree(g, cx + 16, 6, .jungleLog, .jungleLeaves)
    still(g, g.addMob(.polarBear, Double(cx) - 9.0, 100)); still(g, g.addMob(.grizzly, Double(cx) + 4.5, 100), dir: -1)
    still(g, g.addMob(.bear, Double(cx) + 8.5, 100))
    still(g, g.addMob(.elephant, Double(cx) + 12.5, 100), dir: -1)
    g.restT = 0
    look(g, g.pb.x + 1, 94.5)
    render(g, "04_big_animals")
}

// 5: pirates on the shore, and the deep monsters in a cavern
do {
    let g = world(0.32)
    let cx = Int(g.pb.x)
    for x in (cx + 2)...(cx + 30) { g.world.set(x, 100, .sand); g.world.set(x, 101, .sand) }
    g.facing = 1
    g.restT = 0
    let p0 = g.addMob(.pirate, Double(cx) + 4.5, 100); still(g, p0, dir: -1)
    let p1 = g.addMob(.pirateGunner, Double(cx) + 7.5, 100); still(g, p1, dir: -1); p1.st = 3
    let p2 = g.addMob(.pirateCaptain, Double(cx) + 10.5, 100); still(g, p2, dir: -1); p2.st = 3
    let p3 = g.addMob(.pirate, Double(cx) + 13.5, 100); still(g, p3, dir: -1); p3.st = 4
    let cr = g.addMob(.crawler, Double(cx) - 4.5, 100); still(g, cr)
    let go = g.addMob(.golem, Double(cx) - 9.0, 100); still(g, go)
    let se = g.addMob(.sentinel, Double(cx) - 14.0, 98.0); still(g, se)
    look(g, g.pb.x, 95.5)
    render(g, "05_foes")
}

// 6: the three bosses
do {
    let g = world(0.4)
    let cx = Int(g.pb.x)
    g.pb.x = Double(cx) - 20
    let ur = g.addMob(.bearBoss, Double(cx) - 10.0, 100); still(g, ur)
    let rx = g.addMob(.rex, Double(cx) + 1.0, 100); still(g, rx); rx.st = 2
    let wd = g.addMob(.warden, Double(cx) + 11.0, 98.5); still(g, wd, dir: -1)
    look(g, Double(cx) + 0.5, 95.0)
    render(g, "06_bosses")
}
