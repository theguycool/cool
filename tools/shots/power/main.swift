import SwiftUI
import Foundation
// Headless screenshots of Sparkworks bases
let W = 1100, H = 700
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/pwshots"
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
func steps(_ g: Game, _ n: Int) { for _ in 0..<n { g.tick(1.0 / 60.0) } }
@discardableResult
func put(_ g: Game, _ x: Int, _ y: Int, _ t: Tile, dir: Int = 0) -> PowerDev? {
    g.world.set(x, y, t); let d = g.world.powerDev(x, y); d?.dir = dir; return d
}
func wire(_ g: Game, _ layer: Int, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
    var x = x0, y = y0
    while true {
        g.world.setWire(x, y, g.world.wireAt(x, y) | Wire.bit(layer))
        if x == x1 && y == y1 { break }
        if x != x1 { x += x1 > x ? 1 : -1 } else { y += y1 > y ? 1 : -1 }
    }
}
let g = Game(mode: .creative, infinite: true, seed: 4242, settings: Settings(), options: .standard)
g.viewW = Double(W); g.viewH = Double(H)
g.monstersEnabled = false; g.pauseSpawning = true; g.godMode = true
g.settings.weatherOn = false
g.tilePx = 30
let w = g.world
let cx = Int(g.pb.x)
w.loadAround(centerX: cx, radius: 6)
for x in (cx - 40)...(cx + 40) {
    for y in 60..<100 { w.set(x, y, .air) }
    for y in 100..<106 { w.set(x, y, .stone) }
    w.set(x, 100, .grass)
}
// a little house: brick walls, plank roof with solar panels on it
for y in 92...99 { w.set(cx - 14, y, .brick) }
for y in 92...96 { w.set(cx + 2, y, .brick) }
for x in (cx - 14)...(cx + 2) { w.set(x, 91, .planks) }
for k in 0..<4 { put(g, cx - 12 + k * 3, 90, .solarPanel) }
wire(g, 0, cx - 12, 90, cx - 3, 90); wire(g, 0, cx - 12, 90, cx - 12, 92)
// battery bank and a meter inside
put(g, cx - 12, 99, .battery)!.charge = 520
put(g, cx - 11, 99, .battery)!.charge = 310
put(g, cx - 10, 99, .accumulator)!.charge = 3600
put(g, cx - 12, 97, .powerMeter)
put(g, cx - 12, 95, .breaker)
wire(g, 0, cx - 12, 92, cx - 12, 99); wire(g, 0, cx - 12, 99, cx - 10, 99)
// lamps along the ceiling, on a lever
for k in 0..<5 { put(g, cx - 9 + k * 2, 92, .lampOff) }
wire(g, 0, cx - 12, 93, cx - 1, 93)
for k in 0..<5 { wire(g, 0, cx - 9 + k * 2, 92, cx - 9 + k * 2, 93) }
let lv = put(g, cx - 7, 97, .lever)!
wire(g, 1, cx - 7, 97, cx - 7, 94); wire(g, 1, cx - 7, 94, cx - 1, 94)
for k in 0..<5 { wire(g, 1, cx - 9 + k * 2, 92, cx - 9 + k * 2, 94) }
// the door: a steel gate that opens for the player (proximity sensor)
put(g, cx + 2, 98, .gateClosed); put(g, cx + 2, 99, .gateClosed); put(g, cx + 2, 97, .gateClosed)
let px = put(g, cx + 5, 97, .proximitySensor)!
px.param = 3
wire(g, 0, cx - 1, 93, cx + 1, 93); wire(g, 0, cx + 1, 93, cx + 1, 97); wire(g, 0, cx + 1, 97, cx + 5, 97)
wire(g, 0, cx + 2, 97, cx + 2, 99)
wire(g, 2, cx + 5, 97, cx + 5, 96); wire(g, 2, cx + 5, 96, cx + 2, 96); wire(g, 2, cx + 2, 96, cx + 2, 99)
// outside: logic test bench and a machine line
let a = put(g, cx + 9, 93, .lever)!
let b = put(g, cx + 9, 97, .lever)!
put(g, cx + 9, 95, .logicGate, dir: 0)!.mode = 0
wire(g, 1, cx + 9, 93, cx + 9, 94); wire(g, 1, cx + 9, 96, cx + 9, 97)
wire(g, 1, cx + 10, 95, cx + 12, 95)
put(g, cx + 12, 95, .signalLight)
put(g, cx + 14, 95, .inverter, dir: 0)
wire(g, 1, cx + 12, 95, cx + 13, 95)
wire(g, 1, cx + 15, 95, cx + 16, 95)
put(g, cx + 16, 95, .signalLight)
put(g, cx + 12, 92, .pulseTimer, dir: 0)!.param = 0.8
wire(g, 1, cx + 13, 92, cx + 16, 92)
put(g, cx + 16, 91, .signalLight); wire(g, 1, cx + 16, 92, cx + 16, 91)
// machine line on the ground: drill into dirt, conveyor, collector, chest
for y in 95...99 { w.set(cx + 24, y, .dirt) }
put(g, cx + 23, 98, .autoDrill, dir: 0)
for i in 0..<4 { put(g, cx + 18 + i, 99, .conveyor, dir: 0) }
put(g, cx + 22, 99, .collector)
w.set(cx + 22, 98, .chest); w.setChestItems(cx + 22, 98, [])
put(g, cx + 18, 100, .arcTrap)
put(g, cx + 26, 99, .crankGen)!.charge = 40
put(g, cx + 28, 99, .fuelGen)!.charge = 300
put(g, cx + 30, 99, .battery)!.charge = 100
wire(g, 0, cx + 5, 97, cx + 5, 98); wire(g, 0, cx + 5, 98, cx + 23, 98); wire(g, 0, cx + 18, 98, cx + 18, 100)
wire(g, 0, cx + 18, 99, cx + 22, 99)
wire(g, 0, cx + 26, 99, cx + 30, 99); wire(g, 0, cx + 26, 99, cx + 26, 98); wire(g, 0, cx + 24, 98, cx + 26, 98)
g.pb.x = Double(cx - 4) + 0.5; g.pb.y = 100
g.camX = Double(cx + 6); g.camY = 94; g.camTX = g.camX; g.camTY = g.camY
g.usePowerDevice(cx - 7, 97, .lever)
g.usePowerDevice(cx + 9, 93, .lever)
g.timeOfDay = 0.3
// hold the probe so the wiring shows
g.inv.slots[0] = Stack(item: .gadget(.probe), count: 1); g.sel = 0
steps(g, 90)
g.camX = Double(cx + 6); g.camY = 94
render(g, "base_day")
g.timeOfDay = 0.75
g.light.valid = false
g.usePowerDevice(cx + 9, 97, .lever)
steps(g, 60)
g.camX = Double(cx + 6); g.camY = 94
render(g, "base_night")
g.probeAt(Double(cx - 5) + 0.5, 93.5)
steps(g, 10)
g.camX = Double(cx + 6); g.camY = 94
render(g, "probe")
// with the wiring hidden (nothing in hand, default setting)
g.inv.slots[0] = nil
g.inspect = nil
steps(g, 5)
g.camX = Double(cx + 6); g.camY = 94
render(g, "plain_night")
print(a.on, b.on, lv.on)
