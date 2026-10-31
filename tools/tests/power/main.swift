import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) { var t = 0.0; while t < secs { g.tick(dt); t += dt } }

/// open ground: air above row 100, stone below; noon, no weather, no monsters
func arena(_ opts: WorldOptions = .standard) -> (Game, Int) {
    let g = Game(mode: .survival, infinite: true, seed: 4242, settings: Settings(), options: opts)
    g.viewW = 1100; g.viewH = 800
    g.settings.weatherOn = false
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.godMode = true
    g.mobs.removeAll()
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 6)
    for x in x0...(x0 + 80) {
        for y in 40..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.timeOfDay = 0.25
    g.camX = g.pb.x; g.camY = g.pb.y - 2
    return (g, x0 + 40)
}
@discardableResult
func put(_ g: Game, _ x: Int, _ y: Int, _ t: Tile, dir: Int = 0) -> PowerDev? {
    g.world.set(x, y, t)
    let d = g.world.powerDev(x, y)
    d?.dir = dir
    return d
}
/// a straight run of wire on one layer (0 power, 1 amber, 2 teal)
func wire(_ g: Game, _ layer: Int, _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
    var x = x0, y = y0
    while true {
        g.world.setWire(x, y, g.world.wireAt(x, y) | Wire.bit(layer))
        if x == x1 && y == y1 { break }
        if x != x1 { x += x1 > x ? 1 : -1 } else { y += y1 > y ? 1 : -1 }
    }
}
func cut(_ g: Game, _ x: Int, _ y: Int) { g.world.setWire(x, y, 0) }
func tile(_ g: Game, _ x: Int, _ y: Int) -> Tile { return g.world.tile(x, y) }

// ---------------------------------------------------------------- A. power: make, move, store, switch
print("== power")
do {
    let (g, px) = arena()
    let cr = put(g, px + 2, 99, .crankGen)!
    put(g, px + 6, 99, .lampOff)
    wire(g, 0, px + 2, 99, px + 6, 99)
    step(g, 1)
    check(tile(g, px + 6, 99) == .lampOff, "a lamp on a crank generator that hasn't been wound stays dark")
    g.usePowerDevice(px + 2, 99, .crankGen)
    step(g, 0.6)
    check(tile(g, px + 6, 99) == .lampOn, "wind the crank: the lamp on its cable lights (charge \(Int(cr.charge)))")
    check(g.world.tile(px + 6, 99).light >= 14, "the lit lamp gives real light")
    // 15 sparks at 1 spark a second: dark again well within 20 s
    step(g, 20)
    check(tile(g, px + 6, 99) == .lampOff && cr.charge < 1, "when the flywheel runs down, the lamp goes out (no free energy)")
}
do {
    // a battery stores the sun's power and gives it back at night
    let (g, px) = arena()
    put(g, px + 1, 99, .solarPanel)
    let bat = put(g, px + 3, 99, .battery)!
    wire(g, 0, px + 1, 99, px + 3, 99)
    step(g, 20)
    let charged = bat.charge
    check(charged > 50, "a solar panel at noon charges a battery (\(Int(charged)) sparks in 20 s)")
    put(g, px + 5, 99, .lampOff)
    wire(g, 0, px + 3, 99, px + 5, 99)
    g.timeOfDay = 0.75
    step(g, 2)
    check(tile(g, px + 5, 99) == .lampOn, "at night the battery keeps the lamp lit")
    let before = bat.charge
    step(g, 10)
    check(bat.charge < before - 5, "...and runs down while it does (\(Int(before)) -> \(Int(bat.charge)))")
    bat.charge = 0
    step(g, 1)
    check(tile(g, px + 5, 99) == .lampOff, "an empty battery at night: the lamp goes dark")
    let net = g.power.pnets[bat.pnet]
    check(net.short, "the line reports not enough power")
}
do {
    // a power switch and cutting cable
    let (g, px) = arena()
    let cr = put(g, px, 99, .crankGen)!
    cr.charge = 60
    let sw = put(g, px + 3, 99, .powerSwitch)!
    put(g, px + 6, 99, .lampOff)
    wire(g, 0, px, 99, px + 6, 99)
    step(g, 0.6)
    check(tile(g, px + 6, 99) == .lampOn, "power passes a switch that is on")
    g.usePowerDevice(px + 3, 99, .powerSwitch)
    step(g, 0.6)
    check(!sw.on && tile(g, px + 6, 99) == .lampOff, "turn the switch off: the lamp goes out")
    g.usePowerDevice(px + 3, 99, .powerSwitch)
    step(g, 0.6)
    check(tile(g, px + 6, 99) == .lampOn, "and on again")
    cut(g, px + 5, 99)
    step(g, 0.6)
    check(tile(g, px + 6, 99) == .lampOff, "cut the cable: the lamp loses power at once (no phantom power)")
    wire(g, 0, px + 5, 99, px + 5, 99)
    step(g, 0.6)
    check(tile(g, px + 6, 99) == .lampOn, "mend it: power returns")
    g.world.set(px, 99, .air)
    step(g, 0.6)
    check(tile(g, px + 6, 99) == .lampOff && g.world.powerDev(px, 99) == nil, "take the generator down: its entry goes and the lamp goes dark")
}
do {
    // a breaker trips when too much is asked of its line
    let (g, px) = arena()
    let bat = put(g, px, 99, .accumulator)!
    bat.charge = 5000
    let br = put(g, px + 2, 99, .breaker)!
    br.mode = 0   // trips above 10 sparks/s
    wire(g, 0, px, 99, px + 30, 99)
    for i in 0..<8 { put(g, px + 4 + i, 98, .lampOff); wire(g, 0, px + 4 + i, 98, px + 4 + i, 99) }
    step(g, 1)
    check(br.on && tile(g, px + 4, 98) == .lampOn, "eight lamps (8 sparks/s) under a 10 spark breaker: all lit")
    for i in 0..<4 { put(g, px + 14 + i, 98, .lampOff); wire(g, 0, px + 14 + i, 98, px + 14 + i, 99) }
    step(g, 1)
    check(!br.on && br.flag && tile(g, px + 4, 98) == .lampOff, "twelve lamps: the breaker trips and the line goes dead")
    for i in 0..<4 { g.world.set(px + 14 + i, 98, .air) }
    g.usePowerDevice(px + 2, 99, .breaker)
    step(g, 1)
    check(br.on && tile(g, px + 4, 98) == .lampOn, "remove the extra load and reset the breaker: back on")
}
do {
    // fuel only burns for what is needed
    let (g, px) = arena()
    let fg = put(g, px, 99, .fuelGen)!
    fg.charge = 100
    wire(g, 0, px, 99, px + 4, 99)
    step(g, 5)
    check(abs(fg.charge - 100) < 0.01, "a fuel generator with nothing to power burns no fuel")
    put(g, px + 4, 99, .lampOff)
    step(g, 5)
    check(fg.charge < 100 && fg.charge > 99, "with one lamp it burns just a little (100 -> \(String(format: "%.2f", fg.charge)) s)")
    check(tile(g, px + 4, 99) == .lampOn, "...and the lamp is lit")
    // feeding it from the bag
    g.inv.slots[0] = Stack(item: .mat(.coal), count: 3)
    g.sel = 0
    g.usePowerDevice(px, 99, .fuelGen)
    check(fg.charge > 150 && g.inv.slots[0]?.count == 2, "tapping it with coal adds a minute of fuel and takes one coal")
}
do {
    // the wind turbine feeds the line from its own charge
    let (g, px) = arena()
    put(g, px, 99, .windTurbine)
    let k = g.deviceKey(DeviceSpot(x: px, y: 99, t: .windTurbine))
    g.weather.store[k] = 40
    put(g, px + 3, 99, .lampOff)
    wire(g, 0, px, 99, px + 3, 99)
    step(g, 2)
    let left = g.weather.store[k] ?? 0
    check(tile(g, px + 3, 99) == .lampOn && left < 40 && left > 35, "a wind turbine's stored charge runs a lamp, a spark a second (40 -> \(f1(left)))")
}
do {
    // water wheel
    let (g, px) = arena()
    let ww = put(g, px, 98, .waterWheel)!
    for dy in -1...1 { g.world.set(px + 1, 98 + dy, .water); g.world.set(px - 1, 98 + dy, .water) }
    put(g, px + 3, 99, .lampOff)
    wire(g, 0, px, 98, px + 3, 98); wire(g, 0, px + 3, 98, px + 3, 99)
    step(g, 1)
    check(ww.made > 3 && tile(g, px + 3, 99) == .lampOn, "a water wheel among water makes power (\(f1(ww.made)) sparks/s)")
}

// ---------------------------------------------------------------- B. pulses and logic
print("== pulses and logic")
do {
    // a lever on an amber pulse wire controls a powered lamp
    let (g, px) = arena()
    let bat = put(g, px, 99, .battery)!
    bat.charge = 600
    put(g, px + 5, 99, .lampOff)
    wire(g, 0, px, 99, px + 5, 99)
    put(g, px + 5, 97, .lever)
    wire(g, 1, px + 5, 97, px + 5, 99)
    step(g, 0.6)
    check(tile(g, px + 5, 99) == .lampOff, "a lamp with a pulse wire stays off while the pulse is off")
    g.usePowerDevice(px + 5, 97, .lever)
    step(g, 0.3)
    check(tile(g, px + 5, 99) == .lampOn, "pull the lever: the lamp lights")
    g.usePowerDevice(px + 5, 97, .lever)
    step(g, 0.3)
    check(tile(g, px + 5, 99) == .lampOff, "push it back: dark again")
}
do {
    // every gate type, every input combination
    let names = ["AND", "OR", "XOR", "NAND", "NOR"]
    let truth: [[Bool]] = [[false, false, false, true], [false, true, true, true], [false, true, true, false], [true, true, true, false], [true, false, false, false]]
    var allOK = true
    var report = ""
    for m in 0..<5 {
        let (g, px) = arena()
        // gate facing right at (px, 95): inputs above (up side) and below (down side)
        let gate = put(g, px, 95, .logicGate, dir: 0)!
        gate.mode = m
        let a = put(g, px, 92, .lever)!
        let b = put(g, px, 98, .lever)!
        wire(g, 1, px, 92, px, 94)
        wire(g, 1, px, 96, px, 98)
        let light = put(g, px + 3, 95, .signalLight)!
        wire(g, 1, px + 1, 95, px + 3, 95)
        step(g, 0.3)
        var row: [Bool] = []
        for combo in 0..<4 {
            let wa = combo & 1 != 0, wb = combo & 2 != 0
            if a.on != wa { g.usePowerDevice(px, 92, .lever) }
            if b.on != wb { g.usePowerDevice(px, 98, .lever) }
            step(g, 0.25)
            row.append(g.pulseHere(light) ?? false)
        }
        let want = [truth[m][0], truth[m][1], truth[m][1], truth[m][2]]
        // combos in order: 00, 10, 01, 11 -> truth index 0, 1, 1, 2 (symmetric gates); NAND/NOR from their own row
        let expect: [Bool]
        switch m {
        case 0: expect = [false, false, false, true]
        case 1: expect = [false, true, true, true]
        case 2: expect = [false, true, true, false]
        case 3: expect = [true, true, true, false]
        default: expect = [true, false, false, false]
        }
        _ = want
        if row != expect { allOK = false }
        report += "\(names[m]) \(row.map { $0 ? 1 : 0 }) "
    }
    check(allOK, "AND, OR, XOR, NAND and NOR give the right output for every input pair (\(report))")
}
do {
    // inverter, relay delay, a loop that can't hang
    let (g, px) = arena()
    let lv = put(g, px, 95, .lever)!
    put(g, px + 2, 95, .inverter, dir: 0)
    wire(g, 1, px, 95, px + 1, 95)
    let sl = put(g, px + 4, 95, .signalLight)!
    wire(g, 1, px + 3, 95, px + 4, 95)
    step(g, 0.3)
    check(g.pulseHere(sl) == true, "an inverter sends ON while its input is off")
    g.usePowerDevice(px, 95, .lever)
    step(g, 0.3)
    check(g.pulseHere(sl) == false && lv.on, "...and off once its input is on")
    // relay with a 4-step delay
    let (g2, p2) = arena()
    let b = put(g2, p2, 95, .pushButton)!
    let rel = put(g2, p2 + 2, 95, .repeater, dir: 0)!
    rel.param = 4
    wire(g2, 1, p2, 95, p2 + 1, 95)
    let sl2 = put(g2, p2 + 4, 95, .signalLight)!
    wire(g2, 1, p2 + 3, 95, p2 + 4, 95)
    step(g2, 0.3)
    g2.usePowerDevice(p2, 95, .pushButton)
    var tOn = -1.0
    var t = 0.0
    while t < 1.0 { g2.tick(1.0 / 60.0); t += 1.0 / 60.0; if tOn < 0 && (g2.pulseHere(sl2) ?? false) { tOn = t } }
    _ = b
    check(tOn > 0.15 && tOn < 0.45, "a pulse relay set to 4 steps passes a button press on about 0.2 s later (\(f1(tOn * 1000)) ms)")
    // a loop: an inverter whose output runs back to its own input
    let (g3, p3) = arena()
    let inv = put(g3, p3, 95, .inverter, dir: 0)!
    wire(g3, 1, p3 + 1, 95, p3 + 1, 93)
    wire(g3, 1, p3 + 1, 93, p3 - 1, 93)
    wire(g3, 1, p3 - 1, 93, p3 - 1, 95)
    let t0 = Date()
    step(g3, 3)
    let ms = Date().timeIntervalSince(t0) * 1000.0 / 180.0
    check(inv.burnT > 0 || inv.flips <= 25, "an inverter wired into a loop doesn't hang the game: it flips, then burns out for a moment (burn \(f1(inv.burnT)) s)")
    check(ms < 20, "...and frames stay quick while it does (\(f1(ms)) ms a frame, debug build)")
}
do {
    // a clock timer blinks a lamp
    let (g, px) = arena()
    let bat = put(g, px, 99, .battery)!
    bat.charge = 600
    put(g, px + 4, 99, .lampOff)
    wire(g, 0, px, 99, px + 4, 99)
    let tm = put(g, px + 2, 96, .pulseTimer, dir: 0)!
    tm.param = 1.0
    wire(g, 1, px + 3, 96, px + 4, 96)
    wire(g, 1, px + 4, 96, px + 4, 99)
    var flips = 0
    var last = tile(g, px + 4, 99)
    var t = 0.0
    while t < 4.0 { g.tick(1.0 / 60.0); t += 1.0 / 60.0; let now = tile(g, px + 4, 99); if now != last { flips += 1; last = now } }
    check(flips >= 6 && flips <= 9, "a 1 s clock timer blinks a lamp on and off (\(flips) changes in 4 s)")
}

// ---------------------------------------------------------------- C. sensors and smart doors
print("== sensors")
do {
    // a gate that opens for the player and stays shut for monsters
    let (g, px) = arena()
    let bat = put(g, px + 10, 99, .battery)!
    bat.charge = 600
    let prox = put(g, px + 8, 97, .proximitySensor)!
    prox.mode = 0
    prox.param = 4
    put(g, px + 10, 98, .gateClosed)
    put(g, px + 10, 97, .gateClosed)
    wire(g, 0, px + 8, 97, px + 10, 97); wire(g, 0, px + 10, 97, px + 10, 99)
    wire(g, 1, px + 8, 97, px + 10, 97); wire(g, 1, px + 10, 97, px + 10, 98)
    g.pb.x = Double(px - 10)
    step(g, 1)
    check(tile(g, px + 10, 98) == .gateClosed, "a proximity-sensor gate is shut while nobody is near")
    let z = g.addMob(.zombie, Double(px + 7) + 0.5, 100)
    g.pauseMobs = true
    step(g, 1)
    check(tile(g, px + 10, 98) == .gateClosed, "a zombie next to it: the gate stays shut (sensor set to the player)")
    z.removed = true
    g.pb.x = Double(px + 8) + 0.5
    step(g, 1)
    let gd = g.world.powerDev(px + 10, 98)!
    check(tile(g, px + 10, 98) == .gateOpen && tile(g, px + 10, 97) == .gateOpen, "the player walks up: the gate opens")
    g.pb.x = Double(px - 10)
    step(g, 1.5)
    check(tile(g, px + 10, 98) == .gateClosed, "the player walks away: it shuts again")
    bat.charge = 0
    g.pb.x = Double(px + 8) + 0.5
    step(g, 1.5)
    check(tile(g, px + 10, 98) == .gateClosed, "with no power the sensor is blind and the gate can't move")
}
do {
    // daylight sensor, weather sensor driving storm shutters, a lever opening a wooden door, a siren
    let (g, px) = arena()
    let bat = put(g, px, 99, .battery)!
    bat.charge = 600
    let ds = put(g, px + 2, 99, .daySensor)!
    let ws = put(g, px + 6, 99, .weatherSensor)!
    ws.mode = 0
    wire(g, 0, px, 99, px + 6, 99)
    let s1 = put(g, px + 2, 96, .signalLight)!
    wire(g, 1, px + 2, 96, px + 2, 99)
    g.world.set(px + 6, 96, .shutterOpen)
    wire(g, 2, px + 6, 96, px + 6, 99)
    step(g, 1.5)
    check(ds.out && (g.pulseHere(s1) ?? false), "a daylight sensor is on at noon")
    g.timeOfDay = 0.75
    step(g, 1.5)
    check(!ds.out, "...and off at night")
    check(tile(g, px + 6, 96) == .shutterOpen, "a weather sensor in clear weather leaves its shutter open")
    g.settings.weatherOn = true
    g.debugForceWeather(.heavyRain)
    g.weather.precip = 0.9
    g.weather.cover = 1.0
    step(g, 2)
    check(ws.out && tile(g, px + 6, 96) == .shutterClosed, "rain: the weather sensor closes the storm shutter by itself")
    // lever and wooden door
    let (g2, p2) = arena()
    g2.world.set(p2 + 4, 99, .doorClosed); g2.world.set(p2 + 4, 98, .doorClosed)
    put(g2, p2, 98, .lever)
    wire(g2, 2, p2, 98, p2 + 4, 98)
    step(g2, 0.3)
    g2.usePowerDevice(p2, 98, .lever)
    step(g2, 0.3)
    check(tile(g2, p2 + 4, 99) == .doorOpen && tile(g2, p2 + 4, 98) == .doorOpen, "a lever on a pulse wire opens a wooden door (no power needed)")
    g2.usePowerDevice(p2, 98, .lever)
    step(g2, 0.3)
    check(tile(g2, p2 + 4, 99) == .doorClosed, "...and closes it")
    // a siren on a pulse wire
    g2.world.set(p2 + 8, 99, .stormSiren)
    let lv2 = put(g2, p2 + 10, 98, .lever)!
    wire(g2, 1, p2 + 8, 98, p2 + 10, 98); wire(g2, 1, p2 + 8, 98, p2 + 8, 99)
    g2.pb.x = Double(p2 + 8)
    step(g2, 0.6)
    g2.usePowerDevice(p2 + 10, 98, .lever)
    step(g2, 1.2)
    check(lv2.on && g2.sirenLevel > 0.5, "a storm siren on a pulse wire sounds when the pulse is on (level \(f1(g2.sirenLevel)))")
}

// ---------------------------------------------------------------- D. machines and items
print("== machines")
do {
    // drill -> conveyor -> collector -> chest: nothing made, nothing lost
    let (g, px) = arena()
    let bat = put(g, px - 6, 99, .accumulator)!
    bat.charge = 5000
    // a column of dirt for the drill to bore into, to its right
    for y in 92...99 { g.world.set(px + 1, y, .dirt) }
    let dr = put(g, px, 96, .autoDrill, dir: 0)!
    wire(g, 0, px - 6, 99, px - 6, 96); wire(g, 0, px - 6, 96, px, 96)
    g.pb.x = Double(px - 25)
    step(g, 6)
    let bored = tile(g, px + 1, 96) == .air
    check(bored, "a powered auto drill bores out the block it faces")
    let dropsNow = g.drops.filter { $0.stack.item == .block(.dirt) }.reduce(0) { $0 + $1.stack.count }
    check(dropsNow >= 1, "what it digs drops as an item, as if mined (\(dropsNow) dirt lying there)")
    // cut the power: it stops
    cut(g, px - 1, 96)
    let workBefore = dr.work
    step(g, 3)
    check(tile(g, px + 1, 95) == .dirt && !dr.powered, "cut its cable: the drill stops (work \(f1(workBefore)) -> \(f1(dr.work)))")
}
do {
    // the real conveyor test
    let (g, px) = arena()
    let bat = put(g, px - 8, 97, .accumulator)!
    bat.charge = 5000
    // belts form the floor of a raised walkway at row 97, items dropped on them at the left end
    for i in 0..<6 { put(g, px + i, 97, .conveyor, dir: 0) }
    put(g, px + 6, 97, .collector)
    g.world.set(px + 7, 97, .chest)
    g.world.setChestItems(px + 7, 97, [Stack(item: .mat(.coal), count: 5)])
    wire(g, 0, px - 8, 97, px + 6, 97)
    var dropped = 0
    for i in 0..<4 {
        let n = 10 + i
        dropped += n
        g.spawnDrop(Stack(item: .mat(.ironOre), count: n), Double(px) + 0.5, 96.6, 0, 0)
    }
    g.pb.x = Double(px - 20)
    step(g, 8)
    let inChest = g.world.chestItems(px + 7, 97).filter { $0.item == .mat(.ironOre) }.reduce(0) { $0 + $1.count }
    let lying = g.drops.filter { $0.stack.item == .mat(.ironOre) }.reduce(0) { $0 + $1.stack.count }
    let coal = g.world.chestItems(px + 7, 97).filter { $0.item == .mat(.coal) }.reduce(0) { $0 + $1.count }
    check(inChest + lying == dropped, "conveyor and collector: every item accounted for, none made or lost (\(dropped) dropped, \(inChest) in the chest, \(lying) lying)")
    check(inChest == dropped, "...and all of them reached the chest")
    check(coal == 5, "the chest's other contents are untouched")
    // they stack properly
    let stacks = g.world.chestItems(px + 7, 97).filter { $0.item == .mat(.ironOre) }
    check(stacks.count == 1, "the collected ore stacks into one stack (\(stacks.map { $0.count }))")
}
do {
    // auto crafter: logs behind, planks in front
    let (g, px) = arena()
    let bat = put(g, px - 4, 99, .accumulator)!
    bat.charge = 5000
    let cf = put(g, px, 99, .autoCrafter, dir: 0)!
    g.world.set(px - 1, 99, .chest)
    g.world.set(px + 1, 99, .chest)
    g.world.setChestItems(px - 1, 99, [Stack(item: .block(.log), count: 3)])
    g.world.setChestItems(px + 1, 99, [])
    let r = RecipeBook.all.first { $0.out == .block(.planks) && $0.cost.count == 1 && $0.cost[0].item == .block(.log) }!
    cf.item = r.id
    wire(g, 0, px - 4, 99, px, 99)
    step(g, 9)
    let logs = g.world.chestItems(px - 1, 99).reduce(0) { $0 + $1.count }
    let planks = g.world.chestItems(px + 1, 99).filter { $0.item == .block(.planks) }.reduce(0) { $0 + $1.count }
    check(logs == 0 && planks == 12, "an auto crafter turns 3 logs from the chest behind into 12 planks in the chest in front (\(logs) logs, \(planks) planks)")
    step(g, 4)
    let planks2 = g.world.chestItems(px + 1, 99).filter { $0.item == .block(.planks) }.reduce(0) { $0 + $1.count }
    check(planks2 == 12, "with no logs left it makes nothing more (no free items)")
}
do {
    // arc trap
    let (g, px) = arena()
    let bat = put(g, px - 4, 100, .accumulator)!
    bat.charge = 5000
    g.world.set(px, 100, .arcTrap)
    wire(g, 0, px - 4, 100, px, 100)
    let z = g.addMob(.zombie, Double(px) + 0.5, 100)
    z.maxHP = 1000; z.hp = 1000
    g.pauseMobs = true
    g.pb.x = Double(px - 20)
    var hits = 0
    var last = z.hp
    var t = 0.0
    while t < 3.05 { g.tick(1.0 / 60.0); t += 1.0 / 60.0; if z.hp < last { hits += 1; last = z.hp } }
    check(hits >= 3 && hits <= 4, "an arc trap zaps a zombie standing on it about once a second, never every frame (\(hits) zaps in 3 s)")
    g.pb.x = Double(px) + 0.5
    g.godMode = false
    let hp0 = g.hp
    step(g, 1.5)
    check(g.hp == hp0, "set to creatures only, it leaves the player alone")
}
do {
    // sump pump
    let (g, px) = arena()
    let bat = put(g, px - 4, 99, .accumulator)!
    bat.charge = 5000
    for x in (px + 1)...(px + 3) { g.world.set(x, 99, .water) }
    put(g, px, 99, .sumpPump)
    wire(g, 0, px - 4, 99, px, 99)
    step(g, 2)
    let water = ((px + 1)...(px + 3)).filter { g.world.tile($0, 99) == .water }.count
    check(water == 0, "a sump pump drains the water around it (\(water) left)")
}

// ---------------------------------------------------------------- E. saving, chunks, touch
print("== saving, chunks and touch")
do {
    let (g, px) = arena()
    let bat = put(g, px, 99, .battery)!
    bat.charge = 321
    let gate = put(g, px + 3, 95, .logicGate, dir: 2)!
    gate.mode = 2
    put(g, px + 5, 99, .lampOff)
    wire(g, 0, px, 99, px + 5, 99)
    let lv = put(g, px + 5, 96, .lever)!
    wire(g, 1, px + 5, 96, px + 5, 99)
    g.usePowerDevice(px + 5, 96, .lever)
    step(g, 0.6)
    check(tile(g, px + 5, 99) == .lampOn && lv.on, "before saving: the lamp is lit by its lever")
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = try! JSONDecoder().decode(SaveData.self, from: data)
    let g2 = Game.load(back, settings: Settings())
    g2.viewW = 1100; g2.viewH = 800
    g2.settings.weatherOn = false
    g2.godMode = true
    g2.pauseSpawning = true
    g2.world.loadAround(centerX: px, radius: 4)
    step(g2, 0.6)
    let b2 = g2.world.powerDev(px, 99)
    let gt2 = g2.world.powerDev(px + 3, 95)
    check(b2 != nil && abs((b2?.charge ?? 0) - 321) < 1.5, "after saving and loading, the battery keeps its charge (\(Int(b2?.charge ?? -1)))")
    check(gt2?.mode == 2 && gt2?.dir == 2, "...a gate keeps its type and facing")
    check(g2.world.wireAt(px + 2, 99) & Wire.power != 0 && g2.world.wireAt(px + 5, 97) & Wire.pulseA != 0, "...the wiring is all there")
    check(g2.world.tile(px + 5, 99) == .lampOn && (g2.world.powerDev(px + 5, 96)?.on ?? false), "...and the circuit works as it did: the lamp is lit, the lever still on")
    // a save from before power loads with no devices or wires
    var old = back
    old.power = nil
    for i in 0..<old.chunks.count { old.chunks[i].wires = nil }
    let g3 = Game.load(old, settings: Settings())
    check(g3.world.devs.isEmpty, "an older save with no power section loads cleanly")
}
do {
    // walk far away (the base unloads) and come back
    let (g, px) = arena()
    let sp = put(g, px, 99, .solarPanel)!
    let bat = put(g, px + 2, 99, .battery)!
    put(g, px + 4, 99, .lampOff)
    wire(g, 0, px, 99, px + 4, 99)
    step(g, 3)
    let c0 = bat.charge
    g.debugTeleport(Double(px + 900), 60)
    step(g, 3)
    let unloaded = !g.world.isLoaded(px)
    check(unloaded && g.power.devs.allSatisfy({ abs($0.x - px) > 100 }), "far away the base's chunks unload and its devices drop out of the simulation")
    let cFar = g.world.devs[ChestKey(d: 0, x: px + 2, y: 99)]?.charge ?? -1
    check(abs(cFar - bat.charge) < 0.001, "its battery is kept as it was (frozen, not lost)")
    g.debugTeleport(Double(px) + 0.5, 99)
    step(g, 3)
    let lampBack = g.world.tile(px + 4, 99)
    check(g.world.isLoaded(px) && lampBack == .lampOn && bat.charge >= c0 - 1, "back home the circuit picks up again (lamp lit, charge \(Int(bat.charge)))")
    _ = sp
}
do {
    // laying wire by touch: drag with a spool, snip it back up
    let (g, px) = arena()
    g.inv.slots[0] = Stack(item: .gadget(.powerCable), count: 20)
    g.sel = 0
    g.pointerDown(Double(px + 1) + 0.5, 98.5)
    g.tick(1.0 / 60.0)
    for i in 1...5 { g.pointerMove(Double(px + 1 + i) + 0.5, 98.5); g.tick(1.0 / 60.0) }
    g.pointerUp()
    g.tick(1.0 / 60.0)
    let laid = (px + 1...px + 6).filter { g.world.wireAt($0, 98) & Wire.power != 0 }.count
    check(laid == 6 && g.inv.slots[0]?.count == 14, "dragging with power cable lays a cable along the drag, one per block (\(laid) laid, \(g.inv.slots[0]?.count ?? 0) left)")
    // a fast drag (big jump between frames) leaves no gap
    g.pointerDown(Double(px + 1) + 0.5, 96.5)
    g.tick(1.0 / 60.0)
    g.pointerMove(Double(px + 6) + 0.5, 96.5)
    g.tick(1.0 / 60.0)
    g.pointerUp()
    g.tick(1.0 / 60.0)
    let fast = (px + 1...px + 6).filter { g.world.wireAt($0, 96) & Wire.power != 0 }.count
    check(fast == 6, "a quick swipe still lays an unbroken line (\(fast) of 6)")
    // over a lever: wiring, not flipping it
    let lv = put(g, px + 3, 94, .lever)!
    g.pointerDown(Double(px + 3) + 0.5, 94.5)
    g.tick(1.0 / 60.0)
    g.pointerUp()
    g.tick(1.0 / 60.0)
    check(!lv.on && g.world.wireAt(px + 3, 94) & Wire.power != 0, "with wire in hand a tap on a lever lays wire and doesn't flip it")
    let beforeSnip = g.inv.total(.gadget(.powerCable))
    g.inv.slots[1] = Stack(item: .gadget(.wireSnips), count: 1)
    g.sel = 1
    g.pointerDown(Double(px + 1) + 0.5, 98.5)
    g.tick(1.0 / 60.0)
    for i in 1...5 { g.pointerMove(Double(px + 1 + i) + 0.5, 98.5); g.tick(1.0 / 60.0) }
    g.pointerUp()
    g.tick(1.0 / 60.0)
    let leftWire = (px + 1...px + 6).filter { g.world.wireAt($0, 98) != 0 }.count
    check(leftWire == 0 && g.inv.total(.gadget(.powerCable)) == beforeSnip + 6, "snips take it back up and return every piece (\(beforeSnip) -> \(g.inv.total(.gadget(.powerCable))) cable in the bag)")
    // the probe lights up a network and reports on it
    g.inv.slots[2] = Stack(item: .gadget(.probe), count: 1)
    g.sel = 2
    g.probeAt(Double(px + 3) + 0.5, 96.5)
    check((g.inspect?.cells.count ?? 0) == 6, "the probe on a cable lights up its whole network (\(g.inspect?.cells.count ?? 0) blocks)")
    let bat = put(g, px + 1, 96, .battery)!
    step(g, 0.3)
    g.probeAt(Double(px + 1) + 0.5, 96.5)
    check(g.showPower && g.powerAt == bat.key, "the probe on a device opens its panel")
    check(!g.powerPanelLines(bat).isEmpty, "the panel describes it and its line")
}
do {
    // Flat World
    var o = WorldOptions(); o.flat = true
    let (g, px) = arena(o)
    let cr = put(g, px, 99, .crankGen)!
    cr.charge = 60
    put(g, px + 3, 99, .lampOff)
    wire(g, 0, px, 99, px + 3, 99)
    step(g, 0.6)
    check(g.world.tile(px + 3, 99) == .lampOn, "Sparkworks works in a flat world")
}
do {
    // a big base stays cheap: 40 lamps on a clock, long cables, many logic parts
    let (g, px) = arena()
    let bat = put(g, px - 30, 99, .accumulator)!
    bat.charge = 5000
    wire(g, 0, px - 30, 99, px + 30, 99)
    let tm = put(g, px - 28, 95, .pulseTimer, dir: 0)!
    tm.param = 0.5
    wire(g, 1, px - 27, 95, px + 30, 95)
    for i in 0..<40 {
        let x = px - 20 + i
        put(g, x, 97, .lampOff)
        wire(g, 0, x, 97, x, 98)
        wire(g, 1, x, 96, x, 97)
    }
    for i in 0..<20 { put(g, px - 20 + i * 2, 92, .repeater, dir: 0) }
    step(g, 1)
    let t0 = Date()
    step(g, 4)
    let ms = Date().timeIntervalSince(t0) * 1000.0 / 240.0
    check(ms < 25, "40 blinking lamps, long lines and 20 relays: frames stay quick (\(f1(ms)) ms a frame, debug build)")
    check(g.power.rebuilds < 10, "the networks are only worked out again when the wiring changes (\(g.power.rebuilds) rebuilds)")
}


// ---------------------------------------------------------------- F. more parts
print("== more parts")
do {
    // the Ember Dynamo burns ember for a lot of power
    let (g, px) = arena()
    let dy = put(g, px, 99, .emberDynamo)!
    g.inv.slots[0] = Stack(item: .mat(.emberBar), count: 2); g.sel = 0
    g.usePowerDevice(px, 99, .emberDynamo)
    check(dy.charge == 300 && g.inv.slots[0]?.count == 1, "an Ember Dynamo takes an ember bar as five minutes of fuel")
    g.inv.slots[0] = Stack(item: .mat(.coal), count: 2)
    g.usePowerDevice(px, 99, .emberDynamo)
    check(dy.charge == 300 && g.inv.slots[0]?.count == 2, "...and refuses coal (it opens its panel instead)")
    g.showPower = false
    wire(g, 0, px, 99, px + 30, 99)
    for i in 0..<30 { put(g, px + 1 + i, 98, .lampOff); wire(g, 0, px + 1 + i, 98, px + 1 + i, 99) }
    step(g, 1.5)
    let lit = (0..<30).filter { tile(g, px + 1 + $0, 98) == .lampOn }.count
    check(lit == 30 && dy.made > 29, "it lights thirty lamps on its own (\(lit) lit, making \(f1(dy.made)) sparks/s)")
}
do {
    // crossing lines: amber and teal on the same cells stay separate
    let (g, px) = arena()
    let a = put(g, px, 95, .lever)!
    put(g, px + 6, 95, .signalLight)
    wire(g, 1, px, 95, px + 6, 95)
    put(g, px + 3, 92, .lever)
    let lb = put(g, px + 3, 98, .signalLight)!
    wire(g, 2, px + 3, 92, px + 3, 98)
    step(g, 0.3)
    g.usePowerDevice(px, 95, .lever)
    step(g, 0.3)
    let la = g.world.powerDev(px + 6, 95)!
    check(a.on && (g.pulseHere(la) ?? false) && !(g.pulseHere(lb) ?? true), "an amber line crossing a teal one: switching the amber leaves the teal off")
}
do {
    // push button pulse length, timer in delay mode
    let (g, px) = arena()
    let b = put(g, px, 95, .pushButton)!
    b.param = 1.5
    let sl = put(g, px + 2, 95, .signalLight)!
    wire(g, 1, px, 95, px + 2, 95)
    step(g, 0.2)
    g.usePowerDevice(px, 95, .pushButton)
    step(g, 1.0)
    let mid = g.pulseHere(sl) ?? false
    step(g, 1.0)
    check(mid && !(g.pulseHere(sl) ?? true), "a push button set to 1.5 s sends a pulse that long, then stops")
    let (g2, p2) = arena()
    let lv = put(g2, p2, 95, .lever)!
    let tm = put(g2, p2 + 2, 95, .pulseTimer, dir: 0)!
    tm.mode = 1
    tm.param = 1.0
    wire(g2, 1, p2, 95, p2 + 1, 95)
    let s2 = put(g2, p2 + 4, 95, .signalLight)!
    wire(g2, 1, p2 + 3, 95, p2 + 4, 95)
    step(g2, 0.2)
    g2.usePowerDevice(p2, 95, .lever)
    step(g2, 0.7)
    let early = g2.pulseHere(s2) ?? false
    step(g2, 0.6)
    check(lv.on && !early && (g2.pulseHere(s2) ?? false), "a timer in delay mode passes the lever on after its 1 s delay, not before")
}
do {
    // pressure plate modes, motion sensor, item sensor
    let (g, px) = arena()
    let pp = put(g, px + 3, 99, .pressurePlate)!
    pp.mode = 1
    let sl = put(g, px + 3, 96, .signalLight)!
    wire(g, 1, px + 3, 96, px + 3, 99)
    g.pb.x = Double(px - 10)
    let z = g.addMob(.pig, Double(px + 3) + 0.5, 100)
    g.pauseMobs = true
    step(g, 0.5)
    check(!(g.pulseHere(sl) ?? true), "a pressure plate set to the player ignores a pig standing on it")
    z.removed = true
    g.pb.x = Double(px + 3) + 0.5
    step(g, 0.5)
    check(g.pulseHere(sl) ?? false, "...and presses when the player steps on")
    g.pb.x = Double(px - 10)
    step(g, 0.5)
    check(!(g.pulseHere(sl) ?? true), "...and lets go when they step off")

    let (g2, p2) = arena()
    let bat = put(g2, p2, 99, .battery)!
    bat.charge = 600
    let ms = put(g2, p2 + 2, 99, .motionSensor)!
    ms.param = 5
    let ist = put(g2, p2 + 6, 99, .itemSensor)!
    g2.world.set(p2 + 7, 99, .chest)
    g2.world.setChestItems(p2 + 7, 99, [])
    wire(g2, 0, p2, 99, p2 + 6, 99)
    g2.pb.x = Double(p2 + 3) + 0.5
    g2.pb.vx = 0
    step(g2, 0.6)
    let still = ms.out
    g2.stick = 1
    step(g2, 0.4)
    g2.stick = 0
    check(!still && ms.out, "a motion sensor ignores the player standing still and sees them move")
    check(!ist.out, "an item sensor beside an empty chest is off")
    g2.world.setChestItems(p2 + 7, 99, [Stack(item: .mat(.coal), count: 3)])
    step(g2, 0.6)
    check(ist.out, "...and on once the chest holds something")
}
do {
    // cranking is work
    let (g, px) = arena()
    put(g, px, 99, .crankGen)
    g.godMode = false
    let h0 = g.hunger
    for _ in 0..<4 { g.usePowerDevice(px, 99, .crankGen) }
    check(g.hunger < h0, "winding the crank by hand makes the player hungry (\(f1(h0)) -> \(f1(g.hunger)))")
}

print(fails == 0 ? "ALL POWER TESTS PASSED" : "\(fails) FAILED, \(passes) passed")
