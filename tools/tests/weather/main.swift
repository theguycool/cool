import SwiftUI
import Foundation

var fails = 0
var passes = 0
func check(_ ok: Bool, _ msg: String) {
    print((ok ? "PASS " : "FAIL ") + msg)
    if ok { passes += 1 } else { fails += 1 }
}
func f2(_ v: Double) -> String { return String(format: "%.2f", v) }
func f1(_ v: Double) -> String { return String(format: "%.1f", v) }

/// an open-air test ground: air above row 100, stone below, around x
func arena(_ seed: UInt64 = 4242, opts: WorldOptions = .standard, at: Int? = nil, settings: Settings = Settings()) -> Game {
    let g = Game(mode: .survival, infinite: true, seed: seed, settings: settings, options: opts)
    g.viewW = 1100; g.viewH = 800
    g.monstersEnabled = false
    g.pauseSpawning = true
    g.mobs.removeAll()
    if let x = at { g.pb.x = Double(x) + 0.5 }
    let w = g.world
    let x0 = Int(g.pb.x) - 40
    w.loadAround(centerX: Int(g.pb.x), radius: 6)
    for x in x0...(x0 + 80) {
        for y in 40..<100 { w.set(x, y, .air) }
        for y in 100..<106 { w.set(x, y, .stone) }
    }
    g.pb.x = Double(x0 + 40) + 0.5; g.pb.y = 100; g.pb.vx = 0; g.pb.vy = 0
    g.hp = g.maxHP
    g.light.valid = false
    g.camX = g.pb.x; g.camY = g.pb.y - 2
    return g
}
func step(_ g: Game, _ secs: Double, _ dt: Double = 1.0 / 60.0) { var t = 0.0; while t < secs { g.tick(dt); t += dt } }
/// the simulation alone (no world ticks): fast, for long runs
func simRun(_ g: Game, _ secs: Double, _ dt: Double = 0.5, _ each: ((Double) -> Void)? = nil) {
    var t = 0.0
    while t < secs {
        g.stepWeatherSim(dt)
        g.wxHere = g.weatherAt(g.pb.x, g.pb.y - g.pb.h)
        g.updateTornado(dt)
        g.updateHurricane(dt)
        g.updateSurge(dt)
        each?(t)
        t += dt
    }
}
/// make a kind of weather start, at full strength, for a long while
func force(_ g: Game, _ k: WeatherKind) {
    g.debugForceWeather(k)
    g.weather.stateDur = 99999
    let p = g.allowedProfile(k)
    g.weather.precip = p.precip
    g.weather.cover = 1.0
    g.weather.cloud = p.cloud
}
func biomeX(_ g: Game, _ b: Biome, from: Int = 0) -> Int? {
    var x = from
    while x < from + 60000 {
        if g.gen.col(x).biome == b && g.gen.col(x - 30).biome == b && g.gen.col(x + 30).biome == b { return x }
        x += 16
    }
    return nil
}
/// a land column about `inland` blocks from an ocean, and which side the sea is on
func coastX(_ g: Game, inland: Int) -> (Int, Double)? {
    var x = 0
    while x < 80000 {
        if g.gen.col(x).biome == .ocean && g.gen.col(x - 8).biome != .ocean {
            // land to the west of this sea
            let lx = x - inland
            if g.gen.col(lx).biome != .ocean && g.gen.col(lx).h < WorldGen.sea { return (lx, 1) }
        }
        x += 4
    }
    return nil
}

// ---------------------------------------------------------------- A. the simulation
print("== the simulation: states, plan, transitions")
do {
    let g = arena()
    check(g.weather.kind == .clear && g.settings.weatherOn, "a new world starts with clear weather, weather on by default")
    g.tick(1.0 / 60.0)
    check(g.weather.plan.count == 4 && g.forecast().count == 5, "after one step the plan holds four spells (the forecast shows five lines)")
    check(g.weather.calmUntil >= 600, "a new world has a calm before any severe weather (\(Int(g.weather.calmUntil)) s)")
}
do {
    // a long run: which states follow which, how long they last, how often severe weather comes
    let neighbours: [WeatherKind: Set<WeatherKind>] = [
        .clear: [.clear, .partlyCloudy, .strongWind],
        .partlyCloudy: [.clear, .partlyCloudy, .overcast, .strongWind],
        .overcast: [.partlyCloudy, .overcast, .lightRain, .heavyRain, .snowfall, .windstorm, .hailstorm, .thunderstorm, .hurricane],
        .lightRain: [.overcast, .lightRain, .heavyRain],
        .heavyRain: [.lightRain, .heavyRain, .thunderstorm],
        .thunderstorm: [.heavyRain, .overcast, .hailstorm, .tornado],
        .strongWind: [.partlyCloudy, .clear, .strongWind, .windstorm, .hurricane],
        .windstorm: [.strongWind, .overcast],
        .hailstorm: [.heavyRain, .lightRain, .overcast],
        .snowfall: [.overcast, .snowfall, .blizzard],
        .blizzard: [.snowfall, .overcast],
        .tornado: [.heavyRain, .lightRain, .overcast],
        .hurricane: [.heavyRain, .lightRain, .overcast]
    ]
    var stats: [Int: (Double, Double, Int, Int)] = [:]
    for freq in [0, 1, 2] {
        var st = Settings(); st.severeFrequency = freq
        // on the plains (tornado country, the sea within reach): deserts and the snow get fewer storms
        let probe = Game(mode: .survival, infinite: true, seed: 4242, settings: st)
        let g = arena(4242, at: biomeX(probe, .plains) ?? 0, settings: st)
        var last = g.weather.kind
        var bad: [String] = []
        var severeT = 0.0
        var total = 0.0
        var tornadoes = 0
        var forecastHits = 0
        var forecastAll = 0
        var predicted: WeatherKind? = nil
        var maxJump = 0.0
        var prevPrecip = g.weather.precip
        var prevCloud = g.weather.cloud
        var prevStateT = -1.0
        let hours: Double = 60
        simRun(g, hours * 3600, 0.5) { _ in
            total += 0.5
            if g.weather.kind.severe { severeT += 0.5 }
            // a new spell has begun (also when it is the same kind again)
            if g.weather.stateT < prevStateT {
                if !(neighbours[last]?.contains(g.weather.kind) ?? false) { bad.append("\(last)→\(g.weather.kind)") }
                if g.weather.kind == .tornado { tornadoes += 1 }
                if let p = predicted { forecastAll += 1; if p == g.weather.kind { forecastHits += 1 } }
                last = g.weather.kind
            }
            prevStateT = g.weather.stateT
            predicted = g.weather.plan.first?.kind
            maxJump = max(maxJump, abs(g.weather.precip - prevPrecip), abs(g.weather.cloud - prevCloud))
            prevPrecip = g.weather.precip
            prevCloud = g.weather.cloud
        }
        stats[freq] = (severeT / total, maxJump, tornadoes, forecastAll - forecastHits)
        if freq == 1 {
            check(bad.isEmpty, "weather only moves between neighbouring states over 60 hours (\(bad.prefix(4)))")
            check(maxJump < 0.06, "the amounts change gradually: the most cloud or rain changed in half a second was \(f2(maxJump))")
            check(forecastAll > 100 && forecastHits == forecastAll, "the forecast comes true: \(forecastHits) of \(forecastAll) spells were the one the plan said was next")
        }
    }
    let r = stats[0]!, n = stats[1]!, fq = stats[2]!
    check(r.0 < n.0 && n.0 < fq.0, "severe weather: rare \(Int(r.0 * 100))% of the time, normal \(Int(n.0 * 100))%, frequent \(Int(fq.0 * 100))%")
    check(n.0 < 0.2, "severe weather is uncommon by default (\(Int(n.0 * 100))% of play time)")
    check(r.2 <= fq.2 && n.2 <= fq.2 && n.2 <= 20 && fq.2 >= 1, "tornadoes are rare: \(r.2) / \(n.2) / \(fq.2) in 60 hours (rare / normal / frequent)")
}
do {
    // the same world, saved and loaded, carries on with the same weather
    let g = arena(31337)
    simRun(g, 1800, 0.5)
    let data = try! JSONEncoder().encode(g.makeSave())
    let s = try! JSONDecoder().decode(SaveData.self, from: data)
    let h = Game.load(s, settings: Settings())
    h.pb.x = g.pb.x; h.pb.y = g.pb.y
    check(h.weather.kind == g.weather.kind && h.weather.plan.map { $0.kind } == g.weather.plan.map { $0.kind } && h.weather.rngS == g.weather.rngS, "a saved world loads with the same weather, plan and random state")
    var seqA: [WeatherKind] = [], seqB: [WeatherKind] = []
    simRun(g, 3600, 0.5) { _ in if seqA.last != g.weather.kind { seqA.append(g.weather.kind) } }
    simRun(h, 3600, 0.5) { _ in if seqB.last != h.weather.kind { seqB.append(h.weather.kind) } }
    check(seqA == seqB && seqA.count > 5, "after loading, the next hour's weather is exactly what it would have been (\(seqA.count) spells)")
    // an old save (no weather in it) starts fair
    var old = s
    old.weather = nil
    let o = Game.load(old, settings: Settings())
    check(o.weather.kind == .clear && o.weather.plan.isEmpty, "a save from before the weather loads with fresh, fair weather")
}
do {
    // the weather at a place does not depend on which chunks are loaded, and has no seams at chunk edges
    let g = arena(99)
    force(g, .lightRain)
    g.weather.cover = 0.55
    var a: [Double] = [], b: [Double] = []
    for x in stride(from: -600, to: 600, by: 3) { let L = g.weatherAt(Double(x), 90); a.append(L.precip + L.wind + L.chill) }
    for k in Array(g.world.chunks.keys) { g.world.unloadChunk(k) }
    for x in stride(from: -600, to: 600, by: 3) { let L = g.weatherAt(Double(x), 90); b.append(L.precip + L.wind + L.chill) }
    check(a == b, "the weather at every place is the same with its chunks loaded or not")
    var seam = 0.0, inner = 0.0
    for c in -30...30 {
        let x = Double(c * chunkW)
        seam = max(seam, abs(g.weatherAt(x - 0.01, 90).precip - g.weatherAt(x + 0.01, 90).precip))
        inner = max(inner, abs(g.weatherAt(x + 7.99, 90).precip - g.weatherAt(x + 8.01, 90).precip))
    }
    check(seam < 0.02, "no jump in the rain at chunk boundaries (largest \(f2(seam)))")
    var wet = 0, dry = 0
    for x in stride(from: -2000, to: 2000, by: 10) { if g.weatherAt(Double(x), 90).precip > 0.1 { wet += 1 } else { dry += 1 } }
    check(wet > 20 && dry > 20, "showers are local: rain over \(wet) and dry over \(dry) of 400 places")
    let x0 = 0.0
    let p0 = (0..<40).map { g.weatherAt(x0 + Double($0) * 25, 90).precip }
    g.weather.drift += 120
    let p1 = (0..<40).map { g.weatherAt(x0 + Double($0) * 25, 90).precip }
    check(p0 != p1, "storm cells drift over the land with the wind")
}

// ---------------------------------------------------------------- B. settings
print("== settings: every switch on its own, and the master switch")
do {
    // persisted, and old settings files load with the defaults
    var st = Settings()
    st.weatherOn = false; st.allowHail = false; st.weatherIntensity = 0.5; st.severeFrequency = 2; st.reduceFlashes = true; st.weatherParticles = 0.4
    let back = try! JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(st))
    check(!back.weatherOn && !back.allowHail && back.weatherIntensity == 0.5 && back.severeFrequency == 2 && back.reduceFlashes && back.weatherParticles == 0.4, "weather settings are saved and read back")
    let oldJSON = "{\"hair\":1,\"soundOn\":true}".data(using: .utf8)!
    let o = try! JSONDecoder().decode(Settings.self, from: oldJSON)
    check(o.weatherOn && o.allowTornado && o.weatherIntensity == 1.0 && o.severeFrequency == 1 && o.hair == 1, "a settings file from before the weather gets the weather defaults")
}
do {
    func settled(_ k: WeatherKind, _ edit: (inout Settings) -> Void) -> Game {
        let g = arena(4242)
        edit(&g.settings)
        force(g, k)
        step(g, 3.0)
        return g
    }
    let rainOff = settled(.heavyRain) { $0.allowRain = false }
    let rainOn = settled(.heavyRain) { _ in }
    check(rainOff.weather.precip < 0.02 && rainOn.weather.precip > 0.5 && abs(rainOff.weather.wind) > 1, "rain off: no rain falls (\(f2(rainOff.weather.precip)) vs \(f2(rainOn.weather.precip))), the wind still blows")
    let dry = settled(.thunderstorm) { $0.allowRain = false }
    check(dry.weather.thunder > 1 && dry.weather.precip < 0.02 && dry.weatherLabel(.thunderstorm, snow: false) == "Dry thunderstorm", "rain off, lightning on: a dry thunderstorm")
    let noThunder = settled(.thunderstorm) { $0.allowThunder = false }
    var strikes = 0
    for _ in 0..<1800 { noThunder.tick(1.0 / 30.0); if !noThunder.bolts.isEmpty { strikes += 1 } }
    check(noThunder.weather.thunder < 0.01 && noThunder.weather.precip > 0.5 && strikes == 0, "lightning off: the storm still rains (\(f2(noThunder.weather.precip))) and no bolt falls in a minute")
    let noWind = settled(.windstorm) { $0.allowWind = false }
    let bliz = settled(.blizzard) { $0.allowWind = false }
    check(abs(noWind.weather.wind) < 0.1 && noWind.weather.cloud > 0.3 && abs(bliz.weather.wind) > 5, "wind off: a windstorm is only cloud (wind \(f1(noWind.weather.wind))); a blizzard still blows (its own switch)")
    let noHail = settled(.hailstorm) { $0.allowHail = false }
    var stones = 0
    for _ in 0..<300 { noHail.tick(1.0 / 60.0); stones += noHail.hailPool.filter { $0.on }.count }
    check(noHail.weather.hail < 0.01 && noHail.weather.precip > 0.3 && stones == 0, "hail off: the hailstorm rains but no hail falls")
    let noBliz = settled(.blizzard) { $0.allowBlizzard = false }
    check(abs(noBliz.weather.wind) < 4 && noBliz.weatherLabel(.blizzard, snow: true) == "Snowfall", "blizzards off: a blizzard comes as plain snowfall (wind \(f1(noBliz.weather.wind)))")
    let noTor = settled(.tornado) { $0.allowTornado = false }
    let tor = settled(.tornado) { _ in }
    check(noTor.weather.tornado == nil && tor.weather.tornado != nil, "tornadoes off: no tornado forms (on: one does)")
    let noHur = settled(.hurricane) { $0.allowHurricane = false }
    let hur = settled(.hurricane) { _ in }
    check(noHur.weather.hurricane == nil && hur.weather.hurricane != nil, "hurricanes off: no hurricane comes (on: one does)")
    let torBanner = tor.wxBanner
    // switching an event off while it is happening ends it at once
    tor.settings.allowTornado = false
    tor.tick(1.0 / 60.0)
    check(tor.weather.tornado == nil, "switching tornadoes off mid-storm removes the tornado at once")
    // switched-off kinds never appear in the forecast
    let plan = settled(.clear) { $0.allowTornado = false; $0.allowHurricane = false; $0.allowHail = false }
    var seen: Set<WeatherKind> = []
    simRun(plan, 30 * 3600, 1.0) { _ in seen.insert(plan.weather.kind); for p in plan.weather.plan { seen.insert(p.kind) } }
    check(!seen.contains(.tornado) && !seen.contains(.hurricane) && !seen.contains(.hailstorm), "kinds switched off are never planned (30 hours)")
    // intensity scales what the weather brings
    let soft = settled(.windstorm) { $0.weatherIntensity = 0.5 }
    let hard = settled(.windstorm) { $0.weatherIntensity = 1.5 }
    check(abs(hard.weather.wind) > abs(soft.weather.wind) * 2, "intensity scales the wind (\(f1(abs(soft.weather.wind))) at 50%, \(f1(abs(hard.weather.wind))) at 150%)")
    // alerts off: no banner, no messages; the siren is a device and still works
    let quiet = settled(.tornado) { $0.weatherAlerts = false }
    check(quiet.wxBanner.isEmpty && torBanner.contains("TORNADO"), "alerts off: no warning banner (on: \"\(torBanner.prefix(26))…\")")
}
do {
    // the master switch: everything stops at once and nothing is left behind
    let g = arena(4242)
    force(g, .thunderstorm)
    step(g, 2)
    g.debugForceWeather(.tornado)
    g.weather.stateDur = 999
    step(g, 1)
    g.strikeMark = StrikeMark(x: g.pb.x, y: 100, t: 1.0, total: 1.5)
    g.fireZones.append(FireZone(x: g.pb.x + 3, y: 100, r: 1.6, t: 5, uid: 99, env: true))
    for i in 0..<4 { g.hailPool.append(HailStone(x: g.pb.x + Double(i), y: 90, vx: 0, vy: 10, bounces: 0, size: 0.1, on: true)) }
    g.settings.weatherOn = false
    g.tick(1.0 / 60.0)
    let clean = g.weather.tornado == nil && g.weather.hurricane == nil && g.bolts.isEmpty && g.thunderQueue.isEmpty && g.strikeMark == nil && !g.hailPool.contains { $0.on } && g.fireZones.allSatisfy { !$0.env } && g.wxBanner.isEmpty && g.weatherRain == 0 && g.wxAccelX == 0 && g.wxAccelY == 0
    check(clean, "weather off: no tornado, bolt, pending thunder, strike, hail, lightning fire, banner or push is left")
    let hp0 = g.hp
    let x0 = g.pb.x
    step(g, 20)
    check(g.hp >= hp0 && abs(g.pb.x - x0) < 0.01 && g.bolts.isEmpty && g.weather.precip == 0 && g.bodyCold == 0, "for 20 s after: no harm, no push, no strikes, no rain")
    g.settings.weatherOn = true
    step(g, 1)
    check(g.weather.kind == .clear && g.weather.calmUntil >= g.weather.t + 250 && g.weather.plan.count == 4, "weather back on: it starts fair, with a calm first, and a fresh forecast")
}

// ---------------------------------------------------------------- C. lightning
print("== lightning")
do {
    let g = arena(4242)
    force(g, .thunderstorm)
    g.weather.thunder = 12
    var nearStrikes: [Double] = []
    var markedFirst = 0
    var markT = -1.0
    var hits = 0
    var strikes = 0
    var lastBolts = 0
    var t = 0.0
    let dt = 1.0 / 30.0
    while t < 1500 {
        g.weather.thunder = 12
        g.stepWeatherSim(dt)
        g.wxHere = g.weatherAt(g.pb.x, g.pb.y - g.pb.h)
        let hadMark = g.strikeMark != nil
        if hadMark && markT < 0 { markT = t }
        let hp0 = g.hp
        g.updateLightning(dt)
        if g.hp < hp0 { hits += 1 }
        g.hp = g.maxHP
        for b in g.bolts where b.life == b.maxLife {
            strikes += 1
            if let e = b.pts.last, abs(e.0 - g.pb.x) < 12 {
                nearStrikes.append(t)
                if markT >= 0 && t - markT >= 1.4 { markedFirst += 1 }
            }
        }
        if !hadMark && g.strikeMark == nil { markT = -1 }
        t += dt
    }
    _ = lastBolts
    var gaps: [Double] = []
    for i in 1..<max(1, nearStrikes.count) where nearStrikes.count > 1 { gaps.append(nearStrikes[i] - nearStrikes[i - 1]) }
    check(strikes > 50, "a thunderstorm brings plenty of lightning (\(strikes) strikes in 25 min)")
    check(!nearStrikes.isEmpty && markedFirst == nearStrikes.count, "every strike near the player is marked at least 1.4 s before it lands (\(markedFirst) of \(nearStrikes.count))")
    check(gaps.allSatisfy { $0 >= 44.9 }, "never twice near the player within 45 s (shortest gap \(f1(gaps.min() ?? 999)) s)")
    check(hits <= nearStrikes.count, "the player is only hurt by a strike they were warned of (\(hits) hits, standing still all along)")
}
do {
    // a lightning rod takes every strike near it, and nothing near it is hurt or set alight
    let g = arena(4242)
    let rx = Int(floor(g.pb.x)) + 4
    g.world.set(rx, 99, .lightningRod)
    force(g, .thunderstorm)
    var onRod = 0, nearNotRod = 0, hurt = 0
    var t = 0.0
    let dt = 1.0 / 30.0
    var lastLife = -1.0
    while t < 900 {
        g.weather.thunder = 12
        g.stepWeatherSim(dt)
        g.wxHere = g.weatherAt(g.pb.x, g.pb.y - g.pb.h)
        let hp0 = g.hp
        g.updateLightning(dt)
        if g.hp < hp0 { hurt += 1 }
        for b in g.bolts where b.life == b.maxLife {
            if let e = b.pts.last {
                if abs(e.0 - (Double(rx) + 0.5)) < 0.01 { onRod += 1 } else if abs(e.0 - Double(rx)) <= rodReach { nearNotRod += 1 }
            }
        }
        _ = lastLife
        t += dt
    }
    check(onRod > 3 && nearNotRod == 0, "a lightning rod takes every strike within 14 blocks (\(onRod) on the rod, \(nearNotRod) elsewhere near it)")
    check(hurt == 0 && g.strikeMark == nil, "under its protection the player is never struck")
    // under cover the rod is no use
    g.world.set(rx, 95, .stone)
    check(g.rodCovering(Double(rx)) == nil, "a rod with a roof over it does not work")
}
do {
    // lightning starts fires on things that burn (less in the rain); the damage switches decide
    let g = arena(4242)
    let lx = Int(floor(g.pb.x)) + 10
    g.world.set(lx, 99, .hay)
    g.lightningStrike(Double(lx) + 0.5, 99, rod: false)
    check(g.fireZones.contains { $0.env } && g.world.tile(lx, 99) == .air, "a strike on hay burns it away and starts a fire")
    let wetFire = g.fireZones.first { $0.env }!.t
    let g2 = arena(4242)
    force(g2, .heavyRain)
    step(g2, 2)
    g2.world.set(lx, 99, .hay)
    g2.lightningStrike(Double(lx) + 0.5, 99, rod: false)
    let rainFire = g2.fireZones.first { $0.env }?.t ?? 0
    check(rainFire < wetFire, "in heavy rain a lightning fire is shorter (\(f1(rainFire)) s vs \(f1(wetFire)) s)")
    let g3 = arena(4242)
    g3.settings.weatherHurtsBlocks = false
    g3.settings.weatherHurtsPlayer = false
    g3.world.set(lx, 99, .hay)
    g3.lightningStrike(Double(lx) + 0.5, 99, rod: false)
    let hp0 = g3.hp
    g3.lightningStrike(g3.pb.x, 100, rod: false)
    check(g3.world.tile(lx, 99) == .hay && g3.fireZones.isEmpty && g3.hp == hp0, "with block and player damage off, strikes burn nothing and hurt nobody")
    let g4 = arena(4242)
    let hp4 = g4.hp
    g4.lightningStrike(g4.pb.x, 100, rod: false)
    check(g4.hp < hp4, "with damage on, a direct strike hurts the player (\(Int(hp4 - g4.hp)) hp)")
    let g5 = arena(4242)
    g5.settings.weatherHurtsCreatures = false
    let pig = g5.addMob(.pig, g5.pb.x + 6, 100); pig.persistent = true
    g5.mobGrid.rebuild(g5.mobs)
    g5.lightningStrike(pig.b.x, 100, rod: false)
    let g6 = arena(4242)
    let pig2 = g6.addMob(.pig, g6.pb.x + 6, 100); pig2.persistent = true
    g6.mobGrid.rebuild(g6.mobs)
    g6.lightningStrike(pig2.b.x, 100, rod: false)
    check(pig.hp == pig.maxHP && pig2.hp < pig2.maxHP, "creature damage off spares the pig; on, the strike hurts it")
    // thunder comes later the further off the strike
    let g7 = arena(4242)
    g7.lightningStrike(g7.pb.x + 90, 100, rod: false)
    check(g7.thunderQueue.count == 1 && abs(g7.thunderQueue[0].t - 2.0) < 0.1, "thunder from 90 blocks away arrives \(f1(g7.thunderQueue.first?.t ?? 0)) s after the flash")
    // gentler flashes: dimmer, but the strike is just as real
    let g8 = arena(4242)
    g8.settings.reduceFlashes = true
    let hp8 = g8.hp
    g8.lightningStrike(g8.pb.x, 100, rod: false)
    check(g8.skyFlash <= 0.15 && g4.skyFlash >= 0.5 && g8.hp < hp8, "gentler flashes: the sky flash is \(f2(g8.skyFlash)) instead of \(f2(g4.skyFlash)); the strike still hurts")
}

// ---------------------------------------------------------------- D. hail
print("== hail")
do {
    func hailRun(_ edit: (Game) -> Void) -> (Double, Int, Int) {
        let g = arena(4242)
        force(g, .hailstorm)
        g.weather.bigHail = true
        g.weather.hail = 1
        edit(g)
        var taken = 0.0
        var stones = 0
        var maxStones = 0
        for _ in 0..<1800 {
            let before = g.hp
            g.tick(1.0 / 60.0)
            if g.hp < before { taken += before - g.hp }
            let n = g.hailPool.filter { $0.on }.count
            stones += n
            maxStones = max(maxStones, n)
        }
        return (taken, stones, maxStones)
    }
    let open = hailRun { _ in }
    let roofed = hailRun { g in for x in -4...4 { g.world.set(Int(floor(g.pb.x)) + x, 96, .planks) } }
    let helmet = hailRun { g in g.inv.armor[0] = Stack(item: .armor(.head, .iron), count: 1) }
    check(open.0 >= 3, "large hail hurts a player out in it (\(Int(open.0)) hp in 30 s)")
    check(roofed.0 == 0, "a roof keeps it all off")
    check(helmet.0 < open.0, "a helmet turns most of it (\(Int(helmet.0)) hp)")
    check(open.1 > 1000 && open.2 <= 56, "hailstones come from a pool of 56 (at most \(open.2) at once)")
    // crops and glass
    let g = arena(4242)
    force(g, .hailstorm)
    g.weather.bigHail = true
    g.weather.hail = 1
    let cx = Int(floor(g.pb.x))
    for k in 0..<30 { g.world.set(cx - 15 + k, 100, .farmland); g.world.set(cx - 15 + k, 99, .wheat3) }
    for k in 0..<40 { g.world.set(cx - 30 + k, 97, .air) }
    for k in -28...(-18) { g.world.set(cx + k, 99, .glass) }
    // a covered row of crops a little way off
    for k in 20...26 { g.world.set(cx + k, 100, .farmland); g.world.set(cx + k, 99, .wheat3); g.world.set(cx + k, 96, .planks) }
    step(g, 120, 1.0 / 30.0)
    var beaten = 0, coveredBeaten = 0
    for k in 0..<30 where g.world.tile(cx - 15 + k, 99) != .wheat3 { beaten += 1 }
    for k in 20...26 where g.world.tile(cx + k, 99) != .wheat3 { coveredBeaten += 1 }
    var glassGone = 0
    for k in -28...(-18) where g.world.tile(cx + k, 99) != .glass { glassGone += 1 }
    check(beaten > 0 && coveredBeaten == 0, "hail beats down open crops (\(beaten) of 30), never covered ones")
    check(glassGone >= 1 && glassGone <= 6, "large hail breaks glass left open to the sky, but no more than six panes in one storm (\(glassGone) of 11)")
    let g2 = arena(4242)
    g2.settings.weatherHurtsBlocks = false
    force(g2, .hailstorm); g2.weather.bigHail = true; g2.weather.hail = 1
    for k in 0..<30 { g2.world.set(cx - 15 + k, 100, .farmland); g2.world.set(cx - 15 + k, 99, .wheat3) }
    step(g2, 60, 1.0 / 30.0)
    var b2 = 0
    for k in 0..<30 where g2.world.tile(cx - 15 + k, 99) != .wheat3 { b2 += 1 }
    check(b2 == 0, "with block damage off, hail spares the crops")
}

// ---------------------------------------------------------------- E. wind
print("== wind")
do {
    /// (shift standing still for 4 s, fastest speed then, shift over one jump straight up)
    func pushTest(_ k: WeatherKind, _ edit: (Game) -> Void) -> (Double, Double, Double) {
        let g = arena(4242)
        force(g, k)
        g.weather.windDir = 1
        g.weather.wind = abs(g.allowedProfile(k).wind)
        edit(g)
        step(g, 1)
        let x0 = g.pb.x
        var top = 0.0
        for _ in 0..<240 { g.tick(1.0 / 60.0); top = max(top, abs(g.pb.vx)) }
        let stand = g.pb.x - x0
        let jx = g.pb.x
        g.jumpHeld = true; g.tick(1.0 / 60.0); g.jumpHeld = false
        var n = 0
        while n < 200 && !(g.pb.onGround && n > 5) { g.tick(1.0 / 60.0); n += 1 }
        return (stand, top, g.pb.x - jx)
    }
    let calm = pushTest(.clear) { _ in }
    let breezy = pushTest(.partlyCloudy) { _ in }
    let gale = pushTest(.windstorm) { _ in }
    let storm = pushTest(.hurricane) { _ in }
    let inside = pushTest(.windstorm) { g in
        let px = Int(floor(g.pb.x))
        for y in 92...99 { g.world.set(px - 4, y, .stone); g.world.set(px + 4, y, .stone) }
        for x in (px - 4)...(px + 4) { g.world.set(x, 92, .stone) }
        g.warmthT = 0
    }
    check(calm.0 == 0 && breezy.0 == 0 && abs(calm.2) < 0.01 && abs(breezy.2) < 0.01, "a calm day or a breeze moves nobody, standing or jumping")
    check(gale.2 > 0.8, "a windstorm carries a jumping player downwind (\(f1(gale.2)) blocks in one jump)")
    check(abs(gale.0) < 0.5 && storm.1 <= 0.81, "standing still braces against it: a windstorm shifts you \(f2(gale.0)) blocks in 4 s, a hurricane at most \(f2(storm.1)) blocks/s")
    check(abs(inside.0) < 0.01 && abs(inside.2) < 0.05, "indoors the wind does not reach you (jump shift \(f2(inside.2)))")
    // walking against the wind is slower than walking with it
    func walk(_ dir: Double) -> Double {
        let g = arena(4242)
        force(g, .windstorm)
        g.weather.windDir = 1; g.weather.wind = 14; g.weather.gust = 0
        step(g, 0.5)
        let x0 = g.pb.x
        for _ in 0..<120 { g.stick = dir; g.tick(1.0 / 60.0) }
        g.stick = 0
        return abs(g.pb.x - x0)
    }
    let withW = walk(1), against = walk(-1)
    check(withW > against && against > 4, "walking with the wind is quicker (\(f1(withW)) blocks) than against it (\(f1(against)))")
    // shots drift with the wind; heavy shots barely
    func shot(_ k: ProjKind, wind: Bool) -> Double {
        let g = arena(4242)
        if wind { force(g, .windstorm); g.weather.windDir = 1; g.weather.wind = 14; g.weather.gust = 0 }
        step(g, 0.5)
        var p = Projectile(kind: k, x: g.pb.x, y: 97.6, vx: 0, vy: -14, dmg: 1, fromPlayer: true, gravity: 22)
        p.life = 3
        p.source = .player
        g.projectiles = [p]
        var x = g.pb.x
        var ws = 0.0
        for _ in 0..<60 { g.tick(1.0 / 60.0); ws += g.wxHere.wind; if let q = g.projectiles.first { x = q.x } }
        if wind { print("   (wind on the shot: \(f1(ws / 60)) blocks/s on average)") }
        return x - g.pb.x
    }
    let arrowCalm = shot(.arrow, wind: false), arrowWind = shot(.arrow, wind: true), bullet = shot(.bullet, wind: true)
    check(abs(arrowCalm) < 0.05 && arrowWind > 1.0 && abs(bullet) < 0.05, "an arrow shot straight up drifts \(f1(arrowWind)) blocks downwind in a second (none when calm; a bullet not at all)")
}

// ---------------------------------------------------------------- F. snow, blizzards and the cold
print("== snow, blizzards and the cold")
do {
    let probe = arena(4242)
    guard let tx = biomeX(probe, .tundra), let px = biomeX(probe, .plains) else { check(false, "found tundra and plains"); exit(1) }
    func cold(_ edit: (Game) -> Void, secs: Double = 40) -> (Double, Double, Game) {
        let g = arena(4242, at: tx)
        g.timeOfDay = 0.2
        force(g, .blizzard)
        g.weather.wind = 13 * g.weather.windDir
        g.weather.chill = 1
        edit(g)
        let hp0 = g.hp
        step(g, secs, 1.0 / 30.0)
        return (g.bodyCold, hp0 - g.hp, g)
    }
    let bare = cold({ _ in })
    let coat = cold({ g in g.inv.armor[3] = Stack(item: .gear(.winterCoat), count: 1) })
    let fire = cold({ g in g.world.set(Int(floor(g.pb.x)) + 2, 99, .campfire) })
    let heater = cold({ g in g.world.set(Int(floor(g.pb.x)) + 2, 99, .heater) })
    let indoors = cold({ g in
        let x = Int(floor(g.pb.x))
        for y in 94...99 { g.world.set(x - 4, y, .stone); g.world.set(x + 4, y, .stone) }
        for xx in (x - 4)...(x + 4) { g.world.set(xx, 94, .stone) }
    })
    check(bare.0 > 0.5, "in a tundra blizzard the cold gets into a player out in it (\(f2(bare.0)) after 40 s)")
    check(coat.0 < bare.0 * 0.6, "a winter coat keeps most of it out (\(f2(coat.0)))")
    check(fire.0 < 0.1 && heater.0 < 0.1, "a campfire or a heater close by keeps you warm (\(f2(fire.0)), \(f2(heater.0)))")
    check(indoors.0 < bare.0 * 0.4, "indoors it is much slower (\(f2(indoors.0)))")
    let long = cold({ _ in }, secs: 300)
    check(long.1 > 0 && long.2.hp >= 1, "freezing hurts in the end, but never kills outside hardcore (hp \(Int(long.2.hp)))")
    let safe = cold({ g in g.settings.weatherHurtsPlayer = false }, secs: 200)
    check(safe.1 == 0, "with player damage off the cold never hurts")
    // snow here, rain there, from the same weather
    let g = arena(4242, at: tx)
    force(g, .snowfall)
    let snowL = g.weatherAt(Double(tx), Double(g.gen.col(tx).h) - 2)
    let rainL = g.weatherAt(Double(px), Double(g.gen.col(px).h) - 2)
    check(snowL.snow && !rainL.snow, "the same storm falls as snow on the tundra and as rain on the plains")
    // snow lies on the ground, deep snow and ice make the footing slippery; snow boots grip
    simRun(g, 240, 0.5) { _ in g.updateGroundCells(0.5) }
    let cover = g.groundValue(g.pb.x, true)
    check(cover > 0.5, "snow builds up on the ground (\(f2(cover)) after 4 min of snowfall)")
    g.tick(1.0 / 60.0); g.warmthT = 0; g.tick(1.0 / 60.0)
    let slip = g.wxSlip
    g.inv.armor[4] = Stack(item: .gear(.snowBoots), count: 1)
    g.tick(1.0 / 60.0)
    check(slip > 0.2 && g.wxSlip < slip * 0.3, "deep snow is slippery (\(f2(slip))); snow boots grip (\(f2(g.wxSlip)))")
    // thaw: away from the cold, lying snow melts again (a temporary effect)
    g.debugTeleport(Double(px), Double(g.gen.col(px).h) - 1)
    g.weather.cells[Int(floor(Double(px) / groundCellW))] = GroundCell(wet: 0, snow: 1, t: g.weather.t)
    force(g, .clear)
    simRun(g, 400, 0.5) { _ in g.updateGroundCells(0.5) }
    check(g.groundValue(Double(px), true) < 0.1, "snow on warmer ground melts away (\(f2(g.groundValue(Double(px), true))) left)")
}

// ---------------------------------------------------------------- G. tornadoes
print("== tornadoes")
do {
    let g = arena(4242)
    // a little copse and a shed in its way
    let cx = Int(floor(g.pb.x))
    var natural: [(Int, Int, Tile)] = []
    for x in (cx - 150)...(cx + 150) {
        for y in 60..<140 {
            let t = g.world.tile(x, y)
            if windBreak(t) == 0 && t != .air && !t.liquid { natural.append((x, y, t)) }
        }
    }
    for k in [-30, -20, 12, 25] {
        for y in 95...99 { g.world.set(cx + k, y, .log) }
        for dx in -2...2 { for dy in 92...94 { g.world.set(cx + k + dx, dy, .leaves) } }
    }
    for x in (cx + 16)...(cx + 20) { g.world.set(x, 96, .planks) }
    g.world.set(cx + 18, 99, .stormBrick)
    g.debugForceWeather(.tornado)
    guard let e0 = g.weather.tornado else { check(false, "a tornado formed"); exit(1) }
    var warnedFor = 0.0
    var bannerWarn = false
    var maxV = 0.0, maxUp = 0.0
    var minHP = g.hp
    var forceStart = -1.0
    var brokenMax = 0
    var t = 0.0
    while t < 200 && g.weather.tornado != nil {
        g.tick(1.0 / 60.0)
        t += 1.0 / 60.0
        brokenMax = max(brokenMax, g.weather.tornado?.broken ?? 0)
        if let e = g.weather.tornado {
            if e.force <= 0 { warnedFor = t; if g.wxBanner.contains("TORNADO WARNING") { bannerWarn = true } }
            if e.force > 0 && forceStart < 0 { forceStart = t }
        }
        maxV = max(maxV, abs(g.pb.vx))
        maxUp = max(maxUp, -g.pb.vy)
        minHP = min(minHP, g.hp)
    }
    check(e0.warnDur >= 30 && warnedFor >= 29 && bannerWarn, "a tornado gives at least 30 s of warning before it touches down (\(Int(warnedFor)) s, with a TORNADO WARNING banner)")
    check(g.weather.tornado == nil && t < 200, "it crosses the land and ropes out (\(Int(t)) s in all)")
    check(maxV <= 16.01 && maxUp <= 16.01, "its pull is bounded: the player never moved faster than \(f1(maxV)) blocks/s across or \(f1(maxUp)) up")
    check(minHP > 0 && !g.dead, "a player caught in the open lives through it (lowest hp \(Int(minHP)))")
    var groundChanged = 0
    for (x, y, tl) in natural where g.world.tile(x, y) != tl { groundChanged += 1 }
    check(groundChanged == 0, "it never tears up the ground or stone (\(groundChanged) changed of \(natural.count))")
    check(g.world.tile(cx + 18, 99) == .stormBrick, "reinforced walls stand")
    var leavesLeft = 0
    for k in [-30, -20, 12, 25] { for dx in -2...2 { for dy in 92...94 where isLeafTile(g.world.tile(cx + k + dx, dy)) { leavesLeft += 1 } } }
    check(leavesLeft < 60, "it strips the trees in its path (\(60 - leavesLeft) of 60 leaves gone)")
    check(brokenMax > 0 && brokenMax <= 90, "it counts what it tears loose (\(brokenMax), limit 90 per tornado)")
    check(g.journal.storms?.contains { $0.kind == WeatherKind.tornado.rawValue } ?? false, "the journal records the tornado")
    // sheltered underground: no pull, no harm
    let u = arena(4242)
    let ux = Int(floor(u.pb.x))
    for x in (ux - 3)...(ux + 3) { for y in 100...106 { u.world.set(x, y, .air) } }
    for x in (ux - 3)...(ux + 3) { u.world.set(x, 107, .stone); for y in 95...99 { u.world.set(x, y, .stone) } }
    u.pb.y = 107
    u.debugForceWeather(.tornado)
    var uMax = 0.0
    let uhp = u.hp
    var ut = 0.0
    while ut < 200 && u.weather.tornado != nil {
        u.tick(1.0 / 60.0); ut += 1.0 / 60.0
        uMax = max(uMax, abs(u.wxAccelX) + abs(u.wxAccelY))
    }
    check(uMax == 0 && u.hp >= uhp, "underground the tornado passes overhead without touching the player")
    // block damage switch
    let n = arena(4242)
    n.settings.weatherHurtsBlocks = false
    let nx = Int(floor(n.pb.x))
    for k in [-20, 12] { for dx in -2...2 { for dy in 92...94 { n.world.set(nx + k + dx, dy, .leaves) } } }
    n.debugForceWeather(.tornado)
    var nt = 0.0
    while nt < 200 && n.weather.tornado != nil { n.tick(1.0 / 60.0); nt += 1.0 / 60.0 }
    var kept = 0
    for k in [-20, 12] { for dx in -2...2 { for dy in 92...94 where n.world.tile(nx + k + dx, dy) == .leaves { kept += 1 } } }
    check(kept == 30, "with block damage off a tornado leaves every block where it was")
}
do {
    // the tear limit
    let g = arena(4242)
    let cx = Int(floor(g.pb.x))
    for x in (cx - 40)...(cx + 40) { for y in 80...99 { g.world.set(x, y, .leaves) } }
    g.debugForceWeather(.tornado)
    var maxBroken = 0
    var t = 0.0
    while t < 200 && g.weather.tornado != nil { g.tick(1.0 / 30.0); t += 1.0 / 30.0; maxBroken = max(maxBroken, g.weather.tornado?.broken ?? 0) }
    check(maxBroken <= 90 && maxBroken > 20, "a tornado tears loose at most 90 blocks, even through a forest of leaves (\(maxBroken))")
    check(g.drops.count > 0, "what it tore loose is scattered as drops to pick up")
}

// ---------------------------------------------------------------- H. hurricanes
print("== hurricanes")
do {
    let probe = arena(4242)
    guard let (lx, side) = coastX(probe, inland: 30) else { check(false, "found a coast"); exit(1) }
    let g = arena(4242, at: lx)
    // the arena flattened this ground; put the shore back the way it was from the sea's edge
    g.debugTeleport(Double(lx) + 0.5, Double(g.world.surfaceY(lx)) - 0.1)
    let ctx = g.weatherContext()
    check(ctx.seaSide == side, "near the coast the sea is found (\(ctx.seaSide > 0 ? "east" : "west"), shore near x \(Int(ctx.coastX)))")
    g.debugForceWeather(.hurricane)
    guard let h0 = g.weather.hurricane else { check(false, "a hurricane formed"); exit(1) }
    var stages: [HurricaneStage] = []
    var windBefore = 0.0, windAfter = 0.0, eyeWind = 99.0, peakWind = 0.0
    var bannerApproach = false
    var maxSurge = 0
    var surgeRows: Set<Int> = []
    var t = 0.0
    var savedMid: Data? = nil
    while t < 600 && g.weather.hurricane != nil {
        g.tick(1.0 / 20.0)
        t += 1.0 / 20.0
        guard let h = g.weather.hurricane else { break }
        if stages.last != h.stage { stages.append(h.stage) }
        if h.stage == .approaching && g.wxBanner.contains("HURRICANE") { bannerApproach = true }
        if h.stage == .peak { windBefore = g.weather.wind; peakWind = max(peakWind, abs(g.weather.wind)) }
        if h.stage == .eye && h.t > h.stageDur * 0.7 { eyeWind = min(eyeWind, abs(g.weather.wind)) }
        if h.stage == .backside && h.t > h.stageDur * 0.5 { windAfter = g.weather.wind }
        maxSurge = max(maxSurge, g.weather.surge.count)
        for c in g.weather.surge { surgeRows.insert(c.y) }
        if savedMid == nil && g.weather.surge.count > 5 { savedMid = try? JSONEncoder().encode(g.makeSave()) }
    }
    check(stages == HurricaneStage.allCases, "it passes through every stage in order: \(stages.map { $0.name }.joined(separator: ", "))")
    check(h0.total >= 300, "it lasts a long while (\(Int(h0.total)) s)")
    check(bannerApproach, "it is announced while still approaching, before the damage starts")
    check(windBefore * windAfter < 0 && eyeWind < peakWind * 0.5, "the wind drops in the eye (\(f1(eyeWind)) vs \(f1(peakWind))) and comes back from the other side")
    check(maxSurge > 0 && surgeRows.isSubset(of: [WorldGen.sea - 1, WorldGen.sea - 2]), "the sea surges up the shore (\(maxSurge) spots flooded, only one or two rows above sea level)")
    check(g.weather.surge.isEmpty, "when it has passed every flooded spot is drained again")
    // a save in the middle of the surge still drains after loading
    if let d = savedMid, let s = try? JSONDecoder().decode(SaveData.self, from: d) {
        let h = Game.load(s, settings: Settings())
        let cells = h.weather.surge
        var ht = 0.0
        while ht < 700 && (h.weather.hurricane != nil || !h.weather.surge.isEmpty) { h.tick(1.0 / 20.0); ht += 1.0 / 20.0 }
        let wet = cells.filter { h.world.tile($0.x, $0.y) == .water }.count
        check(!cells.isEmpty && h.weather.surge.isEmpty && wet == 0, "saved mid-surge, the loaded world drains its \(cells.count) flooded spots when the storm passes")
    } else {
        check(false, "saved a world mid-surge")
    }
    check(g.journal.storms?.contains { $0.kind == WeatherKind.hurricane.rawValue } ?? false, "the journal records the hurricane")
    // sandbags hold the sea back
    let b = arena(4242, at: lx)
    b.debugTeleport(Double(lx) + 0.5, Double(b.world.surfaceY(lx)) - 0.1)
    b.debugForceWeather(.hurricane)
    if let h = b.weather.hurricane {
        let inland = h.side > 0 ? -1 : 1
        var sx = Int(floor(h.coastX)) - inland * 8
        var k = 0
        while k < 60 && b.world.tile(sx, WorldGen.sea) == .water { sx += inland; k += 1 }
        for y in (WorldGen.sea - 3)..<WorldGen.sea { b.world.set(sx, y, .sandbag) }
        var tt = 0.0
        var through = 0
        while tt < 600 && b.weather.hurricane != nil {
            b.tick(1.0 / 20.0); tt += 1.0 / 20.0
            through = max(through, b.weather.surge.filter { ($0.x - sx) * inland > 0 }.count)
        }
        check(through == 0, "a sandbag wall at the waterline keeps the surge off the land behind it")
    }
    // inland, no hurricane ever comes
    let i = arena(4242)
    var far = 0
    var xx = 0
    while xx < 80000 { if probe.seaNear(xx) == nil && probe.gen.col(xx).biome == .plains { far = xx; break }; xx += 64 }
    let inl = arena(4242, at: far)
    var hurricanes = 0
    var lastK = inl.weather.kind
    simRun(inl, 30 * 3600, 1.0) { _ in if inl.weather.kind != lastK { if inl.weather.kind == .hurricane { hurricanes += 1 }; lastK = inl.weather.kind } }
    check(far != 0 && hurricanes == 0, "far inland no hurricane comes in 30 hours")
    _ = i
}
do {
    // boats in rough water are tossed but never flung
    let probe = arena(4242)
    guard let (lx, _) = coastX(probe, inland: 30) else { exit(1) }
    let g = arena(4242, at: lx)
    var sx = lx
    while g.world.tile(sx, WorldGen.sea) != .water && sx < lx + 200 { sx += 1 }
    g.debugTeleport(Double(sx + 12) + 0.5, Double(WorldGen.sea) - 1)
    let v = Vehicle(id: g.newID(), first: .hull, x: 0, y: 0)
    v.parts.removeAll()
    for p in kitLayout(.boatKit) { v.parts[PartCell(dx: p.dx, dy: p.dy)] = p.p }
    v.recompute(keepAnchor: false)
    v.placeBox(left: Double(sx + 16), bottom: Double(WorldGen.sea) + 0.4)
    g.vehicles.append(v)
    g.debugForceWeather(.hurricane)
    var maxBV = 0.0
    for _ in 0..<1200 { g.tick(1.0 / 20.0); for v in g.vehicles where v.isBoat { maxBV = max(maxBV, abs(v.vx), abs(v.vy)) } }
    check(!g.vehicles.isEmpty && maxBV > 0.5 && maxBV <= 12.01, "a boat in a hurricane is tossed about, within limits (fastest \(f1(maxBV)) blocks/s)")
}

// ---------------------------------------------------------------- I. devices
print("== weather devices")
do {
    // every weather recipe can be made at its station
    let g = arena(4242)
    let px = Int(floor(g.pb.x))
    g.world.set(px + 1, 99, .workbench)
    g.world.set(px + 2, 99, .anvil)
    g.world.set(px - 1, 99, .tinkerBench)
    g.world.set(px - 2, 99, .furnace)
    var made: [String] = []
    var failed: [String] = []
    for r in RecipeBook.all where r.cat == .weather {
        g.inv = Inventory()
        for c in r.cost { _ = g.inv.add(c.item, c.n) }
        g.craft(r)
        if g.inv.total(r.out) >= r.outCount { made.append(r.out.name) } else { failed.append(r.out.name) }
    }
    check(failed.isEmpty && made.count >= 18, "all \(made.count) weather recipes craft at their stations (\(failed))")
    // placed the normal way, standing on the ground
    var placed: [String] = []
    var notPlaced: [String] = []
    let tiles: [Tile] = [.weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater, .sandbag, .shutterClosed, .stormBrick, .shingles]
    for t in tiles {
        let p = arena(4242)
        p.inv.slots[0] = Stack(item: .block(t), count: 3)
        p.setSel(0)
        p.aimX = p.pb.x + 2.5; p.aimY = 99.5; p.aimValid = true
        p.usePlaceBlock(t, 1.0 / 60.0)
        if p.world.tile(Int(floor(p.aimX)), 99) == t { placed.append(t.name) } else { notPlaced.append(t.name) }
    }
    check(notPlaced.isEmpty, "every weather block places like any other (\(placed.count) placed; \(notPlaced))")
    let fl = arena(4242)
    check(!fl.canPlaceAt(Int(floor(fl.pb.x)) + 2, 90, .lightningRod), "devices that stand need something under them (a rod can't hang in the air)")
}
do {
    // the station shows the simulation's own forecast; a Doppler station next to a charged turbine shows more
    let g = arena(4242)
    let px = Int(floor(g.pb.x))
    g.world.set(px + 2, 99, .weatherStation)
    g.tick(1.0 / 60.0)
    g.interact(Double(px + 2) + 0.5, 99.5)
    check(g.showWeather && g.stationAt?.t == .weatherStation, "tapping a station opens its screen")
    let lines = g.stationReport()
    let planNames = g.weather.plan.prefix(2).map { g.weatherLabel($0.kind, snow: g.wxHere.snow) }
    check(lines.first?.text == "Now: " + g.weatherLabel(g.weather.kind, snow: g.wxHere.snow) && planNames.allSatisfy { n in lines.contains { $0.text == n } }, "its screen shows the weather now and the next spells of the simulation's own plan")
    g.world.set(px + 2, 99, .dopplerStation)
    g.stationAt = DeviceSpot(x: px + 2, y: 99, t: .dopplerStation)
    let unpowered = g.stationReport()
    g.world.set(px + 6, 99, .windTurbine)
    g.weather.store[g.deviceKey(DeviceSpot(x: px + 6, y: 99, t: .windTurbine))] = 50
    let powered = g.stationReport()
    check(unpowered.contains { $0.text == "Radar unpowered" } && powered.count > unpowered.count - 1 && powered.contains { $0.sub.hasPrefix("In about") || $0.sub.hasPrefix("In under") }, "a Doppler station runs off a charged turbine and then gives exact times (\(powered.count) lines)")
    g.debugForceWeather(.tornado)
    g.stationAt = DeviceSpot(x: px + 2, y: 99, t: .dopplerStation)
    let tl = g.stationReport()
    check(tl.contains { $0.text.contains("TORNADO") && $0.text.contains("blocks") }, "it tracks a tornado: \"\(tl.first { $0.text.contains("TORNADO") }?.text ?? "-")\" / \(tl.first { $0.text.contains("TORNADO") }?.sub ?? "")")
    // the barometer reads the same pressure the simulation has
    let b = arena(4242)
    force(b, .clear); step(b, 3)
    let pClear = b.pressureNow()
    force(b, .thunderstorm); step(b, 25)
    let pStorm = b.pressureNow()
    check(pStorm < pClear - 10, "pressure falls under a storm (\(Int(pClear)) → \(Int(pStorm)) hPa)")
    b.weather.plan[0] = WeatherStep(kind: .hurricane, dur: 300)
    force(b, .overcast); b.weather.plan = [WeatherStep(kind: .hurricane, dur: 300)]
    step(b, 2)
    check(b.barometerReading().contains("storm likely"), "a barometer warns when the next spell is a bad one (\"\(b.barometerReading())\")")
}
do {
    // a rain barrel fills with the rain that falls on it, a covered one does not; its water grows crops
    let g = arena(4242)
    let px = Int(floor(g.pb.x))
    g.world.set(px + 3, 99, .rainBarrel)
    g.world.set(px - 3, 99, .rainBarrel)
    for x in (px - 5)...(px - 1) { g.world.set(x, 96, .planks) }
    force(g, .heavyRain)
    step(g, 60, 1.0 / 30.0)
    let open = g.weather.store[g.deviceKey(DeviceSpot(x: px + 3, y: 99, t: .rainBarrel))] ?? 0
    let covered = g.weather.store[g.deviceKey(DeviceSpot(x: px - 3, y: 99, t: .rainBarrel))] ?? 0
    check(open > 1 && open <= 8 && covered == 0, "an open barrel fills in the rain (\(f1(open)) of 8 in a minute), a covered one stays dry")
    g.interact(Double(px + 3) + 0.5, 99.5)
    check(g.inv.total(.gadget(.waterFlask)) == 1, "tapping a barrel with water in it fills a flask")
    g.world.set(px + 1, 100, .farmland); g.world.set(px + 1, 99, .wheat1)
    if let i = g.inv.slots.firstIndex(where: { $0?.item == .gadget(.waterFlask) }) { g.inv.swap(i, 0) }
    g.setSel(0)
    g.aimX = Double(px + 1) + 0.5; g.aimY = 99.5; g.aimValid = true
    g.useCD = 0
    g.useWaterFlask(true)
    check(g.world.tile(px + 1, 99) == .wheat2 && g.inv.total(.gadget(.waterFlask)) == 0, "pouring the flask on a young crop makes it grow a stage")
    // a turbine stores more in a gale than on a calm day
    let c = arena(4242)
    let cx = Int(floor(c.pb.x))
    c.world.set(cx + 4, 99, .windTurbine)
    force(c, .clear); step(c, 30, 1.0 / 30.0)
    let calm = c.weather.store[c.deviceKey(DeviceSpot(x: cx + 4, y: 99, t: .windTurbine))] ?? 0
    c.weather.store.removeAll()
    force(c, .windstorm); c.weather.wind = 14; step(c, 30, 1.0 / 30.0)
    let gale = c.weather.store[c.deviceKey(DeviceSpot(x: cx + 4, y: 99, t: .windTurbine))] ?? 0
    check(calm == 0 && gale > 20, "a turbine charges from the real wind: \(f1(calm))% in 30 calm seconds (below its cut-in speed), \(f1(gale))% in a windstorm")
    // a siren sounds for a tornado, not for a sunny day
    let s = arena(4242)
    let sx = Int(floor(s.pb.x))
    s.world.set(sx + 5, 99, .stormSiren)
    step(s, 1)
    let quiet = s.sirenLevel
    s.debugForceWeather(.tornado)
    step(s, 1.5)
    check(quiet == 0 && s.sirenLevel > 0.5, "a storm siren is silent in fair weather and sounds for a tornado (\(f2(s.sirenLevel)))")
    // shutters open and close; the vane reads the wind
    s.world.set(sx - 2, 99, .shutterClosed)
    s.interact(Double(sx - 2) + 0.5, 99.5)
    let opened = s.world.tile(sx - 2, 99)
    s.interact(Double(sx - 2) + 0.5, 99.5)
    check(opened == .shutterOpen && !opened.solid && s.world.tile(sx - 2, 99) == .shutterClosed && Tile.shutterClosed.solid, "a storm shutter opens and closes")
    // device state and blocks are saved
    let data = try! JSONEncoder().encode(g.makeSave())
    let back = Game.load(try! JSONDecoder().decode(SaveData.self, from: data), settings: Settings())
    back.world.loadAround(centerX: px, radius: 2)
    check(back.world.tile(px + 3, 99) == .rainBarrel && back.weather.store == g.weather.store, "weather blocks and what they hold are saved with the world")
}
do {
    // shelter: storm-proof blocks make a storm shelter; animals head for cover in a downpour
    let g = arena(4242)
    let x = Int(floor(g.pb.x))
    for y in 94...99 { g.world.set(x - 3, y, .stormBrick); g.world.set(x + 3, y, .stormBrick) }
    for xx in (x - 3)...(x + 3) { g.world.set(xx, 94, .stormBrick) }
    check(g.shelterAt(g.pb.x, g.pb.y) == 3, "reinforced walls and roof make a storm shelter")
    for y in 94...99 { g.world.set(x - 3, y, .planks); g.world.set(x + 3, y, .planks) }
    for xx in (x - 3)...(x + 3) { g.world.set(xx, 94, .planks) }
    check(g.shelterAt(g.pb.x, g.pb.y) == 2, "plank walls and roof are only indoors")
    let a = arena(4242)
    let ax = Int(floor(a.pb.x))
    for xx in (ax + 8)...(ax + 12) { a.world.set(xx, 94, .leaves) }
    let pig = a.addMob(.pig, a.pb.x + 3, 100); pig.persistent = true
    force(a, .heavyRain)
    a.weather.precip = 1
    step(a, 12, 1.0 / 30.0)
    check(!a.rainReaches(pig.b.x, pig.b.y, pig.b.h), "in a downpour a pig goes and stands under a tree (now at \(f1(pig.b.x - a.pb.x)) blocks)")
}

// ---------------------------------------------------------------- J. flat worlds
print("== flat worlds")
do {
    var o = WorldOptions(); o.flat = true
    let g = arena(4242, opts: o)
    var kinds: Set<WeatherKind> = []
    var rained = false
    simRun(g, 30 * 3600, 1.0) { _ in kinds.insert(g.weather.kind); if g.wxHere.precip > 0.2 { rained = true } }
    check(!kinds.contains(.hurricane) && rained && kinds.count >= 5, "a flat world has weather (\(kinds.count) kinds in 30 hours, rain included) but no hurricanes (it has no sea)")
    force(g, .thunderstorm)
    step(g, 20, 1.0 / 30.0)
    g.debugForceWeather(.tornado)
    var t = 0.0
    while t < 200 && g.weather.tornado != nil { g.tick(1.0 / 30.0); t += 1.0 / 30.0 }
    check(!g.dead && g.weather.tornado == nil, "storms and a tornado play out on flat ground")
}

// ---------------------------------------------------------------- K. cost
print("== cost")
do {
    func tickMs(_ g: Game, _ n: Int) -> Double {
        let t0 = perfNow()
        for _ in 0..<n { g.tick(1.0 / 60.0) }
        return (perfNow() - t0) * 1000 / Double(n)
    }
    func drawMs(_ g: Game, _ n: Int) -> Double {
        var ctx = GraphicsContext()
        let size = CGSize(width: 1100, height: 800)
        let t0 = perfNow()
        for _ in 0..<n { WorldRenderer.draw(&ctx, size, g) }
        return (perfNow() - t0) * 1000 / Double(n)
    }
    let off = arena(4242); off.settings.weatherOn = false; step(off, 1)
    let clear = arena(4242); force(clear, .clear); step(clear, 1)
    let storm = arena(4242); force(storm, .thunderstorm); storm.weather.thunder = 12; step(storm, 3)
    let hail = arena(4242); force(hail, .hailstorm); hail.weather.bigHail = true; step(hail, 3)
    let tor = arena(4242); tor.debugForceWeather(.tornado); step(tor, 45)
    let rows: [(String, Game)] = [("weather off", off), ("clear", clear), ("thunderstorm", storm), ("hailstorm", hail), ("tornado close by", tor)]
    var report: [String] = []
    var worstTick = 0.0, offTick = 0.0
    for (name, g) in rows {
        _ = tickMs(g, 30); _ = drawMs(g, 5)
        let tm = tickMs(g, 300)
        let dm = drawMs(g, 30)
        if name == "weather off" { offTick = tm }
        worstTick = max(worstTick, tm)
        report.append("\(name): tick \(String(format: "%.2f", tm)) ms, draw \(String(format: "%.2f", dm)) ms")
    }
    print(report.joined(separator: "\n"))
    check(worstTick < offTick + 2.0, "the worst weather adds \(String(format: "%.2f", worstTick - offTick)) ms to a game step (unoptimised test build)")
}

print("\(passes) passed, \(fails) failed")
print(fails == 0 ? "ALL WEATHER TESTS PASSED" : "SOME WEATHER TESTS FAILED")
