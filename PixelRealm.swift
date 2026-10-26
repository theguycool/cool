// PIXEL REALM v2 — a 2D pixel-art survival game for Swift Playgrounds (one file).
// Paste this whole file into MyApp.swift (delete ContentView.swift) and press Run.
// All art is generated in code. Sections: utilities, tiles, items, recipes, sprites, world generation,
// chunks, structures, the Umbral Realm, lighting, physics, mobs, vehicles, game logic, saving, UI.

import SwiftUI

// ===== p01_util =====
// ============================================================
// PIXEL REALM 2  -  expanded survival sandbox
// Single file. Paste it as the entire contents of MyApp.swift
// (delete ContentView.swift). iOS 16+ / macOS 13+.
// ============================================================

// MARK: - Utilities

// Fast conversions. Playgrounds builds in debug mode, where the generic integer
// initialisers (Int(UInt8), UInt64(Int)...) are slow function calls. These avoid them.
@inline(__always) func i8(_ v: UInt8) -> Int { return Int(Double(v)) }
// unsafeBitCast is transparent (inlined even in debug builds) and is exactly a bit reinterpretation
// between the two 64-bit types; the generic truncatingIfNeeded path was a large share of hashing time.
@inline(__always) func u64(_ v: Int) -> UInt64 { return unsafeBitCast(v, to: UInt64.self) }
@inline(__always) func iu64(_ v: UInt64) -> Int { return unsafeBitCast(v, to: Int.self) }

// MARK: - Performance counters (shown in the debug menu)

@inline(__always) func perfNow() -> Double { return Date().timeIntervalSinceReferenceDate }

final class Perf: @unchecked Sendable {
    static let shared: Perf = Perf()
    /// smoothed milliseconds
    var genMs: Double = 0
    var genWorstMs: Double = 0
    var chunksGenerated: Int = 0
    var aiMs: Double = 0
    var physMs: Double = 0
    var lightMs: Double = 0
    var renderMs: Double = 0
    var frameMs: Double = 0
    var frameWorstMs: Double = 0
    /// per-frame counts (the last finished frame)
    var moveCalls: Int = 0
    var boxChecks: Int = 0
    var damageQueries: Int = 0
    var lightFull: Int = 0
    var lightDyn: Int = 0
    var aiSkipped: Int = 0
    private var curMove: Int = 0
    private var curBox: Int = 0
    private var curDmg: Int = 0
    private var curSkip: Int = 0

    @inline(__always) func countMove() { curMove &+= 1 }
    @inline(__always) func countBox() { curBox &+= 1 }
    @inline(__always) func countDamage() { curDmg &+= 1 }
    @inline(__always) func countSkip() { curSkip &+= 1 }

    func endFrame() {
        moveCalls = curMove; boxChecks = curBox; damageQueries = curDmg; aiSkipped = curSkip
        curMove = 0; curBox = 0; curDmg = 0; curSkip = 0
    }

    func noteGen(_ secs: Double) {
        let ms: Double = secs * 1000.0
        chunksGenerated += 1
        genMs = genMs == 0 ? ms : genMs * 0.8 + ms * 0.2
        genWorstMs = max(genWorstMs * 0.999, ms)
    }

    static func smooth(_ old: Double, _ secs: Double) -> Double {
        return old * 0.9 + secs * 1000.0 * 0.1
    }
}

struct RNG {
    var s: UInt64
    init(_ seed: UInt64) { s = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        s = s &+ 0x9E3779B97F4A7C15
        var z: UInt64 = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func double() -> Double { Double(next() >> 11) / 9007199254740992.0 }
    mutating func int(_ n: Int) -> Int { return iu64(next() % u64(max(1, n))) }
}

func hashU(_ x: Int, _ y: Int, _ s: UInt64) -> UInt64 {
    var h: UInt64 = u64(x) &* 0x9E3779B97F4A7C15
    h ^= u64(y) &* 0xC2B2AE3D27D4EB4F
    h ^= s &* 0x165667B19E3779F9
    h ^= h >> 29
    h = h &* 0xBF58476D1CE4E5B9
    h ^= h >> 32
    h = h &* 0x94D049BB133111EB
    h ^= h >> 29
    return h
}

func hash2(_ x: Int, _ y: Int, _ s: UInt64) -> Double {
    return Double(iu64(hashU(x, y, s) >> 40)) / 16777216.0
}

func smooth(_ f: Double) -> Double { return f * f * (3.0 - 2.0 * f) }

func noise1(_ x: Double, _ s: UInt64) -> Double {
    let fl: Double = floor(x)
    let xi: Int = Int(fl)
    let u: Double = smooth(x - fl)
    let a: Double = hash2(xi, 7, s)
    let b: Double = hash2(xi + 1, 7, s)
    return a + (b - a) * u
}

func fbm1(_ x: Double, _ s: UInt64, _ oct: Int) -> Double {
    var sum: Double = 0
    var amp: Double = 1
    var freq: Double = 1
    var norm: Double = 0
    for i in 0..<oct {
        sum += noise1(x * freq, s &+ u64(i) &* 101) * amp
        norm += amp
        amp *= 0.5
        freq *= 2.0
    }
    return sum / norm
}

func vnoise(_ x: Double, _ y: Double, _ s: UInt64) -> Double {
    let fx0: Double = floor(x)
    let fy0: Double = floor(y)
    let xi: Int = Int(fx0)
    let yi: Int = Int(fy0)
    let u: Double = smooth(x - fx0)
    let v: Double = smooth(y - fy0)
    let a: Double = hash2(xi, yi, s)
    let b: Double = hash2(xi + 1, yi, s)
    let c: Double = hash2(xi, yi + 1, s)
    let d: Double = hash2(xi + 1, yi + 1, s)
    let top: Double = a + (b - a) * u
    let bot: Double = c + (d - c) * u
    return top + (bot - top) * v
}

/// Value noise with the four lattice corners cached. Gives exactly the same values as
/// vnoise() but skips the hashing while consecutive samples stay inside one lattice cell
/// (world generation walks down columns, so most samples do).
struct VNoiseCache {
    let s: UInt64
    var cx: Int = Int.min
    var cy: Int = Int.min
    var a: Double = 0
    var b: Double = 0
    var c: Double = 0
    var d: Double = 0
    /// smallest / largest corner of the current cell: the interpolated value always lies between
    /// them, which lets callers skip work exactly (no change to the generated world)
    var lo: Double = 0
    var hi: Double = 0
    init(_ seed: UInt64) { s = seed }

    @inline(__always) mutating func load(_ xi: Int, _ yi: Int) {
        if xi != cx || yi != cy {
            cx = xi
            cy = yi
            a = hash2(xi, yi, s)
            b = hash2(xi + 1, yi, s)
            c = hash2(xi, yi + 1, s)
            d = hash2(xi + 1, yi + 1, s)
            lo = min(min(a, b), min(c, d))
            hi = max(max(a, b), max(c, d))
        }
    }

    /// Loads the cell containing (x, y) and returns its corner range
    mutating func bounds(_ x: Double, _ y: Double) -> (Double, Double) {
        load(Int(floor(x)), Int(floor(y)))
        return (lo, hi)
    }

    mutating func at(_ x: Double, _ y: Double) -> Double {
        let fx0: Double = floor(x)
        let fy0: Double = floor(y)
        let xi: Int = Int(fx0)
        let yi: Int = Int(fy0)
        load(xi, yi)
        let u: Double = smooth(x - fx0)
        let v: Double = smooth(y - fy0)
        let top: Double = a + (b - a) * u
        let bot: Double = c + (d - c) * u
        return top + (bot - top) * v
    }
}

func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return max(lo, min(hi, v)) }
func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double { return a + (b - a) * t }
func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { return max(lo, min(hi, v)) }

func floorDiv(_ a: Int, _ b: Int) -> Int {
    var q: Int = a / b
    if (a % b != 0) && ((a < 0) != (b < 0)) { q -= 1 }
    return q
}

func floorMod(_ a: Int, _ b: Int) -> Int {
    let m: Int = a % b
    return m < 0 ? m + b : m
}

func mixRGB(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    let tt: Double = clampD(t, 0, 1)
    func ch(_ s: UInt32) -> UInt32 {
        let ia: UInt32 = (a >> s) & 255
        let ib: UInt32 = (b >> s) & 255
        let ca: Double = Double(ia)
        let cb: Double = Double(ib)
        let d: Double = cb - ca
        let v: Double = ca + d * tt
        return UInt32(v)
    }
    return (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

func shadeRGB(_ c: UInt32, _ f: Double) -> UInt32 {
    func ch(_ s: UInt32) -> UInt32 {
        let ic: UInt32 = (c >> s) & 255
        let base: Double = Double(ic)
        let v: Double = base * f
        let cl: Double = clampD(v, 0, 255)
        return UInt32(cl)
    }
    return (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

// MARK: - Pixel buffers (platform neutral)

struct PixelBuf {
    var w: Int
    var h: Int
    var px: [UInt32]

    init(w: Int, h: Int) {
        self.w = w
        self.h = h
        self.px = [UInt32](repeating: 0, count: w * h)
    }

    func get(_ x: Int, _ y: Int) -> UInt32 {
        if x < 0 || y < 0 || x >= w || y >= h { return 0 }
        return px[y * w + x]
    }

    mutating func set(_ x: Int, _ y: Int, _ rgb: UInt32) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        px[y * w + x] = 0xFF000000 | rgb
    }

    mutating func clear(_ x: Int, _ y: Int) {
        if x < 0 || y < 0 || x >= w || y >= h { return }
        px[y * w + x] = 0
    }

    mutating func rect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ rgb: UInt32) {
        if rw <= 0 || rh <= 0 { return }
        for yy in y..<(y + rh) {
            for xx in x..<(x + rw) { set(xx, yy, rgb) }
        }
    }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rgb: UInt32) {
        let x0: Int = Int(floor(cx - rx)) - 1
        let x1: Int = Int(ceil(cx + rx)) + 1
        let y0: Int = Int(floor(cy - ry)) - 1
        let y1: Int = Int(ceil(cy + ry)) + 1
        for yy in y0...y1 {
            for xx in x0...x1 {
                let dx: Double = (Double(xx) + 0.5 - cx) / rx
                let dy: Double = (Double(yy) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 { set(xx, yy, rgb) }
            }
        }
    }

    mutating func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ rgb: UInt32) {
        let n: Int = max(abs(x1 - x0), abs(y1 - y0))
        if n == 0 { set(x0, y0, rgb); return }
        for i in 0...n {
            let t: Double = Double(i) / Double(n)
            let xx: Int = Int((Double(x0) + Double(x1 - x0) * t).rounded())
            let yy: Int = Int((Double(y0) + Double(y1 - y0) * t).rounded())
            set(xx, yy, rgb)
        }
    }

    /// Fur / stone style brightness jitter
    mutating func texture(_ seed: UInt64, _ amount: Double) {
        for yy in 0..<h {
            for xx in 0..<w {
                let c: UInt32 = px[yy * w + xx]
                if (c >> 24) == 0 { continue }
                let j: Double = 1.0 + (hash2(xx, yy, seed) - 0.5) * amount
                let rgb: UInt32 = shadeRGB(c & 0xFFFFFF, j)
                px[yy * w + xx] = 0xFF000000 | rgb
            }
        }
    }

    /// Darken the lower part for a lit-from-above look
    mutating func underShade(_ f: Double) {
        for yy in 0..<h {
            let t: Double = Double(yy) / Double(max(1, h - 1))
            if t < 0.55 { continue }
            for xx in 0..<w {
                let c: UInt32 = px[yy * w + xx]
                if (c >> 24) == 0 { continue }
                px[yy * w + xx] = 0xFF000000 | shadeRGB(c & 0xFFFFFF, f)
            }
        }
    }

    /// 1px outline around opaque pixels (needs transparent margin)
    mutating func outline(_ rgb: UInt32) {
        var out: [UInt32] = px
        for yy in 0..<h {
            for xx in 0..<w {
                if (px[yy * w + xx] >> 24) != 0 { continue }
                var near: Bool = false
                if xx > 0 && (px[yy * w + xx - 1] >> 24) != 0 { near = true }
                if xx < w - 1 && (px[yy * w + xx + 1] >> 24) != 0 { near = true }
                if yy > 0 && (px[(yy - 1) * w + xx] >> 24) != 0 { near = true }
                if yy < h - 1 && (px[(yy + 1) * w + xx] >> 24) != 0 { near = true }
                if near { out[yy * w + xx] = 0xFF000000 | rgb }
            }
        }
        px = out
    }

    func flipped() -> PixelBuf {
        var o = PixelBuf(w: w, h: h)
        for yy in 0..<h {
            for xx in 0..<w { o.px[yy * w + (w - 1 - xx)] = px[yy * w + xx] }
        }
        return o
    }

    /// Draw another buffer on top (alpha is on/off)
    mutating func blit(_ other: PixelBuf, _ ox: Int, _ oy: Int) {
        for yy in 0..<other.h {
            for xx in 0..<other.w {
                let c: UInt32 = other.px[yy * other.w + xx]
                if (c >> 24) == 0 { continue }
                let tx: Int = ox + xx
                let ty: Int = oy + yy
                if tx < 0 || ty < 0 || tx >= w || ty >= h { continue }
                px[ty * w + tx] = c
            }
        }
    }

    func tinted(_ rgb: UInt32, _ amount: Double) -> PixelBuf {
        var o = self
        for i in 0..<o.px.count {
            let c: UInt32 = o.px[i]
            if (c >> 24) == 0 { continue }
            o.px[i] = 0xFF000000 | mixRGB(c & 0xFFFFFF, rgb, amount)
        }
        return o
    }

    func whiteFlash() -> PixelBuf { return tinted(0xFFFFFF, 0.75) }
}

/// Build a buffer from rows of characters and a palette.
func bufFromRows(_ rows: [String], _ pal: [Character: UInt32]) -> PixelBuf {
    var wmax: Int = 1
    for r in rows { wmax = max(wmax, r.count) }
    var b = PixelBuf(w: wmax, h: rows.count)
    for (y, row) in rows.enumerated() {
        let chars: [Character] = Array(row)
        for x in 0..<chars.count {
            if let c = pal[chars[x]] { b.set(x, y, c) }
        }
    }
    return b
}

// ===== p02_tiles =====

// MARK: - Tiles

enum TStyle: Int {
    case noise, grassTop, log, leaves, planks, bricks, ore, water, glass, custom, lava, snow, ice, mud, cactus, crystal, farmland, sandstone, ash
}

struct TileDef {
    var name: String
    var hard: Double = 1.0
    var tier: Int = 0
    var solid: Bool = true
    var opaque: Bool = true
    var light: Int = 0
    var liquid: Bool = false
    var platform: Bool = false
    var plant: Bool = false
    var hurt: Bool = false
    var style: TStyle = .noise
    var colors: [UInt32] = [0x8A8A8A, 0x7A7A7A, 0x9A9A9A, 0x6A6A6A, 0x8A8A8A]
    var drop: Item? = nil
    var noDrop: Bool = false
}

enum Tile: UInt8, CaseIterable, Codable {
    case air, grass, dirt, stone, sand, log, leaves, water
    case coal, copper, iron, gold, diamond, mythril
    case planks, glass, brick, bedrock
    case snow, ice, sandstone, cactus, jungleLeaves, mud, dryGrass, jungleGrass, mossGrass
    case slate, deepRock, lava, obsidian
    case tallGrass, flowerR, flowerY, deadBush, mushroom, reed
    case workbench, furnace, campfire, torch, lantern, chest, platform
    case farmland, wheat1, wheat2, wheat3, carrot1, carrot2, carrot3
    case crackedBrick, mossBrick, spikes, fossil
    case ashStone, emberOre, voidOre, glowCrystal
    case portalFrame, portalOff, portalOn
    case jungleLog, palmLog, cobweb, hay
    case doorClosed, doorOpen

    static let defTable: [TileDef] = Tile.allCases.map { Tile.makeDef($0) }
    static let solidTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid }
    static let opaqueTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).opaque }
    static let lightTable: [Int] = Tile.allCases.map { Tile.makeDef($0).light }
    static let liquidTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).liquid }
    static let hurtTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).hurt }
    static let platformTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).platform }
    static let plantTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).plant }
    static let hardTable: [Double] = Tile.allCases.map { Tile.makeDef($0).hard }
    static let tierTable: [Int] = Tile.allCases.map { Tile.makeDef($0).tier }

    var idx: Int { return i8(rawValue) }
    var def: TileDef { return Tile.defTable[i8(rawValue)] }
    var solid: Bool { return Tile.solidTable[i8(rawValue)] }
    var opaque: Bool { return Tile.opaqueTable[i8(rawValue)] }
    var light: Int { return Tile.lightTable[i8(rawValue)] }
    var liquid: Bool { return Tile.liquidTable[i8(rawValue)] }
    var name: String { return def.name }
    var isPlant: Bool { return Tile.plantTable[i8(rawValue)] }
    var hurts: Bool { return Tile.hurtTable[i8(rawValue)] }
    var isPlatform: Bool { return Tile.platformTable[i8(rawValue)] }
    var hardness: Double { return Tile.hardTable[i8(rawValue)] }

    static func make(_ raw: UInt8) -> Tile { return Tile(rawValue: raw) ?? .air }

    static func makeDef(_ t: Tile) -> TileDef {
        let stoneCols: [UInt32] = [0x8A8A8A, 0x7A7A7A, 0x9A9A9A, 0x6A6A6A, 0x8A8A8A]
        switch t {
        case .air:
            return TileDef(name: "Air", hard: 0, solid: false, opaque: false)
        case .grass:
            return TileDef(name: "Grass", hard: 0.5, style: .grassTop, colors: [0x5DAA3A, 0x4B9230, 0x7A5230, 0x5A3A1E, 0x8A6038], drop: .block(.dirt))
        case .dirt:
            return TileDef(name: "Dirt", hard: 0.4, colors: [0x7A5230, 0x6B4626, 0x8A6038, 0x5A3A1E, 0x7A5230])
        case .stone:
            return TileDef(name: "Stone", hard: 1.2, tier: 1, colors: stoneCols)
        case .sand:
            return TileDef(name: "Sand", hard: 0.4, colors: [0xE0D08A, 0xD2C078, 0xEBDDA0, 0xC4B268, 0xE0D08A])
        case .log:
            return TileDef(name: "Log", hard: 0.9, opaque: true, style: .log, colors: [0x6B4A2A, 0x5A3C20, 0x7C5733, 0x4A3018, 0x6B4A2A])
        case .leaves:
            // canopies are one-way: walk and shoot through them, land on top of them
            return TileDef(name: "Leaves", hard: 0.2, solid: false, opaque: false, platform: true, style: .leaves, colors: [0x3E8A2E, 0x2F7324, 0x56A83F, 0x225C1A, 0x3E8A2E], noDrop: true)
        case .water:
            return TileDef(name: "Water", hard: 0, solid: false, opaque: false, liquid: true, style: .water, colors: [0x3B7BE0, 0x4F90F0, 0x2E64C0, 0x8DBBFF, 0x3B7BE0], noDrop: true)
        case .coal:
            return TileDef(name: "Coal Ore", hard: 1.6, tier: 1, style: .ore, colors: stoneCols + [0x1E1E1E, 0x333333], drop: .mat(.coal))
        case .copper:
            return TileDef(name: "Copper Ore", hard: 1.8, tier: 2, style: .ore, colors: stoneCols + [0xD2793A, 0xF0A060], drop: .mat(.copperOre))
        case .iron:
            return TileDef(name: "Iron Ore", hard: 2.2, tier: 3, style: .ore, colors: stoneCols + [0xD8A878, 0xB88858], drop: .mat(.ironOre))
        case .gold:
            return TileDef(name: "Gold Ore", hard: 2.6, tier: 4, light: 2, style: .ore, colors: stoneCols + [0xF5D142, 0xFFE98A], drop: .mat(.goldOre))
        case .diamond:
            return TileDef(name: "Diamond Ore", hard: 3.2, tier: 5, light: 4, style: .ore, colors: stoneCols + [0x4FE3E8, 0xB8FBFF], drop: .mat(.diamond))
        case .mythril:
            return TileDef(name: "Mythril Ore", hard: 4.0, tier: 6, light: 5, style: .ore, colors: stoneCols + [0x6A5CFF, 0xB3A8FF], drop: .mat(.mythrilOre))
        case .planks:
            return TileDef(name: "Planks", hard: 0.8, style: .planks, colors: [0xB98A4E, 0x8F6732, 0xC89B5E, 0x7A5628, 0xB98A4E])
        case .glass:
            return TileDef(name: "Glass", hard: 0.3, opaque: false, style: .glass, colors: [0xCFEFFF, 0xFFFFFF, 0x9CCBE0, 0xCFEFFF, 0xCFEFFF])
        case .brick:
            return TileDef(name: "Stone Brick", hard: 1.5, tier: 1, style: .bricks, colors: [0xA64B3C, 0x8A8A8A, 0xB85A48, 0x8E3B2E, 0xA64B3C])
        case .bedrock:
            return TileDef(name: "Bedrock", hard: 9999, tier: 99, colors: [0x3A3A3A, 0x2A2A2A, 0x4A4A4A, 0x1A1A1A, 0x3A3A3A], noDrop: true)
        case .snow:
            return TileDef(name: "Snow", hard: 0.3, style: .snow, colors: [0xF2F8FF, 0xDCEBFA, 0xFFFFFF, 0xC4D8EE, 0xF2F8FF])
        case .ice:
            return TileDef(name: "Ice", hard: 0.5, opaque: false, style: .ice, colors: [0xAEDCF5, 0x8CC8EC, 0xD6F0FF, 0x78B4DC, 0xAEDCF5])
        case .sandstone:
            return TileDef(name: "Sandstone", hard: 1.0, tier: 1, style: .sandstone, colors: [0xD2B574, 0xC4A562, 0xDEC488, 0xB89850, 0xD2B574])
        case .cactus:
            return TileDef(name: "Cactus", hard: 0.4, hurt: true, style: .cactus, colors: [0x3F8F3F, 0x2F7A2F, 0x58AE58, 0x1F5F1F, 0x3F8F3F])
        case .jungleLeaves:
            return TileDef(name: "Jungle Leaves", hard: 0.2, solid: false, opaque: false, platform: true, style: .leaves, colors: [0x1F8A3A, 0x146B2A, 0x32AA4E, 0x0E5420, 0x1F8A3A], noDrop: true)
        case .mud:
            return TileDef(name: "Mud", hard: 0.5, style: .mud, colors: [0x4E3A2A, 0x3E2E20, 0x5E4834, 0x30241A, 0x4E3A2A])
        case .dryGrass:
            return TileDef(name: "Dry Grass", hard: 0.5, style: .grassTop, colors: [0xBDB35A, 0xA39A48, 0x7A5230, 0x5A3A1E, 0x8A6038], drop: .block(.dirt))
        case .jungleGrass:
            return TileDef(name: "Jungle Grass", hard: 0.5, style: .grassTop, colors: [0x2E9E3A, 0x1F8A2C, 0x4E3A2A, 0x3E2E20, 0x5E4834], drop: .block(.mud))
        case .mossGrass:
            return TileDef(name: "Moss", hard: 0.5, style: .grassTop, colors: [0x6E8A3A, 0x5A7430, 0x4E3A2A, 0x3E2E20, 0x5E4834], drop: .block(.mud))
        case .slate:
            return TileDef(name: "Slate", hard: 1.7, tier: 1, colors: [0x5E6678, 0x4F5666, 0x6D7688, 0x40475A, 0x5E6678])
        case .deepRock:
            return TileDef(name: "Deep Rock", hard: 2.6, tier: 3, colors: [0x3E3846, 0x34303C, 0x4A4452, 0x2A2632, 0x3E3846])
        case .lava:
            return TileDef(name: "Lava", hard: 0, solid: false, opaque: false, light: 14, liquid: true, hurt: true, style: .lava, colors: [0xE8580C, 0xFF8A1E, 0xC03A06, 0xFFD060, 0xE8580C], noDrop: true)
        case .obsidian:
            return TileDef(name: "Obsidian", hard: 4.2, tier: 5, colors: [0x241838, 0x1A1028, 0x34244E, 0x120A1E, 0x241838])
        case .tallGrass:
            return TileDef(name: "Tall Grass", hard: 0, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
        case .flowerR:
            return TileDef(name: "Red Flower", hard: 0, solid: false, opaque: false, plant: true, style: .custom)
        case .flowerY:
            return TileDef(name: "Yellow Flower", hard: 0, solid: false, opaque: false, plant: true, style: .custom)
        case .deadBush:
            return TileDef(name: "Dead Bush", hard: 0, solid: false, opaque: false, plant: true, style: .custom, drop: .mat(.stick))
        case .mushroom:
            return TileDef(name: "Glow Mushroom", hard: 0, solid: false, opaque: false, light: 6, plant: true, style: .custom)
        case .reed:
            return TileDef(name: "Reed", hard: 0, solid: false, opaque: false, plant: true, style: .custom, drop: .mat(.stick))
        case .workbench:
            return TileDef(name: "Workbench", hard: 0.6, solid: false, opaque: false, style: .custom)
        case .furnace:
            return TileDef(name: "Furnace", hard: 1.0, tier: 1, solid: false, opaque: false, light: 7, style: .custom)
        case .campfire:
            return TileDef(name: "Campfire", hard: 0.5, solid: false, opaque: false, light: 13, hurt: false, style: .custom)
        case .torch:
            return TileDef(name: "Torch", hard: 0, solid: false, opaque: false, light: 12, plant: true, style: .custom)
        case .lantern:
            return TileDef(name: "Lantern", hard: 0.2, solid: false, opaque: false, light: 14, plant: true, style: .custom)
        case .chest:
            return TileDef(name: "Chest", hard: 0.8, solid: false, opaque: false, style: .custom, noDrop: false)
        case .platform:
            return TileDef(name: "Platform", hard: 0.3, solid: false, opaque: false, platform: true, style: .custom)
        case .farmland:
            return TileDef(name: "Farmland", hard: 0.4, style: .farmland, colors: [0x5A3A1E, 0x4A2E16, 0x6B4626, 0x3A220E, 0x5A3A1E], drop: .block(.dirt))
        case .wheat1, .wheat2, .wheat3:
            return TileDef(name: "Wheat", hard: 0, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
        case .carrot1, .carrot2, .carrot3:
            return TileDef(name: "Carrots", hard: 0, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
        case .crackedBrick:
            return TileDef(name: "Cracked Brick", hard: 1.0, tier: 1, style: .bricks, colors: [0x8E7A68, 0x6A5A4C, 0xA08C78, 0x5A4A3C, 0x8E7A68])
        case .mossBrick:
            return TileDef(name: "Mossy Brick", hard: 1.4, tier: 1, style: .bricks, colors: [0x6E8A5A, 0x4C5E3E, 0x82A06C, 0x3C4C30, 0x6E8A5A])
        case .spikes:
            return TileDef(name: "Spikes", hard: 0.8, tier: 1, solid: false, opaque: false, hurt: true, style: .custom)
        case .fossil:
            return TileDef(name: "Fossil Block", hard: 1.5, tier: 1, style: .custom, drop: .mat(.bone))
        case .ashStone:
            return TileDef(name: "Ashstone", hard: 2.2, tier: 4, style: .ash, colors: [0x4A3A48, 0x3C2E3A, 0x5A4858, 0x2E222C, 0x4A3A48])
        case .emberOre:
            return TileDef(name: "Ember Ore", hard: 3.4, tier: 7, light: 7, style: .ore, colors: [0x4A3A48, 0x3C2E3A, 0x5A4858, 0x2E222C, 0x4A3A48, 0xFF7A1E, 0xFFC050], drop: .mat(.emberOre))
        case .voidOre:
            return TileDef(name: "Voidium Ore", hard: 4.6, tier: 8, light: 8, style: .ore, colors: [0x4A3A48, 0x3C2E3A, 0x5A4858, 0x2E222C, 0x4A3A48, 0xB04CFF, 0xE8A8FF], drop: .mat(.voidOre))
        case .glowCrystal:
            return TileDef(name: "Glow Crystal", hard: 1.2, tier: 4, opaque: false, light: 11, style: .crystal, colors: [0x7A4CFF, 0xB38CFF, 0x4E2AC0, 0xE6D8FF, 0x7A4CFF])
        case .portalFrame:
            return TileDef(name: "Portal Frame", hard: 99999, tier: 99, light: 4, style: .bricks, colors: [0x2A1A40, 0x6A3CC0, 0x3A2858, 0x1A0E2C, 0x2A1A40], noDrop: true)
        case .portalOff:
            return TileDef(name: "Dormant Portal", hard: 99999, tier: 99, solid: false, opaque: false, style: .custom, noDrop: true)
        case .portalOn:
            return TileDef(name: "Portal", hard: 99999, tier: 99, solid: false, opaque: false, light: 13, style: .custom, noDrop: true)
        case .jungleLog:
            return TileDef(name: "Jungle Log", hard: 1.0, style: .log, colors: [0x5A4A2A, 0x4A3A20, 0x6C5C34, 0x3A2C14, 0x5A4A2A])
        case .palmLog:
            return TileDef(name: "Palm Log", hard: 0.8, style: .log, colors: [0x9A7A4A, 0x826238, 0xB08C58, 0x6A4E2A, 0x9A7A4A])
        case .cobweb:
            return TileDef(name: "Cobweb", hard: 0.1, solid: false, opaque: false, plant: true, style: .custom, noDrop: true)
        case .hay:
            return TileDef(name: "Hay Bale", hard: 0.4, style: .noise, colors: [0xD8B83A, 0xBE9E2A, 0xE8CC52, 0xA88820, 0xD8B83A])
        case .doorClosed:
            return TileDef(name: "Wooden Door", hard: 0.6, solid: true, opaque: false, style: .custom, colors: [0x8F6732], drop: .block(.doorClosed))
        case .doorOpen:
            return TileDef(name: "Open Door", hard: 0.6, solid: false, opaque: false, style: .custom, colors: [0x8F6732], drop: .block(.doorClosed))
        }
    }
}

// MARK: - Tile art

func customTileRows(_ t: Tile) -> ([String], [Character: UInt32])? {
    switch t {
    case .torch:
        return ([".......", "...y...", "..yoy..", "...r...", "...b...", "...b...", "...b...", "...b..."].map { String($0) },
                ["y": 0xFFE680, "o": 0xFFA030, "r": 0xE05818, "b": 0x8A5A2A])
    case .lantern:
        return (["...kk...", "..kyyk..", ".kyYYyk.", ".kyYYyk.", ".kyyyyk.", "..kkkk.."],
                ["k": 0x3A3A3A, "y": 0xFFC84A, "Y": 0xFFF2B0])
    case .campfire:
        return (["........", "...y....", "..yoy.y.", "..oryo..", ".bbrobb.", "bbbbbbbb", "ssbbbbss", "........"],
                ["y": 0xFFE680, "o": 0xFFA030, "r": 0xE05818, "b": 0x6B4A2A, "s": 0x808080])
    case .workbench:
        return (["........", "........", "tttttttt", "bbbbbbbb", "b.b..b.b", "b.b..b.b", "b.b..b.b", "b.b..b.b"],
                ["t": 0xC89B5E, "b": 0x8F6732])
    case .furnace:
        return (["ssssssss", "sSSSSSSs", "sSkkkkSs", "sSkoOkSs", "sSkOykSs", "sSkkkkSs", "sSSSSSSs", "ssssssss"],
                ["s": 0x6A6A6A, "S": 0x8A8A8A, "k": 0x2A2020, "o": 0xE05818, "O": 0xFFA030, "y": 0xFFE680])
    case .chest:
        return (["........", "........", "wwwwwwww", "wddddddw", "wwwgwwww", "wddddddw", "wddddddw", "wwwwwwww"],
                ["w": 0x8F6732, "d": 0xB98A4E, "g": 0xF5D142])
    case .platform:
        return (["........", "........", "........", "........", "........", "........", "pppppppp", "qqqqqqqq"],
                ["p": 0xC89B5E, "q": 0x8F6732])
    case .tallGrass:
        return (["........", "........", "........", ".g...g..", ".g.g.g.g", "gg.g.ggg", "gggggggg", "gggggggg"],
                ["g": 0x4B9A30])
    case .flowerR:
        return (["........", "........", "...rr...", "..rYr...", "...rr...", "....g...", "....g...", "...ggg.."],
                ["r": 0xE63A3A, "Y": 0xFFE060, "g": 0x3E8A2E])
    case .flowerY:
        return (["........", "........", "..yy....", ".yOyy...", "..yy....", "...g....", "...g....", "..ggg..."],
                ["y": 0xFFE040, "O": 0xE08A20, "g": 0x3E8A2E])
    case .deadBush:
        return (["........", "........", ".b...b..", "..b.b...", "...b..b.", "..bbbb..", "...b....", "...b...."],
                ["b": 0x8A6A3A])
    case .mushroom:
        return (["........", "........", "..cccc..", ".cCcccc.", ".cccCcc.", "...ww...", "...ww...", "...ww..."],
                ["c": 0x3AC8C8, "C": 0xA8FFFF, "w": 0xD8E8F0])
    case .reed:
        return (["...b....", "...b..b.", "...g..b.", "...g..g.", ".g.g..g.", ".g.g.gg.", ".g.ggg..", "..gggg.."],
                ["g": 0x6E8A3A, "b": 0x6B4A2A])
    case .wheat1:
        return (["........", "........", "........", "........", "........", "g.g..g.g", "g.g..g.g", "gggggggg"],
                ["g": 0x7AB83A])
    case .wheat2:
        return (["........", "........", "........", "y.y..y.y", "g.g..g.g", "g.g..g.g", "g.g..g.g", "gggggggg"],
                ["g": 0x8AB03A, "y": 0xD8C050])
    case .wheat3:
        return (["y.y..y.y", "yyy..yyy", "yyy..yyy", "y.y..y.y", "g.g..g.g", "g.g..g.g", "g.g..g.g", "gggggggg"],
                ["g": 0xB0A030, "y": 0xE8C850])
    case .carrot1:
        return (["........", "........", "........", "........", "........", "..g..g..", ".ggggg..", "gggggggg"],
                ["g": 0x4EA83A])
    case .carrot2:
        return (["........", "........", "........", "..g..g..", ".ggggg..", ".gggggg.", "gggggggg", "gggggggg"],
                ["g": 0x4EB83A])
    case .carrot3:
        return (["........", "..g..g..", ".ggggg..", ".gggggg.", "ggoggogg", "gggggggg", "gggoggog", "gggggggg"],
                ["g": 0x4EB83A, "o": 0xF08A1E])
    case .spikes:
        return (["........", "........", "........", "...s....", "..sss.s.", ".sssssss", "ssssssss", "dddddddd"],
                ["s": 0xC8C8D0, "d": 0x5A5A5A])
    case .fossil:
        return (["ssssssss", "sbbsssss", "ssbbssss", "sssbbbbs", "ssssbssb", "sbbbssbs", "ssbssbss", "ssssssss"],
                ["s": 0x8A8A8A, "b": 0xE8E0C8])
    case .portalOff:
        return (["pppppppp", "pqqqqqqp", "pqqqqqqp", "pqqqqqqp", "pqqqqqqp", "pqqqqqqp", "pqqqqqqp", "pppppppp"],
                ["p": 0x2A1A40, "q": 0x14091E])
    case .portalOn:
        return (["mmmmmmmm", "mMMMMMMm", "mMppppMm", "mMpPPpMm", "mMpPPpMm", "mMppppMm", "mMMMMMMm", "mmmmmmmm"],
                ["m": 0x7A3CE0, "M": 0xA868FF, "p": 0xD8A8FF, "P": 0xFFFFFF])
    case .doorClosed:
        return (["dDDDDDDd", "dDdddDDd", "dDdddDDd", "dDDDDDDd", "dDDDDgDd", "dDdddDDd", "dDdddDDd", "dDDDDDDd"],
                ["d": 0x6A4A22, "D": 0xA97B45, "g": 0xE8C040])
    case .doorOpen:
        return (["dD......", "dD......", "dD......", "dD......", "dD......", "dD......", "dD......", "dD......"],
                ["d": 0x6A4A22, "D": 0xA97B45])
    case .cobweb:
        return (["w.....w.", ".w...w..", "..w.w...", "...w....", "..w.w...", ".w...w..", "w.....w.", "........"],
                ["w": 0xE8E8F0])
    default:
        return nil
    }
}

func tileBuf(_ t: Tile) -> PixelBuf {
    var b = PixelBuf(w: 8, h: 8)
    let d: TileDef = t.def
    if d.style == .custom {
        if let cr = customTileRows(t) {
            // always hand back an 8x8 tile: centre narrow art, stand short art on the floor
            let cb: PixelBuf = bufFromRows(cr.0, cr.1)
            var o = PixelBuf(w: 8, h: 8)
            o.blit(cb, (8 - cb.w) / 2, 8 - cb.h)
            return o
        }
        return b
    }
    var rng = RNG(UInt64(t.rawValue) &* 7919 &+ 13)
    let c: [UInt32] = d.colors
    let specks: [(Int, Int)] = [(2, 2), (3, 2), (3, 3), (5, 5), (6, 5), (5, 6), (1, 6), (6, 1)]
    for y in 0..<8 {
        for x in 0..<8 {
            let r: Int = rng.int(100)
            var col: UInt32 = c[0]
            switch d.style {
            case .grassTop:
                if y < 2 { col = r < 60 ? c[0] : c[1] }
                else if y == 2 { col = r < 50 ? c[1] : c[2] }
                else { col = r < 60 ? c[2] : (r < 85 ? c[3] : c[4]) }
            case .log:
                col = (x % 4 == 0) ? c[1] : (r < 20 ? c[2] : c[0])
                if x == 7 { col = c[3] }
            case .leaves:
                col = r < 50 ? c[0] : (r < 80 ? c[1] : (r < 92 ? c[2] : c[3]))
                if r > 95 { b.clear(x, y); continue }
            case .planks:
                col = (y == 3 || y == 7) ? c[1] : (r < 15 ? c[3] : (r < 40 ? c[2] : c[0]))
            case .bricks:
                let off: Int = (y / 4) % 2 == 0 ? 0 : 4
                if y % 4 == 3 || (x + off) % 8 == 7 { col = c[1] }
                else { col = r < 50 ? c[0] : (r < 80 ? c[2] : c[3]) }
            case .glass:
                if x == 0 || y == 0 || x == 7 || y == 7 { col = c[2] }
                else if (x == y && x < 4) || (x == y + 1 && x < 3) { col = c[1] }
                else { continue }
            case .water:
                let base: UInt32 = (y == 0 || r < 10) ? c[3] : (r < 50 ? c[1] : c[0])
                b.px[y * 8 + x] = 0xB0000000 | base
                continue
            case .lava:
                col = r < 25 ? c[3] : (r < 60 ? c[1] : (r < 85 ? c[0] : c[2]))
            case .ore:
                col = r < 55 ? c[0] : (r < 80 ? c[1] : c[2])
                if specks.contains(where: { $0.0 == x && $0.1 == y }) { col = r < 60 ? c[5] : c[6] }
            case .snow:
                col = r < 60 ? c[0] : (r < 85 ? c[1] : c[2])
            case .ice:
                col = r < 50 ? c[0] : (r < 75 ? c[1] : c[2])
                if (x + y) % 6 == 0 { col = c[3] }
                b.px[y * 8 + x] = 0xE0000000 | col
                continue
            case .mud:
                col = r < 55 ? c[0] : (r < 80 ? c[1] : (r < 92 ? c[2] : c[3]))
            case .cactus:
                col = (x == 0 || x == 7) ? c[3] : ((x == 3 || x == 4) ? c[2] : c[0])
                if y % 4 == 1 && (x == 1 || x == 6) { col = c[3] }
            case .crystal:
                col = r < 40 ? c[0] : (r < 70 ? c[1] : c[2])
                if (x + y) % 5 == 0 { col = c[3] }
            case .farmland:
                col = (y % 3 == 1) ? c[1] : (r < 40 ? c[2] : c[0])
            case .sandstone:
                col = (y % 3 == 2) ? c[1] : (r < 25 ? c[2] : c[0])
            case .ash:
                col = r < 55 ? c[0] : (r < 80 ? c[1] : (r < 93 ? c[2] : c[3]))
            default:
                col = r < 55 ? c[0] : (r < 80 ? c[1] : (r < 93 ? c[2] : c[3]))
            }
            b.set(x, y, col)
        }
    }
    return b
}

// ===== p03_items =====

// MARK: - Items

enum Tier: Int, Codable, CaseIterable {
    case wood = 1, stone, copper, iron, gold, diamond, mythril, ember, voidium

    var name: String {
        switch self {
        case .wood: return "Wooden"
        case .stone: return "Stone"
        case .copper: return "Copper"
        case .iron: return "Iron"
        case .gold: return "Golden"
        case .diamond: return "Diamond"
        case .mythril: return "Mythril"
        case .ember: return "Ember"
        case .voidium: return "Voidium"
        }
    }
    var armorName: String { return self == .wood ? "Leather" : name }
    var color: UInt32 {
        switch self {
        case .wood: return 0xB98A4E
        case .stone: return 0x8E8E96
        case .copper: return 0xD2793A
        case .iron: return 0xD0D4DA
        case .gold: return 0xF5D142
        case .diamond: return 0x4FE3E8
        case .mythril: return 0x8A7CFF
        case .ember: return 0xFF6A1E
        case .voidium: return 0xB04CFF
        }
    }
    var mineSpeed: Double {
        let t: [Double] = [1, 2.0, 3.2, 4.2, 5.5, 7.0, 9.0, 12.0, 16.0, 22.0]
        return t[rawValue]
    }
    var damage: Double {
        let t: [Double] = [2, 4, 5.5, 6.5, 8.5, 10, 14, 19, 26, 36]
        return t[rawValue]
    }
    var defense: Double {
        let t: [Double] = [0, 1.0, 1.0, 1.5, 2.0, 2.3, 3.0, 4.0, 5.0, 6.0]
        return t[rawValue]
    }
}

enum ToolType: Int, Codable, CaseIterable {
    case pickaxe, axe, shovel, hoe
    var name: String {
        switch self {
        case .pickaxe: return "Pickaxe"
        case .axe: return "Axe"
        case .shovel: return "Shovel"
        case .hoe: return "Hoe"
        }
    }
}

enum ArmorSlot: Int, Codable, CaseIterable {
    case head, chest, legs
    var name: String {
        switch self {
        case .head: return "Helmet"
        case .chest: return "Chestplate"
        case .legs: return "Leggings"
        }
    }
    var weight: Double {
        switch self {
        case .head: return 0.8
        case .chest: return 1.3
        case .legs: return 0.9
        }
    }
}

enum Mat: Int, Codable, CaseIterable {
    case stick, coal, copperOre, ironOre, goldOre, mythrilOre, diamond, emberOre, voidOre
    case copperBar, ironBar, goldBar, mythrilBar, emberBar, voidBar
    case string, leather, bone, feather, wool, gunpowder, seeds, claw, tusk, fur

    var name: String {
        switch self {
        case .stick: return "Stick"
        case .coal: return "Coal"
        case .copperOre: return "Copper Ore"
        case .ironOre: return "Iron Ore"
        case .goldOre: return "Gold Ore"
        case .mythrilOre: return "Mythril Ore"
        case .diamond: return "Diamond"
        case .emberOre: return "Ember Ore"
        case .voidOre: return "Voidium Ore"
        case .copperBar: return "Copper Bar"
        case .ironBar: return "Iron Bar"
        case .goldBar: return "Gold Bar"
        case .mythrilBar: return "Mythril Bar"
        case .emberBar: return "Ember Bar"
        case .voidBar: return "Voidium Bar"
        case .string: return "String"
        case .leather: return "Leather"
        case .bone: return "Bone"
        case .feather: return "Feather"
        case .wool: return "Wool"
        case .gunpowder: return "Gunpowder"
        case .seeds: return "Seeds"
        case .claw: return "Claw"
        case .tusk: return "Tusk"
        case .fur: return "Thick Fur"
        }
    }
}

enum Food: Int, Codable, CaseIterable {
    case apple, rawMeat, cookedMeat, rawFish, cookedFish, wheat, bread, carrot
    var name: String {
        switch self {
        case .apple: return "Apple"
        case .rawMeat: return "Raw Meat"
        case .cookedMeat: return "Steak"
        case .rawFish: return "Raw Fish"
        case .cookedFish: return "Cooked Fish"
        case .wheat: return "Wheat"
        case .bread: return "Bread"
        case .carrot: return "Carrot"
        }
    }
    var hunger: Double {
        switch self {
        case .apple: return 3
        case .rawMeat: return 2
        case .cookedMeat: return 8
        case .rawFish: return 2
        case .cookedFish: return 6
        case .wheat: return 1
        case .bread: return 6
        case .carrot: return 3
        }
    }
    var heal: Double {
        switch self {
        case .cookedMeat: return 3
        case .cookedFish: return 2
        case .bread: return 1
        default: return 0
        }
    }
}

enum GunType: Int, Codable, CaseIterable {
    case pistol, rifle
    var name: String { return self == .pistol ? "Flintlock Pistol" : "Long Rifle" }
    var damage: Double { return self == .pistol ? 9 : 24 }
    var cooldown: Double { return self == .pistol ? 0.32 : 0.85 }
    var magazine: Int { return self == .pistol ? 6 : 4 }
    var reloadTime: Double { return self == .pistol ? 1.3 : 2.2 }
    var speed: Double { return self == .pistol ? 34 : 48 }
}

enum AmmoType: Int, Codable, CaseIterable {
    case arrow, bullet
    var name: String { return self == .arrow ? "Arrow" : "Bullet" }
}

enum PartType: Int, Codable, CaseIterable {
    case frame, wheel, engine, steering, seat, fuelTank, hull, propeller, paddle, drill, diamondDrill
    var name: String {
        switch self {
        case .frame: return "Vehicle Frame"
        case .wheel: return "Wheel"
        case .engine: return "Engine"
        case .steering: return "Steering Wheel"
        case .seat: return "Seat"
        case .fuelTank: return "Fuel Tank"
        case .hull: return "Hull Float"
        case .propeller: return "Propeller"
        case .paddle: return "Paddle"
        case .drill: return "Iron Drill"
        case .diamondDrill: return "Diamond Drill"
        }
    }
    var mass: Double {
        switch self {
        case .frame: return 1.0
        case .wheel: return 0.6
        case .engine: return 2.0
        case .steering: return 0.3
        case .seat: return 0.5
        case .fuelTank: return 1.2
        case .hull: return 0.8
        case .propeller: return 0.5
        case .paddle: return 0.3
        case .drill: return 1.6
        case .diamondDrill: return 1.8
        }
    }
}

enum Gadget: Int, Codable, CaseIterable {
    case shears, wrench, treasureMap, portalKey, carKit, boatKit, motorboatKit, bomb
    var name: String {
        switch self {
        case .shears: return "Shears"
        case .wrench: return "Wrench"
        case .treasureMap: return "Treasure Map"
        case .portalKey: return "Portal Key"
        case .carKit: return "Car Kit"
        case .boatKit: return "Rowboat Kit"
        case .motorboatKit: return "Motorboat Kit"
        case .bomb: return "Bomb"
        }
    }
}

enum Item: Hashable, Codable {
    case block(Tile)
    case tool(ToolType, Tier)
    case sword(Tier)
    case armor(ArmorSlot, Tier)
    case mat(Mat)
    case food(Food)
    case bow
    case gun(GunType)
    case ammo(AmmoType)
    case part(PartType)
    case gadget(Gadget)
    case wall(Int)

    var name: String {
        switch self {
        case .block(let t): return t.name
        case .tool(let k, let t): return t.name + " " + k.name
        case .sword(let t): return t.name + " Sword"
        case .armor(let s, let t): return t.armorName + " " + s.name
        case .mat(let m): return m.name
        case .food(let f): return f.name
        case .bow: return "Bow"
        case .gun(let g): return g.name
        case .ammo(let a): return a.name
        case .part(let p): return p.name
        case .gadget(let g): return g.name
        case .wall(let k): return wallName(k)
        }
    }

    var maxStack: Int {
        switch self {
        case .block, .mat, .food, .ammo, .wall: return 99
        case .part: return 20
        case .gadget(let g): return g == .bomb ? 30 : 1
        default: return 1
        }
    }

    var isWeapon: Bool {
        switch self {
        case .sword, .bow, .gun: return true
        default: return false
        }
    }

    var isRanged: Bool {
        switch self {
        case .bow, .gun: return true
        default: return false
        }
    }

    var tierValue: Tier? {
        switch self {
        case .tool(_, let t): return t
        case .sword(let t): return t
        case .armor(_, let t): return t
        default: return nil
        }
    }

    /// Melee damage when swung
    var meleeDamage: Double {
        switch self {
        case .sword(let t): return t.damage
        case .tool(let k, let t):
            switch k {
            case .axe: return t.damage * 0.8
            case .pickaxe: return t.damage * 0.6
            case .shovel: return t.damage * 0.5
            case .hoe: return t.damage * 0.4
            }
        case .gun, .bow: return 2.0
        default: return 1.5
        }
    }

    var meleeCooldown: Double {
        switch self {
        case .sword: return 0.42
        case .tool(let k, _): return k == .axe ? 0.55 : 0.5
        default: return 0.4
        }
    }

    var meleeReach: Double {
        switch self {
        case .sword: return 2.7
        case .tool: return 2.2
        default: return 1.8
        }
    }

    var isFood: Bool {
        if case .food = self { return true }
        return false
    }
}

struct Stack: Codable, Hashable {
    var item: Item
    var count: Int
    var extra: Int = 0
}

// MARK: - Item icons

func tierShade(_ c: UInt32, _ f: Double) -> UInt32 { return shadeRGB(c, f) }

func iconTool(_ k: ToolType, _ tier: Tier) -> PixelBuf {
    var b = PixelBuf(w: 12, h: 12)
    let m: UInt32 = tier.color
    let hi: UInt32 = tierShade(m, 1.25)
    let lo: UInt32 = tierShade(m, 0.7)
    let hd: UInt32 = 0x9A6A32
    let hdd: UInt32 = 0x5E3C1C
    b.line(1, 11, 8, 4, hd)
    b.line(2, 11, 9, 4, hdd)
    switch k {
    case .pickaxe:
        b.line(4, 1, 10, 7, m)
        b.line(5, 1, 10, 6, hi)
        b.line(3, 2, 4, 1, lo)
        b.line(10, 7, 11, 8, lo)
        b.line(4, 2, 10, 8, lo)
    case .axe:
        b.ellipse(8.5, 3.0, 3.0, 2.6, m)
        b.line(6, 1, 6, 5, hi)
        b.line(11, 1, 11, 6, lo)
        b.line(8, 6, 10, 5, lo)
    case .shovel:
        b.ellipse(9.0, 3.0, 2.2, 2.8, m)
        b.line(8, 1, 8, 4, hi)
        b.line(10, 5, 10, 5, lo)
    case .hoe:
        b.line(7, 3, 11, 3, m)
        b.line(7, 2, 10, 2, hi)
        b.line(11, 3, 11, 6, lo)
        b.line(10, 4, 10, 5, m)
    }
    b.outline(0x1A1410)
    return b
}

func iconSword(_ tier: Tier) -> PixelBuf {
    var b = PixelBuf(w: 12, h: 12)
    let m: UInt32 = tier.color
    let hi: UInt32 = tierShade(m, 1.3)
    let lo: UInt32 = tierShade(m, 0.7)
    b.line(5, 6, 10, 1, m)
    b.line(6, 6, 10, 2, lo)
    b.line(5, 5, 9, 1, hi)
    b.line(3, 6, 5, 8, 0xC8A040)
    b.line(1, 10, 4, 7, 0x8A5A2A)
    b.set(1, 10, 0xE0C060)
    b.outline(0x1A1410)
    return b
}

func iconArmor(_ s: ArmorSlot, _ tier: Tier) -> PixelBuf {
    var b = PixelBuf(w: 12, h: 12)
    let m: UInt32 = tier.color
    let hi: UInt32 = tierShade(m, 1.25)
    let lo: UInt32 = tierShade(m, 0.7)
    switch s {
    case .head:
        b.rect(3, 3, 6, 5, m)
        b.rect(4, 2, 4, 1, m)
        b.rect(3, 8, 1, 2, m)
        b.rect(8, 8, 1, 2, m)
        b.rect(4, 5, 4, 2, 0x20202A)
        b.rect(4, 3, 4, 1, hi)
        b.rect(3, 7, 6, 1, lo)
    case .chest:
        b.rect(2, 2, 8, 8, m)
        b.rect(0, 2, 2, 4, m)
        b.rect(10, 2, 2, 4, m)
        b.rect(4, 2, 4, 1, 0x20202A)
        b.rect(3, 4, 6, 1, hi)
        b.rect(2, 9, 8, 1, lo)
        b.rect(5, 5, 2, 4, lo)
    case .legs:
        b.rect(2, 1, 8, 3, m)
        b.rect(2, 4, 3, 6, m)
        b.rect(7, 4, 3, 6, m)
        b.rect(2, 2, 8, 1, hi)
        b.rect(2, 9, 3, 1, lo)
        b.rect(7, 9, 3, 1, lo)
    }
    b.outline(0x1A1410)
    return b
}

func iconMat(_ m: Mat) -> PixelBuf {
    var b = PixelBuf(w: 10, h: 10)
    func ore(_ c: UInt32) {
        b.ellipse(5, 5.5, 3.6, 3.2, 0x8A8A8A)
        b.rect(3, 4, 2, 1, c)
        b.rect(6, 6, 2, 2, c)
        b.rect(4, 7, 1, 1, c)
        b.rect(6, 3, 1, 1, tierShade(c, 1.3))
    }
    func bar(_ c: UInt32) {
        b.rect(1, 4, 8, 4, c)
        b.rect(2, 3, 6, 1, tierShade(c, 1.3))
        b.rect(1, 7, 8, 1, tierShade(c, 0.7))
        b.rect(3, 5, 2, 1, tierShade(c, 1.4))
    }
    switch m {
    case .stick: b.line(2, 8, 7, 2, 0x8A5A2A); b.line(3, 8, 8, 2, 0x6A4220)
    case .coal: b.ellipse(5, 5.5, 3.4, 3.0, 0x222226); b.set(4, 4, 0x55555C); b.set(6, 6, 0x3A3A40)
    case .copperOre: ore(0xD2793A)
    case .ironOre: ore(0xD8A878)
    case .goldOre: ore(0xF5D142)
    case .mythrilOre: ore(0x8A7CFF)
    case .emberOre: ore(0xFF7A1E)
    case .voidOre: ore(0xB04CFF)
    case .diamond:
        b.rect(3, 2, 4, 1, 0xB8FBFF); b.rect(2, 3, 6, 2, 0x4FE3E8); b.rect(3, 5, 4, 2, 0x2EB8C0); b.rect(4, 7, 2, 1, 0x1E8890); b.set(4, 3, 0xFFFFFF)
    case .copperBar: bar(0xD2793A)
    case .ironBar: bar(0xD0D4DA)
    case .goldBar: bar(0xF5D142)
    case .mythrilBar: bar(0x8A7CFF)
    case .emberBar: bar(0xFF6A1E)
    case .voidBar: bar(0xB04CFF)
    case .string: b.line(1, 2, 8, 3, 0xEEEEEE); b.line(8, 3, 2, 5, 0xDDDDDD); b.line(2, 5, 8, 7, 0xEEEEEE); b.line(8, 7, 2, 8, 0xCCCCCC)
    case .leather: b.rect(2, 2, 6, 6, 0x9A5A2A); b.rect(3, 3, 4, 4, 0xB8743A); b.set(2, 2, 0); b.set(7, 7, 0)
    case .bone: b.line(2, 7, 7, 2, 0xE8E0C8); b.rect(1, 6, 2, 2, 0xE8E0C8); b.rect(7, 1, 2, 2, 0xE8E0C8)
    case .feather: b.line(2, 8, 8, 1, 0xDDDDEE); b.line(3, 8, 8, 2, 0x9A9AB0); b.line(2, 8, 1, 9, 0x666666)
    case .wool: b.ellipse(5, 5, 3.6, 3.2, 0xF4F4F0); b.rect(3, 3, 2, 1, 0xFFFFFF); b.rect(5, 7, 3, 1, 0xD8D8D0)
    case .gunpowder: b.ellipse(5, 6, 3.4, 2.4, 0x5A5A60); b.rect(3, 5, 1, 1, 0x8A8A90); b.rect(6, 6, 1, 1, 0x3A3A40)
    case .seeds: b.rect(2, 3, 1, 1, 0xC8B040); b.rect(5, 2, 1, 1, 0xC8B040); b.rect(7, 5, 1, 1, 0xC8B040); b.rect(3, 6, 1, 1, 0xC8B040); b.rect(6, 8, 1, 1, 0xC8B040)
    case .claw: b.line(2, 7, 7, 2, 0xEDE6D0); b.line(3, 7, 7, 3, 0xBDB69A); b.rect(1, 7, 2, 2, 0x7A5A3A)
    case .tusk: b.line(2, 8, 4, 3, 0xF4EEDC); b.line(4, 3, 8, 2, 0xF4EEDC); b.line(3, 8, 5, 4, 0xC8C0A8)
    case .fur: b.rect(2, 2, 6, 6, 0x7A7066); b.rect(3, 3, 4, 4, 0x9A9086); b.set(2, 2, 0); b.set(7, 7, 0); b.set(3, 5, 0xBAB0A6)
    }
    b.outline(0x1A1410)
    return b
}

func iconFood(_ f: Food) -> PixelBuf {
    var b = PixelBuf(w: 10, h: 10)
    switch f {
    case .apple:
        b.ellipse(5, 6, 3.4, 3.2, 0xD62E2E); b.set(4, 4, 0xFF9A9A); b.line(5, 2, 5, 3, 0x6B4A2A); b.rect(6, 1, 2, 1, 0x3E8A2E)
    case .rawMeat:
        b.ellipse(5, 5.5, 3.8, 3.0, 0xE06A7A); b.ellipse(4.5, 5, 1.8, 1.4, 0xF0A0AA); b.rect(7, 2, 1, 2, 0xE8E0C8)
    case .cookedMeat:
        b.ellipse(5, 5.5, 3.8, 3.0, 0x8A4A24); b.ellipse(4.5, 5, 1.8, 1.4, 0xB86A38); b.rect(7, 2, 1, 2, 0xE8E0C8)
    case .rawFish:
        b.ellipse(5, 5, 3.4, 2.2, 0x8FB4D8); b.rect(8, 3, 1, 4, 0x6A94B8); b.set(3, 4, 0x101010)
    case .cookedFish:
        b.ellipse(5, 5, 3.4, 2.2, 0xC88A4A); b.rect(8, 3, 1, 4, 0xA06A30); b.set(3, 4, 0x101010)
    case .wheat:
        b.line(5, 9, 5, 3, 0xC8B040); b.rect(4, 1, 3, 3, 0xE8C850); b.set(3, 4, 0xE8C850); b.set(7, 5, 0xE8C850)
    case .bread:
        b.ellipse(5, 6, 4.0, 2.6, 0xC88A3A); b.rect(3, 4, 4, 1, 0xE0A850); b.set(4, 6, 0x9A6A2A)
    case .carrot:
        b.line(2, 3, 7, 8, 0xF08A1E); b.line(3, 3, 7, 7, 0xD06A10); b.line(1, 1, 3, 3, 0x4EB83A); b.line(3, 1, 3, 3, 0x4EB83A)
    }
    b.outline(0x1A1410)
    return b
}

func iconMisc(_ it: Item) -> PixelBuf {
    var b = PixelBuf(w: 12, h: 12)
    switch it {
    case .bow:
        b.line(8, 0, 10, 3, 0xA06A2E); b.line(10, 3, 10, 8, 0xA06A2E); b.line(10, 8, 8, 11, 0xA06A2E)
        b.line(9, 0, 11, 3, 0x7A4A1E); b.line(11, 3, 11, 8, 0x7A4A1E); b.line(11, 8, 9, 11, 0x7A4A1E)
        b.line(8, 0, 8, 11, 0xE8E8E8)
        b.line(2, 6, 7, 6, 0xB08A5A); b.set(1, 6, 0xDDDDDD)
    case .gun(let g):
        if g == .pistol {
            b.rect(2, 3, 8, 2, 0x6A6A74); b.rect(2, 5, 4, 2, 0x5A5A64); b.rect(2, 5, 2, 4, 0x8A5A2A); b.rect(9, 2, 2, 1, 0x9A9AA4); b.set(6, 5, 0x3A3A44)
        } else {
            b.rect(0, 4, 11, 1, 0x6A6A74); b.rect(4, 5, 4, 2, 0x5A5A64); b.rect(0, 5, 4, 3, 0x8A5A2A); b.rect(5, 7, 1, 2, 0x8A5A2A); b.rect(10, 3, 1, 1, 0x9A9AA4)
        }
    case .ammo(let a):
        if a == .arrow {
            b.line(1, 10, 9, 2, 0x8A5A2A); b.rect(9, 1, 2, 2, 0xC8C8D0); b.line(1, 10, 1, 8, 0xF0F0F0); b.line(1, 10, 3, 10, 0xF0F0F0)
        } else {
            b.rect(4, 3, 3, 6, 0xC8A040); b.rect(4, 2, 3, 1, 0x8A8A90); b.set(5, 4, 0xFFE080)
        }
    case .part(let p):
        switch p {
        case .frame: b.rect(1, 3, 10, 6, 0xB98A4E); b.rect(2, 4, 8, 4, 0x2A2A30); b.line(2, 4, 9, 7, 0x8F6732); b.line(2, 7, 9, 4, 0x8F6732)
        case .wheel: b.ellipse(6, 6, 5, 5, 0x222226); b.ellipse(6, 6, 3, 3, 0x9A9AA4); b.set(6, 6, 0x222226)
        case .engine: b.rect(1, 3, 10, 6, 0x6A6A74); b.rect(3, 1, 2, 2, 0xA8A8B0); b.rect(7, 1, 2, 2, 0xA8A8B0); b.rect(2, 5, 8, 1, 0xE06A2A); b.rect(0, 5, 1, 2, 0x4A4A52)
        case .steering: b.ellipse(6, 6, 4.5, 4.5, 0x8A5A2A); b.ellipse(6, 6, 2.6, 2.6, 0); b.line(6, 1, 6, 11, 0x8A5A2A); b.line(1, 6, 11, 6, 0x8A5A2A)
        case .seat: b.rect(2, 1, 3, 7, 0x8A3A3A); b.rect(2, 7, 8, 3, 0x9A4A4A); b.rect(2, 10, 2, 1, 0x4A4A52); b.rect(8, 10, 2, 1, 0x4A4A52)
        case .fuelTank: b.rect(2, 2, 8, 8, 0xC03A3A); b.rect(2, 2, 8, 1, 0xE06A6A); b.rect(4, 0, 4, 2, 0x4A4A52); b.rect(4, 5, 4, 3, 0xF0E0A0)
        case .hull: b.rect(0, 4, 12, 3, 0x8F6732); b.rect(1, 7, 10, 2, 0x6A4A22); b.rect(2, 9, 8, 1, 0x4A3216); b.rect(1, 3, 10, 1, 0xB98A4E)
        case .propeller: b.rect(5, 1, 2, 10, 0x9A9AA4); b.rect(1, 5, 10, 2, 0x7A7A84); b.rect(5, 5, 2, 2, 0x4A4A52)
        case .paddle: b.line(2, 10, 8, 4, 0x8A5A2A); b.rect(8, 1, 3, 5, 0xB98A4E); b.rect(8, 1, 1, 5, 0x8F6732)
        case .drill, .diamondDrill:
            let bit: UInt32 = p == .drill ? 0xC8CCD4 : 0x6FE6EC
            b.rect(0, 3, 4, 6, 0x6A6A74); b.rect(0, 3, 4, 1, 0x9A9AA4)
            b.rect(4, 3, 3, 6, bit); b.rect(7, 4, 2, 4, bit); b.rect(9, 5, 2, 2, bit); b.set(11, 5, bit)
            b.line(5, 3, 7, 8, shadeRGB(bit, 0.7)); b.line(8, 4, 9, 7, shadeRGB(bit, 0.7))
        }
    case .gadget(let g):
        switch g {
        case .shears: b.line(2, 9, 8, 3, 0xC8C8D0); b.line(3, 3, 9, 9, 0xA8A8B0); b.ellipse(2.5, 9.5, 1.6, 1.6, 0xD04A3A); b.ellipse(9.5, 9.5, 1.6, 1.6, 0xD04A3A)
        case .wrench: b.line(2, 10, 8, 4, 0xB8B8C0); b.line(3, 10, 9, 4, 0x8A8A94); b.ellipse(9, 3, 2.2, 2.2, 0xB8B8C0); b.rect(9, 1, 2, 2, 0)
        case .treasureMap:
            b.rect(1, 2, 10, 8, 0xE8D4A0); b.rect(1, 2, 10, 1, 0xC8B080); b.rect(1, 9, 10, 1, 0xC8B080)
            b.line(3, 7, 5, 5, 0x7A5A2A); b.line(5, 5, 7, 6, 0x7A5A2A); b.line(7, 6, 9, 4, 0x7A5A2A)
            b.line(7, 3, 9, 5, 0xD02020); b.line(9, 3, 7, 5, 0xD02020)
        case .portalKey:
            b.ellipse(3.5, 3.5, 2.6, 2.6, 0xB04CFF); b.ellipse(3.5, 3.5, 1.2, 1.2, 0); b.line(5, 5, 10, 10, 0xD8A8FF); b.line(6, 4, 10, 8, 0x8A3CD0); b.rect(8, 9, 2, 1, 0xD8A8FF); b.rect(9, 7, 1, 1, 0xD8A8FF)
        case .carKit:
            b.rect(1, 5, 10, 3, 0xC03A3A); b.rect(3, 3, 5, 2, 0xC03A3A); b.rect(4, 3, 3, 1, 0x9AD0F0)
            b.ellipse(3, 9, 1.8, 1.8, 0x222226); b.ellipse(9, 9, 1.8, 1.8, 0x222226); b.set(3, 9, 0x9A9AA4); b.set(9, 9, 0x9A9AA4)
        case .boatKit:
            b.rect(1, 6, 10, 2, 0x8F6732); b.rect(2, 8, 8, 1, 0x6A4A22); b.rect(3, 9, 6, 1, 0x4A3216); b.line(8, 1, 10, 6, 0xB98A4E)
            b.rect(1, 10, 10, 1, 0x3A70C8)
        case .motorboatKit:
            b.rect(1, 6, 10, 2, 0xE8E8EC); b.rect(2, 8, 8, 1, 0x3A6AA8); b.rect(3, 9, 6, 1, 0x2A4A78); b.rect(5, 4, 4, 2, 0x9AD0F0)
            b.rect(0, 7, 1, 2, 0x6A6A74); b.rect(1, 10, 10, 1, 0x3A70C8)
        case .bomb:
            b.ellipse(5.5, 7.0, 3.8, 3.8, 0x3A3A44); b.ellipse(4.5, 6.0, 1.4, 1.2, 0x6A6A78)
            b.rect(5, 2, 2, 2, 0x8A6A3A); b.line(7, 2, 9, 0, 0xC8A060); b.set(9, 0, 0xFFD040); b.set(10, 0, 0xFF8030)
        }
    default:
        break
    }
    b.outline(0x1A1410)
    return b
}

/// Icon buffer for any item (blocks use their 8x8 tile art)
func itemBuf(_ it: Item) -> PixelBuf {
    switch it {
    case .block(let t): return tileBuf(t)
    case .tool(let k, let t): return iconTool(k, t)
    case .sword(let t): return iconSword(t)
    case .armor(let s, let t): return iconArmor(s, t)
    case .mat(let m): return iconMat(m)
    case .food(let f): return iconFood(f)
    case .wall(let k): return wallIcon(k)
    default: return iconMisc(it)
    }
}

// ===== p04_recipes =====

// MARK: - Recipes & inventory

enum Station: Int, Codable {
    case hand, bench, furnace, campfire
    var name: String {
        switch self {
        case .hand: return "By hand"
        case .bench: return "Workbench"
        case .furnace: return "Furnace"
        case .campfire: return "Campfire / Furnace"
        }
    }
}

enum RecipeCat: Int, CaseIterable {
    case basic, tools, weapons, armor, smelt, food, vehicle
    var name: String {
        switch self {
        case .basic: return "Basics"
        case .tools: return "Tools"
        case .weapons: return "Weapons"
        case .armor: return "Armor"
        case .smelt: return "Smelting"
        case .food: return "Food"
        case .vehicle: return "Vehicles"
        }
    }
}

struct CostLine {
    var item: Item
    var n: Int
}

struct Recipe: Identifiable {
    let id: Int
    let out: Item
    let outCount: Int
    let cost: [CostLine]
    let station: Station
    let cat: RecipeCat
}

func tierMaterial(_ t: Tier) -> Item {
    switch t {
    case .wood: return .block(.planks)
    case .stone: return .block(.stone)
    case .copper: return .mat(.copperBar)
    case .iron: return .mat(.ironBar)
    case .gold: return .mat(.goldBar)
    case .diamond: return .mat(.diamond)
    case .mythril: return .mat(.mythrilBar)
    case .ember: return .mat(.emberBar)
    case .voidium: return .mat(.voidBar)
    }
}

func armorMaterial(_ t: Tier) -> Item {
    if t == .wood { return .mat(.leather) }
    return tierMaterial(t)
}

enum RecipeBook {
    static let all: [Recipe] = RecipeBook.build()

    static func build() -> [Recipe] {
        var list: [Recipe] = []
        func add(_ out: Item, _ n: Int, _ cost: [(Item, Int)], _ st: Station, _ cat: RecipeCat) {
            let lines: [CostLine] = cost.map { CostLine(item: $0.0, n: $0.1) }
            list.append(Recipe(id: list.count, out: out, outCount: n, cost: lines, station: st, cat: cat))
        }
        let stick: Item = .mat(.stick)
        let coal: Item = .mat(.coal)
        let planks: Item = .block(.planks)
        // Basics
        add(planks, 4, [(.block(.log), 1)], .hand, .basic)
        add(planks, 4, [(.block(.jungleLog), 1)], .hand, .basic)
        add(planks, 4, [(.block(.palmLog), 1)], .hand, .basic)
        add(stick, 4, [(planks, 2)], .hand, .basic)
        add(.block(.workbench), 1, [(planks, 8)], .hand, .basic)
        add(.block(.torch), 4, [(stick, 1), (coal, 1)], .hand, .basic)
        add(.block(.campfire), 1, [(.block(.log), 3), (stick, 2)], .hand, .basic)
        add(.block(.furnace), 1, [(.block(.stone), 12)], .bench, .basic)
        add(.block(.platform), 4, [(planks, 2)], .hand, .basic)
        add(.block(.chest), 1, [(planks, 8)], .bench, .basic)
        add(.block(.brick), 2, [(.block(.stone), 2)], .bench, .basic)
        add(.block(.lantern), 1, [(.mat(.ironBar), 1), (.block(.torch), 1)], .bench, .basic)
        add(.block(.hay), 2, [(.food(.wheat), 4)], .bench, .basic)
        add(.mat(.string), 2, [(.mat(.wool), 1)], .hand, .basic)
        add(.mat(.gunpowder), 2, [(coal, 1), (.block(.sand), 1)], .bench, .basic)
        add(.block(.glass), 1, [(.block(.sand), 2)], .furnace, .smelt)
        // Doors and background walls (walls have no collision)
        add(.block(.doorClosed), 1, [(planks, 6)], .bench, .basic)
        add(.wall(5), 4, [(planks, 1)], .bench, .basic)
        add(.wall(6), 4, [(.block(.brick), 1)], .bench, .basic)
        add(.wall(2), 4, [(.block(.stone), 1)], .bench, .basic)
        add(.wall(1), 4, [(.block(.dirt), 1)], .bench, .basic)
        add(.wall(7), 4, [(.block(.sandstone), 1)], .bench, .basic)
        add(.wall(4), 4, [(.block(.ashStone), 1)], .bench, .basic)
        // Smelting
        add(.mat(.copperBar), 1, [(.mat(.copperOre), 2), (coal, 1)], .furnace, .smelt)
        add(.mat(.ironBar), 1, [(.mat(.ironOre), 2), (coal, 1)], .furnace, .smelt)
        add(.mat(.goldBar), 1, [(.mat(.goldOre), 2), (coal, 1)], .furnace, .smelt)
        add(.mat(.mythrilBar), 1, [(.mat(.mythrilOre), 3), (coal, 2)], .furnace, .smelt)
        add(.mat(.emberBar), 1, [(.mat(.emberOre), 3), (coal, 1)], .furnace, .smelt)
        add(.mat(.voidBar), 1, [(.mat(.voidOre), 3), (coal, 2)], .furnace, .smelt)
        // Food
        add(.food(.cookedMeat), 1, [(.food(.rawMeat), 1)], .campfire, .food)
        add(.food(.cookedFish), 1, [(.food(.rawFish), 1)], .campfire, .food)
        add(.food(.bread), 1, [(.food(.wheat), 3)], .bench, .food)
        // Tools, swords, armor for every tier
        for t in Tier.allCases {
            let m: Item = tierMaterial(t)
            add(.tool(.pickaxe, t), 1, [(m, 3), (stick, 2)], .bench, .tools)
            add(.tool(.axe, t), 1, [(m, 3), (stick, 2)], .bench, .tools)
            add(.tool(.shovel, t), 1, [(m, 1), (stick, 2)], .bench, .tools)
            add(.tool(.hoe, t), 1, [(m, 2), (stick, 2)], .bench, .tools)
            add(.sword(t), 1, [(m, 2), (stick, 1)], .bench, .weapons)
            let a: Item = armorMaterial(t)
            add(.armor(.head, t), 1, [(a, 5)], .bench, .armor)
            add(.armor(.chest, t), 1, [(a, 8)], .bench, .armor)
            add(.armor(.legs, t), 1, [(a, 7)], .bench, .armor)
        }
        // Ranged
        add(.bow, 1, [(stick, 3), (.mat(.string), 3)], .bench, .weapons)
        add(.ammo(.arrow), 6, [(stick, 1), (.mat(.feather), 1), (.block(.stone), 1)], .bench, .weapons)
        add(.gun(.pistol), 1, [(.mat(.ironBar), 5), (planks, 2)], .bench, .weapons)
        add(.gun(.rifle), 1, [(.mat(.ironBar), 8), (planks, 4), (.mat(.gunpowder), 2)], .bench, .weapons)
        add(.ammo(.bullet), 8, [(.mat(.ironBar), 1), (.mat(.gunpowder), 1)], .bench, .weapons)
        add(.gadget(.shears), 1, [(.mat(.ironBar), 2)], .bench, .tools)
        add(.gadget(.wrench), 1, [(.mat(.ironBar), 3), (stick, 1)], .bench, .tools)
        add(.gadget(.bomb), 3, [(.mat(.gunpowder), 2), (.mat(.ironBar), 1), (.mat(.string), 1)], .bench, .weapons)
        // Ready-made vehicles (place them in one tap) - easiest way to get driving
        add(.gadget(.carKit), 1, [(planks, 10), (.mat(.ironBar), 14), (.mat(.leather), 2), (.mat(.wool), 2)], .bench, .vehicle)
        add(.gadget(.boatKit), 1, [(planks, 20), (.mat(.string), 4), (.mat(.wool), 2)], .bench, .vehicle)
        add(.gadget(.motorboatKit), 1, [(planks, 20), (.mat(.ironBar), 12), (.mat(.copperBar), 3), (.mat(.wool), 2), (.block(.glass), 1)], .bench, .vehicle)
        // Vehicle parts (for building your own design)
        add(.part(.frame), 1, [(planks, 4), (.mat(.ironBar), 1)], .bench, .vehicle)
        add(.part(.wheel), 1, [(.mat(.ironBar), 2), (.mat(.leather), 1)], .bench, .vehicle)
        add(.part(.engine), 1, [(.mat(.ironBar), 6), (.mat(.copperBar), 3), (coal, 2)], .bench, .vehicle)
        add(.part(.steering), 1, [(.mat(.ironBar), 1), (stick, 2)], .bench, .vehicle)
        add(.part(.seat), 1, [(planks, 2), (.mat(.wool), 2)], .bench, .vehicle)
        add(.part(.fuelTank), 1, [(.mat(.ironBar), 3), (.block(.glass), 1)], .bench, .vehicle)
        add(.part(.hull), 1, [(planks, 6), (.mat(.string), 2)], .bench, .vehicle)
        add(.part(.propeller), 1, [(.mat(.ironBar), 3)], .bench, .vehicle)
        add(.part(.paddle), 1, [(planks, 2), (stick, 2)], .bench, .vehicle)
        add(.part(.drill), 1, [(.mat(.ironBar), 6), (.mat(.copperBar), 2)], .bench, .vehicle)
        add(.part(.diamondDrill), 1, [(.part(.drill), 1), (.mat(.diamond), 4), (.mat(.goldBar), 2)], .bench, .vehicle)
        return list
    }
}

// MARK: - Inventory

struct Inventory: Codable {
    var slots: [Stack?]
    var armor: [Stack?]
    static let hotbarCount: Int = 10
    static let size: Int = 40

    init() {
        slots = [Stack?](repeating: nil, count: Inventory.size)
        armor = [Stack?](repeating: nil, count: 3)
    }

    func total(_ item: Item) -> Int {
        var n: Int = 0
        for s in slots {
            if let st = s, st.item == item { n += st.count }
        }
        return n
    }

    /// Adds items, returns the leftover count that did not fit
    mutating func add(_ item: Item, _ count: Int, extra: Int = 0) -> Int {
        var left: Int = count
        let ms: Int = item.maxStack
        if ms > 1 {
            for i in 0..<slots.count {
                if left <= 0 { break }
                if var st = slots[i], st.item == item, st.count < ms {
                    let put: Int = min(ms - st.count, left)
                    st.count += put
                    slots[i] = st
                    left -= put
                }
            }
        }
        for i in 0..<slots.count {
            if left <= 0 { break }
            if slots[i] == nil {
                let put: Int = min(ms, left)
                slots[i] = Stack(item: item, count: put, extra: extra)
                left -= put
            }
        }
        return left
    }

    mutating func remove(_ item: Item, _ count: Int) -> Bool {
        if total(item) < count { return false }
        var left: Int = count
        for i in 0..<slots.count {
            if left <= 0 { break }
            if var st = slots[i], st.item == item {
                let take: Int = min(st.count, left)
                st.count -= take
                left -= take
                slots[i] = st.count > 0 ? st : nil
            }
        }
        return true
    }

    func canAfford(_ cost: [CostLine]) -> Bool {
        for c in cost {
            if total(c.item) < c.n { return false }
        }
        return true
    }

    func canFit(_ item: Item, _ count: Int) -> Bool {
        var room: Int = 0
        let ms: Int = item.maxStack
        for s in slots {
            if let st = s {
                if st.item == item && ms > 1 { room += ms - st.count }
            } else { room += ms }
        }
        return room >= count
    }

    mutating func removeAt(_ i: Int, _ n: Int) {
        if i < 0 || i >= slots.count { return }
        if var st = slots[i] {
            st.count -= n
            slots[i] = st.count > 0 ? st : nil
        }
    }

    mutating func swap(_ a: Int, _ b: Int) {
        let t: Stack? = slots[a]
        slots[a] = slots[b]
        slots[b] = t
    }

    /// Total armor defense value
    var defense: Double {
        var d: Double = 0
        for s in armor {
            if let st = s, case .armor(let slot, let tier) = st.item { d += tier.defense * slot.weight }
        }
        return d
    }

    var hasAnyRecognizedItems: Bool {
        for s in slots { if s != nil { return true } }
        return false
    }
}

// ===== p05a_humanoid =====

// MARK: - Humanoid sprites

enum HandItem { case none, sword, cutlass, pistol }

struct HumanStyle {
    var skin: UInt32 = 0xF1C27D
    var hair: UInt32 = 0x3B2417
    var shirt: UInt32 = 0x8A5A2E
    var sleeve: UInt32 = 0x7A4C24
    var belt: UInt32 = 0xD8B060
    var pants: UInt32 = 0x3A4A6E
    var boots: UInt32 = 0x2A2A30
    var scarf: UInt32 = 0
    var eye: UInt32 = 0x1A1A1A
    var hat: UInt32 = 0
    var hatStyle: Int = 0
    var weapon: HandItem = .none
    var weaponColor: UInt32 = 0xD0D4DA
    var shield: UInt32 = 0
    var zombieArms: Bool = false
    var ribs: Bool = false
}

let humanW: Int = 20
let humanH: Int = 16
let humanOX: Int = 5

func humanoidFrame(_ s: HumanStyle, legs: Int, pose: Int) -> PixelBuf {
    var rows: [String] = []
    let hasHat: Bool = s.hat != 0
    if s.hair == 0 && !hasHat {
        rows.append("...ssss...")
        rows.append("..ssssss..")
        rows.append("..ssksks..")
        rows.append("..ssssss..")
        rows.append("...ssss...")
    } else if hasHat && s.hatStyle == 1 {
        rows.append("..HHHHH...")
        rows.append("..HHHHHHH.")
        rows.append("..HsssseH.")
        rows.append("..ssssss..")
        rows.append("...ssss...")
    } else if hasHat {
        rows.append("...HHHH...")
        rows.append("..HHHHHH..")
        rows.append("..HHssse..")
        rows.append("..ssssss..")
        rows.append("...ssss...")
    } else {
        rows.append("...hhhh...")
        rows.append("..hhhhhh..")
        rows.append("..hsssse..")
        rows.append("..ssssss..")
        rows.append("...ssss...")
    }
    rows.append(s.scarf != 0 ? "..cccccc.." : "...tttt...")
    rows.append(".aattttaa.")
    rows.append(".aattttaa.")
    rows.append(".ssttttss.")
    rows.append("..xxxxxx..")
    rows.append("..pppppp..")
    rows.append("..pppppp..")
    if legs == 1 {
        rows.append(".pp....pp."); rows.append(".pp....pp."); rows.append(".oo....oo."); rows.append(".oo....oo.")
    } else if legs == 2 {
        rows.append("...pppp..."); rows.append("...pppp..."); rows.append("...oooo..."); rows.append("...oooo...")
    } else {
        rows.append("..pp..pp.."); rows.append("..pp..pp.."); rows.append("..oo..oo.."); rows.append("..oo..oo..")
    }
    var pal: [Character: UInt32] = [:]
    pal["h"] = s.hair
    pal["H"] = s.hat
    pal["s"] = s.skin
    pal["e"] = s.eye
    pal["k"] = 0x181818
    pal["t"] = s.shirt
    pal["a"] = s.sleeve
    pal["x"] = s.belt
    pal["p"] = s.pants
    pal["o"] = s.boots
    pal["c"] = s.scarf
    var base: PixelBuf = bufFromRows(rows, pal)
    if s.ribs {
        for y in 6...8 {
            for x in 3...6 {
                if (x + y) % 2 == 0 { base.set(x, y, 0x5A5A52) }
            }
        }
    }
    var cv = PixelBuf(w: humanW, h: humanH)
    cv.blit(base, humanOX, 0)
    // arms: remove the right arm for poses that draw their own
    let ownArm: Bool = pose >= 2 || s.zombieArms
    if ownArm {
        for y in 6...8 { cv.clear(12, y); cv.clear(13, y) }
    }
    if s.zombieArms {
        cv.rect(11, 7, 6, 2, shadeRGB(s.sleeve, 0.8))
        cv.rect(12, 6, 6, 2, s.sleeve)
        cv.rect(16, 6, 2, 2, s.skin)
        cv.rect(15, 7, 2, 2, s.skin)
        return cv
    }
    let bl: UInt32 = s.weaponColor
    let blh: UInt32 = shadeRGB(bl, 1.3)
    let gold: UInt32 = 0xC8A040
    switch s.weapon {
    case .sword, .cutlass:
        if pose == 0 || pose == 3 {
            if pose == 0 {
                cv.line(14, 1, 14, 7, bl)
                cv.set(14, 0, blh)
                cv.rect(13, 7, 3, 1, gold)
                cv.set(14, 8, 0x6A4220)
            }
        } else if pose == 1 {
            cv.rect(12, 5, 3, 2, s.sleeve)
            cv.line(13, 5, 10, 0, bl)
            cv.line(14, 5, 11, 0, blh)
            cv.rect(13, 5, 2, 1, gold)
        } else if pose == 2 {
            cv.rect(12, 6, 3, 2, s.sleeve)
            cv.rect(14, 7, 1, 1, s.skin)
            cv.rect(15, 5, 1, 5, gold)
            cv.line(16, 7, 19, 7, bl)
            cv.line(16, 6, 19, 6, blh)
            if s.weapon == .cutlass { cv.set(19, 8, bl); cv.set(19, 5, blh) }
        }
    case .pistol:
        if pose == 4 || pose == 2 {
            cv.rect(12, 6, 3, 2, s.sleeve)
            cv.rect(15, 6, 4, 2, 0x4A4A54)
            cv.rect(15, 8, 1, 2, 0x8A5A2A)
            cv.set(19, 6, 0xFFE080)
        }
    case .none:
        break
    }
    if s.shield != 0 && pose == 3 {
        cv.rect(12, 6, 3, 2, s.sleeve)
        let sh: UInt32 = s.shield
        cv.rect(14, 3, 5, 10, shadeRGB(sh, 0.6))
        cv.rect(15, 4, 3, 8, sh)
        cv.rect(16, 6, 1, 4, shadeRGB(sh, 1.4))
        cv.rect(15, 4, 3, 1, shadeRGB(sh, 1.25))
    } else if s.shield != 0 {
        // shield worn on the back arm side, low
        cv.rect(7, 7, 2, 5, shadeRGB(s.shield, 0.7))
        cv.rect(7, 8, 1, 3, s.shield)
    }
    return cv
}

/// frames: 0 idle, 1 walkA, 2 walkB, 3 windup, 4 attack, 5 block, 6 shoot
func humanoidFrames(_ s: HumanStyle) -> [PixelBuf] {
    var out: [PixelBuf] = []
    out.append(humanoidFrame(s, legs: 0, pose: 0))
    out.append(humanoidFrame(s, legs: 1, pose: 0))
    out.append(humanoidFrame(s, legs: 2, pose: 0))
    out.append(humanoidFrame(s, legs: 0, pose: 1))
    out.append(humanoidFrame(s, legs: 0, pose: 2))
    out.append(humanoidFrame(s, legs: 0, pose: 3))
    out.append(humanoidFrame(s, legs: 0, pose: 4))
    for i in 0..<out.count { out[i].outline(0x1A1410) }
    return out
}

// MARK: - Character styles

let hairChoices: [UInt32] = [0xC8501E, 0x2B2B30, 0xE8D080, 0x6A3A8A, 0x3A8A5A]
let scarfChoices: [UInt32] = [0xE8C03A, 0xD03A3A, 0x2EB8B0, 0xF0F0F0, 0xE060A8]

func playerStyle(hairIdx: Int, scarfIdx: Int, head: Tier?, chest: Tier?, legs: Tier?) -> HumanStyle {
    var s = HumanStyle()
    s.skin = 0xF1C27D
    s.hair = hairChoices[clampI(hairIdx, 0, hairChoices.count - 1)]
    s.scarf = scarfChoices[clampI(scarfIdx, 0, scarfChoices.count - 1)]
    s.shirt = 0x8A5A2E
    s.sleeve = 0x7A4C24
    s.belt = 0xD8B060
    s.pants = 0x3A4A6E
    s.boots = 0x2A2A30
    if let t = head { s.hat = t == .wood ? 0x9A5A2A : t.color }
    if let t = chest {
        let c: UInt32 = t == .wood ? 0x9A5A2A : t.color
        s.shirt = c
        s.sleeve = shadeRGB(c, 0.82)
    }
    if let t = legs {
        let c: UInt32 = t == .wood ? 0x7A4A22 : t.color
        s.pants = shadeRGB(c, 0.85)
        s.boots = shadeRGB(c, 0.6)
    }
    return s
}

func zombieStyle(_ variant: Int) -> HumanStyle {
    var s = HumanStyle()
    s.skin = variant == 1 ? 0xC8B070 : (variant == 2 ? 0x6E9A7A : 0x6FA860)
    s.hair = variant == 1 ? 0x8A7A4A : 0x2E5A2E
    s.shirt = variant == 1 ? 0x9A8A5A : 0x3A8A8A
    s.sleeve = shadeRGB(s.shirt, 0.85)
    s.belt = 0x2A2A2A
    s.pants = 0x2B3A6B
    s.boots = 0x333333
    s.eye = 0xCC2222
    s.zombieArms = true
    return s
}

func skeletonStyle() -> HumanStyle {
    var s = HumanStyle()
    s.skin = 0xE8E4D4
    s.hair = 0
    s.shirt = 0xD8D4C4
    s.sleeve = 0xCFCAB8
    s.belt = 0x6A6A60
    s.pants = 0xCFCAB8
    s.boots = 0xB8B4A4
    s.weapon = .sword
    s.weaponColor = 0xB8C0CC
    s.shield = 0x8A5A2E
    s.ribs = true
    return s
}

func pirateStyle(_ captain: Bool) -> HumanStyle {
    var s = HumanStyle()
    s.skin = 0xE0B080
    s.hair = 0x2A1A10
    s.hat = captain ? 0x2A2A38 : 0xC03030
    s.hatStyle = captain ? 0 : 1
    s.shirt = captain ? 0x8A2A2A : 0xE8E8E0
    s.sleeve = captain ? 0x6A1E1E : 0xB04040
    s.belt = 0x2A2018
    s.pants = captain ? 0x2A2A38 : 0x5A4A3A
    s.boots = 0x1E1814
    s.weapon = .cutlass
    s.weaponColor = 0xC8CCD4
    return s
}

func pirateGunnerStyle() -> HumanStyle {
    var s = pirateStyle(false)
    s.weapon = .pistol
    s.shirt = 0x3A5A8A
    s.sleeve = 0x2E4A70
    return s
}

func villagerStyle(_ v: Int) -> HumanStyle {
    var s = HumanStyle()
    let robes: [UInt32] = [0x7A5A9A, 0x5A8A5A, 0xB07A3A, 0x4A7AA0]
    s.skin = 0xE8BC8C
    s.hair = [0x5A3A20, 0xB8B0A0, 0x2A2A2A, 0x8A5A2A][v % 4]
    s.shirt = robes[v % 4]
    s.sleeve = shadeRGB(robes[v % 4], 0.85)
    s.pants = shadeRGB(robes[v % 4], 0.7)
    s.belt = 0xC8A860
    s.boots = 0x4A3A2A
    return s
}

func impStyle() -> HumanStyle {
    var s = HumanStyle()
    s.skin = 0xC83A2A
    s.hair = 0x6A1010
    s.shirt = 0x4A1A1A
    s.sleeve = 0x3A1010
    s.belt = 0xFFB030
    s.pants = 0x4A1A1A
    s.boots = 0x2A0A0A
    s.eye = 0xFFE040
    s.zombieArms = true
    return s
}

// ===== p05b_animals =====

// MARK: - Animal sprite generators (procedural pixel art)

struct MGeo {
    var cx: Double
    var cy: Double
    var hx: Double
    var hy: Double
    var bw: Double
    var bh: Double
    var ground: Int
    var frame: Int
}

struct Mammal {
    var H: Int = 16
    var fur: UInt32 = 0x8A5A2A
    var dark: UInt32 = 0x5A3A1A
    var belly: UInt32 = 0xA8784A
    var nose: UInt32 = 0x1A1210
    var eye: UInt32 = 0x101010
    var bodyRX: Double = 8
    var bodyRY: Double = 4.5
    var legLen: Int = 4
    var legW: Int = 2
    var headRX: Double = 3.5
    var headRY: Double = 3.2
    var headDX: Double = 1.0
    var headDY: Double = -1.0
    var snout: Int = 2
    var ears: Int = 1
    var tail: Int = 1
    var tex: Double = 0.14
    var tailExtra: Int = 3
}

func mammalFrames(_ m: Mammal, seed: UInt64, _ decorate: ((inout PixelBuf, MGeo) -> Void)?) -> [PixelBuf] {
    var frames: [PixelBuf] = []
    let wD: Double = 2.0 + Double(m.tailExtra) + m.bodyRX * 2.0 + m.headDX + m.headRX * 2.0 + Double(m.snout) + 2.0
    let W: Int = Int(ceil(wD))
    let ground: Int = m.H - 2
    let bcx: Double = 2.0 + Double(m.tailExtra) + m.bodyRX
    let bcy: Double = Double(ground - m.legLen) - m.bodyRY + 1.0
    for f in 0..<3 {
        var b = PixelBuf(w: W, h: m.H)
        let xs: [Double] = [bcx - m.bodyRX * 0.62, bcx - m.bodyRX * 0.28, bcx + m.bodyRX * 0.30, bcx + m.bodyRX * 0.64]
        for i in 0..<4 {
            var lift: Int = 0
            if f == 1 && (i == 0 || i == 2) { lift = 1 }
            if f == 2 && (i == 1 || i == 3) { lift = 1 }
            let col: UInt32 = (i == 0 || i == 3) ? m.dark : shadeRGB(m.fur, 0.9)
            let lx: Int = Int(xs[i].rounded()) - m.legW / 2
            let top: Int = ground - m.legLen + 1
            b.rect(lx, top, m.legW, m.legLen - lift, col)
        }
        b.ellipse(bcx, bcy, m.bodyRX, m.bodyRY, m.fur)
        // belly shading
        let y0: Int = Int(floor(bcy)) - 1
        let y1: Int = Int(ceil(bcy + m.bodyRY)) + 1
        let x0: Int = Int(floor(bcx - m.bodyRX)) - 1
        let x1: Int = Int(ceil(bcx + m.bodyRX)) + 1
        for yy in y0...y1 {
            for xx in x0...x1 {
                let dx: Double = (Double(xx) + 0.5 - bcx) / m.bodyRX
                let dy: Double = (Double(yy) + 0.5 - bcy) / m.bodyRY
                if dx * dx + dy * dy <= 1.0 && dy > 0.45 { b.set(xx, yy, m.belly) }
            }
        }
        // tail
        if m.tail == 1 {
            b.rect(Int(bcx - m.bodyRX) - 1, Int(bcy - m.bodyRY * 0.5), 2, 2, m.fur)
        } else if m.tail == 2 {
            b.line(Int(bcx - m.bodyRX) + 1, Int(bcy - m.bodyRY * 0.4), Int(bcx - m.bodyRX) - m.tailExtra, Int(bcy - m.bodyRY * 0.1) + (f == 1 ? 1 : 0), m.dark)
        }
        // head
        let hx: Double = bcx + m.bodyRX + m.headDX
        let hy: Double = bcy + m.headDY
        b.ellipse(hx, hy, m.headRX, m.headRY, m.fur)
        if m.snout > 0 {
            b.rect(Int(hx + m.headRX) - 1, Int(hy) - 1 + (m.snout > 2 ? 1 : 0), m.snout, 2, shadeRGB(m.fur, 1.12))
            b.set(Int(hx + m.headRX) - 2 + m.snout, Int(hy) - 1 + (m.snout > 2 ? 1 : 0), m.nose)
        }
        if m.ears == 1 {
            b.ellipse(hx - m.headRX * 0.35, hy - m.headRY + 0.2, 1.5, 1.5, m.dark)
        } else if m.ears == 2 {
            b.set(Int(hx - 1.5), Int(hy - m.headRY) - 1, m.dark)
            b.set(Int(hx - 1.5), Int(hy - m.headRY), m.dark)
            b.set(Int(hx + 0.5), Int(hy - m.headRY) - 1, m.dark)
            b.set(Int(hx + 0.5), Int(hy - m.headRY), m.dark)
        }
        b.set(Int(hx + m.headRX * 0.35), Int(hy - m.headRY * 0.3), m.eye)
        let geo = MGeo(cx: bcx, cy: bcy, hx: hx, hy: hy, bw: m.bodyRX, bh: m.bodyRY, ground: ground, frame: f)
        if let d = decorate { d(&b, geo) }
        b.texture(seed, m.tex)
        b.underShade(0.86)
        b.outline(0x1A1410)
        frames.append(b)
    }
    return frames
}

func spritePig() -> [PixelBuf] {
    var m = Mammal()
    m.H = 14; m.fur = 0xF2A5B5; m.dark = 0xD97C8E; m.belly = 0xF8C0CC; m.nose = 0xD97C8E
    m.bodyRX = 6.5; m.bodyRY = 3.8; m.legLen = 3; m.headRX = 3.0; m.headRY = 2.8; m.headDX = 0.5; m.headDY = 0.3
    m.snout = 2; m.ears = 2; m.tail = 1; m.tailExtra = 1
    return mammalFrames(m, seed: 11, nil)
}

func spriteCow() -> [PixelBuf] {
    var m = Mammal()
    m.H = 19; m.fur = 0xF2F2EE; m.dark = 0x2E2E2C; m.belly = 0xE0D8D0; m.nose = 0xE8A0A8
    m.bodyRX = 8.5; m.bodyRY = 4.8; m.legLen = 5; m.headRX = 3.6; m.headRY = 3.4; m.headDX = 0.3; m.headDY = 0.0
    m.snout = 2; m.ears = 1; m.tail = 2; m.tailExtra = 3
    return mammalFrames(m, seed: 12) { b, g in
        for yy in 0..<b.h {
            for xx in 0..<b.w {
                let c: UInt32 = b.get(xx, yy)
                if (c >> 24) == 0 { continue }
                if c & 0xFFFFFF == 0xF2F2EE || c & 0xFFFFFF == 0xE0D8D0 {
                    if vnoise(Double(xx) * 0.33, Double(yy) * 0.33, 77) > 0.64 && Double(xx) < g.hx + 1 { b.set(xx, yy, 0x2E2E2C) }
                }
            }
        }
        b.set(Int(g.hx - 2), Int(g.hy - 4), 0xE8E0C8)
        b.set(Int(g.hx + 1), Int(g.hy - 4), 0xE8E0C8)
    }
}

func spriteSheep(shorn: Bool) -> [PixelBuf] {
    var m = Mammal()
    m.H = 16
    m.fur = shorn ? 0xE8B8A8 : 0xF0F0EA
    m.dark = 0x4A4A50
    m.belly = shorn ? 0xD8A898 : 0xDADAD4
    m.nose = 0x222222
    m.bodyRX = 7; m.bodyRY = 4.6; m.legLen = 4; m.headRX = 2.6; m.headRY = 2.5; m.headDX = 0.6; m.headDY = 0.8
    m.snout = 1; m.ears = 2; m.tail = 1; m.tailExtra = 2
    return mammalFrames(m, seed: 13) { b, g in
        if !shorn {
            var k: Int = 0
            while k < 9 {
                let ang: Double = Double(k) * 0.7
                b.ellipse(g.cx + cos(ang) * g.bw * 0.85, g.cy + sin(ang) * g.bh * 0.85, 1.8, 1.8, 0xF6F6F2)
                k += 1
            }
        }
        b.ellipse(g.hx, g.hy, 2.5, 2.4, 0x55555C)
        b.set(Int(g.hx + 1), Int(g.hy - 1), 0xE8E8E8)
        b.set(Int(g.hx + 2), Int(g.hy), 0x222222)
    }
}

func spriteBear(kind: Int) -> [PixelBuf] {
    // 0 brown, 1 grizzly, 2 polar
    var m = Mammal()
    m.H = kind == 0 ? 21 : 24
    m.fur = kind == 0 ? 0x6B4A2E : (kind == 1 ? 0x8A5A2A : 0xF2F6FC)
    m.dark = kind == 0 ? 0x4A3220 : (kind == 1 ? 0x5E3A18 : 0xD0DAE8)
    m.belly = kind == 0 ? 0x7A5A3A : (kind == 1 ? 0x9A6A34 : 0xE2EAF4)
    m.nose = 0x111111
    m.bodyRX = kind == 0 ? 9 : 10.5
    m.bodyRY = kind == 0 ? 5.5 : 6.5
    m.legLen = kind == 0 ? 4 : 5
    m.legW = 3
    m.headRX = kind == 0 ? 4.0 : 4.6
    m.headRY = kind == 0 ? 3.6 : 4.0
    m.headDX = 0.5; m.headDY = 0.6
    m.snout = kind == 2 ? 3 : 2
    m.ears = 1; m.tail = 1; m.tailExtra = 2
    return mammalFrames(m, seed: UInt64(20 + kind)) { b, g in
        if kind == 1 {
            b.ellipse(g.cx + g.bw * 0.45, g.cy - g.bh * 0.55, 4.5, 3.0, 0xA8783A)
        }
        let claw: UInt32 = 0xEDE6D0
        b.set(Int(g.cx + g.bw * 0.64) + 1, g.ground, claw)
        b.set(Int(g.cx + g.bw * 0.30) + 1, g.ground, claw)
    }
}

func spriteTiger() -> [PixelBuf] {
    var m = Mammal()
    m.H = 18; m.fur = 0xE8872A; m.dark = 0x2A1A10; m.belly = 0xF4E8D0; m.nose = 0xE06070
    m.bodyRX = 10; m.bodyRY = 4.4; m.legLen = 5; m.legW = 2; m.headRX = 3.8; m.headRY = 3.4; m.headDX = 0.6; m.headDY = -0.2
    m.snout = 1; m.ears = 1; m.tail = 2; m.tailExtra = 5
    return mammalFrames(m, seed: 31) { b, g in
        var x: Int = Int(g.cx - g.bw * 0.8)
        while x < Int(g.cx + g.bw * 0.8) {
            for yy in Int(g.cy - g.bh)...Int(g.cy + g.bh * 0.3) {
                let c: UInt32 = b.get(x, yy)
                if (c >> 24) != 0 && ((yy + x) % 5 != 0) { b.set(x, yy, 0x2A1A10) }
            }
            x += 3
        }
        b.set(Int(g.hx - 1), Int(g.hy - 2), 0x2A1A10)
        b.set(Int(g.hx + 1), Int(g.hy - 2), 0x2A1A10)
        b.set(Int(g.hx), Int(g.hy + 1), 0x2A1A10)
    }
}

func spriteElephant() -> [PixelBuf] {
    var m = Mammal()
    m.H = 34; m.fur = 0x8A8E96; m.dark = 0x6A6E78; m.belly = 0x9EA2AA; m.nose = 0x6A6E78
    m.bodyRX = 14; m.bodyRY = 9; m.legLen = 9; m.legW = 5; m.headRX = 6.5; m.headRY = 6.5; m.headDX = -1.5; m.headDY = 1.5
    m.snout = 0; m.ears = 0; m.tail = 2; m.tailExtra = 3
    return mammalFrames(m, seed: 41) { b, g in
        // ear
        b.ellipse(g.hx - 3.0, g.hy - 1.0, 3.6, 4.8, 0x7A7E88)
        b.ellipse(g.hx - 3.0, g.hy - 1.0, 2.2, 3.4, 0x9A9EA8)
        // trunk
        var k: Int = 0
        while k < 12 {
            let tx: Int = Int(g.hx + 6.5) - 2 + (k > 6 ? (k - 6) / 2 : 0)
            let ty: Int = Int(g.hy) + 1 + k
            b.rect(tx, ty, 3, 1, k > 9 ? 0x6A6E78 : 0x8A8E96)
            k += 1
        }
        // tusks
        b.line(Int(g.hx + 2), Int(g.hy + 4), Int(g.hx + 6), Int(g.hy + 6), 0xF4EEDC)
        b.line(Int(g.hx + 2), Int(g.hy + 5), Int(g.hx + 6), Int(g.hy + 7), 0xD8D2C0)
        b.set(Int(g.hx + 2), Int(g.hy - 2), 0x101010)
        b.set(Int(g.hx + 3), Int(g.hy - 2), 0x101010)
    }
}

func spriteGiraffe() -> [PixelBuf] {
    var m = Mammal()
    m.H = 46; m.fur = 0xE8C050; m.dark = 0x8A5A2A; m.belly = 0xF0D890; m.nose = 0x6A4A2A
    m.bodyRX = 7.5; m.bodyRY = 4.4; m.legLen = 14; m.legW = 2; m.headRX = 3.0; m.headRY = 2.3; m.headDX = 3.0; m.headDY = -18
    m.snout = 2; m.ears = 2; m.tail = 2; m.tailExtra = 3
    return mammalFrames(m, seed: 51) { b, g in
        // neck from shoulder up to head
        let sx: Double = g.cx + g.bw * 0.7
        let sy: Double = g.cy - g.bh * 0.5
        var t: Int = 0
        let steps: Int = Int(sy - g.hy) + 2
        while t <= steps {
            let f: Double = Double(t) / Double(max(1, steps))
            let nx: Double = sx + (g.hx - sx) * f
            let ny: Double = sy + (g.hy + 1 - sy) * f
            b.rect(Int(nx) - 2, Int(ny), 4, 1, 0xE8C050)
            t += 1
        }
        for yy in 0..<b.h {
            for xx in 0..<b.w {
                let c: UInt32 = b.get(xx, yy)
                if (c >> 24) == 0 { continue }
                if c & 0xFFFFFF == 0xE8C050 && vnoise(Double(xx) * 0.5, Double(yy) * 0.5, 91) > 0.62 { b.set(xx, yy, 0x8A5A2A) }
            }
        }
        b.set(Int(g.hx - 1), Int(g.hy - 3), 0x6A4A2A)
        b.set(Int(g.hx + 1), Int(g.hy - 3), 0x6A4A2A)
        b.set(Int(g.hx + 1), Int(g.hy - 1), 0x101010)
    }
}

func spriteWolf(tamedColors: Bool) -> [PixelBuf] {
    var m = Mammal()
    m.H = 14
    m.fur = tamedColors ? 0xC8A165 : 0x7A7E86
    m.dark = tamedColors ? 0x8B6B3E : 0x4E5258
    m.belly = tamedColors ? 0xE0C890 : 0xB8BCC4
    m.nose = 0x111111
    m.bodyRX = tamedColors ? 6.5 : 7.5; m.bodyRY = tamedColors ? 3.4 : 3.6; m.legLen = tamedColors ? 4 : 5; m.legW = 2
    m.headRX = 3.2; m.headRY = 2.7; m.headDX = 0.6; m.headDY = -0.8
    m.snout = 3; m.ears = tamedColors ? 1 : 2; m.tail = 2; m.tailExtra = 4
    if tamedColors { m.H = 13 }
    return mammalFrames(m, seed: tamedColors ? 61 : 62, nil)
}

func spriteCat() -> [PixelBuf] {
    var m = Mammal()
    m.H = 10; m.fur = 0xE0944A; m.dark = 0xA8642A; m.belly = 0xF4DDB0; m.nose = 0xFFB0C0
    m.bodyRX = 5; m.bodyRY = 2.8; m.legLen = 3; m.legW = 1; m.headRX = 2.4; m.headRY = 2.2; m.headDX = 0.4; m.headDY = -0.6
    m.snout = 0; m.ears = 2; m.tail = 2; m.tailExtra = 5
    return mammalFrames(m, seed: 71, nil)
}

func spriteFrog() -> [PixelBuf] {
    var m = Mammal()
    m.H = 8; m.fur = 0x4EA83A; m.dark = 0x2E7A28; m.belly = 0xC8E890; m.nose = 0x2E7A28
    m.bodyRX = 3.2; m.bodyRY = 2.2; m.legLen = 2; m.legW = 1; m.headRX = 2.0; m.headRY = 1.8; m.headDX = -0.4; m.headDY = -0.2
    m.snout = 0; m.ears = 0; m.tail = 0; m.tailExtra = 1
    return mammalFrames(m, seed: 81) { b, g in
        b.set(Int(g.hx), Int(g.hy - 2), 0xFFFFFF)
        b.set(Int(g.hx + 1), Int(g.hy - 2), 0xFFFFFF)
        b.set(Int(g.hx + 1), Int(g.hy - 2), 0x101010)
    }
}

// MARK: - Birds, fish, small creatures

func spriteCrow(colorA: UInt32, colorB: UInt32) -> [PixelBuf] {
    var out: [PixelBuf] = []
    for f in 0..<3 {
        var b = PixelBuf(w: 14, h: 12)
        b.ellipse(6.5, 7.0, 4.0, 2.6, colorA)
        b.ellipse(10.5, 5.0, 2.2, 2.0, colorA)
        b.rect(12, 5, 2, 1, 0xE8A030)
        b.set(11, 4, 0xFFFFFF)
        b.line(3, 7, 0, 8, colorB)
        b.line(3, 8, 0, 9, colorB)
        if f == 0 {
            b.line(4, 6, 8, 8, colorB)
            b.line(6, 10, 6, 10, 0xE8A030); b.line(8, 10, 8, 10, 0xE8A030)
        } else if f == 1 {
            b.line(5, 6, 3, 1, colorB); b.line(6, 6, 5, 1, colorB); b.line(7, 6, 8, 1, colorB)
        } else {
            b.line(5, 8, 2, 10, colorB); b.line(6, 8, 5, 11, colorB); b.line(7, 8, 8, 11, colorB)
        }
        b.texture(UInt64(91 + f), 0.12)
        b.outline(0x101018)
        out.append(b)
    }
    return out
}

func spriteChicken() -> [PixelBuf] {
    var out: [PixelBuf] = []
    for f in 0..<3 {
        var b = PixelBuf(w: 12, h: 11)
        b.ellipse(5.5, 6.0, 3.8, 3.0, 0xF4F4F0)
        b.ellipse(9.0, 3.6, 2.0, 2.0, 0xF4F4F0)
        b.rect(10, 1, 2, 1, 0xD83030)
        b.rect(11, 3, 2, 1, 0xE8B030)
        b.set(10, 3, 0x101010)
        b.rect(10, 5, 1, 2, 0xD83030)
        b.line(2, 5, 0, 4, 0xE0E0DA)
        b.line(3, 7, 6, 8, 0xD8D8D0)
        let lx: Int = f == 1 ? 4 : 5
        b.line(lx, 9, lx, 9, 0xE8B030); b.line(lx, 10, lx + (f == 1 ? -1 : 0), 10, 0xE8B030)
        b.line(7, 9, 7, 9, 0xE8B030); b.line(7, 10, 7 + (f == 2 ? 1 : 0), 10, 0xE8B030)
        b.outline(0x1A1410)
        out.append(b)
    }
    return out
}

func spriteFish() -> [PixelBuf] {
    var out: [PixelBuf] = []
    for f in 0..<2 {
        var b = PixelBuf(w: 12, h: 8)
        b.ellipse(6.0, 4.0, 3.8, 2.2, 0x6AA8D8)
        b.ellipse(6.0, 5.0, 3.2, 1.0, 0xC8E0F0)
        b.line(2, 4, 0, 2 + f * 2, 0x4A88B8)
        b.line(2, 4, 0, 6 - f * 2, 0x4A88B8)
        b.set(8, 3, 0x101010)
        b.rect(5, 1, 2, 1, 0x4A88B8)
        b.outline(0x1A2A3A)
        out.append(b)
    }
    return out
}

func spriteSlime(main: UInt32, glow: UInt32, eye: UInt32) -> [PixelBuf] {
    var out: [PixelBuf] = []
    for f in 0..<2 {
        var b = PixelBuf(w: 16, h: 13)
        let ry: Double = f == 0 ? 4.6 : 5.6
        let rx: Double = f == 0 ? 6.4 : 5.6
        b.ellipse(8.0, 11.0 - ry, rx, ry, main)
        b.ellipse(7.0, 11.0 - ry - 1.4, rx * 0.6, ry * 0.5, glow)
        b.rect(5, 11 - Int(ry) - 1, 2, 2, eye)
        b.rect(10, 11 - Int(ry) - 1, 2, 2, eye)
        b.texture(UInt64(101 + f), 0.1)
        b.outline(0x142A14)
        out.append(b)
    }
    return out
}

func spriteBat() -> [PixelBuf] {
    var out: [PixelBuf] = []
    for f in 0..<2 {
        var b = PixelBuf(w: 16, h: 11)
        b.ellipse(8.0, 6.0, 2.4, 2.8, 0x3B2A4A)
        b.set(7, 5, 0xFF4444); b.set(9, 5, 0xFF4444)
        b.set(6, 2, 0x3B2A4A); b.set(10, 2, 0x3B2A4A)
        if f == 0 {
            b.line(6, 5, 1, 2, 0x4A3860); b.line(6, 6, 1, 4, 0x4A3860); b.line(6, 7, 2, 7, 0x4A3860)
            b.line(10, 5, 15, 2, 0x4A3860); b.line(10, 6, 15, 4, 0x4A3860); b.line(10, 7, 14, 7, 0x4A3860)
        } else {
            b.line(6, 6, 1, 8, 0x4A3860); b.line(6, 7, 2, 10, 0x4A3860); b.line(6, 7, 4, 9, 0x4A3860)
            b.line(10, 6, 15, 8, 0x4A3860); b.line(10, 7, 14, 10, 0x4A3860); b.line(10, 7, 12, 9, 0x4A3860)
        }
        b.outline(0x120A1A)
        out.append(b)
    }
    return out
}

func spriteScorpion() -> [PixelBuf] {
    var out: [PixelBuf] = []
    for f in 0..<2 {
        var b = PixelBuf(w: 20, h: 13)
        b.ellipse(9.0, 9.0, 4.5, 2.4, 0xB8803A)
        b.ellipse(14.0, 9.0, 2.4, 2.0, 0xA8702E)
        b.line(5, 8, 3, 5, 0xA8702E); b.line(3, 5, 4, 2, 0xA8702E); b.line(4, 2, 8, 1, 0xA8702E)
        b.rect(8, 1, 2, 2, 0xE04A2A)
        b.line(15, 8, 18, 6 + f, 0xA8702E); b.rect(17, 5 + f, 2, 2, 0x8A5A22)
        b.line(15, 10, 18, 11 - f, 0xA8702E); b.rect(17, 10 - f, 2, 2, 0x8A5A22)
        for k in 0..<3 {
            let lx: Int = 7 + k * 2
            b.line(lx, 11, lx + (f == 0 ? -1 : 1), 12, 0x7A4A1A)
        }
        b.set(15, 8, 0x101010)
        b.texture(UInt64(111 + f), 0.14)
        b.outline(0x1A1008)
        out.append(b)
    }
    return out
}

func spriteWraith() -> [PixelBuf] {
    var out: [PixelBuf] = []
    for f in 0..<2 {
        var b = PixelBuf(w: 16, h: 22)
        b.ellipse(8.0, 8.0, 5.0, 6.0, 0x4A2A7A)
        b.rect(3, 8, 10, 10, 0x4A2A7A)
        for x in 3..<13 {
            let wob: Int = ((x + f * 2) % 4 < 2) ? 0 : 2
            b.rect(x, 18, 1, 1 + wob, 0x4A2A7A)
        }
        b.ellipse(8.0, 7.0, 3.2, 3.6, 0x14081E)
        b.rect(6, 6, 2, 2, 0xFFE040); b.rect(10, 6, 2, 2, 0xFFE040)
        b.rect(4, 10, 8, 1, 0x7A4AB0); b.rect(5, 13, 6, 1, 0x6A3AA0)
        b.texture(UInt64(121 + f), 0.12)
        b.outline(0x14081E)
        out.append(b)
    }
    return out
}

// ===== p05c_bosses =====

// MARK: - Boss, boat and vehicle-part sprites

func spriteBearBoss() -> [PixelBuf] {
    var out: [PixelBuf] = []
    var m = Mammal()
    m.H = 40; m.fur = 0x3A2A22; m.dark = 0x20140E; m.belly = 0x4A362A; m.nose = 0x0A0A0A; m.eye = 0xFF2A1A
    m.bodyRX = 16; m.bodyRY = 9.5; m.legLen = 10; m.legW = 6
    m.headRX = 7.5; m.headRY = 6.5; m.headDX = -1.0; m.headDY = 1.5
    m.snout = 4; m.ears = 1; m.tail = 1; m.tailExtra = 3; m.tex = 0.22
    let walk: [PixelBuf] = mammalFrames(m, seed: 201) { b, g in
        var x: Int = Int(g.cx - g.bw * 0.7)
        while x < Int(g.cx + g.bw * 0.55) {
            let nx: Double = (Double(x) - g.cx) / g.bw
            let inner: Double = max(0.05, 1.0 - nx * nx)
            let rise: Double = g.bh * sqrt(inner)
            let topY: Int = Int(g.cy - rise) - 1
            b.line(x, topY, x + 1, topY - 4, 0xD8D0B8)
            b.line(x + 1, topY, x + 1, topY - 3, 0xB8B098)
            x += 4
        }
        b.line(Int(g.hx - 3), Int(g.hy - 4), Int(g.hx + 3), Int(g.hy + 2), 0xB8A08A)
        b.line(Int(g.hx - 2), Int(g.hy - 4), Int(g.hx + 4), Int(g.hy + 2), 0x7A6050)
        b.rect(Int(g.hx + 2), Int(g.hy) - 3, 3, 2, 0xFF2A1A)
        b.set(Int(g.hx + 3), Int(g.hy) - 3, 0xFFE0A0)
        b.set(Int(g.hx + 7), Int(g.hy) + 2, 0xF4EEDC)
        b.set(Int(g.hx + 9), Int(g.hy) + 2, 0xF4EEDC)
        b.line(Int(g.hx + 8), Int(g.hy) + 2, Int(g.hx + 8), Int(g.hy) + 3, 0xF4EEDC)
        let claw: UInt32 = 0xEDE6D0
        b.rect(Int(g.cx + g.bw * 0.64) - 1, g.ground, 4, 1, claw)
        b.rect(Int(g.cx + g.bw * 0.30) - 1, g.ground, 4, 1, claw)
    }
    out.append(walk[1])
    out.append(walk[2])
    // rear-up pose and swipe pose
    for pose in 0..<2 {
        var b = PixelBuf(w: walk[0].w, h: 40)
        let cx: Double = 24
        b.rect(14, 28, 7, 9, 0x20140E); b.rect(30, 28, 7, 9, 0x2A1C14)
        b.rect(12, 37, 10, 1, 0xEDE6D0); b.rect(29, 37, 10, 1, 0xEDE6D0)
        b.ellipse(cx + 2, 22, 12.5, 14, 0x3A2A22)
        b.ellipse(cx + 3, 26, 8, 9, 0x4A362A)
        var sp: Int = 0
        while sp < 5 {
            b.line(8 + sp * 2, 14 + sp * 3, 5 + sp * 2, 11 + sp * 3, 0xD8D0B8)
            sp += 1
        }
        // head
        b.ellipse(cx + 8, 6, 8.5, 6.5, 0x3A2A22)
        b.rect(29, 7, 9, 5, 0x3A2A22)
        b.rect(31, 9, 8, 3, 0x6A0E0E)
        b.rect(31, 8, 1, 2, 0xF4EEDC); b.rect(34, 8, 1, 2, 0xF4EEDC); b.rect(37, 8, 1, 2, 0xF4EEDC)
        b.rect(32, 12, 1, 2, 0xF4EEDC); b.rect(36, 12, 1, 2, 0xF4EEDC)
        b.rect(30, 4, 3, 2, 0xFF2A1A); b.set(31, 4, 0xFFE0A0)
        b.ellipse(21, 1.5, 2, 2, 0x20140E); b.ellipse(31, 0.5, 2, 2, 0x20140E)
        b.line(22, 3, 28, 9, 0xB8A08A)
        if pose == 0 {
            // both arms raised
            b.rect(34, 8, 7, 14, 0x2A1C14)
            b.rect(36, 2, 8, 8, 0x3A2A22)
            b.rect(37, 0, 1, 3, 0xEDE6D0); b.rect(40, 0, 1, 3, 0xEDE6D0); b.rect(43, 1, 1, 3, 0xEDE6D0)
            b.rect(14, 10, 6, 12, 0x2A1C14)
        } else {
            // swing forward
            b.rect(33, 16, 20, 7, 0x3A2A22)
            b.rect(48, 14, 7, 11, 0x2A1C14)
            b.rect(53, 14, 3, 1, 0xEDE6D0); b.rect(54, 17, 3, 1, 0xEDE6D0); b.rect(54, 20, 3, 1, 0xEDE6D0); b.rect(53, 23, 3, 1, 0xEDE6D0)
            b.rect(14, 12, 6, 12, 0x2A1C14)
        }
        b.texture(UInt64(210 + pose), 0.22)
        b.outline(0x0A0604)
        out.append(b)
    }
    return out
}

func spriteTRex() -> [PixelBuf] {
    var out: [PixelBuf] = []
    let skin: UInt32 = 0x5E8A3A
    let dark: UInt32 = 0x3E6428
    let belly: UInt32 = 0xC8C88A
    for f in 0..<3 {
        var b = PixelBuf(w: 76, h: 46)
        let lift: Int = f == 1 ? 2 : 0
        let lift2: Int = f == 0 ? 2 : 0
        // legs
        b.ellipse(36, 31, 6.5, 8.5, dark)
        b.rect(32, 36, 5, 7 - lift, dark)
        b.rect(28, 42 - lift, 10, 3, dark)
        b.rect(28, 44 - lift, 3, 1, 0xEDE6D0); b.rect(32, 44 - lift, 3, 1, 0xEDE6D0); b.rect(36, 44 - lift, 3, 1, 0xEDE6D0)
        b.ellipse(26, 31, 6.5, 8.5, skin)
        b.rect(22, 36, 5, 7 - lift2, skin)
        b.rect(18, 42 - lift2, 10, 3, skin)
        b.rect(18, 44 - lift2, 3, 1, 0xEDE6D0); b.rect(22, 44 - lift2, 3, 1, 0xEDE6D0); b.rect(26, 44 - lift2, 3, 1, 0xEDE6D0)
        // body & tail
        b.ellipse(32, 24, 16, 9.5, skin)
        b.ellipse(34, 28, 12, 5, belly)
        var t: Int = 0
        while t < 22 {
            let tx: Int = 18 - t
            let ty: Int = 22 + t / 4
            let th: Int = max(2, 8 - t / 3)
            b.rect(tx, ty - th / 2, 2, th, t % 2 == 0 ? skin : dark)
            t += 1
        }
        // neck & head
        b.ellipse(46, 17, 7, 8, skin)
        let open: Bool = f == 2
        b.ellipse(56, 11, 10, 7, skin)
        b.rect(60, 11, 14, 4, skin)
        b.rect(74, 11, 1, 3, dark)
        // lower jaw
        let jy: Int = open ? 19 : 15
        b.rect(54, jy, 19, 3, dark)
        if open {
            b.rect(58, 15, 15, 4, 0x6A0E1E)
            b.rect(60, 18, 12, 1, 0xE06070)
        }
        // teeth
        var tx: Int = 60
        while tx < 74 {
            b.set(tx, 15, 0xF4F0DC)
            b.set(tx, 16, 0xF4F0DC)
            if open { b.set(tx + 1, jy - 1, 0xF4F0DC) }
            tx += 3
        }
        b.rect(56, 6, 4, 3, 0xFFC820); b.set(58, 7, 0x101010)
        b.rect(66, 8, 2, 1, dark)
        b.line(52, 4, 56, 3, dark)
        // tiny arms
        b.line(50, 24, 54, 28, dark); b.line(54, 28, 56, 28, 0xEDE6D0)
        b.line(49, 25, 52, 29, skin)
        // back ridge
        var rx: Int = 22
        while rx < 46 {
            b.set(rx, 15 + (abs(rx - 34) / 3), dark)
            rx += 3
        }
        b.texture(UInt64(220 + f), 0.2)
        b.outline(0x14240A)
        out.append(b)
    }
    return out
}

func spritePirateBoat() -> PixelBuf {
    var b = PixelBuf(w: 76, h: 40)
    let wood: UInt32 = 0x6A4220
    let woodHi: UInt32 = 0x8A5A2E
    let woodLo: UInt32 = 0x3E2610
    // hull rows
    for y in 22..<34 {
        let k: Int = y - 22
        let x0: Int = 4 + k
        let x1: Int = 70 - k
        b.rect(x0, y, x1 - x0, 1, (y % 3 == 0) ? woodLo : wood)
    }
    b.rect(3, 21, 68, 2, woodHi)
    b.rect(4, 22, 66, 1, 0xA8743A)
    // cannon ports
    var p: Int = 16
    while p < 60 {
        b.rect(p, 26, 3, 3, 0x14100A)
        b.set(p + 1, 27, 0x6A6A70)
        p += 12
    }
    // rails
    b.rect(5, 17, 64, 1, woodHi)
    var rp: Int = 5
    while rp < 70 {
        b.rect(rp, 17, 1, 5, wood)
        rp += 6
    }
    // bowsprit
    b.line(70, 21, 75, 16, wood)
    // mast and yard
    b.rect(36, 3, 3, 18, woodHi)
    b.rect(36, 3, 1, 18, wood)
    b.rect(24, 6, 27, 2, woodHi)
    // sail
    b.rect(25, 8, 25, 11, 0xE8E0C8)
    b.rect(25, 8, 25, 1, 0xC8C0A8)
    for i in 0..<6 {
        b.rect(26 + i * 4, 17 + (i % 2), 2, 2, 0xE8E0C8)
        b.rect(27 + i * 4, 9, 1, 8, 0xD0C8B0)
    }
    // skull emblem
    b.rect(35, 10, 5, 4, 0x1A1A1E)
    b.set(36, 11, 0xE8E0C8); b.set(38, 11, 0xE8E0C8)
    b.rect(36, 14, 3, 1, 0x1A1A1E)
    // flag
    b.rect(39, 0, 8, 4, 0x1A1A1E)
    b.set(42, 1, 0xE8E0C8)
    b.rect(39, 2, 2, 1, 0x1A1A1E)
    b.outline(0x0A0604)
    return b
}

func partBuf(_ p: PartType) -> PixelBuf {
    var b = PixelBuf(w: 8, h: 8)
    switch p {
    case .frame:
        b.rect(0, 0, 8, 1, 0xA8783A); b.rect(0, 7, 8, 1, 0x6A4A22)
        b.rect(0, 0, 1, 8, 0xA8783A); b.rect(7, 0, 1, 8, 0x6A4A22)
        b.line(1, 1, 6, 6, 0x8A5A2E); b.line(1, 6, 6, 1, 0x8A5A2E)
    case .wheel:
        b.ellipse(4, 4, 4, 4, 0x1E1E22)
        b.ellipse(4, 4, 2.4, 2.4, 0xA0A0AA)
        b.set(4, 4, 0x3A3A44)
        b.set(3, 3, 0xD8D8E0)
    case .engine:
        b.rect(0, 1, 8, 6, 0x6A6A74)
        b.rect(0, 1, 8, 1, 0x9A9AA4)
        b.rect(1, 3, 4, 2, 0xE06A2A)
        b.rect(6, 3, 2, 2, 0x3A3A44)
        b.rect(2, 0, 1, 1, 0xA8A8B0); b.rect(5, 0, 1, 1, 0xA8A8B0)
    case .steering:
        b.ellipse(4, 4, 3.4, 3.4, 0x8A5A2E)
        b.ellipse(4, 4, 1.8, 1.8, 0)
        b.rect(3, 6, 2, 2, 0x4A4A52)
    case .seat:
        b.rect(1, 0, 2, 6, 0x9A3A3A)
        b.rect(1, 5, 6, 2, 0xB04A4A)
        b.rect(1, 7, 1, 1, 0x4A4A52); b.rect(6, 7, 1, 1, 0x4A4A52)
    case .fuelTank:
        b.rect(1, 1, 6, 6, 0xC03A3A)
        b.rect(1, 1, 6, 1, 0xE06A6A)
        b.rect(3, 0, 2, 1, 0x4A4A52)
        b.rect(2, 3, 4, 2, 0xF0E0A0)
    case .hull:
        b.rect(0, 3, 8, 2, 0xB98A4E)
        b.rect(0, 5, 8, 2, 0x7A5628)
        b.rect(1, 7, 6, 1, 0x4A3216)
        b.rect(0, 2, 8, 1, 0xE8E0C8)
    case .propeller:
        b.rect(3, 0, 2, 8, 0x9A9AA4)
        b.rect(0, 3, 8, 2, 0x7A7A84)
        b.rect(3, 3, 2, 2, 0x4A4A52)
    case .paddle:
        b.line(0, 7, 5, 2, 0x8A5A2E)
        b.rect(5, 0, 3, 4, 0xB98A4E)
    case .drill, .diamondDrill:
        // drawn pointing right; the renderer turns it to face its open side
        let bit: UInt32 = p == .drill ? 0xC8CCD4 : 0x6FE6EC
        b.rect(0, 1, 3, 6, 0x5A5A64); b.rect(0, 1, 3, 1, 0x8A8A94)
        b.rect(3, 1, 2, 6, bit); b.rect(5, 2, 1, 4, bit); b.rect(6, 3, 1, 2, bit); b.set(7, 3, bit); b.set(7, 4, shadeRGB(bit, 0.7))
        b.set(3, 2, shadeRGB(bit, 0.65)); b.set(4, 4, shadeRGB(bit, 0.65)); b.set(3, 6, shadeRGB(bit, 0.65)); b.set(5, 5, shadeRGB(bit, 0.65))
    }
    b.outline(0x1A1410)
    return b
}

// ===== p06_worldgen =====

// MARK: - World generation (deterministic, chunk based)

enum Biome: Int, Codable {
    case ocean, plains, forest, desert, tundra, jungle, savanna, swamp, mountain, umbral

    var name: String {
        switch self {
        case .ocean: return "Ocean"
        case .plains: return "Plains"
        case .forest: return "Forest"
        case .desert: return "Desert"
        case .tundra: return "Snowy Tundra"
        case .jungle: return "Jungle"
        case .savanna: return "Savanna"
        case .swamp: return "Swamp"
        case .mountain: return "Mountains"
        case .umbral: return "Umbral Realm"
        }
    }
}

enum Dimension: Int, Codable {
    case overworld, umbral
}

enum LairKind: Int { case bear, rex }

struct Col {
    var h: Int
    var biome: Biome
    var land: Double
    var mtn: Double
    var swamp: Double
}

struct VillageSite {
    var cell: Int
    var x: Int
    var halfW: Int
    var seed: UInt64
    var ground: Int
    var biome: Biome
}

enum RareKind: Int {
    case house, tower, fort, camp, overgrown, bunker
}

struct RareSite {
    var cell: Int
    var x: Int
    var kind: RareKind
    var seed: UInt64
}

struct LairInfo {
    var kind: LairKind
    var cx: Int
    var k: Int
}

/// Memoised world-generation lookups. Column, village and ruin queries are pure functions of the
/// seed, but chunk generation asked for the same ones thousands of times (every column checks three
/// village cells, and every village check samples ~14 columns). A class so the value-type WorldGen
/// can share it.
final class GenCache {
    var cols: [Int: Col] = [:]
    var villages: [Int: VillageSite?] = [:]
    var rares: [Int: RareSite?] = [:]
    var hits: Int = 0
    var misses: Int = 0

    func clear() {
        cols.removeAll(keepingCapacity: true)
        villages.removeAll(keepingCapacity: true)
        rares.removeAll(keepingCapacity: true)
    }

    /// Keeps memory bounded in infinite worlds
    func trim() {
        if cols.count > 24_000 { cols.removeAll(keepingCapacity: true) }
        if villages.count > 4_000 { villages.removeAll(keepingCapacity: true) }
        if rares.count > 8_000 { rares.removeAll(keepingCapacity: true) }
    }
}

struct WorldGen {
    let cache: GenCache = GenCache()
    let seed: UInt64
    let infinite: Bool
    let width: Int
    let spawnX: Int
    /// 1 = original rules (kept for worlds saved before ocean basins), 2 = with ocean basins
    let genVersion: Int
    static let currentVersion: Int = 2
    let rareChance: Double
    let zones: [Int]
    var portalX: Int
    var portalY: Int
    static let H: Int = 560
    static let sea: Int = 120
    static let villageCell: Int = 640
    static let rareCell: Int = 192
    static let finiteWidth: Int = 4096
    static let edgeOcean: Int = 520

    /// Finite worlds lay biome zones out in a seeded order so every biome is always present.
    /// climate ids: 0 tundra, 1 plains, 2 forest, 3 desert, 4 jungle, 5 savanna, 6 swamp
    static func makeZones(_ seed: UInt64, _ infinite: Bool) -> [Int] {
        if infinite { return [] }
        var pool: [Int] = [0, 3, 5, 6, 1, 2]
        let extra: [Int] = [0, 3, 5, 1, 2]
        pool[5] = extra[Int(hash2(7, 7, seed) * 5.0) % 5]
        var rng = RNG(seed &+ 4242)
        var i: Int = pool.count - 1
        while i > 0 {
            let j: Int = rng.int(i + 1)
            pool.swapAt(i, j)
            i -= 1
        }
        var z: [Int] = [Int](repeating: 1, count: 9)
        z[1] = 4
        z[4] = hash2(8, 8, seed) < 0.5 ? 1 : 2
        z[7] = 2
        let slots: [Int] = [0, 2, 3, 5, 6, 8]
        for k in 0..<6 { z[slots[k]] = pool[k] }
        return z
    }

    init(seed: UInt64, infinite: Bool, rareChance: Double, genVersion: Int = WorldGen.currentVersion) {
        self.genVersion = genVersion
        self.seed = seed
        self.infinite = infinite
        self.width = infinite ? 2_000_000_000 : WorldGen.finiteWidth
        self.spawnX = infinite ? 0 : WorldGen.finiteWidth / 2
        self.rareChance = rareChance
        self.zones = WorldGen.makeZones(seed, infinite)
        // provisional values so methods can be used while searching for the portal
        self.portalX = 0
        self.portalY = 0
        let hs: Double = hash2(1, 2, seed)
        let dist: Int = infinite ? 1500 + Int(hs * 1800.0) : 300 + Int(hs * 400.0)
        let side: Int = hash2(3, 4, seed) < 0.5 ? -1 : 1
        var found: Int = spawnX + side * dist
        var ok: Bool = false
        for attempt in 0..<4 {
            let sd: Int = attempt % 2 == 0 ? side : -side
            let dd: Int = attempt < 2 ? dist : (infinite ? 2400 : 520)
            var step: Int = 0
            while step < 400 && !ok {
                let off: Int = ((step % 2 == 0) ? 1 : -1) * ((step + 1) / 2) * 5
                let x: Int = spawnX + sd * dd + off
                let c: Col = WorldGen.colBaseStatic(seed, infinite, width, spawnX, zones, x, basins: genVersion >= 2)
                if c.biome != .ocean && c.biome != .swamp && c.land > 0.5 && WorldGen.lairStatic(spawnX, infinite, x, 230) == nil && abs(x - spawnX) < 3800 && abs(x - spawnX) > 200 {
                    found = x
                    ok = true
                }
                step += 1
            }
            if ok { break }
        }
        self.portalX = found
        self.portalY = 350 + Int(hash2(5, 6, seed) * 60.0)
    }

    // MARK: lairs

    static func lairStatic(_ spawnX: Int, _ infinite: Bool, _ x: Int, _ radius: Int) -> LairInfo? {
        let period: Int = 4096
        let bases: [Int] = [spawnX + 1000, spawnX - 1100]
        for i in 0..<2 {
            let base: Int = bases[i]
            var k: Int = Int((Double(x - base) / Double(period)).rounded())
            if !infinite { k = 0 }
            let cx: Int = base + k * period
            if abs(x - cx) < radius { return LairInfo(kind: i == 0 ? .bear : .rex, cx: cx, k: k) }
        }
        return nil
    }

    func lairAt(_ x: Int, radius: Int = 150) -> LairInfo? {
        return WorldGen.lairStatic(spawnX, infinite, x, radius)
    }

    func lairCenters(near x: Int) -> [LairInfo] {
        var out: [LairInfo] = []
        let period: Int = 4096
        let bases: [Int] = [spawnX + 1000, spawnX - 1100]
        for i in 0..<2 {
            let base: Int = bases[i]
            let kc: Int = infinite ? Int((Double(x - base) / Double(period)).rounded()) : 0
            let ks: [Int] = infinite ? [kc - 1, kc, kc + 1] : [0]
            for k in ks { out.append(LairInfo(kind: i == 0 ? .bear : .rex, cx: base + k * period, k: k)) }
        }
        return out
    }

    // MARK: climate & terrain

    static let zoneClimate: [(Double, Double)] = [
        (0.14, 0.50), (0.50, 0.33), (0.50, 0.64), (0.88, 0.14), (0.88, 0.88), (0.88, 0.50), (0.50, 0.90)
    ]

    /// position inside the zone layout: 0 = centre of first zone ... count-1 = centre of last
    static func zoneCoord(_ width: Int, _ count: Int, _ x: Int) -> Double {
        let x0: Double = Double(WorldGen.edgeOcean)
        let zw: Double = (Double(width) - 2.0 * x0) / Double(count)
        return (Double(x) - x0) / zw - 0.5
    }

    static func climate(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ zones: [Int], _ x: Int) -> (Double, Double) {
        let fx: Double = Double(x)
        var temp: Double = fbm1(fx / 700.0, seed &+ 11, 2)
        var humid: Double = fbm1(fx / 520.0, seed &+ 12, 2)
        if infinite || zones.count < 2 {
            temp = 0.5 + (temp - 0.5) * 1.3
            humid = 0.5 + (humid - 0.5) * 1.3
            return (temp, humid)
        }
        let t: Double = clampD(zoneCoord(width, zones.count, x), 0, Double(zones.count - 1) - 0.0001)
        let i: Int = Int(t)
        let f: Double = t - Double(i)
        let s: Double = smooth(clampD((f - 0.3) / 0.4, 0, 1))
        let a: (Double, Double) = zoneClimate[zones[i]]
        let b: (Double, Double) = zoneClimate[zones[i + 1]]
        temp = lerpD(a.0, b.0, s) + (temp - 0.5) * 0.30
        humid = lerpD(a.1, b.1, s) + (humid - 0.5) * 0.30
        return (temp, humid)
    }

    /// 0...1 bump marking a mountain range centred somewhere near x
    static func rangeBump(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ x: Int) -> Double {
        var best: Double = 0
        if infinite {
            let cellW: Int = 1100
            let c0: Int = floorDiv(x, cellW)
            for c in (c0 - 1)...(c0 + 1) {
                if hash2(c, 302, seed) > 0.52 { continue }
                let cen: Int = c * cellW + 200 + Int(hash2(c, 303, seed) * 700.0)
                let hw: Double = 130.0 + hash2(c, 304, seed) * 110.0
                let b: Double = smooth(clampD(1.0 - Double(abs(x - cen)) / hw, 0, 1))
                best = max(best, b)
            }
        } else {
            let zw: Double = (Double(width) - 2.0 * Double(WorldGen.edgeOcean)) / 9.0
            let ka: Int = 2 + Int(hash2(1, 305, seed) * 2.0)
            let kb: Int = 6 + Int(hash2(2, 305, seed) * 2.0)
            let ca: Double = Double(WorldGen.edgeOcean) + zw * Double(ka) + (hash2(1, 307, seed) - 0.5) * 80.0
            let cb: Double = Double(WorldGen.edgeOcean) + zw * Double(kb) + (hash2(2, 307, seed) - 0.5) * 80.0
            let cs: [Double] = [ca, cb]
            for k in 0..<2 {
                let hw: Double = 160.0 + hash2(k, 306, seed) * 70.0
                let b: Double = smooth(clampD(1.0 - abs(Double(x) - cs[k]) / hw, 0, 1))
                best = max(best, b)
            }
        }
        return best
    }

    /// Lair centres near x (bear at spawn+1000, rex at spawn-1100, repeating every 4096 in infinite worlds)
    static func lairCentersStatic(_ spawnX: Int, _ infinite: Bool, _ x: Int) -> [Int] {
        var out: [Int] = []
        for base in [spawnX + 1000, spawnX - 1100] {
            if !infinite { out.append(base); continue }
            let k: Int = Int((Double(x - base) / 4096.0).rounded())
            for kk in (k - 1)...(k + 1) { out.append(base + kk * 4096) }
        }
        return out
    }

    /// One ocean basin: centre, half width of the open water, and the coastal ramp width
    struct Basin {
        var center: Int
        var halfW: Int
        var ramp: Int
    }

    /// The guaranteed sea near spawn, on a seeded side, so every world has an ocean within reach
    static func homeBasin(_ seed: UInt64, _ spawnX: Int) -> Basin {
        let side: Int = hash2(41, 42, seed) < 0.5 ? -1 : 1
        let off: Int = 560 + Int(hash2(43, 44, seed) * 120.0)
        return Basin(center: spawnX + side * off, halfW: 150 + Int(hash2(45, 46, seed) * 50.0), ramp: 110)
    }

    /// Random large basins in infinite worlds (about two in five 1600-wide cells), kept clear of spawn and lairs
    static func cellBasin(_ seed: UInt64, _ spawnX: Int, _ c: Int) -> Basin? {
        if hash2(c, 401, seed) > 0.26 { return nil }
        let cellW: Int = 1600
        let hw: Int = 140 + Int(hash2(c, 402, seed) * 220.0)
        let cen: Int = c * cellW + hw + 140 + Int(hash2(c, 403, seed) * Double(max(1, cellW - 2 * hw - 280)))
        if abs(cen - spawnX) < hw + 900 { return nil }
        for lc in lairCentersStatic(spawnX, true, cen) where abs(cen - lc) < hw + 330 { return nil }
        return Basin(center: cen, halfW: hw, ramp: 140)
    }

    /// 0...1: how strongly x lies inside an ocean basin (1 = open sea, ramping down over the coast)
    static func oceanBasin(_ seed: UInt64, _ infinite: Bool, _ spawnX: Int, _ x: Int) -> Double {
        func weight(_ b: Basin) -> Double {
            let d: Double = Double(abs(x - b.center))
            return 1.0 - smooth(clampD((d - Double(b.halfW)) / Double(b.ramp), 0, 1))
        }
        var w: Double = weight(homeBasin(seed, spawnX))
        if infinite {
            let c0: Int = floorDiv(x, 1600)
            for c in (c0 - 1)...(c0 + 1) {
                if let b = cellBasin(seed, spawnX, c) { w = max(w, weight(b)) }
            }
        }
        return w
    }

    static func colBaseStatic(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ spawnX: Int, _ zones: [Int], _ x: Int, basins: Bool = true) -> Col {
        let fx: Double = Double(x)
        let H: Int = WorldGen.H
        let sea: Int = WorldGen.sea
        var land: Double = fbm1(fx / 800.0, seed &+ 1, 3)
        if !infinite {
            let e: Double = Double(min(x, width - 1 - x))
            let eo: Double = Double(WorldGen.edgeOcean)
            if e < eo { land *= smooth(clampD(e / eo, 0, 1)) }
            if x < 0 || x >= width { land = 0 }
            if zones.count > 1 && e > eo * 0.55 {
                // guarantee some dry land in the middle of every biome zone
                let zc: Double = zoneCoord(width, zones.count, x) + 0.5
                let fr: Double = abs(zc - zc.rounded(.down) - 0.5)
                let wgt: Double = 1.0 - smooth(clampD((fr - 0.2) / 0.2, 0, 1))
                land = lerpD(land, max(land, 0.62), wgt)
            }
        }
        let ds: Double = Double(abs(x - spawnX))
        if ds < 320 { land = lerpD(land, max(land, 0.64), min(1.0, (1.0 - ds / 320.0) * 1.6)) }
        var lw: Double = 0
        var forced: Biome? = nil
        if let L = WorldGen.lairStatic(spawnX, infinite, x, 150) {
            let d: Double = Double(abs(x - L.cx))
            lw = 1.0 - smooth(clampD((d - 60.0) / 90.0, 0, 1))
            land = max(land, lerpD(land, 0.65, lw))
            if d < 120 { forced = L.kind == .bear ? .forest : .jungle }
        }
        // ocean basins pull the land value down into deep water (after the spawn/lair guarantees,
        // which basins are placed well away from)
        let basin: Double = basins ? WorldGen.oceanBasin(seed, infinite, spawnX, x) : 0
        if basin > 0 { land = min(land, lerpD(land, 0.17, basin)) }
        let mraw: Double = max(fbm1(fx / 420.0, seed &+ 3, 2) - 0.08, 0.56 + 0.40 * WorldGen.rangeBump(seed, infinite, width, x))
        var mtn: Double = smooth(clampD((mraw - 0.60) / 0.16, 0, 1)) * clampD((land - 0.45) / 0.1, 0, 1)
        mtn *= clampD((ds - 170.0) / 130.0, 0, 1)
        if lw > 0 { mtn *= (1.0 - lw) }
        let cl: (Double, Double) = WorldGen.climate(seed, infinite, width, zones, x)
        let temp: Double = cl.0
        let humid: Double = cl.1
        let tundra: Double = smooth(clampD((0.31 - temp) / 0.06, 0, 1))
        let hot: Double = smooth(clampD((temp - 0.64) / 0.06, 0, 1))
        let desert: Double = hot * smooth(clampD((0.42 - humid) / 0.06, 0, 1))
        let jungle: Double = hot * smooth(clampD((humid - 0.58) / 0.06, 0, 1))
        let savanna: Double = hot * (1.0 - desert) * (1.0 - jungle)
        var swamp: Double = smooth(clampD((humid - 0.68) / 0.06, 0, 1)) * (1.0 - tundra) * (1.0 - hot)
        if lw > 0 { swamp *= (1.0 - lw) }
        var biome: Biome = humid > 0.5 ? .forest : .plains
        if tundra > 0.5 { biome = .tundra }
        else if desert > 0.5 { biome = .desert }
        else if jungle > 0.5 { biome = .jungle }
        else if savanna > 0.5 { biome = .savanna }
        else if swamp > 0.5 { biome = .swamp }
        if mtn > 0.35 { biome = .mountain }
        if land < 0.40 { biome = .ocean }
        if let f = forced { biome = f }
        let amp: Double = max(0.12, 1.0 - 0.4 * tundra - 0.3 * desert - 0.5 * savanna - 0.88 * swamp + 0.15 * jungle)
        var h: Double
        if land >= 0.40 {
            let t: Double = clampD((land - 0.40) / 0.25, 0, 1)
            h = Double(sea) - 2.0 - t * 12.0
            let hills: Double = (fbm1(fx / 55.0, seed &+ 2, 3) - 0.5) * 2.0 * 15.0 * amp
            let bumps: Double = (noise1(fx / 9.0, seed &+ 8) - 0.5) * 3.0 * amp
            h -= hills + bumps
            let v: Double = fbm1(fx / 140.0, seed &+ 5, 2)
            if v < 0.36 { h += (0.36 - v) / 0.36 * 16.0 * min(1.0, amp) }
            let cliff: Double = noise1(fx / 95.0, seed &+ 6)
            if cliff > 0.72 { h -= 10.0 * smooth(clampD((cliff - 0.72) / 0.015, 0, 1)) }
            let peak: Double = fbm1(fx / 70.0, seed &+ 4, 4)
            h -= mtn * (14.0 + peak * 70.0)
            if swamp > 0 {
                let target: Double = Double(sea) + (noise1(fx / 14.0, seed &+ 9) - 0.55) * 5.0
                h = lerpD(h, target, swamp)
            }
        } else {
            let d: Double = clampD((0.40 - land) / 0.14, 0, 1)
            h = Double(sea) - 2.0 + d * 48.0 + (noise1(fx / 7.0, seed &+ 10) - 0.5) * 3.0 * d
        }
        if lw > 0 { h = lerpD(h, Double(sea - 10), lw) }
        let hi: Int = clampI(Int(h.rounded()), 14, H - 80)
        return Col(h: hi, biome: biome, land: land, mtn: mtn, swamp: swamp)
    }

    func colBase(_ x: Int) -> Col {
        if let c = cache.cols[x] {
            cache.hits &+= 1
            return c
        }
        cache.misses &+= 1
        let c: Col = WorldGen.colBaseStatic(seed, infinite, width, spawnX, zones, x, basins: genVersion >= 2)
        cache.cols[x] = c
        return c
    }

    // MARK: village sites

    func villageSite(cell c: Int) -> VillageSite? {
        if let v = cache.villages[c] { return v }
        let v: VillageSite? = computeVillageSite(cell: c)
        cache.villages[c] = v
        return v
    }

    func computeVillageSite(cell c: Int) -> VillageSite? {
        let cellW: Int = WorldGen.villageCell
        let spawnCell: Bool = floorDiv(spawnX, cellW) == c
        if !spawnCell && hash2(c, 99, seed) > 0.62 { return nil }
        var sx: Int = c * cellW + 120 + Int(hash2(c, 98, seed) * Double(cellW - 240))
        if spawnCell {
            let side: Int = hash2(c, 96, seed) < 0.5 ? -1 : 1
            sx = spawnX + side * (150 + Int(hash2(c, 98, seed) * 60.0))
        }
        let halfW: Int = 28 + Int(hash2(c, 97, seed) * 12.0)
        let base: Col = colBase(sx)
        let ok: [Biome] = [.plains, .forest, .savanna, .desert, .tundra, .jungle]
        if !ok.contains(base.biome) || base.land < 0.5 { return nil }
        if lairAt(sx, radius: 330) != nil && !spawnCell { return nil }
        // footprint must be on land
        var dx: Int = -halfW
        while dx <= halfW {
            let cc: Col = colBase(sx + dx)
            if cc.biome == .ocean || cc.biome == .mountain || cc.biome == .swamp { return nil }
            if abs(cc.h - base.h) > 45 { return nil }
            dx += 6
        }
        if !infinite && (sx - halfW < 300 || sx + halfW > width - 300) { return nil }
        return VillageSite(cell: c, x: sx, halfW: halfW, seed: hashU(c, 55, seed), ground: base.h, biome: base.biome)
    }

    func villages(overlapping x0: Int, _ x1: Int) -> [VillageSite] {
        var out: [VillageSite] = []
        let cellW: Int = WorldGen.villageCell
        let c0: Int = floorDiv(x0 - 80, cellW) - 1
        let c1: Int = floorDiv(x1 + 80, cellW) + 1
        for c in c0...c1 {
            if let v = villageSite(cell: c) {
                if v.x + v.halfW + 8 >= x0 && v.x - v.halfW - 8 <= x1 { out.append(v) }
            }
        }
        return out
    }

    func nearestVillage(to x: Int) -> VillageSite? {
        let vs: [VillageSite] = villages(overlapping: x - 700, x + 700)
        var best: VillageSite? = nil
        var bd: Int = Int.max
        for v in vs {
            let d: Int = abs(v.x - x)
            if d < bd { bd = d; best = v }
        }
        return best
    }

    // MARK: rare sites

    func rareSite(cell c: Int) -> RareSite? {
        if let r = cache.rares[c] { return r }
        let r: RareSite? = computeRareSite(cell: c)
        cache.rares[c] = r
        return r
    }

    func computeRareSite(cell c: Int) -> RareSite? {
        if hash2(c, 71, seed) > rareChance { return nil }
        let cellW: Int = WorldGen.rareCell
        let sx: Int = c * cellW + 32 + Int(hash2(c, 72, seed) * Double(cellW - 64))
        let base: Col = colBase(sx)
        if base.biome == .ocean || base.land < 0.45 { return nil }
        if lairAt(sx, radius: 260) != nil { return nil }
        if abs(sx - portalX) < 90 { return nil }
        if !infinite && (sx < 300 || sx > width - 300) { return nil }
        if nearestVillageSimple(sx) { return nil }
        let r: Double = hash2(c, 73, seed)
        var kind: RareKind = .house
        if r < 0.17 { kind = .house }
        else if r < 0.34 { kind = .tower }
        else if r < 0.51 { kind = .fort }
        else if r < 0.68 { kind = .camp }
        else if r < 0.84 { kind = .overgrown }
        else { kind = .bunker }
        return RareSite(cell: c, x: sx, kind: kind, seed: hashU(c, 74, seed))
    }

    func nearestVillageSimple(_ x: Int) -> Bool {
        let cellW: Int = WorldGen.villageCell
        let c0: Int = floorDiv(x, cellW)
        for c in (c0 - 1)...(c0 + 1) {
            if let v = villageSite(cell: c) {
                if abs(v.x - x) < v.halfW + 90 { return true }
            }
        }
        return false
    }

    func rareSites(overlapping x0: Int, _ x1: Int) -> [RareSite] {
        var out: [RareSite] = []
        let cellW: Int = WorldGen.rareCell
        let c0: Int = floorDiv(x0 - 40, cellW)
        let c1: Int = floorDiv(x1 + 40, cellW)
        for c in c0...c1 {
            if let s = rareSite(cell: c) {
                if s.x + 30 >= x0 && s.x - 30 <= x1 { out.append(s) }
            }
        }
        return out
    }

    /// Full column info including village flattening
    func col(_ x: Int) -> Col {
        var c: Col = colBase(x)
        let cellW: Int = WorldGen.villageCell
        let c0: Int = floorDiv(x, cellW)
        for cc in (c0 - 1)...(c0 + 1) {
            if let v = villageSite(cell: cc) {
                let d: Int = abs(x - v.x)
                if d <= v.halfW + 10 {
                    let t: Double = clampD(Double(d - v.halfW) / 10.0, 0, 1)
                    c.h = Int(lerpD(Double(v.ground), Double(c.h), t).rounded())
                    if d <= v.halfW + 4 && c.biome != .ocean { c.biome = v.biome }
                }
            }
        }
        return c
    }
}

// ===== p07_chunk =====

// MARK: - Chunks

let chunkW: Int = 16

final class Chunk {
    let cx: Int
    let H: Int
    var tiles: [UInt8]
    var skyTop: [Int]
    var dirty: Bool = false
    var hasSky: Bool = true
    var rev: Int = 0
    var surf: [Int] = [Int](repeating: 0, count: chunkW)
    var ceilY: [Int] = [Int](repeating: 0, count: chunkW)
    var back: [UInt8] = []
    var walls: [UInt8] = []
    var backRev: Int = -1
    /// change counter per 16-row section (the renderer only rebuilds sections that changed)
    var secRev: [Int]

    init(cx: Int, H: Int) {
        self.cx = cx
        self.H = H
        self.tiles = [UInt8](repeating: 0, count: chunkW * H)
        self.skyTop = [Int](repeating: 0, count: chunkW)
        self.secRev = [Int](repeating: 0, count: H / 16 + 1)
    }

    /// Marks every section touching rows y0...y1 as changed
    func bumpRows(_ y0: Int, _ y1: Int) {
        let n: Int = secRev.count
        var s: Int = max(0, y0) / 16
        let e: Int = min(n - 1, max(0, y1) / 16)
        while s <= e {
            secRev[s] &+= 1
            s += 1
        }
    }

    func bumpAll() {
        for i in 0..<secRev.count { secRev[i] &+= 1 }
    }

    var x0: Int { return cx * chunkW }

    @inline(__always) func get(_ lx: Int, _ y: Int) -> Tile {
        if y < 0 { return .air }
        if y >= H { return .bedrock }
        return Tile.make(tiles[lx * H + y])
    }

    @inline(__always) func raw(_ lx: Int, _ y: Int) -> UInt8 {
        return tiles[lx * H + y]
    }

    func setLocal(_ lx: Int, _ y: Int, _ t: Tile) {
        if lx < 0 || lx >= chunkW || y < 0 || y >= H { return }
        tiles[lx * H + y] = t.rawValue
    }

    /// Global-x write used by structure builders; ignores anything outside this chunk
    func put(_ x: Int, _ y: Int, _ t: Tile) {
        let lx: Int = x - x0
        if lx < 0 || lx >= chunkW || y < 1 || y >= H - 1 { return }
        tiles[lx * H + y] = t.rawValue
    }

    func putIfAir(_ x: Int, _ y: Int, _ t: Tile) {
        let lx: Int = x - x0
        if lx < 0 || lx >= chunkW || y < 1 || y >= H - 1 { return }
        if tiles[lx * H + y] == Tile.air.rawValue { tiles[lx * H + y] = t.rawValue }
    }

    func at(_ x: Int, _ y: Int) -> Tile {
        let lx: Int = x - x0
        if lx < 0 || lx >= chunkW || y < 0 || y >= H { return .air }
        return Tile.make(tiles[lx * H + y])
    }

    func fill(_ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ t: Tile) {
        if xb < xa || yb < ya { return }
        for x in xa...xb {
            if x < x0 || x >= x0 + chunkW { continue }
            for y in ya...yb { put(x, y, t) }
        }
    }

    /// Global-x background wall write used by structure builders
    func putWall(_ x: Int, _ y: Int, _ k: UInt8) {
        let lx: Int = x - x0
        if lx < 0 || lx >= chunkW || y < 1 || y >= H - 1 { return }
        if walls.isEmpty { walls = [UInt8](repeating: 0, count: chunkW * H) }
        walls[lx * H + y] = k
    }

    func fillWall(_ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ k: UInt8) {
        if xb < xa || yb < ya { return }
        for x in xa...xb { for y in ya...yb { putWall(x, y, k) } }
    }

    func rebuildSky() {
        for lx in 0..<chunkW { recomputeSky(lx) }
    }

    func recomputeSky(_ lx: Int) {
        if !hasSky { skyTop[lx] = H; return }
        var y: Int = 0
        while y < H {
            if Tile.opaqueTable[Int(tiles[lx * H + y])] { break }
            y += 1
        }
        skyTop[lx] = y
    }
}

// MARK: - Cave, ore and tree rules

struct OreRule {
    var tile: Tile
    var minY: Int
    var maxY: Int
    var thr: Double
    var p: Double
    var salt: UInt64
}

let oreRules: [OreRule] = [
    OreRule(tile: .coal, minY: 128, maxY: 340, thr: 0.80, p: 0.70, salt: 31),
    OreRule(tile: .copper, minY: 150, maxY: 370, thr: 0.84, p: 0.65, salt: 32),
    OreRule(tile: .iron, minY: 205, maxY: 450, thr: 0.855, p: 0.62, salt: 33),
    OreRule(tile: .gold, minY: 310, maxY: 530, thr: 0.885, p: 0.58, salt: 34),
    OreRule(tile: .diamond, minY: 390, maxY: 548, thr: 0.925, p: 0.55, salt: 35),
    OreRule(tile: .mythril, minY: 455, maxY: 548, thr: 0.945, p: 0.55, salt: 36)
]

func oreBias(_ b: Biome, _ t: Tile) -> Double {
    switch (b, t) {
    case (.desert, .gold): return 0.045
    case (.mountain, .iron): return 0.035
    case (.mountain, .mythril): return 0.03
    case (.tundra, .diamond): return 0.03
    case (.jungle, .copper): return 0.04
    case (.savanna, .gold): return 0.03
    case (.swamp, .coal): return 0.05
    default: return 0
    }
}

extension WorldGen {
    func isCave(_ x: Int, _ y: Int, _ depth: Int) -> Bool {
        if depth < 5 { return false }
        let fx: Double = Double(x)
        let fy: Double = Double(y)
        // winding tunnels follow the 0.5 contour of a smooth noise field
        let region: Double = vnoise(fx * 0.013, fy * 0.013, seed &+ 25)
        if region > 0.34 {
            let a: Double = vnoise(fx * 0.045, fy * 0.06, seed &+ 21)
            let w: Double = 0.030 + 0.05 * vnoise(fx * 0.02, fy * 0.02, seed &+ 22)
            if abs(a - 0.5) < w { return true }
        }
        // big chambers
        if depth > 26 {
            let c: Double = vnoise(fx * 0.03, fy * 0.045, seed &+ 23) * 0.65 + vnoise(fx * 0.085, fy * 0.1, seed &+ 24) * 0.35
            let bonus: Double = min(0.05, Double(max(0, y - 150)) * 0.00015)
            if c > 0.715 - bonus { return true }
        }
        // surface shafts: a few cave mouths
        if depth < 40 {
            let n: Double = noise1(fx / 18.0, seed &+ 26)
            if n > 0.90 && vnoise(fx * 0.2, fy * 0.2, seed &+ 27) > 0.35 { return true }
        }
        return false
    }

    func oreAt(_ x: Int, _ y: Int, _ biome: Biome) -> Tile? {
        let fx: Double = Double(x)
        let fy: Double = Double(y)
        for r in oreRules {
            if y < r.minY || y > r.maxY { continue }
            let blob: Double = vnoise(fx * 0.22, fy * 0.22, seed &+ r.salt)
            if blob + oreBias(biome, r.tile) > r.thr {
                if hash2(x, y, seed &+ 40 &+ r.salt) < r.p { return r.tile }
            }
        }
        return nil
    }

    func rockAt(_ x: Int, _ y: Int) -> Tile {
        let hy: Double = hash2(x, y / 3, seed &+ 5)
        let hoff: Double = (hy - 0.5) * 12.0
        let by: Int = y + Int(hoff)
        if by < 300 { return .stone }
        if by < 430 { return .slate }
        return .deepRock
    }

    func treeDensity(_ b: Biome, _ h: Int) -> Double {
        switch b {
        case .forest: return 0.14
        case .plains: return 0.04
        case .jungle: return 0.22
        case .savanna: return 0.04
        case .tundra: return 0.08
        case .swamp: return 0.10
        case .mountain: return h > 98 ? 0.05 : 0.0
        case .desert: return 0.035
        default: return 0.0
        }
    }
}

// MARK: - Overworld chunk generation

func generateOverworldChunk(_ g: WorldGen, _ cx: Int) -> Chunk {
    let H: Int = WorldGen.H
    let sea: Int = WorldGen.sea
    let ch = Chunk(cx: cx, H: H)
    let x0: Int = cx * chunkW
    let m: Int = 12
    var cols: [Col] = []
    for x in (x0 - m)..<(x0 + chunkW + m) { cols.append(g.col(x)) }
    func colAt(_ x: Int) -> Col { return cols[x - (x0 - m)] }
    var surfBiome: [Biome] = []
    var samp: GenSampler = GenSampler(g)
    defer { samp.free() }
    for lx in 0..<chunkW {
        let x: Int = x0 + lx
        let c: Col = colAt(x)
        samp.startColumn(x, c.h)
        let hj: Double = hash2(x, 1, g.seed &+ 61)
        let jd: Double = (hj - 0.5) * 10.0
        let jit: Int = Int(jd)
        var sb: Biome = colAt(x + jit).biome
        if c.biome == .ocean { sb = .ocean }
        else if sb == .ocean { sb = c.biome }
        surfBiome.append(sb)
        let base: Int = lx * H
        if !g.infinite && (x < 0 || x >= g.width) {
            for y in 0..<H { ch.tiles[base + y] = Tile.bedrock.rawValue }
            continue
        }
        let h: Int = c.h
        ch.surf[lx] = h
        var topT: Tile = .grass
        var fillT: Tile = .dirt
        var fillD: Int = 5
        switch sb {
        case .plains, .forest: break
        case .desert: topT = .sand; fillT = .sand; fillD = 9
        case .tundra: topT = .snow; fillT = .snow; fillD = 3
        case .jungle: topT = .jungleGrass; fillT = .mud; fillD = 7
        case .savanna: topT = .dryGrass; fillD = 4
        case .swamp: topT = .mossGrass; fillT = .mud; fillD = 6
        case .ocean: topT = .sand; fillT = .sand; fillD = 5
        case .mountain:
            if h <= 72 { topT = .snow; fillT = .snow; fillD = 3 }
            else if h <= 100 { topT = .stone; fillT = .stone; fillD = 4 }
        case .umbral: break
        }
        if sb != .ocean && sb != .swamp && sb != .desert && h >= sea - 1 && h <= sea + 2 { topT = .sand; fillT = .sand; fillD = 4 }
        if h > sea {
            for y in sea..<h {
                ch.tiles[base + y] = ((sb == .tundra && y == sea) ? Tile.ice : Tile.water).rawValue
            }
        }
        ch.tiles.withUnsafeMutableBufferPointer { tb in
            guard let tp = tb.baseAddress else { return }
            var y: Int = h
            while y < H {
                let depth: Int = y - h
                var t: Tile
                if y >= H - 1 { t = .bedrock }
                else if y >= H - 5 && hash2(x, y, g.seed &+ 3) < Double(y - (H - 6)) * 0.22 { t = .bedrock }
                else if depth == 0 { t = topT }
                else if depth < fillD { t = (sb == .tundra && depth >= 3) ? .dirt : fillT }
                else if sb == .desert && depth < 24 { t = .sandstone }
                else { t = samp.rockAt(x, y) }
                if depth >= 4 && y < H - 5 {
                    if samp.isCave(x, y, depth) {
                        if y >= 500 { t = .lava }
                        else if y > 200 && y < 430 && hash2(x / 60, y / 48, g.seed &+ 28) < 0.28 && (y % 48) > 28 { t = .water }
                        else { t = .air }
                    } else if depth > 8 && t != .sand && t != .snow {
                        if let o = samp.oreAt(x, y, c.biome) { t = o }
                    }
                }
                tp[base + y] = t.rawValue
                y += 1
            }
        }
        // underground decoration on cave floors / ceilings
        var y: Int = h + 8
        while y < H - 6 {
            if ch.tiles[base + y] == Tile.air.rawValue {
                let below: Tile = Tile.make(ch.tiles[base + y + 1])
                let above: Tile = Tile.make(ch.tiles[base + y - 1])
                if below.solid && below != .bedrock && y > 190 && y < 470 && hash2(x, y, g.seed &+ 81) < 0.025 {
                    ch.tiles[base + y] = Tile.mushroom.rawValue
                } else if above.solid && hash2(x, y, g.seed &+ 82) < 0.012 {
                    ch.tiles[base + y] = Tile.cobweb.rawValue
                }
            }
            y += 1
        }
    }
    // surface plants & trees
    let villages: [VillageSite] = g.villages(overlapping: x0 - 20, x0 + chunkW + 20)
    let rares: [RareSite] = g.rareSites(overlapping: x0 - 30, x0 + chunkW + 30)
    func blocked(_ x: Int) -> Bool {
        for v in villages { if abs(x - v.x) < v.halfW + 6 { return true } }
        for r in rares { if abs(x - r.x) < 16 { return true } }
        if let l = g.lairAt(x, radius: 110) { _ = l; return true }
        return false
    }
    func isTree(_ x: Int) -> Bool {
        let c: Col = colAt(x)
        let d: Double = g.treeDensity(c.biome, c.h)
        if d <= 0 { return false }
        if hash2(x, 3, g.seed &+ 99) >= d { return false }
        if c.h > sea - 1 && c.biome != .swamp { return false }
        return true
    }
    for lx in -6..<(chunkW + 6) {
        let x: Int = x0 + lx
        if !g.infinite && (x < 4 || x > g.width - 5) { continue }
        let c: Col = colAt(x)
        if c.biome == .ocean || blocked(x) { continue }
        let sbIdx: Int = lx >= 0 && lx < chunkW ? lx : -1
        let sb: Biome = sbIdx >= 0 ? surfBiome[sbIdx] : c.biome
        // plants (only for columns inside this chunk)
        if sbIdx >= 0 {
            let r: Double = hash2(x, 5, g.seed &+ 90)
            let gy: Int = c.h - 1
            let surf: Tile = ch.get(lx, c.h)
            if gy > 0 && ch.get(lx, gy) == .air && c.h <= sea {
                switch (sb, surf) {
                case (.plains, .grass), (.forest, .grass):
                    if r < 0.20 { ch.setLocal(lx, gy, .tallGrass) } else if r < 0.235 { ch.setLocal(lx, gy, .flowerR) } else if r < 0.27 { ch.setLocal(lx, gy, .flowerY) }
                case (.jungle, .jungleGrass):
                    if r < 0.30 { ch.setLocal(lx, gy, .tallGrass) } else if r < 0.34 { ch.setLocal(lx, gy, .flowerR) }
                case (.savanna, .dryGrass):
                    if r < 0.14 { ch.setLocal(lx, gy, .tallGrass) }
                case (.swamp, .mossGrass):
                    if r < 0.14 { ch.setLocal(lx, gy, .reed) } else if r < 0.17 { ch.setLocal(lx, gy, .mushroom) }
                case (.desert, .sand):
                    if r < 0.03 { ch.setLocal(lx, gy, .deadBush) }
                default: break
                }
            }
        }
        // trees: origin at x, drawn clipped into this chunk
        if !isTree(x) { continue }
        if isTree(x - 1) || isTree(x - 2) || isTree(x - 3) { continue }
        if abs(colAt(x - 1).h - colAt(x + 1).h) > 1 { continue }
        let tr: Double = hash2(x, 4, g.seed &+ 98)
        let gy: Int = c.h
        let tb: Biome = c.biome
        if tb == .desert {
            let th: Int = 2 + Int(tr * 4.0)
            for k in 1...th { ch.put(x, gy - k, .cactus) }
            if th >= 4 { ch.put(x - 1, gy - 3, .cactus); ch.put(x + 1, gy - 2, .cactus) }
        } else if tb == .jungle {
            let th: Int = 9 + Int(tr * 9.0)
            for k in 1...th { ch.put(x, gy - k, .jungleLog) }
            for dy in -3...1 { for dx in -4...4 {
                if abs(dx) == 4 && abs(dy + 1) > 1 { continue }
                if abs(dx) + abs(dy + 1) > 6 { continue }
                ch.putIfAir(x + dx, gy - th + dy, .jungleLeaves)
            } }
        } else if tb == .savanna {
            let th: Int = 5 + Int(tr * 3.0)
            for k in 1...th { ch.put(x, gy - k, .log) }
            for dx in -4...4 { ch.putIfAir(x + dx, gy - th, .leaves) }
            for dx in -2...2 { ch.putIfAir(x + dx, gy - th - 1, .leaves) }
        } else if tb == .tundra || (tb == .mountain && c.h > 98) {
            let th: Int = 6 + Int(tr * 5.0)
            for k in 1...th { ch.put(x, gy - k, .log) }
            var layer: Int = 0
            while layer < th - 1 {
                let wdt: Int = min(3, 1 + layer / 2)
                for dx in -wdt...wdt { ch.putIfAir(x + dx, gy - th - 1 + layer, .leaves) }
                layer += 1
            }
            ch.putIfAir(x, gy - th - 2, .leaves)
        } else if tb == .swamp {
            let th: Int = 4 + Int(tr * 2.0)
            for k in 1...th { ch.put(x, gy - k, .log) }
            for dx in -3...3 { ch.putIfAir(x + dx, gy - th, .jungleLeaves); if abs(dx) < 3 { ch.putIfAir(x + dx, gy - th - 1, .jungleLeaves) } }
        } else {
            let th: Int = 4 + Int(tr * 4.0)
            for k in 1...th { ch.put(x, gy - k, .log) }
            for dy in -3...1 { for dx in -2...2 {
                if abs(dx) == 2 && (dy == -3 || dy == 1) { continue }
                ch.putIfAir(x + dx, gy - th + dy, .leaves)
            } }
        }
    }
    // palms on warm beaches
    for lx in 0..<chunkW {
        let x: Int = x0 + lx
        let c: Col = colAt(x)
        if c.biome == .ocean || c.h < sea - 3 || c.h > sea + 1 { continue }
        if ch.get(lx, c.h) != .sand || ch.get(lx, c.h - 1) != .air { continue }
        if hash2(x, 6, g.seed &+ 97) > 0.035 { continue }
        let th: Int = 6 + Int(hash2(x, 7, g.seed &+ 97) * 4.0)
        for k in 1...th { ch.put(x + (k > th - 3 ? 1 : 0), c.h - k, .palmLog) }
        for dx in -3...4 { ch.putIfAir(x + 1 + dx, c.h - th - (abs(dx - 0) > 2 ? 0 : 1), .jungleLeaves) }
    }
    applyStructures(g, ch, cols, x0 - m)
    ch.rebuildSky()
    return ch
}

// MARK: - Column samplers for chunk generation

/// Fills out[y - y0] with vnoise(fx, Double(y) * fyScale, seed) for y in y0...y1. Gives bit-identical
/// values to vnoise(), but hashes each lattice row once instead of four hashes per sample, and makes
/// no function calls per sample (in debug builds each call costs more than the maths).
func columnNoise(_ seed: UInt64, _ fx: Double, _ fyScale: Double, _ y0: Int, _ y1: Int, _ out: inout [Double]) {
    if y1 < y0 { return }
    let n: Int = y1 - y0 + 1
    if out.count < n { out = [Double](repeating: 0, count: n) }
    let fx0: Double = floor(fx)
    let xi: Int = Int(fx0)
    let fu: Double = fx - fx0
    let u: Double = fu * fu * (3.0 - 2.0 * fu)
    var rowI: Int = Int.min
    var a: Double = 0, b: Double = 0, c: Double = 0, d: Double = 0
    var top: Double = 0
    var bot: Double = 0
    // fy0 tracks floor(fy) incrementally (samples only move forward), avoiding a libm call per sample
    var fy0: Double = floor(Double(y0) * fyScale)
    out.withUnsafeMutableBufferPointer { bp in
        guard let p = bp.baseAddress else { return }
        var y: Int = y0
        var k: Int = 0
        while k < n {
            let fy: Double = Double(y) * fyScale
            while fy >= fy0 + 1.0 { fy0 += 1.0 }
            let yi: Int = Int(fy0)
            if yi != rowI {
                if yi == rowI &+ 1 {
                    a = c
                    b = d
                } else {
                    a = hash2(xi, yi, seed)
                    b = hash2(xi + 1, yi, seed)
                }
                c = hash2(xi, yi + 1, seed)
                d = hash2(xi + 1, yi + 1, seed)
                top = a + (b - a) * u
                bot = c + (d - c) * u
                rowI = yi
            }
            let f: Double = fy - fy0
            let v: Double = f * f * (3.0 - 2.0 * f)
            p[k] = top + (bot - top) * v
            y += 1
            k += 1
        }
    }
}

/// Cave, ore and rock sampling for one column at a time. startColumn() precomputes every noise
/// field the column needs; isCave/oreAt/rockAt then only read buffers. Same results as the
/// per-tile WorldGen.isCave/oreAt/rockAt.
/// Written for debug builds: a struct used as a local `var` with mutating methods (no copies and
/// no runtime exclusivity checks), and raw buffers instead of arrays (no retain/release per read).
/// Call free() when done.
struct GenSampler {
    let seed: UInt64
    let H: Int
    var top: Int = 0
    var chamTop: Int = 0
    var shaftN: Double = 0
    var biasBiome: Int = -1
    var rockY3: Int = Int.min
    var rockH: Double = 0
    var scratch: [Double] = []
    let region: UnsafeMutablePointer<Double>
    let tunnel: UnsafeMutablePointer<Double>
    let width: UnsafeMutablePointer<Double>
    let cham: UnsafeMutablePointer<Double>
    let shaft: UnsafeMutablePointer<Double>
    let ores: UnsafeMutablePointer<Double>
    /// per ore rule: [lo, hi] rows, threshold+bias, chance, salt, tile
    let oreLo: UnsafeMutablePointer<Int>
    let oreHi: UnsafeMutablePointer<Int>
    let oreThr: UnsafeMutablePointer<Double>
    let oreP: UnsafeMutablePointer<Double>
    let oreSalt: UnsafeMutablePointer<UInt64>
    let oreTile: UnsafeMutablePointer<UInt8>
    let nOre: Int

    init(_ g: WorldGen) {
        seed = g.seed
        H = WorldGen.H
        nOre = oreRules.count
        region = UnsafeMutablePointer<Double>.allocate(capacity: H)
        tunnel = UnsafeMutablePointer<Double>.allocate(capacity: H)
        width = UnsafeMutablePointer<Double>.allocate(capacity: H)
        cham = UnsafeMutablePointer<Double>.allocate(capacity: H)
        shaft = UnsafeMutablePointer<Double>.allocate(capacity: H)
        ores = UnsafeMutablePointer<Double>.allocate(capacity: H * oreRules.count)
        oreLo = UnsafeMutablePointer<Int>.allocate(capacity: oreRules.count)
        oreHi = UnsafeMutablePointer<Int>.allocate(capacity: oreRules.count)
        oreThr = UnsafeMutablePointer<Double>.allocate(capacity: oreRules.count)
        oreP = UnsafeMutablePointer<Double>.allocate(capacity: oreRules.count)
        oreSalt = UnsafeMutablePointer<UInt64>.allocate(capacity: oreRules.count)
        oreTile = UnsafeMutablePointer<UInt8>.allocate(capacity: oreRules.count)
        for k in 0..<oreRules.count {
            oreP[k] = oreRules[k].p
            oreSalt[k] = oreRules[k].salt
            oreTile[k] = oreRules[k].tile.rawValue
            oreThr[k] = oreRules[k].thr
            oreLo[k] = 0
            oreHi[k] = -1
        }
    }

    func free() {
        region.deallocate(); tunnel.deallocate(); width.deallocate(); cham.deallocate(); shaft.deallocate()
        ores.deallocate(); oreLo.deallocate(); oreHi.deallocate(); oreThr.deallocate(); oreP.deallocate()
        oreSalt.deallocate(); oreTile.deallocate()
    }

    private mutating func fill(_ dst: UnsafeMutablePointer<Double>, _ s: UInt64, _ fx: Double, _ fyScale: Double, _ y0: Int, _ y1: Int) {
        if y1 < y0 { return }
        columnNoise(s, fx, fyScale, y0, y1, &scratch)
        let n: Int = y1 - y0 + 1
        scratch.withUnsafeBufferPointer { bp in
            guard let src = bp.baseAddress else { return }
            dst.update(from: src, count: n)
        }
    }

    /// Call once per column (h = surface row) before sampling it
    mutating func startColumn(_ cx: Int, _ h: Int) {
        rockY3 = Int.min
        let fx: Double = Double(cx)
        shaftN = noise1(fx / 18.0, seed &+ 26)
        top = h + 5
        chamTop = h + 27
        let y1: Int = H - 1
        fill(region, seed &+ 25, fx * 0.013, 0.013, top, y1)
        fill(tunnel, seed &+ 21, fx * 0.045, 0.06, top, y1)
        fill(width, seed &+ 22, fx * 0.02, 0.02, top, y1)
        // chambers: keep the combined value
        if chamTop <= y1 {
            let n: Int = y1 - chamTop + 1
            fill(cham, seed &+ 23, fx * 0.03, 0.045, chamTop, y1)
            columnNoise(seed &+ 24, fx * 0.085, 0.1, chamTop, y1, &scratch)
            let c: UnsafeMutablePointer<Double> = cham
            scratch.withUnsafeBufferPointer { bp in
                guard let src = bp.baseAddress else { return }
                var k: Int = 0
                while k < n { c[k] = c[k] * 0.65 + src[k] * 0.35; k += 1 }
            }
        }
        if shaftN > 0.90 { fill(shaft, seed &+ 27, fx * 0.2, 0.2, top, min(y1, h + 39)) }
        var k: Int = 0
        while k < nOre {
            let lo: Int = max(oreRules[k].minY, h + 9)
            let hi: Int = min(oreRules[k].maxY, H - 6)
            oreLo[k] = lo
            oreHi[k] = hi
            if hi >= lo { fill(ores + k * H, seed &+ oreSalt[k], fx * 0.22, 0.22, lo, hi) }
            k += 1
        }
    }

    mutating func isCave(_ x: Int, _ y: Int, _ depth: Int) -> Bool {
        if depth < 5 || y < top { return false }
        let i: Int = y - top
        if region[i] > 0.34 {
            let a: Double = tunnel[i]
            let w: Double = 0.030 + 0.05 * width[i]
            if abs(a - 0.5) < w { return true }
        }
        if depth > 26 && y >= chamTop {
            let bonus: Double = min(0.05, Double(max(0, y - 150)) * 0.00015)
            if cham[y - chamTop] > 0.715 - bonus { return true }
        }
        if depth < 40 && shaftN > 0.90 {
            if shaft[i] > 0.35 { return true }
        }
        return false
    }

    mutating func oreAt(_ x: Int, _ y: Int, _ biome: Biome) -> Tile? {
        if biome.rawValue != biasBiome {
            biasBiome = biome.rawValue
            var k: Int = 0
            while k < nOre {
                oreThr[k] = oreRules[k].thr - oreBias(biome, oreRules[k].tile)
                k += 1
            }
        }
        var k: Int = 0
        while k < nOre {
            let lo: Int = oreLo[k]
            if y >= lo && y <= oreHi[k] {
                if ores[k * H + (y - lo)] > oreThr[k] {
                    if hash2(x, y, seed &+ 40 &+ oreSalt[k]) < oreP[k] { return Tile.make(oreTile[k]) }
                }
            }
            k += 1
        }
        return nil
    }

    mutating func rockAt(_ x: Int, _ y: Int) -> Tile {
        let y3: Int = y / 3
        if y3 != rockY3 {
            rockY3 = y3
            rockH = hash2(x, y3, seed &+ 5)
        }
        let hoff: Double = (rockH - 0.5) * 12.0
        let by: Int = y + Int(hoff)
        if by < 300 { return .stone }
        if by < 430 { return .slate }
        return .deepRock
    }
}

// ===== p08a_villages =====

// MARK: - Structures: villages

struct Palette {
    var wall: Tile
    var post: Tile
    var roof: Tile
    var floor: Tile
    var path: Tile
}

func villagePalette(_ b: Biome) -> Palette {
    switch b {
    case .desert: return Palette(wall: .sandstone, post: .sandstone, roof: .sandstone, floor: .sandstone, path: .sandstone)
    case .tundra: return Palette(wall: .planks, post: .log, roof: .snow, floor: .planks, path: .stone)
    case .savanna: return Palette(wall: .planks, post: .log, roof: .hay, floor: .planks, path: .dirt)
    case .jungle: return Palette(wall: .planks, post: .jungleLog, roof: .hay, floor: .planks, path: .mud)
    default: return Palette(wall: .planks, post: .log, roof: .brick, floor: .planks, path: .dirt)
    }
}

func buildHouse(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ ht: Int, _ pal: Palette, _ seed: UInt64) {
    ch.fill(x - 1, gy - ht - w / 2 - 3, x + w, gy - 1, .air)
    ch.fill(x, gy, x + w - 1, gy, pal.floor)
    for yy in (gy - ht)...(gy - 1) {
        ch.put(x, yy, pal.wall)
        ch.put(x + w - 1, yy, pal.wall)
    }
    ch.put(x, gy - 1, pal.post); ch.put(x, gy - ht, pal.post)
    ch.put(x + w - 1, gy - 1, pal.post); ch.put(x + w - 1, gy - ht, pal.post)
    // doorway on one side, window on the other
    let doorLeft: Bool = hash2(x, 1, seed) < 0.5
    let dx: Int = doorLeft ? x : x + w - 1
    let wx: Int = doorLeft ? x + w - 1 : x
    ch.put(dx, gy - 1, .doorClosed); ch.put(dx, gy - 2, .doorClosed)
    ch.put(wx, gy - 3, .glass)
    // background wall inside the house
    let wk: UInt8 = pal.wall == .sandstone ? 7 : 5
    ch.fillWall(x + 1, gy - ht, x + w - 2, gy - 1, wk)
    // gabled roof
    var k: Int = 0
    while x - 1 + k <= x + w - k {
        let yy: Int = gy - ht - 1 - k
        for xx in (x - 1 + k)...(x + w - k) { ch.put(xx, yy, pal.roof) }
        k += 1
    }
    ch.fillWall(x, gy - ht, x + w - 1, gy - ht, wk)
    // interior
    ch.put(x + w / 2, gy - ht + 1, .lantern)
    let r: Double = hash2(x, 2, seed)
    if r < 0.5 {
        ch.put(x + 2, gy - 1, .workbench)
        ch.put(x + w - 3, gy - 1, .chest)
    } else {
        ch.put(x + 2, gy - 1, .chest)
        ch.put(x + w - 3, gy - 1, .furnace)
    }
    ch.put(x + w / 2, gy - 1, .platform)
}

func buildWell(_ ch: Chunk, _ x: Int, _ gy: Int, _ pal: Palette) {
    ch.fill(x - 1, gy - 6, x + 5, gy - 1, .air)
    ch.fill(x + 1, gy, x + 3, gy + 3, .water)
    ch.fill(x, gy - 1, x, gy - 1, .brick)
    ch.fill(x + 4, gy - 1, x + 4, gy - 1, .brick)
    ch.fill(x, gy, x, gy + 3, .brick)
    ch.fill(x + 4, gy, x + 4, gy + 3, .brick)
    ch.fill(x, gy + 4, x + 4, gy + 4, .brick)
    ch.fill(x, gy - 4, x, gy - 2, pal.post)
    ch.fill(x + 4, gy - 4, x + 4, gy - 2, pal.post)
    ch.fill(x - 1, gy - 5, x + 5, gy - 5, pal.wall)
    ch.fill(x, gy - 6, x + 4, gy - 6, pal.roof)
}

func buildFarm(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ seed: UInt64) {
    ch.fill(x - 1, gy - 4, x + w, gy - 1, .air)
    for i in 0..<w {
        let xx: Int = x + i
        if i % 5 == 2 {
            ch.put(xx, gy, .water)
            ch.put(xx, gy + 1, .brick)
        } else {
            ch.put(xx, gy, .farmland)
            let wheat: Bool = hash2(xx, 3, seed) < 0.6
            ch.put(xx, gy - 1, wheat ? .wheat3 : .carrot3)
        }
    }
    ch.put(x - 1, gy - 1, .log); ch.put(x + w, gy - 1, .log)
    ch.put(x - 1, gy - 2, .lantern)
}

func buildSmithy(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ pal: Palette) {
    ch.fill(x - 1, gy - 8, x + w, gy - 1, .air)
    ch.fill(x, gy, x + w - 1, gy, .stone)
    ch.fill(x, gy - 4, x, gy - 1, pal.post)
    ch.fill(x + w - 1, gy - 4, x + w - 1, gy - 1, pal.post)
    ch.fill(x - 1, gy - 5, x + w, gy - 5, pal.roof == .brick ? .planks : pal.roof)
    ch.put(x + 2, gy - 1, .furnace)
    ch.put(x + 4, gy - 1, .workbench)
    ch.fillWall(x, gy - 4, x + w - 1, gy - 1, 5)
    ch.put(x + w - 3, gy - 1, .chest)
    ch.put(x + w / 2, gy - 4, .lantern)
    ch.put(x + 1, gy - 1, .hay)
}

func buildStall(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ pal: Palette) {
    ch.fill(x - 1, gy - 7, x + w, gy - 1, .air)
    ch.fill(x, gy - 3, x, gy - 1, pal.post)
    ch.fill(x + w - 1, gy - 3, x + w - 1, gy - 1, pal.post)
    ch.fill(x - 1, gy - 4, x + w, gy - 4, pal.roof == .brick ? .hay : pal.roof)
    ch.put(x + 1, gy - 1, .hay)
    ch.put(x + 2, gy - 1, .chest)
    ch.put(x + w - 2, gy - 1, .hay)
}

func buildTower(_ ch: Chunk, _ x: Int, _ gy: Int, _ w: Int, _ pal: Palette) {
    let ht: Int = 14
    ch.fill(x - 1, gy - ht - 4, x + w, gy - 1, .air)
    ch.fill(x, gy, x + w - 1, gy, .brick)
    ch.fill(x, gy - ht, x, gy - 1, .brick)
    ch.fill(x + w - 1, gy - ht, x + w - 1, gy - 1, .brick)
    ch.fill(x - 1, gy - ht - 1, x + w, gy - ht - 1, .brick)
    var cr: Int = x - 1
    while cr <= x + w {
        ch.put(cr, gy - ht - 2, .brick)
        cr += 2
    }
    // zig-zag platforms to climb
    var yy: Int = gy - 2
    var left: Bool = true
    while yy > gy - ht {
        if left { ch.fill(x + 1, yy, x + w - 3, yy, .platform) } else { ch.fill(x + 2, yy, x + w - 2, yy, .platform) }
        left = !left
        yy -= 2
    }
    ch.put(x, gy - 1, .doorClosed); ch.put(x, gy - 2, .doorClosed)
    ch.fillWall(x + 1, gy - ht, x + w - 2, gy - 1, 6)
    ch.put(x + w / 2, gy - ht + 1, .lantern)
    ch.put(x + w / 2, gy - 1, .torch)
    ch.put(x + 1, gy - ht, .chest)
}

func buildLamp(_ ch: Chunk, _ x: Int, _ gy: Int) {
    ch.fill(x, gy - 3, x, gy - 1, .log)
    ch.put(x, gy - 4, .lantern)
}

func buildVillage(_ g: WorldGen, _ ch: Chunk, _ v: VillageSite) {
    let x0: Int = ch.x0
    if v.x + v.halfW + 14 < x0 || v.x - v.halfW - 14 > x0 + chunkW { return }
    var rng = RNG(v.seed)
    let gy: Int = v.ground
    let pal: Palette = villagePalette(v.biome)
    let left: Int = v.x - v.halfW
    let right: Int = v.x + v.halfW
    ch.fill(left - 3, gy - 24, right + 3, gy - 1, .air)
    for x in (left - 1)...(right + 1) {
        ch.put(x, gy, pal.path)
        if v.biome == .desert { ch.put(x, gy + 1, .sandstone) } else { ch.put(x, gy + 1, .dirt) }
    }
    buildWell(ch, v.x - 2, gy, pal)
    var haveSmithy: Bool = false
    var haveTower: Bool = false
    var haveFarm: Bool = false
    for side in 0..<2 {
        let dir: Int = side == 0 ? -1 : 1
        var cursor: Int = v.x + dir * 7
        var guardCount: Int = 0
        while abs(cursor - v.x) < v.halfW - 4 && guardCount < 12 {
            guardCount += 1
            let r: Double = rng.double()
            var kind: Int = 0
            if r < 0.28 { kind = 0 } else if r < 0.48 { kind = 1 } else if r < 0.62 { kind = 3 } else if r < 0.74 { kind = 4 } else if r < 0.86 { kind = 5 } else { kind = 6 }
            if kind == 4 && haveSmithy { kind = 1 }
            if kind == 6 && haveTower { kind = 0 }
            if kind == 3 && haveFarm && side == 0 { kind = 1 }
            var w: Int = 9
            switch kind {
            case 0: w = 9
            case 1: w = 7
            case 3: w = 12
            case 4: w = 9
            case 5: w = 6
            default: w = 7
            }
            let bx: Int = dir < 0 ? cursor - w + 1 : cursor
            if abs(bx - v.x) + w > v.halfW + 2 { break }
            switch kind {
            case 0: buildHouse(ch, bx, gy, w, 5, pal, rng.next())
            case 1: buildHouse(ch, bx, gy, w, 4, pal, rng.next())
            case 3: buildFarm(ch, bx, gy, w, rng.next()); haveFarm = true
            case 4: buildSmithy(ch, bx, gy, w, pal); haveSmithy = true
            case 5: buildStall(ch, bx, gy, w, pal)
            default: buildTower(ch, bx, gy, w, pal); haveTower = true
            }
            let gap: Int = 2 + rng.int(3)
            if gap >= 3 {
                let lx: Int = dir < 0 ? bx - 1 - gap / 2 : bx + w + gap / 2
                buildLamp(ch, lx, gy)
            }
            cursor = dir < 0 ? bx - gap - 1 : bx + w + gap
        }
    }
    // flowers & hay near the well
    ch.put(v.x - 4, gy - 1, .flowerR)
    ch.put(v.x + 4, gy - 1, .flowerY)
}

// ===== p08b_ruins =====

// MARK: - Structures: ruins, lairs, portal chamber

func groundAtX(_ g: WorldGen, _ cols: [Col], _ off: Int, _ x: Int) -> Int {
    let i: Int = x - off
    if i >= 0 && i < cols.count { return cols[i].h }
    return g.col(x).h
}

/// Level the ground between xa...xb to row gy and clear the air above
func padGround(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ xa: Int, _ xb: Int, _ gy: Int, _ clearH: Int) {
    for x in xa...xb {
        if x < ch.x0 || x >= ch.x0 + chunkW { continue }
        let h: Int = groundAtX(g, cols, off, x)
        if h > gy { ch.fill(x, gy, x, h - 1, .dirt) }
        if h < gy { ch.fill(x, h, x, gy - 1, .air) }
        ch.fill(x, gy - clearH, x, gy - 1, .air)
        ch.put(x, gy, .dirt)
    }
}

func decay(_ ch: Chunk, _ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ p: Double, _ seed: UInt64) {
    for x in xa...xb {
        if x < ch.x0 || x >= ch.x0 + chunkW { continue }
        for y in ya...yb {
            let t: Tile = ch.at(x, y)
            if !t.solid { continue }
            if hash2(x, y, seed) < p { ch.put(x, y, .air) }
            else if hash2(x, y, seed &+ 5) < 0.18 {
                if t == .planks || t == .log { ch.put(x, y, .mossBrick) }
            }
        }
    }
}

func scatterCobwebs(_ ch: Chunk, _ xa: Int, _ ya: Int, _ xb: Int, _ yb: Int, _ p: Double, _ seed: UInt64) {
    for x in xa...xb {
        for y in ya...yb {
            if ch.at(x, y) == .air && hash2(x, y, seed) < p { ch.putIfAir(x, y, .cobweb) }
        }
    }
}

func buildRuinHouse(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
    let w: Int = 11
    let x: Int = s.x - w / 2
    let gy: Int = groundAtX(g, cols, off, s.x)
    padGround(g, ch, cols, off, x - 2, x + w + 2, gy, 12)
    buildHouse(ch, x, gy, w, 5, villagePalette(.plains), s.seed)
    decay(ch, x - 1, gy - 12, x + w, gy - 1, 0.28, s.seed &+ 1)
    scatterCobwebs(ch, x + 1, gy - 5, x + w - 2, gy - 1, 0.18, s.seed &+ 2)
    for k in 0..<4 { ch.putIfAir(x + 2 + k * 2, gy - 1, hash2(k, 1, s.seed) < 0.5 ? .tallGrass : .flowerY) }
    // cellar reached through a hatch in the floor, with a spike trap
    let hx: Int = x + w / 2
    ch.fill(x + 1, gy + 1, x + w - 2, gy + 7, .mossBrick)
    ch.fill(x + 2, gy + 2, x + w - 3, gy + 6, .air)
    ch.put(hx, gy, .air); ch.put(hx, gy + 1, .air)
    ch.fill(hx - 1, gy + 6, hx + 1, gy + 6, .spikes)
    ch.put(x + 2, gy + 6, .chest)
    ch.put(x + w - 3, gy + 6, .chest)
    ch.put(x + w / 2 + 2, gy + 2, .lantern)
    ch.fill(x + 2, gy + 7, x + w - 3, gy + 7, .mossBrick)
}

func buildRuinTower(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
    let w: Int = 9
    let x: Int = s.x - w / 2
    let gy: Int = groundAtX(g, cols, off, s.x)
    let ht: Int = 14 + Int(hash2(1, 1, s.seed) * 6.0)
    padGround(g, ch, cols, off, x - 3, x + w + 2, gy, ht + 4)
    ch.fill(x, gy - ht, x + w - 1, gy, .mossBrick)
    ch.fill(x + 1, gy - ht + 1, x + w - 2, gy - 1, .air)
    ch.fill(x, gy, x + w - 1, gy, .brick)
    var yy: Int = gy - 3
    var odd: Bool = true
    while yy > gy - ht {
        if odd { ch.fill(x + 1, yy, x + w - 4, yy, .platform) } else { ch.fill(x + 3, yy, x + w - 2, yy, .platform) }
        odd = !odd
        yy -= 3
    }
    ch.put(x, gy - 1, .air); ch.put(x, gy - 2, .air); ch.put(x, gy - 3, .air)
    ch.put(x + w - 1, gy - ht + 4, .glass)
    ch.put(x + w / 2, gy - 1, .chest)
    ch.put(x + 2, gy - 1, .torch)
    for k in 0..<ht {
        let frac: Double = Double(k) / Double(ht)
        decay(ch, x - 1, gy - k, x + w, gy - k, 0.04 + frac * 0.55, s.seed &+ UInt64(k))
    }
    scatterCobwebs(ch, x + 1, gy - ht, x + w - 2, gy - 4, 0.08, s.seed &+ 9)
    for dx in -2...(w + 1) {
        if hash2(dx, 3, s.seed) < 0.5 { ch.putIfAir(x + dx, gy - 1, .mossBrick) }
        if hash2(dx, 4, s.seed) < 0.35 { ch.putIfAir(x + dx, gy - 2, .leaves) }
    }
}

func buildRuinFort(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
    let x: Int = s.x - 17
    let gy: Int = groundAtX(g, cols, off, s.x)
    padGround(g, ch, cols, off, x - 2, x + 36, gy, 14)
    // left wall block and right wall block with a collapsed gate between
    ch.fill(x, gy - 8, x + 9, gy, .brick)
    ch.fill(x + 1, gy - 7, x + 8, gy - 1, .air)
    ch.fill(x + 25, gy - 6, x + 34, gy, .brick)
    ch.fill(x + 26, gy - 5, x + 33, gy - 1, .air)
    var cx: Int = x
    while cx <= x + 9 { ch.put(cx, gy - 9, .brick); cx += 2 }
    cx = x + 25
    while cx <= x + 34 { ch.put(cx, gy - 7, .brick); cx += 2 }
    // low connecting wall
    ch.fill(x + 10, gy - 2, x + 24, gy, .mossBrick)
    for k in 0...6 { ch.fill(x + 11 + k * 2, gy - 3, x + 11 + k * 2, gy - 3, .mossBrick) }
    // rubble mounds
    for dx in 8...14 { let hgt: Int = max(0, 4 - abs(dx - 11)); ch.fill(x + dx, gy - hgt, x + dx, gy - 1, .stone) }
    for dx in 22...28 { let hgt: Int = max(0, 3 - abs(dx - 25)); ch.fill(x + dx, gy - hgt, x + dx, gy - 1, .brick) }
    // courtyard camp inside
    ch.put(x + 17, gy - 1, .campfire)
    ch.put(x + 20, gy - 1, .chest)
    ch.put(x + 4, gy - 1, .chest)
    ch.put(x + 4, gy - 6, .lantern)
    ch.put(x + 29, gy - 1, .hay)
    decay(ch, x - 1, gy - 10, x + 35, gy - 2, 0.30, s.seed)
    scatterCobwebs(ch, x + 1, gy - 7, x + 34, gy - 2, 0.05, s.seed &+ 3)
}

func buildCamp(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
    let x: Int = s.x - 8
    let gy: Int = groundAtX(g, cols, off, s.x)
    padGround(g, ch, cols, off, x - 2, x + 18, gy, 8)
    // tent
    var k: Int = 0
    while k < 5 {
        ch.put(x + k, gy - 1 - k, .planks)
        ch.put(x + 9 - k, gy - 1 - k, .planks)
        k += 1
    }
    ch.put(x + 4, gy - 5, .planks); ch.put(x + 5, gy - 5, .planks)
    ch.fill(x + 1, gy - 1, x + 8, gy - 1, .air)
    ch.put(x + 3, gy - 1, .hay)
    ch.put(x + 7, gy - 1, .chest)
    ch.put(x + 14, gy - 1, .campfire)
    ch.put(x + 12, gy - 1, .log)
    ch.put(x + 16, gy - 1, .log)
    ch.put(x + 13, gy - 2, .fossil)
    ch.put(x + 17, gy - 1, .deadBush)
    scatterCobwebs(ch, x + 1, gy - 4, x + 8, gy - 2, 0.1, s.seed)
}

func buildOvergrown(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
    let x: Int = s.x - 12
    let gy: Int = groundAtX(g, cols, off, s.x)
    padGround(g, ch, cols, off, x - 2, x + 26, gy, 12)
    ch.fill(x, gy, x + 24, gy, .mossBrick)
    for p in 0..<5 {
        let px: Int = x + 1 + p * 6
        let ph: Int = 4 + Int(hash2(p, 1, s.seed) * 6.0)
        ch.fill(px, gy - ph, px + 1, gy - 1, .mossBrick)
        if hash2(p, 2, s.seed) < 0.6 && p < 4 { ch.fill(px + 2, gy - ph, px + 6, gy - ph, .mossBrick) }
        for lv in 0..<6 {
            let lx: Int = px - 1 + Int(hash2(lv, p, s.seed) * 4.0)
            ch.putIfAir(lx, gy - ph - 1 - Int(hash2(p, lv, s.seed &+ 1) * 2.0), .leaves)
        }
    }
    ch.put(x + 12, gy - 1, .chest)
    ch.put(x + 11, gy - 1, .flowerR)
    ch.put(x + 13, gy - 1, .flowerY)
    ch.put(x + 9, gy - 1, .reed)
    decay(ch, x, gy - 12, x + 24, gy - 2, 0.22, s.seed &+ 7)
    for dx in 0...24 { if hash2(dx, 8, s.seed) < 0.5 { ch.putIfAir(x + dx, gy - 1, hash2(dx, 9, s.seed) < 0.5 ? .tallGrass : .mushroom) } }
}

func buildBunker(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
    let gy: Int = groundAtX(g, cols, off, s.x)
    let y0: Int = gy + 60 + Int(hash2(2, 2, s.seed) * 90.0)
    let x: Int = s.x - 14
    ch.fill(x, y0 - 1, x + 28, y0 + 11, .mossBrick)
    ch.fill(x + 1, y0, x + 27, y0 + 9, .air)
    ch.fill(x, y0 + 10, x + 28, y0 + 10, .brick)
    // inner divider with a cracked (hidden) door
    ch.fill(x + 18, y0, x + 18, y0 + 9, .brick)
    ch.fill(x + 18, y0 + 7, x + 18, y0 + 9, .crackedBrick)
    // corridor with traps
    for k in 0..<5 { ch.put(x + 4 + k * 3, y0 + 9, .spikes) }
    ch.put(x + 2, y0 + 9, .chest)
    ch.put(x + 14, y0 + 8, .torch)
    ch.put(x + 7, y0 + 1, .lantern)
    // treasure room
    ch.put(x + 21, y0 + 9, .chest)
    ch.put(x + 25, y0 + 9, .chest)
    ch.put(x + 23, y0 + 1, .lantern)
    ch.put(x + 20, y0 + 9, .torch)
    ch.put(x + 22, y0 + 9, .glowCrystal)
    scatterCobwebs(ch, x + 1, y0, x + 17, y0 + 4, 0.1, s.seed)
}

func buildRare(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int, _ s: RareSite) {
    switch s.kind {
    case .house: buildRuinHouse(g, ch, cols, off, s)
    case .tower: buildRuinTower(g, ch, cols, off, s)
    case .fort: buildRuinFort(g, ch, cols, off, s)
    case .camp: buildCamp(g, ch, cols, off, s)
    case .overgrown: buildOvergrown(g, ch, cols, off, s)
    case .bunker: buildBunker(g, ch, cols, off, s)
    }
}

// MARK: lairs

func lairFloorRow() -> Int { return WorldGen.sea - 10 + 9 }

func buildLair(_ g: WorldGen, _ ch: Chunk, _ L: LairInfo) {
    let gy: Int = WorldGen.sea - 10
    let cx: Int = L.cx
    let kraw: UInt64 = UInt64(L.kind.rawValue + 1)
    let kmul: UInt64 = kraw &* 7777
    let seed: UInt64 = g.seed &+ kmul
    let isRex: Bool = L.kind == .rex
    for x in (cx - 52)...(cx + 52) {
        if x < ch.x0 || x >= ch.x0 + chunkW { continue }
        let d: Int = abs(x - cx)
        var depth: Int = 0
        if d <= 30 { depth = 9 } else if d <= 39 { depth = 9 - (d - 30) }
        ch.fill(x, gy - 22, x, gy - 1, .air)
        if depth > 0 { ch.fill(x, gy, x, gy + depth - 1, .air) }
        // floor surface of the pit
        if depth > 0 {
            ch.put(x, gy + depth, isRex ? .mud : .stone)
            ch.put(x, gy + depth + 1, isRex ? .mud : .stone)
        } else {
            ch.put(x, gy, isRex ? .jungleGrass : .grass)
        }
        let fy: Int = gy + depth - 1
        if depth >= 8 && hash2(x, 1, seed) < 0.09 { ch.put(x, fy, .fossil) }
        if depth >= 8 && hash2(x, 2, seed) < 0.05 { ch.put(x, fy - 1, .cobweb) }
        if depth == 0 && hash2(x, 3, seed) < 0.12 { ch.put(x, gy - 1, isRex ? .tallGrass : .deadBush) }
    }
    // rim decorations
    for side in [-1, 1] {
        let rx: Int = cx + side * 44
        ch.fill(rx, gy - 4, rx, gy - 1, .stone)
        ch.put(rx, gy - 5, .torch)
        let rx2: Int = cx + side * 36
        ch.put(rx2, gy - 1, .torch)
    }
    if isRex {
        // giant rib bones arching over the nest
        for side in [-1, 1] {
            for rb in 0..<3 {
                let bx: Int = cx + side * (14 + rb * 8)
                let top: Int = gy + 9 - 10 - rb
                ch.fill(bx, top, bx, gy + 8, .fossil)
                ch.put(bx - side, top - 1, .fossil)
                ch.put(bx - 2 * side, top - 1, .fossil)
            }
        }
        for k in 0..<10 { ch.putIfAir(cx - 24 + k * 5, gy + 7, .jungleLeaves) }
    } else {
        ch.fill(cx - 18, gy + 6, cx - 18, gy + 8, .stone)
        ch.fill(cx + 18, gy + 6, cx + 18, gy + 8, .stone)
        ch.put(cx - 18, gy + 5, .torch)
        ch.put(cx + 18, gy + 5, .torch)
    }
    // treasure chest at the far edge of the pit floor
    ch.put(cx + (isRex ? -27 : 27), gy + 8, .chest)
}

// MARK: portal chamber

func buildPortalChamber(_ g: WorldGen, _ ch: Chunk) {
    let px: Int = g.portalX
    let py: Int = g.portalY
    ch.fill(px - 12, py - 10, px + 12, py + 7, .brick)
    ch.fill(px - 10, py - 8, px + 10, py + 5, .air)
    ch.fill(px - 12, py + 6, px + 12, py + 7, .obsidian)
    // frame: 7 wide, 9 tall; interior 5x7
    let fx: Int = px - 3
    let fy: Int = py + 5
    ch.fill(fx, fy - 8, fx + 6, fy - 8, .portalFrame)
    ch.fill(fx, fy, fx + 6, fy, .portalFrame)
    ch.fill(fx, fy - 8, fx, fy, .portalFrame)
    ch.fill(fx + 6, fy - 8, fx + 6, fy, .portalFrame)
    ch.fill(fx + 1, fy - 7, fx + 5, fy - 1, .portalOff)
    // decorations: torches and mossy rubble
    ch.put(px - 9, py + 4, .torch)
    ch.put(px + 9, py + 4, .torch)
    ch.put(px - 9, py - 4, .lantern)
    ch.put(px + 9, py - 4, .lantern)
    for k in 0..<8 {
        let rx: Int = px - 10 + k * 3
        if abs(rx - px) <= 3 { continue }
        if hash2(rx, 1, g.seed) < 0.6 { ch.put(rx, py + 5, .mossBrick) }
        if hash2(rx, 2, g.seed) < 0.3 { ch.put(rx, py + 4, .cobweb) }
    }
    ch.put(px - 7, py + 5, .glowCrystal)
    ch.put(px + 7, py + 5, .glowCrystal)
}

func applyStructures(_ g: WorldGen, _ ch: Chunk, _ cols: [Col], _ off: Int) {
    let x0: Int = ch.x0
    let mid: Int = x0 + chunkW / 2
    for L in g.lairCenters(near: mid) {
        if abs(L.cx - mid) < 62 { buildLair(g, ch, L) }
    }
    for v in g.villages(overlapping: x0 - 14, x0 + chunkW + 14) { buildVillage(g, ch, v) }
    for r in g.rareSites(overlapping: x0 - 30, x0 + chunkW + 30) { buildRare(g, ch, cols, off, r) }
    if abs(g.portalX - mid) < 24 { buildPortalChamber(g, ch) }
}

// ===== p09_umbral =====

// MARK: - Umbral Realm (second dimension)

let umbralH: Int = 320
let umbralLava: Int = 240

extension WorldGen {
    func uCeil(_ x: Int) -> Int {
        return 12 + Int(fbm1(Double(x) / 55.0, seed &+ 501, 3) * 30.0)
    }

    func uFloorRaw(_ x: Int) -> Int {
        return 176 + Int(fbm1(Double(x) / 75.0, seed &+ 502, 3) * 86.0)
    }

    /// floor level of the portal platform
    var umbralPortalFloor: Int {
        return clampI(uFloorRaw(portalX), 192, 226)
    }

    func uFloor(_ x: Int) -> Int {
        let raw: Int = uFloorRaw(x)
        let d: Int = abs(x - portalX)
        if d > 44 { return raw }
        let t: Double = smooth(clampD((Double(d) - 16.0) / 28.0, 0, 1))
        return Int(lerpD(Double(umbralPortalFloor), Double(raw), t).rounded())
    }

    func uRuinSite(cell c: Int) -> Int? {
        if hash2(c, 511, seed) > 0.55 { return nil }
        let sx: Int = c * 260 + 40 + Int(hash2(c, 512, seed) * 180.0)
        if abs(sx - portalX) < 60 { return nil }
        if !infinite && (sx < 40 || sx > width - 40) { return nil }
        return sx
    }
}

func generateUmbralChunk(_ g: WorldGen, _ cx: Int) -> Chunk {
    let H: Int = umbralH
    let ch = Chunk(cx: cx, H: H)
    ch.hasSky = false
    let x0: Int = cx * chunkW
    for lx in 0..<chunkW {
        let x: Int = x0 + lx
        let base: Int = lx * H
        if !g.infinite && (x < 0 || x >= g.width) {
            for y in 0..<H { ch.tiles[base + y] = Tile.bedrock.rawValue }
            continue
        }
        let ceil: Int = g.uCeil(x)
        let floorY: Int = g.uFloor(x)
        ch.surf[lx] = floorY
        ch.ceilY[lx] = ceil
        for y in 0..<H {
            var t: Tile = .air
            if y <= 2 || y >= H - 3 { t = .bedrock }
            else if y < ceil { t = .ashStone }
            else if y >= floorY {
                let depth: Int = y - floorY
                t = .ashStone
                if depth >= 5 && g.isCave(x, y, depth) {
                    t = y >= umbralLava - 10 ? .lava : .air
                } else if depth >= 3 {
                    let ev: Double = vnoise(Double(x) * 0.2, Double(y) * 0.2, g.seed &+ 521)
                    let vv: Double = vnoise(Double(x) * 0.2, Double(y) * 0.2, g.seed &+ 522)
                    let ob: Double = vnoise(Double(x) * 0.12, Double(y) * 0.12, g.seed &+ 523)
                    if ev > 0.80 && hash2(x, y, g.seed &+ 524) < 0.7 { t = .emberOre }
                    else if vv > 0.895 && y > 235 && hash2(x, y, g.seed &+ 525) < 0.7 { t = .voidOre }
                    else if ob > 0.86 { t = .obsidian }
                    else if depth > 30 && hash2(x, y / 4, g.seed &+ 526) < 0.02 { t = .deepRock }
                }
            } else {
                // open cavern: floating islands
                if y > ceil + 14 && y < floorY - 26 {
                    let isle: Double = vnoise(Double(x) * 0.045, Double(y) * 0.085, g.seed &+ 531)
                    let mid: Double = Double(ceil + floorY) * 0.5
                    let pen: Double = abs(Double(y) - mid) * 0.0035
                    if isle > 0.735 + pen { t = .ashStone }
                }
                if y >= umbralLava && t == .air { t = .lava }
            }
            ch.tiles[base + y] = t.rawValue
        }
        // stalactites hanging from the ceiling
        let sn: Double = hash2(x, 3, g.seed &+ 541)
        if sn < 0.16 {
            let len: Int = 1 + Int(hash2(x, 4, g.seed &+ 541) * 7.0)
            for k in 0..<len { ch.setLocal(lx, ceil + k, .ashStone) }
            if sn < 0.012 { ch.setLocal(lx, ceil + len, .glowCrystal) }
        }
        // surface decoration: crystals, spikes
        if floorY > 3 && floorY < H - 6 {
            let above: Tile = ch.get(lx, floorY - 1)
            if above == .air {
                let r: Double = hash2(x, 5, g.seed &+ 551)
                if r < 0.03 { ch.setLocal(lx, floorY - 1, .glowCrystal) }
                else if r < 0.08 && abs(x - g.portalX) > 20 { ch.setLocal(lx, floorY - 1, .spikes) }
                else if r < 0.11 { ch.setLocal(lx, floorY - 1, .mushroom) }
            }
        }
    }
    for c in (floorDiv(x0 - 40, 260))...(floorDiv(x0 + chunkW + 40, 260)) {
        if let sx = g.uRuinSite(cell: c) { buildUmbralRuin(g, ch, sx, hashU(c, 513, g.seed)) }
    }
    if abs(g.portalX - (x0 + chunkW / 2)) < 30 { buildUmbralPortal(g, ch) }
    ch.rebuildSky()
    return ch
}

func buildUmbralRuin(_ g: WorldGen, _ ch: Chunk, _ sx: Int, _ seed: UInt64) {
    let gy: Int = g.uFloor(sx)
    let w: Int = 15
    let x: Int = sx - w / 2
    // level the site
    for xx in (x - 3)...(x + w + 2) {
        if xx < ch.x0 || xx >= ch.x0 + chunkW { continue }
        let f: Int = g.uFloor(xx)
        if f > gy { ch.fill(xx, gy, xx, f, .ashStone) }
        ch.fill(xx, gy - 10, xx, gy - 1, .air)
        ch.put(xx, gy, .ashStone)
    }
    ch.fill(x, gy - 7, x + w - 1, gy - 1, .brick)
    ch.fill(x + 1, gy - 6, x + w - 2, gy - 2, .air)
    ch.fill(x, gy - 1, x + w - 1, gy - 1, .brick)
    ch.fill(x + 1, gy - 1, x + w - 2, gy - 1, .air)
    // doorway and roof gap
    ch.fill(x, gy - 3, x, gy - 2, .air)
    ch.fill(x + w - 1, gy - 3, x + w - 1, gy - 2, .air)
    for k in 0..<5 { if hash2(k, 1, seed) < 0.6 { ch.put(x + 3 + k * 2, gy - 7, .air) } }
    // contents
    ch.put(x + 2, gy - 2, .torch)
    ch.put(x + w - 3, gy - 2, .torch)
    ch.put(x + w / 2, gy - 2, .chest)
    ch.put(x + w / 2 - 3, gy - 2, .spikes)
    ch.put(x + w / 2 + 3, gy - 2, .spikes)
    if hash2(1, 2, seed) < 0.6 { ch.put(x + w / 2 + 5, gy - 2, .chest) }
    ch.put(x + 1, gy - 5, .glowCrystal)
    // crumble
    for xx in x...(x + w - 1) {
        for yy in (gy - 7)...(gy - 2) {
            if ch.at(xx, yy) == .brick && hash2(xx, yy, seed) < 0.12 { ch.put(xx, yy, .crackedBrick) }
        }
    }
}

func buildUmbralPortal(_ g: WorldGen, _ ch: Chunk) {
    let px: Int = g.portalX
    let gy: Int = g.umbralPortalFloor
    ch.fill(px - 14, gy - 14, px + 14, gy - 1, .air)
    ch.fill(px - 14, gy, px + 14, gy + 3, .obsidian)
    for dx in -14...14 {
        if abs(dx) > 11 { ch.put(px + dx, gy, .ashStone) }
    }
    let fx: Int = px - 3
    let fyb: Int = gy - 1
    ch.fill(fx, fyb - 8, fx + 6, fyb - 8, .portalFrame)
    ch.fill(fx, fyb, fx + 6, fyb, .portalFrame)
    ch.fill(fx, fyb - 8, fx, fyb, .portalFrame)
    ch.fill(fx + 6, fyb - 8, fx + 6, fyb, .portalFrame)
    ch.fill(fx + 1, fyb - 7, fx + 5, fyb - 1, .portalOn)
    // lights and a welcome chest
    ch.put(px - 9, gy - 1, .lantern)
    ch.put(px + 9, gy - 1, .lantern)
    ch.put(px - 12, gy - 1, .glowCrystal)
    ch.put(px + 12, gy - 1, .glowCrystal)
    ch.put(px + 7, gy - 1, .chest)
}

func generateChunk(_ g: WorldGen, _ dim: Dimension, _ cx: Int) -> Chunk {
    return dim == .overworld ? generateOverworldChunk(g, cx) : generateUmbralChunk(g, cx)
}

func dimHeight(_ dim: Dimension) -> Int {
    return dim == .overworld ? WorldGen.H : umbralH
}

// ===== p10_world =====

// MARK: - World container: chunk streaming, tile access, chests

struct ChestKey: Hashable, Codable {
    var d: Int
    var x: Int
    var y: Int
}

struct ChestEntry: Codable {
    var key: ChestKey
    var items: [Stack]
}

final class World {
    let gen: WorldGen
    var dim: Dimension = .overworld
    var H: Int = WorldGen.H
    var chunks: [Int: Chunk] = [:]
    var parked: [[Int: Chunk]] = [[:], [:]]
    /// bounding box of tile edits since the light map last looked (lets lighting skip far-away edits)
    var editAny: Bool = false
    var editX0: Int = 0
    var editX1: Int = 0
    var editY0: Int = 0
    var editY1: Int = 0
    /// bumps when chunks load/unload or the dimension changes
    var layoutVersion: Int = 0

    func noteEdit(_ x: Int, _ y: Int) {
        if !editAny {
            editAny = true
            editX0 = x; editX1 = x; editY0 = y; editY1 = y
        } else {
            if x < editX0 { editX0 = x }
            if x > editX1 { editX1 = x }
            if y < editY0 { editY0 = y }
            if y > editY1 { editY1 = y }
        }
    }
    var chests: [ChestKey: [Stack]] = [:]
    var version: Int = 0
    var loadedCount: Int { return chunks.count }
    private var cacheCX: Int = Int.min
    private var cacheChunk: Chunk? = nil

    init(gen: WorldGen) {
        self.gen = gen
    }

    // MARK: chunk streaming

    func inRange(_ cx: Int) -> Bool {
        if gen.infinite { return true }
        return cx >= 0 && cx < gen.width / chunkW
    }

    func chunk(_ cx: Int) -> Chunk? {
        if cx == cacheCX { return cacheChunk }
        let c: Chunk? = chunks[cx]
        cacheCX = cx
        cacheChunk = c
        return c
    }

    func isLoaded(_ x: Int) -> Bool {
        return chunks[floorDiv(x, chunkW)] != nil
    }

    @discardableResult
    func loadChunk(_ cx: Int) -> Chunk? {
        if let c = chunks[cx] { return c }
        if !inRange(cx) { return nil }
        var c: Chunk
        if let p = parked[dim.rawValue][cx] {
            c = p
            parked[dim.rawValue][cx] = nil
        } else {
            let t0: Double = perfNow()
            c = generateChunk(gen, dim, cx)
            Perf.shared.noteGen(perfNow() - t0)
        }
        chunks[cx] = c
        cacheCX = Int.min
        version += 1
        noteEdit(cx * chunkW, 0)
        noteEdit(cx * chunkW + chunkW - 1, H - 1)
        gen.cache.trim()
        return c
    }

    func unloadChunk(_ cx: Int) {
        guard let c = chunks[cx] else { return }
        if c.dirty { parked[dim.rawValue][cx] = c }
        chunks[cx] = nil
        cacheCX = Int.min
        version += 1
        noteEdit(cx * chunkW, 0)
        noteEdit(cx * chunkW + chunkW - 1, H - 1)
    }

    /// Streams chunks around a centre column. Loads nearest first (budget limits work per call);
    /// unloads only chunks farther than load radius + hysteresis, and never any in `keep`.
    @discardableResult
    func stream(centerX: Int, radius: Int, hysteresis: Int, budget: Int, keep: Set<Int>) -> Int {
        let cc: Int = floorDiv(centerX, chunkW)
        var loaded: Int = 0
        var d: Int = 0
        while d <= radius && loaded < budget {
            let a: Int = cc - d
            let b: Int = cc + d
            if inRange(a) && chunks[a] == nil { loadChunk(a); loaded += 1 }
            if d > 0 && loaded < budget && inRange(b) && chunks[b] == nil { loadChunk(b); loaded += 1 }
            d += 1
        }
        if chunks.count > radius * 2 + 4 {
            var drop: [Int] = []
            for k in chunks.keys {
                if abs(k - cc) > radius + hysteresis && !keep.contains(k) { drop.append(k) }
            }
            for k in drop { unloadChunk(k) }
        }
        return loaded
    }

    func loadAround(centerX: Int, radius: Int) {
        let cc: Int = floorDiv(centerX, chunkW)
        for d in 0...radius {
            if inRange(cc - d) { loadChunk(cc - d) }
            if inRange(cc + d) { loadChunk(cc + d) }
        }
    }

    func switchDimension(_ nd: Dimension) {
        if nd == dim { return }
        for (k, c) in chunks { if c.dirty { parked[dim.rawValue][k] = c } }
        chunks.removeAll()
        cacheCX = Int.min
        dim = nd
        H = dimHeight(nd)
        version += 1
        layoutVersion += 1
    }

    var dirtyChunkCount: Int {
        var n: Int = 0
        for (_, c) in chunks { if c.dirty { n += 1 } }
        for d in 0..<2 { n += parked[d].count }
        return n
    }

    // MARK: tile access

    func virtualTile(_ x: Int, _ y: Int) -> Tile {
        if !gen.infinite && (x < 0 || x >= gen.width) { return .bedrock }
        return .stone
    }

    @inline(__always) func tile(_ x: Int, _ y: Int) -> Tile {
        if y < 0 { return .air }
        if y >= H { return .bedrock }
        let cx: Int = floorDiv(x, chunkW)
        if let c = chunk(cx) { return c.get(x - cx * chunkW, y) }
        return virtualTile(x, y)
    }

    func solid(_ x: Int, _ y: Int) -> Bool { return tile(x, y).solid }

    func liquidAt(_ x: Int, _ y: Int) -> Bool { return tile(x, y).liquid }

    /// Returns the previous tile. Handles dependent tiles (unsupported plants) and sky light columns.
    @discardableResult
    func set(_ x: Int, _ y: Int, _ t: Tile) -> Tile {
        if y < 1 || y >= H - 1 { return .air }
        let cx: Int = floorDiv(x, chunkW)
        guard let c = chunk(cx) else { return .air }
        let lx: Int = x - cx * chunkW
        let old: Tile = c.get(lx, y)
        if old == t { return old }
        c.tiles[lx * H + y] = t.rawValue
        c.dirty = true
        c.rev &+= 1
        version += 1
        // a roof can add or remove house walls up to 12 rows below it
        c.bumpRows(y - 1, y + 13)
        if old.opaque != t.opaque {
            let before: Int = c.skyTop[lx]
            c.recomputeSky(lx)
            let after: Int = c.skyTop[lx]
            if before != after { c.bumpRows(min(before, after) - 1, max(before, after) + 13) }
        }
        noteEdit(x, y)
        return old
    }

    func needsSupport(_ t: Tile) -> Bool {
        if t.isPlant && t != .torch && t != .lantern && t != .cobweb { return true }
        switch t {
        case .workbench, .furnace, .chest, .campfire, .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3, .doorClosed, .doorOpen: return true
        default: return false
        }
    }

    func supports(_ below: Tile, _ t: Tile) -> Bool {
        switch t {
        case .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3: return below == .farmland
        case .doorClosed, .doorOpen: return below.solid || below == .doorClosed || below == .doorOpen
        default: return below.solid || below == .platform
        }
    }

    func skyTop(_ x: Int) -> Int {
        let cx: Int = floorDiv(x, chunkW)
        if let c = chunk(cx) { return c.skyTop[x - cx * chunkW] }
        return 0
    }

    func isSkyExposed(_ x: Int, _ y: Int) -> Bool {
        if dim != .overworld { return false }
        return y < skyTop(x)
    }

    func surfaceY(_ x: Int) -> Int {
        var y: Int = 0
        while y < H - 1 {
            let t: Tile = tile(x, y)
            if t.solid || t.liquid { return y }
            y += 1
        }
        return H - 1
    }

    /// Row of the first solid tile at or below fromY
    func groundBelow(_ x: Int, _ fromY: Int) -> Int {
        var y: Int = max(0, fromY)
        while y < H - 1 {
            if tile(x, y).solid { return y }
            y += 1
        }
        return H - 1
    }

    // MARK: chests

    func chestKey(_ x: Int, _ y: Int) -> ChestKey {
        return ChestKey(d: dim.rawValue, x: x, y: y)
    }

    func chestItems(_ x: Int, _ y: Int) -> [Stack] {
        let k: ChestKey = chestKey(x, y)
        if let it = chests[k] { return it }
        let it: [Stack] = generateChestLoot(gen, dim, x, y)
        chests[k] = it
        return it
    }

    func setChestItems(_ x: Int, _ y: Int, _ items: [Stack]) {
        chests[chestKey(x, y)] = items
    }

    func removeChest(_ x: Int, _ y: Int) -> [Stack] {
        let k: ChestKey = chestKey(x, y)
        var out: [Stack] = []
        if let it = chests[k] { out = it } else { out = generateChestLoot(gen, dim, x, y) }
        chests[k] = nil
        return out
    }

    // MARK: save helpers (RLE of raw tile bytes)

    static func rle(_ a: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var i: Int = 0
        while i < a.count {
            let v: UInt8 = a[i]
            var n: Int = 1
            while i + n < a.count && a[i + n] == v && n < 255 { n += 1 }
            out.append(UInt8(n))
            out.append(v)
            i += n
        }
        return out
    }

    static func unrle(_ a: [UInt8], _ count: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count)
        var i: Int = 0
        while i + 1 < a.count {
            let n: Int = Int(a[i])
            let v: UInt8 = a[i + 1]
            for _ in 0..<n { out.append(v) }
            i += 2
        }
        if out.count < count { out.append(contentsOf: [UInt8](repeating: 0, count: count - out.count)) }
        return out
    }
}

// MARK: - Chest loot (deterministic per position, generated on first open)

func lootStack(_ it: Item, _ n: Int) -> Stack { return Stack(item: it, count: n) }

func generateChestLoot(_ g: WorldGen, _ dim: Dimension, _ x: Int, _ y: Int) -> [Stack] {
    var rng = RNG(hashU(x, y, g.seed &+ 777))
    var out: [Stack] = []
    func add(_ it: Item, _ lo: Int, _ hi: Int, _ p: Double) {
        if rng.double() < p { out.append(lootStack(it, lo + rng.int(max(1, hi - lo + 1)))) }
    }
    func tierPick(_ lo: Int, _ hi: Int) -> Tier {
        let r: Int = lo + rng.int(max(1, hi - lo + 1))
        return Tier(rawValue: clampI(r, 1, 9)) ?? .wood
    }
    if dim == .umbral {
        add(.mat(.emberBar), 2, 6, 0.8)
        add(.mat(.voidBar), 1, 3, 0.35)
        add(.mat(.diamond), 1, 4, 0.6)
        add(.ammo(.arrow), 15, 40, 0.5)
        add(.ammo(.bullet), 8, 20, 0.5)
        add(.sword(tierPick(6, 8)), 1, 1, 0.35)
        add(.armor(ArmorSlot.allCases[rng.int(3)], tierPick(6, 8)), 1, 1, 0.3)
        add(.food(.cookedMeat), 3, 6, 0.6)
        add(.block(.lantern), 2, 4, 0.5)
        return out
    }
    // portal vault
    if abs(x - g.portalX) < 20 && y > 300 {
        add(.mat(.diamond), 3, 7, 1.0)
        add(.mat(.mythrilBar), 2, 5, 0.9)
        add(.mat(.goldBar), 4, 9, 0.8)
        add(.gun(.rifle), 1, 1, 0.5)
        add(.ammo(.bullet), 12, 30, 0.9)
        add(.food(.cookedMeat), 4, 8, 0.8)
        return out
    }
    // lair treasure
    if let L = g.lairAt(x, radius: 70), y < 200 {
        add(.mat(.goldBar), 3, 8, 0.9)
        add(.mat(.diamond), 1, 3, 0.6)
        add(.sword(tierPick(4, 6)), 1, 1, 0.5)
        add(.armor(ArmorSlot.allCases[rng.int(3)], tierPick(4, 6)), 1, 1, 0.5)
        if L.kind == .bear { add(.mat(.fur), 2, 5, 0.9); add(.mat(.claw), 1, 3, 0.7) } else { add(.mat(.tusk), 1, 2, 0.5); add(.mat(.bone), 6, 14, 1.0) }
        add(.food(.cookedMeat), 3, 6, 0.8)
        return out
    }
    // villages
    if y < 200, let v = g.nearestVillage(to: x), abs(x - v.x) <= v.halfW + 12 {
        add(.food(.bread), 2, 5, 0.9)
        add(.food(.carrot), 2, 5, 0.6)
        add(.mat(.seeds), 3, 8, 0.8)
        add(.block(.torch), 4, 10, 0.8)
        add(.tool(.pickaxe, tierPick(2, 3)), 1, 1, 0.35)
        add(.sword(tierPick(2, 4)), 1, 1, 0.3)
        add(.mat(.ironBar), 1, 4, 0.45)
        add(.mat(.string), 2, 5, 0.4)
        add(.ammo(.arrow), 8, 20, 0.35)
        if out.isEmpty { add(.block(.planks), 6, 12, 1.0) }
        return out
    }
    // ruins by kind
    if y < 260 {
        for r in g.rareSites(overlapping: x - 40, x + 40) {
            if abs(r.x - x) > 40 { continue }
            switch r.kind {
            case .tower:
                add(.bow, 1, 1, 0.45); add(.ammo(.arrow), 12, 30, 0.9); add(.mat(.goldBar), 1, 4, 0.5)
            case .fort:
                add(.sword(tierPick(3, 5)), 1, 1, 0.6); add(.armor(ArmorSlot.allCases[rng.int(3)], tierPick(3, 5)), 1, 1, 0.6); add(.ammo(.bullet), 6, 14, 0.4)
            case .camp:
                add(.food(.cookedMeat), 2, 5, 0.9); add(.food(.bread), 2, 4, 0.7); add(.mat(.string), 3, 7, 0.6); add(.block(.torch), 5, 12, 0.8)
            case .overgrown:
                add(.mat(.seeds), 5, 12, 0.9); add(.food(.apple), 3, 6, 0.8); add(.mat(.diamond), 1, 2, 0.3); add(.gadget(.shears), 1, 1, 0.3)
            case .bunker:
                add(.gun(.pistol), 1, 1, 0.55); add(.gun(.rifle), 1, 1, 0.18); add(.ammo(.bullet), 10, 28, 0.9); add(.mat(.goldBar), 3, 8, 0.8); add(.mat(.mythrilBar), 1, 3, 0.4)
            case .house:
                add(.food(.cookedFish), 2, 5, 0.7); add(.block(.lantern), 1, 3, 0.6); add(.tool(.axe, tierPick(2, 4)), 1, 1, 0.4); add(.mat(.copperBar), 2, 6, 0.6)
            }
            if out.isEmpty { add(.block(.planks), 5, 10, 1.0) }
            return out
        }
    }
    // generic by depth
    if y < WorldGen.sea + 40 {
        add(.block(.planks), 6, 14, 0.8)
        add(.food(.bread), 1, 3, 0.6)
        add(.block(.torch), 3, 8, 0.7)
        add(.mat(.copperBar), 1, 4, 0.5)
    } else if y < 320 {
        add(.mat(.ironBar), 2, 6, 0.8)
        add(.mat(.goldBar), 1, 4, 0.5)
        add(.block(.torch), 6, 14, 0.8)
        add(.tool(.pickaxe, tierPick(3, 5)), 1, 1, 0.25)
        add(.ammo(.arrow), 10, 24, 0.5)
        add(.food(.cookedMeat), 2, 4, 0.6)
    } else {
        add(.mat(.goldBar), 3, 8, 0.8)
        add(.mat(.diamond), 1, 4, 0.55)
        add(.mat(.mythrilBar), 1, 3, 0.4)
        add(.sword(tierPick(5, 7)), 1, 1, 0.3)
        add(.ammo(.bullet), 8, 20, 0.45)
        add(.block(.lantern), 2, 5, 0.6)
    }
    if out.isEmpty { add(.block(.torch), 3, 6, 1.0) }
    return out
}

// ===== p11_light =====

// MARK: - Lighting: flood-fill light over the visible window (sky light + block light)
// Written with raw buffers and plain Ints so it stays fast in Swift Playgrounds' debug builds.

let lightLUT: [Double] = (0...15).map { pow(Double($0) / 15.0, 1.0) }

final class LightMap {
    var ox: Int = 0
    var oy: Int = 0
    var w: Int = 0
    var h: Int = 0
    var sky: [Int] = []
    var blk: [Int] = []
    /// block light from tiles only; moving lights are layered on top by applyDynamic()
    var blkBase: [Int] = []
    var opq: [Bool] = []
    var drawn: [Bool] = []
    var ambientFloor: Double = 0
    var valid: Bool = false
    var stamp: Int = -1
    var skyUsed: Int = -1
    var dynUsed: Int = 0
    var dimUsed: Int = -1
    var layoutUsed: Int = -1
    // bucket queues: 16 levels, each with room for every cell (a cell enters a level at most once)
    private var qCap: Int = 0
    private var queue: UnsafeMutablePointer<Int> = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    private var skySeed: UnsafeMutablePointer<Int> = UnsafeMutablePointer<Int>.allocate(capacity: 1)
    private var lens: UnsafeMutablePointer<Int> = UnsafeMutablePointer<Int>.allocate(capacity: 16)
    private var skyN: Int = 0
    // colour tables for buildPixels (index = sky * 16 + block)
    private var darkLUT: [UInt32] = [UInt32](repeating: 0, count: 256)
    private var glowLUT: [UInt32] = [UInt32](repeating: 0, count: 256)

    deinit {
        queue.deallocate()
        skySeed.deallocate()
        lens.deallocate()
    }

    func covers(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Bool {
        return valid && x0 >= ox && y0 >= oy && x1 < ox + w && y1 < oy + h
    }

    func compute(_ world: World, _ nox: Int, _ noy: Int, _ nw: Int, _ nh: Int, _ skyLevel: Int, _ dyn: [(Int, Int, Int)]) {
        ox = nox; oy = noy; w = nw; h = nh
        let n: Int = w * h
        if sky.count != n {
            sky = [Int](repeating: 0, count: n)
            blk = [Int](repeating: 0, count: n)
            opq = [Bool](repeating: false, count: n)
            drawn = [Bool](repeating: true, count: n)
        }
        if qCap < n {
            queue.deallocate()
            skySeed.deallocate()
            qCap = n
            queue = UnsafeMutablePointer<Int>.allocate(capacity: n * 16)
            skySeed = UnsafeMutablePointer<Int>.allocate(capacity: n)
        }
        var l0: Int = 0
        while l0 < 16 { lens[l0] = 0; l0 += 1 }
        let H: Int = world.H
        let hasSky: Bool = world.dim == .overworld
        let sl: Int = clampI(skyLevel, 0, 15)
        let q: UnsafeMutablePointer<Int> = queue
        let ss: UnsafeMutablePointer<Int> = skySeed
        let ln: UnsafeMutablePointer<Int> = lens
        let cap: Int = qCap
        let ww: Int = w
        let hh: Int = h
        let oxx: Int = ox
        let oyy: Int = oy
        var sn: Int = 0
        let opT: [Bool] = Tile.opaqueTable
        let liT: [Int] = Tile.lightTable
        sky.withUnsafeMutableBufferPointer { skyB in
            blk.withUnsafeMutableBufferPointer { blkB in
                opq.withUnsafeMutableBufferPointer { opqB in
                    drawn.withUnsafeMutableBufferPointer { drB in
                        opT.withUnsafeBufferPointer { opTB in
                            liT.withUnsafeBufferPointer { liTB in
                                guard let skyP = skyB.baseAddress, let blkP = blkB.baseAddress, let opqP = opqB.baseAddress,
                                      let drP = drB.baseAddress, let opTP = opTB.baseAddress, let liTP = liTB.baseAddress else { return }
                                var i0: Int = 0
                                while i0 < n { skyP[i0] = 0; blkP[i0] = 0; i0 += 1 }
                                var ix: Int = 0
                                while ix < ww {
                                    let x: Int = oxx + ix
                                    let cx: Int = floorDiv(x, chunkW)
                                    let lx: Int = x - cx * chunkW
                                    if let c = world.chunk(cx) {
                                        let skyTop: Int = hasSky ? c.skyTop[lx] : -1
                                        let back: [UInt8] = world.backdrop(c)
                                        c.tiles.withUnsafeBufferPointer { tb in
                                            back.withUnsafeBufferPointer { bb in
                                                guard let tp = tb.baseAddress, let bp = bb.baseAddress else { return }
                                                let base: Int = lx * H
                                                var iy: Int = 0
                                                var i: Int = ix
                                                while iy < hh {
                                                    let y: Int = oyy + iy
                                                    if y < 0 {
                                                        opqP[i] = false
                                                        drP[i] = false
                                                        if hasSky && sl > 0 {
                                                            skyP[i] = sl
                                                            ss[sn] = i; sn += 1
                                                        }
                                                    } else if y >= H {
                                                        opqP[i] = true
                                                        drP[i] = true
                                                    } else {
                                                        let rb: UInt8 = tp[base + y]
                                                        let raw: Int = i8(rb)
                                                        let op: Bool = opTP[raw]
                                                        opqP[i] = op
                                                        drP[i] = rb != 0 || bp[base + y] != 0
                                                        let emit: Int = liTP[raw]
                                                        if emit > 0 {
                                                            blkP[i] = emit
                                                            q[emit * cap + ln[emit]] = i; ln[emit] += 1
                                                        }
                                                        if hasSky && !op && y < skyTop && sl > 0 {
                                                            skyP[i] = sl
                                                            ss[sn] = i; sn += 1
                                                        }
                                                    }
                                                    iy += 1
                                                    i += ww
                                                }
                                            }
                                        }
                                    } else {
                                        var iy: Int = 0
                                        var i: Int = ix
                                        while iy < hh {
                                            let y: Int = oyy + iy
                                            opqP[i] = y >= 0
                                            drP[i] = y >= 0
                                            if y < 0 && hasSky && sl > 0 {
                                                skyP[i] = sl
                                                ss[sn] = i; sn += 1
                                            }
                                            iy += 1
                                            i += ww
                                        }
                                    }
                                    ix += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        skyN = sn
        // block light pass (tiles only)
        blk.withUnsafeMutableBufferPointer { p in propagate(p) }
        // sky light pass
        var l1: Int = 0
        while l1 < 16 { lens[l1] = 0; l1 += 1 }
        if sl > 0 {
            var k: Int = 0
            let dst: UnsafeMutablePointer<Int> = queue + sl * qCap
            while k < skyN { dst[k] = skySeed[k]; k += 1 }
            lens[sl] = skyN
        }
        sky.withUnsafeMutableBufferPointer { p in propagate(p) }
        blkBase = blk
        applyDynamic(dyn)
        Perf.shared.lightFull += 1
        valid = true
        skyUsed = skyLevel
        dimUsed = world.dim.rawValue
        stamp = world.version
        layoutUsed = world.layoutVersion
        world.editAny = false
    }

    /// Re-lights only what moving light sources touch: starts from the cached tile light and floods
    /// outward from each source. Far cheaper than a full recompute when only the player moved.
    func applyDynamic(_ dyn: [(Int, Int, Int)]) {
        if blkBase.count != w * h || blkBase.isEmpty { return }
        blk = blkBase
        var l: Int = 0
        while l < 16 { lens[l] = 0; l += 1 }
        var any: Bool = false
        for (dx, dy, lv) in dyn {
            let lx: Int = dx - ox
            let ly: Int = dy - oy
            if lx < 0 || ly < 0 || lx >= w || ly >= h { continue }
            let i: Int = ly * w + lx
            let v: Int = clampI(lv, 0, 15)
            if v > blk[i] {
                blk[i] = v
                queue[v * qCap + lens[v]] = i
                lens[v] += 1
                any = true
            }
        }
        if any { blk.withUnsafeMutableBufferPointer { p in propagate(p) } }
    }

    private func propagate(_ lvb: UnsafeMutableBufferPointer<Int>) {
        guard let lv = lvb.baseAddress else { return }
        let q: UnsafeMutablePointer<Int> = queue
        let ln: UnsafeMutablePointer<Int> = lens
        let cap: Int = qCap
        let ww: Int = w
        let hh: Int = h
        opq.withUnsafeBufferPointer { opb in
            guard let op = opb.baseAddress else { return }
            var l: Int = 15
            while l >= 2 {
                var k: Int = 0
                let nl: Int = l - 1
                let ol: Int = l - 2
                let qa: UnsafeMutablePointer<Int> = q + l * cap
                let qn: UnsafeMutablePointer<Int> = q + nl * cap
                let qo: UnsafeMutablePointer<Int> = q + ol * cap
                while k < ln[l] {
                    let ci: Int = qa[k]
                    k += 1
                    if lv[ci] != l { continue }
                    let cy: Int = ci / ww
                    let cx: Int = ci - cy * ww
                    if cx > 0 {
                        let nb: Int = ci - 1
                        if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
                        else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
                    }
                    if cx < ww - 1 {
                        let nb: Int = ci + 1
                        if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
                        else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
                    }
                    if cy > 0 {
                        let nb: Int = ci - ww
                        if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
                        else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
                    }
                    if cy < hh - 1 {
                        let nb: Int = ci + ww
                        if !op[nb] { if lv[nb] < nl { lv[nb] = nl; qn[ln[nl]] = nb; ln[nl] += 1 } }
                        else if ol >= 1 && lv[nb] < ol { lv[nb] = ol; qo[ln[ol]] = nb; ln[ol] += 1 }
                    }
                }
                l -= 1
            }
        }
    }

    /// Light level seen at a cell (opaque cells show the light of their brightest open neighbour)
    func level(_ x: Int, _ y: Int) -> (Int, Int) {
        let lx: Int = x - ox
        let ly: Int = y - oy
        if lx < 0 || ly < 0 || lx >= w || ly >= h { return (0, 0) }
        let i: Int = ly * w + lx
        var s: Int = sky[i]
        var b: Int = blk[i]
        if opq[i] {
            if lx > 0 { s = max(s, sky[i - 1]); b = max(b, blk[i - 1]) }
            if lx < w - 1 { s = max(s, sky[i + 1]); b = max(b, blk[i + 1]) }
            if ly > 0 { s = max(s, sky[i - w]); b = max(b, blk[i - w]) }
            if ly < h - 1 { s = max(s, sky[i + w]); b = max(b, blk[i + w]) }
        }
        return (s, b)
    }

    /// Best single brightness 0...15 at a tile (for gameplay checks such as spawning)
    func brightness(_ x: Int, _ y: Int) -> Int {
        let (s, b) = level(x, y)
        return max(s, b)
    }

    private func buildTables(_ ambient: Double, _ nightMix: Double) {
        for s in 0..<16 {
            for b in 0..<16 {
                let sb: Double = lightLUT[s]
                let bb: Double = lightLUT[b]
                let bright: Double = max(max(sb, bb), ambient)
                let a: Int = max(0, Int((1.0 - bright) * 252.0))
                let skyShare: Double = sb > bb ? 1.0 : 0.0
                let tint: Double = skyShare * nightMix
                let r: Int = Int(3.0 + 9.0 * tint)
                let g: Int = Int(4.0 + 14.0 * tint)
                let bl: Int = Int(9.0 + 44.0 * tint)
                // premultiplied ARGB (the renderer hands these straight to Core Graphics)
                let packed: Int = (a << 24) | ((r * a / 255) << 16) | ((g * a / 255) << 8) | (bl * a / 255)
                darkLUT[s * 16 + b] = UInt32(packed)
                let ga: Double = bb * (1.0 - sb * 0.9) * 0.34
                let gaa: Int = Int(ga * 255.0)
                let gp: Int = (gaa << 24) | ((255 * gaa / 255) << 16) | ((0x96 * gaa / 255) << 8) | (0x3C * gaa / 255)
                glowLUT[s * 16 + b] = UInt32(gp)
            }
        }
    }

    /// Builds the two overlay layers (premultiplied ARGB): darkness and warm glow.
    func buildPixels(_ dark: inout [UInt32], _ glow: inout [UInt32], _ ambient: Double, _ nightMix: Double) {
        let n: Int = w * h
        if dark.count != n { dark = [UInt32](repeating: 0, count: n) }
        if glow.count != n { glow = [UInt32](repeating: 0, count: n) }
        buildTables(ambient, nightMix)
        let ww: Int = w
        let hh: Int = h
        dark.withUnsafeMutableBufferPointer { dB in
            glow.withUnsafeMutableBufferPointer { gB in
                sky.withUnsafeBufferPointer { sB in
                    blk.withUnsafeBufferPointer { bB in
                        opq.withUnsafeBufferPointer { oB in
                            drawn.withUnsafeBufferPointer { drB in
                                darkLUT.withUnsafeBufferPointer { dLB in
                                    glowLUT.withUnsafeBufferPointer { gLB in
                                        guard let dP = dB.baseAddress, let gP = gB.baseAddress, let sP = sB.baseAddress, let bP = bB.baseAddress,
                                              let oP = oB.baseAddress, let drP = drB.baseAddress, let dL = dLB.baseAddress, let gL = gLB.baseAddress else { return }
                                        var iy: Int = 0
                                        while iy < hh {
                                            var ix: Int = 0
                                            let row: Int = iy * ww
                                            while ix < ww {
                                                let i: Int = row + ix
                                                if !drP[i] {
                                                    dP[i] = 0
                                                    gP[i] = 0
                                                    ix += 1
                                                    continue
                                                }
                                                var s: Int = sP[i]
                                                var b: Int = bP[i]
                                                if oP[i] {
                                                    if ix > 0 { s = max(s, sP[i - 1]); b = max(b, bP[i - 1]) }
                                                    if ix < ww - 1 { s = max(s, sP[i + 1]); b = max(b, bP[i + 1]) }
                                                    if iy > 0 { s = max(s, sP[i - ww]); b = max(b, bP[i - ww]) }
                                                    if iy < hh - 1 { s = max(s, sP[i + ww]); b = max(b, bP[i + ww]) }
                                                }
                                                let k: Int = s * 16 + b
                                                dP[i] = dL[k]
                                                gP[i] = gL[k]
                                                ix += 1
                                            }
                                            iy += 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ===== p12_phys =====

// MARK: - Physics: bodies, collision, projectiles, drops, particles

struct Deck {
    var x0: Double
    var x1: Double
    var y: Double
    var vx: Double
    var id: Int
}

struct Body {
    var x: Double          // centre x
    var y: Double          // feet y (bottom)
    var vx: Double = 0
    var vy: Double = 0
    var w: Double
    var h: Double
    var onGround: Bool = false
    var hitWall: Bool = false
    var hitCeil: Bool = false
    var inWater: Bool = false
    var inLava: Bool = false
    var deck: Int = -1
    var wasOnGround: Bool = false

    init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    var left: Double { return x - w * 0.5 }
    var right: Double { return x + w * 0.5 }
    var top: Double { return y - h }
    var cy: Double { return y - h * 0.5 }
}

let gravityG: Double = 34.0
let terminalV: Double = 26.0

extension World {
    func boxSolid(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        Perf.shared.countBox()
        let tx0: Int = Int(floor(x0))
        let tx1: Int = Int(floor(x1 - 0.0001))
        let ty0: Int = Int(floor(y0))
        let ty1: Int = Int(floor(y1 - 0.0001))
        if tx1 < tx0 || ty1 < ty0 { return false }
        for ty in ty0...ty1 {
            for tx in tx0...tx1 {
                if tile(tx, ty).solid { return true }
            }
        }
        return false
    }

    func boxHurts(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Tile? {
        let tx0: Int = Int(floor(x0))
        let tx1: Int = Int(floor(x1 - 0.0001))
        let ty0: Int = Int(floor(y0))
        let ty1: Int = Int(floor(y1 - 0.0001))
        if tx1 < tx0 || ty1 < ty0 { return nil }
        for ty in ty0...ty1 {
            for tx in tx0...tx1 {
                let t: Tile = tile(tx, ty)
                if t.hurts { return t }
            }
        }
        return nil
    }

    func liquidFraction(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ lava: Bool) -> Double {
        let tx0: Int = Int(floor(x0))
        let tx1: Int = Int(floor(x1 - 0.0001))
        let ty0: Int = Int(floor(y0))
        let ty1: Int = Int(floor(y1 - 0.0001))
        if tx1 < tx0 || ty1 < ty0 { return 0 }
        var n: Int = 0
        var m: Int = 0
        for ty in ty0...ty1 {
            for tx in tx0...tx1 {
                m += 1
                let t: Tile = tile(tx, ty)
                if lava { if t == .lava { n += 1 } } else if t == .water { n += 1 }
            }
        }
        return m > 0 ? Double(n) / Double(m) : 0
    }

    /// Moves a body with gravity-free integration; the caller sets vx/vy. Collides with solid tiles,
    /// one-way platforms and decks. stepUp = max ledge height (tiles) climbed automatically.
    func moveBody(_ b: inout Body, _ dt: Double, stepUp: Double, dropThrough: Bool, decks: [Deck]) {
        Perf.shared.countMove()
        b.wasOnGround = b.onGround
        b.hitWall = false
        b.hitCeil = false
        b.onGround = false
        b.deck = -1
        let speed: Double = max(abs(b.vx), abs(b.vy))
        let steps: Int = max(1, Int(ceil(speed * dt / 0.3)))
        let sdt: Double = dt / Double(steps)
        let hw: Double = b.w * 0.5
        // unstick: if inside solid, push upward
        if boxSolid(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02) {
            var k: Int = 0
            while k < 6 && boxSolid(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02) {
                b.y -= 1.0
                k += 1
            }
        }
        for _ in 0..<steps {
            // horizontal
            if b.vx != 0 {
                let nx: Double = b.x + b.vx * sdt
                if !boxSolid(nx - hw, b.y - b.h + 0.001, nx + hw, b.y - 0.001) {
                    b.x = nx
                } else {
                    var done: Bool = false
                    if (b.wasOnGround || b.onGround) && stepUp > 0 {
                        var lift: Double = 1.0
                        while lift <= stepUp + 0.001 && !done {
                            if !boxSolid(nx - hw, b.y - lift - b.h + 0.001, nx + hw, b.y - lift - 0.001) {
                                b.x = nx
                                b.y -= lift
                                done = true
                            }
                            lift += 1.0
                        }
                    }
                    if !done {
                        b.hitWall = true
                        b.vx = 0
                    }
                }
            }
            // vertical
            do {
                let prevY: Double = b.y
                let ny: Double = b.y + b.vy * sdt
                if b.vy >= 0 {
                    var landed: Bool = false
                    var landY: Double = ny
                    if boxSolid(b.x - hw, ny - b.h + 0.001, b.x + hw, ny + 0.0005) {
                        // find top of the colliding row at feet
                        landY = floor(ny + 0.0005)
                        if landY < prevY - 0.0001 { landY = prevY }
                        landed = true
                    } else {
                        // platforms
                        let rowF: Int = Int(floor(ny + 0.0005))
                        if !dropThrough {
                            let tx0: Int = Int(floor(b.x - hw))
                            let tx1: Int = Int(floor(b.x + hw - 0.0001))
                            if tx1 >= tx0 {
                                for tx in tx0...tx1 {
                                    if tile(tx, rowF).isPlatform && prevY <= Double(rowF) + 0.001 && ny >= Double(rowF) - 0.0001 {
                                        landed = true
                                        landY = Double(rowF)
                                    }
                                }
                            }
                        }
                        if !landed {
                            for (i, d) in decks.enumerated() {
                                if b.x + hw > d.x0 && b.x - hw < d.x1 && prevY <= d.y + 0.06 && ny >= d.y - 0.0001 && !dropThrough {
                                    landed = true
                                    landY = d.y
                                    b.deck = i
                                }
                            }
                        }
                    }
                    if landed {
                        b.y = landY
                        b.vy = 0
                        b.onGround = true
                    } else {
                        b.y = ny
                    }
                } else {
                    if boxSolid(b.x - hw, ny - b.h, b.x + hw, ny - 0.001) {
                        let ceilRow: Double = floor(ny - b.h) + 1.0
                        b.y = ceilRow + b.h
                        b.vy = 0
                        b.hitCeil = true
                    } else {
                        b.y = ny
                    }
                }
            }
        }
        // liquids
        let lf: Double = liquidFraction(b.x - hw, b.y - b.h, b.x + hw, b.y, false)
        b.inWater = lf > 0.35
        b.inLava = liquidFraction(b.x - hw, b.y - b.h, b.x + hw, b.y, true) > 0.2
    }

    /// Light-weight ray test used by projectiles: tile-step along a short segment.
    func segmentHitsSolid(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> (Int, Int)? {
        let dx: Double = x1 - x0
        let dy: Double = y1 - y0
        let dist: Double = sqrt(dx * dx + dy * dy)
        let n: Int = max(1, Int(ceil(dist / 0.4)))
        var i: Int = 1
        while i <= n {
            let t: Double = Double(i) / Double(n)
            let px: Double = x0 + dx * t
            let py: Double = y0 + dy * t
            let tx: Int = Int(floor(px))
            let ty: Int = Int(floor(py))
            if tile(tx, ty).solid { return (tx, ty) }
            i += 1
        }
        return nil
    }
}

// MARK: - Projectiles

enum ProjKind: Int, Codable {
    case arrow, bullet, fireball, rock, shock, spit, bolt, bomb
}

struct Projectile {
    var kind: ProjKind
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var dmg: Double
    var fromPlayer: Bool
    var life: Double = 4.0
    var stuck: Double = 0
    var gravity: Double
    var owner: Int = -1
    var pierce: Int = 0
    var hit: Bool = false
    var w: Double = 0.3
    /// who fired it (decides what it may hurt and who gets the kill)
    var source: DamageSource = DamageSource.environment
    /// attack instance id for damage cooldowns
    var uid: Int = 0
    /// id of the last creature it passed through (piercing shots)
    var lastHit: Int = -1
    var stuckAngle: Double = 0
    var trail: Int = 0
    var angle: Double { return atan2(vy, vx) }
}

// MARK: - Drops and particles

struct DropItem {
    var stack: Stack
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var age: Double = 0
    var pickDelay: Double = 0.5
    var onGround: Bool = false
}

struct Particle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double
    var maxLife: Double
    var color: UInt32
    var size: Double
    var gravity: Double
}

struct FloatText {
    var x: Double
    var y: Double
    var text: String
    var life: Double
    var color: UInt32
}

// ===== p13a_mobdefs =====

// MARK: - Mob definitions

enum MobKind: Int, Codable, CaseIterable {
    case pig, cow, sheep, chicken, crow, giraffe, frog, fish
    case elephant, bear, grizzly, polarBear, tiger, wolf, cat
    case zombie, skeleton, slime, bat, scorpion, wraith
    case villager, pirate, pirateGunner, pirateCaptain
    case imp, emberSlime, cinderBat
    case bearBoss, rex
}

enum Behavior: Int {
    case passive, skittish, defensive, hostile, ranged, flyer, swimmer, boss
}

struct MobDef {
    var name: String
    var w: Double
    var h: Double
    var hp: Double
    var speed: Double
    var dmg: Double
    var behavior: Behavior
    var flying: Bool = false
    var aggro: Double = 14
    var jump: Double = 12
    var hostile: Bool = false
}

/// Mob definitions are built once into a table: building a MobDef (it holds a String) on every
/// lookup was one of the hottest calls in the AI loop in debug builds.
let mobDefTable: [MobDef] = MobKind.allCases.map { makeMobDef($0) }

@inline(__always) func mobDef(_ k: MobKind) -> MobDef { return mobDefTable[k.rawValue] }

func makeMobDef(_ k: MobKind) -> MobDef {
    switch k {
    case .pig: return MobDef(name: "Pig", w: 0.9, h: 0.7, hp: 10, speed: 1.6, dmg: 0, behavior: .passive)
    case .cow: return MobDef(name: "Cow", w: 1.3, h: 1.1, hp: 14, speed: 1.4, dmg: 0, behavior: .passive)
    case .sheep: return MobDef(name: "Sheep", w: 1.1, h: 0.95, hp: 12, speed: 1.5, dmg: 0, behavior: .passive)
    case .chicken: return MobDef(name: "Chicken", w: 0.6, h: 0.6, hp: 5, speed: 1.8, dmg: 0, behavior: .skittish)
    case .crow: return MobDef(name: "Crow", w: 0.6, h: 0.5, hp: 4, speed: 3.6, dmg: 0, behavior: .flyer, flying: true)
    case .giraffe: return MobDef(name: "Giraffe", w: 1.6, h: 3.2, hp: 30, speed: 3.4, dmg: 0, behavior: .skittish)
    case .frog: return MobDef(name: "Frog", w: 0.5, h: 0.4, hp: 3, speed: 2.0, dmg: 0, behavior: .skittish, jump: 9)
    case .fish: return MobDef(name: "Fish", w: 0.7, h: 0.4, hp: 3, speed: 2.2, dmg: 0, behavior: .swimmer)
    case .elephant: return MobDef(name: "Elephant", w: 2.8, h: 2.4, hp: 80, speed: 2.4, dmg: 16, behavior: .defensive, aggro: 10)
    case .bear: return MobDef(name: "Brown Bear", w: 1.8, h: 1.2, hp: 42, speed: 2.8, dmg: 10, behavior: .defensive, aggro: 11)
    case .grizzly: return MobDef(name: "Grizzly Bear", w: 2.0, h: 1.4, hp: 70, speed: 3.4, dmg: 16, behavior: .hostile, aggro: 12, hostile: true)
    case .polarBear: return MobDef(name: "Polar Bear", w: 2.0, h: 1.4, hp: 64, speed: 3.2, dmg: 15, behavior: .hostile, aggro: 12, hostile: true)
    case .tiger: return MobDef(name: "Tiger", w: 1.7, h: 1.0, hp: 48, speed: 4.6, dmg: 14, behavior: .hostile, aggro: 14, jump: 15, hostile: true)
    case .wolf: return MobDef(name: "Wolf", w: 1.2, h: 0.9, hp: 24, speed: 4.0, dmg: 6, behavior: .defensive, aggro: 11, jump: 14)
    case .cat: return MobDef(name: "Cat", w: 0.7, h: 0.6, hp: 10, speed: 3.0, dmg: 0, behavior: .skittish, jump: 13)
    case .zombie: return MobDef(name: "Zombie", w: 0.7, h: 1.7, hp: 30, speed: 1.8, dmg: 8, behavior: .hostile, aggro: 16, hostile: true)
    case .skeleton: return MobDef(name: "Skeleton Knight", w: 0.7, h: 1.8, hp: 38, speed: 2.1, dmg: 9, behavior: .hostile, aggro: 15, hostile: true)
    case .slime: return MobDef(name: "Slime", w: 0.9, h: 0.7, hp: 18, speed: 2.6, dmg: 5, behavior: .hostile, aggro: 12, jump: 11, hostile: true)
    case .bat: return MobDef(name: "Cave Bat", w: 0.6, h: 0.4, hp: 6, speed: 4.2, dmg: 4, behavior: .flyer, flying: true, aggro: 12, hostile: true)
    case .scorpion: return MobDef(name: "Scorpion", w: 1.2, h: 0.6, hp: 26, speed: 2.6, dmg: 8, behavior: .hostile, aggro: 11, hostile: true)
    case .wraith: return MobDef(name: "Wraith", w: 0.9, h: 1.5, hp: 44, speed: 2.8, dmg: 12, behavior: .flyer, flying: true, aggro: 18, hostile: true)
    case .villager: return MobDef(name: "Villager", w: 0.7, h: 1.7, hp: 20, speed: 1.4, dmg: 0, behavior: .passive)
    case .pirate: return MobDef(name: "Pirate", w: 0.7, h: 1.8, hp: 48, speed: 2.5, dmg: 11, behavior: .hostile, aggro: 20, hostile: true)
    case .pirateGunner: return MobDef(name: "Pirate Gunner", w: 0.7, h: 1.8, hp: 40, speed: 1.9, dmg: 9, behavior: .ranged, aggro: 20, hostile: true)
    case .pirateCaptain: return MobDef(name: "Pirate Captain", w: 0.8, h: 1.9, hp: 140, speed: 2.5, dmg: 15, behavior: .hostile, aggro: 22, hostile: true)
    case .imp: return MobDef(name: "Umbral Imp", w: 0.7, h: 1.5, hp: 34, speed: 2.6, dmg: 10, behavior: .ranged, aggro: 18, hostile: true)
    case .emberSlime: return MobDef(name: "Ember Slime", w: 1.0, h: 0.8, hp: 36, speed: 2.8, dmg: 9, behavior: .hostile, aggro: 12, jump: 12, hostile: true)
    case .cinderBat: return MobDef(name: "Cinder Bat", w: 0.6, h: 0.4, hp: 14, speed: 4.6, dmg: 7, behavior: .flyer, flying: true, aggro: 14, hostile: true)
    case .bearBoss: return MobDef(name: "Ursavor, Warden of the Gate", w: 5.2, h: 3.9, hp: 900, speed: 3.0, dmg: 22, behavior: .boss, aggro: 60, hostile: true)
    case .rex: return MobDef(name: "Tyrannax the Bonecrown", w: 7.0, h: 4.4, hp: 1400, speed: 3.4, dmg: 30, behavior: .boss, aggro: 60, hostile: true)
    }
}

// MARK: - Drops

func mobDrops(_ k: MobKind, _ rng: inout RNG, _ sheared: Bool) -> [Stack] {
    var out: [Stack] = []
    func add(_ it: Item, _ lo: Int, _ hi: Int, _ p: Double) {
        if rng.double() < p { out.append(Stack(item: it, count: lo + rng.int(max(1, hi - lo + 1)))) }
    }
    switch k {
    case .pig: add(.food(.rawMeat), 1, 3, 1.0)
    case .cow: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 1, 2, 0.8)
    case .sheep: add(.food(.rawMeat), 1, 2, 1.0); if !sheared { add(.mat(.wool), 1, 3, 0.9) }
    case .chicken: add(.food(.rawMeat), 1, 1, 0.9); add(.mat(.feather), 1, 3, 0.9)
    case .crow: add(.mat(.feather), 1, 2, 0.8)
    case .giraffe: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 2, 4, 0.9)
    case .frog: add(.mat(.string), 0, 1, 0.1)
    case .fish: add(.food(.rawFish), 1, 1, 1.0)
    case .elephant: add(.food(.rawMeat), 4, 7, 1.0); add(.mat(.tusk), 1, 2, 0.8); add(.mat(.leather), 2, 4, 0.9)
    case .bear: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.fur), 1, 3, 0.9); add(.mat(.claw), 1, 1, 0.3)
    case .grizzly: add(.food(.rawMeat), 3, 5, 1.0); add(.mat(.fur), 2, 4, 1.0); add(.mat(.claw), 1, 2, 0.6)
    case .polarBear: add(.food(.rawMeat), 3, 5, 1.0); add(.mat(.fur), 2, 4, 1.0); add(.mat(.claw), 1, 2, 0.5)
    case .tiger: add(.food(.rawMeat), 2, 4, 1.0); add(.mat(.leather), 1, 3, 0.9); add(.mat(.claw), 1, 2, 0.6)
    case .wolf: add(.food(.rawMeat), 1, 2, 0.9); add(.mat(.fur), 1, 2, 0.6); add(.mat(.bone), 1, 2, 0.4)
    case .cat: add(.mat(.string), 1, 2, 0.5)
    case .zombie: add(.food(.rawMeat), 0, 1, 0.3); add(.mat(.string), 0, 2, 0.3); add(.food(.carrot), 1, 1, 0.08); add(.mat(.ironBar), 1, 1, 0.04)
    case .skeleton: add(.mat(.bone), 1, 3, 0.9); add(.ammo(.arrow), 2, 6, 0.5); add(.sword(.stone), 1, 1, 0.06); add(.mat(.coal), 1, 3, 0.4)
    case .slime: add(.mat(.string), 1, 2, 0.4); add(.block(.torch), 1, 3, 0.3)
    case .bat: add(.mat(.string), 0, 1, 0.2)
    case .scorpion: add(.mat(.claw), 1, 1, 0.5); add(.food(.rawMeat), 1, 1, 0.5)
    case .wraith: add(.mat(.mythrilOre), 1, 2, 0.4); add(.mat(.goldBar), 1, 2, 0.3)
    case .villager: break
    case .pirate: add(.mat(.goldBar), 1, 2, 0.5); add(.ammo(.bullet), 2, 6, 0.4); add(.mat(.gunpowder), 1, 3, 0.5); add(.sword(.iron), 1, 1, 0.1); add(.gadget(.bomb), 1, 2, 0.15)
    case .pirateGunner: add(.mat(.goldBar), 1, 2, 0.5); add(.ammo(.bullet), 3, 8, 0.7); add(.mat(.gunpowder), 1, 4, 0.7); add(.gun(.pistol), 1, 1, 0.12)
    case .pirateCaptain: add(.mat(.goldBar), 4, 8, 1.0); add(.mat(.diamond), 1, 3, 0.8); add(.gun(.rifle), 1, 1, 0.4); add(.ammo(.bullet), 8, 16, 1.0)
    case .imp: add(.mat(.emberOre), 1, 2, 0.5); add(.mat(.coal), 2, 4, 0.6)
    case .emberSlime: add(.mat(.emberOre), 1, 3, 0.6); add(.block(.torch), 2, 5, 0.5)
    case .cinderBat: add(.mat(.emberOre), 0, 1, 0.3)
    case .bearBoss:
        add(.mat(.fur), 6, 10, 1.0); add(.mat(.claw), 3, 5, 1.0); add(.mat(.goldBar), 6, 12, 1.0)
        add(.mat(.diamond), 3, 6, 1.0); add(.food(.cookedMeat), 6, 10, 1.0)
        add(.armor(.chest, .gold), 1, 1, 0.5)
    case .rex:
        add(.mat(.bone), 10, 20, 1.0); add(.mat(.tusk), 2, 4, 1.0); add(.mat(.goldBar), 6, 12, 1.0)
        add(.mat(.mythrilBar), 2, 5, 1.0); add(.food(.cookedMeat), 6, 10, 1.0)
    }
    return out
}

// MARK: - Spawn rules

enum SpawnPlace { case surface, cave, ocean, umbral }
enum SpawnWhen { case any, day, night }

struct SpawnRule {
    var kind: MobKind
    var weight: Double
    var place: SpawnPlace
    var when: SpawnWhen
    var biomes: [Biome]
    var group: Int
    var minY: Int = 0
    var maxY: Int = 9999
}

let spawnRules: [SpawnRule] = [
    // surface, passive and wild animals by biome
    SpawnRule(kind: .pig, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest], group: 2),
    SpawnRule(kind: .cow, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest], group: 2),
    SpawnRule(kind: .sheep, weight: 5, place: .surface, when: .any, biomes: [.plains, .forest, .mountain], group: 3),
    SpawnRule(kind: .chicken, weight: 4, place: .surface, when: .day, biomes: [.plains, .forest, .savanna], group: 3),
    SpawnRule(kind: .crow, weight: 3, place: .surface, when: .any, biomes: [.plains, .forest, .desert, .savanna, .swamp, .mountain], group: 2),
    SpawnRule(kind: .giraffe, weight: 5, place: .surface, when: .any, biomes: [.savanna], group: 2),
    SpawnRule(kind: .elephant, weight: 3, place: .surface, when: .any, biomes: [.savanna, .jungle], group: 1),
    SpawnRule(kind: .tiger, weight: 3, place: .surface, when: .any, biomes: [.jungle, .savanna], group: 1),
    SpawnRule(kind: .bear, weight: 3, place: .surface, when: .any, biomes: [.forest, .mountain], group: 1),
    SpawnRule(kind: .grizzly, weight: 2, place: .surface, when: .any, biomes: [.mountain, .forest], group: 1),
    SpawnRule(kind: .polarBear, weight: 4, place: .surface, when: .any, biomes: [.tundra], group: 1),
    SpawnRule(kind: .wolf, weight: 3, place: .surface, when: .night, biomes: [.tundra, .forest, .plains], group: 3),
    SpawnRule(kind: .frog, weight: 5, place: .surface, when: .any, biomes: [.swamp], group: 2),
    SpawnRule(kind: .scorpion, weight: 5, place: .surface, when: .any, biomes: [.desert], group: 1),
    // surface hostile
    SpawnRule(kind: .zombie, weight: 7, place: .surface, when: .night, biomes: [], group: 2),
    SpawnRule(kind: .slime, weight: 3, place: .surface, when: .night, biomes: [.plains, .forest, .jungle, .swamp], group: 1),
    // oceans
    SpawnRule(kind: .fish, weight: 8, place: .ocean, when: .any, biomes: [], group: 4),
    // caves
    SpawnRule(kind: .skeleton, weight: 6, place: .cave, when: .any, biomes: [], group: 2, minY: 150),
    SpawnRule(kind: .zombie, weight: 2, place: .cave, when: .any, biomes: [], group: 1, minY: 140),
    SpawnRule(kind: .slime, weight: 3, place: .cave, when: .any, biomes: [], group: 2, minY: 140),
    SpawnRule(kind: .bat, weight: 4, place: .cave, when: .any, biomes: [], group: 3, minY: 150),
    SpawnRule(kind: .wraith, weight: 2, place: .cave, when: .any, biomes: [], group: 1, minY: 380),
    // umbral realm
    SpawnRule(kind: .imp, weight: 5, place: .umbral, when: .any, biomes: [], group: 1),
    SpawnRule(kind: .wraith, weight: 3, place: .umbral, when: .any, biomes: [], group: 1),
    SpawnRule(kind: .emberSlime, weight: 5, place: .umbral, when: .any, biomes: [], group: 2),
    SpawnRule(kind: .cinderBat, weight: 4, place: .umbral, when: .any, biomes: [], group: 3)
]

// MARK: - Mob instance

final class Mob {
    let id: Int
    var kind: MobKind
    var b: Body
    var hp: Double
    var maxHP: Double
    var dir: Int = 1
    var anim: Double = 0
    var hurtT: Double = 0
    var cd: Double = 0
    var t1: Double = 0
    var t2: Double = 0
    var t3: Double = 0
    var st: Int = 0
    var variant: Int = 0
    var tame: Bool = false
    var angry: Bool = false
    var persistent: Bool = false
    var sheared: Bool = false
    var blocking: Bool = false
    var boat: Int = -1
    var boatOffX: Double = 0
    var raiding: Bool = false
    var burn: Double = 0
    var stuckT: Double = 0
    var lastX: Double = 0
    var homeX: Double = 0
    var homeY: Double = 0
    var mounted: Bool = false
    var downed: Bool = false
    var lair: Int = 0
    var phase: Int = 0
    var tele: Double = 0
    var atk: Int = 0
    var tx: Double = 0
    var ty: Double = 0
    var regrow: Double = 0
    var knock: Double = 0
    /// time folded in while far-away AI updates were skipped
    var aiAccum: Double = 0
    /// set when the mob should leave the list at the end of the frame
    var removed: Bool = false
    /// white hit flash, death animation and knockback lean
    var flash: Double = 0
    var deathT: Double = -1
    var lean: Double = 0
    /// hazard and damage bookkeeping (see the damage system)
    var hazardT: Double = 0
    var lastAttacker: Int = 0
    var lastHitByPlayer: Double = -100
    var hitStamps: [Int: Double] = [:]
    var fallPeak: Double = 0
    var burnTick: Double = 0

    init(id: Int, kind: MobKind, x: Double, y: Double) {
        self.id = id
        self.kind = kind
        let d: MobDef = mobDef(kind)
        self.b = Body(x: x, y: y, w: d.w, h: d.h)
        self.hp = d.hp
        self.maxHP = d.hp
        self.homeX = x
        self.homeY = y
        self.lastX = x
        self.dir = Int.random(in: 0...1) == 0 ? -1 : 1
        self.t1 = Double.random(in: 0.5...3.0)
    }

    var def: MobDef { return mobDef(kind) }
    var x: Double { return b.x }
    var y: Double { return b.y }
    var isBoss: Bool { return kind == .bearBoss || (kind == .rex && !tame) }
}

struct MobSave: Codable {
    var kind: Int
    var x: Double
    var y: Double
    var hp: Double
    var maxHP: Double
    var tame: Bool
    var variant: Int
    var downed: Bool
    var lair: Int
}

// ===== p13b_vehicles =====

// MARK: - Vehicles (player built) and pirate ships

struct PartCell: Hashable, Codable {
    var dx: Int
    var dy: Int
}

struct VPartSave: Codable {
    var dx: Int
    var dy: Int
    var type: Int
}

struct VehicleSave: Codable {
    var id: Int
    var parts: [VPartSave]
    /// centre of mass (saves with `rot`), or the bottom-centre of the box (older saves)
    var x: Double
    var y: Double
    var fuel: Double
    var dir: Int
    var kit: Int?
    /// rotation in radians; nil in saves made before vehicles could rotate
    var rot: Double? = nil
}

/// Displaced volume per part (how much it floats)
func partVolume(_ p: PartType) -> Double {
    switch p {
    case .hull: return 4.0
    case .frame: return 0.3
    case .fuelTank: return 0.25
    case .seat: return 0.1
    default: return 0.0
    }
}

/// Mining power of a drill part: (tier it can break, speed)
func drillPower(_ p: PartType) -> (Int, Double) {
    switch p {
    case .drill: return (4, 4.6)
    case .diamondDrill: return (7, 8.5)
    default: return (0, 0)
    }
}

func isDrill(_ p: PartType) -> Bool { return p == .drill || p == .diamondDrill }

/// A player-built vehicle: a rigid body made of 1x1 parts. It has a centre of mass, a rotation and
/// an angular velocity, and every part collides, floats and drives at its rotated position, so
/// what you see is exactly what touches the world.
final class Vehicle {
    let id: Int
    var parts: [PartCell: PartType] = [:]
    /// world-space bounding box of the rotated parts (kept for spawning, decks, pick tests)
    var b: Body
    // rigid body state
    var px: Double = 0
    var py: Double = 0
    var vx: Double = 0
    var vy: Double = 0
    var angle: Double = 0
    var angVel: Double = 0
    /// centre of mass in cell coordinates (cell (0,0) spans 0...1)
    var comX: Double = 0.5
    var comY: Double = 0.5
    var inertia: Double = 1
    var fuel: Double = 0
    var dir: Int = 1
    var minX: Int = 0
    var maxX: Int = 0
    var minY: Int = 0
    var maxY: Int = 0
    var mass: Double = 1
    var buoyancy: Double = 0
    var engines: Int = 0
    var wheels: Int = 0
    var propellers: Int = 0
    var paddles: Int = 0
    var tanks: Int = 0
    var drills: Int = 0
    var hasSeat: Bool = false
    var hasSteering: Bool = false
    var throttle: Double = 0
    var wheelRot: Double = 0
    var rider: Bool = false
    var propRot: Double = 0
    var drillRot: Double = 0
    var drilling: Bool = false
    var smoke: Double = 0
    /// contacts touched in the last physics step (wheels on the ground, any part on the ground)
    var wheelContacts: Int = 0
    var contacts: Int = 0
    var submerged: Double = 0
    var sleepT: Double = 0
    var asleep: Bool = false
    /// direction each drill faces in vehicle space, and its mining progress
    var drillDir: [PartCell: (Int, Int)] = [:]
    var drillWork: [PartCell: (Int, Int, Double)] = [:]
    /// the kit this vehicle came from (-1 = built part by part, or changed since)
    var kit: Int = -1

    init(id: Int, first: PartType, x: Double, y: Double) {
        self.id = id
        self.b = Body(x: x, y: y, w: 1, h: 1)
        parts[PartCell(dx: 0, dy: 0)] = first
        recompute(keepAnchor: false)
        placeBox(left: x - 0.5, bottom: y)
    }

    // MARK: transforms

    var cosA: Double { return cos(angle) }
    var sinA: Double { return sin(angle) }

    /// vehicle-space point (cell units) to world
    func toWorld(_ lx: Double, _ ly: Double) -> (Double, Double) {
        let ox: Double = lx - comX
        let oy: Double = ly - comY
        let c: Double = cosA
        let s: Double = sinA
        return (px + ox * c - oy * s, py + ox * s + oy * c)
    }

    /// world point to vehicle space (cell units)
    func toLocal(_ wx: Double, _ wy: Double) -> (Double, Double) {
        let dx: Double = wx - px
        let dy: Double = wy - py
        let c: Double = cosA
        let s: Double = sinA
        return (dx * c + dy * s + comX, -dx * s + dy * c + comY)
    }

    func cellCenter(_ c: PartCell) -> (Double, Double) {
        return toWorld(Double(c.dx) + 0.5, Double(c.dy) + 0.5)
    }

    /// top-left of the cell's (unrotated) box around its rotated centre
    func cellPos(_ c: PartCell) -> (Double, Double) {
        let p: (Double, Double) = cellCenter(c)
        return (p.0 - 0.5, p.1 - 0.5)
    }

    func cellAt(_ wx: Double, _ wy: Double) -> PartCell {
        let l: (Double, Double) = toLocal(wx, wy)
        return PartCell(dx: Int(floor(l.0)), dy: Int(floor(l.1)))
    }

    /// Places an unrotated vehicle so its parts' box has this left edge and bottom
    func placeBox(left: Double, bottom: Double) {
        angle = 0
        px = left + (comX - Double(minX))
        py = bottom - (Double(maxY + 1) - comY)
        updateBox()
    }

    /// Recomputes the world bounding box from the rotated part corners
    func updateBox() {
        var x0: Double = 1e9, x1: Double = -1e9, y0: Double = 1e9, y1: Double = -1e9
        let c: Double = cosA
        let s: Double = sinA
        for (cell, _) in parts {
            let corners: [(Double, Double)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
            for k in corners {
                let ox: Double = Double(cell.dx) + k.0 - comX
                let oy: Double = Double(cell.dy) + k.1 - comY
                let wx: Double = px + ox * c - oy * s
                let wy: Double = py + ox * s + oy * c
                x0 = min(x0, wx); x1 = max(x1, wx); y0 = min(y0, wy); y1 = max(y1, wy)
            }
        }
        b.w = max(0.1, x1 - x0)
        b.h = max(0.1, y1 - y0)
        b.x = (x0 + x1) * 0.5
        b.y = y1
        b.vx = vx
        b.vy = vy
    }

    func recompute(keepAnchor: Bool) {
        // remember where one surviving cell is, so the rest of the vehicle stays put in the world
        var anchor: PartCell? = nil
        var anchorW: (Double, Double) = (0, 0)
        if keepAnchor, let c0 = parts.keys.first {
            anchor = c0
            anchorW = cellCenter(c0)
        }
        var x0: Int = 0, x1: Int = 0, y0: Int = 0, y1: Int = 0
        var first: Bool = true
        mass = 0
        buoyancy = 0
        engines = 0; wheels = 0; propellers = 0; paddles = 0; tanks = 0; drills = 0
        hasSeat = false
        hasSteering = false
        var mx: Double = 0
        var my: Double = 0
        for (c, t) in parts {
            if first { x0 = c.dx; x1 = c.dx; y0 = c.dy; y1 = c.dy; first = false }
            x0 = min(x0, c.dx); x1 = max(x1, c.dx); y0 = min(y0, c.dy); y1 = max(y1, c.dy)
            mass += t.mass
            mx += t.mass * (Double(c.dx) + 0.5)
            my += t.mass * (Double(c.dy) + 0.5)
            buoyancy += partVolume(t)
            switch t {
            case .engine: engines += 1
            case .wheel: wheels += 1
            case .propeller: propellers += 1
            case .paddle: paddles += 1
            case .fuelTank: tanks += 1
            case .seat: hasSeat = true
            case .steering: hasSteering = true
            case .drill, .diamondDrill: drills += 1
            default: break
            }
        }
        minX = x0; maxX = x1; minY = y0; maxY = y1
        mass = max(0.3, mass)
        comX = mx / mass
        comY = my / mass
        // moment of inertia: each part as a 1x1 plate around the centre of mass
        var inert: Double = 0
        for (c, t) in parts {
            let ox: Double = Double(c.dx) + 0.5 - comX
            let oy: Double = Double(c.dy) + 0.5 - comY
            inert += t.mass * (ox * ox + oy * oy + 1.0 / 6.0)
        }
        inertia = max(0.2, inert)
        // drills face the open side of their cell
        drillDir.removeAll()
        for (c, t) in parts where isDrill(t) {
            let free: (PartCell) -> Bool = { self.parts[$0] == nil }
            if free(PartCell(dx: c.dx + 1, dy: c.dy)) && !free(PartCell(dx: c.dx - 1, dy: c.dy)) { drillDir[c] = (1, 0) }
            else if free(PartCell(dx: c.dx - 1, dy: c.dy)) && !free(PartCell(dx: c.dx + 1, dy: c.dy)) { drillDir[c] = (-1, 0) }
            else if free(PartCell(dx: c.dx, dy: c.dy + 1)) { drillDir[c] = (0, 1) }
            else if free(PartCell(dx: c.dx + 1, dy: c.dy)) { drillDir[c] = (1, 0) }
            else { drillDir[c] = (0, -1) }
        }
        drillWork = drillWork.filter { parts[$0.key] != nil }
        if let a = anchor, parts[a] != nil {
            // put the anchor cell back where it was
            let ox: Double = Double(a.dx) + 0.5 - comX
            let oy: Double = Double(a.dy) + 0.5 - comY
            let c: Double = cosA
            let s: Double = sinA
            px = anchorW.0 - (ox * c - oy * s)
            py = anchorW.1 - (ox * s + oy * c)
        }
        asleep = false
        updateBox()
    }

    var fuelCapacity: Double { return Double(tanks) * 60.0 + (engines > 0 ? 8.0 : 0.0) }
    var isBoat: Bool { return buoyancy > 0 }
    var canDriveOnLand: Bool { return wheels >= 2 && engines > 0 }
    var canSail: Bool { return buoyancy >= mass * 0.8 && ((engines > 0 && propellers > 0) || paddles > 0) }
    var topY: Double { return b.y - b.h }
    var speed: Double { return sqrt(vx * vx + vy * vy) }
    /// roughly upright (flat enough to stand on, to place kits next to, and so on)
    var upright: Bool { return abs(remainder(angle, 2.0 * Double.pi)) < 0.35 }

    func hasNeighbor(_ c: PartCell) -> Bool {
        let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
        for k in n { if parts[k] != nil { return true } }
        return false
    }

    func canAttach(_ c: PartCell, _ t: PartType) -> Bool {
        if parts[c] != nil { return false }
        if !hasNeighbor(c) { return false }
        if t == .wheel {
            // wheels hang below the body: something must be directly above, nothing below
            if parts[PartCell(dx: c.dx, dy: c.dy - 1)] == nil { return false }
            if parts[PartCell(dx: c.dx, dy: c.dy + 1)] != nil { return false }
        }
        if t == .steering {
            let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
            var ok: Bool = false
            for k in n { if parts[k] == .seat { ok = true } }
            if !ok { return false }
        }
        if t == .propeller || t == .paddle {
            // must sit at the edge of the vehicle
            let side: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy)]
            var free: Bool = false
            for k in side { if parts[k] == nil { free = true } }
            if !free { return false }
        }
        if isDrill(t) {
            // a drill needs one open side to bore into
            let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1)]
            var free: Bool = false
            for k in n { if parts[k] == nil { free = true } }
            if !free { return false }
        }
        return true
    }

    /// Removes a part, returning every part that is no longer connected (including the removed one)
    func removePart(_ c: PartCell) -> [PartType] {
        var out: [PartType] = []
        if let t = parts[c] { out.append(t) }
        parts[c] = nil
        if parts.isEmpty { return out }
        // flood fill from any remaining cell
        var seen: Set<PartCell> = []
        var stack: [PartCell] = [parts.keys.first!]
        while let cur = stack.popLast() {
            if seen.contains(cur) { continue }
            seen.insert(cur)
            let n: [PartCell] = [PartCell(dx: cur.dx + 1, dy: cur.dy), PartCell(dx: cur.dx - 1, dy: cur.dy), PartCell(dx: cur.dx, dy: cur.dy + 1), PartCell(dx: cur.dx, dy: cur.dy - 1)]
            for k in n { if parts[k] != nil && !seen.contains(k) { stack.append(k) } }
        }
        // keep the largest connected group
        var group: Set<PartCell> = seen
        if seen.count * 2 < parts.count {
            var other: Set<PartCell> = []
            for k in parts.keys { if !seen.contains(k) { other.insert(k) } }
            group = other
        }
        for k in Array(parts.keys) {
            if !group.contains(k) {
                if let t = parts[k] { out.append(t) }
                parts[k] = nil
            }
        }
        return out
    }

    func save() -> VehicleSave {
        var ps: [VPartSave] = []
        for (c, t) in parts { ps.append(VPartSave(dx: c.dx, dy: c.dy, type: t.rawValue)) }
        return VehicleSave(id: id, parts: ps, x: px, y: py, fuel: fuel, dir: dir, kit: kit, rot: angle)
    }

    static func restore(_ s: VehicleSave) -> Vehicle {
        let v = Vehicle(id: s.id, first: .frame, x: s.x, y: s.y)
        v.parts.removeAll()
        for p in s.parts { v.parts[PartCell(dx: p.dx, dy: p.dy)] = PartType(rawValue: p.type) ?? .frame }
        if v.parts.isEmpty { v.parts[PartCell(dx: 0, dy: 0)] = .frame }
        v.recompute(keepAnchor: false)
        if let r = s.rot {
            v.px = s.x
            v.py = s.y
            v.angle = r
            v.updateBox()
        } else {
            // older save: x, y were the bottom-centre of an unrotated box
            let w: Double = Double(v.maxX - v.minX + 1)
            v.placeBox(left: s.x - w * 0.5, bottom: s.y)
        }
        v.fuel = s.fuel
        v.dir = s.dir
        v.kit = s.kit ?? -1
        return v
    }
}

// MARK: - Pirate ships

struct ShipSave: Codable {
    var id: Int
    var x: Double
    var hp: Double
    var dir: Int
    var looted: Bool
}

final class PirateShip {
    let id: Int
    var x: Double
    var dir: Int
    var hp: Double = 180
    var maxHP: Double = 180
    var crew: [Int] = []
    var state: Int = 0
    var t: Double = 0
    var looted: Bool = false
    var bob: Double = 0
    var patrolMin: Double
    var patrolMax: Double
    var sink: Double = 0
    var hitT: Double = 0
    var speed: Double = 0

    static let deckHalf: Double = 4.0
    static let deckAbove: Double = 1.0
    static let spriteW: Double = 9.5
    static let spriteH: Double = 5.0
    static let waterRow: Double = 3.6
    static let deckRow: Double = 2.625

    init(id: Int, x: Double, dir: Int, pMin: Double, pMax: Double) {
        self.id = id
        self.x = x
        self.dir = dir
        self.patrolMin = pMin
        self.patrolMax = pMax
    }

    /// y of the deck standing line in tiles
    func deckY(_ seaY: Double) -> Double {
        return seaY - PirateShip.waterRow + PirateShip.deckRow + sink + sin(bob) * 0.12
    }
}

// ===== p14a_game =====

// MARK: - Game state

enum GameMode: String, Codable {
    case survival, creative, hardcore
    var title: String { return rawValue.capitalized }
}

struct Settings: Codable {
    var hair: Int = 0
    var scarf: Int = 0
    var touchControls: Bool = true
    var peaceful: Bool = false
    var showCoords: Bool = true
    var tilePx: Int = 24
    var rareChance: Double = 0.28
    var smoothLight: Bool = true
    /// true = 60 frames per second, false = 30 (smoother on older iPads)
    var fps60: Bool = true
    var showFPS: Bool = false
    // camera
    var camSmoothOn: Bool = true
    /// 0 = loose and floaty, 1 = tight
    var camFollow: Double = 0.55
    /// tiles the player can move before the camera starts to follow
    var camDeadZone: Double = 0.8
    var camLookAhead: Bool = true
    var shakeOn: Bool = true
    var shakeIntensity: Double = 0.5
    var showTrajectory: Bool = true

    var shakeScale: Double { return shakeOn ? shakeIntensity : 0 }

    static let cameraDefaults: Settings = Settings()

    mutating func resetCamera() {
        let d: Settings = Settings.cameraDefaults
        camSmoothOn = d.camSmoothOn
        camFollow = d.camFollow
        camDeadZone = d.camDeadZone
        camLookAhead = d.camLookAhead
        shakeOn = d.shakeOn
        shakeIntensity = d.shakeIntensity
        tilePx = d.tilePx
    }

    init() {}

    // Missing keys (settings saved by an older version) fall back to the defaults
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hair = (try? c.decodeIfPresent(Int.self, forKey: .hair)) ?? 0
        scarf = (try? c.decodeIfPresent(Int.self, forKey: .scarf)) ?? 0
        touchControls = (try? c.decodeIfPresent(Bool.self, forKey: .touchControls)) ?? true
        peaceful = (try? c.decodeIfPresent(Bool.self, forKey: .peaceful)) ?? false
        showCoords = (try? c.decodeIfPresent(Bool.self, forKey: .showCoords)) ?? true
        tilePx = (try? c.decodeIfPresent(Int.self, forKey: .tilePx)) ?? 24
        rareChance = (try? c.decodeIfPresent(Double.self, forKey: .rareChance)) ?? 0.28
        smoothLight = (try? c.decodeIfPresent(Bool.self, forKey: .smoothLight)) ?? true
        fps60 = (try? c.decodeIfPresent(Bool.self, forKey: .fps60)) ?? true
        showFPS = (try? c.decodeIfPresent(Bool.self, forKey: .showFPS)) ?? false
        camSmoothOn = (try? c.decodeIfPresent(Bool.self, forKey: .camSmoothOn)) ?? true
        camFollow = (try? c.decodeIfPresent(Double.self, forKey: .camFollow)) ?? 0.55
        camDeadZone = (try? c.decodeIfPresent(Double.self, forKey: .camDeadZone)) ?? 0.8
        camLookAhead = (try? c.decodeIfPresent(Bool.self, forKey: .camLookAhead)) ?? true
        shakeOn = (try? c.decodeIfPresent(Bool.self, forKey: .shakeOn)) ?? true
        shakeIntensity = (try? c.decodeIfPresent(Double.self, forKey: .shakeIntensity)) ?? 0.5
        showTrajectory = (try? c.decodeIfPresent(Bool.self, forKey: .showTrajectory)) ?? true
    }
}

/// The HUD and panels watch this instead of the whole game, so they only redraw when something they show changes.
final class HUDSignal: ObservableObject, @unchecked Sendable {
    @Published var tick: Int = 0
}

/// The world canvas watches this; it changes once per game step.
final class FrameTicker: ObservableObject, @unchecked Sendable {
    @Published var frame: Int = 0
}

struct IntPair: Equatable {
    var x: Int
    var y: Int
}

final class Game: ObservableObject, @unchecked Sendable {
    // UI refresh signals
    let hud: HUDSignal = HUDSignal()
    let ticker: FrameTicker = FrameTicker()
    var lastHudKey: Int = 0
    var renderFPS: Double = 0
    var hudTick: Int { return hud.tick }
    @Published var showInventory: Bool = false
    @Published var showDebug: Bool = false
    @Published var showMap: Bool = false
    @Published var paused: Bool = false
    @Published var openChest: IntPair? = nil
    @Published var message: String? = nil
    @Published var dead: Bool = false
    @Published var craftStation: Station = .hand

    // setup
    var world: World
    var settings: Settings
    var mode: GameMode
    var worldName: String = "World"
    var slot: Int = 0
    var seedValue: UInt64

    // time
    var timeOfDay: Double = 0.06
    let dayLength: Double = 720
    var dayCount: Int = 1
    var clock: Double = 0
    var playSeconds: Double = 0
    var messageT: Double = 0
    var hudAccum: Int = 0

    // player
    var pb: Body
    var facing: Int = 1
    var hp: Double = 20
    var maxHP: Double = 20
    var hunger: Double = 20
    var air: Double = 10
    var hurtT: Double = 0
    var invuln: Double = 0
    var deathT: Double = 0
    var inv: Inventory = Inventory()
    var sel: Int = 0
    var spawnX: Double = 0
    var spawnY: Double = 0
    var kills: Int = 0
    var coyote: Double = 0
    var jumpBuf: Double = 0
    var dropT: Double = 0
    var starveT: Double = 0
    var regenT: Double = 0
    var lastVy: Double = 0
    var walkAnim: Double = 0
    var fallPeak: Double = 0

    // cheats / debug
    var flying: Bool = false
    var noclip: Bool = false
    var godMode: Bool = false
    var freezeTime: Bool = false
    var monstersEnabled: Bool = true
    var speedMult: Double = 1.0
    var showHitboxes: Bool = false
    var showChunks: Bool = false
    var fullBright: Bool = false
    var infiniteReach: Bool = false

    // tool use
    var swingT: Double = 0
    var swingDur: Double = 0.25
    var swingDir: Int = 1
    var useCD: Double = 0
    var bowCharge: Double = 0
    var reloadT: Double = 0
    var reloadSlot: Int = -1
    var mineX: Int = 0
    var mineY: Int = 0
    var mineP: Double = 0
    var mining: Bool = false
    var muzzleT: Double = 0
    var recoilT: Double = 0
    var bowRecoil: Double = 0
    var eatT: Double = 0

    // input state (set by the UI layer)
    var stick: Double = 0
    var stickY: Double = 0
    var keyL: Bool = false
    var keyR: Bool = false
    var jumpHeld: Bool = false
    var jumpPrev: Bool = false
    var downHeld: Bool = false
    var useHeld: Bool = false
    var usePressedFlag: Bool = false
    var useReleasedFlag: Bool = false
    var aimX: Double = 0
    var aimY: Double = 0
    var aimValid: Bool = false
    var tapPending: Bool = false
    var useWasHeld: Bool = false
    var lavaT: Double = 0
    var drownT: Double = 0
    var hardcoreOver: Bool = false
    var tapT: Double = 0
    var holdT: Double = 0
    var pendingInteract: Bool = false
    var downTime: Double = 0
    var pointerStartX: Double = 0
    var pointerStartY: Double = 0
    var carry: Stack? = nil
    var placeCD: Double = 0
    var villagerTimer: Double = 1.0
    var decksCache: [Deck] = []
    var mineNeed: Double = 1

    // camera and view
    var camX: Double = 0
    /// where the camera is heading (dead zone applied); camX/camY ease toward it
    var camTX: Double = 0
    var camTY: Double = 0
    var camLead: Double = 0
    var camY: Double = 0
    var viewW: Double = 1024
    var viewH: Double = 768
    var tilePx: Int = 24
    var shake: Double = 0

    // entities
    var mobs: [Mob] = []
    var projectiles: [Projectile] = []
    var drops: [DropItem] = []
    var particles: [Particle] = []
    var floats: [FloatText] = []
    var vehicles: [Vehicle] = []
    var ships: [PirateShip] = []
    var nextID: Int = 1
    var spawnTimer: Double = 2.0
    var shipTimer: Double = 20.0
    var villagerCells: Set<Int> = []
    var fallingBlocks: [FallingBlock] = []
    var decayZones: [DecayZone] = []
    let mobGrid: MobGrid = MobGrid()
    var frameNo: Int = 0

    // damage bookkeeping
    var playerHitStamps: [Int: Double] = [:]
    var playerBurn: Double = 0
    var playerBurnTick: Double = 0
    /// debug multipliers: damage the player deals / takes
    var dmgOutMult: Double = 1.0
    var dmgInMult: Double = 1.0

    // lighting
    var light: LightMap = LightMap()
    var lightDark: [UInt32] = []
    var lightGlow: [UInt32] = []
    var lightRev: Int = 0
    var lightTimer: Double = 0
    var dynLights: [(Int, Int, Int)] = []

    // bosses & progress
    var defeated: Set<Int> = []
    var rex: Mob? = nil
    var rexSave: MobSave? = nil
    var activeBoss: Mob? = nil
    var bossBarName: String = ""
    var bossBarFrac: Double = 0
    var gotMap: Bool = false
    var portalOpened: Bool = false
    var portalT: Double = 0
    var portalCool: Double = 0
    var fadeT: Double = 0
    var mounted: Mob? = nil
    var inVehicle: Vehicle? = nil
    var steerTick: Double = 0
    var vehicleStash: [[Vehicle]] = [[], []]
    var mapCache: TreasureMap? = nil
    var hintT: Double = 0
    var autosaveT: Double = 0

    // streaming stats
    var loadRadius: Int = 5
    var lastStreamCX: Int = Int.min
    var chunksLoadedLast: Int = 0
    var tickMs: Double = 0
    var tickWorstMs: Double = 0

    init(mode: GameMode, infinite: Bool, seed: UInt64, settings: Settings, genVersion: Int = WorldGen.currentVersion) {
        self.mode = mode
        self.settings = settings
        self.seedValue = seed
        let gen = WorldGen(seed: seed, infinite: infinite, rareChance: settings.rareChance, genVersion: genVersion)
        self.world = World(gen: gen)
        self.tilePx = settings.tilePx
        self.pb = Body(x: Double(gen.spawnX) + 0.5, y: 100, w: 0.7, h: 1.8)
        world.loadAround(centerX: gen.spawnX, radius: 6)
        let sy: Int = world.surfaceY(gen.spawnX)
        pb.y = Double(sy)
        spawnX = pb.x
        spawnY = pb.y
        camX = pb.x
        camY = pb.y - 2
        setupStartingKit()
        timeOfDay = 0.06
    }

    func setupStartingKit() {
        if mode == .creative {
            flying = false
            return
        }
        _ = inv.add(.block(.torch), 4)
    }

    var gen: WorldGen { return world.gen }
    var isCreative: Bool { return mode == .creative }
    var viewTilesW: Double { return viewW / Double(tilePx) }
    var viewTilesH: Double { return viewH / Double(tilePx) }

    func newID() -> Int {
        nextID += 1
        return nextID
    }

    func say(_ s: String, _ t: Double = 3.0) {
        message = s
        messageT = t
        hud.tick &+= 1
    }

    func bumpHUD() {
        hud.tick &+= 1
    }

    // MARK: time of day

    /// 1 = full day, 0 = deep night
    var dayFactor: Double {
        let t: Double = timeOfDay
        if world.dim != .overworld { return 0 }
        if t < 0.50 { return 1.0 }
        if t < 0.58 { return 1.0 - smooth((t - 0.50) / 0.08) }
        if t < 0.92 { return 0.0 }
        return smooth((t - 0.92) / 0.08)
    }

    var skyLevel: Int {
        if world.dim != .overworld { return 0 }
        return Int((6.0 + 9.0 * dayFactor).rounded())
    }

    var isNight: Bool { return dayFactor < 0.35 }

    // MARK: items

    func giveItem(_ it: Item, _ n: Int, extra: Int = 0) {
        let left: Int = inv.add(it, n, extra: extra)
        if left > 0 {
            spawnDrop(Stack(item: it, count: left, extra: extra), pb.x, pb.y - 1.0, Double(facing) * 3.0, -4.0)
        }
        bumpHUD()
    }

    func spawnDrop(_ s: Stack, _ x: Double, _ y: Double, _ vx: Double, _ vy: Double) {
        if s.count <= 0 { return }
        drops.append(DropItem(stack: s, x: x, y: y, vx: vx, vy: vy))
    }

    func spawnParticles(_ x: Double, _ y: Double, _ color: UInt32, _ n: Int, _ speed: Double, _ life: Double = 0.6, _ grav: Double = 18) {
        if particles.count > 160 { return }
        for _ in 0..<n {
            let a: Double = Double.random(in: 0...(2 * Double.pi))
            let s: Double = Double.random(in: 0.3...1.0) * speed
            particles.append(Particle(x: x, y: y, vx: cos(a) * s, vy: sin(a) * s - speed * 0.3, life: life * Double.random(in: 0.6...1.2), maxLife: life, color: color, size: Double.random(in: 0.08...0.18), gravity: grav))
        }
    }

    func floatText(_ s: String, _ x: Double, _ y: Double, _ color: UInt32 = 0xFFFFFF) {
        if floats.count > 14 { floats.removeFirst() }
        floats.append(FloatText(x: x, y: y, text: s, life: 1.0, color: color))
    }

    // MARK: selected item helpers

    var heldStack: Stack? { return inv.slots[sel] }
    var heldItem: Item? { return inv.slots[sel]?.item }

    func setSel(_ i: Int) {
        sel = clampI(i, 0, Inventory.hotbarCount - 1)
        bowCharge = 0
        mining = false
        mineP = 0
        bumpHUD()
    }

    var playerCenterX: Double { return pb.x }
    var playerCenterY: Double { return pb.y - pb.h * 0.5 }

    func tileCoord(_ v: Double) -> Int { return Int(floor(v)) }
}

// ===== p14b_player =====

// MARK: - Master tick, player movement, survival, camera, streaming, lighting

extension Game {
    func tick(_ rawDt: Double) {
        if paused { return }
        let dt: Double = min(max(rawDt, 0.001), 0.05) * (freezeTime ? 1.0 : 1.0)
        let t0: Double = Date().timeIntervalSinceReferenceDate
        clock += dt
        if !dead { playSeconds += dt }
        if messageT > 0 {
            messageT -= dt
            if messageT <= 0 { message = nil }
        }
        updateTime(dt)
        mobGrid.rebuild(mobs)
        decksCache = (ships.isEmpty && vehicles.isEmpty) ? [] : buildDecks()
        updatePointerTimers(dt)
        updateInputEdges()
        updatePlayer(dt)
        updateUse(dt)
        updateMobs(dt)
        updateBosses(dt)
        updateSpawning(dt)
        updateProjectiles(dt)
        updateFallingBlocks(dt)
        updateDrops(dt)
        updateVehicles(dt)
        updateShips(dt)
        updateWorldTicks(dt)
        updatePortal(dt)
        updateAutosave(dt)
        updateParticles(dt)
        updateStreaming()
        updateCamera(dt)
        updateLight(dt)
        hudAccum += 1
        if hudAccum >= 5 {
            hudAccum = 0
            let k: Int = hudKey()
            if k != lastHudKey || showDebug {
                lastHudKey = k
                hud.tick &+= 1
            }
        }
        let t1: Double = Date().timeIntervalSinceReferenceDate
        tickMs = tickMs * 0.9 + (t1 - t0) * 1000.0 * 0.1
        tickWorstMs = max(tickWorstMs * 0.995, (t1 - t0) * 1000.0)
        Perf.shared.endFrame()
    }

    /// Screen shake, scaled (or disabled) by the camera settings
    func addShake(_ amount: Double) {
        shake = max(shake, amount * settings.shakeScale)
    }

    func updateTime(_ dt: Double) {
        if freezeTime || world.dim != .overworld { return }
        timeOfDay += dt / dayLength
        if timeOfDay >= 1.0 {
            timeOfDay -= 1.0
            dayCount += 1
        }
    }

    func updateInputEdges() {
        if useHeld && !usePressedFlag && !useWasHeld { usePressedFlag = true }
        useWasHeld = useHeld
    }

    // MARK: player

    func updatePlayer(_ dt: Double) {
        if dead {
            deathT += dt
            return
        }
        if invuln > 0 { invuln -= dt }
        if hurtT > 0 { hurtT -= dt }
        if shake > 0 { shake = max(0, shake - dt * 1.5) }
        var ix: Double = stick
        if keyL { ix -= 1.0 }
        if keyR { ix += 1.0 }
        ix = clampD(ix, -1.0, 1.0)
        if abs(ix) < 0.08 { ix = 0 }
        let jumpPressed: Bool = jumpHeld && !jumpPrev
        jumpPrev = jumpHeld
        if let v = inVehicle {
            driveVehicle(v, ix, jumpPressed, dt)
            return
        }
        if let r = mounted {
            rideRex(r, ix, jumpPressed, dt)
            return
        }
        let runMax: Double = 7.4 * speedMult
        if ix != 0 {
            facing = ix > 0 ? 1 : -1
        }
        if swingT > 0 || useHeld {
            if aimValid {
                facing = aimX >= pb.x ? 1 : -1
            }
        }
        if flying || noclip {
            let tx: Double = ix * 13.0 * speedMult
            var ty: Double = 0
            if jumpHeld { ty = -10.0 }
            if downHeld || stickY > 0.55 { ty = 10.0 }
            pb.vx += (tx - pb.vx) * min(1.0, dt * 9.0)
            pb.vy += (ty - pb.vy) * min(1.0, dt * 9.0)
            if noclip {
                pb.x += pb.vx * dt
                pb.y += pb.vy * dt
            } else {
                world.moveBody(&pb, dt, stepUp: 0, dropThrough: true, decks: [])
            }
            walkAnim += abs(pb.vx) * dt * 0.5
            lastVy = pb.vy
            checkHazards(dt)
            return
        }
        let inWater: Bool = pb.inWater
        let inLava: Bool = pb.inLava
        let swimming: Bool = inWater || inLava
        let target: Double = ix * runMax * (swimming ? 0.55 : 1.0)
        let accel: Double = pb.onGround ? 72.0 : 40.0
        if ix != 0 {
            if pb.vx < target { pb.vx = min(target, pb.vx + accel * dt) } else { pb.vx = max(target, pb.vx - accel * dt) }
        } else {
            let fr: Double = (pb.onGround ? 90.0 : 12.0) * dt
            if pb.vx > 0 { pb.vx = max(0, pb.vx - fr) } else { pb.vx = min(0, pb.vx + fr) }
        }
        if pb.onGround { coyote = 0.11 } else { coyote -= dt }
        if jumpPressed { jumpBuf = 0.13 } else { jumpBuf -= dt }
        if jumpBuf > 0 && coyote > 0 && !swimming {
            pb.vy = -15.9
            coyote = 0
            jumpBuf = 0
            pb.onGround = false
            spawnParticles(pb.x, pb.y, 0xB0A890, 4, 2.5, 0.35, 10)
        }
        if swimming {
            pb.vy += (inLava ? 14.0 : 11.0) * dt
            if jumpHeld { pb.vy = max(pb.vy - 52.0 * dt, -6.5) }
            pb.vy = clampD(pb.vy, -8.0, inLava ? 3.0 : 6.0)
        } else {
            var g: Double = gravityG
            if !jumpHeld && pb.vy < -5.0 { g *= 2.6 }
            pb.vy = min(pb.vy + g * dt, terminalV)
        }
        if (downHeld || stickY > 0.6) { dropT = 0.22 }
        if dropT > 0 { dropT -= dt }
        let decks: [Deck] = allDecks()
        let wasAir: Bool = !pb.onGround
        let peak: Double = pb.vy
        world.moveBody(&pb, dt, stepUp: 1.0, dropThrough: dropT > 0, decks: decks)
        if pb.deck >= 0 && pb.deck < decks.count {
            let dk: Deck = decks[pb.deck]
            pb.x += dk.vx * dt
        }
        doorTouch(ix)
        if !pb.onGround && pb.vy > 0 { fallPeak = max(fallPeak, pb.vy) }
        if pb.onGround && wasAir {
            if fallPeak > 20.0 && !swimming && mode != .creative && !godMode {
                let dmg: Double = (fallPeak - 20.0) * 1.15
                damagePlayer(dmg, from: pb.x, knock: 0, ignoreArmor: true)
                shake = 0.3
            }
            if fallPeak > 9.0 { spawnParticles(pb.x, pb.y, 0xB0A890, 6, 3.0, 0.4, 10) }
            fallPeak = 0
        }
        if pb.onGround || swimming { fallPeak = 0 }
        _ = peak
        walkAnim += abs(pb.vx) * dt * 0.55
        lastVy = pb.vy
        checkHazards(dt)
        updateSurvival(dt, ix)
    }

    func checkHazards(_ dt: Double) {
        if mode == .creative || godMode { return }
        // spikes underfoot, cactus touched from the side (cactus is solid, so test a slightly wider box)
        if let t = world.boxHurts(pb.left + 0.05, pb.top + 0.1, pb.right - 0.05, pb.y - 0.02) ?? world.boxHurts(pb.left - 0.04, pb.top + 0.2, pb.right + 0.04, pb.y - 0.1) {
            if t == .spikes || t == .cactus {
                var info = DamageInfo(amount: t == .spikes ? 6 : 3, type: .hazard, source: .environment)
                info.originX = pb.x + Double(-facing)
                info.knock = 5
                _ = hurtPlayer(info)
            }
        }
        if world.tile(Int(floor(pb.x)), Int(floor(pb.y - 0.5))) == .campfire { playerBurn = max(playerBurn, 1.2) }
        if pb.inLava {
            playerBurn = max(playerBurn, 2.5)
            lavaT += dt
            if lavaT > 0.35 {
                lavaT = 0
                var info = DamageInfo(amount: 5, type: .lava, source: .environment)
                info.originX = pb.x
                _ = hurtPlayer(info)
            }
        } else {
            lavaT = 0
        }
        updatePlayerBurn(dt)
    }

    func updateSurvival(_ dt: Double, _ ix: Double) {
        if mode == .creative { return }
        // air
        let headY: Int = Int(floor(pb.y - pb.h * 0.92))
        if world.tile(Int(floor(pb.x)), headY) == .water {
            air -= dt
            if air <= 0 {
                air = 0
                drownT += dt
                if drownT >= 1.0 {
                    drownT = 0
                    damagePlayer(2, from: pb.x, knock: 0, ignoreArmor: true)
                }
            }
        } else {
            air = min(10.0, air + dt * 5.0)
            drownT = 0
        }
        // hunger
        let rate: Double = (ix != 0 ? 0.030 : 0.016) * (pb.inWater ? 1.3 : 1.0)
        hunger = max(0, hunger - rate * dt)
        if hunger <= 0 {
            starveT += dt
            if starveT >= 3.0 {
                starveT = 0
                if hp > 1 || mode == .hardcore { damagePlayer(1, from: pb.x, knock: 0, ignoreArmor: true) }
            }
        } else {
            starveT = 0
        }
        if hunger >= 14 && hp < maxHP {
            regenT += dt
            let period: Double = hunger >= 18 ? 0.9 : 1.6
            if regenT >= period {
                regenT = 0
                hp = min(maxHP, hp + 1)
                hunger = max(0, hunger - 0.12)
                bumpHUD()
            }
        } else {
            regenT = 0
        }
    }

    func damagePlayer(_ dmg: Double, from sx: Double, knock: Double = 6, ignoreArmor: Bool = false) {
        if dead || godMode || mode == .creative { return }
        if invuln > 0 && !ignoreArmor { return }
        var d: Double = dmg
        if !ignoreArmor { d *= (1.0 - min(0.75, inv.defense * 0.045)) }
        d = max(1.0, d.rounded())
        hp -= d
        invuln = 0.55
        hurtT = 0.35
        if knock > 0 {
            let dirk: Double = pb.x >= sx ? 1.0 : -1.0
            pb.vx = dirk * knock
            pb.vy = -6.0
        }
        floatText("-" + String(Int(d)), pb.x, pb.y - pb.h - 0.3, 0xFF5050)
        shake = max(shake, 0.2)
        bumpHUD()
        if hp <= 0 { die() }
    }

    func heal(_ amount: Double) {
        hp = min(maxHP, hp + amount)
        bumpHUD()
    }

    func die() {
        if dead { return }
        dead = true
        hp = 0
        deathT = 0
        mounted = nil
        if let v = inVehicle { v.rider = false }
        inVehicle = nil
        spawnParticles(pb.x, pb.y - 1, 0xC03030, 24, 6.0, 0.9, 16)
        say(mode == .hardcore ? "You died. Your hardcore world is lost." : "You died!", 5.0)
        if mode == .hardcore { hardcoreOver = true }
        bumpHUD()
    }

    func respawn() {
        if mode == .hardcore && hardcoreOver { return }
        if world.dim != .overworld { travelTo(.overworld, arriveX: spawnX, arriveY: spawnY, silent: true) }
        dead = false
        hp = maxHP
        hunger = max(hunger, 14)
        air = 10
        pb.x = spawnX
        pb.y = spawnY
        pb.vx = 0
        pb.vy = 0
        invuln = 3.0
        fallPeak = 0
        world.loadAround(centerX: Int(spawnX), radius: 3)
        let sy: Int = world.surfaceY(Int(spawnX))
        pb.y = Double(sy)
        camX = pb.x
        camY = pb.y - 2
        say("Respawned.", 2.0)
        bumpHUD()
    }

    // MARK: camera, streaming, light

    /// Camera follow: a dead zone around the player, optional look-ahead in the direction of travel
    /// (eased so turning around does not jerk the view), and frame-rate independent exponential smoothing.
    func updateCamera(_ dt: Double) {
        let st: Settings = settings
        // look ahead: further when driving fast, eased in and out
        var leadTarget: Double = 0
        if st.camLookAhead {
            if let v = inVehicle {
                leadTarget = clampD(v.vx * 0.35, -6.0, 6.0)
            } else if abs(pb.vx) > 1.0 {
                leadTarget = Double(facing) * 1.6
            }
        }
        camLead += (leadTarget - camLead) * min(1.0, dt * 2.5)
        let fx: Double = pb.x + camLead
        let fy: Double = pb.y - 1.6
        // the target only moves once the player leaves the dead zone around it
        let dz: Double = clampD(st.camDeadZone, 0, 4)
        if fx > camTX + dz { camTX = fx - dz } else if fx < camTX - dz { camTX = fx + dz }
        let dzy: Double = dz * 0.75
        if fy > camTY + dzy { camTY = fy - dzy } else if fy < camTY - dzy { camTY = fy + dzy }
        if abs(camTX - camX) > 40 || abs(camTY - camY) > 40 || !st.camSmoothOn {
            // teleports, respawns and "smoothing off" snap straight to the target
            camX = camTX
            camY = camTY
        } else {
            let rate: Double = 2.5 + clampD(st.camFollow, 0, 1) * 11.5
            let k: Double = 1.0 - exp(-rate * dt)
            camX += (camTX - camX) * k
            camY += (camTY - camY) * k
        }
        let halfW: Double = viewTilesW * 0.5
        let halfH: Double = viewTilesH * 0.5
        if !gen.infinite {
            if viewTilesW < Double(gen.width) { camX = clampD(camX, halfW, Double(gen.width) - halfW) }
        }
        let Hh: Double = Double(world.H)
        camY = clampD(camY, halfH - 14.0, Hh - halfH + 1.0)
    }

    func updateStreaming() {
        let need: Int = Int(ceil(viewTilesW * 0.5 / Double(chunkW))) + 2
        loadRadius = need
        var keep: Set<Int> = []
        for m in mobs where m.persistent || m.isBoss || m.tame {
            keep.insert(floorDiv(Int(floor(m.b.x)), chunkW))
        }
        for v in vehicles { keep.insert(floorDiv(Int(floor(v.b.x)), chunkW)) }
        let cx: Int = Int(floor(camX))
        let n: Int = world.stream(centerX: cx, radius: loadRadius, hysteresis: 3, budget: 1, keep: keep)
        chunksLoadedLast = n
        // keep the player's own chunk always available
        let pc: Int = floorDiv(Int(floor(pb.x)), chunkW)
        if world.chunks[pc] == nil { world.loadChunk(pc) }
    }

    func heldLightLevel() -> Int {
        if let it = heldItem, case .block(let t) = it {
            let l: Int = t.light
            if l >= 9 { return l - 2 }
        }
        return 0
    }

    func updateLight(_ dt: Double) {
        lightTimer -= dt
        // dynamic lights
        var dyn: [(Int, Int, Int)] = []
        let pcx: Int = Int(floor(pb.x))
        let pcy: Int = Int(floor(pb.y - pb.h * 0.6))
        var hl: Int = heldLightLevel()
        hl = max(hl, 5)
        dyn.append((pcx, pcy, hl))
        for m in mobs {
            var lv: Int = 0
            switch m.kind {
            case .emberSlime: lv = 9
            case .imp: lv = 8
            case .wraith: lv = 6
            case .cinderBat: lv = 6
            case .bearBoss, .rex: lv = m.isBoss ? 6 : 0
            default: lv = 0
            }
            if m.burn > 0 { lv = max(lv, 6) }
            if lv > 0 { dyn.append((Int(floor(m.b.x)), Int(floor(m.b.y - m.b.h * 0.5)), lv)) }
        }
        for p in projectiles where p.kind == .fireball {
            dyn.append((Int(floor(p.x)), Int(floor(p.y)), 10))
        }
        for s in ships {
            dyn.append((Int(floor(s.x)) - 3, Int(floor(s.deckY(Double(WorldGen.sea)))) - 2, 10))
            dyn.append((Int(floor(s.x)) + 3, Int(floor(s.deckY(Double(WorldGen.sea)))) - 2, 10))
        }
        for v in vehicles where v.rider && v.engines > 0 && v.fuel > 0 {
            dyn.append((Int(floor(v.b.x + Double(v.dir) * (v.b.w * 0.5 + 1.0))), Int(floor(v.b.y - v.b.h * 0.5)), 10))
        }
        var key: Int = dyn.count
        for d in dyn { key = key &* 31 &+ d.0 &* 7 &+ d.1 &* 13 &+ d.2 }
        // window
        let vw: Int = Int(ceil(viewTilesW)) + 2
        let vh: Int = Int(ceil(viewTilesH)) + 2
        let vx0: Int = Int(floor(camX - viewTilesW * 0.5)) - 1
        let vy0: Int = Int(floor(camY - viewTilesH * 0.5)) - 1
        let covered: Bool = light.covers(vx0 - 3, vy0 - 3, vx0 + vw + 3, vy0 + vh + 3)
        // only edits that touch the light window matter (crops growing far away do not)
        var edited: Bool = false
        if world.editAny {
            let ex0: Int = light.ox - 1
            let ex1: Int = light.ox + light.w
            let ey0: Int = light.oy - 1
            let ey1: Int = light.oy + light.h
            if world.editX1 >= ex0 && world.editX0 <= ex1 && world.editY1 >= ey0 && world.editY0 <= ey1 {
                edited = true
            } else {
                world.editAny = false
            }
        }
        let layoutChanged: Bool = light.layoutUsed != world.layoutVersion
        let needsStatic: Bool = !light.valid || !covered || light.skyUsed != skyLevel || light.dimUsed != world.dim.rawValue || edited || layoutChanged
        let amb: Double = fullBright ? 1.0 : (world.dim == .umbral ? 0.2 : 0.07)
        if !needsStatic {
            // only moving lights changed: cheap partial relight
            if light.dynUsed == key { return }
            let t0: Double = perfNow()
            light.applyDynamic(dyn)
            light.dynUsed = key
            light.buildPixels(&lightDark, &lightGlow, amb, 1.0 - dayFactor)
            lightRev &+= 1
            Perf.shared.lightDyn += 1
            Perf.shared.lightMs = Perf.smooth(Perf.shared.lightMs, perfNow() - t0)
            return
        }
        if lightTimer > 0 && light.valid && covered && light.dimUsed == world.dim.rawValue { return }
        let t0: Double = perfNow()
        lightTimer = 0.04
        let m: Int = 17
        var ox: Int = vx0 - m
        ox = floorDiv(ox, 4) * 4
        var oy: Int = vy0 - m
        oy = floorDiv(oy, 4) * 4
        var w: Int = (vx0 + vw + m) - ox + 4
        w = (w / 4 + 1) * 4
        var h: Int = (vy0 + vh + m) - oy + 4
        h = (h / 4 + 1) * 4
        light.compute(world, ox, oy, w, h, skyLevel, dyn)
        light.dynUsed = key
        light.buildPixels(&lightDark, &lightGlow, amb, 1.0 - dayFactor)
        lightRev &+= 1
        Perf.shared.lightMs = Perf.smooth(Perf.shared.lightMs, perfNow() - t0)
    }

    // MARK: random world ticks (crops, grass)

    func updateWorldTicks(_ dt: Double) {
        let n: Int = 7
        let px: Int = Int(floor(pb.x))
        let py: Int = Int(floor(pb.y))
        for _ in 0..<n {
            let x: Int = px + Int.random(in: -40...40)
            let y: Int = py + Int.random(in: -26...26)
            let t: Tile = world.tile(x, y)
            switch t {
            case .wheat1: if Double.random(in: 0...1) < 0.35 { world.set(x, y, .wheat2) }
            case .wheat2: if Double.random(in: 0...1) < 0.35 { world.set(x, y, .wheat3) }
            case .carrot1: if Double.random(in: 0...1) < 0.35 { world.set(x, y, .carrot2) }
            case .carrot2: if Double.random(in: 0...1) < 0.35 { world.set(x, y, .carrot3) }
            case .dirt:
                if world.dim == .overworld && y < world.skyTop(x) + 1 && world.tile(x, y - 1) == .air {
                    let a: Tile = world.tile(x - 1, y)
                    let b: Tile = world.tile(x + 1, y)
                    if a == .grass || b == .grass { if Double.random(in: 0...1) < 0.2 { world.set(x, y, .grass) } }
                }
            case .grass:
                if world.tile(x, y - 1).opaque && Double.random(in: 0...1) < 0.3 { world.set(x, y, .dirt) }
            default: break
            }
        }
        updateLeafDecay(dt)
        // lantern/torch/crop support is checked when neighbours change (see breakTile)
    }
}

// ===== p14c_input =====

// MARK: - Pointer input, interaction, inventory operations, crafting

extension Game {
    // MARK: pointer (world coordinates in tiles)

    func pointerDown(_ wx: Double, _ wy: Double) {
        aimX = wx
        aimY = wy
        aimValid = true
        downTime = 0
        usePressedFlag = false
        if isInteractive(wx, wy) {
            pendingInteract = true
            useHeld = false
        } else {
            pendingInteract = false
            useHeld = true
            useWasHeld = false
        }
        pointerStartX = wx
        pointerStartY = wy
    }

    func pointerMove(_ wx: Double, _ wy: Double) {
        aimX = wx
        aimY = wy
        aimValid = true
        if pendingInteract {
            let dx: Double = wx - pointerStartX
            let dy: Double = wy - pointerStartY
            if dx * dx + dy * dy > 0.5 {
                pendingInteract = false
                useHeld = true
            }
        }
    }

    func pointerUp() {
        if pendingInteract {
            if downTime < 0.3 { interact(aimX, aimY) }
            pendingInteract = false
        }
        if useHeld { useReleasedFlag = true }
        useHeld = false
        useWasHeld = false
    }

    func updatePointerTimers(_ dt: Double) {
        if pendingInteract {
            downTime += dt
            if downTime >= 0.3 {
                pendingInteract = false
                useHeld = true
                useWasHeld = false
            }
        }
    }

    func reachDistance() -> Double {
        if infiniteReach { return 60 }
        return isCreative ? 8.0 : 5.5
    }

    func inReach(_ x: Double, _ y: Double) -> Bool {
        let dx: Double = x - pb.x
        let dy: Double = y - (pb.y - pb.h * 0.6)
        let r: Double = reachDistance()
        return dx * dx + dy * dy <= r * r
    }

    // MARK: interactive targets

    func mobAtPoint(_ wx: Double, _ wy: Double, _ pad: Double) -> Mob? {
        var best: Mob? = nil
        var bd: Double = 1e9
        for m in mobs {
            if m.hp <= 0 { continue }
            let x0: Double = m.b.left - pad
            let x1: Double = m.b.right + pad
            let y0: Double = m.b.top - pad
            let y1: Double = m.b.y + pad
            if wx >= x0 && wx <= x1 && wy >= y0 && wy <= y1 {
                let d: Double = abs(wx - m.b.x) + abs(wy - m.b.cy)
                if d < bd { bd = d; best = m }
            }
        }
        return best
    }

    func vehicleAtPoint(_ wx: Double, _ wy: Double) -> (Vehicle, PartCell)? {
        for v in vehicles {
            if wx < v.b.left - 0.2 || wx > v.b.right + 0.2 || wy < v.b.top - 0.2 || wy > v.b.y + 0.2 { continue }
            // pick in the vehicle's own (rotated) grid
            let c: PartCell = v.cellAt(wx, wy)
            if v.parts[c] != nil { return (v, c) }
        }
        return nil
    }

    func shipChestAt(_ wx: Double, _ wy: Double) -> PirateShip? {
        for s in ships {
            if s.looted { continue }
            let dy: Double = s.deckY(Double(WorldGen.sea))
            if abs(wx - (s.x - 2.5)) < 1.2 && abs(wy - (dy - 0.6)) < 1.4 { return s }
        }
        return nil
    }

    func isInteractive(_ wx: Double, _ wy: Double) -> Bool {
        let tx: Int = Int(floor(wx))
        let ty: Int = Int(floor(wy))
        let t: Tile = world.tile(tx, ty)
        switch t {
        case .chest, .workbench, .furnace, .campfire, .portalOff, .doorClosed, .doorOpen: return true
        default: break
        }
        if let m = mobAtPoint(wx, wy, 0.15) {
            if m.kind == .villager || m.tame || (m.kind == .rex && m.tame) { return true }
        }
        if vehicleAtPoint(wx, wy) != nil {
            if let it = heldItem, case .part = it { return false }
            if let it = heldItem, case .gadget(let g) = it, g == .wrench { return false }
            return true
        }
        if shipChestAt(wx, wy) != nil { return true }
        return false
    }

    func interact(_ wx: Double, _ wy: Double) {
        let tx: Int = Int(floor(wx))
        let ty: Int = Int(floor(wy))
        if !inReach(wx, wy) && !(mobAtPoint(wx, wy, 0.2)?.tame ?? false) {
            say("Too far away.", 1.2)
            return
        }
        let t: Tile = world.tile(tx, ty)
        switch t {
        case .chest:
            openChest = IntPair(x: tx, y: ty)
            showInventory = true
            bumpHUD()
            return
        case .workbench:
            craftStation = .bench
            showInventory = true
            bumpHUD()
            return
        case .furnace:
            craftStation = .furnace
            showInventory = true
            bumpHUD()
            return
        case .campfire:
            craftStation = .campfire
            showInventory = true
            bumpHUD()
            return
        case .portalOff:
            tryOpenPortal(tx, ty)
            return
        case .doorClosed, .doorOpen:
            toggleDoor(tx, ty)
            return
        default: break
        }
        if let m = mobAtPoint(wx, wy, 0.2) {
            interactMob(m)
            return
        }
        if let (v, c) = vehicleAtPoint(wx, wy) {
            interactVehicle(v, c)
            return
        }
        if let s = shipChestAt(wx, wy) {
            lootShip(s)
            return
        }
    }

    func interactMob(_ m: Mob) {
        switch m.kind {
        case .villager:
            let lines: [String] = [
                "Beware the bear in the east. They say it guards a gate.",
                "Skeletons walk the caves below. Bring plenty of light.",
                "Pirates have been raiding the coast lately.",
                "A hidden portal lies far beneath the earth. A key opens it.",
                "Crops grow best on tilled soil. Use a hoe!",
                "Need a weapon? Copper and iron tools are cheap to forge."
            ]
            say("Villager: " + lines[Int.random(in: 0..<lines.count)], 4.0)
        case .rex:
            if m.tame { mountRex(m) }
        case .wolf, .cat:
            if m.tame {
                m.st = m.st == 7 ? 0 : 7
                say(m.st == 7 ? "Your pet will stay here." : "Your pet follows you.", 2.0)
            }
        default: break
        }
    }

    func tryOpenPortal(_ tx: Int, _ ty: Int) {
        let key: Item = .gadget(.portalKey)
        if !isCreative && inv.total(key) < 1 {
            say("The portal is sealed. It needs a Portal Key.", 3.0)
            return
        }
        if !isCreative { _ = inv.remove(key, 1) }
        // flood fill all dormant portal tiles
        var stack: [IntPair] = [IntPair(x: tx, y: ty)]
        var count: Int = 0
        while let p = stack.popLast() {
            if world.tile(p.x, p.y) != .portalOff { continue }
            world.set(p.x, p.y, .portalOn)
            count += 1
            if count > 80 { break }
            stack.append(IntPair(x: p.x + 1, y: p.y))
            stack.append(IntPair(x: p.x - 1, y: p.y))
            stack.append(IntPair(x: p.x, y: p.y + 1))
            stack.append(IntPair(x: p.x, y: p.y - 1))
        }
        portalOpened = true
        spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, 0xB070FF, 40, 7.0, 1.2, 0)
        shake = 0.5
        say("The portal awakens! Step inside to enter the Umbral Realm.", 5.0)
        bumpHUD()
    }

    func lootShip(_ s: PirateShip) {
        if !s.crew.isEmpty {
            var alive: Bool = false
            for id in s.crew { for m in mobs { if m.id == id && m.hp > 0 { alive = true } } }
            if alive {
                say("Defeat the crew first!", 2.0)
                return
            }
        }
        s.looted = true
        var rng = RNG(UInt64(truncatingIfNeeded: s.id) &* 7919 &+ gen.seed)
        giveItem(.mat(.goldBar), 3 + rng.int(6))
        giveItem(.ammo(.bullet), 8 + rng.int(14))
        giveItem(.mat(.gunpowder), 2 + rng.int(5))
        if rng.double() < 0.35 { giveItem(.gun(.pistol), 1) }
        if rng.double() < 0.5 { giveItem(.mat(.diamond), 1 + rng.int(3)) }
        giveItem(.food(.cookedFish), 2 + rng.int(4))
        say("You looted the pirate treasure!", 3.0)
        spawnParticles(s.x - 2.5, s.deckY(Double(WorldGen.sea)) - 1, 0xF5D142, 20, 5.0, 0.9, 12)
    }

    // MARK: inventory operations (used by the UI)

    func tapSlot(_ i: Int) {
        if let h = carry {
            // place carried stack
            if let s = inv.slots[i] {
                if s.item == h.item && h.item.maxStack > 1 {
                    let room: Int = h.item.maxStack - s.count
                    let put: Int = min(room, h.count)
                    var ns: Stack = s
                    ns.count += put
                    inv.slots[i] = ns
                    if h.count - put > 0 {
                        var c: Stack = h
                        c.count = h.count - put
                        carry = c
                    } else {
                        carry = nil
                    }
                } else {
                    inv.slots[i] = h
                    carry = s
                }
            } else {
                inv.slots[i] = h
                carry = nil
            }
        } else if let s = inv.slots[i] {
            carry = s
            inv.slots[i] = nil
        }
        bumpHUD()
    }

    func splitSlot(_ i: Int) {
        if carry != nil { return }
        if let s = inv.slots[i], s.count > 1 {
            let half: Int = s.count / 2
            var a: Stack = s
            a.count = s.count - half
            var b: Stack = s
            b.count = half
            inv.slots[i] = a
            carry = b
            bumpHUD()
        }
    }

    func dropCarried() {
        if let c = carry {
            spawnDrop(c, pb.x + Double(facing) * 0.8, pb.y - 1.2, Double(facing) * 4.0, -4.0)
            carry = nil
            bumpHUD()
        }
    }

    func returnCarried() {
        if let c = carry {
            let left: Int = inv.add(c.item, c.count, extra: c.extra)
            if left > 0 { spawnDrop(Stack(item: c.item, count: left, extra: c.extra), pb.x, pb.y - 1.0, 2.0, -3.0) }
            carry = nil
            bumpHUD()
        }
    }

    func tapArmorSlot(_ i: Int) {
        if let h = carry {
            if case .armor(let slot, _) = h.item, slot.rawValue == i {
                let old: Stack? = inv.armor[i]
                inv.armor[i] = h
                carry = old
            }
        } else if let s = inv.armor[i] {
            carry = s
            inv.armor[i] = nil
        }
        bumpHUD()
    }

    func quickEquip(_ i: Int) {
        if let s = inv.slots[i], case .armor(let slot, _) = s.item {
            let old: Stack? = inv.armor[slot.rawValue]
            inv.armor[slot.rawValue] = s
            inv.slots[i] = old
            bumpHUD()
        }
    }

    // chest transfer
    func chestTapSlot(_ cx: Int, _ cy: Int, _ idx: Int) {
        var items: [Stack] = world.chestItems(cx, cy)
        if let h = carry {
            if idx < items.count {
                let s: Stack = items[idx]
                if s.item == h.item && h.item.maxStack > 1 {
                    var ns: Stack = s
                    let put: Int = min(h.item.maxStack - s.count, h.count)
                    ns.count += put
                    items[idx] = ns
                    if h.count - put > 0 { var c: Stack = h; c.count = h.count - put; carry = c } else { carry = nil }
                } else {
                    items[idx] = h
                    carry = s
                }
            } else if items.count < 27 {
                items.append(h)
                carry = nil
            }
        } else if idx < items.count {
            carry = items[idx]
            items.remove(at: idx)
        }
        world.setChestItems(cx, cy, items)
        bumpHUD()
    }

    func chestQuickMove(_ cx: Int, _ cy: Int, _ idx: Int) {
        var items: [Stack] = world.chestItems(cx, cy)
        if idx >= items.count { return }
        let s: Stack = items[idx]
        let left: Int = inv.add(s.item, s.count, extra: s.extra)
        if left == 0 { items.remove(at: idx) } else { items[idx].count = left }
        world.setChestItems(cx, cy, items)
        bumpHUD()
    }

    func chestStore(_ cx: Int, _ cy: Int, _ slotIndex: Int) {
        guard let s = inv.slots[slotIndex] else { return }
        var items: [Stack] = world.chestItems(cx, cy)
        if items.count >= 27 { say("Chest is full.", 1.5); return }
        items.append(s)
        inv.slots[slotIndex] = nil
        world.setChestItems(cx, cy, items)
        bumpHUD()
    }

    // MARK: crafting

    func stationAvailable(_ s: Station) -> Bool {
        if s == .hand { return true }
        if isCreative { return true }
        let px: Int = Int(floor(pb.x))
        let py: Int = Int(floor(pb.y - 1))
        for dy in -4...3 {
            for dx in -5...5 {
                let t: Tile = world.tile(px + dx, py + dy)
                switch s {
                case .bench: if t == .workbench { return true }
                case .furnace: if t == .furnace { return true }
                case .campfire: if t == .furnace || t == .campfire { return true }
                default: break
                }
            }
        }
        return false
    }

    func canCraft(_ r: Recipe) -> Bool {
        if !stationAvailable(r.station) { return false }
        if !inv.canAfford(r.cost) { return false }
        return inv.canFit(r.out, r.outCount)
    }

    func craft(_ r: Recipe) {
        if !canCraft(r) {
            if !stationAvailable(r.station) { say("Needs a " + r.station.name + " nearby.", 2.0) }
            return
        }
        for c in r.cost { _ = inv.remove(c.item, c.n) }
        let left: Int = inv.add(r.out, r.outCount)
        if left > 0 { spawnDrop(Stack(item: r.out, count: left), pb.x, pb.y - 1, 2, -3) }
        floatText("+" + String(r.outCount) + " " + r.out.name, pb.x, pb.y - 2.2, 0xFFE070)
        bumpHUD()
    }

    // MARK: creative palette

    func creativeItems() -> [Item] {
        var out: [Item] = []
        for t in Tile.allCases {
            switch t {
            case .air, .water, .lava, .bedrock, .portalFrame, .portalOff, .portalOn, .wheat1, .wheat2, .carrot1, .carrot2, .doorOpen: continue
            default: out.append(.block(t))
            }
        }
        for tier in Tier.allCases {
            for k in ToolType.allCases { out.append(.tool(k, tier)) }
            out.append(.sword(tier))
            for s in ArmorSlot.allCases { out.append(.armor(s, tier)) }
        }
        out.append(.bow)
        out.append(.gun(.pistol))
        out.append(.gun(.rifle))
        out.append(.ammo(.arrow))
        out.append(.ammo(.bullet))
        for g in Gadget.allCases { out.append(.gadget(g)) }
        for k in wallKinds { out.append(.wall(k)) }
        for p in PartType.allCases { out.append(.part(p)) }
        for f in Food.allCases { out.append(.food(f)) }
        for m in Mat.allCases { out.append(.mat(m)) }
        return out
    }

    func creativeGive(_ it: Item) {
        let n: Int = it.maxStack > 1 ? it.maxStack : 1
        giveItem(it, n, extra: gunLoad(it))
        bumpHUD()
    }

    func gunLoad(_ it: Item) -> Int {
        if case .gun(let g) = it { return g.magazine }
        return 0
    }
}

// ===== p14d_tools =====

// MARK: - Item use: mining, placing, melee, ranged weapons, eating, farming

func toolClass(_ t: Tile) -> ToolType {
    switch t {
    case .log, .jungleLog, .palmLog, .planks, .workbench, .chest, .platform, .leaves, .jungleLeaves, .cactus, .hay, .reed, .lantern, .torch:
        return .axe
    case .dirt, .grass, .sand, .snow, .mud, .dryGrass, .jungleGrass, .mossGrass, .farmland:
        return .shovel
    default:
        return .pickaxe
    }
}

func isLogTile(_ t: Tile) -> Bool {
    return t == .log || t == .jungleLog || t == .palmLog
}

struct DecayZone {
    var x: Int
    var y: Int
    var t: Double
}

extension Game {
    /// Any trunk tile within r tiles (keeps a tree's canopy alive)
    func logNear(_ x: Int, _ y: Int, _ r: Int) -> Bool {
        for dy in -r...r {
            for dx in -r...r where isLogTile(world.tile(x + dx, y + dy)) { return true }
        }
        return false
    }

    /// Where a trunk was cut, leaves that no longer have a trunk nearby wither over the next half
    /// minute. Only around cut trees, so leafy ruin decorations are left alone.
    func updateLeafDecay(_ dt: Double) {
        if decayZones.isEmpty { return }
        var keep: [DecayZone] = []
        for z0 in decayZones {
            var z: DecayZone = z0
            z.t -= dt
            for _ in 0..<4 {
                let x: Int = z.x + Int.random(in: -7...7)
                let y: Int = z.y + Int.random(in: -10...4)
                let t: Tile = world.tile(x, y)
                if (t == .leaves || t == .jungleLeaves) && !logNear(x, y, 4) { breakTile(x, y, false) }
            }
            if z.t > 0 { keep.append(z) }
        }
        decayZones = keep
    }
}

extension Game {
    func updateUse(_ dt: Double) {
        if useCD > 0 { useCD -= dt }
        if swingT > 0 { swingT -= dt }
        if muzzleT > 0 { muzzleT -= dt }
        if bowRecoil > 0 { bowRecoil -= dt }
        if eatT > 0 { eatT -= dt }
        if placeCD > 0 { placeCD -= dt }
        if dead || inVehicle != nil {
            mining = false
            usePressedFlag = false
            useReleasedFlag = false
            return
        }
        updateReload(dt)
        let pressed: Bool = usePressedFlag
        usePressedFlag = false
        let released: Bool = useReleasedFlag
        useReleasedFlag = false
        if !aimValid { return }
        let held: Item? = heldItem
        if !useHeld {
            mining = false
            mineP = max(0, mineP - dt * 2.0)
        }
        // bow release logic works on edges
        if case .bow? = held {
            handleBow(dt, pressed, released)
            return
        } else if bowCharge > 0 {
            bowCharge = 0
        }
        if !useHeld { return }
        guard let it = held else {
            useBareHand(dt)
            return
        }
        switch it {
        case .block(let t): usePlaceBlock(t, dt)
        case .tool(let k, let tr): useToolItem(k, tr, dt)
        case .sword: useSword(it)
        case .gun(let g): useGun(g, pressed)
        case .food(let f): useFood(f, pressed)
        case .mat(let m):
            if m == .seeds { usePlant(.wheat1, it, pressed) }
        case .part(let p): usePart(p, pressed)
        case .gadget(let g): useGadget(g, pressed)
        case .wall(let k): usePlaceWall(k)
        case .armor:
            if pressed { quickEquip(sel); say("Equipped.", 1.0) }
        default: break
        }
    }

    // MARK: bare hands & tools

    func useBareHand(_ dt: Double) {
        if let m = targetMob() {
            meleeHit(nil, m)
            return
        }
        let tx: Int = Int(floor(aimX))
        let ty: Int = Int(floor(aimY))
        mineStep(tx, ty, nil, nil, dt)
    }

    func useToolItem(_ k: ToolType, _ tr: Tier, _ dt: Double) {
        let it: Item = .tool(k, tr)
        let tx: Int = Int(floor(aimX))
        let ty: Int = Int(floor(aimY))
        if let m = targetMob() {
            meleeHit(it, m)
            return
        }
        if k == .hoe {
            if useCD <= 0 {
                let t: Tile = world.tile(tx, ty)
                if (t == .grass || t == .dirt || t == .dryGrass || t == .mossGrass) && inReach(Double(tx) + 0.5, Double(ty) + 0.5) && !world.tile(tx, ty - 1).solid {
                    world.set(tx, ty, .farmland)
                    // plants on top of the tilled tile are removed
                    if world.tile(tx, ty - 1).isPlant { world.set(tx, ty - 1, .air) }
                    useCD = 0.25
                    swingT = 0.2
                    swingDir = facing
                    spawnParticles(Double(tx) + 0.5, Double(ty), 0x6B4626, 6, 2.5, 0.4, 12)
                    return
                }
            }
        }
        mineStep(tx, ty, k, tr, dt)
    }

    func useSword(_ it: Item) {
        if let m = targetMob() {
            meleeHit(it, m)
        } else if useCD <= 0 {
            swingEmpty(it)
        }
    }

    func swingEmpty(_ it: Item?) {
        let cd: Double = it?.meleeCooldown ?? 0.4
        useCD = cd
        swingT = swingDur
        swingDir = facing
        // wide arc may still catch mobs close to the player
        let reach: Double = it?.meleeReach ?? 1.8
        let dmg: Double = it?.meleeDamage ?? 1.5
        meleeArc(dmg, reach, it)
    }

    func targetMob() -> Mob? {
        if let m = mobAtPoint(aimX, aimY, 0.35) {
            if m.tame || m.kind == .villager { return nil }
            if inReach(m.b.x, m.b.cy) { return m }
        }
        return nil
    }

    func meleeHit(_ it: Item?, _ target: Mob) {
        if useCD > 0 { return }
        let cd: Double = it?.meleeCooldown ?? 0.4
        useCD = cd
        swingT = swingDur
        swingDir = aimX >= pb.x ? 1 : -1
        facing = swingDir
        let reach: Double = (it?.meleeReach ?? 1.8) + 0.8
        let dmg: Double = it?.meleeDamage ?? 1.5
        meleeArc(dmg, reach, it)
        _ = target
    }

    /// damage every hostile/neutral mob inside the arc in front of the player
    func meleeArc(_ dmg: Double, _ reach: Double, _ it: Item?) {
        let ox: Double = pb.x
        let oy: Double = pb.y - pb.h * 0.55
        var hitAny: Bool = false
        let swingKey: Int = newID()
        for m in mobsNear(ox - reach - 4, ox + reach + 4) {
            if m.hp <= 0 || m.tame || m.kind == .villager { continue }
            let dx: Double = m.b.x - ox
            let dy: Double = m.b.cy - oy
            // front only
            if dx * Double(swingDir) < -0.4 - m.b.w * 0.5 { continue }
            let ex: Double = abs(dx) - m.b.w * 0.5
            let ey: Double = abs(dy) - m.b.h * 0.5
            if ex > reach || ey > 1.2 { continue }
            var d: Double = dmg
            if Double.random(in: 0...1) < 0.1 { d *= 1.5 }
            var info = DamageInfo(amount: d, type: .melee, source: .player)
            info.dirX = Double(swingDir)
            info.knock = 6.0
            info.originX = ox
            info.key = swingKey
            info.cooldown = 0.3
            if applyMobDamage(m, info) { hitAny = true }
        }
        // pirate ships
        for s in ships {
            let dx: Double = abs(s.x - ox)
            let dy: Double = abs(s.deckY(Double(WorldGen.sea)) - pb.y)
            if dx < 5.0 + reach * 0.3 && dy < 3.5 {
                s.hp -= dmg * 0.6
                s.hitT = 0.2
                hitAny = true
            }
        }
        if hitAny { addShake(0.08) }
    }

    // MARK: mining & breaking

    func mineStep(_ tx: Int, _ ty: Int, _ kind: ToolType?, _ tier: Tier?, _ dt: Double) {
        let t: Tile = world.tile(tx, ty)
        if t == .air && mineWall(tx, ty, kind, tier, dt) { return }
        if t == .air || t.liquid {
            mining = false
            mineP = 0
            if useCD <= 0 && kind != nil && kind != .hoe {
                swingT = 0.2
                swingDir = aimX >= pb.x ? 1 : -1
                facing = swingDir
                useCD = 0.3
            }
            return
        }
        let def: TileDef = t.def
        if def.hard >= 9999 {
            if useCD <= 0 { say("That can't be broken.", 1.2); useCD = 0.6 }
            return
        }
        if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) {
            mining = false
            mineP = 0
            return
        }
        let cls: ToolType = toolClass(t)
        if def.tier > 0 && !isCreative {
            let pt: Int = (kind == .pickaxe) ? (tier?.rawValue ?? 0) : 0
            if pt < def.tier {
                mining = false
                if useCD <= 0 {
                    say(kind == .pickaxe ? "This needs a stronger pickaxe." : "You need a pickaxe for that.", 1.5)
                    useCD = 0.8
                    swingT = 0.2
                    swingDir = aimX >= pb.x ? 1 : -1
                }
                return
            }
        }
        if mineX != tx || mineY != ty || !mining {
            if mineX != tx || mineY != ty { mineP = 0 }
            mineX = tx
            mineY = ty
        }
        mining = true
        var speed: Double = 1.0
        if let k = kind, let tr = tier { speed = tr.mineSpeed * (k == cls ? 1.0 : 0.35) }
        if isCreative { speed = 1000 }
        mineNeed = max(0.05, def.hard * 1.5)
        mineP += dt * speed
        if useCD <= 0 {
            swingT = 0.22
            swingDir = aimX >= pb.x ? 1 : -1
            facing = swingDir
            useCD = 0.26
            let col: UInt32 = def.colors.first ?? 0x888888
            spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, col, 3, 3.0, 0.4, 14)
        }
        if mineP >= mineNeed {
            mineP = 0
            mining = false
            let fell: Bool = isLogTile(t) && kind == .axe
            if fell { fellTree(tx, ty) } else { breakTile(tx, ty, true) }
        }
    }

    func tileDropStacks(_ t: Tile, _ x: Int, _ y: Int) -> [Stack] {
        var out: [Stack] = []
        let r: Double = Double.random(in: 0...1)
        switch t {
        case .tallGrass:
            if r < 0.14 { out.append(Stack(item: .mat(.seeds), count: 1)) }
        case .leaves, .jungleLeaves:
            if r < 0.05 { out.append(Stack(item: .food(.apple), count: 1)) }
        case .wheat3:
            out.append(Stack(item: .food(.wheat), count: 1 + Int.random(in: 0...1)))
            out.append(Stack(item: .mat(.seeds), count: 1 + Int.random(in: 0...2)))
        case .wheat1, .wheat2:
            out.append(Stack(item: .mat(.seeds), count: 1))
        case .carrot3:
            out.append(Stack(item: .food(.carrot), count: 1 + Int.random(in: 0...2)))
        case .carrot1, .carrot2:
            out.append(Stack(item: .food(.carrot), count: 1))
        case .cobweb:
            out.append(Stack(item: .mat(.string), count: 1))
        case .chest:
            for s in world.removeChest(x, y) { out.append(s) }
            out.append(Stack(item: .block(.chest), count: 1))
        default:
            if let d = t.def.drop { out.append(Stack(item: d, count: 1)) }
            else if !t.def.noDrop { out.append(Stack(item: .block(t), count: 1)) }
        }
        return out
    }

    func breakTile(_ x: Int, _ y: Int, _ byPlayer: Bool, dropChance: Double = 1.0) {
        let t: Tile = world.tile(x, y)
        if t == .air || t.hardness >= 9999 { return }
        if isDoor(t) {
            // remove the other half quietly so a door only drops once
            if isDoor(world.tile(x, y - 1)) { world.set(x, y - 1, .air) }
            if isDoor(world.tile(x, y + 1)) { world.set(x, y + 1, .air) }
        }
        if world.set(x, y, .air) == .air && t != .air { return }
        if isLogTile(t) && decayZones.count < 24 { decayZones.append(DecayZone(x: x, y: y, t: 30)) }
        let col: UInt32 = t.def.colors.first ?? 0x888888
        spawnParticles(Double(x) + 0.5, Double(y) + 0.5, col, 6, 3.5, 0.5, 16)
        if !(byPlayer && isCreative) {
            for s in tileDropStacks(t, x, y) {
                if dropChance < 1.0 && Double.random(in: 0...1) > dropChance { continue }
                spawnDrop(s, Double(x) + 0.5, Double(y) + 0.4, Double.random(in: -1.5...1.5), -3.0)
            }
        } else if t == .chest {
            _ = world.removeChest(x, y)
        }
        // dependent tiles
        let above: Tile = world.tile(x, y - 1)
        if world.needsSupport(above) && !world.supports(world.tile(x, y), above) {
            breakTile(x, y - 1, byPlayer)
        }
        if t == .farmland {
            let a2: Tile = world.tile(x, y - 1)
            if a2 == .wheat1 || a2 == .wheat2 || a2 == .wheat3 || a2 == .carrot1 || a2 == .carrot2 || a2 == .carrot3 { breakTile(x, y - 1, byPlayer) }
        }
        // unsupported sand above falls
        if world.tile(x, y - 1) == .sand { checkFalling(x, y - 1) }
        bumpHUD()
    }

    func fellTree(_ x: Int, _ y: Int) {
        // find the base and walk upward
        var by: Int = y
        while isLogTile(world.tile(x, by + 1)) { by += 1 }
        var cy: Int = by
        var top: Int = y
        var count: Int = 0
        while isLogTile(world.tile(x, cy)) && count < 40 {
            top = cy
            cy -= 1
            count += 1
        }
        // remove logs from top to bottom (only from the struck tile upwards)
        var yy: Int = y
        while isLogTile(world.tile(x, yy)) && yy >= top {
            breakTile(x, yy, true)
            yy -= 1
        }
        // leaves around the crown
        let ty: Int = top
        for dy in -7...3 {
            for dx in -6...6 {
                let lx: Int = x + dx
                let ly: Int = ty + dy
                let lt: Tile = world.tile(lx, ly)
                if lt == .leaves || lt == .jungleLeaves {
                    // only fell leaves that belong to this tree (near the trunk top)
                    if abs(dx) + abs(dy + 1) <= 8 { breakTile(lx, ly, true) }
                }
            }
        }
    }

    // MARK: placing blocks

    func canPlaceAt(_ tx: Int, _ ty: Int, _ t: Tile) -> Bool {
        if ty < 2 || ty >= world.H - 2 { return false }
        let cur: Tile = world.tile(tx, ty)
        if !(cur == .air || cur.liquid || (cur.isPlant && cur != .torch && cur != .lantern) || cur == .cobweb) { return false }
        if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return false }
        if t.solid {
            // no overlap with bodies
            let x0: Double = Double(tx), x1: Double = Double(tx + 1)
            let y0: Double = Double(ty), y1: Double = Double(ty + 1)
            if pb.right > x0 + 0.02 && pb.left < x1 - 0.02 && pb.y > y0 + 0.02 && pb.top < y1 - 0.02 && !noclip { return false }
            for m in mobs {
                if m.hp <= 0 { continue }
                if m.b.right > x0 + 0.02 && m.b.left < x1 - 0.02 && m.b.y > y0 + 0.02 && m.b.top < y1 - 0.02 { return false }
            }
            for v in vehicles {
                if v.b.x + v.b.w * 0.5 > x0 + 0.02 && v.b.x - v.b.w * 0.5 < x1 - 0.02 && v.b.y > y0 + 0.02 && v.b.y - v.b.h < y1 - 0.02 { return false }
            }
        }
        if world.needsSupport(t) {
            let below: Tile = world.tile(tx, ty + 1)
            if !world.supports(below, t) { return false }
        }
        if isCreative || flying { return true }
        // needs an adjacent tile to attach to
        let n: [Tile] = [world.tile(tx - 1, ty), world.tile(tx + 1, ty), world.tile(tx, ty - 1), world.tile(tx, ty + 1)]
        for k in n {
            if k != .air && !k.liquid && !(k.isPlant && k != .torch) { return true }
        }
        return false
    }

    func usePlaceBlock(_ t: Tile, _ dt: Double) {
        if placeCD > 0 { return }
        let tx: Int = Int(floor(aimX))
        let ty: Int = Int(floor(aimY))
        if t == .doorClosed || t == .doorOpen {
            if placeDoor(tx, ty) {
                if !isCreative { inv.removeAt(sel, 1) }
                placeCD = 0.25
                swingT = 0.14
                bumpHUD()
            }
            return
        }
        if !canPlaceAt(tx, ty, t) { return }
        // plants / crops need special support handled in canPlaceAt through needsSupport
        world.set(tx, ty, t)
        if t == .chest { world.setChestItems(tx, ty, []) }
        if !isCreative { inv.removeAt(sel, 1) }
        placeCD = 0.11
        swingT = 0.14
        swingDir = aimX >= pb.x ? 1 : -1
        facing = swingDir
        bumpHUD()
    }

    var placeCDValue: Double { return placeCD }

    func usePlant(_ crop: Tile, _ it: Item, _ pressed: Bool) {
        if placeCD > 0 { return }
        let tx: Int = Int(floor(aimX))
        let ty: Int = Int(floor(aimY))
        if world.tile(tx, ty) == .air && world.tile(tx, ty + 1) == .farmland && inReach(Double(tx) + 0.5, Double(ty) + 0.5) {
            world.set(tx, ty, crop)
            if !isCreative { inv.removeAt(sel, 1) }
            placeCD = 0.2
            swingT = 0.14
            bumpHUD()
        }
    }

    // MARK: food

    func useFood(_ f: Food, _ pressed: Bool) {
        let tx: Int = Int(floor(aimX))
        let ty: Int = Int(floor(aimY))
        if f == .carrot && world.tile(tx, ty) == .air && world.tile(tx, ty + 1) == .farmland {
            usePlant(.carrot1, .food(.carrot), pressed)
            return
        }
        if !pressed || eatT > 0.0 { return }
        if hunger >= 19.5 && hp >= maxHP && !isCreative {
            say("You're not hungry.", 1.2)
            return
        }
        hunger = min(20, hunger + f.hunger)
        if f.heal > 0 { heal(f.heal) }
        if !isCreative { inv.removeAt(sel, 1) }
        eatT = 0.5
        useCD = 0.5
        spawnParticles(pb.x + Double(facing) * 0.4, pb.y - 1.4, 0xC8A060, 5, 2.0, 0.4, 8)
        floatText("+" + String(Int(f.hunger)), pb.x, pb.y - pb.h - 0.4, 0xE0A040)
        bumpHUD()
    }

    // MARK: bow

    /// Bow stats live in one place so new bows only need a new entry here
    struct BowStats {
        var minSpeed: Double = 20
        var maxSpeed: Double = 40
        var baseDamage: Double = 5
        var chargeDamage: Double = 9
        var chargeTime: Double = 0.55
        var useTime: Double = 0.32
        var gravity: Double = 15
    }

    func bowStats(_ it: Item) -> BowStats { return BowStats() }

    /// Hold to draw (aim with your finger, the dotted arc shows the flight path), release to shoot.
    /// A quick tap still fires a useful shot, and holding at full draw keeps firing automatically.
    func handleBow(_ dt: Double, _ pressed: Bool, _ released: Bool) {
        let hasArrow: Bool = isCreative || inv.total(.ammo(.arrow)) > 0
        let st: BowStats = bowStats(.bow)
        if useHeld {
            if !hasArrow {
                if pressed { say("No arrows!", 1.2) }
                bowCharge = 0
                return
            }
            if useCD > 0 && bowCharge == 0 { return }
            bowCharge = min(1.0, max(bowCharge, 0.01) + dt / st.chargeTime)
            facing = aimX >= pb.x ? 1 : -1
            if bowCharge >= 1.0 && useCD <= 0 {
                fireArrow(1.0)
                bowCharge = 0.3
            }
        } else if released && bowCharge > 0 && hasArrow {
            fireArrow(max(0.45, bowCharge))
            bowCharge = 0
        } else {
            bowCharge = 0
        }
    }

    /// Where the arrow leaves the bow and its starting velocity for a given draw
    func arrowLaunch(_ charge: Double) -> (Double, Double, Double, Double) {
        let st: BowStats = bowStats(.bow)
        let ox: Double = pb.x + Double(facing) * 0.35
        let oy: Double = pb.y - 1.2
        var dx: Double = aimX - ox
        var dy: Double = aimY - oy
        let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
        dx /= len
        dy /= len
        let speed: Double = st.minSpeed + (st.maxSpeed - st.minSpeed) * charge
        // a little of the archer's own motion carries into the arrow, so shots on the run still land
        return (ox + dx * 0.4, oy + dy * 0.4, dx * speed + pb.vx * 0.3, dy * speed + min(0, pb.vy) * 0.2)
    }

    func fireArrow(_ charge: Double) {
        if !isCreative { _ = inv.remove(.ammo(.arrow), 1) }
        let st: BowStats = bowStats(.bow)
        let l: (Double, Double, Double, Double) = arrowLaunch(charge)
        var dmg: Double = st.baseDamage + st.chargeDamage * charge
        if charge >= 0.99 && Double.random(in: 0...1) < 0.15 { dmg *= 1.5 }
        var p = Projectile(kind: .arrow, x: l.0, y: l.1, vx: l.2, vy: l.3, dmg: dmg, fromPlayer: true, gravity: st.gravity)
        p.life = 6.0
        p.w = 0.22
        p.source = .player
        p.uid = newID()
        projectiles.append(p)
        useCD = st.useTime
        swingT = 0.18
        swingDir = facing
        bowRecoil = 0.12
        bumpHUD()
    }

    /// Sample points of the arrow's flight for the aiming arc
    func arrowPreview() -> [(Double, Double)] {
        if bowCharge <= 0 { return [] }
        let st: BowStats = bowStats(.bow)
        let l: (Double, Double, Double, Double) = arrowLaunch(max(0.45, bowCharge))
        var x: Double = l.0
        var y: Double = l.1
        let vx: Double = l.2
        var vy: Double = l.3
        var out: [(Double, Double)] = []
        let step: Double = 0.03
        var i: Int = 0
        while i < 40 {
            vy = min(vy + st.gravity * step, 40)
            let nx: Double = x + vx * step
            let ny: Double = y + vy * step
            if world.segmentSolidT(x, y, nx, ny) != nil { break }
            x = nx
            y = ny
            if i % 2 == 1 { out.append((x, y)) }
            i += 1
        }
        return out
    }

    // MARK: guns

    func gunStack() -> Stack? {
        if case .gun? = heldItem { return heldStack }
        return nil
    }

    func updateReload(_ dt: Double) {
        if reloadT <= 0 { return }
        if reloadSlot != sel {
            reloadT = 0
            reloadSlot = -1
            return
        }
        reloadT -= dt
        if reloadT <= 0 {
            reloadT = 0
            if var st = inv.slots[sel], case .gun(let g) = st.item {
                let need: Int = g.magazine - st.extra
                var take: Int = need
                if !isCreative {
                    take = min(need, inv.total(.ammo(.bullet)))
                    _ = inv.remove(.ammo(.bullet), take)
                }
                st.extra += take
                inv.slots[sel] = st
                bumpHUD()
            }
            reloadSlot = -1
        }
    }

    func startReload() {
        guard let st = heldStack, case .gun(let g) = st.item else { return }
        if reloadT > 0 || st.extra >= g.magazine { return }
        if !isCreative && inv.total(.ammo(.bullet)) <= 0 {
            say("Out of bullets!", 1.5)
            return
        }
        reloadT = g.reloadTime
        reloadSlot = sel
        say("Reloading...", 1.0)
    }

    func useGun(_ g: GunType, _ pressed: Bool) {
        guard var st = inv.slots[sel] else { return }
        if reloadT > 0 { return }
        if st.extra <= 0 {
            if pressed || useCD <= 0 { startReload() }
            return
        }
        if useCD > 0 { return }
        if g == .rifle && !pressed { return }
        st.extra -= 1
        inv.slots[sel] = st
        let ox: Double = pb.x + Double(facing) * 0.7
        let oy: Double = pb.y - 1.2
        facing = aimX >= pb.x ? 1 : -1
        var dx: Double = aimX - ox
        var dy: Double = aimY - oy
        let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
        dx /= len
        dy /= len
        var p = Projectile(kind: .bullet, x: ox, y: oy, vx: dx * g.speed, vy: dy * g.speed, dmg: g.damage, fromPlayer: true, gravity: 0)
        p.life = 1.6
        p.source = .player
        p.uid = newID()
        p.pierce = g == .rifle ? 1 : 0
        projectiles.append(p)
        useCD = g.cooldown
        muzzleT = 0.08
        swingT = 0.1
        swingDir = facing
        shake = max(shake, g == .rifle ? 0.16 : 0.07)
        pb.vx -= Double(facing) * (g == .rifle ? 2.5 : 1.0)
        spawnParticles(ox + dx * 0.4, oy + dy * 0.4, 0xFFE080, 4, 3.0, 0.15, 0)
        if st.extra <= 0 && (isCreative || inv.total(.ammo(.bullet)) > 0) { startReload() }
        bumpHUD()
    }

    // MARK: gadgets & vehicle parts

    func useGadget(_ g: Gadget, _ pressed: Bool) {
        switch g {
        case .treasureMap:
            if pressed {
                showMap = true
                bumpHUD()
            }
        case .shears:
            if let m = mobAtPoint(aimX, aimY, 0.3), m.kind == .sheep, !m.sheared, inReach(m.b.x, m.b.cy), useCD <= 0 {
                m.sheared = true
                m.regrow = 150
                useCD = 0.4
                swingT = 0.2
                for _ in 0..<(1 + Int.random(in: 0...2)) {
                    spawnDrop(Stack(item: .mat(.wool), count: 1), m.b.x, m.b.y - 0.8, Double.random(in: -2...2), -4)
                }
                spawnParticles(m.b.x, m.b.cy, 0xF0F0F0, 8, 3.0, 0.5, 8)
            }
        case .wrench:
            if pressed, useCD <= 0, let (v, c) = vehicleAtPoint(aimX, aimY), inReach(aimX, aimY) {
                removeVehiclePart(v, c)
                useCD = 0.3
            }
        case .portalKey:
            if pressed { say("Use the key on the sealed portal.", 2.0) }
        case .carKit, .boatKit, .motorboatKit:
            if pressed && useCD <= 0 { placeKit(g) }
        case .bomb:
            if pressed { throwBomb() }
        }
    }

    func removeVehiclePart(_ v: Vehicle, _ c: PartCell) {
        if v.rider { dismount() }
        let returned: [PartType] = v.removePart(c)
        for t in returned { giveItem(.part(t), 1) }
        if v.parts.isEmpty {
            vehicles.removeAll { $0.id == v.id }
        } else {
            v.recompute(keepAnchor: true)
        }
        bumpHUD()
    }

    func usePart(_ p: PartType, _ pressed: Bool) {
        if !pressed || useCD > 0 { return }
        if !inReach(aimX, aimY) {
            say("Too far away. Tap closer to you.", 1.2)
            return
        }
        // attach to an existing vehicle (the tapped cell must touch it)
        for v in vehicles {
            if aimX < v.b.left - 1.5 || aimX > v.b.right + 1.5 || aimY < v.b.top - 1.5 || aimY > v.b.y + 1.5 { continue }
            let c: PartCell = v.cellAt(aimX, aimY)
            if v.parts[c] != nil || !v.hasNeighbor(c) { continue }
            if let problem = attachProblem(v, c, p) {
                say(problem + " Green squares show where it fits.", 2.5)
                useCD = 0.3
                return
            }
            let wasReady: Bool = vehicleCheck(v).ready
            liftIfBuried(v, c)
            v.parts[c] = p
            v.recompute(keepAnchor: true)
            if !isCreative { inv.removeAt(sel, 1) }
            useCD = 0.2
            swingT = 0.15
            let check: VehicleCheck = vehicleCheck(v)
            if check.ready && !wasReady {
                let kind: String = check.title.lowercased()
                say("Your \(kind) is ready! Stand next to it and press DRIVE.", 3.5)
            }
            bumpHUD()
            return
        }
        // start a new vehicle on the ground
        let first: [PartType] = [.frame, .hull, .seat, .fuelTank, .engine]
        if !first.contains(p) {
            if nearestVehicle(10) != nil {
                let pn: String = p.name
                say("Tap one of the green squares to attach the \(pn).", 2.5)
            } else {
                say("Start with a Frame (car) or Hull Float (boat). Or craft a ready-made kit in Vehicles.", 3.0)
            }
            return
        }
        let tx: Int = Int(floor(aimX))
        let ty: Int = Int(floor(aimY))
        if world.solid(tx, ty) { return }
        let v = Vehicle(id: newID(), first: p, x: Double(tx) + 0.5, y: Double(ty) + 1.0)
        vehicles.append(v)
        if !isCreative { inv.removeAt(sel, 1) }
        useCD = 0.25
        say("Vehicle started. Now hold more parts: green squares show where they fit.", 3.0)
        bumpHUD()
    }
}

// ===== p15a_mobai =====

// MARK: - Mob AI

extension Game {
    func buildDecks() -> [Deck] {
        var out: [Deck] = []
        let sea: Double = Double(WorldGen.sea)
        for s in ships where s.sink < 3.0 {
            let dy: Double = s.deckY(sea)
            out.append(Deck(x0: s.x - PirateShip.deckHalf, x1: s.x + PirateShip.deckHalf - 0.1, y: dy, vx: s.speed * Double(s.dir), id: s.id))
        }
        // a parked vehicle you can stand on (only while it is roughly level)
        for v in vehicles where !v.rider && v.upright {
            out.append(Deck(x0: v.b.x - v.b.w * 0.5, x1: v.b.x + v.b.w * 0.5, y: v.b.y - v.b.h, vx: v.vx, id: 1_000_000 + v.id))
        }
        return out
    }

    func allDecks() -> [Deck] { return decksCache }

    func accelX(_ m: Mob, _ target: Double, _ a: Double, _ dt: Double) {
        let d: Double = target - m.b.vx
        let s: Double = a * dt
        if d > s { m.b.vx += s } else if d < -s { m.b.vx -= s } else { m.b.vx = target }
    }

    func stepMob(_ m: Mob, _ dt: Double, stepUp: Double = 1.0) {
        let d: MobDef = m.def
        if d.flying {
            // keep flyers from sinking; their AI sets vy directly
        } else if m.b.inWater {
            m.b.vy += 12.0 * dt
            m.b.vy = clampD(m.b.vy, -5.0, 5.0)
            if m.hp > 0 && d.behavior != .swimmer { m.b.vy -= 26.0 * dt }
        } else {
            m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
        }
        if m.knock > 0 { m.knock -= dt }
        world.moveBody(&m.b, dt, stepUp: d.flying ? 0 : stepUp, dropThrough: false, decks: decksCache)
        if m.b.deck >= 0 && m.b.deck < decksCache.count { m.b.x += decksCache[m.b.deck].vx * dt }
        if m.boat >= 0 { clampToDeck(m) }
        if m.b.onGround { m.anim += abs(m.b.vx) * dt * 0.8 } else { m.anim += dt * 0.5 }
    }

    func cliffAhead(_ m: Mob, _ dir: Int) -> Bool {
        let fx: Int = Int(floor(m.b.x + Double(dir) * (m.b.w * 0.5 + 0.6)))
        let fy: Int = Int(floor(m.b.y + 0.2))
        var d: Int = 0
        while d < 5 {
            let t: Tile = world.tile(fx, fy + d)
            if t.solid || t == .platform || t.liquid { return false }
            d += 1
        }
        return true
    }

    func wander(_ m: Mob, _ dt: Double, _ speedK: Double) {
        let d: MobDef = m.def
        m.t1 -= dt
        if m.t1 <= 0 {
            if m.st == 0 {
                m.st = 1
                m.dir = Bool.random() ? 1 : -1
                if abs(m.b.x - m.homeX) > 24 { m.dir = m.b.x > m.homeX ? -1 : 1 }
                m.t1 = Double.random(in: 1.5...4.5)
            } else {
                m.st = 0
                m.t1 = Double.random(in: 1.0...4.0)
            }
        }
        if m.st == 1 {
            if cliffAhead(m, m.dir) || (m.b.hitWall && !m.b.onGround) { m.dir = -m.dir }
            if m.b.hitWall && m.b.onGround { m.dir = -m.dir }
            accelX(m, Double(m.dir) * d.speed * speedK, 14, dt)
        } else {
            accelX(m, 0, 18, dt)
        }
    }

    func flee(_ m: Mob, _ fromX: Double, _ dt: Double, _ speedK: Double) {
        let dirX: Double = m.b.x >= fromX ? 1.0 : -1.0
        m.dir = Int(dirX)
        accelX(m, dirX * m.def.speed * speedK, 30, dt)
        if m.b.hitWall && m.b.onGround { m.b.vy = -m.def.jump }
    }

    func chase(_ m: Mob, _ tx: Double, _ speedK: Double, _ dt: Double) {
        let d: MobDef = m.def
        let dirX: Double = tx >= m.b.x ? 1.0 : -1.0
        if abs(tx - m.b.x) > 0.35 {
            m.dir = Int(dirX)
            accelX(m, dirX * d.speed * speedK, 26, dt)
        } else {
            accelX(m, 0, 30, dt)
        }
        if m.b.hitWall && m.b.onGround { m.b.vy = -d.jump }
        if m.b.inWater { m.b.vy -= 18 * dt }
    }

    func playerOverlaps(_ m: Mob, _ pad: Double) -> Bool {
        if dead { return false }
        return pb.right > m.b.left - pad && pb.left < m.b.right + pad && pb.y > m.b.top - pad && pb.top < m.b.y + pad
    }

    func contactHurt(_ m: Mob, _ dmg: Double) {
        if m.cd > 0 { return }
        if playerOverlaps(m, -0.05) {
            var info = DamageInfo(amount: dmg, type: .contact, source: .mob(m, faction(of: m)))
            info.knock = 6.5
            info.originX = m.b.x
            if hurtPlayer(info) { m.cd = 0.9 }
        }
    }

    /// A creature's swing: hits the player and any creature from another side inside the reach box
    func mobStrike(_ m: Mob, reach: Double, height: Double, dmg: Double, knock: Double) {
        let x0: Double = m.dir > 0 ? m.b.x - 0.3 : m.b.x - reach - 0.3
        let x1: Double = m.dir > 0 ? m.b.x + reach + 0.3 : m.b.x + 0.3
        var info = DamageInfo(amount: dmg, type: .melee, source: .mob(m, faction(of: m)))
        info.dirX = Double(m.dir)
        info.knock = knock
        info.originX = m.b.x
        info.key = newID()
        damageBox(x0, m.b.y - height, x1, m.b.y + 0.1, info)
    }

    func updateMobs(_ dt: Double) {
        let t0: Double = perfNow()
        let px: Double = pb.x
        let py: Double = pb.y
        frameNo &+= 1
        // iterated by index because AI code may append new mobs while it runs
        var i: Int = 0
        while i < mobs.count {
            let m: Mob = mobs[i]
            i += 1
            if m.hp <= 0 || m.removed { continue }
            let dx: Double = abs(m.b.x - px)
            let dy: Double = abs(m.b.y - py)
            if !m.persistent && !m.tame && !m.isBoss && (dx > 115 || dy > 85) {
                m.removed = true
                continue
            }
            if m.hurtT > 0 { m.hurtT -= dt }
            if m.cd > 0 { m.cd -= dt }
            if m.flash > 0 { m.flash -= dt }
            if m.regrow > 0 {
                m.regrow -= dt
                if m.regrow <= 0 { m.sheared = false }
            }
            if !world.isLoaded(Int(floor(m.b.x))) { continue }
            // creatures well off screen wait until the player comes closer (saves a lot of work)
            if !m.isBoss && !m.tame && m.boat < 0 && (dx > 72 || dy > 56) { continue }
            // mid-distance creatures think and move at a third of the rate, staggered by id, with the
            // skipped time folded into their next step so they still cover the same ground
            var step: Double = dt
            if !m.isBoss && !m.tame && m.boat < 0 && (dx > 40 || dy > 30) {
                m.aiAccum += dt
                if (frameNo &+ m.id) % 3 != 0 {
                    Perf.shared.countSkip()
                    continue
                }
                step = min(0.1, m.aiAccum)
            }
            m.aiAccum = 0
            updateMob(m, step)
            if m.hp > 0 { mobHazards(m, step) }
        }
        updateDying(dt)
        // compact once: drop removed mobs and finished death animations
        if mobs.contains(where: { $0.removed }) { mobs.removeAll { $0.removed } }
        Perf.shared.aiMs = Perf.smooth(Perf.shared.aiMs, perfNow() - t0)
    }

    func nearestHostileTo(_ x: Double, _ y: Double, _ r: Double) -> Mob? {
        var best: Mob? = nil
        var bd: Double = r * r
        for o in mobs {
            if o.hp <= 0 || o.tame || !o.def.hostile { continue }
            let dx: Double = o.b.x - x
            let dy: Double = o.b.cy - y
            let d: Double = dx * dx + dy * dy
            if d < bd { bd = d; best = o }
        }
        return best
    }

    func updateMob(_ m: Mob, _ dt: Double) {
        let d: MobDef = m.def
        if m.kind == .bearBoss || m.kind == .rex {
            updateBossMob(m, dt)
            return
        }
        if m.boat >= 0 && updateCrew(m, dt) { return }
        let toPX: Double = pb.x - m.b.x
        let dist: Double = abs(toPX)
        let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
        let near: Bool = dist < d.aggro && abs(dyP) < 14 && !dead
        let peaceful: Bool = settings.peaceful
        if m.tame {
            updatePet(m, dt)
            return
        }
        switch m.kind {
        case .pig, .cow, .sheep, .villager:
            if m.t2 > 0 {
                m.t2 -= dt
                flee(m, m.tx, dt, 1.9)
            } else {
                wander(m, dt, 0.55)
            }
            stepMob(m, dt)
        case .giraffe, .chicken, .frog, .cat:
            if m.t2 > 0 {
                m.t2 -= dt
                flee(m, m.tx, dt, 1.7)
            } else if dist < 6.0 && !dead && m.kind != .cat {
                flee(m, pb.x, dt, 1.4)
            } else {
                wander(m, dt, 0.5)
            }
            if m.kind == .frog && m.b.onGround && m.st == 1 && Double.random(in: 0...1) < 0.04 { m.b.vy = -9; m.b.vx = Double(m.dir) * 3.5 }
            stepMob(m, dt)
        case .elephant, .bear, .wolf:
            if m.angry && !dead {
                m.t3 -= dt
                if m.t3 <= 0 || dist > 30 { m.angry = false } else {
                    chase(m, pb.x, 1.0, dt)
                    if m.kind == .wolf && m.b.onGround && dist < 4.0 && Double.random(in: 0...1) < 0.03 { m.b.vy = -12; m.b.vx = Double(m.dir) * 7.0 }
                    if peaceful { m.angry = false }
                    else if abs(dyP) < 1.4 { contactHurt(m, d.dmg) }
                }
            } else {
                wander(m, dt, 0.5)
                // territorial bears and elephants warn when the player is very close
                if m.kind != .wolf && dist < 2.8 && abs(dyP) < 2.0 && !peaceful && Double.random(in: 0...1) < 0.01 { m.angry = true; m.t3 = 8.0 }
                if m.kind == .wolf && isNight && near && !peaceful && Double.random(in: 0...1) < 0.002 { m.angry = true; m.t3 = 12.0 }
            }
            stepMob(m, dt)
        case .grizzly, .polarBear, .tiger, .scorpion:
            if near && !peaceful {
                chase(m, pb.x, 1.0, dt)
                if m.kind == .tiger && m.b.onGround && dist < 6.5 && dist > 2.0 && m.cd <= 0.4 && Double.random(in: 0...1) < 0.04 {
                    m.b.vy = -11.5
                    m.b.vx = Double(m.dir) * 10.0
                    m.t3 = 0.6
                }
                if abs(dyP) < 1.5 { contactHurt(m, d.dmg) }
            } else {
                wander(m, dt, 0.5)
            }
            stepMob(m, dt)
        case .zombie:
            updateZombie(m, dt, near && !peaceful, dyP)
        case .skeleton, .pirate, .pirateCaptain:
            updateSwordsman(m, dt, near && !peaceful, dist, dyP)
        case .pirateGunner, .imp:
            updateShooter(m, dt, near && !peaceful, dist, dyP)
        case .slime, .emberSlime:
            updateSlime(m, dt, near && !peaceful, dyP)
        case .crow, .bat, .cinderBat, .wraith:
            updateFlyer(m, dt, near && !peaceful, dist, dyP)
        case .fish:
            updateFish(m, dt)
        case .bearBoss, .rex:
            break
        }
    }

    // MARK: specific AIs

    func updateZombie(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dyP: Double) {
        let d: MobDef = m.def
        // burn in sunlight
        if world.dim == .overworld && dayFactor > 0.7 && world.isSkyExposed(Int(floor(m.b.x)), Int(floor(m.b.y - 1))) && !m.b.inWater {
            m.burn = 2.0
        }
        if aggro {
            chase(m, pb.x, 1.0, dt)
            if abs(dyP) < 1.6 { contactHurt(m, d.dmg) }
        } else {
            wander(m, dt, 0.45)
        }
        stepMob(m, dt)
    }

    /// skeleton knight (shield), pirate and captain (cutlass)
    func updateSwordsman(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
        let d: MobDef = m.def
        let isSkel: Bool = m.kind == .skeleton
        if m.st == 3 {
            // wind-up
            m.t3 -= dt
            accelX(m, 0, 40, dt)
            if m.t3 <= 0 {
                m.st = 4
                m.t3 = 0.22
                // strike
                mobStrike(m, reach: 2.2, height: 1.9, dmg: d.dmg, knock: 7.0)
            }
        } else if m.st == 4 {
            m.t3 -= dt
            accelX(m, 0, 40, dt)
            if m.t3 <= 0 {
                m.st = 0
                m.cd = m.kind == .pirateCaptain ? 0.9 : 1.2
            }
        } else if aggro {
            let sp: Double = dist > 8 ? 1.15 : 0.95
            if isSkel {
                // raise the shield while approaching, drop it to attack
                m.blocking = dist > 2.4 && dist < 11
                if dist < 2.0 && m.cd <= 0 && abs(dyP) < 1.6 {
                    m.st = 3
                    m.t3 = 0.38
                    m.blocking = false
                    m.dir = pb.x >= m.b.x ? 1 : -1
                }
                chase(m, pb.x, m.blocking ? 0.7 : sp, dt)
            } else {
                if dist < 2.0 && m.cd <= 0 && abs(dyP) < 1.6 {
                    m.st = 3
                    m.t3 = 0.3
                    m.dir = pb.x >= m.b.x ? 1 : -1
                }
                chase(m, pb.x, sp, dt)
            }
        } else {
            m.blocking = false
            wander(m, dt, 0.4)
        }
        if m.st == 0 && !aggro { m.blocking = false }
        stepMob(m, dt)
    }

    /// pirate gunner and imp: keep range and shoot
    func updateShooter(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
        let isImp: Bool = m.kind == .imp
        if m.st == 3 {
            m.t3 -= dt
            accelX(m, 0, 40, dt)
            m.dir = pb.x >= m.b.x ? 1 : -1
            if m.t3 <= 0 {
                m.st = 6
                m.t3 = 0.18
                shootAtPlayer(m, isImp)
            }
        } else if m.st == 6 {
            m.t3 -= dt
            accelX(m, 0, 40, dt)
            if m.t3 <= 0 { m.st = 0; m.cd = isImp ? 1.9 : 2.2 }
        } else if aggro {
            let want: Double = isImp ? 8.0 : 9.0
            if dist < want - 3.0 {
                flee(m, pb.x, dt, 0.8)
            } else if dist > want + 3.0 {
                chase(m, pb.x, 0.9, dt)
            } else {
                accelX(m, 0, 20, dt)
                m.dir = pb.x >= m.b.x ? 1 : -1
            }
            if m.cd <= 0 && dist < 17 && abs(dyP) < 9 {
                m.st = 3
                m.t3 = 0.5
            }
        } else {
            wander(m, dt, 0.4)
        }
        stepMob(m, dt)
    }

    func shootAtPlayer(_ m: Mob, _ fire: Bool) {
        let ox: Double = m.b.x + Double(m.dir) * 0.6
        let oy: Double = m.b.y - m.b.h * 0.65
        var dx: Double = pb.x - ox
        var dy: Double = (pb.y - pb.h * 0.55) - oy
        let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
        dx /= len
        dy /= len
        let sp: Double = fire ? 11.0 : 20.0
        var p = Projectile(kind: fire ? .fireball : .bullet, x: ox, y: oy, vx: dx * sp, vy: dy * sp, dmg: m.def.dmg, fromPlayer: false, gravity: 0)
        p.life = 3.0
        p.owner = m.id
        p.source = .mob(m, faction(of: m))
        p.uid = newID()
        projectiles.append(p)
        spawnParticles(ox, oy, fire ? 0xFF7020 : 0xFFE080, 4, 2.5, 0.18, 0)
    }

    func updateSlime(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dyP: Double) {
        let d: MobDef = m.def
        m.t1 -= dt
        if m.b.onGround {
            m.b.vx *= 0.8
            if m.t1 <= 0 {
                if aggro {
                    let dirX: Double = pb.x >= m.b.x ? 1.0 : -1.0
                    m.dir = Int(dirX)
                    m.b.vy = -d.jump
                    m.b.vx = dirX * d.speed * 1.6
                    m.t1 = Double.random(in: 0.7...1.3)
                } else {
                    m.dir = Bool.random() ? 1 : -1
                    m.b.vy = -8.5
                    m.b.vx = Double(m.dir) * 2.0
                    m.t1 = Double.random(in: 1.5...3.5)
                }
            }
        }
        if m.kind == .emberSlime && Double.random(in: 0...1) < 0.1 {
            spawnParticles(m.b.x, m.b.y - 0.4, 0xFF8A20, 1, 1.2, 0.4, -3)
        }
        if aggro && abs(dyP) < 1.5 { contactHurt(m, d.dmg) }
        stepMob(m, dt)
    }

    func updateFlyer(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
        let d: MobDef = m.def
        m.anim += dt * 8.0
        var tx: Double = m.homeX
        var ty: Double = m.homeY
        var spd: Double = d.speed * 0.6
        if m.kind == .crow {
            // wander around home; flee when approached
            m.t1 -= dt
            if m.t1 <= 0 {
                m.t1 = Double.random(in: 2...5)
                m.tx = m.homeX + Double.random(in: -12...12)
                let gy: Double = Double(world.surfaceY(Int(floor(m.tx))))
                m.ty = gy - Double.random(in: 3...8)
            }
            tx = m.tx
            ty = m.ty
            if dist < 5.0 && !dead {
                tx = m.b.x + (m.b.x - pb.x) * 3
                ty = m.b.y - 6
                spd = d.speed * 1.4
            }
        } else if aggro {
            tx = pb.x
            ty = pb.y - 1.3 + sin(clock * 3.0 + Double(m.id)) * 1.2
            spd = d.speed
        } else {
            m.t1 -= dt
            if m.t1 <= 0 {
                m.t1 = Double.random(in: 1.5...4)
                m.tx = m.b.x + Double.random(in: -8...8)
                m.ty = m.b.y + Double.random(in: -4...4)
            }
            tx = m.tx
            ty = m.ty
        }
        var ax: Double = tx - m.b.x
        var ay: Double = ty - m.b.y
        let len: Double = max(0.001, sqrt(ax * ax + ay * ay))
        ax /= len
        ay /= len
        m.b.vx += (ax * spd - m.b.vx) * min(1.0, dt * 4.0)
        m.b.vy += (ay * spd - m.b.vy) * min(1.0, dt * 4.0)
        if abs(m.b.vx) > 0.3 { m.dir = m.b.vx > 0 ? 1 : -1 }
        if m.kind == .wraith {
            // drifts through walls, slower inside solid tiles
            let inside: Bool = world.solid(Int(floor(m.b.x)), Int(floor(m.b.y - 0.7)))
            let k: Double = inside ? 0.5 : 1.0
            m.b.x += m.b.vx * dt * k
            m.b.y += m.b.vy * dt * k
        } else {
            world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
            if m.b.hitWall || m.b.hitCeil || m.b.onGround { m.b.vy = -1.0; m.t1 = 0 }
        }
        if aggro && m.kind != .crow && abs(dyP) < 1.6 { contactHurt(m, d.dmg) }
    }

    func updateFish(_ m: Mob, _ dt: Double) {
        m.anim += dt * 6.0
        if !m.b.inWater {
            // flopping on land
            m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
            world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
            m.t2 += dt
            if m.t2 > 1.0 { m.t2 = 0; hurtMob(m, 1, 0, 0, false) }
            return
        }
        m.t1 -= dt
        if m.t1 <= 0 {
            m.t1 = Double.random(in: 1.5...4)
            m.tx = m.b.x + Double.random(in: -8...8)
            m.ty = m.b.y + Double.random(in: -3...3)
        }
        if abs(pb.x - m.b.x) < 4 && abs(pb.y - m.b.y) < 3 && pb.inWater {
            m.tx = m.b.x + (m.b.x - pb.x) * 3
            m.ty = m.b.y + (m.b.y - pb.y) * 2
        }
        var ax: Double = m.tx - m.b.x
        var ay: Double = m.ty - m.b.y
        let len: Double = max(0.001, sqrt(ax * ax + ay * ay))
        ax /= len
        ay /= len
        let sp: Double = m.def.speed
        m.b.vx += (ax * sp - m.b.vx) * min(1.0, dt * 3.0)
        m.b.vy += (ay * sp * 0.6 - m.b.vy) * min(1.0, dt * 3.0)
        if abs(m.b.vx) > 0.2 { m.dir = m.b.vx > 0 ? 1 : -1 }
        let nx: Double = m.b.x + m.b.vx * dt
        let ny: Double = m.b.y + m.b.vy * dt
        let tx: Int = Int(floor(nx))
        let ty: Int = Int(floor(ny - 0.2))
        if world.tile(tx, ty) == .water && world.tile(tx, Int(floor(ny))) != .air {
            m.b.x = nx
            m.b.y = ny
        } else {
            m.t1 = 0
            m.b.vx = -m.b.vx
            m.b.vy = -m.b.vy
        }
        let hw: Double = m.b.w * 0.5
        m.b.inWater = world.liquidFraction(m.b.x - hw, m.b.y - m.b.h, m.b.x + hw, m.b.y, false) > 0.3
    }

    // MARK: pets

    func updatePet(_ m: Mob, _ dt: Double) {
        let d: MobDef = m.def
        let toP: Double = pb.x - m.b.x
        let dist: Double = abs(toP)
        if dist > 45 || abs(pb.y - m.b.y) > 30 {
            m.b.x = pb.x - Double(facing) * 1.5
            m.b.y = pb.y
            m.b.vx = 0
            m.b.vy = 0
            return
        }
        if m.st == 7 {
            accelX(m, 0, 20, dt)
            stepMob(m, dt)
            return
        }
        // attack nearby hostiles
        var target: Mob? = nil
        if m.kind == .wolf {
            target = nearestHostileTo(pb.x, pb.y - 1, 9.0)
        }
        if let t = target, t.hp > 0 {
            chase(m, t.b.x, 1.2, dt)
            if m.cd <= 0 && abs(t.b.x - m.b.x) < 1.6 && abs(t.b.cy - m.b.cy) < 1.5 {
                hurtMob(t, 7, Double(m.dir), 5.0, true)
                m.cd = 0.7
            }
        } else if dist > 3.5 {
            let sp: Double = dist > 12 ? 1.8 : 1.15
            chase(m, pb.x, sp, dt)
        } else {
            accelX(m, 0, 20, dt)
        }
        _ = d
        stepMob(m, dt)
    }

    func tryTame(_ m: Mob) -> Bool {
        if m.tame { return false }
        guard let it = heldItem else { return false }
        var ok: Bool = false
        if m.kind == .wolf, case .mat(let mm) = it, mm == .bone { ok = true }
        if m.kind == .cat, case .food(let f) = it, f == .rawFish || f == .cookedFish { ok = true }
        if !ok { return false }
        if !isCreative { inv.removeAt(sel, 1) }
        if Double.random(in: 0...1) < 0.6 {
            m.tame = true
            m.persistent = true
            m.angry = false
            m.hp = m.maxHP
            say("You tamed the " + m.def.name.lowercased() + "!", 3.0)
            spawnParticles(m.b.x, m.b.y - 1, 0xFF6080, 10, 3.0, 0.8, -4)
        } else {
            say("The " + m.def.name.lowercased() + " isn't convinced yet...", 2.0)
        }
        useCD = 0.5
        bumpHUD()
        return true
    }
}

// ===== p15b_spawn =====

// MARK: - Mob spawning, villagers

extension Game {
    func updateSpawning(_ dt: Double) {
        villagerTimer -= dt
        if villagerTimer <= 0 {
            villagerTimer = 2.5
            ensureVillagers()
        }
        spawnTimer -= dt
        if spawnTimer > 0 { return }
        spawnTimer = Double.random(in: 0.45...1.0)
        if dead { return }
        var passive: Int = 0
        var hostile: Int = 0
        var aquatic: Int = 0
        for m in mobs {
            if m.hp <= 0 || m.tame || m.persistent { continue }
            if abs(m.b.x - pb.x) > 100 { continue }
            if m.kind == .fish { aquatic += 1 }
            else if m.def.hostile { hostile += 1 }
            else if m.kind != .villager { passive += 1 }
        }
        let px: Int = Int(floor(pb.x))
        var place: SpawnPlace = .surface
        if world.dim == .umbral {
            place = .umbral
        } else {
            let sh: Int = gen.col(px).h
            let open: Bool = world.isSkyExposed(px, Int(pb.y) - 1)
            let depth: Int = Int(pb.y) - sh
            if depth > 18 && !open { place = .cave }
        }
        let half: Double = viewTilesW * 0.5 + 3.0
        let side: Double = Bool.random() ? 1.0 : -1.0
        let sx: Double = pb.x + side * (half + Double.random(in: 2...24))
        let ix: Int = Int(floor(sx))
        if !world.isLoaded(ix) { return }
        if !gen.infinite && (ix < 4 || ix > gen.width - 5) { return }
        var sy: Double = 0
        var eff: SpawnPlace = place
        if place == .surface {
            let h: Int = world.surfaceY(ix)
            let ht: Tile = world.tile(ix, h)
            if ht.liquid {
                eff = .ocean
                var wy: Int = h + 1
                var dep: Int = 0
                while world.tile(ix, wy) == .water && dep < 40 { wy += 1; dep += 1 }
                if dep < 5 { return }
                sy = Double(h + 2 + Int.random(in: 0..<max(1, dep - 3)))
            } else if ht.solid {
                if world.solid(ix, h - 1) || world.solid(ix, h - 2) || world.tile(ix, h - 1).liquid { return }
                sy = Double(h)
            } else { return }
        } else {
            let startY: Int = Int(pb.y) + Int.random(in: -20...20)
            var found: Bool = false
            var y: Int = startY
            var tries: Int = 0
            while tries < 22 {
                if !world.solid(ix, y) && !world.solid(ix, y - 1) && !world.solid(ix, y - 2) && world.solid(ix, y + 1) && !world.tile(ix, y).liquid {
                    found = true
                    break
                }
                y += 1
                tries += 1
            }
            if !found { return }
            if place == .cave && world.isSkyExposed(ix, y) { return }
            if light.valid && light.covers(ix, y, ix, y) && light.brightness(ix, y) > 6 && !fullBright { return }
            sy = Double(y + 1)
        }
        let biome: Biome = world.dim == .overworld ? gen.col(ix).biome : .umbral
        let night: Bool = isNight
        var cands: [SpawnRule] = []
        var total: Double = 0
        for r in spawnRules {
            if r.place != eff { continue }
            if r.when == .day && night { continue }
            if r.when == .night && !night { continue }
            if !r.biomes.isEmpty && !r.biomes.contains(biome) { continue }
            if eff == .cave || eff == .umbral {
                if Int(sy) < r.minY || Int(sy) > r.maxY { continue }
            }
            let d: MobDef = mobDef(r.kind)
            if d.hostile {
                if !monstersEnabled || settings.peaceful { continue }
                let cap: Int = (eff == .cave || eff == .umbral) ? 9 : 6
                if hostile >= cap { continue }
                if eff == .surface && !night && d.behavior == .hostile && r.kind == .zombie { continue }
            } else if r.kind == .fish {
                if aquatic >= 9 { continue }
            } else {
                if passive >= 9 { continue }
            }
            cands.append(r)
            total += r.weight
        }
        if cands.isEmpty || total <= 0 { return }
        var pick: Double = Double.random(in: 0..<total)
        var chosen: SpawnRule = cands[0]
        for r in cands {
            pick -= r.weight
            if pick <= 0 { chosen = r; break }
        }
        let n: Int = 1 + Int.random(in: 0..<max(1, chosen.group))
        for k in 0..<n {
            let ox: Double = Double(k) * 1.1 * side + Double.random(in: -0.4...0.4)
            let x: Double = sx + ox
            var y: Double = sy
            if mobDef(chosen.kind).flying && eff != .ocean { y -= Double.random(in: 1...3) }
            let m: Mob = addMob(chosen.kind, x, y)
            m.homeX = x
            m.homeY = y
            if chosen.kind == .sheep && Double.random(in: 0...1) < 0.1 { m.sheared = true }
        }
    }

    func ensureVillagers() {
        if world.dim != .overworld { return }
        let px: Int = Int(floor(pb.x))
        for v in gen.villages(overlapping: px - 80, px + 80) {
            if villagerCells.contains(v.cell) { continue }
            if !world.isLoaded(v.x) { continue }
            villagerCells.insert(v.cell)
            let n: Int = 3 + Int.random(in: 0...2)
            for _ in 0..<n {
                let x: Double = Double(v.x) + Double.random(in: -Double(v.halfW - 6)...Double(v.halfW - 6))
                let m: Mob = addMob(.villager, x, Double(v.ground))
                m.homeX = x
                m.persistent = false
            }
            let c: Mob = addMob(.cat, Double(v.x) + Double.random(in: -8...8), Double(v.ground))
            c.homeX = c.b.x
        }
    }
}

// ===== p16a_combat =====

// MARK: - Combat: damage, death, projectiles, drops, particles

extension Game {
    func hurtMob(_ m: Mob, _ dmg: Double, _ dirX: Double, _ knock: Double, _ byPlayer: Bool) {
        if m.hp <= 0 { return }
        if m.kind == .rex && m.tame && byPlayer { return }
        var d: Double = dmg
        var kb: Double = knock
        if m.blocking && m.kind == .skeleton && dirX != 0 && dirX * Double(m.dir) < 0 {
            d *= 0.1
            kb *= 0.25
            spawnParticles(m.b.x - Double(m.dir) * 0.5, m.b.y - 1.0, 0xE8F0FF, 5, 4.0, 0.2, 0)
            floatText("Blocked", m.b.x, m.b.top - 0.4, 0xA0C0FF)
        }
        if d < 0.5 { d = 0.5 }
        m.hp -= d
        m.hurtT = 0.22
        m.flash = 0.12
        if dirX != 0 && kb > 0 { m.lean = clampD(dirX * kb / 9.0, -1, 1) }
        let resist: Double = m.isBoss ? 0.97 : (m.def.w > 2.0 ? 0.6 : 0.0)
        if dirX != 0 && kb > 0 {
            m.b.vx = dirX * kb * (1.0 - resist)
            if resist < 0.9 { m.b.vy = min(m.b.vy, -3.5) }
        }
        floatText(String(Int(d.rounded())), m.b.x, m.b.top - 0.2, byPlayer ? 0xFFFFFF : 0xFFAA40)
        spawnParticles(m.b.x, m.b.cy, m.kind == .skeleton ? 0xE8E8E0 : 0xB02828, 4, 3.0, 0.4, 14)
        switch m.def.behavior {
        case .passive, .skittish:
            m.t2 = 3.5
            m.tx = m.b.x - (dirX == 0 ? 1.0 : dirX) * 6.0
        case .defensive:
            // animals only hold a grudge against the player; hurt by anything else they just bolt
            if !byPlayer { break }
            m.angry = true
            m.t3 = 10.0
            if m.kind == .wolf {
                for o in mobs where o.kind == .wolf && !o.tame && abs(o.b.x - m.b.x) < 16 {
                    o.angry = true
                    o.t3 = 12.0
                }
            }
        default: break
        }
        if m.boat >= 0 { alertShip(m.boat) }
        if m.hp <= 0 { killMob(m, byPlayer) }
    }

    func killMob(_ m: Mob, _ byPlayer: Bool) {
        if m.kind == .rex && m.tame {
            downRex(m)
            return
        }
        m.hp = 0
        m.deathT = 0
        m.burn = 0
        // a creature the player hit recently still counts as the player's kill if lava, a fall or
        // another creature finishes it off
        let credit: Bool = byPlayer || clock - m.lastHitByPlayer < 6.0
        var rng = RNG(UInt64(truncatingIfNeeded: m.id) &* 6364136223846793005 &+ UInt64(truncatingIfNeeded: Int(clock * 1000)))
        for s in mobDrops(m.kind, &rng, m.sheared) {
            spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2...2), -4.5)
        }
        var col: UInt32 = 0xB02828
        if m.kind == .skeleton { col = 0xE8E8E0 }
        if m.kind == .slime { col = 0x60C060 }
        if m.kind == .emberSlime { col = 0xFF8A20 }
        spawnParticles(m.b.x, m.b.cy, col, Int(10 + m.b.w * 4), 5.0, 0.7, 14)
        if credit { kills += 1 }
        if m.kind == .bearBoss { onBearDefeated(m) }
        if m.kind == .rex { onRexDefeated(m) }
        if m === activeBoss { activeBoss = nil }
        bumpHUD()
    }

    func addMob(_ kind: MobKind, _ x: Double, _ y: Double) -> Mob {
        let m = Mob(id: newID(), kind: kind, x: x, y: y)
        if kind == .zombie { m.variant = Int.random(in: 0...2) }
        if kind == .villager { m.variant = Int.random(in: 0...2); m.persistent = false }
        mobs.append(m)
        return m
    }

    // MARK: projectiles

    /// Steps every projectile. Collision is swept along the whole frame's movement, so fast arrows and
    /// bullets cannot skip over a target between frames, and the first thing along the path is hit.
    func updateProjectiles(_ dt: Double) {
        if projectiles.isEmpty { return }
        let list: [Projectile] = projectiles
        // projectiles created while stepping (none today, but explosions could) land in the fresh array
        projectiles = []
        var keep: [Projectile] = []
        keep.reserveCapacity(list.count)
        for p0 in list {
            var p: Projectile = p0
            if stepProjectile(&p, dt) { keep.append(p) }
        }
        if !projectiles.isEmpty { keep.append(contentsOf: projectiles) }
        projectiles = keep
    }

    /// Returns false when the projectile is used up
    func stepProjectile(_ p: inout Projectile, _ dt: Double) -> Bool {
        p.life -= dt
        if p.life <= 0 {
            if p.kind == .bomb { explode(p.x, p.y, radius: 3.4, power: p.dmg, source: p.source, breakBlocks: true) }
            return false
        }
        if p.stuck > 0 {
            p.stuck -= dt
            if p.stuck <= 0 && p.kind == .arrow && p.source.kind == .player && !isCreative && Double.random(in: 0...1) < 0.35 {
                // some arrows survive and can be picked back up
                spawnDrop(Stack(item: .ammo(.arrow), count: 1), p.x, p.y, 0, -1)
            }
            return p.stuck > 0
        }
        if p.kind == .shock { return stepShock(&p, dt) }
        p.vy = min(p.vy + p.gravity * dt, 40.0)
        let nx: Double = p.x + p.vx * dt
        let ny: Double = p.y + p.vy * dt
        // first solid tile along the path
        var wallT: Double = 2.0
        var wallTile: (Int, Int) = (0, 0)
        if let hit = world.segmentSolidT(p.x, p.y, nx, ny) {
            wallT = hit.2
            wallTile = (hit.0, hit.1)
        }
        // first creature (or the player) along the path, before the wall
        if p.kind != .bomb {
            if let target = firstEntityOnPath(p, nx, ny, maxT: wallT) {
                let hx: Double = p.x + (nx - p.x) * target.t
                let hy: Double = p.y + (ny - p.y) * target.t
                let dirx: Double = p.vx >= 0 ? 1.0 : -1.0
                var info = DamageInfo(amount: p.dmg, type: .projectile, source: p.source)
                info.dirX = dirx
                info.knock = p.kind == .bullet ? 4.0 : (p.kind == .arrow ? 3.5 : 3.0)
                info.originX = p.x
                info.originY = p.y
                info.key = p.uid
                info.cooldown = 1.0
                if p.kind == .fireball { info.type = .fire }
                if let m = target.mob {
                    if applyMobDamage(m, info) {
                        if p.kind == .fireball { m.burn = max(m.burn, 2.5) }
                        spawnParticles(hx, hy, p.kind == .fireball ? 0xFF8030 : 0xE8E0D0, 3, 2.5, 0.25, 8)
                    }
                    p.lastHit = m.id
                } else {
                    _ = hurtPlayer(info)
                    if p.kind == .fireball { playerBurn = max(playerBurn, 1.5); spawnParticles(hx, hy, 0xFF8030, 8, 4.0, 0.4, 6) }
                }
                if p.pierce > 0 && target.mob != nil {
                    p.pierce -= 1
                    p.dmg *= 0.7
                } else {
                    return false
                }
            }
        }
        if wallT <= 1.0 {
            let hx: Double = p.x + (nx - p.x) * wallT
            let hy: Double = p.y + (ny - p.y) * wallT
            switch p.kind {
            case .arrow:
                // stick into the block, nudged back out of it slightly so it reads as embedded
                p.x = hx - p.vx * 0.004
                p.y = hy - p.vy * 0.004
                p.stuckAngle = atan2(p.vy, p.vx)
                p.vx = 0
                p.vy = 0
                p.stuck = 4.0
                p.gravity = 0
                spawnParticles(hx, hy, 0xA0A0A0, 2, 1.5, 0.2, 8)
                return true
            case .rock:
                rockImpact(p, hx, hy)
                return false
            case .bomb:
                // bounce, losing energy
                let solidLeftRight: Bool = Int(floor(hx - p.vx * 0.01)) != wallTile.0
                if solidLeftRight { p.vx = -p.vx * 0.45 } else { p.vy = -p.vy * 0.4; p.vx *= 0.7 }
                p.x = hx - (nx - p.x) * 0.02
                p.y = hy - (ny - p.y) * 0.02
                return true
            default:
                spawnParticles(hx, hy, p.kind == .fireball ? 0xFF8030 : 0xFFE080, 5, 3.0, 0.25, 6)
                if p.kind == .fireball { igniteNear(hx, hy, p.source) }
                return false
            }
        }
        p.x = nx
        p.y = ny
        // player shots also damage pirate ships
        if p.source.kind == .player {
            for s in ships {
                let dy: Double = s.deckY(Double(WorldGen.sea))
                if abs(p.x - s.x) < 4.6 && p.y > dy - 3.0 && p.y < dy + 2.0 {
                    s.hp -= p.dmg * 0.5
                    s.hitT = 0.2
                    spawnParticles(p.x, p.y, 0x8A5A2E, 4, 3.0, 0.3, 12)
                    return false
                }
            }
        }
        if p.kind == .fireball && Double.random(in: 0...1) < 0.5 { spawnParticles(p.x, p.y, 0xFFB040, 1, 1.0, 0.25, -2) }
        if p.kind == .arrow && p.source.kind == .player && p.trail < 6 { p.trail += 1 }
        return true
    }

    struct PathHit {
        var t: Double
        var mob: Mob?
    }

    /// Nearest creature or player the segment passes through that this projectile is allowed to hurt
    func firstEntityOnPath(_ p: Projectile, _ nx: Double, _ ny: Double, maxT: Double) -> PathHit? {
        var best: PathHit? = nil
        var bt: Double = min(1.0, maxT)
        let pad: Double = max(0.08, p.w * 0.5)
        if !dead && canHarm(p.source, targetFaction: .player, targetID: 0, area: false) {
            if let t = segmentBoxT(p.x, p.y, nx, ny, pb.left - pad, pb.top - pad, pb.right + pad, pb.y + pad), t <= bt {
                bt = t
                best = PathHit(t: t, mob: nil)
            }
        }
        let x0: Double = min(p.x, nx) - 4.0
        let x1: Double = max(p.x, nx) + 4.0
        for m in mobsNear(x0, x1) {
            if m.hp <= 0 || m.id == p.lastHit || m.downed { continue }
            if !canHarm(p.source, targetFaction: faction(of: m), targetID: m.id, area: false) { continue }
            if let t = segmentBoxT(p.x, p.y, nx, ny, m.b.left - pad, m.b.top - pad, m.b.right + pad, m.b.y + pad), t <= bt {
                bt = t
                best = PathHit(t: t, mob: m)
            }
        }
        return best
    }

    /// Boss shockwaves run along the ground and hurt anything standing in them
    func stepShock(_ p: inout Projectile, _ dt: Double) -> Bool {
        p.x += p.vx * dt
        let gy: Int = world.groundBelow(Int(floor(p.x)), Int(floor(p.y)) - 3)
        p.y = Double(gy) - 0.5
        if world.solid(Int(floor(p.x)), Int(floor(p.y - 0.6))) && world.solid(Int(floor(p.x + p.vx * 0.1)), Int(floor(p.y - 0.4))) { return false }
        var info = DamageInfo(amount: p.dmg, type: .stomp, source: p.source)
        info.dirX = p.vx >= 0 ? 1 : -1
        info.knock = 7.0
        info.originX = p.x - p.vx
        info.originY = p.y
        info.key = p.uid
        info.cooldown = 2.0
        damageBox(p.x - 0.5, p.y - 0.9, p.x + 0.5, p.y + 0.5, info)
        if Double.random(in: 0...1) < 0.5 { spawnParticles(p.x, p.y + 0.3, 0xA08860, 1, 1.5, 0.3, 6) }
        return true
    }

    func rockImpact(_ p: Projectile, _ x: Double, _ y: Double) {
        spawnParticles(x, y, 0x8A8A8A, 10, 5.0, 0.5, 16)
        addShake(0.25)
        var info = DamageInfo(amount: p.dmg, type: .impact, source: p.source)
        info.knock = 5.0
        info.originX = x
        info.originY = y - 1.0
        info.key = p.uid
        info.cooldown = 1.0
        damageArea(x, y - 0.8, radius: 1.8, info, falloff: false, lineOfSight: false)
    }

    /// Fireballs set fire to whatever stands where they burst
    func igniteNear(_ x: Double, _ y: Double, _ src: DamageSource) {
        for m in mobsNear(x - 1.5, x + 1.5) where m.hp > 0 && !isHeatImmune(m.kind) {
            if abs(m.b.cy - y) < m.b.h * 0.5 + 1.0 && canHarm(src, targetFaction: faction(of: m), targetID: m.id, area: true) {
                m.burn = max(m.burn, 2.0)
            }
        }
    }

    func throwBomb() {
        if useCD > 0 { return }
        if !isCreative { inv.removeAt(sel, 1) }
        let ox: Double = pb.x + Double(facing) * 0.4
        let oy: Double = pb.y - 1.3
        var dx: Double = aimX - ox
        var dy: Double = aimY - oy
        let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
        dx /= len
        dy /= len
        let speed: Double = min(16.0, 6.0 + len * 1.6)
        var p = Projectile(kind: .bomb, x: ox, y: oy, vx: dx * speed + pb.vx * 0.5, vy: dy * speed - 2.0, dmg: 26, fromPlayer: true, gravity: 22.0)
        p.life = 1.8
        p.w = 0.4
        p.source = DamageSource.player
        p.uid = newID()
        projectiles.append(p)
        useCD = 0.45
        swingT = 0.18
        swingDir = facing
        bumpHUD()
    }

    // MARK: drops

    func updateDrops(_ dt: Double) {
        var i: Int = 0
        while i < drops.count {
            var d: DropItem = drops[i]
            d.age += dt
            if d.pickDelay > 0 { d.pickDelay -= dt }
            if d.age > 400 {
                drops.remove(at: i)
                continue
            }
            var b = Body(x: d.x, y: d.y, w: 0.3, h: 0.3)
            b.vx = d.vx
            b.vy = d.vy
            let px: Double = pb.x
            let py: Double = pb.y - pb.h * 0.5
            let dx: Double = px - d.x
            let dy: Double = py - (d.y - 0.15)
            let dist: Double = sqrt(dx * dx + dy * dy)
            var magnet: Bool = false
            if !dead && d.pickDelay <= 0 && dist < 3.2 && inv.canFit(d.stack.item, 1) {
                magnet = true
                let k: Double = 16.0
                b.vx = dx / max(dist, 0.1) * k * (1.0 + (3.2 - dist) * 0.3)
                b.vy = dy / max(dist, 0.1) * k * (1.0 + (3.2 - dist) * 0.3)
            } else {
                b.vy = min(b.vy + gravityG * 0.8 * dt, 18)
                b.vx *= (1.0 - min(1.0, dt * (d.onGround ? 6.0 : 0.6)))
            }
            if magnet {
                b.x += b.vx * dt
                b.y += b.vy * dt
            } else {
                world.moveBody(&b, dt, stepUp: 0, dropThrough: false, decks: decksCache)
                if b.inWater { b.vy = min(b.vy, 1.5); b.vx *= 0.9 }
            }
            d.x = b.x
            d.y = b.y
            d.vx = b.vx
            d.vy = b.vy
            d.onGround = b.onGround
            if !dead && d.pickDelay <= 0 && dist < 0.9 {
                let left: Int = inv.add(d.stack.item, d.stack.count, extra: d.stack.extra)
                if left < d.stack.count {
                    floatText("+" + String(d.stack.count - left) + " " + d.stack.item.name, px, pb.y - pb.h - 0.5, 0xFFF0A0)
                    bumpHUD()
                }
                if left == 0 {
                    drops.remove(at: i)
                    continue
                } else {
                    d.stack.count = left
                }
            }
            drops[i] = d
            i += 1
        }
    }

    // MARK: particles and floating text

    func updateParticles(_ dt: Double) {
        // compact in place: remove(at:) in a loop was O(n^2) when bursts of particles expired together
        let n: Int = particles.count
        var w: Int = 0
        particles.withUnsafeMutableBufferPointer { bp in
            var i: Int = 0
            while i < n {
                var p: Particle = bp[i]
                p.life -= dt
                if p.life > 0 {
                    p.vy += p.gravity * dt
                    p.x += p.vx * dt
                    p.y += p.vy * dt
                    bp[w] = p
                    w += 1
                }
                i += 1
            }
        }
        if w < n { particles.removeLast(n - w) }
        var j: Int = 0
        while j < floats.count {
            floats[j].life -= dt
            floats[j].y -= dt * 1.1
            if floats[j].life <= 0 { floats.remove(at: j); continue }
            j += 1
        }
    }
}

// ===== p16c_damage =====

// MARK: - Unified damage system
// Every source of harm (swings, projectiles, boss stomps, explosions, falling blocks, vehicles, lava,
// fire, spikes) builds a DamageInfo and goes through the same few functions. They decide who can be
// hurt (factions), stop one attack from hitting the same target every frame (per-attack cooldown
// keys), apply armor and resistances, push targets back, and remember who to credit for a kill.

enum DamageType: Int {
    case melee, projectile, explosion, fire, lava, impact, stomp, contact, fall, drown, starve, hazard, crush

    /// Armor does not help against these
    var bypassesArmor: Bool {
        switch self {
        case .fire, .lava, .fall, .drown, .starve: return true
        default: return false
        }
    }

    /// Area attacks hit everything in range (except their owner), including members of the attacker's
    /// own side. Aimed attacks never hurt the attacker's own side.
    var isArea: Bool {
        switch self {
        case .explosion, .stomp, .impact, .crush, .fire, .lava, .hazard: return true
        default: return false
        }
    }
}

enum Faction: Int {
    case player, ally, wild, hostile, pirate, umbral, boss, environment
}

enum SourceKind: Int {
    case player, mob, environment
}

struct DamageSource {
    var kind: SourceKind
    var id: Int
    var faction: Faction

    static let player: DamageSource = DamageSource(kind: .player, id: 0, faction: .player)
    static let environment: DamageSource = DamageSource(kind: .environment, id: -1, faction: .environment)
    static func mob(_ m: Mob, _ f: Faction) -> DamageSource { return DamageSource(kind: .mob, id: m.id, faction: f) }
}

struct DamageInfo {
    var amount: Double
    var type: DamageType
    var source: DamageSource
    /// knockback direction (-1 / 1); 0 = push away from the origin
    var dirX: Double = 0
    var knock: Double = 0
    var originX: Double = 0
    var originY: Double = 0
    /// attack instance id: the same key never hits the same target twice within `cooldown` seconds
    var key: Int = 0
    var cooldown: Double = 0.5

    init(amount: Double, type: DamageType, source: DamageSource) {
        self.amount = amount
        self.type = type
        self.source = source
    }
}

/// Bucketed mob positions, rebuilt once per frame, so area attacks and projectiles only look at
/// creatures near them instead of every mob in the world.
final class MobGrid {
    static let cell: Int = 8
    var buckets: [Int: [Mob]] = [:]

    func rebuild(_ mobs: [Mob]) {
        for k in buckets.keys { buckets[k]?.removeAll(keepingCapacity: true) }
        for m in mobs where m.hp > 0 && !m.removed {
            let k: Int = floorDiv(Int(floor(m.b.x)), MobGrid.cell)
            if buckets[k] == nil { buckets[k] = [] }
            buckets[k]?.append(m)
        }
        if buckets.count > 256 { buckets = buckets.filter { !$0.value.isEmpty } }
    }
}

func isHeatImmune(_ k: MobKind) -> Bool {
    switch k {
    case .imp, .emberSlime, .cinderBat: return true
    default: return false
    }
}

/// Fraction of damage a creature takes from a damage type (1 = full)
func damageResist(_ k: MobKind, _ t: DamageType) -> Double {
    switch (k, t) {
    case (.imp, .fire), (.emberSlime, .fire), (.cinderBat, .fire), (.imp, .lava), (.emberSlime, .lava), (.cinderBat, .lava): return 0
    case (.wraith, .fall), (.bat, .fall), (.cinderBat, .fall), (.crow, .fall): return 0
    case (.skeleton, .projectile): return 0.75
    case (.bearBoss, .lava), (.rex, .lava): return 0.5
    case (.bearBoss, .explosion), (.rex, .explosion): return 0.6
    case (.slime, .fall), (.emberSlime, .fall), (.cat, .fall), (.frog, .fall): return 0.2
    default: return 1
    }
}

/// Segment/box intersection (slab method). Returns the entry fraction along the segment, or nil.
func segmentBoxT(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ bx0: Double, _ by0: Double, _ bx1: Double, _ by1: Double) -> Double? {
    let dx: Double = x1 - x0
    let dy: Double = y1 - y0
    var tmin: Double = 0
    var tmax: Double = 1
    if abs(dx) < 1e-9 {
        if x0 < bx0 || x0 > bx1 { return nil }
    } else {
        var ta: Double = (bx0 - x0) / dx
        var tb: Double = (bx1 - x0) / dx
        if ta > tb { let s: Double = ta; ta = tb; tb = s }
        tmin = max(tmin, ta)
        tmax = min(tmax, tb)
        if tmin > tmax { return nil }
    }
    if abs(dy) < 1e-9 {
        if y0 < by0 || y0 > by1 { return nil }
    } else {
        var ta: Double = (by0 - y0) / dy
        var tb: Double = (by1 - y0) / dy
        if ta > tb { let s: Double = ta; ta = tb; tb = s }
        tmin = max(tmin, ta)
        tmax = min(tmax, tb)
        if tmin > tmax { return nil }
    }
    return tmin
}

extension World {
    /// First solid tile along a segment: (tile x, tile y, fraction along the segment)
    func segmentSolidT(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> (Int, Int, Double)? {
        let dx: Double = x1 - x0
        let dy: Double = y1 - y0
        let dist: Double = sqrt(dx * dx + dy * dy)
        let n: Int = max(1, Int(ceil(dist / 0.2)))
        var i: Int = 1
        while i <= n {
            let t: Double = Double(i) / Double(n)
            let tx: Int = Int(floor(x0 + dx * t))
            let ty: Int = Int(floor(y0 + dy * t))
            if tile(tx, ty).solid {
                // refine the entry point against the tile box
                let et: Double = segmentBoxT(x0, y0, x1, y1, Double(tx), Double(ty), Double(tx + 1), Double(ty + 1)) ?? t
                return (tx, ty, et)
            }
            i += 1
        }
        return nil
    }

    /// True when nothing solid blocks the straight line between two points
    func lineClear(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
        return segmentSolidT(x0, y0, x1, y1) == nil
    }
}

extension Game {
    // MARK: sides

    func faction(of m: Mob) -> Faction {
        if m.tame || m.kind == .villager { return .ally }
        switch m.kind {
        case .pirate, .pirateGunner, .pirateCaptain: return .pirate
        case .imp, .emberSlime, .cinderBat: return .umbral
        case .bearBoss, .rex: return .boss
        default: return m.def.hostile ? .hostile : .wild
        }
    }

    /// May `src` hurt a target of `targetFaction`?
    func canHarm(_ src: DamageSource, targetFaction tf: Faction, targetID: Int, area: Bool) -> Bool {
        // nothing hurts itself (the player's own bombs are the exception, handled in explode())
        if src.kind == .mob && src.id == targetID { return false }
        if src.kind == .player && tf == .player { return false }
        switch src.faction {
        case .environment, .boss: return true
        case .player: return tf != .ally
        case .ally: return tf != .player && tf != .ally
        default:
            if area { return true }
            return tf != src.faction
        }
    }

    // MARK: queries

    func mobsNear(_ x0: Double, _ x1: Double) -> [Mob] {
        Perf.shared.countDamage()
        let c0: Int = floorDiv(Int(floor(x0)), MobGrid.cell)
        let c1: Int = floorDiv(Int(floor(x1)), MobGrid.cell)
        if c1 - c0 > 64 { return mobs }
        var out: [Mob] = []
        var c: Int = c0
        while c <= c1 {
            if let b = mobGrid.buckets[c] { out.append(contentsOf: b) }
            c += 1
        }
        return out
    }

    // MARK: applying damage

    /// Damages a creature. Returns true if the hit landed.
    @discardableResult
    func applyMobDamage(_ m: Mob, _ info: DamageInfo) -> Bool {
        if m.hp <= 0 || m.removed { return false }
        if !canHarm(info.source, targetFaction: faction(of: m), targetID: m.id, area: info.type.isArea) { return false }
        if info.key != 0 {
            if let last = m.hitStamps[info.key], clock - last < info.cooldown { return false }
            m.hitStamps[info.key] = clock
            if m.hitStamps.count > 24 { m.hitStamps = m.hitStamps.filter { clock - $0.value < 4.0 } }
        }
        var amount: Double = info.amount * damageResist(m.kind, info.type)
        if info.source.kind == .player { amount *= dmgOutMult }
        if amount <= 0 { return false }
        let byPlayer: Bool = info.source.kind == .player
        if byPlayer { m.lastHitByPlayer = clock }
        m.lastAttacker = info.source.id
        var dir: Double = info.dirX
        if dir == 0 && info.knock > 0 { dir = m.b.x >= info.originX ? 1.0 : -1.0 }
        hurtMob(m, amount, dir, info.knock, byPlayer)
        return true
    }

    /// Damages the player. Returns true if the hit landed.
    @discardableResult
    func hurtPlayer(_ info: DamageInfo) -> Bool {
        if dead { return false }
        if !canHarm(info.source, targetFaction: .player, targetID: 0, area: info.type.isArea) && info.source.kind != .player { return false }
        if info.key != 0 {
            if let last = playerHitStamps[info.key], clock - last < info.cooldown { return false }
            playerHitStamps[info.key] = clock
            if playerHitStamps.count > 24 { playerHitStamps = playerHitStamps.filter { clock - $0.value < 4.0 } }
        }
        let before: Double = hp
        damagePlayer(info.amount * dmgInMult, from: info.originX, knock: info.knock, ignoreArmor: info.type.bypassesArmor)
        return hp < before
    }

    /// Hits everything (player and creatures) inside a box
    func damageBox(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ info: DamageInfo) {
        if !dead && pb.right > x0 && pb.left < x1 && pb.y > y0 && pb.top < y1 { _ = hurtPlayer(info) }
        for m in mobsNear(x0 - 4, x1 + 4) {
            if m.hp <= 0 { continue }
            if m.b.right > x0 && m.b.left < x1 && m.b.y > y0 && m.b.top < y1 { applyMobDamage(m, info) }
        }
    }

    /// Hits everything within `radius` of a point. With falloff, damage drops to 35% at the edge;
    /// with lineOfSight, targets behind solid blocks are spared.
    func damageArea(_ cx: Double, _ cy: Double, radius: Double, _ info: DamageInfo, falloff: Bool, lineOfSight: Bool) {
        func scaled(_ d: Double) -> DamageInfo {
            var i: DamageInfo = info
            if falloff { i.amount = info.amount * (1.0 - 0.65 * clampD(d / radius, 0, 1)) }
            i.knock = info.knock * (falloff ? (1.0 - 0.5 * clampD(d / radius, 0, 1)) : 1.0)
            i.originX = cx
            i.originY = cy
            return i
        }
        if !dead {
            let d: Double = boxDistance(cx, cy, pb.left, pb.top, pb.right, pb.y)
            if d <= radius && (!lineOfSight || world.lineClear(cx, cy, pb.x, pb.cy)) { _ = hurtPlayer(scaled(d)) }
        }
        for m in mobsNear(cx - radius - 4, cx + radius + 4) {
            if m.hp <= 0 { continue }
            let d: Double = boxDistance(cx, cy, m.b.left, m.b.top, m.b.right, m.b.y)
            if d > radius { continue }
            if lineOfSight && !world.lineClear(cx, cy, m.b.x, m.b.cy) { continue }
            applyMobDamage(m, scaled(d))
        }
    }

    func boxDistance(_ px: Double, _ py: Double, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Double {
        let dx: Double = max(0, max(x0 - px, px - x1))
        let dy: Double = max(0, max(y0 - py, py - y1))
        return sqrt(dx * dx + dy * dy)
    }

    // MARK: explosions

    func explode(_ x: Double, _ y: Double, radius: Double, power: Double, source: DamageSource, breakBlocks: Bool) {
        var info = DamageInfo(amount: power, type: .explosion, source: source)
        info.knock = 11.0
        info.key = newID()
        info.cooldown = 1.0
        damageArea(x, y, radius: radius, info, falloff: true, lineOfSight: true)
        // the thrower is not immune to their own bomb, but takes less
        if source.kind == .player && !dead {
            let d: Double = boxDistance(x, y, pb.left, pb.top, pb.right, pb.y)
            if d <= radius && world.lineClear(x, y, pb.x, pb.cy) {
                damagePlayer(power * 0.45 * (1.0 - 0.65 * clampD(d / radius, 0, 1)), from: x, knock: 9.0)
            }
        }
        if breakBlocks {
            let r: Int = Int(ceil(radius * 0.7))
            let tx: Int = Int(floor(x))
            let ty: Int = Int(floor(y))
            for dy in -r...r {
                for dx in -r...r {
                    let dd: Double = Double(dx * dx + dy * dy)
                    if dd > radius * radius * 0.5 { continue }
                    let t: Tile = world.tile(tx + dx, ty + dy)
                    if t == .air || t.liquid || t.hardness > 2.7 || Tile.tierTable[t.idx] > 4 { continue }
                    if t == .chest || t == .portalOff || t == .portalOn || t == .portalFrame { continue }
                    breakTile(tx + dx, ty + dy, false, dropChance: 0.35)
                }
            }
        }
        for s in ships where abs(s.x - x) < radius + 4.5 && abs(s.deckY(Double(WorldGen.sea)) - y) < radius + 2 {
            s.hp -= power
            s.hitT = 0.3
        }
        spawnParticles(x, y, 0xFFC050, 18, 8.0, 0.5, 2)
        spawnParticles(x, y, 0x606060, 12, 4.0, 1.0, -3)
        addShake(0.6)
    }

    // MARK: hazards for creatures

    /// Lava, fire, spikes, cactus and fall damage for every creature, through the same damage path
    /// as everything else. Hazards are timed (not per frame) and resistances apply.
    func mobHazards(_ m: Mob, _ dt: Double) {
        if m.removed || m.downed { return }
        if m.hazardT > 0 { m.hazardT -= dt }
        let hw: Double = m.b.w * 0.5
        let x0: Double = m.b.x - hw
        let x1: Double = m.b.x + hw
        let heatImmune: Bool = isHeatImmune(m.kind)
        // lava: check the body and the feet row (fast movers can graze it in one frame)
        let inLava: Bool = world.liquidFraction(x0, m.b.top, x1, m.b.y + 0.05, true) > 0.04 || m.b.inLava
        if inLava && !heatImmune {
            m.burn = max(m.burn, 3.0)
            if m.hazardT <= 0 {
                m.hazardT = 0.35
                var info = DamageInfo(amount: m.isBoss ? 14 : 6, type: .lava, source: .environment)
                info.originX = m.b.x
                applyMobDamage(m, info)
                if m.hp > 0 && !m.def.flying { m.b.vy = min(m.b.vy, -7.0) }
            }
        }
        // burning
        if m.burn > 0 {
            if heatImmune || m.b.inWater {
                m.burn = 0
            } else {
                m.burn -= dt
                m.burnTick += dt
                if m.burnTick >= 0.5 {
                    m.burnTick = 0
                    var info = DamageInfo(amount: m.isBoss ? 3 : 2, type: .fire, source: .environment)
                    info.originX = m.b.x
                    applyMobDamage(m, info)
                    spawnParticles(m.b.x, m.b.y - m.b.h * 0.7, 0xFF8030, 2, 1.5, 0.4, -4)
                }
            }
        }
        // spikes, cactus, campfires
        if !m.def.flying && m.hazardT <= 0 {
            if let t = world.boxHurts(x0 + 0.05, m.b.y - 0.6, x1 - 0.05, m.b.y + 0.05) ?? world.boxHurts(x0 - 0.02, m.b.top + 0.1, x1 + 0.02, m.b.y - 0.1) {
                if t == .spikes || t == .cactus {
                    m.hazardT = 0.6
                    var info = DamageInfo(amount: t == .spikes ? 5 : 2, type: .hazard, source: .environment)
                    info.originX = m.b.x - Double(m.dir)
                    info.knock = 3.0
                    applyMobDamage(m, info)
                }
            }
            let fx: Int = Int(floor(m.b.x))
            let fy: Int = Int(floor(m.b.y - 0.5))
            if world.tile(fx, fy) == .campfire && !heatImmune { m.burn = max(m.burn, 2.0) }
        }
        // falling (knockback off a ledge counts too)
        if !m.def.flying && m.kind != .fish {
            if !m.b.onGround && m.b.vy > 0 && !m.b.inWater { m.fallPeak = max(m.fallPeak, m.b.vy) }
            if m.b.onGround || m.b.inWater {
                if m.fallPeak > 23.0 && !m.b.inWater && !m.isBoss {
                    var info = DamageInfo(amount: (m.fallPeak - 21.0) * 1.5, type: .fall, source: .environment)
                    info.originX = m.b.x
                    applyMobDamage(m, info)
                }
                m.fallPeak = 0
            }
        }
    }

    /// Dead creatures topple, fall and fade out for a moment before they are removed
    func updateDying(_ dt: Double) {
        for m in mobs where m.hp <= 0 && !m.removed {
            if m.deathT < 0 { m.deathT = 0 }
            m.deathT += dt
            if !m.def.flying || m.deathT > 0.1 {
                m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
                m.b.vx *= (1.0 - min(1.0, dt * 4.0))
                if m.deathT < 0.8 { world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: []) }
            }
            if m.deathT > 0.7 { m.removed = true }
        }
    }

    // MARK: player fire

    func updatePlayerBurn(_ dt: Double) {
        if playerBurn <= 0 { return }
        if pb.inWater || mode == .creative { playerBurn = 0; return }
        playerBurn -= dt
        playerBurnTick += dt
        if playerBurnTick >= 0.6 {
            playerBurnTick = 0
            var info = DamageInfo(amount: 1, type: .fire, source: .environment)
            info.originX = pb.x
            _ = hurtPlayer(info)
            spawnParticles(pb.x, pb.y - 1.2, 0xFF8030, 2, 1.5, 0.4, -4)
        }
    }

    // MARK: falling blocks

    /// Sand with nothing under it falls; it hurts whatever it lands on
    func checkFalling(_ x: Int, _ y: Int) {
        var yy: Int = y
        var n: Int = 0
        while n < 16 && world.tile(x, yy) == .sand {
            let below: Tile = world.tile(x, yy + 1)
            if below.solid || below.isPlatform { break }
            world.set(x, yy, .air)
            fallingBlocks.append(FallingBlock(x: Double(x) + 0.5, y: Double(yy) + 1.0, vy: 0, tile: .sand, uid: newID()))
            yy -= 1
            n += 1
        }
    }

    func updateFallingBlocks(_ dt: Double) {
        if fallingBlocks.isEmpty { return }
        var keep: [FallingBlock] = []
        for fb0 in fallingBlocks {
            var fb: FallingBlock = fb0
            fb.vy = min(fb.vy + gravityG * dt, terminalV)
            let ny: Double = fb.y + fb.vy * dt
            // crush whatever is underneath while moving fast enough
            if fb.vy > 4.0 {
                var info = DamageInfo(amount: 2.0 + fb.vy * 0.4, type: .crush, source: .environment)
                info.originX = fb.x
                info.originY = fb.y - 1.0
                info.key = fb.uid
                info.cooldown = 5.0
                damageBox(fb.x - 0.45, fb.y - 1.0, fb.x + 0.45, ny, info)
            }
            let tx: Int = Int(floor(fb.x))
            let landRow: Int = Int(floor(ny))
            if world.tile(tx, landRow).solid || world.tile(tx, landRow).isPlatform || landRow >= world.H - 2 {
                let restY: Int = landRow - 1
                let cur: Tile = world.tile(tx, restY)
                if cur == .air || cur.liquid || cur.isPlant {
                    world.set(tx, restY, fb.tile)
                } else {
                    spawnDrop(Stack(item: .block(fb.tile), count: 1), fb.x, Double(restY), 0, -2)
                }
                spawnParticles(fb.x, Double(landRow), 0xE0D08A, 4, 2.0, 0.3, 10)
                continue
            }
            fb.y = ny
            keep.append(fb)
        }
        fallingBlocks = keep
    }
}

struct FallingBlock {
    var x: Double
    var y: Double
    var vy: Double
    var tile: Tile
    var uid: Int
}

// ===== p16b_bosses =====

// MARK: - Bosses (giant bear, T-rex), rex companion

enum BossAtk: Int {
    case melee, sweep, charge, slam, roar
}

extension Game {
    func lairKey(_ L: LairInfo) -> Int {
        return L.kind.rawValue * 1_000_000 + (L.k + 500_000)
    }

    func updateBosses(_ dt: Double) {
        if world.dim != .overworld {
            activeBoss = nil
            return
        }
        let px: Int = Int(floor(pb.x))
        for L in gen.lairCenters(near: px) {
            let key: Int = lairKey(L)
            if defeated.contains(key) { continue }
            let dist: Double = abs(Double(L.cx) - pb.x)
            var existing: Mob? = nil
            for m in mobs where m.isBoss && m.lair == key { existing = m }
            if dist < 90 && existing == nil && world.isLoaded(L.cx) && !dead {
                spawnBoss(L, key)
            } else if dist > 180, let e = existing {
                e.hp = 0
                mobs.removeAll { $0 === e }
            }
        }
        var best: Mob? = nil
        var bd: Double = 70
        for m in mobs where m.isBoss && m.hp > 0 {
            let d: Double = abs(m.b.x - pb.x)
            if d < bd { bd = d; best = m }
        }
        activeBoss = best
        if let b = best {
            bossBarName = b.def.name
            bossBarFrac = clampD(b.hp / b.maxHP, 0, 1)
        }
        // companion housekeeping
        if let r = rex, r.hp <= 0 && !r.downed { rex = nil }
    }

    func spawnBoss(_ L: LairInfo, _ key: Int) {
        let kind: MobKind = L.kind == .bear ? .bearBoss : .rex
        let floorY: Double = Double(lairFloorRow())
        let m: Mob = addMob(kind, Double(L.cx) + 0.5, floorY)
        m.lair = key
        m.homeX = Double(L.cx)
        m.homeY = floorY
        m.st = 3
        m.t2 = 1.5
        m.t1 = 2.0
        m.phase = 1
        m.persistent = true
        m.dir = pb.x >= m.b.x ? 1 : -1
        say(m.def.name + " awakens!", 3.5)
    }

    func updateBossMob(_ m: Mob, _ dt: Double) {
        if m.kind == .rex && m.tame {
            updateRexCompanion(m, dt)
            return
        }
        bossBrain(m, dt)
    }

    // MARK: boss attack machine

    func bossBrain(_ m: Mob, _ dt: Double) {
        let isBear: Bool = m.kind == .bearBoss
        let hpf: Double = m.hp / m.maxHP
        let newPhase: Int = hpf < 0.5 ? 2 : 1
        if newPhase != m.phase {
            m.phase = newPhase
            if newPhase == 2 {
                m.st = 1
                m.atk = BossAtk.roar.rawValue
                m.t2 = 1.3
                say(m.def.name + " flies into a rage!", 3.0)
            }
        }
        let enrage: Bool = hpf < 0.25
        let toP: Double = pb.x - m.b.x
        let dist: Double = abs(toP)
        let dirP: Int = toP >= 0 ? 1 : -1
        let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
        let sp: Double = m.def.speed * (m.phase == 2 ? 1.25 : 1.0) * (enrage ? 1.15 : 1.0)
        if dead {
            accelX(m, 0, 20, dt)
            m.st = 0
            stepMob(m, dt, stepUp: 2.0)
            return
        }
        switch m.st {
        case 0:
            m.dir = dirP
            if dist > (isBear ? 2.6 : 3.8) {
                accelX(m, Double(dirP) * sp, 16, dt)
            } else {
                accelX(m, 0, 30, dt)
            }
            if abs(m.b.x - m.homeX) > 33 && (m.b.x - m.homeX) * Double(dirP) > 0 { accelX(m, 0, 40, dt) }
            if m.b.hitWall && m.b.onGround { m.b.vy = -12 }
            m.t1 -= dt
            if dist < (isBear ? 3.4 : 4.6) && abs(dyP) < 2.8 { contactHurt(m, m.def.dmg * 0.45) }
            if m.t1 <= 0 { chooseAttack(m, dist) }
        case 1:
            accelX(m, 0, 40, dt)
            if m.t2 > 0.25 { m.dir = dirP }
            m.tele = m.t2
            m.t2 -= dt
            if m.atk == BossAtk.charge.rawValue && Double.random(in: 0...1) < 0.5 {
                spawnParticles(m.b.x + Double(m.dir) * 1.5, m.b.y, 0xA08860, 1, 3.0, 0.4, 6)
            }
            if m.atk == BossAtk.roar.rawValue { shake = max(shake, 0.1) }
            if m.t2 <= 0 { beginAttack(m) }
        case 2:
            runAttack(m, dt)
        case 3:
            accelX(m, 0, 30, dt)
            m.tele = 0
            m.t2 -= dt
            if m.t2 <= 0 {
                m.st = 0
                m.t1 = m.phase == 2 ? Double.random(in: 0.8...1.6) : Double.random(in: 1.4...2.6)
            }
        case 4:
            accelX(m, 0, 30, dt)
            m.t2 -= dt
            if m.t2 <= 0 { m.st = 0; m.t1 = 0.9 }
        default:
            m.st = 0
        }
        stepMob(m, dt, stepUp: 2.0)
    }

    func chooseAttack(_ m: Mob, _ dist: Double) {
        let isBear: Bool = m.kind == .bearBoss
        var opts: [(BossAtk, Double)] = []
        if dist < (isBear ? 6.5 : 8.5) {
            opts.append((.melee, 5))
            if !isBear { opts.append((.sweep, 3)) }
            opts.append((.slam, 2.5))
            opts.append((.charge, 1.5))
        } else {
            opts.append((.charge, 5))
            opts.append((.slam, 3))
            opts.append((.melee, 1))
            if m.phase == 2 { opts.append((.roar, 2)) }
        }
        var total: Double = 0
        for o in opts { total += o.1 }
        var r: Double = Double.random(in: 0..<total)
        var pick: BossAtk = .melee
        for o in opts {
            r -= o.1
            if r <= 0 { pick = o.0; break }
        }
        m.atk = pick.rawValue
        m.st = 1
        var tt: Double = 0.9
        switch pick {
        case .melee: tt = isBear ? 0.95 : 0.8
        case .sweep: tt = 0.75
        case .charge: tt = 1.05
        case .slam: tt = 0.95
        case .roar: tt = 1.3
        }
        if m.phase == 2 { tt *= 0.8 }
        m.t2 = tt
        m.dir = pb.x >= m.b.x ? 1 : -1
    }

    func beginAttack(_ m: Mob) {
        m.st = 2
        m.t3 = 0
        m.tele = 0
        m.knock = 0
        let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
        switch a {
        case .melee: m.t2 = 0.4
        case .sweep: m.t2 = 0.35
        case .charge: m.t2 = 1.6
        case .slam:
            m.t2 = 2.4
            m.b.vy = -17.0
            m.tx = pb.x
            m.t3 = 0
        case .roar:
            m.t2 = 3.2
            m.ty = 0
            shake = max(shake, 0.35)
        }
    }

    func runAttack(_ m: Mob, _ dt: Double) {
        let isBear: Bool = m.kind == .bearBoss
        let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
        m.t2 -= dt
        switch a {
        case .melee:
            accelX(m, Double(m.dir) * (isBear ? 0.0 : 6.0), 30, dt)
            if m.t3 == 0 {
                let reach: Double = isBear ? 5.6 : 7.6
                let fx0: Double = m.dir > 0 ? m.b.x - 0.5 : m.b.x - reach
                let fx1: Double = m.dir > 0 ? m.b.x + reach : m.b.x + 0.5
                var info = DamageInfo(amount: m.def.dmg, type: .melee, source: .mob(m, .boss))
                info.dirX = Double(m.dir)
                info.knock = 10.0
                info.originX = m.b.x
                info.key = newID()
                damageBox(fx0, m.b.top - 0.5, fx1, m.b.y + 0.2, info)
                addShake(0.3)
                m.t3 = 1
                spawnParticles(m.b.x + Double(m.dir) * (reach * 0.6), m.b.y - 1.6, 0xE8E0D0, 6, 5.0, 0.3, 4)
            }
            if m.t2 <= 0 { m.st = 3; m.t2 = 0.8 }
        case .sweep:
            accelX(m, 0, 30, dt)
            if m.t3 == 0 {
                var info = DamageInfo(amount: m.def.dmg * 0.75, type: .stomp, source: .mob(m, .boss))
                info.knock = 11.0
                info.originX = m.b.x
                info.key = newID()
                damageBox(m.b.x - 7.0, m.b.y - 2.0, m.b.x + 7.0, m.b.y + 0.3, info)
                m.t3 = 1
                addShake(0.25)
                spawnParticles(m.b.x - Double(m.dir) * 4.5, m.b.y - 0.4, 0xA08860, 8, 5.0, 0.4, 6)
            }
            if m.t2 <= 0 { m.st = 3; m.t2 = 0.8 }
        case .charge:
            let spd: Double = (isBear ? 13.0 : 11.5) * (m.phase == 2 ? 1.15 : 1.0)
            m.b.vx = Double(m.dir) * spd
            if Double.random(in: 0...1) < 0.7 { spawnParticles(m.b.x - Double(m.dir) * 2.0, m.b.y, 0xA08860, 1, 3.0, 0.4, 6) }
            // the charge tramples everything in its path, one hit per target
            var info = DamageInfo(amount: m.def.dmg * 1.3, type: .impact, source: .mob(m, .boss))
            info.dirX = Double(m.dir)
            info.knock = 13.0
            info.originX = m.b.x
            info.key = m.id &* 1000 &+ Int(m.t2 > 0 ? 1 : 0) &+ m.atk
            info.cooldown = 1.2
            damageBox(m.b.left - 0.1, m.b.top, m.b.right + 0.1, m.b.y + 0.1, info)
            if m.b.hitWall {
                m.st = 4
                m.t2 = 1.8
                m.b.vx = 0
                shake = 0.6
                spawnParticles(m.b.x + Double(m.dir) * 2.5, m.b.y - 2.0, 0x9A9A9A, 20, 6.0, 0.7, 18)
                rainRocks(m, 3)
            } else if m.t2 <= 0 {
                m.st = 3
                m.t2 = 0.9
            }
        case .slam:
            if !m.b.onGround { m.t3 = 1 }
            let flight: Double = 0.95
            if m.t3 == 0 || !m.b.onGround {
                let target: Double = clampD(m.tx, m.homeX - 33, m.homeX + 33)
                m.b.vx = clampD((target - m.b.x) / flight, -11, 11)
            }
            if m.b.onGround && m.t3 == 1 {
                shake = 0.7
                spawnParticles(m.b.x, m.b.y, 0xA08860, 24, 7.0, 0.6, 10)
                let sp: Double = isBear ? 9.0 : 8.0
                for sgn in [-1.0, 1.0] {
                    var p = Projectile(kind: .shock, x: m.b.x + sgn * (m.b.w * 0.5), y: m.b.y - 0.5, vx: sgn * sp, vy: 0, dmg: m.def.dmg * 0.8, fromPlayer: false, gravity: 0)
                    p.life = 3.0
                    p.w = 0.6
                    p.source = .mob(m, .boss)
                    p.uid = newID()
                    projectiles.append(p)
                }
                // the landing itself: everything under and right beside the body
                var info = DamageInfo(amount: m.def.dmg, type: .stomp, source: .mob(m, .boss))
                info.knock = 9.0
                info.originX = m.b.x
                info.key = newID()
                damageArea(m.b.x, m.b.y - 0.5, radius: m.b.w * 0.5 + 1.2, info, falloff: true, lineOfSight: false)
                m.st = 3
                m.t2 = 1.0
                m.b.vx = 0
            } else if m.t2 <= 0 {
                m.st = 3
                m.t2 = 0.8
            }
        case .roar:
            accelX(m, 0, 30, dt)
            shake = max(shake, 0.15)
            m.ty -= dt
            if m.ty <= 0 {
                m.ty = 0.42
                rainRocks(m, 1)
            }
            if m.t2 <= 0 { m.st = 3; m.t2 = 1.0 }
        }
    }

    func rainRocks(_ m: Mob, _ n: Int) {
        for _ in 0..<n {
            let rx: Double = clampD(pb.x + Double.random(in: -9...9), m.homeX - 36, m.homeX + 36)
            var p = Projectile(kind: .rock, x: rx, y: m.b.y - 17.0, vx: 0, vy: 0, dmg: 16, fromPlayer: false, gravity: 26)
            p.life = 5.0
            p.w = 0.9
            // falling rocks hurt anyone underneath, the boss's own minions included
            p.source = .mob(m, .boss)
            p.uid = newID()
            projectiles.append(p)
            spawnParticles(rx, m.b.y - 0.3, 0x8A8A8A, 2, 1.0, 0.8, 0)
        }
    }

    // MARK: rewards

    func onBearDefeated(_ m: Mob) {
        defeated.insert(m.lair)
        shake = 0.8
        spawnDrop(Stack(item: .gadget(.portalKey), count: 1), m.b.x, m.b.y - 2.0, 0, -6.0)
        spawnDrop(Stack(item: .gadget(.treasureMap), count: 1), m.b.x + 0.8, m.b.y - 2.0, 1.0, -6.0)
        gotMap = true
        say(m.def.name + " has fallen! It dropped a Portal Key and a Treasure Map.", 6.0)
        spawnParticles(m.b.x, m.b.cy, 0xFFE070, 40, 9.0, 1.2, 8)
    }

    func onRexDefeated(_ m: Mob) {
        defeated.insert(m.lair)
        shake = 0.8
        spawnParticles(m.b.x, m.b.cy, 0xFFE070, 40, 9.0, 1.2, 8)
        if rex == nil {
            m.tame = true
            m.persistent = true
            m.maxHP = 700
            m.hp = 420
            m.downed = false
            m.st = 0
            m.phase = 1
            m.lair = 0
            rex = m
            say(m.def.name + " bows its head. It will follow you now. Tap it to ride!", 6.0)
        } else {
            say(m.def.name + " has fallen!", 4.0)
        }
    }

    // MARK: companion

    func downRex(_ m: Mob) {
        m.downed = true
        m.hp = 1
        m.t1 = 40
        m.mounted = false
        if mounted === m {
            dismount()
        }
        floatText("Tyrannax is down!", m.b.x, m.b.top - 0.5, 0xFF6060)
        say("Tyrannax collapsed. It will recover in a moment.", 3.0)
    }

    func nearestGround(_ x: Double, _ y: Double) -> Double {
        let ix: Int = Int(floor(x))
        var yy: Int = Int(floor(y)) - 8
        var n: Int = 0
        while n < 40 {
            if world.solid(ix, yy) { return Double(yy) }
            yy += 1
            n += 1
        }
        return y
    }

    func teleportRexNearPlayer(_ m: Mob) {
        let side: Double = Double(-facing)
        var x: Double = pb.x + side * 6.0
        if !world.isLoaded(Int(floor(x))) { x = pb.x }
        // find a free spot big enough
        var y: Double = pb.y
        var tries: Int = 0
        while tries < 4 && world.boxSolid(x - m.b.w * 0.5, y - m.b.h, x + m.b.w * 0.5, y - 0.05) {
            x = pb.x + side * (6.0 + Double(tries) * 3.0)
            y = nearestGround(x, pb.y - 6.0)
            tries += 1
        }
        if world.boxSolid(x - m.b.w * 0.5, y - m.b.h, x + m.b.w * 0.5, y - 0.05) {
            // carve space if the area is blocked
            let x0: Int = Int(floor(x - m.b.w * 0.5))
            let x1: Int = Int(ceil(x + m.b.w * 0.5))
            let y0: Int = Int(floor(y - m.b.h))
            let y1: Int = Int(ceil(y)) - 1
            for tx in x0...x1 { for ty in y0...y1 { if world.tile(tx, ty).solid && world.tile(tx, ty).def.hard < 9000 { world.set(tx, ty, .air) } } }
        }
        m.b.x = x
        m.b.y = y
        m.b.vx = 0
        m.b.vy = 0
        m.stuckT = 0
        m.lastX = x
    }

    func updateRexCompanion(_ m: Mob, _ dt: Double) {
        if m.downed {
            m.t1 -= dt
            m.b.vx = 0
            m.b.vy = min(m.b.vy + gravityG * dt, terminalV)
            world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
            if m.t1 <= 0 {
                m.downed = false
                m.hp = m.maxHP * 0.5
                floatText("Tyrannax rises!", m.b.x, m.b.top - 0.5, 0x80FF80)
            }
            return
        }
        if mounted === m { return }
        m.hp = min(m.maxHP, m.hp + dt * 1.2)
        let toP: Double = pb.x - m.b.x
        let dist: Double = abs(toP)
        if dist > 70 || abs(pb.y - m.b.y) > 40 || m.stuckT > 4.0 {
            if dist > 12 || abs(pb.y - m.b.y) > 6 { teleportRexNearPlayer(m) }
            m.stuckT = 0
        }
        var target: Mob? = nil
        if !dead { target = nearestHostileTo(m.b.x, m.b.cy, 13.0) }
        if let t = target, t.hp > 0, !t.isBoss {
            let dx: Double = t.b.x - m.b.x
            m.dir = dx >= 0 ? 1 : -1
            if abs(dx) > 4.2 { accelX(m, Double(m.dir) * 5.5, 22, dt) } else { accelX(m, 0, 30, dt) }
            if m.cd <= 0 && abs(dx) < 5.6 && abs(t.b.cy - m.b.cy) < 3.5 {
                m.st = 2
                m.t2 = 0.3
                m.cd = 1.1
                hurtMob(t, 28, Double(m.dir), 9.0, true)
            }
        } else if dist > 7.5 {
            m.dir = toP >= 0 ? 1 : -1
            let sp: Double = dist > 25 ? 11.0 : 6.0
            accelX(m, Double(m.dir) * sp, 24, dt)
        } else {
            accelX(m, 0, 24, dt)
            if dist > 1 { m.dir = toP >= 0 ? 1 : -1 }
        }
        if m.st == 2 {
            m.t2 -= dt
            if m.t2 <= 0 { m.st = 0 }
        }
        if m.b.hitWall && m.b.onGround { m.b.vy = -16.0 }
        // stuck detection
        m.t3 += dt
        if m.t3 >= 0.5 {
            m.t3 = 0
            let moved: Double = abs(m.b.x - m.lastX)
            m.lastX = m.b.x
            if moved < 0.15 && abs(m.b.vx) > 0.5 && dist > 8 { m.stuckT += 0.5 } else if moved >= 0.15 { m.stuckT = 0 }
        }
        stepMob(m, dt, stepUp: 2.0)
    }

    func mountRex(_ m: Mob) {
        if m.downed { say("Tyrannax is recovering.", 2.0); return }
        if inVehicle != nil { return }
        if abs(m.b.x - pb.x) > 9 || abs(m.b.y - pb.y) > 8 { say("Get closer to ride.", 2.0); return }
        mounted = m
        m.mounted = true
        pb.vx = 0
        pb.vy = 0
        say("Riding Tyrannax. Bite attacks are automatic!", 2.5)
        bumpHUD()
    }

    func rideRex(_ r: Mob, _ ix: Double, _ jumpPressed: Bool, _ dt: Double) {
        if r.downed || r.hp <= 0 {
            dismount()
            return
        }
        if ix != 0 { r.dir = ix > 0 ? 1 : -1 }
        let target: Double = ix * 10.0
        accelX(r, target, 40, dt)
        if jumpPressed && r.b.onGround { r.b.vy = -19.0 }
        if r.cd > 0 { r.cd -= dt }
        if r.st == 2 {
            r.t2 -= dt
            if r.t2 <= 0 { r.st = 0 }
        }
        // auto bite
        if r.cd <= 0 {
            var bestM: Mob? = nil
            var bd: Double = 6.5
            for o in mobs {
                if o === r || o.hp <= 0 || o.tame || o.kind == .villager { continue }
                let dx: Double = (o.b.x - r.b.x) * Double(r.dir)
                if dx < -1.0 { continue }
                let d: Double = abs(o.b.x - r.b.x) - o.b.w * 0.5
                if d < bd && abs(o.b.cy - r.b.cy) < 3.8 && (!o.isBoss || true) { bd = d; bestM = o }
            }
            if let t = bestM {
                hurtMob(t, 26, Double(r.dir), 9.0, true)
                r.st = 2
                r.t2 = 0.3
                r.cd = 0.9
            }
        }
        stepMob(r, dt, stepUp: 2.0)
        pb.x = r.b.x - Double(r.dir) * 0.5
        pb.y = r.b.y - 3.4
        pb.vx = 0
        pb.vy = 0
        facing = r.dir
        fallPeak = 0
        walkAnim += dt * 2
    }

    func dismount() {
        if let r = mounted {
            r.mounted = false
            pb.x = r.b.x + Double(-r.dir) * 1.5
            pb.y = r.b.y
            pb.vx = 0
            pb.vy = 0
            mounted = nil
            invuln = max(invuln, 0.5)
        }
        if let v = inVehicle {
            v.rider = false
            v.throttle = 0
            pb.x = v.b.x
            pb.y = v.b.y - v.b.h - 0.1
            pb.vx = 0
            pb.vy = 0
            inVehicle = nil
        }
        bumpHUD()
    }
}

// ===== p17_vehicles_ships =====

// MARK: - Vehicle driving and rigid-body physics

/// One collision sample on a vehicle part: where it is on the part (vehicle space) and whether it
/// belongs to a wheel (wheels roll and push; everything else slides with friction)
struct VSample {
    var lx: Double
    var ly: Double
    var wheel: Bool
}

extension Game {
    func updateVehicles(_ dt: Double) {
        let t0: Double = perfNow()
        for v in vehicles { stepVehicle(v, dt) }
        separateVehicles()
        Perf.shared.physMs = Perf.smooth(Perf.shared.physMs, perfNow() - t0)
    }

    func seatCell(_ v: Vehicle) -> PartCell? {
        for (c, t) in v.parts where t == .seat { return c }
        return nil
    }

    /// Collision samples: the four corners and edge midpoints of square parts; a ring for wheels
    func vehicleSamples(_ v: Vehicle) -> [VSample] {
        var out: [VSample] = []
        out.reserveCapacity(v.parts.count * 8)
        for (c, t) in v.parts {
            let x0: Double = Double(c.dx)
            let y0: Double = Double(c.dy)
            if t == .wheel {
                var k: Int = 0
                while k < 10 {
                    let a: Double = Double(k) / 10.0 * 2.0 * Double.pi
                    out.append(VSample(lx: x0 + 0.5 + cos(a) * 0.47, ly: y0 + 0.5 + sin(a) * 0.47, wheel: true))
                    k += 1
                }
            } else {
                let pts: [(Double, Double)] = [(0.02, 0.02), (0.5, 0.0), (0.98, 0.02), (1.0, 0.5), (0.98, 0.98), (0.5, 1.0), (0.02, 0.98), (0.0, 0.5)]
                for p in pts {
                    // only outer edges can touch the world
                    let nx: Int = p.0 < 0.25 ? -1 : (p.0 > 0.75 ? 1 : 0)
                    let ny: Int = p.1 < 0.25 ? -1 : (p.1 > 0.75 ? 1 : 0)
                    let openX: Bool = nx == 0 || v.parts[PartCell(dx: c.dx + nx, dy: c.dy)] == nil
                    let openY: Bool = ny == 0 || v.parts[PartCell(dx: c.dx, dy: c.dy + ny)] == nil
                    if openX || openY { out.append(VSample(lx: x0 + p.0, ly: y0 + p.1, wheel: false)) }
                }
            }
        }
        return out
    }

    /// How far a point is inside solid ground and which way is out (the exposed face it is nearest).
    /// For wheels, the top corner of a block with open space above acts like a ramp, so cars roll up
    /// one-block steps and block "stairs" instead of jamming against them.
    func penetration(_ x: Double, _ y: Double, wheel: Bool = false) -> (Double, Double, Double)? {
        let tx: Int = Int(floor(x))
        let ty: Int = Int(floor(y))
        if !world.tile(tx, ty).solid { return nil }
        var best: Double = 9
        var nx: Double = 0
        var ny: Double = -1
        let up: Double = y - Double(ty)
        let down: Double = Double(ty + 1) - y
        let left: Double = x - Double(tx)
        let right: Double = Double(tx + 1) - x
        let topOpen: Bool = !world.tile(tx, ty - 1).solid
        if wheel && topOpen && up < 0.8 {
            let leftOpen: Bool = !world.tile(tx - 1, ty).solid
            let rightOpen: Bool = !world.tile(tx + 1, ty).solid
            if leftOpen && left < up { return (up * 0.75, -0.6, -0.8) }
            if rightOpen && right < up { return (up * 0.75, 0.6, -0.8) }
            return (up, 0, -1)
        }
        // prefer resting on top over catching on a side when barely inside
        if topOpen && up < 0.3 { return (up, 0, -1) }
        if topOpen && up < best { best = up; nx = 0; ny = -1 }
        if !world.tile(tx - 1, ty).solid && left < best { best = left; nx = -1; ny = 0 }
        if !world.tile(tx + 1, ty).solid && right < best { best = right; nx = 1; ny = 0 }
        if !world.tile(tx, ty + 1).solid && down < best { best = down; nx = 0; ny = 1 }
        if best > 8 { best = up; nx = 0; ny = -1 }
        return (best, nx, ny)
    }

    func stepVehicle(_ v: Vehicle, _ dt: Double) {
        if !world.isLoaded(Int(floor(v.px))) { return }
        let throttle: Double = v.rider ? v.throttle : 0
        if v.asleep && abs(throttle) < 0.05 && !v.drilling {
            // resting vehicles cost nothing until something wakes them
            if world.boxSolid(v.b.left + 0.05, v.b.y + 0.02, v.b.right - 0.05, v.b.y + 0.2) || v.submerged > 0 { return }
        }
        v.asleep = false
        let steerOK: Bool = v.hasSeat && v.hasSteering
        let hasFuel: Bool = v.fuel > 0 || isCreative
        let samples: [VSample] = vehicleSamples(v)
        let maxSpeed: Double = v.speed + abs(v.angVel) * 3.0
        let steps: Int = clampI(Int(ceil(maxSpeed * dt / 0.22)), 2, 10)
        let h: Double = dt / Double(steps)
        let invM: Double = 1.0 / v.mass
        let invI: Double = 1.0 / v.inertia
        var wheelHits: Int = 0
        var anyHits: Int = 0
        var subFrac: Double = 0
        var rammed: [(Int, Int)] = []
        for _ in 0..<steps {
            // gravity
            v.vy += gravityG * h
            let c: Double = v.cosA
            let s: Double = v.sinA
            // buoyancy and water drag, part by part (so boats tilt and settle naturally)
            var wetParts: Int = 0
            for (cell, t) in v.parts {
                let lx: Double = Double(cell.dx) + 0.5 - v.comX
                let ly: Double = Double(cell.dy) + 0.5 - v.comY
                let wx: Double = v.px + lx * c - ly * s
                let wy: Double = v.py + lx * s + ly * c
                var wet: Double = 0
                if world.tile(Int(floor(wx)), Int(floor(wy - 0.3))) == .water { wet += 0.5 }
                if world.tile(Int(floor(wx)), Int(floor(wy + 0.3))) == .water { wet += 0.5 }
                if wet <= 0 { continue }
                wetParts += 1
                let up: Double = gravityG * (partVolume(t) * 0.92 + 0.15) * wet
                let rx: Double = wx - v.px
                let ry: Double = wy - v.py
                // buoyant force (upward) at the part, plus drag against the part's velocity
                let pvx: Double = v.vx - v.angVel * ry
                let pvy: Double = v.vy + v.angVel * rx
                let fx: Double = -pvx * 1.6 * wet
                let fy: Double = -up - pvy * 4.0 * wet
                v.vx += fx * invM * h
                v.vy += fy * invM * h
                v.angVel += (rx * fy - ry * fx) * invI * h
            }
            subFrac = Double(wetParts) / Double(max(1, v.parts.count))
            // boat propulsion along the hull
            if wetParts > 0 && steerOK && abs(throttle) > 0.1 {
                var thrust: Double = 0
                var vmax: Double = 0
                if v.engines > 0 && v.propellers > 0 && hasFuel {
                    thrust = Double(v.engines) * 18.0
                    vmax = min(11.0, 4.5 + 2.0 * Double(v.engines))
                } else if v.paddles > 0 {
                    thrust = Double(v.paddles) * 5.0
                    vmax = 3.4
                }
                let along: Double = v.vx * c + v.vy * s
                if !(abs(along) > vmax && along * throttle > 0) {
                    v.vx += c * thrust * throttle * invM * h
                    v.vy += s * thrust * throttle * invM * h
                }
            }
            // integrate
            v.px += v.vx * h
            v.py += v.vy * h
            v.angle += v.angVel * h
            // contacts
            let c2: Double = v.cosA
            let s2: Double = v.sinA
            // deepest penetration per direction; pushing out by the maximum (not the sum) keeps many
            // simultaneous contacts from launching the vehicle
            var outUp: Double = 0
            var outDown: Double = 0
            var outLeft: Double = 0
            var outRight: Double = 0
            var stepWheel: Int = 0
            let hitsBefore: Int = anyHits
            for smp in samples {
                let lx: Double = smp.lx - v.comX
                let ly: Double = smp.ly - v.comY
                let rx: Double = lx * c2 - ly * s2
                let ry: Double = lx * s2 + ly * c2
                let wx: Double = v.px + rx
                let wy: Double = v.py + ry
                guard let pen = penetration(wx, wy, wheel: smp.wheel) else { continue }
                let depth: Double = pen.0
                let nx: Double = pen.1
                let ny: Double = pen.2
                anyHits += 1
                if smp.wheel && ny < -0.5 { stepWheel += 1 }
                // velocity of the contact point
                let pvx: Double = v.vx - v.angVel * ry
                let pvy: Double = v.vy + v.angVel * rx
                let vn: Double = pvx * nx + pvy * ny
                // ramming: a hard hit knocks out weak blocks (trunks fell the whole tree)
                if vn < -3.0 && v.mass * -vn > 25.0 {
                    let tt: Tile = world.tile(Int(floor(wx)), Int(floor(wy)))
                    // tree trunks give way to a moderate hit; other wooden builds need a hard one
                    // only free-standing wooden things break; terrain (dirt, sand, stone) never gets dug out
                    if tt.hardness <= 1.0 && tt != .doorClosed && toolClass(tt) == .axe && (isLogTile(tt) || vn < -5.5) { rammed.append((Int(floor(wx)), Int(floor(wy)))) }
                }
                if vn < 0 {
                    let rn: Double = rx * ny - ry * nx
                    let kn: Double = invM + rn * rn * invI
                    let jn: Double = -(1.0 + 0.04) * vn / kn
                    v.vx += jn * nx * invM
                    v.vy += jn * ny * invM
                    v.angVel += rn * jn * invI
                    // friction along the surface; wheels roll unless braking
                    let tx: Double = -ny
                    let ty: Double = nx
                    let pvx2: Double = v.vx - v.angVel * ry
                    let pvy2: Double = v.vy + v.angVel * rx
                    let vt: Double = pvx2 * tx + pvy2 * ty
                    let rt: Double = rx * ty - ry * tx
                    let kt: Double = invM + rt * rt * invI
                    var mu: Double = 0.7
                    if smp.wheel {
                        let braking: Bool = abs(throttle) < 0.1 || throttle * vt < 0
                        mu = braking ? (v.rider ? 0.9 : 0.25) : 0.06
                    }
                    var jt: Double = -vt / kt
                    let lim: Double = mu * jn
                    jt = clampD(jt, -lim, lim)
                    v.vx += jt * tx * invM
                    v.vy += jt * ty * invM
                    v.angVel += rt * jt * invI
                }
                let d: Double = max(0, depth - 0.01)
                if ny < -0.5 { outUp = max(outUp, d) } else if ny > 0.5 { outDown = max(outDown, d) }
                else if nx < -0.5 { outLeft = max(outLeft, d) } else { outRight = max(outRight, d) }
            }
            v.px += (outRight - outLeft) * 0.8
            v.py += (outDown - outUp) * 0.8
            wheelHits = max(wheelHits, stepWheel)
            // grounded stability assist: a tilted vehicle resting on something is eased back toward
            // upright, and rotation that would tip it further is damped. Flips stay possible in the air.
            if anyHits > hitsBefore {
                let a: Double = v.angle.truncatingRemainder(dividingBy: 2.0 * Double.pi)
                let wrapped: Double = a > Double.pi ? a - 2.0 * Double.pi : (a < -Double.pi ? a + 2.0 * Double.pi : a)
                if abs(wrapped) > 0.4 && abs(wrapped) < 2.5 {
                    v.angVel -= sin(wrapped) * 11.0 * h
                    if v.angVel * wrapped > 0 { v.angVel *= (1.0 - min(1.0, 8.0 * h)) }
                }
            }
            // engine drive through wheels that are on the ground
            // (only while roughly upright: a car on its nose or roof cannot push itself along)
            if stepWheel > 0 && v.canDriveOnLand && steerOK && hasFuel && abs(throttle) > 0.1 && abs(remainder(v.angle, 2.0 * Double.pi)) < 1.0 {
                let vmax: Double = min(17.0, 6.5 + 3.0 * Double(v.engines))
                let along: Double = v.vx * c2 + v.vy * s2
                if !(abs(along) > vmax && along * throttle > 0) {
                    // heavier builds accelerate and climb slower; more engines help
                    let power: Double = Double(v.engines) * 135.0 * min(1.0, Double(stepWheel) / 4.0 + 0.5)
                    v.vx += c2 * power * throttle * invM * h
                    v.vy += s2 * power * throttle * invM * h
                }
            }
            // a little rolling drag and air resistance
            v.vx *= (1.0 - min(1.0, 0.05 * h))
            v.angVel *= (1.0 - min(1.0, (anyHits > 0 ? 1.2 : 0.3) * h))
            // stability limits
            v.vx = clampD(v.vx, -30, 30)
            v.vy = clampD(v.vy, -30, 30)
            v.angVel = clampD(v.angVel, -12, 12)
        }
        for r in rammed where world.tile(r.0, r.1).solid {
            let t: Tile = world.tile(r.0, r.1)
            if isLogTile(t) { fellTree(r.0, r.1) } else { breakTile(r.0, r.1, v.rider) }
            addShake(0.25)
            v.vx *= 0.6
        }
        v.wheelContacts = wheelHits
        v.contacts = anyHits
        v.submerged = subFrac
        // in the air, the driver can pitch the vehicle (lean back / forward); flips are possible
        if anyHits == 0 && subFrac == 0 && v.wheels > 0 {
            // airborne wheeled vehicles slowly level out and shed spin (arcade suspension: driving off a
            // ledge at speed no longer guarantees a nosedive)
            let a: Double = remainder(v.angle, 2.0 * Double.pi)
            if abs(a) < 2.0 { v.angVel -= sin(a) * 4.0 * dt }
            v.angVel *= (1.0 - min(1.0, 1.5 * dt))
        }
        if anyHits == 0 && subFrac == 0 && v.rider && abs(throttle) > 0.1 {
            // gentle and capped, so holding the throttle over a jump leans the car rather than spinning it
            // (like most driving games: throttle leans the car back, reverse tips the nose down)
            if abs(v.angVel) < 2.5 || v.angVel * throttle > 0 { v.angVel -= throttle * 2.5 * dt }
        }
        // fuel and exhaust
        let burning: Bool = v.engines > 0 && v.fuel > 0 && abs(throttle) > 0.1
        if burning && !isCreative {
            v.fuel = max(0, v.fuel - dt * Double(v.engines) * (v.drilling ? 1.5 : 1.0))
        }
        if burning {
            v.smoke += dt
            if v.smoke > 0.12 {
                v.smoke = 0
                let back: (Double, Double) = v.toWorld(v.dir > 0 ? Double(v.minX) - 0.2 : Double(v.maxX) + 1.2, Double(v.maxY) + 0.3)
                spawnParticles(back.0, back.1, 0x707070, 1, 1.5, 0.6, -2)
            }
        }
        if abs(throttle) > 0.2 { v.dir = throttle > 0 ? 1 : -1 }
        v.wheelRot += (v.vx * v.cosA + v.vy * v.sinA) * dt * 2.0
        v.propRot += (abs(throttle) > 0.1 && subFrac > 0 ? 18.0 : 3.0) * dt
        v.updateBox()
        if v.drills > 0 { runDrills(v, dt) }
        vehicleImpacts(v, dt)
        // resting: let it sleep so it stops costing time (and cannot jitter)
        if anyHits > 0 && v.speed < 0.08 && abs(v.angVel) < 0.03 && abs(throttle) < 0.05 && !v.drilling {
            v.sleepT += dt
            if v.sleepT > 0.6 { v.asleep = true; v.vx = 0; v.vy = 0; v.angVel = 0 }
        } else {
            v.sleepT = 0
        }
        if v.py > Double(world.H) + 5 {
            v.py = Double(world.H) - 6
            v.vy = 0
        }
    }

    /// Vehicles shove each other apart instead of overlapping
    func separateVehicles() {
        if vehicles.count < 2 { return }
        for i in 0..<vehicles.count {
            for j in (i + 1)..<vehicles.count {
                let a: Vehicle = vehicles[i]
                let b: Vehicle = vehicles[j]
                let ox: Double = min(a.b.right, b.b.right) - max(a.b.left, b.b.left)
                let oy: Double = min(a.b.y, b.b.y) - max(a.b.top, b.b.top)
                if ox <= 0 || oy <= 0 { continue }
                let dirx: Double = a.b.x < b.b.x ? -1.0 : 1.0
                let tot: Double = a.mass + b.mass
                let push: Double = min(ox, 0.3)
                a.px += dirx * push * (b.mass / tot)
                b.px -= dirx * push * (a.mass / tot)
                let rel: Double = (a.vx - b.vx) * -dirx
                if rel < 0 {
                    // exchange momentum along x
                    let j: Double = rel * a.mass * b.mass / tot * 1.1
                    a.vx += dirx * j / a.mass * -1.0
                    b.vx -= dirx * j / b.mass * -1.0
                }
                a.asleep = false
                b.asleep = false
                a.updateBox()
                b.updateBox()
            }
        }
    }

    /// Hitting creatures (or the player) at speed hurts them according to speed and weight
    func vehicleImpacts(_ v: Vehicle, _ dt: Double) {
        let sp: Double = v.speed
        if sp < 4.0 { return }
        let src: DamageSource = v.rider ? .player : .environment
        let nudge: Double = 0.15
        for m in mobsNear(v.b.left - 1, v.b.right + 1) {
            if m.hp <= 0 || m.tame || m.kind == .villager { continue }
            if m.b.right < v.b.left - nudge || m.b.left > v.b.right + nudge || m.b.y < v.b.top || m.b.top > v.b.y { continue }
            // must actually touch a part, not just the box
            let cell: PartCell = v.cellAt(m.b.x, m.b.cy)
            var touching: Bool = v.parts[cell] != nil
            if !touching {
                for (c, _) in v.parts {
                    let cc: (Double, Double) = v.cellCenter(c)
                    if abs(cc.0 - m.b.x) < 0.5 + m.b.w * 0.5 + nudge && abs(cc.1 - m.b.cy) < 0.5 + m.b.h * 0.5 { touching = true; break }
                }
            }
            if !touching { continue }
            var info = DamageInfo(amount: (sp - 3.0) * (1.2 + v.mass * 0.35), type: .impact, source: src)
            info.dirX = v.vx >= 0 ? 1 : -1
            info.knock = min(14.0, 4.0 + sp * 0.8)
            info.originX = v.b.x
            info.key = 7_000_000 + v.id
            info.cooldown = 0.7
            if applyMobDamage(m, info) {
                // the creature's weight slows the vehicle
                let mm: Double = m.def.w * m.def.h * 0.8
                v.vx *= v.mass / (v.mass + mm * 0.5)
                addShake(0.12)
            }
        }
        if !v.rider && !dead && inVehicle !== v {
            if pb.right > v.b.left && pb.left < v.b.right && pb.y > v.b.top && pb.top < v.b.y {
                var info = DamageInfo(amount: (sp - 3.0) * (1.0 + v.mass * 0.3), type: .impact, source: .environment)
                info.knock = 9.0
                info.originX = v.b.x
                info.key = 7_000_000 + v.id
                info.cooldown = 0.8
                _ = hurtPlayer(info)
            }
        }
    }

    // MARK: drills

    /// Running drills bore into the block in front of them, using the same hardness and tier rules
    /// (and drops) as hand mining. One block at a time per drill.
    func runDrills(_ v: Vehicle, _ dt: Double) {
        let powered: Bool = v.rider && (v.engines > 0 && (v.fuel > 0 || isCreative))
        v.drilling = false
        if !powered { v.drillWork.removeAll(); return }
        v.drillRot += dt * 25.0
        for (cell, d) in v.drillDir {
            guard let pt = v.parts[cell] else { continue }
            let pw: (Int, Double) = drillPower(pt)
            let tip: (Double, Double) = v.toWorld(Double(cell.dx) + 0.5 + Double(d.0) * 0.85, Double(cell.dy) + 0.5 + Double(d.1) * 0.85)
            // the bit is three blocks wide across its facing (so the hull and wheels behind it fit
            // through the hole); it clears one block at a time, the centre one first
            var tx: Int = Int(floor(tip.0))
            var ty: Int = Int(floor(tip.1))
            var t: Tile = world.tile(tx, ty)
            if t == .air || t.liquid || t.isPlant || Tile.tierTable[t.idx] > pw.0 {
                for side in [1.0, -1.0] {
                    let q: (Double, Double) = v.toWorld(Double(cell.dx) + 0.5 + Double(d.0) * 0.85 + Double(d.1) * side * -1.0 + (d.1 == 0 ? 0 : 0),
                                                       Double(cell.dy) + 0.5 + Double(d.1) * 0.85 + Double(d.0) * side * (d.0 == 0 ? 0 : 1))
                    let qt: Tile = world.tile(Int(floor(q.0)), Int(floor(q.1)))
                    if qt != .air && !qt.liquid && !qt.isPlant && qt.hardness < 9000 && Tile.tierTable[qt.idx] <= pw.0 {
                        tx = Int(floor(q.0)); ty = Int(floor(q.1)); t = qt
                        break
                    }
                }
            }
            // creatures caught in the bit get hurt
            for m in mobsNear(tip.0 - 1, tip.0 + 1) where m.hp > 0 && !m.tame && m.kind != .villager {
                if abs(m.b.x - tip.0) < m.b.w * 0.5 + 0.3 && tip.1 > m.b.top - 0.2 && tip.1 < m.b.y + 0.2 {
                    var info = DamageInfo(amount: 5, type: .melee, source: .player)
                    info.originX = v.px
                    info.knock = 4
                    info.key = 8_000_000 + v.id
                    info.cooldown = 0.35
                    applyMobDamage(m, info)
                }
            }
            if t == .air || t.liquid || t.isPlant {
                v.drillWork[cell] = nil
                continue
            }
            let hard: Double = t.hardness
            if hard >= 9000 || Tile.tierTable[t.idx] > pw.0 {
                if Double.random(in: 0...1) < 0.1 { spawnParticles(tip.0, tip.1, 0xFFE080, 1, 3.0, 0.2, 6) }
                continue
            }
            v.drilling = true
            var work: (Int, Int, Double) = v.drillWork[cell] ?? (tx, ty, 0)
            if work.0 != tx || work.1 != ty { work = (tx, ty, 0) }
            work.2 += dt * pw.1
            if Double.random(in: 0...1) < 0.35 {
                spawnParticles(tip.0, tip.1, t.def.colors.first ?? 0x888888, 1, 3.0, 0.3, 12)
            }
            if work.2 >= max(0.05, hard * 1.5) {
                breakTile(tx, ty, true)
                v.drillWork[cell] = nil
                addShake(0.04)
            } else {
                v.drillWork[cell] = work
            }
        }
    }

    // MARK: driving

    func driveVehicle(_ v: Vehicle, _ ix: Double, _ jumpPressed: Bool, _ dt: Double) {
        v.throttle = ix
        if abs(ix) > 0.05 { v.asleep = false }
        if let c = seatCell(v) {
            // sit on the seat, following the vehicle's rotation
            let p: (Double, Double) = v.toWorld(Double(c.dx) + 0.5, Double(c.dy) + 0.95)
            pb.x = p.0
            pb.y = p.1
        } else {
            pb.x = v.b.x
            pb.y = v.b.top
        }
        pb.vx = v.vx
        pb.vy = v.vy
        fallPeak = 0
        facing = v.dir
        if jumpPressed {
            let tilt: Double = abs(remainder(v.angle, 2.0 * Double.pi))
            if tilt > 0.9 && v.contacts > 0 && v.speed < 3.0 {
                // upside down: give it a shove back onto its wheels
                v.vy = -7.5
                v.angVel = (remainder(v.angle, 2.0 * Double.pi) > 0 ? -1.0 : 1.0) * 6.0
                v.asleep = false
                say("Heave! Flipping the vehicle back over.", 1.5)
            } else if v.speed < 2.5 {
                dismount()
            }
        }
    }

    func cellPos(_ v: Vehicle, _ c: PartCell) -> (Double, Double) {
        return v.cellPos(c)
    }

    func interactVehicle(_ v: Vehicle, _ c: PartCell) {
        if let it = heldItem {
            var add: Double = 0
            switch it {
            case .mat(let m):
                if m == .coal { add = 30 }
                if m == .emberBar { add = 120 }
            case .block(let t):
                if t == .planks { add = 8 }
                if t == .log || t == .jungleLog || t == .palmLog { add = 14 }
            default: break
            }
            if add > 0 {
                if v.fuelCapacity <= 0 {
                    say("This vehicle has no engine or fuel tank.", 2.5)
                    return
                }
                if v.fuel >= v.fuelCapacity - 0.5 {
                    say("The fuel tank is full.", 1.5)
                    return
                }
                v.fuel = min(v.fuelCapacity, v.fuel + add)
                if !isCreative { inv.removeAt(sel, 1) }
                say("Refueled: " + String(Int(v.fuel)) + "/" + String(Int(v.fuelCapacity)), 1.5)
                bumpHUD()
                return
            }
        }
        if let t = v.parts[c], t == .seat || t == .steering {
            mountVehicle(v)
            return
        }
        let massS: String = String(format: "%.1f", v.mass)
        let fuelA: Int = Int(v.fuel)
        let fuelB: Int = Int(v.fuelCapacity)
        var info: String = "Vehicle: mass \(massS), fuel \(fuelA)/\(fuelB)"
        if !v.hasSeat { info += ". Needs a seat." }
        else if !v.hasSteering { info += ". Needs a steering wheel next to the seat." }
        else if v.buoyancy > 0 && !v.canSail && v.wheels < 2 { info += ". Add engine + propeller (or a paddle)." }
        else if v.wheels >= 2 && v.engines == 0 { info += ". Add an engine." }
        else { info += ". Tap the seat to drive." }
        say(info, 3.5)
    }

    func mountVehicle(_ v: Vehicle) {
        if !v.hasSeat || !v.hasSteering {
            say(v.hasSeat ? "Add a steering wheel next to the seat." : "Add a seat first.", 2.5)
            return
        }
        if mounted != nil { dismount() }
        inVehicle = v
        v.rider = true
        v.asleep = false
        let drillTip: String = v.drills > 0 ? " Drills spin while the engine runs." : ""
        say("Driving. Hold the stick to move; in the air it tilts the vehicle. Jump to get out when stopped." + drillTip, 3.5)
        bumpHUD()
    }
}

// MARK: - Pirate ships

extension Game {
    func shipById(_ id: Int) -> PirateShip? {
        for s in ships where s.id == id { return s }
        return nil
    }

    func alertShip(_ id: Int) {
        guard let s = shipById(id) else { return }
        if s.state == 0 { s.state = 1 }
        for cid in s.crew {
            for m in mobs where m.id == cid { m.t3 = max(m.t3, 0) }
        }
    }

    func updateCrew(_ m: Mob, _ dt: Double) -> Bool {
        guard let s = shipById(m.boat) else {
            m.boat = -1
            return false
        }
        if s.sink >= 3.0 { m.boat = -1; return false }
        if !m.raiding && s.state == 2 {
            // anchored at the shore: attackers go ashore
            if abs(pb.x - s.x) < 40 { m.raiding = true }
        }
        return false
    }

    func clampToDeck(_ m: Mob) {
        guard m.boat >= 0, !m.raiding, let s = shipById(m.boat) else { return }
        let lo: Double = s.x - PirateShip.deckHalf + m.b.w * 0.5
        let hi: Double = s.x + PirateShip.deckHalf - 0.2 - m.b.w * 0.5
        if m.b.x < lo { m.b.x = lo; m.b.vx = max(0, m.b.vx) }
        if m.b.x > hi { m.b.x = hi; m.b.vx = min(0, m.b.vx) }
    }

    func oceanOK(_ x: Int) -> Bool {
        let c: Col = gen.col(x)
        return c.biome == .ocean && c.h - WorldGen.sea >= 9
    }

    func updateShips(_ dt: Double) {
        if world.dim != .overworld {
            if !ships.isEmpty {
                for s in ships { for id in s.crew { mobs.removeAll { $0.id == id } } }
                ships.removeAll()
            }
            return
        }
        // spawning
        shipTimer -= dt
        if shipTimer <= 0 {
            shipTimer = Double.random(in: 25...50)
            trySpawnShip()
        }
        var i: Int = 0
        let sea: Double = Double(WorldGen.sea)
        while i < ships.count {
            let s: PirateShip = ships[i]
            if abs(s.x - pb.x) > 170 {
                for id in s.crew { mobs.removeAll { $0.id == id } }
                ships.remove(at: i)
                continue
            }
            if !world.isLoaded(Int(floor(s.x))) { i += 1; continue }
            s.bob += dt * 1.5
            if s.hitT > 0 { s.hitT -= dt }
            if s.hp <= 0 && s.sink == 0 {
                s.sink = 0.01
                say("The pirate ship is sinking!", 3.0)
                for id in s.crew { for m in mobs where m.id == id { m.boat = -1; m.raiding = true } }
                for _ in 0..<6 { spawnDrop(Stack(item: .block(.planks), count: 2), s.x + Double.random(in: -3...3), s.deckY(sea) - 1, Double.random(in: -2...2), -4) }
                spawnDrop(Stack(item: .mat(.goldBar), count: 2 + Int.random(in: 0...3)), s.x, s.deckY(sea) - 1, 0, -5)
                if !s.looted { spawnDrop(Stack(item: .mat(.gunpowder), count: 4), s.x + 1, s.deckY(sea) - 1, 1, -5) }
            }
            if s.sink > 0 {
                s.sink += dt * 0.8
                s.speed = 0
                spawnParticles(s.x + Double.random(in: -4...4), sea - 0.2, 0xFFFFFF, 1, 1.5, 0.5, 4)
                if s.sink > 6.0 {
                    ships.remove(at: i)
                    continue
                }
                i += 1
                continue
            }
            // crew bookkeeping
            var alive: Int = 0
            for id in s.crew { for m in mobs where m.id == id && m.hp > 0 { alive += 1 } }
            if alive == 0 && s.state != 3 {
                s.state = 3
                s.speed = 0
            }
            let dxP: Double = pb.x - s.x
            let landOnly: Bool = !pb.inWater
            switch s.state {
            case 0:
                s.speed = 1.6
                if abs(dxP) < 75 && landOnly && pb.y < sea + 2 { s.state = 1 }
            case 1:
                s.speed = 2.6
                s.dir = dxP >= 0 ? 1 : -1
                if abs(dxP) > 110 { s.state = 0 }
            case 2:
                s.speed = 0
                if abs(dxP) > 70 { s.state = 0 }
            default:
                s.speed = 0
            }
            if s.state == 0 || s.state == 1 {
                let aheadX: Int = Int(floor(s.x + Double(s.dir) * 6.0))
                let waterAhead: Bool = world.tile(aheadX, WorldGen.sea + 1) == .water && world.tile(aheadX, WorldGen.sea + 5) == .water
                let withinPatrol: Bool = s.x + Double(s.dir) * 6.0 > s.patrolMin && s.x + Double(s.dir) * 6.0 < s.patrolMax
                if !waterAhead || (!withinPatrol && s.state == 0) {
                    if s.state == 1 { s.state = 2; s.speed = 0 } else { s.dir = -s.dir }
                } else {
                    s.x += Double(s.dir) * s.speed * dt
                }
                // reached the shore: anchor and let the raiders out
                if s.state == 1 && abs(dxP) < 14 && !waterAhead { s.state = 2 }
            }
            i += 1
        }
    }

    func trySpawnShip() {
        if ships.count >= 2 || dead { return }
        if Double.random(in: 0...1) > 0.55 { return }
        let side: Double = Bool.random() ? 1.0 : -1.0
        let x: Int = Int(floor(pb.x + side * Double.random(in: 52...78)))
        if !world.isLoaded(x) { return }
        if !gen.infinite && (x < 40 || x > gen.width - 40) { return }
        if !oceanOK(x) || !oceanOK(x - 6) || !oceanOK(x + 6) { return }
        if world.tile(x, WorldGen.sea + 1) != .water { return }
        // patrol range = ocean extent
        var lo: Int = x
        var hi: Int = x
        var n: Int = 0
        while n < 260 && oceanOK(lo - 4) { lo -= 4; n += 1 }
        n = 0
        while n < 260 && oceanOK(hi + 4) { hi += 4; n += 1 }
        if hi - lo < 50 { return }
        let s = PirateShip(id: newID(), x: Double(x), dir: side > 0 ? -1 : 1, pMin: Double(lo + 8), pMax: Double(hi - 8))
        s.state = 0
        let sea: Double = Double(WorldGen.sea)
        let dy: Double = s.deckY(sea)
        var kinds: [MobKind] = [.pirate, .pirateGunner, .pirate]
        if Double.random(in: 0...1) < 0.3 { kinds.append(.pirateCaptain) }
        if Double.random(in: 0...1) < 0.4 { kinds.append(.pirateGunner) }
        var k: Int = 0
        for kind in kinds {
            let ox: Double = -2.8 + Double(k) * 1.8
            let m: Mob = addMob(kind, s.x + ox, dy)
            m.boat = s.id
            m.homeX = m.b.x
            m.persistent = true
            s.crew.append(m.id)
            k += 1
        }
        ships.append(s)
        say("Pirates ahoy! A pirate ship patrols the sea.", 3.0)
    }
}

// ===== p18_portal_map =====

// MARK: - Portal travel between dimensions

extension Game {
    func updatePortal(_ dt: Double) {
        if portalCool > 0 { portalCool -= dt }
        if fadeT > 0 { fadeT = max(0, fadeT - dt * 1.4) }
        if dead {
            portalT = 0
            return
        }
        var px: Double = pb.x
        var py: Double = pb.y - pb.h * 0.5
        if let r = mounted {
            px = r.b.x
            py = r.b.cy
        }
        let a: Tile = world.tile(Int(floor(px)), Int(floor(py)))
        let b: Tile = world.tile(Int(floor(px)), Int(floor(pb.y - 0.3)))
        let inside: Bool = a == .portalOn || b == .portalOn
        if inside && portalCool <= 0 {
            portalT += dt
            fadeT = max(fadeT, min(1.0, portalT / 1.1))
            if Double.random(in: 0...1) < 0.5 {
                spawnParticles(px + Double.random(in: -1...1), py + Double.random(in: -1.5...1.5), 0xB070FF, 1, 2.0, 0.6, -2)
            }
            if portalT >= 1.1 {
                portalT = 0
                let dest: Dimension = world.dim == .overworld ? .umbral : .overworld
                let spot: (Double, Double) = portalArrival(dest)
                travelTo(dest, arriveX: spot.0, arriveY: spot.1, silent: false)
            }
        } else if portalT > 0 {
            portalT = max(0, portalT - dt * 2.0)
        }
        // the key hums when the hidden portal is near
        if world.dim == .overworld && !portalOpened {
            hintT -= dt
            if hintT <= 0 {
                hintT = 6.0
                if inv.total(.gadget(.portalKey)) > 0 {
                    let lv: Int = portalHintLevel()
                    if lv >= 2 { say(portalHintText(lv), 3.0) }
                }
            }
        }
    }

    /// Standing spot just to the right of the portal frame in the given dimension
    func portalArrival(_ dim: Dimension) -> (Double, Double) {
        if dim == .overworld {
            return (Double(gen.portalX) + 5.5, Double(gen.portalY + 6))
        }
        return (Double(gen.portalX) + 5.5, Double(gen.umbralPortalFloor))
    }

    func standable(_ x: Int, _ y: Int) -> Bool {
        // feet at row y means the tile at row y is the floor
        let f: Tile = world.tile(x, y)
        if !(f.solid || f == .platform) { return false }
        for k in 1...2 {
            let t: Tile = world.tile(x, y - k)
            if t.solid || t.liquid || t == .portalOn { return false }
        }
        return true
    }

    func findSafeSpot(_ ax: Double, _ ay: Double) -> (Double, Double) {
        let bx: Int = Int(floor(ax))
        let by: Int = Int(floor(ay))
        let offs: [Int] = [0, 1, -1, 2, -2, 3, -3, 4, -4, 6, -6, 8, -8, 10, -10]
        for o in offs {
            let x: Int = bx + o
            for dy in 0...24 {
                for sgn in [1, -1] {
                    let y: Int = by + dy * sgn
                    if y < 3 || y >= world.H - 2 { continue }
                    if standable(x, y) { return (Double(x) + 0.5, Double(y)) }
                    if dy == 0 { break }
                }
            }
        }
        // nothing usable: carve a 2x3 pocket and lay a floor
        for x in bx...(bx + 1) {
            for y in (by - 3)...(by - 1) {
                let t: Tile = world.tile(x, y)
                if t.def.hard < 9000 { world.set(x, y, .air) }
            }
            if !world.tile(x, by).solid { world.set(x, by, .stone) }
        }
        return (Double(bx) + 0.5, Double(by))
    }

    func travelTo(_ dim: Dimension, arriveX: Double, arriveY: Double, silent: Bool) {
        if inVehicle != nil { dismount() }
        let riding: Mob? = mounted
        // pets close to the player come along
        var carried: [Mob] = []
        for m in mobs where m.tame && m.hp > 0 && !(m === rex) {
            if abs(m.b.x - pb.x) < 14 && abs(m.b.y - pb.y) < 10 && m.st != 7 { carried.append(m) }
        }
        let bringRex: Mob? = (rex != nil && rex!.hp > 0) ? rex : nil
        // everything else stays behind
        vehicleStash[world.dim.rawValue] = vehicles
        vehicles = vehicleStash[dim.rawValue]
        vehicleStash[dim.rawValue] = []
        mobs.removeAll()
        projectiles.removeAll()
        drops.removeAll()
        particles.removeAll()
        ships.removeAll()
        shipTimer = 30
        activeBoss = nil
        villagerCells.removeAll()
        decksCache = []
        world.switchDimension(dim)
        world.loadAround(centerX: Int(floor(arriveX)), radius: 3)
        let spot: (Double, Double) = findSafeSpot(arriveX, arriveY)
        pb.x = spot.0
        pb.y = spot.1
        pb.vx = 0
        pb.vy = 0
        pb.onGround = true
        fallPeak = 0
        facing = -1
        camX = pb.x
        camY = pb.y - 2
        lastStreamCX = Int.min
        light.valid = false
        lightTimer = 0
        portalCool = 3.0
        portalT = 0
        fadeT = 1.0
        for (i, m) in carried.enumerated() {
            m.b.x = pb.x + 1.2 + Double(i) * 0.9
            m.b.y = pb.y
            m.b.vx = 0
            m.b.vy = 0
            mobs.append(m)
        }
        if let r = bringRex {
            r.b.vx = 0
            r.b.vy = 0
            if riding === r {
                r.b.x = pb.x
                r.b.y = pb.y
                if world.boxSolid(r.b.left, r.b.top, r.b.right, r.b.y - 0.05) {
                    r.b.x = Double(gen.portalX) - 6.5
                }
            } else {
                r.b.x = Double(gen.portalX) - 6.5
                r.b.y = pb.y
            }
            if world.boxSolid(r.b.left, r.b.top, r.b.right, r.b.y - 0.05) {
                teleportRexNearPlayer(r)
            }
            r.stuckT = 0
            r.lastX = r.b.x
            mobs.append(r)
        } else {
            mounted = nil
        }
        if let r = mounted, r !== bringRex { _ = r; mounted = nil }
        if !silent {
            if dim == .umbral {
                say("You step into the Umbral Realm. Beware the heat and the dark.", 5.0)
            } else {
                say("You return to the Overworld.", 3.0)
            }
            shake = 0.4
        }
        bumpHUD()
    }

    // MARK: portal proximity hint

    /// 0 silent ... 4 right on top of it
    func portalHintLevel() -> Int {
        if world.dim != .overworld { return 0 }
        let dx: Double = pb.x - Double(gen.portalX)
        let dy: Double = (pb.y - Double(gen.portalY)) * 0.6
        let d: Double = sqrt(dx * dx + dy * dy)
        if d < 45 { return 4 }
        if d < 120 { return 3 }
        if d < 300 { return 2 }
        if d < 700 { return 1 }
        return 0
    }

    func portalHintText(_ lv: Int) -> String {
        switch lv {
        case 4: return "The Portal Key burns in your hand. The gate is very close!"
        case 3: return "The Portal Key hums loudly. You are near."
        case 2: return "The Portal Key trembles faintly..."
        case 1: return "The Portal Key is cool and quiet. The gate is far."
        default: return "The Portal Key is silent."
        }
    }
}

// MARK: - Treasure map

struct MapMarker {
    var x: Int
    var kind: Int      // 0 spawn, 1 bear lair, 2 rex lair, 3 village, 4 ruin
    var label: String
}

struct TreasureMap {
    var x0: Int
    var x1: Int
    var step: Int
    var heights: [Int]
    var biomes: [Biome]
    var ringX: Int
    var ringY: Int
    var ringRX: Int
    var ringRY: Int
    var markers: [MapMarker]
    var clues: [String]
    var worldH: Int
}

func biomeMapColor(_ b: Biome) -> UInt32 {
    switch b {
    case .ocean: return 0x5C88B0
    case .plains: return 0x8DB25A
    case .forest: return 0x4E8A3E
    case .desert: return 0xE0C878
    case .tundra: return 0xE8F0F4
    case .jungle: return 0x2F7A2A
    case .savanna: return 0xC8B058
    case .swamp: return 0x5E7048
    case .mountain: return 0x8C8478
    case .umbral: return 0x50306A
    }
}

func roughDistance(_ d: Int) -> String {
    let unit: Int = d < 1000 ? 50 : 100
    let r: Int = max(unit, Int((Double(d) / Double(unit)).rounded()) * unit)
    if r >= 1000 {
        let th: Int = r / 1000
        let rest: Int = (r % 1000) / 100
        return String(th) + "," + String(rest) + "00"
    }
    return String(r)
}

extension Game {
    func treasureMap() -> TreasureMap {
        if let m = mapCache { return m }
        let m: TreasureMap = buildTreasureMap()
        mapCache = m
        return m
    }

    func buildTreasureMap() -> TreasureMap {
        let g: WorldGen = gen
        let px: Int = g.portalX
        let py: Int = g.portalY
        let rx: Int = 150
        let ry: Int = 80
        // the ring is offset so the exact spot stays a mystery, but the portal is always inside it
        let ox: Int = Int((hash2(11, 12, g.seed) - 0.5) * 2.0 * 0.55 * Double(rx))
        let oy: Int = Int((hash2(13, 14, g.seed) - 0.5) * 2.0 * 0.55 * Double(ry))
        let ringX: Int = px + ox
        let ringY: Int = clampI(py + oy, 200 + ry / 2, WorldGen.H - 20 - ry / 2)
        let sx: Int = g.spawnX
        var x0: Int = min(sx, ringX - rx) - 160
        var x1: Int = max(sx, ringX + rx) + 160
        if !g.infinite {
            x0 = max(0, x0)
            x1 = min(g.width - 1, x1)
        }
        let step: Int = max(4, (x1 - x0) / 300)
        var hs: [Int] = []
        var bs: [Biome] = []
        var x: Int = x0
        while x <= x1 {
            let c: Col = g.col(x)
            hs.append(c.h)
            bs.append(c.biome)
            x += step
        }
        var markers: [MapMarker] = [MapMarker(x: sx, kind: 0, label: "Start")]
        for L in g.lairCenters(near: (x0 + x1) / 2) {
            if L.cx < x0 || L.cx > x1 { continue }
            markers.append(MapMarker(x: L.cx, kind: L.kind == .bear ? 1 : 2, label: L.kind == .bear ? "Bear Den" : "Bone Nest"))
        }
        for v in g.villages(overlapping: x0, x1) {
            markers.append(MapMarker(x: v.x, kind: 3, label: "Village"))
        }
        var ruins: [RareSite] = []
        for r in g.rareSites(overlapping: x0, x1) {
            ruins.append(r)
            markers.append(MapMarker(x: r.x, kind: 4, label: rareName(r.kind)))
        }
        // clues
        var clues: [String] = []
        let d: Int = abs(px - sx)
        let dirS: String = px >= sx ? "east" : "west"
        clues.append("The gate lies roughly " + roughDistance(d) + " blocks " + dirS + " of where you first woke.")
        let top: Col = g.col(px)
        clues.append("Above it, the land is " + top.biome.name + ".")
        clues.append("It sleeps far below the surface, deeper than the iron veins. Dig down.")
        // nearest landmark
        var best: MapMarker? = nil
        var bd: Int = Int.max
        for mk in markers where mk.kind != 0 {
            let dd: Int = abs(mk.x - px)
            if dd < bd && dd < 900 { bd = dd; best = mk }
        }
        if let b = best {
            let side: String = b.x < px ? "west" : "east"
            clues.append("The nearest landmark, a " + b.label.lowercased() + ", stands about " + roughDistance(bd) + " blocks to its " + side + ".")
        }
        // terrain hint on each side
        for side in [-1, 1] {
            var mt: Int = 0
            var oc: Int = 0
            var k: Int = 20
            while k <= 220 {
                let b: Biome = g.colBase(px + side * k).biome
                if b == .mountain { mt += 1 }
                if b == .ocean { oc += 1 }
                k += 20
            }
            let sn: String = side < 0 ? "west" : "east"
            if mt >= 3 { clues.append("Mountains guard its " + sn + " side.") }
            else if oc >= 3 { clues.append("The sea is close on its " + sn + " side.") }
        }
        clues.append("The Portal Key hums louder as you draw near.")
        _ = ruins
        return TreasureMap(x0: x0, x1: x1, step: step, heights: hs, biomes: bs, ringX: ringX, ringY: ringY, ringRX: rx, ringRY: ry, markers: markers, clues: clues, worldH: WorldGen.H)
    }
}

func rareName(_ k: RareKind) -> String {
    switch k {
    case .house: return "Ruined House"
    case .tower: return "Ruined Tower"
    case .fort: return "Old Fort"
    case .camp: return "Abandoned Camp"
    case .overgrown: return "Overgrown Ruin"
    case .bunker: return "Buried Bunker"
    }
}

// ===== p19_save =====

// MARK: - Saving and loading

struct ChunkSave: Codable {
    var dim: Int
    var cx: Int
    var data: Data
    var walls: Data? = nil
}

struct SaveMeta: Codable {
    var slot: Int
    var name: String
    var mode: GameMode
    var infinite: Bool
    var seed: UInt64
    var day: Int
    var playSeconds: Double
    var dim: Int
    /// world generation rules the world was created with (nil in saves made before basins existed)
    var genVersion: Int? = nil
}

struct SaveData: Codable {
    var version: Int = 2
    var meta: SaveMeta
    var settings: Settings
    var px: Double
    var py: Double
    var hp: Double
    var maxHP: Double
    var hunger: Double
    var timeOfDay: Double
    var kills: Int
    var spawnX: Double
    var spawnY: Double
    var inv: Inventory
    var sel: Int
    var defeated: [Int]
    var gotMap: Bool
    var portalOpened: Bool
    var chests: [ChestEntry]
    var chunks: [ChunkSave]
    var vehicles: [[VehicleSave]]
    var pets: [MobSave]
    var rex: MobSave?
    var nextID: Int
}

func mobToSave(_ m: Mob) -> MobSave {
    return MobSave(kind: m.kind.rawValue, x: m.b.x, y: m.b.y, hp: m.hp, maxHP: m.maxHP, tame: m.tame, variant: m.variant, downed: m.downed, lair: m.lair)
}

enum SaveStore {
    static var dir: URL {
        let fm = FileManager.default
        if let d = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let u = d.appendingPathComponent("PixelRealmSaves", isDirectory: true)
            try? fm.createDirectory(at: u, withIntermediateDirectories: true)
            return u
        }
        return URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func url(_ slot: Int) -> URL {
        return dir.appendingPathComponent("slot" + String(slot) + ".json")
    }

    static func metaURL(_ slot: Int) -> URL {
        return dir.appendingPathComponent("slot" + String(slot) + ".meta.json")
    }

    static func write(_ s: SaveData) -> Bool {
        let enc = JSONEncoder()
        guard let d = try? enc.encode(s), let m = try? enc.encode(s.meta) else { return false }
        do {
            try d.write(to: url(s.meta.slot), options: .atomic)
            try m.write(to: metaURL(s.meta.slot), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func read(_ slot: Int) -> SaveData? {
        guard let d = try? Data(contentsOf: url(slot)) else { return nil }
        return try? JSONDecoder().decode(SaveData.self, from: d)
    }

    static func meta(_ slot: Int) -> SaveMeta? {
        guard let d = try? Data(contentsOf: metaURL(slot)) else { return nil }
        return try? JSONDecoder().decode(SaveMeta.self, from: d)
    }

    static func delete(_ slot: Int) {
        try? FileManager.default.removeItem(at: url(slot))
        try? FileManager.default.removeItem(at: metaURL(slot))
    }

    static let slotCount: Int = 4

    /// First empty slot, or the least recently played one when all are used
    static func freeSlot() -> Int {
        for i in 0..<slotCount where meta(i) == nil { return i }
        var best: Int = 0
        var bt: Date = .distantFuture
        for i in 0..<slotCount {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url(i).path)
            let t: Date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            if t < bt { bt = t; best = i }
        }
        return best
    }

    static func mostRecent() -> SaveMeta? {
        var best: SaveMeta? = nil
        var bt: Date = .distantPast
        for i in 0..<slotCount {
            guard let m = meta(i) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url(i).path)
            let t: Date = (attrs?[.modificationDate] as? Date) ?? .distantPast
            if best == nil || t > bt { best = m; bt = t }
        }
        return best
    }
}

extension Game {
    func makeSave() -> SaveData {
        var cs: [ChunkSave] = []
        let cur: Int = world.dim.rawValue
        for (k, c) in world.chunks where c.dirty {
            cs.append(ChunkSave(dim: cur, cx: k, data: Data(World.rle(c.tiles)), walls: c.walls.isEmpty ? nil : Data(World.rle(c.walls))))
        }
        for d in 0..<2 {
            for (k, c) in world.parked[d] {
                if d == cur && world.chunks[k] != nil { continue }
                cs.append(ChunkSave(dim: d, cx: k, data: Data(World.rle(c.tiles)), walls: c.walls.isEmpty ? nil : Data(World.rle(c.walls))))
            }
        }
        var chestList: [ChestEntry] = []
        for (k, v) in world.chests { chestList.append(ChestEntry(key: k, items: v)) }
        var vs: [[VehicleSave]] = [[], []]
        for d in 0..<2 {
            let list: [Vehicle] = d == cur ? vehicles : vehicleStash[d]
            vs[d] = list.map { $0.save() }
        }
        var pets: [MobSave] = []
        for m in mobs where m.tame && m.hp > 0 && m.kind != .rex { pets.append(mobToSave(m)) }
        var rs: MobSave? = nil
        if let r = rex { rs = mobToSave(r) }
        var px: Double = pb.x
        var py: Double = pb.y
        if let r = mounted { px = r.b.x; py = r.b.y }
        if let v = inVehicle { px = v.b.x; py = v.b.y - v.b.h }
        let meta = SaveMeta(slot: slot, name: worldName, mode: mode, infinite: gen.infinite, seed: seedValue, day: dayCount, playSeconds: playSeconds, dim: cur, genVersion: gen.genVersion)
        return SaveData(meta: meta, settings: settings, px: px, py: py, hp: max(1, hp), maxHP: maxHP, hunger: hunger, timeOfDay: timeOfDay, kills: kills, spawnX: spawnX, spawnY: spawnY, inv: inv, sel: sel, defeated: Array(defeated), gotMap: gotMap, portalOpened: portalOpened, chests: chestList, chunks: cs, vehicles: vs, pets: pets, rex: rs, nextID: nextID)
    }

    @discardableResult
    func saveNow() -> Bool {
        if mode == .hardcore && hardcoreOver { return false }
        if dead { return false }
        return SaveStore.write(makeSave())
    }

    static func load(_ s: SaveData, settings: Settings) -> Game {
        var st: Settings = settings
        st.rareChance = s.settings.rareChance
        // worlds saved before the generation changes keep generating exactly as they did
        let g = Game(mode: s.meta.mode, infinite: s.meta.infinite, seed: s.meta.seed, settings: st, genVersion: s.meta.genVersion ?? 1)
        g.slot = s.meta.slot
        g.worldName = s.meta.name
        g.dayCount = s.meta.day
        g.playSeconds = s.meta.playSeconds
        g.timeOfDay = s.timeOfDay
        g.hp = s.hp
        g.maxHP = s.maxHP
        g.hunger = s.hunger
        g.kills = s.kills
        g.spawnX = s.spawnX
        g.spawnY = s.spawnY
        g.inv = s.inv
        g.sel = clampI(s.sel, 0, Inventory.hotbarCount - 1)
        g.defeated = Set(s.defeated)
        g.gotMap = s.gotMap
        g.portalOpened = s.portalOpened
        g.nextID = max(g.nextID, s.nextID)
        let w: World = g.world
        w.chunks.removeAll()
        w.parked = [[:], [:]]
        for c in s.chunks {
            if c.dim < 0 || c.dim > 1 { continue }
            let H: Int = dimHeight(Dimension(rawValue: c.dim) ?? .overworld)
            let ch = Chunk(cx: c.cx, H: H)
            ch.hasSky = c.dim == 0
            ch.tiles = World.unrle([UInt8](c.data), chunkW * H)
            if ch.tiles.count > chunkW * H { ch.tiles = Array(ch.tiles.prefix(chunkW * H)) }
            if let wd = c.walls { ch.walls = World.unrle([UInt8](wd), chunkW * H) }
            ch.dirty = true
            ch.rebuildSky()
            fillSurface(ch, g.gen, c.dim == 0 ? .overworld : .umbral)
            w.parked[c.dim][c.cx] = ch
        }
        for e in s.chests { w.chests[e.key] = e.items }
        let dim: Dimension = Dimension(rawValue: s.meta.dim) ?? .overworld
        if dim != w.dim {
            w.dim = dim
            w.H = dimHeight(dim)
        }
        w.version += 1
        w.layoutVersion += 1
        for d in 0..<2 where d < s.vehicles.count {
            let list: [Vehicle] = s.vehicles[d].map { Vehicle.restore($0) }
            if d == dim.rawValue { g.vehicles = list } else { g.vehicleStash[d] = list }
        }
        w.loadAround(centerX: Int(floor(s.px)), radius: 4)
        g.pb.x = s.px
        g.pb.y = s.py
        g.pb.vx = 0
        g.pb.vy = 0
        if w.boxSolid(g.pb.left, g.pb.top, g.pb.right, g.pb.y - 0.05) {
            let spot: (Double, Double) = g.findSafeSpot(s.px, s.py)
            g.pb.x = spot.0
            g.pb.y = spot.1
        }
        g.camX = g.pb.x
        g.camY = g.pb.y - 2
        for p in s.pets {
            guard let k = MobKind(rawValue: p.kind) else { continue }
            let m: Mob = g.addMob(k, g.pb.x + Double.random(in: -2...2), g.pb.y)
            m.tame = true
            m.hp = p.hp
            m.maxHP = p.maxHP
            m.variant = p.variant
        }
        if let r = s.rex {
            let m: Mob = g.addMob(.rex, r.x, r.y)
            m.tame = true
            m.persistent = true
            m.hp = max(1, r.hp)
            m.maxHP = r.maxHP
            m.downed = r.downed
            if m.downed { m.t1 = 20 }
            g.rex = m
            if abs(m.b.x - g.pb.x) > 40 || w.boxSolid(m.b.left, m.b.top, m.b.right, m.b.y - 0.05) {
                g.teleportRexNearPlayer(m)
            }
        }
        g.invuln = 2.0
        return g
    }

    func updateAutosave(_ dt: Double) {
        autosaveT += dt
        if autosaveT >= 60 {
            autosaveT = 0
            if saveNow() { floatText("Saved", pb.x, pb.y - pb.h - 0.8, 0xA0FFA0) }
        }
        if mode == .hardcore && hardcoreOver && SaveStore.meta(slot) != nil {
            SaveStore.delete(slot)
        }
    }
}

// ===== p20_assist =====

// MARK: - Action button (auto-aim), debug commands, info for the HUD

final class ActState: @unchecked Sendable {
    var held: Bool = false
    var was: Bool = false
}

let actState = ActState()

extension Game {
    /// Called once per frame before tick. While the on-screen action button is held, the game
    /// aims for you: nearest enemy in reach for weapons, otherwise the block in front of you.
    func applyActButton() {
        let held: Bool = actState.held
        defer { actState.was = held }
        if !held {
            if actState.was {
                useHeld = false
                useWasHeld = false
                useReleasedFlag = true
            }
            return
        }
        if dead { return }
        let it: Item? = heldItem
        var tx: Double = pb.x + Double(facing) * 1.1
        var ty: Double = pb.y - 1.3
        var aimed: Bool = false
        var wantsMob: Bool = true
        if let i = it {
            switch i {
            case .block, .part, .mat, .food, .wall: wantsMob = false
            default: wantsMob = true
            }
        }
        if wantsMob {
            let range: Double = (it?.isRanged ?? false) ? 22.0 : reachDistance() + 0.5
            var best: Mob? = nil
            var bd: Double = range
            for m in mobs {
                if m.hp <= 0 || m.tame || m.kind == .villager { continue }
                if !m.def.hostile && !m.angry && !(it?.isWeapon ?? false) { continue }
                let dx: Double = m.b.x - pb.x
                let dy: Double = m.b.cy - (pb.y - pb.h * 0.6)
                let d: Double = sqrt(dx * dx + dy * dy)
                if d < bd { bd = d; best = m }
            }
            if let m = best {
                tx = m.b.x
                ty = m.b.cy
                if case .bow? = it {
                    // lead the target and aim above it so the arrow's drop carries it onto the target
                    let st: BowStats = bowStats(.bow)
                    let dx: Double = tx - pb.x
                    let dy: Double = ty - (pb.y - 1.2)
                    let t: Double = sqrt(dx * dx + dy * dy) / st.maxSpeed
                    tx += m.b.vx * t
                    ty -= 0.5 * st.gravity * t * t
                }
                aimed = true
            }
        }
        if !aimed {
            let fx: Int = Int(floor(pb.x + Double(facing) * (pb.w * 0.5 + 0.55)))
            let chest: Int = Int(floor(pb.y - 1.3))
            let feet: Int = Int(floor(pb.y - 0.4))
            let below: Int = Int(floor(pb.y + 0.5))
            var placing: Bool = false
            if case .block? = it { placing = true }
            if case .wall? = it { placing = true }
            if placing {
                // build in front at foot level, then the step below
                if !world.solid(fx, feet) { tx = Double(fx) + 0.5; ty = Double(feet) + 0.5 }
                else if !world.solid(fx, chest) { tx = Double(fx) + 0.5; ty = Double(chest) + 0.5 }
                else { tx = Double(fx) + 0.5; ty = Double(chest - 1) + 0.5 }
            } else if world.tile(fx, chest) != .air {
                tx = Double(fx) + 0.5; ty = Double(chest) + 0.5
            } else if world.tile(fx, feet) != .air {
                tx = Double(fx) + 0.5; ty = Double(feet) + 0.5
            } else if stickY > 0.5 {
                let px: Int = Int(floor(pb.x))
                tx = Double(px) + 0.5; ty = Double(below) + 0.5
            } else {
                tx = Double(fx) + 0.5; ty = Double(chest) + 0.5
            }
        }
        aimX = tx
        aimY = ty
        aimValid = true
        if !actState.was {
            useHeld = true
            useWasHeld = false
            usePressedFlag = false
        } else {
            useHeld = true
        }
    }

    // MARK: debug

    func debugSpawn(_ k: MobKind) {
        let x: Double = pb.x + Double(facing) * 5.0
        var y: Double = pb.y
        let ix: Int = Int(floor(x))
        var yy: Int = Int(floor(pb.y)) - 6
        var n: Int = 0
        while n < 30 {
            if world.solid(ix, yy) && !world.solid(ix, yy - 1) && !world.solid(ix, yy - 2) { y = Double(yy); break }
            yy += 1
            n += 1
        }
        if k == .fish {
            y = pb.y - 0.5
        }
        let m: Mob = addMob(k, x, y)
        m.homeX = x
        m.homeY = y
        if k == .bearBoss || k == .rex {
            m.persistent = true
            m.homeX = x
            m.st = 3
            m.t2 = 1.0
            m.phase = 1
            m.lair = -1
        }
        say("Spawned " + m.def.name, 1.5)
    }

    func debugGiveKit() {
        let kit: [(Item, Int)] = [
            (.tool(.pickaxe, .diamond), 1), (.tool(.axe, .diamond), 1), (.sword(.diamond), 1), (.bow, 1),
            (.ammo(.arrow), 99), (.gun(.rifle), 1), (.gun(.pistol), 1), (.ammo(.bullet), 99),
            (.block(.torch), 99), (.block(.planks), 99), (.block(.stone), 99), (.food(.cookedMeat), 30),
            (.armor(.head, .diamond), 1), (.armor(.chest, .diamond), 1), (.armor(.legs, .diamond), 1),
            (.part(.frame), 10), (.part(.wheel), 4), (.part(.engine), 2), (.part(.seat), 1), (.part(.steering), 1),
            (.part(.fuelTank), 2), (.part(.hull), 6), (.part(.propeller), 1), (.mat(.coal), 40), (.gadget(.wrench), 1),
            (.gadget(.portalKey), 1), (.gadget(.treasureMap), 1), (.gadget(.carKit), 1), (.gadget(.motorboatKit), 1)
        ]
        for (it, n) in kit { giveItem(it, n, extra: gunLoad(it)) }
        gotMap = true
        say("Debug kit added.", 2.0)
    }

    func debugKillHostiles() {
        for m in mobs where m.def.hostile && !m.tame && m.hp > 0 { killMob(m, true) }
    }

    func debugTeleport(_ x: Double, _ y: Double) {
        if inVehicle != nil || mounted != nil { dismount() }
        world.loadAround(centerX: Int(floor(x)), radius: 3)
        let s: (Double, Double) = findSafeSpot(x, y)
        pb.x = s.0
        pb.y = s.1
        pb.vx = 0
        pb.vy = 0
        fallPeak = 0
        camX = pb.x
        camY = pb.y - 2
        light.valid = false
        if let r = rex, r.hp > 0 { teleportRexNearPlayer(r) }
    }

    func debugToSurface() {
        let x: Int = Int(floor(pb.x))
        if world.dim == .overworld {
            debugTeleport(Double(x) + 0.5, Double(world.surfaceY(x)))
        } else {
            debugTeleport(Double(x) + 0.5, Double(gen.uFloor(x)))
        }
    }

    func debugToPortal() {
        if world.dim == .overworld {
            let a: (Double, Double) = portalArrival(.overworld)
            debugTeleport(a.0, a.1)
        } else {
            let a: (Double, Double) = portalArrival(.umbral)
            debugTeleport(a.0, a.1)
        }
    }

    func debugToLair(_ kind: LairKind) {
        if world.dim != .overworld { travelTo(.overworld, arriveX: spawnX, arriveY: spawnY, silent: true) }
        for L in gen.lairCenters(near: Int(floor(pb.x))) where L.kind == kind {
            let x: Double = Double(L.cx) + (Double(L.cx) > pb.x ? -60.0 : 60.0)
            world.loadAround(centerX: Int(x), radius: 3)
            debugTeleport(x, Double(world.surfaceY(Int(x))))
            return
        }
    }

    func debugSwitchDimension() {
        let dest: Dimension = world.dim == .overworld ? .umbral : .overworld
        let a: (Double, Double) = portalArrival(dest)
        travelTo(dest, arriveX: a.0, arriveY: a.1, silent: false)
    }

    func debugSetTime(_ t: Double) {
        timeOfDay = t
        light.valid = false
    }

    // MARK: info

    var biomeHere: Biome {
        if world.dim == .umbral { return .umbral }
        return gen.col(Int(floor(pb.x))).biome
    }

    var depthText: String {
        let y: Int = Int(floor(pb.y))
        if world.dim == .umbral { return "Umbral depth " + String(y) }
        let d: Int = y - WorldGen.sea
        if d < -2 { return String(-d) + " above sea" }
        if d <= 2 { return "Sea level" }
        if d < 60 { return String(d) + " deep" }
        if d < 220 { return String(d) + " deep (caverns)" }
        if d < 360 { return String(d) + " deep (deep caves)" }
        return String(d) + " deep (the abyss)"
    }

    var selectedName: String {
        guard let s = heldStack else { return "Empty hand" }
        if case .gun(let g) = s.item {
            let nm: String = s.item.name
            let ex: Int = s.extra
            let mg: Int = g.magazine
            return "\(nm)  \(ex)/\(mg)"
        }
        return s.item.name
    }

    func armorPieces() -> (Tier?, Tier?, Tier?) {
        var r: [Tier?] = [nil, nil, nil]
        for i in 0..<3 {
            if let s = inv.armor[i], case .armor(_, let t) = s.item { r[i] = t }
        }
        return (r[0], r[1], r[2])
    }

    var armorKey: Int {
        let a = armorPieces()
        let h: Int = a.0?.rawValue ?? 0
        let c: Int = a.1?.rawValue ?? 0
        let l: Int = a.2?.rawValue ?? 0
        return h * 100 + c * 10 + l + settings.hair * 1000 + settings.scarf * 10000
    }

    /// Which humanoid frame to show for the player: 0 idle, 1/2 walk, 3 windup, 4 attack, 6 shoot
    func playerFrame() -> Int {
        if mounted != nil || inVehicle != nil { return 0 }
        if swingT > 0 {
            if let it = heldItem, it.isRanged { return 6 }
            return swingT > swingDur * 0.5 ? 3 : 4
        }
        if bowCharge > 0 { return 6 }
        if !pb.onGround && !pb.inWater { return 1 }
        if abs(pb.vx) > 0.6 {
            return (Int(walkAnim * 2.0) % 2 == 0) ? 1 : 2
        }
        return 0
    }
}

// ===== p21_backdrop =====

// MARK: - Backdrop walls (drawn behind open tiles; also decides what the light overlay may darken)
// 0 none (sky shows through), 1 dirt, 2 stone, 3 deep rock, 4 ash, 5 planks, 6 brick, 7 sandstone

func fillSurface(_ ch: Chunk, _ g: WorldGen, _ dim: Dimension) {
    for lx in 0..<chunkW {
        let x: Int = ch.x0 + lx
        if dim == .overworld {
            ch.surf[lx] = g.col(x).h
        } else {
            ch.surf[lx] = g.uFloor(x)
            ch.ceilY[lx] = g.uCeil(x)
        }
    }
}

func wallForRoof(_ t: Tile) -> UInt8 {
    switch t {
    case .brick, .crackedBrick, .mossBrick, .stone, .obsidian, .portalFrame: return 6
    case .sandstone: return 7
    case .ashStone: return 4
    default: return 5
    }
}

extension World {
    func backdrop(_ ch: Chunk) -> [UInt8] {
        if ch.backRev == ch.rev && !ch.back.isEmpty { return ch.back }
        let H: Int = ch.H
        var b: [UInt8] = [UInt8](repeating: 0, count: chunkW * H)
        let over: Bool = dim == .overworld
        let hasWalls: Bool = !ch.walls.isEmpty
        for lx in 0..<chunkW {
            let x: Int = ch.x0 + lx
            let s: Int = ch.surf[lx]
            let base: Int = lx * H
            let top: Int = ch.skyTop[lx]
            var y: Int = 0
            while y < H {
                var k: UInt8 = 0
                if over {
                    if y > s + 1 {
                        let d: Int = y - s
                        k = d < 14 ? 1 : (y < 330 ? 2 : 3)
                    }
                } else if y > s + 1 || y < ch.ceilY[lx] - 1 {
                    k = 4
                }
                if hasWalls && ch.walls[base + y] != 0 {
                    k = ch.walls[base + y]
                } else if k == 0 && y >= top && ch.tiles[base + y] == 0 {
                    k = enclosedWall(x, y, ch, lx)
                }
                b[base + y] = k
                y += 1
            }
        }
        ch.back = b
        ch.backRev = ch.rev
        return b
    }

    /// Air under a roof with walls on both sides (a house, a ruin) gets a wall behind it
    func enclosedWall(_ x: Int, _ y: Int, _ ch: Chunk, _ lx: Int) -> UInt8 {
        var roof: Tile = .air
        var k: Int = 1
        while k <= 12 {
            let t: Tile = ch.get(lx, y - k)
            if t.opaque && t.solid {
                switch t {
                case .planks, .brick, .crackedBrick, .mossBrick, .sandstone, .hay: roof = t
                default: return 0
                }
                break
            }
            k += 1
        }
        if roof == .air { return 0 }
        var leftOK: Bool = false
        var d: Int = 1
        while d <= 12 {
            let t: Tile = tile(x - d, y)
            if t.solid || t == .glass { leftOK = true; break }
            d += 1
        }
        if !leftOK { return 0 }
        d = 1
        while d <= 12 {
            let t: Tile = tile(x + d, y)
            if t.solid || t == .glass { return wallForRoof(roof) }
            d += 1
        }
        return 0
    }
}

// ===== p22_walls_doors =====

// MARK: - Background walls (no collision) and doors

let wallKinds: [Int] = [1, 2, 4, 5, 6, 7]

func wallName(_ k: Int) -> String {
    switch k {
    case 1: return "Dirt Wall"
    case 2: return "Stone Wall"
    case 3: return "Deep Rock Wall"
    case 4: return "Ash Wall"
    case 5: return "Plank Wall"
    case 6: return "Brick Wall"
    case 7: return "Sandstone Wall"
    default: return "Wall"
    }
}

func wallSourceTile(_ k: Int) -> Tile {
    switch k {
    case 1: return .dirt
    case 2: return .stone
    case 3: return .deepRock
    case 4: return .ashStone
    case 5: return .planks
    case 6: return .brick
    default: return .sandstone
    }
}

/// Inventory icon: a darkened block with a frame, so walls read differently from blocks
func wallIcon(_ k: Int) -> PixelBuf {
    var b: PixelBuf = tileBuf(wallSourceTile(k))
    for i in 0..<b.px.count {
        let c: UInt32 = b.px[i]
        if (c >> 24) != 0 { b.px[i] = 0xFF000000 | shadeRGB(c & 0xFFFFFF, 0.6) }
    }
    for i in 0..<8 {
        b.set(i, 0, 0x2A2420); b.set(i, 7, 0x2A2420); b.set(0, i, 0x2A2420); b.set(7, i, 0x2A2420)
    }
    return b
}

extension World {
    func wallAt(_ x: Int, _ y: Int) -> Int {
        if y < 0 || y >= H { return 0 }
        let cx: Int = floorDiv(x, chunkW)
        guard let c = chunk(cx), !c.walls.isEmpty else { return 0 }
        return Int(c.walls[(x - cx * chunkW) * H + y])
    }

    @discardableResult
    func setWall(_ x: Int, _ y: Int, _ k: Int) -> Bool {
        if y < 1 || y >= H - 1 { return false }
        let cx: Int = floorDiv(x, chunkW)
        guard let c = chunk(cx) else { return false }
        if c.walls.isEmpty {
            if k == 0 { return false }
            c.walls = [UInt8](repeating: 0, count: chunkW * H)
        }
        let i: Int = (x - cx * chunkW) * H + y
        if Int(c.walls[i]) == k { return false }
        c.walls[i] = UInt8(clampI(k, 0, 255))
        c.dirty = true
        c.rev &+= 1
        c.bumpRows(y - 1, y + 1)
        version += 1
        noteEdit(x, y)
        return true
    }
}

func isDoor(_ t: Tile) -> Bool { return t == .doorClosed || t == .doorOpen }

extension Game {
    /// The two cells of the door containing (x, y): (top, bottom)
    func doorCells(_ x: Int, _ y: Int) -> (Int, Int) {
        var top: Int = y
        var bot: Int = y
        if isDoor(world.tile(x, y - 1)) && !isDoor(world.tile(x, y + 1)) { top = y - 1 }
        else if isDoor(world.tile(x, y + 1)) { bot = y + 1 }
        return (top, bot)
    }

    func doorBlocked(_ x: Int, _ top: Int, _ bot: Int) -> Bool {
        let x0: Double = Double(x), x1: Double = Double(x + 1)
        let y0: Double = Double(top), y1: Double = Double(bot + 1)
        if pb.right > x0 + 0.05 && pb.left < x1 - 0.05 && pb.y > y0 + 0.05 && pb.top < y1 - 0.05 { return true }
        for m in mobs where m.hp > 0 {
            if m.b.right > x0 + 0.05 && m.b.left < x1 - 0.05 && m.b.y > y0 + 0.05 && m.b.top < y1 - 0.05 { return true }
        }
        return false
    }

    func setDoor(_ x: Int, _ y: Int, open: Bool) {
        let c: (Int, Int) = doorCells(x, y)
        if !open && doorBlocked(x, c.0, c.1) { return }
        let t: Tile = open ? .doorOpen : .doorClosed
        for yy in c.0...c.1 where isDoor(world.tile(x, yy)) { world.set(x, yy, t) }
    }

    func toggleDoor(_ x: Int, _ y: Int) {
        let open: Bool = world.tile(x, y) == .doorClosed
        setDoor(x, y, open: open)
        spawnParticles(Double(x) + 0.5, Double(y) + 0.5, 0xA97B45, 2, 1.5, 0.3, 8)
    }

    /// Walking into a closed door opens it (tap a door to close it again)
    func doorTouch(_ ix: Double) {
        if ix != 0 {
            let sgn: Double = ix > 0 ? 1.0 : -1.0
            let reachX: Double = pb.w * 0.5 + 0.2
            let fxd: Double = pb.x + sgn * reachX
            let fx: Int = Int(floor(fxd))
            for yy in [Int(floor(pb.y - 0.5)), Int(floor(pb.y - 1.4))] {
                if world.tile(fx, yy) == .doorClosed { setDoor(fx, yy, open: true); break }
            }
        }
    }

    func placeDoor(_ tx: Int, _ ty0: Int) -> Bool {
        // aim at either cell: the door always stands on the floor
        var ty: Int = ty0
        if world.tile(tx, ty + 1) == .air && world.tile(tx, ty + 2).solid { ty += 1 }
        if !world.tile(tx, ty + 1).solid { return false }
        for yy in [ty, ty - 1] {
            let cur: Tile = world.tile(tx, yy)
            if !(cur == .air || (cur.isPlant && cur != .torch && cur != .lantern)) { return false }
        }
        if doorBlocked(tx, ty - 1, ty) { return false }
        if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return false }
        world.set(tx, ty - 1, .doorClosed)
        world.set(tx, ty, .doorClosed)
        return true
    }

    func usePlaceWall(_ k: Int) {
        if placeCD > 0 { return }
        let tx: Int = Int(floor(aimX))
        let ty: Int = Int(floor(aimY))
        if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return }
        if world.wallAt(tx, ty) != 0 { return }
        if world.setWall(tx, ty, k) {
            if !isCreative { inv.removeAt(sel, 1) }
            placeCD = 0.06
            swingT = 0.12
            swingDir = aimX >= pb.x ? 1 : -1
            facing = swingDir
            bumpHUD()
        }
    }

    /// Pickaxes and axes knock out placed walls when nothing is in front of them
    func mineWall(_ tx: Int, _ ty: Int, _ kind: ToolType?, _ tier: Tier?, _ dt: Double) -> Bool {
        let k: Int = world.wallAt(tx, ty)
        if k == 0 || kind == nil || kind == .hoe { return false }
        if !inReach(Double(tx) + 0.5, Double(ty) + 0.5) { return false }
        if mineX != tx || mineY != ty { mineP = 0; mineX = tx; mineY = ty }
        mining = true
        mineNeed = 0.9
        let sp: Double = isCreative ? 1000 : (tier?.mineSpeed ?? 1.0)
        mineP += dt * sp
        if useCD <= 0 {
            swingT = 0.22
            swingDir = aimX >= pb.x ? 1 : -1
            facing = swingDir
            useCD = 0.26
        }
        if mineP >= mineNeed {
            mineP = 0
            mining = false
            world.setWall(tx, ty, 0)
            spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, shadeRGB(wallSourceTile(k).def.colors.first ?? 0x888888, 0.6), 5, 3.0, 0.4, 14)
            if !isCreative { spawnDrop(Stack(item: .wall(k), count: 1), Double(tx) + 0.5, Double(ty) + 0.5, 0, -2) }
        }
        return true
    }
}

// ===== p23_fast =====

// MARK: - Fast enum comparisons
// In debug builds (which Playgrounds uses) "==" on raw-value enums otherwise goes through a slow
// generic RawRepresentable path. These concrete versions compare the raw values directly.

extension TStyle {
    static func == (a: TStyle, b: TStyle) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: TStyle, b: TStyle) -> Bool { return a.rawValue != b.rawValue }
}

extension Tile {
    static func == (a: Tile, b: Tile) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Tile, b: Tile) -> Bool { return a.rawValue != b.rawValue }
}

extension Tier {
    static func == (a: Tier, b: Tier) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Tier, b: Tier) -> Bool { return a.rawValue != b.rawValue }
}

extension ToolType {
    static func == (a: ToolType, b: ToolType) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: ToolType, b: ToolType) -> Bool { return a.rawValue != b.rawValue }
}

extension ArmorSlot {
    static func == (a: ArmorSlot, b: ArmorSlot) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: ArmorSlot, b: ArmorSlot) -> Bool { return a.rawValue != b.rawValue }
}

extension Mat {
    static func == (a: Mat, b: Mat) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Mat, b: Mat) -> Bool { return a.rawValue != b.rawValue }
}

extension Food {
    static func == (a: Food, b: Food) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Food, b: Food) -> Bool { return a.rawValue != b.rawValue }
}

extension GunType {
    static func == (a: GunType, b: GunType) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: GunType, b: GunType) -> Bool { return a.rawValue != b.rawValue }
}

extension AmmoType {
    static func == (a: AmmoType, b: AmmoType) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: AmmoType, b: AmmoType) -> Bool { return a.rawValue != b.rawValue }
}

extension PartType {
    static func == (a: PartType, b: PartType) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: PartType, b: PartType) -> Bool { return a.rawValue != b.rawValue }
}

extension Gadget {
    static func == (a: Gadget, b: Gadget) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Gadget, b: Gadget) -> Bool { return a.rawValue != b.rawValue }
}

extension Station {
    static func == (a: Station, b: Station) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Station, b: Station) -> Bool { return a.rawValue != b.rawValue }
}

extension RecipeCat {
    static func == (a: RecipeCat, b: RecipeCat) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: RecipeCat, b: RecipeCat) -> Bool { return a.rawValue != b.rawValue }
}

extension Biome {
    static func == (a: Biome, b: Biome) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Biome, b: Biome) -> Bool { return a.rawValue != b.rawValue }
}

extension Dimension {
    static func == (a: Dimension, b: Dimension) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Dimension, b: Dimension) -> Bool { return a.rawValue != b.rawValue }
}

extension LairKind {
    static func == (a: LairKind, b: LairKind) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: LairKind, b: LairKind) -> Bool { return a.rawValue != b.rawValue }
}

extension RareKind {
    static func == (a: RareKind, b: RareKind) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: RareKind, b: RareKind) -> Bool { return a.rawValue != b.rawValue }
}

extension ProjKind {
    static func == (a: ProjKind, b: ProjKind) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: ProjKind, b: ProjKind) -> Bool { return a.rawValue != b.rawValue }
}

extension MobKind {
    static func == (a: MobKind, b: MobKind) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: MobKind, b: MobKind) -> Bool { return a.rawValue != b.rawValue }
}

extension Behavior {
    static func == (a: Behavior, b: Behavior) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: Behavior, b: Behavior) -> Bool { return a.rawValue != b.rawValue }
}

extension BossAtk {
    static func == (a: BossAtk, b: BossAtk) -> Bool { return a.rawValue == b.rawValue }
    static func != (a: BossAtk, b: BossAtk) -> Bool { return a.rawValue != b.rawValue }
}

// ===== p24_painter =====

// MARK: - Fast terrain section painter
// Paints a 16x16-tile section into a premultiplied ARGB pixel buffer using raw pointers,
// so it stays quick in Playgrounds' debug builds. The UI turns the result into an image.

/// Premultiplies non-premultiplied ARGB pixels in place (only pixels with partial alpha change).
func premultiplyARGB(_ px: inout [UInt32]) {
    let n: Int = px.count
    px.withUnsafeMutableBufferPointer { bp in
        guard let p = bp.baseAddress else { return }
        var i: Int = 0
        while i < n {
            let c: UInt32 = p[i]
            let a: UInt32 = c >> 24
            if a == 0 {
                p[i] = 0
            } else if a != 255 {
                let r: UInt32 = ((c >> 16) & 255) * a / 255
                let g: UInt32 = ((c >> 8) & 255) * a / 255
                let b: UInt32 = (c & 255) * a / 255
                p[i] = (a << 24) | (r << 16) | (g << 8) | b
            }
            i += 1
        }
    }
}

final class SectionPainter: @unchecked Sendable {
    static let shared: SectionPainter = SectionPainter()

    let tileCount: Int
    /// 8x8 art for every tile, by raw value (64 pixels each)
    var tilePx: [UInt32]
    /// 0 = fully transparent, 1 = fully opaque, 2 = mixed alpha
    var tileKind: [Int]
    /// darkened 8x8 backdrop walls, by wall kind - 1
    var wallPx: [UInt32]
    var wallBufs: [PixelBuf]
    var tileBufs: [PixelBuf]
    let wallCount: Int

    init() {
        var tb: [PixelBuf] = []
        for t in Tile.allCases { tb.append(tileBuf(t)) }
        tileBufs = tb
        tileCount = tb.count
        var px: [UInt32] = [UInt32](repeating: 0, count: 256 * 64)
        var kinds: [Int] = [Int](repeating: 0, count: 256)
        for (i, b) in tb.enumerated() {
            var allClear: Bool = true
            var allSolid: Bool = true
            for k in 0..<64 {
                let c: UInt32 = k < b.px.count ? b.px[k] : 0
                px[i * 64 + k] = c
                let a: UInt32 = c >> 24
                if a != 0 { allClear = false }
                if a != 255 { allSolid = false }
            }
            kinds[i] = allClear ? 0 : (allSolid ? 1 : 2)
        }
        tilePx = px
        tileKind = kinds
        let srcs: [Tile] = [.dirt, .stone, .deepRock, .ashStone, .planks, .brick, .sandstone]
        var ws: [PixelBuf] = []
        var wp: [UInt32] = []
        for (k, s) in srcs.enumerated() {
            var w: PixelBuf = tileBuf(s)
            let f: Double = k >= 4 ? 0.55 : 0.42
            for i in 0..<w.px.count {
                let c: UInt32 = w.px[i]
                w.px[i] = 0xFF000000 | shadeRGB(c & 0xFFFFFF, f)
            }
            ws.append(w)
            for i in 0..<64 { wp.append(i < w.px.count ? w.px[i] : 0xFF000000) }
        }
        wallBufs = ws
        wallPx = wp
        wallCount = srcs.count
    }

    /// Paints section `sy` (rows sy*16 ..< sy*16+16) of a chunk. Returns 128x128 premultiplied ARGB.
    func paint(_ world: World, _ ch: Chunk, _ sy: Int) -> [UInt32] {
        let W: Int = chunkW * 8
        let Hh: Int = 16 * 8
        var buf: [UInt32] = [UInt32](repeating: 0, count: W * Hh)
        let H: Int = ch.H
        let y0: Int = sy * 16
        let back: [UInt8] = world.backdrop(ch)
        let opT: [Bool] = Tile.opaqueTable
        let soT: [Bool] = Tile.solidTable
        let wc: Int = wallCount
        buf.withUnsafeMutableBufferPointer { bb in
            ch.tiles.withUnsafeBufferPointer { tb in
                back.withUnsafeBufferPointer { kb in
                    tilePx.withUnsafeBufferPointer { ab in
                        tileKind.withUnsafeBufferPointer { kib in
                            wallPx.withUnsafeBufferPointer { wb in
                                opT.withUnsafeBufferPointer { ob in
                                    soT.withUnsafeBufferPointer { sb in
                                        guard let out = bb.baseAddress, let tiles = tb.baseAddress, let backs = kb.baseAddress,
                                              let art = ab.baseAddress, let tk = kib.baseAddress, let walls = wb.baseAddress,
                                              let opq = ob.baseAddress, let sol = sb.baseAddress else { return }
                                        var lx: Int = 0
                                        while lx < chunkW {
                                            let colBase: Int = lx * H
                                            let ox: Int = lx * 8
                                            var ly: Int = 0
                                            while ly < 16 {
                                                let y: Int = y0 + ly
                                                if y < 0 || y >= H { ly += 1; continue }
                                                let raw: Int = i8(tiles[colBase + y])
                                                let oy: Int = ly * 8
                                                let opaque: Bool = opq[raw]
                                                let wall: Int = i8(backs[colBase + y]) - 1
                                                if wall >= 0 && wall < wc && !opaque {
                                                    let src: UnsafePointer<UInt32> = walls + wall * 64
                                                    var yy: Int = 0
                                                    while yy < 8 {
                                                        let row: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
                                                        let s: UnsafePointer<UInt32> = src + yy * 8
                                                        row[0] = s[0]; row[1] = s[1]; row[2] = s[2]; row[3] = s[3]
                                                        row[4] = s[4]; row[5] = s[5]; row[6] = s[6]; row[7] = s[7]
                                                        yy += 1
                                                    }
                                                }
                                                if raw == 0 { ly += 1; continue }
                                                let kind: Int = tk[raw]
                                                let src: UnsafePointer<UInt32> = art + raw * 64
                                                if kind == 1 {
                                                    var yy: Int = 0
                                                    while yy < 8 {
                                                        let row: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
                                                        let s: UnsafePointer<UInt32> = src + yy * 8
                                                        row[0] = s[0]; row[1] = s[1]; row[2] = s[2]; row[3] = s[3]
                                                        row[4] = s[4]; row[5] = s[5]; row[6] = s[6]; row[7] = s[7]
                                                        yy += 1
                                                    }
                                                } else if kind == 2 {
                                                    var yy: Int = 0
                                                    while yy < 8 {
                                                        let row: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
                                                        var xx: Int = 0
                                                        while xx < 8 {
                                                            let c: UInt32 = src[yy * 8 + xx]
                                                            let a: UInt32 = c >> 24
                                                            if a == 255 {
                                                                row[xx] = c
                                                            } else if a != 0 {
                                                                let under: UInt32 = row[xx]
                                                                if (under >> 24) == 0 {
                                                                    row[xx] = c
                                                                } else {
                                                                    let f: Double = Double(a) / 255.0
                                                                    row[xx] = 0xFF000000 | mixRGB(under & 0xFFFFFF, c & 0xFFFFFF, f)
                                                                }
                                                            }
                                                            xx += 1
                                                        }
                                                        yy += 1
                                                    }
                                                }
                                                // darker rim where a solid block meets open space (easier to read the terrain)
                                                if sol[raw] && opaque {
                                                    let upOpaque: Bool = y > 0 ? opq[i8(tiles[colBase + y - 1])] : false
                                                    if !upOpaque {
                                                        let row: UnsafeMutablePointer<UInt32> = out + oy * W + ox
                                                        var xx: Int = 0
                                                        while xx < 8 {
                                                            row[xx] = 0xFF000000 | shadeRGB(row[xx] & 0xFFFFFF, 1.12)
                                                            xx += 1
                                                        }
                                                    }
                                                    let dnOpaque: Bool = y + 1 < H ? opq[i8(tiles[colBase + y + 1])] : true
                                                    if !dnOpaque {
                                                        let row: UnsafeMutablePointer<UInt32> = out + (oy + 7) * W + ox
                                                        var xx: Int = 0
                                                        while xx < 8 {
                                                            row[xx] = 0xFF000000 | shadeRGB(row[xx] & 0xFFFFFF, 0.7)
                                                            xx += 1
                                                        }
                                                    }
                                                }
                                                ly += 1
                                            }
                                            lx += 1
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        premultiplyARGB(&buf)
        return buf
    }
}

// ===== p25_hud =====

// MARK: - HUD change detection
// The HUD only redraws when something it shows has changed (checked a few times a second).

extension Game {
    func hudKey() -> Int {
        var h: Hasher = Hasher()
        h.combine(Int(hp * 2.0))
        h.combine(Int(maxHP))
        h.combine(Int(hunger * 2.0))
        h.combine(Int(air * 2.0))
        h.combine(Int(inv.defense))
        h.combine(sel)
        for i in 0..<Inventory.hotbarCount {
            if let s = inv.slots[i] {
                h.combine(s.item)
                h.combine(s.count)
                h.combine(s.extra)
            } else {
                h.combine(-1)
            }
        }
        if showInventory || openChest != nil {
            for i in Inventory.hotbarCount..<inv.slots.count {
                if let s = inv.slots[i] {
                    h.combine(i)
                    h.combine(s.item)
                    h.combine(s.count)
                }
            }
            for a in inv.armor { h.combine(a?.item) }
            h.combine(carry?.item)
            h.combine(carry?.count ?? 0)
            if let p = openChest {
                let items: [Stack] = world.chestItems(p.x, p.y)
                for s in items {
                    h.combine(s.item)
                    h.combine(s.count)
                }
            }
        }
        h.combine(reloadT > 0)
        h.combine(mounted != nil)
        h.combine(inVehicle != nil)
        h.combine(flying || noclip)
        h.combine(activeBoss != nil)
        h.combine(Int(bossBarFrac * 120.0))
        h.combine(gotMap)
        h.combine(dayCount)
        h.combine(isNight)
        h.combine(world.dim.rawValue)
        h.combine(tilePx)
        if settings.showCoords {
            h.combine(Int(floor(pb.x)))
            h.combine(Int(floor(pb.y)))
        }
        h.combine(vehicleHelpKey())
        h.combine(message ?? "")
        if settings.showFPS { h.combine(Int(renderFPS)) }
        return h.finalize()
    }
}

// ===== p26_vehicle_ux =====

// MARK: - Vehicle building made simple: kits, attach hints, a checklist, drive / pack-up

struct KitPart {
    var dx: Int
    var dy: Int
    var p: PartType
}

/// Ready-made layouts (dy grows downwards; row 0 is the top)
func kitLayout(_ g: Gadget) -> [KitPart] {
    switch g {
    case .carKit:
        return [KitPart(dx: 1, dy: 0, p: .seat), KitPart(dx: 2, dy: 0, p: .steering),
                KitPart(dx: 0, dy: 1, p: .fuelTank), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .frame), KitPart(dx: 3, dy: 1, p: .engine),
                KitPart(dx: 0, dy: 2, p: .wheel), KitPart(dx: 3, dy: 2, p: .wheel)]
    case .boatKit:
        return [KitPart(dx: 1, dy: 0, p: .seat), KitPart(dx: 2, dy: 0, p: .steering),
                KitPart(dx: 0, dy: 1, p: .hull), KitPart(dx: 1, dy: 1, p: .hull), KitPart(dx: 2, dy: 1, p: .hull), KitPart(dx: 3, dy: 1, p: .paddle)]
    case .motorboatKit:
        return [KitPart(dx: 1, dy: 0, p: .fuelTank), KitPart(dx: 2, dy: 0, p: .seat), KitPart(dx: 3, dy: 0, p: .steering),
                KitPart(dx: 0, dy: 1, p: .propeller), KitPart(dx: 1, dy: 1, p: .engine), KitPart(dx: 2, dy: 1, p: .hull), KitPart(dx: 3, dy: 1, p: .hull), KitPart(dx: 4, dy: 1, p: .hull)]
    default:
        return []
    }
}

func isKit(_ g: Gadget) -> Bool {
    return g == .carKit || g == .boatKit || g == .motorboatKit
}

struct VehicleCheck {
    var title: String
    var lines: [String]
    var oks: [Bool]
    var ready: Bool
    var hint: String
}

/// A spot where the held part could go, in world coordinates (top-left of the cell)
struct GhostCell {
    var x: Double
    var y: Double
    var ok: Bool
    var ang: Double = 0
}

extension Game {
    // MARK: kits

    /// Where a kit would land if placed at the aim point: (left tile x, bottom tile y, fits).
    /// Tries a few spots around the aim so small bumps, plants or trees don't block it.
    func kitPlacement(_ g: Gadget, _ ax: Double, _ ay: Double) -> (Int, Int, Bool) {
        let layout: [KitPart] = kitLayout(g)
        var w: Int = 1
        var h: Int = 1
        for k in layout { w = max(w, k.dx + 1); h = max(h, k.dy + 1) }
        let baseLeft: Int = Int(floor(ax)) - w / 2
        let shifts: [Int] = [0, 1, -1, 2, -2, 3, -3]
        var firstLeft: Int = baseLeft
        var firstBottom: Int = Int(floor(ay))
        var firstSet: Bool = false
        for sx in shifts {
            let left: Int = baseLeft + sx
            // drop down onto the ground (or the water surface) below the aim point
            var bottom: Int = Int(floor(ay))
            var n: Int = 0
            while n < 10 && !kitSupport(left, w, bottom + 1) {
                bottom += 1
                n += 1
            }
            if !firstSet {
                firstSet = true
                firstLeft = left
                firstBottom = bottom
            }
            var lift: Int = 0
            while lift <= 3 {
                let by: Int = bottom - lift
                if kitFits(layout, left, by, h) { return (left, by, true) }
                lift += 1
            }
        }
        return (firstLeft, firstBottom, false)
    }

    /// Something to rest on under any column of the kit
    func kitSupport(_ left: Int, _ w: Int, _ y: Int) -> Bool {
        var x: Int = left
        while x < left + w {
            let t: Tile = world.tile(x, y)
            if t.solid || t.liquid || t == .platform { return true }
            x += 1
        }
        return false
    }

    func kitFits(_ layout: [KitPart], _ left: Int, _ bottom: Int, _ h: Int) -> Bool {
        for k in layout {
            let tx: Int = left + k.dx
            let ty: Int = bottom - (h - 1) + k.dy
            if world.solid(tx, ty) { return false }
        }
        return true
    }

    func placeKit(_ g: Gadget) {
        let layout: [KitPart] = kitLayout(g)
        if layout.isEmpty { return }
        if !inReach(aimX, aimY) {
            say("Tap closer to you to place it.", 1.5)
            return
        }
        let pl: (Int, Int, Bool) = kitPlacement(g, aimX, aimY)
        if !pl.2 {
            say("Not enough room here. Find open, flat ground (or water for a boat).", 2.5)
            return
        }
        var h: Int = 1
        for k in layout { h = max(h, k.dy + 1) }
        let v: Vehicle = Vehicle(id: newID(), first: layout[0].p, x: 0, y: 0)
        v.parts.removeAll()
        for k in layout { v.parts[PartCell(dx: k.dx, dy: k.dy)] = k.p }
        v.recompute(keepAnchor: false)
        v.placeBox(left: Double(pl.0), bottom: Double(pl.1 + 1))
        _ = h
        v.kit = g.rawValue
        if v.engines > 0 { v.fuel = min(v.fuelCapacity, 40.0) }
        vehicles.append(v)
        if !isCreative { inv.removeAt(sel, 1) }
        useCD = 0.3
        swingT = 0.15
        spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0xFFF0A0, 10, 3.0, 0.5, 6)
        say("Placed! Walk up to it and press DRIVE.", 3.0)
        bumpHUD()
    }

    // MARK: finding vehicles

    func nearestVehicle(_ maxDist: Double) -> Vehicle? {
        var best: Vehicle? = nil
        var bd: Double = maxDist
        for v in vehicles {
            let dx: Double = abs(v.b.x - pb.x) - v.b.w * 0.5
            let dy: Double = abs((v.b.y - v.b.h * 0.5) - (pb.y - pb.h * 0.5)) - v.b.h * 0.5
            let d: Double = max(0, max(dx, dy))
            if d <= bd {
                bd = d
                best = v
            }
        }
        return best
    }

    var holdingVehicleThing: Bool {
        guard let it = heldItem else { return false }
        switch it {
        case .part: return true
        case .gadget(let g): return g == .wrench || isKit(g)
        default: return false
        }
    }

    /// The vehicle the help box talks about (nil = no box)
    var vehicleHelpTarget: Vehicle? {
        if inVehicle != nil || dead { return nil }
        if holdingVehicleThing { return nearestVehicle(10) }
        return nearestVehicle(2.5)
    }

    /// The vehicle the DRIVE / PACK UP buttons act on
    var vehicleNearby: Vehicle? {
        if inVehicle != nil || mounted != nil || dead { return nil }
        return nearestVehicle(2.0)
    }

    // MARK: attaching parts

    /// Why a part can't go in a cell (nil = it can)
    func attachProblem(_ v: Vehicle, _ c: PartCell, _ p: PartType) -> String? {
        if v.parts[c] != nil { return "That spot is taken." }
        if !v.hasNeighbor(c) { return "Parts must touch the vehicle." }
        if p == .wheel {
            if v.parts[PartCell(dx: c.dx, dy: c.dy - 1)] == nil { return "Wheels go directly under another part." }
            if v.parts[PartCell(dx: c.dx, dy: c.dy + 1)] != nil { return "Wheels must be on the bottom." }
        }
        if p == .steering && !v.canAttach(c, p) { return "The steering wheel goes right next to the seat." }
        if (p == .propeller || p == .paddle) && !v.canAttach(c, p) { return "Propellers and paddles go on the end of the vehicle." }
        if !v.canAttach(c, p) { return "Can't attach that there." }
        let wp: (Double, Double) = v.cellPos(c)
        if world.boxSolid(wp.0 + 0.02, wp.1 + 0.02, wp.0 + 0.98, wp.1 + 0.98) {
            // a part under a vehicle that sits on the ground: lift the vehicle one block to make room
            if c.dy > v.maxY && canLift(v, c) { return nil }
            return "Something is in the way."
        }
        return nil
    }

    /// True if the whole vehicle (plus the new cell) would fit one block higher
    func canLift(_ v: Vehicle, _ extra: PartCell) -> Bool {
        var cells: [PartCell] = Array(v.parts.keys)
        cells.append(extra)
        for c in cells {
            let wp: (Double, Double) = v.cellPos(c)
            let y: Double = wp.1 - 1.0
            if world.boxSolid(wp.0 + 0.02, y + 0.02, wp.0 + 0.98, y + 0.98) { return false }
        }
        return true
    }

    /// Lifts the vehicle one block if the new cell is buried in the ground
    func liftIfBuried(_ v: Vehicle, _ c: PartCell) {
        let wp: (Double, Double) = v.cellPos(c)
        if world.boxSolid(wp.0 + 0.02, wp.1 + 0.02, wp.0 + 0.98, wp.1 + 0.98) {
            v.py -= 1.0
            v.vy = 0
            v.updateBox()
        }
    }

    /// Every free cell around a vehicle where the part would fit
    func attachSpots(_ v: Vehicle, _ p: PartType) -> [PartCell] {
        var out: [PartCell] = []
        var seen: Set<PartCell> = []
        for (c, _) in v.parts {
            let n: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy),
                                 PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
            for k in n {
                if seen.contains(k) || v.parts[k] != nil { continue }
                seen.insert(k)
                if attachProblem(v, k, p) == nil { out.append(k) }
            }
        }
        return out
    }

    /// Outlines drawn while holding a part (green = can attach here) or a kit (its footprint)
    func vehicleGhosts() -> [GhostCell] {
        guard let it = heldItem, inVehicle == nil, !dead else { return [] }
        var out: [GhostCell] = []
        switch it {
        case .part(let p):
            if let v = nearestVehicle(10) {
                for c in attachSpots(v, p) {
                    let wp: (Double, Double) = v.cellPos(c)
                    out.append(GhostCell(x: wp.0, y: wp.1, ok: true, ang: v.angle))
                }
            }
        case .gadget(let g):
            if isKit(g) && aimValid {
                let pl: (Int, Int, Bool) = kitPlacement(g, aimX, aimY)
                let layout: [KitPart] = kitLayout(g)
                var h: Int = 1
                for k in layout { h = max(h, k.dy + 1) }
                let ok: Bool = pl.2 && inReach(aimX, aimY)
                for k in layout {
                    out.append(GhostCell(x: Double(pl.0 + k.dx), y: Double(pl.1 - (h - 1) + k.dy), ok: ok))
                }
            }
        default:
            break
        }
        return out
    }

    // MARK: checklist

    func vehicleCheck(_ v: Vehicle) -> VehicleCheck {
        var lines: [String] = []
        var oks: [Bool] = []
        var hulls: Int = 0
        for (_, t) in v.parts where t == .hull { hulls += 1 }
        let isBoat: Bool = hulls > 0 && v.wheels < 2
        func add(_ ok: Bool, _ s: String) {
            lines.append(s)
            oks.append(ok)
        }
        add(v.hasSeat, "Seat")
        add(v.hasSteering, "Steering wheel (next to the seat)")
        var hint: String = ""
        if isBoat {
            let floats: Bool = v.buoyancy >= v.mass * 0.8
            add(floats, "Enough hull floats to stay up")
            let motor: Bool = v.engines > 0 && v.propellers > 0
            add(motor || v.paddles > 0, "Paddle, or engine + propeller")
            if v.engines > 0 { add(v.fuel > 0.5, fuelLine(v)) }
            hint = "Boats only move in water."
        } else {
            let wn: Int = v.wheels
            add(v.wheels >= 2, "2 wheels under the frame (\(wn)/2)")
            add(v.engines > 0, "Engine")
            add(v.fuel > 0.5, fuelLine(v))
            hint = "Refuel: hold coal or wood and tap the vehicle."
        }
        var ready: Bool = true
        for o in oks where !o { ready = false }
        let title: String = isBoat ? (v.engines > 0 ? "MOTORBOAT" : "BOAT") : "CAR"
        return VehicleCheck(title: title, lines: lines, oks: oks, ready: ready, hint: hint)
    }

    func fuelLine(_ v: Vehicle) -> String {
        let a: Int = Int(v.fuel)
        let b: Int = Int(v.fuelCapacity)
        return "Fuel \(a)/\(b)"
    }

    /// Changes whenever the help box or vehicle buttons would look different
    func vehicleHelpKey() -> Int {
        var k: Int = 0
        if let v = vehicleHelpTarget {
            k = v.id &* 31 &+ v.parts.count &* 7 &+ Int(v.fuel) &+ 1
        }
        if let v = vehicleNearby { k = k &* 13 &+ v.id &+ 5 }
        if holdingVehicleThing { k = k &* 3 &+ 1 }
        return k
    }

    // MARK: drive / pack up

    func driveNearby() {
        guard let v = vehicleNearby else { return }
        mountVehicle(v)
    }

    func packUpVehicle() {
        guard let v = vehicleNearby else { return }
        if v.rider { dismount() }
        var back: [Item] = []
        if v.kit >= 0, let g = Gadget(rawValue: v.kit), kitMatches(v, g) {
            back.append(.gadget(g))
        } else {
            for (_, t) in v.parts { back.append(.part(t)) }
        }
        for it in back { giveItem(it, 1) }
        vehicles.removeAll { $0.id == v.id }
        spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0xC8C8C8, 8, 3.0, 0.4, 6)
        say("Packed up. Place it again any time.", 2.0)
        bumpHUD()
    }

    func kitMatches(_ v: Vehicle, _ g: Gadget) -> Bool {
        let layout: [KitPart] = kitLayout(g)
        if layout.count != v.parts.count { return false }
        for k in layout {
            if v.parts[PartCell(dx: k.dx, dy: k.dy)] != k.p { return false }
        }
        return true
    }
}

// ===== u01_art =====

// MARK: - Art store (converts the procedural PixelBufs into SwiftUI images)

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let ir: UInt32 = (hex >> 16) & 255
        let ig: UInt32 = (hex >> 8) & 255
        let ib: UInt32 = hex & 255
        let r: Double = Double(ir) / 255.0
        let g: Double = Double(ig) / 255.0
        let b: Double = Double(ib) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

/// Fast path: pixels are already premultiplied ARGB words (0xAARRGGBB). No per-pixel work.
func makeCGImagePremul(_ px: [UInt32], _ w: Int, _ h: Int) -> CGImage? {
    if w <= 0 || h <= 0 || px.count < w * h { return nil }
    let data: Data = px.withUnsafeBufferPointer { bp in Data(buffer: bp) }
    guard let provider = CGDataProvider(data: data as CFData) else { return nil }
    let raw: UInt32 = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    let info: CGBitmapInfo = CGBitmapInfo(rawValue: raw)
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info,
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}

/// Pixels are non-premultiplied ARGB (what the art generators produce)
func makeCGImage(_ px: [UInt32], _ w: Int, _ h: Int) -> CGImage? {
    var p: [UInt32] = px
    premultiplyARGB(&p)
    return makeCGImagePremul(p, w, h)
}

func pixImage(_ b: PixelBuf) -> Image {
    if let cg = makeCGImage(b.px, b.w, b.h) {
        return Image(decorative: cg, scale: 1.0).interpolation(.none)
    }
    return Image(systemName: "questionmark")
}

/// A set of animation frames for one creature, with the metrics needed to stand it on the ground.
struct SpriteSet {
    var right: [Image]
    var left: [Image]
    var hurtR: [Image]
    var hurtL: [Image]
    var w: Int
    var h: Int
    var footRow: Int      // art pixel row of the bottom of the feet
    var centerCol: Double // art pixel column of the body centre (facing right)
    var scale: Double     // tiles per art pixel

    func frame(_ i: Int, left lf: Bool, hurt: Bool) -> Image {
        let n: Int = max(1, right.count)
        let k: Int = ((i % n) + n) % n
        if hurt { return lf ? hurtL[k] : hurtR[k] }
        return lf ? left[k] : right[k]
    }
}

func opaqueBounds(_ b: PixelBuf) -> (Int, Int, Int, Int) {
    var x0: Int = b.w
    var x1: Int = -1
    var y0: Int = b.h
    var y1: Int = -1
    for y in 0..<b.h {
        for x in 0..<b.w where (b.px[y * b.w + x] >> 24) != 0 {
            if x < x0 { x0 = x }
            if x > x1 { x1 = x }
            if y < y0 { y0 = y }
            if y > y1 { y1 = y }
        }
    }
    if x1 < 0 { return (0, 0, b.w - 1, b.h - 1) }
    return (x0, y0, x1, y1)
}

func makeSpriteSet(_ frames: [PixelBuf], hitH: Double, fixedScale: Double? = nil) -> SpriteSet {
    let f0: PixelBuf = frames.isEmpty ? PixelBuf(w: 1, h: 1) : frames[0]
    let bb: (Int, Int, Int, Int) = opaqueBounds(f0)
    let opaqueH: Double = Double(bb.3 - bb.1 + 1)
    var sc: Double = 0.125
    if let f = fixedScale { sc = f } else {
        sc = clampD(hitH * 1.12 / max(1.0, opaqueH), 0.05, 0.125)
    }
    var r: [Image] = []
    var l: [Image] = []
    var hr: [Image] = []
    var hl: [Image] = []
    for f in frames {
        r.append(pixImage(f))
        l.append(pixImage(f.flipped()))
        let t: PixelBuf = f.tinted(0xFF3030, 0.55)
        hr.append(pixImage(t))
        hl.append(pixImage(t.flipped()))
    }
    let foot: Int = bb.3     // outline pixel sits on the ground line
    let cc: Double = Double(bb.0 + bb.2 + 1) * 0.5
    return SpriteSet(right: r, left: l, hurtR: hr, hurtL: hl, w: f0.w, h: f0.h, footRow: foot, centerCol: cc, scale: sc)
}

func heartBuf(_ full: Bool) -> PixelBuf {
    let rows: [String] = [".rr.rr..", "rRrrrrr.", "rRrrrrr.", "rrrrrrr.", ".rrrrr..", "..rrr...", "...r....", "........"]
    let col: UInt32 = full ? 0xE02828 : 0x3A2A2A
    let hi: UInt32 = full ? 0xFF9090 : 0x5A4A4A
    var b: PixelBuf = bufFromRows(rows, ["r": col, "R": hi])
    b = padBuf(b)
    b.outline(0x101010)
    return b
}

func foodBuf(_ full: Bool) -> PixelBuf {
    let rows: [String] = ["....bb..", "...bmm..", "..mmmm..", ".mmMmm..", ".mmmm...", "bmmm....", "bb......", "........"]
    let m: UInt32 = full ? 0xC0703A : 0x3A2E26
    let mh: UInt32 = full ? 0xE8A070 : 0x4A3E36
    let bo: UInt32 = full ? 0xF0E8D8 : 0x50504C
    var b: PixelBuf = bufFromRows(rows, ["m": m, "M": mh, "b": bo])
    b = padBuf(b)
    b.outline(0x101010)
    return b
}

func bubbleBuf() -> PixelBuf {
    let rows: [String] = ["..bbb...", ".bWbbb..", "bWbbbbb.", "bbbbbbb.", "bbbbbbb.", ".bbbbb..", "..bbb...", "........"]
    var b: PixelBuf = bufFromRows(rows, ["b": 0x6AB8FF, "W": 0xFFFFFF])
    b = padBuf(b)
    b.outline(0x102040)
    return b
}

func shieldBuf() -> PixelBuf {
    let rows: [String] = ["sssssss.", "sSSSSSs.", "sSssSSs.", "sSSSSSs.", ".sSSSs..", ".sSSSs..", "..sss...", "........"]
    var b: PixelBuf = bufFromRows(rows, ["s": 0x9AA0AA, "S": 0xC8D0DA])
    b = padBuf(b)
    b.outline(0x101010)
    return b
}

func padBuf(_ b: PixelBuf) -> PixelBuf {
    var o = PixelBuf(w: b.w + 2, h: b.h + 2)
    o.blit(b, 1, 1)
    return o
}

final class Art: @unchecked Sendable {
    static let shared: Art = Art()

    var tiles: [Image] = []
    var tileBufs: [PixelBuf] = []
    var walls: [PixelBuf] = []
    var heartFull: Image
    var heartEmpty: Image
    var foodFull: Image
    var foodEmpty: Image
    var bubble: Image
    var shieldIcon: Image
    var boat: Image
    var boatL: Image
    var parts: [Image] = []
    private var icons: [Item: Image] = [:]
    private var mobSets: [Int: SpriteSet] = [:]
    private var playerSets: [Int: SpriteSet] = [:]
    var crack: [Image] = []

    init() {
        let painter: SectionPainter = SectionPainter.shared
        tileBufs = painter.tileBufs
        var ti: [Image] = []
        for b in painter.tileBufs { ti.append(pixImage(b)) }
        tiles = ti
        // dark backdrop walls, indexed by backdrop kind - 1
        walls = painter.wallBufs
        heartFull = pixImage(heartBuf(true))
        heartEmpty = pixImage(heartBuf(false))
        foodFull = pixImage(foodBuf(true))
        foodEmpty = pixImage(foodBuf(false))
        bubble = pixImage(bubbleBuf())
        shieldIcon = pixImage(shieldBuf())
        let bt: PixelBuf = spritePirateBoat()
        boat = pixImage(bt)
        boatL = pixImage(bt.flipped())
        var ps: [Image] = []
        for p in PartType.allCases { ps.append(pixImage(partBuf(p))) }
        parts = ps
        var cr: [Image] = []
        for stage in 0..<5 {
            var b = PixelBuf(w: 8, h: 8)
            var rng = RNG(UInt64(stage + 3))
            let n: Int = 3 + stage * 4
            for _ in 0..<n { b.set(rng.int(8), rng.int(8), 0x101010) }
            if stage >= 2 { b.line(1, 2, 6, 5, 0x101010) }
            if stage >= 3 { b.line(5, 0, 2, 7, 0x101010) }
            cr.append(pixImage(b))
        }
        crack = cr
    }

    func tile(_ t: Tile) -> Image { return tiles[Int(t.rawValue)] }

    func icon(_ it: Item) -> Image {
        if let i = icons[it] { return i }
        let img: Image = pixImage(itemBuf(it))
        icons[it] = img
        return img
    }

    func playerSet(_ g: Game) -> SpriteSet {
        let key: Int = g.armorKey
        if let s = playerSets[key] { return s }
        let a = g.armorPieces()
        let st: HumanStyle = playerStyle(hairIdx: g.settings.hair, scarfIdx: g.settings.scarf, head: a.0, chest: a.1, legs: a.2)
        let s: SpriteSet = makeSpriteSet(humanoidFrames(st), hitH: 1.8, fixedScale: 0.125)
        playerSets[key] = s
        return s
    }

    func previewPlayer(hair: Int, scarf: Int) -> Image {
        let st: HumanStyle = playerStyle(hairIdx: hair, scarfIdx: scarf, head: nil, chest: nil, legs: nil)
        let f: [PixelBuf] = humanoidFrames(st)
        return pixImage(f[0])
    }

    func mobSet(_ m: Mob) -> SpriteSet {
        var variant: Int = 0
        switch m.kind {
        case .zombie, .villager: variant = m.variant
        case .sheep: variant = m.sheared ? 1 : 0
        case .wolf: variant = m.tame ? 1 : 0
        default: variant = 0
        }
        let key: Int = m.kind.rawValue * 16 + variant
        if let s = mobSets[key] { return s }
        let s: SpriteSet = buildMobSet(m.kind, variant)
        mobSets[key] = s
        return s
    }

    func kindSet(_ k: MobKind) -> SpriteSet {
        let key: Int = k.rawValue * 16
        if let s = mobSets[key] { return s }
        let s: SpriteSet = buildMobSet(k, 0)
        mobSets[key] = s
        return s
    }

    func buildMobSet(_ k: MobKind, _ v: Int) -> SpriteSet {
        let h: Double = mobDef(k).h
        switch k {
        case .pig: return makeSpriteSet(spritePig(), hitH: h)
        case .cow: return makeSpriteSet(spriteCow(), hitH: h)
        case .sheep: return makeSpriteSet(spriteSheep(shorn: v == 1), hitH: h)
        case .chicken: return makeSpriteSet(spriteChicken(), hitH: h)
        case .crow: return makeSpriteSet(spriteCrow(colorA: 0x2A2A34, colorB: 0x16161E), hitH: h)
        case .giraffe: return makeSpriteSet(spriteGiraffe(), hitH: h)
        case .frog: return makeSpriteSet(spriteFrog(), hitH: h)
        case .fish: return makeSpriteSet(spriteFish(), hitH: h)
        case .elephant: return makeSpriteSet(spriteElephant(), hitH: h)
        case .bear: return makeSpriteSet(spriteBear(kind: 0), hitH: h)
        case .grizzly: return makeSpriteSet(spriteBear(kind: 1), hitH: h)
        case .polarBear: return makeSpriteSet(spriteBear(kind: 2), hitH: h)
        case .tiger: return makeSpriteSet(spriteTiger(), hitH: h)
        case .wolf: return makeSpriteSet(spriteWolf(tamedColors: v == 1), hitH: h)
        case .cat: return makeSpriteSet(spriteCat(), hitH: h)
        case .zombie: return makeSpriteSet(humanoidFrames(zombieStyle(v)), hitH: h, fixedScale: 0.125)
        case .skeleton: return makeSpriteSet(humanoidFrames(skeletonStyle()), hitH: h, fixedScale: 0.125)
        case .slime: return makeSpriteSet(spriteSlime(main: 0x4EC04E, glow: 0x9AF09A, eye: 0x103010), hitH: h)
        case .bat: return makeSpriteSet(spriteBat(), hitH: h)
        case .scorpion: return makeSpriteSet(spriteScorpion(), hitH: h)
        case .wraith: return makeSpriteSet(spriteWraith(), hitH: h)
        case .villager: return makeSpriteSet(humanoidFrames(villagerStyle(v)), hitH: h, fixedScale: 0.125)
        case .pirate: return makeSpriteSet(humanoidFrames(pirateStyle(false)), hitH: h, fixedScale: 0.125)
        case .pirateGunner: return makeSpriteSet(humanoidFrames(pirateGunnerStyle()), hitH: h, fixedScale: 0.125)
        case .pirateCaptain: return makeSpriteSet(humanoidFrames(pirateStyle(true)), hitH: h, fixedScale: 0.125)
        case .imp: return makeSpriteSet(humanoidFrames(impStyle()), hitH: h, fixedScale: 0.125)
        case .emberSlime: return makeSpriteSet(spriteSlime(main: 0xE8601E, glow: 0xFFC060, eye: 0x401000), hitH: h)
        case .cinderBat:
            let f: [PixelBuf] = spriteBat().map { $0.tinted(0xFF6A1E, 0.45) }
            return makeSpriteSet(f, hitH: h)
        case .bearBoss: return makeSpriteSet(spriteBearBoss(), hitH: h)
        case .rex: return makeSpriteSet(spriteTRex(), hitH: h)
        }
    }
}

/// True for creatures drawn with the shared humanoid frames
func isHumanoid(_ k: MobKind) -> Bool {
    switch k {
    case .zombie, .skeleton, .villager, .pirate, .pirateGunner, .pirateCaptain, .imp: return true
    default: return false
    }
}

// ===== u02_render =====

// MARK: - World renderer (Canvas)

struct SectionEntry {
    var img: Image
    var rev: Int
    var used: Int
}

final class RenderCache: @unchecked Sendable {
    static let shared: RenderCache = RenderCache()
    var owner: ObjectIdentifier? = nil
    var sections: [Int: SectionEntry] = [:]
    var frame: Int = 0
    var lightRev: Int = -1
    var lightImg: Image? = nil
    var glowImg: Image? = nil
    var lightOX: Int = 0
    var lightOY: Int = 0
    var lightW: Int = 0
    var lightH: Int = 0
    var builtThisFrame: Int = 0
    var lastDraw: Double = 0

    func reset(for g: Game) {
        let id: ObjectIdentifier = ObjectIdentifier(g)
        if owner != id {
            owner = id
            sections.removeAll()
            lightRev = -1
            lightImg = nil
            glowImg = nil
        }
    }

    func key(_ dim: Int, _ cx: Int, _ sy: Int) -> Int {
        return ((cx &* 64) &+ sy) &* 2 &+ dim
    }

    func evict() {
        if sections.count < 420 { return }
        var keep: [Int: SectionEntry] = [:]
        for (k, e) in sections where frame - e.used < 240 { keep[k] = e }
        sections = keep
    }
}

/// Builds one 16x16-tile section as an image (tiles over a dark backdrop wall where underground).
func buildSection(_ g: Game, _ ch: Chunk, _ sy: Int) -> Image {
    let px: [UInt32] = SectionPainter.shared.paint(g.world, ch, sy)
    if let cg = makeCGImagePremul(px, chunkW * 8, 16 * 8) {
        return Image(decorative: cg, scale: 1.0).interpolation(.none)
    }
    return Image(systemName: "square")
}

// MARK: - Simple drawing helpers (all maths in Double, converted once; keeps the type checker fast)

func rgbColor(_ c: UInt32, _ a: Double = 1.0) -> Color {
    let rgb: UInt32 = c & 0xFFFFFF
    return Color(hex: rgb, alpha: a)
}

func mkRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
    let cx: CGFloat = CGFloat(x)
    let cy: CGFloat = CGFloat(y)
    let cw: CGFloat = CGFloat(w)
    let chh: CGFloat = CGFloat(h)
    return CGRect(x: cx, y: cy, width: cw, height: chh)
}

func mkPoint(_ x: Double, _ y: Double) -> CGPoint {
    let cx: CGFloat = CGFloat(x)
    let cy: CGFloat = CGFloat(y)
    return CGPoint(x: cx, y: cy)
}

func fillRect(_ ctx: inout GraphicsContext, _ r: CGRect, _ c: Color) {
    let p: Path = Path(r)
    ctx.fill(p, with: .color(c))
}

func fillOval(_ ctx: inout GraphicsContext, _ r: CGRect, _ c: Color) {
    let p: Path = Path(ellipseIn: r)
    ctx.fill(p, with: .color(c))
}

func strokeRect(_ ctx: inout GraphicsContext, _ r: CGRect, _ c: Color, _ w: Double) {
    let p: Path = Path(r)
    let lw: CGFloat = CGFloat(w)
    ctx.stroke(p, with: .color(c), lineWidth: lw)
}

func strokeLine(_ ctx: inout GraphicsContext, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ c: Color, _ w: Double) {
    var p: Path = Path()
    p.move(to: mkPoint(x0, y0))
    p.addLine(to: mkPoint(x1, y1))
    let lw: CGFloat = CGFloat(w)
    ctx.stroke(p, with: .color(c), lineWidth: lw)
}

func drawLabel(_ ctx: inout GraphicsContext, _ s: String, _ x: Double, _ y: Double, _ size: Double, _ c: Color) {
    let f: Font = Font.system(size: CGFloat(size), weight: .heavy, design: .monospaced)
    let t: Text = Text(s).font(f).foregroundColor(c)
    ctx.draw(t, at: mkPoint(x, y))
}

func vGradient(_ ctx: inout GraphicsContext, _ r: CGRect, _ colors: [Color], _ y0: Double, _ y1: Double) {
    let grad: Gradient = Gradient(colors: colors)
    let a: CGPoint = mkPoint(0, y0)
    let b: CGPoint = mkPoint(0, y1)
    let sh: GraphicsContext.Shading = .linearGradient(grad, startPoint: a, endPoint: b)
    ctx.fill(Path(r), with: sh)
}

struct View2D {
    var tp: Double
    var left: Double
    var top: Double
    var wTiles: Double
    var hTiles: Double

    func sx(_ x: Double) -> Double {
        let d: Double = x - left
        return d * tp
    }
    func sy(_ y: Double) -> Double {
        let d: Double = y - top
        return d * tp
    }
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        let ww: Double = w * tp
        let hh: Double = h * tp
        return mkRect(sx(x), sy(y), ww, hh)
    }
    func visible(_ x: Double, _ y: Double, _ pad: Double) -> Bool {
        let x0: Double = left - pad
        let x1: Double = left + wTiles + pad
        let y0: Double = top - pad
        let y1: Double = top + hTiles + pad
        if x < x0 || x > x1 { return false }
        if y < y0 || y > y1 { return false }
        return true
    }
}

enum WorldRenderer {
    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ g: Game) {
        let cache: RenderCache = RenderCache.shared
        cache.reset(for: g)
        cache.frame += 1
        cache.builtThisFrame = 0
        let nowT: Double = Date().timeIntervalSinceReferenceDate
        if cache.lastDraw > 0 {
            let d: Double = nowT - cache.lastDraw
            if d > 0.0001 && d < 1.0 { g.renderFPS = g.renderFPS * 0.9 + (1.0 / d) * 0.1 }
        }
        cache.lastDraw = nowT
        let W: Double = Double(size.width)
        let H: Double = Double(size.height)
        let tp: Double = Double(g.tilePx)
        let wT: Double = W / tp
        let hT: Double = H / tp
        var left: Double = g.camX - wT * 0.5
        var top: Double = g.camY - hT * 0.5
        if g.shake > 0 {
            let s: Double = g.shake * 0.3
            left += Double.random(in: -1.0...1.0) * s
            top += Double.random(in: -1.0...1.0) * s
        }
        left = floor(left * 8.0) / 8.0
        top = floor(top * 8.0) / 8.0
        let v: View2D = View2D(tp: tp, left: left, top: top, wTiles: wT, hTiles: hT)
        if skyHidden(g, v) {
            fillRect(&ctx, mkRect(0, 0, W, H), Color.black)
        } else {
            drawSky(&ctx, W, H, g, v)
        }
        drawSections(&ctx, g, v, cache)
        drawShips(&ctx, g, v)
        drawVehicles(&ctx, g, v)
        drawDrops(&ctx, g, v)
        drawMobs(&ctx, g, v)
        drawPlayer(&ctx, g, v)
        drawProjectiles(&ctx, g, v)
        drawParticles(&ctx, g, v)
        drawLight(&ctx, g, v, cache)
        drawOverlays(&ctx, W, H, g, v)
        drawFloats(&ctx, g, v)
        if g.showChunks || g.showHitboxes { drawDebug(&ctx, H, g, v) }
        if g.settings.showFPS {
            let fpsN: Int = Int(g.renderFPS.rounded())
            let tickS: String = String(format: "%.1f", g.tickMs)
            fillRect(&ctx, mkRect(W * 0.5 - 70.0, 4, 140, 20), Color.black.opacity(0.55))
            drawLabel(&ctx, "FPS \(fpsN)  tick \(tickS)ms", W * 0.5, 14, 11, Color.yellow)
        }
        cache.evict()
    }

    /// True when the whole view is underground (behind backdrop walls), so the sky can be skipped
    static func skyHidden(_ g: Game, _ v: View2D) -> Bool {
        let x0: Int = Int(floor(v.left))
        let x1: Int = Int(ceil(v.left + v.wTiles))
        let top: Int = Int(floor(v.top))
        var x: Int = x0
        while x <= x1 {
            let cx: Int = floorDiv(x, chunkW)
            guard let ch = g.world.chunk(cx) else { return false }
            let lx: Int = x - cx * chunkW
            if top <= ch.surf[lx] + 2 { return false }
            x += 1
        }
        return true
    }

    // MARK: sky & background

    static func drawSky(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D) {
        let full: CGRect = mkRect(0, 0, W, H)
        if g.world.dim == .umbral {
            let cols: [Color] = [Color(hex: 0x0C0614), Color(hex: 0x241030), Color(hex: 0x5A1A12)]
            let lava: Double = Double(umbralLava)
            vGradient(&ctx, full, cols, v.sy(20.0), v.sy(lava))
            // distant spires
            let col: Color = Color(hex: 0x1A0C22)
            let step: Double = v.tp
            let base: Double = v.sy(lava - 10.0)
            var sx: Double = 0
            var path: Path = Path()
            while sx < W {
                let wx: Double = v.left * 0.35 + sx / v.tp
                let n: Double = fbm1(wx / 18.0, 9091, 3)
                let h: Double = 20.0 + n * 60.0
                let lift: Double = h * v.tp * 0.5
                let topY: Double = base - lift
                let hh: Double = max(0.0, H - topY)
                path.addRect(mkRect(sx, topY, step + 1.0, hh))
                sx += step
            }
            ctx.fill(path, with: .color(col))
            return
        }
        let day: Double = g.dayFactor
        let biome: Biome = g.biomeHere
        var topC: UInt32 = mixRGB(0x060A1E, 0x3E86D8, day)
        var botC: UInt32 = mixRGB(0x18223E, 0xB4DCFF, day)
        let t: Double = g.timeOfDay
        var dusk: Double = 0
        if t > 0.46 && t < 0.62 {
            let d: Double = abs(t - 0.54)
            dusk = 1.0 - d / 0.08
        }
        if t > 0.88 || t < 0.04 {
            let tt: Double = t > 0.5 ? t - 1.0 : t
            let d: Double = abs(tt + 0.04)
            dusk = max(dusk, 1.0 - d / 0.08)
        }
        dusk = clampD(dusk, 0, 1)
        botC = mixRGB(botC, 0xF08A4A, dusk * 0.7)
        switch biome {
        case .desert, .savanna: botC = mixRGB(botC, 0xF0D8A0, 0.25 * day)
        case .tundra:
            topC = mixRGB(topC, 0xA8C0D8, 0.25 * day)
            botC = mixRGB(botC, 0xF0F4FA, 0.3 * day)
        case .swamp: botC = mixRGB(botC, 0x9AB08A, 0.35 * day)
        case .jungle: botC = mixRGB(botC, 0xA8E0B0, 0.2 * day)
        default: break
        }
        vGradient(&ctx, full, [rgbColor(topC), rgbColor(botC)], 0, H)
        // stars
        if day < 0.6 {
            let a: Double = (0.6 - day) / 0.6
            // three twinkle groups, one draw each
            for grp in 0..<3 {
                var path: Path = Path()
                var i: Int = grp
                while i < 70 {
                    let x: Double = hash2(i, 1, 5) * W
                    let y: Double = hash2(i, 2, 5) * H * 0.6
                    let s: Double = i % 7 == 0 ? 3.0 : 2.0
                    path.addRect(mkRect(x, y, s, s))
                    i += 3
                }
                let ph: Double = g.clock * 2.0 + Double(grp) * 2.1
                let tw: Double = 0.6 + 0.4 * sin(ph)
                ctx.fill(path, with: .color(Color.white.opacity(a * tw)))
            }
        }
        // sun & moon
        let ang: Double = t < 0.5 ? (t / 0.5) : ((t - 0.5) / 0.5)
        let bx: Double = (0.1 + 0.8 * ang) * W
        let arc: Double = sin(ang * Double.pi)
        let by: Double = H * (0.55 - 0.42 * arc)
        if t < 0.5 {
            fillRect(&ctx, mkRect(bx - 36.0, by - 36.0, 72.0, 72.0), Color(hex: 0xFFE680, alpha: 0.25))
            fillRect(&ctx, mkRect(bx - 28.0, by - 28.0, 56.0, 56.0), Color(hex: 0xFFD84A))
            fillRect(&ctx, mkRect(bx - 18.0, by - 18.0, 36.0, 36.0), Color(hex: 0xFFF2A0))
        } else {
            fillRect(&ctx, mkRect(bx - 22.0, by - 22.0, 44.0, 44.0), Color(hex: 0xE8ECF4))
            fillRect(&ctx, mkRect(bx - 8.0, by - 12.0, 10.0, 10.0), Color(hex: 0xC0C6D0))
            fillRect(&ctx, mkRect(bx + 6.0, by + 4.0, 8.0, 8.0), Color(hex: 0xC0C6D0))
        }
        // clouds
        let span: Double = W + 400.0
        let cloudShade: Double = max(day, 0.15)
        let cl: Color = rgbColor(mixRGB(0x4A5068, 0xFFFFFF, cloudShade), 0.85)
        for i in 0..<6 {
            let speed: Double = 6.0 + Double(i) * 2.0
            let par: Double = v.left * v.tp * 0.08
            var cx: Double = hash2(i, 3, 7) * span + g.clock * speed - par
            cx = cx.truncatingRemainder(dividingBy: span)
            if cx < 0 { cx += span }
            cx -= 200.0
            let cy: Double = 30.0 + hash2(i, 4, 7) * H * 0.28
            fillRect(&ctx, mkRect(cx, cy, 128.0, 20.0), cl)
            fillRect(&ctx, mkRect(cx + 24.0, cy - 16.0, 64.0, 16.0), cl)
        }
        // parallax hills (two layers)
        let baseY: Double = v.sy(Double(WorldGen.sea) + 6.0)
        if baseY > -200.0 {
            for k in 0..<2 {
                let factor: Double = k == 0 ? 0.2 : 0.45
                let amp: Double = k == 0 ? 36.0 : 22.0
                let squash: Double = k == 0 ? 0.6 : 0.8
                var colr: UInt32 = k == 0 ? 0x7FA0B8 : 0x5E8A6A
                if biome == .desert { colr = k == 0 ? 0xC8B080 : 0xB09060 }
                if biome == .tundra { colr = k == 0 ? 0xC0D0E0 : 0xA0B4C8 }
                if biome == .mountain { colr = k == 0 ? 0x8890A0 : 0x6A7080 }
                colr = mixRGB(0x101624, colr, max(0.2, day))
                let c: Color = rgbColor(colr)
                let step: Double = v.tp * 0.5
                let seed: UInt64 = UInt64(700 + k)
                let drop: Double = Double(k) * 30.0
                var sx: Double = 0
                var path: Path = Path()
                while sx < W {
                    let wx: Double = v.left * factor + sx / v.tp
                    let n: Double = fbm1(wx / 40.0, seed, 3)
                    let h: Double = n * amp + 6.0
                    let lift: Double = h * v.tp * squash
                    let topY: Double = baseY - lift + drop
                    let snap: Double = floor(topY / 4.0) * 4.0
                    let hh: Double = max(0.0, H - snap)
                    path.addRect(mkRect(sx, snap, step + 1.0, hh))
                    sx += step
                }
                ctx.fill(path, with: .color(c))
            }
        }
    }

    // MARK: terrain

    static func drawSections(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ cache: RenderCache) {
        let H: Int = g.world.H
        let tx0: Int = Int(floor(v.left))
        let tx1: Int = Int(ceil(v.left + v.wTiles))
        let ty0: Int = max(0, Int(floor(v.top)))
        let ty1: Int = min(H - 1, Int(ceil(v.top + v.hTiles)))
        if ty1 < ty0 { return }
        let c0: Int = floorDiv(tx0, chunkW)
        let c1: Int = floorDiv(tx1, chunkW)
        let s0: Int = ty0 / 16
        let s1: Int = ty1 / 16
        let dim: Int = g.world.dim.rawValue
        let secPx: Double = 16.0 * v.tp
        let cap: Int = cache.sections.isEmpty ? 10000 : 4
        for cx in c0...c1 {
            guard let ch = g.world.chunks[cx] else { continue }
            for sy in s0...s1 {
                let k: Int = cache.key(dim, cx, sy)
                var img: Image? = nil
                let srev: Int = sy < ch.secRev.count ? ch.secRev[sy] : ch.rev
                if var e = cache.sections[k] {
                    if e.rev == srev || cache.builtThisFrame >= cap {
                        e.used = cache.frame
                        cache.sections[k] = e
                        img = e.img
                    }
                }
                if img == nil {
                    let im: Image = buildSection(g, ch, sy)
                    cache.sections[k] = SectionEntry(img: im, rev: srev, used: cache.frame)
                    cache.builtThisFrame += 1
                    img = im
                }
                if let im = img {
                    let wx: Double = Double(cx * chunkW)
                    let wy: Double = Double(sy * 16)
                    ctx.draw(im, in: mkRect(v.sx(wx), v.sy(wy), secPx, secPx))
                }
            }
        }
    }

    // MARK: entities

    /// Creatures standing in front of open sky are not covered by the darkness overlay,
    /// so they are tinted by the light level where they stand instead.
    static func openShade(_ g: Game, _ x: Double, _ y: Double) -> Double {
        if g.fullBright || !g.light.valid { return 1.0 }
        let tx: Int = Int(floor(x))
        let ty: Int = Int(floor(y))
        let L: LightMap = g.light
        if !L.covers(tx, ty, tx, ty) { return 1.0 }
        if L.drawn.count != L.w * L.h { return 1.0 }
        let row: Int = (ty - L.oy) * L.w
        let i: Int = row + (tx - L.ox)
        if L.drawn[i] { return 1.0 }
        let lv: (Int, Int) = L.level(tx, ty)
        let a: Double = lightLUT[lv.0]
        let b: Double = lightLUT[lv.1]
        return clampD(max(a, b), 0.32, 1.0)
    }

    static func shadeColor(_ shade: Double) -> Color {
        let r: Double = shade * 0.92
        let gg: Double = shade * 0.96
        let b: Double = min(1.0, shade * 1.2)
        return Color(.sRGB, red: r, green: gg, blue: b, opacity: 1.0)
    }

    static func drawSet(_ ctx: inout GraphicsContext, _ v: View2D, _ s: SpriteSet, _ frame: Int, _ left: Bool, _ hurt: Bool, _ x: Double, _ y: Double, _ alpha: Double = 1.0, shade: Double = 1.0) {
        let px: Double = s.scale * v.tp
        let sw: Double = Double(s.w)
        let shh: Double = Double(s.h)
        let cc: Double = left ? (sw - s.centerCol) : s.centerCol
        let foot: Double = Double(s.footRow)
        var dx: Double = v.sx(x) - cc * px
        var dy: Double = v.sy(y) - foot * px
        let snap: Double = max(1.0, px)
        dx = (dx / snap).rounded() * snap
        dy = (dy / snap).rounded() * snap
        let r: CGRect = mkRect(dx, dy, sw * px, shh * px)
        let img: Image = s.frame(frame, left: left, hurt: hurt)
        if alpha < 0.999 || shade < 0.98 {
            var c: GraphicsContext = ctx
            c.opacity = alpha
            if shade < 0.98 { c.addFilter(.colorMultiply(shadeColor(shade))) }
            c.draw(img, in: r)
        } else {
            ctx.draw(img, in: r)
        }
    }

    static func walkFrame(_ m: Mob) -> Int {
        let a: Int = Int(m.anim * 2.0)
        return 1 + a % 2
    }

    static func mobFrame(_ m: Mob) -> Int {
        let moving: Bool = abs(m.b.vx) > 0.3
        if isHumanoid(m.kind) {
            if m.st == 3 {
                if m.kind == .pirateGunner || m.kind == .imp { return 6 }
                return 3
            }
            if m.st == 4 { return 4 }
            if m.st == 6 { return 6 }
            if m.blocking { return 5 }
            return moving ? walkFrame(m) : 0
        }
        let slow: Int = Int(m.anim * 1.5)
        switch m.kind {
        case .bearBoss:
            if m.st == 1 { return 2 }
            if m.st == 2 {
                let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
                if a == .melee || a == .sweep { return 3 }
                if a == .slam || a == .roar { return 2 }
            }
            return slow % 2
        case .rex:
            if m.st == 2 { return 2 }
            if m.st == 1 {
                let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
                if a == .melee || a == .sweep { return 2 }
            }
            return slow % 2
        case .slime, .emberSlime:
            return m.b.onGround ? 0 : 1
        case .bat, .cinderBat, .crow, .wraith, .fish:
            return slow
        default:
            return moving ? walkFrame(m) : 0
        }
    }

    static func drawMobs(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        let art: Art = Art.shared
        for m in g.mobs {
            if m.hp <= 0 && !m.downed { continue }
            if !v.visible(m.b.x, m.b.y, 8) { continue }
            let s: SpriteSet = art.mobSet(m)
            let left: Bool = m.dir < 0
            var alpha: Double = 1.0
            if m.kind == .wraith { alpha = 0.82 }
            if m.downed { alpha = 0.55 }
            let warn: Bool = m.isBoss && m.st == 1
            if warn { drawTelegraph(&ctx, g, v, m) }
            let shade: Double = openShade(g, m.b.x, m.b.cy)
            drawSet(&ctx, v, s, mobFrame(m), left, m.hurtT > 0, m.b.x, m.b.y, alpha, shade: shade)
            if m.burn > 0 {
                let fl: Double = 0.25 + 0.15 * sin(g.clock * 20.0)
                let r: CGRect = v.rect(m.b.left, m.b.top + m.b.h * 0.3, m.b.w, m.b.h * 0.7)
                fillRect(&ctx, r, Color(hex: 0xFF7020, alpha: fl))
            }
            if m.tame {
                drawLabel(&ctx, "♥", v.sx(m.b.x), v.sy(m.b.top) - 10.0, 12, Color(hex: 0xFF5A7A))
            }
            let damaged: Bool = m.hp < m.maxHP && m.hp > 0
            if !m.isBoss && damaged && m.kind != .villager {
                let w: Double = max(0.9, m.b.w)
                let bx: Double = m.b.x - w * 0.5
                let byy: Double = m.b.top - 0.45
                fillRect(&ctx, v.rect(bx, byy, w, 0.14), Color.black.opacity(0.7))
                let frac: Double = m.hp / m.maxHP
                let col: Color = m.tame ? Color(hex: 0x50E070) : Color(hex: 0xE04040)
                fillRect(&ctx, v.rect(bx, byy, w * frac, 0.14), col)
            }
            if warn {
                let blink: Bool = Int(g.clock * 8.0) % 2 == 0
                let col: Color = blink ? Color(hex: 0xFF3030) : Color(hex: 0xFFE040)
                drawLabel(&ctx, "!", v.sx(m.b.x), v.sy(m.b.top) - 20.0, 30, col)
            }
        }
    }

    static func drawTelegraph(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ m: Mob) {
        let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
        let pulse: Double = 0.18 + 0.12 * sin(g.clock * 14.0)
        let red: Color = Color(hex: 0xFF2020, alpha: pulse)
        let isBear: Bool = m.kind == .bearBoss
        let x: Double = m.b.x
        let y: Double = m.b.y
        switch a {
        case .melee:
            let reach: Double = isBear ? 5.6 : 7.6
            let x0: Double = m.dir > 0 ? x : x - reach
            fillRect(&ctx, v.rect(x0, m.b.top - 0.5, reach, m.b.h + 0.5), red)
        case .sweep:
            fillRect(&ctx, v.rect(x - 7.0, y - 2.0, 14.0, 2.0), red)
        case .charge:
            let x0: Double = m.dir > 0 ? x : x - 30.0
            fillRect(&ctx, v.rect(x0, y - 1.6, 30.0, 1.6), red)
            let dirD: Double = Double(m.dir)
            let tipOff: Double = m.b.w * 0.5 + 2.0
            let ax: Double = v.sx(x + dirD * tipOff)
            let ay: Double = v.sy(y - 0.8)
            let d: Double = dirD * v.tp
            let half: Double = v.tp * 0.6
            let yel: Color = Color(hex: 0xFFE040)
            strokeLine(&ctx, ax, ay - half, ax + d, ay, yel, 4)
            strokeLine(&ctx, ax + d, ay, ax, ay + half, yel, 4)
        case .slam:
            let tx: Double = clampD(g.pb.x, m.homeX - 33.0, m.homeX + 33.0)
            fillOval(&ctx, v.rect(tx - 3.0, y - 0.8, 6.0, 1.0), Color(hex: 0xFF2020, alpha: pulse + 0.15))
            fillRect(&ctx, v.rect(x - 16.0, y - 0.7, 32.0, 0.7), red)
        case .roar:
            let grow: Double = pulse * 10.0
            let r: CGRect = v.rect(x - 3.0 - grow, m.b.top - 1.0 - grow * 0.6, 6.0 + grow * 2.0, m.b.h + 1.0 + grow * 1.2)
            let p: Path = Path(ellipseIn: r)
            ctx.stroke(p, with: .color(Color(hex: 0xFFE040, alpha: 0.6)), lineWidth: 3)
        }
    }

    static func drawPlayer(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        if g.dead { return }
        let art: Art = Art.shared
        let s: SpriteSet = art.playerSet(g)
        let left: Bool = g.facing < 0
        var alpha: Double = 1.0
        let blink: Bool = Int(g.clock * 12.0) % 2 == 0
        if g.invuln > 0 && g.hurtT <= 0 && blink { alpha = 0.55 }
        let fr: Int = g.playerFrame()
        let pose: Bool = fr >= 3
        var showItem: Bool = g.heldItem != nil
        if g.mounted != nil || g.inVehicle != nil { showItem = false }
        if showItem && !pose { drawHeldItem(&ctx, g, v) }
        let shade: Double = openShade(g, g.pb.x, g.pb.cy)
        drawSet(&ctx, v, s, fr, left, g.hurtT > 0, g.pb.x, g.pb.y, alpha, shade: shade)
        if showItem && pose { drawHeldItem(&ctx, g, v) }
        if g.pb.inWater && g.air < 10 {
            let headY: Double = g.pb.y - g.pb.h * 0.92
            let ht: Tile = g.world.tile(Int(floor(g.pb.x)), Int(floor(headY)))
            if ht == .water {
                let rise: Double = (g.clock * 0.8).truncatingRemainder(dividingBy: 0.6)
                for i in 0..<3 {
                    let di: Double = Double(i)
                    let wob: Double = sin(g.clock * 3.0 + di) * 3.0
                    let bx: Double = v.sx(g.pb.x + 0.2 * di) + wob
                    let by: Double = v.sy(headY - 0.3 - di * 0.35 - rise)
                    let p: Path = Path(ellipseIn: mkRect(bx, by, 5, 5))
                    ctx.stroke(p, with: .color(Color.white.opacity(0.7)), lineWidth: 1)
                }
            }
        }
    }

    static func drawHeldItem(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        guard let it = g.heldItem else { return }
        let img: Image = Art.shared.icon(it)
        let f: Double = Double(g.facing)
        let hx: Double = g.pb.x + f * 0.38
        let hy: Double = g.pb.y - 0.92
        var c: GraphicsContext = ctx
        c.translateBy(x: CGFloat(v.sx(hx)), y: CGFloat(v.sy(hy)))
        if g.facing < 0 { c.scaleBy(x: -1, y: 1) }
        let sz: Double = 1.02 * v.tp
        var rect: CGRect = mkRect(-sz * 0.15, -sz * 0.85, sz, sz)
        let aimDX: Double = (g.aimX - hx) * f
        let aimDY: Double = g.aimY - hy
        let aimAng: Double = atan2(aimDY, max(0.05, aimDX))
        var ang: Double = 0
        switch it {
        case .gun:
            ang = clampD(aimAng, -1.3, 1.3)
            if g.reloadT > 0 { ang = 0.9 }
            if g.recoilT > 0 || g.muzzleT > 0 { ang -= 0.2 }
            rect = mkRect(-sz * 0.2, -sz * 0.45, sz, sz)
        case .bow:
            ang = clampD(aimAng, -1.3, 1.3)
            rect = mkRect(-sz * 0.35, -sz * 0.5, sz, sz)
            c.rotate(by: Angle(radians: ang))
            c.scaleBy(x: -1, y: 1)
            c.draw(img, in: rect)
            if g.bowCharge > 0 {
                let pull: Double = min(1.0, g.bowCharge) * 0.3 * v.tp
                let x0: Double = sz * 0.2
                strokeLine(&c, x0, 0, x0 + pull, 0, Color(hex: 0xE8E8E8), 2)
            }
            return
        case .block, .mat, .food, .ammo, .part, .gadget, .wall:
            let small: Double = sz * 0.7
            rect = mkRect(-small * 0.2, -small * 0.8, small, small)
            if g.swingT > 0 {
                let t: Double = 1.0 - g.swingT / max(0.01, g.swingDur)
                ang = -0.6 * sin(t * Double.pi)
            }
        default:
            if g.swingT > 0 {
                let t: Double = 1.0 - g.swingT / max(0.01, g.swingDur)
                let e: Double = t * t * (3.0 - 2.0 * t)
                let deg: Double = -100.0 + 190.0 * e
                ang = deg * Double.pi / 180.0
            } else if g.mining {
                let wob: Double = abs(sin(g.clock * 9.0))
                let deg: Double = -30.0 + 50.0 * wob
                ang = deg * Double.pi / 180.0
            } else {
                ang = -0.25
            }
        }
        c.rotate(by: Angle(radians: ang))
        c.draw(img, in: rect)
        if case .gun = it, g.muzzleT > 0 {
            let fx: Double = Double(rect.maxX) - 2.0
            let fy: Double = Double(rect.minY) + sz * 0.15
            fillOval(&c, mkRect(fx, fy, sz * 0.35, sz * 0.3), Color(hex: 0xFFE070))
        }
    }

    static func drawShips(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        if g.ships.isEmpty { return }
        let art: Art = Art.shared
        let sea: Double = Double(WorldGen.sea)
        for s in g.ships {
            let deck: Double = s.deckY(sea)
            if !v.visible(s.x, deck, 12) { continue }
            let topY: Double = deck - PirateShip.deckRow
            let x0: Double = s.x - PirateShip.spriteW * 0.5
            let r: CGRect = v.rect(x0, topY, PirateShip.spriteW, PirateShip.spriteH)
            var c: GraphicsContext = ctx
            if s.sink > 0 { c.opacity = max(0.2, 1.0 - s.sink / 4.0) }
            let img: Image = s.dir < 0 ? art.boatL : art.boat
            c.draw(img, in: r)
            if s.hitT > 0 { fillRect(&c, r, Color(hex: 0xFF4040, alpha: 0.18)) }
            if s.hp < s.maxHP && s.sink <= 0 {
                fillRect(&ctx, v.rect(s.x - 2.0, topY - 0.6, 4.0, 0.18), Color.black.opacity(0.7))
                let frac: Double = max(0.0, s.hp / s.maxHP)
                fillRect(&ctx, v.rect(s.x - 2.0, topY - 0.6, 4.0 * frac, 0.18), Color(hex: 0xE0A040))
            }
            if !s.looted && s.sink <= 0 {
                ctx.draw(art.tile(.chest), in: v.rect(s.x - 3.0, deck - 0.9, 0.9, 0.9))
            }
        }
    }

    static func drawVehicles(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        let art: Art = Art.shared
        let tp: Double = v.tp
        for veh in g.vehicles {
            if !v.visible(veh.b.x, veh.b.y, 10) { continue }
            let shade: Double = openShade(g, veh.b.x, veh.b.cy)
            for (cell, t) in veh.parts {
                // every part is drawn at its rotated position with the vehicle's rotation, exactly
                // where its collision samples are
                let p: (Double, Double) = veh.cellCenter(cell)
                var c: GraphicsContext = ctx
                if shade < 0.98 { c.addFilter(.colorMultiply(shadeColor(shade))) }
                c.translateBy(x: CGFloat(v.sx(p.0)), y: CGFloat(v.sy(p.1)))
                var rot: Double = veh.angle
                var jitter: Double = 0
                if t == .wheel { rot += veh.wheelRot }
                if t == .propeller { rot += veh.propRot }
                if isDrill(t), let d = veh.drillDir[cell] {
                    rot += atan2(Double(d.1), Double(d.0))
                    if veh.drilling { jitter = sin(veh.drillRot * 3.0) * tp * 0.03 }
                }
                c.rotate(by: Angle(radians: rot))
                let img: Image = art.parts[t.rawValue]
                let w: Double = tp * 1.02
                c.draw(img, in: mkRect(-w * 0.5 + jitter, -w * 0.5, w, w))
                if isDrill(t) && veh.drilling {
                    // spinning bit: alternating highlight bands
                    let band: Double = (veh.drillRot.truncatingRemainder(dividingBy: 1.0)) * w * 0.4
                    fillRect(&c, mkRect(w * 0.0 + band - w * 0.1, -w * 0.25, w * 0.08, w * 0.5), Color.white.opacity(0.35))
                }
            }
        }
        // where the held part can go (green), or where a kit would land
        let ghosts: [GhostCell] = g.vehicleGhosts()
        if !ghosts.isEmpty {
            let pulse: Double = 0.55 + 0.25 * sin(g.clock * 6.0)
            for gc in ghosts {
                let col: Color = gc.ok ? Color(hex: 0x50F070) : Color(hex: 0xFF5050)
                var c: GraphicsContext = ctx
                c.translateBy(x: CGFloat(v.sx(gc.x + 0.5)), y: CGFloat(v.sy(gc.y + 0.5)))
                c.rotate(by: Angle(radians: gc.ang))
                let r: CGRect = mkRect(-tp * 0.5, -tp * 0.5, tp, tp)
                fillRect(&c, r, col.opacity(0.22 * pulse + 0.08))
                strokeRect(&c, r, col.opacity(pulse), 2)
            }
        }
    }

    static func drawDrops(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        let art: Art = Art.shared
        let s: Double = 0.62
        for d in g.drops {
            if !v.visible(d.x, d.y, 2) { continue }
            let bob: Double = d.onGround ? sin(d.age * 3.0) * 0.08 : 0.0
            let y0: Double = d.y - s - 0.04 + bob
            let r: CGRect = v.rect(d.x - s * 0.5, y0, s, s)
            ctx.draw(art.icon(d.stack.item), in: r)
            if d.stack.count > 1 {
                drawLabel(&ctx, String(d.stack.count), Double(r.maxX), Double(r.maxY), 10, Color.white)
            }
        }
    }

    static func drawProjectiles(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        let tp: Double = v.tp
        for p in g.projectiles {
            if !v.visible(p.x, p.y, 2) { continue }
            let x: Double = v.sx(p.x)
            let y: Double = v.sy(p.y)
            switch p.kind {
            case .arrow:
                // the arrow points along its flight (or the angle it hit at, once stuck)
                let ang: Double = p.stuck > 0 ? p.stuckAngle : atan2(p.vy, p.vx)
                let dx: Double = cos(ang)
                let dy: Double = sin(ang)
                let hx: Double = dx * tp * 0.42
                let hy: Double = dy * tp * 0.42
                let lw: Double = max(2.0, tp / 11.0)
                if p.stuck <= 0 && p.trail > 0 {
                    let tl: Double = tp * 0.9
                    strokeLine(&ctx, x - hx - dx * tl, y - hy - dy * tl, x - hx, y - hy, Color.white.opacity(0.18), lw)
                }
                strokeLine(&ctx, x - hx, y - hy, x + hx, y + hy, Color(hex: 0x8A5A2A), lw)
                strokeLine(&ctx, x + hx * 0.6, y + hy * 0.6, x + hx * 1.05, y + hy * 1.05, Color(hex: 0xD0D0D8), lw + 1.0)
                let nx: Double = -dy * tp * 0.12
                let ny: Double = dx * tp * 0.12
                strokeLine(&ctx, x - hx, y - hy, x - hx * 0.7 + nx, y - hy * 0.7 + ny, Color(hex: 0xF0F0F0), lw * 0.8)
                strokeLine(&ctx, x - hx, y - hy, x - hx * 0.7 - nx, y - hy * 0.7 - ny, Color(hex: 0xF0F0F0), lw * 0.8)
            case .bomb:
                let r: Double = tp * 0.32
                fillOval(&ctx, mkRect(x - r, y - r, r * 2.0, r * 2.0), Color(hex: 0x30303A))
                fillOval(&ctx, mkRect(x - r * 0.6, y - r * 0.7, r * 0.6, r * 0.5), Color(hex: 0x6A6A78))
                let blink: Bool = Int(p.life * 10.0) % 2 == 0
                fillRect(&ctx, mkRect(x + r * 0.3, y - r * 1.4, 3, 3), blink ? Color(hex: 0xFFE040) : Color(hex: 0xFF6020))
            case .bullet:
                fillRect(&ctx, mkRect(x - 3.0, y - 2.0, 6, 4), Color(hex: 0xFFE080))
            case .fireball:
                let a: Double = tp * 0.4
                let b: Double = tp * 0.22
                fillOval(&ctx, mkRect(x - a, y - a, a * 2.0, a * 2.0), Color(hex: 0xFF6A1E, alpha: 0.5))
                fillOval(&ctx, mkRect(x - b, y - b, b * 2.0, b * 2.0), Color(hex: 0xFFD060))
            case .rock:
                let s: Double = p.w * tp
                let h: Double = s * 0.5
                fillRect(&ctx, mkRect(x - h, y - h, s, s), Color(hex: 0x7A7A7A))
                fillRect(&ctx, mkRect(x - h, y - h, s * 0.5, s * 0.4), Color(hex: 0x9A9A9A))
            case .shock:
                let h: Double = tp * 1.3
                fillOval(&ctx, mkRect(x - tp * 0.35, y - h * 0.8, tp * 0.7, h), Color(hex: 0xE8D8A0, alpha: 0.6))
            case .spit:
                fillOval(&ctx, mkRect(x - 4.0, y - 4.0, 8, 8), Color(hex: 0x8AE04A))
            case .bolt:
                fillOval(&ctx, mkRect(x - 5.0, y - 5.0, 10, 10), Color(hex: 0xC080FF))
            }
        }
    }

    static func drawParticles(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        for p in g.particles {
            if !v.visible(p.x, p.y, 1) { continue }
            let a: Double = clampD(p.life / max(0.01, p.maxLife), 0, 1)
            let s: Double = max(2.0, p.size * v.tp)
            let h: Double = s * 0.5
            fillRect(&ctx, mkRect(v.sx(p.x) - h, v.sy(p.y) - h, s, s), rgbColor(p.color, a))
        }
    }

    // MARK: lighting

    static func drawLight(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ cache: RenderCache) {
        if g.fullBright || !g.light.valid { return }
        if cache.lightRev != g.lightRev {
            cache.lightRev = g.lightRev
            cache.lightOX = g.light.ox
            cache.lightOY = g.light.oy
            cache.lightW = g.light.w
            cache.lightH = g.light.h
            let interp: Image.Interpolation = g.settings.smoothLight ? .high : .none
            if let cg = makeCGImagePremul(g.lightDark, g.light.w, g.light.h) {
                cache.lightImg = Image(decorative: cg, scale: 1.0).interpolation(interp)
            }
            if let cg = makeCGImagePremul(g.lightGlow, g.light.w, g.light.h) {
                cache.glowImg = Image(decorative: cg, scale: 1.0).interpolation(interp)
            }
        }
        let r: CGRect = v.rect(Double(cache.lightOX), Double(cache.lightOY), Double(cache.lightW), Double(cache.lightH))
        if let gi = cache.glowImg {
            var c: GraphicsContext = ctx
            c.blendMode = .plusLighter
            c.draw(gi, in: r)
        }
        if let li = cache.lightImg { ctx.draw(li, in: r) }
    }

    // MARK: overlays

    static func drawOverlays(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D) {
        let art: Art = Art.shared
        if g.mining && g.mineP > 0 {
            let f: Double = clampD(g.mineP / max(0.01, g.mineNeed), 0, 0.999)
            let st: Int = Int(f * 5.0)
            ctx.draw(art.crack[st], in: v.rect(Double(g.mineX), Double(g.mineY), 1, 1))
        }
        let aiming: Bool = g.useHeld || g.pendingInteract || actState.held
        if g.aimValid && !g.dead && aiming {
            let tx: Double = floor(g.aimX)
            let ty: Double = floor(g.aimY)
            let ok: Bool = g.inReach(g.aimX, g.aimY)
            let col: Color = ok ? Color.white.opacity(0.8) : Color(hex: 0xFF5050, alpha: 0.6)
            strokeRect(&ctx, v.rect(tx, ty, 1, 1), col, 2)
        }
        let full: CGRect = mkRect(0, 0, W, H)
        let headY: Double = g.pb.y - g.pb.h * 0.9
        let headT: Tile = g.world.tile(Int(floor(g.pb.x)), Int(floor(headY)))
        if headT == .water { fillRect(&ctx, full, Color(hex: 0x1A4AA0, alpha: 0.28)) }
        if g.pb.inLava { fillRect(&ctx, full, Color(hex: 0xFF4010, alpha: 0.3)) }
        if g.hurtT > 0 { fillRect(&ctx, full, Color(hex: 0xFF0000, alpha: g.hurtT * 0.35)) }
        if g.fadeT > 0 { fillRect(&ctx, full, Color(hex: 0x6A2AB0, alpha: min(1.0, g.fadeT))) }
    }

    static func drawFloats(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
        for f in g.floats {
            let a: Double = clampD(f.life, 0, 1)
            let x: Double = v.sx(f.x)
            let y: Double = v.sy(f.y)
            drawLabel(&ctx, f.text, x + 2.0, y + 2.0, 15, Color.black.opacity(a))
            drawLabel(&ctx, f.text, x, y, 15, rgbColor(f.color, a))
        }
    }

    static func drawDebug(_ ctx: inout GraphicsContext, _ H: Double, _ g: Game, _ v: View2D) {
        if g.showChunks {
            let c0: Int = floorDiv(Int(floor(v.left)), chunkW)
            let c1: Int = floorDiv(Int(ceil(v.left + v.wTiles)), chunkW)
            for cx in c0...(c1 + 1) {
                let x: Double = v.sx(Double(cx * chunkW))
                let loaded: Bool = g.world.chunks[cx] != nil
                let col: Color = loaded ? Color.yellow.opacity(0.6) : Color.red.opacity(0.6)
                strokeLine(&ctx, x, 0, x, H, col, 1)
                let dirty: Bool = g.world.chunks[cx]?.dirty ?? false
                let star: String = dirty ? "*" : ""
                let label: String = "c\(cx)\(star)"
                drawLabel(&ctx, label, x + 22.0, 120, 11, Color.yellow)
            }
        }
        if g.showHitboxes {
            strokeRect(&ctx, v.rect(g.pb.left, g.pb.top, g.pb.w, g.pb.h), Color.green, 1)
            for m in g.mobs where v.visible(m.b.x, m.b.y, 4) {
                let col: Color = m.def.hostile ? Color.red : Color.cyan
                strokeRect(&ctx, v.rect(m.b.left, m.b.top, m.b.w, m.b.h), col, 1)
            }
            for d in g.decksCache {
                strokeLine(&ctx, v.sx(d.x0), v.sy(d.y), v.sx(d.x1), v.sy(d.y), Color.orange, 2)
            }
            for veh in g.vehicles {
                strokeRect(&ctx, v.rect(veh.b.left, veh.b.top, veh.b.w, veh.b.h), Color.purple, 1)
            }
        }
    }
}

// ===== u03_hud =====

// MARK: - Shared UI pieces

extension Font {
    static func pixel(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        return Font.system(size: size, weight: weight, design: .monospaced)
    }
}

/// Joins strings without long '+' chains (keeps the type checker fast)
func joinText(_ parts: String...) -> String {
    return parts.joined()
}

func pick(_ on: Bool, _ a: UInt32, _ b: UInt32) -> Color {
    if on { return Color(hex: a) }
    return Color(hex: b)
}

struct PixelBox: View {
    var color: Color = Color(hex: 0x6B6B6B)
    var body: some View {
        ZStack {
            Rectangle().fill(Color.black)
            Rectangle().fill(color).padding(3)
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.3)).frame(height: 3)
                Spacer(minLength: 0)
                Rectangle().fill(Color.black.opacity(0.35)).frame(height: 3)
            }
            .padding(3)
        }
    }
}

struct PixelButton: View {
    let title: String
    var color: Color = Color(hex: 0x6B6B6B)
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pixel(17))
                .foregroundColor(Color.white)
                .shadow(color: Color.black, radius: 0, x: 2, y: 2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(PixelBox(color: color))
        }
        .buttonStyle(.plain)
    }
}

struct SmallButton: View {
    let title: String
    var color: Color = Color(hex: 0x6B6B6B)
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.pixel(13))
                .foregroundColor(Color.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(PixelBox(color: color).opacity(0.92))
        }
        .buttonStyle(.plain)
    }
}

struct HoldButton: View {
    let label: String
    var size: CGFloat = 70
    var color: Color = Color(hex: 0x6B6B6B)
    var onChange: (Bool) -> Void
    @State var pressed: Bool = false
    var fontSize: CGFloat { return size * 0.3 }
    var fill: Color { return pressed ? Color(hex: 0x3A3A3A) : color }
    var body: some View {
        Text(label)
            .font(.pixel(fontSize))
            .foregroundColor(Color.white)
            .frame(width: size, height: size)
            .background(PixelBox(color: fill).opacity(0.78))
            .contentShape(Rectangle())
            .gesture(holdGesture)
    }

    var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in press() }
            .onEnded { _ in release() }
    }

    func press() {
        if !pressed {
            pressed = true
            onChange(true)
        }
    }

    func release() {
        pressed = false
        onChange(false)
    }
}

/// Item icon with stack count, used by the hotbar and every inventory grid
struct SlotView: View {
    let stack: Stack?
    var selected: Bool = false
    var size: CGFloat = 44
    var dim: Bool = false
    var iconSize: CGFloat { return size * 0.72 }
    var countFont: CGFloat { return size * 0.27 }
    var ammoFont: CGFloat { return size * 0.22 }
    var border: Color { return selected ? Color.white : Color.gray.opacity(0.55) }
    var borderWidth: CGFloat { return selected ? 3 : 1 }
    var iconOpacity: Double { return dim ? 0.4 : 1.0 }
    func ammoText(_ s: Stack, _ gt: GunType) -> String {
        let a: String = String(s.extra)
        let b: String = String(gt.magazine)
        return "\(a)/\(b)"
    }
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Rectangle().fill(Color.black.opacity(0.55))
            if let s = stack {
                Art.shared.icon(s.item)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .frame(width: size, height: size)
                    .opacity(iconOpacity)
                if s.count > 1 {
                    Text(String(s.count))
                        .font(.pixel(countFont))
                        .foregroundColor(Color.white)
                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                        .padding(2)
                }
                if case .gun(let gt) = s.item {
                    Text(ammoText(s, gt))
                        .font(.pixel(ammoFont))
                        .foregroundColor(Color(hex: 0xFFE080))
                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                        .padding(2)
                }
            }
        }
        .frame(width: size, height: size)
        .overlay(Rectangle().stroke(border, lineWidth: borderWidth))
    }
}

struct IconRow: View {
    let value: Double
    let perIcon: Double
    let count: Int
    let full: Image
    let empty: Image
    var size: CGFloat = 18
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<count, id: \.self) { i in
                ZStack(alignment: .leading) {
                    empty.resizable().frame(width: size, height: size)
                    full.resizable()
                        .frame(width: size, height: size)
                        .frame(width: partWidth(i), height: size, alignment: .leading)
                        .clipped()
                }
                .frame(width: size, height: size, alignment: .leading)
            }
        }
    }

    func partWidth(_ i: Int) -> CGFloat {
        let f: CGFloat = fraction(i)
        return size * f
    }

    func fraction(_ i: Int) -> CGFloat {
        let f: Double = (value - Double(i) * perIcon) / perIcon
        let q: Double = (clampD(f, 0, 1) * 2.0).rounded(.down) / 2.0
        return CGFloat(q)
    }
}

struct OutlinedText: View {
    let text: String
    var size: CGFloat = 13
    var color: Color = .white
    var body: some View {
        Text(text)
            .font(.pixel(size))
            .foregroundColor(color)
            .shadow(color: Color.black, radius: 0, x: 1, y: 1)
            .shadow(color: Color.black, radius: 0, x: -1, y: -1)
    }
}

// MARK: - Virtual joystick

struct StickView: View {
    let game: Game
    var radius: CGFloat = 62
    @State var knob: CGSize = CGSize.zero
    var diameter: CGFloat { return radius * 2 }
    var box: CGFloat { return diameter + 30 }

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.22)).frame(width: diameter, height: diameter)
            Circle().stroke(Color.white.opacity(0.35), lineWidth: 3).frame(width: diameter, height: diameter)
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: diameter, height: 2)
            Circle().fill(Color.white.opacity(0.55)).frame(width: 58, height: 58).offset(knob)
        }
        .frame(width: box, height: box)
        .contentShape(Rectangle())
        .gesture(stickGesture)
    }

    var stickGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { v in moved(v.location) }
            .onEnded { _ in released() }
    }

    func moved(_ p: CGPoint) {
        let r: Double = Double(radius)
        let c: Double = Double(box) * 0.5
        let pxd: Double = Double(p.x)
        let pyd: Double = Double(p.y)
        var dx: Double = pxd - c
        var dy: Double = pyd - c
        let len: Double = sqrt(dx * dx + dy * dy)
        if len > r {
            dx = dx / len * r
            dy = dy / len * r
        }
        knob = CGSize(width: CGFloat(dx), height: CGFloat(dy))
        var sx: Double = dx / r
        if abs(sx) < 0.18 { sx = 0 }
        // make walking feel snappy: most of the range is full speed
        let mag: Double = min(1.0, abs(sx) * 1.35)
        game.stick = sx >= 0 ? mag : -mag
        game.stickY = dy / r
    }

    func released() {
        knob = CGSize.zero
        game.stick = 0
        game.stickY = 0
    }
}

// MARK: - Vehicle checklist

struct VehicleHelpBox: View {
    let check: VehicleCheck
    var titleText: String {
        if check.ready { return joinText(check.title, " - READY") }
        return joinText(check.title, " - needs:")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            OutlinedText(text: titleText, size: 13, color: pick(check.ready, 0x8CF07A, 0xFFE066))
            ForEach(0..<check.lines.count, id: \.self) { i in
                checkRow(i)
            }
            Text(verbatim: check.hint)
                .font(.pixel(10, .semibold))
                .foregroundColor(Color.white.opacity(0.75))
        }
        .padding(8)
        .background(PixelBox(color: Color(hex: 0x2A2A2E)).opacity(0.88))
        .frame(maxWidth: 320, alignment: .leading)
    }

    func checkRow(_ i: Int) -> some View {
        let ok: Bool = check.oks[i]
        let mark: String = ok ? "[x]" : "[ ]"
        return HStack(spacing: 5) {
            Text(verbatim: mark).font(.pixel(11)).foregroundColor(pick(ok, 0x8CF07A, 0xFF7060))
            Text(verbatim: check.lines[i]).font(.pixel(11, .semibold)).foregroundColor(Color.white)
        }
    }
}

// MARK: - HUD

struct HUDView: View {
    let game: Game
    @ObservedObject var hud: HUDSignal
    var body: some View {
        VStack(spacing: 0) {
            topBar
            if game.activeBoss != nil { bossBar.padding(.top, 4) }
            if let m = game.message {
                Text(m)
                    .font(.pixel(14))
                    .foregroundColor(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(8)
                    .background(PixelBox(color: Color(hex: 0x2E2E2E)).opacity(0.9))
                    .padding(.top, 6)
                    .frame(maxWidth: 560)
            }
            vehicleArea
            Spacer(minLength: 0)
            bottomArea
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    var vehicleArea: some View {
        if let v = game.vehicleHelpTarget {
            HStack {
                VehicleHelpBox(check: game.vehicleCheck(v))
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
        } else if let tip = vehicleTip {
            HStack {
                Text(verbatim: tip)
                    .font(.pixel(11, .bold))
                    .foregroundColor(Color.white)
                    .padding(8)
                    .background(PixelBox(color: Color(hex: 0x2E2E2E)).opacity(0.85))
                    .frame(maxWidth: 300, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
        }
    }

    var vehicleTip: String? {
        guard let it = game.heldItem else { return nil }
        if game.inVehicle != nil { return nil }
        switch it {
        case .gadget(let g):
            if isKit(g) { return "Tap open, flat ground near you to place it. Boats go on water." }
            return nil
        case .part:
            return "Place a Frame (car) or Hull Float (boat) on the ground first, then add parts to it. Kits in the Vehicles tab are quicker."
        default:
            return nil
        }
    }

    var topBar: some View {
        HStack(alignment: .top, spacing: 8) {
            statusBlock
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 6) {
                    SmallButton(title: "−") { zoom(-8) }
                    SmallButton(title: "+") { zoom(8) }
                    if game.gotMap || game.inv.total(.gadget(.treasureMap)) > 0 {
                        SmallButton(title: "MAP", color: Color(hex: 0x9A7A3A)) { game.showMap = true }
                    }
                    SmallButton(title: "BAG", color: Color(hex: 0x3E6FAA)) { game.showInventory = true }
                    SmallButton(title: "DBG") { game.showDebug.toggle() }
                    SmallButton(title: "II") { game.paused = true }
                }
                if game.settings.showCoords { infoBlock }
            }
        }
    }

    var statusBlock: some View {
        let art: Art = Art.shared
        return VStack(alignment: .leading, spacing: 3) {
            if game.isCreative {
                OutlinedText(text: "CREATIVE", size: 14)
            } else {
                IconRow(value: game.hp, perIcon: game.maxHP / 10.0, count: 10, full: art.heartFull, empty: art.heartEmpty)
                IconRow(value: game.hunger, perIcon: 2.0, count: 10, full: art.foodFull, empty: art.foodEmpty)
                if game.air < 9.99 {
                    IconRow(value: game.air, perIcon: 1.0, count: 10, full: art.bubble, empty: art.heartEmpty, size: 14)
                }
                if game.inv.defense > 0 {
                    HStack(spacing: 4) {
                        art.shieldIcon.resizable().frame(width: 16, height: 16)
                        OutlinedText(text: String(Int(game.inv.defense.rounded())), size: 12)
                    }
                }
            }
            if game.mode == .hardcore { OutlinedText(text: "HARDCORE", size: 11, color: Color(hex: 0xFF6060)) }
        }
    }

    var infoBlock: some View {
        let x: Int = Int(floor(game.pb.x))
        let y: Int = Int(floor(game.pb.y))
        var dayText: String = "Umbral Realm"
        if game.world.dim != .umbral {
            let dn: Int = Int(game.dayCount)
            let nt: String = game.isNight ? " · Night" : ""
            dayText = "Day \(dn)\(nt)"
        }
        return VStack(alignment: .trailing, spacing: 1) {
            OutlinedText(text: joinText("X ", String(x), "  Y ", String(y)), size: 11)
            OutlinedText(text: joinText(game.biomeHere.name, " · ", game.depthText), size: 11)
            OutlinedText(text: dayText, size: 11)
        }
    }

    var bossBar: some View {
        let fracD: Double = game.bossBarFrac * 356.0
        let barW: CGFloat = CGFloat(fracD)
        return VStack(spacing: 2) {
            OutlinedText(text: game.bossBarName, size: 14, color: Color(hex: 0xFFD060))
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.black.opacity(0.75)).frame(width: 360, height: 14)
                Rectangle().fill(Color(hex: 0xC02828)).frame(width: barW, height: 10).padding(.leading, 2)
            }
            .overlay(Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 2))
        }
    }

    var bottomArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if game.settings.touchControls {
                StickView(game: game)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                contextButtons
                OutlinedText(text: game.selectedName, size: 12)
                hotbar
            }
            Spacer(minLength: 0)
            if game.settings.touchControls {
                VStack(alignment: .trailing, spacing: 8) {
                    HoldButton(label: "USE", size: 64, color: Color(hex: 0xA06A2A)) { down in actState.held = down }
                    HoldButton(label: "JUMP", size: 82, color: Color(hex: 0x4E8A3E)) { down in game.jumpHeld = down }
                }
            }
        }
    }

    var contextButtons: some View {
        HStack(spacing: 6) {
            if game.vehicleNearby != nil {
                SmallButton(title: "DRIVE", color: Color(hex: 0x4E8A3E)) { game.driveNearby() }
                SmallButton(title: "PACK UP", color: Color(hex: 0x6A5A2A)) { game.packUpVehicle() }
            }
            if game.mounted != nil || game.inVehicle != nil {
                SmallButton(title: "DISMOUNT", color: Color(hex: 0xA03030)) { game.dismount() }
            }
            if let s = game.heldStack, case .gun(let gt) = s.item {
                if game.reloadT > 0 {
                    OutlinedText(text: "RELOADING", size: 12, color: Color(hex: 0xFFE080))
                } else if s.extra < gt.magazine {
                    SmallButton(title: "RELOAD", color: Color(hex: 0x6A5A2A)) { game.startReload() }
                }
            }
            if game.flying || game.noclip {
                HoldButton(label: "▼", size: 44) { down in game.downHeld = down }
            }
        }
    }

    var hotbar: some View {
        HStack(spacing: 3) {
            ForEach(0..<Inventory.hotbarCount, id: \.self) { i in
                Button {
                    game.setSel(i)
                } label: {
                    SlotView(stack: game.inv.slots[i], selected: game.sel == i, size: 40)
                }
                .buttonStyle(.plain)
            }
        }
    }

    func zoom(_ d: Int) {
        game.tilePx = clampI(game.tilePx + d, 16, 56)
        game.settings.tilePx = game.tilePx
        game.light.valid = false
        game.bumpHUD()
    }
}

// ===== u04_panels =====

// MARK: - Inventory, crafting, chests, creative palette

struct InventoryPanel: View {
    @ObservedObject var game: Game
    @ObservedObject var hud: HUDSignal
    @State var cat: RecipeCat = .basic
    @State var creativeTab: Bool = false
    @State var onlyCraftable: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            header
            HStack(alignment: .top, spacing: 12) {
                leftColumn
                rightColumn
            }
        }
        .foregroundColor(Color.white)
        .padding(14)
        .background(PixelBox(color: Color(hex: 0x2C2C30)).opacity(0.97))
        .frame(maxWidth: 1000)
        .padding(10)
    }

    var titleText: String {
        if game.openChest != nil { return "INVENTORY  ·  CHEST" }
        return "INVENTORY"
    }

    var header: some View {
        HStack {
            Text(verbatim: titleText).font(.pixel(18))
            Spacer()
            if game.isCreative && game.openChest == nil {
                SmallButton(title: creativeTab ? "CRAFTING" : "ALL ITEMS", color: Color(hex: 0x3E6FAA)) { creativeTab.toggle() }
            }
            SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) { close() }
        }
    }

    func close() {
        game.returnCarried()
        game.openChest = nil
        game.craftStation = .hand
        game.showInventory = false
        game.bumpHUD()
    }

    var leftColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                armorColumn
                VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { r in
                        HStack(spacing: 3) {
                            ForEach(0..<10, id: \.self) { c in
                                invSlot(r * 10 + c)
                            }
                        }
                    }
                }
            }
            carryBar
            Text(verbatim: holdHint)
                .font(.pixel(10, .semibold))
                .foregroundColor(Color.white.opacity(0.7))
        }
    }

    var holdHint: String {
        let tail: String = game.openChest != nil ? "move to chest." : "split stack, equip armor."
        return joinText("Tap: pick up / place. Hold: ", tail)
    }

    func invSlot(_ i: Int) -> some View {
        let isHot: Bool = i < Inventory.hotbarCount
        let selected: Bool = isHot && game.sel == i
        let ring: Color = isHot ? Color(hex: 0xFFE070, alpha: 0.35) : Color.clear
        return SlotView(stack: game.inv.slots[i], selected: selected, size: 40)
            .overlay(Rectangle().stroke(ring, lineWidth: 1))
            .onTapGesture { game.tapSlot(i) }
            .onLongPressGesture(minimumDuration: 0.35) { longPress(i) }
    }

    func longPress(_ i: Int) {
        if let p = game.openChest {
            game.chestStore(p.x, p.y, i)
            return
        }
        if let s = game.inv.slots[i], case .armor = s.item {
            game.quickEquip(i)
            return
        }
        game.splitSlot(i)
    }

    var armorColumn: some View {
        let names: [String] = ["Head", "Body", "Legs"]
        return VStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                VStack(spacing: 1) {
                    SlotView(stack: game.inv.armor[i], size: 40)
                        .onTapGesture { game.tapArmorSlot(i) }
                    Text(names[i]).font(.pixel(9, .bold)).foregroundColor(Color.white.opacity(0.7))
                }
            }
            HStack(spacing: 2) {
                Art.shared.shieldIcon.resizable().frame(width: 14, height: 14)
                Text(String(Int(game.inv.defense.rounded()))).font(.pixel(11))
            }
        }
    }

    var carryBar: some View {
        HStack(spacing: 8) {
            if let c = game.carry {
                SlotView(stack: c, size: 36)
                Text(verbatim: joinText("Holding ", c.item.name)).font(.pixel(12))
                Spacer()
                SmallButton(title: "PUT BACK") { game.returnCarried() }
                SmallButton(title: "DROP", color: Color(hex: 0xA06A2A)) { game.dropCarried() }
            } else {
                Text("Hand empty").font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.6))
                Spacer()
            }
        }
        .frame(height: 40)
    }

    @ViewBuilder
    var rightColumn: some View {
        if let p = game.openChest {
            ChestPanel(game: game, hud: game.hud, cx: p.x, cy: p.y)
        } else if creativeTab && game.isCreative {
            creativePalette
        } else {
            craftingList
        }
    }

    var creativePalette: some View {
        let items: [Item] = game.creativeItems()
        let cols: [GridItem] = [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 3)]
        return ScrollView {
            LazyVGrid(columns: cols, spacing: 3) {
                ForEach(0..<items.count, id: \.self) { i in
                    SlotView(stack: Stack(item: items[i], count: 1), size: 40)
                        .onTapGesture { game.creativeGive(items[i]) }
                }
            }
        }
        .frame(minWidth: 280, maxWidth: 420, maxHeight: 360)
    }

    var stationText: String {
        var s: [String] = ["Hand"]
        if game.stationAvailable(.bench) { s.append("Workbench") }
        if game.stationAvailable(.furnace) { s.append("Furnace") }
        else if game.stationAvailable(.campfire) { s.append("Campfire") }
        return "Near: " + s.joined(separator: ", ")
    }

    func visibleRecipes() -> [Recipe] {
        var out: [Recipe] = []
        for r in RecipeBook.all {
            if r.cat != cat { continue }
            if onlyCraftable && !game.canCraft(r) { continue }
            out.append(r)
        }
        return out
    }

    func catButton(_ c: RecipeCat) -> some View {
        let col: Color = pick(c == cat, 0x4E8A3E, 0x555555)
        return SmallButton(title: c.name, color: col) { cat = c }
    }

    var craftingList: some View {
        let list: [Recipe] = visibleRecipes()
        return VStack(alignment: .leading, spacing: 6) {
            Text("CRAFTING").font(.pixel(15))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(RecipeCat.allCases, id: \.self) { c in
                        catButton(c)
                    }
                }
            }
            HStack {
                Text(stationText).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.75))
                Spacer()
                SmallButton(title: onlyCraftable ? "CAN MAKE" : "SHOW ALL") { onlyCraftable.toggle() }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(list) { r in
                        RecipeRow(game: game, recipe: r)
                    }
                }
            }
            .frame(maxHeight: 330)
        }
        .frame(minWidth: 300, maxWidth: 440)
    }
}

struct RecipeRow: View {
    let game: Game
    let recipe: Recipe
    var body: some View {
        let ok: Bool = game.canCraft(recipe)
        let stationOK: Bool = game.stationAvailable(recipe.station)
        return HStack(spacing: 6) {
            SlotView(stack: Stack(item: recipe.out, count: recipe.outCount), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.out.name).font(.pixel(12)).lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(0..<recipe.cost.count, id: \.self) { k in
                        costView(recipe.cost[k])
                    }
                }
                if !stationOK {
                    Text(verbatim: joinText("Needs ", recipe.station.name)).font(.pixel(9, .bold)).foregroundColor(Color(hex: 0xFF8A60))
                }
            }
            Spacer(minLength: 2)
            makeButton(ok)
        }
        .padding(4)
        .background(Color.black.opacity(0.25))
    }

    func makeButton(_ ok: Bool) -> some View {
        let col: Color = pick(ok, 0x4E8A3E, 0x444444)
        let op: Double = ok ? 1.0 : 0.6
        return SmallButton(title: "MAKE", color: col) { game.craft(recipe) }.opacity(op)
    }

    func costView(_ c: CostLine) -> some View {
        let have: Int = game.inv.total(c.item)
        let enough: Bool = have >= c.n || game.isCreative
        return HStack(spacing: 1) {
            Art.shared.icon(c.item).resizable().frame(width: 16, height: 16)
            Text(String(c.n)).font(.pixel(10)).foregroundColor(pick(enough, 0xFFFFFF, 0xFF6060))
        }
    }
}

struct ChestPanel: View {
    @ObservedObject var game: Game
    @ObservedObject var hud: HUDSignal
    let cx: Int
    let cy: Int
    var body: some View {
        let items: [Stack] = game.world.chestItems(cx, cy)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CHEST").font(.pixel(15))
                Spacer()
                SmallButton(title: "TAKE ALL", color: Color(hex: 0x4E8A3E)) { takeAll() }
            }
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { r in
                    HStack(spacing: 3) {
                        ForEach(0..<9, id: \.self) { c in
                            chestSlot(r * 9 + c, items)
                        }
                    }
                }
            }
            Text("Tap: take / put the held stack. Hold: move into your bag.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.7))
        }
    }

    func chestSlot(_ i: Int, _ items: [Stack]) -> some View {
        let s: Stack? = i < items.count ? items[i] : nil
        return SlotView(stack: s, size: 40)
            .onTapGesture { game.chestTapSlot(cx, cy, i) }
            .onLongPressGesture(minimumDuration: 0.35) { game.chestQuickMove(cx, cy, i) }
    }

    func takeAll() {
        var n: Int = 0
        while n < 30 {
            let items: [Stack] = game.world.chestItems(cx, cy)
            if items.isEmpty { break }
            let before: Int = items.count
            game.chestQuickMove(cx, cy, 0)
            if game.world.chestItems(cx, cy).count >= before { break }
            n += 1
        }
    }
}

// MARK: - Treasure map

struct MapPanel: View {
    @ObservedObject var game: Game
    @ObservedObject var hud: HUDSignal
    var body: some View {
        let map: TreasureMap = game.treasureMap()
        return VStack(spacing: 8) {
            HStack {
                Text("TREASURE MAP").font(.pixel(18)).foregroundColor(Color(hex: 0x4A2A10))
                Spacer()
                SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) { game.showMap = false }
            }
            Canvas { ctx, size in
                MapDrawer.draw(&ctx, size, map, game)
            }
            .frame(height: 260)
            .overlay(Rectangle().stroke(Color(hex: 0x7A5A2A), lineWidth: 3))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<map.clues.count, id: \.self) { i in
                    Text(verbatim: joinText("• ", map.clues[i])).font(.pixel(12, .bold)).foregroundColor(Color(hex: 0x3A2410))
                }
                if game.inv.total(.gadget(.portalKey)) > 0 && game.world.dim == .overworld {
                    Text(verbatim: joinText("Key: ", game.portalHintText(game.portalHintLevel())))
                        .font(.pixel(12, .heavy)).foregroundColor(Color(hex: 0x6A2AB0))
                }
                if game.portalOpened {
                    Text("The gate has been opened.").font(.pixel(12, .heavy)).foregroundColor(Color(hex: 0x2A6A2A))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(hex: 0xE8D4A0))
        .overlay(Rectangle().stroke(Color(hex: 0x5A3A1A), lineWidth: 4))
        .frame(maxWidth: 820)
        .padding(16)
    }
}

enum MapDrawer {
    static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, _ m: TreasureMap, _ g: Game) {
        let W: Double = Double(size.width)
        let Hh: Double = Double(size.height)
        let span: Double = Double(max(1, m.x1 - m.x0))
        let yTop: Double = 20.0
        let yBot: Double = Double(m.worldH) - 40.0
        let x0: Double = Double(m.x0)
        func mx(_ x: Double) -> Double {
            let d: Double = x - x0
            return d / span * W
        }
        func my(_ y: Double) -> Double {
            let d: Double = y - yTop
            let r: Double = yBot - yTop
            return d / r * Hh
        }
        fillRect(&ctx, mkRect(0, 0, W, Hh), Color(hex: 0xF0E0B4))
        let n: Int = m.heights.count
        if n == 0 { return }
        let nD: Double = Double(n)
        let colW: Double = max(1.0, W / nD + 1.0)
        let seaY: Double = my(Double(WorldGen.sea))
        let deepY: Double = my(330.0)
        let water: Color = Color(hex: 0x7AA4C8)
        let soil: Color = Color(hex: 0xB89868)
        let rock: Color = Color(hex: 0xA8906C)
        let deep: Color = Color(hex: 0x988060)
        for i in 0..<n {
            let x: Double = Double(i) / nD * W
            let hD: Double = Double(m.heights[i])
            let b: Biome = m.biomes[i]
            let top: Double = my(hD)
            let soilEnd: Double = my(hD + 30.0)
            if b == .ocean {
                fillRect(&ctx, mkRect(x, seaY, colW, max(0.0, top - seaY)), water)
            }
            let surf: Color = rgbColor(mixRGB(biomeMapColor(b), 0xE8D4A0, 0.25))
            fillRect(&ctx, mkRect(x, top, colW, 4.0), surf)
            let soilTop: Double = top + 4.0
            fillRect(&ctx, mkRect(x, soilTop, colW, max(0.0, soilEnd - soilTop)), soil)
            fillRect(&ctx, mkRect(x, soilEnd, colW, max(0.0, deepY - soilEnd)), rock)
            fillRect(&ctx, mkRect(x, deepY, colW, max(0.0, Hh - deepY)), deep)
        }
        // depth lines
        let dash: StrokeStyle = StrokeStyle(lineWidth: 1, dash: [3, 5])
        let lineCol: Color = Color(hex: 0x7A5A3A, alpha: 0.35)
        for d in [200.0, 330.0, 450.0] {
            let y: Double = my(d)
            var p: Path = Path()
            p.move(to: mkPoint(0, y))
            p.addLine(to: mkPoint(W, y))
            ctx.stroke(p, with: .color(lineCol), style: dash)
        }
        // markers
        let stepN: Int = max(1, m.step)
        for mk in m.markers {
            let x: Double = mx(Double(mk.x))
            let rel: Int = mk.x - m.x0
            let idxRaw: Int = rel / stepN
            let idx: Int = clampI(idxRaw, 0, n - 1)
            let y: Double = my(Double(m.heights[idx])) - 10.0
            var sym: String = "●"
            var col: Color = Color(hex: 0x3A2410)
            switch mk.kind {
            case 0:
                sym = "⌂"
                col = Color(hex: 0x2A6A2A)
            case 1:
                sym = "☠"
                col = Color(hex: 0x8A2A1A)
            case 2:
                sym = "☠"
                col = Color(hex: 0x5A3A8A)
            case 3:
                sym = "⌂"
                col = Color(hex: 0x6A4A1A)
            default:
                sym = "▲"
                col = Color(hex: 0x5A5A5A)
            }
            drawLabel(&ctx, sym, x, y, 16, col)
            if mk.kind <= 2 { drawLabel(&ctx, mk.label, x, y - 14.0, 9, col) }
        }
        // the dashed ring (the gate is somewhere inside)
        let rx: Double = Double(m.ringRX) / span * W
        let ry: Double = Double(m.ringRY) / (yBot - yTop) * Hh
        let cx: Double = mx(Double(m.ringX))
        let cy: Double = my(Double(m.ringY))
        let ring: CGRect = mkRect(cx - rx, cy - ry, rx * 2.0, ry * 2.0)
        let ringStyle: StrokeStyle = StrokeStyle(lineWidth: 3, dash: [8, 6])
        ctx.stroke(Path(ellipseIn: ring), with: .color(Color(hex: 0xC02020)), style: ringStyle)
        drawLabel(&ctx, "?", cx, cy, 22, Color(hex: 0xC02020))
        // you are here
        if g.world.dim == .overworld {
            let px: Double = g.pb.x
            if px >= x0 && px <= Double(m.x1) {
                let ux: Double = mx(px)
                let uy: Double = my(g.pb.y)
                fillOval(&ctx, mkRect(ux - 5.0, uy - 5.0, 10, 10), Color(hex: 0x2050D0))
                drawLabel(&ctx, "YOU", ux, uy - 12.0, 9, Color(hex: 0x2050D0))
            }
        }
        drawLabel(&ctx, "W  <-  -> E", W - 60.0, 14, 11, Color(hex: 0x5A3A1A))
    }
}

// MARK: - Pause, death

struct PauseView: View {
    @ObservedObject var game: Game
    @ObservedObject var hud: HUDSignal
    var worldLine: String {
        let kind: String = game.gen.infinite ? " · Infinite" : " · Classic"
        return joinText(game.worldName, " · ", game.mode.title, kind)
    }
    var quit: () -> Void
    @State var savedNote: String = ""
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("PAUSED").font(.pixel(30)).foregroundColor(Color.white)
                Text(verbatim: worldLine)
                    .font(.pixel(12, .bold)).foregroundColor(Color.white.opacity(0.8))
                PixelButton(title: "RESUME", color: Color(hex: 0x4E8A3E)) { game.paused = false }
                PixelButton(title: "SAVE GAME", color: Color(hex: 0x3E6FAA)) {
                    savedNote = game.saveNow() ? "Saved!" : "Could not save."
                }
                toggles
                PixelButton(title: "SAVE & QUIT", color: Color(hex: 0xA03030)) { quit() }
                if !savedNote.isEmpty { Text(savedNote).font(.pixel(12)).foregroundColor(Color.white) }
            }
            .frame(maxWidth: 340)
            .padding()
        }
    }

    /// A toggle binding that also refreshes this screen (the game is paused, so nothing else would)
    func setting(_ kp: WritableKeyPath<Settings, Bool>) -> Binding<Bool> {
        let g: Game = game
        return Binding<Bool>(get: { g.settings[keyPath: kp] }, set: { v in
            g.settings[keyPath: kp] = v
            g.light.valid = false
            g.bumpHUD()
        })
    }

    var toggles: some View {
        VStack(spacing: 8) {
            Toggle("Touch controls", isOn: setting(\.touchControls))
            Toggle("Smooth lighting", isOn: setting(\.smoothLight))
            Toggle("Show coordinates", isOn: setting(\.showCoords))
            Toggle("60 FPS (off = 30, smoother on older iPads)", isOn: setting(\.fps60))
            Toggle("Show FPS counter", isOn: setting(\.showFPS))
        }
        .font(.pixel(13, .bold))
        .foregroundColor(Color.white)
    }
}

struct DeathView: View {
    @ObservedObject var game: Game
    @ObservedObject var hud: HUDSignal
    var quit: () -> Void
    var deathTitle: String {
        if game.mode == .hardcore { return "GAME OVER" }
        return "YOU DIED"
    }
    var body: some View {
        ZStack {
            Color(hex: 0x700000, alpha: 0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                Text(verbatim: deathTitle).font(.pixel(34)).foregroundColor(Color.white)
                    .shadow(color: Color.black, radius: 0, x: 3, y: 3)
                Text(verbatim: joinText("Kills: ", String(game.kills), "   Days: ", String(game.dayCount))).font(.pixel(14)).foregroundColor(Color.white)
                if game.mode == .hardcore {
                    Text("This hardcore world has been deleted.").font(.pixel(12, .bold)).foregroundColor(Color.white)
                } else {
                    PixelButton(title: "RESPAWN", color: Color(hex: 0x4E8A3E)) { game.respawn() }
                }
                PixelButton(title: "MAIN MENU", color: Color(hex: 0xA03030)) { quit() }
            }
            .frame(maxWidth: 320)
            .padding()
        }
    }
}

// MARK: - Debug menu

struct DebugPanel: View {
    @ObservedObject var game: Game
    @ObservedObject var hud: HUDSignal
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("DEBUG").font(.pixel(16)).foregroundColor(Color(hex: 0xFFE066))
                    Spacer()
                    SmallButton(title: "X", color: Color(hex: 0xA03030)) { game.showDebug = false }
                }
                stats
                toggles
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: joinText("Speed x", String(format: "%.1f", game.speedMult))).font(.pixel(11, .semibold))
                    Slider(value: $game.speedMult, in: 0.5...4.0, step: 0.5)
                }
                actions
                section("SPAWN MOB")
                spawnGrid
            }
            .font(.pixel(12, .bold))
            .foregroundColor(Color.white)
            .padding(12)
        }
        .background(PixelBox(color: Color(hex: 0x1E1E1E)).opacity(0.94))
    }

    var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("TIME")
            HStack(spacing: 6) {
                SmallButton(title: "Dawn") { game.debugSetTime(0.0) }
                SmallButton(title: "Noon") { game.debugSetTime(0.25) }
                SmallButton(title: "Dusk") { game.debugSetTime(0.5) }
                SmallButton(title: "Night") { game.debugSetTime(0.75) }
            }
            section("PLAYER")
            HStack(spacing: 6) {
                SmallButton(title: "Heal") { game.hp = game.maxHP; game.hunger = 20; game.air = 10; game.bumpHUD() }
                SmallButton(title: "Give kit") { game.debugGiveKit() }
                SmallButton(title: "Kill hostiles") { game.debugKillHostiles() }
            }
            section("TELEPORT")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SmallButton(title: "Spawn") { game.debugTeleport(game.spawnX, game.spawnY) }
                    SmallButton(title: "Surface") { game.debugToSurface() }
                    SmallButton(title: "Portal") { game.debugToPortal() }
                }
                HStack(spacing: 6) {
                    SmallButton(title: "Bear den") { game.debugToLair(.bear) }
                    SmallButton(title: "Rex nest") { game.debugToLair(.rex) }
                    SmallButton(title: "Other realm", color: Color(hex: 0x6A3AA0)) { game.debugSwitchDimension() }
                }
                HStack(spacing: 6) {
                    SmallButton(title: "Up 20") { game.pb.y -= 20; game.pb.vy = 0; game.fallPeak = 0 }
                    SmallButton(title: "Down 20") { game.pb.y += 20; game.pb.vy = 0; game.fallPeak = 0 }
                    SmallButton(title: "→ 200") { game.debugTeleport(game.pb.x + 200, game.pb.y) }
                }
            }
        }
    }

    func section(_ s: String) -> some View {
        return Text(s).font(.pixel(11)).foregroundColor(Color(hex: 0xFFE066)).padding(.top, 4)
    }

    var statLines: [String] {
        var out: [String] = []
        let tickS: String = String(format: "%.2f", game.tickMs)
        out.append("Tick \(tickS) ms")
        let fpsN: Int = Int(game.renderFPS.rounded())
        out.append("FPS \(fpsN)")
        let dimName: String = game.world.dim == .overworld ? "Overworld" : "Umbral"
        let xs: String = String(format: "%.1f", game.pb.x)
        let ys: String = String(format: "%.1f", game.pb.y)
        out.append("XY \(xs), \(ys)  \(dimName)")
        let kind: String = game.gen.infinite ? "Infinite" : "Classic"
        let seedS: String = String(game.seedValue)
        out.append("Seed \(seedS)  \(kind)")
        let chunkN: Int = game.world.chunks.count
        let dirtyN: Int = game.world.dirtyChunkCount
        out.append("Chunks \(chunkN)  Dirty \(dirtyN)")
        let mobN: Int = game.mobs.count
        let shipN: Int = game.ships.count
        out.append("Mobs \(mobN)  Ships \(shipN)")
        let vehN: Int = game.vehicles.count
        out.append("Vehicles \(vehN)")
        let timeS: String = String(format: "%.2f", game.timeOfDay)
        let dayN: Int = game.dayCount
        let skyN: Int = Int(game.skyLevel)
        out.append("Time \(timeS)  Day \(dayN)  Sky \(skyN)")
        let open: String = game.portalOpened ? " (open)" : ""
        let px: Int = Int(game.gen.portalX)
        let py: Int = Int(game.gen.portalY)
        out.append("Portal \(px),\(py)\(open)")
        return out
    }

    var stats: some View {
        let lines: [String] = statLines
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<lines.count, id: \.self) { i in
                Text(lines[i])
            }
        }
        .font(.pixel(10, .semibold))
    }

    var toggles: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("God mode", isOn: $game.godMode)
            Toggle("Fly", isOn: $game.flying)
            Toggle("Noclip", isOn: $game.noclip)
            Toggle("Monsters", isOn: $game.monstersEnabled)
            Toggle("Freeze time", isOn: $game.freezeTime)
            Toggle("Full bright", isOn: $game.fullBright)
            Toggle("Infinite reach", isOn: $game.infiniteReach)
            Toggle("Hitboxes", isOn: $game.showHitboxes)
            Toggle("Chunk borders", isOn: $game.showChunks)
        }
        .font(.pixel(12, .bold))
    }

    var spawnGrid: some View {
        let kinds: [MobKind] = MobKind.allCases
        let cols: [GridItem] = [GridItem(.adaptive(minimum: 104), spacing: 4)]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
            ForEach(0..<kinds.count, id: \.self) { i in
                SmallButton(title: shortName(kinds[i])) { game.debugSpawn(kinds[i]) }
            }
        }
    }

    func shortName(_ k: MobKind) -> String {
        switch k {
        case .bearBoss: return "Bear Boss"
        case .rex: return "T-Rex Boss"
        case .pirateGunner: return "Gunner"
        case .pirateCaptain: return "Captain"
        case .polarBear: return "Polar Bear"
        case .emberSlime: return "Ember Slime"
        case .cinderBat: return "Cinder Bat"
        default: return mobDef(k).name
        }
    }
}

// ===== u05_menu =====

// MARK: - Settings persistence

enum SettingsStore {
    static let key: String = "PixelRealm.settings.v2"

    static func load() -> Settings {
        if let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(Settings.self, from: d) {
            return s
        }
        return Settings()
    }

    static func save(_ s: Settings) {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: key) }
    }
}

func seedFrom(_ text: String) -> UInt64 {
    let t: String = text.trimmingCharacters(in: .whitespaces)
    if t.isEmpty { return UInt64.random(in: 1...999_999_999) }
    if let n = UInt64(t) { return n }
    var h: UInt64 = 5381
    for u in t.unicodeScalars { h = (h &* 33) &+ UInt64(u.value) }
    return h
}

// MARK: - Animated title background

final class MenuArt: @unchecked Sendable {
    static let shared: MenuArt = MenuArt()
    var player: SpriteSet
    var wolf: SpriteSet
    var zombie: SpriteSet
    var slime: SpriteSet
    var pig: SpriteSet
    var bat: SpriteSet
    var skeleton: SpriteSet
    var key: Int = -1

    init() {
        let st: HumanStyle = playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil)
        player = makeSpriteSet(humanoidFrames(st), hitH: 1.8, fixedScale: 0.125)
        wolf = makeSpriteSet(spriteWolf(tamedColors: true), hitH: 0.9)
        zombie = makeSpriteSet(humanoidFrames(zombieStyle(0)), hitH: 1.7, fixedScale: 0.125)
        slime = makeSpriteSet(spriteSlime(main: 0x4EC04E, glow: 0x9AF09A, eye: 0x103010), hitH: 0.7)
        pig = makeSpriteSet(spritePig(), hitH: 0.7)
        bat = makeSpriteSet(spriteBat(), hitH: 0.4)
        skeleton = makeSpriteSet(humanoidFrames(skeletonStyle()), hitH: 1.8, fixedScale: 0.125)
    }

    func setPlayer(hair: Int, scarf: Int) {
        let k: Int = hair * 10 + scarf
        if k == key { return }
        key = k
        let st: HumanStyle = playerStyle(hairIdx: hair, scarfIdx: scarf, head: nil, chest: nil, legs: nil)
        player = makeSpriteSet(humanoidFrames(st), hitH: 1.8, fixedScale: 0.125)
    }
}

struct MenuBackground: View {
    var hair: Int
    var scarf: Int
    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                MenuBackground.paint(&ctx, size, tl.date.timeIntervalSinceReferenceDate, hair, scarf)
            }
        }
        .ignoresSafeArea()
    }

    static func paint(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ hair: Int, _ scarf: Int) {
        let art: Art = Art.shared
        let ma: MenuArt = MenuArt.shared
        ma.setPlayer(hair: hair, scarf: scarf)
        let W: Double = Double(size.width)
        let H: Double = Double(size.height)
        let full: CGRect = mkRect(0, 0, W, H)
        vGradient(&ctx, full, [Color(hex: 0x3E86D8), Color(hex: 0xC4E6FF)], 0, H)
        let sunX: Double = W * 0.78
        fillRect(&ctx, mkRect(sunX, 70, 56, 56), Color(hex: 0xFFD84A))
        fillRect(&ctx, mkRect(sunX + 12.0, 82, 32, 32), Color(hex: 0xFFF2A0))
        let cloud: Color = Color.white.opacity(0.9)
        let span: Double = W + 300.0
        for i in 0..<5 {
            let speed: Double = 8.0 + Double(i) * 3.0
            var cx: Double = hash2(i, 1, 9) * span + t * speed
            cx = cx.truncatingRemainder(dividingBy: span) - 150.0
            let cy: Double = 40.0 + hash2(i, 2, 9) * H * 0.3
            fillRect(&ctx, mkRect(cx, cy, 120, 20), cloud)
            fillRect(&ctx, mkRect(cx + 20.0, cy - 16.0, 70, 16), cloud)
        }
        let ground: Double = H - 130.0
        for layer in 0..<2 {
            let speed: Double = layer == 0 ? 10.0 : 25.0
            let col: Color = layer == 0 ? Color(hex: 0x7FA7B8) : Color(hex: 0x5E9A62)
            let lift: Double = layer == 0 ? 110.0 : 50.0
            let ph: Double = Double(layer)
            var hx: Double = 0
            while hx < W {
                let wx: Double = (hx + t * speed) * 0.012
                let w1: Double = sin(wx * 2.0 + ph) * 30.0
                let w2: Double = sin(wx * 5.0) * 10.0
                let raw: Double = ground - lift + w1 + w2
                let top: Double = floor(raw / 8.0) * 8.0
                fillRect(&ctx, mkRect(hx, top, 12, H - top), col)
                hx += 12.0
            }
        }
        let ts: Double = 32.0
        let off: Double = (t * 60.0).truncatingRemainder(dividingBy: ts)
        let rows: [Tile] = [.grass, .dirt, .dirt, .stone, .stone]
        var gx: Double = -ts - off
        while gx < W + ts {
            for (k, tile) in rows.enumerated() {
                let y: Double = ground + ts * Double(k)
                ctx.draw(art.tile(tile), in: mkRect(gx, y, ts, ts))
            }
            gx += ts
        }
        let v: View2D = View2D(tp: ts, left: 0, top: 0, wTiles: 100, hTiles: 100)
        let step: Int = Int(t * 6.0) % 2
        let walk: Int = 1 + step
        let gy: Double = ground / ts
        let px: Double = W * 0.32 / ts
        let zx: Double = px - 7.0 + sin(t) * 0.4
        let kx: Double = px - 10.0 + sin(t * 0.7) * 0.3
        WorldRenderer.drawSet(&ctx, v, ma.player, walk, false, false, px, gy)
        WorldRenderer.drawSet(&ctx, v, ma.wolf, walk, false, false, px - 2.6, gy)
        WorldRenderer.drawSet(&ctx, v, ma.zombie, walk, false, false, zx, gy)
        WorldRenderer.drawSet(&ctx, v, ma.skeleton, walk, false, false, kx, gy)
        let hop: Double = abs(sin(t * 3.0)) * 0.7
        let slimeFrame: Int = hop > 0.1 ? 1 : 0
        WorldRenderer.drawSet(&ctx, v, ma.slime, slimeFrame, true, false, px + 7.5, gy - hop)
        WorldRenderer.drawSet(&ctx, v, ma.pig, walk, true, false, px + 4.0, gy)
        let bx: Double = W * 0.55 / ts + sin(t * 0.8) * 3.5
        let byy: Double = 5.5 + sin(t * 2.0) * 0.8
        WorldRenderer.drawSet(&ctx, v, ma.bat, Int(t * 10.0), false, false, bx, byy)
    }
}

// MARK: - Main menu

enum MenuScreen {
    case main, newWorld, load, character, settings, help
}

struct MenuView: View {
    @Binding var settings: Settings
    var start: (Game) -> Void
    @State var screen: MenuScreen = .main
    @State var seedText: String = ""
    @State var nameText: String = "My World"
    @State var mode: GameMode = .survival
    @State var infinite: Bool = false
    @State var splash: String = ""
    @State var metas: [SaveMeta] = []
    let splashes: [String] = ["Now with pirates!", "Beware the Bear!", "Find the hidden gate!", "Ride a T-Rex!",
                              "Build a car. Then a boat.", "Torches keep the dark away!", "Infinite worlds!"]

    var body: some View {
        ZStack {
            MenuBackground(hair: settings.hair, scarf: settings.scarf)
            ScrollView {
                VStack(spacing: 14) {
                    Spacer(minLength: 24)
                    title
                    content
                        .frame(maxWidth: 420)
                        .padding(.horizontal, 24)
                    Text("v2.0 · all art generated in code").font(.pixel(11, .bold)).foregroundColor(Color.white.opacity(0.85))
                        .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            splash = splashes.randomElement() ?? ""
            refreshSaves()
        }
    }

    var title: some View {
        VStack(spacing: 0) {
            Text("PIXEL REALM")
                .font(.system(size: 52, weight: .black, design: .monospaced))
                .foregroundColor(Color(hex: 0xFFE066))
                .shadow(color: Color(hex: 0x7A4A00), radius: 0, x: 4, y: 4)
                .shadow(color: Color.black, radius: 0, x: 6, y: 6)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(splash)
                .font(.pixel(15))
                .foregroundColor(Color(hex: 0xFFF58A))
                .shadow(color: Color.black, radius: 0, x: 2, y: 2)
                .rotationEffect(.degrees(-3))
                .padding(.top, 6)
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder
    var content: some View {
        switch screen {
        case .main: mainButtons
        case .newWorld: newWorldForm
        case .load: loadList
        case .character: CharacterView(settings: $settings, done: backToMain)
        case .settings: SettingsView(settings: $settings, done: backToMain)
        case .help: HelpView(done: backToMain)
        }
    }

    func backToMain() {
        SettingsStore.save(settings)
        screen = .main
    }

    var continueTitle: String {
        if let m = metas.first { return joinText("CONTINUE: ", m.name.uppercased()) }
        return "CONTINUE"
    }

    var mainButtons: some View {
        VStack(spacing: 10) {
            if let m = metas.first {
                PixelButton(title: continueTitle, color: Color(hex: 0x4E8A3E)) { load(m.slot) }
            }
            PixelButton(title: "NEW WORLD", color: Color(hex: 0x3E6FAA)) { screen = .newWorld }
            if !metas.isEmpty {
                PixelButton(title: "LOAD WORLD") { refreshSaves(); screen = .load }
            }
            HStack(spacing: 10) {
                PixelButton(title: "CHARACTER", color: Color(hex: 0x8A5A2E)) { screen = .character }
                PixelButton(title: "SETTINGS") { screen = .settings }
            }
            PixelButton(title: "HOW TO PLAY") { screen = .help }
        }
    }

    var worldBlurb: String {
        if infinite { return "Endless world that streams in as you explore." }
        return "A large world (4096 wide) with every biome and ocean edges."
    }

    var newWorldForm: some View {
        VStack(spacing: 10) {
            Text("NEW WORLD").font(.pixel(20)).foregroundColor(Color.white).shadow(color: Color.black, radius: 0, x: 2, y: 2)
            TextField("World name", text: $nameText)
                .font(.pixel(15, .bold))
                .padding(10)
                .background(Color.black.opacity(0.75))
                .foregroundColor(Color.white)
            HStack(spacing: 6) {
                modeButton(.survival, "SURVIVAL", 0x4E8A3E)
                modeButton(.creative, "CREATIVE", 0x3E6FAA)
                modeButton(.hardcore, "HARDCORE", 0xA03030)
            }
            HStack(spacing: 6) {
                PixelButton(title: "CLASSIC", color: pick(!infinite, 0x8A6A2E, 0x555555)) { infinite = false }
                PixelButton(title: "INFINITE", color: pick(infinite, 0x8A6A2E, 0x555555)) { infinite = true }
            }
            Text(verbatim: worldBlurb)
                .font(.pixel(11, .bold)).foregroundColor(Color.white).shadow(color: Color.black, radius: 0, x: 1, y: 1)
                .multilineTextAlignment(.center)
            TextField("Seed (optional)", text: $seedText)
                .font(.pixel(15, .bold))
                .padding(10)
                .background(Color.black.opacity(0.75))
                .foregroundColor(Color.white)
            PixelButton(title: "CREATE", color: Color(hex: 0x4E8A3E)) { create() }
            PixelButton(title: "BACK") { screen = .main }
        }
    }

    func modeButton(_ m: GameMode, _ label: String, _ col: UInt32) -> some View {
        let on: Bool = mode == m
        let c: Color = pick(on, col, 0x555555)
        return PixelButton(title: label, color: c) { mode = m }
    }

    var loadList: some View {
        VStack(spacing: 8) {
            Text("LOAD WORLD").font(.pixel(20)).foregroundColor(Color.white).shadow(color: Color.black, radius: 0, x: 2, y: 2)
            ForEach(0..<metas.count, id: \.self) { i in
                saveRow(metas[i])
            }
            PixelButton(title: "BACK") { screen = .main }
        }
    }

    func saveRow(_ m: SaveMeta) -> some View {
        let mins: Int = Int(m.playSeconds / 60.0)
        let kindS: String = m.infinite ? "Infinite" : "Classic"
        let modeS: String = m.mode.title
        let dayS: Int = Int(m.day)
        let detail: String = "\(modeS) · \(kindS) · Day \(dayS) · \(mins) min"
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.pixel(15)).foregroundColor(Color.white)
                Text(detail).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.8))
            }
            Spacer()
            SmallButton(title: "PLAY", color: Color(hex: 0x4E8A3E)) { load(m.slot) }
            SmallButton(title: "DEL", color: Color(hex: 0xA03030)) {
                SaveStore.delete(m.slot)
                refreshSaves()
            }
        }
        .padding(8)
        .background(PixelBox(color: Color(hex: 0x3A3A3A)).opacity(0.92))
    }

    func refreshSaves() {
        var list: [SaveMeta] = []
        var dates: [Date] = []
        for i in 0..<SaveStore.slotCount {
            if let m = SaveStore.meta(i) {
                list.append(m)
                let attrs = try? FileManager.default.attributesOfItem(atPath: SaveStore.url(i).path)
                dates.append((attrs?[.modificationDate] as? Date) ?? Date.distantPast)
            }
        }
        // most recent first
        var idx: [Int] = Array(0..<list.count)
        idx.sort { dates[$0] > dates[$1] }
        metas = idx.map { list[$0] }
    }

    func create() {
        let seed: UInt64 = seedFrom(seedText)
        let nm: String = nameText.trimmingCharacters(in: .whitespaces).isEmpty ? "My World" : nameText
        let g = Game(mode: mode, infinite: infinite, seed: seed, settings: settings)
        g.worldName = nm
        g.slot = SaveStore.freeSlot()
        _ = g.saveNow()
        start(g)
    }

    func load(_ slot: Int) {
        if let s = SaveStore.read(slot) {
            let g: Game = Game.load(s, settings: settings)
            start(g)
        } else {
            refreshSaves()
        }
    }
}

// MARK: - Character, settings, help

struct CharacterView: View {
    @Binding var settings: Settings
    var done: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            Text("CHARACTER").font(.pixel(20)).foregroundColor(Color.white).shadow(color: Color.black, radius: 0, x: 2, y: 2)
            Art.shared.previewPlayer(hair: settings.hair, scarf: settings.scarf)
                .resizable()
                .frame(width: 160, height: 128)
                .background(PixelBox(color: Color(hex: 0x5A7A9A)).opacity(0.9))
            Text("Brown shirt adventurer. Pick a hair and scarf colour.").font(.pixel(11, .bold)).foregroundColor(Color.white)
                .shadow(color: Color.black, radius: 0, x: 1, y: 1)
                .multilineTextAlignment(.center)
            colorRow("HAIR", hairChoices, settings.hair) { settings.hair = $0 }
            colorRow("SCARF", scarfChoices, settings.scarf) { settings.scarf = $0 }
            PixelButton(title: "DONE", color: Color(hex: 0x4E8A3E)) { done() }
        }
    }

    func swatch(_ c: UInt32, _ on: Bool) -> some View {
        let edge: Color = pick(on, 0xFFFFFF, 0x000000)
        let w: CGFloat = on ? 4 : 2
        return Rectangle().fill(Color(hex: c))
            .frame(width: 38, height: 38)
            .overlay(Rectangle().stroke(edge, lineWidth: w))
    }

    func colorRow(_ label: String, _ cols: [UInt32], _ sel: Int, _ pick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.pixel(13)).foregroundColor(Color.white).frame(width: 64, alignment: .leading)
            ForEach(0..<cols.count, id: \.self) { i in
                Button {
                    pick(i)
                } label: {
                    swatch(cols[i], i == sel)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SettingsView: View {
    @Binding var settings: Settings
    var rareLine: String {
        let pct: Int = Int(settings.rareChance * 100.0)
        return joinText("Abandoned structures (new worlds): ", String(pct), "% of sites")
    }
    var done: () -> Void
    var toggles: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("On-screen touch controls", isOn: $settings.touchControls)
            Toggle("Peaceful (no monsters)", isOn: $settings.peaceful)
            Toggle("Show coordinates", isOn: $settings.showCoords)
            Toggle("Smooth lighting", isOn: $settings.smoothLight)
            Toggle("60 FPS (off = 30, smoother on older iPads)", isOn: $settings.fps60)
            Toggle("Show FPS counter", isOn: $settings.showFPS)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SETTINGS").font(.pixel(20))
            toggles
            Text(verbatim: joinText("Default zoom: ", String(settings.tilePx), " px per block")).font(.pixel(13, .bold))
            Stepper("", value: $settings.tilePx, in: 16...56, step: 8)
            Text(verbatim: rareLine).font(.pixel(13, .bold))
            Slider(value: $settings.rareChance, in: 0.0...0.8, step: 0.02)
            PixelButton(title: "DONE", color: Color(hex: 0x4E8A3E)) { done() }
        }
        .font(.pixel(14, .bold))
        .foregroundColor(Color.white)
        .padding(18)
        .background(PixelBox(color: Color(hex: 0x2C2C30)).opacity(0.95))
    }
}

struct HelpView: View {
    var done: () -> Void
    let lines: [String] = [
        "Move with the left stick (or A/D). JUMP button (W/Space). Pull the stick down to drop through platforms.",
        "Touch the world to mine, attack, place or use the item in your hand. The USE button aims for you.",
        "Hotbar: tap a slot. BAG opens your inventory, armor and crafting. Hold a slot to split a stack.",
        "Craft a workbench, then a furnace. Better pickaxes mine deeper ores: copper, iron, gold, diamond, mythril.",
        "Torches, lanterns and campfires light the dark. Caves get darker and more dangerous the deeper you go.",
        "Eat to stay fed. Cook meat at a campfire. Hunger at zero hurts you.",
        "Skeleton knights block with shields. Pirates sail the seas and raid the coast.",
        "Defeat Ursavor the giant bear to get a Portal Key and a Treasure Map. The map hints where the hidden gate is.",
        "Beat Tyrannax the T-Rex and it becomes your companion. Tap it to ride.",
        "Vehicles, the easy way: craft a Car Kit, Rowboat Kit or Motorboat Kit (Vehicles tab at a workbench) and tap the ground to place it. Stand next to it and press DRIVE. PACK UP puts it back in your bag.",
        "Your own designs: place a Frame (car) or Hull Float (boat), then hold a part - green squares show where it fits. A checklist shows what is still missing. Coal or wood is fuel: hold it and tap the vehicle.",
        "Zoom with + and −. The DBG button opens the debug menu. II pauses and saves.",
        "Keyboard: A/D move, W jump, S down, 1-0 hotbar, E bag, M map, F use, R reload, X dismount, +/- zoom, Esc pause."
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HOW TO PLAY").font(.pixel(20))
            ForEach(0..<lines.count, id: \.self) { i in
                Text(verbatim: joinText("• ", lines[i])).font(.pixel(12, .semibold))
            }
            PixelButton(title: "GOT IT", color: Color(hex: 0x4E8A3E)) { done() }
        }
        .foregroundColor(Color.white)
        .padding(18)
        .background(PixelBox(color: Color(hex: 0x2C2C30)).opacity(0.95))
    }
}

// ===== u06_root =====

// MARK: - Keyboard (hardware keyboards on iPad)

struct KeyInput: ViewModifier {
    let game: Game
    @FocusState var focused: Bool

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content
                .focusable()
                .focused($focused)
                .focusEffectDisabled()
                .onAppear { focused = true }
                .onKeyPress(phases: [.down, .up]) { press in handle(press) }
        } else {
            content
        }
    }

    @available(iOS 17.0, macOS 14.0, *)
    func handle(_ press: KeyPress) -> KeyPress.Result {
        let isDown: Bool = press.phase != .up
        if press.key == .leftArrow { game.keyL = isDown; return .handled }
        if press.key == .rightArrow { game.keyR = isDown; return .handled }
        if press.key == .upArrow || press.key == .space { game.jumpHeld = isDown; return .handled }
        if press.key == .downArrow { game.downHeld = isDown; return .handled }
        if press.key == .escape {
            if isDown { game.paused.toggle() }
            return .handled
        }
        if press.key == .tab {
            if isDown { game.showDebug.toggle() }
            return .handled
        }
        let c: String = press.characters.lowercased()
        switch c {
        case "a": game.keyL = isDown
        case "d": game.keyR = isDown
        case "w": game.jumpHeld = isDown
        case "s": game.downHeld = isDown
        case "f": actState.held = isDown
        case "e":
            if isDown {
                if game.showInventory {
                    game.returnCarried()
                    game.openChest = nil
                    game.craftStation = .hand
                    game.showInventory = false
                } else {
                    game.showInventory = true
                }
            }
        case "m": if isDown && (game.gotMap || game.inv.total(.gadget(.treasureMap)) > 0) { game.showMap.toggle() }
        case "r": if isDown { game.startReload() }
        case "x": if isDown { game.dismount() }
        case "=", "+": if isDown { game.tilePx = clampI(game.tilePx + 8, 16, 56); game.bumpHUD() }
        case "-": if isDown { game.tilePx = clampI(game.tilePx - 8, 16, 56); game.bumpHUD() }
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            if isDown, let n = Int(c) { game.setSel(n - 1) }
        case "0":
            if isDown { game.setSel(9) }
        default:
            return .ignored
        }
        return .handled
    }
}

// MARK: - Game screen

final class LoopClock: @unchecked Sendable {
    var last: Double = 0
    var skip: Bool = false
    var pending: Double = 0
    var fpsT: Double = 0
    var fpsN: Int = 0
}

/// The world picture. It only redraws when the game steps (it watches the frame ticker, not the whole game).
struct WorldLayer: View {
    let game: Game
    @ObservedObject var ticker: FrameTicker
    var body: some View {
        Canvas(opaque: true) { ctx, size in
            WorldLayer.render(&ctx, size, game)
        }
    }

    static func render(_ ctx: inout GraphicsContext, _ size: CGSize, _ g: Game) {
        g.viewW = Double(size.width)
        g.viewH = Double(size.height)
        WorldRenderer.draw(&ctx, size, g)
    }
}

struct GameView: View {
    @ObservedObject var game: Game
    var quit: () -> Void
    @State var dragging: Bool = false
    @State var clock: LoopClock = LoopClock()
    let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            worldLayer
            if !game.showInventory && !game.showMap && !game.dead {
                HUDView(game: game, hud: game.hud)
            }
            if game.showInventory {
                Color.black.opacity(0.35).ignoresSafeArea()
                ScrollView {
                    InventoryPanel(game: game, hud: game.hud)
                }
            }
            if game.showMap {
                Color.black.opacity(0.45).ignoresSafeArea()
                ScrollView {
                    MapPanel(game: game, hud: game.hud)
                }
            }
            if game.showDebug && !game.showInventory && !game.showMap {
                HStack {
                    Spacer()
                    DebugPanel(game: game, hud: game.hud)
                        .frame(width: 300)
                        .padding(.top, 54)
                        .padding(.bottom, 8)
                        .padding(.trailing, 8)
                }
            }
            if game.paused { PauseView(game: game, hud: game.hud, quit: quit) }
            if game.dead { DeathView(game: game, hud: game.hud, quit: quit) }
        }
        .background(Color.black)
        .onReceive(timer) { _ in step() }
        .modifier(KeyInput(game: game))
    }

    var worldLayer: some View {
        WorldLayer(game: game, ticker: game.ticker)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(worldGesture)
    }

    var worldGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in touchMoved(v.location) }
            .onEnded { _ in touchEnded() }
    }

    func touchMoved(_ p: CGPoint) {
        let w: (Double, Double) = toWorld(p)
        if !dragging {
            dragging = true
            game.pointerDown(w.0, w.1)
        } else {
            game.pointerMove(w.0, w.1)
        }
    }

    func touchEnded() {
        dragging = false
        game.pointerUp()
    }

    func toWorld(_ p: CGPoint) -> (Double, Double) {
        let tp: Double = Double(game.tilePx)
        let wT: Double = game.viewW / tp
        let hT: Double = game.viewH / tp
        let left: Double = floor((game.camX - wT * 0.5) * 8.0) / 8.0
        let top: Double = floor((game.camY - hT * 0.5) * 8.0) / 8.0
        let px: Double = Double(p.x)
        let py: Double = Double(p.y)
        let wx: Double = left + px / tp
        let wy: Double = top + py / tp
        return (wx, wy)
    }

    /// One game step. Runs from a 60 Hz timer; in 30 fps mode every second tick is merged into the next.
    func step() {
        let now: Double = Date().timeIntervalSinceReferenceDate
        var dt: Double = now - clock.last
        if clock.last == 0 || dt > 0.1 { dt = 1.0 / 60.0 }
        clock.last = now
        if game.paused { return }
        if !game.settings.fps60 {
            clock.skip.toggle()
            if clock.skip {
                clock.pending += dt
                return
            }
            dt += clock.pending
            clock.pending = 0
        }
        game.applyActButton()
        game.tick(dt)
        game.ticker.frame &+= 1
    }
}

// MARK: - Root

/// Saves when the app goes to the background (uses the iOS 17 onChange form when available)
struct PhaseWatcher: ViewModifier {
    let phase: ScenePhase
    let changed: (ScenePhase) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            content.onChange(of: phase) { _, newPhase in changed(newPhase) }
        } else {
            content.onChange(of: phase) { newPhase in changed(newPhase) }
        }
    }
}

struct RootView: View {
    @State var game: Game? = nil
    @State var settings: Settings = SettingsStore.load()
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        ZStack {
            if let g = game {
                GameView(game: g, quit: { leave() })
            } else {
                MenuView(settings: $settings) { g in
                    game = g
                }
            }
        }
        .preferredColorScheme(.dark)
        .modifier(PhaseWatcher(phase: scenePhase, changed: phaseChanged))
    }

    func phaseChanged(_ phase: ScenePhase) {
        if phase != .active, let g = game {
            _ = g.saveNow()
            SettingsStore.save(settings)
        }
    }

    func leave() {
        if let g = game {
            _ = g.saveNow()
            settings.touchControls = g.settings.touchControls
            settings.smoothLight = g.settings.smoothLight
            settings.fps60 = g.settings.fps60
            settings.showFPS = g.settings.showFPS
            settings.showCoords = g.settings.showCoords
            settings.tilePx = g.tilePx
            SettingsStore.save(settings)
            if g.mode == .hardcore && g.hardcoreOver { SaveStore.delete(g.slot) }
        }
        actState.held = false
        game = nil
    }
}

@main
struct PixelRealmApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
