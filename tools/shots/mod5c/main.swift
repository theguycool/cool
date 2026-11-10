import SwiftUI
import Foundation
// Headless screenshots of step 5c: more of the game in mods. A vehicle kept in a mod, built from its
// kit (with a mod block working as its wing); mod blocks on a power line (a generator lighting powered
// lamps, a solar block) and a block that falls like sand; the Overworld's rain in a mod's colour; a
// custom dimension in a blizzard. The Mod Creator's new pages are SwiftUI and are not drawn here.
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/mod5cshots"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
ModStore.overrideDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("prmod5cshots-" + String(Int.random(in: 1000...999999)), isDirectory: true)

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
    g.updateLight(1.0 / 60.0)
}
func art(_ c: UInt32, _ edge: UInt32) -> ModPixels {
    var px = ModPixels(w: 8, h: 8)
    for y in 0..<8 { for x in 0..<8 { px.setARGB(x, y, (x == 0 || y == 0 || x == 7 || y == 7) ? 0xFF000000 | edge : 0xFF000000 | c) } }
    return px
}
func lampArt(_ lit: Bool) -> ModPixels {
    var px = ModPixels(w: 8, h: 8)
    for y in 1..<7 { for x in 2..<6 { px.setARGB(x, y, lit ? 0xFFFFE070 : 0xFF5A5040) } }
    for x in 1..<7 { px.setARGB(x, 7, 0xFF3A3A3A) }
    return px
}
func theMod() -> ModPack {
    var p = ModPack(); p.id = "shop"; p.name = "Workshop"
    var wing = ModBlock(); wing.id = "skywing"; wing.name = "Sky Wing"; wing.art = art(0x60C8F0, 0x205080); wing.vehRole = .wing; wing.vehPower = 1.5
    var dyn = ModBlock(); dyn.id = "dynamo"; dyn.name = "Dynamo"; dyn.art = art(0xC07030, 0x5A3010); dyn.powerRole = .generator; dyn.powerAmt = 8
    var sol = ModBlock(); sol.id = "panel"; sol.name = "Sun Panel"; sol.art = art(0x3050A0, 0xC0C8D8); sol.powerRole = .solar; sol.powerAmt = 6
    var lamp = ModBlock(); lamp.id = "glow"; lamp.name = "Glow Lamp"; lamp.art = lampArt(true); lamp.function = .lamp; lamp.powerRole = .lamp; lamp.powerAmt = 1; lamp.collision = .none; lamp.light = 14
    var grav = ModBlock(); grav.id = "gravel"; grav.name = "Gravel"; grav.art = art(0x8A8478, 0x5A5650); grav.falls = true
    p.blocks = [wing, dyn, sol, lamp, grav]
    var v = ModVehicle(); v.id = "skiff"; v.name = "Sky Skiff"
    v.cells = [ModVehicleCell(5, 0, .cockpit), ModVehicleCell(0, 0, .elevator),
               ModVehicleCell(0, 1, .frame), ModVehicleCell(1, 1, .frame), ModVehicleCell(2, 1, .frame, "shop:skywing"), ModVehicleCell(3, 1, .frame, "shop:skywing"),
               ModVehicleCell(4, 1, .frame, "shop:skywing"), ModVehicleCell(5, 1, .fuelTank), ModVehicleCell(6, 1, .engine), ModVehicleCell(7, 1, .airProp),
               ModVehicleCell(3, 2, .wheel), ModVehicleCell(6, 2, .wheel), ModVehicleCell(1, 0, .frame, "tile:" + String(Tile.brick.rawValue))]
    p.vehicles = [v]
    var w = ModWeather(); w.rain = 2; w.rainColor = 0x60F070
    p.weather = w
    p.rules = ["nights": 1.6]
    return p
}

func world(_ mods: [ModPack], _ tile: Int) -> Game {
    ModRuntime.activate(mods, world: nil)
    let g = Game(mode: .creative, infinite: true, seed: 5252, settings: Settings(), options: .standard)
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

// 1: a vehicle kept in a mod, built from its kit
do {
    let g = world([theMod()], 32)
    g.inv.slots[0] = Stack(item: .custom("shop:skiff"), count: 1)
    g.sel = 0
    g.aimX = g.pb.x + 6; g.aimY = 99.5; g.aimValid = true
    g.useModItem("shop:skiff", 1.0 / 60.0, true)
    for _ in 0..<30 { g.tick(1.0 / 60.0) }
    look(g, g.pb.x + 5, 96)
    render(g, "01_mod_vehicle")
}

// 2: mod blocks on a power line, at dusk
do {
    let g = world([theMod()], 34)
    let rt = ModRuntime.shared
    let y: Int = 99
    let x0: Int = Int(g.pb.x) - 8
    if let dyn = rt.tileForKey["shop:dynamo"], let lamp = rt.tileForKey["shop:glow"], let panel = rt.tileForKey["shop:panel"], let grav = rt.tileForKey["shop:gravel"] {
        g.world.set(x0, y, dyn)
        for k in 0..<3 {
            g.world.set(x0 + 4 + k * 3, y, lamp)
            g.world.set(x0 + 4 + k * 3, y - 3, lamp)
        }
        for x in x0...(x0 + 10) { _ = g.world.setWire(x, y, g.world.wireAt(x, y) | Wire.power) }
        for yy in (y - 3)...y { _ = g.world.setWire(x0 + 4, yy, g.world.wireAt(x0 + 4, yy) | Wire.power) }
        for k in 0..<3 { _ = g.world.setWire(x0 + 4 + k, y - 3, g.world.wireAt(x0 + 4 + k, y - 3) | Wire.power) }
        g.world.set(x0 + 15, y, panel)
        // a column of gravel with its support knocked out: falling
        for k in 0..<4 { g.world.set(x0 + 19, y - 4 - k, grav) }
        g.world.set(x0 + 19, y - 3, .stone)
        g.breakTile(x0 + 19, y - 3, true)
        g.timeOfDay = 0.55
        g.settings.showWires = 1
        for _ in 0..<50 {
            g.clock += 0.1
            g.updatePower(0.1)
        }
        for _ in 0..<12 { g.tick(1.0 / 60.0) }
    }
    look(g, Double(x0) + 10, 95)
    render(g, "02_power_blocks")
}

// 3: the Overworld's rain in a mod's colour
do {
    let g = world([theMod()], 30)
    g.settings.weatherOn = true
    g.debugForceWeather(.heavyRain)
    for _ in 0..<240 { g.tick(1.0 / 60.0) }
    look(g, g.pb.x, 95)
    render(g, "03_mod_rain")
}

// 4: a custom dimension with blizzards
do {
    var p = ModPack(); p.id = "frost"; p.name = "Frost"
    var d = ModDimension(); d.id = "tundra"; d.name = "Tundra"
    d.weather = 8
    p.dims = [d]
    let g = world([p], 30)
    if let r = ModRuntime.shared.dimRT(.custom0) {
        g.settings.weatherOn = true
        g.enterCustomDim(r)
        g.fadeT = 0
        for _ in 0..<240 { g.tick(1.0 / 60.0) }
        look(g, g.pb.x, g.pb.y - 3)
    }
    render(g, "04_dimension_blizzard")
}
