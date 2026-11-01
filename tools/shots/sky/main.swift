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

// the sky: clouds in clear weather, cloudy, a storm, dusk and night, and a hilltop
func setCover(_ g: Game, cover: Double) {
    g.weather.stateDur = 9999
    g.weather.cloud = cover; g.weather.cover = cover; g.weather.precip = 0
}
do {
    let g = game(); standAt(g, biomeX(g, .plains)); g.timeOfDay = 0.25
    g.debugForceWeather(WeatherKind.clear); steps(g, 30); render(g, "1_clear_day")
    force(g, .overcast); steps(g, 600); render(g, "2_cloudy")
}
do {
    let g = game(); standAt(g, biomeX(g, .plains)); g.timeOfDay = 0.25
    force(g, .thunderstorm); steps(g, 120); render(g, "3_storm")
}
do {
    let g = game(); standAt(g, biomeX(g, .plains)); g.timeOfDay = 0.54
    g.debugForceWeather(WeatherKind.clear); setCover(g, cover: 0.2); steps(g, 30); render(g, "4_dusk")
    g.timeOfDay = 0.8; steps(g, 30); render(g, "5_night")
}
do {
    let g = game(); standAt(g, biomeX(g, .mountain)); g.timeOfDay = 0.25
    g.debugForceWeather(WeatherKind.clear); setCover(g, cover: 0.3); steps(g, 30); render(g, "6_mountain")
}
