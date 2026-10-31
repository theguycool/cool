import SwiftUI
import Foundation
// Headless screenshots of the weather (software rasteriser in the SwiftUI stand-in)
let W = 960, H = 640
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/wxshots"
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
func game(_ seed: UInt64 = 4242, _ opts: WorldOptions = .standard) -> Game {
    let g = Game(mode: .survival, infinite: true, seed: seed, settings: Settings(), options: opts)
    g.viewW = Double(W); g.viewH = Double(H)
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.godMode = true
    return g
}
func biomeX(_ g: Game, _ b: Biome, from: Int = 0) -> Int {
    var x = from
    while x < from + 80000 { if g.gen.col(x).biome == b && g.gen.col(x - 40).biome == b && g.gen.col(x + 40).biome == b { return x }; x += 16 }
    return 0
}
func standAt(_ g: Game, _ x0: Int) {
    // a dry, open spot: solid ground with air above it and no water close by
    var x = x0
    g.world.loadAround(centerX: x, radius: 5)
    for _ in 0..<400 {
        g.world.loadAround(centerX: x, radius: 3)
        let h = g.gen.col(x).h
        var wet = false
        for k in -12...12 { if g.world.tile(x + k, g.gen.col(x + k).h - 1).liquid || g.world.tile(x + k, g.gen.col(x + k).h).liquid { wet = true } }
        if !wet && g.world.tile(x, h).solid && g.world.tile(x, h - 1) == .air && g.world.tile(x, h - 2) == .air && h < WorldGen.sea { break }
        x += 7
    }
    g.world.loadAround(centerX: x, radius: 5)
    g.debugTeleport(Double(x) + 0.5, Double(g.gen.col(x).h) - 0.05)
    g.camX = g.pb.x; g.camY = g.pb.y - 2; g.camTX = g.camX; g.camTY = g.camY
}
func force(_ g: Game, _ k: WeatherKind) {
    g.debugForceWeather(k)
    g.weather.stateDur = 9999
    let p = g.allowedProfile(k)
    g.weather.precip = p.precip; g.weather.cover = 1; g.weather.cloud = p.cloud
}
func soak(_ g: Game, wet: Double, snow: Double) {
    let c0 = Int(floor(g.pb.x / groundCellW))
    for c in (c0 - 4)...(c0 + 4) { g.weather.cells[c] = GroundCell(wet: wet, snow: snow, t: g.weather.t) }
}
func steps(_ g: Game, _ n: Int) { for _ in 0..<n { g.tick(1.0 / 60.0) } }

// 1. heavy rain in a forest, the ground soaked
do {
    let g = game(); standAt(g, biomeX(g, .forest)); g.timeOfDay = 0.22
    force(g, .heavyRain); g.weather.wind = 6; soak(g, wet: 1, snow: 0)
    steps(g, 60); render(g, "1_rain")
}
// 2. thunderstorm at dusk with a bolt
do {
    let g = game(); standAt(g, biomeX(g, .plains)); g.timeOfDay = 0.52
    force(g, .thunderstorm); soak(g, wet: 0.7, snow: 0)
    steps(g, 60)
    g.lightningStrike(g.pb.x + 9.5, Double(g.world.rainTop(Int(g.pb.x) + 9)), rod: false)
    g.tick(1.0 / 60.0)
    render(g, "2_thunderstorm")
}
// 3. a blizzard on the tundra, snow lying deep, the player freezing
do {
    let g = game(); standAt(g, biomeX(g, .tundra)); g.timeOfDay = 0.3
    force(g, .blizzard); g.weather.wind = 13; soak(g, wet: 0, snow: 1)
    steps(g, 90); g.bodyCold = 0.75
    render(g, "3_blizzard")
}
// 4. large hail on a farm
do {
    let g = game(); standAt(g, biomeX(g, .plains)); g.timeOfDay = 0.2
    let x = Int(floor(g.pb.x)) + 3
    let gy = Int(floor(g.pb.y))
    for k in -8...8 { g.world.set(x + k, gy, .farmland); g.world.set(x + k, gy - 1, k % 3 == 0 ? .wheat2 : .wheat3) }
    force(g, .hailstorm); g.weather.bigHail = true; g.weather.hail = 1
    steps(g, 120); render(g, "4_hail")
}
// 5. a windstorm over the desert
do {
    let g = game(); standAt(g, biomeX(g, .desert)); g.timeOfDay = 0.25
    force(g, .windstorm); g.weather.windDir = 1; g.weather.wind = 14
    steps(g, 60); print("windstorm: local wind", g.wxHere.wind, "shelter", g.shelterLevel, g.biomeHere.name); render(g, "5_windstorm")
}
// 6. a tornado on the ground, close
do {
    let g = game(); standAt(g, biomeX(g, .plains)); g.timeOfDay = 0.24
    g.debugForceWeather(.tornado)
    if var e = g.weather.tornado { e.x = g.pb.x + 9; e.phase = 1; e.t = 10; e.dir = -1; g.weather.tornado = e }
    g.weather.stateDur = 9999
    g.weather.precip = 0.5; g.weather.cloud = 1; g.weather.cover = 1
    steps(g, 30)
    if var e = g.weather.tornado { e.x = g.pb.x + 9; g.weather.tornado = e }
    steps(g, 1)
    render(g, "6_tornado")
}
// 7. a hurricane coming in off the sea, and at its height on the coast
do {
    let g = game()
    var x = 0
    while x < 80000 { if g.gen.col(x).biome == .ocean && g.gen.col(x - 8).biome != .ocean && g.gen.col(x - 30).h < WorldGen.sea { break }; x += 4 }
    standAt(g, x - 14); g.timeOfDay = 0.2
    g.debugForceWeather(.hurricane)
    g.weather.stateDur = 9999
    if var h = g.weather.hurricane { h.t = h.stageDur * 0.8; g.weather.hurricane = h }
    steps(g, 30)
    render(g, "7_hurricane_approach")
    if var h = g.weather.hurricane { h.stage = .peak; h.t = 2; h.force = h.strength; g.weather.hurricane = h }
    g.weather.precip = 1; g.weather.cloud = 1; g.weather.cover = 1; g.weather.wind = -15 * (g.weather.hurricane?.side ?? 1)
    steps(g, 200)
    render(g, "8_hurricane_peak")
}
// 9. the weather devices, in a strong wind, with a tornado warning out
do {
    let g = game(); standAt(g, biomeX(g, .plains, from: 3000)); g.timeOfDay = 0.25
    let x = Int(floor(g.pb.x))
    let gy = Int(floor(g.pb.y))
    for k in -14...14 { for y in (gy - 8)..<gy { g.world.set(x + k, y, .air) }; g.world.set(x + k, gy, .grass) }
    let row: [Tile] = [.weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater, .sandbag, .shutterClosed, .shutterOpen, .stormBrick, .shingles]
    for (i, t) in row.enumerated() { g.world.set(x - 13 + i * 2, gy - 1, t) }
    g.weather.store[g.deviceKey(DeviceSpot(x: x - 13 + 10, y: gy - 1, t: .rainBarrel))] = 6
    g.weather.store[g.deviceKey(DeviceSpot(x: x - 13 + 12, y: gy - 1, t: .rainCistern))] = 20
    force(g, .strongWind); g.weather.wind = 9
    g.debugForceWeather(.tornado); g.weather.stateDur = 9999; g.weather.precip = 0; g.weather.wind = 9
    steps(g, 40)
    render(g, "9_devices")
}
