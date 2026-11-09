import SwiftUI
import Foundation
// Headless screenshots of phase 4's vehicles: every kit parked in a row; a plane, a helicopter and an
// airship in the air; a tank firing at a wrecked truck; a ship built from blocks with the assembler;
// and a plane halfway through a turn.
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/vehicleshots"
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
func world(_ tile: Int = 22) -> Game {
    let g = Game(mode: .creative, infinite: true, seed: 4242, settings: Settings())
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false; g.pauseSpawning = true; g.godMode = true
    g.settings.weatherOn = false
    g.tilePx = tile
    g.timeOfDay = 0.3
    let x0 = Int(g.pb.x) - 70
    g.world.loadAround(centerX: Int(g.pb.x), radius: 8)
    for x in x0...(x0 + 140) {
        for y in 20..<100 { g.world.set(x, y, .air); g.world.setWall(x, y, 0) }
        g.world.set(x, 100, .grass)
        for y in 101..<106 { g.world.set(x, y, .dirt) }
    }
    return g
}
func kit(_ g: Game, _ k: Gadget, _ left: Double, _ bottom: Double) -> Vehicle {
    let v = Vehicle(id: g.newID(), first: .frame, x: 0, y: 0)
    v.parts.removeAll()
    for p in kitLayout(k) { v.parts[PartCell(dx: p.dx, dy: p.dy)] = p.p }
    v.recompute(keepAnchor: false)
    v.placeBox(left: left, bottom: bottom)
    v.fuel = v.fuelCapacity
    g.vehicles.append(v)
    return v
}
func settle(_ g: Game, _ n: Int = 3) { for _ in 0..<n { g.tick(1.0 / 60.0) } }

// 1: every new kit parked on a field
do {
    let g = world(20)
    let x = Double(Int(g.pb.x) - 24)
    _ = kit(g, .planeKit, x, 100)
    _ = kit(g, .heliKit, x + 10, 100)
    _ = kit(g, .tankKit, x + 18, 100)
    _ = kit(g, .truckKit, x + 26, 100)
    _ = kit(g, .airshipKit, x + 35, 100)
    g.pb.x = x - 3; g.pb.y = 100
    for _ in 0..<30 { g.tick(1.0 / 60.0) }
    g.camX = x + 21; g.camY = 93
    render(g, "01_fleet")
}

// 2: in the air: a plane with its propeller turning, a hovering helicopter, an airship with its burners lit
do {
    let g = world(20)
    let x = Double(Int(g.pb.x) - 22)
    let p = kit(g, .planeKit, x, 88)
    let h = kit(g, .heliKit, x + 13, 84)
    let a = kit(g, .airshipKit, x + 25, 92)
    g.pauseVehicles = true
    p.throttle = 1; p.rider = true; p.propRot = 0.4; p.angle = -0.08; p.updateBox()
    h.collective = 0.8; h.propRot = 0.9; h.angle = 0.12; h.updateBox()
    a.heat = 0.7; a.throttle = 0.6
    g.pb.x = x - 6; g.pb.y = 100
    settle(g)
    g.camX = x + 18; g.camY = 88
    render(g, "02_flying")
}

// 3: a tank firing at a wrecked truck: the shell in flight, cracks in the damaged truck, a part broken off
do {
    let g = world(22)
    let x = Double(Int(g.pb.x) - 20)
    let t = kit(g, .tankKit, x, 100)
    let tr = kit(g, .truckKit, x + 22, 100)
    settle(g, 20)
    for (c, _) in tr.parts { tr.dmg[c] = vehicleCellHP(tr, c, tr.parts[c]!) * 0.6 }
    g.damageVehicle(tr, PartCell(dx: 2, dy: 0), 200, tr.cellCenter(PartCell(dx: 2, dy: 0)).0, tr.cellCenter(PartCell(dx: 2, dy: 0)).1)
    g.inVehicle = t; t.rider = true
    g.aimX = tr.b.x; g.aimY = tr.b.y - 3; g.aimValid = true
    g.useHeld = true
    for _ in 0..<40 { g.aimX = tr.b.x; g.aimY = tr.b.y - 3; g.aimValid = true; g.useHeld = true; g.tick(1.0 / 60.0) }
    g.useHeld = false
    g.shake = 0
    g.camX = x + 14; g.camY = 95
    render(g, "03_battle")
}

// 4: a ship built from blocks in the world and turned into one vehicle with the assembler, a balloon on
// top; and a car with a stone block and a torch built onto it
do {
    let g = world(18)
    let x0 = Int(g.pb.x) - 16
    func b(_ x: Int, _ y: Int, _ t: Tile) { g.world.set(x, y, t); g.world.setBuilt(x, y, true) }
    for x in x0...(x0 + 14) { b(x, 97, .planks) }
    for x in (x0 + 1)...(x0 + 13) { b(x, 98, .logBlock) }
    for x in (x0 + 3)...(x0 + 11) { b(x, 99, .planks) }
    b(x0, 96, .planks); b(x0 + 14, 96, .planks); b(x0 + 14, 95, .planks)
    b(x0 + 4, 96, .chest); b(x0 + 6, 96, .glass); b(x0 + 7, 96, .glass); b(x0 + 9, 96, .lantern); b(x0 + 11, 96, .bookshelf)
    g.inv.slots[0] = Stack(item: .gadget(.assembler), count: 1)
    g.setSel(0)
    g.pb.x = Double(x0) + 3.5; g.pb.y = 100
    g.aimX = Double(x0 + 4) + 0.5; g.aimY = 98.5; g.aimValid = true
    g.useCD = 0
    g.useAssembler(true)
    if let v = g.vehicles.last {
        // on the deck: a cockpit, burners and an engine; a balloon above; a propeller at the stern
        let deck: Int = v.minY + 1
        v.parts[PartCell(dx: 2, dy: deck - 1)] = .cockpit
        for dx in 5...9 { v.parts[PartCell(dx: dx, dy: deck - 2)] = .burner }
        v.parts[PartCell(dx: 12, dy: deck - 1)] = .engine
        for dy in 3...5 { for dx in 1...13 { v.parts[PartCell(dx: dx, dy: deck - dy)] = .envelope } }
        v.parts[PartCell(dx: -1, dy: deck)] = .airProp
        v.recompute(keepAnchor: true)
        v.heat = 0.6
        print("assembled ship:", v.parts.count, "cells, mass", v.mass, "kind", g.vehicleKindName(v))
    }
    let car = kit(g, .carKit, Double(x0 + 22), 100)
    car.parts[PartCell(dx: 1, dy: -1)] = .block
    car.blocks[PartCell(dx: 1, dy: -1)] = .stone
    car.parts[PartCell(dx: 2, dy: -1)] = .block
    car.blocks[PartCell(dx: 2, dy: -1)] = .torch
    car.recompute(keepAnchor: true)
    settle(g, 10)
    g.camX = Double(x0 + 14); g.camY = 92
    render(g, "04_built")
}

// 5: a plane halfway through a turn (drawn on its edge)
do {
    let g = world(26)
    let x = Double(Int(g.pb.x) - 4)
    let p = kit(g, .planeKit, x, 90)
    g.pauseVehicles = true
    p.throttle = 1; p.rider = true; p.propRot = 0.4
    p.turnT = 0.38
    g.pb.x = x - 8; g.pb.y = 100
    settle(g)
    g.camX = x + 4; g.camY = 90
    render(g, "05_turning")
}
