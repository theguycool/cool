import SwiftUI
import Foundation
// Headless screenshots of step 5b: suits built piece by piece. A sheet of designs (the ready-made ones in
// several metals, a painted one, a damaged one, and the walk and strike poses); then in the world a
// suited player whose turret fires at a zombie, a flight on jets and a wing, and a laser and a cannon
// shell. The Assembly Station's designer is SwiftUI and is not drawn here.
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/suit5shots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prsuit5shots-" + String(Int.random(in: 1000...999999)), isDirectory: true)

func render(_ g: Game, _ name: String) {
    let t = RasterTarget(W, H)
    GraphicsContext.target = t
    var ctx = GraphicsContext()
    WorldRenderer.draw(&ctx, CGSize(width: W, height: H), g)
    GraphicsContext.target = nil
    t.save(outDir + "/" + name + ".rgb")
    print("rendered", name)
}
func steps(_ g: Game, _ n: Int) { for _ in 0..<n { g.tick(1.0 / 60.0) } }
func look(_ g: Game, _ x: Double, _ y: Double) {
    g.camX = x; g.camY = y
    g.updateLight(1.0 / 60.0)
}
func piece(_ k: SuitKind, _ b: SuitBone, _ cx: Double, _ cy: Double, _ w: Double, _ h: Double, _ m: ExoMat, _ s: SuitShape = .box, rot: Double = 0, color: UInt32 = 0, thick: Int = 1) -> SuitPiece {
    var p: SuitPiece = SuitTemplates.piece(k, b, cx, cy, w, h, m, s)
    p.rot = rot
    p.color = color
    p.thick = thick
    return p
}
func design(_ ps: [SuitPiece]) -> SuitDesign {
    var d = SuitDesign()
    for var p in ps {
        p.id = d.newID()
        d.pieces.append(p)
    }
    return d
}
/// a hand-made design: a crested, painted samurai-like suit with spiked shoulders and a lamp
func painted() -> SuitDesign {
    let red: UInt32 = 0xB8282E
    let black: UInt32 = 0x24242A
    let gold: UInt32 = 0xE8C048
    return design([
        piece(.plate, .head, 5.0, 3.2, 6.2, 4.6, .iron, .rounded, color: black),
        piece(.plate, .head, 5.0, 1.0, 3.6, 0.8, .gold, .wedge, rot: 0, color: gold),
        piece(.plate, .head, 3.2, 0.6, 0.8, 2.4, .gold, .spike, rot: -25, color: gold),
        piece(.plate, .head, 6.8, 0.6, 0.8, 2.4, .gold, .spike, rot: 25, color: gold),
        piece(.frame, .head, 6.0, 3.6, 3.4, 0.6, .iron, color: 0xFFE070),
        piece(.plate, .torso, 5.0, 8.4, 4.2, 3.8, .iron, color: red),
        piece(.plate, .torso, 5.0, 8.0, 3.0, 0.6, .gold, color: gold),
        piece(.plate, .torso, 5.0, 10.8, 6.4, 1.2, .iron, color: black),
        piece(.plate, .armBack, 1.8, 7.2, 3.0, 1.6, .iron, .rounded, color: red),
        piece(.plate, .armFront, 8.2, 7.2, 3.0, 1.6, .iron, .rounded, color: red),
        piece(.plate, .armBack, 0.6, 6.6, 0.8, 1.6, .gold, .spike, rot: -40, color: gold),
        piece(.plate, .armFront, 9.4, 6.6, 0.8, 1.6, .gold, .spike, rot: 40, color: gold),
        piece(.plate, .armBack, 2.0, 9.2, 2.0, 1.8, .iron, color: black),
        piece(.plate, .armFront, 8.0, 9.2, 2.0, 1.8, .iron, color: black),
        piece(.plate, .legBack, 3.0, 12.6, 2.4, 2.0, .iron, .wedge, rot: 90, color: red),
        piece(.plate, .legFront, 7.0, 12.6, 2.4, 2.0, .iron, .wedge, rot: 180, color: red),
        piece(.plate, .legBack, 3.0, 14.4, 2.0, 1.6, .iron, color: black),
        piece(.plate, .legFront, 7.0, 14.4, 2.0, 1.6, .iron, color: black),
        piece(.plate, .legBack, 3.0, 15.5, 2.6, 1.0, .iron, .rounded, color: gold),
        piece(.plate, .legFront, 7.0, 15.5, 2.6, 1.0, .iron, .rounded, color: gold)
    ])
}

// 1: a sheet of designs, drawn as the Assembly Station draws them, three times larger
do {
    var sheet = PixelBuf(w: W, h: H)
    for i in 0..<sheet.px.count { sheet.px[i] = 0xFF22262E }
    let plain: [PixelBuf] = humanoidFrames(playerStyle(hairIdx: 1, scarfIdx: 2, head: nil, chest: nil, legs: nil))
    var designs: [(SuitDesign, Int)] = []
    designs.append((SuitTemplates.design(1, .bronze), 0))
    designs.append((SuitTemplates.design(2, .iron), 0))
    designs.append((SuitTemplates.design(3, .diamond), 0))
    designs.append((SuitTemplates.design(4, .mythril), 0))
    designs.append((painted(), 0))
    var worn: SuitDesign = SuitTemplates.design(2, .ember)
    for k in worn.pieces.indices { worn.pieces[k].dmg = Double(k % 4) * 0.3 }
    worn.pieces[2].dmg = 1
    worn.pieces[5].dmg = 1
    designs.append((worn, 0))
    var gear: SuitDesign = SuitTemplates.design(2, .voidium)
    for m in [ExoModule.turret, .laser, .hover, .lamp] {
        var p: SuitPiece = SuitTemplates.module(m)
        p.id = gear.newID()
        gear.pieces.append(p)
    }
    var c: SuitPiece = SuitTemplates.core(.heart)
    c.id = gear.newID()
    gear.pieces.append(c)
    designs.append((gear, 0))
    designs.append((painted(), 1))
    designs.append((painted(), 4))
    designs.append((gear, 6))
    let scale: Int = 3
    let cellW: Int = 164
    for (i, dv) in designs.enumerated() {
        var cv: PixelBuf = upscale3(plain[dv.1])
        paintSuitPieces(&cv, dv.0, frame: dv.1)
        let col: Int = i % 5
        let row: Int = i / 5
        let ox: Int = 18 + col * (cellW + 52)
        let oy: Int = 60 + row * 320
        for y in 0..<cv.h {
            for x in 4..<(cv.w - 4) {
                let p: UInt32 = cv.px[y * cv.w + x]
                if (p >> 24) == 0 { continue }
                for yy in 0..<scale {
                    for xx in 0..<scale {
                        let sx: Int = ox + (x - 4) * scale + xx
                        let sy: Int = oy + y * scale + yy
                        if sx >= 0 && sy >= 0 && sx < W && sy < H { sheet.px[sy * W + sx] = p }
                    }
                }
            }
        }
    }
    var raw: [UInt8] = []
    raw.reserveCapacity(W * H * 3)
    for p in sheet.px {
        raw.append(UInt8((p >> 16) & 0xFF))
        raw.append(UInt8((p >> 8) & 0xFF))
        raw.append(UInt8(p & 0xFF))
    }
    _ = FileManager.default.createFile(atPath: outDir + "/01_designs.rgb", contents: Data(raw))
    print("rendered 01_designs")
}

func world(_ tile: Int) -> Game {
    ModRuntime.activate([], world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 5151, settings: Settings(), options: .standard)
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true
    g.settings.weatherOn = false
    g.tilePx = tile
    g.timeOfDay = 0.3
    g.freezeTime = true
    let w = g.world
    let cx = Int(g.pb.x)
    w.loadAround(centerX: cx, radius: 6)
    for x in (cx - 50)...(cx + 50) {
        for y in 50..<100 { w.set(x, y, .air); w.setWall(x, y, 0) }
        for y in 100..<106 { w.set(x, y, .dirt) }
        w.set(x, 100, .grass)
    }
    g.pb.x = Double(cx) + 0.5; g.pb.y = 100
    return g
}
func wear(_ g: Game, _ d: SuitDesign) {
    _ = g.applyDesign(d)
    _ = g.wearSuit()
    g.suit.energy = g.suitStats.capacity
}

// 2: the knight's suit in iron with a turret on the shoulder, shooting a zombie; a plate broken off
do {
    let g = world(34)
    var d: SuitDesign = SuitTemplates.design(2, .iron)
    for m in [ExoModule.turret] {
        var p: SuitPiece = SuitTemplates.module(m)
        p.id = d.newID()
        d.pieces.append(p)
    }
    var c: SuitPiece = SuitTemplates.core(.crystal)
    c.id = d.newID()
    d.pieces.append(c)
    wear(g, d)
    g.godMode = true
    var dd: SuitDesign = g.suit.d
    dd.pieces[8].dmg = 1
    dd.pieces[3].dmg = 0.7
    g.suit.d = dd
    g.suitChanged()
    let z: Mob = g.addMob(.zombie, g.pb.x + 6, 100)
    z.persistent = true
    z.maxHP = 500; z.hp = 500
    for _ in 0..<70 {
        g.tick(1.0 / 60.0)
        z.b.x = g.pb.x + 6
    }
    look(g, g.pb.x + 3, 97)
    render(g, "02_turret_and_damage")
}

// 3: flying on three jets with a wing
do {
    let g = world(30)
    var d: SuitDesign = SuitTemplates.design(1, .mythril)
    for k in 0..<3 {
        var j: SuitPiece = SuitTemplates.module(.hover)
        j.w = 6; j.h = 9
        j.y += Double(k) * 3
        j.id = d.newID()
        d.pieces.append(j)
    }
    var w: SuitPiece = SuitTemplates.module(.wing)
    w.w = 30; w.h = 9
    w.id = d.newID()
    d.pieces.append(w)
    var c: SuitPiece = SuitTemplates.core(.heart)
    c.id = d.newID()
    d.pieces.append(c)
    wear(g, d)
    g.mode = .survival
    g.godMode = true
    g.pb.y = 92
    g.pb.onGround = false
    g.jumpHeld = true
    g.keyR = true
    steps(g, 50)
    look(g, g.pb.x + 2, g.pb.y - 2)
    render(g, "03_flying")
}

// 4: a laser burning a zombie and a cannon shell on its way
do {
    let g = world(30)
    var d: SuitDesign = painted()
    for m in [ExoModule.laser, .cannon] {
        var p: SuitPiece = SuitTemplates.module(m)
        p.id = d.newID()
        d.pieces.append(p)
    }
    var c: SuitPiece = SuitTemplates.core(.heart)
    c.id = d.newID()
    d.pieces.append(c)
    wear(g, d)
    g.godMode = true
    let z: Mob = g.addMob(.zombie, g.pb.x + 7, 100)
    z.persistent = true
    z.maxHP = 900; z.hp = 900
    g.aimX = z.b.x; g.aimY = z.b.cy; g.aimValid = true
    g.suitFireHeld = true
    for _ in 0..<12 {
        g.tick(1.0 / 60.0)
        z.b.x = g.pb.x + 7
        g.aimX = z.b.x; g.aimY = z.b.cy
    }
    look(g, g.pb.x + 3, 97)
    render(g, "04_laser_and_cannon")
}
