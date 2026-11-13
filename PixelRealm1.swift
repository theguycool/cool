// PIXEL REALM v2, part 1 of 6: utilities, tiles, items, recipes, creature sprites, world generation, chunks, villages and
// ruins, the Umbral Realm, the world, light and physics, and the hand-drawn pictures kept as text.
// The game is six files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm6.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 1 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// ===== p01_util =====
// ============================================================
// PIXEL REALM 2  -  expanded survival sandbox
// Six files (see the top of each part). iOS 16+ / macOS 13+.
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

func clampD(_ v: Double, _ lo: Double, _ hi: Double) -> Double { return max(lo, min(hi, v)) }
func lerpD(_ a: Double, _ b: Double, _ t: Double) -> Double { return a + (b - a) * t }
func clampI(_ v: Int, _ lo: Int, _ hi: Int) -> Int { return max(lo, min(hi, v)) }

func floorDiv(_ a: Int, _ b: Int) -> Int {
	var q: Int = a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) { q -= 1 }
	return q
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

/// The game's colour grade (the same as `grade` in tools/art/artlib.py, which the hand-drawn art went
/// through): strong colours lose some saturation and the brightest of them a little brightness, so
/// the world reads earthy rather than candy-bright. Greys and dark tones barely move. It is used for
/// what is still drawn in code (older blocks and creatures, the sky, item icons, sparks) and for the
/// colours a player picks for their look.
let gradeSat: Double = 0.42
let gradeVal: Double = 0.20

func artGrade(_ c: UInt32) -> UInt32 {
	let r: Double = Double((c >> 16) & 255) / 255.0
	let g: Double = Double((c >> 8) & 255) / 255.0
	let b: Double = Double(c & 255) / 255.0
	let mx: Double = max(r, max(g, b))
	let mn: Double = min(r, min(g, b))
	if mx <= 0 || mx == mn { return c & 0xFFFFFF }
	let s: Double = (mx - mn) / mx
	let s2: Double = s * (1.0 - gradeSat * s)
	let v2: Double = mx * (1.0 - gradeVal * mx * s)
	let lo2: Double = v2 * (1.0 - s2)
	func ch(_ x: Double) -> UInt32 {
		let t: Double = (x - mn) / (mx - mn)
		return UInt32(clampD(((lo2 + (v2 - lo2) * t) * 255.0).rounded(), 0, 255))
	}
	return (ch(r) << 16) | (ch(g) << 8) | ch(b)
}

/// A picture through the grade (each pixel keeps its opacity)
func gradeBuf(_ b: PixelBuf) -> PixelBuf {
	var o: PixelBuf = b
	for i in 0..<o.px.count {
		let c: UInt32 = o.px[i]
		if (c >> 24) == 0 { continue }
		o.px[i] = (c & 0xFF000000) | artGrade(c & 0xFFFFFF)
	}
	return o
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
			o.px[i] = (c & 0xFF000000) | mixRGB(c & 0xFFFFFF, rgb, amount)
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
	/// logs placed by the player as building blocks: solid, unlike tree trunks (appended, so the raw
	/// values of every existing tile, and therefore old saves, are unchanged)
	case logBlock, jungleLogBlock, palmLogBlock
	/// climbable: hold jump (or up) to climb, down to descend
	case ladder
	/// workstations: metalwork from iron up, machinery and vehicles, and Umbral gear
	case anvil, tinkerBench, riftForge
	/// crystal deposits that line the walls of crystal grottos
	case crystalOre
	/// birch trunks (passable, like every tree trunk) and the solid block a placed birch log becomes,
	/// birch and pine foliage
	case birchLog, birchLogBlock, birchLeaves, pineLeaves
	/// ores of the upper ground and the middle depths (tin, saltpeter, silver, amethyst geodes), a
	/// building block cut from amethyst, and old mine fittings: rails, supply crates and ore carts
	case tin, saltpeter, silver, amethyst, amethystBlock, rail, crate, oreCart
	/// weather (appended): a weather station and its Doppler upgrade, a storm siren, a lightning rod, a
	/// wind turbine, a rain barrel and the larger cistern, a weather vane, a heater, and storm building:
	/// sandbags, storm shutters (closed and open), reinforced walls and storm shingles
	case weatherStation, dopplerStation, stormSiren, lightningRod, windTurbine, rainBarrel, rainCistern, weatherVane, heater
	case sandbag, shutterClosed, shutterOpen, stormBrick, shingles
	/// Sparkworks power and automation (appended): generators, storage, power control, pulse sources
	/// and logic, sensors, and machines (lamps and gates have on and off forms)
	case crankGen, solarPanel, fuelGen, waterWheel, emberDynamo
	case battery, accumulator
	case powerSwitch, breaker, powerMeter
	case lever, pushButton, pressurePlate, pulseTimer, repeater, inverter, logicGate
	case motionSensor, daySensor, weatherSensor, itemSensor, proximitySensor
	case gateClosed, gateOpen, lampOff, lampOn, arcTrap, autoDrill, conveyor, collector, autoCrafter, sumpPump, signalLight
	/// reserved for blocks from mods (appended): what each one is depends on the mods the world uses
	/// (see ModRuntime); each world remembers which block has which number
	case mod00, mod01, mod02, mod03, mod04, mod05, mod06, mod07, mod08, mod09, mod10, mod11, mod12, mod13, mod14, mod15, mod16, mod17, mod18, mod19, mod20, mod21, mod22, mod23, mod24, mod25, mod26, mod27, mod28, mod29, mod30, mod31, mod32, mod33, mod34, mod35, mod36, mod37, mod38, mod39, mod40, mod41, mod42, mod43, mod44, mod45, mod46, mod47, mod48, mod49, mod50, mod51, mod52, mod53, mod54, mod55, mod56, mod57, mod58, mod59, mod60, mod61, mod62, mod63
	/// alchemy, infusion and the exosuit (appended after the mod tiles, so every saved number stays)
	case alchemyStill, infuser, exoStation
	/// a young tree (appended): planted on soil, it grows into a tree that suits the land it stands in
	case sapling
	/// furniture (appended): to sit on, sleep in, keep things in, or to make a room look lived in. A bed
	/// is two tiles, its head on the left
	case chair, table, bedL, bedR, cabinet, wardrobe, shelf, bookshelf, floorLamp, sofa
	/// stairs (appended), rising to the right (R) or the left (L): a full-width lower step and a
	/// half-width upper one, walked up like any step (see World.stairHit)
	case stairWoodR, stairWoodL, stairStoneR, stairStoneL, stairBrickR, stairBrickL
	/// elevators (appended): the rail a lift car runs on, the button that calls it to a floor, and the
	/// car itself (an item: placed on a rail it becomes a moving Lift)
	case liftRail, liftButton, liftCar

	// the tables are built once; the reserved mod tiles are rewritten when a world's mods are switched
	// on (see `patch`), the game's own tiles never change
	static var defTable: [TileDef] = Tile.allCases.map { Tile.makeDef($0) }
	static var solidTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid }
	static var opaqueTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).opaque }
	static var lightTable: [Int] = Tile.allCases.map { Tile.makeDef($0).light }
	static var liquidTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).liquid }
	/// what a vehicle can meet: anything solid, any liquid
	static var meetTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid || Tile.makeDef($0).liquid }
	static var hurtTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).hurt }
	static var platformTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).platform }
	static var plantTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).plant }
	static var hardTable: [Double] = Tile.allCases.map { Tile.makeDef($0).hard }
	static var tierTable: [Int] = Tile.allCases.map { Tile.makeDef($0).tier }
	/// things can rest on or hang from these (solid tiles, plus tree trunks, which have no collision)
	static var supportTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid || isLogTile($0) || stairSide($0) != 0 }
	/// rain, hail and lightning stop at these (anything solid, glass, platforms, leaves, water)
	static var rainStopTable: [Bool] = Tile.allCases.map { Tile.makeDef($0).solid || Tile.makeDef($0).platform || Tile.makeDef($0).liquid || isLeafTile($0) || stairSide($0) != 0 }
	/// stairs by raw value: 1 rising to the right, 2 rising to the left, 0 not a stair (see World.stairHit)
	static let stairTable: [UInt8] = Tile.allCases.map { stairSide($0) }
	static let deviceTable: [Bool] = Tile.allCases.map { isWeatherDevice($0) }
	/// the game's own devices (a mod block's power role is per world: see isPower)
	static let powerTable: [Bool] = Tile.allCases.map { !$0.isMod && powerRole($0) != .none }
	/// the tool that mines each reserved mod tile at full speed
	static var modToolTable: [ToolType] = [ToolType](repeating: .pickaxe, count: ModLimits.blockSlots)
	/// the first tile number reserved for mods
	static let modBase: UInt8 = Tile.mod00.rawValue

	/// a tile reserved for a mod block
	var isMod: Bool { return rawValue >= Tile.modBase && Int(rawValue) < Int(Tile.modBase) + ModLimits.blockSlots }

	/// Rewrites one reserved mod tile in every table
	static func patch(_ t: Tile, _ d: TileDef, tool: ToolType) {
		let i: Int = Int(t.rawValue)
		if !t.isMod || i >= defTable.count { return }
		defTable[i] = d
		solidTable[i] = d.solid
		meetTable[i] = d.solid
		opaqueTable[i] = d.opaque
		lightTable[i] = d.light
		liquidTable[i] = d.liquid
		meetTable[i] = d.solid || d.liquid
		hurtTable[i] = d.hurt
		platformTable[i] = d.platform
		plantTable[i] = d.plant
		hardTable[i] = d.hard
		tierTable[i] = d.tier
		supportTable[i] = d.solid
		rainStopTable[i] = d.solid || d.platform || d.liquid
		modToolTable[i - Int(modBase)] = tool
	}

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
	var supportsThings: Bool { return Tile.supportTable[i8(rawValue)] }
	/// a Sparkworks device (or the wind turbine, which feeds power cable too)
	var isPower: Bool { return Tile.powerTable[i8(rawValue)] || (isMod && ModRuntime.shared.powerTiles[rawValue] != nil) }

	/// The tile a held block becomes when placed: a log item builds a solid log block, not a tree trunk
	var placedForm: Tile {
		switch self {
		case .log: return .logBlock
		case .jungleLog: return .jungleLogBlock
		case .palmLog: return .palmLogBlock
		case .birchLog: return .birchLogBlock
		default: return self
		}
	}

	/// The other way round: the tree trunk a solid log block stands for (trees are never walls)
	var trunkForm: Tile {
		switch self {
		case .logBlock: return .log
		case .jungleLogBlock: return .jungleLog
		case .palmLogBlock: return .palmLog
		case .birchLogBlock: return .birchLog
		default: return self
		}
	}

	static func make(_ raw: UInt8) -> Tile { return Tile(rawValue: raw) ?? .air }

	/// The game's own tiles (mods change them through OverrideRT), kept as text: a table of TileDef(...)
	/// calls made the game's build much bigger. A line a tile (or several, split by commas): its names, what
	/// it is called, then the settings that differ from TileDef's: hard, tier, solid, opaque, light, liquid,
	/// platform, plant, hurt, style, colors (hex), drop (block:<tile> or mat:<material>), noDrop; a note after "//"
	static let gameDefs: [UInt8: TileDef] = parseDefs(defText)

	static func makeDef(_ t: Tile) -> TileDef {
		if let d = gameDefs[t.rawValue] { return d }
		// the tiles reserved for mods, until a world's mods give them a meaning (see ModRuntime)
		return TileDef(name: "Unused Mod Block", hard: 9999, style: .custom, colors: [0xFF00FF, 0x200020, 0xFF00FF, 0x200020, 0xFF00FF], noDrop: true)
	}

	static func parseDefs(_ s: String) -> [UInt8: TileDef] {
		var tiles: [String: Tile] = [:]
		for t in Tile.allCases { tiles[String(describing: t)] = t }
		var mats: [String: Mat] = [:]
		for m in Mat.allCases { mats[String(describing: m)] = m }
		var styles: [String: TStyle] = [:]
		var n: Int = 0
		while let st = TStyle(rawValue: n) {
			styles[String(describing: st)] = st
			n += 1
		}
		var out: [UInt8: TileDef] = [:]
		for line in s.split(separator: "\n") {
			let text: String = line.components(separatedBy: " //")[0]
			let f: [String] = text.components(separatedBy: "|")
			guard f.count >= 2 else { continue }
			var d = TileDef(name: f[1])
			for kv in f.dropFirst(2) {
				let p: [String] = kv.components(separatedBy: "=")
				guard p.count == 2 else { continue }
				let v: String = p[1]
				let on: Bool = v == "1"
				switch p[0] {
				case "hard": d.hard = Double(v) ?? d.hard
				case "tier": d.tier = Int(v) ?? 0
				case "light": d.light = Int(v) ?? 0
				case "solid": d.solid = on
				case "opaque": d.opaque = on
				case "liquid": d.liquid = on
				case "platform": d.platform = on
				case "plant": d.plant = on
				case "hurt": d.hurt = on
				case "noDrop": d.noDrop = on
				case "style": d.style = styles[v] ?? d.style
				case "colors": d.colors = v.split(separator: ",").compactMap { UInt32($0, radix: 16) }
				case "drop":
					let q: [String] = v.components(separatedBy: ":")
					if q.count == 2, q[0] == "block", let b = tiles[q[1]] { d.drop = .block(b) }
					if q.count == 2, q[0] == "mat", let m = mats[q[1]] { d.drop = .mat(m) }
				default: break
				}
			}
			for name in f[0].split(separator: ",") {
				if let t = tiles[String(name)] { out[t.rawValue] = d }
			}
		}
		return out
	}

	static let defText: String = """
		air|Air|hard=0|solid=0|opaque=0
		grass|Grass|hard=0.5|style=grassTop|colors=5DAA3A,4B9230,7A5230,5A3A1E,8A6038|drop=block:dirt
		dirt|Dirt|hard=0.4|colors=7A5230,6B4626,8A6038,5A3A1E,7A5230
		stone|Stone|hard=1.2|tier=1|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A
		sand|Sand|hard=0.4|colors=E0D08A,D2C078,EBDDA0,C4B268,E0D08A
		log|Log|hard=0.9|solid=0|opaque=0|style=log|colors=6B4A2A,5A3C20,7C5733,4A3018,6B4A2A // tree trunks have no collision: everything walks (and flies, drives and shoots) through them, and they let skylight past like the canopy does (a trunk standing on the ground used to cast a dark shaft down through it). See logBlock for the solid building block.
		leaves|Leaves|hard=0.2|solid=0|opaque=0|platform=1|style=leaves|colors=3E8A2E,2F7324,56A83F,225C1A,3E8A2E|noDrop=1 // canopies are one-way: walk and shoot through them, land on top of them
		water|Water|hard=0|solid=0|opaque=0|liquid=1|style=water|colors=3B7BE0,4F90F0,2E64C0,8DBBFF,3B7BE0|noDrop=1
		coal|Coal Ore|hard=1.6|tier=1|style=ore|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,1E1E1E,333333|drop=mat:coal
		copper|Copper Ore|hard=1.8|tier=2|style=ore|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,D2793A,F0A060|drop=mat:copperOre
		iron|Iron Ore|hard=2.2|tier=3|style=ore|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,D8A878,B88858|drop=mat:ironOre
		gold|Gold Ore|hard=2.6|tier=4|light=2|style=ore|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,F5D142,FFE98A|drop=mat:goldOre
		diamond|Diamond Ore|hard=3.2|tier=5|light=4|style=ore|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,4FE3E8,B8FBFF|drop=mat:diamond
		mythril|Mythril Ore|hard=4.0|tier=6|light=5|style=ore|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,6A5CFF,B3A8FF|drop=mat:mythrilOre
		planks|Planks|hard=0.8|style=planks|colors=B98A4E,8F6732,C89B5E,7A5628,B98A4E
		glass|Glass|hard=0.3|opaque=0|style=glass|colors=CFEFFF,FFFFFF,9CCBE0,CFEFFF,CFEFFF
		brick|Stone Brick|hard=1.5|tier=1|style=bricks|colors=A64B3C,8A8A8A,B85A48,8E3B2E,A64B3C
		bedrock|Bedrock|hard=9999|tier=99|colors=3A3A3A,2A2A2A,4A4A4A,1A1A1A,3A3A3A|noDrop=1
		snow|Snow|hard=0.3|style=snow|colors=F2F8FF,DCEBFA,FFFFFF,C4D8EE,F2F8FF
		ice|Ice|hard=0.5|opaque=0|style=ice|colors=AEDCF5,8CC8EC,D6F0FF,78B4DC,AEDCF5
		sandstone|Sandstone|hard=1.0|tier=1|style=sandstone|colors=D2B574,C4A562,DEC488,B89850,D2B574
		cactus|Cactus|hard=0.4|hurt=1|style=cactus|colors=3F8F3F,2F7A2F,58AE58,1F5F1F,3F8F3F
		jungleLeaves|Jungle Leaves|hard=0.2|solid=0|opaque=0|platform=1|style=leaves|colors=1F8A3A,146B2A,32AA4E,0E5420,1F8A3A|noDrop=1
		mud|Mud|hard=0.5|style=mud|colors=4E3A2A,3E2E20,5E4834,30241A,4E3A2A
		dryGrass|Dry Grass|hard=0.5|style=grassTop|colors=BDB35A,A39A48,7A5230,5A3A1E,8A6038|drop=block:dirt
		jungleGrass|Jungle Grass|hard=0.5|style=grassTop|colors=2E9E3A,1F8A2C,4E3A2A,3E2E20,5E4834|drop=block:mud
		mossGrass|Moss|hard=0.5|style=grassTop|colors=6E8A3A,5A7430,4E3A2A,3E2E20,5E4834|drop=block:mud
		slate|Slate|hard=1.7|tier=1|colors=5E6678,4F5666,6D7688,40475A,5E6678
		deepRock|Deep Rock|hard=2.6|tier=3|colors=3E3846,34303C,4A4452,2A2632,3E3846
		lava|Lava|hard=0|solid=0|opaque=0|light=14|liquid=1|hurt=1|style=lava|colors=E8580C,FF8A1E,C03A06,FFD060,E8580C|noDrop=1
		obsidian|Obsidian|hard=4.2|tier=5|colors=241838,1A1028,34244E,120A1E,241838
		tallGrass|Tall Grass|hard=0|solid=0|opaque=0|plant=1|style=custom|noDrop=1
		flowerR|Red Flower|hard=0|solid=0|opaque=0|plant=1|style=custom
		flowerY|Yellow Flower|hard=0|solid=0|opaque=0|plant=1|style=custom
		deadBush|Dead Bush|hard=0|solid=0|opaque=0|plant=1|style=custom|drop=mat:stick
		mushroom|Glow Mushroom|hard=0|solid=0|opaque=0|light=6|plant=1|style=custom
		reed|Reed|hard=0|solid=0|opaque=0|plant=1|style=custom|drop=mat:stick
		workbench|Workbench|hard=0.6|solid=0|opaque=0|style=custom
		furnace|Furnace|hard=1.0|tier=1|solid=0|opaque=0|light=7|style=custom
		campfire|Campfire|hard=0.5|solid=0|opaque=0|light=13|hurt=0|style=custom
		torch|Torch|hard=0|solid=0|opaque=0|light=12|plant=1|style=custom
		lantern|Lantern|hard=0.2|solid=0|opaque=0|light=14|plant=1|style=custom
		chest|Chest|hard=0.8|solid=0|opaque=0|style=custom|noDrop=0
		platform|Platform|hard=0.3|solid=0|opaque=0|platform=1|style=custom
		farmland|Farmland|hard=0.4|style=farmland|colors=5A3A1E,4A2E16,6B4626,3A220E,5A3A1E|drop=block:dirt
		wheat1,wheat2,wheat3|Wheat|hard=0|solid=0|opaque=0|plant=1|style=custom|noDrop=1
		carrot1,carrot2,carrot3|Carrots|hard=0|solid=0|opaque=0|plant=1|style=custom|noDrop=1
		crackedBrick|Cracked Brick|hard=1.0|tier=1|style=bricks|colors=8E7A68,6A5A4C,A08C78,5A4A3C,8E7A68
		mossBrick|Mossy Brick|hard=1.4|tier=1|style=bricks|colors=6E8A5A,4C5E3E,82A06C,3C4C30,6E8A5A
		spikes|Spikes|hard=0.8|tier=1|solid=0|opaque=0|hurt=1|style=custom
		fossil|Fossil Block|hard=1.5|tier=1|style=custom|drop=mat:bone
		ashStone|Ashstone|hard=2.2|tier=4|style=ash|colors=4A3A48,3C2E3A,5A4858,2E222C,4A3A48
		emberOre|Ember Ore|hard=3.4|tier=7|light=7|style=ore|colors=4A3A48,3C2E3A,5A4858,2E222C,4A3A48,FF7A1E,FFC050|drop=mat:emberOre
		voidOre|Voidium Ore|hard=4.6|tier=8|light=8|style=ore|colors=4A3A48,3C2E3A,5A4858,2E222C,4A3A48,B04CFF,E8A8FF|drop=mat:voidOre
		glowCrystal|Glow Crystal|hard=1.2|tier=4|opaque=0|light=11|style=crystal|colors=7A4CFF,B38CFF,4E2AC0,E6D8FF,7A4CFF
		portalFrame|Rift Anchor|hard=99999|tier=99|light=4|style=custom|colors=23262E,3A3F4A,2E323B,16181E,23262E|noDrop=1
		portalOff|Dormant Rift|hard=99999|tier=99|solid=0|opaque=0|style=custom|noDrop=1
		portalOn|Open Rift|hard=99999|tier=99|solid=0|opaque=0|light=13|style=custom|noDrop=1
		jungleLog|Jungle Log|hard=1.0|solid=0|opaque=0|style=log|colors=5A4A2A,4A3A20,6C5C34,3A2C14,5A4A2A
		palmLog|Palm Log|hard=0.8|solid=0|opaque=0|style=log|colors=9A7A4A,826238,B08C58,6A4E2A,9A7A4A
		cobweb|Cobweb|hard=0.1|solid=0|opaque=0|plant=1|style=custom|noDrop=1
		hay|Hay Bale|hard=0.4|style=noise|colors=D8B83A,BE9E2A,E8CC52,A88820,D8B83A
		doorClosed|Wooden Door|hard=0.6|solid=1|opaque=0|style=custom|colors=8F6732|drop=block:doorClosed
		doorOpen|Open Door|hard=0.6|solid=0|opaque=0|style=custom|colors=8F6732|drop=block:doorClosed
		logBlock|Log|hard=0.9|style=log|colors=6B4A2A,5A3C20,7C5733,4A3018,6B4A2A|drop=block:log
		jungleLogBlock|Jungle Log|hard=1.0|style=log|colors=5A4A2A,4A3A20,6C5C34,3A2C14,5A4A2A|drop=block:jungleLog
		palmLogBlock|Palm Log|hard=0.8|style=log|colors=9A7A4A,826238,B08C58,6A4E2A,9A7A4A|drop=block:palmLog
		ladder|Ladder|hard=0.3|solid=0|opaque=0|style=custom|colors=9A6E3A
		anvil|Anvil|hard=1.6|tier=1|solid=0|opaque=0|style=custom|colors=5A5E68
		tinkerBench|Tinker's Bench|hard=0.8|solid=0|opaque=0|style=custom|colors=8F6732
		riftForge|Rift Forge|hard=3.0|tier=5|solid=0|opaque=0|light=9|style=custom|colors=2A1A3A
		crystalOre|Crystal Vein|hard=2.8|tier=4|light=6|style=custom|colors=5E6678,4F5666,6D7688,40475A,5E6678,8AF0E8,D8FFFA|drop=mat:crystalShard
		birchLog|Birch Log|hard=0.8|solid=0|opaque=0|style=custom|colors=E2DED2,C8C4B8,F4F2EA,3A3632,E2DED2
		birchLogBlock|Birch Log|hard=0.8|style=custom|colors=E2DED2,C8C4B8,F4F2EA,3A3632,E2DED2|drop=block:birchLog
		birchLeaves|Birch Leaves|hard=0.2|solid=0|opaque=0|platform=1|style=leaves|colors=7DB846,649A34,9ACC5A,4E7E28,7DB846|noDrop=1
		pineLeaves|Pine Needles|hard=0.2|solid=0|opaque=0|platform=1|style=leaves|colors=2E6E52,225A42,3E8464,18463A,2E6E52|noDrop=1
		tin|Tin Ore|hard=1.7|tier=2|style=custom|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,C8D2DA,F2F6FA|drop=mat:tinOre
		saltpeter|Saltpeter|hard=1.0|tier=1|style=custom|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,EDEAE0,FFFFFF|drop=mat:saltpeter
		silver|Silver Ore|hard=2.4|tier=3|light=1|style=custom|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,DDE4EE,FFFFFF|drop=mat:silverOre
		amethyst|Amethyst Geode|hard=1.8|tier=2|light=4|style=custom|colors=8A8A8A,7A7A7A,9A9A9A,6A6A6A,8A8A8A,9A5ADC,E0C0FF|drop=mat:amethyst
		amethystBlock|Amethyst Block|hard=1.4|tier=1|light=6|style=crystal|colors=8A4CC8,B07AE8,6A34A8,E8D0FF,8A4CC8
		rail|Rail|hard=0.2|solid=0|opaque=0|plant=1|style=custom|colors=6A6A72
		crate|Supply Crate|hard=0.7|style=custom|colors=A97B45
		oreCart|Ore Cart|hard=0.8|solid=0|opaque=0|style=custom|colors=5A5E68|noDrop=1
		weatherStation|Weather Station|hard=1.0|solid=0|opaque=0|light=3|style=custom|colors=8F6732
		dopplerStation|Doppler Station|hard=1.4|tier=1|solid=0|opaque=0|light=5|style=custom|colors=5A6470
		stormSiren|Storm Siren|hard=1.4|tier=1|solid=0|opaque=0|style=custom|colors=8A8E98
		lightningRod|Lightning Rod|hard=0.8|solid=0|opaque=0|style=custom|colors=D2793A
		windTurbine|Wind Turbine|hard=1.2|tier=1|solid=0|opaque=0|style=custom|colors=C8CCD4
		rainBarrel|Rain Barrel|hard=0.7|solid=0|opaque=0|style=custom|colors=8F6732
		rainCistern|Rain Cistern|hard=1.4|tier=1|solid=0|opaque=0|style=custom|colors=6A6E78
		weatherVane|Weather Vane|hard=0.6|solid=0|opaque=0|style=custom|colors=D2793A
		heater|Heater|hard=1.2|tier=1|solid=0|opaque=0|light=9|style=custom|colors=4A4E58
		sandbag|Sandbags|hard=0.9|style=custom|colors=B8A070
		shutterClosed|Storm Shutter|hard=1.0|style=custom|colors=6A7A5A|drop=block:shutterClosed
		shutterOpen|Open Shutter|hard=1.0|solid=0|opaque=0|style=custom|colors=6A7A5A|drop=block:shutterClosed
		stormBrick|Reinforced Wall|hard=3.0|tier=2|style=custom|colors=6A6E78
		shingles|Storm Shingles|hard=1.1|tier=1|style=custom|colors=7A4A3A
		crankGen|Hand Crank Generator|hard=1.0|solid=0|opaque=0|style=custom|colors=5A6270
		solarPanel|Solar Panel|hard=1.0|tier=1|solid=0|opaque=0|style=custom|colors=2A5A9A
		fuelGen|Fuel Generator|hard=1.4|tier=1|solid=0|opaque=0|style=custom|colors=5A6270
		waterWheel|Water Wheel|hard=0.9|solid=0|opaque=0|style=custom|colors=8F6732
		emberDynamo|Ember Dynamo|hard=2.4|tier=4|solid=0|opaque=0|light=5|style=custom|colors=2A1E2E
		battery|Copper Cell|hard=1.0|tier=1|solid=0|opaque=0|style=custom|colors=5A6270
		accumulator|Crystal Accumulator|hard=1.8|tier=2|solid=0|opaque=0|light=3|style=custom|colors=30A0A0
		powerSwitch|Power Switch|hard=0.6|solid=0|opaque=0|style=custom|colors=5A6270
		breaker|Circuit Breaker|hard=0.8|solid=0|opaque=0|style=custom|colors=5A6270
		powerMeter|Power Meter|hard=0.6|solid=0|opaque=0|style=custom|colors=E8E4D8
		lever|Lever|hard=0.5|solid=0|opaque=0|style=custom|colors=5A6270
		pushButton|Push Button|hard=0.5|solid=0|opaque=0|style=custom|colors=30B0C0
		pressurePlate|Pressure Plate|hard=0.5|solid=0|opaque=0|style=custom|colors=8A94A4
		pulseTimer|Pulse Timer|hard=0.6|solid=0|opaque=0|style=custom|colors=E8E4D8
		repeater|Pulse Relay|hard=0.6|solid=0|opaque=0|style=custom|colors=5A6270
		inverter|Inverter|hard=0.6|solid=0|opaque=0|style=custom|colors=6A4A7A
		logicGate|Logic Gate|hard=0.6|solid=0|opaque=0|style=custom|colors=3A6A6A
		motionSensor|Motion Sensor|hard=0.7|solid=0|opaque=0|style=custom|colors=C86A3A
		daySensor|Daylight Sensor|hard=0.7|solid=0|opaque=0|style=custom|colors=5A8AC8
		weatherSensor|Weather Sensor|hard=0.7|solid=0|opaque=0|style=custom|colors=3B7BE0
		itemSensor|Item Sensor|hard=0.7|solid=0|opaque=0|style=custom|colors=A97B45
		proximitySensor|Proximity Sensor|hard=0.7|solid=0|opaque=0|style=custom|colors=30E0D0
		gateClosed|Steel Gate|hard=2.2|tier=2|opaque=0|style=custom|colors=8A94A4|drop=block:gateClosed
		gateOpen|Open Steel Gate|hard=2.2|tier=2|solid=0|opaque=0|style=custom|colors=8A94A4|drop=block:gateClosed
		lampOff|Spark Lamp|hard=0.8|opaque=0|style=custom|colors=8A9AA0|drop=block:lampOff
		lampOn|Lit Spark Lamp|hard=0.8|opaque=0|light=15|style=custom|colors=FFF4C0|drop=block:lampOff
		arcTrap|Arc Trap|hard=1.8|tier=2|style=custom|colors=5A6270
		autoDrill|Auto Drill|hard=2.0|tier=2|style=custom|colors=E8C020
		conveyor|Conveyor Belt|hard=1.2|tier=1|style=custom|colors=2A2A2E
		collector|Item Collector|hard=1.2|tier=1|style=custom|colors=8A94A4
		autoCrafter|Auto Crafter|hard=1.6|tier=2|style=custom|colors=B0A060
		sumpPump|Sump Pump|hard=1.4|tier=1|style=custom|colors=3B7BE0
		signalLight|Pulse Indicator|hard=0.4|solid=0|opaque=0|style=custom|colors=30E0D0
		alchemyStill|Alchemy Still|hard=1.0|solid=0|opaque=0|light=4|style=custom|colors=D2793A
		infuser|Infusion Crucible|hard=2.0|tier=1|solid=0|opaque=0|light=6|style=custom|colors=6A5A8A
		exoStation|Assembly Station|hard=2.0|tier=1|solid=0|opaque=0|style=custom|colors=5A6270
		sapling|Sapling|hard=0|solid=0|opaque=0|plant=1|style=custom|colors=4B9A30
		chair|Chair|hard=0.4|solid=0|opaque=0|style=custom|colors=A0703A
		table|Table|hard=0.5|solid=0|opaque=0|platform=1|style=custom|colors=C89B5E
		bedL|Bed|hard=0.4|solid=0|opaque=0|platform=1|style=custom|colors=C03838
		bedR|Bed|hard=0.4|solid=0|opaque=0|platform=1|style=custom|colors=C03838|drop=block:bedL
		cabinet|Cabinet|hard=0.6|solid=0|opaque=0|platform=1|style=custom|colors=9A6A38
		wardrobe|Wardrobe|hard=0.6|solid=0|opaque=0|style=custom|colors=7A5230
		shelf|Shelf|hard=0.3|solid=0|opaque=0|platform=1|style=custom|colors=C89B5E
		bookshelf|Bookshelf|hard=0.6|solid=0|opaque=0|platform=1|style=custom|colors=8F6732
		floorLamp|Floor Lamp|hard=0.3|solid=0|opaque=0|light=13|style=custom|colors=FFE680
		sofa|Sofa|hard=0.4|solid=0|opaque=0|style=custom|colors=3A6AA8
		stairWoodR,stairWoodL|Wooden Stairs|hard=0.6|solid=0|opaque=0|style=custom|colors=C89B5E|drop=block:stairWoodR
		stairStoneR,stairStoneL|Stone Stairs|hard=1.4|tier=1|solid=0|opaque=0|style=custom|colors=8A8A8A|drop=block:stairStoneR
		stairBrickR,stairBrickL|Brick Stairs|hard=1.6|tier=1|solid=0|opaque=0|style=custom|colors=B0503A|drop=block:stairBrickR
		liftRail|Lift Rail|hard=0.5|solid=0|opaque=0|style=custom|colors=9AA4B0
		liftButton|Lift Button|hard=0.3|solid=0|opaque=0|light=4|style=custom|colors=5A6270
		liftCar|Lift Car|hard=0.5|solid=0|opaque=0|style=custom|colors=7A8490
		"""
}

// MARK: - Tile art

func customTileRows(_ t: Tile) -> ([String], [Character: UInt32])? {
	switch t {
	case .stairWoodR, .stairWoodL:
		let r: [String] = ["....tttt", "....pppp", "....pppp", "....PPPP", "tttttttt", "pppppppp", "pppppppp", "PPPPPPPP"]
		return (t == .stairWoodR ? r : r.map { String($0.reversed()) }, ["t": 0xE0B47A, "p": 0xC89B5E, "P": 0x8F6732])
	case .stairStoneR, .stairStoneL:
		let r: [String] = ["....tttt", "....sSss", "....ssSs", "....dddd", "tttttttt", "sSssSsss", "ssSsssSs", "dddddddd"]
		return (t == .stairStoneR ? r : r.map { String($0.reversed()) }, ["t": 0xB0B0B0, "s": 0x8A8A8A, "S": 0x9A9A9A, "d": 0x5E5E5E])
	case .stairBrickR, .stairBrickL:
		let r: [String] = ["....tttt", "....bbmb", "....bbmb", "....mmmm", "tttttttt", "bbmbbbmb", "bbmbbbmb", "mmmmmmmm"]
		return (t == .stairBrickR ? r : r.map { String($0.reversed()) }, ["t": 0xD07050, "b": 0xB0503A, "m": 0x8A8070])
	default:
		return TileArt.rows[t.rawValue]
	}
}

/// The 8x8 art of most tiles, kept as text (a table of string literals in code made the game's
/// build much bigger): a line a tile, its name, its rows from the top split by commas ("." is
/// clear), then what each letter paints, and a note after "//"
enum TileArt {
	static let rows: [UInt8: ([String], [Character: UInt32])] = parse(text)

	static func parse(_ s: String) -> [UInt8: ([String], [Character: UInt32])] {
		var byName: [String: Tile] = [:]
		for t in Tile.allCases { byName[String(describing: t)] = t }
		var out: [UInt8: ([String], [Character: UInt32])] = [:]
		for line in s.split(separator: "\n") {
			let text: Substring = line.components(separatedBy: " //").first.map { Substring($0) } ?? line
			let f: [Substring] = text.split(separator: " ")
			guard f.count >= 2, let t = byName[String(f[0])] else { continue }
			let rows: [String] = f[1].split(separator: ",").map { String($0) }
			var pal: [Character: UInt32] = [:]
			for e in f.dropFirst(2) {
				guard e.count > 2, let k = e.first, let v = UInt32(e.dropFirst(2), radix: 16) else { continue }
				pal[k] = v
			}
			out[t.rawValue] = (rows, pal)
		}
		return out
	}

	static let text: String = """
		torch .......,...y...,..yoy..,...r...,...b...,...b...,...b...,...b... y=FFE680 o=FFA030 r=E05818 b=8A5A2A
		lantern ...kk...,..kyyk..,.kyYYyk.,.kyYYyk.,.kyyyyk.,..kkkk.. k=3A3A3A y=FFC84A Y=FFF2B0
		campfire ........,...y....,..yoy.y.,..oryo..,.bbrobb.,bbbbbbbb,ssbbbbss,........ y=FFE680 o=FFA030 r=E05818 b=6B4A2A s=808080
		workbench ........,........,tttttttt,bbbbbbbb,b.b..b.b,b.b..b.b,b.b..b.b,b.b..b.b t=C89B5E b=8F6732
		furnace ssssssss,sSSSSSSs,sSkkkkSs,sSkoOkSs,sSkOykSs,sSkkkkSs,sSSSSSSs,ssssssss s=6A6A6A S=8A8A8A k=2A2020 o=E05818 O=FFA030 y=FFE680
		chest ........,........,wwwwwwww,wddddddw,wwwgwwww,wddddddw,wddddddw,wwwwwwww w=8F6732 d=B98A4E g=F5D142
		platform ........,........,........,........,........,........,pppppppp,qqqqqqqq p=C89B5E q=8F6732
		tallGrass ........,........,........,.g...g..,.g.g.g.g,gg.g.ggg,gggggggg,gggggggg g=4B9A30
		flowerR ........,........,...rr...,..rYr...,...rr...,....g...,....g...,...ggg.. r=E63A3A Y=FFE060 g=3E8A2E
		flowerY ........,........,..yy....,.yOyy...,..yy....,...g....,...g....,..ggg... y=FFE040 O=E08A20 g=3E8A2E
		deadBush ........,........,.b...b..,..b.b...,...b..b.,..bbbb..,...b....,...b.... b=8A6A3A
		mushroom ........,........,..cccc..,.cCcccc.,.cccCcc.,...ww...,...ww...,...ww... c=3AC8C8 C=A8FFFF w=D8E8F0
		reed ...b....,...b..b.,...g..b.,...g..g.,.g.g..g.,.g.g.gg.,.g.ggg..,..gggg.. g=6E8A3A b=6B4A2A
		wheat1 ........,........,........,........,........,g.g..g.g,g.g..g.g,gggggggg g=7AB83A
		wheat2 ........,........,........,y.y..y.y,g.g..g.g,g.g..g.g,g.g..g.g,gggggggg g=8AB03A y=D8C050
		wheat3 y.y..y.y,yyy..yyy,yyy..yyy,y.y..y.y,g.g..g.g,g.g..g.g,g.g..g.g,gggggggg g=B0A030 y=E8C850
		carrot1 ........,........,........,........,........,..g..g..,.ggggg..,gggggggg g=4EA83A
		carrot2 ........,........,........,..g..g..,.ggggg..,.gggggg.,gggggggg,gggggggg g=4EB83A
		carrot3 ........,..g..g..,.ggggg..,.gggggg.,ggoggogg,gggggggg,gggoggog,gggggggg g=4EB83A o=F08A1E
		spikes ........,........,........,...s....,..sss.s.,.sssssss,ssssssss,dddddddd s=C8C8D0 d=5A5A5A
		fossil ssssssss,sbbsssss,ssbbssss,sssbbbbs,ssssbssb,sbbbssbs,ssbssbss,ssssssss s=8A8A8A b=E8E0C8
		portalOff ........ // drawn as one shape by the renderer's rift pass; the tiles themselves are see-through
		portalOn ........ // drawn as one shape by the renderer's rift pass; the tiles themselves are see-through
		portalFrame kkbbbbkk,kbbBbbbk,bbbbaBbb,bBbaabbb,bbaabbBb,bbabbbbb,kbbbBbbk,kkbbbbkk k=16181E b=2A2E37 B=3C424E a=C08040 // dark basalt anchor stone with an amber vein
		doorClosed dDDDDDDd,dDdddDDd,dDdddDDd,dDDDDDDd,dDDDDgDd,dDdddDDd,dDdddDDd,dDDDDDDd d=6A4A22 D=A97B45 g=E8C040
		doorOpen dD......,dD......,dD......,dD......,dD......,dD......,dD......,dD...... d=6A4A22 D=A97B45
		cobweb w.....w.,.w...w..,..w.w...,...w....,..w.w...,.w...w..,w.....w.,........ w=E8E8F0
		ladder .r....r.,.rgggggr,.r....r.,.r....r.,.r....r.,.rgggggr,.r....r.,.r....r. r=7A5428 g=B98A4E
		anvil ........,........,hhhhhhh.,.HHHHHHh,..sss...,..sss...,.bbbbb..,bbbbbbb. h=8A8E98 H=6A6E78 s=4A4E58 b=3A3E48
		tinkerBench ....g...,...ggg..,tttttttt,bbbbbbbb,b.c..k.b,b.c..k.b,b......b,b......b t=C89B5E b=8F6732 g=D8A040 c=B0B4BC k=C03A3A
		riftForge ..pppp..,.pPppPp.,oovvvvoo,ovVvvVvo,ovvVVvvo,oovvvvoo,oooooooo,oooooooo o=241838 p=8A4CD8 P=D8A8FF v=4A2A7A V=B070FF
		alchemyStill ..c.....,.ccc..g.,cCCCc.g.,cCCCcgg.,cCCCc.f.,.ccc.fFf,bbbbbfff,b...b... c=B8612A C=F0A060 g=CFEFFF f=B8E0F0 F=7AD040 b=5A4A3A // a copper pot on a stand, its coil running to a flask
		infuser ..p..p..,.PvvvvP.,svVVVVvs,sSvvvvSs,.sSSSSs.,..ssss..,.ssssss.,ssssssss p=C07CFF P=8A6AB8 v=9A5ADC V=E0B8FF s=5A5E68 S=7A7E88 // a stone crucible brimming with something that glows
		chair b.......,b.......,b.......,bsssss..,bSSSSS..,b....l..,b....l..,b....l.. b=7A5230 s=C08A50 S=9A6A38 l=7A5230 // side on, its back to the left
		table ........,........,tttttttt,TTTTTTTT,.l....l.,.l....l.,.l....l.,.l....l. t=C89B5E T=8F6732 l=7A5230
		bedL hh......,hh......,hh......,hhwwwbbb,hhWWWBBB,hhffffff,hh......,h....... h=7A5230 w=F0EEE6 W=C8C4B8 b=C83A3A B=962828 f=8F6732 // the headboard and the pillow
		bedR ........,........,.......f,bbbbbbbf,BBBBBBBf,ffffffff,.......f,.......f b=C83A3A B=962828 f=7A5230 // the foot of the bed
		cabinet tttttttt,cddkkddc,cddkkddc,cddddddc,cddddddc,cddddddc,cccccccc,c......c t=C89B5E c=7A5230 d=B07E48 k=E8C84A
		wardrobe cccccccc,cdddcddc,cddkckdc,cdddcddc,cdddcddc,cdddcddc,cccccccc,c......c c=5E3E22 d=8F6732 k=E8C84A
		shelf ........,........,..r..g..,.rr.ggb.,pppppppp,PPPPPPPP,.k....k.,........ r=C83A3A g=4E9A3E b=3A6AA8 p=C89B5E P=8F6732 k=5A5A5A
		bookshelf wwwwwwww,wrgbywbw,wrgbyrbw,wwwwwwww,wbyrgwrw,wbyrgbrw,wwwwwwww,w......w w=7A5230 r=B83A3A g=3E8A4E b=3A5AA8 y=D8B040
		floorLamp ..yyyy..,.yYYYYy.,.yyyyyy.,...ss...,...ss...,...ss...,..ssss..,.ssssss. y=E8C060 Y=FFF2B0 s=4A4A52
		sofa ........,bbbbbbbb,BbbbbbbB,aBccccBa,aBCCCCBa,aaaaaaaa,l......l,........ b=4A7AB8 B=3A6AA8 a=2E5A90 c=5A8AC8 C=4A7AB8 l=5E3E22
		liftRail Mm....mM,Mm....mM,Mm....mM,MmxxxxmM,Mm....mM,Mm....mM,Mm....mM,MmxxxxmM M=5A6270 m=9AA4B0 x=7A5230
		liftButton ........,..pppp..,..pUUp..,..pppp..,..pDDp..,..pppp..,........,........ p=4A5260 U=5AD05A D=E05050
		liftCar kkkkkkkk,k.k..k.k,k.k..k.k,k.k..k.k,k.k..k.k,k......k,ffffffff,FFFFFFFF k=5A6270 f=9AA4B0 F=4A5260
		sapling ........,...gg...,..gGgg..,.gg.bgg.,..g.b.g.,....b...,...bb...,....b... g=4B9A30 G=7AC84A b=7A5230 // a thin stem with a few young leaves
		exoStation kkkkkkkk,k.mmmm.k,k.mccm.k,kmmmmmmk,k.mmmm.k,k.m..m.k,ssssssss,sysyysys k=4A5260 m=9AA4B0 c=60E0FF s=3A3E48 y=E8C020 // a gantry with a suit hanging in its clamps
		crystalOre sSsdsSss,sdsscCss,ssscWCds,sSccWCcs,dscWCcss,ssCcsdSs,sSsssscs,dsSdsssS s=5E6678 S=6D7688 d=4F5666 c=3AA8B0 C=8AF0E8 W=E8FFFF // slate with a cluster of pale cyan shards breaking through it
		birchLog lwwwwwws,lwwkkwws,lwwwwwws,lwwwwwws,lkwwwwks,lwwwwwws,lwwwkkws,lwwwwwws l=F4F2EA w=E2DED2 k=3A3632 s=B8B4A8 // the newer ores each get their own shape, not just a colour, so they read at a glance in a dark cave
		birchLogBlock lwwwwwws,lwwkkwws,lwwwwwws,lwwwwwws,lkwwwwks,lwwwwwws,lwwwkkws,lwwwwwws l=F4F2EA w=E2DED2 k=3A3632 s=B8B4A8 // the newer ores each get their own shape, not just a colour, so they read at a glance in a dark cave
		tin sSsdssSs,sttsSdss,tWTtssds,sTTsdttS,ssdsTWTs,dSsstTTs,stTssdss,sTWsSssd s=8A8A8A S=9A9A9A d=6A6A6A t=AEB8C2 T=C8D2DA W=F2F6FA // rounded pale nuggets with a bright glint
		saltpeter sSswwsds,swwWwsss,ssssdSss,dsswwwWs,sSwWwsss,sssssdss,swwwSsds,sSdwWwws s=8A8A8A S=9A9A9A d=6A6A6A w=DCD8CC W=FFFFFF // a white crust in feathery streaks along the bedding of the rock
		silver sSssdsvW,ssdssvvs,sSsvvsSs,dsvvssds,svvsSsss,vWsssdss,vssdsSsv,sSdsssvW s=7E8088 S=92949C d=62646C v=C4CCD8 W=FFFFFF // thin bright veins with sparkling points
		amethyst sSsdssSs,ssdsaSss,sSsaAads,dsaAWAas,saAWAAas,aAAAaAAa,dsSssdSs,sSdssSsd s=8A8A8A S=9A9A9A d=6A6A6A a=7A3CBC A=B07AE8 W=EEDCFF // violet crystal points growing out of a hollow in the rock
		rail ........,........,........,........,........,........,rrrrrrrr,t.t..t.t r=9A9EA8 t=6A4A26
		crate pppppppp,pPddddPp,pdPddPdp,pddPPddp,pddPPddp,pdPddPdp,pPddddPp,pppppppp p=7A5628 P=A97B45 d=C89B5E
		oreCart ........,........,..oyoc..,mmmmmmmm,mMMMMMMm,mMMMMMMm,.kk..kk.,.kk..kk. m=4A4E58 M=6A6E78 o=D2793A y=C8D2DA c=2A2A2E k=2A2A2E // weather devices: each reads at a glance (cups on a station, a dish on the Doppler, a horn and beacon on the siren); their moving parts are drawn live over the tile
		weatherStation .c...c..,.ccpcc..,...p....,bbbbbbbb,bkkkkkkb,bkGgGgkb,bbbbbbbb,bb....bb c=C8CCD4 p=8A8E98 b=8F6732 k=1A2A2A G=60E0A0 g=2A8A5A
		dopplerStation ..dddd..,.dDDDDd.,...pp...,mmmmmmmm,mkkkkkkm,mkRgRgkm,mmmmmmmm,mm....mm d=E0E4EA D=9AA0AC p=6A6E78 m=5A6470 k=10181C R=FF5050 g=60E0A0
		stormSiren ...rr...,..rRRr..,..mmmm..,hHmmmmHh,hHmmmmHh,...pp...,...pp...,..bbbb.. r=C02020 R=FF6060 m=8A8E98 h=6A6E78 H=A8AEB8 p=5A5E68 b=3A3E48
		lightningRod ...yy...,...oo...,...oO...,...oO...,...oO...,...oO...,..bbbb..,.bbbbbb. y=FFE8A0 o=D2793A O=A85A28 b=5A5E68
		windTurbine ..nnnn..,..nNNn..,...pp...,...pp...,...pp...,...pp...,...pp...,..bbbb.. n=E8ECF0 N=C8CCD4 p=D8DCE2 b=6A6E78
		rainBarrel ........,.kddddk.,.bBbbBb.,.hhhhhh.,.bBbbBb.,.bBbbBb.,.hhhhhh.,.bBbbBb. k=5A3A1A d=2A1A0E b=8F6732 B=B98A4E h=5A5E68
		rainCistern mmmmmmmm,mkkkkkkm,mSSSSSSm,mSsSSsSm,mSSSSSSm,mSsSSsSm,mSSSSSSm,mmmmmmmm m=5A5E68 k=1A1A20 S=8A8A8A s=7A7A7A
		weatherVane ........,........,...yy...,...pp...,..cpPc..,...pp...,...pp...,..bbbb.. y=FFE8A0 p=A85A28 P=D2793A c=D2793A b=5A5E68
		heater ...pp...,...pp...,mmmmmmmm,mkooookm,mkOyOokm,mkooookm,mmmmmmmm,m.m..m.m p=4A4E58 m=5A5E68 k=2A2A2E o=E05818 O=FFA030 y=FFE680
		sandbag tTTttTTt,tttttttt,dttdtttd,TTttTTtt,tttttttt,tdtttdtt,tTTttTTt,tttttttt t=B8A070 T=D2BC8A d=8A7448
		shutterClosed ffffffff,fsSsSsSf,fssssssf,fsSsSsSf,fssssssf,fsSsSsSf,fssssssf,ffffffff f=4A4E58 s=6A7A5A S=8A9A72
		shutterOpen ff......,fs......,fS......,fs......,fS......,fs......,fS......,ff...... f=4A4E58 s=6A7A5A S=8A9A72
		stormBrick iiiiiiii,bbbkbbbk,bbbkbbbk,kkkkkkkk,bkbbbkbb,bkbbbkbb,iiiiiiii,bbbkbbbk i=9AA0AC b=6A6E78 k=4A4E58
		shingles rRrrRrrR,rrrrrrrr,kkkkkkkk,RrrRrrRr,rrrrrrrr,kkkkkkkk,rRrrRrrR,rrrrrrrr r=7A4A3A R=9A6250 k=4A2A20 // Sparkworks: slate casings with copper fittings and teal or amber lights; switch handles, dials, arrows, charge bars and moving parts are drawn live over the tile
		crankGen ......hH,...mm.h.,..mMMmh.,kmmmmmmk,kmccccmk,kmcaacmk,kmmmmmmk,kk....kk k=2E323A m=5A6270 M=8A94A4 c=D2793A a=FFC020 h=8A5A2A H=C89040
		solarPanel ........,bBbBbBbB,BbBbBbBb,bBbBbBbB,mmmmmmmm,...pp...,...pp...,..mmmm.. b=1A3A6A B=2E62A8 m=8A94A4 p=5A6270
		fuelGen .pp.....,.pp.....,kkkkkkkk,kmmmmmmk,kmrrrrmk,kmrrrrmk,kmmmmmmk,kk....kk k=2E323A m=5A6270 r=1A1A1E p=6A6E78
		waterWheel ..wwww..,.wWwwWw.,wWw..wWw,ww.pp.ww,ww.pp.ww,wWw..wWw,.wWwwWw.,..wwww.. w=8F6732 W=B98A4E p=5A5E68
		emberDynamo kkkkkkkk,kOOOOOOk,kOeEEeOk,kOEyyEOk,kOEyyEOk,kOeEEeOk,kOOOOOOk,kkkkkkkk k=16121A O=2A1E2E e=C04010 E=FF7020 y=FFD060
		battery ..cccc..,.kkkkkk.,.kmmmmk.,.kmmmmk.,.kmmmmk.,.kmmmmk.,.kmmmmk.,.kkkkkk. k=2E323A m=4A515E c=D2793A
		accumulator kkkkkkkk,kgGggGgk,kGtttTGk,kgtTttgk,kgtttTgk,kGTtttGk,kgGggGgk,kkkkkkkk k=2E323A g=5A8A90 G=8AC8C8 t=30A0A0 T=8AF0E8
		powerSwitch ........,.kkkkkk.,.kmmmmk.,.km..mk.,.km..mk.,.kmmmmk.,.kkkkkk.,........ k=2E323A m=6A7280
		breaker kkkkkkkk,kyykyykk,kmmmmmmk,kmk..kmk,kmk..kmk,kmkkkkmk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 y=E8C020
		powerMeter .kkkkkk.,kwwwwwwk,kwnwwwwk,kwwnwwwk,kwwwnwwk,kkkkkkkk,kmmmmmmk,.kkkkkk. k=2E323A w=E8E4D8 n=3A3A40 m=5A6270
		lever ........,........,........,........,........,..kkkk..,.kmmmmk.,kkkkkkkk k=2E323A m=6A7280
		pushButton ........,........,..kkkk..,.kmmmmk.,.kmBBmk.,.kmBBmk.,.kmmmmk.,..kkkk.. k=2E323A m=6A7280 B=30B0C0
		pressurePlate ........,........,........,........,........,........,.mMMMMm.,kkkkkkkk k=2E323A m=6A7280 M=9AA4B4
		pulseTimer kkkkkkkk,kmwwwwmk,kwwnwwwk,kwwnnnwk,kwwwwwwk,kmwwwwmk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 w=E8E4D8 n=3A3A40
		repeater ........,........,kkkkkkkk,kmmmmmmk,kmmmmmmk,kmmmmmmk,kkkkkkkk,........ k=2E323A m=5A6270
		inverter ........,........,kkkkkkkk,kiiiiiik,kiiiiiik,kiiiiiik,kkkkkkkk,........ k=2E323A i=6A4A7A
		logicGate ........,kkkkkkkk,kqqqqqqk,kqqqqqqk,kqqqqqqk,kqqqqqqk,kkkkkkkk,........ k=2E323A q=3A6A6A
		motionSensor ..gggg..,.gGggGg.,.gggggg.,kkkkkkkk,kmmmmmmk,kmmmmmmk,kkkkkkkk,........ k=2E323A m=5A6270 g=C86A3A G=F0A070
		daySensor kkkkkkkk,kssSSssk,ksSyySsk,ksSyySsk,kssSSssk,kmmmmmmk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 s=3A5A8A S=E8C040 y=FFF0A0
		weatherSensor .c...c..,.ccpcc..,...p....,kkkkkkkk,kmdmmmmk,kdddmmmk,kmdmmmmk,kkkkkkkk k=2E323A m=5A6270 c=C8CCD4 p=8A8E98 d=3B7BE0
		itemSensor kkkkkkkk,kmmmmmmk,kmbbbbmk,kmbBBbmk,kmbbbbmk,kmmmmmmk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 b=A97B45 B=E8C060
		proximitySensor ..tttt..,.t....t.,t..tt..t,..t..t..,...tt...,kkkkkkkk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 t=30E0D0
		gateClosed kkkkkkkk,kM.M.M.k,kM.M.M.k,kkkkkkkk,kM.M.M.k,kM.M.M.k,kM.M.M.k,kkkkkkkk k=4A515E M=9AA4B4
		gateOpen kk....kk,k......k,k......k,k......k,k......k,k......k,k......k,kk....kk k=4A515E
		lampOff kmmmmmmk,mgggggGm,mggGgggm,mgggggGm,mgGggggm,mgggggGm,mggggggm,kmmmmmmk k=2E323A m=6A7280 g=7A8A90 G=9AAAB0
		lampOn kmmmmmmk,myyyyyWm,myyWyyym,myyyyyWm,myWyyyym,myyyyyWm,myyyyyym,kmmmmmmk k=2E323A m=8A94A4 y=FFF0B0 W=FFFFFF
		arcTrap cCcCcCcC,kkkkkkkk,kmmmmmmk,kmcmcmck,kmmmmmmk,kmcmcmck,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 c=D2793A C=8AF0E8
		autoDrill kkkkkkkk,kmmmmmmk,kmyyyymk,kmykkymk,kmykkymk,kmyyyymk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 y=E8C020
		conveyor bBbbBbbB,bbbbbbbb,kkkkkkkk,kmRmmRmk,kRMRRMRk,kmRmmRmk,kkkkkkkk,k......k b=2A2A2E B=4A4A52 k=2E323A m=5A6270 R=9AA0AC M=6A7280
		collector MMMMMMMM,.mMMMMm.,..mMMm..,kkkkkkkk,kmmmmmmk,kmbbbbmk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 M=9AA4B4 b=1A1A1E
		autoCrafter kkkkkkkk,kmmmmmmk,kmGmmGmk,kmmGGmmk,kmmGGmmk,kmGmmGmk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 G=C8B060
		sumpPump ...pp...,...pp...,kkkkkkkk,kmddddmk,kmdDDdmk,kmddddmk,kmmmmmmk,kkkkkkkk k=2E323A m=5A6270 p=6A6E78 d=2A5AB0 D=5A9AE8
		signalLight ........,..gggg..,.gGggGg.,.gggggg.,..gggg..,..kkkk..,.kmmmmk.,kkkkkkkk k=2E323A m=5A6270 g=2A5A5A G=4A8A8A
		"""
}

/// Art pixels along a block's side. The hand-drawn blocks of ArtSheet are this size; the older 8 x 8
/// ones (below) are drawn with every pixel doubled until they are redrawn.
let tileArtPx: Int = 16

/// A block's picture, tileArtPx a side
func tileBuf(_ t: Tile) -> PixelBuf {
	if t.isMod {
		let i: Int = Int(t.rawValue - Tile.modBase)
		return fitTileArt(ModRuntime.shared.slotArt[i] ?? missingTileBuf())
	}
	if let b = TileSheet.bufs[t.rawValue] { return b }
	return fitTileArt(gradeBuf(olderTileBuf(t)))
}

/// Any block picture at tileArtPx a side: an 8 x 8 one has its pixels doubled, other sizes are
/// stretched to fit (nearest pixel)
func fitTileArt(_ b: PixelBuf) -> PixelBuf {
	let n: Int = tileArtPx
	if b.w == n && b.h == n { return b }
	var o = PixelBuf(w: n, h: n)
	if b.w <= 0 || b.h <= 0 { return o }
	for y in 0..<n {
		let sy: Int = min(b.h - 1, y * b.h / n)
		for x in 0..<n {
			o.px[y * n + x] = b.px[sy * b.w + min(b.w - 1, x * b.w / n)]
		}
	}
	return o
}

/// The older 8 x 8 art of a block
func olderTileBuf(_ t: Tile) -> PixelBuf {
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
	// calmer textures: pixels group into 2x2 clumps and the accent colours sit closer to the base,
	// so terrain reads as surfaces rather than static
	let k1: UInt32 = mixRGB(c[0], c[1], 0.6)
	let k2: UInt32 = mixRGB(c[0], c[2], 0.6)
	let k3: UInt32 = mixRGB(c[0], c[3], 0.5)
	func clump(_ x: Int, _ y: Int) -> Int {
		return Int(hashU(x / 2 + (y / 2) * 5, Int(t.rawValue), 9127) % 100)
	}
	func calm(_ x: Int, _ y: Int, _ r: Int) -> UInt32 {
		let cl: Int = clump(x, y)
		if r < 6 { return k3 }
		if cl < 28 { return k1 }
		if cl > 80 { return k2 }
		return c[0]
	}
	let specks: [(Int, Int)] = [(2, 2), (3, 2), (3, 3), (5, 5), (6, 5), (5, 6), (1, 6), (6, 1)]
	for y in 0..<8 {
		for x in 0..<8 {
			let r: Int = rng.int(100)
			var col: UInt32 = c[0]
			switch d.style {
			case .grassTop:
				if y < 2 { col = r < 60 ? c[0] : c[1] }
				else if y == 2 { col = r < 50 ? c[1] : c[2] }
				else {
					let cl: Int = clump(x, y)
					col = cl < 60 ? c[2] : (cl < 88 ? mixRGB(c[2], c[3], 0.7) : mixRGB(c[2], c[4], 0.7))
				}
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
				col = calm(x, y, r + 10)
				if specks.contains(where: { $0.0 == x && $0.1 == y }) { col = r < 60 ? c[5] : c[6] }
			case .snow:
				col = calm(x, y, 50)
			case .ice:
				col = r < 50 ? c[0] : (r < 75 ? c[1] : c[2])
				if (x + y) % 6 == 0 { col = c[3] }
				b.px[y * 8 + x] = 0xE0000000 | col
				continue
			case .mud:
				col = calm(x, y, r)
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
				col = calm(x, y, r)
			default:
				col = calm(x, y, r)
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
	/// armour points of one piece (times the slot's share: a full set is three times this). Each point
	/// takes 4% off a blow, at most 80%: a full leather set 19%, iron 41%, diamond 55%, voidium 80%
	var defense: Double {
		let t: [Double] = [0, 1.6, 2.0, 2.6, 3.4, 3.8, 4.6, 5.4, 6.2, 7.0]
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
	/// rare: crystal grottos, relic chests in ruins, and the Hollow Warden's heart
	case crystalShard, relicFragment, umbralHeart
	/// appended: tin (alloyed with copper into bronze), saltpeter for powder and fire, silver, amethyst
	case tinOre, bronzeBar, saltpeter, silverOre, silverBar, amethyst
	/// appended: alchemy (vials and water, herbs, creature parts, storm essence) and rare relics of golems,
	/// the Crystal Sentinel and mutated creatures
	case vial, waterVial, sunleaf, glowcap, slimeGel, venomSac, frostCrystal, emberAsh, wraithDust, stormEssence, golemCore, sentinelLens, mutantGland

	var name: String {
		switch self {
		case .vial: return "Empty Vial"
		case .waterVial: return "Water Vial"
		case .sunleaf: return "Sunleaf"
		case .glowcap: return "Glowcap"
		case .slimeGel: return "Slime Gel"
		case .venomSac: return "Venom Sac"
		case .frostCrystal: return "Frost Crystal"
		case .emberAsh: return "Ember Ash"
		case .wraithDust: return "Wraith Dust"
		case .stormEssence: return "Storm Essence"
		case .golemCore: return "Golem Core"
		case .sentinelLens: return "Sentinel Lens"
		case .mutantGland: return "Mutant Gland"

		case .tinOre: return "Tin Ore"
		case .bronzeBar: return "Bronze Bar"
		case .saltpeter: return "Saltpeter"
		case .silverOre: return "Silver Ore"
		case .silverBar: return "Silver Bar"
		case .amethyst: return "Amethyst Shard"
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
		case .crystalShard: return "Crystal Shard"
		case .relicFragment: return "Relic Fragment"
		case .umbralHeart: return "Umbral Heart"
		}
	}

	/// what the material is good for, for its tooltip
	var use: String {
		switch self {
		case .coal: return "Fuel for smelting; torches; gunpowder"
		case .copperOre, .ironOre, .goldOre, .mythrilOre, .emberOre, .voidOre, .silverOre: return "Smelt it into bars in a furnace"
		case .tinOre: return "Smelt with copper ore into bronze"
		case .bronzeBar: return "Crossbows, bolts, maces, lanterns, rails"
		case .saltpeter: return "Strong gunpowder and fire flasks"
		case .silverBar: return "Silver charm, storm rod"
		case .amethyst: return "Amethyst blocks, headlamps, the storm rod"
		case .copperBar, .ironBar, .goldBar, .mythrilBar, .emberBar, .voidBar: return "Tools, weapons and armour"
		case .crystalShard, .relicFragment, .umbralHeart: return "Rare crafting material"
		case .vial: return "Tap water with it to fill it"
		case .waterVial: return "The base of every potion and compound"
		case .sunleaf: return "Herb: from tall grass and flowers"
		case .glowcap: return "Cave mushroom: from mushrooms and bats"
		case .slimeGel: return "From slimes"
		case .venomSac: return "From scorpions and crawlers"
		case .frostCrystal: return "From ice, snow and polar bears"
		case .emberAsh: return "From Umbral creatures"
		case .wraithDust: return "From wraiths"
		case .stormEssence: return "Left where lightning strikes (a rod catches more)"
		case .golemCore: return "From golems: cores, Quarry, Thrift"
		case .sentinelLens: return "From the Crystal Sentinel: the rarest work"
		case .mutantGland: return "From mutated creatures: cheaper mutagen"
		default: return "Crafting material"
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

/// Weapons that are loaded and then fired with a tap: firearms, bolt throwers and the storm rod. Each
/// keeps its loaded shots in the stack's `extra`.
enum GunType: Int, Codable, CaseIterable {
	case pistol, rifle
	/// appended (saved numbers stay valid): a bolt thrower and its heavy upgrade, a scattergun, a rare
	/// repeating crossbow, and a rod whose charge of lightning refills on its own
	case crossbow, arbalest, blunderbuss, repeater, stormRod
	var name: String {
		switch self {
		case .pistol: return "Flintlock Pistol"
		case .rifle: return "Long Rifle"
		case .crossbow: return "Crossbow"
		case .arbalest: return "Heavy Crossbow"
		case .blunderbuss: return "Blunderbuss"
		case .repeater: return "Prospector's Repeater"
		case .stormRod: return "Storm Rod"
		}
	}
	/// damage of one shot (one pellet for the blunderbuss, the first strike for the storm rod)
	var damage: Double {
		switch self {
		case .pistol: return 9
		case .rifle: return 24
		case .crossbow: return 15
		case .arbalest: return 26
		case .blunderbuss: return 4.5
		case .repeater: return 11
		case .stormRod: return 12
		}
	}
	var cooldown: Double {
		switch self {
		case .pistol: return 0.32
		case .rifle: return 0.85
		case .crossbow, .arbalest, .blunderbuss: return 0.2
		case .repeater: return 0.2
		case .stormRod: return 0.5
		}
	}
	var magazine: Int {
		switch self {
		case .pistol: return 6
		case .rifle: return 4
		case .crossbow, .arbalest, .blunderbuss: return 1
		case .repeater: return 5
		case .stormRod: return 5
		}
	}
	var reloadTime: Double {
		switch self {
		case .pistol: return 1.3
		case .rifle: return 2.2
		case .crossbow: return 0.85
		case .arbalest: return 1.35
		case .blunderbuss: return 1.7
		case .repeater: return 2.0
		case .stormRod: return 2.5
		}
	}
	var speed: Double {
		switch self {
		case .pistol: return 34
		case .rifle: return 48
		case .crossbow: return 42
		case .arbalest: return 50
		case .blunderbuss: return 30
		case .repeater: return 40
		case .stormRod: return 0
		}
	}
	/// what a reload takes from the bag (the storm rod recharges by itself instead)
	var ammo: AmmoType? {
		switch self {
		case .pistol, .rifle, .blunderbuss: return .bullet
		case .crossbow, .arbalest, .repeater: return .bolt
		case .stormRod: return nil
		}
	}
	/// creatures each shot may pass through before it stops
	var pierce: Int {
		switch self {
		case .rifle, .crossbow: return 1
		case .arbalest: return 2
		default: return 0
		}
	}
	/// downward pull on the shot (bolts drop a little; bullets fly straight)
	var gravity: Double {
		switch self {
		case .crossbow, .repeater: return 6
		case .arbalest: return 4
		default: return 0
		}
	}
	/// how long a shot flies before it is spent (sets the range)
	var shotLife: Double {
		switch self {
		case .blunderbuss: return 0.3
		case .crossbow, .arbalest, .repeater: return 2.0
		default: return 1.6
		}
	}
	var knock: Double {
		switch self {
		case .arbalest: return 8
		case .blunderbuss: return 3.2
		case .crossbow, .repeater: return 5
		default: return 4
		}
	}
	/// heavy weapons need a fresh press for every shot; the rest keep firing while held
	var needsPress: Bool { return self == .rifle || self == .arbalest || self == .blunderbuss }
	var isFirearm: Bool { return self == .pistol || self == .rifle || self == .blunderbuss }
	var isBoltThrower: Bool { return self == .crossbow || self == .arbalest || self == .repeater }
}

enum AmmoType: Int, Codable, CaseIterable {
	case arrow, bullet
	/// crossbow bolts (appended)
	case bolt
	var name: String {
		switch self {
		case .arrow: return "Arrow"
		case .bullet: return "Bullet"
		case .bolt: return "Crossbow Bolt"
		}
	}
}

/// The club family: crude blunt weapons whose blows leave foes dazed for a moment
enum ClubKind: Int, Codable, CaseIterable {
	case wooden, studded, mace
	var name: String {
		switch self {
		case .wooden: return "Wooden Club"
		case .studded: return "Studded Club"
		case .mace: return "Bronze Mace"
		}
	}
	var damage: Double {
		switch self {
		case .wooden: return 5
		case .studded: return 7.5
		case .mace: return 11
		}
	}
	var daze: Double {
		switch self {
		case .wooden: return 0.45
		case .studded: return 0.55
		case .mace: return 0.7
		}
	}
}

/// One-of-a-kind weapons. They are never crafted: they turn up, rarely, in the deeper and better
/// hidden chests of old mines, grottos and lairs.
enum Relic: Int, Codable, CaseIterable {
	case moonDagger, emberCleaver, quakeMaul
	var name: String {
		switch self {
		case .moonDagger: return "Moonsilver Dagger"
		case .emberCleaver: return "Ember Cleaver"
		case .quakeMaul: return "Quake Maul"
		}
	}
}

enum PartType: Int, Codable, CaseIterable {
	case frame, wheel, engine, steering, seat, fuelTank, hull, propeller, paddle, drill, diamondDrill
	/// appended (saved part numbers stay valid): a heavy wheel that pulls harder, a lamp that lights the
	/// way ahead while driving, a crate that carries 27 stacks, and a drill that bores through anything
	case offroadWheel, headlight, cargo, voidDrill
	/// appended (vehicles of every kind): any block built onto a vehicle (its tile is kept in
	/// Vehicle.blocks), a cockpit (seat and controls in one), wings and a tail elevator, an air
	/// propeller and a jet engine, a main rotor and a tail rotor, a balloon envelope and the burner that
	/// heats it, tank tracks and armour, a cannon and a machine gun, and an autopilot
	case block, cockpit, wing, elevator, airProp, jet, rotor, tailRotor, envelope, burner, track, armor, cannon, autoGun, autopilot
	/// appended (flight and water): a wing with a flap that drops for slow flight, an air brake, a fixed
	/// tailplane that steadies the nose, and a ballast tank that fills with water to dive
	case flap, airBrake, stabilizer, ballast
	/// appended (big vehicles and rails): a flanged wheel that rolls almost freely on rails, a coupler that
	/// links two vehicles into a train, and a wheel three cells across
	case railWheel, coupler, bigWheel
	/// appended (joints and mechs): a free hinge, a servo that turns what is built beyond it, and a piston
	/// that pushes it out and pulls it back
	case hinge, servo, piston
	var name: String {
		switch self {
		case .hinge: return "Hinge"
		case .servo: return "Servo"
		case .piston: return "Piston"
		case .railWheel: return "Rail Wheel"
		case .coupler: return "Coupler"
		case .bigWheel: return "Big Wheel"
		case .flap: return "Flapped Wing"
		case .airBrake: return "Air Brake"
		case .stabilizer: return "Tailplane"
		case .ballast: return "Ballast Tank"
		case .block: return "Block"
		case .cockpit: return "Cockpit"
		case .wing: return "Wing"
		case .elevator: return "Tail Elevator"
		case .airProp: return "Air Propeller"
		case .jet: return "Jet Engine"
		case .rotor: return "Main Rotor"
		case .tailRotor: return "Tail Rotor"
		case .envelope: return "Balloon Envelope"
		case .burner: return "Hot-Air Burner"
		case .track: return "Tank Track"
		case .armor: return "Armour Plate"
		case .cannon: return "Cannon"
		case .autoGun: return "Machine Gun"
		case .autopilot: return "Autopilot"
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
		case .offroadWheel: return "Offroad Wheel"
		case .headlight: return "Headlight"
		case .cargo: return "Cargo Crate"
		case .voidDrill: return "Void Drill"
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
		case .offroadWheel: return 1.1
		case .headlight: return 0.3
		case .cargo: return 1.0
		case .voidDrill: return 2.0
		case .block: return 1.0
		case .cockpit: return 0.9
		case .wing: return 0.4
		case .elevator: return 0.25
		case .airProp: return 0.5
		case .jet: return 2.2
		case .rotor: return 1.0
		case .tailRotor: return 0.3
		case .envelope: return 0.12
		case .burner: return 1.0
		case .track: return 1.5
		case .armor: return 3.0
		case .cannon: return 2.4
		case .autoGun: return 1.0
		case .autopilot: return 0.4
		case .flap: return 0.5
		case .airBrake: return 0.4
		case .stabilizer: return 0.25
		case .ballast: return 1.4
		case .railWheel: return 0.7
		case .coupler: return 0.4
		case .bigWheel: return 3.2
		case .hinge: return 0.6
		case .servo: return 1.2
		case .piston: return 1.4
		}
	}

	/// what the part does, for its tooltip
	var role: String {
		switch self {
		case .wheel: return "Goes under the body. Two or more, plus an engine, drive on land."
		case .offroadWheel: return "A heavier wheel that pulls harder up slopes and over rough ground."
		case .headlight: return "Lights the way ahead while someone is driving."
		case .cargo: return "Tap it to store up to 27 stacks; they travel with the vehicle."
		case .drill, .diamondDrill, .voidDrill: return "Bores through blocks in front of it while the engine runs."
		case .cockpit: return "A seat and the controls in one. Tap it to drive or fly."
		case .wing: return "Lifts as air flows over it: the faster, the more. Tilted too far, it stalls."
		case .elevator: return "A tail surface the pilot tilts (stick up or down) to raise or lower the nose."
		case .airProp: return "Pushes through the air, powered by the engines. Goes on an end."
		case .jet: return "Engine and thruster in one: strong and fast, but thirsty. Its open end is the exhaust."
		case .rotor: return "Lifts straight up, powered by the engines. Goes on top, open above."
		case .tailRotor: return "Keeps a single main rotor from spinning the helicopter round. Goes on an end."
		case .envelope: return "Fills with hot air from a burner and lifts. Light, but bursts easily."
		case .burner: return "Heats up to 12 balloon envelopes: stick up to climb, down to sink."
		case .track: return "Grips anything and climbs steps, but is heavy and slow. Goes under the body."
		case .armor: return "Very heavy and very tough: soaks up shots and blasts."
		case .cannon: return "Fires explosive shells where you aim. Uses gunpowder."
		case .autoGun: return "Fires a stream of bullets where you aim. Uses bullets."
		case .autopilot: return "Holds speed and height, or drives a route you mark (AUTO button)."
		case .flap: return "A wing whose flap drops by itself when flying slowly: more lift for take-off and landing, and more drag."
		case .airBrake: return "Opens when you push the stick against your motion (or roll to a stop on the ground): a lot of drag."
		case .stabilizer: return "A fixed tail surface: keeps the nose steady by itself, with no controls."
		case .ballast: return "Fills with water to sink and blows it out to rise (stick down and up, in water). Makes a submarine."
		case .railWheel: return "Rolls almost freely along rails (and drags on anything else). Ore carts and trains run on them."
		case .coupler: return "Links up with another vehicle's coupler when they touch: a train. Tap it to uncouple."
		case .bigWheel: return "A wheel three cells across: climbs over steps a small wheel stops at. Takes a free space three by three."
		case .hinge: return "What is built on beyond it swings freely about it: a section of its own (a flap, a door, a loose arm)."
		case .servo: return "Turns what is built beyond it, as the stick, a button or a walk tells it. Tap it to set it up."
		case .piston: return "Pushes what is built beyond it out and pulls it back (up to four blocks). Tap it to set it up."
		case .block: return "A block built onto a vehicle."
		default: return "Vehicle part"
		}
	}
}

/// Parts that hang under the body and roll on the ground (tracks too: they ride on wheels)
func isWheelPart(_ p: PartType) -> Bool { return p == .wheel || p == .offroadWheel || p == .track || p == .railWheel || p == .bigWheel }

/// How many cells across a part is (most are one; a big wheel three)
func partSpan(_ p: PartType) -> Int { return p == .bigWheel ? 3 : 1 }

/// Equipment worn in the two gear slots
enum Gear: Int, Codable, CaseIterable {
	case headlamp, swiftBoots, divingMask, emberCharm, wardenSigil
	/// appended: a silver ward against the restless dead
	case silverCharm
	/// appended: warm clothes against the cold, and boots that grip snow and ice
	case winterCoat, snowBoots
	var name: String {
		switch self {
		case .winterCoat: return "Winter Coat"
		case .snowBoots: return "Snow Boots"
		case .headlamp: return "Headlamp"
		case .swiftBoots: return "Swift Boots"
		case .divingMask: return "Diving Mask"
		case .emberCharm: return "Ember Charm"
		case .wardenSigil: return "Warden's Sigil"
		case .silverCharm: return "Silver Charm"
		}
	}
	var effect: String {
		switch self {
		case .headlamp: return "Lights the way around you"
		case .swiftBoots: return "Run 18% faster"
		case .divingMask: return "Hold your breath three times as long"
		case .emberCharm: return "Lava and fire hurt far less"
		case .wardenSigil: return "Hit 20% harder, take 15% less damage"
		case .silverCharm: return "The undead hit you 25% softer; you hit them 25% harder"
		case .winterCoat: return "Keeps out most of the cold of a blizzard"
		case .snowBoots: return "No slipping on snow and ice, no sinking in deep snow"
		}
	}
}

enum Gadget: Int, Codable, CaseIterable {
	case shears, wrench, treasureMap, portalKey, carKit, boatKit, motorboatKit, bomb
	/// appended: a thrown flask that bursts into a patch of fire
	case fireFlask
	/// appended: a pocket barometer, and a flask of rainwater from a rain barrel
	case barometer, waterFlask
	/// Sparkworks (appended): spools of power cable and pulse wire (two colours), snips that take wire
	/// back up, and the probe that reads and sets up devices and networks
	case powerCable, pulseWire, pulseWireB, wireSnips, probe
	/// vehicles (appended): ready-made aircraft, an airship, a tank and a truck, and the assembler that
	/// turns a structure built from blocks into a vehicle (and back)
	case planeKit, heliKit, airshipKit, tankKit, truckKit, assembler
	/// appended (flowing liquids): an iron bucket that carries a block of water, lava or a mod's liquid
	/// (what it holds is in the stack's `extra`: 0 empty, else the liquid's tile number + 1)
	case bucket

	/// a wiring tool: taps lay or cut wire instead of using what is under them
	var wiring: Bool { return self == .powerCable || self == .pulseWire || self == .pulseWireB || self == .wireSnips }
	/// the wire layer a spool lays (0 power, 1 amber pulse, 2 teal pulse)
	var wireLayer: Int { return self == .powerCable ? 0 : (self == .pulseWire ? 1 : 2) }

	var name: String {
		switch self {
		case .powerCable: return "Power Cable"
		case .pulseWire: return "Pulse Wire (amber)"
		case .pulseWireB: return "Pulse Wire (teal)"
		case .wireSnips: return "Wire Snips"
		case .probe: return "Spark Probe"
		case .barometer: return "Barometer"
		case .waterFlask: return "Water Flask"
		case .fireFlask: return "Fire Flask"
		case .shears: return "Shears"
		case .wrench: return "Wrench"
		case .treasureMap: return "Treasure Map"
		case .portalKey: return "Portal Key"
		case .carKit: return "Car Kit"
		case .boatKit: return "Rowboat Kit"
		case .motorboatKit: return "Motorboat Kit"
		case .bomb: return "Bomb"
		case .planeKit: return "Plane Kit"
		case .heliKit: return "Helicopter Kit"
		case .airshipKit: return "Airship Kit"
		case .tankKit: return "Tank Kit"
		case .truckKit: return "Truck Kit"
		case .assembler: return "Vehicle Assembler"
		case .bucket: return "Bucket"
		}
	}
}

/// The shape of a melee swing (drives the hit test, the animation and the trail)
enum SwingStyle: Int {
	case slash, thrust, smash, stab, bash
}

/// How a melee weapon strikes. One table drives the hit test, the timing, the animation and the
/// effects, so a weapon reaches exactly as far and as wide whether the player taps a foe, holds the
/// attack stick or swings at empty air.
struct MeleeProfile {
	var damage: Double
	var cooldown: Double
	/// from the shoulder to the near edge of a target
	var reach: Double
	/// half the angle swept either side of the aim (radians)
	var halfArc: Double
	var style: SwingStyle = .slash
	/// thrusts hit along a straight band this wide instead of an arc
	var band: Double = 0.55
	var maxHits: Int = 99
	var knock: Double = 6
	/// a crushing blow: breaks raised guards and cracks stone hides
	var heavy: Bool = false
	/// seconds a struck foe is left dazed (clubs)
	var daze: Double = 0
	/// the blow lands this long after the swing starts (heavy weapons)
	var windup: Double = 0
	var swingTime: Double = 0.25
	/// run speed while the swing lasts (heavy weapons commit you to the blow)
	var moveScale: Double = 1.0
	var critChance: Double = 0.1
	/// seconds of fire a hit sets on the target
	var burn: Double = 0
	var undeadMult: Double = 1
	/// every third blow in a quick run lands twice as hard
	var combo: Bool = false
	/// multiplier for a blow into a foe's back
	var backstab: Double = 1
	/// the blow sends a shockwave along the ground
	var shockwave: Bool = false
	var trail: UInt32 = 0xFFFFFF
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
	/// long reach, a quick thrust that runs through two foes in a line
	case spear(Tier)
	/// slow and heavy: big knockback, smashes guards and stone hides
	case hammer(Tier)
	case gear(Gear)
	/// appended: quick stabs at close range, every third in a run hits twice as hard, cuts deep from behind
	case knife(Tier)
	/// cheap blunt weapons that daze
	case club(ClubKind)
	/// slings stones (any rock in the bag) in a lob that knocks foes back
	case sling
	/// one of a kind, found and never made
	case relic(Relic)
	/// appended: an item from a player's mod ("mod:id"); see ModRuntime
	case custom(String)
	/// appended: potions, infusion compounds, and the exosuit's parts, plates, cores and modules
	case potion(Potion)
	case compound(Infusion)
	case exoPart(ExoPart, ExoMat)
	case exoPlate(ExoMat)
	case exoCore(ExoCore)
	case exoModule(ExoModule)

	/// Order used by inventory sorting: gear first, then building blocks, materials and the rest
	var sortGroup: Int {
		switch self {
		case .sword, .spear, .hammer, .knife, .club, .relic: return 0
		case .gear: return 4
		case .bow, .gun, .sling: return 1
		case .ammo: return 2
		case .tool: return 3
		case .armor: return 4
		case .food: return 5
		case .gadget: return 6
		case .part: return 7
		case .block: return 8
		case .wall: return 9
		case .mat: return 10
		case .custom(let k): return ModRuntime.shared.item(k)?.sortGroup ?? 10
		case .potion: return 5
		case .compound: return 6
		case .exoPart, .exoPlate, .exoCore, .exoModule: return 4
		}
	}

	/// The bag's filter groups (see ItemBrowser.groups): 0 blocks, 1 tools, 2 weapons and ammunition,
	/// 3 armour and suit parts, 4 materials, 5 food and potions, 6 everything else
	var bagGroup: Int {
		switch sortGroup {
		case 0, 1, 2: return 2
		case 3: return 1
		case 4: return 3
		case 5: return 5
		case 8, 9: return 0
		case 10: return 4
		default: return 6
		}
	}

	/// Short description lines for tooltips: what the weapon is for, then its numbers
	var infoLines: [String] {
		switch self {
		case .sword, .spear, .hammer, .knife, .club, .relic:
			let p: MeleeProfile = melee
			var lines: [String] = [weaponBlurb]
			lines.append(String(format: "Damage %.1f · every %.2f s", p.damage, p.cooldown))
			let reachS: String = String(format: "Reach %.1f", p.reach)
			let hits: String = p.maxHits >= 99 ? "hits all in the arc" : (p.maxHits == 1 ? "one foe" : "up to \(p.maxHits) foes")
			lines.append(reachS + " · " + hits)
			return lines
		case .gear(let g): return ["Gear: wear it in a gear slot", g.effect]
		case .tool(let k, let t): return [k.name + " (tool)", String(format: "Mining speed x%.1f", t.mineSpeed), "Tier \(t.rawValue)"]
		case .armor(let s, let t): return [s.name + " armour", String(format: "Defense +%.1f", t.defense * s.weight)]
		case .food(let f): return ["Food", String(format: "Restores %.0f hunger", f.hunger), f.heal > 0 ? String(format: "Heals %.0f", f.heal) : "Eat to recover"]
		case .bow: return ["Bow: hold to draw, release to fire", "Damage 5-14 · arcing shots", "Uses arrows"]
		case .sling: return ["Sling: tap to throw a stone in a lob", "Damage 4.5 · every 0.55 s · big knockback", "Uses any stone or slate you carry"]
		case .gun(let g):
			var lines: [String] = [weaponBlurb]
			if g == .blunderbuss {
				lines.append(String(format: "7 pellets x %.1f · reload %.1f s", g.damage, g.reloadTime))
			} else if g == .stormRod {
				lines.append(String(format: "Damage %.0f, then leaps to 3 more · %d charges", g.damage, g.magazine))
			} else {
				lines.append(String(format: "Damage %.0f · %d loaded · reload %.1f s", g.damage, g.magazine, g.reloadTime))
			}
			if let a = g.ammo { lines.append("Uses " + a.name.lowercased() + "s") } else { lines.append("Recharges by itself") }
			return lines
		case .ammo: return ["Ammunition"]
		case .part(let p): return [p.role, String(format: "Mass %.1f", p.mass)]
		case .gadget(let g):
			if g == .fireFlask { return ["Throw it: bursts into fire that burns", "everything standing in it"] }
			if g == .bomb { return ["Throw it: explodes after a moment", "Breaks blocks"] }
			if g == .barometer { return ["Hold it to read the air pressure", "Falling fast: a storm is coming"] }
			if g == .waterFlask { return ["Rainwater: pour it on a young crop", "to help it grow, or on a fire"] }
			if g == .powerCable { return ["Carries power from generators", "to batteries and machines: drag to lay"] }
			if g == .pulseWire || g == .pulseWireB { return ["Carries on/off pulses from switches,", "sensors and logic to machines: drag to lay"] }
			if g == .wireSnips { return ["Drag over wire to take it back up"] }
			if g == .probe { return ["Tap a device to set it up, or a wire", "to see its whole network and its power"] }
			if g == .assembler { return ["Tap a structure you built: it becomes a vehicle", "Tap a parked vehicle: its blocks go back"] }
			if isKit(g) { return ["A ready-made vehicle: tap open ground", "to place it (boats and ships on water)"] }
			return ["Gadget: use it from the hotbar"]
		case .block(.sapling): return ["Plant it on grass, dirt or snow", "It grows into a tree that suits the land"]
		case .block(let t) where furnitureBlurb(t) != nil: return [furnitureBlurb(t) ?? "", weightLine(t)]
		case .block(let t): return [t.solid ? "Building block" : "Placeable", t.light > 0 ? "Gives light" : (t.hardness >= 99 ? "Unbreakable" : String(format: "Hardness %.1f", t.hardness)), weightLine(t)]
		case .wall: return ["Background wall"]
		case .mat(let m): return [m.use]
		case .custom(let k): return ModRuntime.shared.item(k)?.infoLines ?? ["From a mod that is not installed", "Kept safe until the mod is back"]
		case .potion(let p): return [p.useLine, p.blurb, p.rarity.name]
		case .compound(let i):
			let goes: [String] = i.classes.map { $0.name }
			return ["Infusion compound: work it in at an Infusion Crucible", i.blurb, joinText("Goes on ", goes.joined(separator: " or "), " · ", i.rarity.name)]
		case .exoPart(_, let m):
			return [joinText("An old suit part (", m.name.lowercased(), ")"), "Suits are built piece by piece now", "Melt it down at an Assembly Station for its metal"]
		case .exoPlate(let m): return [joinText("An old suit plate (", m.name.lowercased(), ")"), "Suits are built piece by piece now", "Melt it down at an Assembly Station for its metal"]
		case .exoCore(let c): return ["Suit power core: place it on a suit at an Assembly Station", String(format: "Holds %.0f · gives %.0f a second", c.capacity, c.output), String(format: "Refills %.1f a second by itself", c.recharge)]
		case .exoModule(let m):
			return [m.blurb, "Place it on a suit at an Assembly Station, wherever it should go", String(format: "Weight %.0f · %@", m.weight, m.rarity.name)]
		}
	}

	/// What a weapon is for, in a line
	var weaponBlurb: String {
		switch self {
		case .sword: return "Sword: quick, even sweeps that hit every foe in front"
		case .spear: return "Spear: long reach, a thrust that runs through two foes"
		case .hammer: return "Hammer: slow and heavy, smashes guards and stone"
		case .knife: return "Knife: fast stabs, every 3rd in a run hits double, deadly from behind"
		case .club: return "Club: cheap blunt blows that leave foes dazed"
		case .relic(let r):
			switch r {
			case .moonDagger: return "Relic knife: the restless dead fall to it twice as fast"
			case .emberCleaver: return "Relic blade: a wide sweep that sets foes ablaze"
			case .quakeMaul: return "Relic maul: its blow sends a quake along the ground"
			}
		case .gun(let g):
			switch g {
			case .pistol: return "Pistol: quick shots, six to a load"
			case .rifle: return "Rifle: a heavy shot that runs through a foe"
			case .crossbow: return "Crossbow: tap to fire a fast, flat bolt"
			case .arbalest: return "Heavy crossbow: a crushing bolt through two foes"
			case .blunderbuss: return "Blunderbuss: a close-range blast of pellets"
			case .repeater: return "Repeater: five bolts in quick succession"
			case .stormRod: return "Storm rod: lightning that leaps between foes"
			}
		default: return name
		}
	}

	var name: String {
		switch self {
		case .block(let t): return t.name
		case .tool(let k, let t): return t.name + " " + k.name
		case .sword(let t): return t.name + " Sword"
		case .spear(let t): return t.name + " Spear"
		case .hammer(let t): return t.name + " War Hammer"
		case .knife(let t): return t.name + " Knife"
		case .club(let k): return k.name
		case .relic(let r): return r.name
		case .sling: return "Sling"
		case .gear(let g): return g.name
		case .armor(let s, let t): return t.armorName + " " + s.name
		case .mat(let m): return m.name
		case .food(let f): return f.name
		case .bow: return "Bow"
		case .gun(let g): return g.name
		case .ammo(let a): return a.name
		case .part(let p): return p.name
		case .gadget(let g): return g.name
		case .wall(let k): return wallName(k)
		case .custom(let k): return ModRuntime.shared.item(k)?.def.name ?? "Missing item"
		case .potion(let p): return p.name
		case .compound(let i): return joinText(i.name, " Compound")
		case .exoPart(let p, let m): return joinText(m.name, " ", p.name)
		case .exoPlate(let m): return joinText(m.name, " Armour Plate")
		case .exoCore(let c): return c.name
		case .exoModule(let m): return m.name
		}
	}

	var maxStack: Int {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.stack ?? 99
		case .potion(let p): return p.maxStack
		case .compound: return 10
		case .block, .mat, .food, .ammo, .wall: return 99
		case .part: return 20
		case .gadget(let g): return g == .bomb ? 30 : (g == .fireFlask ? 20 : (g == .waterFlask ? 10 : ((g == .powerCable || g == .pulseWire || g == .pulseWireB) ? 250 : 1)))
		default: return 1
		}
	}

	var isWeapon: Bool {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.kind.isWeapon ?? false
		case .sword, .spear, .hammer, .knife, .club, .relic, .bow, .gun, .sling: return true
		case .gadget(let g): return g == .bomb || g == .fireFlask
		case .potion(let p): return p.thrown
		default: return false
		}
	}

	/// a hand-held melee weapon (tools are not, though they can still hit)
	var isMeleeWeapon: Bool {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.kind == .melee
		case .sword, .spear, .hammer, .knife, .club, .relic: return true
		default: return false
		}
	}

	var isRanged: Bool {
		switch self {
		case .custom(let k): return ModRuntime.shared.item(k)?.def.kind.isRanged ?? false
		case .bow, .gun, .sling: return true
		case .gadget(let g): return g == .bomb || g == .fireFlask
		case .potion(let p): return p.thrown
		default: return false
		}
	}

	/// How this item strikes when swung, with any change a mod makes to a game weapon or tool
	var melee: MeleeProfile {
		let p: MeleeProfile = baseMelee
		if OverrideRT.shared.items.isEmpty { return p }
		if let o = OverrideRT.shared.items[self] { return o.apply(p) }
		return p
	}

	/// How this item strikes when swung (anything can be swung; weapons are made for it)
	var baseMelee: MeleeProfile {
		switch self {
		case .sword(let t):
			return MeleeProfile(damage: t.damage, cooldown: 0.42, reach: 3.0, halfArc: 1.1, style: .slash, knock: 6, trail: tierShade(t.color, 1.2))
		case .spear(let t):
			return MeleeProfile(damage: t.damage * 0.95, cooldown: 0.48, reach: 3.8, halfArc: 0.25, style: .thrust, band: 0.55, maxHits: 2, knock: 4.5, swingTime: 0.3, trail: tierShade(t.color, 1.2))
		case .hammer(let t):
			return MeleeProfile(damage: t.damage * 1.75, cooldown: 0.8, reach: 2.6, halfArc: 0.95, style: .smash, knock: 11.5, heavy: true, windup: 0.14, swingTime: 0.42, moveScale: 0.55, trail: tierShade(t.color, 1.1))
		case .knife(let t):
			return MeleeProfile(damage: t.damage * 0.48, cooldown: 0.24, reach: 2.0, halfArc: 0.6, style: .stab, maxHits: 1, knock: 3, swingTime: 0.16, critChance: 0.08, combo: true, backstab: 1.5, trail: tierShade(t.color, 1.3))
		case .club(let k):
			return MeleeProfile(damage: k.damage, cooldown: 0.62, reach: 2.5, halfArc: 0.85, style: .bash, maxHits: 2, knock: 8, daze: k.daze, windup: 0.06, swingTime: 0.32, moveScale: 0.8, trail: 0xE8D8B8)
		case .relic(let r):
			switch r {
			case .moonDagger:
				return MeleeProfile(damage: 6.5, cooldown: 0.24, reach: 2.1, halfArc: 0.65, style: .stab, maxHits: 1, knock: 3, swingTime: 0.16, critChance: 0.1, undeadMult: 2.0, combo: true, backstab: 1.6, trail: 0xC8E8FF)
			case .emberCleaver:
				return MeleeProfile(damage: 13, cooldown: 0.5, reach: 3.1, halfArc: 1.3, style: .slash, knock: 7, swingTime: 0.3, burn: 3.0, trail: 0xFF8A30)
			case .quakeMaul:
				return MeleeProfile(damage: 20, cooldown: 0.95, reach: 2.7, halfArc: 1.0, style: .smash, knock: 13, heavy: true, windup: 0.18, swingTime: 0.46, moveScale: 0.5, shockwave: true, trail: 0xE8C878)
			}
		case .tool(let k, let t):
			var d: Double = t.damage * 0.4
			switch k {
			case .axe: d = t.damage * 0.8
			case .pickaxe: d = t.damage * 0.6
			case .shovel: d = t.damage * 0.5
			case .hoe: d = t.damage * 0.4
			}
			return MeleeProfile(damage: d, cooldown: k == .axe ? 0.55 : 0.5, reach: 2.4, halfArc: 0.8, style: .slash, knock: 5, swingTime: 0.25, trail: 0xE0E0E0)
		case .gun, .bow, .sling:
			return MeleeProfile(damage: 2.0, cooldown: 0.4, reach: 1.9, halfArc: 0.7, style: .bash, knock: 4, swingTime: 0.22, trail: 0xD0D0D0)
		case .custom(let k):
			return ModRuntime.shared.item(k)?.melee ?? Item.bareHands
		default:
			return Item.bareHands
		}
	}

	/// what an empty hand does
	static let bareHands: MeleeProfile = MeleeProfile(damage: 1.5, cooldown: 0.4, reach: 1.8, halfArc: 0.75, style: .bash, knock: 4, swingTime: 0.22, trail: 0xE8D8C8)

	/// Melee damage when swung
	var meleeDamage: Double { return melee.damage }
	var meleeCooldown: Double { return melee.cooldown }
	var meleeReach: Double { return melee.reach }

	/// how long the swing animation of a melee attack lasts
	var swingTime: Double { return melee.swingTime }
}

struct Stack: Codable, Hashable {
	var item: Item
	var count: Int
	var extra: Int = 0
	/// the infusions worked into it (by number; nil: none)
	var inf: [Int]? = nil
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
	case .crystalShard:
		b.line(3, 8, 5, 1, 0x8AF0E8); b.line(4, 8, 6, 2, 0x5CC8C8); b.line(5, 8, 7, 4, 0x3A9AA8)
		b.rect(2, 8, 6, 1, 0x3A9AA8); b.set(5, 2, 0xD8FFFA); b.set(4, 4, 0xD8FFFA)
	case .relicFragment:
		b.rect(2, 3, 6, 5, 0xB8A070); b.rect(2, 3, 6, 1, 0xD8C090); b.rect(2, 7, 6, 1, 0x8A7450)
		b.set(4, 5, 0x5ED8C8); b.set(5, 5, 0x5ED8C8); b.set(7, 2, 0xB8A070); b.set(1, 6, 0x8A7450)
	case .umbralHeart:
		b.ellipse(3.6, 4.2, 2.0, 2.0, 0x8A3CD0); b.ellipse(6.4, 4.2, 2.0, 2.0, 0x8A3CD0)
		b.rect(2, 5, 6, 2, 0x8A3CD0); b.rect(3, 7, 4, 1, 0x6A2AA8); b.rect(4, 8, 2, 1, 0x4A1A80)
		b.set(3, 3, 0xE0B8FF); b.set(4, 5, 0xFF60C0)
	case .tinOre:
		b.ellipse(5, 5.5, 3.6, 3.2, 0x8A8A8A)
		b.ellipse(3.6, 4.6, 1.2, 1.1, 0xC8D2DA); b.ellipse(6.4, 6.6, 1.3, 1.1, 0xC8D2DA); b.set(3, 4, 0xF2F6FA); b.set(6, 6, 0xF2F6FA)
	case .bronzeBar: bar(0xC89040)
	case .saltpeter:
		b.ellipse(5, 6.5, 3.8, 2.4, 0xD8D4C8); b.rect(3, 4, 2, 2, 0xF4F2EA); b.rect(5, 3, 2, 3, 0xFFFFFF); b.set(7, 5, 0xEDEAE0); b.set(2, 7, 0xB8B4A8)
	case .silverOre:
		b.ellipse(5, 5.5, 3.6, 3.2, 0x7E8088)
		b.line(2, 7, 7, 3, 0xC4CCD8); b.line(3, 7, 7, 4, 0xDDE4EE); b.set(6, 3, 0xFFFFFF); b.set(3, 7, 0xFFFFFF)
	case .silverBar: bar(0xD8DEE8)
	case .amethyst:
		b.line(3, 8, 4, 2, 0xB07AE8); b.line(4, 8, 5, 3, 0x7A3CBC); b.line(5, 8, 7, 3, 0x9A5ADC); b.line(6, 8, 8, 5, 0x7A3CBC)
		b.rect(2, 8, 7, 1, 0x5A2A8A); b.set(4, 3, 0xEEDCFF); b.set(6, 4, 0xEEDCFF)
	case .vial:
		b.rect(4, 1, 2, 1, 0x8A5A2A); b.rect(4, 2, 2, 2, 0xCFEFFF); b.ellipse(5, 6.5, 2.8, 2.6, 0xCFEFFF); b.set(4, 5, 0xFFFFFF)
	case .waterVial:
		b.rect(4, 1, 2, 1, 0x8A5A2A); b.rect(4, 2, 2, 2, 0xCFEFFF); b.ellipse(5, 6.5, 2.8, 2.6, 0xCFEFFF); b.ellipse(5, 7.2, 2.1, 1.8, 0x3B7BE0); b.set(4, 5, 0xFFFFFF)
	case .sunleaf:
		b.ellipse(5.5, 4.5, 3.0, 2.0, 0x9AD040); b.line(2, 8, 5, 5, 0x5A8A2A); b.line(4, 4, 7, 5, 0xC8E870); b.set(7, 3, 0xF0F070)
	case .glowcap:
		b.ellipse(5, 4, 3.6, 2.2, 0x40C8D8); b.rect(4, 5, 2, 4, 0xD8D0C0); b.set(3, 3, 0xB8FFFF); b.set(6, 3, 0xB8FFFF)
	case .slimeGel:
		b.ellipse(5, 6, 3.6, 2.8, 0x6AC85A); b.ellipse(4, 5, 1.2, 0.9, 0xB8F0A8); b.set(6, 7, 0x3A8A3A)
	case .venomSac:
		b.ellipse(5, 5.5, 3.2, 3.2, 0x7A5AA0); b.ellipse(5, 6, 2.0, 1.8, 0x9AE050); b.set(4, 4, 0xD8C8F0)
	case .frostCrystal:
		b.line(5, 1, 5, 8, 0xA8E8FF); b.line(3, 3, 7, 7, 0xD8F8FF); b.line(7, 3, 3, 7, 0xD8F8FF); b.line(2, 5, 8, 5, 0x7AC8F0); b.set(5, 5, 0xFFFFFF)
	case .emberAsh:
		b.ellipse(5, 6.5, 3.6, 2.2, 0x4A4448); b.set(3, 6, 0xFF7A2A); b.set(6, 5, 0xFFB040); b.set(5, 7, 0xE8502A)
	case .wraithDust:
		b.set(3, 3, 0xD8C8F0); b.set(6, 2, 0xB8A8E0); b.set(4, 6, 0xE8E0FF); b.set(7, 5, 0xC8B8F0); b.set(2, 7, 0xB8A8E0); b.set(6, 8, 0xD8C8F0); b.set(5, 4, 0xFFFFFF)
	case .stormEssence:
		b.ellipse(5, 5, 3.2, 3.2, 0x5A5A3A); b.line(5, 1, 3, 5, 0xFFF07A); b.line(3, 5, 6, 5, 0xFFF07A); b.line(6, 5, 4, 9, 0xFFF07A); b.set(5, 5, 0xFFFFFF)
	case .golemCore:
		b.ellipse(5, 5, 3.6, 3.6, 0x7A7E88); b.line(3, 3, 6, 6, 0x60E0FF); b.line(6, 6, 7, 4, 0x60E0FF); b.set(4, 3, 0xA8ACB8)
	case .sentinelLens:
		b.rect(3, 2, 4, 1, 0xF0B8E8); b.rect(2, 3, 6, 3, 0xC88AE8); b.rect(3, 6, 4, 2, 0x8AF0E8); b.set(4, 3, 0xFFFFFF); b.set(5, 6, 0xD8FFFA)
	case .mutantGland:
		b.ellipse(5, 5.5, 3.4, 3.0, 0xC8789A); b.ellipse(4, 5, 1.4, 1.2, 0x9AF04A); b.set(6, 7, 0x7A3A5A); b.set(3, 4, 0xF0B8D0)
	}
	b.outline(0x1A1410)
	return b
}

func iconSpear(_ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	// a long shaft with a leaf-shaped head, drawn on the same diagonal as the sword
	b.line(1, 11, 8, 4, 0x9A6A32)
	b.line(2, 11, 8, 5, 0x5E3C1C)
	b.line(8, 3, 11, 0, m)
	b.line(8, 4, 10, 2, tierShade(m, 0.7))
	b.line(9, 2, 10, 1, tierShade(m, 1.3))
	b.rect(7, 4, 2, 1, 0xC8A040)
	b.outline(0x1A1410)
	return b
}

func iconHammer(_ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	let hi: UInt32 = tierShade(m, 1.25)
	let lo: UInt32 = tierShade(m, 0.7)
	b.line(1, 11, 7, 5, 0x9A6A32)
	b.line(2, 11, 7, 6, 0x5E3C1C)
	// a broad, squared head across the top of the haft
	b.rect(5, 1, 6, 4, m)
	b.rect(5, 1, 6, 1, hi)
	b.rect(5, 4, 6, 1, lo)
	b.rect(10, 1, 1, 4, lo)
	b.rect(7, 2, 2, 1, hi)
	b.outline(0x1A1410)
	return b
}

func iconKnife(_ tier: Tier) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let m: UInt32 = tier.color
	// a short, broad blade on the sword's diagonal, a stubby guard and a wrapped grip
	b.line(6, 5, 10, 1, m)
	b.line(6, 6, 10, 2, tierShade(m, 0.7))
	b.line(5, 5, 9, 1, tierShade(m, 1.35))
	b.line(4, 5, 6, 7, 0x6A6A74)
	b.line(2, 9, 5, 6, 0x6A4220)
	b.set(3, 8, 0x9A6A32)
	b.set(2, 9, 0x9A6A32)
	b.outline(0x1A1410)
	return b
}

func iconClub(_ k: ClubKind) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch k {
	case .wooden, .studded:
		// a haft that swells into a knotted head
		b.line(1, 11, 5, 7, 0x7A5428)
		b.line(2, 11, 5, 8, 0x5E3C1C)
		b.ellipse(7.8, 4.2, 3.2, 3.2, 0x9A6A32)
		b.ellipse(7.2, 3.6, 1.6, 1.4, 0xB98A4E)
		b.set(9, 6, 0x6A4220)
		if k == .studded {
			for (x, y) in [(6, 2), (9, 2), (10, 5), (7, 6), (5, 4)] { b.set(x, y, 0xD8D8E0) }
		}
	case .mace:
		b.line(1, 11, 6, 6, 0x6A4220)
		b.line(2, 11, 6, 7, 0x4A3018)
		b.ellipse(8, 4, 2.8, 2.8, 0xC89040)
		b.ellipse(7.4, 3.4, 1.2, 1.2, 0xF0C070)
		b.rect(7, 0, 2, 1, 0xA87030); b.rect(11, 3, 1, 2, 0xA87030); b.rect(4, 3, 1, 2, 0xA87030); b.rect(7, 7, 2, 1, 0xA87030)
	}
	b.outline(0x1A1410)
	return b
}

func iconSling() -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	// two cords meeting in a leather pouch that holds a stone
	b.line(1, 1, 6, 8, 0xC8B080)
	b.line(4, 1, 7, 7, 0xA89060)
	b.ellipse(7.5, 8.5, 2.6, 2.0, 0x8A5A2A)
	b.ellipse(7.5, 8.0, 1.4, 1.2, 0x9A9A9A)
	b.set(7, 7, 0xC8C8C8)
	b.rect(0, 0, 2, 2, 0x6A4220)
	b.outline(0x1A1410)
	return b
}

func iconRelic(_ r: Relic) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch r {
	case .moonDagger:
		b.line(5, 6, 11, 0, 0xDDE4EE)
		b.line(6, 6, 11, 1, 0x9AA8C0)
		b.line(5, 5, 10, 0, 0xFFFFFF)
		b.line(3, 5, 6, 8, 0x8AA8E8)
		b.line(1, 10, 4, 7, 0x3A4A7A)
		b.set(1, 10, 0xC8E8FF)
		b.set(9, 3, 0xC8E8FF)
	case .emberCleaver:
		// a broad, hooked blade glowing along its edge
		b.line(1, 11, 4, 8, 0x4A3018)
		b.rect(4, 6, 2, 2, 0x3A2A2A)
		b.line(5, 5, 10, 0, 0x5A3A3A)
		b.line(6, 6, 11, 1, 0xC0401A)
		b.line(7, 6, 11, 2, 0xFF7A1E)
		b.line(7, 7, 11, 3, 0xFFC050)
		b.set(11, 0, 0xFFE080)
	case .quakeMaul:
		b.line(1, 11, 6, 6, 0x6A4A26)
		b.line(2, 11, 6, 7, 0x4A3018)
		b.rect(4, 0, 7, 5, 0x8A8070)
		b.rect(4, 0, 7, 1, 0xB8AC90)
		b.rect(4, 4, 7, 1, 0x5A5448)
		b.line(6, 1, 8, 3, 0xF0C860)
		b.line(8, 3, 9, 1, 0xF0C860)
	}
	b.outline(0x1A1410)
	return b
}

func iconLauncher(_ g: GunType) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch g {
	case .crossbow, .arbalest, .repeater:
		let prod: UInt32 = g == .crossbow ? 0xA06A2E : (g == .arbalest ? 0x9AA0AA : 0xC89040)
		// a stock pointing right, the bow arms across its front, the drawn string behind them
		b.rect(1, 6, 9, 2, 0x8A5A2A)
		b.rect(1, 7, 3, 2, 0x6A4220)
		b.line(9, 1, 10, 5, prod); b.line(10, 8, 9, 11, prod); b.rect(9, 5, 2, 3, prod)
		b.line(9, 1, 6, 6, 0xE8E8E8); b.line(6, 7, 9, 11, 0xE8E8E8)
		b.rect(7, 5, 4, 1, 0xC8C8D0)
		if g == .arbalest { b.rect(0, 5, 2, 1, 0x6A6E78); b.set(0, 4, 0x6A6E78) }
		if g == .repeater { b.rect(4, 3, 4, 3, 0x7A5428); b.rect(4, 3, 4, 1, 0xC89040) }
	case .blunderbuss:
		b.rect(3, 4, 7, 2, 0x5A5A64)
		b.rect(3, 4, 7, 1, 0x7A7A84)
		b.rect(10, 2, 2, 6, 0x6A6A74)
		b.rect(11, 3, 1, 4, 0x2A2A30)
		b.rect(0, 5, 4, 3, 0x8A5A2A)
		b.rect(4, 6, 2, 2, 0x6A4220)
		b.set(1, 5, 0xB07A40)
	case .stormRod:
		b.line(1, 11, 8, 4, 0xC4CCD8)
		b.line(2, 11, 8, 5, 0x8A929E)
		b.ellipse(9, 2.8, 2.2, 2.2, 0x9A5ADC)
		b.ellipse(8.6, 2.4, 1.0, 1.0, 0xEEDCFF)
		b.set(11, 0, 0xFFF4A0); b.set(11, 5, 0xFFF4A0); b.set(6, 1, 0xFFF4A0)
		b.rect(6, 6, 2, 1, 0xD2793A)
	default:
		break
	}
	b.outline(0x1A1410)
	return b
}

func iconGear(_ g: Gear) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	switch g {
	case .headlamp:
		b.rect(1, 5, 10, 2, 0x5A4030); b.rect(1, 5, 10, 1, 0x7A5A40)
		b.ellipse(6, 5.5, 2.4, 2.4, 0x6A6E78); b.ellipse(6, 5.5, 1.4, 1.4, 0xFFF0A0); b.set(5, 5, 0xFFFFFF)
		b.set(9, 3, 0xFFF0A0); b.set(10, 2, 0xFFF0A0)
	case .swiftBoots:
		b.rect(2, 2, 4, 6, 0x8A5A2A); b.rect(2, 8, 8, 2, 0x8A5A2A); b.rect(2, 10, 9, 1, 0x4A3018)
		b.rect(3, 3, 2, 4, 0xB8743A); b.line(6, 4, 9, 2, 0xF0F0F8); b.line(6, 5, 9, 4, 0xC8C8D8)
	case .divingMask:
		b.rect(1, 4, 10, 4, 0x3A4A5A); b.rect(2, 5, 3, 2, 0x8AD0F0); b.rect(7, 5, 3, 2, 0x8AD0F0)
		b.set(2, 5, 0xE0F8FF); b.set(7, 5, 0xE0F8FF); b.rect(5, 8, 2, 3, 0xD87A30); b.rect(5, 1, 2, 3, 0xD87A30)
	case .wardenSigil:
		b.ellipse(6, 6, 4.6, 4.6, 0x3A2C4A); b.ellipse(6, 6, 3.4, 3.4, 0x6A4A8A)
		b.line(6, 3, 6, 9, 0xD8A8FF); b.line(3, 6, 9, 6, 0xD8A8FF); b.set(6, 6, 0xFFFFFF)
		b.set(4, 4, 0xB070FF); b.set(8, 8, 0xB070FF); b.set(4, 8, 0xB070FF); b.set(8, 4, 0xB070FF)
	case .emberCharm:
		b.line(3, 1, 6, 4, 0xC8A040); b.line(9, 1, 6, 4, 0xC8A040)
		b.ellipse(6, 7, 3.0, 3.4, 0xE8580C); b.ellipse(6, 7.4, 1.8, 2.0, 0xFFA030); b.set(6, 7, 0xFFE680); b.set(5, 5, 0xFFD060)
	case .silverCharm:
		// a silver crescent on a fine chain
		b.line(3, 1, 6, 4, 0xA8AEB8); b.line(9, 1, 6, 4, 0xA8AEB8)
		b.ellipse(6, 7.5, 3.4, 3.4, 0xDDE4EE)
		// the bite that makes it a crescent is cut clean out (left see-through, not painted black)
		for yy in 0..<12 { for xx in 0..<12 {
			let dx: Double = Double(xx) + 0.5 - 7.6
			let dy: Double = Double(yy) + 0.5 - 6.6
			if dx * dx + dy * dy < 2.7 * 2.7 { b.clear(xx, yy) }
		} }
		b.set(3, 8, 0xFFFFFF); b.set(5, 10, 0xB8C0CC); b.set(3, 6, 0xF4F8FF)
	case .winterCoat:
		// a padded coat with a fur collar
		b.rect(2, 2, 8, 9, 0x8A3A3A); b.rect(1, 3, 2, 6, 0x8A3A3A); b.rect(9, 3, 2, 6, 0x8A3A3A)
		b.rect(3, 1, 6, 2, 0xE8E0D0); b.line(6, 3, 6, 10, 0x5A2424)
		b.set(5, 5, 0xD8C060); b.set(5, 7, 0xD8C060); b.rect(3, 4, 1, 5, 0xA84A4A)
	case .snowBoots:
		// fur-topped boots with a cleated sole
		b.rect(2, 2, 4, 6, 0x5A4030); b.rect(2, 8, 8, 2, 0x5A4030); b.rect(2, 1, 4, 2, 0xE8E0D0)
		b.rect(2, 10, 9, 1, 0x2A2A30); b.set(3, 11, 0x9AA0AC); b.set(6, 11, 0x9AA0AC); b.set(9, 11, 0x9AA0AC)
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
	case .gun(let g) where g != .pistol && g != .rifle:
		return iconLauncher(g)
	case .ammo(.bolt):
		b.line(2, 9, 8, 3, 0x7A5428); b.line(3, 9, 8, 4, 0x5E3C1C)
		b.rect(8, 2, 2, 2, 0xC89040); b.set(10, 1, 0xF0C070)
		b.line(1, 10, 2, 8, 0xC8C8D0); b.line(1, 10, 3, 10, 0xC8C8D0)
	case .gadget(.fireFlask):
		b.ellipse(6, 7.5, 3.6, 3.4, 0xB8E0F0)
		b.ellipse(6, 8.2, 2.8, 2.4, 0xFF7A1E)
		b.ellipse(5.4, 7.4, 1.2, 1.0, 0xFFD060)
		b.rect(5, 2, 2, 2, 0xB8E0F0)
		b.rect(5, 1, 2, 1, 0x8A5A2A)
		b.set(8, 6, 0xFFFFFF)
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
		case .offroadWheel: b.ellipse(6, 6, 5.6, 5.6, 0x18181C); b.ellipse(6, 6, 3.4, 3.4, 0x3A3A42); b.ellipse(6, 6, 2.2, 2.2, 0xC89040); b.set(6, 6, 0x4A3A20)
		case .headlight: b.rect(1, 4, 5, 5, 0x5A5A64); b.rect(6, 3, 4, 7, 0x9A9AA4); b.rect(7, 4, 3, 5, 0xFFF0A0); b.set(8, 5, 0xFFFFFF); b.line(10, 4, 11, 2, 0xFFF0A0); b.line(10, 8, 11, 10, 0xFFF0A0)
		case .cargo: b.rect(1, 2, 10, 9, 0x8F6732); b.rect(2, 3, 8, 7, 0xB98A4E); b.line(2, 3, 9, 9, 0x8F6732); b.line(2, 9, 9, 3, 0x8F6732); b.rect(1, 2, 10, 1, 0x6A6A74)
		case .drill, .diamondDrill, .voidDrill:
			let bit: UInt32 = p == .drill ? 0xC8CCD4 : (p == .diamondDrill ? 0x6FE6EC : 0xB070FF)
			b.rect(0, 3, 4, 6, 0x6A6A74); b.rect(0, 3, 4, 1, 0x9A9AA4)
			b.rect(4, 3, 3, 6, bit); b.rect(7, 4, 2, 4, bit); b.rect(9, 5, 2, 2, bit); b.set(11, 5, bit)
			b.line(5, 3, 7, 8, shadeRGB(bit, 0.7)); b.line(8, 4, 9, 7, shadeRGB(bit, 0.7))
		default:
			// the newer parts use their 8x8 vehicle art
			b.blit(partBuf(p), 2, 2)
		}
	case .gadget(let g):
		switch g {
		case .bucket:
			// an iron pail with a handle
			b.rect(2, 4, 8, 7, 0x8A8E96); b.rect(2, 4, 8, 1, 0xB8BCC4); b.rect(3, 10, 6, 1, 0x5A5E66); b.rect(2, 5, 1, 5, 0xA8ACB4)
			b.line(2, 4, 5, 1, 0x4A4E56); b.line(9, 4, 6, 1, 0x4A4E56); b.set(5, 1, 0x4A4E56); b.set(6, 1, 0x4A4E56)
		case .powerCable, .pulseWire, .pulseWireB:
			// a spool of wire with a loose end
			let c: UInt32 = g == .powerCable ? 0xD2793A : (g == .pulseWire ? 0xFFC020 : 0x30E0D0)
			let dk: UInt32 = shadeRGB(c, 0.6)
			b.ellipse(5.5, 6.0, 4.4, 4.4, dk); b.ellipse(5.5, 6.0, 3.6, 3.6, c); b.ellipse(5.5, 6.0, 1.4, 1.4, 0x5A4030)
			b.line(2, 4, 9, 4, dk); b.line(2, 7, 9, 7, dk); b.line(9, 6, 11, 10, c); b.set(11, 11, 0xE8E8EC)
		case .wireSnips:
			b.line(2, 2, 7, 7, 0xC8CCD4); b.line(9, 2, 4, 7, 0xA8AEB8); b.rect(5, 6, 2, 2, 0x6A6E78)
			b.line(3, 8, 1, 11, 0xD2793A); b.line(8, 8, 10, 11, 0xD2793A); b.line(4, 8, 2, 11, 0xA85A28); b.line(7, 8, 9, 11, 0xA85A28)
		case .probe:
			// a hand meter with a dial and a probe lead
			b.rect(2, 1, 7, 9, 0x3A3F4A); b.rect(3, 2, 5, 4, 0xE8E4D8); b.line(4, 5, 6, 3, 0x2A2A30); b.set(5, 7, 0x30E0D0); b.set(7, 7, 0xFFC020)
			b.line(8, 9, 10, 11, 0xD2793A); b.set(11, 11, 0xE8E8EC)
		case .fireFlask: break
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
		case .barometer:
			// a brass dial with a needle
			b.ellipse(6, 6, 5.0, 5.0, 0xC89040); b.ellipse(6, 6, 3.8, 3.8, 0xF0E8D0)
			b.line(6, 6, 8, 3, 0x2A2A30); b.set(6, 6, 0x8A3A3A); b.set(3, 6, 0x6A6A70); b.set(9, 6, 0x6A6A70); b.set(6, 9, 0x6A6A70)
		case .waterFlask:
			b.ellipse(6, 7.5, 3.6, 3.4, 0xB8E0F0); b.ellipse(6, 8.2, 2.8, 2.4, 0x3B7BE0); b.ellipse(5.4, 7.4, 1.0, 0.8, 0x8DBBFF)
			b.rect(5, 2, 2, 2, 0xB8E0F0); b.rect(5, 1, 2, 1, 0x8A5A2A); b.set(8, 6, 0xFFFFFF)
		case .planeKit:
			b.rect(1, 6, 9, 2, 0xD8D8E0); b.rect(0, 4, 2, 3, 0xC84A3A); b.rect(4, 5, 4, 1, 0x9A9AA4); b.rect(3, 8, 5, 1, 0x9A9AA4)
			b.rect(7, 5, 2, 1, 0x9AD0F0); b.rect(10, 4, 1, 5, 0x6A6A74); b.set(10, 6, 0x3A3A44); b.set(3, 9, 0x222226); b.set(8, 9, 0x222226)
		case .heliKit:
			b.ellipse(7, 7, 3.4, 2.6, 0x4E8A3E); b.rect(7, 6, 3, 2, 0x9AD0F0); b.rect(0, 6, 5, 1, 0x4E8A3E); b.rect(0, 4, 1, 3, 0x6A6A74)
			b.rect(1, 2, 11, 1, 0x3A3A44); b.rect(6, 2, 1, 3, 0x5A5A64); b.rect(4, 10, 6, 1, 0x5A5A64)
		case .airshipKit:
			b.ellipse(6, 4.5, 5.5, 3.5, 0xD8483C); b.rect(4, 1, 1, 7, 0xF0E4D0); b.rect(8, 1, 1, 7, 0xF0E4D0)
			b.rect(4, 9, 4, 2, 0x8F6732); b.set(4, 8, 0x6A4A22); b.set(7, 8, 0x6A4A22); b.rect(8, 9, 1, 2, 0x9A9AA4)
		case .tankKit:
			b.rect(1, 8, 10, 3, 0x2A2A30); b.set(3, 9, 0x6A6A74); b.set(6, 9, 0x6A6A74); b.set(9, 9, 0x6A6A74)
			b.rect(1, 6, 10, 2, 0x5A6450); b.rect(4, 4, 4, 2, 0x4A5040); b.rect(8, 4, 4, 1, 0x2A2A30)
		case .truckKit:
			b.rect(7, 3, 4, 5, 0x3A6AA8); b.rect(8, 4, 2, 2, 0x9AD0F0); b.rect(0, 5, 7, 3, 0x8F6732); b.rect(0, 5, 7, 1, 0xB98A4E)
			b.ellipse(2.5, 9, 1.6, 1.6, 0x222226); b.ellipse(9, 9, 1.6, 1.6, 0x222226)
		case .assembler:
			b.rect(2, 3, 8, 8, 0x5A5A64); b.rect(3, 4, 6, 6, 0x3A3F4A); b.ellipse(6, 7, 2.2, 2.2, 0x30C0E0); b.set(5, 6, 0xB0F0FF)
			b.rect(5, 0, 2, 3, 0xC89040); b.rect(1, 2, 2, 2, 0xC89040); b.rect(9, 2, 2, 2, 0xC89040)
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
	case .spear(let t): return iconSpear(t)
	case .hammer(let t): return iconHammer(t)
	case .knife(let t): return iconKnife(t)
	case .club(let k): return iconClub(k)
	case .relic(let r): return iconRelic(r)
	case .sling: return iconSling()
	case .gear(let g): return iconGear(g)
	case .armor(let s, let t): return iconArmor(s, t)
	case .mat(let m): return iconMat(m)
	case .food(let f): return iconFood(f)
	case .wall(let k): return wallIcon(k)
	case .custom(let k): return ModRuntime.shared.item(k)?.icon ?? missingItemBuf()
	case .potion(let p): return iconPotion(p)
	case .compound(let i): return iconCompound(i)
	case .exoPart, .exoPlate, .exoCore, .exoModule: return iconExo(it)
	default: return iconMisc(it)
	}
}

/// The icon of an item whose mod is missing: a question mark on magenta
func missingItemBuf() -> PixelBuf {
	let rows: [String] = [".mmmmmm.", "mmkkkkmm", "mkmmmmkm", "mmmmmkmm", "mmmmkmmm", "mmmkmmmm", "mmmmmmmm", ".mmkmmm."]
	var b: PixelBuf = bufFromRows(rows, ["m": 0xE040E0, "k": 0x200020])
	b = padBuf(b)
	b.outline(0x101010)
	return b
}

// ===== p04_recipes =====

// MARK: - Recipes & inventory

enum Station: Int, Codable {
	case hand, bench, furnace, campfire
	/// appended, so the raw values above never change: metalwork, machinery, Umbral smithing
	case anvil, tinker, forge
	/// appended: brewing, infusion compounds and suit parts
	case still, infuser, assembly
	var name: String {
		switch self {
		case .still: return "Alchemy Still"
		case .infuser: return "Infusion Crucible"
		case .assembly: return "Assembly Station"
		case .hand: return "By hand"
		case .bench: return "Workbench"
		case .furnace: return "Furnace"
		case .campfire: return "Campfire / Furnace"
		case .anvil: return "Anvil"
		case .tinker: return "Tinker's Bench"
		case .forge: return "Rift Forge"
		}
	}
	/// the block that provides this station
	var tile: Tile? {
		switch self {
		case .hand, .campfire: return nil
		case .bench: return .workbench
		case .furnace: return .furnace
		case .anvil: return .anvil
		case .tinker: return .tinkerBench
		case .forge: return .riftForge
		case .still: return .alchemyStill
		case .infuser: return .infuser
		case .assembly: return .exoStation
		}
	}
}

/// Which station a tier of tools, weapons and armour is made at: wood to copper at the workbench,
/// iron to mythril on an anvil, and the Umbral metals only in a rift forge
func tierStation(_ t: Tier) -> Station {
	switch t {
	case .wood, .stone, .copper: return .bench
	case .iron, .gold, .diamond, .mythril: return .anvil
	case .ember, .voidium: return .forge
	}
}

enum RecipeCat: Int, CaseIterable {
	case basic, build, tools, weapons, armor, gear, smelt, food, vehicle
	/// appended: weather devices and storm building
	case weather
	/// appended: Sparkworks power, pulses and machines
	case power
	/// appended: recipes from mods
	case mods
	/// appended: potions, infusion compounds, suit parts
	case alchemy, infusion, exosuit
	var name: String {
		switch self {
		case .alchemy: return "Alchemy"
		case .infusion: return "Infusion"
		case .exosuit: return "Exosuit"
		case .mods: return "Mods"
		case .power: return "Power"
		case .weather: return "Weather"
		case .basic: return "Basics"
		case .build: return "Building"
		case .tools: return "Tools"
		case .weapons: return "Weapons"
		case .armor: return "Armor"
		case .gear: return "Gear"
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
	/// a mod block that must be nearby instead of a game station (mod recipes only)
	var modStation: Tile? = nil
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
	/// the game's own recipes
	static let base: [Recipe] = RecipeBook.build()
	/// what the crafting screens show: the game's recipes, then those of the world's mods
	static var all: [Recipe] = RecipeBook.base

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
		add(planks, 4, [(.block(.birchLog), 1)], .hand, .basic)
		add(stick, 4, [(planks, 2)], .hand, .basic)
		add(.block(.workbench), 1, [(planks, 8)], .hand, .basic)
		add(.block(.torch), 4, [(stick, 1), (coal, 1)], .hand, .basic)
		add(.block(.campfire), 1, [(.block(.log), 3), (stick, 2)], .hand, .basic)
		add(.block(.furnace), 1, [(.block(.stone), 12)], .bench, .basic)
		// the stations that unlock the later recipe tiers
		add(.block(.anvil), 1, [(.mat(.ironBar), 6), (.block(.stone), 4)], .bench, .basic)
		add(.block(.tinkerBench), 1, [(planks, 6), (.mat(.ironBar), 3), (.mat(.copperBar), 2)], .bench, .basic)
		add(.block(.riftForge), 1, [(.block(.obsidian), 12), (.block(.glowCrystal), 4), (.mat(.emberBar), 2)], .anvil, .basic)
		add(.mat(.string), 2, [(.mat(.wool), 1)], .hand, .basic)
		add(.mat(.gunpowder), 2, [(coal, 1), (.block(.sand), 1)], .bench, .basic)
		add(.mat(.gunpowder), 4, [(coal, 1), (.mat(.saltpeter), 1)], .bench, .basic)
		add(.block(.glass), 1, [(.block(.sand), 2)], .furnace, .smelt)
		// Building: platforms, ladders, storage, light, doors and background walls (no collision)
		add(.block(.platform), 4, [(planks, 2)], .hand, .build)
		add(.block(.ladder), 3, [(stick, 5)], .hand, .build)
		add(.block(.chest), 1, [(planks, 8)], .bench, .build)
		add(.block(.brick), 2, [(.block(.stone), 2)], .bench, .build)
		add(.block(.lantern), 1, [(.mat(.ironBar), 1), (.block(.torch), 1)], .bench, .build)
		add(.block(.hay), 2, [(.food(.wheat), 4)], .bench, .build)
		add(.block(.doorClosed), 1, [(planks, 6)], .bench, .build)
		add(.wall(5), 4, [(planks, 1)], .bench, .build)
		add(.wall(6), 4, [(.block(.brick), 1)], .bench, .build)
		add(.wall(2), 4, [(.block(.stone), 1)], .bench, .build)
		add(.wall(1), 4, [(.block(.dirt), 1)], .bench, .build)
		add(.wall(7), 4, [(.block(.sandstone), 1)], .bench, .build)
		add(.wall(4), 4, [(.block(.ashStone), 1)], .bench, .build)
		add(.block(.amethystBlock), 1, [(.mat(.amethyst), 4)], .bench, .build)
		add(.block(.lantern), 1, [(.mat(.bronzeBar), 1), (.block(.torch), 1)], .bench, .build)
		add(.block(.rail), 8, [(.mat(.bronzeBar), 1), (stick, 2)], .bench, .build)
		add(.block(.crate), 1, [(planks, 6)], .bench, .build)
		// Smelting
		add(.mat(.copperBar), 1, [(.mat(.copperOre), 2), (coal, 1)], .furnace, .smelt)
		add(.mat(.ironBar), 1, [(.mat(.ironOre), 2), (coal, 1)], .furnace, .smelt)
		add(.mat(.goldBar), 1, [(.mat(.goldOre), 2), (coal, 1)], .furnace, .smelt)
		add(.mat(.mythrilBar), 1, [(.mat(.mythrilOre), 3), (coal, 2)], .furnace, .smelt)
		add(.mat(.emberBar), 1, [(.mat(.emberOre), 3), (coal, 1)], .furnace, .smelt)
		add(.mat(.voidBar), 1, [(.mat(.voidOre), 3), (coal, 2)], .furnace, .smelt)
		// bronze is copper with a little tin; silver smelts like the other metals
		add(.mat(.bronzeBar), 2, [(.mat(.copperOre), 2), (.mat(.tinOre), 1), (coal, 1)], .furnace, .smelt)
		add(.mat(.silverBar), 1, [(.mat(.silverOre), 2), (coal, 1)], .furnace, .smelt)
		// Food
		add(.food(.cookedMeat), 1, [(.food(.rawMeat), 1)], .campfire, .food)
		add(.food(.cookedFish), 1, [(.food(.rawFish), 1)], .campfire, .food)
		add(.food(.bread), 1, [(.food(.wheat), 3)], .bench, .food)
		// Tools, swords, armor for every tier
		// Tools, weapons and armour for every tier, each tier at its own station
		for t in Tier.allCases {
			let m: Item = tierMaterial(t)
			let st: Station = tierStation(t)
			add(.tool(.pickaxe, t), 1, [(m, 3), (stick, 2)], st, .tools)
			add(.tool(.axe, t), 1, [(m, 3), (stick, 2)], st, .tools)
			add(.tool(.shovel, t), 1, [(m, 1), (stick, 2)], st, .tools)
			add(.tool(.hoe, t), 1, [(m, 2), (stick, 2)], st, .tools)
			add(.sword(t), 1, [(m, 2), (stick, 1)], st, .weapons)
			add(.spear(t), 1, [(m, 2), (stick, 3)], st, .weapons)
			add(.hammer(t), 1, [(m, 4), (stick, 2)], st, .weapons)
			if t != .wood { add(.knife(t), 1, [(m, 1), (stick, 1)], st, .weapons) }
			let a: Item = armorMaterial(t)
			add(.armor(.head, t), 1, [(a, 5)], st, .armor)
			add(.armor(.chest, t), 1, [(a, 8)], st, .armor)
			add(.armor(.legs, t), 1, [(a, 7)], st, .armor)
		}
		// Ranged
		add(.bow, 1, [(stick, 3), (.mat(.string), 3)], .bench, .weapons)
		add(.ammo(.arrow), 6, [(stick, 1), (.mat(.feather), 1), (.block(.stone), 1)], .bench, .weapons)
		add(.gun(.pistol), 1, [(.mat(.ironBar), 5), (planks, 2)], .anvil, .weapons)
		add(.gun(.rifle), 1, [(.mat(.ironBar), 8), (planks, 4), (.mat(.gunpowder), 2)], .anvil, .weapons)
		add(.ammo(.bullet), 8, [(.mat(.ironBar), 1), (.mat(.gunpowder), 1)], .anvil, .weapons)
		add(.gadget(.shears), 1, [(.mat(.ironBar), 2)], .anvil, .tools)
		add(.gadget(.wrench), 1, [(.mat(.ironBar), 3), (stick, 1)], .anvil, .tools)
		add(.gadget(.bomb), 3, [(.mat(.gunpowder), 2), (.mat(.ironBar), 1), (.mat(.string), 1)], .bench, .weapons)
		// the club line: a crude start, studded with bone, then a bronze mace
		add(.club(.wooden), 1, [(planks, 3), (stick, 1)], .hand, .weapons)
		add(.club(.studded), 1, [(.club(.wooden), 1), (.mat(.bone), 3)], .bench, .weapons)
		add(.club(.mace), 1, [(.club(.studded), 1), (.mat(.bronzeBar), 4)], .anvil, .weapons)
		add(.sling, 1, [(.mat(.leather), 1), (.mat(.string), 2)], .hand, .weapons)
		// bolt throwers: bronze makes the crossbow and its bolts; iron makes the heavy one
		add(.gun(.crossbow), 1, [(.mat(.bronzeBar), 3), (planks, 3), (.mat(.string), 2)], .bench, .weapons)
		add(.ammo(.bolt), 8, [(.mat(.bronzeBar), 1), (stick, 2)], .bench, .weapons)
		add(.ammo(.bolt), 8, [(.mat(.ironBar), 1), (stick, 2)], .anvil, .weapons)
		add(.gun(.arbalest), 1, [(.gun(.crossbow), 1), (.mat(.ironBar), 4), (.mat(.string), 2)], .anvil, .weapons)
		add(.gun(.blunderbuss), 1, [(.mat(.bronzeBar), 5), (.mat(.ironBar), 2), (planks, 2), (.mat(.gunpowder), 2)], .anvil, .weapons)
		add(.gadget(.fireFlask), 2, [(.block(.glass), 1), (.mat(.saltpeter), 1), (coal, 1)], .bench, .weapons)
		add(.gun(.stormRod), 1, [(.mat(.silverBar), 3), (.mat(.amethyst), 4), (.mat(.copperBar), 2), (.mat(.goldBar), 1)], .tinker, .weapons)
		// Gear, worn in the two gear slots
		add(.gear(.divingMask), 1, [(.block(.glass), 3), (.mat(.copperBar), 2), (.mat(.leather), 1)], .bench, .gear)
		add(.gear(.headlamp), 1, [(.mat(.ironBar), 2), (.mat(.crystalShard), 1), (.block(.torch), 1)], .tinker, .gear)
		add(.gear(.headlamp), 1, [(.mat(.ironBar), 2), (.mat(.amethyst), 2), (.block(.torch), 1)], .tinker, .gear)
		add(.gear(.silverCharm), 1, [(.mat(.silverBar), 4), (.mat(.string), 1)], .anvil, .gear)
		add(.gear(.swiftBoots), 1, [(.mat(.leather), 4), (.mat(.feather), 3), (.mat(.goldBar), 2)], .anvil, .gear)
		add(.gear(.emberCharm), 1, [(.mat(.emberBar), 3), (.block(.glowCrystal), 2), (.mat(.crystalShard), 1)], .forge, .gear)
		add(.gear(.wardenSigil), 1, [(.mat(.umbralHeart), 1), (.mat(.voidBar), 4), (.mat(.crystalShard), 4)], .forge, .gear)
		// Ready-made vehicles (place them in one tap) - easiest way to get driving
		add(.gadget(.carKit), 1, [(planks, 10), (.mat(.ironBar), 14), (.mat(.leather), 2), (.mat(.wool), 2)], .tinker, .vehicle)
		add(.gadget(.boatKit), 1, [(planks, 20), (.mat(.string), 4), (.mat(.wool), 2)], .bench, .vehicle)
		add(.gadget(.motorboatKit), 1, [(planks, 20), (.mat(.ironBar), 12), (.mat(.copperBar), 3), (.mat(.wool), 2), (.block(.glass), 1)], .tinker, .vehicle)
		// Vehicle parts (for building your own design): wooden ones at the workbench, machinery at
		// the tinker's bench
		add(.part(.frame), 1, [(planks, 4), (.mat(.ironBar), 1)], .bench, .vehicle)
		add(.part(.wheel), 1, [(.mat(.ironBar), 2), (.mat(.leather), 1)], .tinker, .vehicle)
		add(.part(.engine), 1, [(.mat(.ironBar), 6), (.mat(.copperBar), 3), (coal, 2)], .tinker, .vehicle)
		add(.part(.steering), 1, [(.mat(.ironBar), 1), (stick, 2)], .tinker, .vehicle)
		add(.part(.seat), 1, [(planks, 2), (.mat(.wool), 2)], .bench, .vehicle)
		add(.part(.fuelTank), 1, [(.mat(.ironBar), 3), (.block(.glass), 1)], .tinker, .vehicle)
		add(.part(.hull), 1, [(planks, 6), (.mat(.string), 2)], .bench, .vehicle)
		add(.part(.propeller), 1, [(.mat(.ironBar), 3)], .tinker, .vehicle)
		add(.part(.propeller), 1, [(.mat(.bronzeBar), 3)], .tinker, .vehicle)
		add(.part(.paddle), 1, [(planks, 2), (stick, 2)], .bench, .vehicle)
		add(.part(.drill), 1, [(.mat(.ironBar), 6), (.mat(.copperBar), 2)], .tinker, .vehicle)
		add(.part(.diamondDrill), 1, [(.part(.drill), 1), (.mat(.diamond), 4), (.mat(.goldBar), 2)], .tinker, .vehicle)
		add(.part(.offroadWheel), 1, [(.mat(.ironBar), 3), (.mat(.leather), 2), (.mat(.fur), 1)], .tinker, .vehicle)
		add(.part(.headlight), 1, [(.mat(.copperBar), 1), (.block(.glass), 1), (.block(.torch), 2)], .tinker, .vehicle)
		add(.part(.cargo), 1, [(planks, 8), (.mat(.ironBar), 2)], .tinker, .vehicle)
		add(.part(.voidDrill), 1, [(.part(.diamondDrill), 1), (.mat(.voidBar), 4), (.mat(.emberBar), 2)], .forge, .vehicle)
		// aircraft, airships, tanks and armed vehicles: wood and canvas at the workbench, machinery at the
		// tinker's bench, armour and guns at the anvil, the jet at the forge
		add(.part(.cockpit), 1, [(.mat(.ironBar), 3), (.block(.glass), 2), (.mat(.wool), 1)], .tinker, .vehicle)
		add(.part(.wing), 1, [(planks, 3), (.mat(.ironBar), 1), (.mat(.string), 2)], .bench, .vehicle)
		add(.part(.elevator), 1, [(planks, 2), (.mat(.ironBar), 1), (.mat(.string), 1)], .bench, .vehicle)
		add(.part(.airProp), 1, [(planks, 2), (.mat(.ironBar), 2)], .tinker, .vehicle)
		add(.part(.jet), 1, [(.mat(.ironBar), 8), (.mat(.copperBar), 4), (.mat(.emberBar), 2)], .forge, .vehicle)
		add(.part(.rotor), 1, [(.mat(.ironBar), 5), (.mat(.copperBar), 2)], .tinker, .vehicle)
		add(.part(.tailRotor), 1, [(.mat(.ironBar), 2), (.mat(.copperBar), 1)], .tinker, .vehicle)
		add(.part(.envelope), 2, [(.mat(.wool), 3), (.mat(.string), 1)], .bench, .vehicle)
		add(.part(.burner), 1, [(.mat(.ironBar), 3), (.mat(.copperBar), 2), (coal, 2)], .tinker, .vehicle)
		add(.part(.track), 1, [(.mat(.ironBar), 4), (.mat(.leather), 2)], .anvil, .vehicle)
		add(.part(.armor), 1, [(.mat(.ironBar), 6)], .anvil, .vehicle)
		add(.part(.cannon), 1, [(.mat(.ironBar), 8), (.mat(.bronzeBar), 2), (.mat(.gunpowder), 2)], .anvil, .vehicle)
		add(.part(.autoGun), 1, [(.mat(.ironBar), 5), (.mat(.copperBar), 2), (.mat(.gunpowder), 1)], .anvil, .vehicle)
		add(.part(.autopilot), 1, [(.mat(.copperBar), 4), (.mat(.goldBar), 1), (.block(.glass), 1)], .tinker, .vehicle)
		add(.gadget(.assembler), 1, [(.mat(.ironBar), 3), (.mat(.copperBar), 2), (.mat(.goldBar), 1)], .tinker, .vehicle)
		add(.gadget(.planeKit), 1, [(planks, 10), (.mat(.ironBar), 14), (.mat(.copperBar), 3), (.mat(.string), 6), (.block(.glass), 2), (.mat(.wool), 1)], .tinker, .vehicle)
		add(.gadget(.heliKit), 1, [(.mat(.ironBar), 24), (.mat(.copperBar), 7), (.block(.glass), 2), (.mat(.wool), 1)], .tinker, .vehicle)
		add(.gadget(.airshipKit), 1, [(.mat(.wool), 36), (.mat(.string), 14), (planks, 14), (.mat(.ironBar), 12), (.mat(.copperBar), 4)], .tinker, .vehicle)
		add(.gadget(.tankKit), 1, [(.mat(.ironBar), 50), (.mat(.leather), 8), (.mat(.bronzeBar), 2), (.mat(.gunpowder), 2)], .anvil, .vehicle)
		add(.gadget(.truckKit), 1, [(planks, 18), (.mat(.ironBar), 18), (.mat(.leather), 3), (.mat(.wool), 2)], .tinker, .vehicle)
		// Weather: reading it, warning of it, and building against it
		add(.block(.weatherStation), 1, [(.mat(.copperBar), 3), (.block(.glass), 2), (planks, 4), (.mat(.feather), 1)], .bench, .weather)
		add(.block(.dopplerStation), 1, [(.block(.weatherStation), 1), (.mat(.silverBar), 2), (.mat(.amethyst), 2), (.mat(.copperBar), 2)], .tinker, .weather)
		add(.gadget(.barometer), 1, [(.mat(.copperBar), 2), (.block(.glass), 1)], .bench, .weather)
		add(.block(.weatherVane), 1, [(.mat(.copperBar), 2), (stick, 2)], .bench, .weather)
		add(.block(.lightningRod), 1, [(.mat(.copperBar), 4)], .bench, .weather)
		add(.block(.stormSiren), 1, [(.mat(.ironBar), 3), (.mat(.copperBar), 2), (.mat(.bronzeBar), 1)], .anvil, .weather)
		add(.block(.windTurbine), 1, [(.mat(.ironBar), 4), (planks, 6), (.mat(.copperBar), 2)], .tinker, .weather)
		add(.block(.rainBarrel), 1, [(planks, 6), (.mat(.copperBar), 1)], .bench, .weather)
		add(.block(.rainCistern), 1, [(.block(.rainBarrel), 1), (.mat(.ironBar), 3), (.block(.stone), 6)], .anvil, .weather)
		add(.block(.heater), 1, [(.mat(.ironBar), 3), (.block(.brick), 2), (coal, 2)], .bench, .weather)
		add(.block(.sandbag), 4, [(.block(.sand), 4), (.mat(.string), 1)], .bench, .weather)
		add(.block(.shutterClosed), 2, [(planks, 3), (.mat(.ironBar), 1)], .bench, .weather)
		add(.block(.stormBrick), 4, [(.block(.brick), 4), (.mat(.ironBar), 1)], .anvil, .weather)
		add(.block(.shingles), 6, [(planks, 3), (.block(.stone), 3)], .bench, .weather)
		add(.gear(.winterCoat), 1, [(.mat(.wool), 5), (.mat(.leather), 3)], .bench, .weather)
		add(.gear(.winterCoat), 1, [(.mat(.fur), 3), (.mat(.leather), 2)], .bench, .weather)
		add(.gear(.snowBoots), 1, [(.mat(.leather), 3), (.mat(.wool), 2)], .bench, .weather)
		add(.block(.mud), 2, [(.block(.dirt), 2), (.gadget(.waterFlask), 1)], .hand, .weather)
		// Sparkworks. First steps at the workbench: wire, a crank, a battery, switches and lamps.
		let cu: Item = .mat(.copperBar)
		let fe: Item = .mat(.ironBar)
		let bz: Item = .mat(.bronzeBar)
		let ag: Item = .mat(.silverBar)
		let glass: Item = .block(.glass)
		let stone: Item = .block(.stone)
		add(.gadget(.powerCable), 12, [(cu, 1)], .bench, .power)
		add(.gadget(.pulseWire), 12, [(bz, 1)], .bench, .power)
		add(.gadget(.pulseWireB), 12, [(bz, 1), (glass, 1)], .bench, .power)
		add(.gadget(.wireSnips), 1, [(fe, 1), (cu, 1)], .bench, .power)
		add(.gadget(.probe), 1, [(cu, 2), (glass, 1)], .bench, .power)
		add(.block(.crankGen), 1, [(planks, 4), (cu, 2), (stick, 2)], .bench, .power)
		add(.block(.waterWheel), 1, [(planks, 8), (fe, 1)], .bench, .power)
		add(.block(.battery), 1, [(cu, 4), (fe, 1), (coal, 2)], .bench, .power)
		add(.block(.powerSwitch), 1, [(cu, 1), (stone, 2)], .bench, .power)
		add(.block(.lever), 1, [(stick, 1), (stone, 1)], .hand, .power)
		add(.block(.pushButton), 2, [(stone, 2)], .hand, .power)
		add(.block(.pressurePlate), 1, [(stone, 2), (cu, 1)], .bench, .power)
		add(.block(.lampOff), 2, [(glass, 2), (cu, 1)], .bench, .power)
		add(.block(.signalLight), 2, [(glass, 1), (cu, 1)], .bench, .power)
		// Then metalwork and machinery: solar, fuel, breakers and meters, logic, sensors, machines.
		add(.block(.solarPanel), 1, [(glass, 3), (ag, 1), (cu, 2)], .tinker, .power)
		add(.block(.fuelGen), 1, [(fe, 6), (.block(.furnace), 1), (cu, 2)], .anvil, .power)
		add(.block(.breaker), 1, [(fe, 1), (cu, 2), (bz, 1)], .tinker, .power)
		add(.block(.powerMeter), 1, [(glass, 1), (cu, 2), (fe, 1)], .tinker, .power)
		add(.block(.repeater), 2, [(bz, 1), (stone, 2), (cu, 1)], .tinker, .power)
		add(.block(.inverter), 2, [(bz, 1), (stone, 2), (.mat(.saltpeter), 1)], .tinker, .power)
		add(.block(.logicGate), 2, [(bz, 2), (ag, 1), (stone, 2)], .tinker, .power)
		add(.block(.pulseTimer), 1, [(bz, 2), (glass, 1), (cu, 1)], .tinker, .power)
		add(.block(.motionSensor), 1, [(ag, 1), (glass, 1), (cu, 2)], .tinker, .power)
		add(.block(.daySensor), 1, [(glass, 2), (ag, 1), (cu, 1)], .tinker, .power)
		add(.block(.weatherSensor), 1, [(cu, 2), (glass, 1), (.mat(.feather), 1)], .tinker, .power)
		add(.block(.itemSensor), 1, [(cu, 2), (fe, 1), (.block(.chest), 1)], .tinker, .power)
		add(.block(.proximitySensor), 1, [(ag, 1), (.mat(.amethyst), 1), (cu, 2)], .tinker, .power)
		add(.block(.gateClosed), 1, [(fe, 4), (cu, 1)], .anvil, .power)
		add(.block(.arcTrap), 1, [(fe, 3), (cu, 4), (ag, 1)], .anvil, .power)
		add(.block(.conveyor), 4, [(fe, 2), (.mat(.leather), 2), (cu, 1)], .tinker, .power)
		add(.block(.collector), 1, [(fe, 3), (cu, 2), (.block(.chest), 1)], .tinker, .power)
		add(.block(.sumpPump), 1, [(fe, 4), (bz, 1), (glass, 1)], .tinker, .power)
		// Late: big storage, automation that mines and makes things, and the Umbral-fired dynamo.
		add(.block(.accumulator), 1, [(.block(.battery), 2), (.mat(.crystalShard), 4), (.mat(.goldBar), 2)], .tinker, .power)
		add(.block(.autoDrill), 1, [(fe, 6), (.mat(.diamond), 1), (cu, 3)], .anvil, .power)
		add(.block(.autoCrafter), 1, [(.block(.workbench), 1), (fe, 4), (.mat(.goldBar), 2), (.mat(.crystalShard), 1)], .tinker, .power)
		add(.block(.emberDynamo), 1, [(.mat(.emberBar), 4), (.block(.obsidian), 6), (.mat(.crystalShard), 2), (.block(.accumulator), 1)], .forge, .power)
		addFeatureRecipes(add)
		// appended last so every older recipe keeps its number
		addBuildingRecipes(add)
		addPhysicsRecipes(add)
		return list
	}
}

extension RecipeBook {
	/// The physics overhaul's parts and tools (appended after every older recipe, so their numbers stay)
	static func addPhysicsRecipes(_ add: (Item, Int, [(Item, Int)], Station, RecipeCat) -> Void) {
		let planks: Item = .block(.planks)
		add(.part(.flap), 1, [(.part(.wing), 1), (.mat(.ironBar), 1), (.mat(.copperBar), 1)], .tinker, .vehicle)
		add(.part(.airBrake), 1, [(.mat(.ironBar), 3), (planks, 1)], .tinker, .vehicle)
		add(.part(.stabilizer), 1, [(planks, 2), (.mat(.ironBar), 1)], .bench, .vehicle)
		add(.part(.ballast), 1, [(.mat(.ironBar), 5), (.mat(.copperBar), 1), (.block(.glass), 1)], .tinker, .vehicle)
		add(.gadget(.bucket), 1, [(.mat(.ironBar), 3)], .anvil, .tools)
		add(.part(.railWheel), 2, [(.mat(.ironBar), 3)], .anvil, .vehicle)
		add(.part(.coupler), 1, [(.mat(.ironBar), 2), (.mat(.string), 1)], .anvil, .vehicle)
		add(.part(.bigWheel), 1, [(.mat(.ironBar), 4), (.mat(.leather), 3), (.mat(.fur), 1)], .tinker, .vehicle)
		add(.block(.oreCart), 1, [(.mat(.ironBar), 4), (planks, 2)], .anvil, .vehicle)
		add(.part(.hinge), 1, [(.mat(.ironBar), 2)], .anvil, .vehicle)
		add(.part(.servo), 1, [(.mat(.ironBar), 3), (.mat(.copperBar), 3), (.mat(.goldBar), 1)], .tinker, .vehicle)
		add(.part(.piston), 1, [(.mat(.ironBar), 4), (.mat(.copperBar), 2)], .tinker, .vehicle)
	}
}

// MARK: - Inventory

struct Inventory: Codable {
	var slots: [Stack?]
	/// head, body, legs, then the two gear slots
	var armor: [Stack?]
	static let hotbarCount: Int = 10
	static let size: Int = 40
	static let armorSlots: Int = 5
	static let firstGearSlot: Int = 3

	enum CodingKeys: String, CodingKey {
		case slots, armor
	}

	init() {
		slots = [Stack?](repeating: nil, count: Inventory.size)
		armor = [Stack?](repeating: nil, count: Inventory.armorSlots)
	}

	/// Saves from before the gear slots hold three armour entries: they gain two empty gear slots
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		slots = try c.decode([Stack?].self, forKey: .slots)
		armor = try c.decode([Stack?].self, forKey: .armor)
		while slots.count < Inventory.size { slots.append(nil) }
		while armor.count < Inventory.armorSlots { armor.append(nil) }
	}

	func wearing(_ g: Gear) -> Bool {
		for i in Inventory.firstGearSlot..<armor.count {
			if let s = armor[i], case .gear(let x) = s.item, x == g { return true }
		}
		return false
	}

	func total(_ item: Item) -> Int {
		var n: Int = 0
		for s in slots {
			if let st = s, st.item == item { n += st.count }
		}
		return n
	}

	/// Adds items, returns the leftover count that did not fit. Infused items keep their infusions and
	/// never merge with plain ones.
	mutating func add(_ item: Item, _ count: Int, extra: Int = 0, inf: [Int]? = nil) -> Int {
		var left: Int = count
		let ms: Int = item.maxStack
		if ms > 1 {
			for i in 0..<slots.count {
				if left <= 0 { break }
				if var st = slots[i], st.item == item, st.inf == inf, st.count < ms {
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
				slots[i] = Stack(item: item, count: put, extra: extra, inf: inf)
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

	/// Merges partial stacks of the same item (same load and infusions) into the first of them, bag and
	/// hotbar alike, so a material spread over many slots ends up in as few as it fits. Gives how many
	/// stacks were folded in.
	mutating func mergeStacks() -> Int {
		var merged: Int = 0
		for i in 0..<slots.count {
			guard var a = slots[i] else { continue }
			let ms: Int = a.item.maxStack
			if ms <= 1 || a.count >= ms { continue }
			for j in (i + 1)..<slots.count {
				if a.count >= ms { break }
				guard var b = slots[j], b.item == a.item, b.extra == a.extra, b.inf == a.inf else { continue }
				let put: Int = min(ms - a.count, b.count)
				a.count += put
				b.count -= put
				slots[j] = b.count > 0 ? b : nil
				merged += 1
			}
			slots[i] = a
		}
		return merged
	}

	/// Sorts the bag (everything past the hotbar): equal stacks merge, then items group by kind and name.
	/// The hotbar is left alone so a sort never moves what the player has ready.
	mutating func sortBag() {
		var list: [Stack] = []
		for i in Inventory.hotbarCount..<slots.count {
			guard let s = slots[i] else { continue }
			slots[i] = nil
			if s.item.maxStack > 1, let j = list.firstIndex(where: { $0.item == s.item && $0.extra == s.extra && $0.inf == s.inf && $0.count < $0.item.maxStack }) {
				let room: Int = list[j].item.maxStack - list[j].count
				let put: Int = min(room, s.count)
				list[j].count += put
				if s.count - put > 0 { var r: Stack = s; r.count = s.count - put; list.append(r) }
			} else {
				list.append(s)
			}
		}
		list.sort { a, b in
			let ka: Int = a.item.sortGroup
			let kb: Int = b.item.sortGroup
			if ka != kb { return ka < kb }
			if a.item.name != b.item.name { return a.item.name < b.item.name }
			return a.count > b.count
		}
		for (k, s) in list.enumerated() where Inventory.hotbarCount + k < slots.count {
			slots[Inventory.hotbarCount + k] = s
		}
	}

	/// Total armor defense value
	var defense: Double {
		var d: Double = 0
		for s in armor {
			if let st = s, case .armor(let slot, let tier) = st.item { d += OverrideRT.shared.items[st.item]?.defense ?? tier.defense * slot.weight }
			if let st = s, case .custom(let k) = st.item, let r = ModRuntime.shared.item(k), r.def.kind == .armor { d += r.def.defense }
		}
		return d
	}

}

// ===== p05a_humanoid =====

// MARK: - Creature art: inks, the shared finishing pass and frame composition

/// Sprite inks. The alpha byte tells the finishing pass how to treat a pixel:
/// 0xFF is body material (it gets the top light and the bottom shadow), 0xFE is a flat detail
/// (eyes, claws, markings, hand-placed tones) that keeps its colour.
@inline(__always) func inkS(_ c: UInt32) -> UInt32 { return 0xFF000000 | c }
@inline(__always) func inkF(_ c: UInt32) -> UInt32 { return 0xFE000000 | c }

/// The tones every creature derives from its base colours: a warm highlight, a cool shadow and a
/// darkened outline of the neighbouring colour (never plain black)
func toneL(_ c: UInt32) -> UInt32 { return mixRGB(c, 0xFFF2D8, 0.28) }
func toneD(_ c: UInt32) -> UInt32 { return mixRGB(shadeRGB(c, 0.76), 0x2A2448, 0.14) }
func toneO(_ c: UInt32) -> UInt32 { return mixRGB(shadeRGB(c, 0.45), 0x1E1828, 0.42) }

func artLum(_ c: UInt32) -> Double {
	return Double((c >> 16) & 0xFF) * 0.3 + Double((c >> 8) & 0xFF) * 0.59 + Double(c & 0xFF) * 0.11
}

/// The older drawings (made in code, below) have 8 art pixels to a block; the hand-drawn creatures and
/// blocks of ArtSheet have 16. Every picture carries its own size, so both kinds sit side by side while
/// the older ones are being redrawn.
let creatureScale: Double = 0.125
let fineScale: Double = 0.0625

extension PixelBuf {
	/// Writes an ink (alpha byte included) without touching it
	mutating func ink(_ x: Int, _ y: Int, _ v: UInt32) {
		if x < 0 || y < 0 || x >= w || y >= h { return }
		px[y * w + x] = v
	}

	/// Paints rows of palette letters; '.' is transparent
	mutating func paint(_ rows: [String], _ pal: [Character: UInt32], _ ox: Int, _ oy: Int) {
		var y: Int = 0
		for row in rows {
			var x: Int = 0
			for ch in row {
				if ch != "." && ch != " ", let v = pal[ch] { ink(ox + x, oy + y, v) }
				x += 1
			}
			y += 1
		}
	}

	mutating func inkRect(_ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ v: UInt32) {
		if rw <= 0 || rh <= 0 { return }
		for yy in y..<(y + rh) {
			for xx in x..<(x + rw) { ink(xx, yy, v) }
		}
	}

	mutating func inkEllipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ v: UInt32) {
		let x0: Int = Int(floor(cx - rx)) - 1
		let x1: Int = Int(ceil(cx + rx)) + 1
		let y0: Int = Int(floor(cy - ry)) - 1
		let y1: Int = Int(ceil(cy + ry)) + 1
		for yy in y0...y1 {
			for xx in x0...x1 {
				let dx: Double = (Double(xx) + 0.5 - cx) / rx
				let dy: Double = (Double(yy) + 0.5 - cy) / ry
				if dx * dx + dy * dy <= 1.0 { ink(xx, yy, v) }
			}
		}
	}

	/// Filled polygon (even-odd test per pixel centre)
	mutating func inkPoly(_ pts: [(Double, Double)], _ v: UInt32) {
		if pts.count < 3 { return }
		var minX: Double = pts[0].0, maxX: Double = pts[0].0, minY: Double = pts[0].1, maxY: Double = pts[0].1
		for p in pts { minX = min(minX, p.0); maxX = max(maxX, p.0); minY = min(minY, p.1); maxY = max(maxY, p.1) }
		for yy in Int(floor(minY))...Int(ceil(maxY)) {
			for xx in Int(floor(minX))...Int(ceil(maxX)) {
				let px: Double = Double(xx) + 0.5
				let py: Double = Double(yy) + 0.5
				var inside: Bool = false
				var j: Int = pts.count - 1
				for i in 0..<pts.count {
					let a = pts[i]
					let b = pts[j]
					if (a.1 > py) != (b.1 > py) && px < (b.0 - a.0) * (py - a.1) / (b.1 - a.1) + a.0 { inside = !inside }
					j = i
				}
				if inside { ink(xx, yy, v) }
			}
		}
	}

	mutating func inkLine(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ v: UInt32) {
		let n: Int = max(abs(x1 - x0), abs(y1 - y0))
		if n == 0 { ink(x0, y0, v); return }
		for i in 0...n {
			let t: Double = Double(i) / Double(n)
			let xx: Int = Int((Double(x0) + Double(x1 - x0) * t).rounded())
			let yy: Int = Int((Double(y0) + Double(y1 - y0) * t).rounded())
			ink(xx, yy, v)
		}
	}
}

/// The finishing pass every creature goes through, so they all read as one set:
/// - body pixels open to the sky get a warm rim light (two rows on large sprites)
/// - body pixels just above empty space get a cool shadow (`band` rows deep)
/// - a 1px outline in a darkened version of the colour it borders
/// Flat details are left as drawn.
func finishCreature(_ src: PixelBuf, band: Int) -> PixelBuf {
	let w: Int = src.w
	let h: Int = src.h
	let base: [UInt32] = src.px
	var out: [UInt32] = src.px
	func opaque(_ x: Int, _ y: Int) -> Bool {
		if x < 0 || y < 0 || x >= w || y >= h { return false }
		return (base[y * w + x] >> 24) != 0
	}
	for y in 0..<h {
		for x in 0..<w {
			let v: UInt32 = base[y * w + x]
			if (v >> 24) != 0xFF { continue }
			let c: UInt32 = v & 0xFFFFFF
			if !opaque(x, y - 1) { out[y * w + x] = 0xFF000000 | toneL(c); continue }
			if band > 1 && !opaque(x, y - 2) { out[y * w + x] = 0xFF000000 | mixRGB(c, toneL(c), 0.45); continue }
			var k: Int = 1
			while k <= band {
				if !opaque(x, y + k) { out[y * w + x] = 0xFF000000 | toneD(c); break }
				k += 1
			}
		}
	}
	var res: [UInt32] = out
	for y in 0..<h {
		for x in 0..<w {
			if opaque(x, y) { continue }
			var best: UInt32 = 0
			var found: Bool = false
			for (dx, dy) in [(0, 1), (0, -1), (-1, 0), (1, 0)] {
				if !opaque(x + dx, y + dy) { continue }
				let n: UInt32 = base[(y + dy) * w + x + dx] & 0xFFFFFF
				if !found || artLum(n) < artLum(best) { best = n; found = true }
			}
			if found { res[y * w + x] = 0xFF000000 | toneO(best) }
		}
	}
	for i in 0..<res.count where (res[i] >> 24) != 0 { res[i] = 0xFF000000 | (res[i] & 0xFFFFFF) }
	var b: PixelBuf = src
	b.px = res
	return b
}

/// Builds finished frames from parts: each frame lists (rows, dx, dy) drawn in order onto a w x h
/// interior with a 1px margin for the outline
func composeCreature(_ w: Int, _ h: Int, _ pal: [Character: UInt32], _ frames: [[([String], Int, Int)]], band: Int = 0) -> [PixelBuf] {
	var out: [PixelBuf] = []
	for fr in frames {
		var b = PixelBuf(w: w + 2, h: h + 2)
		for p in fr { b.paint(p.0, pal, 1 + p.1, 1 + p.2) }
		out.append(finishCreature(b, band: band > 0 ? band : (b.h <= 16 ? 1 : 2)))
	}
	return out
}

/// How a creature's frames are used beyond the walk cycle (frames 1-2)
struct CreatureAnim {
	/// shown now and then while standing still (grazing, pecking); -1 for none
	var idleAlt: Int = -1
	/// shown while an attack lands; -1 for none
	var attack: Int = -1
	/// 0 on the ground, 1 in the air (slimes, frogs)
	var hop: Bool = false
	/// looping frames for swimmers and fliers
	var cycle: [Int] = []
	/// the frames of the walk in order (two in the older drawings, four in the hand-drawn ones)
	var walk: [Int] = [1, 2]
	/// the frame shown in the air by creatures that hop
	var hopFrame: Int = 1
	/// frames of poses by name ("windup", "strike", "block", "shoot", "front", ...) for creatures that
	/// have them; the older drawings keep their fixed frame numbers instead
	var poses: [String: Int] = [:]

	func pose(_ name: String, _ fallback: Int) -> Int { return poses[name] ?? fallback }

	/// The frame of a walk `t` strides in (a whole cycle takes as long with four frames as with two)
	func walkFrame(_ t: Double) -> Int {
		if walk.isEmpty { return 0 }
		let rate: Double = walk.count > 2 ? Double(walk.count) : 2.0
		return walk[Int(abs(t) * rate) % walk.count]
	}
}

/// A creature's finished frames, how they are used and how large they are drawn
struct CreatureLook {
	var frames: [PixelBuf]
	var anim: CreatureAnim
	/// blocks to an art pixel
	var scale: Double
	/// the row just under the soles and the column of the body's middle, when the drawing says
	/// (otherwise both are taken from the first frame)
	var foot: Int? = nil
	var cx: Double? = nil
	/// true for the hand-drawn pictures of ArtSheet
	var fine: Bool = false
}

// MARK: - Humanoid sprites

enum HandItem { case none, sword, cutlass, pistol, bow }

struct HumanStyle {
	var skin: UInt32 = 0xF1C27D
	var hair: UInt32 = 0x3B2417
	var shirt: UInt32 = 0x8A5A2E
	var sleeve: UInt32 = 0x7A4C24
	var belt: UInt32 = 0xD8B060
	var pants: UInt32 = 0x3A4A6E
	var boots: UInt32 = 0x2A2A30
	var scarf: UInt32 = 0
	var eye: UInt32 = 0x1E1418
	var hat: UInt32 = 0
	/// 0 cap or helmet, 1 bandana, 2 tricorn, 3 horns
	var hatStyle: Int = 0
	var weapon: HandItem = .none
	var weaponColor: UInt32 = 0xD0D4DA
	var shield: UInt32 = 0
	var zombieArms: Bool = false
	var ribs: Bool = false
	var skull: Bool = false
	var beard: UInt32 = 0
	var patch: Bool = false
	var coat: Bool = false
	var tail: Bool = false
}

let humanW: Int = 22
let humanH: Int = 17
let humanOX: Int = 6

/// One humanoid frame: a 10 x 15 figure (head 5, neck 1, torso 3, belt 1, hips 1, legs 4) facing right,
/// with room on the right for a weapon. legs: 0 standing, 1 stride, 2 passing. pose: 0 idle,
/// 1 wind-up, 2 attack, 3 block, 4 shoot.
func humanoidFrame(_ s: HumanStyle, legs: Int, pose: Int) -> PixelBuf {
	var rows: [String] = []
	let hasHat: Bool = s.hat != 0
	if s.skull {
		rows += ["...HHHH...", "..HHHHHH..", "..Hsksks..", "..ssssss..", "...sjsj..."]
	} else if hasHat && s.hatStyle == 1 {
		rows += ["..HHHHH...", ".HHHHHHH..", "H.hssses..", "..ssssss..", "...ssss..."]
	} else if hasHat && s.hatStyle == 2 {
		rows += ["..HHHHH...", "HHHHHHHHH.", "..hsssse..", "..ssssss..", "...ssss..."]
	} else if hasHat && s.hatStyle == 3 {
		rows += ["..H....H..", "..hhhhhh..", "..hsssse..", "..ssssss..", "...ssss..."]
	} else if hasHat {
		rows += ["...HHHH...", "..HHHHHH..", "..HHssse..", "..ssssss..", "...ssss..."]
	} else if s.hair == 0 {
		rows += ["...ssss...", "..ssssss..", "..ssssse..", "..ssssss..", "...ssss..."]
	} else {
		rows += ["...hhhh...", "..hhhhhh..", "..hsssse..", "..ssssss..", "...ssss..."]
	}
	if s.beard != 0 {
		rows[3] = "..sbbbbb.."
		rows[4] = "...bbbb..."
	}
	if s.patch {
		var ch: [Character] = Array(rows[2])
		ch[7] = "k"
		rows[2] = String(ch)
	}
	rows.append(s.scarf != 0 ? "..cccccc.." : "...tttt...")
	rows += [".aattttaa.", ".aattttaa.", ".ssttttss."]
	rows.append("..xxxxxx..")
	rows.append(s.coat ? ".aappppaa." : "..pppppp..")
	if legs == 1 {
		rows += [".pp....pp.", ".pp....pp.", ".pp....pp.", ".oo....oo."]
	} else if legs == 2 {
		rows += ["...pppp...", "...pppp...", "...pppp...", "...oooo..."]
	} else {
		rows += ["..pp..pp..", "..pp..pp..", "..pp..pp..", "..oo..oo.."]
	}
	if s.ribs {
		rows[6] = ".aatgtgaa."
		rows[7] = ".aagtgtaa."
	}
	var pal: [Character: UInt32] = [:]
	pal["h"] = inkS(s.hair)
	pal["H"] = inkS(s.hat)
	pal["s"] = inkS(s.skin)
	pal["e"] = inkF(s.eye)
	pal["k"] = inkF(0x1E1418)
	pal["t"] = inkS(s.shirt)
	pal["a"] = inkS(s.sleeve)
	pal["x"] = inkS(s.belt)
	pal["p"] = inkS(s.pants)
	pal["o"] = inkS(s.boots)
	pal["c"] = inkS(s.scarf)
	pal["b"] = inkS(s.beard)
	pal["g"] = inkF(0x6A6A70)
	pal["j"] = inkF(0x3A3040)
	var cv = PixelBuf(w: humanW, h: humanH)
	cv.paint(rows, pal, humanOX, 1)
	// arms: remove the right arm for poses that draw their own
	if pose >= 2 || s.zombieArms {
		for y in 7...9 { cv.clear(13, y); cv.clear(14, y) }
	}
	if s.zombieArms {
		// arms reach forward; raised a pixel in the attack pose
		let lift: Int = pose == 2 ? 1 : 0
		for i in 0..<6 {
			let c: UInt32 = i < 4 ? s.sleeve : s.skin
			cv.ink(13 + i, 7 - lift, inkS(c))
			cv.ink(13 + i, 8 - lift, inkS(c))
		}
	}
	if s.tail {
		cv.ink(6, 12, inkS(s.skin)); cv.ink(5, 13, inkS(s.skin)); cv.ink(4, 13, inkS(s.skin)); cv.ink(3, 12, inkS(s.skin))
		cv.ink(3, 11, inkF(0x3A1414))
	}
	if s.zombieArms { return finishCreature(cv, band: 1) }
	let bl: UInt32 = inkF(s.weaponColor)
	let blh: UInt32 = inkF(shadeRGB(s.weaponColor, 1.3))
	let gold: UInt32 = inkF(0xC8A040)
	switch s.weapon {
	case .sword, .cutlass:
		if pose == 0 {
			cv.inkLine(15, 2, 15, 8, bl)
			cv.ink(15, 1, blh)
			cv.inkRect(14, 8, 3, 1, gold)
			cv.ink(15, 9, inkF(0x6A4220))
		} else if pose == 1 {
			cv.inkRect(13, 6, 3, 2, inkS(s.sleeve))
			cv.inkLine(14, 6, 11, 1, bl)
			cv.inkLine(15, 6, 12, 1, blh)
			cv.inkRect(14, 6, 2, 1, gold)
		} else if pose == 2 {
			cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
			cv.inkRect(15, 8, 1, 1, inkS(s.skin))
			cv.inkRect(16, 6, 1, 5, gold)
			cv.inkLine(17, 8, 20, 8, bl)
			cv.inkLine(17, 7, 20, 7, blh)
			if s.weapon == .cutlass { cv.ink(20, 9, bl); cv.ink(20, 6, blh) }
		}
	case .pistol:
		if pose == 4 || pose == 2 {
			cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
			cv.inkRect(16, 7, 4, 2, inkF(0x4A4A54))
			cv.inkRect(16, 9, 1, 2, inkF(0x8A5A2A))
			cv.ink(20, 7, inkF(0xFFE080))
		}
	case .bow:
		let wood: UInt32 = inkF(s.weaponColor)
		let str: UInt32 = inkF(0xE8E0D0)
		if pose == 4 || pose == 2 {
			// arm out, string drawn back to the cheek, arrow nocked
			cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
			cv.inkLine(17, 3, 18, 5, wood)
			cv.inkLine(18, 5, 18, 10, wood)
			cv.inkLine(18, 10, 17, 12, wood)
			cv.inkLine(17, 3, 14, 7, str)
			cv.inkLine(14, 8, 17, 12, str)
			cv.inkLine(14, 8, 20, 8, inkF(0xB08A5A))
			cv.ink(21, 8, inkF(0xD0D0D8))
		} else {
			// carried at the side
			cv.inkLine(15, 4, 16, 6, wood)
			cv.inkLine(16, 6, 16, 10, wood)
			cv.inkLine(16, 10, 15, 12, wood)
			cv.inkLine(15, 5, 15, 11, str)
		}
	case .none:
		break
	}
	if s.shield != 0 && pose == 3 {
		let sh: UInt32 = s.shield
		cv.inkRect(13, 7, 3, 2, inkS(s.sleeve))
		cv.inkRect(15, 4, 5, 10, inkF(shadeRGB(sh, 0.6)))
		cv.inkRect(16, 5, 3, 8, inkF(sh))
		cv.inkRect(17, 7, 1, 4, inkF(shadeRGB(sh, 1.4)))
		cv.inkRect(16, 5, 3, 1, inkF(shadeRGB(sh, 1.25)))
	} else if s.shield != 0 {
		// shield worn on the back arm side, low
		cv.inkRect(8, 8, 2, 5, inkF(shadeRGB(s.shield, 0.7)))
		cv.inkRect(8, 9, 1, 3, inkF(s.shield))
	}
	return finishCreature(cv, band: 1)
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
	return out
}

// MARK: - Character styles

/// The colours and styles a player picks their look from (the character screen). The first of each is
/// the player's own drawing: black hair, a dark red T-shirt, navy trousers, no scarf (scarf colour 0
/// is none). A saved choice is a place in these lists, so new ones go at the end; the style lists
/// follow the drawings (player_hair_0 ... in ArtSheet).
let hairChoices: [UInt32] = [0x0A0A14, 0xC8501E, 0xE8D080, 0x6A3A8A, 0x3A8A5A, 0x6A4428, 0x8A8A94, 0xD8D0C0, 0x2A3A6A, 0xA02A2A]
let scarfChoices: [UInt32] = [0, 0xD03A3A, 0x2EB8B0, 0xF0F0F0, 0xE060A8, 0xE8C03A]
let shirtChoices: [UInt32] = [0x4B2A31, 0x2E3E5E, 0x3E5A34, 0x8A6A2A, 0x5A5A62, 0xD8D2C4, 0x1E1E24, 0x2E6A6A, 0x5A3A6A, 0x8A4A2A]
let pantsChoices: [UInt32] = [0x25385B, 0x1E1E24, 0x6A5A42, 0x4A3226, 0x4A4C54, 0x2E4A32, 0x3A4E7A]
let hairStyleNames: [String] = ["Short", "Spiky", "Long", "Ponytail", "Buzz", "Curly"]
let shirtStyleNames: [String] = ["T-shirt", "Long sleeves", "Tank top", "Hoodie"]
let pantsStyleNames: [String] = ["Trousers", "Shorts", "Cropped"]

func playerStyle(hairIdx: Int, scarfIdx: Int, head: Tier?, chest: Tier?, legs: Tier?) -> HumanStyle {
	var s = HumanStyle()
	s.skin = 0xC19573
	s.hair = hairChoices[clampI(hairIdx, 0, hairChoices.count - 1)]
	s.scarf = scarfChoices[clampI(scarfIdx, 0, scarfChoices.count - 1)]
	s.shirt = 0x4B2A31
	s.sleeve = 0xAD7757
	s.belt = 0x311C24
	s.pants = 0x25385B
	s.boots = 0x0B0B15
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

/// 0 green zombie, 1 desert husk, 2 drowned
func zombieStyle(_ variant: Int) -> HumanStyle {
	let v: Int = variant >= 0 && variant <= 2 ? variant : 0
	var s = HumanStyle()
	s.skin = [0x76B060, 0xC8B074, 0x6EA4A0][v]
	s.hair = [0x2E5A2E, 0x8A7A4A, 0x2E4A5A][v]
	s.shirt = [0x3A8A8A, 0xA08A5A, 0x4A6A50][v]
	s.sleeve = shadeRGB(s.shirt, 0.85)
	s.belt = 0x3A3030
	s.pants = [0x34407A, 0x7A6A4A, 0x3A4A5A][v]
	s.boots = 0x3A3438
	s.eye = 0xE03A2A
	s.zombieArms = true
	return s
}

/// The Skeleton Knight: a skull under an iron helm, ribs showing, sword and shield
func skeletonStyle() -> HumanStyle {
	var s = HumanStyle()
	s.skull = true
	s.skin = 0xEAE4D2
	s.hair = 0
	s.hat = 0x8C94A2
	s.shirt = 0xDCD6C4
	s.sleeve = 0xD0CAB6
	s.belt = 0x6A5A4A
	s.pants = 0xD0CAB6
	s.boots = 0x8C94A2
	s.weapon = .sword
	s.weaponColor = 0xB8C0CC
	s.shield = 0x8A5A2E
	s.ribs = true
	return s
}

/// The Skeleton Archer: a hooded skull with a longbow and no shield
/// The Bow Zombie, which took the skeleton archer's place: a zombie in a ragged hunter's hood, bow in hand
func zombieArcherStyle() -> HumanStyle {
	var s = zombieStyle(2)
	s.zombieArms = false
	s.hat = 0x4A3A28
	s.shirt = 0x5A6A3A
	s.sleeve = shadeRGB(0x5A6A3A, 0.85)
	s.belt = 0x5A3A20
	s.weapon = .bow
	s.weaponColor = 0x8A5A2A
	return s
}

func skeletonArcherStyle() -> HumanStyle {
	var s = skeletonStyle()
	s.hat = 0x3E4A36
	s.shield = 0
	s.weapon = .bow
	s.weaponColor = 0x8A5A2A
	s.belt = 0x5A4A30
	return s
}

/// Deckhands wear a bandana and an eye patch; the captain a tricorn, a long coat and a beard
func pirateStyle(_ captain: Bool) -> HumanStyle {
	var s = HumanStyle()
	s.skin = 0xE0B080
	s.hair = 0x2A1A10
	s.boots = 0x2A2024
	s.weapon = .cutlass
	s.weaponColor = 0xC8CCD4
	if captain {
		s.hat = 0x2A2A3A
		s.hatStyle = 2
		s.shirt = 0x9A2E2E
		s.sleeve = 0x7A2222
		s.belt = 0xD8B060
		s.pants = 0x2E2E3E
		s.coat = true
		s.beard = 0x2A1A10
	} else {
		s.hat = 0xC83A34
		s.hatStyle = 1
		s.shirt = 0xEDEAE0
		s.sleeve = 0xC84A44
		s.belt = 0x3A2A20
		s.pants = 0x6A5440
		s.patch = true
	}
	return s
}

func pirateGunnerStyle() -> HumanStyle {
	var s = pirateStyle(false)
	s.weapon = .pistol
	s.shirt = 0x3E62A0
	s.sleeve = 0x324F84
	s.hat = 0x2E4E86
	s.patch = false
	return s
}

/// The Umbral Imp: red skin, horns, glowing eyes, clawed arms and a tail
func impStyle() -> HumanStyle {
	var s = HumanStyle()
	s.skin = 0xD04A34
	s.hair = 0x6A1414
	s.hat = 0x3A1414
	s.hatStyle = 3
	s.shirt = 0x5A1E22
	s.sleeve = 0x4A1418
	s.belt = 0xFFB030
	s.pants = 0x5A1E22
	s.boots = 0x3A1010
	s.eye = 0xFFE040
	s.zombieArms = true
	s.tail = true
	return s
}

// MARK: - Boss sprites (shapes plus hand-placed details, through the same finishing pass)

/// Ursavor, the bear boss: a hulking bear with bone plates along its spine, a scarred eye and an amber glare.
/// Frames: 0-1 walk, 2 rear up (roar / slam wind-up), 3 swipe.
func spriteBearBoss() -> [PixelBuf] {
	let W: Int = 51
	let H: Int = 34
	let fur: UInt32 = 0x5E4230
	let far: UInt32 = 0x46301F
	let muz: UInt32 = 0xA8865E
	let bone: UInt32 = inkF(0xE6DAC0)
	let boneD: UInt32 = inkF(0xA89878)
	let claw: UInt32 = inkF(0xF2ECDC)
	let eye: UInt32 = inkF(0xFFB02E)
	let gnd: Int = H
	var out: [PixelBuf] = []

	func paw(_ b: inout PixelBuf, _ x: Int, _ top: Int, _ c: UInt32, _ claws: Bool) {
		b.inkRect(x, top, 6, gnd - top - 1, inkS(c))
		b.inkRect(x - 1, gnd - 2, 8, 2, inkS(c))
		if claws { b.ink(x + 2, gnd, claw); b.ink(x + 4, gnd, claw); b.ink(x + 6, gnd, claw) }
	}

	for f in 0..<2 {
		var b = PixelBuf(w: W + 2, h: H + 3)
		let s: Int = f == 0 ? 2 : -2
		let bob: Int = f == 0 ? 0 : 1
		let bd: Double = Double(bob)
		paw(&b, 15 - s, 24, far, false)
		paw(&b, 34 + s, 24, far, false)
		b.inkEllipse(9.5, 19 + bd, 8.5, 8.5, inkS(fur))                    // rump
		b.inkEllipse(22, 18 + bd, 18, 10, inkS(fur))                       // body
		b.inkEllipse(30, 13.5 + bd, 11, 9, inkS(fur))                      // shoulder hump
		b.inkEllipse(24, 25.5 + bd, 14, 2.2, inkF(toneD(fur)))             // shadowed belly
		paw(&b, 9 + s, 25, fur, true)
		paw(&b, 29 - s, 25, fur, true)
		// bone plates along the spine
		let plates: [(Double, Double, Double)] = [(7, 12, 3), (12, 9.5, 4), (17.5, 8, 5), (23, 6.5, 5.5), (28.5, 5.5, 6), (34, 6, 5)]
		for p in plates {
			let x: Double = p.0
			let top: Double = p.1 + bd
			b.inkPoly([(x - 1.8, top + 1.5), (x + 0.6, top - p.2), (x + 2.2, top + 1.5)], bone)
			b.ink(Int(x) - 1, Int(top) + 1, boneD)
			b.ink(Int(x) + 1, Int(top) + 1, boneD)
		}
		let hy: Int = 19 + bob
		let hyd: Double = Double(hy)
		let hx: Int = 1
		let hxd: Double = Double(hx)
		let head: UInt32 = mixRGB(fur, muz, 0.2)                            // a shade lighter than the body
		b.inkEllipse(37.5 + hxd, hyd - 6.2, 2.3, 2.3, inkS(far))            // ears
		b.inkEllipse(43 + hxd, hyd - 6.8, 2.3, 2.3, inkS(far))
		b.inkEllipse(41 + hxd, hyd, 7.4, 6.6, inkS(head))                   // head
		b.inkEllipse(46.6 + hxd, hyd + 2.4, 3.8, 2.9, inkS(muz))            // muzzle
		b.inkRect(49 + hx, hy, 2, 2, inkF(0x1E1418))                        // nose
		b.inkLine(43 + hx, hy + 4, 49 + hx, hy + 4, inkF(0x3A2418))         // mouth
		b.ink(45 + hx, hy + 5, claw)
		b.ink(48 + hx, hy + 5, claw)
		b.inkRect(43 + hx, hy - 2, 2, 1, eye)
		b.ink(45 + hx, hy - 2, inkF(0x2A1000))
		b.inkLine(42 + hx, hy - 3, 46 + hx, hy - 4, inkF(0x2C1E16))         // brow
		b.inkLine(42 + hx, hy - 5, 45 + hx, hy + 1, inkF(0xC8A888))         // scar
		out.append(b)
	}

	for pose in 0..<2 {
		var b = PixelBuf(w: W + 2, h: H + 3)
		paw(&b, 15, 27, far, false)
		paw(&b, 25, 27, fur, true)
		if pose == 0 {
			// far arm raised
			b.inkPoly([(17, 15), (21, 14), (17, 3), (13, 4)], inkS(far))
			b.inkEllipse(15, 3.5, 3, 2.6, inkS(far))
			b.ink(13, 0, claw); b.ink(15, 0, claw); b.ink(17, 0, claw)
		} else {
			b.inkPoly([(17, 15), (21, 15), (20, 25), (16, 25)], inkS(far))
		}
		b.inkEllipse(22, 25, 10, 8.5, inkS(fur))                            // belly
		b.inkEllipse(23, 16, 8.5, 8.5, inkS(fur))                           // chest
		b.inkEllipse(23, 31.5, 8, 1.8, inkF(toneD(fur)))
		// plates down the back
		for k in 0..<5 {
			let kd: Double = Double(k)
			let py: Double = 9 + kd * 4.0
			let px: Double = 15.5 - (k < 3 ? kd * 0.9 : (4 - kd) * 0.9 + 1.0)
			b.inkPoly([(px + 1.5, py - 1.7), (px - 3.5, py - 0.3), (px + 1.5, py + 1.7)], bone)
			b.ink(Int(px), Int(py), boneD)
		}
		b.inkEllipse(25.5, 2.8, 2.2, 2.2, inkS(far))
		b.inkEllipse(31, 2.4, 2.2, 2.2, inkS(far))
		b.inkEllipse(29, 8.5, 6.8, 6, inkS(fur))                            // head, roaring
		b.inkEllipse(34.2, 11, 3.6, 2.9, inkS(muz))
		b.inkRect(36, 7, 2, 2, inkF(0x1E1418))
		b.inkRect(32, 11, 5, 3, inkF(0x5A0E10))                             // open mouth
		b.ink(33, 11, claw); b.ink(35, 11, claw); b.ink(34, 13, claw)
		b.inkRect(30, 5, 2, 1, eye)
		b.ink(32, 5, inkF(0x2A1000))
		b.inkLine(29, 4, 33, 3, inkF(0x2C1E16))
		b.inkLine(29, 2, 32, 7, inkF(0xC8A888))
		if pose == 0 {
			// near arm raised high
			b.inkPoly([(26, 17), (31, 18), (40, 5), (36, 3)], inkS(fur))
			b.inkEllipse(39, 3.6, 3.3, 2.8, inkS(fur))
			b.ink(37, 0, claw); b.ink(39, 0, claw); b.ink(41, 0, claw)
		} else {
			// swipe: arm thrown forward, claws spread
			b.inkPoly([(26, 15), (45, 13), (46, 19), (27, 21)], inkS(fur))
			b.inkEllipse(46, 16, 3.6, 4, inkS(fur))
			b.inkLine(49, 12, 51, 11, claw)
			b.inkLine(50, 15, 52, 15, claw)
			b.inkLine(50, 18, 52, 19, claw)
			b.inkLine(49, 20, 50, 22, claw)
		}
		out.append(b)
	}
	return out.map { finishCreature(padBuf($0), band: 2) }
}

/// Tyrannax the Bonecrown: a dark olive hunter with a crown of bone spikes, a striped back and a pale throat.
/// Frames: 0-1 walk, 2 bite (jaw open, head lunging).
func spriteTRex() -> [PixelBuf] {
	let W: Int = 62
	let H: Int = 37
	let skin: UInt32 = 0x5A8A42
	let far: UInt32 = 0x426A32
	let stripe: UInt32 = inkF(0x34522A)
	let belly: UInt32 = inkS(0xDCD4A0)
	let bone: UInt32 = inkF(0xE8DEC4)
	let boneD: UInt32 = inkF(0xAA9C7C)
	let claw: UInt32 = inkF(0xF2ECDC)
	let eye: UInt32 = inkF(0xFFC23A)
	let gnd: Int = H
	let gd: Double = Double(gnd)
	var out: [PixelBuf] = []

	func leg(_ b: inout PixelBuf, _ hipX: Double, _ step: Double, _ c: UInt32, _ near: Bool) {
		b.inkEllipse(hipX, 23, 5.5, 7, inkS(c))                                                       // thigh
		let footX: Double = hipX + step
		let shin: UInt32 = near ? inkF(toneD(c)) : inkS(c)
		b.inkPoly([(hipX - 2.5, 26), (hipX + 2.5, 26), (footX + 1.8, gd - 2), (footX - 1.8, gd - 2)], shin)
		b.inkRect(Int(footX) - 3, gnd - 2, 8, 2, shin)
		b.ink(Int(footX) + 5, gnd - 1, claw)
		b.ink(Int(footX) + 2, gnd - 1, claw)
	}

	for f in 0..<3 {
		var b = PixelBuf(w: W + 2, h: H + 3)
		let step: Double = f == 0 ? 2.5 : (f == 1 ? -2.5 : 0)
		let bob: Double = f == 1 ? 1 : 0
		let bite: Bool = f == 2
		leg(&b, 30, -step, far, false)
		b.inkPoly([(18, 10 + bob), (0, 18 + bob), (1, 20 + bob), (19, 24 + bob)], inkS(skin))            // tail
		b.inkPoly([(9, 16 + bob), (0, 18 + bob), (1, 20 + bob), (10, 20 + bob)], inkF(toneD(skin)))
		b.inkEllipse(26, 17 + bob, 12, 7.5, inkS(skin))                                                 // body
		b.inkPoly([(24, 23 + bob), (35, 21.5 + bob), (40, 17 + bob), (37, 24 + bob), (25, 25.5 + bob)], belly)
		let hx: Double = bite ? 2 : 0
		let hy: Double = bite ? 2 : 0
		let hxi: Int = Int(hx)
		let yo: Double = bob + hy
		let yoi: Int = Int(yo)
		b.inkPoly([(32, 13 + bob), (40, 6 + yo), (44, 13 + yo), (36, 21 + bob)], inkS(skin))               // neck
		b.inkEllipse(47 + hx, 9 + yo, 8, 5.5, inkS(skin))                                                // skull
		b.inkPoly([(47 + hx, 5 + yo), (61, 7 + yo), (61, 11 + yo), (47 + hx, 12 + yo)], inkS(skin))      // snout
		b.ink(59, 8 + yoi, stripe)                                                                       // nostril
		let jy: Double = bite ? 16 : 12
		b.inkPoly([(41 + hx, 12 + yo), (60, jy - 1 + yo), (59, jy + 1.5 + yo), (42 + hx, 16 + yo)], inkF(toneD(skin)))   // lower jaw
		b.inkPoly([(41 + hx, 13.5 + yo), (52, jy + 0.5 + yo), (52, jy + 2 + yo), (42 + hx, 17 + yo)], belly)            // throat
		if bite {
			b.inkPoly([(48 + hx, 11.5 + yo), (61, 11.5 + yo), (59, 14.5 + yo), (49 + hx, 14 + yo)], inkF(0x6A1420))
		}
		var tx: Int = 50 + hxi
		while tx < 61 {
			b.ink(tx, 11 + yoi, claw)
			b.ink(tx + 1, (bite ? Int(jy) - 1 : 12) + yoi, claw)
			tx += 3
		}
		b.inkRect(48 + hxi, 7 + yoi, 2, 1, eye)
		b.ink(49 + hxi, 7 + yoi, inkF(0x201000))
		b.inkLine(45 + hxi, 6 + yoi, 51 + hxi, 5 + yoi, stripe)                                          // brow ridge
		// crown of bone spikes
		for k in 0..<5 {
			let kd: Double = Double(k)
			let cx: Double = 41.5 + hx + kd * 2.4
			let tip: Double = 1.2 + yo - (k == 2 ? 1 : 0)
			b.inkPoly([(cx - 1.2, 4.8 + yo - kd * 0.15), (cx, tip), (cx + 1.2, 4.8 + yo - kd * 0.15)], bone)
			b.ink(Int(cx), Int(4.4 + yo), boneD)
		}
		// back stripes
		let bobi: Int = Int(bob)
		for k in 0..<6 {
			let sx: Int = 15 + k * 4
			b.inkLine(sx, 10 + bobi + abs(k - 3) / 2, sx - 2, 14 + bobi + abs(k - 3) / 2, stripe)
		}
		// little arm
		b.inkLine(39, 19 + bobi, 42, 21 + bobi, inkF(toneD(skin)))
		b.ink(43, 21 + bobi, claw)
		leg(&b, 23, step, skin, true)
		out.append(b)
	}
	return out.map { finishCreature(padBuf($0), band: 2) }
}

// MARK: - Creature table

/// The name a creature's drawing has in ArtSheet ("zombie", "zombie_1", ...)
func creatureSheetName(_ k: MobKind, _ v: Int) -> String {
	let base: String = String(describing: k)
	return v > 0 ? joinText(base, "_", String(v)) : base
}

/// A creature's look: its hand-drawn picture when it has one, otherwise the older one made in code
func creatureLook(_ k: MobKind, _ v: Int) -> CreatureLook {
	let kind: MobKind = k == .custom ? .zombie : k
	let vv: Int = k == .custom ? 0 : v
	if let l = CreatureSheet.look(creatureSheetName(kind, vv)) { return l }
	let old: ([PixelBuf], CreatureAnim) = olderCreatureArt(kind, vv)
	return CreatureLook(frames: old.0.map { gradeBuf($0) }, anim: old.1, scale: creatureScale)
}

/// Finished frames and frame roles for every creature
func creatureArt(_ k: MobKind, _ v: Int) -> ([PixelBuf], CreatureAnim) {
	let l: CreatureLook = creatureLook(k, v)
	return (l.frames, l.anim)
}

/// The older drawings (8 pixels to a block): what a creature looks like until it is redrawn by hand,
/// and what a mod's repaint made before the redrawing still follows (frame order and size)
func olderCreatureArt(_ k: MobKind, _ v: Int) -> ([PixelBuf], CreatureAnim) {
	var a = CreatureAnim()
	switch k {
	case .pig: a.idleAlt = 3; return (spritePig(), a)
	case .cow: a.idleAlt = 3; return (spriteCow(), a)
	case .sheep: a.idleAlt = 3; return (v == 1 ? spriteSheepShorn() : spriteSheepWool(), a)
	case .chicken: a.idleAlt = 3; return (spriteChicken(), a)
	case .crow: a.cycle = [0, 1, 2, 1]; return (spriteCrow(), a)
	case .giraffe: a.idleAlt = 3; return (spriteGiraffe(), a)
	case .frog: a.hop = true; return (spriteFrog(), a)
	case .fish: a.cycle = [0, 1]; return (spriteFish(), a)
	case .elephant: a.attack = 3; return (spriteElephant(), a)
	case .bear: a.attack = 3; return (spriteBrownBear(), a)
	case .grizzly: a.attack = 3; return (spriteGrizzly(), a)
	case .polarBear: a.attack = 3; return (spritePolarBear(), a)
	case .tiger: a.attack = 3; return (spriteTiger(), a)
	case .wolf: a.attack = 3; return (v == 1 ? spriteDog() : spriteWildWolf(), a)
	case .cat: return (spriteCat(), a)
	case .zombie: return (humanoidFrames(zombieStyle(v)), a)
	case .skeleton: return (humanoidFrames(skeletonStyle()), a)
	case .slime: a.hop = true; a.attack = 2; return (spriteGreenSlime(), a)
	case .bat: a.cycle = [0, 1, 2, 1]; return (spriteCaveBat(), a)
	case .scorpion: a.attack = 3; return (spriteScorpion(), a)
	case .wraith: a.cycle = [0, 1]; a.attack = 2; return (spriteWraith(), a)
	// a retired kind (villagers are gone): kept so saved creature numbers stay the same
	case .villager: return (humanoidFrames(zombieStyle(v)), a)
	case .pirate: return (humanoidFrames(pirateStyle(false)), a)
	case .pirateGunner: return (humanoidFrames(pirateGunnerStyle()), a)
	case .pirateCaptain: return (humanoidFrames(pirateStyle(true)), a)
	case .imp: return (humanoidFrames(impStyle()), a)
	case .emberSlime: a.hop = true; a.attack = 2; return (spriteEmberSlime(), a)
	case .cinderBat: a.cycle = [0, 1, 2, 1]; return (spriteCinderBat(), a)
	case .bearBoss: return (spriteBearBoss(), a)
	case .rex: return (spriteTRex(), a)
	case .crawler: a.attack = 3; return (spriteCaveCrawler(), a)
	case .golem: return (spriteStoneGolem(), a)
	case .archer: return (humanoidFrames(zombieArcherStyle()), a)
	case .sentinel: a.cycle = [0, 1]; return (spriteCrystalSentinel(), a)
	case .mimic: return (spriteMimic(), a)
	case .warden: return (spriteHollowWarden(), a)
	case .custom: return olderCreatureArt(.zombie, 0)
	}
}

// ===== p05e_newcreatures =====

// MARK: - Sprites for the cave crawler, stone golem, crystal sentinel, mimic and Hollow Warden

/// Cave Crawler: a low, many-legged hunter with a red eye cluster. Frames: 0 idle, 1-2 scuttle, 3 pounce.
func spriteCaveCrawler() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x6A5078), "d": inkS(0x4A3858), "e": inkF(0xFF5A4A), "E": inkF(0xFFB0A0),
									"l": inkF(0x2E2238), "f": inkF(0xE8E0C8), "s": inkF(0x8A6A9A)]
	let body: [String] = [
		"....dbbbd...",
		"..dbbsbsbbb.",
		".dbbbbbbbbeE",
		"..dbdbdbbbef",
	]
	let legs0: [String] = [
		".l.l..l.l.l.",
		"l..l..l..l.l",
	]
	let legs1: [String] = [
		"..l.l.l..l..",
		".l...l..l..l",
	]
	let legs2: [String] = [
		".ll..l.ll...",
		"l...l..l..ll",
	]
	let pounceBody: [String] = [
		"...dbbbd....",
		".dbbsbsbbbb.",
		"dbbbbbbbbbeE",
		".dbdbdbbbbef",
	]
	let pounceLegs: [String] = [
		"l.l......lll",
		".l.........l",
	]
	return composeCreature(12, 6, pal, [
		[(body, 0, 0), (legs0, 0, 4)],
		[(body, 0, 0), (legs1, 0, 4)],
		[(body, 0, 0), (legs2, 0, 4)],
		[(pounceBody, 0, 0), (pounceLegs, 0, 4)],
	])
}

/// Stone Golem: a hulking boulder with glowing eyes, moss on its shoulders and a crystal set in its
/// chest. Frames: 0 idle, 1-2 walk, 3 fists raised, 4 slam, 5 throw.
func spriteStoneGolem() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x6E6A66), "G": inkS(0x8A8682), "s": inkS(0x7A7672), "S": inkS(0x96928C),
									"e": inkF(0x7AF8F0), "m": inkS(0x5E8A3E), "c": inkF(0x8AF0E8), "k": inkF(0x4A4644), "a": inkS(0x6A6662)]
	let head: [String] = [
		"....gggggg....",
		"...gGGGGGGg...",
		"...gGeGGeGg...",
		"...gGGGGGGg...",
		"....gkkkkg....",
	]
	let torso: [String] = [
		"..mmsssssmm...",
		".msSSSSSSSSsm.",
		".sSSSSSSSSSSs.",
		".sSSSSccSSSSs.",
		".sSSSSckSSSSs.",
		"..sSSSSSSSSs..",
		"...ssssssss...",
	]
	let armsDown: [String] = [
		"aa..........aa",
		"aa..........aa",
		"aaa........aaa",
		"aaa........aaa",
		".aa........aa.",
	]
	let legsA: [String] = [
		"...sss..sss...",
		"...sss..sss...",
		"..ssss..ssss..",
		"..kkkk..kkkk..",
	]
	let legsB: [String] = [
		"..sss....sss..",
		"..sss....sss..",
		".ssss....ssss.",
		".kkkk....kkkk.",
	]
	let legsC: [String] = [
		"....ssssss....",
		"....ss..ss....",
		"...sss..sss...",
		"...kkk..kkk...",
	]
	let armsUp: [String] = [
		"aa..........aa",
		"aaa........aaa",
		"aaa........aaa",
		".aa........aa.",
		"..a........a..",
	]
	let armsSlam: [String] = [
		"...........aaa",
		"..........aaaa",
		"..........aaaa",
		"...........aaa",
	]
	let rock: [String] = [
		"...........kk.",
		"..........kggk",
		"..........kggk",
		"...........kk.",
	]
	return composeCreature(14, 20, pal, [
		[(head, 0, 0), (torso, 0, 5), (armsDown, 0, 6), (legsA, 0, 12), (["....ssssss...."], 0, 11)],
		[(head, 0, 0), (torso, 0, 5), (armsDown, 0, 6), (legsB, 0, 12), (["....ssssss...."], 0, 11)],
		[(head, 0, 0), (torso, 0, 5), (armsDown, 0, 6), (legsC, 0, 12), (["....ssssss...."], 0, 11)],
		[(armsUp, 0, 0), (head, 0, 1), (torso, 0, 6), (legsA, 0, 13), (["....ssssss...."], 0, 12)],
		[(head, 0, 2), (torso, 0, 7), (armsSlam, 0, 13), (legsB, 0, 14), (["....ssssss...."], 0, 13)],
		[(rock, 0, 0), (["...........aa.", "...........aa."], 0, 4), (head, 0, 1), (torso, 0, 6), (armsDown, 0, 7), (legsA, 0, 13), (["....ssssss...."], 0, 12)],
	])
}

/// Crystal Sentinel: a floating construct of crystal around a bright core, with shards orbiting it.
/// Frames: 0-1 hovering, 2 charging, 3 striking.
func spriteCrystalSentinel() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["c": inkS(0x2E8E9A), "C": inkS(0x5ECAD2), "H": inkS(0xA8F0F0), "W": inkF(0xF0FFFF),
									"O": inkF(0xFFFFFF), "o": inkF(0x9AF8F0), "k": inkF(0x1E5A66)]
	let core: [String] = [
		".....cc.....",
		"....cHCc....",
		"...cHCCCc...",
		"...cWkWCc...",
		"...cCCCCc...",
		"....cCCc....",
		"............",
		"....cCCc....",
		"...cHooCc...",
		"...cCOOCc...",
		"...cCooCc...",
		"....cCCc....",
		".....cc.....",
		"......c.....",
	]
	let shardsA: [String] = [
		".c........c.",
		"cC........Cc",
		".c........c.",
	]
	let shardsB: [String] = [
		"............",
		".c........c.",
		"cC........Cc",
		".c........c.",
	]
	let below: [String] = [".....cc.....", "......c....."]
	let chargeCore: [String] = [
		"...cHOOCc...",
		"...cOOOOc...",
		"...cHOOCc...",
	]
	let strikeShards: [String] = [
		"..........cC",
		"...........c",
		"..........cC",
	]
	return composeCreature(12, 17, pal, [
		[(core, 0, 0), (shardsA, 0, 7), (below, 0, 15)],
		[(core, 0, 0), (shardsB, 0, 7), (below, 0, 14)],
		[(core, 0, 0), (chargeCore, 0, 8), (["c..........c", "Cc........cC", "c..........c"], 0, 6), (below, 0, 15)],
		[(core, 0, 0), (chargeCore, 0, 8), (strikeShards, 0, 7), (below, 0, 15)],
	])
}

/// Mimic: closed, it is a plain wooden chest; open, a mouthful of teeth. Frames: 0 closed, 1-2 hopping
/// with the lid ajar, 3 biting wide.
func spriteMimic() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0x8F6732), "d": inkS(0xB98A4E), "g": inkF(0xF5D142), "t": inkF(0xF4F0E0),
									"k": inkF(0x2A1010), "r": inkF(0xD04A5A), "e": inkF(0xFFE040)]
	let closed: [String] = [
		"..........",
		"..........",
		"wwwwwwwwww",
		"wddddddddw",
		"wwwwgwwwww",
		"wddddddddw",
		"wddddddddw",
		"wwwwwwwwww",
	]
	let ajar: [String] = [
		"..........",
		"wwwwwwwwww",
		"wddddddeew",
		"wtkttkttkw",
		"kkkkkkkrrk",
		"wtttkttttw",
		"wddddddddw",
		"wwwwwwwwww",
	]
	let wide: [String] = [
		"wwwwwwwww.",
		"wdddddeew.",
		"wtktktktw.",
		"kk.......k",
		"kkkkkkrrrk",
		"wttkttkttw",
		"wddddddddw",
		"wwwwwwwwww",
	]
	return composeCreature(10, 8, pal, [
		[(closed, 0, 0)],
		[(ajar, 0, 0)],
		[(ajar, 0, 0)],
		[(wide, 0, 0)],
	])
}

/// The Hollow Warden: an empty suit of armour under a ragged hood, two violet lights for eyes, carrying a
/// great scythe. Frames: 0-1 hovering, 2 scythe drawn back, 3 sweep, 4 casting.
func spriteHollowWarden() -> [PixelBuf] {
	let W: Int = 30
	let H: Int = 42
	let cloak: UInt32 = 0x34283E
	let cloakHi: UInt32 = 0x4A3A58
	let iron: UInt32 = 0x5C5A6E
	let ironHi: UInt32 = 0x8A88A0
	let hood: UInt32 = 0x2A2034
	let eye: UInt32 = 0xE0B0FF
	let rune: UInt32 = 0xB070FF
	let shaft: UInt32 = 0x8A6A4A
	let blade: UInt32 = 0xD8DCE8
	let edge: UInt32 = 0x9A9EB0
	func base(_ sway: Int) -> PixelBuf {
		var b = PixelBuf(w: W + 2, h: H + 2)
		let ox: Int = 1
		let oy: Int = 1
		// cloak: widening from the shoulders to a ragged hem
		for y in 12..<38 {
			let half: Int = 5 + (y - 12) / 3
			let cx: Int = 13 + ox
			for x in (cx - half)...(cx + half) { b.ink(x, y + oy, inkS(cloak)) }
			b.ink(cx - half + 1, y + oy, inkS(cloakHi))
		}
		for x in 4..<24 {
			let len: Int = (x + sway) % 3 == 0 ? 3 : ((x + sway) % 3 == 1 ? 1 : 2)
			for k in 0..<len where 38 + k < H { b.ink(x + ox, 38 + k + oy, inkS(cloak)) }
		}
		// pauldrons and breastplate
		b.inkRect(6 + ox, 11 + oy, 6, 3, inkS(iron))
		b.inkRect(15 + ox, 11 + oy, 6, 3, inkS(iron))
		b.inkRect(7 + ox, 11 + oy, 4, 1, inkS(ironHi))
		b.inkRect(16 + ox, 11 + oy, 4, 1, inkS(ironHi))
		b.inkRect(10 + ox, 14 + oy, 7, 8, inkS(iron))
		b.inkRect(11 + ox, 14 + oy, 1, 8, inkS(ironHi))
		b.ink(13 + ox, 17 + oy, inkF(rune)); b.ink(13 + ox, 18 + oy, inkF(rune)); b.ink(12 + ox, 18 + oy, inkF(rune)); b.ink(14 + ox, 18 + oy, inkF(rune)); b.ink(13 + ox, 19 + oy, inkF(rune))
		b.inkRect(9 + ox, 22 + oy, 9, 1, inkS(0x6A5A4A))
		// hood with a dark hollow and two lights
		b.inkEllipse(13.5 + Double(ox), 6.0 + Double(oy), 5.2, 5.6, inkS(hood))
		b.inkEllipse(14.2 + Double(ox), 7.2 + Double(oy), 3.2, 3.4, inkF(0x0E0814))
		b.ink(13 + ox, 7 + oy, inkF(eye)); b.ink(16 + ox, 7 + oy, inkF(eye))
		b.ink(13 + ox, 8 + oy, inkF(0x8A5AC0)); b.ink(16 + ox, 8 + oy, inkF(0x8A5AC0))
		return b
	}
	func scythe(_ b: inout PixelBuf, _ pose: Int) {
		let ox: Int = 1
		let oy: Int = 1
		switch pose {
		case 0:
			// upright in the front hand
			b.inkLine(22 + ox, 3 + oy, 22 + ox, 40 + oy, inkF(shaft))
			b.inkLine(22 + ox, 1 + oy, 28 + ox, 4 + oy, inkF(blade))
			b.inkLine(22 + ox, 2 + oy, 28 + ox, 5 + oy, inkF(blade))
			b.inkLine(23 + ox, 3 + oy, 28 + ox, 6 + oy, inkF(edge))
			b.inkLine(28 + ox, 5 + oy, 28 + ox, 8 + oy, inkF(blade))
			b.inkRect(20 + ox, 20 + oy, 3, 3, inkS(iron))
		case 1:
			// drawn back over the shoulder
			b.inkLine(4 + ox, 4 + oy, 20 + ox, 26 + oy, inkF(shaft))
			b.inkLine(3 + ox, 4 + oy, 0 + ox, 11 + oy, inkF(blade))
			b.inkLine(4 + ox, 4 + oy, 1 + ox, 11 + oy, inkF(blade))
			b.inkLine(5 + ox, 4 + oy, 2 + ox, 11 + oy, inkF(edge))
			b.inkRect(18 + ox, 22 + oy, 3, 3, inkS(iron))
		case 2:
			// swept low and level in front
			b.inkLine(6 + ox, 27 + oy, 29 + ox, 27 + oy, inkF(shaft))
			b.inkLine(6 + ox, 28 + oy, 29 + ox, 28 + oy, inkF(shaft))
			b.inkLine(29 + ox, 27 + oy, 26 + ox, 36 + oy, inkF(blade))
			b.inkLine(28 + ox, 28 + oy, 25 + ox, 36 + oy, inkF(blade))
			b.inkLine(27 + ox, 28 + oy, 24 + ox, 35 + oy, inkF(edge))
			b.inkRect(18 + ox, 25 + oy, 3, 3, inkS(iron))
		default:
			// held aside while the free hand casts
			b.inkLine(4 + ox, 6 + oy, 4 + ox, 40 + oy, inkF(shaft))
			b.inkLine(4 + ox, 4 + oy, 0 + ox, 8 + oy, inkF(blade))
			b.inkLine(4 + ox, 5 + oy, 0 + ox, 9 + oy, inkF(blade))
			b.inkRect(20 + ox, 18 + oy, 3, 3, inkS(iron))
			b.inkEllipse(25.0 + Double(ox), 19.5 + Double(oy), 2.4, 2.4, inkF(0x9A5AE0))
			b.inkEllipse(25.0 + Double(ox), 19.5 + Double(oy), 1.2, 1.2, inkF(0xF0D8FF))
		}
	}
	var frames: [PixelBuf] = []
	for (sway, pose) in [(0, 0), (1, 0), (0, 1), (0, 2), (1, 3)] {
		var b: PixelBuf = base(sway)
		scythe(&b, pose)
		frames.append(finishCreature(b, band: 2))
	}
	return frames
}

func creatureSpriteSet(_ k: MobKind, _ v: Int) -> SpriteSet {
	return lookSpriteSet(creatureLook(k, v), hitH: mobDef(k).h)
}

/// The sprite set of a look, drawn `grow` times its own size
func lookSpriteSet(_ l: CreatureLook, hitH: Double, grow: Double = 1.0) -> SpriteSet {
	return makeSpriteSet(l.frames, hitH: hitH, fixedScale: l.scale * grow, anim: l.anim, foot: l.foot, cx: l.cx)
}

// ===== p05b_animals =====

// MARK: - Animal and monster sprites (hand-drawn rows; see composeCreature)

/// Pig. Frames: 0 idle, 1-2 walk, 3 grazing.
func spritePig() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["p": inkS(0xF0A0B0), "e": inkS(0xD9788E), "n": inkF(0xD06C84), "k": inkF(0x2A1A22), "h": inkF(0x7A4A50)]
	let frame0: [String] = [
		".....ee..",
		".pppppppp",
		"epppppkpn",
		".pppppppn",
		".h.h..h.h",
	]
	let frame1: [String] = [
		".....ee..",
		".pppppppp",
		"epppppkpn",
		".pppppppn",
		"h..h.h..h",
	]
	let frame2: [String] = [
		".....ee..",
		".pppppppp",
		"epppppkpn",
		".pppppppn",
		"..hh...hh",
	]
	let frame3: [String] = [
		".....e...",
		".ppppppe.",
		"epppppppp",
		".ppppppkp",
		".h.h..hnn",
	]
	return composeCreature(9, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Cow. Frames: 0 idle, 1-2 walk, 3 grazing.
func spriteCow() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xF4F2EC), "s": inkS(0x3A3438), "m": inkS(0xF0B0B8), "k": inkF(0x1E1418), "h": inkF(0xE8DCC0), "l": inkS(0xF4F2EC), "L": inkS(0xCFCAC2), "f": inkF(0x4A3A30), "t": inkS(0x3A3438)]
	let frame0: [String] = [
		"........h.h.",
		"t.......wsww",
		"twwssswwwwkw",
		"twwwsswwswwm",
		".wwwwwwwsmmm",
		".wwwwmwwww..",
		".lL....lL...",
		".ff....ff...",
	]
	let frame1: [String] = [
		"........h.h.",
		"t.......wsww",
		"twwssswwwwkw",
		"twwwsswwswwm",
		".wwwwwwwsmmm",
		".wwwwmwwww..",
		"l..L..l..L..",
		"f..f..f..f..",
	]
	let frame2: [String] = [
		"........h.h.",
		"t.......wsww",
		"twwssswwwwkw",
		"twwwsswwswwm",
		".wwwwwwwsmmm",
		".wwwwmwwww..",
		"..lL...Ll...",
		"..ff...ff...",
	]
	let frame3: [String] = [
		"............",
		"t...........",
		"twwssswwwh.h",
		"twwwsswwswsw",
		".wwwwwwwswkw",
		".wwwwmwwwwmm",
		".lL....lL.mm",
		".ff....ff...",
	]
	return composeCreature(12, 8, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Sheep in full wool. Frames: 0 idle, 1-2 walk, 3 grazing.
func spriteSheepWool() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xF2F0E8), "f": inkS(0x4A4450), "k": inkF(0xF4F0E0), "l": inkS(0x4A4450), "h": inkF(0x2A2430)]
	let frame0: [String] = [
		"..w.w.w...",
		".wwwwwwwf.",
		"wwwwwwwfff",
		"wwwwwwwfkf",
		".wwwwwwwff",
		"..l.l..l.l",
		"..h.h..h.h",
	]
	let frame1: [String] = [
		"..w.w.w...",
		".wwwwwwwf.",
		"wwwwwwwfff",
		"wwwwwwwfkf",
		".wwwwwwwff",
		".l..l.l..l",
		".h..h.h..h",
	]
	let frame2: [String] = [
		"..w.w.w...",
		".wwwwwwwf.",
		"wwwwwwwfff",
		"wwwwwwwfkf",
		".wwwwwwwff",
		"...ll...ll",
		"...hh...hh",
	]
	let frame3: [String] = [
		"..w.w.w...",
		".wwwwwww..",
		"wwwwwwwwf.",
		"wwwwwwwfff",
		".wwwwwwfkf",
		"..l.l..lff",
		"..h.h..h..",
	]
	return composeCreature(10, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Shorn sheep (same frames as the woolly one).
func spriteSheepShorn() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xE8C4B4), "f": inkS(0x4A4450), "k": inkF(0xF4F0E0), "l": inkS(0x4A4450), "h": inkF(0x2A2430)]
	let frame0: [String] = [
		"..........",
		"..wwwwww.f",
		".wwwwwwfff",
		".wwwwwwfkf",
		"..wwwwwwff",
		"..l.l..l.l",
		"..h.h..h.h",
	]
	let frame1: [String] = [
		"..........",
		"..wwwwww.f",
		".wwwwwwfff",
		".wwwwwwfkf",
		"..wwwwwwff",
		".l..l.l..l",
		".h..h.h..h",
	]
	let frame2: [String] = [
		"..........",
		"..wwwwww.f",
		".wwwwwwfff",
		".wwwwwwfkf",
		"..wwwwwwff",
		"...ll...ll",
		"...hh...hh",
	]
	let frame3: [String] = [
		"..........",
		"..wwwwww..",
		".wwwwwwwf.",
		".wwwwwwfff",
		"..wwwwwfkf",
		"..l.l..lff",
		"..h.h..h..",
	]
	return composeCreature(10, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Chicken. Frames: 0 idle, 1-2 walk, 3 pecking.
func spriteChicken() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["w": inkS(0xF6F4EE), "r": inkF(0xE04038), "y": inkF(0xF0B030), "k": inkF(0x1E1418)]
	let frame0: [String] = [
		"...rr.",
		"w..wky",
		"wwwwwr",
		".wwww.",
		"..y.y.",
	]
	let frame1: [String] = [
		"...rr.",
		"w..wky",
		"wwwwwr",
		".wwww.",
		".y..y.",
	]
	let frame2: [String] = [
		"...rr.",
		"w..wky",
		"wwwwwr",
		".wwww.",
		"...yy.",
	]
	let frame3: [String] = [
		"......",
		"w.....",
		"wwwwr.",
		".wwwwk",
		"..y.yy",
	]
	return composeCreature(6, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Brown bear. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteBrownBear() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x7A5436), "B": inkS(0x5E402A), "g": inkS(0xB08A5A), "m": inkS(0xC49A68), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "c": inkF(0xEDE6D0), "r": inkF(0x8A2A2A), "w": inkF(0xF4F0E4)]
	let frame0: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbmm.",
		"..bbbbbbbbbbb...",
		".bBb.....bBb....",
		".bBb.....bBb....",
		"cbBbc...cbBbc...",
	]
	let frame1: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbmm.",
		"..bbbbbbbbbbb...",
		"bb.Bb...bb.Bb...",
		"bb..Bb..bb..Bb..",
		"cb...Bc.cb...Bc.",
	]
	let frame2: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbmm.",
		"..bbbbbbbbbbb...",
		"..bBb.....bBb...",
		"..bbB.....bbB...",
		".cbbBc...cbbBc..",
	]
	let frame3: [String] = [
		"......bbbb......",
		"..bbbbbbbbbb.b..",
		".bbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbkmn",
		"bbbbbbbbbbbbbbm.",
		".bbbbbbbbbbbbrw.",
		"..bbbbbbbbbbbmmm",
		".bBb.....bBb....",
		".bBb.....bBb....",
		"cbBbc...cbBbc...",
	]
	return composeCreature(16, 10, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Grizzly: bigger, with a frosted shoulder hump. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteGrizzly() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x8E6236), "B": inkS(0x6A4626), "g": inkS(0xB08A5A), "m": inkS(0xD0A872), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "c": inkF(0xEDE6D0), "r": inkF(0x8A2A2A), "w": inkF(0xF4F0E4)]
	let frame0: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbbmm.",
		"..bbbbbbbbbbbb...",
		".bBb.....bBb.....",
		".bBb.....bBb.....",
		"cbBbc...cbBbc....",
	]
	let frame1: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbbmm.",
		"..bbbbbbbbbbbb...",
		"bb.Bb...bb.Bb....",
		"bb..Bb..bb..Bb...",
		"cb...Bc.cb...Bc..",
	]
	let frame2: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkbm",
		"bbbbbbbbbbbbbbbmn",
		".bbbbbbbbbbbbbmm.",
		"..bbbbbbbbbbbb...",
		"..bBb.....bBb....",
		"..bbB.....bbB....",
		".cbbBc...cbbBc...",
	]
	let frame3: [String] = [
		".......gggg......",
		"....gggggggg.b...",
		"..bbbbbbbbbbbbb..",
		".bbbbbbbbbbbbbbb.",
		"bbbbbbbbbbbbbbkmn",
		"bbbbbbbbbbbbbbbm.",
		".bbbbbbbbbbbbbrw.",
		"..bbbbbbbbbbbbmmm",
		".bBb.....bBb.....",
		".bBb.....bBb.....",
		"cbBbc...cbBbc....",
	]
	return composeCreature(17, 11, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Polar bear: long neck, low head. Frames: 0 idle, 1-2 walk, 3 bite.
func spritePolarBear() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0xF0F2F4), "B": inkS(0xC8D0DA), "g": inkS(0xB08A5A), "m": inkS(0xFAFAF6), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "c": inkF(0xEDE6D0), "r": inkF(0x8A2A2A), "w": inkF(0xF4F0E4)]
	let frame0: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkb",
		"bbbbbbbbbbbbbbbbbn",
		".bbbbbbbbbbbbbbb..",
		"..bbbbbbbbbbbb....",
		".bBb.....bBb......",
		".bBb.....bBb......",
		"cbBbc...cbBbc.....",
	]
	let frame1: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkb",
		"bbbbbbbbbbbbbbbbbn",
		".bbbbbbbbbbbbbbb..",
		"..bbbbbbbbbbbb....",
		"bb.Bb...bb.Bb.....",
		"bb..Bb..bb..Bb....",
		"cb...Bc.cb...Bc...",
	]
	let frame2: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkb",
		"bbbbbbbbbbbbbbbbbn",
		".bbbbbbbbbbbbbbb..",
		"..bbbbbbbbbbbb....",
		"..bBb.....bBb.....",
		"..bbB.....bbB.....",
		".cbbBc...cbbBc....",
	]
	let frame3: [String] = [
		".....bbbbb........",
		"..bbbbbbbbbbb.....",
		".bbbbbbbbbbbbbbb..",
		"bbbbbbbbbbbbbbbbkn",
		"bbbbbbbbbbbbbbbbb.",
		".bbbbbbbbbbbbbbrw.",
		"..bbbbbbbbbbbbbbbb",
		".bBb.....bBb......",
		".bBb.....bBb......",
		"cbBbc...cbBbc.....",
	]
	return composeCreature(18, 10, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Tiger. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteTiger() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["o": inkS(0xE8862C), "w": inkS(0xF6EEDC), "s": inkF(0x2E1E1A), "k": inkF(0x1E1418), "n": inkF(0xE06878), "O": inkS(0xC06A22), "r": inkF(0x8A2A2A), "c": inkF(0xF4F0E4)]
	let frame0: [String] = [
		"s.............o.o",
		"o..ososososoooooo",
		".oooososososoosok",
		"..ooooooooooooooon",
		"..owwwwwwwwwoowww.",
		"...oO......oO.....",
		"...oO......oO.....",
		"...cc......cc.....",
	]
	let frame1: [String] = [
		"s.............o.o",
		"o..ososososoooooo",
		".oooososososoosok",
		"..ooooooooooooooon",
		"..owwwwwwwwwoowww.",
		"..o..O....o..O....",
		".o....O..o....O...",
		".c....c..c....c...",
	]
	let frame2: [String] = [
		"s.............o.o",
		"o..ososososoooooo",
		".oooososososoosok",
		"..ooooooooooooooon",
		"..owwwwwwwwwoowww.",
		"....oO.....Oo.....",
		"....oO.....Oo.....",
		"....cc.....cc.....",
	]
	let frame3: [String] = [
		"s.............o.o.",
		"o..ososososoooooo.",
		".oooososososoosokn",
		"..ooooooooooooooo.",
		"..owwwwwwwwwoowrc.",
		"...oO......oO.....",
		"...oO......oO.....",
		"...cc......cc.....",
	]
	return composeCreature(18, 8, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Wolf: grey, amber eyes, tail low. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteWildWolf() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x8A909A), "G": inkS(0x666C78), "w": inkS(0xC8CCD2), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "r": inkF(0x8A2A2A), "c": inkF(0xF4F0E4), "C": inkF(0xD83A3A), "e": inkF(0xFFD040)]
	let frame0: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggegg.",
		"gggggggggggggggn",
		"g..gwwwwwwgww...",
		"...gG....gG.....",
		"...gG....gG.....",
	]
	let frame1: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggegg.",
		"gggggggggggggggn",
		"g..gwwwwwwgww...",
		"..g..G..g..G....",
		".g....Gg....G...",
	]
	let frame2: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggegg.",
		"gggggggggggggggn",
		"g..gwwwwwwgww...",
		"....gG...Gg.....",
		"....gG...Gg.....",
	]
	let frame3: [String] = [
		".........g.g....",
		"..gggggggggg....",
		".gggggggggggeggn",
		"ggggggggggggggg.",
		"g..gwwwwwwgwrc..",
		"...gG....gG.....",
		"...gG....gG.....",
	]
	return composeCreature(16, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Tamed wolf: golden coat, red collar, tail up. Frames: 0 idle, 1-2 walk, 3 bite.
func spriteDog() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0xD8A860), "G": inkS(0xB08442), "w": inkS(0xF2DCAA), "k": inkF(0x1E1418), "n": inkF(0x1E1418), "r": inkF(0x8A2A2A), "c": inkF(0xF4F0E4), "C": inkF(0xD83A3A), "e": inkF(0x1E1418)]
	let frame0: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgek.",
		"..ggggggggCgggn",
		"..gwwwwwwwgww..",
		"...gG....gG....",
		"...gG....gG....",
	]
	let frame1: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgek.",
		"..ggggggggCgggn",
		"..gwwwwwwwgww..",
		"..g..G..g..G...",
		".g....Gg....G..",
	]
	let frame2: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgek.",
		"..ggggggggCgggn",
		"..gwwwwwwwgww..",
		"....gG...Gg....",
		"....gG...Gg....",
	]
	let frame3: [String] = [
		"g.........g....",
		"gg........ggg..",
		".gggggggggCgekn",
		"..ggggggggCggg.",
		"..gwwwwwwwgwrc.",
		"...gG....gG....",
		"...gG....gG....",
	]
	return composeCreature(15, 7, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Cat. Frames: 0 idle, 1-2 walk.
func spriteCat() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["o": inkS(0xE8964A), "s": inkF(0xB8682A), "w": inkS(0xF6E6C8), "k": inkF(0x1E1418), "n": inkF(0xF08898), "O": inkS(0xC07838)]
	let frame0: [String] = [
		"o....o.o",
		"o.....oo",
		".osossok",
		".owwwwwn",
		".o.O.oO.",
	]
	let frame1: [String] = [
		"o....o.o",
		"o.....oo",
		".osossok",
		".owwwwwn",
		"o..Oo..O",
	]
	let frame2: [String] = [
		"o....o.o",
		"o.....oo",
		".osossok",
		".owwwwwn",
		"..oO.Oo.",
	]
	return composeCreature(8, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Elephant. Frames: 0 idle, 1-2 walk, 3 trunk raised (attack).
func spriteElephant() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x9298A2), "G": inkS(0x737A86), "e": inkS(0x7E8492), "E": inkF(0xB8A0A8), "k": inkF(0x1E1418), "t": inkF(0xF6F0E0), "n": inkF(0x5E6470)]
	let farIdle: [String] = [
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
		".....GGGG.......GGGG.",
	]
	let tail: [String] = [
		"g",
		"g",
		"g",
		"n",
	]
	let body: [String] = [
		"......gggggggggg.......",
		"...gggggggggggggggg....",
		"..gggggggggggggggggg...",
		".gggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		"ggggggggggggggggggggg..",
		".ggggggggggggggggggg...",
		"..gggggggggggggggggg...",
	]
	let legsIdle: [String] = [
		"..gggg........gggg...",
		"..gggg........gggg...",
		"..gggg........gggg...",
		"..gggg........gggg...",
		".tgtgt.......tgtgt...",
	]
	let head: [String] = [
		"...gggg...",
		"..gggggg..",
		".eeeggggg.",
		"eeEeegkgg.",
		"eeEeegggg.",
		"eeEeegggg.",
		"eeeeegggt.",
		".eeeggggtt",
		"..eeggg..t",
		"....gggg..",
		".....ggg..",
		"......gg..",
		"......gn..",
	]
	let farA: [String] = [
		"......GGGG....GGGG...",
		"......GGGG....GGGG...",
		".......GGGG..GGGG....",
		".......GGGG..GGGG....",
		".......GGGG..GGGG....",
	]
	let legsA: [String] = [
		".gggg..........gggg..",
		".gggg..........gggg..",
		"gggg............gggg.",
		"gggg............gggg.",
		"tgtg............tgtg.",
	]
	let farB: [String] = [
		"...GGGG.........GGGG.",
		"...GGGG.........GGGG.",
		"..GGGG...........GGGG",
		"..GGGG...........GGGG",
		"..GGGG...........GGGG",
	]
	let legsB: [String] = [
		"...gggg......gggg....",
		"...gggg......gggg....",
		"...gggg......gggg....",
		"...gggg......gggg....",
		"..tgtgt.....tgtgt....",
	]
	let headTrunkUp: [String] = [
		"...gggg.....",
		"..gggggg....",
		".eeeggggg...",
		"eeEeegkggg..",
		"eeEeeggggg..",
		"eeEeegggtgg.",
		"eeeeegggt.g.",
		".eeeggggt.g.",
		"..eeggg..gg.",
		"....gg...g..",
	]
	return composeCreature(26, 20, pal, [
		[(farIdle, 1, 15), (tail, 0, 6), (body, 1, 6), (legsIdle, 1, 15), (head, 16, 1)],
		[(farA, 1, 15), (tail, 0, 6), (body, 1, 6), (legsA, 1, 15), (head, 16, 1)],
		[(farB, 1, 15), (tail, 0, 6), (body, 1, 6), (legsB, 1, 15), (head, 16, 1)],
		[(farIdle, 1, 15), (tail, 0, 6), (body, 1, 6), (legsIdle, 1, 15), (headTrunkUp, 16, 1)],
	], band: 2)
}

/// Giraffe. Frames: 0 idle, 1-2 walk, 3 head dipped.
func spriteGiraffe() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["y": inkS(0xEAC25A), "p": inkF(0xA86A30), "Y": inkS(0xC8A048), "k": inkF(0x1E1418), "h": inkF(0x6A4A2A), "m": inkS(0xD8A870), "w": inkS(0xF4E4B0)]
	let farIdle: [String] = [
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...YY.....YY",
		"...hh.....hh",
	]
	let tail: [String] = [
		"y",
		"y",
		"y",
		"h",
	]
	let body: [String] = [
		".........yy.",
		".yyyyyyyyyyy",
		"yypyyypyyyyy",
		"yyyyyyyyypyy",
		"ypyypyyyyyyy",
		".yyyyyyyyyy.",
	]
	let legsIdle: [String] = [
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".yy......yy.",
		".hh......hh.",
	]
	let neck: [String] = [
		"....h.h",
		"....yyyy",
		"...yykyyy",
		"...yyyyymm",
		"....yyymm.",
		"...yyy....",
		"...ypy....",
		"...yyy....",
		"..yyp.....",
		"..yyy.....",
		"..pyy.....",
		"..yyy.....",
		".yypy.....",
		".yyyy.....",
		".ypyy.....",
		"yyyy......",
	]
	let farA: [String] = [
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....YY..YY..",
		"....hh..hh..",
	]
	let legsA: [String] = [
		".yy.......yy",
		".yy.......yy",
		"yy.........y",
		"yy........yy",
		"yy........yy",
		"yy........yy",
		"yy........yy",
		"hh........hh",
	]
	let farB: [String] = [
		"..YY......YY",
		".YY.......YY",
		".YY........Y",
		".YY........Y",
		".YY.......YY",
		".YY.......YY",
		".YY.......YY",
		".hh.......hh",
	]
	let legsB: [String] = [
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..yy....yy..",
		"..hh....hh..",
	]
	return composeCreature(19, 27, pal, [
		[(farIdle, 1, 19), (tail, 0, 14), (body, 1, 13), (legsIdle, 1, 19), (neck, 8, 0)],
		[(farA, 1, 19), (tail, 0, 14), (body, 1, 13), (legsA, 1, 19), (neck, 8, 0)],
		[(farB, 1, 19), (tail, 0, 14), (body, 1, 13), (legsB, 1, 19), (neck, 8, 0)],
		[(farIdle, 1, 19), (tail, 0, 14), (body, 1, 13), (legsIdle, 1, 19), (neck, 8, 1)],
	], band: 2)
}

/// Frog. Frames: 0 sitting, 1 hop.
func spriteFrog() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x5AB040), "G": inkS(0x3E8A30), "y": inkS(0xD8EC98), "e": inkF(0x1E1418)]
	let frame0: [String] = [
		"..g.g.",
		".gggge",
		"Gggyg.",
	]
	let frame1: [String] = [
		"...g.g",
		"Ggggge",
		"G...GG",
	]
	return composeCreature(6, 3, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
	])
}

/// Fish. Frames: 0-1 swim.
func spriteFish() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x5EA8DC), "f": inkS(0x3C7CB8), "w": inkS(0xD4ECF8), "k": inkF(0x1E1418)]
	let frame0: [String] = [
		"f.bbb.",
		"fbbbkb",
		"f.www.",
	]
	let frame1: [String] = [
		"..bbb.",
		"ffbbkb",
		"..www.",
	]
	return composeCreature(6, 3, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
	])
}

/// Crow. Frames: 0 wings up, 1 level, 2 down.
func spriteCrow() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["c": inkS(0x343448), "C": inkS(0x22222E), "y": inkF(0xD8A030), "k": inkF(0xD8D4E0)]
	let frame0: [String] = [
		"..C....",
		"...C...",
		"CccCcky",
		"..cc...",
		".......",
	]
	let frame1: [String] = [
		".......",
		".......",
		"CcccCky",
		"CCCC...",
		".......",
	]
	let frame2: [String] = [
		".......",
		".......",
		"Cccccky",
		"..CC...",
		"...C...",
	]
	return composeCreature(7, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Slime. Frames: 0 resting, 1 airborne, 2 bite.
func spriteGreenSlime() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0x58C050), "h": inkF(0xB4F0A0), "c": inkS(0x3E9A3A), "k": inkF(0x1E2A1A), "m": inkF(0x6A1E20), "y": inkF(0xFFD060)]
	let frame0: [String] = [
		".........",
		"..ggggg..",
		".ghhggggg",
		"gggggkgkg",
		"ggcgggggg",
		".ggggggg.",
	]
	let frame1: [String] = [
		"...ggg...",
		"..ghggg..",
		".ggggkgk.",
		".gcgggg..",
		".ccggggg.",
		"..ggggg..",
	]
	let frame2: [String] = [
		".........",
		"..ggggg..",
		".ghhgkgkg",
		"gggggmmmg",
		"ggcggymyg",
		".gggggggg",
	]
	return composeCreature(9, 6, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Ember slime: a magma slime with glowing cracks. Frames as the slime.
func spriteEmberSlime() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["g": inkS(0xE86A28), "h": inkF(0xFFC870), "c": inkS(0xC04A1A), "k": inkF(0x3A1008), "m": inkF(0x5A1408), "y": inkF(0xFFD060)]
	let frame0: [String] = [
		".........",
		"..ggggg..",
		".ghhggggg",
		"gggggkgkg",
		"ggyggggyg",
		".gggggyg.",
	]
	let frame1: [String] = [
		"...ggg...",
		"..ghggg..",
		".ggggkgk.",
		".gygggg..",
		".gggyggg.",
		"..ggggg..",
	]
	let frame2: [String] = [
		".........",
		"..ggggg..",
		".ghhgkgkg",
		"gggggmmmg",
		"ggyggymyg",
		".gggggggg",
	]
	return composeCreature(9, 6, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Cave bat. Frames: 0 wings up, 1 level, 2 down.
func spriteCaveBat() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x4A3A5E), "w": inkS(0x6A5480), "k": inkF(0xFF4A4A)]
	let frame0: [String] = [
		"w.......w",
		"ww.b.b.ww",
		".wwbbbww.",
		"...bkb...",
		".........",
	]
	let frame1: [String] = [
		".........",
		"...b.b...",
		"wwwbbbwww",
		".w.bkb.w.",
		".........",
	]
	let frame2: [String] = [
		".........",
		"...b.b...",
		"..wbbbw..",
		".wwbkbww.",
		"w.......w",
	]
	return composeCreature(9, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Cinder bat: charcoal body, ember wings. Frames as the cave bat.
func spriteCinderBat() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["b": inkS(0x3A2A2A), "w": inkS(0xE06A28), "k": inkF(0xFFD040)]
	let frame0: [String] = [
		"w.......w",
		"ww.b.b.ww",
		".wwbbbww.",
		"...bkb...",
		".........",
	]
	let frame1: [String] = [
		".........",
		"...b.b...",
		"wwwbbbwww",
		".w.bkb.w.",
		".........",
	]
	let frame2: [String] = [
		".........",
		"...b.b...",
		"..wbbbw..",
		".wwbkbww.",
		"w.......w",
	]
	return composeCreature(9, 5, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

/// Scorpion. Frames: 0 idle, 1-2 walk, 3 sting.
func spriteScorpion() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["a": inkS(0xC88A40), "A": inkS(0xA87034), "d": inkS(0x9A6430), "s": inkF(0xE85030), "k": inkF(0x1E1418), "l": inkS(0x9A6430)]
	let frame0: [String] = [
		".aAa.......",
		"a...s......",
		"A..........",
		"aAaAaAa..dd",
		".aaaaaaakdd",
		".l.l.l.l...",
	]
	let frame1: [String] = [
		".aAa.......",
		"a...s......",
		"A..........",
		"aAaAaAa..dd",
		".aaaaaaakdd",
		"l.l.l.l....",
	]
	let frame2: [String] = [
		".aAa.......",
		"a...s......",
		"A..........",
		"aAaAaAa..dd",
		".aaaaaaakdd",
		".l.l.l.l...",
	]
	let frame3: [String] = [
		"....aAas...",
		"..aA.......",
		".a.........",
		"aAaAaAa...d",
		".aaaaaaakdd",
		".l.l.l.l...",
	]
	return composeCreature(11, 6, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
		[(frame3, 0, 0)],
	])
}

/// Wraith. Frames: 0-1 drifting, 2 grab.
func spriteWraith() -> [PixelBuf] {
	let pal: [Character: UInt32] = ["r": inkS(0x5A3A8A), "R": inkS(0x3E2668), "v": inkF(0x140A20), "e": inkF(0xFFE070), "c": inkF(0xC8C0D8)]
	let frame0: [String] = [
		"..rrrr...",
		".rrrrrr..",
		"rrvvvvrr.",
		"rvevevvr.",
		"rvvvvvvr.",
		"rrvvvvrr.",
		"rrrrrrcc.",
		"rRrrrrr..",
		"rRrrrrr..",
		".RRrrrr..",
		".R.Rr.r..",
		"...R...r.",
	]
	let frame1: [String] = [
		"..rrrr...",
		".rrrrrr..",
		"rrvvvvrr.",
		"rvevevvr.",
		"rvvvvvvr.",
		"rrvvvvrr.",
		"rrrrrrcc.",
		"rRrrrrr..",
		"rRrrrrr..",
		".RRrrrr..",
		"..RR.rr..",
		".R..r..r.",
	]
	let frame2: [String] = [
		"..rrrr...",
		".rrrrrr..",
		"rrvvvvrr.",
		"rvevevvr.",
		"rvvvvvvrc",
		"rrvvvvrrc",
		"rrrrrrrcc",
		"rRrrrrr..",
		"rRrrrrr..",
		".RRrrrr..",
		".R.Rr.r..",
		"...R...r.",
	]
	return composeCreature(9, 12, pal, [
		[(frame0, 0, 0)],
		[(frame1, 0, 0)],
		[(frame2, 0, 0)],
	])
}

// ===== p05c_bosses =====

// MARK: - Boat and vehicle-part sprites

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
	case .offroadWheel:
		b.ellipse(4, 4, 4, 4, 0x18181C)
		for k in 0..<8 {
			let a: Double = Double(k) / 8.0 * 2.0 * Double.pi
			b.set(Int((4.0 + cos(a) * 3.6).rounded()), Int((4.0 + sin(a) * 3.6).rounded()), 0x3A3A42)
		}
		b.ellipse(4, 4, 2.0, 2.0, 0xC89040)
		b.set(4, 4, 0x4A3A20)
		b.set(3, 3, 0xF0C060)
	case .headlight:
		b.rect(0, 2, 4, 4, 0x5A5A64); b.rect(0, 2, 4, 1, 0x8A8A94)
		b.rect(4, 1, 3, 6, 0x9A9AA4); b.rect(5, 2, 2, 4, 0xFFF0A0); b.set(6, 3, 0xFFFFFF); b.set(7, 4, 0xFFF0A0)
	case .cargo:
		b.rect(0, 0, 8, 8, 0x8F6732); b.rect(1, 1, 6, 6, 0xB98A4E)
		b.line(1, 1, 6, 6, 0x8F6732); b.line(1, 6, 6, 1, 0x8F6732)
		b.rect(0, 0, 8, 1, 0x6A6A74); b.rect(0, 7, 8, 1, 0x6A6A74)
	case .drill, .diamondDrill, .voidDrill:
		// drawn pointing right; the renderer turns it to face its open side
		let bit: UInt32 = p == .drill ? 0xC8CCD4 : (p == .diamondDrill ? 0x6FE6EC : 0xB070FF)
		b.rect(0, 1, 3, 6, 0x5A5A64); b.rect(0, 1, 3, 1, 0x8A8A94)
		b.rect(3, 1, 2, 6, bit); b.rect(5, 2, 1, 4, bit); b.rect(6, 3, 1, 2, bit); b.set(7, 3, bit); b.set(7, 4, shadeRGB(bit, 0.7))
		b.set(3, 2, shadeRGB(bit, 0.65)); b.set(4, 4, shadeRGB(bit, 0.65)); b.set(3, 6, shadeRGB(bit, 0.65)); b.set(5, 5, shadeRGB(bit, 0.65))
	case .block:
		// never drawn: a block cell shows its own tile
		b.rect(0, 0, 8, 8, 0x8A8A8A)
	case .cockpit:
		// a glass canopy over a seat, on a metal tub
		b.ellipse(4, 4.2, 3.7, 3.4, 0x9AD0F0); b.set(2, 2, 0xE0F4FF); b.set(3, 1, 0xE0F4FF)
		b.rect(3, 2, 1, 3, 0x3A3A44); b.rect(3, 4, 3, 1, 0x3A3A44)
		b.rect(0, 5, 8, 3, 0x5A6A7A); b.rect(0, 5, 8, 1, 0x8A9AAA); b.set(6, 6, 0xE0A040)
	case .wing:
		// the wing's cross-section: a thin airfoil along the cell
		b.rect(1, 3, 6, 1, 0xE8E8EC); b.rect(0, 4, 8, 1, 0xC8C8D0); b.rect(1, 5, 5, 1, 0x8A8A94); b.set(7, 3, 0xC8C8D0)
	case .elevator:
		// a small tail surface with a hinged red flap
		b.rect(0, 3, 5, 1, 0xE8E8EC); b.rect(0, 4, 5, 1, 0xA8A8B0); b.rect(5, 3, 3, 2, 0xC84A3A); b.set(5, 4, 0x8A2A22); b.rect(0, 2, 1, 1, 0xC84A3A)
	case .airProp:
		// drawn facing right: hub and spinner, the blade edge-on across the open side
		b.rect(0, 3, 4, 2, 0x6A6A74); b.rect(4, 2, 2, 4, 0x8A8A94); b.set(6, 3, 0xC8C8D0); b.set(6, 4, 0xC8C8D0)
		b.rect(7, 0, 1, 8, 0x8F6732); b.set(7, 3, 0x5A4020); b.set(7, 4, 0x5A4020)
	case .jet:
		// drawn with the exhaust to the right: intake ring, casing, glowing nozzle
		b.rect(0, 1, 2, 6, 0x3A3A44); b.rect(2, 1, 4, 6, 0x9A9AA4); b.rect(2, 1, 4, 1, 0xC8C8D0); b.rect(2, 6, 4, 1, 0x6A6A74)
		b.rect(6, 2, 2, 4, 0x5A5A64); b.rect(7, 3, 1, 2, 0xFF8A30); b.set(1, 3, 0x1A1A20); b.set(1, 4, 0x1A1A20)
	case .rotor:
		// the mast and hub; the blades are drawn spinning above it
		b.rect(3, 1, 2, 7, 0x5A5A64); b.rect(1, 0, 6, 2, 0x7A7A84); b.rect(1, 0, 6, 1, 0xA8A8B0); b.rect(2, 6, 4, 2, 0x4A4A52)
	case .tailRotor:
		// a short boom with a small rotor at its open end (drawn facing right)
		b.rect(0, 3, 5, 2, 0x5A6A5A); b.rect(0, 3, 5, 1, 0x7A8A7A); b.ellipse(6.2, 4, 1.5, 3.6, 0x9A9AA4); b.set(6, 4, 0x3A3A44)
	case .envelope:
		// balloon canvas in red and cream stripes (it tiles into one big envelope)
		b.rect(0, 0, 4, 8, 0xD8483C); b.rect(4, 0, 4, 8, 0xF0E4D0); b.rect(3, 0, 1, 8, 0xB83A30); b.rect(7, 0, 1, 8, 0xD8CCB8)
	case .burner:
		// a burner frame with its gas jet and pilot flame
		b.rect(1, 4, 6, 4, 0x6A6A74); b.rect(1, 4, 6, 1, 0x9A9AA4); b.rect(2, 6, 4, 1, 0x8A5A2A)
		b.rect(3, 2, 2, 2, 0x4A4A52); b.set(3, 1, 0x60A0FF); b.set(4, 0, 0xFFB040); b.set(4, 1, 0xFF7020)
	case .track:
		// a stretch of track: rubber belt and lugs round a road wheel
		b.rect(0, 1, 8, 6, 0x2A2A30); b.rect(0, 1, 8, 1, 0x4A4A52); b.rect(0, 6, 8, 1, 0x4A4A52)
		b.set(1, 0, 0x3A3A42); b.set(4, 0, 0x3A3A42); b.set(7, 0, 0x3A3A42); b.set(1, 7, 0x3A3A42); b.set(4, 7, 0x3A3A42); b.set(7, 7, 0x3A3A42)
		b.ellipse(4, 4, 2.2, 2.2, 0x6A6A74); b.set(4, 4, 0xA8A8B0)
	case .armor:
		// thick riveted steel plate
		b.rect(0, 0, 8, 8, 0x5A6068); b.rect(0, 0, 8, 1, 0x7A8088); b.rect(0, 7, 8, 1, 0x3A4048); b.rect(0, 0, 1, 8, 0x6A7078)
		b.set(1, 1, 0x9AA0A8); b.set(6, 1, 0x9AA0A8); b.set(1, 6, 0x9AA0A8); b.set(6, 6, 0x9AA0A8)
	case .cannon:
		// the turret ring; the barrel is drawn turning toward the aim
		b.rect(0, 5, 8, 3, 0x4A5040); b.ellipse(4, 5.2, 3.2, 2.6, 0x5A6450); b.set(3, 4, 0x7A8470); b.rect(0, 7, 8, 1, 0x2A2E24)
	case .autoGun:
		// the gun mount and its ammunition box; the barrel is drawn turning toward the aim
		b.rect(1, 5, 6, 3, 0x3A3A40); b.rect(2, 3, 4, 2, 0x4A4A52); b.rect(5, 5, 2, 2, 0x6A5A2A); b.set(3, 3, 0x6A6A74)
	case .autopilot:
		// a control box with a little screen
		b.rect(0, 1, 8, 6, 0x3A3F4A); b.rect(1, 2, 6, 3, 0x1A2A2A); b.line(2, 4, 3, 3, 0x50F070); b.line(3, 3, 5, 3, 0x50F070)
		b.set(1, 5, 0xE04040); b.set(3, 5, 0x50F070); b.set(5, 5, 0xFFC020)
	case .flap:
		// a wing with its hinged flap at the trailing end, drooped a little
		b.rect(1, 3, 5, 1, 0xE8E8EC); b.rect(0, 4, 6, 1, 0xC8C8D0); b.rect(1, 5, 4, 1, 0x8A8A94)
		b.rect(6, 4, 2, 1, 0xD8A030); b.set(7, 5, 0xD8A030); b.set(6, 5, 0x9A6A20)
	case .airBrake:
		// two panels hinged open on a frame, edged in yellow
		b.rect(0, 5, 8, 2, 0x6A6A74); b.rect(0, 5, 8, 1, 0x9A9AA4)
		b.line(1, 4, 3, 1, 0xC8C8D0); b.line(6, 4, 4, 1, 0xC8C8D0); b.set(3, 1, 0xE8C040); b.set(4, 1, 0xE8C040)
	case .stabilizer:
		// a thin fixed tail surface with a fin
		b.rect(0, 4, 8, 1, 0xC8C8D0); b.rect(1, 3, 6, 1, 0xE8E8EC); b.rect(0, 5, 7, 1, 0x8A8A94)
		b.rect(5, 1, 2, 2, 0xA8A8B0); b.set(6, 0, 0xA8A8B0)
	case .ballast:
		// a riveted steel tank with a water line and its valve
		b.rect(0, 1, 8, 6, 0x5A6470); b.rect(0, 1, 8, 1, 0x7A8490); b.rect(1, 4, 6, 2, 0x3B6FC8); b.rect(1, 4, 6, 1, 0x6A9AE0)
		b.set(1, 2, 0x2A3038); b.set(6, 2, 0x2A3038); b.rect(3, 0, 2, 1, 0xC84A3A)
	case .railWheel:
		// a steel wheel with its flange (the darker rim that rides inside the rail)
		b.ellipse(4, 4, 4, 4, 0x3A3E46); b.ellipse(4, 4, 3, 3, 0x8A8E98); b.ellipse(4, 4, 1.4, 1.4, 0x4A4E56)
		b.set(4, 4, 0xC8CCD4); b.set(2, 2, 0xB8BCC4)
	case .coupler:
		// a buffer beam with a hook and a link
		b.rect(0, 2, 3, 4, 0x5A5E66); b.rect(0, 2, 3, 1, 0x8A8E96); b.rect(3, 3, 3, 2, 0x3A3E46)
		b.ellipse(6.5, 4, 1.6, 1.6, 0x2A2E36); b.set(6, 4, 0x8A8E96); b.set(7, 4, 0x8A8E96)
	case .hinge:
		// two leaves round a pin
		b.rect(0, 2, 3, 4, 0x8A8E96); b.rect(5, 2, 3, 4, 0x8A8E96); b.rect(3, 1, 2, 6, 0x5A5E66)
		b.set(4, 3, 0xC8CCD4); b.set(4, 4, 0xC8CCD4); b.set(1, 3, 0x3A3E46); b.set(6, 4, 0x3A3E46)
	case .servo:
		// a motor housing with its output disc and a yellow mark
		b.rect(0, 1, 8, 6, 0x4A5060); b.rect(0, 1, 8, 1, 0x6A7080); b.ellipse(4, 4, 2.6, 2.6, 0x9AA0AC)
		b.ellipse(4, 4, 1.2, 1.2, 0x3A3E46); b.set(4, 2, 0xE8C040); b.set(1, 6, 0xC84A3A)
	case .piston:
		// a cylinder with its rod sticking out to the right
		b.rect(0, 2, 5, 4, 0x5A6470); b.rect(0, 2, 5, 1, 0x7A8490); b.rect(5, 3, 3, 2, 0xC8CCD4); b.rect(7, 2, 1, 4, 0x8A8E96)
		b.set(1, 4, 0x3A3E46)
	case .bigWheel:
		// drawn three cells across: a tyre with heavy tread and a spoked hub
		b.ellipse(4, 4, 4, 4, 0x1E1E22); b.ellipse(4, 4, 3.2, 3.2, 0x2E2E34); b.ellipse(4, 4, 2.2, 2.2, 0x9A9AA4)
		b.line(2, 4, 6, 4, 0x5A5A64); b.line(4, 2, 4, 6, 0x5A5A64); b.set(4, 4, 0xD8D8E0); b.set(1, 1, 0x3A3A42); b.set(6, 6, 0x3A3A42)
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
	/// appended: the three custom dimension slots a world's mods can fill (see ModDimension)
	case custom0, custom1, custom2
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

/// A flat world's pond: a bowl of water whose surface is level with the ground
struct PondSite {
	var cx: Int
	var halfW: Int
	var depth: Int
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
	var ponds: [Int: PondSite?] = [:]
	var grottos: [Int: GrottoSite?] = [:]
	var mines: [Int: MineSite?] = [:]
	/// the Warden's citadel, worked out once (nil inside = this world has none)
	var citadel: CitadelSite?? = nil
	var hits: Int = 0
	var misses: Int = 0

	func clear() {
		cols.removeAll(keepingCapacity: true)
		villages.removeAll(keepingCapacity: true)
		rares.removeAll(keepingCapacity: true)
		ponds.removeAll(keepingCapacity: true)
		grottos.removeAll(keepingCapacity: true)
		mines.removeAll(keepingCapacity: true)
	}

	/// Keeps memory bounded in infinite worlds
	func trim() {
		if cols.count > 24_000 { cols.removeAll(keepingCapacity: true) }
		if villages.count > 4_000 { villages.removeAll(keepingCapacity: true) }
		if rares.count > 8_000 { rares.removeAll(keepingCapacity: true) }
		if ponds.count > 8_000 { ponds.removeAll(keepingCapacity: true) }
		if grottos.count > 4_000 { grottos.removeAll(keepingCapacity: true) }
		if mines.count > 4_000 { mines.removeAll(keepingCapacity: true) }
	}
}

/// Choices made when a world is created; saved with the world so it keeps generating the same way
struct WorldOptions: Codable, Equatable {
	/// flat terrain: one surface height and the same layers everywhere (no caves, seas or mountains)
	var flat: Bool = false
	/// flat worlds only: trees and plants on the surface
	var trees: Bool = true
	/// flat worlds only: ruins, mines and boss lairs (the buried portal chamber is always there)
	var structures: Bool = true
	/// flat worlds only: caves, underground lakes and deep lava, all below an unbroken crust
	var caves: Bool = false
	/// flat worlds only: small ponds set into the ground, their water level with the surface
	var ponds: Bool = false

	static let standard: WorldOptions = WorldOptions()

	enum CodingKeys: String, CodingKey {
		case flat, trees, structures, caves, ponds
	}
}

extension WorldOptions {
	/// Saves from earlier versions lack the newer keys. They decode with those features off, so the
	/// terrain such a world has not generated yet still matches the terrain it already has.
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		flat = try c.decodeIfPresent(Bool.self, forKey: .flat) ?? false
		trees = try c.decodeIfPresent(Bool.self, forKey: .trees) ?? true
		structures = try c.decodeIfPresent(Bool.self, forKey: .structures) ?? true
		caves = try c.decodeIfPresent(Bool.self, forKey: .caves) ?? false
		ponds = try c.decodeIfPresent(Bool.self, forKey: .ponds) ?? false
	}
}

struct WorldGen {
	let cache: GenCache = GenCache()
	let seed: UInt64
	let infinite: Bool
	let width: Int
	let spawnX: Int
	/// 1 = original rules (kept for worlds saved before ocean basins), 2 = with ocean basins,
	/// 3 = buildings and lairs that never wall off the way along the ground, birch and pine trees,
	/// surface landmarks, crystal grottos and abandoned mines, 4 = mines grown into branching networks
	/// (side rooms, drifts down ladders, dead ends, collapses hiding chests, a great chamber),
	/// 5 = no villages (worlds saved earlier keep the villages they already have, empty of villagers),
	/// 6 = more trees (and a grove around the spawn), iron from higher up, a little more coal, copper
	/// and tin, and seas about a fifth narrower
	let genVersion: Int
	static let currentVersion: Int = 6
	let options: WorldOptions
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
	/// surface row of flat worlds: the height boss lairs are built at, ten rows above sea level
	static let flatSurface: Int = WorldGen.sea - 10
	/// rows of solid ground kept under a flat world's surface before any cave may open
	static let flatCrust: Int = 16

	var hasTrees: Bool { return !options.flat || options.trees }
	/// Structures built so the ground can always be walked through: doors at both ends, walk-through
	/// posts, ruins with gateways, lair rims and ribs a jump clears. Worlds saved with older rules keep
	/// their structures exactly (their unexplored ground must match what they already have), except
	/// flat worlds, where a wall across the only way along is a dead end.
	var passableStructures: Bool { return genVersion >= 3 || options.flat }
	var hasStructures: Bool { return !options.flat || options.structures }
	/// Villages are only generated for worlds saved before generator version 5, so their unexplored
	/// ground matches what they already have. New worlds have none.
	var hasVillages: Bool { return genVersion < 5 && hasStructures }

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

	init(seed: UInt64, infinite: Bool, rareChance: Double, genVersion: Int = WorldGen.currentVersion, options: WorldOptions = .standard) {
		self.genVersion = genVersion
		self.options = options
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
				let c: Col = options.flat ? WorldGen.flatColStatic(seed, infinite, width, spawnX, zones, x, lairs: false) : WorldGen.colBaseStatic(seed, infinite, width, spawnX, zones, x, basins: genVersion >= 2, smallSeas: genVersion >= 6)
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
		if !hasStructures { return nil }
		return WorldGen.lairStatic(spawnX, infinite, x, radius)
	}

	func lairCenters(near x: Int) -> [LairInfo] {
		var out: [LairInfo] = []
		if !hasStructures { return out }
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
	/// (narrower from generator 6: `small`)
	static func homeBasin(_ seed: UInt64, _ spawnX: Int, small: Bool = false) -> Basin {
		let side: Int = hash2(41, 42, seed) < 0.5 ? -1 : 1
		let off: Int = 560 + Int(hash2(43, 44, seed) * 120.0)
		if small { return Basin(center: spawnX + side * off, halfW: 112 + Int(hash2(45, 46, seed) * 38.0), ramp: 90) }
		return Basin(center: spawnX + side * off, halfW: 150 + Int(hash2(45, 46, seed) * 50.0), ramp: 110)
	}

	/// Random large basins in infinite worlds (about two in five 1600-wide cells), kept clear of spawn and lairs
	static func cellBasin(_ seed: UInt64, _ spawnX: Int, _ c: Int, small: Bool = false) -> Basin? {
		if hash2(c, 401, seed) > 0.26 { return nil }
		let cellW: Int = 1600
		var hw: Int = 140 + Int(hash2(c, 402, seed) * 220.0)
		let cen: Int = c * cellW + hw + 140 + Int(hash2(c, 403, seed) * Double(max(1, cellW - 2 * hw - 280)))
		if abs(cen - spawnX) < hw + 900 { return nil }
		for lc in lairCentersStatic(spawnX, true, cen) where abs(cen - lc) < hw + 330 { return nil }
		// generator 6: the same seas, a quarter narrower, with shorter shelving coasts
		if small {
			hw = hw * 3 / 4
			return Basin(center: cen, halfW: hw, ramp: 105)
		}
		return Basin(center: cen, halfW: hw, ramp: 140)
	}

	/// 0...1: how strongly x lies inside an ocean basin (1 = open sea, ramping down over the coast)
	static func oceanBasin(_ seed: UInt64, _ infinite: Bool, _ spawnX: Int, _ x: Int, small: Bool = false) -> Double {
		func weight(_ b: Basin) -> Double {
			let d: Double = Double(abs(x - b.center))
			return 1.0 - smooth(clampD((d - Double(b.halfW)) / Double(b.ramp), 0, 1))
		}
		var w: Double = weight(homeBasin(seed, spawnX, small: small))
		if infinite {
			let c0: Int = floorDiv(x, 1600)
			for c in (c0 - 1)...(c0 + 1) {
				if let b = cellBasin(seed, spawnX, c, small: small) { w = max(w, weight(b)) }
			}
		}
		return w
	}

	static func colBaseStatic(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ spawnX: Int, _ zones: [Int], _ x: Int, basins: Bool = true, smallSeas: Bool = false) -> Col {
		let fx: Double = Double(x)
		let H: Int = WorldGen.H
		let sea: Int = WorldGen.sea
		// generator 6: seas and continents a little narrower, so a crossing is shorter
		var land: Double = fbm1(fx / (smallSeas ? 700.0 : 800.0), seed &+ 1, 3)
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
		// generator 6: the open sea the land field makes on its own ends sooner (land just under the
		// shore line is lifted a little, so coasts move out to sea; the deep water is unchanged)
		if smallSeas && land < 0.50 && land > 0.25 {
			land += 0.06 * (1.0 - smooth(clampD(abs(land - 0.40) / 0.09, 0, 1)))
		}
		// ocean basins pull the land value down into deep water (after the spawn/lair guarantees,
		// which basins are placed well away from)
		let basin: Double = basins ? WorldGen.oceanBasin(seed, infinite, spawnX, x, small: smallSeas) : 0
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

	/// Flat worlds: every column has the same height; the biome comes from the climate alone (the
	/// same temperature and humidity thresholds as colBaseStatic, without seas or mountains), and the
	/// ground around a boss lair keeps its forest or jungle
	static func flatColStatic(_ seed: UInt64, _ infinite: Bool, _ width: Int, _ spawnX: Int, _ zones: [Int], _ x: Int, lairs: Bool) -> Col {
		let cl: (Double, Double) = WorldGen.climate(seed, infinite, width, zones, x)
		let temp: Double = cl.0
		let humid: Double = cl.1
		let tundra: Double = smooth(clampD((0.31 - temp) / 0.06, 0, 1))
		let hot: Double = smooth(clampD((temp - 0.64) / 0.06, 0, 1))
		let desert: Double = hot * smooth(clampD((0.42 - humid) / 0.06, 0, 1))
		let jungle: Double = hot * smooth(clampD((humid - 0.58) / 0.06, 0, 1))
		let savanna: Double = hot * (1.0 - desert) * (1.0 - jungle)
		let swamp: Double = smooth(clampD((humid - 0.68) / 0.06, 0, 1)) * (1.0 - tundra) * (1.0 - hot)
		var biome: Biome = humid > 0.5 ? .forest : .plains
		if tundra > 0.5 { biome = .tundra }
		else if desert > 0.5 { biome = .desert }
		else if jungle > 0.5 { biome = .jungle }
		else if savanna > 0.5 { biome = .savanna }
		else if swamp > 0.5 { biome = .swamp }
		if lairs, let L = WorldGen.lairStatic(spawnX, infinite, x, 150), abs(x - L.cx) < 120 { biome = L.kind == .bear ? .forest : .jungle }
		return Col(h: WorldGen.flatSurface, biome: biome, land: 0.7, mtn: 0, swamp: 0)
	}

	func colBase(_ x: Int) -> Col {
		if let c = cache.cols[x] {
			cache.hits &+= 1
			return c
		}
		cache.misses &+= 1
		let c: Col = options.flat ? WorldGen.flatColStatic(seed, infinite, width, spawnX, zones, x, lairs: hasStructures) : WorldGen.colBaseStatic(seed, infinite, width, spawnX, zones, x, basins: genVersion >= 2, smallSeas: genVersion >= 6)
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
		if !hasVillages { return nil }
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
		if !hasStructures { return nil }
		if hash2(c, 71, seed) > rareChance { return nil }
		let cellW: Int = WorldGen.rareCell
		let sx: Int = c * cellW + 32 + Int(hash2(c, 72, seed) * Double(cellW - 64))
		let base: Col = colBase(sx)
		if base.biome == .ocean || base.land < 0.45 { return nil }
		if lairAt(sx, radius: 260) != nil { return nil }
		if abs(sx - portalX) < 90 { return nil }
		if !infinite && (sx < 300 || sx > width - 300) { return nil }
		if nearestVillageSimple(sx) { return nil }
		// flat worlds keep the spawn point clear (in other worlds the terrain search does that)
		if options.flat && abs(sx - spawnX) < 48 { return nil }
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

	// MARK: ponds (flat worlds)

	static let pondCell: Int = 260

	func pondSite(cell c: Int) -> PondSite? {
		if let p = cache.ponds[c] { return p }
		let p: PondSite? = computePondSite(cell: c)
		cache.ponds[c] = p
		return p
	}

	func computePondSite(cell c: Int) -> PondSite? {
		if !options.flat || !options.ponds { return nil }
		if hash2(c, 501, seed) > 0.5 { return nil }
		let cw: Int = WorldGen.pondCell
		let cx: Int = c * cw + 50 + Int(hash2(c, 502, seed) * Double(cw - 100))
		let hw: Int = 4 + Int(hash2(c, 503, seed) * 6.0)
		let depth: Int = hash2(c, 504, seed) < 0.4 ? 3 : 2
		if !infinite && (cx - hw < 40 || cx + hw > width - 40) { return nil }
		// never where something else is built, or at the spawn point
		if abs(cx - spawnX) < hw + 24 { return nil }
		if abs(cx - portalX) < hw + 16 { return nil }
		if lairAt(cx, radius: hw + 60) != nil { return nil }
		for v in villages(overlapping: cx - hw - 20, cx + hw + 20) where abs(v.x - cx) < v.halfW + hw + 20 { return nil }
		for r in rareSites(overlapping: cx - hw - 40, cx + hw + 40) where abs(r.x - cx) < hw + 40 { return nil }
		return PondSite(cx: cx, halfW: hw, depth: depth)
	}

	/// Water depth of a flat world's pond at x (0 = dry ground); the bowl is deepest in the middle
	func pondDepth(_ x: Int) -> Int {
		if !options.flat || !options.ponds { return 0 }
		let c: Int = floorDiv(x, WorldGen.pondCell)
		for cc in (c - 1)...(c + 1) {
			guard let p = pondSite(cell: cc) else { continue }
			let dx: Int = abs(x - p.cx)
			if dx > p.halfW { continue }
			let f: Double = Double(dx) / (Double(p.halfW) + 0.5)
			let d: Int = Int((Double(p.depth) * sqrt(max(0, 1.0 - f * f))).rounded(.up))
			return clampI(d, 1, p.depth)
		}
		return 0
	}

	/// True within `pad` columns of a pond (its sandy banks, and where trees keep back)
	func nearPond(_ x: Int, _ pad: Int) -> Bool {
		if !options.flat || !options.ponds { return false }
		let c: Int = floorDiv(x, WorldGen.pondCell)
		for cc in (c - 1)...(c + 1) {
			if let p = pondSite(cell: cc), abs(x - p.cx) <= p.halfW + pad { return true }
		}
		return false
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
	/// a number no other chunk made in this run has (the renderer only reuses a picture of the land
	/// for the very chunk it was drawn from)
	let serial: Int = Chunk.nextSerial()
	static var serialCount: Int = 0
	static func nextSerial() -> Int {
		serialCount += 1
		return serialCount
	}
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
	/// which blocks were put there rather than generated (see World.isBuilt); empty until the first
	var built: [UInt8] = []
	/// how many stair tiles the chunk holds (-1: not counted yet; see World.stairsNear)
	var stairs: Int = -1
	/// how full each part-full liquid cell is (1...254 of 255; 0: a whole block or no liquid), and how
	/// many there are (see p12c_fluids)
	var level: [UInt8] = []
	var partials: Int = 0
	/// Sparkworks wiring over each cell (see Wire), and how many cells have any
	var wires: [UInt8] = []
	var wireCount: Int = 0
	var backRev: Int = -1
	/// change counter per 16-row section (the renderer only rebuilds sections that changed)
	var secRev: [Int]
	/// weather facts re-read when the chunk changes (see World.weatherScan): per column the row rain
	/// stops at, and the weather devices standing in it
	var wxRev: Int = -1
	var wxTop: [Int] = []
	var wxDev: [DeviceSpot] = []

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
	/// above 0: the ore only forms where a broad regional field passes this value, so it is common in
	/// some stretches of land and absent from others
	var region: Double = 0
}

/// Ores by depth (rows count down from the sky; the sea is at 120). Each rule is a field of blobs: rock
/// where the field passes `thr` turns to ore with chance `p`. The first rule that matches wins, so
/// the rare ones come first. Shallow ground has coal, copper, saltpeter and (in some regions) tin;
/// iron and silver start in the middle depths; gold, diamond and mythril are kept for the deep.
let oreRules: [OreRule] = [
	OreRule(tile: .amethyst, minY: 150, maxY: 330, thr: 0.967, p: 0.9, salt: 41),
	OreRule(tile: .saltpeter, minY: 112, maxY: 205, thr: 0.865, p: 0.55, salt: 42),
	OreRule(tile: .tin, minY: 122, maxY: 265, thr: 0.845, p: 0.62, salt: 43, region: 0.47),
	OreRule(tile: .coal, minY: 120, maxY: 340, thr: 0.81, p: 0.66, salt: 31),
	OreRule(tile: .copper, minY: 125, maxY: 345, thr: 0.84, p: 0.65, salt: 32),
	OreRule(tile: .silver, minY: 200, maxY: 400, thr: 0.913, p: 0.6, salt: 44),
	OreRule(tile: .iron, minY: 205, maxY: 450, thr: 0.86, p: 0.56, salt: 33),
	OreRule(tile: .gold, minY: 310, maxY: 530, thr: 0.885, p: 0.58, salt: 34),
	OreRule(tile: .diamond, minY: 390, maxY: 548, thr: 0.925, p: 0.55, salt: 35),
	OreRule(tile: .mythril, minY: 455, maxY: 548, thr: 0.945, p: 0.55, salt: 36)
]

/// Generator 6: iron from row 150 (some 35 blocks under the ground instead of 90), and a little more
/// coal, copper and tin; everything deeper as before
let oreRules6: [OreRule] = [
	OreRule(tile: .amethyst, minY: 150, maxY: 330, thr: 0.967, p: 0.9, salt: 41),
	OreRule(tile: .saltpeter, minY: 112, maxY: 205, thr: 0.865, p: 0.55, salt: 42),
	OreRule(tile: .tin, minY: 122, maxY: 265, thr: 0.832, p: 0.62, salt: 43, region: 0.47),
	OreRule(tile: .coal, minY: 120, maxY: 340, thr: 0.79, p: 0.66, salt: 31),
	OreRule(tile: .copper, minY: 125, maxY: 345, thr: 0.82, p: 0.65, salt: 32),
	OreRule(tile: .silver, minY: 200, maxY: 400, thr: 0.913, p: 0.6, salt: 44),
	OreRule(tile: .iron, minY: 150, maxY: 450, thr: 0.86, p: 0.56, salt: 33),
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
	// saltpeter crusts form in dry ground and hardly at all in wet
	case (.desert, .saltpeter): return 0.05
	case (.savanna, .saltpeter): return 0.04
	case (.mountain, .saltpeter): return 0.02
	case (.swamp, .saltpeter), (.jungle, .saltpeter), (.ocean, .saltpeter): return -0.2
	case (.mountain, .tin), (.tundra, .tin): return 0.03
	case (.mountain, .silver), (.tundra, .silver): return 0.02
	default: return 0
	}
}

/// the broad field that decides where regional ores (tin) form
func oreRegion(_ x: Int, _ salt: UInt64, _ seed: UInt64) -> Double {
	return vnoise(Double(x) * 0.006, 0.37, seed &+ salt &+ 900)
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

	/// The ore table this world generates with
	var oreTable: [OreRule] { return genVersion >= 6 ? oreRules6 : oreRules }

	func oreAt(_ x: Int, _ y: Int, _ biome: Biome) -> Tile? {
		let fx: Double = Double(x)
		let fy: Double = Double(y)
		for r in oreTable {
			if y < r.minY || y > r.maxY { continue }
			if r.region > 0 && oreRegion(x, r.salt, seed) < r.region { continue }
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

	/// The chance a column starts a tree (four columns are always kept between trees)
	func treeDensity(_ b: Biome, _ h: Int, _ x: Int = Int.min) -> Double {
		if genVersion >= 6 { return treeDensity6(b, h, x) }
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

	/// Generator 6: about half as many trees again, and a grove around the spawn, so the first wood is
	/// never far away (forests stay walkable: trees still stand at least four columns apart)
	func treeDensity6(_ b: Biome, _ h: Int, _ x: Int) -> Double {
		var d: Double = 0
		switch b {
		case .forest: d = 0.22
		case .plains: d = 0.10
		case .jungle: d = 0.24
		case .savanna: d = 0.065
		case .tundra: d = 0.12
		case .swamp: d = 0.13
		case .mountain: d = h > 98 ? 0.08 : 0.0
		case .desert: return 0.035
		default: return 0.0
		}
		if x != Int.min && abs(x - spawnX) < 110 && b != .mountain { d = max(d, 0.22) }
		return d
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
		samp.startColumn(x, c.h, caves: !g.options.flat || g.options.caves)
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
		if g.options.flat {
			fillFlatColumn(ch, g, &samp, lx, x, h, sb, c.biome)
		} else {
			fillStandardColumn(ch, g, &samp, lx, x, h, sb, c.biome)
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
	// mine headframes and grotto cave mouths keep their ground clear as well
	let mines: [MineSite] = g.mineSites(overlapping: x0 - 20, x0 + chunkW + 20)
	var mouths: [Int] = []
	for s in g.grottoSites(overlapping: x0 - 30, x0 + chunkW + 30) where s.open { mouths.append(s.passStartX + s.dir * s.passLen) }
	func blocked(_ x: Int) -> Bool {
		for v in villages { if abs(x - v.x) < v.halfW + 6 { return true } }
		for r in rares { if abs(x - r.x) < 16 { return true } }
		for mn in mines { if x >= mn.x - 6 && x <= mn.x + (mn.plan == nil ? 8 : 11) { return true } }
		for mx in mouths { if abs(x - mx) < 16 { return true } }
		if let l = g.lairAt(x, radius: 110) { _ = l; return true }
		// flat worlds keep the spawn point clear of trees, and trees out of ponds
		if g.options.flat && (abs(x - g.spawnX) < 5 || g.nearPond(x, 2)) { return true }
		return false
	}
	func isTree(_ x: Int) -> Bool {
		let c: Col = colAt(x)
		let d: Double = g.treeDensity(c.biome, c.h, x)
		if d <= 0 { return false }
		if hash2(x, 3, g.seed &+ 99) >= d { return false }
		if c.h > sea - 1 && c.biome != .swamp { return false }
		return true
	}
	for lx in -6..<(chunkW + 6) where g.hasTrees {
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
		// trees: origin at x, drawn clipped into this chunk; four columns apart (from generator 6
		// three, except the broad jungle trees)
		if !isTree(x) { continue }
		if isTree(x - 1) || isTree(x - 2) { continue }
		if (g.genVersion < 6 || c.biome == .jungle) && isTree(x - 3) { continue }
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
			let needles: Tile = g.genVersion >= 3 ? .pineLeaves : .leaves
			let th: Int = 6 + Int(tr * 5.0)
			for k in 1...th { ch.put(x, gy - k, .log) }
			var layer: Int = 0
			while layer < th - 1 {
				let wdt: Int = min(3, 1 + layer / 2)
				for dx in -wdt...wdt { ch.putIfAir(x + dx, gy - th - 1 + layer, needles) }
				layer += 1
			}
			ch.putIfAir(x, gy - th - 2, needles)
		} else if tb == .swamp {
			let th: Int = 4 + Int(tr * 2.0)
			for k in 1...th { ch.put(x, gy - k, .log) }
			for dx in -3...3 { ch.putIfAir(x + dx, gy - th, .jungleLeaves); if abs(dx) < 3 { ch.putIfAir(x + dx, gy - th - 1, .jungleLeaves) } }
		} else {
			// newer worlds mix birches into forests and plains, and tall pines into forests
			let variety: Double = g.genVersion >= 3 ? hash2(x, 8, g.seed &+ 96) : 1.0
			if variety < 0.3 && (tb == .forest || tb == .plains) {
				// birch: a slim white trunk under a narrow, airy crown
				let th: Int = 6 + Int(tr * 4.0)
				for k in 1...th { ch.put(x, gy - k, .birchLog) }
				for dy in -4...0 {
					let w: Int = (dy == -4 || dy == 0) ? 1 : 2
					for dx in -w...w {
						if abs(dx) == 2 && hash2(x + dx, gy + dy, g.seed &+ 95) < 0.3 { continue }
						ch.putIfAir(x + dx, gy - th + dy, .birchLeaves)
					}
				}
				ch.putIfAir(x, gy - th - 5, .birchLeaves)
			} else if variety < 0.44 && tb == .forest {
				// pine: tall, with a stepped cone of dark needles
				let th: Int = 10 + Int(tr * 5.0)
				for k in 1...th { ch.put(x, gy - k, .log) }
				var layer: Int = 0
				while layer < th - 4 {
					var wdt: Int = min(3, 1 + layer / 3)
					if layer % 3 == 0 && layer > 0 { wdt -= 1 }
					for dx in -wdt...wdt { ch.putIfAir(x + dx, gy - th - 1 + layer, .pineLeaves) }
					layer += 1
				}
				ch.putIfAir(x, gy - th - 2, .pineLeaves)
			} else {
				let th: Int = 4 + Int(tr * 4.0)
				for k in 1...th { ch.put(x, gy - k, .log) }
				for dy in -3...1 { for dx in -2...2 {
					if abs(dx) == 2 && (dy == -3 || dy == 1) { continue }
					ch.putIfAir(x + dx, gy - th + dy, .leaves)
				} }
			}
		}
	}
	// palms on warm beaches
	for lx in 0..<chunkW where g.hasTrees {
		let x: Int = x0 + lx
		let c: Col = colAt(x)
		if c.biome == .ocean || c.h < sea - 3 || c.h > sea + 1 { continue }
		if ch.get(lx, c.h) != .sand || ch.get(lx, c.h - 1) != .air { continue }
		if hash2(x, 6, g.seed &+ 97) > 0.035 { continue }
		let th: Int = 6 + Int(hash2(x, 7, g.seed &+ 97) * 4.0)
		for k in 1...th { ch.put(x + (k > th - 3 ? 1 : 0), c.h - k, .palmLog) }
		for dx in -3...4 { ch.putIfAir(x + 1 + dx, c.h - th - (abs(dx - 0) > 2 ? 0 : 1), .jungleLeaves) }
	}
	if g.hasLandmarks { placeLandmarks(g, ch, colAt, blocked) }
	applyStructures(g, ch, cols, x0 - m)
	if ModRuntime.shared.hasWorldGen { applyModGen(g, ch, .overworld) }
	ch.rebuildSky()
	return ch
}

/// One column of a standard world: the biome's surface and topsoil, sea water above low ground,
/// rock layers, caves (with underground lakes and deep lava) and ores
func fillStandardColumn(_ ch: Chunk, _ g: WorldGen, _ samp: inout GenSampler, _ lx: Int, _ x: Int, _ h: Int, _ sb: Biome, _ biome: Biome) {
	let H: Int = WorldGen.H
	let sea: Int = WorldGen.sea
	let base: Int = lx * H
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
					if let o = samp.oreAt(x, y, biome) { t = o }
				}
			}
			tp[base + y] = t.rawValue
			y += 1
		}
	}
}

/// One column of a flat world: the same layers everywhere. The surface block and four rows of
/// topsoil follow the biome; below them stone to row 300, slate to 430, deep rock, and a three-row
/// bedrock floor, with ores in the rock. With caves on, tunnels and chambers (and their lakes and deep
/// lava) open up only below an unbroken crust, so nothing underground ever reaches the surface.
/// Ponds sit in the ground with their water level with the surface, on a sandy bed with sandy banks.
func fillFlatColumn(_ ch: Chunk, _ g: WorldGen, _ samp: inout GenSampler, _ lx: Int, _ x: Int, _ h: Int, _ surfBiome: Biome, _ biome: Biome) {
	let H: Int = WorldGen.H
	var topT: Tile = .grass
	var fillT: Tile = .dirt
	switch surfBiome {
	case .desert: topT = .sand; fillT = .sand
	case .tundra: topT = .snow
	case .jungle: topT = .jungleGrass; fillT = .mud
	case .savanna: topT = .dryGrass
	case .swamp: topT = .mossGrass; fillT = .mud
	default: break
	}
	let pond: Int = g.pondDepth(x)
	if pond == 0 && g.nearPond(x, 1) { topT = .sand }
	let caves: Bool = g.options.caves
	let base: Int = lx * H
	var y: Int = h
	while y < H {
		let depth: Int = y - h
		var t: Tile
		if y >= H - 3 { t = .bedrock }
		else if depth < pond { t = (surfBiome == .tundra && depth == 0) ? .ice : .water }
		else if depth == pond && pond > 0 { t = .sand }
		else if depth == 0 { t = topT }
		else if depth <= 4 { t = fillT }
		else if y < 300 { t = .stone }
		else if y < 430 { t = .slate }
		else { t = .deepRock }
		if y < H - 5 && depth >= WorldGen.flatCrust && caves && samp.isCave(x, y, depth) {
			if y >= 500 { t = .lava }
			else if y > 200 && y < 430 && hash2(x / 60, y / 48, g.seed &+ 28) < 0.28 && (y % 48) > 28 { t = .water }
			else { t = .air }
		} else if depth > 8 && y < H - 5, let o = samp.oreAt(x, y, biome) {
			t = o
		}
		ch.tiles[base + y] = t.rawValue
		y += 1
	}
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
	/// the ore table of the world being generated (see WorldGen.oreTable)
	let rules: [OreRule]

	init(_ g: WorldGen) {
		seed = g.seed
		H = WorldGen.H
		rules = g.oreTable
		nOre = rules.count
		region = UnsafeMutablePointer<Double>.allocate(capacity: H)
		tunnel = UnsafeMutablePointer<Double>.allocate(capacity: H)
		width = UnsafeMutablePointer<Double>.allocate(capacity: H)
		cham = UnsafeMutablePointer<Double>.allocate(capacity: H)
		shaft = UnsafeMutablePointer<Double>.allocate(capacity: H)
		ores = UnsafeMutablePointer<Double>.allocate(capacity: H * rules.count)
		oreLo = UnsafeMutablePointer<Int>.allocate(capacity: rules.count)
		oreHi = UnsafeMutablePointer<Int>.allocate(capacity: rules.count)
		oreThr = UnsafeMutablePointer<Double>.allocate(capacity: rules.count)
		oreP = UnsafeMutablePointer<Double>.allocate(capacity: rules.count)
		oreSalt = UnsafeMutablePointer<UInt64>.allocate(capacity: rules.count)
		oreTile = UnsafeMutablePointer<UInt8>.allocate(capacity: rules.count)
		for k in 0..<rules.count {
			oreP[k] = rules[k].p
			oreSalt[k] = rules[k].salt
			oreTile[k] = rules[k].tile.rawValue
			oreThr[k] = rules[k].thr
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

	/// Call once per column (h = surface row) before sampling it. Without caves only the ore fields
	/// are prepared (isCave must not be called then).
	mutating func startColumn(_ cx: Int, _ h: Int, caves: Bool = true) {
		rockY3 = Int.min
		let fx: Double = Double(cx)
		if caves { startCaves(cx, h) }
		var k: Int = 0
		while k < nOre {
			let lo: Int = max(rules[k].minY, h + 9)
			var hi: Int = min(rules[k].maxY, H - 6)
			// a regional ore is missing from this column altogether outside its region
			if rules[k].region > 0 && oreRegion(cx, oreSalt[k], seed) < rules[k].region { hi = lo - 1 }
			oreLo[k] = lo
			oreHi[k] = hi
			if hi >= lo { fill(ores + k * H, seed &+ oreSalt[k], fx * 0.22, 0.22, lo, hi) }
			k += 1
		}
	}

	private mutating func startCaves(_ cx: Int, _ h: Int) {
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
				oreThr[k] = rules[k].thr - oreBias(biome, rules[k].tile)
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
	/// free-standing uprights (porch, smithy, stall and well posts): trunk tiles, which can be walked
	/// through, so a building never walls off the way along the ground
	var beam: Tile
	/// see WorldGen.passableStructures
	var passable: Bool = true
}

func villagePalette(_ b: Biome, passable: Bool) -> Palette {
	var p: Palette = villagePaletteBase(b)
	p.passable = passable
	if !passable { p.beam = p.post }
	return p
}

func villagePaletteBase(_ b: Biome) -> Palette {
	switch b {
	case .desert: return Palette(wall: .sandstone, post: .sandstone, roof: .sandstone, floor: .sandstone, path: .sandstone, beam: .palmLog)
	case .tundra: return Palette(wall: .planks, post: .log, roof: .snow, floor: .planks, path: .stone, beam: .log)
	case .savanna: return Palette(wall: .planks, post: .log, roof: .hay, floor: .planks, path: .dirt, beam: .log)
	case .jungle: return Palette(wall: .planks, post: .jungleLog, roof: .hay, floor: .planks, path: .mud, beam: .jungleLog)
	default: return Palette(wall: .planks, post: .log, roof: .brick, floor: .planks, path: .dirt, beam: .log)
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
	// a door in each end wall (the way along the ground always goes through a house), and a
	// window above one of them
	let doorLeft: Bool = hash2(x, 1, seed) < 0.5
	let wx: Int = doorLeft ? x + w - 1 : x
	if pal.passable {
		for dx in [x, x + w - 1] { ch.put(dx, gy - 1, .doorClosed); ch.put(dx, gy - 2, .doorClosed) }
		if ht >= 4 { ch.put(wx, gy - 3, .glass) }
	} else {
		let dx: Int = doorLeft ? x : x + w - 1
		ch.put(dx, gy - 1, .doorClosed); ch.put(dx, gy - 2, .doorClosed)
		ch.put(wx, gy - 3, .glass)
	}
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
	ch.fill(x, gy - 4, x, gy - 2, pal.beam)
	ch.fill(x + 4, gy - 4, x + 4, gy - 2, pal.beam)
	// a plank cover level with the lip, so the way through the village walks straight over the well
	// (drop through it to reach the water)
	if pal.passable { ch.fill(x + 1, gy - 1, x + 3, gy - 1, .platform) }
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
	ch.fill(x, gy - 4, x, gy - 1, pal.beam)
	ch.fill(x + w - 1, gy - 4, x + w - 1, gy - 1, pal.beam)
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
	ch.fill(x, gy - 3, x, gy - 1, pal.beam)
	ch.fill(x + w - 1, gy - 3, x + w - 1, gy - 1, pal.beam)
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
	if pal.passable { ch.put(x + w - 1, gy - 1, .doorClosed); ch.put(x + w - 1, gy - 2, .doorClosed) }
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
	let pal: Palette = villagePalette(v.biome, passable: g.passableStructures)
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
	buildHouse(ch, x, gy, w, 5, villagePalette(.plains, passable: g.passableStructures), s.seed)
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
	// the way back up: a ladder under a platform in the floor
	if g.passableStructures {
		ch.put(x + 3, gy, .platform)
		ch.fill(x + 3, gy + 1, x + 3, gy + 6, .ladder)
	}
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
	if g.passableStructures {
		for dx in [x, x + w - 1] { ch.fill(dx, gy - 3, dx, gy - 1, .air) }
	} else {
		ch.put(x, gy - 1, .air); ch.put(x, gy - 2, .air); ch.put(x, gy - 3, .air)
	}
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
	// rubble mounds (no higher than a jump where structures are passable)
	let capH: Int = g.passableStructures ? 3 : 4
	for dx in 8...14 { let hgt: Int = min(capH, max(0, 4 - abs(dx - 11))); ch.fill(x + dx, gy - hgt, x + dx, gy - 1, .stone) }
	for dx in 22...28 { let hgt: Int = max(0, 3 - abs(dx - 25)); ch.fill(x + dx, gy - hgt, x + dx, gy - 1, .brick) }
	// broken gateways through each wall block, so the fort can be walked through
	if g.passableStructures { for wx in [x, x + 9, x + 25, x + 34] { ch.fill(wx, gy - 3, wx, gy - 1, .air) } }
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
	// the tent flap is open on the fire side
	if g.passableStructures { ch.put(x + 9, gy - 1, .air); ch.put(x + 8, gy - 2, .air) }
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
		if g.passableStructures {
			// the shafts are crumbled to their back walls; their capitals still stand overhead
			ch.fillWall(px, gy - ph + 1, px + 1, gy - 1, 6)
			ch.fill(px, gy - ph, px + 1, gy - ph, .mossBrick)
			if hash2(p, 3, s.seed) < 0.5 { ch.put(px, gy - 1, .mossBrick) }
		} else {
			ch.fill(px, gy - ph, px + 1, gy - 1, .mossBrick)
		}
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

/// Row the boss stands on: the floor of the pit, or the ground of a flat world's open arena
func lairFloorRow(_ g: WorldGen) -> Int { return g.options.flat ? WorldGen.flatSurface : WorldGen.sea - 10 + 9 }

func buildLair(_ g: WorldGen, _ ch: Chunk, _ L: LairInfo) {
	if g.options.flat {
		buildFlatLair(g, ch, L)
		return
	}
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
	// rim decorations: marker stones (low enough to jump where structures are passable; a full jump
	// clears three blocks)
	let rimH: Int = g.passableStructures ? 2 : 4
	for side in [-1, 1] {
		let rx: Int = cx + side * 44
		ch.fill(rx, gy - rimH, rx, gy - 1, .stone)
		ch.put(rx, gy - rimH - 1, .torch)
		let rx2: Int = cx + side * 36
		ch.put(rx2, gy - 1, .torch)
	}
	if isRex {
		// the half-buried ribs of something enormous: two-block stubs curling over at the top, low
		// enough that the nest floor can still be crossed with a jump
		for side in [-1, 1] {
			for rb in 0..<3 {
				let bx: Int = cx + side * (14 + rb * 8)
				if g.passableStructures {
					ch.fill(bx, gy + 7, bx, gy + 8, .fossil)
					ch.put(bx - side, gy + 7, .fossil)
				} else {
					// older worlds: full ribs arching over the nest
					let top: Int = gy + 9 - 10 - rb
					ch.fill(bx, top, bx, gy + 8, .fossil)
					ch.put(bx - side, top - 1, .fossil)
					ch.put(bx - 2 * side, top - 1, .fossil)
				}
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

/// A flat world's lair: an open arena on the surface instead of a pit, paved and ringed with low
/// marker stones, so the ground stays level. The boss fights on the surface (see lairFloorRow).
func buildFlatLair(_ g: WorldGen, _ ch: Chunk, _ L: LairInfo) {
	let gy: Int = WorldGen.flatSurface
	let cx: Int = L.cx
	let kraw: UInt64 = UInt64(L.kind.rawValue + 1)
	let seed: UInt64 = g.seed &+ (kraw &* 7777)
	let isRex: Bool = L.kind == .rex
	for x in (cx - 52)...(cx + 52) {
		if x < ch.x0 || x >= ch.x0 + chunkW { continue }
		let d: Int = abs(x - cx)
		ch.fill(x, gy - 22, x, gy - 1, .air)
		if d <= 39 {
			// the trampled arena floor
			let worn: Bool = hash2(x, 4, seed) < (isRex ? 0.25 : 0.35)
			ch.put(x, gy, isRex ? (worn ? .mossGrass : .mud) : (worn ? .crackedBrick : .stone))
			ch.put(x, gy + 1, isRex ? .mud : .stone)
			if d >= 4 && hash2(x, 1, seed) < 0.07 { ch.put(x, gy, .fossil) }
		} else {
			ch.put(x, gy, isRex ? .jungleGrass : .grass)
			if hash2(x, 3, seed) < 0.12 { ch.put(x, gy - 1, isRex ? .tallGrass : .deadBush) }
		}
	}
	for side in [-1, 1] {
		let rx: Int = cx + side * 44
		ch.fill(rx, gy - 2, rx, gy - 1, .stone)
		ch.put(rx, gy - 3, .torch)
		ch.put(cx + side * 36, gy - 1, .torch)
	}
	if isRex {
		for side in [-1, 1] {
			for rb in 0..<3 {
				let bx: Int = cx + side * (14 + rb * 8)
				ch.fill(bx, gy - 2, bx, gy - 1, .fossil)
				ch.put(bx - side, gy - 2, .fossil)
			}
		}
		for k in 0..<10 { ch.putIfAir(cx - 24 + k * 5, gy - 1, .tallGrass) }
	} else {
		for side in [-1, 1] {
			ch.put(cx + side * 18, gy - 1, .stone)
			ch.put(cx + side * 18, gy - 2, .torch)
		}
	}
	ch.put(cx + (isRex ? -27 : 27), gy - 1, .chest)
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
	if g.genVersion >= 2 {
		buildRift(ch, px, fy, .portalOff)
	} else {
		ch.fill(fx, fy - 8, fx + 6, fy - 8, .portalFrame)
		ch.fill(fx, fy, fx + 6, fy, .portalFrame)
		ch.fill(fx, fy - 8, fx, fy, .portalFrame)
		ch.fill(fx + 6, fy - 8, fx + 6, fy, .portalFrame)
		ch.fill(fx + 1, fy - 7, fx + 5, fy - 1, .portalOff)
	}
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
	for s in g.grottoSites(overlapping: x0, x0 + chunkW - 1) { buildGrotto(g, ch, s) }
	for s in g.mineSites(overlapping: x0, x0 + chunkW - 1) { buildMine(g, ch, s) }
}

// MARK: - Crystal grottos, old mines and surface landmarks (generator version 3)

/// A vaulted cavern deep underground, its walls studded with crystal, a guarded altar chest at the
/// centre, a still pool, and a long stepped passage climbing from it toward the surface (in standard
/// worlds it comes out as a cave mouth; flat worlds keep their crust whole, so there it ends sealed)
struct GrottoSite {
	var cell: Int
	var x: Int
	/// the row the cavern floor is on
	var floorY: Int
	var rx: Int
	var ry: Int
	/// the passage leaves the cavern on this side and climbs one row per column
	var dir: Int
	var passLen: Int
	/// whether the passage reaches the surface
	var open: Bool
	var seed: UInt64
	var passStartX: Int { return x + dir * (rx - 3) }
	var minX: Int { return min(x - rx - 3, passStartX + min(0, dir * passLen) - 2) }
	var maxX: Int { return max(x + rx + 3, passStartX + max(0, dir * passLen) + 2) }
}

/// An old mine: a timber headframe over a covered, laddered shaft, with galleries off it
struct MineSite {
	var cell: Int
	/// left column of the three-wide shaft (the ladder runs up the middle column)
	var x: Int
	var ground: Int
	/// floor rows of the galleries, top to bottom; the last one is the floor of the shaft
	var levels: [Int]
	var left: [Int]
	var right: [Int]
	var seed: UInt64
	/// worlds made with generator version 4 or later: the whole network, laid out once
	var plan: MinePlan? = nil
	var bottom: Int { return levels.last ?? ground }
	var minX: Int { if let p = plan { return p.minX - 2 }; return x - (left.max() ?? 0) - 3 }
	var maxX: Int { if let p = plan { return p.maxX + 2 }; return x + 2 + (right.max() ?? 0) + 3 }
	/// the lowest open row anywhere in the mine
	var deepest: Int { return max(bottom, plan?.maxY ?? bottom) }
}

extension WorldGen {
	static let grottoCell: Int = 700
	static let mineCell: Int = 900
	static let landmarkCell: Int = 72
	/// the longest passage a grotto may have (the deepest floors lie about 280 rows down)
	static let grottoReach: Int = 420

	var hasGrottos: Bool { return genVersion >= 3 && hasStructures && (!options.flat || options.caves) }
	var hasMines: Bool { return genVersion >= 3 && hasStructures }
	var hasLandmarks: Bool { return genVersion >= 3 && hasTrees }

	func grottoSite(cell c: Int) -> GrottoSite? {
		if let v = cache.grottos[c] { return v }
		let v: GrottoSite? = computeGrottoSite(cell: c)
		cache.grottos[c] = v
		return v
	}

	/// whether a grotto passage may come out of the ground at x: dry land with nothing built there
	func caveMouthClear(_ x: Int) -> Bool {
		let c: Col = col(x)
		if c.biome == .ocean || c.h >= WorldGen.sea - 1 { return false }
		if abs(x - spawnX) < 30 || abs(x - portalX) < 60 { return false }
		if lairAt(x, radius: 140) != nil { return false }
		for v in villages(overlapping: x - 20, x + 20) where abs(v.x - x) < v.halfW + 16 { return false }
		for r in rareSites(overlapping: x - 40, x + 40) where abs(r.x - x) < 40 { return false }
		return true
	}

	func computeGrottoSite(cell c: Int) -> GrottoSite? {
		if !hasGrottos { return nil }
		if hash2(c, 601, seed) > 0.6 { return nil }
		let cw: Int = WorldGen.grottoCell
		let x: Int = c * cw + 90 + Int(hash2(c, 602, seed) * Double(cw - 180))
		if !infinite && (x < 260 || x > width - 260) { return nil }
		if abs(x - portalX) < 240 { return nil }
		let rx: Int = 17 + Int(hash2(c, 604, seed) * 9.0)
		let ry: Int = 8 + Int(hash2(c, 605, seed) * 4.0)
		let floorY: Int = 250 + Int(hash2(c, 603, seed) * 130.0)
		let first: Int = hash2(c, 606, seed) < 0.5 ? -1 : 1
		var site = GrottoSite(cell: c, x: x, floorY: floorY, rx: rx, ry: ry, dir: first, passLen: 0, open: false, seed: hashU(c, 607, seed))
		// trace the passage up one row per column; try the other side if the first comes out badly
		var best: (Int, Int, Bool)? = nil
		for d in [first, -first] {
			let sx: Int = x + d * (rx - 3)
			var k: Int = 0
			var result: (Int, Bool)? = nil
			var checked: Bool = false
			while k < WorldGen.grottoReach {
				let px: Int = sx + d * k
				if !infinite && (px < 40 || px > width - 40) { result = (max(0, k - 1), false); break }
				let h: Int = col(px).h
				let fk: Int = floorY - k
				if options.flat {
					// stop while the passage roof is still below the crust
					if fk - 5 < h + WorldGen.flatCrust { result = (max(0, k - 1), false); break }
				} else {
					if !checked && fk <= h + 8 {
						// the last stretch: open only onto clear, dry ground
						checked = true
						var clear: Bool = true
						var j: Int = 0
						while j <= 16 && clear { clear = caveMouthClear(px + d * j); j += 4 }
						if !clear {
							// generator 6: the passage stops short enough that its roof keeps four rows of
							// ground over it, even where the land drops away just there
							var kk: Int = k
							if genVersion >= 6 {
								while kk > 0 && floorY - kk - 4 <= col(sx + d * kk).h + 3 { kk -= 1 }
							}
							result = (kk, false)
							break
						}
					}
					if fk <= h { result = (k, true); break }
				}
				k += 1
			}
			let r: (Int, Bool) = result ?? (k, false)
			if r.1 { best = (d, r.0, true); break }
			if best == nil { best = (d, r.0, false) }
		}
		if let b = best {
			site.dir = b.0
			site.passLen = b.1
			site.open = b.2
		}
		return site
	}

	func grottoSites(overlapping x0: Int, _ x1: Int) -> [GrottoSite] {
		var out: [GrottoSite] = []
		if !hasGrottos { return out }
		let cw: Int = WorldGen.grottoCell
		let c0: Int = floorDiv(x0 - WorldGen.grottoReach - 40, cw)
		let c1: Int = floorDiv(x1 + WorldGen.grottoReach + 40, cw)
		for c in c0...c1 {
			if let s = grottoSite(cell: c), s.maxX >= x0 && s.minX <= x1 { out.append(s) }
		}
		return out
	}

	func mineSite(cell c: Int) -> MineSite? {
		if let v = cache.mines[c] { return v }
		let v: MineSite? = computeMineSite(cell: c)
		cache.mines[c] = v
		return v
	}

	func computeMineSite(cell c: Int) -> MineSite? {
		if !hasMines { return nil }
		if hash2(c, 621, seed) > (genVersion >= 4 ? 0.62 : 0.55) { return nil }
		let cw: Int = WorldGen.mineCell
		let ok: [Biome] = [.plains, .forest, .mountain, .tundra, .savanna, .desert]
		// a few tries across the cell for a level spot to sink the shaft
		func usable(_ x: Int) -> Col? {
			if !infinite && (x < 320 || x > width - 320) { return nil }
			if abs(x - spawnX) < 60 || abs(x - portalX) < 80 { return nil }
			let base: Col = col(x)
			if !ok.contains(base.biome) || base.h >= WorldGen.sea - 1 { return nil }
			for d in -4...6 {
				let cc: Col = col(x + d)
				if cc.biome == .ocean || abs(cc.h - base.h) > 1 { return nil }
			}
			if lairAt(x, radius: 200) != nil { return nil }
			if nearestVillageSimple(x) { return nil }
			for r in rareSites(overlapping: x - 70, x + 70) where abs(r.x - x) < 70 { return nil }
			return base
		}
		var found: (Int, Col)? = nil
		for attempt in 0..<10 {
			let x: Int = c * cw + 120 + Int(hash2(c, 622 + attempt * 3, seed) * Double(cw - 240))
			if let b = usable(x) { found = (x, b); break }
		}
		guard let (x, base) = found else { return nil }
		if genVersion >= 4 {
			let (plan, levels, lefts, rights) = planMine(cell: c, x: x, ground: base.h)
			var site = MineSite(cell: c, x: x, ground: base.h, levels: levels, left: lefts, right: rights, seed: hashU(c, 624, seed))
			site.plan = plan
			return site
		}
		let depth: Int = 60 + Int(hash2(c, 623, seed) * 100.0)
		let n: Int = depth > 130 ? 3 : (depth > 90 ? 2 : 1)
		var levels: [Int] = []
		var left: [Int] = []
		var right: [Int] = []
		for k in 0..<n {
			levels.append(base.h + depth * (k + 1) / n)
			left.append(16 + Int(hash2(c, 630 + k, seed) * 40.0))
			right.append(16 + Int(hash2(c, 640 + k, seed) * 40.0))
		}
		return MineSite(cell: c, x: x, ground: base.h, levels: levels, left: left, right: right, seed: hashU(c, 624, seed))
	}

	func mineSites(overlapping x0: Int, _ x1: Int) -> [MineSite] {
		var out: [MineSite] = []
		if !hasMines { return out }
		let cw: Int = WorldGen.mineCell
		let reach: Int = genVersion >= 4 ? 160 : 80
		for c in floorDiv(x0 - reach, cw)...floorDiv(x1 + reach, cw) {
			if let s = mineSite(cell: c), s.maxX >= x0 && s.minX <= x1 { out.append(s) }
		}
		return out
	}
}

/// Water or lava touching carved-out space becomes stone, so nothing hangs in the air
private func sealLiquid(_ ch: Chunk, _ x: Int, _ y: Int) {
	if ch.at(x, y).liquid { ch.put(x, y, .stone) }
}

func buildGrotto(_ g: WorldGen, _ ch: Chunk, _ s: GrottoSite) {
	let cx0: Int = ch.x0
	let cx1: Int = ch.x0 + chunkW - 1
	let rxD: Double = Double(s.rx)
	let ryD: Double = Double(s.ry)
	let fy: Int = s.floorY
	let xa: Int = max(cx0, s.x - s.rx - 3)
	let xb: Int = min(cx1, s.x + s.rx + 3)
	if xa <= xb {
		for x in xa...xb {
			let u: Double = Double(x - s.x) / rxD
			let wob: Double = 1.0 + (vnoise(Double(x) * 0.18, 3.0, s.seed) - 0.5) * 0.26
			let inner: Double = wob * wob - u * u
			let vaultD: Double = inner > 0 ? (sqrt(inner) / wob * ryD).rounded() : 0
			let vault: Int = Int(vaultD)
			let ow: Double = wob * 1.28
			let outer: Double = ow * ow - u * u
			let shellD: Double = outer > 0 ? (sqrt(outer) / ow * ryD * 1.2).rounded() + 1.0 : 0
			let shell: Int = Int(shellD)
			let side: Double = -Double(s.dir)
			let along: Double = u * side
			let pool: Bool = along > 0.45 && along < 0.8
			// crystal-studded shell around the vault
			if shell > 0 {
				for y in (fy - shell - 1)...(fy + 1) {
					if y >= fy - vault && y < fy { continue }
					let t: Tile = ch.at(x, y)
					if t.liquid { ch.put(x, y, .stone); continue }
					if !t.solid || t == .bedrock { continue }
					let r: Double = hash2(x, y, s.seed &+ 3)
					if r < 0.22 { ch.put(x, y, .crystalOre) } else if r < 0.27 { ch.put(x, y, .glowCrystal) }
				}
			}
			if vault <= 0 { continue }
			for y in (fy - vault)..<fy { ch.put(x, y, .air) }
			// a level floor (stone bridges any cave below), or the pool
			if pool {
				ch.put(x, fy, .water)
				ch.put(x, fy + 1, .water)
				if !ch.at(x, fy + 2).solid { ch.put(x, fy + 2, .stone) }
				sealLiquid(ch, x, fy + 2)
			} else if !ch.at(x, fy).solid || ch.at(x, fy) == .glowCrystal {
				ch.put(x, fy, .stone)
			}
			// crystals hanging from the vault and standing on the floor
			if vault > 4 && hash2(x, 1, s.seed &+ 5) < 0.14 { ch.put(x, fy - vault, .glowCrystal) }
			if !pool && abs(x - s.x) > 7 && hash2(x, 2, s.seed &+ 5) < 0.08 { ch.put(x, fy - 1, .glowCrystal) }
		}
		// the altar, its chest, and two crystal pillars standing guard
		for dx in -2...2 { ch.put(s.x + dx, fy - 1, .mossBrick) }
		ch.put(s.x, fy - 2, .chest)
		for side in [-1, 1] {
			ch.put(s.x + side * 6, fy - 1, .glowCrystal)
			ch.put(s.x + side * 6, fy - 2, .glowCrystal)
		}
	}
	// the passage: four rows tall, climbing one row per column, lit by crystals in its roof
	if s.passLen <= 0 { return }
	let sx: Int = s.passStartX
	for k in 0...s.passLen {
		let px: Int = sx + s.dir * k
		if px < cx0 || px > cx1 { continue }
		let fk: Int = fy - k
		for y in (fk - 4)...(fk - 1) where ch.at(px, y) != .bedrock { ch.put(px, y, .air) }
		if !ch.at(px, fk).solid && k < s.passLen - 2 { ch.put(px, fk, .stone) }
		sealLiquid(ch, px, fk)
		sealLiquid(ch, px, fk - 5)
		if k % 7 == 3 && ch.at(px, fk - 5).solid && ch.at(px, fk - 5) != .bedrock { ch.put(px, fk - 5, .glowCrystal) }
		if s.open {
			// near the mouth, clear away trunks and leaves left hanging over the cut
			let h: Int = g.col(px).h
			let lo: Int = max(1, h - 18)
			let hi: Int = fk - 4
			if fk - 5 <= h + 1 && lo < hi {
				for y in lo..<hi {
					let t: Tile = ch.at(px, y)
					if isLogTile(t) || isLeafTile(t) { ch.put(px, y, .air) }
				}
			}
		}
	}
}

func buildMine(_ g: WorldGen, _ ch: Chunk, _ s: MineSite) {
	let cx0: Int = ch.x0
	let cx1: Int = ch.x0 + chunkW - 1
	let gy: Int = s.ground
	let bottom: Int = s.bottom
	let sx: Int = s.x
	let plankWall: UInt8 = 5
	func clipped(_ a: Int, _ b: Int) -> ClosedRange<Int>? {
		let lo: Int = max(a, cx0)
		let hi: Int = min(b, cx1)
		return lo <= hi ? lo...hi : nil
	}
	// the headframe: two timber posts (background walls, so they never block the way), a beam you
	// can stand on, a lantern under it, torches either side
	if let r = clipped(sx - 2, sx + 4) {
		for x in r {
			for y in (gy - 7)...(gy - 1) {
				let t: Tile = ch.at(x, y)
				if t.isPlant || isLogTile(t) || isLeafTile(t) { ch.put(x, y, .air) }
			}
		}
	}
	ch.fillWall(sx - 1, gy - 5, sx - 1, gy - 1, plankWall)
	ch.fillWall(sx + 3, gy - 5, sx + 3, gy - 1, plankWall)
	ch.fill(sx - 1, gy - 6, sx + 3, gy - 6, .platform)
	ch.put(sx + 1, gy - 5, .lantern)
	ch.put(sx - 2, gy - 1, .torch)
	ch.put(sx + 4, gy - 1, .torch)
	if let plan = s.plan {
		// version 4: the shaft is covered with boards you drop through; the network lies below
		if let r = clipped(sx, sx + 2) { for x in r { ch.put(x, gy, .platform) } }
		// an ore cart left on a short run of rail by the headframe
		if let r = clipped(sx + 5, sx + 9) {
			for x in r where (ch.at(x, gy - 1) == .air || ch.at(x, gy - 1).isPlant) && ch.at(x, gy).solid { ch.put(x, gy - 1, x == sx + 7 ? .oreCart : .rail) }
		}
		buildMinePlan(g, ch, s, plan)
		return
	}
	let galleryRows: Set<Int> = Set(s.levels.flatMap { [$0 - 3, $0 - 2, $0 - 1] })
	// the shaft: covered with planks you can drop through, a ladder all the way down
	if let r = clipped(sx, sx + 2) {
		for x in r {
			ch.put(x, gy, .platform)
			for y in (gy + 1)..<bottom { ch.put(x, y, x == sx + 1 ? .ladder : .air) }
			ch.put(x, bottom, .planks)
			ch.fillWall(x, gy + 1, x, bottom - 1, plankWall)
		}
	}
	// timber lining where the shaft passes through open cave or water
	for x in [sx - 1, sx + 3] where x >= cx0 && x <= cx1 {
		for y in (gy + 1)..<bottom where !galleryRows.contains(y) {
			let t: Tile = ch.at(x, y)
			if !t.solid || t.liquid { ch.put(x, y, .planks) }
		}
	}
	// the galleries
	for (i, f) in s.levels.enumerated() {
		let xa: Int = sx - s.left[i]
		let xb: Int = sx + 2 + s.right[i]
		let depthBelow: Int = f - gy
		if let r = clipped(xa, xb) {
			for x in r {
				let inShaft: Bool = x >= sx && x <= sx + 2
				if inShaft {
					// landings either side of the ladder at the upper galleries
					if f != bottom && x != sx + 1 { ch.put(x, f, .platform) }
					continue
				}
				let rel: Int = x < sx ? sx - x : x - (sx + 2)
				for y in (f - 3)...(f - 1) { ch.put(x, y, .air) }
				if !ch.at(x, f).solid || ch.at(x, f).liquid { ch.put(x, f, .planks) }
				sealLiquid(ch, x, f - 4)
				if rel % 6 == 3 {
					// a timber support: posts behind, a beam overhead
					ch.fillWall(x, f - 3, x, f - 1, plankWall)
					ch.put(x, f - 4, .planks)
				} else if rel % 12 == 7 {
					ch.put(x, f - 1, .torch)
				}
				if rel % 6 == 4 && hash2(x, f + 1, s.seed) < 0.35 { ch.put(x, f - 3, .cobweb) }
				// ore showing in the roof and floor
				let r0: Double = hash2(x, f, s.seed &+ 7)
				if r0 < 0.09 && rel % 6 != 3 {
					let ores: [Tile] = depthBelow < 80 ? [.coal, .copper, .coal] : (depthBelow < 130 ? [.iron, .copper, .coal] : [.iron, .gold, .iron])
					let ore: Tile = ores[Int(hash2(x, f, s.seed &+ 8) * 3.0) % 3]
					let oy: Int = r0 < 0.05 ? f - 4 : f
					if ch.at(x, oy).solid && ch.at(x, oy) != .planks { ch.put(x, oy, ore) }
				}
			}
		}
		// one end keeps a chest, the other has caved in
		let chestLeft: Bool = hash2(i, 650, s.seed) < 0.5
		if hash2(i, 651, s.seed) < 0.75 { ch.put(chestLeft ? xa + 1 : xb - 1, f - 1, .chest) }
		let rubble: Int = chestLeft ? xb : xa
		ch.put(rubble, f - 1, .stone)
		ch.put(rubble, f - 2, .stone)
	}
}

// MARK: - Old mines, version 4: a branching network round a laddered shaft

/// Where a chest in a mine sits, which sets what it may hold: out in a gallery, in a side room or at
/// a dead end, or hidden (behind fallen rock, or in a nook high in a chamber roof)
enum MineSpot: Int {
	case open, room, hidden
}

struct MineChest {
	var x: Int
	var y: Int
	var spot: MineSpot
	/// 0 for the top gallery, rising with depth (the great chamber counts one deeper)
	var depth: Int
}

/// A column of open space carved out of the rock
struct MineSpan {
	var x: Int
	var y0: Int
	var y1: Int
}

struct MineTile {
	var x: Int
	var y: Int
	var t: Tile
}

struct MineWall {
	var x: Int
	var y0: Int
	var y1: Int
}

/// Everything a v4 mine is made of, worked out once per site: the spaces to carve, the floors to make
/// sound, the timber walls behind, the fittings, the ore showing in the walls and the chests. Each
/// chunk applies the part that falls inside it, in the same order, so a mine is seamless across chunks.
struct MinePlan {
	var carve: [MineSpan] = []
	var floors: [MineTile] = []
	var walls: [MineWall] = []
	var tiles: [MineTile] = []
	/// ore exposed in the rock face: only placed where the rock is still solid
	var ores: [MineTile] = []
	var chests: [MineChest] = []
	var minX: Int = 0
	var maxX: Int = 0
	var maxY: Int = 0
	/// how the mine is laid out (for tests, and to keep the variety honest)
	var tunnels: Int = 0
	var rooms: Int = 0
	var chambers: Int = 0
	var winzes: Int = 0
	var deadEnds: Int = 0
	/// where the great chamber is, if there is one (its centre column and floor row)
	var chamberX: Int = 0
	var chamberFloor: Int = 0
}

/// One gallery as laid out: where it starts, which way it runs and its floor row at each column
struct MineRun {
	var startX: Int
	var dir: Int
	var floors: [Int]
	var depth: Int
	func x(_ k: Int) -> Int { return startX + dir * k }
}

/// Builds a plan. Everything is drawn from the site's own seeded generator, so the same world seed
/// always gives the same mine. Side workings are tried one at a time and kept only if the space they
/// would open does not run into space already opened (apart from where they are meant to join),
/// so no drift ever cuts across a gallery or lays its floor in someone else's way.
struct MinePlanner {
	var plan: MinePlan = MinePlan()
	var rng: RNG
	let shaftX: Int
	let ground: Int
	/// every open cell so far, for the overlap test
	var open: Set<Int> = []

	init(seed: UInt64, shaftX: Int, ground: Int) {
		rng = RNG(seed)
		self.shaftX = shaftX
		self.ground = ground
		plan.minX = shaftX - 3
		plan.maxX = shaftX + 5
	}

	@inline(__always) static func key(_ x: Int, _ y: Int) -> Int { return x &* 4096 &+ y }

	mutating func chance(_ p: Double) -> Bool { return rng.double() < p }
	mutating func range(_ lo: Int, _ hi: Int) -> Int { return lo + rng.int(max(1, hi - lo + 1)) }

	mutating func carve(_ x: Int, _ y0: Int, _ y1: Int) {
		if y1 < y0 { return }
		plan.carve.append(MineSpan(x: x, y0: y0, y1: y1))
		plan.minX = min(plan.minX, x - 1)
		plan.maxX = max(plan.maxX, x + 1)
		plan.maxY = max(plan.maxY, y1 + 1)
	}

	mutating func tile(_ x: Int, _ y: Int, _ t: Tile) { plan.tiles.append(MineTile(x: x, y: y, t: t)) }
	mutating func floor(_ x: Int, _ y: Int) { plan.floors.append(MineTile(x: x, y: y, t: .planks)) }
	mutating func wall(_ x: Int, _ y0: Int, _ y1: Int) { plan.walls.append(MineWall(x: x, y0: y0, y1: y1)) }
	mutating func ore(_ x: Int, _ y: Int, _ t: Tile) { plan.ores.append(MineTile(x: x, y: y, t: t)) }

	/// chests go in last, each on sound floor (see buildMinePlan)
	mutating func chest(_ x: Int, _ y: Int, _ spot: MineSpot, _ depth: Int) {
		if plan.chests.contains(where: { abs($0.x - x) <= 1 && $0.y == y }) { return }
		plan.chests.append(MineChest(x: x, y: y, spot: spot, depth: depth))
	}

	/// marks everything carved since `from` as open
	mutating func commit(_ from: Int) {
		var i: Int = from
		while i < plan.carve.count {
			let sp: MineSpan = plan.carve[i]
			for y in sp.y0...sp.y1 { open.insert(MinePlanner.key(sp.x, y)) }
			i += 1
		}
	}

	/// Lays out a side working with `body`; keeps it only if what it carves (and the floor and fittings
	/// it lays) stays clear of space opened before, except inside the joint (`jx0...jx1` x `jy0...jy1`)
	@discardableResult
	mutating func attempt(_ jx0: Int, _ jx1: Int, _ jy0: Int, _ jy1: Int, _ body: (inout MinePlanner) -> Void) -> Bool {
		let snap: MinePlan = plan
		let c0: Int = plan.carve.count
		let f0: Int = plan.floors.count
		let t0: Int = plan.tiles.count
		body(&self)
		func clash(_ x: Int, _ y: Int) -> Bool {
			if x >= jx0 && x <= jx1 && y >= jy0 && y <= jy1 { return false }
			return open.contains(MinePlanner.key(x, y))
		}
		var bad: Bool = false
		var i: Int = c0
		while i < plan.carve.count && !bad {
			let sp: MineSpan = plan.carve[i]
			for y in (sp.y0 - 1)...(sp.y1 + 1) where clash(sp.x, y) || clash(sp.x - 1, y) || clash(sp.x + 1, y) { bad = true; break }
			i += 1
		}
		// a floor plank or a fitting laid inside space that is already open would be in the way
		var j: Int = f0
		while j < plan.floors.count && !bad { if clash(plan.floors[j].x, plan.floors[j].y) { bad = true }; j += 1 }
		var k: Int = t0
		while k < plan.tiles.count && !bad { if clash(plan.tiles[k].x, plan.tiles[k].y) { bad = true }; k += 1 }
		if bad {
			plan = snap
			return false
		}
		commit(c0)
		return true
	}

	/// The ore that shows in a mine's rock face at row y, following the same depth bands as the ore in
	/// the open ground: coal, copper, tin and saltpeter up top, iron and silver from the middle depths,
	/// gold only deep down, and a little amethyst in between
	mutating func oreFor(_ y: Int) -> Tile {
		let r: Double = rng.double()
		if y < 205 { return r < 0.45 ? .coal : (r < 0.75 ? .copper : (r < 0.92 ? .tin : .saltpeter)) }
		if y < 300 { return r < 0.22 ? .coal : (r < 0.38 ? .copper : (r < 0.5 ? .tin : (r < 0.8 ? .iron : (r < 0.95 ? .silver : .amethyst)))) }
		return r < 0.15 ? .coal : (r < 0.55 ? .iron : (r < 0.8 ? .silver : .gold))
	}

	/// A run of gallery from x0 out to x1 (either way) whose floor drifts up and down a row at a
	/// time, with timber sets, torches, rails, cobwebs and ore along it
	mutating func gallery(from x0: Int, to x1: Int, floor f0: Int, depth: Int, rails: Bool, lit: Double) -> MineRun {
		let dir: Int = x1 >= x0 ? 1 : -1
		let n: Int = abs(x1 - x0) + 1
		var floors: [Int] = []
		var f: Int = f0
		var nextStep: Int = range(7, 15)
		let support: Int = range(5, 7)
		let torchGap: Int = range(10, 15)
		var lastTorch: Int = -range(2, 6)
		var k: Int = 0
		while k < n {
			let x: Int = x0 + dir * k
			// the floor drifts a row now and then, never far from the level's own height
			if k == nextStep && k > 3 && k < n - 3 {
				let d: Int = chance(0.5) ? 1 : -1
				if abs(f + d - f0) <= 3 { f += d }
				nextStep = k + range(7, 15)
			}
			floors.append(f)
			let tall: Bool = k > 0 && floors[k - 1] != f
			carve(x, f - (tall ? 4 : 3), f - 1)
			floor(x, f)
			var torch: Bool = false
			if k % support == support / 2 && k > 1 {
				// a timber set: posts behind, a beam overhead (a few have rotted away)
				if chance(0.85) {
					wall(x, f - 3, f - 1)
					tile(x, f - 4 - (tall ? 1 : 0), .planks)
				} else {
					wall(x, f - 2, f - 1)
				}
			} else if k - lastTorch >= torchGap && chance(lit) {
				tile(x, f - 1, .torch)
				lastTorch = k
				torch = true
			} else if chance(0.05 + 0.03 * Double(depth)) {
				tile(x, f - 3, .cobweb)
			}
			if rails && !torch && k > 2 && !tall && chance(0.92) { tile(x, f - 1, .rail) }
			// ore showing in the roof and floor
			if chance(0.085) { ore(x, chance(0.55) ? f - 4 - (tall ? 1 : 0) : f, oreFor(f)) }
			k += 1
		}
		plan.tunnels += 1
		return MineRun(startX: x0, dir: dir, floors: floors, depth: depth)
	}

	/// A storage room above the gallery, reached by a short ladder through its roof
	mutating func storageRoom(_ x: Int, _ f: Int, _ depth: Int) {
		let w: Int = range(6, 9)
		let x0: Int = x - w / 2
		let x1: Int = x0 + w - 1
		let rf: Int = f - 5
		let h: Int = 4
		for xx in x0...x1 {
			carve(xx, rf - h, rf - 1)
			floor(xx, rf)
			wall(xx, rf - h, rf - 1)
		}
		// the hatch: a ladder from the gallery up through the room's floor
		carve(x, rf, f - 4)
		for y in rf...(f - 1) { tile(x, y, .ladder) }
		// crates stacked along the walls, a lantern, and the chest in a corner
		let crateLeft: Bool = chance(0.5)
		let cx: Int = crateLeft ? x0 : x1
		tile(cx, rf - 1, .crate)
		if chance(0.6) { tile(cx, rf - 2, .crate) }
		let other: Int = crateLeft ? x1 : x0
		tile(other, rf - 1, .crate)
		tile(x, rf - h, .lantern)
		chest(crateLeft ? x0 + 1 : x1 - 1, rf - 1, .room, depth)
		plan.rooms += 1
	}

	/// An abandoned work area: the gallery opens up, a workbench and furnace stand cold, a cart sits
	/// off its rails; sometimes a chest of the crew's things
	mutating func workArea(_ run: MineRun, _ k0: Int, _ w: Int) {
		let f: Int = run.floors[k0]
		for j in 0..<w {
			let xx: Int = run.x(k0 + j)
			carve(xx, f - 5, f - 4)
			wall(xx, f - 5, f - 1)
		}
		tile(run.x(k0 + 1), f - 1, .workbench)
		tile(run.x(k0 + 2), f - 1, .furnace)
		tile(run.x(k0 + w - 2), f - 1, .oreCart)
		tile(run.x(k0 + w / 2), f - 5, .lantern)
		if chance(0.5) { chest(run.x(k0 + w - 3), f - 1, .room, run.depth) }
		plan.rooms += 1
	}

	/// A ladder down from the gallery to a short drift that runs off one way and ends blind
	mutating func winze(_ x: Int, _ f: Int, _ depth: Int, _ drop: Int) {
		let bottom: Int = f + drop
		carve(x, f, bottom - 1)
		for y in f...(bottom - 1) { tile(x, y, .ladder) }
		let dir: Int = chance(0.5) ? 1 : -1
		let len: Int = range(12, 24)
		let run: MineRun = gallery(from: x, to: x + dir * len, floor: bottom, depth: depth + 1, rails: false, lit: 0.3)
		plan.winzes += 1
		deadEnd(run.x(len), run.floors.last ?? bottom, dir, depth + 1)
	}

	/// A ladder up through the gallery roof to a short drift above it that ends blind
	mutating func raise(_ x: Int, _ f: Int, _ depth: Int, _ rise: Int) {
		let top: Int = f - rise
		carve(x, top - 3, f - 4)
		for y in (top - 1)...(f - 1) { tile(x, y, .ladder) }
		let dir: Int = chance(0.5) ? 1 : -1
		let len: Int = range(10, 20)
		let run: MineRun = gallery(from: x + dir, to: x + dir * len, floor: top, depth: depth, rails: false, lit: 0.3)
		plan.winzes += 1
		deadEnd(run.x(len - 1), run.floors.last ?? top, dir, depth)
	}

	/// A sloping drift carried on past the end of a gallery, climbing or falling a row every two
	/// columns, to a dead end
	mutating func ramp(_ x: Int, _ f: Int, _ dir: Int, _ depth: Int) {
		let rise: Int = chance(0.5) ? -1 : 1
		let rows: Int = range(4, 7)
		var ff: Int = f
		for k in 0..<(rows * 2) {
			if k % 2 == 1 { ff += rise }
			let xx: Int = x + dir * k
			carve(xx, ff - 3 - (k % 2 == 1 ? 1 : 0), ff - 1)
			floor(xx, ff)
		}
		let x1: Int = x + dir * (rows * 2)
		let len: Int = range(5, 12)
		let run: MineRun = gallery(from: x1, to: x1 + dir * len, floor: ff, depth: depth, rails: false, lit: 0.2)
		deadEnd(run.x(len), run.floors.last ?? ff, dir, depth)
	}

	/// The blind end of a drift at x: bare rock and a cart, or a chest left behind, or a fall of rock
	/// that hides a little pocket with a chest in it (dig through to find it)
	mutating func deadEnd(_ x: Int, _ f: Int, _ dir: Int, _ depth: Int) {
		plan.deadEnds += 1
		let r: Double = rng.double()
		if r < 0.3 {
			chest(x - dir, f - 1, .room, depth)
		} else if r < 0.55 {
			attempt(x, x, f - 4, f) { p in p.collapse(x, f, dir, depth) }
		} else if r < 0.75 {
			tile(x - dir, f - 1, .oreCart)
		}
		// otherwise just the rock face
	}

	/// rubble two or three blocks thick at the end of a drift, then the pocket beyond it
	mutating func collapse(_ x: Int, _ f: Int, _ dir: Int, _ depth: Int) {
		let thick: Int = range(2, 3)
		for j in 1...thick {
			let xx: Int = x + dir * j
			carve(xx, f - 3, f - 1)
			for y in (f - 3)...(f - 1) { tile(xx, y, rubble()) }
			floor(xx, f)
		}
		let p0: Int = x + dir * (thick + 1)
		for j in 0..<4 {
			carve(p0 + dir * j, f - 3, f - 1)
			floor(p0 + dir * j, f)
		}
		chest(p0 + dir * 3, f - 1, .hidden, depth)
		tile(p0 + dir * 1, f - 3, .cobweb)
	}

	/// what a collapse is made of: broken stone, earth and rotten timber
	mutating func rubble() -> Tile {
		let r: Double = rng.double()
		return r < 0.45 ? .stone : (r < 0.8 ? .dirt : .planks)
	}

	/// The great chamber on the lowest level: a tall hall over the gallery shored up with timber, a
	/// scaffold half-way up with a chest on it, ore-rich walls, and a nook high in the roof with
	/// something tucked away (only reached by building up to it)
	mutating func chamber(_ run: MineRun, _ kc: Int, _ hw: Int) {
		let f: Int = run.floors[kc]
		let cx: Int = run.x(kc)
		let h: Int = range(9, 12)
		for dx in -hw...hw {
			let x: Int = cx + dx
			let u: Double = Double(dx) / Double(hw)
			let top: Int = f - 3 - Int((Double(h - 3) * (1.0 - u * u)).rounded())
			carve(x, top, f - 4)
			if abs(dx) % 7 == 3 && abs(dx) < hw - 1 { wall(x, top, f - 1) }
			if chance(0.3) { ore(x, top - 1, oreFor(top)) }
		}
		for y in (f - 6)...(f - 1) where chance(0.4) {
			ore(cx - hw - 1, y, oreFor(y))
			ore(cx + hw + 1, y, oreFor(y))
		}
		// the scaffold: a walkway half-way up with a ladder at one end
		let sy: Int = f - 5
		let s0: Int = cx - hw / 2
		let s1: Int = cx + hw / 2
		for x in s0...s1 { tile(x, sy, .platform) }
		for y in sy...(f - 1) { tile(s0, y, .ladder) }
		chest(s1 - 1, sy - 1, .room, run.depth + 1)
		tile(cx, f - h + 1, .lantern)
		// the nook: a hollow just above the roof's high point
		if chance(0.6) {
			let ny: Int = f - h - 1
			carve(cx + 2, ny - 1, ny)
			carve(cx + 3, ny - 1, ny)
			floor(cx + 3, ny + 1)
			chest(cx + 3, ny, .hidden, run.depth + 1)
		}
		plan.chambers += 1
		plan.chamberX = cx
		plan.chamberFloor = f
	}
}

extension WorldGen {
	/// Lays out a version-4 mine at `x` (left column of the three-wide shaft) on ground row `ground`
	func planMine(cell c: Int, x: Int, ground: Int) -> (MinePlan, [Int], [Int], [Int]) {
		var p = MinePlanner(seed: hashU(c, 700, seed), shaftX: x, ground: ground)
		let depth: Int = 60 + p.rng.int(100)
		let nLevels: Int = depth > 135 ? 4 : (depth > 95 ? 3 : 2)
		var levels: [Int] = []
		for k in 0..<nLevels {
			var f: Int = ground + depth * (k + 1) / nLevels
			if k < nLevels - 1 { f += p.range(-3, 3) }
			levels.append(f)
		}
		let bottom: Int = levels.last ?? (ground + depth)
		// the shaft: three wide, a ladder up the middle, covered over at the top
		for xx in x...(x + 2) {
			p.carve(xx, ground + 1, bottom - 1)
			p.wall(xx, ground + 1, bottom - 1)
		}
		for y in (ground + 1)...(bottom - 1) { p.tile(x + 1, y, .ladder) }
		for xx in x...(x + 2) { p.floor(xx, bottom) }
		// first every level's landing and its two galleries
		var lefts: [Int] = []
		var rights: [Int] = []
		var runs: [(MineRun, MineRun)] = []
		for (i, f) in levels.enumerated() {
			let left: Int = p.range(24, 64)
			let right: Int = p.range(24, 64)
			lefts.append(left)
			rights.append(right)
			let rails: Bool = i < 2 && p.chance(0.7)
			let lit: Double = max(0.25, 0.9 - 0.2 * Double(i))
			for xx in x...(x + 2) { p.carve(xx, f - 3, f - 1) }
			if f != bottom {
				p.tile(x, f, .platform)
				p.tile(x + 2, f, .platform)
			}
			let l: MineRun = p.gallery(from: x - 1, to: x - left, floor: f, depth: i, rails: rails, lit: lit)
			let r: MineRun = p.gallery(from: x + 3, to: x + 2 + right, floor: f, depth: i, rails: rails, lit: lit)
			runs.append((l, r))
		}
		p.commit(0)
		// the great chamber, on the lowest level, along its longer gallery
		if p.chance(0.66), let last = runs.last {
			let run: MineRun = last.0.floors.count >= last.1.floors.count ? last.0 : last.1
			if run.floors.count >= 30 {
				let hw: Int = p.range(9, min(13, (run.floors.count - 10) / 2))
				let kc: Int = p.range(hw + 4, run.floors.count - hw - 4)
				let cx: Int = run.x(kc)
				// the hall opens round its own gallery, whose floor wanders a few rows: all of that is the joint
				p.attempt(cx - hw - 2, cx + hw + 2, run.floors[kc] - 8, run.floors[kc] + 4) { q in q.chamber(run, kc, hw) }
			}
		}
		// then the side workings along each gallery, each kept only if it fits
		for (i, pair) in runs.enumerated() {
			for run in [pair.0, pair.1] {
				let n: Int = run.floors.count
				var k: Int = p.range(8, 13)
				while k < n - 6 {
					let gx: Int = run.x(k)
					let gf: Int = run.floors[k]
					let r: Double = p.rng.double()
					var used: Int = 0
					if r < 0.24 {
						if p.attempt(gx - 1, gx + 1, gf - 6, gf) { q in q.storageRoom(gx, gf, i) } { used = 10 }
					} else if r < 0.42 {
						let drop: Int = p.range(8, 13)
						if p.attempt(gx - 1, gx + 1, gf - 4, gf + 1) { q in q.winze(gx, gf, i, drop) } { used = 9 }
					} else if r < 0.56 {
						let rise: Int = p.range(7, 10)
						if p.attempt(gx - 1, gx + 1, gf - 5, gf) { q in q.raise(gx, gf, i, rise) } { used = 9 }
					} else if r < 0.7 {
						let w: Int = p.range(6, 8)
						if k + w < n - 2 && (0..<w).allSatisfy({ run.floors[k + $0] == gf }) {
							let xa: Int = min(run.x(k), run.x(k + w - 1))
							let xb: Int = max(run.x(k), run.x(k + w - 1))
							if p.attempt(xa - 1, xb + 1, gf - 4, gf) { q in q.workArea(run, k, w) } { used = w + 2 }
						}
					}
					k += max(used, p.range(5, 9)) + p.range(3, 7)
				}
				// the far end: a slope carried on to a dead end, or the dead end itself
				let endX: Int = run.x(n - 1)
				let endF: Int = run.floors.last ?? levels[i]
				if p.chance(0.4) {
					let ja: Int = min(endX, endX + run.dir)
					let jb: Int = max(endX, endX + run.dir)
					if !p.attempt(ja, jb, endF - 4, endF + 1, { q in q.ramp(endX + run.dir, endF, run.dir, i) }) {
						p.deadEnd(endX, endF, run.dir, i)
					}
				} else {
					p.deadEnd(endX, endF, run.dir, i)
				}
			}
		}
		return (p.plan, levels, lefts, rights)
	}
}

/// Builds the part of a version-4 mine that falls in this chunk: carve, seal any water or lava that
/// would pour in, make the floors sound, timber behind, fittings, ore in the rock face, then chests
func buildMinePlan(_ g: WorldGen, _ ch: Chunk, _ s: MineSite, _ plan: MinePlan) {
	let cx0: Int = ch.x0
	let cx1: Int = ch.x0 + chunkW - 1
	@inline(__always) func inside(_ x: Int) -> Bool { return x >= cx0 && x <= cx1 }
	for sp in plan.carve where sp.x >= cx0 - 1 && sp.x <= cx1 + 1 {
		if inside(sp.x) { for y in sp.y0...sp.y1 { ch.put(sp.x, y, .air) } }
	}
	for sp in plan.carve where sp.x >= cx0 - 1 && sp.x <= cx1 + 1 {
		for y in sp.y0...sp.y1 {
			if ch.at(sp.x - 1, y).liquid { ch.put(sp.x - 1, y, .stone) }
			if ch.at(sp.x + 1, y).liquid { ch.put(sp.x + 1, y, .stone) }
		}
		if ch.at(sp.x, sp.y0 - 1).liquid { ch.put(sp.x, sp.y0 - 1, .stone) }
		if ch.at(sp.x, sp.y1 + 1).liquid { ch.put(sp.x, sp.y1 + 1, .stone) }
	}
	for f in plan.floors where inside(f.x) {
		let t: Tile = ch.at(f.x, f.y)
		if !t.solid || t.liquid { ch.put(f.x, f.y, f.t) }
	}
	let plankWall: UInt8 = 5
	for w in plan.walls where inside(w.x) { ch.fillWall(w.x, w.y0, w.x, w.y1, plankWall) }
	for t in plan.tiles where inside(t.x) { ch.put(t.x, t.y, t.t) }
	for o in plan.ores where inside(o.x) {
		let t: Tile = ch.at(o.x, o.y)
		if t == .stone || t == .slate || t == .deepRock || t == .sandstone { ch.put(o.x, o.y, o.t) }
	}
	for c in plan.chests where inside(c.x) {
		let below: Tile = ch.at(c.x, c.y + 1)
		if !(below.solid || below == .platform) || below.liquid { ch.put(c.x, c.y + 1, .planks) }
		ch.put(c.x, c.y, .chest)
	}
}

/// The small set pieces scattered over the land
enum Landmark {
	case boulder, mossyBoulder, snowBoulder, fallenLog, fallenJungleLog, mossyLog, meadow, mushroomRing
	case bones, sandstoneRuin, iceSpikes, cairn, termiteMound, reeds

	var halfWidth: Int {
		switch self {
		case .boulder, .mossyBoulder, .snowBoulder, .termiteMound: return 2
		case .fallenLog, .fallenJungleLog, .mossyLog, .bones, .sandstoneRuin, .reeds: return 4
		case .meadow: return 6
		case .mushroomRing, .iceSpikes: return 3
		case .cairn: return 1
		}
	}

	static func pick(_ b: Biome, _ r: Double) -> Landmark? {
		switch b {
		case .plains: return r < 0.4 ? .boulder : (r < 0.75 ? .meadow : .fallenLog)
		case .forest: return r < 0.45 ? .fallenLog : (r < 0.7 ? .mossyBoulder : .mushroomRing)
		case .jungle: return r < 0.5 ? .fallenJungleLog : .meadow
		case .savanna: return r < 0.45 ? .boulder : (r < 0.75 ? .bones : .termiteMound)
		case .desert: return r < 0.55 ? .bones : .sandstoneRuin
		case .tundra: return r < 0.6 ? .iceSpikes : .snowBoulder
		case .swamp: return r < 0.55 ? .mossyLog : .reeds
		case .mountain: return r < 0.65 ? .boulder : .cairn
		case .ocean, .umbral: return nil
		}
	}
}

/// One landmark (or none) per 72 columns, picked by biome. Each is at most three blocks tall, so it
/// can always be walked or hopped over, and each only goes on level, dry ground away from buildings.
func placeLandmarks(_ g: WorldGen, _ ch: Chunk, _ colAt: (Int) -> Col, _ blocked: (Int) -> Bool) {
	let x0: Int = ch.x0
	let cw: Int = WorldGen.landmarkCell
	for c in floorDiv(x0 - 8, cw)...floorDiv(x0 + chunkW + 8, cw) {
		if hash2(c, 701, g.seed) > 0.5 { continue }
		let lx: Int = c * cw + 8 + Int(hash2(c, 702, g.seed) * Double(cw - 16))
		if lx + 6 < x0 || lx - 6 >= x0 + chunkW { continue }
		if !g.infinite && (lx < 24 || lx > g.width - 24) { continue }
		if abs(lx - g.spawnX) < 14 { continue }
		let base: Col = colAt(lx)
		guard let kind = Landmark.pick(base.biome, hash2(c, 703, g.seed)) else { continue }
		let hw: Int = kind.halfWidth
		var ok: Bool = true
		for d in -hw...hw {
			let cc: Col = colAt(lx + d)
			if cc.biome == .ocean || cc.h >= WorldGen.sea - 1 || abs(cc.h - base.h) > 1 || blocked(lx + d) { ok = false; break }
		}
		if !ok { continue }
		let seed: UInt64 = hashU(c, 704, g.seed)
		// writes over air and small plants only, so trunks and buildings stay as they are
		func place(_ d: Int, _ up: Int, _ t: Tile) {
			let x: Int = lx + d
			let y: Int = colAt(x).h - up
			let cur: Tile = ch.at(x, y)
			if cur == .air || (cur.isPlant && cur != .torch && cur != .lantern) { ch.put(x, y, t) }
		}
		func plant(_ d: Int, _ t: Tile) {
			let x: Int = lx + d
			let h: Int = colAt(x).h
			if x < x0 || x >= x0 + chunkW { return }
			if !ch.at(x, h).solid { return }
			if ch.at(x, h - 1) == .air || ch.at(x, h - 1) == .tallGrass { ch.put(x, h - 1, t) }
		}
		func rnd(_ k: Int) -> Double { return hash2(lx, k, seed) }
		switch kind {
		case .boulder, .mossyBoulder, .snowBoulder:
			let cap: Tile = kind == .mossyBoulder ? .mossGrass : (kind == .snowBoulder ? .snow : .stone)
			let wide: Bool = rnd(1) < 0.5
			for d in -2...2 {
				if abs(d) == 2 && !wide { continue }
				let hgt: Int = abs(d) == 2 || (abs(d) == 1 && !wide) ? 1 : 2
				for k in 1...hgt { place(d, k, k == hgt ? cap : .stone) }
			}
		case .fallenLog, .fallenJungleLog, .mossyLog:
			let len: Int = 4 + Int(rnd(1) * 4.0)
			let start: Int = -len / 2
			let wood: Tile = kind == .fallenJungleLog ? .jungleLogBlock : (rnd(3) < 0.35 && kind == .fallenLog ? .birchLogBlock : .logBlock)
			for d in start..<(start + len) { place(d, 1, wood) }
			if rnd(2) < 0.6 || kind == .mossyLog { place(start + 1, 2, .mushroom) }
			if kind == .mossyLog { place(start + len - 2, 2, .mushroom) }
			plant(start - 1, .tallGrass)
			plant(start + len, .tallGrass)
		case .meadow:
			for d in -6...6 {
				let r: Double = rnd(10 + d)
				plant(d, r < 0.36 ? .flowerR : (r < 0.72 ? .flowerY : .tallGrass))
			}
		case .mushroomRing:
			for d in [-3, -2, 2, 3] { plant(d, .mushroom) }
			plant(0, .tallGrass)
		case .bones:
			for d in -3...3 { place(d, 1, .fossil) }
			for d in [-2, 0, 2] { place(d, 2, .fossil) }
			place(4, 1, .fossil)
			place(4, 2, .fossil)
		case .sandstoneRuin:
			for d in [-3, 3] {
				place(d, 1, .sandstone)
				if rnd(d + 5) < 0.7 { place(d, 2, .sandstone) }
			}
			for d in -1...1 { place(d, 1, .sandstone) }
			if rnd(4) < 0.3 { place(0, 2, .chest) }
		case .iceSpikes:
			for (d, hgt) in [(-2, 2), (0, 3), (2, 2)] where rnd(d + 7) < 0.85 || d == 0 {
				for k in 1...hgt { place(d, k, .ice) }
			}
		case .cairn:
			for k in 1...3 { place(0, k, .stone) }
			place(0, 4, .torch)
			place(-1, 1, .stone)
			place(1, 1, .stone)
		case .termiteMound:
			for (d, hgt) in [(-2, 1), (-1, 2), (0, 3), (1, 2), (2, 1)] {
				for k in 1...hgt { place(d, k, .dirt) }
			}
		case .reeds:
			for d in -4...4 where rnd(20 + d) < 0.7 { plant(d, .reed) }
		}
	}
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
		var raw: Int = uFloorRaw(x)
		if let c = citadel {
			// the citadel stands on level ground, with long ramps down (or up) to the cavern floor
			let dc: Int = abs(x - c.x)
			if dc <= 110 {
				let t: Double = smooth(clampD(Double(dc - 50) / 60.0, 0, 1))
				raw = Int(lerpD(Double(c.floor), Double(raw), t).rounded())
			}
		}
		let d: Int = abs(x - portalX)
		if d > 44 { return raw }
		let t: Double = smooth(clampD((Double(d) - 16.0) / 28.0, 0, 1))
		return Int(lerpD(Double(umbralPortalFloor), Double(raw), t).rounded())
	}

	/// The Hollow Warden's citadel (worlds of generator version 3): some 380 to 540 blocks from the
	/// rift, its gate facing back toward it
	var citadel: CitadelSite? {
		if let c = cache.citadel { return c }
		let c: CitadelSite? = computeCitadel()
		cache.citadel = .some(c)
		return c
	}

	func computeCitadel() -> CitadelSite? {
		if genVersion < 3 { return nil }
		let side: Int = hash2(77, 78, seed) < 0.5 ? -1 : 1
		let dist: Int = 380 + Int(hash2(79, 80, seed) * 160.0)
		var x: Int = portalX + side * dist
		if !infinite && (x < 200 || x > width - 200) { x = portalX - side * dist }
		if !infinite && (x < 200 || x > width - 200) { return nil }
		let floor: Int = clampI(uFloorRaw(x), 190, 226)
		return CitadelSite(x: x, floor: floor, gate: portalX >= x ? 1 : -1)
	}

	func uRuinSite(cell c: Int) -> Int? {
		if hash2(c, 511, seed) > 0.55 { return nil }
		if let cd = citadel, abs(c * 260 + 140 - cd.x) < 200 { return nil }
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
	if let c = g.citadel, abs(c.x - (x0 + chunkW / 2)) < 60 { buildCitadel(g, ch, c) }
	if ModRuntime.shared.hasWorldGen { applyModGen(g, ch, .umbral) }
	ch.rebuildSky()
	return ch
}

/// Where the Hollow Warden keeps its hall
struct CitadelSite {
	var x: Int
	var floor: Int
	/// the side the gate faces (toward the rift); the throne stands at the far end
	var gate: Int
	var throneX: Int { return x - gate * 33 }
	var chestX: Int { return x - gate * 37 }
}

/// A ruined hall: a paved floor between two gate towers, ash-stone walls behind, broken arches above,
/// lanterns on plinths, a throne on a low dais and the Warden's hoard behind it. Both towers have
/// doorways, so the hall can always be walked through.
func buildCitadel(_ g: WorldGen, _ ch: Chunk, _ c: CitadelSite) {
	let f: Int = c.floor
	let seed: UInt64 = g.seed &+ 9191
	for x in (c.x - 50)...(c.x + 50) {
		if x < ch.x0 || x >= ch.x0 + chunkW { continue }
		let dx: Int = x - c.x
		ch.fill(x, f - 22, x, f - 1, .air)
		ch.fill(x, f + 1, x, f + 3, .obsidian)
		ch.put(x, f, abs(dx) % 6 == 0 ? .crackedBrick : .brick)
		if abs(dx) <= 40 { ch.fillWall(x, f - 14, x, f - 1, 4) }
		if abs(dx) == 12 || abs(dx) == 26 { ch.fillWall(x, f - 14, x, f - 1, 6) }
		// gate towers with doorways
		if abs(dx) == 41 || abs(dx) == 42 {
			ch.fill(x, f - 15, x, f - 6, .brick)
			if hash2(x, 3, seed) < 0.3 { ch.put(x, f - 10, .crackedBrick) }
		}
		// the broken arches overhead
		if abs(dx) <= 42 && hash2(x, 4, seed) > 0.2 {
			ch.put(x, f - 16, hash2(x, 5, seed) < 0.25 ? .crackedBrick : .brick)
			if abs(dx) % 9 == 4 { ch.put(x, f - 15, .glowCrystal) }
		}
		// lanterns on plinths
		if abs(dx) == 6 || abs(dx) == 19 || abs(dx) == 33 {
			if x != c.throneX && x != c.chestX {
				ch.put(x, f - 1, .brick)
				ch.put(x, f - 2, .lantern)
			}
		}
	}
	// the throne on its dais, the hoard behind it
	for dx in -3...3 { ch.put(c.throneX + dx, f - 1, .brick) }
	ch.fill(c.throneX - c.gate, f - 4, c.throneX - c.gate, f - 2, .obsidian)
	ch.put(c.throneX + 1, f - 2, .crackedBrick)
	ch.put(c.throneX - 1, f - 2, .crackedBrick)
	ch.put(c.chestX, f - 1, .chest)
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

/// The rift (world version 2+): an oval tear standing on a low basalt plinth, held by two floating
/// anchor crescents and a keystone. Open at the sides, so it is walked into rather than climbed into.
/// The oval occupies the same 5x7 footprint as the old frame's interior, so its centre is unchanged.
func buildRift(_ ch: Chunk, _ px: Int, _ base: Int, _ fill: Tile) {
	riftShape(px, base, fill) { x, y, t in ch.put(x, y, t) }
}

func riftShape(_ px: Int, _ base: Int, _ fill: Tile, _ put: (Int, Int, Tile) -> Void) {
	for dx in -3...3 { put(px + dx, base, .portalFrame) }
	for dy in -7...(-1) {
		for dx in -2...2 {
			let ey: Double = (Double(dy) + 4.0) / 3.6
			let ex: Double = Double(dx) / 2.6
			put(px + dx, base + dy, ex * ex + ey * ey <= 1.0 ? fill : .air)
		}
	}
	for side in [-3, 3] {
		put(px + side, base - 6, .portalFrame)
		put(px + side, base - 5, .portalFrame)
		put(px + side, base - 4, .portalFrame)
	}
	put(px, base - 9, .portalFrame)
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
	if g.genVersion >= 2 {
		buildRift(ch, px, fyb, .portalOn)
	} else {
		ch.fill(fx, fyb - 8, fx + 6, fyb - 8, .portalFrame)
		ch.fill(fx, fyb, fx + 6, fyb, .portalFrame)
		ch.fill(fx, fyb - 8, fx, fyb, .portalFrame)
		ch.fill(fx + 6, fyb - 8, fx + 6, fyb, .portalFrame)
		ch.fill(fx + 1, fyb - 7, fx + 5, fyb - 1, .portalOn)
	}
	// lights and a welcome chest
	ch.put(px - 9, gy - 1, .lantern)
	ch.put(px + 9, gy - 1, .lantern)
	ch.put(px - 12, gy - 1, .glowCrystal)
	ch.put(px + 12, gy - 1, .glowCrystal)
	ch.put(px + 7, gy - 1, .chest)
}

/// What the world's mods add to a freshly made chunk: veins of their ores (and their structures, see
/// applyModStructures). It all comes from the world seed and the chunk's place, so a chunk always comes
/// out the same; the work is done once, when the chunk is first made, never per frame.
func applyModGen(_ g: WorldGen, _ ch: Chunk, _ dim: Dimension) {
	let rt: ModRuntime = ModRuntime.shared
	let d: Int = dim.rawValue
	let H: Int = ch.H
	_ = H
	// each ore places itself (see ModOreRT.place: the original settings give the original veins)
	for o in rt.ores where o.dim == d { o.place(g, ch) }
	applyModStructures(g, ch, dim)
}

/// The ground a custom ore may take the place of: 0 any rock, 1 stone, 2 slate and deep rock,
/// 3 dirt and sand, 4 any natural ground
func modOreHost(_ t: Tile, _ host: Int) -> Bool {
	switch host {
	case 1: return t == .stone
	case 2: return t == .slate || t == .deepRock
	case 3: return t == .dirt || t == .sand || t == .mud
	case 4:
		switch t {
		case .stone, .slate, .deepRock, .ashStone, .sandstone, .dirt, .sand, .mud, .snow: return true
		default: return false
		}
	default:
		switch t {
		case .stone, .slate, .deepRock, .ashStone, .sandstone: return true
		default: return false
		}
	}
}

/// True where a custom structure must not go: the spawn point, the rift gate, and the world's own
/// villages, ruins, mines, lairs and landmarks, and (for one underground) the crystal grottos; on the
/// surface only a grotto's cave mouth matters (Umbral: the gate, the citadel and the ruins)
func modSiteBlocked(_ g: WorldGen, _ dim: Dimension, _ xa: Int, _ xb: Int, _ placement: ModPlacement = .surface) -> Bool {
	func hits(_ a: Int, _ b: Int) -> Bool { return xb > a && xa < b }
	if dim == .umbral {
		if hits(g.portalX - 40, g.portalX + 40) { return true }
		if let c = g.citadel, hits(c.x - 90, c.x + 90) { return true }
		for c in floorDiv(xa - 40, 260)...floorDiv(xb + 40, 260) {
			if let rx = g.uRuinSite(cell: c), hits(rx - 30, rx + 30) { return true }
		}
		return false
	}
	if hits(g.spawnX - 16, g.spawnX + 16) || hits(g.portalX - 50, g.portalX + 50) { return true }
	for v in g.villages(overlapping: xa - 20, xb + 20) where hits(v.x - v.halfW - 6, v.x + v.halfW + 6) { return true }
	for r in g.rareSites(overlapping: xa - 30, xb + 30) where hits(r.x - 16, r.x + 16) { return true }
	for mn in g.mineSites(overlapping: xa - 20, xb + 20) where hits(mn.x - 8, mn.x + 14) { return true }
	for s in g.grottoSites(overlapping: xa - 60, xb + 60) {
		if placement == .underground {
			let p0: Int = min(s.x - s.rx, s.passStartX + min(0, s.dir * s.passLen))
			let p1: Int = max(s.x + s.rx, s.passStartX + max(0, s.dir * s.passLen))
			if hits(p0 - 8, p1 + 8) { return true }
		} else if placement == .surface && s.open {
			let mouth: Int = s.passStartX + s.dir * s.passLen
			if hits(mouth - 16, mouth + 16) { return true }
		}
	}
	for L in g.lairCenters(near: (xa + xb) / 2) where hits(L.cx - 70, L.cx + 70) { return true }
	if placement != .underground {
		let cw: Int = WorldGen.landmarkCell
		for c in floorDiv(xa - 8, cw)...floorDiv(xb + 8, cw) {
			if hash2(c, 701, g.seed) > 0.5 { continue }
			let lx: Int = c * cw + 8 + Int(hash2(c, 702, g.seed) * Double(cw - 16))
			if hits(lx - 7, lx + 7) { return true }
		}
	}
	return false
}

/// A custom structure's site in one of its spacing cells: its left column and top row, or nil when the
/// cell holds none. It comes from the seed and the generator's own ground heights only, so every chunk
/// agrees on it, however the world is explored.
func modStructSite(_ g: WorldGen, _ s: ModStructRT, _ dim: Dimension, _ cell: Int) -> (Int, Int)? {
	let d: ModStructure = s.def
	let sp: Int = max(64, d.spacing)
	let key: UInt64 = g.seed &+ s.salt
	if hash2(cell, 1907, key) >= d.chance { return nil }
	let room: Int = max(1, sp - d.w - 16)
	let sx: Int = cell * sp + 8 + Int(hash2(cell, 1913, key) * Double(room))
	if !g.infinite && (sx < 24 || sx + d.w > g.width - 24) { return nil }
	if modSiteBlocked(g, dim, sx - 4, sx + d.w + 4, d.placement) { return nil }
	let mid: Int = sx + d.w / 2
	let pick: Double = hash2(cell, 1931, key)
	let H: Int = dimHeight(dim)
	var top: Int = 0
	if dim.isCustom {
		guard let cd = ModRuntime.shared.dimRT(dim) else { return nil }
		let surf: Int = cd.surfaceAt(mid, g.seed)
		if !d.biomes.isEmpty && !d.biomes.contains(cd.biomeAt(Double(mid)).rawValue) { return nil }
		switch d.placement {
		case .surface:
			if cd.def.sea > 0 && surf >= cd.def.sea - 1 { return nil }
			top = surf - d.h + 1
		case .underground:
			let lo: Int = max(d.minY, surf + 6)
			let hi: Int = max(lo, d.maxY - d.h)
			top = lo + Int(pick * Double(hi - lo + 1))
		case .sky: top = surf - d.h - 18 - Int(pick * 14.0)
		}
	} else if dim == .overworld {
		let c: Col = g.col(mid)
		if !d.biomes.isEmpty && !d.biomes.contains(c.biome.rawValue) { return nil }
		switch d.placement {
		case .surface:
			// on dry land only; its bottom row takes the place of the ground's top
			if c.biome == .ocean || c.h >= WorldGen.sea { return nil }
			top = c.h - d.h + 1
		case .underground:
			let lo: Int = max(d.minY, c.h + 6)
			let hi: Int = max(lo, d.maxY - d.h)
			top = lo + Int(pick * Double(hi - lo + 1))
		case .sky:
			top = c.h - d.h - 18 - Int(pick * 14.0)
		}
	} else {
		switch d.placement {
		case .surface: top = g.uFloor(mid) - d.h + 1
		case .underground:
			let hi: Int = max(d.minY, d.maxY - d.h)
			top = d.minY + Int(pick * Double(hi - d.minY + 1))
		case .sky: top = g.uCeil(mid) + 1
		}
	}
	top = clampI(top, 2, H - 3 - d.h)
	return (sx, top)
}

/// Builds the custom structures of the world's mods into a freshly made chunk, clipped to it (each chunk
/// builds its own part, so a structure across several chunks comes out whole). Bedrock is never touched;
/// a structure on the surface gets a foundation of earth under it so it never floats.
func applyModStructures(_ g: WorldGen, _ ch: Chunk, _ dim: Dimension) {
	let rt: ModRuntime = ModRuntime.shared
	if rt.structures.isEmpty { return }
	if dim == .overworld && !g.hasLandmarks { return }
	let d: Int = dim.rawValue
	let x0: Int = ch.x0
	let x1: Int = x0 + chunkW - 1
	for s in rt.structures where s.def.dim == d {
		let sp: Int = max(64, s.def.spacing)
		for cell in floorDiv(x0 - ModLimits.maxStructW - 16, sp)...floorDiv(x1, sp) {
			guard let site = modStructSite(g, s, dim, cell) else { continue }
			if site.0 + s.def.w - 1 < x0 || site.0 > x1 { continue }
			buildModStructure(ch, s, site.0, site.1, foundation: s.def.placement == .surface)
		}
	}
}

func buildModStructure(_ ch: Chunk, _ s: ModStructRT, _ sx: Int, _ top: Int, foundation: Bool) {
	let w: Int = s.def.w
	let h: Int = s.def.h
	var cx: Int = 0
	while cx < w {
		let lx: Int = sx + cx - ch.x0
		if lx < 0 || lx >= chunkW {
			cx += 1
			continue
		}
		var cy: Int = 0
		while cy < h {
			let v: Int = s.cells[cy * w + cx]
			let y: Int = top + cy
			if v >= 0 && v < 256 && y >= 1 && y < ch.H - 1 && ch.get(lx, y) != .bedrock {
				ch.setLocal(lx, y, Tile.make(UInt8(v)))
			}
			cy += 1
		}
		if foundation {
			// earth under a solid bottom block, down to the ground (at most 12 rows)
			let bottom: Int = s.cells[(h - 1) * w + cx]
			if bottom > 0 && bottom < 256 && Tile.make(UInt8(bottom)).solid {
				var y: Int = top + h
				var k: Int = 0
				while k < 12 && y < ch.H - 1 && !ch.get(lx, y).solid {
					ch.setLocal(lx, y, .dirt)
					y += 1
					k += 1
				}
			}
		}
		cx += 1
	}
}

extension ModRuntime {
	/// The loot table for a chest that one of the mods' structures put there, if any
	func structureChestLoot(_ g: WorldGen, _ dim: Dimension, _ x: Int, _ y: Int) -> String? {
		let d: Int = dim.rawValue
		if dim == .overworld && !g.hasLandmarks { return nil }
		for s in structures where s.def.dim == d && !s.loot.isEmpty {
			let sp: Int = max(64, s.def.spacing)
			for cell in floorDiv(x - ModLimits.maxStructW - 16, sp)...floorDiv(x, sp) {
				guard let site = modStructSite(g, s, dim, cell) else { continue }
				let cx: Int = x - site.0
				let cy: Int = y - site.1
				if cx < 0 || cy < 0 || cx >= s.def.w || cy >= s.def.h { continue }
				if s.cells[cy * s.def.w + cx] == Int(Tile.chest.rawValue) { return s.loot }
			}
		}
		return nil
	}
}

extension Game {
	// MARK: structure capture

	/// Starts picking a part of the world to save as a structure (two taps on the world)
	func startCapture() {
		capturing = true
		showCapture = false
		capA = nil
		capB = nil
		releaseAllInput()
		say("Tap two corners of what you built.", 4.0)
		bumpHUD()
	}

	func cancelCapture() {
		capturing = false
		showCapture = false
		capA = nil
		capB = nil
		bumpHUD()
	}

	/// A tap while capturing: the first corner, then the second (which opens the save panel); a third
	/// tap starts again
	func captureTap(_ wx: Double, _ wy: Double) {
		let t: (Int, Int) = (Int(floor(wx)), Int(floor(wy)))
		if capA == nil || capB != nil {
			capA = t
			capB = nil
		} else {
			capB = t
			showCapture = true
		}
		bumpHUD()
	}

	/// The selection with its corners in order, held to the largest structure size
	func captureRect() -> (Int, Int, Int, Int)? {
		guard let a = capA else { return nil }
		let b: (Int, Int) = capB ?? (Int(floor(aimX)), Int(floor(aimY)))
		let x0: Int = min(a.0, b.0)
		let y0: Int = min(a.1, b.1)
		let x1: Int = min(max(a.0, b.0), x0 + ModLimits.maxStructW - 1)
		let y1: Int = min(max(a.1, b.1), y0 + ModLimits.maxStructH - 1)
		return (x0, y0, x1, y1)
	}

	/// Turns the selected blocks into a structure. Machines, the rift gate and bedrock are left out (they
	/// can't be copied safely) and counted; empty space either clears the ground or leaves it as it is.
	/// Custom blocks are kept by their keys, so the structure works in any world that has their mod.
	func captureStructure(clearAir: Bool) -> (ModStructure, Int) {
		var st = ModStructure()
		guard let r = captureRect() else { return (st, 0) }
		let rt: ModRuntime = ModRuntime.shared
		st.w = r.2 - r.0 + 1
		st.h = r.3 - r.1 + 1
		st.dim = world.dim == .umbral ? 1 : 0
		if let cd = customDim { st.dimKey = splitModKey(cd.key).1 }
		var skipped: Int = 0
		var cells: [Int] = []
		cells.reserveCapacity(st.w * st.h)
		for y in r.1...r.3 {
			for x in r.0...r.2 {
				let t: Tile = world.tile(x, y)
				if t == .air {
					cells.append(clearAir ? 0 : -1)
				} else if t.isMod {
					var key: String = rt.slotKey[Int(t.rawValue - Tile.modBase)] ?? ""
					if let hash = key.firstIndex(of: "#") { key = String(key[key.startIndex..<hash]) }
					if key.isEmpty {
						cells.append(-1)
						skipped += 1
					} else {
						if !st.palette.contains(key) { st.palette.append(key) }
						cells.append(1000 + (st.palette.firstIndex(of: key) ?? 0))
					}
				} else if !modStructureTileOK(t) {
					cells.append(-1)
					skipped += 1
				} else {
					cells.append(Int(t.rawValue))
				}
			}
		}
		st.cells = cells
		// where it was found decides where it goes: on the surface, underground or up in the sky
		let mid: Int = (r.0 + r.2) / 2
		if world.dim == .overworld {
			let ground: Int = gen.col(mid).h
			if r.3 > ground + 6 {
				st.placement = .underground
				st.minY = clampI(r.1 - 40, 4, 550)
				st.maxY = clampI(r.3 + 40, st.minY, 550)
			} else if r.3 < ground - 12 {
				st.placement = .sky
			}
		}
		return (st, skipped)
	}

	/// Saves the captured structure into a mod (a new one, switched on, when `modID` is empty) and ends
	/// the capture. Returns what to tell the player.
	func saveCapture(name: String, modID: String, newModName: String, placement: ModPlacement, clearAir: Bool) -> String {
		var cap: (ModStructure, Int) = captureStructure(clearAir: clearAir)
		if cap.0.w < 1 || cap.0.h < 1 { return "Pick two corners first." }
		if !cap.0.cells.contains(where: { $0 > 0 }) { return "There are no blocks in that area." }
		var p: ModPack = ModPack()
		var isNew: Bool = true
		if !modID.isEmpty, let existing = ModStore.pack(modID) {
			p = existing
			isNew = false
		} else {
			p.id = newModID()
			let nm: String = newModName.trimmingCharacters(in: .whitespaces)
			p.name = nm.isEmpty ? "My Structures" : String(nm.prefix(32))
		}
		if p.structures.count >= ModLimits.maxStructures { return joinText(p.name, " already holds the most structures a mod can.") }
		let nm: String = name.trimmingCharacters(in: .whitespaces)
		cap.0.name = nm.isEmpty ? "Structure" : String(nm.prefix(32))
		cap.0.placement = placement
		cap.0.id = p.freshID("structure")
		p.structures.append(cap.0)
		if !ModStore.save(p) { return "The mod could not be saved." }
		if isNew { ModStore.setEnabled(p.id, true) }
		cancelCapture()
		let note: String = cap.1 > 0 ? " Machines, bedrock and the rift gate were left out." : ""
		return joinText("Saved \u{201C}", cap.0.name, "\u{201D} in ", p.name, ". New worlds with this mod will have it.", note)
	}
}

/// Blocks a structure may hold: not machines (their wiring and settings can't come along), the rift gate
/// (one per world) or bedrock
func modStructureTileOK(_ t: Tile) -> Bool {
	if t.isPower || t == .bedrock || t == .portalFrame || t == .portalOff || t == .portalOn { return false }
	if Tile(rawValue: t.rawValue) == nil { return false }
	switch t {
	case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater: return false
	default: return true
	}
}

func generateChunk(_ g: WorldGen, _ dim: Dimension, _ cx: Int) -> Chunk {
	if dim.isCustom { return generateCustomChunk(g, dim, cx) }
	return dim == .overworld ? generateOverworldChunk(g, cx) : generateUmbralChunk(g, cx)
}

func dimHeight(_ dim: Dimension) -> Int {
	if dim.isCustom { return customDimH }
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
	var parked: [[Int: Chunk]] = [[Int: Chunk]](repeating: [:], count: dimCount)
	/// bounding box of tile edits since the light map last looked (lets lighting skip far-away edits)
	var editAny: Bool = false
	var editX0: Int = 0
	var editX1: Int = 0
	var editY0: Int = 0
	var editY1: Int = 0
	/// bumps when chunks load/unload or the dimension changes
	var layoutVersion: Int = 0
	/// structural physics is on: every change is noted for it to look at (see Game.updateStructures)
	var structWatch: Bool = false
	var structEdits: [IntPair] = []
	/// liquid cells awake (see p12c_fluids), a step counter, edits that should not wake them (the storm
	/// surge), where lava met water this step, and a count of every level change
	var flowQ: [IntPair] = []
	var flowSet: Set<IntPair> = []
	var flowTick: Int = 0
	var flowHold: Bool = false
	var flowSteam: [IntPair] = []
	var flowRev: Int = 0

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
	/// Sparkworks devices by place (settings and charge), and a counter bumped whenever wiring or
	/// devices change, so the networks are worked out again
	var devs: [ChestKey: PowerDev] = [:]
	var powerRev: Int = 0
	var version: Int = 0
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
			chunks[cx] = c
			wakePartials(c)
		} else {
			let t0: Double = perfNow()
			c = generateChunk(gen, dim, cx)
			Perf.shared.noteGen(perfNow() - t0)
		}
		chunks[cx] = c
		cacheCX = Int.min
		version += 1
		if c.wireCount > 0 { powerRev &+= 1 }
		noteEdit(cx * chunkW, 0)
		noteEdit(cx * chunkW + chunkW - 1, H - 1)
		// the land next door is drawn again with its edge lines toward this chunk
		chunks[cx - 1]?.bumpRows(0, H - 1)
		chunks[cx + 1]?.bumpRows(0, H - 1)
		gen.cache.trim()
		return c
	}

	func unloadChunk(_ cx: Int) {
		guard let c = chunks[cx] else { return }
		if c.dirty { parked[dim.rawValue][cx] = c }
		if c.wireCount > 0 { powerRev &+= 1 }
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
		flowQ.removeAll()
		flowSet.removeAll()
		for (k, c) in chunks { if c.dirty { parked[dim.rawValue][k] = c } }
		chunks.removeAll()
		cacheCX = Int.min
		powerRev &+= 1
		dim = nd
		H = dimHeight(nd)
		version += 1
		layoutVersion += 1
	}

	var dirtyChunkCount: Int {
		var n: Int = 0
		for (_, c) in chunks { if c.dirty { n += 1 } }
		for d in 0..<parked.count { n += parked[d].count }
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
		if !c.level.isEmpty && c.level[lx * H + y] != 0 {
			// a new tile in a part-full liquid cell: it is a whole block of whatever it is now
			c.level[lx * H + y] = 0
			c.partials -= 1
			c.bumpRows(y, y)
		}
		// a new block is not "built" until whoever put it there says so (see setBuilt)
		if !c.built.isEmpty { c.built[lx * H + y] = 0 }
		if c.stairs >= 0 {
			if Tile.stairTable[Int(old.rawValue)] != 0 { c.stairs -= 1 }
			if Tile.stairTable[Int(t.rawValue)] != 0 { c.stairs += 1 }
		}
		if structWatch && structEdits.count < 128 { structEdits.append(IntPair(x: x, y: y)) }
		// a roof can add or remove house walls up to 12 rows below it
		c.bumpRows(y - 1, y + 13)
		// a block on a chunk's edge is drawn with a dark line toward open space next door, and a leaf
		// block with tufts into it, so the neighbour's picture follows when the edge changes
		if (lx == 0 || lx == chunkW - 1) && (old.opaque != t.opaque || isLeafTile(old) != isLeafTile(t)) {
			chunks[lx == 0 ? cx - 1 : cx + 1]?.bumpRows(y, y)
		}
		if old.opaque != t.opaque {
			let before: Int = c.skyTop[lx]
			c.recomputeSky(lx)
			let after: Int = c.skyTop[lx]
			if before != after { c.bumpRows(min(before, after) - 1, max(before, after) + 13) }
		}
		noteEdit(x, y)
		if old.isPower || t.isPower { powerTileChanged(x, y, old, t) }
		if !flowHold { wakeFlow(x, y) }
		return old
	}

	func needsSupport(_ t: Tile) -> Bool {
		if t.isPlant && t != .torch && t != .lantern && t != .cobweb { return true }
		switch t {
		case .workbench, .furnace, .chest, .campfire, .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3, .doorClosed, .doorOpen, .oreCart: return true
		case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane, .heater: return true
		case .crankGen, .solarPanel, .fuelGen, .emberDynamo, .battery, .accumulator, .pressurePlate, .lever: return true
		case .alchemyStill, .infuser, .exoStation: return true
		case .chair, .table, .bedL, .bedR, .cabinet, .wardrobe, .bookshelf, .floorLamp, .sofa: return true
		default: return false
		}
	}

	func supports(_ below: Tile, _ t: Tile) -> Bool {
		switch t {
		case .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3: return below == .farmland
		case .sapling: return isSoil(below)
		case .doorClosed, .doorOpen: return below.solid || below == .doorClosed || below == .doorOpen
		default: return below.supportsThings || below == .platform
		}
	}

	/// Ground a sapling takes root in
	func isSoil(_ t: Tile) -> Bool {
		switch t {
		case .grass, .dirt, .farmland, .jungleGrass, .mossGrass, .dryGrass, .snow, .mud: return true
		default:
			// a custom dimension's own ground takes saplings too
			guard dim.isCustom, let d = ModRuntime.shared.dimRT(dim) else { return false }
			return d.soils.contains(t.rawValue)
		}
	}

	func skyTop(_ x: Int) -> Int {
		let cx: Int = floorDiv(x, chunkW)
		if let c = chunk(cx) { return c.skyTop[x - cx * chunkW] }
		return 0
	}

	func isSkyExposed(_ x: Int, _ y: Int) -> Bool {
		if dim != .overworld && !dimHasSky(dim) { return false }
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
		let rt: ModRuntime = ModRuntime.shared
		var it: [Stack] = []
		if rt.active, let key = rt.structureChestLoot(gen, dim, x, y) {
			var rng = RNG(hashU(x, y, gen.seed &+ 4441))
			it = rt.roll(key, &rng)
		} else {
			// the game's own chests also turn up ingredients (a mod structure's chest holds only its table)
			it = alchemyChestExtras(generateChestLoot(gen, dim, x, y), gen, dim, x, y)
		}
		if rt.active { it = rt.addChestLoot(it, gen, dim, x, y) }
		chests[k] = it
		return it
	}

	func setChestItems(_ x: Int, _ y: Int, _ items: [Stack]) {
		chests[chestKey(x, y)] = items
	}

	func removeChest(_ x: Int, _ y: Int) -> [Stack] {
		let k: ChestKey = chestKey(x, y)
		var out: [Stack] = []
		// storage under a key outside the world (a vehicle's cargo crate, the suit's pack) is never rolled
		if let it = chests[k] { out = it } else if y >= 0 { out = chestItems(x, y) }
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

/// One line of a loot table: what, how many, how likely against the others in its tier, and the
/// shallowest mine level it can turn up at
struct LootEntry {
	var item: Item
	var lo: Int
	var hi: Int
	var weight: Double
	var minDepth: Int = 0
}

/// Mine chest loot by rarity. Most of what a chest holds comes from the common tier; a pull from the
/// useful tier is occasional; a chest gets at most one chance at the exceptional tier, and that chance
/// is small: larger deeper down and in rooms, and largest in chests that were hidden away.
enum MineLoot {
	static let common: [LootEntry] = [
		LootEntry(item: .mat(.coal), lo: 3, hi: 8, weight: 10),
		LootEntry(item: .block(.torch), lo: 3, hi: 8, weight: 9),
		LootEntry(item: .block(.planks), lo: 4, hi: 10, weight: 5),
		LootEntry(item: .mat(.stick), lo: 3, hi: 8, weight: 4),
		LootEntry(item: .mat(.copperOre), lo: 2, hi: 5, weight: 5),
		LootEntry(item: .mat(.tinOre), lo: 2, hi: 4, weight: 4),
		LootEntry(item: .mat(.string), lo: 1, hi: 4, weight: 3),
		LootEntry(item: .food(.bread), lo: 1, hi: 2, weight: 4),
		LootEntry(item: .food(.apple), lo: 1, hi: 3, weight: 2),
		LootEntry(item: .block(.ladder), lo: 2, hi: 6, weight: 3),
		LootEntry(item: .block(.rail), lo: 3, hi: 8, weight: 2),
		LootEntry(item: .mat(.ironOre), lo: 1, hi: 3, weight: 3, minDepth: 1)
	]
	static let useful: [LootEntry] = [
		LootEntry(item: .mat(.ironBar), lo: 1, hi: 3, weight: 6),
		LootEntry(item: .mat(.bronzeBar), lo: 2, hi: 4, weight: 6),
		LootEntry(item: .ammo(.arrow), lo: 6, hi: 14, weight: 4),
		LootEntry(item: .ammo(.bolt), lo: 4, hi: 10, weight: 4),
		LootEntry(item: .ammo(.bullet), lo: 4, hi: 8, weight: 2, minDepth: 1),
		LootEntry(item: .mat(.saltpeter), lo: 2, hi: 5, weight: 3),
		LootEntry(item: .mat(.gunpowder), lo: 2, hi: 4, weight: 3),
		LootEntry(item: .gadget(.fireFlask), lo: 1, hi: 2, weight: 2),
		LootEntry(item: .gadget(.bomb), lo: 1, hi: 2, weight: 2),
		LootEntry(item: .block(.lantern), lo: 1, hi: 2, weight: 3),
		LootEntry(item: .food(.cookedMeat), lo: 1, hi: 3, weight: 3),
		LootEntry(item: .mat(.silverBar), lo: 1, hi: 2, weight: 2, minDepth: 1),
		LootEntry(item: .mat(.goldBar), lo: 1, hi: 2, weight: 2, minDepth: 2),
		LootEntry(item: .mat(.amethyst), lo: 1, hi: 3, weight: 1.5, minDepth: 1),
		LootEntry(item: .knife(.iron), lo: 1, hi: 1, weight: 1.5),
		LootEntry(item: .tool(.pickaxe, .iron), lo: 1, hi: 1, weight: 1.2),
		LootEntry(item: .club(.studded), lo: 1, hi: 1, weight: 1),
		LootEntry(item: .gun(.crossbow), lo: 1, hi: 1, weight: 0.8),
		LootEntry(item: .armor(.head, .iron), lo: 1, hi: 1, weight: 0.8)
	]
	static let exceptional: [LootEntry] = [
		LootEntry(item: .relic(.moonDagger), lo: 1, hi: 1, weight: 2),
		LootEntry(item: .relic(.emberCleaver), lo: 1, hi: 1, weight: 1.5, minDepth: 2),
		LootEntry(item: .relic(.quakeMaul), lo: 1, hi: 1, weight: 1.5, minDepth: 2),
		LootEntry(item: .gun(.repeater), lo: 1, hi: 1, weight: 2, minDepth: 1),
		LootEntry(item: .gun(.stormRod), lo: 1, hi: 1, weight: 1, minDepth: 2),
		LootEntry(item: .mat(.diamond), lo: 1, hi: 3, weight: 3, minDepth: 1),
		LootEntry(item: .mat(.mythrilBar), lo: 1, hi: 2, weight: 1.5, minDepth: 2),
		LootEntry(item: .gear(.swiftBoots), lo: 1, hi: 1, weight: 1.5),
		LootEntry(item: .gear(.headlamp), lo: 1, hi: 1, weight: 2),
		LootEntry(item: .gear(.silverCharm), lo: 1, hi: 1, weight: 1.5),
		LootEntry(item: .mat(.relicFragment), lo: 1, hi: 2, weight: 2)
	]

	/// the chance a chest gets its one pull from the exceptional tier
	static func exceptionalChance(_ spot: MineSpot, _ depth: Int) -> Double {
		var p: Double = 0.012 + 0.008 * Double(depth)
		if spot == .room { p += 0.012 }
		if spot == .hidden { p += 0.05 }
		return min(p, 0.12)
	}

	/// the chance each pull comes from the useful tier rather than the common one
	static func usefulChance(_ spot: MineSpot, _ depth: Int) -> Double {
		var p: Double = 0.18 + 0.05 * Double(depth)
		if spot == .room { p += 0.06 }
		if spot == .hidden { p += 0.15 }
		return min(p, 0.55)
	}

	static func pick(_ table: [LootEntry], _ depth: Int, _ rng: inout RNG) -> LootEntry? {
		let ok: [LootEntry] = table.filter { $0.minDepth <= depth }
		var total: Double = 0
		for e in ok { total += e.weight }
		if total <= 0 { return nil }
		var r: Double = rng.double() * total
		for e in ok {
			r -= e.weight
			if r <= 0 { return e }
		}
		return ok.last
	}

	/// Rolls a mine chest: two to four stacks, never the same item twice, counts within stack limits
	static func roll(_ rng: inout RNG, _ spot: MineSpot, _ depth: Int) -> [Stack] {
		var out: [Stack] = []
		var n: Int = 2 + rng.int(2) + (spot == .open ? 0 : 1)
		func add(_ e: LootEntry, _ rng: inout RNG) -> Bool {
			if out.contains(where: { $0.item == e.item }) { return false }
			let c: Int = min(e.item.maxStack, max(1, e.lo + rng.int(max(1, e.hi - e.lo + 1))))
			out.append(Stack(item: e.item, count: c))
			return true
		}
		if rng.double() < exceptionalChance(spot, depth), let e = pick(exceptional, depth, &rng) {
			if add(e, &rng) { n -= 1 }
		}
		let pu: Double = usefulChance(spot, depth)
		var tries: Int = 0
		while n > 0 && tries < 12 {
			tries += 1
			let table: [LootEntry] = rng.double() < pu ? useful : common
			if let e = pick(table, depth, &rng), add(e, &rng) { n -= 1 }
		}
		if out.isEmpty { out.append(Stack(item: .block(.torch), count: 4)) }
		return out
	}

	static func isExceptional(_ it: Item) -> Bool {
		return exceptional.contains { $0.item == it }
	}
}

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
	if dim == .umbral, let c = g.citadel, abs(x - c.chestX) <= 1 && abs(y - (c.floor - 1)) <= 1 {
		// the Warden's hoard
		add(.mat(.voidBar), 3, 6, 1.0)
		add(.mat(.emberBar), 4, 8, 1.0)
		add(.mat(.diamond), 3, 6, 1.0)
		add(.mat(.relicFragment), 2, 3, 1.0)
		add(.armor(ArmorSlot.allCases[rng.int(3)], .voidium), 1, 1, 0.5)
		add(.spear(.voidium), 1, 1, 0.3)
		return out
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
	// crystal grottos and old mines
	if y > 150 {
		for s in g.grottoSites(overlapping: x - 2, x + 2) where abs(x - s.x) <= s.rx && abs(y - s.floorY) < 6 {
			add(.mat(.crystalShard), 3, 7, 1.0)
			add(.mat(.diamond), 1, 3, 0.7)
			add(.block(.glowCrystal), 2, 5, 0.8)
			add(.mat(.relicFragment), 1, 2, 0.8)
			add(.mat(.mythrilBar), 1, 3, 0.45)
			add(.gear(.headlamp), 1, 1, 0.3)
			add(.spear(tierPick(4, 6)), 1, 1, 0.35)
			return out
		}
	}
	if g.hasMines {
		for s in g.mineSites(overlapping: x - 2, x + 2) where y > s.ground + 8 && y <= s.deepest + 2 {
			if let plan = s.plan {
				// version 4: the plan knows each chest's place, and that sets its loot
				if let c = plan.chests.first(where: { $0.x == x && $0.y == y }) { return MineLoot.roll(&rng, c.spot, c.depth) }
				return MineLoot.roll(&rng, .open, 0)
			}
			// older mines: a chest at the end of a gallery, deeper galleries a little richer
			var lv: Int = 0
			for (i, f) in s.levels.enumerated() where y <= f { lv = i; break }
			return MineLoot.roll(&rng, .room, lv)
		}
	}
	// chests in the villages of worlds saved before generator version 5 (new worlds have none)
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
		if g.genVersion >= 3 { add(.mat(.relicFragment), 1, 1, 0.15) }
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

/// Brightness per light level. Slightly lifted (gamma 0.85) so torchlight reaches further into caves and
/// the step from lit to unlit is less harsh.
let lightLUT: [Double] = (0...15).map { pow(Double($0) / 15.0, 0.85) }

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

	/// Lights the window (nox, noy, nw, nh). `noteSeen` is false for a look at ground off the screen
	/// (spawning): the screen's own light map still has to see the edits made since it last looked.
	func compute(_ world: World, _ nox: Int, _ noy: Int, _ nw: Int, _ nh: Int, _ skyLevel: Int, _ dyn: [(Int, Int, Int)], noteSeen: Bool = true) {
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
		let hasSky: Bool = dimHasSky(world.dim)
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
		valid = true
		skyUsed = skyLevel
		dimUsed = world.dim.rawValue
		stamp = world.version
		layoutUsed = world.layoutVersion
		if noteSeen {
			Perf.shared.lightFull += 1
			world.editAny = false
		}
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
						// open air also lights the solid cells diagonally below it, so a block standing
						// on the ground (a cactus, a post) does not leave a dark shaft down its column
						if !op[ci] && ol >= 1 {
							if cx > 0 {
								let dg: Int = nb - 1
								if op[dg] && lv[dg] < ol { lv[dg] = ol; qo[ln[ol]] = dg; ln[ol] += 1 }
							}
							if cx < ww - 1 {
								let dg: Int = nb + 1
								if op[dg] && lv[dg] < ol { lv[dg] = ol; qo[ln[ol]] = dg; ln[ol] += 1 }
							}
						}
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
				// never quite pitch black: cave walls stay faintly readable
				let a: Int = max(0, Int((1.0 - bright) * 238.0))
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
	/// the vehicle whose frame the body is in (0: the land's) and its feet there, in the vehicle's own
	/// cell coordinates; vx and vy are then measured against the vehicle, along its axes (see p12b_frames)
	var ride: Int = 0
	var rlx: Double = 0
	var rly: Double = 0

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

/// How hard things fall (a mod's gravity rule scales it)
var gravityG: Double { return 34.0 * ModRuntime.shared.rule(.gravity) }
let terminalV: Double = 26.0

extension World {
	// Box queries read chunk storage directly, one column at a time: a column of a chunk is a
	// contiguous run of bytes, so this avoids a full tile(x, y) lookup per cell (the hottest path in
	// physics). Columns outside loaded chunks fall back to tile(x, y).

	/// Finds the first tile in the box whose flag in `table` is set. Returns its raw value or -1.
	private func scanBox(_ tx0: Int, _ ty0: Int, _ tx1: Int, _ ty1: Int, _ table: [Bool]) -> Int {
		// (plain local arrays, no closures: withUnsafeBufferPointer costs more than the scan itself in
		// unoptimised builds)
		let hh: Int = H
		let ya: Int = ty0 > 0 ? ty0 : 0
		let yb: Int = ty1 < hh - 1 ? ty1 : hh - 1
		let tb: [Bool] = table
		var tx: Int = tx0
		while tx <= tx1 {
			let cx: Int = floorDiv(tx, chunkW)
			if let c = chunk(cx) {
				let arr: [UInt8] = c.tiles
				var i: Int = (tx - cx * chunkW) * hh + ya
				var y: Int = ya
				while y <= yb {
					let r: Int = i8(arr[i])
					if tb[r] { return r }
					y += 1
					i += 1
				}
				// rows below the world are bedrock (rows above are air)
				if ty1 >= hh {
					let br: Int = i8(Tile.bedrock.rawValue)
					if tb[br] { return br }
				}
			} else {
				var y2: Int = ty0
				while y2 <= ty1 {
					let r: Int = i8(tile(tx, y2).rawValue)
					if tb[r] { return r }
					y2 += 1
				}
			}
			tx += 1
		}
		return -1
	}

	func boxSolid(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
		Perf.shared.countBox()
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return false }
		return scanBox(tx0, ty0, tx1, ty1, Tile.solidTable) >= 0
	}

	/// Nothing in the box for a vehicle to meet: no solid block and no liquid
	func boxOpen(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return true }
		return scanBox(tx0, ty0, tx1, ty1, Tile.meetTable) < 0
	}

	func boxHurts(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Tile? {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return nil }
		let r: Int = scanBox(tx0, ty0, tx1, ty1, Tile.hurtTable)
		return r >= 0 ? Tile.make(UInt8(truncatingIfNeeded: r)) : nil
	}

	/// Fractions of a box covered by water and by lava, in one pass
	func liquidFractions(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> (Double, Double) {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return (0, 0) }
		let lavaR: UInt8 = Tile.lava.rawValue
		let liq: [Bool] = Tile.liquidTable
		let hot: [Bool] = Liquids.hotTable
		let hh: Int = H
		var w: Double = 0
		var l: Double = 0
		var tx: Int = tx0
		while tx <= tx1 {
			let cx: Int = floorDiv(tx, chunkW)
			if let c = chunk(cx), ty0 >= 0, ty1 < hh {
				let arr: [UInt8] = c.tiles
				let lev: [UInt8] = c.level
				var i: Int = (tx - cx * chunkW) * hh + ty0
				var y: Int = ty0
				while y <= ty1 {
					let r: UInt8 = arr[i]
					if liq[Int(r)] {
						// a part-full cell counts by how full it is (a mod's hot liquid burns like lava)
						let a: Double = lev.isEmpty || lev[i] == 0 ? 1.0 : Double(lev[i]) / 255.0
						if r == lavaR || hot[Int(r)] { l += a } else { w += a }
					}
					y += 1
					i += 1
				}
			} else {
				for y in ty0...ty1 {
					let t: Tile = tile(tx, y)
					if t == .water { w += 1 } else if t == .lava { l += 1 }
				}
			}
			tx += 1
		}
		let n: Double = Double((tx1 - tx0 + 1) * (ty1 - ty0 + 1))
		return (w / n, l / n)
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

	// MARK: stairs
	// A stair tile is not solid; it has two solid parts instead: a full-width lower step (its bottom
	// half) and an upper step on its high side (top half, the right half for R, the left for L).
	// Bodies collide with those parts, and step up half a tile at a time.

	func stairAt(_ x: Int, _ y: Int) -> UInt8 {
		if y < 0 || y >= H { return 0 }
		return Tile.stairTable[Int(tile(x, y).rawValue)]
	}

	/// Whether any stairs stand in the loaded chunks covering columns x0...x1 (counted once per chunk)
	func stairsNear(_ x0: Double, _ x1: Double) -> Bool {
		var cx: Int = floorDiv(Int(floor(x0)), chunkW)
		let c1: Int = floorDiv(Int(floor(x1)), chunkW)
		while cx <= c1 {
			if let c = chunk(cx) {
				if c.stairs < 0 {
					var n: Int = 0
					for r in c.tiles where Tile.stairTable[Int(r)] != 0 { n += 1 }
					c.stairs = n
				}
				if c.stairs > 0 { return true }
			}
			cx += 1
		}
		return false
	}

	/// Whether a box overlaps the solid part of any stair
	func stairHit(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return false }
		for tx in tx0...tx1 {
			for ty in ty0...ty1 {
				let s: UInt8 = stairAt(tx, ty)
				if s == 0 { continue }
				let fx: Double = Double(tx)
				let fy: Double = Double(ty)
				// the lower step, full width
				if y1 > fy + 0.5 && y0 < fy + 1.0 { return true }
				// the upper step, on the high side
				let hx: Double = s == 1 ? fx + 0.5 : fx
				if y1 > fy && y0 < fy + 0.5 && x1 > hx && x0 < hx + 0.5 { return true }
			}
		}
		return false
	}

	/// Solid tiles, and the solid parts of stairs when there are any about
	func boxBlocked(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ stairs: Bool) -> Bool {
		if boxSolid(x0, y0, x1, y1) { return true }
		return stairs && stairHit(x0, y0, x1, y1)
	}

	/// The first stair top a body's feet meet coming down from prevY to ny over x0...x1
	func stairLanding(_ x0: Double, _ x1: Double, _ prevY: Double, _ ny: Double) -> Double? {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(prevY - 0.001))
		let ty1: Int = Int(floor(ny + 0.0005))
		if tx1 < tx0 || ty1 < ty0 { return nil }
		var best: Double? = nil
		for tx in tx0...tx1 {
			for ty in ty0...ty1 {
				let s: UInt8 = stairAt(tx, ty)
				if s == 0 { continue }
				let low: Double = Double(ty) + 0.5
				if low >= prevY - 0.001 && low <= ny + 0.0005 { best = min(best ?? low, low) }
				let hx: Double = s == 1 ? Double(tx) + 0.5 : Double(tx)
				if x1 > hx + 0.001 && x0 < hx + 0.499 {
					let up: Double = Double(ty)
					if up >= prevY - 0.001 && up <= ny + 0.0005 { best = min(best ?? up, up) }
				}
			}
		}
		return best
	}

	/// The first stair underside a body's head meets going up from prevTop to newTop over x0...x1
	func stairCeiling(_ x0: Double, _ x1: Double, _ prevTop: Double, _ newTop: Double) -> Double? {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(newTop)) - 1
		let ty1: Int = Int(floor(prevTop))
		if tx1 < tx0 || ty1 < ty0 { return nil }
		var best: Double? = nil
		for tx in tx0...tx1 {
			for ty in ty0...ty1 {
				let s: UInt8 = stairAt(tx, ty)
				if s == 0 { continue }
				let low: Double = Double(ty) + 1.0
				if low <= prevTop + 0.001 && low >= newTop - 0.0005 { best = max(best ?? low, low) }
				let hx: Double = s == 1 ? Double(tx) + 0.5 : Double(tx)
				if x1 > hx + 0.001 && x0 < hx + 0.499 {
					let up: Double = Double(ty) + 0.5
					if up <= prevTop + 0.001 && up >= newTop - 0.0005 { best = max(best ?? up, up) }
				}
			}
		}
		return best
	}

	/// Moves a body with gravity-free integration; the caller sets vx/vy. Collides with solid tiles,
	/// stairs, one-way platforms and decks. stepUp = max ledge height (tiles) climbed automatically
	/// (half a tile at a time on stairs).
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
		let st: Bool = stairsNear(b.x - hw - 1.0, b.x + hw + 1.0)
		let liftStep: Double = st ? 0.5 : 1.0
		// unstick: if inside solid, push upward
		if boxBlocked(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02, st) {
			var k: Int = 0
			while k < (st ? 12 : 6) && boxBlocked(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02, st) {
				b.y -= liftStep
				k += 1
			}
		}
		for _ in 0..<steps {
			// horizontal
			if b.vx != 0 {
				let nx: Double = b.x + b.vx * sdt
				if !boxBlocked(nx - hw, b.y - b.h + 0.001, nx + hw, b.y - 0.001, st) {
					b.x = nx
				} else {
					var done: Bool = false
					if (b.wasOnGround || b.onGround) && stepUp > 0 {
						var lift: Double = liftStep
						while lift <= stepUp + 0.001 && !done {
							if !boxBlocked(nx - hw, b.y - lift - b.h + 0.001, nx + hw, b.y - lift - 0.001, st) {
								b.x = nx
								b.y -= lift
								done = true
							}
							lift += liftStep
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
						if st, let sl = stairLanding(b.x - hw, b.x + hw, prevY, ny), sl < landY { landY = max(sl, prevY) }
						landed = true
					} else if st, let sl = stairLanding(b.x - hw, b.x + hw, prevY, ny) {
						landed = true
						landY = sl
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
					} else if st, let sc = stairCeiling(b.x - hw, b.x + hw, prevY - b.h, ny - b.h) {
						b.y = sc + b.h
						b.vy = 0
						b.hitCeil = true
					} else {
						b.y = ny
					}
				}
			}
		}
		// liquids
		let lf: (Double, Double) = liquidFractions(b.x - hw, b.y - b.h, b.x + hw, b.y)
		b.inWater = lf.0 > 0.35
		b.inLava = lf.1 > 0.2
	}

}

// MARK: - Projectiles

enum ProjKind: Int, Codable {
	case arrow, bullet, fireball, rock, shock, spit, bolt, bomb
	/// a crystal shard thrown by the Crystal Sentinel
	case shard
	/// the player's crossbow bolt, a blunderbuss pellet, a slung stone and a thrown fire flask
	case quarrel, pellet, pebble, flask
	/// a vehicle cannon's explosive shell (appended)
	case shell
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
	/// knockback on hit (0: the kind's usual push)
	var knock: Double = 0
	/// a shot from a mod (index into ModRuntime.shots; -1 for the game's own shots)
	var mod: Int = -1
	/// a thrown potion (its number; -1: a fire flask or any other shot)
	var potion: Int = -1
	/// infusions of the weapon that fired it: 1 fire, 2 frost, 4 volatile, 8 voidrend
	var inf: Int = 0
	/// its custom infusions (their numbers)
	var custom: [Int] = []
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
	/// thrown away by the player: it is not picked up again until the player has walked off from it
	var heldBack: Bool = false
	/// lying on a vehicle: which one, and where in its cells (see Body.ride)
	var ride: Int = 0
	var rlx: Double = 0
	var rly: Double = 0
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

/// A leaf come loose from a canopy, drifting down
struct LeafFlake {
	var x: Double
	var y: Double
	var vy: Double
	/// where it is in its sway and its tumble
	var phase: Double
	var life: Double
	var light: UInt32
	var dark: UInt32
	/// it has come to rest on the ground and is fading
	var landed: Bool = false
}

struct FloatText {
	var x: Double
	var y: Double
	var text: String
	var life: Double
	var color: UInt32
}

// ===== p12b_frames =====

// MARK: - Frames: bodies on and inside vehicles
// A body (the player, a creature, a dropped item) is in one frame at a time: the land's, or a vehicle's.
// In a vehicle's frame its place is kept in the vehicle's own cell coordinates and it moves among the
// vehicle's cells as if they were land: solid cells are floors, walls and ceilings, wings and balloon
// tops are floors to land on from above. Its place in the world is worked out from the vehicle each
// frame, so it is carried exactly however fast the vehicle goes, climbs or turns, with no drift.
// The frame changes by contact. Coming down onto a cell puts a body aboard; stepping onto the ground
// or leaving the vehicle's surroundings puts it back on the land, keeping the speed it had. A body on
// the land that a vehicle's cells reach is pushed out of them (and pushes back with its weight), and a
// rider the land gets in the way of is left behind. Servo sections will be frames too.

/// What a vehicle cell is to somebody walking on it
let cellOpen: UInt8 = 0
let cellSolid: UInt8 = 1
let cellPlatform: UInt8 = 2
/// (to another vehicle only: a wheel, met as the round thing it is)
let cellRound: UInt8 = 3

/// Shared numbers of the physics
enum Phys {
	/// how far anything may move between collision checks (blocks)
	static let maxStep: Double = 0.2
	/// a floor tilted further than this cannot be stood on (radians): bodies slide down it
	static let steep: Double = 0.7
	/// how far round a vehicle's cells a body in the air is still in its frame: beside, below, above
	static let besideReach: Double = 1.0
	static let belowReach: Double = 1.0
	static let aboveReach: Double = 9.0
	/// the player's mass (a vehicle frame is 1, a block of stone 2.5)
	static let playerMass: Double = 0.9
	/// the most sub-steps one fixed step of a vehicle is split into near the land (at 120 steps a
	/// second this covers 4,800 blocks a second; beyond that the steps grow, the count does not)
	static let maxSplit: Int = 200

	/// What two masses meeting head on give each other: the change in the first one's velocity along
	/// the line between them (the second gets the opposite, scaled by the masses)
	static func exchange(_ m1: Double, _ v1: Double, _ m2: Double, _ v2: Double, bounce: Double) -> Double {
		let tot: Double = m1 + m2
		if tot <= 0 { return 0 }
		return -(1.0 + bounce) * (v1 - v2) * m2 / tot
	}
}

/// How heavy a creature is for its size: stone golems are dense, birds, bones and ghosts light
func mobDensity(_ k: MobKind) -> Double {
	switch k {
	case .golem, .sentinel: return 1.6
	case .elephant, .rex, .bearBoss, .bear, .grizzly, .polarBear: return 0.8
	case .skeleton, .wraith, .bat, .cinderBat, .crow, .chicken, .warden: return 0.3
	case .slime, .emberSlime: return 0.45
	default: return 0.55
	}
}

/// How much a creature of a kind weighs at its usual size (a vehicle frame is 1, the player 0.9)
func mobMass(_ k: MobKind) -> Double {
	let d: MobDef = mobDef(k)
	return max(0.05, d.w * d.h * mobDensity(k))
}

/// How much this creature weighs (a mutated one is as much heavier as it is bigger)
func mobMass(_ m: Mob) -> Double {
	return max(0.05, m.b.w * m.b.h * mobDensity(m.kind))
}

extension Vehicle {
	/// What a part is to somebody walking on the vehicle. A block is what it is on the land; frames,
	/// hulls, engines, tanks, crates and armour are solid; wings, tails and balloon tops are stood on;
	/// seats, wheels, lamps, propellers and guns are walked past.
	static func walkKind(_ t: PartType, _ b: Tile?) -> UInt8 {
		if t == .block {
			guard let tile = b else { return cellSolid }
			// (a stair is a step up, like a block: walking into it climbs it)
			if tile.solid || stairSide(tile) != 0 { return cellSolid }
			if tile.isPlatform { return cellPlatform }
			return cellOpen
		}
		switch t {
		case .frame, .hull, .engine, .fuelTank, .cargo, .armor, .jet, .burner, .cannon, .drill, .diamondDrill, .voidDrill, .ballast, .coupler, .hinge, .servo, .piston: return cellSolid
		case .wing, .elevator, .envelope, .flap, .airBrake, .stabilizer: return cellPlatform
		default: return cellOpen
		}
	}

	/// What a part is to another vehicle meeting it: every part is solid, and a block what it is on the
	/// land (a torch or an open door is passed through, a platform is met from above)
	static func meetKind(_ t: PartType, _ b: Tile?) -> UInt8 {
		if t == .bigWheel { return cellSolid }
		if isWheelPart(t) { return cellRound }
		if t != .block { return cellSolid }
		guard let tile = b else { return cellSolid }
		if tile.solid || stairSide(tile) != 0 { return cellSolid }
		if tile.isPlatform { return cellPlatform }
		return cellOpen
	}

	/// The walk and meet kinds of every cell, over the cells' box (worked out again whenever the parts
	/// change)
	func buildWalkGrid() {
		gridW = max(1, maxX - minX + 1)
		gridH = max(1, maxY - minY + 1)
		var g: [UInt8] = [UInt8](repeating: 0, count: gridW * gridH)
		var m: [UInt8] = [UInt8](repeating: 0, count: gridW * gridH)
		for (c, t) in parts {
			let x: Int = c.dx - minX
			let y: Int = c.dy - minY
			if x < 0 || y < 0 || x >= gridW || y >= gridH { continue }
			g[y * gridW + x] = Vehicle.walkKind(t, blocks[c])
			m[y * gridW + x] = Vehicle.meetKind(t, blocks[c])
		}
		walkGrid = g
		meetGrid = m
		artRev &+= 1
	}

	@inline(__always) func walkAt(_ dx: Int, _ dy: Int) -> UInt8 {
		let x: Int = dx - minX
		let y: Int = dy - minY
		if x < 0 || y < 0 || x >= gridW || y >= gridH { return 0 }
		return walkGrid[y * gridW + x]
	}

	@inline(__always) func meetAt(_ dx: Int, _ dy: Int) -> UInt8 {
		let x: Int = dx - minX
		let y: Int = dy - minY
		if x < 0 || y < 0 || x >= gridW || y >= gridH { return 0 }
		return meetGrid[y * gridW + x]
	}

	/// Whether a box in cell coordinates overlaps a solid cell
	func boxSolidCells(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Bool {
		let tx0: Int = Int(floor(x0))
		let tx1: Int = Int(floor(x1 - 0.0001))
		let ty0: Int = Int(floor(y0))
		let ty1: Int = Int(floor(y1 - 0.0001))
		if tx1 < tx0 || ty1 < ty0 { return false }
		if tx1 < minX || tx0 > maxX || ty1 < minY || ty0 > maxY { return false }
		var ty: Int = ty0
		while ty <= ty1 {
			var tx: Int = tx0
			while tx <= tx1 {
				if walkAt(tx, ty) == cellSolid { return true }
				tx += 1
			}
			ty += 1
		}
		return false
	}

	/// How fast the vehicle is moving at a point of the world (its own speed and its turning)
	func pointVel(_ wx: Double, _ wy: Double) -> (Double, Double) {
		return (vx - angVel * (wy - py), vy + angVel * (wx - px))
	}

	/// A push on the vehicle at a point of the world (an impulse: mass times change of speed)
	func push(_ wx: Double, _ wy: Double, _ jx: Double, _ jy: Double) {
		let rx: Double = wx - px
		let ry: Double = wy - py
		vx += jx / mass
		vy += jy / mass
		angVel += (rx * jy - ry * jx) / inertia
	}

	/// Whether a body's box (feet at lx, ly in cell coordinates) is still in the vehicle's surroundings
	func around(_ lx: Double, _ ly: Double, _ hw: Double, _ h: Double) -> Bool {
		if lx + hw < Double(minX) - Phys.besideReach || lx - hw > Double(maxX + 1) + Phys.besideReach { return false }
		if ly - h > Double(maxY + 1) + Phys.belowReach || ly < Double(minY) - Phys.aboveReach { return false }
		return true
	}
}

extension Game {
	func vehicleByID(_ id: Int) -> Vehicle? {
		for v in vehicles where v.id == id { return v }
		return nil
	}

	/// Moves a body for one frame in the frame it is in. `falls`: gravity is acting on it (not a flier,
	/// not somebody on a ladder), so a tilted floor pulls it along; `mass` is what it weighs.
	func moveThing(_ b: inout Body, _ dt: Double, stepUp: Double, dropThrough: Bool, decks: [Deck], mass: Double, falls: Bool = true) {
		if vehicles.isEmpty {
			b.ride = 0
			world.moveBody(&b, dt, stepUp: stepUp, dropThrough: dropThrough, decks: decks)
			return
		}
		if b.ride != 0 {
			if let v = vehicleByID(b.ride), !v.parts.isEmpty {
				// Something else may have moved it since the vehicle last placed it: a knock that shifts it a
				// little is kept (its place aboard follows); a jump to somewhere else (a respawn, a
				// doorway to another place, a seat) takes it off the vehicle.
				let l: (Double, Double) = v.toLocal(b.x, b.y)
				let ex: Double = l.0 - b.rlx
				let ey: Double = l.1 - b.rly
				let off: Double = ex * ex + ey * ey
				if off <= 0.25 {
					if off > 1e-12 {
						b.rlx = l.0
						b.rly = l.1
					}
					rideStep(&b, v, dt, stepUp: stepUp, dropThrough: dropThrough, mass: mass, falls: falls)
					return
				}
			}
			b.ride = 0
		}
		world.moveBody(&b, dt, stepUp: stepUp, dropThrough: dropThrough, decks: decks)
		meetVehicles(&b, dt, dropThrough: dropThrough, mass: mass)
	}

	/// One frame for a body aboard a vehicle: it moves among the vehicle's cells, the land stops it where
	/// the land is in its way, and it weighs on the vehicle where it stands
	func rideStep(_ b: inout Body, _ v: Vehicle, _ dt: Double, stepUp: Double, dropThrough: Bool, mass: Double, falls: Bool) {
		let a: Double = remainder(v.angle, 2.0 * Double.pi)
		let ca: Double = cos(a)
		let sa: Double = sin(a)
		let steepNow: Bool = abs(a) > Phys.steep
		if falls && abs(a) > 0.02 {
			// the caller pulled it straight down its own y axis; on a tilted vehicle part of that pull
			// runs along the floor (held by its footing unless the floor is too steep)
			b.vy -= gravityG * (1.0 - ca) * dt
			if !b.onGround || steepNow { b.vx += gravityG * sa * dt }
		}
		let hw: Double = b.w * 0.5
		let lx0: Double = b.rlx
		let ly0: Double = b.rly
		var lb: Body = b
		lb.x = lx0
		lb.y = ly0
		moveInCells(&lb, v, dt, stepUp: stepUp, dropThrough: dropThrough)
		if steepNow { lb.onGround = false }
		// the land: is it in the way of where that puts the body?
		var lx: Double = lb.x
		var ly: Double = lb.y
		var w: (Double, Double) = v.toWorld(lx, ly)
		if landBlocks(w.0, w.1, hw, b.h) {
			let wx: (Double, Double) = v.toWorld(lx0, ly)
			let wy: (Double, Double) = v.toWorld(lx, ly0)
			if !landBlocks(wx.0, wx.1, hw, b.h) {
				// a wall of the land beside the vehicle
				lx = lx0
				lb.vx = 0
				lb.hitWall = true
				w = wx
			} else if !landBlocks(wy.0, wy.1, hw, b.h) {
				ly = ly0
				w = wy
				if lb.vy >= 0 {
					// it has come down onto the land: off the vehicle, standing on the block it met
					let post: (Double, Double) = v.toWorld(lx, lb.y)
					b.x = w.0
					b.y = min(w.1, floor(post.1 - 0.02))
					if landBlocks(b.x, b.y, hw, b.h) { b.y = w.1 }
					b.vx = lb.vx
					b.vy = 0
					b.onGround = true
					b.hitWall = lb.hitWall
					leaveFrame(&b, v)
					return
				}
				lb.vy = 0
				lb.hitCeil = true
			} else {
				lx = lx0
				ly = ly0
				lb.vx = 0
				lb.vy = 0
				w = v.toWorld(lx, ly)
			}
		}
		// another vehicle's cells (a plane parked on a carrier's deck): stepped onto from above, else in
		// the way like a wall
		if vehicles.count > 1, let o = vehicleInWay(w.0, w.1, hw, b.h, except: v.id) {
			if meetOtherVehicle(&b, v, o, w, lb.vx, lb.vy) { return }
			let wx: (Double, Double) = v.toWorld(lx0, ly)
			if vehicleInWay(wx.0, wx.1, hw, b.h, except: v.id) == nil {
				lx = lx0
				lb.vx = 0
				lb.hitWall = true
				w = wx
			} else {
				lx = lx0
				ly = ly0
				lb.vx = 0
				lb.vy = 0
				w = v.toWorld(lx, ly)
			}
		}
		b.vx = lb.vx
		b.vy = lb.vy
		b.onGround = lb.onGround
		b.wasOnGround = lb.wasOnGround
		b.hitWall = lb.hitWall
		b.hitCeil = lb.hitCeil
		b.deck = -1
		b.rlx = lx
		b.rly = ly
		b.x = w.0
		b.y = w.1
		let lf: (Double, Double) = world.liquidFractions(b.x - hw, b.y - b.h, b.x + hw, b.y)
		// (in the dry air inside a hull under water, nobody swims)
		let dry: Bool = (lf.0 > 0.35 || lf.1 > 0.2) && v.dryAt(lx, ly - b.h * 0.5)
		b.inWater = lf.0 > 0.35 && !dry
		b.inLava = lf.1 > 0.2 && !dry
		if !v.around(lx, ly, hw, b.h) {
			leaveFrame(&b, v)
			return
		}
		// its weight rests on the vehicle where it stands (a vehicle at rest is not woken by somebody
		// standing still on it)
		if b.onGround && mass > 0 {
			if v.asleep {
				if abs(b.vx) > 0.5 && mass > v.mass * 0.08 { v.asleep = false }
			} else {
				v.push(b.x, b.y, 0, mass * gravityG * dt)
			}
		}
	}

	/// Whether the land is in the way of a body standing at a place in the world
	func landBlocks(_ x: Double, _ y: Double, _ hw: Double, _ h: Double) -> Bool {
		return world.boxSolid(x - hw + 0.02, y - h + 0.02, x + hw - 0.02, y - 0.02)
	}

	/// Moves a body among a vehicle's cells for one frame (its x, y are in cell coordinates here): the same
	/// rules as on the land, with whole cells for blocks and wings for platforms
	func moveInCells(_ b: inout Body, _ v: Vehicle, _ dt: Double, stepUp: Double, dropThrough: Bool) {
		b.wasOnGround = b.onGround
		b.hitWall = false
		b.hitCeil = false
		b.onGround = false
		b.deck = -1
		let speed: Double = max(abs(b.vx), abs(b.vy))
		let steps: Int = max(1, Int(ceil(speed * dt / 0.3)))
		let sdt: Double = dt / Double(steps)
		let hw: Double = b.w * 0.5
		if v.boxSolidCells(b.x - hw + 0.02, b.y - b.h + 0.02, b.x + hw - 0.02, b.y - 0.02) { escapeCells(&b, v, 0, 0) }
		for _ in 0..<steps {
			if b.vx != 0 {
				let nx: Double = b.x + b.vx * sdt
				if !v.boxSolidCells(nx - hw, b.y - b.h + 0.001, nx + hw, b.y - 0.001) {
					b.x = nx
				} else {
					var done: Bool = false
					if (b.wasOnGround || b.onGround) && stepUp > 0 {
						var lift: Double = 1.0
						while lift <= stepUp + 0.001 && !done {
							if !v.boxSolidCells(nx - hw, b.y - lift - b.h + 0.001, nx + hw, b.y - lift - 0.001) {
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
			let prevY: Double = b.y
			let ny: Double = b.y + b.vy * sdt
			if b.vy >= 0 {
				var landed: Bool = false
				var landY: Double = ny
				if v.boxSolidCells(b.x - hw, ny - b.h + 0.001, b.x + hw, ny + 0.0005) {
					landY = floor(ny + 0.0005)
					if landY < prevY - 0.0001 { landY = prevY }
					landed = true
				} else if !dropThrough {
					let row: Int = Int(floor(ny + 0.0005))
					if prevY <= Double(row) + 0.001 && ny >= Double(row) - 0.0001 {
						let tx0: Int = Int(floor(b.x - hw))
						let tx1: Int = Int(floor(b.x + hw - 0.0001))
						var tx: Int = tx0
						while tx <= tx1 {
							if v.walkAt(tx, row) == cellPlatform {
								landed = true
								landY = Double(row)
							}
							tx += 1
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
			} else if v.boxSolidCells(b.x - hw, ny - b.h, b.x + hw, ny - 0.001) {
				b.y = floor(ny - b.h) + 1.0 + b.h
				b.vy = 0
				b.hitCeil = true
			} else {
				b.y = ny
			}
		}
	}

	/// A body inside solid cells is moved out the nearest way that is open (the way it came from first
	/// when two are as near). Returns the way it went: 0 none, 1 left, 2 right, 3 up, 4 down.
	@discardableResult
	func escapeCells(_ b: inout Body, _ v: Vehicle, _ rvx: Double, _ rvy: Double) -> Int {
		let hw: Double = b.w * 0.5
		var best: Double = 9
		var way: Int = 0
		// the ways out, the one against its own motion tried first
		var order: [Int] = [3, 1, 2, 4]
		if abs(rvx) > abs(rvy) { order = rvx > 0 ? [1, 3, 2, 4] : [2, 3, 1, 4] } else if rvy < 0 { order = [4, 1, 2, 3] }
		for k in order {
			let dx: Double = k == 1 ? -1.0 : (k == 2 ? 1.0 : 0.0)
			let dy: Double = k == 3 ? -1.0 : (k == 4 ? 1.0 : 0.0)
			var d: Double = 0.05
			while d < best - 0.001 && d <= 2.5 {
				let x: Double = b.x + dx * d
				let y: Double = b.y + dy * d
				if !v.boxSolidCells(x - hw + 0.02, y - b.h + 0.02, x + hw - 0.02, y - 0.02) {
					let w: (Double, Double) = v.toWorld(x, y)
					if !landBlocks(w.0, w.1, hw, b.h) {
						best = d
						way = k
					}
					break
				}
				d += 0.05
			}
		}
		if way == 0 { return 0 }
		b.x += (way == 1 ? -best : (way == 2 ? best : 0))
		b.y += (way == 3 ? -best : (way == 4 ? best : 0))
		return way
	}

	/// Back to the land's frame: the body keeps going as fast as the vehicle carried it, plus its own motion
	func leaveFrame(_ b: inout Body, _ v: Vehicle) {
		let pv: (Double, Double) = v.pointVel(b.x, b.y)
		let c: Double = v.cosA
		let s: Double = v.sinA
		let wx: Double = b.vx * c - b.vy * s
		let wy: Double = b.vx * s + b.vy * c
		b.vx = pv.0 + wx
		b.vy = pv.1 + wy
		b.ride = 0
		settleOnLand(&b)
	}

	/// A body handed back to the land with its feet a hair inside the top of a block stands on that
	/// block (the land's own physics only ever puts feet on a block's top, never just under it)
	func settleOnLand(_ b: inout Body) {
		let f: Double = b.y - floor(b.y)
		if f <= 0 || f > 0.03 { return }
		let hw: Double = b.w * 0.5
		if world.boxSolid(b.x - hw + 0.02, b.y - f, b.x + hw - 0.02, b.y) { b.y = floor(b.y) }
	}

	/// Puts a body aboard a vehicle at a place in its cells, at rest against it
	func boardFrame(_ b: inout Body, _ v: Vehicle, _ lx: Double, _ ly: Double) {
		b.ride = v.id
		b.rlx = lx
		b.rly = ly
		b.vx = 0
		b.vy = 0
		let w: (Double, Double) = v.toWorld(lx, ly)
		b.x = w.0
		b.y = w.1
	}

	/// A body on the land that has just moved, against the vehicles near it: coming down onto a cell
	/// puts it aboard; cells that reach into it push it out, and it pushes back with its weight
	func meetVehicles(_ b: inout Body, _ dt: Double, dropThrough: Bool, mass: Double) {
		let hw: Double = b.w * 0.5
		for v in vehicles {
			if v.parts.isEmpty { continue }
			if b.x + hw < v.b.left - 0.6 || b.x - hw > v.b.right + 0.6 || b.y < v.b.top - 0.6 || b.y - b.h > v.b.y + 0.6 { continue }
			let c: Double = v.cosA
			let s: Double = v.sinA
			let l: (Double, Double) = v.toLocal(b.x, b.y)
			// its velocity as the vehicle sees it there, along the vehicle's axes
			let pv: (Double, Double) = v.pointVel(b.x, b.y)
			let dvx: Double = b.vx - pv.0
			let dvy: Double = b.vy - pv.1
			var rvx: Double = dvx * c + dvy * s
			var rvy: Double = -dvx * s + dvy * c
			let tilt: Double = abs(remainder(v.angle, 2.0 * Double.pi))
			// 1. coming down onto the top of a cell
			if rvy >= -0.01 && tilt < 1.2 {
				let prevLy: Double = l.1 - rvy * dt
				var row: Int = Int(ceil(prevLy - 0.06))
				let last: Int = min(Int(floor(l.1 + 0.0005)), row + 12)
				let tx0: Int = Int(floor(l.0 - hw))
				let tx1: Int = Int(floor(l.0 + hw - 0.0001))
				var landRow: Int? = nil
				while row <= last && landRow == nil {
					var tx: Int = tx0
					while tx <= tx1 {
						let k: UInt8 = v.walkAt(tx, row)
						let above: UInt8 = v.walkAt(tx, row - 1)
						if (k == cellSolid && above != cellSolid) || (k == cellPlatform && !dropThrough) { landRow = row }
						tx += 1
					}
					row += 1
				}
				if let r = landRow, !v.boxSolidCells(l.0 - hw + 0.02, Double(r) - b.h + 0.02, l.0 + hw - 0.02, Double(r) - 0.02) {
					// what it lands with goes into the vehicle
					if mass > 0 && rvy > 0.5 {
						v.push(b.x, b.y, -s * mass * rvy, c * mass * rvy)
						v.asleep = false
					}
					b.ride = v.id
					b.rlx = l.0
					b.rly = Double(r)
					b.vx = rvx
					b.vy = 0
					b.onGround = true
					let w: (Double, Double) = v.toWorld(b.rlx, b.rly)
					b.x = w.0
					b.y = w.1
					return
				}
			}
			// 2. solid cells reaching into it
			if v.boxSolidCells(l.0 - hw + 0.02, l.1 - b.h + 0.02, l.0 + hw - 0.02, l.1 - 0.02) {
				var lb: Body = b
				lb.x = l.0
				lb.y = l.1
				let way: Int = escapeCells(&lb, v, rvx, rvy)
				if way == 0 { continue }
				let w: (Double, Double) = v.toWorld(lb.x, lb.y)
				b.x = w.0
				b.y = w.1
				// it no longer moves into the vehicle; what it lost goes into the vehicle
				var lost: (Double, Double) = (0, 0)
				if (way == 1 && rvx > 0) || (way == 2 && rvx < 0) { lost.0 = rvx; rvx = 0 }
				if (way == 3 && rvy > 0) || (way == 4 && rvy < 0) { lost.1 = rvy; rvy = 0 }
				b.vx = pv.0 + rvx * c - rvy * s
				b.vy = pv.1 + rvx * s + rvy * c
				if way == 1 || way == 2 { b.hitWall = true }
				if mass > 0 && (lost.0 != 0 || lost.1 != 0) {
					v.push(b.x, b.y - b.h * 0.5, (lost.0 * c - lost.1 * s) * mass, (lost.0 * s + lost.1 * c) * mass)
					if abs(lost.0) + abs(lost.1) > 0.5 { v.asleep = false }
				}
				return
			}
		}
	}

	/// After the vehicles have moved: everything aboard is where its vehicle now has it. A rider the land
	/// is in the way of stays behind, stopped.
	func syncRiders() {
		syncRider(&pb)
		for m in mobs where m.b.ride != 0 { syncRider(&m.b) }
		if !drops.isEmpty {
			for i in drops.indices where drops[i].ride != 0 {
				guard let v = vehicleByID(drops[i].ride), !v.parts.isEmpty else { drops[i].ride = 0; continue }
				let w: (Double, Double) = v.toWorld(drops[i].rlx, drops[i].rly)
				if world.boxSolid(w.0 - 0.1, w.1 - 0.25, w.0 + 0.1, w.1 - 0.05) { drops[i].ride = 0; drops[i].vx = 0; drops[i].vy = 0; continue }
				drops[i].x = w.0
				drops[i].y = w.1
			}
		}
	}

	func syncRider(_ b: inout Body) {
		if b.ride == 0 { return }
		guard let v = vehicleByID(b.ride), !v.parts.isEmpty else {
			b.ride = 0
			return
		}
		let w: (Double, Double) = v.toWorld(b.rlx, b.rly)
		if landBlocks(w.0, w.1, b.w * 0.5, b.h) {
			b.ride = 0
			b.vx = 0
			b.vy = 0
			settleOnLand(&b)
			return
		}
		b.x = w.0
		b.y = w.1
	}

	/// Everybody aboard a vehicle that is turned to face the other way is turned with it
	func mirrorRiders(_ v: Vehicle, _ sx: Int) {
		let flip: Double = Double(sx + 1)
		if pb.ride == v.id { pb.rlx = flip - pb.rlx; pb.vx = -pb.vx }
		for m in mobs where m.b.ride == v.id {
			m.b.rlx = flip - m.b.rlx
			m.b.vx = -m.b.vx
		}
		for i in drops.indices where drops[i].ride == v.id { drops[i].rlx = flip - drops[i].rlx }
	}

	/// How fast whatever carries the player is going where they are: a vehicle they drive or stand on
	func carrierVel() -> (Double, Double) {
		if let v = inVehicle { return v.pointVel(pb.x, pb.y) }
		if pb.ride != 0, let v = vehicleByID(pb.ride) { return v.pointVel(pb.x, pb.y) }
		return (0, 0)
	}

	/// How fast a body is really going in the world (aboard a vehicle its own vx, vy are measured against it)
	func worldVel(_ b: Body) -> (Double, Double) {
		if b.ride != 0, let v = vehicleByID(b.ride) {
			let pv: (Double, Double) = v.pointVel(b.x, b.y)
			return (pv.0 + b.vx * v.cosA - b.vy * v.sinA, pv.1 + b.vx * v.sinA + b.vy * v.cosA)
		}
		return (b.vx, b.vy)
	}
}

// MARK: - Inside a vehicle: ladders, doors, seats, beds, stations, back walls
// A vehicle's blocks work as they do on the land: ladders are climbed (in the vehicle's frame, so a
// ladder on a moving ship carries whoever is on it), doors open as somebody walks into them and close
// behind them, chairs and sofas are passenger seats, beds pass the night, a crafting station aboard
// counts as near, chests hold things, and back walls go behind the cells.

/// A door on a vehicle the player opened by walking into it (it closes again behind them)
struct VehicleDoor {
	var vid: Int
	var cell: PartCell
	var t: Double
}

extension Game {
	/// The block of a vehicle's cell (nil for parts)
	func vehicleBlock(_ v: Vehicle, _ c: PartCell) -> Tile? {
		guard v.parts[c] == .block else { return nil }
		return v.blocks[c]
	}

	/// A cell a body can climb: a ladder, a mod's climbable block, or a hatch laid over a ladder
	func climbableCell(_ v: Vehicle, _ x: Int, _ y: Int) -> Bool {
		guard let t = vehicleBlock(v, PartCell(dx: x, dy: y)) else { return false }
		if t == .ladder { return true }
		if t.isMod && ModRuntime.shared.climbTiles.contains(t.rawValue) { return true }
		if t == .platform, vehicleBlock(v, PartCell(dx: x, dy: y + 1)) == .ladder { return true }
		return false
	}

	/// The middle of a ladder a body (feet at lx, ly in the vehicle's cells) is on, or nil
	func ladderIn(_ v: Vehicle, _ lx: Double, _ ly: Double, _ h: Double) -> Double? {
		let cx: Int = Int(floor(lx))
		let frac: Double = lx - Double(cx)
		var cols: [Int] = [cx]
		if frac < 0.34 { cols.append(cx - 1) } else if frac > 0.66 { cols.append(cx + 1) }
		let y0: Int = Int(floor(ly - h + 0.1))
		let y1: Int = Int(floor(ly + 0.05))
		for tx in cols {
			var y: Int = y0
			while y <= y1 {
				if climbableCell(v, tx, y) { return Double(tx) + 0.5 }
				y += 1
			}
		}
		return nil
	}

	/// A ladder the player is on, as the x of its middle in the frame they are in: the land's ladders
	/// while on the land, the vehicle's while aboard one. A vehicle's ladder reached from the land takes
	/// them aboard (keeping their speed), so they climb with it as it moves.
	func ladderSpot() -> Double? {
		if pb.ride != 0 {
			guard let v = vehicleByID(pb.ride) else { return nil }
			return ladderIn(v, pb.rlx, pb.rly, pb.h)
		}
		if let lc = ladderColumn() { return Double(lc) + 0.5 }
		for v in vehicles where !v.parts.isEmpty {
			if pb.right < v.b.left - 0.4 || pb.left > v.b.right + 0.4 || pb.y < v.b.top - 0.4 || pb.top > v.b.y + 0.4 { continue }
			let l: (Double, Double) = v.toLocal(pb.x, pb.y)
			if let x = ladderIn(v, l.0, l.1, pb.h) {
				boardKeeping(&pb, v)
				return x
			}
		}
		return nil
	}

	/// Puts a body aboard a vehicle where it is now, keeping how fast it goes in the world
	func boardKeeping(_ b: inout Body, _ v: Vehicle) {
		let l: (Double, Double) = v.toLocal(b.x, b.y)
		let pv: (Double, Double) = v.pointVel(b.x, b.y)
		let dvx: Double = b.vx - pv.0
		let dvy: Double = b.vy - pv.1
		let c: Double = v.cosA
		let s: Double = v.sinA
		b.ride = v.id
		b.rlx = l.0
		b.rly = l.1
		b.vx = dvx * c + dvy * s
		b.vy = -dvx * s + dvy * c
	}

	/// Another vehicle's solid cells where a body would stand (feet at wx, wy), or nil
	func vehicleInWay(_ wx: Double, _ wy: Double, _ hw: Double, _ h: Double, except: Int) -> Vehicle? {
		for o in vehicles where o.id != except && !o.parts.isEmpty {
			if wx + hw < o.b.left || wx - hw > o.b.right || wy < o.b.top || wy - h > o.b.y { continue }
			let l: (Double, Double) = o.toLocal(wx, wy)
			if o.boxSolidCells(l.0 - hw + 0.02, l.1 - h + 0.02, l.0 + hw - 0.02, l.1 - 0.02) { return o }
		}
		return nil
	}

	/// A body aboard one vehicle meeting another's cells: coming down onto the top of one puts it aboard
	/// that one (a step from a carrier's deck onto a parked plane); otherwise they are in its way.
	/// Returns true when it changed vehicles.
	func meetOtherVehicle(_ b: inout Body, _ v: Vehicle, _ o: Vehicle, _ w: (Double, Double), _ lvx: Double, _ lvy: Double) -> Bool {
		let hw: Double = b.w * 0.5
		let lo: (Double, Double) = o.toLocal(w.0, w.1)
		let row: Double = floor(lo.1 + 0.0005)
		if lvy < 0 || lo.1 - row > 0.5 { return false }
		if o.boxSolidCells(lo.0 - hw + 0.02, row - b.h + 0.02, lo.0 + hw - 0.02, row - 0.02) { return false }
		// its speed in the world, then against the other vehicle
		let c: Double = v.cosA
		let s: Double = v.sinA
		let pv: (Double, Double) = v.pointVel(w.0, w.1)
		b.x = w.0
		b.y = w.1
		b.vx = pv.0 + lvx * c - lvy * s
		b.vy = pv.1 + lvx * s + lvy * c
		boardKeeping(&b, o)
		b.rly = row
		b.vy = 0
		b.onGround = true
		let at: (Double, Double) = o.toWorld(b.rlx, b.rly)
		b.x = at.0
		b.y = at.1
		return true
	}

	// MARK: doors

	/// The run of door cells in a vehicle's column through a cell (a door is two cells high)
	func vehicleDoorCells(_ v: Vehicle, _ c: PartCell) -> [PartCell] {
		var out: [PartCell] = []
		var y: Int = c.dy
		while let t = vehicleBlock(v, PartCell(dx: c.dx, dy: y - 1)), isDoor(t), c.dy - y < 4 { y -= 1 }
		while let t = vehicleBlock(v, PartCell(dx: c.dx, dy: y)), isDoor(t), out.count < 4 {
			out.append(PartCell(dx: c.dx, dy: y))
			y += 1
		}
		return out
	}

	/// Opens or shuts a vehicle's door (all its cells)
	func setVehicleDoor(_ v: Vehicle, _ c: PartCell, open: Bool) {
		let t: Tile = open ? .doorOpen : .doorClosed
		for k in vehicleDoorCells(v, c) { v.blocks[k] = t }
		v.buildWalkGrid()
		let at: (Double, Double) = v.cellCenter(c)
		sfx(.door, at: at.0, 0.6)
	}

	/// Walking into a closed door of a vehicle (aboard it, or from the land) opens it; it closes again once
	/// the player has gone through
	func vehicleDoorTouch(_ ix: Double) {
		if ix == 0 || vehicles.isEmpty { return }
		let sgn: Double = ix > 0 ? 1.0 : -1.0
		for v in vehicles where !v.parts.isEmpty {
			if pb.ride != v.id && (pb.right < v.b.left - 0.5 || pb.left > v.b.right + 0.5 || pb.y < v.b.top - 0.5 || pb.top > v.b.y + 0.5) { continue }
			let l: (Double, Double) = pb.ride == v.id ? (pb.rlx, pb.rly) : v.toLocal(pb.x, pb.y)
			let fx: Int = Int(floor(l.0 + sgn * (pb.w * 0.5 + 0.2)))
			for yy in [Int(floor(l.1 - 0.5)), Int(floor(l.1 - 1.4))] {
				let c: PartCell = PartCell(dx: fx, dy: yy)
				if vehicleBlock(v, c) == .doorClosed {
					setVehicleDoor(v, c, open: true)
					if !vehicleDoors.contains(where: { $0.vid == v.id && $0.cell.dx == fx }) && vehicleDoors.count < 16 {
						vehicleDoors.append(VehicleDoor(vid: v.id, cell: c, t: 0))
					}
					return
				}
			}
		}
	}

	/// Closes the vehicle doors the player walked through, once they are clear of the doorway
	func updateVehicleDoors(_ dt: Double) {
		if vehicleDoors.isEmpty { return }
		var keep: [VehicleDoor] = []
		for var d in vehicleDoors {
			d.t += dt
			guard let v = vehicleByID(d.vid), vehicleBlock(v, d.cell) == .doorOpen else { continue }
			let l: (Double, Double) = pb.ride == v.id ? (pb.rlx, pb.rly) : v.toLocal(pb.x, pb.y)
			let cells: [PartCell] = vehicleDoorCells(v, d.cell)
			let top: Double = Double(cells.first?.dy ?? d.cell.dy)
			let bottom: Double = Double((cells.last?.dy ?? d.cell.dy) + 1)
			let away: Bool = abs(l.0 - (Double(d.cell.dx) + 0.5)) > pb.w * 0.5 + 1.1 || l.1 < top - 0.5 || l.1 - pb.h > bottom + 0.5
			if d.t > 0.5 && away {
				setVehicleDoor(v, d.cell, open: false)
				continue
			}
			if d.t < 60 { keep.append(d) }
		}
		vehicleDoors = keep
	}

	// MARK: seats, beds and stations

	/// Sits down on a chair or sofa built on a vehicle: a passenger, carried with it until they walk or jump
	func sitAboard(_ v: Vehicle, _ c: PartCell) {
		if mounted != nil || inVehicle != nil { return }
		seat = nil
		seatAboard = c
		boardFrame(&pb, v, Double(c.dx) + 0.5, Double(c.dy) + 1.0)
		pb.onGround = true
		fallPeak = 0
		say("You sit down. Walk or jump to get up.", 1.6)
		bumpHUD()
	}

	/// Keeps a passenger in their seat aboard; false (standing up) once they move or jump, or the seat is gone
	func stayInSeatAboard(_ ix: Double, _ jumpPressed: Bool) -> Bool {
		guard let c = seatAboard else { return false }
		guard pb.ride != 0, let v = vehicleByID(pb.ride), let t = vehicleBlock(v, c), isSeat(t) else {
			seatAboard = nil
			bumpHUD()
			return false
		}
		if ix != 0 || jumpPressed || downHeld {
			seatAboard = nil
			bumpHUD()
			return false
		}
		pb.rlx = Double(c.dx) + 0.5
		pb.rly = Double(c.dy) + 1.0
		pb.vx = 0
		pb.vy = 0
		pb.onGround = true
		let w: (Double, Double) = v.toWorld(pb.rlx, pb.rly)
		pb.x = w.0
		pb.y = w.1
		fallPeak = 0
		return true
	}

	/// A bed on a vehicle passes the night like any bed; it moves, so it is not where the player wakes
	func sleepAboard() {
		if world.dim != .overworld {
			say("Nights only pass in the Overworld.", 2.5)
			return
		}
		if !isNight {
			say("You can only sleep at night. (A bed on a vehicle moves, so it can't be where you wake up.)", 3.0)
			return
		}
		for m in mobs where m.hp > 0 && !m.removed && isThreat(m) && abs(m.b.x - pb.x) < 16 && abs(m.b.y - pb.y) < 10 {
			say("You can't sleep now: there are monsters nearby.", 2.0)
			return
		}
		if timeOfDay > 0.5 { dayCount += 1 }
		timeOfDay = 0.02
		hp = min(maxHP, hp + 6.0)
		fadeT = 1.0
		light.valid = false
		say("You sleep until morning, rocked by the vehicle.", 3.0)
		bumpHUD()
	}

	/// A block of a kind built on a vehicle within reach of the player (a crafting station aboard)
	func stationAboard(_ t: Tile) -> Bool {
		for v in vehicles where !v.parts.isEmpty {
			if pb.x < v.b.left - 6 || pb.x > v.b.right + 6 || pb.y < v.b.top - 5 || pb.y > v.b.y + 5 { continue }
			let l: (Double, Double) = v.toLocal(pb.x, pb.y - 1)
			let px: Int = Int(floor(l.0))
			let py: Int = Int(floor(l.1))
			for dy in -4...3 {
				for dx in -5...5 where vehicleBlock(v, PartCell(dx: px + dx, dy: py + dy)) == t { return true }
			}
		}
		return false
	}

	/// A tap on a block built on a vehicle that does something there: doors open and shut, chairs and
	/// sofas are sat on, beds slept in. True when it was one of those.
	func useVehicleBlock(_ v: Vehicle, _ c: PartCell) -> Bool {
		guard let t = vehicleBlock(v, c) else { return false }
		if isDoor(t) {
			setVehicleDoor(v, c, open: t == .doorClosed)
			return true
		}
		if isSeat(t) {
			sitAboard(v, c)
			return true
		}
		let modBed: Bool = t.isMod && ModRuntime.shared.bedTiles.contains(t.rawValue)
		if t == .bedL || t == .bedR || modBed {
			sleepAboard()
			return true
		}
		return false
	}

	// MARK: back walls

	/// Puts a block up as a back wall in a vehicle cell under the aim point (inside its box). True when
	/// the tap was for a vehicle.
	func attachWallToVehicle(_ t: Tile) -> Bool {
		for v in vehicles where !v.parts.isEmpty {
			if aimX < v.b.left - 0.5 || aimX > v.b.right + 0.5 || aimY < v.b.top - 0.5 || aimY > v.b.y + 0.5 { continue }
			let c: PartCell = v.cellAt(aimX, aimY)
			if c.dx < v.minX || c.dx > v.maxX || c.dy < v.minY || c.dy > v.maxY { continue }
			if placeCD > 0 { return true }
			placeCD = 0.16
			if v.walls[c] != nil {
				say("There is a wall there already.", 1.2)
				return true
			}
			let k: Int = blockWallValue(t)
			if k <= 0 || !canBeWall(t) {
				say("That can't be a wall.", 1.2)
				return true
			}
			v.walls[c] = UInt8(k)
			v.recompute(keepAnchor: true)
			v.kit = -1
			if !isCreative { inv.removeAt(sel, 1) }
			sfx(.place, 0.5)
			swingT = 0.14
			bumpHUD()
			return true
		}
		return false
	}

	/// The wrench on an empty vehicle cell with a back wall (or any cell with AS WALL on) takes the wall down
	func removeVehicleWall(_ v: Vehicle, _ c: PartCell) -> Bool {
		guard let k = v.walls[c] else { return false }
		if v.parts[c] != nil && !wallMode { return false }
		v.walls[c] = nil
		v.recompute(keepAnchor: true)
		if let t = blockWallTile(Int(k)) { giveItem(.block(t), 1) }
		sfx(.breakStone, 0.5)
		bumpHUD()
		return true
	}
}

/// How much a back wall adds to a vehicle (a wall is thin: a fifth of its block)
func vehicleWallMass(_ k: UInt8) -> Double {
	guard let t = blockWallTile(Int(k)) else { return 0.2 }
	return max(0.05, tileWeight(t) * 0.2)
}

// ===== p12c_fluids =====

// MARK: - Liquids
// Water, lava and a mod's own liquids flow. A cell holds a level of its liquid: a full cell is simply the
// liquid's block, a part-full one also keeps its level in the chunk's level layer (Chunk.level, 1...254
// of 255). A cell that changes, or whose neighbour does, wakes up: its liquid falls first, then evens
// out with the cells beside it, a few times a second (a thick liquid such as lava more slowly); a cell
// with nothing left to do goes back to sleep, so a still sea costs nothing. Where two liquids meet they
// react (lava and water make stone, or obsidian from a full block of lava), or the lighter one floats
// on the heavier. Thin films dry up instead of spreading forever.

/// What a liquid is like (the game's water and lava, or a mod's)
struct LiquidDef {
	var tile: Tile
	var color: UInt32 = 0x3B6FC8
	/// how see-through it is drawn where it is not a whole block (0 clear ... 1 solid colour)
	var opacity: Double = 0.72
	/// water is 1: what floats in it, and which of two liquids sinks under the other
	var density: Double = 1.0
	/// how thick it is: water 1, lava 4 (it moves that many times less often)
	var thick: Double = 1.0
	/// how far a block of it spreads over flat ground before it is too thin to flow (in blocks)
	var reach: Int = 7
	/// damage a second to whoever is in it, and whether it burns
	var harm: Double = 0
	var hot: Bool = false
	/// what it becomes where it meets another liquid (a part-full cell: `hardensThin`); nil: it does not
	var hardens: Tile? = nil
	var hardensThin: Tile? = nil
	/// a lone film of it dries up
	var dries: Bool = false
	/// an effect it gives whoever is in it (a ModEffectKind's number; -1 none) and how strong
	var effect: Int = -1
	var effectAmt: Double = 0
}

enum Liquids {
	static let water: LiquidDef = LiquidDef(tile: .water, color: 0x3B6FC8, opacity: 0.72, density: 1.0, thick: 1.0, reach: 7, harm: 0, hot: false, hardens: nil, hardensThin: nil, dries: true)
	static let lava: LiquidDef = LiquidDef(tile: .lava, color: 0xE8642A, opacity: 0.95, density: 3.1, thick: 4.0, reach: 4, harm: 4, hot: true, hardens: .obsidian, hardensThin: .stone, dries: false)

	static func def(_ t: Tile) -> LiquidDef? {
		if t == .water { return water }
		if t == .lava { return lava }
		if t.isMod { return ModRuntime.shared.liquidDefs[t.rawValue] }
		return nil
	}

	/// which tiles are liquids that burn (lava, and a mod's hot liquids: see ModRuntime.install)
	static var hotTable: [Bool] = (0..<256).map { $0 == Int(Tile.lava.rawValue) }

	/// how many flow steps a second, and the most cells looked at in one step
	static let rate: Double = 20.0
	static let budget: Int = 1600
	/// how far along a row a liquid evens out in one step (each way), and the least depth (in sevenths of
	/// a block's 255ths) it spreads onto open ground from
	static let rowReach: Int = 24
	static let minSpread: Int = 4
}

extension World {
	/// How full a cell is of its liquid (0: none; 1: a whole block)
	func liquidAmount(_ x: Int, _ y: Int) -> Double {
		if y < 0 || y >= H { return 0 }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return 0 }
		let i: Int = (x - cx * chunkW) * H + y
		if !Tile.liquidTable[Int(c.tiles[i])] { return 0 }
		if c.level.isEmpty { return 1 }
		let l: UInt8 = c.level[i]
		return l == 0 ? 1 : Double(l) / 255.0
	}

	/// Whether a cell holds only part of a block of its liquid
	func partLiquid(_ x: Int, _ y: Int) -> Bool {
		let a: Double = liquidAmount(x, y)
		return a > 0 && a < 1
	}

	/// How full a cell is in 255ths (0 none, 255 a whole block): the flow counts in these, so not a drop
	/// is made or lost as it moves
	func liquidLevel(_ x: Int, _ y: Int) -> Int {
		if y < 0 || y >= H { return 0 }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return 0 }
		let i: Int = (x - cx * chunkW) * H + y
		if !Tile.liquidTable[Int(c.tiles[i])] { return 0 }
		if c.level.isEmpty { return 255 }
		let l: UInt8 = c.level[i]
		return l == 0 ? 255 : Int(l)
	}

	/// Puts so much of a liquid in a cell (none: air; a whole block: the liquid's block)
	func setLiquid(_ x: Int, _ y: Int, _ t: Tile, _ amount: Double) {
		setLiquidLevel(x, y, t, Int((amount * 255.0).rounded()))
	}

	/// The same in 255ths
	func setLiquidLevel(_ x: Int, _ y: Int, _ t: Tile, _ level: Int) {
		if y < 1 || y >= H - 1 { return }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return }
		let i: Int = (x - cx * chunkW) * H + y
		if level <= 0 {
			if Tile.liquidTable[Int(c.tiles[i])] { _ = set(x, y, .air) }
			return
		}
		if tile(x, y) != t { _ = set(x, y, t) }
		let lv: UInt8 = level >= 255 ? 0 : UInt8(level)
		if c.level.isEmpty {
			if lv == 0 { return }
			c.level = [UInt8](repeating: 0, count: chunkW * H)
		}
		let old: UInt8 = c.level[i]
		if old == lv { return }
		c.level[i] = lv
		c.dirty = true
		if (old == 0) != (lv == 0) {
			// whole and part-full cells are drawn differently (see SectionPainter and drawLiquids)
			c.partials += lv == 0 ? -1 : 1
			c.bumpRows(y, y)
		}
		flowRev &+= 1
		wakeFlow(x, y)
	}

	/// Wakes the liquid in a cell and the cells round it
	func wakeFlow(_ x: Int, _ y: Int) {
		queueFlow(x, y)
		queueFlow(x - 1, y)
		queueFlow(x + 1, y)
		queueFlow(x, y - 1)
		queueFlow(x, y + 1)
	}

	@inline(__always) func queueFlow(_ x: Int, _ y: Int) {
		if !tile(x, y).liquid { return }
		let p: IntPair = IntPair(x: x, y: y)
		if flowSet.contains(p) { return }
		flowSet.insert(p)
		flowQ.append(p)
	}

	/// What a liquid can flow into: open air, or a plant it washes away
	@inline(__always) func fillable(_ t: Tile) -> Bool {
		if t == .air { return true }
		return t.isPlant && !t.solid && t != .torch && t != .lantern && t != .sapling && !isDoor(t)
	}

	/// One step of every waking liquid cell (the lowest first, so a falling column moves as one).
	/// Returns how many cells it looked at.
	@discardableResult
	func stepFlow(_ budget: Int) -> Int {
		if flowQ.isEmpty { return 0 }
		flowTick &+= 1
		var work: [IntPair] = flowQ
		flowQ.removeAll(keepingCapacity: true)
		flowSet.removeAll(keepingCapacity: true)
		work.sort { $0.y > $1.y }
		var n: Int = 0
		for p in work {
			if n >= budget {
				// the rest waits for the next step
				if !flowSet.contains(p) { flowSet.insert(p); flowQ.append(p) }
				continue
			}
			flowCell(p.x, p.y)
			n += 1
		}
		return n
	}

	/// One liquid cell's step: it reacts with another liquid next to it, falls, then evens out sideways
	func flowCell(_ x: Int, _ y: Int) {
		if !isLoaded(x) || y < 1 || y >= H - 2 { return }
		let t: Tile = tile(x, y)
		guard t.liquid, let L = Liquids.def(t) else { return }
		let slow: Int = max(1, Int(L.thick.rounded()))
		if slow > 1 && (flowTick &+ x) % slow != 0 {
			// a thick liquid waits its turn (it stays awake meanwhile)
			let p: IntPair = IntPair(x: x, y: y)
			if !flowSet.contains(p) { flowSet.insert(p); flowQ.append(p) }
			return
		}
		if meetLiquids(x, y, t, L) { return }
		var a: Int = liquidLevel(x, y)
		var moved: Bool = false
		// down
		let below: Tile = tile(x, y + 1)
		if fillable(below) {
			setLiquidLevel(x, y + 1, t, a)
			a = 0
			moved = true
		} else if below == t {
			let b: Int = liquidLevel(x, y + 1)
			let take: Int = min(a, 255 - b)
			if take > 0 {
				setLiquidLevel(x, y + 1, t, b + take)
				a -= take
				moved = true
			}
		}
		// sideways, standing on something (the floor, or liquid already full below): it evens out with the
		// row it is on, as far as the same floor goes each way, so a pool is level in a step or two
		if a > 1 && (!moved || a > 5) && rowUneven(x, y, t, a) {
			let lv: Int = levelRow(x, y, t, a, L)
			if lv != a {
				a = lv
				moved = true
			}
		} else if a > 0 && L.dries && a * 2 < 255 / max(1, L.reach) && !tile(x - 1, y).liquid && !tile(x + 1, y).liquid && !fillable(tile(x, y + 1)) {
			// a lone film too thin to flow dries up
			a = 0
			moved = true
		}
		if moved { setLiquidLevel(x, y, t, a) }
	}

	/// Whether a liquid cell has a lower neighbour of the same liquid, or open space, beside it
	func rowUneven(_ x: Int, _ y: Int, _ t: Tile, _ a: Int) -> Bool {
		for d in [-1, 1] {
			if !isLoaded(x + d) { continue }
			let st: Tile = tile(x + d, y)
			if st == t { if liquidLevel(x + d, y) < a - 1 { return true } } else if fillable(st) && a * Liquids.minSpread >= 255 / 7 { return true }
		}
		return false
	}

	/// Shares a liquid out evenly along its row: every cell of it and every open cell as far as the floor
	/// goes each way (a cell over a drop ends the row: the liquid falls from it next). A thin layer only
	/// spreads over as many open cells as it can cover more than a film deep. Nothing is made or lost.
	/// Returns this cell's new level (the others are set here).
	func levelRow(_ x: Int, _ y: Int, _ t: Tile, _ a: Int, _ L: LiquidDef) -> Int {
		var cells: [(Int, Int)] = [(x, a)]
		var total: Int = a
		var held: Int = 1
		for dir in [-1, 1] {
			var k: Int = 1
			while k <= Liquids.rowReach {
				let nx: Int = x + dir * k
				if !isLoaded(nx) { break }
				let st: Tile = tile(nx, y)
				var lvl: Int = 0
				if st == t { lvl = liquidLevel(nx, y) } else if !fillable(st) { break }
				cells.append((nx, lvl))
				total += lvl
				if lvl > 0 { held += 1 }
				let below: Tile = tile(nx, y + 1)
				if fillable(below) || (below == t && liquidLevel(nx, y + 1) < 255) { break }
				k += 1
			}
		}
		if cells.count < 2 { return a }
		// every cell that holds some keeps a share; a thin layer covers only as many open cells (the nearest)
		// as it can cover more than a film deep
		let film: Int = max(1, 255 / max(1, L.reach))
		let most: Int = max(held, total * 4 / (film * 3))
		var keep: [(Int, Int)] = cells.filter { $0.1 > 0 }
		var open: [(Int, Int)] = cells.filter { $0.1 == 0 }
		open.sort { abs($0.0 - x) < abs($1.0 - x) }
		var room: Int = most - keep.count
		for c in open where room > 0 {
			keep.append(c)
			room -= 1
		}
		// (the odd 255ths go to the leftmost cells, whichever cell does the sharing, and a row already even
		// to within one is left alone: it settles instead of trading single drops back and forth)
		cells = keep.sorted { $0.0 < $1.0 }
		let n: Int = cells.count
		if n < 2 { return a }
		let each: Int = total / n
		let extra: Int = total - each * n
		var uneven: Bool = false
		for (i, c) in cells.enumerated() where abs(each + (i < extra ? 1 : 0) - c.1) > 1 { uneven = true }
		if !uneven { return a }
		var mine: Int = a
		for (i, c) in cells.enumerated() {
			let lv: Int = each + (i < extra ? 1 : 0)
			if c.0 == x { mine = lv; continue }
			if lv != c.1 { setLiquidLevel(c.0, y, t, lv) }
		}
		return mine
	}

	/// Where this liquid touches another: one that hardens does (lava into obsidian, or stone where it is
	/// thin), else the heavier one sinks under the lighter. True when anything changed.
	func meetLiquids(_ x: Int, _ y: Int, _ t: Tile, _ L: LiquidDef) -> Bool {
		let ways: [(Int, Int)] = [(0, 1), (0, -1), (1, 0), (-1, 0)]
		for w in ways {
			let nx: Int = x + w.0
			let ny: Int = y + w.1
			let n: Tile = tile(nx, ny)
			if !n.liquid || n == t { continue }
			guard let M = Liquids.def(n) else { continue }
			if L.hardens != nil || M.hardens != nil {
				// the one that hardens does; with both, the hotter (lava stays the one that sets)
				let mine: Bool = L.hardens != nil && (M.hardens == nil || L.hot || !M.hot)
				let hx: Int = mine ? x : nx
				let hy: Int = mine ? y : ny
				let H0: LiquidDef = mine ? L : M
				let full: Bool = liquidAmount(hx, hy) >= 0.99
				let into: Tile = (full ? H0.hardens : (H0.hardensThin ?? H0.hardens)) ?? .stone
				_ = set(hx, hy, into)
				flowSteam.append(IntPair(x: hx, y: hy))
				return true
			}
			if w.1 == 1 && L.density > M.density + 0.01 {
				// heavier on top of lighter: they trade places
				let a: Double = liquidAmount(x, y)
				let b: Double = liquidAmount(nx, ny)
				_ = set(x, y, n)
				setLiquid(x, y, n, b)
				_ = set(nx, ny, t)
				setLiquid(nx, ny, t, a)
				return true
			}
		}
		return false
	}

	/// The liquid placed so far is at rest: nothing flows until something changes next to it again (for
	/// pools built by hand that are meant to stay put, as the world's own seas do)
	func calmLiquids() {
		flowQ.removeAll()
		flowSet.removeAll()
	}

	/// Every part-full cell of a chunk wakes (after loading it, its liquid may be mid-flow)
	func wakePartials(_ c: Chunk) {
		if c.level.isEmpty { return }
		var n: Int = 0
		for i in 0..<c.level.count where c.level[i] != 0 {
			if !Tile.liquidTable[Int(c.tiles[i])] { c.level[i] = 0; continue }
			n += 1
			queueFlow(c.cx * chunkW + i / H, i % H)
		}
		c.partials = n
	}
}

extension Game {
	/// The liquids' flow, a few times a second (also in a dimension's own world)
	func updateFlow(_ dt: Double) {
		if world.flowQ.isEmpty {
			flowAccum = 0
			return
		}
		flowAccum += dt
		var k: Int = 0
		let step: Double = 1.0 / Liquids.rate
		while flowAccum >= step && k < 2 {
			world.stepFlow(Liquids.budget)
			flowAccum -= step
			k += 1
		}
		if flowAccum > step { flowAccum = step }
		// where lava met water: a hiss of steam
		if !world.flowSteam.isEmpty {
			for p in world.flowSteam.prefix(6) {
				spawnParticles(Double(p.x) + 0.5, Double(p.y) + 0.2, 0xE8E8EC, 4, 2.0, 0.6, -4)
			}
			if let p = world.flowSteam.first, abs(Double(p.x) - pb.x) < 30 { sfx(.flask, at: Double(p.x), 0.35) }
			world.flowSteam.removeAll()
		}
	}

	/// The liquid at a point, and how deep it is there (0...1 of the cell)
	func liquidHere(_ x: Double, _ y: Double) -> LiquidDef? {
		let t: Tile = world.tile(Int(floor(x)), Int(floor(y)))
		if !t.liquid { return nil }
		let a: Double = world.liquidAmount(Int(floor(x)), Int(floor(y)))
		if y - floor(y) < 1.0 - a { return nil }
		return Liquids.def(t)
	}
}

extension Game {
	/// The bucket: tapped on a liquid it takes up a block of it (from a part-full cell, what is there and
	/// then from the cells round it); full, tapped on open space, it pours the block out there to flow
	func useBucket() {
		if useCD > 0 { return }
		guard let st = inv.slots[sel], st.item == .gadget(.bucket) else { return }
		useCD = 0.25
		if !inReach(aimX, aimY) {
			say("Too far away. Tap closer to you.", 1.2)
			return
		}
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		swingT = 0.14
		if st.extra == 0 {
			let t: Tile = world.tile(tx, ty)
			guard t.liquid else {
				say("Tap water or lava (or a mod's liquid) to fill the bucket.", 1.8)
				return
			}
			var got: Double = 0
			let near: [(Int, Int)] = [(0, 0), (-1, 0), (1, 0), (0, -1), (0, 1), (-2, 0), (2, 0)]
			for d in near where got < 0.999 {
				let x: Int = tx + d.0
				let y: Int = ty + d.1
				if world.tile(x, y) != t { continue }
				let a: Double = world.liquidAmount(x, y)
				let take: Double = min(a, 1.0 - got)
				world.setLiquid(x, y, t, a - take)
				got += take
			}
			inv.slots[sel]?.extra = Int(t.rawValue) + 1
			sfx(.splash, 0.5)
			say(joinText("Bucket of ", t.name, "."), 1.2)
		} else {
			guard let t = Tile(rawValue: UInt8(clampI(st.extra - 1, 0, 255))), t.liquid else {
				inv.slots[sel]?.extra = 0
				return
			}
			let here: Tile = world.tile(tx, ty)
			if here == t && world.liquidAmount(tx, ty) < 0.999 {
				world.setLiquid(tx, ty, t, 1.0)
			} else if world.fillable(here) && !world.tile(tx, ty).solid {
				world.setLiquid(tx, ty, t, 1.0)
			} else {
				say("Pour it into open space.", 1.2)
				return
			}
			inv.slots[sel]?.extra = 0
			sfx(.splash, 0.6)
		}
		bumpHUD()
	}

	/// What harms or helps whoever is in a mod's liquid (lava and water are handled as before)
	func modLiquidEffects(_ dt: Double) {
		guard let L = liquidHere(pb.x, pb.y - pb.h * 0.4), L.tile.isMod else { return }
		if L.harm > 0 && mode != .creative && !godMode {
			liquidHarmT += dt
			if liquidHarmT >= 0.5 {
				liquidHarmT = 0
				var info = DamageInfo(amount: L.harm * 0.5, type: L.hot ? .lava : .hazard, source: .environment)
				info.originX = pb.x
				_ = hurtPlayer(info)
			}
		}
		if L.effect >= 0, let k = ModEffectKind(rawValue: L.effect) {
			effects.add(k, L.effectAmt, 1.0)
		}
	}
}

// MARK: - Air inside a hull: floating by enclosed volume, flooding, submarines

extension Vehicle {
	/// Whether a point (in its cells) is in the dry air inside it (a cabin under water)
	func dryAt(_ lx: Double, _ ly: Double) -> Bool {
		guard let f = hullAir[PartCell(dx: Int(floor(lx)), dy: Int(floor(ly)))] else { return false }
		return f < 0.5
	}
}

extension Game {
	/// Works out which cells inside a vehicle hold air the liquid outside cannot reach. Liquid comes in
	/// only through cells that are themselves under the surface: from outside the vehicle's box, or from a
	/// flooded cell next to them; solid parts and solid blocks keep it out. So an open boat floats on
	/// the air in its hull (its open top is above the water), a hole below the waterline floods the
	/// cells it reaches, a few at a time, and a sealed hull (a submarine) stays dry however deep it goes.
	/// The air in each dry cell holds the vehicle up like a block of wood would.
	func updateHullAir(_ v: Vehicle, _ dt: Double) {
		v.hullT -= dt
		if v.hullT > 0 { return }
		let step: Double = 0.25
		v.hullT = step
		if v.submerged <= 0.001 && v.hullAir.isEmpty { return }
		let x0: Int = v.minX - 1
		let y0: Int = v.minY - 1
		let gw: Int = v.gridW + 2
		let gh: Int = v.gridH + 2
		if gw * gh > 40_000 { return }
		var under: [Bool] = [Bool](repeating: false, count: gw * gh)
		var tight: [Bool] = [Bool](repeating: false, count: gw * gh)
		for gy in 0..<gh {
			for gx in 0..<gw {
				let c: PartCell = PartCell(dx: x0 + gx, dy: y0 + gy)
				let i: Int = gy * gw + gx
				tight[i] = v.walkAt(c.dx, c.dy) == cellSolid
				let w: (Double, Double) = v.cellCenter(c)
				under[i] = submergedFraction(w.0, w.1) > 0.5
			}
		}
		// the liquid's way in: from the ring outside the box, through cells under the surface
		var wet: [Bool] = [Bool](repeating: false, count: gw * gh)
		var stack: [Int] = []
		for gy in 0..<gh {
			for gx in 0..<gw where gx == 0 || gy == 0 || gx == gw - 1 || gy == gh - 1 {
				let i: Int = gy * gw + gx
				if under[i] && !tight[i] { wet[i] = true; stack.append(i) }
			}
		}
		while let i = stack.popLast() {
			let gx: Int = i % gw
			let gy: Int = i / gw
			let next: [(Int, Int)] = [(gx + 1, gy), (gx - 1, gy), (gx, gy + 1), (gx, gy - 1)]
			for n in next {
				if n.0 < 0 || n.1 < 0 || n.0 >= gw || n.1 >= gh { continue }
				let j: Int = n.1 * gw + n.0
				if wet[j] || tight[j] || !under[j] { continue }
				wet[j] = true
				stack.append(j)
			}
		}
		// each inside cell under the surface: flooding where the liquid reaches, trapped water staying,
		// and cells that rise above the surface draining
		var out: [PartCell: Double] = [:]
		let rate: Double = 1.6 * step
		for gy in 1..<(gh - 1) {
			for gx in 1..<(gw - 1) {
				let i: Int = gy * gw + gx
				if tight[i] { continue }
				let c: PartCell = PartCell(dx: x0 + gx, dy: y0 + gy)
				var f: Double = v.hullAir[c] ?? 0
				if wet[i] { f = min(1.0, f + rate) } else if !under[i] { f = max(0, f - rate) }
				if under[i] || f > 0 { out[c] = f }
			}
		}
		v.hullAir = out
	}

	/// The air held in a vehicle's hull pushes it up where it is (as a block of wood the same size would)
	func hullAirForces(_ v: Vehicle, _ h: Double, _ c: Double, _ s: Double) {
		let invM: Double = 1.0 / v.mass
		let invI: Double = 1.0 / v.inertia
		for (cell, flood) in v.hullAir where flood < 0.999 {
			let lx: Double = Double(cell.dx) + 0.5 - v.comX
			let ly: Double = Double(cell.dy) + 0.5 - v.comY
			let rx: Double = lx * c - ly * s
			let ry: Double = lx * s + ly * c
			let f: Double = submergedFraction(v.px + rx, v.py + ry)
			if f <= 0 { continue }
			// (a cell with a part in it, a seat or a lamp, already floats by the part: the air is the rest)
			let own: Double = v.parts[cell].map { cellDisplacement(v, cell, $0) } ?? 0
			let disp: Double = (1.0 - flood) * max(0, 1.0 - own) * liquidDensity(v.px + rx, v.py + ry)
			let pvy: Double = v.vy + v.angVel * rx
			let fy: Double = -gravityG * disp * f - pvy * 1.5 * disp * f
			v.vy += fy * invM * h
			v.angVel += rx * fy * invI * h
		}
	}

	/// The ballast tanks fill or empty as the stick says (down to dive, up to rise) while the vehicle is
	/// in the water and somebody (or the autopilot) is at the controls; the air brakes open while the stick
	/// pushes against the way it is going, or on the ground with no throttle
	func ballastAndBrakes(_ v: Vehicle, _ dt: Double) {
		let crewed: Bool = v.rider || v.auto != 0
		if v.ballasts > 0 && crewed && abs(v.pitch) > 0.05 {
			v.ballast = clampD(v.ballast - v.pitch * Aero.ballastRate * dt, 0, 1)
			v.asleep = false
			v.sleepT = 0
		}
		if v.airBrakes > 0 {
			let against: Bool = crewed && abs(v.throttle) > 0.1 && v.throttle * v.vx < 0
			let rolling: Bool = v.contacts > 0 && abs(v.throttle) < 0.1 && abs(v.vx) > 1.5
			let want: Double = against || rolling ? 1.0 : 0.0
			v.brakeOpen += clampD(want - v.brakeOpen, -Aero.brakeRate * dt, Aero.brakeRate * dt)
		}
	}

	/// The wind where a vehicle is: the weather's, with gusts that roll along the land, and less of it
	/// behind the land that shelters it (a hill, a wall, a cave roof)
	func windAtVehicle(_ v: Vehicle) -> Double {
		if world.dim != .overworld || !settings.weatherOn { return 0 }
		let base: Double = weatherAt(v.px, v.py).wind
		if abs(base) < 0.05 { return 0 }
		let roll: Double = 1.0 + 0.25 * sin(v.px * 0.045 - clock * 0.8 * (base >= 0 ? 1.0 : -1.0))
		return base * roll * windShelter(v.px, v.py, base >= 0 ? -1 : 1)
	}

	/// How much of the wind reaches a place: land close upwind takes most of it
	func windShelter(_ x: Double, _ y: Double, _ upwind: Int) -> Double {
		let tx: Int = Int(floor(x))
		let ty: Int = Int(floor(y))
		var k: Int = 2
		while k <= 8 {
			let px: Int = tx + upwind * k
			if world.tile(px, ty).solid && world.tile(px, ty - 1).solid { return k <= 4 ? 0.3 : 0.6 }
			k += 2
		}
		// under a roof: hardly any
		var r: Int = 1
		while r <= 6 {
			if world.tile(tx, ty - r).solid && world.tile(tx, ty - r - 1).solid { return 0.2 }
			r += 1
		}
		return 1.0
	}

	/// Tapping a wing (or a flap, elevator or tailplane) of a parked vehicle tilts it a step (3 steps
	/// either way, then round again): a wing tilted up lifts more at a lower speed, with more drag
	func tiltWing(_ v: Vehicle, _ c: PartCell) {
		var k: Int = (v.tilt[c] ?? 0) + 1
		if k > Aero.tiltSteps { k = -Aero.tiltSteps }
		v.tilt[c] = k == 0 ? nil : k
		v.asleep = false
		let deg: Int = Int((Double(k) * Aero.tiltStep * 180.0 / Double.pi).rounded())
		let what: String = k == 0 ? "level" : (k > 0 ? joinText("tilted up ", String(deg), " degrees") : joinText("tilted down ", String(-deg), " degrees"))
		say(joinText((v.parts[c] ?? .wing).name, " ", what, ". Tap again to tilt it further."), 2.5)
	}
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

/// One pixel of a leaf tuft: where in its cell (y * tileArtPx + x), and its colour
struct TuftPixel {
	var at: Int
	var c: UInt32
}

/// Leaves that stick out of a canopy into the open cells beside it, so a tree's crown has a ragged
/// edge instead of a square one. L, g, s and d are the leaf block's own tones from light to dark.
enum LeafTufts {
	/// growing up into the cell above (its bottom four rows; the last row touches the leaves)
	static let up: [String] = [
		"....L........L..",
		"...LgL.....LLgL.",
		"..LgggL...Lgggs.",
		".LggggsL.Lggggs.",
	]
	/// hanging into the cell below (its top four rows; the first row touches the leaves)
	static let down: [String] = [
		".sggggs..sgggs..",
		"..sggs....sgs...",
		"...ss......s....",
		"................",
	]
	/// sticking out into the cell to the left (its right four columns; the last touches the leaves)
	static let left: [String] = [
		"....", "...L", "..Lg", ".Lgg", "..sg", "...s", "....", "....",
		"....", "..Lg", ".Lgg", ".sgg", "..ss", "....", "....", "....",
	]
	/// sticking out into the cell to the right (its left four columns; the first touches the leaves)
	static let right: [String] = [
		"....", "L...", "gL..", "ggs.", "gs..", "s...", "....", "....",
		"....", "gL..", "ggL.", "ggs.", "ss..", "....", "....", "....",
	]

	/// The four tones of a leaf block's picture, light to dark
	static func tones(_ b: PixelBuf) -> [UInt32] {
		var seen: [UInt32] = []
		for c in b.px where (c >> 24) != 0 {
			let rgb: UInt32 = c & 0xFFFFFF
			if !seen.contains(rgb) { seen.append(rgb) }
		}
		if seen.isEmpty { return [0x6A9A4A, 0x4C7A3A, 0x3A5E30, 0x284426] }
		seen.sort { artLum($0) > artLum($1) }
		let n: Int = seen.count
		return [seen[0], seen[min(n - 1, n / 3)], seen[min(n - 1, (2 * n) / 3)], seen[n - 1]]
	}

	/// A leaf block's tufts: for each side (0 up, 1 down, 2 left, 3 right), two versions (the second
	/// mirrored, or moved along the edge) so a canopy's edge does not repeat block by block
	static func make(_ b: PixelBuf) -> [[[TuftPixel]]] {
		let tn: [UInt32] = tones(b)
		let T: Int = tileArtPx
		func ink(_ ch: Character) -> UInt32? {
			switch ch {
			case "L": return 0xFF000000 | tn[0]
			case "g": return 0xFF000000 | tn[1]
			case "s": return 0xFF000000 | tn[2]
			case "d": return 0xFF000000 | tn[3]
			default: return nil
			}
		}
		func cells(_ rows: [String], _ ox: Int, _ oy: Int, _ mirror: Bool, _ shift: Int) -> [TuftPixel] {
			var out: [TuftPixel] = []
			let w: Int = rows.first?.count ?? 0
			for (y, row) in rows.enumerated() {
				for (x, ch) in row.enumerated() {
					guard let c = ink(ch) else { continue }
					let xx: Int = ox + (mirror ? w - 1 - x : x)
					let yy: Int = (oy + y + shift) % T
					out.append(TuftPixel(at: yy * T + xx, c: c))
				}
			}
			return out
		}
		let top: Int = T - up.count
		let side: Int = T - (left.first?.count ?? 4)
		return [
			[cells(up, 0, top, false, 0), cells(up, 0, top, true, 0)],
			[cells(down, 0, 0, false, 0), cells(down, 0, 0, true, 0)],
			[cells(left, side, 0, false, 0), cells(left, side, 0, false, T / 2)],
			[cells(right, 0, 0, false, 0), cells(right, 0, 0, false, T / 2)],
		]
	}
}

final class SectionPainter: @unchecked Sendable {
	static let shared: SectionPainter = SectionPainter()

	let tileCount: Int
	/// art for every tile, by raw value: four pictures each (as drawn, mirrored, turned top to bottom,
	/// both), tileArtPx x tileArtPx pixels a picture
	var tilePx: [UInt32]
	/// which of those four a tile may be drawn as from place to place (0: only as drawn; 1: also
	/// mirrored; 3: all four), so a wall of one block is not wallpaper
	var tileFlip: [Int]
	/// 0 = fully transparent, 1 = fully opaque, 2 = mixed alpha
	var tileKind: [Int]
	/// darkened backdrop walls, by wall kind - 1
	var wallPx: [UInt32]
	var wallBufs: [PixelBuf]
	var tileBufs: [PixelBuf]
	let wallCount: Int
	/// which tiles are leaves, and their tufts (see LeafTufts)
	var leafT: [Bool] = [Bool](repeating: false, count: 256)
	var tufts: [Int: [[[TuftPixel]]]] = [:]
	/// a leaf block's tones, light to dark (for the leaves that fall from it)
	var leafTones: [Int: [UInt32]] = [:]

	/// Works out which tiles are leaves and makes their tufts (again when a world's mods change: a
	/// mod's trees have leaf blocks of their own)
	func findLeaves() {
		var lt: [Bool] = [Bool](repeating: false, count: 256)
		var tf: [Int: [[[TuftPixel]]]] = [:]
		var tn: [Int: [UInt32]] = [:]
		for raw in 0..<min(256, tileBufs.count) {
			guard let t = Tile(rawValue: UInt8(raw)), isLeafTile(t) else { continue }
			lt[raw] = true
			tf[raw] = LeafTufts.make(tileBufs[raw])
			tn[raw] = LeafTufts.tones(tileBufs[raw])
		}
		leafT = lt
		tufts = tf
		leafTones = tn
	}

	/// How dark a wall made from a block is drawn
	static func wallShade(_ c: UInt32) -> UInt32 {
		return (c >> 24) == 0 ? 0 : (c & 0xFF000000) | shadeRGB(c & 0xFFFFFF, 0.5)
	}

	/// Writes a tile's four pictures into the art table and says what kind it is (0 clear, 1 solid,
	/// 2 partly see-through)
	static func put(_ b: PixelBuf, _ px: inout [UInt32], _ i: Int) -> Int {
		let T: Int = tileArtPx
		let n: Int = T * T
		var allClear: Bool = true
		var allSolid: Bool = true
		for y in 0..<T {
			for x in 0..<T {
				let k: Int = y * T + x
				let c: UInt32 = k < b.px.count ? b.px[k] : 0
				let base: Int = i * 4 * n
				px[base + k] = c
				px[base + n + y * T + (T - 1 - x)] = c
				px[base + 2 * n + (T - 1 - y) * T + x] = c
				px[base + 3 * n + (T - 1 - y) * T + (T - 1 - x)] = c
				let a: UInt32 = c >> 24
				if a != 0 { allClear = false }
				if a != 255 { allSolid = false }
			}
		}
		return allClear ? 0 : (allSolid ? 1 : 2)
	}

	init() {
		let n: Int = tileArtPx * tileArtPx
		var tb: [PixelBuf] = []
		for t in Tile.allCases { tb.append(tileBuf(t)) }
		tileBufs = tb
		tileCount = tb.count
		var px: [UInt32] = [UInt32](repeating: 0, count: 256 * 4 * n)
		var kinds: [Int] = [Int](repeating: 0, count: 256)
		var flips: [Int] = [Int](repeating: 0, count: 256)
		for (i, b) in tb.enumerated() {
			kinds[i] = SectionPainter.put(b, &px, i)
			if i < 256, let f = TileSheet.flips[UInt8(i)] { flips[i] = f }
		}
		tilePx = px
		tileKind = kinds
		tileFlip = flips
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
			for i in 0..<n { wp.append(i < w.px.count ? w.px[i] : 0xFF000000) }
		}
		// walls made from any block (wall value 8 + its tile number): its art, darkened
		while wp.count < (blockWallBase - 1) * n { wp.append(0) }
		for raw in 0..<tb.count {
			let b: PixelBuf = tb[raw]
			for k in 0..<n { wp.append(SectionPainter.wallShade(k < b.px.count ? b.px[k] : 0)) }
		}
		wallBufs = ws
		wallPx = wp
		wallCount = blockWallBase - 1 + tb.count
		findLeaves()
	}

	/// Redraws the art of the tiles reserved for mods (their meaning changes with a world's mods)
	func refreshModTiles() {
		let n: Int = tileArtPx * tileArtPx
		let base: Int = Int(Tile.modBase)
		for i in 0..<ModLimits.blockSlots {
			let raw: Int = base + i
			guard raw < tileBufs.count, let t = Tile(rawValue: UInt8(raw)) else { continue }
			let b: PixelBuf = tileBuf(t)
			tileBufs[raw] = b
			tileKind[raw] = SectionPainter.put(b, &tilePx, raw)
			let wb: Int = (blockWallBase - 1 + raw) * n
			for k in 0..<n where wb + k < wallPx.count {
				wallPx[wb + k] = SectionPainter.wallShade(k < b.px.count ? b.px[k] : 0)
			}
		}
		findLeaves()
	}

	/// Paints section `sy` (rows sy*16 ..< sy*16+16) of a chunk: chunkW x 16 blocks at tileArtPx pixels
	/// a block, premultiplied ARGB. Solid ground gets a lit top edge and a dark line where it meets
	/// open space below or beside it, so the land reads as shapes.
	func paint(_ world: World, _ ch: Chunk, _ sy: Int) -> [UInt32] {
		let T: Int = tileArtPx
		let TT: Int = T * T
		let W: Int = chunkW * T
		let Hh: Int = 16 * T
		var buf: [UInt32] = [UInt32](repeating: 0, count: W * Hh)
		let H: Int = ch.H
		let y0: Int = sy * 16
		let back: [UInt8] = world.backdrop(ch)
		let opT: [Bool] = Tile.opaqueTable
		// part-full liquid cells are drawn live over the land (see WorldRenderer.drawLiquids)
		let lev: [UInt8] = ch.partials > 0 ? ch.level : []
		// edge shading follows "solid or trunk", so trees look exactly as they did when trunks had collision
		let soT: [Bool] = Tile.supportTable
		let wc: Int = wallCount
		// the columns just outside the chunk, for the side edges (nil: not loaded, treated as ground)
		let left: Chunk? = world.chunks[ch.cx - 1]
		let right: Chunk? = world.chunks[ch.cx + 1]
		buf.withUnsafeMutableBufferPointer { bb in
			ch.tiles.withUnsafeBufferPointer { tb in
				back.withUnsafeBufferPointer { kb in
					tilePx.withUnsafeBufferPointer { ab in
						tileKind.withUnsafeBufferPointer { kib in
							let flipT: [Int] = tileFlip
							let wx0: Int = ch.cx * chunkW
							wallPx.withUnsafeBufferPointer { wb in
								opT.withUnsafeBufferPointer { ob in
									soT.withUnsafeBufferPointer { sb in
										guard let out = bb.baseAddress, let tiles = tb.baseAddress, let backs = kb.baseAddress,
											  let art = ab.baseAddress, let tk = kib.baseAddress, let walls = wb.baseAddress,
											  let opq = ob.baseAddress, let sol = sb.baseAddress else { return }
										var lx: Int = 0
										while lx < chunkW {
											let colBase: Int = lx * H
											let ox: Int = lx * T
											var ly: Int = 0
											while ly < 16 {
												let y: Int = y0 + ly
												if y < 0 || y >= H { ly += 1; continue }
												let raw: Int = i8(tiles[colBase + y])
												let oy: Int = ly * T
												let opaque: Bool = opq[raw]
												let wall: Int = i8(backs[colBase + y]) - 1
												if wall >= 0 && wall < wc && !opaque {
													let src: UnsafePointer<UInt32> = walls + wall * TT
													var yy: Int = 0
													while yy < T {
														(out + (oy + yy) * W + ox).update(from: src + yy * T, count: T)
														yy += 1
													}
												}
												if raw == 0 { ly += 1; continue }
												if !lev.isEmpty && lev[colBase + y] != 0 { ly += 1; continue }
												let kind: Int = tk[raw]
												// which of the block's four pictures goes here: always the same one for a place
												var pick: Int = 0
												let fm: Int = flipT[raw]
												if fm != 0 {
													var hsh: Int = (wx0 + lx) &* 374761393 &+ y &* 668265263
													hsh = (hsh ^ (hsh >> 13)) &* 1274126177
													pick = (hsh >> 16) & fm
												}
												let src: UnsafePointer<UInt32> = art + (raw * 4 + pick) * TT
												if kind == 1 {
													var yy: Int = 0
													while yy < T {
														(out + (oy + yy) * W + ox).update(from: src + yy * T, count: T)
														yy += 1
													}
												} else if kind == 2 {
													var yy: Int = 0
													while yy < T {
														let row: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
														var xx: Int = 0
														while xx < T {
															let c: UInt32 = src[yy * T + xx]
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
												// edges where solid ground meets open space (easier to read the terrain)
												if sol[raw] && opaque {
													let upOpaque: Bool = y > 0 ? opq[i8(tiles[colBase + y - 1])] : false
													if !upOpaque {
														let row: UnsafeMutablePointer<UInt32> = out + oy * W + ox
														var xx: Int = 0
														while xx < T {
															row[xx] = 0xFF000000 | shadeRGB(row[xx] & 0xFFFFFF, 1.12)
															xx += 1
														}
													}
													let dnOpaque: Bool = y + 1 < H ? opq[i8(tiles[colBase + y + 1])] : true
													if !dnOpaque {
														let row: UnsafeMutablePointer<UInt32> = out + (oy + T - 1) * W + ox
														var xx: Int = 0
														while xx < T {
															row[xx] = 0xFF000000 | shadeRGB(row[xx] & 0xFFFFFF, 0.6)
															xx += 1
														}
													}
													var lfOpaque: Bool = true
													if lx > 0 {
														lfOpaque = opq[i8(tiles[colBase - H + y])]
													} else if let c = left, y < c.H {
														lfOpaque = opq[Int(c.tiles[(chunkW - 1) * c.H + y])]
													}
													if !lfOpaque {
														var yy: Int = 0
														while yy < T {
															let px: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox
															px[0] = 0xFF000000 | shadeRGB(px[0] & 0xFFFFFF, 0.72)
															yy += 1
														}
													}
													var rtOpaque: Bool = true
													if lx + 1 < chunkW {
														rtOpaque = opq[i8(tiles[colBase + H + y])]
													} else if let c = right, y < c.H {
														rtOpaque = opq[Int(c.tiles[y])]
													}
													if !rtOpaque {
														var yy: Int = 0
														while yy < T {
															let px: UnsafeMutablePointer<UInt32> = out + (oy + yy) * W + ox + T - 1
															px[0] = 0xFF000000 | shadeRGB(px[0] & 0xFFFFFF, 0.66)
															yy += 1
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
		paintTufts(&buf, world, ch, sy, left, right)
		premultiplyARGB(&buf)
		return buf
	}

	/// Leaves sticking out of a canopy: every open cell of the section with a leaf block above, below
	/// or beside it gets that block's tufts on that side
	func paintTufts(_ buf: inout [UInt32], _ world: World, _ ch: Chunk, _ sy: Int, _ left: Chunk?, _ right: Chunk?) {
		if tufts.isEmpty { return }
		let T: Int = tileArtPx
		let W: Int = chunkW * T
		let H: Int = ch.H
		let y0: Int = sy * 16
		let opT: [Bool] = Tile.opaqueTable
		func at(_ lx: Int, _ y: Int) -> Int {
			if y < 0 || y >= H { return 0 }
			if lx < 0 {
				guard let c = left, y < c.H else { return 0 }
				return Int(c.tiles[(chunkW - 1) * c.H + y])
			}
			if lx >= chunkW {
				guard let c = right, y < c.H else { return 0 }
				return Int(c.tiles[y])
			}
			return Int(ch.tiles[lx * H + y])
		}
		for lx in 0..<chunkW {
			for ly in 0..<16 {
				let y: Int = y0 + ly
				if y < 0 || y >= H { continue }
				let raw: Int = at(lx, y)
				if opT[raw] || leafT[raw] { continue }
				// (side 0: tufts growing up from the leaves below; 1: hanging from those above; 2: from
				// the leaves to the right, sticking out leftward; 3: from the leaves to the left)
				let near: [(Int, Int)] = [(at(lx, y + 1), 0), (at(lx, y - 1), 1), (at(lx + 1, y), 2), (at(lx - 1, y), 3)]
				for (nraw, side) in near where leafT[nraw] {
					guard let tf = tufts[nraw] else { continue }
					let wx: Int = ch.x0 + lx
					let pick: Int = Int(hashU(wx, y, UInt64(7717 + side)) & 1)
					let base: Int = ly * T * W + lx * T
					for tp in tf[side][pick] {
						let cy: Int = tp.at / T
						let cx: Int = tp.at - cy * T
						buf[base + cy * W + cx] = tp.c
					}
				}
			}
		}
	}
}

// ===== a01_artsheet =====

// MARK: - The hand-drawn pictures, kept as text
// Creatures and blocks are drawn at 16 pixels to a block with the tools in tools/art (parts laid over
// each other, a dark line round each), and packed here as text: pictures in a string cost the build far
// less than the same pictures as code. A picture's pixels run row after row, repeats written as a
// count: "12.3ab" is twelve clear pixels, three of colour a and one of colour b.

enum ArtSheet {
	/// A creature starts on a line "name|width|height|row of the soles|column of the middle|colours|
	/// poses"; the lines after it that start with "+" hold its frames, one after another with "/" between
	static let creatureText: String = """
		// <art:creatures> written by tools/art/build.py pack from tools/art/creatures: change the drawings, not this
		archer|34|34|31|13.5|a17191E,b574736,c392F24,d93B6A4,e71A09D,f3A5357,g507272,h1A1418,iD87067,j381E26,kE7E2C9,l7F8B66,m5A6641,nE4DCCD,o9A7A54,p3E4833,q2C342B,r72573B,s677186,t3F4C5F,u2C3544,v212633,w494048,x3A3238,y2A242C,z1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:5;shoot:5
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmp
		+an2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.asqt2quq2.an2aoa18.a6vuv2an2aoa18.as2tuv2uv2anaoa19.as2
		+tuv2uv2anoa21.a2tuv2uva.2a22.a2tuv2uva25.at2uvu2va25.aeg2agfa26.aeg2agfa25.a4wv3xa24.a4wyv2xza24.4av4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2h
		+ih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.
		+a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.asqt2quq2.an2aoa18.a6vuv2an2aoa18.a2s2tuvuv2anaoa20.as2tu2va.anoa22.a2t2uva2.2a23.vs2tuv28.av2tua28.avega29.aveg2a28.av
		+4wa27.av3wya28.a3va52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf
		+2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.vsqt2quqv2an2aoa18.a6vuv2an2aoa1
		+8.as2tuvtuv2anaoa20.a2tuvt2uvanoa21.a2tu2a2uv3a22.at2u2agfva24.aega.agfa25.aeg2a3xa24.a4wv3xza23.a4wyv3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.
		+acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn
		+2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.a3qp3qa.an2aoa18.asqt2quq2.an2aoa18.a6vuv2an2aoa18.as2tuvt2uvanaoa18.as2tu2at2uvanoa19.a2t2ua.a2u2v2a19.as2tua2.at2uva20.a2tua4.a
		+2uva20.aega5.agfa21.aega5.agf2a20.a3wa4.a4xa19.a3wya3.a3xza20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2g
		+e5ja23.2a2fgkjk2ga22.a3l5f2a22.a2lm5fanoa20.a2lmf2lf2manaoa19.al2mf2mfmpan2aoa18.a3mfmp3fan2aoa18.ap2mfmp2edfn2aoa18.a2p2mfq2gefn2ara19.a2p2m4fana2ra19.qpqmpmqa.an2ara18.
		+a3qp3qa.an2aoa18.vsqt2quqv2an2aoa18.a6vuv2an2aoa18.a2stuv2uv2anaoa20.as2tuvuv2anoa22.a2tuvuva.2a23.aegu3va26.aegvgfa26.a3wvgfa26.a3wyv2xa26.2a2v3xza28.5a50./14.5a28.a5b2a
		+25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja3.a20.a2ge5ja2.aoa18.2a2fgkjk2ga.anaoa16.a3l6fa.an2aoa15.a2l2m5f2a3f2aoa14.a2l2mf4lmfe3defr
		+a14.al2maf4m2p5egfa14.a4mf3pqf2g2ega2gf14.ap4m4f.2a3fg2fa14.a2p4m2pa4.anfaoa15.a2p3mpqa5.anaoa15.qpqmpmqa7.aoa15.a3qp3qa8.a16.asqt2quq26.a6vuva24.as2tuv2uva24.as2tuvuva26
		+.a2tu3va26.a2tu2va27.at2uva28.aegva29.aegva28.a4wva27.a4wyva27.2a3va53.
		bat|24|16|13|12|a14111C,b6F6582,c403854,d2D283D,e5B4D6E,f2C263A,g827495,hDB6E6E,i3F364F,jFFFFFF|idle:0;fly:0,1,2,1
		+.a18.a3.aba16.aba2.acba14.abca2.a2cba12.ab2ca2.ad2cba10.ab2cda3.ad2cba2.a4.2ab2cda5.ad2cb2aea2.aef2cda7.a2dc2a2e2a2ef2da9.3a.aeg2egef2a14.aeh2ehea17.a4ea18.ai2eia19.a2ja2
		+1.2a59./105.a4.a9.7a.aea2.aef6a2.7b2a2e2a2ef6ba.d5cb2aeg2egef5cda.adadadc2aeh2ehefdadada3.a.a.2a2.a4e3a.a.a12.ai2eia19.a2ja21.2a83./81.a4.a17.aea2.aea16.a2e2a2ea12.3a.aeg
		+2egef2a9.a2dc2aeh2ehef2da7.ad2cba.a4efb2cda5.ad2cba2.ai2ei2ab2cda3.ad2cba4.a2ja2.ab2cda2.a2cba6.2a4.ab2ca2.acba14.abca2.aba16.aba3.a18.a27.
		bear|46|26|23|16|a1C1518,bA08061,c422F2C,d815F48,e5B4237,fFFFFFF,g1A1316,hCBB393,i1E1519,jBA9C77,k816B57,l251A18,mE7DFC9,nEFEAD9,o834248|idle:0;walk:1,2,3,4;strike:5
		+106.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9d
		+e6ja7.ae19dce7d2e5ka9.ae19dce6de5la10.a5dc8dc5d2c2e4d2e3ja11.a5dc8ec5d3c7e3a12.a4de10c4dec2e3c4a15.a4de6c3ac4dec3eca19.a3d2ec2e2ca3.a3d2ec2e2ca19.a3d2ec2e2ca3.a3d2ec2e2ca
		+19.a4d2ec2e2ca2.a4d2ec2e2ca18.a5dec3eca2.a5dec3eca18.acmcmcm2cmcma2.acmcmcm2cmcma19.5ac5a4.5ac5a63./106.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17
		+dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.ae19dce6de5la11.ac5dc4dc5dc2ec2e4d2e3ja13.c5dc4e
		+c5dcea2c7e3a14.a4de6c4deca.ae5c2a17.a4de2c3ac4dea2.a4eca19.a3d2eca3.a3d2ea2.a3e2ca19.a3d2eca3.a3d2ea2.a3e2ca19.a4d2eca2.a4d2ea.a4e2ca18.a5deca2.a5dea.a5eca18.acmcmcmca2.a
		+cmcmcma.acmcmcma19.a5ca4.6a3.6a61./60.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g
		+4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.ae19dce6de5la11.a2e11dc5d2c2e4d2e3ja11.a5dc8ec5d3c7e3a12.a5d10c4dec2e3c4a15.a4de6c3ac4dec3eca19.a4dec2e2ca3.a3d2ec
		+3eca19.a3d2ec2e2ca3.a3d2ec2e2ca19.a3d2ec3e2ca2.a4d2ece2ca19.a4d2ec3eca2.a5dec2e2ca18.a5de2cmcma2.acmcmcmc3eca18.acmcmcmc4a4.4a2cmcmcma19.6a14.6a63./106.8a34.4a8b2ac2a25.4
		+a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.
		+ae19dce6de5la8.a5dc12dc4dc2e4d2e3ja9.a5dc12ec5dc7e3a10.a4deca12c4de2c6a13.a4dea.a7c3ac4deca19.a3d2ea2.a3e2ca3.a3d2eca19.a3d2ea2.a3e2ca3.a3d2eca19.a4d2ea.a4e2ca2.a4d2eca18
		+.a5dea.a5eca2.a5deca18.acmcmcma.acmcmcma2.acmcmcmca19.6a3.6a4.a5ca65./60.8a34.4a8b2ac2a25.4a13bc3da22.2a16bcd3ed6a15.a18bcd2e2d6b2a12.a3b17dc2d10ba10.a2b14de3dc3b4d3e3dba
		+9.ab15de2dc2b7dfg4d2a8.a17dedcb8d2g4h2ia7.a17dedc11d4j2ia7.ae17dece9de6ja7.ae19dce7d2e5ka9.ae19dce6de5la10.a5dc13d2ec2e4d2e3ja11.a5dc8ec5d3c7e3a12.a4de10c5dc2e3c4a15.a4de
		+6c3ac4dec3eca19.a3d2ec3eca3.a4dec2e2ca19.a3d2ec2e2ca3.a3d2ec2e2ca19.a4d2ece2ca3.a3d2ec3e2ca18.a5dec2e2ca2.a4d2ec3eca18.acmcmcmc3eca2.a5de2cmcma19.4a2cmcmcma2.acmcmcmc4a25
		+.6a4.6a68./106.8a34.4a8b3a.3a23.4a15bc3da20.2a18bcd3ed6a13.a20bcd2e2d6b2a10.a3b19dc2d10ba8.a2b14de5dc3b4d3e3dba7.ab15de4dc2b7dfg4d2a6.a17de3dcb8d2g4h2ia5.a17de3dc11d4j2ia
		+5.ae17de2dce9dejnjnja6.ae21dce7d2e5oa7.ae15dc5dce6d2e5oa6.a5dc11dc5d2ce5d2ejnjnja6.a5dc11ec4decec2e3d2e4ja7.a4de13c4de2c2a6e3ka8.a4de2a7c3ac3d2e2ca.9a9.a3d2ea.a3e2ca3.a3d
		+2e2ca19.a3d2ea.a4e2ca2.a4d2eca19.a4d2e2a5eca2.a5de2ca18.a5de2acmcmcma2.acmcmcm2ca18.acmcmcma.6a4.a6cma19.6a14.6a64.
		bearBoss|112|92|88|50|a120D10,bDDD5BF,cD1C7AD,d978E7E,e120C10,f493B36,g6B5D53,h322727,i90857C,j231B1D,kBC8B7F,lEFE3AF,mD6AA63,n9F876F,o1A1115,p846B56,q5D4A3E,r231A1C,sE3DBC9,t978E7F,uEFEAD9,v552930,w834248,xE4DCCD|idle:0;walk:1,2,3,4;rear:5;strike:6
		+3533.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h2f7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba
		+3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2d2edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d
		+3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26fh3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa3
		+0.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7fi20fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28
		+fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e
		+66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je51.e2j9f31j9f8je52.j11f30j9fh4j3r53.a11fh29j9fh2j2rhja53.a11fh29j8f2
		+hjr2h2ja54.a9f2h29j8f2hj3h2ja55.a7f2hj6r21jej8f2hj3h2ja55.a7fhj5hja21e2.a7f2hj3h2ja55.a7fhj5hja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6
		+f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a8f2hj3h2ja54.a7f2hj4h2ja22.a9fhj4hja54.a8fhj5hja22.a9fhj4hja54.a9fhj5hja21.a10h6ja54.a10h7ja21.aststststsjststsa55.aststststsjtst
		+stsa23.6a3j6a57.7a2j7a192./3533.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h2f7g3a65.a5.a2bcdgdb2c
		+3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2d2edb2c3d4g15fi3fj2g11
		+fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26fh3fi2fjh14fh10pa30.e2
		+g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7fi20fh7fh14f2j9h6a34.eg
		+28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h2f2hfe44.e2hfh7fh28f
		+21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je51.e5j9f25j9f11jra51.2e2j11f24j9fh7j3rhja
		+52.ej11fh23j9fh5j2r4hja53.j11fh23j8f2h4jr5h2ja54.j9f2h23j8f2h2j2r6h2ja55.a7f2hjr2e20j8f2hjr8h2ja55.a7fhja3.20ej7f2ha.a7h2ja55.a7fhja23.a7f2ha.a7h2ja55.a6f2hja23.a7f2ha.a7
		+h2ja55.a6f2hja23.a7f2ha.a7h2ja55.a6f2hja23.a7f2ha.a7h2ja55.a6f2hja23.a8f2h2a8h2ja54.a7f2hja22.a9fh2a9hja54.a8fhja22.a9fh2a9hja54.a9fhja21.a10h2a10ja54.a10hja21.aststststs
		+a.aststststsa55.aststststsja23.9a3.9a57.a8ja195./3645.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h
		+2f7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2
		+d2edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26
		+fh3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7f
		+i20fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f1
		+7h2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e3j9f8j18h5j9f8je51.ej11f30j9fh7j
		+e52.j11fh29j9fh4j3r53.a11fh29j8f2h2j2r2ja54.a9f2h29j8f2hjr2h2ja55.a7f2h30j8f2hj3h2ja55.a7fhj7r21j2ej7f2hj3h2ja55.a7fhj5hja21e2.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a
		+6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a8f2hj3h2ja54.a7f2hj4h2ja22.a9fhj4hja54.a8fhj5hja22.a9fhj4hja54.a9fhj5hja21.a10h6ja54.a10h7ja21.astst
		+ststsjststsa55.aststststsjtststsa23.6a3j6a57.7a2j7a192./3533.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2b
		+ca.af2h2f7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3
		+ed2b2c2d2edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2
		+g16fi26fh3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.
		+eg7fh7fi20fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh
		+7fh24f17h2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je50.a9f37j9f5
		+je49.a11f36j9fhj3e50.a11fh35j9fhj53.a11fh35j8f2hj54.a9f2h35j8f2hj55.a7f2hj2e7r21j4ej8f2hj55.a7fha3.a6h3r18e5.j7f2hj55.a7fha3.a7hja23.j7f2hj55.a6f2ha3.a6h2ja23.j7f2hj55.a6
		+f2ha3.a6h2ja23.j7f2hj55.a6f2ha3.a6h2ja23.j7f2hj55.a6f2ha3.a6h2ja23.j8f2hj54.a7f2ha2.a7h2ja22.j9fhj54.a8fha2.a8hja22.j9fhj54.a9fha.a9hja21.j10hj54.a10ha.a10ja21.jststststs
		+j55.aststststsa2.aststststsa23.9j57.9a4.9a189./3645.a110.aba108.a2bca102.a3.d2b2cda7.3a90.aba2edb2c2da.a4.a3fa83.a4.a2bcd2g5d.aba2.af3hf7a75.aba.ed2b2c2d3fi2gd2bca.af2h2f
		+7g3a65.a5.a2bcdgdb2c3d5fd2b2cd3a2f12ga55.a7.aba3.a2b2c2dg5d6fdb2c2dj4g11f2ga45.a7.aba5.a2bca2.ab2c3d13f4dj2g16fga43.aba5.a2bca3.d2b2c2d2e5d17fj2g9fk8fga41.a2bca3ed2b2c2d2
		+edb2c3d4g15fi3fj2g11fk4h4fga38.ed2b2c2digdb2c3d3g5d3g11fi9fjg12fklm8f2a35.egdb2c3d3g5d3g14fi15fjg13fk2mf6n2oa33.e3g5d20fi21fj15fk7n3oa32.e2g21fi27fj16f8p2oa31.e2g16fi26fh
		+3fi2fjh14fh10pa30.e2g11fi24fh5fifh6fjh13f2h9pa30.e2g6fi30fi15fjh11f2h9qa31.egfi28fhfi22fjh10fh9oa32.e15fh7fh3fi24fh4fjh8f2h8pa33.e7fh7fh5fi22fh7fh5fj2h6f3h6qa33.eg7fh7fi2
		+0fh7fh14f2j9h6a34.eg28fh7fh24f4j5a40.e21fh7fh28fh5fge44.eg13fh7fh28fh7fh6fe44.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h
		+2f2hfe44.e2hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e3j9f8j18h5j9f8je51.ej11f30j9fh7je5
		+2.j11fh29j9fh4j3r53.a11fh29j8f2h2j2r2ja54.a9f2h29j8f2hjr2h2ja55.a7f2h30j8f2hj3h2ja55.a7fhj7r21j2ej7f2hj3h2ja55.a7fhj5hja21e2.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f
		+2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a7f2hj3h2ja55.a6f2hj4h2ja23.a8f2hj3h2ja54.a7f2hj4h2ja22.a9fhj4hja54.a8fhj5hja22.a9fhj4hja54.a9fhj5hja21.a10h6ja54.a10h7ja21.aststst
		+stsjststsa55.aststststsjtststsa23.6a3j6a57.7a2j7a192./1304.3a108.a3fa106.af3hf7a99.af2h2f7g3a96.2a2f12ga94.a4g11f2ga92.a2g16fga90.a2g9fk8fga88.a2g11fk4h4fga82.a4.ag12fklm
		+8f2a79.aba3.jg13fk2mf6n2oa77.a2bca.aj15fk7n3oa76.a2b2c2dbj16f8p2oa72.a3.ab2c2d2bjh14fhpupupupupa72.aba3.4adbcjh13f2h8va72.a2bca5.2a4jh11f2h8wva71.a2b2cda3.a6fjh10fh9wva71
		+.ab2c2da2.a8fjh8f2h8wva71.2e5d3ej8fhjh7f2hupupupu2pa68.a.e4g6fj8f2hj2h5f2h8pa68.abd3g9fj8fh3j8h5q2a68.a2bcd10fifj7f2hjg5j8a69.a2b2c2d3fi5fh2fj7fhjgea.a73.a4.ab2c3d9fh3fj6
		+fhjfe75.aba2.2e5d14fj7hjie74.a2bcde3g18fjstststsjfge72.a2b2c2d2g16fi2fjsjsjsjsjfge66.a5.db2c3d12fifh7fjfjfjfj3fge64.aba2.2eg5d7fi7fh17fge56.a6.a2bcde4g5fi5fh24fife55.aba4
		+.a2b2c2d2gfi32fh5fe54.a2bca3edb2c3d28fh7fh5fe52.ed2b2c2di2g5d21fh7fh13fe51.egdb2c3d3g18fh7fh21fe50.e3g5d20fifh28fhe49.e2g21fi28fh7fhe48.e2g16fi26fh7fh5fh2fe47.e2g11fi24fh
		+7fh8f2h3f3he46.e2g6fi22fh7fh14f10he46.egfi20fh7fh21f11he46.e15fh7fh23f17he46.e7fh7fh28f19hje45.eg7fh7fi20fh6f19h2je45.eg28fh7fh5f19h3je45.e21fh7fh10f22h2je45.eg13fh7fh15f
		+24h2je46.eg5fh7fh22f22hjh3je46.e6fh28f23h5je47.e27fh5f23h7je47.e19fh7fh2f25h8je47.e11fh7fh6f28h8je48.e2hfh7fh9f29h11je49.e7h11f29h12j2e50.e44h14je52.ej40h16je53.e2j36h18j
		+e55.ej35h18je56.ej32h20je58.ej27h20j4e59.e4j20h21j3e63.e5j13h24j3e66.e7j5h27j3e70.e2j9f24j3e74.j11f19j4e77.a11fh14j4e81.a11fh10j4e86.a9f2h4j4r2e91.a7f2hj4r2ja94.a7fhj5hja
		+95.a7fhj5hja95.a6f2hj4h2ja95.a6f2hj4h2ja95.a6f2hj4h2ja95.a6f2hj4h2ja95.a7f2hj4h2ja94.a8fhj5hja94.a9fhj5hja93.a10h7ja93.aststststsjtststsa95.7a2j7a192./3533.a110.aba108.a2
		+bca102.a3.d2b2cda100.aba2edb2c2da.a5.3a84.a4.a2bcd2g5d.aba3.a3fa82.aba.ed2b2c2d3fi2gd2bca.af3hf7a68.a5.a2bcdgdb2c3d5fd2b2cd2af2h2f7gaxa56.a7.aba3.a2b2c2dg5d6fdb2c2d3a2f8g
		+2x2ga46.a7.aba5.a2bca2.ab2c3d13f5dj4g5f3x3f2ga44.aba5.a2bca3.d2b2c2d2e5d18fj2g4f4x8fga42.a2bca3ed2b2c2d2edb2c3d4g15fi4fj2g3f2x4fk8fga39.ed2b2c2digdb2c3d3g5d3g11fi9fj2g11f
		+k4h4fga37.egdb2c3d3g5d3g14fi15fjg12fklm8f2a34.e3g5d20fi21fjg13fk2mf6n2oa32.e2g21fi27fj15fk7n3oa31.e2g16fi26fh3fi2fj16f8p2oa30.e2g11fi24fh5fifh6fjh14fhpupupupupa30.e2g6fi3
		+0fi10f5jh13f2h8va31.egfi28fhfi14f2j5fjh11f2h8wva31.e15fh7fh3fi19fj8fjh10fh9wva31.e7fh7fh5fi22fhfj10fjh8f2h8wva31.eg7fh7fi20fh7fhfj7f4hjh7f2hupupupu2pa31.eg28fh7fh10fj5h7j
		+2h5f2h8pa32.e21fh7fh19f5j4fh2f2j8h5q2a32.eg13fh7fh28fh7fh4f3j10a34.eg5fh7fh28fh7fh14fe44.e6fh28fh7fh22fe44.e27fh7fh28fhfe44.e19fh7fh28f2h6fhfe44.e11fh7fh24f17h2f2hfe44.e2
		+hfh7fh28f21hf4he44.e7h25fh4f29he44.e66he44.ej63h2je44.e2j61h3je45.ej61h2je46.ej60h2je48.ej54h7je48.e4j50h7je49.e5j37h19je49.e7j5h8j18h22je51.e3j9f47je52.ej11f43j3r54.a11f
		+h40j2rhja54.a11fh39jr2h2ja55.a9f2h37j2r3h2ja56.a7f2hj5r21j7e4r5h2ja56.a7fhj4hja21e8.a7h2ja56.a7fhj4hja29.a7h2ja56.a6f2hj3h2ja29.a7h2ja56.a6f2hj3h2ja29.a7h2ja56.a6f2hj3h2j
		+a29.a7h2ja56.a6f2hj3h2ja29.a8h2ja55.a7f2hj3h2ja28.a9hja55.a8fhj4hja28.a9hja55.a9fhj4hja27.a10ja55.a10h6ja27.aststststsa56.aststststsjststsa29.9a58.6a3j6a192.
		cat|24|17|14|10.5|a211713,bC89961,cD3AB75,dA2744B,e83C66E,f6B4C39,g15111A,hDD909C,iEEDEC0,j926D49,kCEBA9B|idle:0;walk:1,2,3,4
		+13.a5.a6.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.f2bf3i
		+f2b2fa11.a2b3faf2bfja11.a2bfja.a2bfja11.a2ifka.a2ifka12.4a3.4a33./13.a5.a6.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3
		+.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.af2bfif2b3fja11.f2bfaf2bfa2ja11.f2bf.a2b2a2ja11.f2if.a2i2a2ka12.2f3.2a2.2a32./2.2a8.aba3.aba4.abca7.a2b3a2bca2
		+.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.aj5if2bfa12.a2b3faf2bfja11.a2bfja.a2bfja11.a2
		+bfka.a2ifja11.a2ifa3.af2ka12.2a7.2a33./13.a5.a6.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdb
		+f4ia6.a3bd2bd2bd2bf3a7.aj10bja10.a2bf5if2bf11.a2b5faf2bf11.a2b2a2ja.f2bf11.a2i2a2ka.f2if12.2a2.2a3.2f34./2.2a8.aba3.aba4.abca7.a2b3a2bca2.abca8.a2b3c3ba2.aba9.abdbd2bdba2
		+.aba9.abe3be2ba2.abd9afbg3bg2ba3.abf9cf2bh3ba5.fc2bd2bd2bdbf4ia6.a3bd2bd2bd2bf3a7.aj10bja11.f2bf4ikj2fa11.a2b3faf2bfja11.a2bfja.a2bfja11.a2ifja.a2bfka12.af2ka.a2ifa15.2a3
		+.2a35.
		chicken|18|18|15|7.5|a241D22,bC56661,cFAF8F0,d1E1519,eD0AC64,fB5ADB7,gAE874F,h974A50,iDAD4D1|idle:0;walk:1,2,3,4;alt:5
		+8.a2baba12.a4ba12.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a4faea11.a3faea12.7a11.a2ea3ea11.6a24./8.a
		+2baba12.a4ba12.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a3faea12.2afaea14.5a13.2a3ea13.4a25./8.a4ba12
		+.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a5fa12.a3faea12.4aea12.a2e4a12.3a3ea14.3a24./8.a2baba12.a4b
		+a12.a4ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a5faea10.3f3aea10.4a.4a9.a3e2a3ea9.3a2.3a23./8.a4ba12.a4
		+ca5.a5.a3cdcea3.aca2.2af4cega3.a2c2a3cf3cba4.a7cf3caha3.ai3c2i2c3f.a4.ai2c4i3ca7.ai2c2i4ca7.a2i6cia8.a7ia10.a4faea11.a3faea12.ae5a11.4a3ea10.a3e3a12.3a27./73.a16.aca2.4a9
		+.a2c2a4c4a.a3.a9cf2baba2.ai3c2i3cf4ba2.ai2c4i2cf4ca3.ai2c2i2cf3cdcea2.a2i5cf4cega3.a5iaef3cba5.a4faef3caha5.a3f3af2a.a7.a2ea3ea11.6a24.
		cinderBat|24|16|13|12|a1D110F,bC4836F,cB36F51,d7C4D3A,e48302A,f24181C,g755E60,hDFCB78,i322121,jFFFFFF|idle:0;fly:0,1,2,1
		+.a18.a3.aba16.aba2.acba14.abca2.a2cba12.ab2ca2.ad2cba10.ab2cda3.ad2cba2.a4.2ab2cda5.ad2cb2aea2.aef2cda7.a2dc2a2e2a2ef2da9.3a.aeg2egef2a14.aeh2ehea17.a4ea18.ai2eia19.a2ja2
		+1.2a59./105.a4.a9.7a.aea2.aef6a2.7b2a2e2a2ef6ba.d5cb2aeg2egef5cda.adadadc2aeh2ehefdadada3.a.a.2a2.a4e3a.a.a12.ai2eia19.a2ja21.2a83./81.a4.a17.aea2.aea16.a2e2a2ea12.3a.aeg
		+2egef2a9.a2dc2aeh2ehef2da7.ad2cba.a4efb2cda5.ad2cba2.ai2ei2ab2cda3.ad2cba4.a2ja2.ab2cda2.a2cba6.2a4.ab2ca2.acba14.abca2.aba16.aba3.a18.a27.
		cow|34|24|21|14|a1E1B22,bE3D9C1,cBCAE90,dAEA7B4,e38343E,fF6F2EA,g1E1519,hE6A9B0,iD7D1D3,j824C5C,kC4818F,lCA8B98,mEAB5BC,n3A3038|idle:0;walk:1,2,3,4;alt:5
		+22.2a31.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai
		+10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.ae2a3fd7id3f3dia11.a.a3f9d3f2d2ia13.a2fi5d3ad2fid2ida13.a2fidlmla3.a2fid2ida13.a2fidilda3.a2fid2ida13.a2fid2ida3.a2fid2ida13.
		+a3nd3na3.a3nd3na13.a3nd3na3.a3nd3na14.3a.3a5.3a.3a45./22.2a31.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2e
		+fdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.aea.ad3fd3id3fdi3d3ia9.a3.d3f5d3f2d3a3ia13.d2fi3dad2fida2.a2ida13.d2fid
		+a2.a2fia3.a2ida13.d2fid3.a2fia3.a2ida13.d2fid3.a2fia3.a2ida13.d3nd3.a3na3.a3na13.d3nd3.a3na3.a3na14.3d5.3a5.3a43./21.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4
		+fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.aea.a2d8id3f2da1
		+3.a.a3f9d3f2d2ia13.a3f5d3ad2fid3ia13.a2fidlmla3.a2fid2ida13.a2fidilda3.a2fid2ida13.a2fid2ida3.a2fid2ida13.a2fid3na3.a3nd2ida13.a3nd3na3.a3nd3na13.a3n4a5.4a3na14.3a13.3a45
		+./22.2a31.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.ai
		+ai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.ad3f2d10id3fd13.d3fda11d3fd13.a2fia.7d3ad2fid13.a2fia2.amlida3.d2fid13.a2fia3.l2ida3.d2fid13.a2fia3.a2ida3.d2fid13.a3na3.a3
		+na3.d3nd13.a3na3.a3na3.d3nd14.3a5.3a5.3d47./21.a2ba29.abc5a12.13ad3e5f2a8.2a14fd3e6fa6.a4f4e6f2efde4fg3fa4.a4f6e4f4ed5fgf2ha3.ai4f6e5f3ed6f3ha2.aia5f4e7f2efdi3f2hjha2.aia
		+12f2e5fd2i2f4ha2.aia11f4e5fd3i3ka3.aiai10f4e4fi7a4.aia2i10f2e4f2ia10.ae2a3i12f3ia11.ae2a3fd11i3dia11.a.a3f9d3f2d2ia13.a2fi5d3ad3fd2ida13.a2fidlmla3.a2fid2ida13.a2fidilda3
		+.a2fid2ida13.a2fid2ida3.a2fid2ida13.a3nd2ida3.a2fid3na13.a3nd3na3.a3nd3na14.4a3na3.a3n4a19.3a5.3a49./108.15a17.2a15fa15.a4f4e6f2e2fa13.a4f6e4f4e2fa11.ai4f6e5f3e2fa10.aia5
		+f4e7f2e2f3a8.aia12f2e6fd2ba7.aia11f4e4fdbc5a4.aiai10f4e3fd3e5f2a2.aia2i10f2e4fid3e6fa.ae2a3i12f3i2ae4fg3f2ae2a3fd7id3f3did5fgf2ha.a.a3f9d3f2d2id6f3ha3.a2fi5d3ad2fid2id2ai
		+3f2hjha3.a2fidlmla3.a2fid2id2a2i2f4ha3.a2fidilda3.a2fid2ida.a3i3ka4.a2fid2ida3.a2fid2ida2.6a5.a3nd3na3.a3nd3na13.a3nd3na3.a3nd3na14.3a.3a5.3a.3a45.
		crawler|36|18|14|18|a281F2E,b4F3F58,c17121C,d35293E,e8A7696,f695374,gB4A5AD,hC96962,iECAEA2,j493A54,kD2C7B1,l968878,m130E18|idle:0;walk:1,2,3,4;strike:5
		+149.ab3.ab.2c2.2c2.db3.ab13.ab3.dbc2e2c2e2cebc2.db2c10.ababcdbeb2f2e2f2ebfbcdbebec9.abab2ebfb8fbfbdebfbfec8.abcebfb2fbfg4fb2fbdbfhb2fec7.abefbfb2fb6fb2fbdb2fbhifc6.abcj2f
		+bj3fbj3fbj3fbj3fb2fkc5.ab.c2jb14jbd2jfbjlkc5.ab2.cdb14db.2cjbclc6.ab3.ab13cab3.db.c6.ab3.ab15.ab3.ab7.2m3.2m15.2m3.2m77./151.b3.a.2c2.2c2.2cb3.a12.a2.b2.bdc2e2c2ecde2b2.b
		+d2c10.2a.2bc2be2f2e2f2efbebcb3ec8.a2.bc2b2fb8fb2f2bfb2fec7.a2.be2bgfb2fg4fb3f2bfbi2fec6.a.cb2fb3fb6fb3f2bfbfhifc5.a2.cbf2bj3fbj3fbj3f2b2fb3fkc4.a3.bjb16jdbjbfjlkc4.a3.bcb
		+14d2c.bcbjdlc5.a2.b2.bd12cd3.b.bcac5.a3.b.b.a13.a3.b.b.a5.m3.m.m.m13.m3.m.m.m76./113.ab3.ab.2c2.2c2.db3.ab13.ab3.dbc2e2c2e2cebc2.db2c10.ababcdbeb2f2e2f2ebfbcdbebec9.abab2
		+ebfb8fbfbdebfbfec8.abcebfb2fbfg4fb2fbdbfhb2fec7.abefbfb2fb6fb2fbdb2fbhifc6.abcj2fbj3fbj3fbj3fbj3fb2fkc5.ab.c2jb14jbd2jfbjlkc5.ab2.cdb14db.2cjbclc6.ab3.ab13cab3.db.c6.ab3.
		+ab15.ab3.ab7.ab3.ab15.ab3.ab7.2m3.2m15.2m3.2m77./150.a5.b2c2.2c2.cd5.b12.ba2.a2cb2e2c2e2cbec.ac2bc11.2bacd2e2bf2e2f2ebfecdebebc9.ba.b2efbfb6fbfbfdeb2fbec8.bacb2fgbfbfg4fb
		+fbfdbfhibfec7.bdefb2fb2fb4fb2fbfdb3fhbfc6.b.dj2fbjb2fbj3fbj2f2bj4fbfkc5.b.ac4jb11jbjd2j2fjbkc5.b.a.dc2db11dbcacd2jcbc6.ba2.a.cb12cb.a.a2c.b6.b.a.a3.b13.b.a.a3.b5.m.m.m3.m
		+13.m.m.m3.m75./113.ab3.ab.2c2.2c2.db3.ab13.ab3.dbc2e2c2e2cebc2.db2c10.ababcdbeb2f2e2f2ebfbcdbebec9.abab2ebfb8fbfbdebfbfec8.abcebfb2fbfg4fb2fbdbfhb2fec7.abefbfb2fb6fb2fbdb
		+2fbhifc6.abcj2fbj3fbj3fbj3fbj3fb2fkc5.ab.c2jb14jbd2jfbjlkc5.ab2.cdb14db.2cjbclc6.ab3.ab13cab3.db.c6.ab3.ab15.ab3.ab7.ab3.ab15.ab3.ab7.2m3.2m15.2m3.2m77./62.4c3.c27.c4ec.c
		+kc23.abce2fbfecklc13.2c2.2c2.cdbab2fbibfelc11.3c2e2c2e2c2eb.d3bfhbfc10.2c3e2f2e2f2efbe2cjbm2fbfc9.c2e12fbfecdbj2fjbc8.cebfg2fbfg4fgb3feb2c2jclmc6.cebfb2fbfb6fb4fb2.2c.clc
		+6.cjb2fbfb2fb4fb4fbc6.c7.ab4jb13jc14.ab.2cdb12d2c14.ab3.ab13c16.ab3.ab28.2m3.2m100.
		crow|20|18|15|9.5|a0F0F16,b5F5F79,c46465C,d2E2E3F,e1E1E2A,fE2CD81,gA7A7AF,h73737D,i898993|idle:0;fly:0,1,2,1
		+9.2a17.abca15.ab3ca13.ab4ca12.ab4cda11.ab4c2da11.a4c2de2a8.a2.a4de3ba6.aea2.2a2e4bd2a4.a2e4a2d2bf2d2ga4.a2e10dh2ga4.ae10d3a6.a9da10.ae5dea12.2a2i3a15.2a50./111.3a8.a7.a3b
		+a6.a2e4a5ebd2a4.ae2b7cded2ga4.aeb5c2de2dh2ga4.a2e4d2e3d3a6.ad4e4da10.ae5dea12.2a2i3a15.2a70./91.3a8.a7.a3ba6.aea4.2a4bd2a4.a2e2a4e2bf2d2ga4.a3e4de4dh2ga4.ae4c2de3d3a6.eb4
		+c2deda10.eb4cdea12.eb4ce14.ab2cda15.abda17.2a49.
		elephant|64|46|40|26|a1D1B26,bAFB1B9,c4A4A5B,d9598A9,e686979,fAF93A3,gFFFFFF,h1E1519,iA39983,jF1ECDB,k3B3747,lC8BFA4,mD9D3C6,nAEA89F|idle:0;walk:1,2,3,4;strike:5
		+295.7a35.16a4.2a7b2a28.5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.ade
		+cb26dcbd7f2dcd2h7da9.adcb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3
		+j2idia9.ace28dc2e5dec4ei3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea13.a8d14c8dc5ea5.ab4dea13.a
		+7de7c6ac7dec4eca5.ab5ea13.a7dec4eca6.a7dec4eca5.ab3dea14.a6d2ec3e2ca6.a6d2ec3e2ca5.ab3dea14.ab5d2ec3e2ca6.ab5d2ec3e2ca5.ab4ea14.ab5d2ec3e2ca6.ab5d2ec3e2ca6.ab3dea13.ab2de
		+2d2e2c2e2ca6.ab2de2d2e2c2e2ca6.ab3dea13.ab3ded2ecece2ca6.ab3ded2ecece2ca7.ab3ea13.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab3dea12.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab4da12.ab5d2ec3e2ca6.a
		+b5d2ec3e2ca8.a2e2da12.ab5d2ec3e2ca6.ab5d2ec3e2ca9.a2ea13.ab6dec4eca6.ab6dec4eca10.2a14.a8dec4eca5.a8dec4eca25.amdmdm3decn3eca5.amdmdm3decn3eca26.6a3c6a7.6a3c6a278./295.7a
		+35.16a4.2a7b2a28.5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dc
		+bd7f2dcd2h7da9.adcb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia
		+9.ace28dc2e5dec4ei3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea15.a8d10c8d2a8ea3.ab4dea15.a7de3c
		+6ac7de2a7eca3.ab5ea15.a7de2ca6.a7de2a7eca3.ab3dea16.a6d2e2ca6.a6d2e2a6e2ca3.ab3dea16.ab5d2e2ca6.ab5d2e2ad5e2ca3.ab4ea16.ab5d2e2ca6.ab5d2e2ad5e2ca4.ab3dea15.ab2de2d2e2ca6.
		+ab2de2d2e2ad2ec2e2ca4.ab3dea15.ab3ded2e2ca6.ab3ded2e2ad3ece2ca5.ab3ea15.ab5d2e2ca6.ab5d2e2ad5e2ca5.ab3dea14.ab5d2e2ca6.ab5d2e2ad5e2ca5.ab4da14.ab5d2e2ca6.ab5d2e2ad5e2ca6.
		+a2e2da14.ab5d2e2ca6.ab5d2e2ad5e2ca7.a2ea15.ab6de2ca6.ab6de2ad6eca8.2a16.a8de2ca5.a8dec8eca25.amdmdm3de2ca5.amdmdm3decnenen3eca26.2a7c2a7.9a.9a276./231.7a35.16a4.2a7b2a28.
		+5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dcbd7f2dcd2h7da9.ad
		+cb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia9.ace28dc2e5dec4e
		+i3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea17.2a17c8da11.ab4dea13.a8d7c6ac7dec5ea5.ab5ea13.a7
		+dec4eca6.a7dec4eca5.ab3dea14.a7dec3e2ca6.a6d2ec4eca5.ab3dea14.a6d2ec3e2ca6.ab5d2ec3e2ca5.ab4ea14.ab5d2ec3e2ca6.ab5d2ec3e2ca6.ab3dea13.ab5d2e2c2e2ca6.ab2de2d2ec3e2ca6.ab3d
		+ea13.ab2de2d2ecece2ca6.ab3ded2e2c2e2ca7.ab3ea13.ab3ded2ec3e2ca6.ab5d2ecece2ca7.ab3dea12.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab4da12.ab5d2ec3e2ca6.ab5d2ec3e2ca8.a2e2da12.ab5d2ec3e
		+2ca6.ab5d2ec3e2ca9.a2ea13.ab5d2ec4eca6.ab6dec3e2ca10.2a14.ab6dec5eca5.a8dec3eca26.a8decn3eca5.amdmdm3dec4eca25.amdmdm3dec5a7.5a4cen3eca26.9a19.9a278./295.7a35.16a4.2a7b2a
		+28.5a16b4a11b2a23.3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dcbd7f2dcd2h7da9
		+.adcb27dc2d8fdc11da8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia9.ace28dc2e5de
		+c4ei3l3jiji10.c2e28dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea11.a8d18c8dcea7.ab4dea11.a7de11c6ac7de2ca7.ab5e
		+a11.a7de2a7eca6.a7de2ca7.ab3dea12.a6d2e2a6e2ca6.a6d2e2ca7.ab3dea12.ab5d2e2ad5e2ca6.ab5d2e2ca7.ab4ea12.ab5d2e2ad5e2ca6.ab5d2e2ca8.ab3dea11.ab2de2d2e2ad2ec2e2ca6.ab2de2d2e2
		+ca8.ab3dea11.ab3ded2e2ad3ece2ca6.ab3ded2e2ca9.ab3ea11.ab5d2e2ad5e2ca6.ab5d2e2ca9.ab3dea10.ab5d2e2ad5e2ca6.ab5d2e2ca9.ab4da10.ab5d2e2ad5e2ca6.ab5d2e2ca10.a2e2da10.ab5d2e2a
		+d5e2ca6.ab5d2e2ca11.a2ea11.ab6de2ad6eca6.ab6de2ca12.2a12.a8dec8eca5.a8de2ca25.amdmdm3decnenen3eca5.amdmdm3de2ca26.9a.9a7.2a7c2a280./231.7a35.16a4.2a7b2a28.5a16b4a11b2a23.
		+3a23bc14ba15.2a3.2a25b6c9d2ba13.adea.a9b18dc5bc10dba11.adea.a4b23dcb5dbc10dba10.ade2a3b24dcb7dbc10da10.adec2b25dcb2d4f4dcdgh7da9.adecb26dcbd7f2dcd2h7da9.adcb27dc2d8fdc11d
		+a8.adcb7de19dc2d7f2dc11da8.adc8de19dc2d6f2dec5de5da9.ac9de17dece2d5f2dec2d3i6da9.ac9de17dece3d3f2dec2di3j2i3dea8.akce28dce7dec2di2l3j2idia9.ace28dc2e5dec4ei3l3jiji10.c2e2
		+8dc2e3d2ec4a.ai2l4ji11.a2e28dc5ea7.a2i3lia12.a3e25d2e4ca8.abd3iea13.a6e17d6e2a11.ab5ea14.2a25e2a13.ab3dea13.a8d18cac8ea5.ab4dea13.a7de7c6ac8dc4eca5.ab5ea13.a7dec4eca6.a7d
		+ec4eca5.ab3dea14.a6d2ec4eca6.a7dec3e2ca5.ab3dea14.ab5d2ec3e2ca6.a6d2ec3e2ca5.ab4ea14.ab5d2ec3e2ca6.ab5d2ec3e2ca6.ab3dea13.ab2de2d2ec3e2ca6.ab5d2e2c2e2ca6.ab3dea13.ab3ded2
		+e2c2e2ca6.ab2de2d2ecece2ca7.ab3ea13.ab5d2ecece2ca6.ab3ded2ec3e2ca7.ab3dea12.ab5d2ec3e2ca6.ab5d2ec3e2ca7.ab4da12.ab5d2ec3e2ca6.ab5d2ec3e2ca8.a2e2da12.ab5d2ec3e2ca6.ab5d2ec
		+3e2ca9.a2ea13.ab6dec3e2ca6.ab5d2ec4eca10.2a14.a8dec3eca6.ab6dec5eca25.amdmdm3dec4eca5.a8decn3eca26.5a4cen3eca5.amdmdm3dec5a33.9a7.9a284./103.7a55.2a7b2a8.3a41.a11b2a5.ab2
		+da21.16a2.a14ba3.ab3dea15.5a16ba6c9d2ba2.ab2d2ea12.3a22bc5bc10db2ab3dea6.2a3.2a24bcb5dbc10d2bded2ea5.adea.a9b16dcb7dbc14dea5.adea.a4b21dcb2d4f4dcdgh7ded2ea5.ade2a3b23dcbd
		+7f2dcd2h9dea6.adec2b25dc2d8fdc9ded2ea6.adecb26dc2d7f2dc10d2ea7.adcb27dc2d6f2dec2d3ie3d2ea8.adcb7de19dce2d5f2decdi3j2i3ea9.adc8de19dce3d3f2dec2di2l3j2i2a10.ac9de17dedce7de
		+c3di3l3jaja9.ac9de17dedc2e5dec4eaia2l4ja8.akce29dc2e3d2ec4a3.2a3la10.ace30dc5eca9.3a12.c2e30d5ca26.a2e30d3ea28.a3e25d4e2a30.a6e17d6e2a33.2a25e2a37.2a18c8da31.a8d8c6ac7dec
		+4ea26.a7dec5eca6.a7dec3eca26.a7dec4e2ca6.a6d2ec3eca26.a6d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ecec2e2ca6.ab2de2d2ec2e2ca26.ab2de2d2ec2ece2ca6.ab3ded
		+2ec2e2ca26.ab3ded2ec4e2ca6.ab5d2e2ce2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec4e2ca6.ab5d2ec2e2ca26.ab5d2ec5eca6.ab6dec2e2ca26.ab6dec6eca5.a8
		+dec2eca26.a8decen3eca5.amdmdm3dec3eca25.amdmdm3dec6a7.4a5cn3eca26.9a19.9a278.
		emberSlime|26|20|17|13|a382019,bD49D6C,cFFFFFF,dCB8A5D,e986348,f291712,g734738,h412820,iE2CD81|idle:0;hop:1;strike:2
		+113.8a16.2a8b2a13.a3b2c5b2d2a10.a2b3c2b8da8.a2b2cb11dea6.a3b14dea6.ab3dfc6dfc3d2ea4.ab4d2f6d2f3d2ea4.ab17d2ea4.a17d2ega4.a7d6h4d2ega4.ae2d2i12d2ega5.a3e12d2ega7.ag14ega9.
		+16a31./10.6a18.2a6b2a15.a3b2c3b2da13.a2b3cb6da12.ab2cb7dea11.a3b9dea11.ab2dfc4dfc2dea10.ab2d2f4d2f2dea10.ab12dea10.a12d2ea10.a5d4h3d2ea10.a2d2i8d2ea10.ae11dega11.ae9d2ega
		+11.a2e8dega13.a10ea15.a8ga17.8a61./140.8a16.2a8b3a11.2a3b2c5b3d2a8.a3b3cb10d2a5.a3b2cb6dfc5dea3.a3b7dfcd2f5dea3.ab9d2f7d2ea2.ab11d7hd2ea2.ab10dhchchc2hdega2.a11d8hdega2.a
		+e2d2i7dhchchc2dega3.a2e16d2ega4.ag17ega6.19a28.
		fish|18|10|8|9|a1B2638,b364D6A,c80AED4,d6799C6,e4A6D90,fFFFFFF,g15111A,hDBC36E,iD8E8F8|idle:0;fly:0,1
		+20.a4.5a7.aba.2a5c2a5.a2ba2c6dc2a3.aeb8dfgdca2.aeb2d2h7dea2.a2bae7ie2a3.aba.2a5e2a6.a4.5a24./25.5a9.a.2a5c2a6.aba2c6dc2a3.abe8dfgdca2.abe2d2h7dea3.abae7ie2a5.a.2a5e2a11.5
		+a24.
		frog|20|13|10|10|a182F22,bFFFFFF,c15111A,d66A85D,e87BC72,f335737,g477A48,hDDE4AE,i32583B|idle:0;hop:1
		+46.2a4.2a11.a2ba2.a2ba9.abcbd2adbcba8.a4d2e4da7.a12da6.ad10fda6.agd8hdga6.a2gda4had2ga6.a2ia.4a.a2ia7.2a8.2a24./8.2a4.2a11.a2ba2.a2ba9.abcbd2adbcba6.2ae3d2e5da5.ae13da3.a
		+g4d8fda3.ag2dagd6hdga4.a2da.agd4a2da5.aia3.aia3.aia6.a5.a5.a65.
		giraffe|40|62|58|12|a231912,b644A34,c38291E,dCFB474,eD9C286,f6D5942,g957F56,h15111A,iFFFFFF,jECDEB5,k473126,l97704A,m7B5A3B,n392C24|idle:0;walk:1,2,3,4;alt:5
		+22.a.a36.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2d
		+ga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.
		+afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.a2cfdldf5gfdld2fga20.3adld4f2afdldfmga22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a
		+2dgfgfa22.adlgfmfa2.adlgfmfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a2dgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aed
		+gfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.a3nf2na2.a3nf2n
		+a22.a3nf2na2.a3nf2na23.6a4.6a100./22.a.a36.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.
		+aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.
		+2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.a2c3fdldfgfdldf2gfgmga18.2a.afdldfafdld
		+f3agmga21.af2dga.a2dga2.a2gfa21.af2dga.a2dga2.a2gfa21.afdlga.adlga2.agmfa21.af2dga.a2dga2.a2gfa21.af2dga.a2dga2.a2gfa21.af2dga.a2dga2.a2gfa21.afedga.aedga2.adgfa21.afedga
		+.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.
		+afedga.aedga2.adgfa21.afedga.aedga2.adgfa21.af3na.a3na2.a3na21.af3na.a3na2.a3na22.a2fa3.3a4.3a98./21.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d
		+4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga3
		+3.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dg
		+a19.acf2gd11jdga20.a2cfa8gfdldfa22.3adld4f2afdldfmga22.adldfgfa2.a2dgfmga22.a2dgfgfa2.a2dgfgfa22.a2dgfmfa2.adlgfgfa22.adlgfgfa2.a2dgfmfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.
		+a2dgfgfa22.a2dgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.ae
		+dgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgf2na2.a3nfgfa22.a3nf2na2.a3nf2na22.a3nf2a4.2af3na23.3a10.3a100./22.a.a36.ababa35.acac2a33.a2d4
		+e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga
		+33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da
		+19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.afdldf9gfdlda21.fdldf2a5fa2fdlda21.a2dga2.a2gfa.af2dga21.a2dga2.a2gfa.af2dga21.adlga2.agmfa.afdlga21.a2
		+dga2.a2gfa.af2dga21.a2dga2.a2gfa.af2dga21.a2dga2.a2gfa.af2dga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedg
		+a21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.aedga2.adgfa.afedga21.a3na2.a3na.af3na21.a3na2.a3na.af3n
		+a22.3a4.3a3.a2fa101./21.ababa35.acac2a33.a2d4e2a30.a7d2e2a28.fg3dhi4dja26.aefg7djka26.aedfg4d4ja26.aedlf4g3ja26.ae3dgf6a27.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32
		+.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.ae3dga33.ael2dga33.ae3dga33.ae3dga33.aed2lga33.aed2lga32.fe3dga28.5afel2dgf24.4a5efe3dgf20.a.2a4e2d2l2d5fa19.adf
		+2ed2l3d2l7da19.afe3d2l6d2l4da19.af7d2l3d2l4da19.af2d2l3d2l7dlda19.afgd2l7d2l5da19.afg10d2l4dga19.acf2gd11jdga20.a2cfdldf10gfga20.3adld4f2afdldfmga22.a2dgfmga2.adldfgfa22.
		+a2dgfgfa2.a2dgfgfa22.adlgfgfa2.a2dgfmfa22.a2dgfmfa2.adlgfgfa22.a2dgfgfa2.a2dgfgfa22.a2dgfgfa2.a2dgfgfa22.aedgfgfa2.a2dgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.ae
		+dgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.a3nf
		+gfa2.aedgf2na22.a3nf2na2.a3nf2na23.2af3na2.a3nf2a27.3a4.3a103./1094.6a29.5a6ea24.4a5e2d2l2d6a15.a.2a4e2d2l3d2l2dfe3dga13.adf2ed2l3d2l7dfed2lga13.afe3d2l6d2l3dfed2lga14.af
		+7d2l3d2l2dfe3dga15.af2d2l3d2l7dfel2dga15.afgd2l7d2l3dfe3dga15.afg10d2l2dfe3dg2a.a13.acf2gd10jfed2lg2ababa12.a2cfdldf5gfdlfed2lg2acac2a12.3adld4f2afdld4f2a2d4e2a12.a2dgfgf
		+a2.a2dgfgf2a7d2e2a10.a2dgfgfa2.a2dgfgf2ag3dhi4dja9.adlgfmfa2.adlgfmfa.ag7djka9.a2dgfgfa2.a2dgfgfa2.ag4d4ja9.a2dgfgfa2.a2dgfgfa3.a4g3ja10.a2dgfgfa2.a2dgfgfa4.7a11.aedgfgfa
		+2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.
		+aedgfgfa22.aedgfgfa2.aedgfgfa22.aedgfgfa2.aedgfgfa22.a3nf2na2.a3nf2na22.a3nf2na2.a3nf2na23.6a4.6a100.
		golem|48|50|45|20|a16141A,b62824B,c839D65,d9C988F,e455C38,f7D7973,g3D3B40,h242227,i2E2C30,j565454,k86DFDA,lE5FAF8,m6DC3BD,nC4F4EE,o252326,p88837B,q5D5A56|idle:0;walk:1,2,3,4;windup:5;strike:6;throw:7
		+832.5a40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja2
		+0.a9fhj3f2jgj2f5ija20.a5fi4fhj4hfg7ja21.a6fi4fh3dhfm5g2a22.aj9fhd3fjh2nmfja24.aj9fh4fjhmnf2ja24.aj9fh4fjh2f3ja24.a2j8f7hf4ja25.a2j7fh5dh3jga26.a3j5fhd5fdhj2ga27.a7jh6fjh2
		+ga29.a4j2gh5fijh2a31.6gh6fjh33.a2fi2fhj4fijh33.a5fjh5jha33.aj4f2j5hga33.ad5fjg4jga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./832.5a40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbd
		+a32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fhj3f2jgj2f5ija20.a5fi4fh2j3hfg7ja21.a6fi4f2h3
		+dhm5g2a22.aj10fhd3fjhnmfja24.aj10fh4fjhnf2ja24.aj10fh4fjhf3ja24.a2j9fhj5h4ja25.a2j9fh5dhjga26.a3j7fhd5fdhga27.a9jh6fjha29.a4j3gjh5fijh31.a7gh6fja33.g2fi2fhj4fija33.a5fjh5
		+ja34.aj4f2j3h2a35.ad5fj2ga37.a6fj2ga37.a7fj2ga37.2a6g2a168./880.5a40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4d
		+hgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fhj3f2jgj2f5ija20.a5fi4fhj4hfg7ja21.a6fi4fh3dhfm5g2a22.aj9fhd3fjh2nmfja24.aj9fh4fjhmnf2ja24.aj9fh4fjh2f3ja
		+24.a2j8f7hf4ja25.a2j7fh5dh3jga26.a3j5fhd5fdhj2ga27.a7jh6fjh2ga29.a4j2gh5fijh2a31.6gh6fjh33.a5fhj4fijh33.aj4fjh5jha33.ad5fj5hga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./832.5a
		+40.3a2b2cb2a36.2a2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fh
		+j3f2jgj2f5ija20.a5fi4f4hjhfg7ja21.a6fi3fh3dh2fm5g2a22.aj8fhd3fjhm2nmfja24.aj8fh4fjhfmnf2ja24.aj8fh4fjh3f3ja24.a2j7f5hjh2f4ja25.a2j5fh5dh2f3jga26.a3j3fhd5fdh3j2ga27.a5jh6f
		+jhj3ga28.ag4jh5fijh4g29.af4gh6fjh3ga29.a2fi2fhj4fijh2jga29.a5fjh5jh2j2ga29.aj4f2jha3h3j2ga29.ad5fja.af5jga29.a6fja.a6jga29.a7fj2a7jga29.8a2.8a164./880.5a40.3a2b2cb2a36.2a
		+2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad9f4h2fgd5fda21.a2d5fi2fh4dhgd7fda20.ad7fihd4fdg7ifja20.ad8fh5fjg6fklja20.a9fh5fjg8fja20.a9fhj3f2jgj2f5ija20.a
		+5fi4fhj4hfg7ja21.a6fi4fh3dhfm5g2a22.aj9fhd3fjh2nmfja24.aj9fh4fjhmnf2ja24.aj9fh4fjh2f3ja24.a2j8f7hf4ja25.a2j7fh5dh3jga26.a3j5fhd5fdhj2ga27.a7jh6fjh2ga29.a4j2gh5fijh2a31.6g
		+h6fjh33.a5fhj4fijh33.aj4fjh5jha33.ad5fj5hga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./160.5a42.a5fa40.af4j3h2a37.a4jh5da36.a3jhd5fda35.a3jh6fja35.ag2jh5fija36.a2gh6fja37.3hj4f
		+ija36.af2jh5ja37.a4j5h38.a3jhd3fja37.ag2jh4fja37.a3gh4fja35.a2g2bchj2f2ja33.2a2b2c2b2h3jh33.ad2beb2dhdf3hda31.a4d4fh5fjh.5a24.a2d7fh5fjhg5da23.ad8fhj3f2jgd5fda21.a2d5fi3f
		+h4jgd7fda20.ad7fi3f4hg7ifja20.ad8fi6fg6fklja20.a16fg8fja20.a16fgj2f5ija20.a5fi11fg7ja21.a6fi10fm5g2a22.aj15fm2nmfja24.aj16fmnf2ja24.aj18f3ja24.a2j16f4ja25.a2j14f3jga26.a3
		+j11f4j2ga27.a15j3ga29.a4j3g5j3g2a31.15g33.a6fjg4jga33.a2fi3fjgo3jga33.a5f2jg3j2ga33.aj4f2jg3j2ga33.ad5fjg4jga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166./928.5a40.3a2b2cb2a36.2a
		+2b2c2b2c2ba34.ad2beb3d2bcbda32.a4d7f4da.5a24.a2d14fdg5da23.ad15fgd5fda21.a2d5fi6f2hgd7fda20.ad7fi4fh2dg7ifja20.ad8fi2fhd2fg6fklja20.a12fh3fg8fja20.a12fh3fgj2f5ija20.a5fi6
		+fhj3fg7ja21.a6fi6fh3jh6ga22.aj13f4h4fja23.aj16fh4fjh23.aj16fhj2f2jha22.a2j16fh3j4h2a20.a2j14f2j4h5da19.a3j11f4j2ghd5fda19.a15j4gh6fja20.a4j3g5j5gjh5fija21.a13g2a2gh6fja22
		+.aj4f2jgj2ga2.2ahj4fija22.ad5fjg2jga5.a5ja23.a6fjg2jga2.p3.2ap2a3.p20.a7fjg2jga2.p3.p.p3.p22.4a4g4a167./832.5a40.3a2b2cb2a17.4a15.2a2b2c2b2c2ba15.a4pa13.ad2beb3d2bcbda13.
		+a5pqa11.a4d7f4da.5a6.a4p2qa10.a2d14fdg5da6.a4qa11.ad15fgd5fda6.4a11.a2d5fi8fgd7fda20.ad7fi5f2hg7ifjg3a17.ad8fi3fh2dg6fkljg3da16.a12fhd2fg8fjg3fda15.a12fh3fgj2f5ijg3fja15.
		+a5fi6fh4fg7jg3fija15.a6fi5fhj3fj7g5fja15.aj12fh4jhj2fjhj4fija15.aj13f4hnh3j2a5ja16.aj18fj3h2.5a17.a2j16f4ja25.a2j14f3jga26.a3j11f4j2ga27.a15j3ga29.a4j3g5j3g2a31.15g33.a2f
		+i3fjgo3jga33.a5f2jg3j2ga33.aj4f2jg3j2ga33.ad5fjg4jga33.a6fjg4jga33.a7fjg4jga33.6a2g6a166.
		grizzly|50|28|25|18|a181114,bB3A593,c8F755A,d372727,e694F3C,f4B372F,gFFFFFF,h1A1316,iC2AB8D,j1E1519,kAC916F,l786352,m1F1515,nE7DFC9,oEFEAD9,p834248|idle:0;walk:1,2,3,4;strike:5
		+117.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7
		+.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma10.a5ed11ed5edfd2f4e2f3ka11.a5ed11fd5e2dfd7f3a12.a4ef13d4efd3f3d4a15.a4ef7d5ad4efd4fda19.a3e2fd3f2da5.a3e2fd3
		+f2da19.a3e2fd3f2da5.a3e2fd3f2da19.a4e2fd3f2da4.a4e2fd3f2da18.a5efd4fda4.a5efd4fda18.adndndndndndna4.adndndndndndna19.12a6.12a67./117.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.
		+2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e
		+2f5la9.af23edf6ef5ma11.ad5ed7ed5ed3fd2f4e2f3ka13.d5ed7fd5edf3ad7f3a14.a4ef9d4efda2.af5d2a17.a4ef3d5ad4efa3.a4fda19.a3e2f2da5.a3e2fa3.a3f2da19.a3e2f2da5.a3e2fa3.a3f2da19.a
		+4e2f2da4.a4e2fa2.a4f2da18.a5ef2da4.a5efa2.a5fda18.adndndndna4.adndndna2.adndndna19.2a4d2a6.6a4.6a65./67.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a1
		+4.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma11.a2f14e
		+d5edfd2f4e2f3ka11.a5ed11fd5e2dfd7f3a12.a5e13d4efd3f3d4a15.a4ef7d5ad4efd4fda19.a4efd3f2da5.a3e2fd4fda19.a3e2fd3f2da5.a3e2fd3f2da19.a3e2fd4f2da4.a4e2fd2f2da19.a4e2fd4fda4.a
		+5efd3f2da18.a5efdndndna4.adndndnd4fda18.adndndnd5a6.5a2dndndna19.6a18.6a67./117.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c
		+17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma8.a5ed15ed5ed2f4e2f3ka9.a5ed15fd5
		+e2d7f3a10.a4efda15d4ef3d6a13.a4efa.2a7d5ad4ef2da19.a3e2fa3.a3f2da5.a3e2f2da19.a3e2fa3.a3f2da5.a3e2f2da19.a4e2fa2.a4f2da4.a4e2f2da18.a5efa2.a5fda4.a5ef2da18.adndndna2.adnd
		+ndna4.adndndndna19.6a4.6a6.2a4d2a69./67.8a39.3a8b2a34.3a13b2a28.4a3c14b2da24.2a8c10b2cd3ea21.2a21cde3fe6a14.a4c19ede2f2e6c2a11.a3c17ef4ed2e10ca10.a2c18ef3ed3c4e3f3eca9.ac
		+20efed2c7egh4e2a8.a21efedc8e2h4i2ja7.a22efd11e4k2ja7.af22edf9ef6ka7.af23edf7e2f5la9.af23edf6ef5ma10.a5ed16e3fd2f4e2f3ka11.a5ed11fd5e2dfd7f3a12.a4ef13d5ed3f3d4a15.a4ef7d5a
		+d4efd4fda19.a3e2fd4fda5.a4efd3f2da19.a3e2fd3f2da5.a3e2fd3f2da19.a4e2fd2f2da5.a3e2fd4f2da18.a5efd3f2da4.a4e2fd4fda18.adndndnd4fda4.a5efdndndna19.5a2dndndna4.adndndnd5a26.6
		+a6.6a73./117.8a39.3a8b2a34.3a13b2a28.4a3c14bc4a22.2a8c10b4cd3ea19.2a23cde3fe6a12.a4c21ede2f2e6c2a9.a3c17ef6ed2e10ca8.a2c18ef5ed3c4e3f3eca7.ac20ef3ed2c7egh4e2a6.a21ef3edc8
		+e2h4i2ja5.a22ef2ed11e4k2ja5.af24edf9efkokoka6.af25edf7e2f5pa7.af18ed5e2df6e2f5pa6.a5ed14ed5edfdf5e2fkokoka6.a5ed14fd4efd2fd2f3e2f4ka7.a4ef16d4efdfd2a6f3la8.a4ef3a7d5ad3e2
		+fdfda.9a9.a3e2fa2.a3f2da5.a3e2f3da19.a3e2fa2.a4f2da4.a4e2f2da19.a4e2fa.a5fda4.a5ef3da18.a5efa.adndndna4.adndndndfda18.adndndna2.6a6.2a4dndna19.6a18.6a68.
		imp|34|34|31|13.5|a17191E,b381E1E,c251414,dC4826C,eB76659,f5A3834,g804A43,h1A1418,iD9C769,j381E26,kE7E2C9,l7D5C57,m562D2F,n3C2128,o2B1A23,p2A242C,q6F4F58,r472428,s321A20,t23141A,u494048,v3A3238,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6;shoot:5
		+12.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.
		+al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.aqor2oso21.aegp2a6tsta20.3a.aq2rst2sta24.aq2r
		+st2sta25.a2rst2sta25.a2rst2sta25.ar2sts2ta25.aeg2agfa26.aeg2agfa25.a4ut3va24.a4upt2vwa24.4at4a50./12.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih
		+2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.ae
		+ga.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.aqor2oso21.aegp2a6tsta20.3a.a2q2rststa25.aq2rs2ta27.a2r2sta27.tq2rst28.at2rsa28.atega29.ateg2a28.at4ua27.at3upa28.a3t
		+a52./46.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3de
		+fa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.tqor2osota19.aegp2a6tsta20.3a.aq2rstrsta
		+25.a2rstr2sta24.a2rs2a2sta24.ar2s2agfta24.aega.agfa25.aeg2a3va24.a4ut3vwa23.a4upt3a25.5a54./12.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.
		+a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n
		+3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2a.aqor2oso21.aegp2a6tsta20.3a.aq2rstr2sta22.aq2rs2ar2sta22.a2r2sa.a2s2ta20.aq2rsa2.ar2sta20.a2rsa4.a2sta20.aega5.agfa21.aega5
		+.agf2a20.a3ua4.a4va19.a3upa3.a3vwa20.4a5.4a48./46.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2
		+a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga12.a.an4m4f.5ag2a12.ap2a2n4m2na6.a13.aega.a2n3mnoa19.aega2.onomnmoa19.aega2.a3on3oa19.a2e2
		+a.tqor2osota19.aegp2a6tsta20.3a.a2qrst2sta25.aq2rststa26.a2rststa26.aegs3ta26.aegtgfa26.a3utgfa26.a3upt2va26.2a2t3vwa28.5a50./11.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac
		+4d4ea23.ac3e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na22.2an5m2na2
		+2.apo2n4m2na21.aeg2a2n3mnoa20.aega.anomnmoa20.aega2.3on4o20.a2e2a.aor2osoa21.aegp2a6tsta20.3a.aq2rst2sta24.aq2rststa26.a2rs3ta26.a2rs2ta27.ar2sta28.aegta29.aegta28.a4uta2
		+7.a4upta27.2a3ta53./48.a7.a24.aba5.aba23.a2b5a2ba23.acb6dba23.ac4d4ea23.ac3e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a
		+2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa14.a2.an3mf3no2e2d3f13.apa.a2n3m3f2g3edfga11.aega2.a2n3mnofa2g2e2ga10.aega2.aonomnmoa2.2agaga10.aega2.aq3on3oa4.a.a11.a2e2a.tqror2
		+otoa19.aegp2a6tsta20.3a2.aq2rs2ta27.a2r2sta27.tq2rst28.at2rsa28.atega29.ateg2a28.at4ua27.at3upa28.a3ta52.
		mimic|22|22|18|11|a291F18,bC5A374,cA9895F,d856A46,e898D96,fD3BD68,gECE0A2,h685137,iD9C769,j15111A,kFFFFFF,l462026,m70333B,nD17985|idle:0;hop:1,2;strike:3
		+202.14a7.a14ba6.a14ca6.a14da6.a6e2f6ea6.a6cfg6ca6.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48./92.14a7.a14ba6.a2cij6cij2ca6.a14da6.aka2ka2ka2ka2k2a6.al12mla6.al4m5n3mla6.al4m5n
		+3mla6.2ak2ak2ak2ak2aka6.a6e2f6ea6.a6cfg6ca6.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48./48.14a7.a14ba6.a2cij6cij2ca6.a14da6.aka2ka2ka2ka2k2a6.al12mla6.al12mla6.al12mla6.al4m5n
		+3mla6.al4m5n3mla6.2ak2ak2ak2ak2aka6.a6e2f6ea6.a6cfg6ca6.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48./114.14a7.a14ba6.a2cij6cij2ca6.a14da6.aka2ka2ka2ka2k2a6.al12m2a6.al11ma2na5.
		+2ak2ak2ak2ak2a3na4.a6e2f5ea2na4.a6cfg6c2a5.a14ca6.acd10cdca6.a14ca6.a14ha7.14a48.
		pig|30|18|16|11.5|a38202A,bE29DA7,cF2C4BD,d9C5D74,eC47C8E,f1E1519,gFFFFFF,hF0B4B4,i83495D,j5A3644|idle:0;walk:1,2,3,4;alt:5
		+48.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10bed2e4b2d2a6.d3bd3e
		+d3b3d5e2a8.a3b5d3b2ded4a10.a2be5d2bededa14.a2beded2a2bededa14.a3jd2j2a3jd2ja15.6a2.6a11./48.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae
		+11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10bed2e4b2d2a6.aed3bd3bd2e2d5e2a9.2d3bd3b4de3d2a11.ad2bed2bed3a2eda13.ad2bed2bea2.a2eda13.ad3jd3ja2.a3
		+ja14.a2da.3a4.3a9./18.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10
		+bed2e4b2d2a6.a7ed3b3d5e2a8.a3b5d3b2ded4a10.a3b5d2bed2ea14.a2beded2a2bededa14.a2bed2j2a3jdeda14.a3jd2a2.2ad3ja15.3a8.3a11./48.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2
		+c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2ae11bde5bd2hiha4.a2e10bed2e4b2d2a4.a3bd7ed3bd5e2a6.a3b9d3b6a8.a2bed2a6d2bea13.a2bea2.a2e3
		+d2bea13.a3ja2.a3j2d3ja14.3a4.3a.a2da12./18.2a17.9a.a2ba14.2a9cdbe2b3a10.a11cdbeb4ca7.2a2c10bd8ca5.aea11bd2c3bfg2b3a2.aeae11bdc4b2f2b3ha.ae2a11bd8b2hiha2.a2e11bde7b4ha3.2a
		+e11bde5bd2hiha4.a2e10bed2e4b2d2a6.d3bd8e2d5e2a8.a3b5d3b2ded4a10.a2be5d3bdeda14.a2beded2a2bededa14.a3jded2a2bed2ja15.2ad3j2a3jd2a19.3a2.3a14./67.9a19.2a9c2a16.a13ca13.2a2c
		+13bda10.aea14bd2ba8.aeae13bdbe2b3a5.ae2a13bdbeb4ca5.a2e13bd8ca5.2ae11bd2c3bfg2b3a4.a2e10bdc4b2f2b3ha4.d3bd3ed3bd8b2hiha4.a3b5d3bde7b4ha4.a2be5d2be2de5bd2hiha4.a2beded2a2b
		+eded2e4b2d2a5.a3jd2j2a3jd2jd5e2a8.6a2.6a.5a5.
		pirate|32|38|33|16|a7D6153,bAF7B72,c9A605D,d15131A,e704546,f503236,g18151D,h14121A,iB59378,jA17962,k825F4E,lE5DCC5,m676162,nDFD8C5,oB1756A,p4C2A2E,q99524E,r6C3A3B,s969189,t392C24,u8F7E68,v352B2C,w8C7245,x675545,yC5A766,zE6EAF0,AA6AEBB,B4A3C35,CCCAB8E,D2A2124,E645A52,F221A21,G1C1620,HE6EBF5|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7
		+109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh23.h6jh24.h5kh24.hl3mknm23.hopoqrpqrp22.hlm2nsm2sm22.hqp
		+2qrp2rp22.hnmn2sm2sm22.hrpoqrpr2p22.hsmlnsms2m22.hrp2qrpt2p23.3mij3mh22.hu2v2pwdv23.hu2xdyzAd23.hu2xBdzAd24.huxBdAzd24.huxBvdzAd23.h2xBvdAzd23.hCijvjdAd23.hCijvjkd23.hD2E
		+FvDGh23.h4DFvFGh23.3h2v3h108./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh23.h6jh24.h5kh24.h3m2knmh2
		+2.hpoqrp2qrph21.m2n2smn2smh20.hoq2rp2q2rph20.hlnsm3n2smh20.p2qrp3qr2ph20.mijm4ns2mh21.2pwdty2t2ph21.dyzAd4mkh21.hdzAd4vh22.hdAzdB2vh24.hdzAdvh26.dAzdBv25.hvdAdBh25.hxvdxB
		+h25.hivCijh25.hivCijh25.hFvD2EFh24.hFv3DFh25.2h2v2h109./141.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh
		+23.h6jh24.h5kh24.hl3mknm23.hopoqrpqrp22.hlm2nsm2sm22.hqp2qrp2rp22.hnmn2sm2sm22.hrpoqrpr2p22.hsmlnsms2m22.hrp2qrpt2p22.h3mij3mh22.hu2v2pwdv23.hu2xdyzAdh23.huxBdzAdh23.huxB
		+dAzdh23.h2xBvdzAd23.hCijvdAzd23.hCijvDdAd22.hD2EFv2Fdh22.h4DFv2h24.5h111./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5i
		+h19.d.h9ih22.h7ijh23.h6jh24.h5kh24.hl3mknh23.hopoqrpqrh22.hlm2n2smsh22.h2qpqrorph22.h3nml2nsm22.hr3qpoqrp22.hs4nmijm22.hr3tyt2pwd22.6mdyzAd20.hu6vdzAd20.hu2xBv2BdAzd19.hu
		+2xBvx2BvdzAd18.hux2B2hxBvdAzd17.hu2xBh.hx2BvdAd17.huxBh3.hxBvhd18.hCijh3.hijkh19.hCijh3.hijkh19.hD2EFh2.hF2DGh18.h3DFh2.h3FGh19.4h4.4h106./141.6a25.a4b2ca22.da2b6ca20.d2e
		+8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijh23.h6jh24.h5kh24.hl3mknm23.hopoqrpqrp22.hlm2nsm2sm22.hqp2qrp2rp22.hnmn2sm2sm22.hrpoqrpr
		+2p22.hsmlnsms2m22.hrp2qrpt2p22.h3mij3mh22.hu2v2pwdv23.h2uxdyzAd24.hu2xdzAd25.huxdAzd25.huxBdzAd24.hCijdAzd23.hD2EFvdAd23.h3DFvGd25.h3v2FGh26.5h108./108.6a25.a4b2ca22.da2b
		+6ca20.d2e8cea18.defe4c2ge2ah16.2defae3ce2a2gih15.dzaef2a3ea2i2gih15.dAzaeai3aj5ih16.dAza.h9ih17.dAz2dh7ijh18.dAz2mh6jh20.dpijp5kh21.hlnsml3knm20.hoq2rp5qrp19.hn2sm5n2sm19
		+.h2qrp5q2rp20.2hm6n2sm22.hr5qr2p22.hs5ns2m22.hr3ty2t2p23.h7mv23.hu6vh23.hu2xBvBvh23.hu2xB2vh25.huxB2vh25.vuxBvh26.v2xBv27.vCijv27.vCijv26.hD2EFvh25.h4DFv26.h4v111./142.6a
		+25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah17.defae3ce2a2gih17.def2a3ea2i2gih18.deai3aj5ih19.d.h9ih22.h7ijk3H20.h6jh4.3H16.h5k2h8.2H13.h2l3mnm3.d7.H11.h2opoqr3ph2p8d11.h
		+lnm2ns2l2nijm7z11.h3qp2r2q2r2jp7A11.h4n5mh2m8d11.hr5qr2p2.d19.hs5ns2m22.hr3ty2t2p22.h8mh22.hu7v24.hu2xBvh26.vux2Bv25.hvu2xBh25.hxvuxBh25.hivCijh25.hivCijh25.hFvD2EFh24.hF
		+v3DFh25.2h2v2h109./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c2ge2ah2.2d13.defae3ce2a2gih.dzAd12.def2a3ea2i2gihdzAd14.deai3aj5idzAd16.d.h8idzAd20.h6i2pyd22.h4jmijmd22.hk
		+3poqrp22.hlmlnsnsh22.h2op2qr3p22.hl2nm2smsm22.h4q2p2rp22.h6n2sm22.hr5qr2p22.hs5ns2m22.hr3ty2t2p23.8mh22.hu7v23.hu2xBvBvh23.hu2xBvBvh24.huxBvBvh24.huxBvBvh24.h2xBvBvh24.hC
		+ijvjkh24.hCijvjkh23.hD2EFvDGh23.h4DFvFGh23.3h2v3h108.
		pirateCaptain|32|38|33|16|a15131A,b666162,c2C2C38,dB4A071,e7D6153,f14121A,g483429,hA17962,iB59378,j0B0B12,k291E20,l825F4E,mA96D65,n46262C,o8D4747,p633337,q442B30,r855151,s5F3A3E,t1F1D2A,u696465,v8C7245,w2F2F3D,xC5A766,yE6EAF0,zA6AEBB,A252430,B1E1A20,C5C554F,D1A161F,E18141E,FA0716A,GE6EBF5|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7
		+13.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.fm3nl2e23.fmnmo
		+pnopn22.fmn2opn2pn22.fon2opn2pn22.fono2pn2pn22.fpnmopnp2n22.fpnmopnp2n22.npn2opn2qn21.ar3nihnrsq21.atu2t2nvasa21.atu2waxyz2a21.atu2wAayz2a21.artuwAazya22.astuwAtayza22.at
		+2wAtazya23.fuwAtAaza23.fuwAtAta23.fB2CDtBEf23.f4BDtDEf23.3f2t3f108./13.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi
		+2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.f3n2l2ef22.fnmopn2opnf21.n2o2pno2pnf20.fmo2pn2o2pnf20.fmopn3o2pnf20.n2opn3op2nf20.nihn4op2nf21.2nva2o3qnf20.2axyzaqFr
		+sqf20.atayzaq2rsq21.atazyaq2rsa21.artayzarsqa21.arsazya2qa22.as2tazaAf24.atwtawAf25.fwtuwAf25.fwtuwAf25.fDtB2CDf24.fDt3BDf25.2f2t2f109./45.5a25.2a5b2a21.2a2b6cba.a17.ada1
		+0cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.fm3nl2e23.fmnmopnopn22.fmn2opn2pn22.fon2opn2pn22.
		+fono2pn2pn22.fpnmopnp2n22.fpnmopnp2n22.npn2opn2qn21.at3nihnrsq21.atu2t2nvasa21.atu2waxyzaq21.artuwAayzaq21.artuwAazyaf21.ast2wAtayza22.atuwAtazya23.fuwAtBaza22.fB2CDt2Daf
		+22.f4BDt2f24.5f111./13.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2
		+ka23.fm3nl2e23.fmnmopnopf22.fmn2o2pnpf22.f2onopmpnf22.f3onm2opn22.fp3onmopn22.fp4onihn22.n2p3oq2nva20.ar4nqFaxyza19.atu3tq2rayza19.atu2wAq2razya19.tu2wAtqrsqayza18.tuw2A2
		+f3qazya17.fu2wAf.fw2Ataza17.fuwAf3.fwAtfa18.fuwAf3.fwAtf19.fuwAf3.fwAtf19.fB2CDf2.fD2BEf18.f3BDf2.f3DEf19.4f4.4f106./45.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a
		+12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi2h2ie2ke21.fg3i2e4ka21.f2ie6ka22.f2he4ka23.f3le2ka23.fm3nl2e23.fmnmopnopn22.fmn2opn2pn22.fon2opn2pn22.fono2pn2pn22.fpnmop
		+np2n22.fpnmopnp2n22.npn2opn2qn21.at3nihnrsq21.atu2t2nvasa21.at2uwaxyz2a21.artu2wayz2a21.arstuwazya22.asqtuwAayza22.2afuwAazya23.fB2CDtaza23.f3BDtEa25.f3t2DEf26.5f108./12.
		+5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf16.a3.f6gihjif15.aya2.f4gh3i2ef15.azya.f2gi2h2ie2ke16.azya.fg3i2e4ka16.azy2af2ie6ka17.azy2nf2he4ka19.
		+anihn3le2ka20.fmopnm3l2e20.fmo2pn5opn19.fo2pn5o2pn19.f2opn5o2pn20.2fn6o2pn22.fp5op2n22.fp5op2n22.n2p3o3qn21.ar4nqFrsq21.artu2tq2rsq21.artu2wq2rsq21.artu2wqrsqa21.arstuwA3
		+q22.asqtuwAtf24.2at2wAt27.tuwAt27.tuwAt26.fB2CDtf25.f4BDt26.f4t111./46.5a25.2a5b2a21.2a2b6cba.a17.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf20.f6gihjif20.f4gh3i2ef20.f2gi
		+2h2ie2ke21.fg3i2e4ka21.f2ie6ke2G20.f2he4ka3.3G16.f4le2ka7.2G13.f2m3noea2.a7.G11.f2mnmop3nf2n8a11.fmon2op2m2oihn7y11.f3on2p2o2p2hn7z11.f4o5nf2n8a11.fp5op2n2.a19.fp5op2n22.
		+n2p3o3qn21.at4nqFrsq21.atu3tq2rsa21.artu2wq2rsa21.arstuwqrsqa21.ar2tu2w2qa22.astwtuwAf24.atwtuwAf25.fwtuwAf25.fDtB2CDf24.fDt3BDf25.2f2t2f109./13.5a25.2a5b2a21.2a2b6cba.a1
		+7.ada10cada16.ad12cda17.a12da19.12e20.f8g2hf2.2a16.f6gihjif.ayza15.f4gh3i2efayza16.f2gi2h2ie2kayza18.fg3i2e2kayza20.f2ie3k2nxa22.f2heknihna22.fl3nmopn22.fmnmopopf22.f2mn2
		+op3n22.fm2on2pnpn22.f4o2n2pn22.f6o2pn22.fp5op2n22.fp5op2n22.n2p3o3qn21.ar4nqFrsq21.atu3tq2rsa21.atu2wAq2rsa21.atu2wAqrsqa21.artuwAt3q22.astuwAtAtf23.at2wAtAtf24.fuwAtAtf2
		+4.fuwAtAtf23.fB2CDtBEf23.f4BDtDEf23.3f2t3f108.
		pirateGunner|32|38|33|16|a7D6153,b6C798E,c495A77,d15131A,e374258,f2B3043,g14121A,h0B0B12,iB59378,jA17962,k291E20,l825F4E,m7688A4,n2D364F,o516994,p3B4A6B,q392C24,r847663,s2F2629,t4A4E57,u584A3D,v3F3530,w2A2C34,x2A2124,y645A52,z221A21,A1C1620,BC5A766,CECE2A2,DD9AB69,EC47758|idle:0;walk:1,2,3,4;shoot:5;fire:6;strike:6
		+109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g5lg24.gm3nlon23.gmnmopnopn22.gmn2opn2pn22.gon2
		+opn2pn22.gono2pn2pn22.gpnmopnp2n22.gpnmopnp2n22.gpn2opnq2n23.3nij3ng22.gr2s2ntds23.gr2ud2tdg23.gr2uvdtdg24.gruvdwdg24.gruvsdsg24.g2uvsvsg24.gruvsvsg24.gruvsvsg23.gx2yzsxA
		+g23.g4xzszAg23.3g2s3g108./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g5lg24.g3n2long22.gnm
		+opn2opng21.n2o2pno2png20.gmo2pn2o2png20.gmopn3o2png20.g2opn3op2ng20.nijn4op2ng21.2ntdqB2q2ng21.d2td5nlg21.gdtd5sg22.gdwduv2sg24.gd2uvsg26.sru2vs25.gsr2uvg25.gusruvg25.gus
		+ruvg25.gusruvg25.gzsx2yzg24.gzs3xzg25.2g2s2g109./141.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg2
		+4.g5lg24.gm3nlon23.gmnmopnopn22.gmn2opn2pn22.gon2opn2pn22.gono2pn2pn22.gpnmopnp2n22.gpnmopnp2n22.gpn2opnq2n22.g3nij3ng22.gr2s2ntds23.gr2ud2tdsg23.gruvdtdsg23.gruvdwdsg23.
		+g2uvsdvsg23.gruvsuvsg23.gruvs2xAg22.gx2yzs2zAg22.g4xzs2g24.5g111./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3k
		+g22.g7ijg23.g6jg24.g5lg24.gm3nlog23.gmnmopnopg22.gmn2o2pnpg22.g2onopmpng22.g3onm2opn22.gp3onmopn22.gp4onijn22.gp3qBq2ntd22.6nd2td21.gr6sdtd21.gr2uvs2vdwd20.gr2uvsu2vsd21.
		+gru2v2guv2sg19.gr2uvg.gu2vsg19.gruvg3.guvsg19.gruvg3.guvsg19.gruvg3.guvsg19.gx2yzg2.gz2xAg18.g3xzg2.g3zAg19.4g4.4g106./141.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e2ag17
		+.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g5lg24.gm3nlon23.gmnmopnopn22.gmn2opn2pn22.gon2opn2pn22.gono2pn2pn22.gpnmopnp2n22.gpnmopnp2n22.gpn
		+2opnq2n22.g3nij3ng22.gr2s2ntds23.g2rud2tdg24.gr2udtdg25.grudwdg25.gruvdsg25.gruv2sg24.gx2yz2sg24.g3xzsAg25.g3s2zAg26.5g108./109.6a25.a4b2ca22.da2b6ca20.d2e8cea18.defe4c3e
		+2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g6l24.g2m3non3g6d14.g2mnmop6n4twd13.gmon2op2m2oijnt3d14.g3on2p2o2p2jnd17.g4o5ng2nd18.gp5opng2
		+2.gp5opng22.gp3qB2qng23.8n23.gr6sg23.gr2uvsvsg23.gr2uv2sg25.gruv2sg25.sruvsg26.s2uvs27.sruvs27.sruvs26.gx2yzsg25.g4xzs26.g4s111./108.6a25.a4b2ca22.da2b6ca20.d2e8cea18.def
		+e4c3e2ag17.defae3ce3ahig17.def2a3ea3ihig18.deai3aj5ig19.d.g6i3kg22.g7ijg23.g6jg24.g6l24.g2m3non3g6d.C12.g2mnmop6n4tw2CD11.gmon2op2m2oijnt3dDCE11.g3on2p2o2p2jnd4.D12.g4o5n
		+g2nd18.gp5opng22.gp5opng22.gp3qB2q2n23.g7ng23.gr6sg23.gr2uvsvsg23.gr2uv2sg25.gruv2sg25.sruvsg26.s2uvs27.sruvs27.sruvs26.gx2yzsg25.g4xzs26.g4s111.
		player|32|38|33|16|a14121A,bCCAB8E,cB59378,dA17962,e0B0B12,f825F4E,gF0F002,hF0F001,iF0F003,jF0F004,k6A4242|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fcf23.abfbcdfcdf22.abf2cdfcdf22.acf2cdf2df22.acfc2df2df
		+22.adfbcdfc2f22.adfbcdfc2f22.adf2cd4f23.3fcd3fa22.ab7f23.ab2cdfdfa23.ab2cdfdfa24.abcdfdfa24.abcdfdfa24.a2cdfdfa24.abcdfdfa24.abcdfdfa23.ag2hifgja23.a4gifija23.3a2f3a108./
		+109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.a5fcfa22.afbcdf2cdfa21.f2c2df2cdfa20.abc2df2c2dfa20.abcdf3
		+c2dfa20.a2cdf4c2fa20.acdf5c2fa21.2fd4c3fa22.9fa21.ab7fa22.a2b2cd2fa24.ab2cdfa26.fbc2df25.afb2cda25.acfbcda25.acfbcda25.acfbcda25.aifg2hia24.aif3gia25.2a2f2a109./141.6a25.
		+a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fcf23.abfbcdfcdf22.abf2cdfcdf22.acf2cdf2df22.acfc2df2df22.adfbcd
		+fc2f22.adfbcdfc2f22.adf2cd4f22.a3fcd3fa22.ab7f23.ab2cdf2dfa23.abcdf2dfa23.abcdfcdfa23.a2cdfcdfa23.abcdfcdfa23.abcdf2gja22.ag2hif2ija22.a4gif2a24.5a111./109.6a25.a6ba23.a4
		+b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fca23.abfbcdfcda22.abf2c2dfda22.a2cfcdbdfa22.a3cfb2cdf22.ad3cfbcdf22.ad4c
		+fcdf22.a2d4c2fa23.8f23.ab6fa23.ab2cdf2dfa21.ab2cdfc2dfa21.abc2d2acd2fa19.ab2cda.ac2dfa19.abcda3.acdfa19.abcda3.acdfa19.abcda3.acdfa19.ag2hia2.ai2gja18.a3gia2.a3ija19.4a4.
		+4a106./141.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da24.a5fa24.ab4fcf23.abfbcdfcdf22.abf2cdfcdf22.acf2cdf2df22.acf
		+c2df2df22.adfbcdfc2f22.adfbcdfc2f22.adf2cd4f22.a3fcd3fa22.ab7f23.a2b2cd2fa24.ab2cd2fa25.abcd2fa25.abcd2fa25.abcd2fa24.ag2hi2fa24.a3gifja25.a3f2ija26.5a108./108.6a25.a6ba2
		+3.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda21.3a6da21.acd6fa21.abcdfc3fcf20.abc2df5cdf19.ac2df6cdf19.a2cdf5c2df20.2af6c2df22.ad6c2f2
		+2.ad6c2f22.a2d4c3f23.a8f23.ab6fa23.ab2cdfdfa23.ab2cd2fa25.abcd2fa25.fbcdfa26.f2cdf27.fbcdf27.fbcdf26.ag2hifa25.a4gif26.a4f111./142.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20
		+.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.a9ca22.a7cda23.a6da23.a5f2a23.abc3fcf23.abcfbcd3f3a19.abcf2cd2b3cda18.a3cf2d2c4da18.a4c5f3a19.ad6c2f22.ad6c2f22.a2d4c3f22.a8fa22.a
		+b7f24.ab2cdfa26.fbc2df25.afb2cda25.acfbcda25.acfbcda25.acfbcda25.aifg2hia24.aif3gia25.2a2f2a109./109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a
		+3c2d5ca21.a9ca22.a6c2fa23.a4dfcda23.a4fbcda22.abfbcdcda22.abcf2cd3f22.ab2cf2dfdf22.a4c2f2df22.a6c2df22.ad6c2f22.ad6c2f22.a2d4c3f23.8fa22.ab7f23.ab2cdfdfa23.ab2cdfdfa24.ab
		+cdfdfa24.abcdfdfa24.a2cdfdfa24.abcdfdfa24.abcdfdfa23.ag2hifgja23.a4gifija23.3a2f3a108./109.6a25.a6ba23.a4b4ca21.a2b8ca20.ab7c2da20.a3c2d2cdeca20.a2cdfd3ceca20.a3c2d5ca21.
		+a9ca22.a7cda23.a6da24.a6f24.abc3fcf6a17.abcfbcd6fdfa16.abcf2cd2b3cd2fa16.a3cf2d2c4dfa17.a4c5f3a19.ad6cfa22.ad6cfa22.a2d4c2fa23.8f23.ab6fa23.ab2cdfdfa23.ab2cd2fa25.abcd2fa
		+25.fbcdfa26.f2cdf27.fbcdf27.fbcdf26.ag2hifa25.a4gif26.a4f111./108.8a23.a8ba21.a4b6ca20.ab9ca20.ab9ca20.ad8cda20.adce4cecda20.adce4cecda20.a10ca20.ad3c2k3cda21.ad6cda22.a8
		+fa20.2ab9c2a17.ab11c2da16.ab11c2da16.ab11cdba16.ab11cdba16.ab10cdbca16.abcd7c2dbca16.a2c10dcda16.acd10acda16.acdfb6cbfcda17.af2b2c2d2c2bfa19.a2bcd2adc2ba20.a2bcd2adc2ba20
		+.a2bcd2adc2ba20.ab2cd2ad2cba20.a2bcd2adc2ba20.a2bcd2adc2ba20.a2hgi2ai2gha20.a3gi2ai3ga21.4a2.4a107.
		player_hair_0|32|38|33|16|aF00001,bF00002|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b851./141.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b851./173.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b819./141.6a25.a7b23.10b22.8b24.6b2
		+6.4b28.2b31.b851./173.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b819./140.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b852./174.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b818./141.6a25.a7
		+b23.10b22.8b24.6b26.4b28.2b31.b851./141.6a25.a7b23.10b22.8b24.6b26.4b28.2b31.b851./140.8a23.a9b22.10b22.b8.b22.b8.b939.
		player_hair_1|32|38|33|16|a14121A,bF00001,cF00002,dF00003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c883./12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6
		+cd25.5c27.3c29.2c883./44.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c851./12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a1
		+0ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c883./44.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c851./11.a3.a26.aba.aba.a22.abcbabc2
		+aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c884./45.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c850./12.a3.a2
		+6.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c27.3c29.2c883./12.a3.a26.aba.aba.a22.abcbabc2aba21.ab2cb3cbcba20.a10ca19.a11ca19.a9cd23.6cd25.5c2
		+7.3c29.2c883./11.a3.a3.a22.aba.aba.aba21.acbabcbabcba20.a2cb3cb3ca19.ab10cba18.a12ca20.c8.c1003.
		player_hair_2|32|38|33|16|aF00001,bF00002,c14121A,dF00003,e825F4E|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e660./141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.
		+c2bde27.cb2d29.cd692./173.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e628./141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.
		+c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e660./173.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e628./140.6a25.a7b23.10b20.
		+c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.cb2ed27.ce30.e727./174.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bd28.cb2de28.ede30.e627./141.6a25.a7
		+b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2de28.cde30.e660./141.6a25.a7b23.10b20.c10bd20.c8b23.c5bd25.c4bd26.c3bd27.c3bd27.c2b2d27.c2bde27.cb2
		+de28.cde30.e660./140.8a23.a9b22.10b20.c12bc18.c2b8.2bc18.c2b8.2bc18.c2b8.2bc18.cbd8.dbc18.cbd8.dbc18.cd10.dc19.c10.c746.
		player_hair_3|32|38|33|16|aF00001,bF00002,c14121A,dF00003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./173.6a25.a7b21.c.1
		+0b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c791./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./173.6a25.a7b21.c.10b19.ca10b19.ca2bd
		+6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c791./140.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c824./174.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd
		+2.2b25.cdc2.b27.c790./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c823./141.6a25.a7b21.c.10b19.ca10b19.ca2bd6b21.c2bd.4b23.cbd2.2b25.cdc2.b27.c8
		+23./140.8a23.a9b22.10b22.b8.b971.
		player_hair_4|32|38|33|16|aF00002,bF00003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./173.6a25.a6ba23.a8b23.a6b25.a3b28.ab883./141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./173.6a
		+25.a6ba23.a8b23.a6b25.a3b28.ab883./140.6a25.a6ba23.a8b23.a6b25.a3b28.ab916./174.6a25.a6ba23.a8b23.a6b25.a3b28.ab882./141.6a25.a6ba23.a8b23.a6b25.a3b28.ab915./141.6a25.a6b
		+a23.a8b23.a6b25.a3b28.ab915./140.8a23.a8ba22.b8.b1003.
		player_hair_5|32|38|33|16|a14121A,bF00001,cF00002,dF00003,e825F4E|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a787./45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a
		+4cd27.a2cd29.ad31.a787./77.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a755./45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd2
		+0.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a787./77.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a755./44.5a26.a5b2a23.ab6cba21.
		+ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.e788./78.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a754./4
		+5.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4cd27.a2cd29.ad31.a787./45.5a26.a5b2a23.ab6cba21.ab9ca19.ab10cda18.a10cd20.a8cd22.a6cd24.a5cd25.a4
		+cd27.a2cd29.ad31.a787./45.6a24.2a6b2a21.a2b6c2ba19.ab10cba18.a12ca18.a12ca18.a2c8.2ca18.ac10.ca937.
		player_helm|32|38|33|16|aF000F4,bF000F1,cF000F2,dF000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./141.6a25.a6b
		+a23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a818./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./141.6a25.a6ba23.ab6cda21
		+.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a818./108.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a851./142.6a25.a6ba23.ab6cda21.ab8cda20.ab
		+6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a817./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2d2a22.a4c2da24.ac2d3a26.3a850./109.6a25.a6ba23.ab6cda21.ab8cda20.ab6c2da21.a5c2
		+d2a22.a4c2da24.ac2d3a26.3a850./108.8a23.a8ba21.ab8cda20.ab8cda20.a2c6d2ca20.acd6adca21.2a6.2a907.
		player_pants_0|32|38|33|16|a0000F1,b0000F4,c0000F2,d0000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+780.a2b2.3b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb26.acdbdb26.acdbdb29.b32.b29.2b111./780.a7b24.2a2cd2b26.a2cdb27.bac2db26.ba2cd27.cbacd27.cbacd27.cbacd28.b31.b32
		+.2b111./812.a2b2.3b24.a2cdb2db25.acdb2db25.acdbcdb25.2cdbcdb25.acdbcdb25.acdb31.b32.b142./780.a6b25.a2cdb2db23.a2cdbc2db23.ac2d2.cd2b21.a2cd3.c2db21.acd5.cdb21.acd5.cdb21
		+.acd5.cdb203./812.a2b2.3b24.2a2cd2b26.a2cd2b27.acd2b27.acd2b27.acd2b30.2b30.b28.3b143./755.b24.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.bacdb27.bacdb31.b32.b27.4b
		+111./812.a7b25.a2cdb27.bac2db26.ba2cd27.cbacd27.cbacd27.cbacd28.b31.b32.2b111./780.a7b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb26.acdbdb26.acdbdb29.b32.b29.2b111./7
		+80.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.bacdb27.bacdb31.b32.b27.4b111./780.a6ca23.2a2c2d2c2a22.2acd2.dc2a22.2acd2.dc2a22.2acd2.dc2a22.a2cd2.d2ca22.2acd2.dc2a2
		+2.2acd2.dc2a203.
		player_pants_1|32|38|33|16|a0000F1,b0000F4,c0000F2,d0000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+780.a2b2.3b24.a2cdbdb25.a2cdbdb29.b31.b31.b31.b31.b31.b32.b29.2b111./780.a7b24.2a2cd2b26.a2cdb27.b4.b26.b32.b31.b31.b31.b31.b32.2b111./812.a2b2.3b24.a2cdb2db28.b31.b31.b3
		+1.b31.b31.b32.b142./780.a6b25.a2cdb2db23.a2cdbc2db364./812.a2b2.3b24.2a2cd2b30.b31.b31.b31.b31.b31.b28.3b143./755.b24.a6b25.a2cdbdb25.a2cd2b30.b27.b3.b27.b3.b27.b3.b27.b3
		+.b31.b32.b27.4b111./812.a7b25.a2cdb27.b4.b26.b32.b31.b31.b31.b31.b32.2b111./780.a7b24.a2cdbdb25.a2cdbdb29.b31.b31.b31.b31.b31.b32.b29.2b111./780.a6b25.a2cdbdb25.a2cd2b30.
		+b27.b3.b27.b3.b27.b3.b27.b3.b31.b32.b27.4b111./780.a6ca23.2a2c2d2c2a22.2acd2.dc2a363.
		player_pants_2|32|38|33|16|a0000F1,b0000F4,c0000F2,d0000F3|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+780.a2b2.3b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb29.b31.b31.b32.b29.2b111./780.a7b24.2a2cd2b26.a2cdb27.bac2db26.ba2cd27.cbacd28.b31.b31.b31.b32.2b111./812.a2b2.3
		+b24.a2cdb2db25.acdb2db25.acdbcdb25.2cdbcdb28.b31.b31.b32.b142./780.a6b25.a2cdb2db23.a2cdbc2db23.ac2d2.cd2b21.a2cd3.c2db21.acd5.cdb267./812.a2b2.3b24.2a2cd2b26.a2cd2b27.ac
		+d2b27.acd2b30.b31.b31.b28.3b143./755.b24.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.b3.b27.b3.b31.b32.b27.4b111./812.a7b25.a2cdb27.bac2db26.ba2cd27.cbacd28.b31.b31.
		+b31.b32.2b111./780.a7b24.a2cdbdb25.a2cdbdb26.acdbdb26.acdbdb26.2cdbdb29.b31.b31.b32.b29.2b111./780.a6b25.a2cdbdb25.a2cd2b27.acd2b26.bacdb27.b2cdb27.b3.b27.b3.b31.b32.b27.
		+4b111./780.a6ca23.2a2c2d2c2a22.2acd2.dc2a22.2acd2.dc2a22.2acd2.dc2a22.a2cd2.d2ca267.
		player_scarf|32|38|33|16|a14121A,b825F4E,c00F0F2,d00F0F1,e00F0F3,f00F0F4|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+395.ab29.acdb27.ae3c27.a2efe3.f23.aef30.a661./395.ab29.acdb27.ae3c27.a2ef3.ef23.aef30.a661./427.ab29.acdb27.ae3c27.a2efe3.f23.aef30.a629./395.ab29.acdb27.ae3c27.a2efe3.f2
		+3.aef30.a661./427.ab29.acdb27.ae3c27.a2efe3.f23.aef30.a629./394.ab29.a3b27.ab30.b4.3ef28.3f688./428.ab29.acdb27.ae3c4.b22.a2efe3.f23.aef30.f628./395.ab29.acdb27.ae3c27.a2
		+efe27.aef.f28.a661./395.ab29.acdb27.ae3c27.a2ef2e26.aef.f28.a661./427.b8.b56.2fce2f27.fcef29.2f655.
		player_shirt_0|32|38|33|16|a00F001,b00F004,c00F002,d00F003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+493.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.db3.bd2b23.db3.bd2b23.db3.4b23.3b2.3b27.2b431./493.3b2.cb24.bacdb2cdb22.b2c2dbc2db25.db2c2db25.b3c2db25.b3cd2
		+b24.b4cd2b22.2bd4c3b23.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.db3.bd2b23.db3.bd2b23.db3.4b23.3b2.3b27.2b399./493.a3b.c25.abacdbcd24.ab2c2dbd2
		+4.2cbcd2.b24.3cb4.b23.d3cb3.b23.d4cb2.b23.2d4c2b24.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.db3.bd2b23.db3.bd2b23.db3.4b23.3b2.3b27.2b399./460.
		+b31.ba3.cb24.db5cdb20.c2db5c2db20.2cdb5c2db22.b6c2db23.d5cd2b23.d5cd2b23.2d4c3b24.7b461./525.2a3bcb24.2abacd3b23.acb2cd26.3cb2d26.4c5b23.d5cd2b23.d5cd2b23.2d4c3b23.8b428.
		+/403.2b29.b28.3b27.abacd26.2ab2cd3b23.a2cb2dbdb23.4c2b2db23.6c2db23.d5cd2b23.d5cd2b23.2d4c3b23.8b460./493.2a3bcb24.2abacd6b20.acb2cd6.b19.3cb2d6.b19.4c5b23.d5cdb24.d5cdb2
		+4.2d4c2b24.8b460./491.2a8c20.2a10c2d18.a10cb2d18.acb8cbac18.acb8cbac20.bd6cdb22.b2d4c2db22.b8db23.8d23.10b21.b10.b394.
		player_shirt_1|32|38|33|16|a00F001,b00F004,c00F002,d00F003|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+493.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.dbacdbd2b23.dbacdbd2b23.db2cd4b23.3b2.3b27.2b431./493.3b2.cb24.bacdb2cdb22.b2c2dbc2db22.ac2db2c2db22.acdb3c2d
		+b22.2cdb3cd2b24.b4cd2b22.2bd4c3b23.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.dbacdbd2b23.dbacdbd2b23.db2cd4b23.3b2.3b27.2b399./493.a3b.c25.abacd
		+bcd24.ab2c2dbd24.2cbcdadb24.3cba2cdb23.d3cbacdb23.d4cb2.b23.2d4c2b24.8b460./525.a3b.cb24.abacdbcdb23.ab2cdb2db23.cb2cdb2db23.cbc2db2db23.dbacdbd2b23.dbacdbd2b23.db2cd4b23
		+.3b2.3b27.2b399./460.b28.acdba3.cb21.ac2db5cdb20.c2db5c2db20.2cdb5c2db22.b6c2db23.d5cd2b23.d5cd2b23.2d4c3b24.7b461./525.2a3bcb24.2abacd3b23.acb2cd2a2c22.3cb2d2c2d22.4c5b2
		+3.d5cd2b23.d5cd2b23.2d4c3b23.8b428./403.2b29.b28.3bacd24.abacdcd24.2ab2cd3b23.a2cb2dbdb23.4c2b2db23.6c2db23.d5cd2b23.d5cd2b23.2d4c3b23.8b460./493.2a3bcb24.2abacd6b20.acb2
		+cd2a2c2.b19.3cb2d2c2d2.b19.4c5b23.d5cdb24.d5cdb24.2d4c2b24.8b460./491.2a8c20.2a10c2d18.a10cb2d18.acb8cbac18.acb8cbac18.acbd6cdbac18.acb2d4c2dbac18.2cb8dbcd21.8d23.10b21.b
		+10.b394.
		player_shirt_2|32|38|33|16|aCCAB8E,b00F004,c00F001,d00F003,e00F002,fB59378|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+498.ab32.b23.c5.2db23.e5.2db23.e5.2db23.d5.d2b23.d5.d2b23.d5.3b23.2b4.2b460./498.ab29.e2.b28.e2db27.2e2db26.3e2db26.3ed2b25.4ed2b24.d4e3b23.8b460./530.ab32.b23.c5.2db23.e
		+5.2db23.e5.2db23.d5.d2b23.d5.d2b23.d5.3b23.2b4.2b428./498.a57.c6.d24.2e30.3e29.d3e28.d4e27.2d4e26.8b460./530.ab32.b23.c5.2db23.e5.2db23.e5.2db23.d5.d2b23.d5.d2b23.d5.3b23
		+.2b4.2b428./493.a3.ab26.c3e2.b24.5e2db24.5e2db23.6e2db23.d5ed2b23.d5ed2b23.2d4e3b24.7b461./526.a3.ab56.ce30.3e29.4e28.d5ed2b23.d5ed2b23.2d4e3b23.8b428./532.b23.c2e4.db23.
		+4e2.2db23.6e2db23.d5ed2b23.d5ed2b23.2d4e3b23.8b460./494.a3.ab56.ce30.3e29.4e28.d5edb24.d5edb24.2d4e2b24.8b460./493.6e.a22.c8e22.c9eb22.b8ebaf20.b8ebaf20.bd6edb22.b2d4e2db
		+22.b8db23.8d23.10b21.b10.b394.
		player_shirt_3|32|38|33|16|a825F4E,b14121A,c00F001,d00F002,e00F003,f00F004|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:8;front:9
		+363.a30.bca28.bc2da27.b2d2e28.b2e4f.df23.3fcdefdef23.cf2def2ef23.df2def2ef23.dfd2ef2ef23.efcdefe2f23.efcdefe2f23.2f2de4f23.3f2.3f27.2f431./363.a30.bca28.bc2da27.b2d2e28.b
		+2e3f2.df23.2fcdef2def22.f2d2efd2ef22.cd2efd3ef22.cde4f2ef22.2def3de2f24.5fe2f22.10f23.8f460./395.a30.bca28.bc2da27.b2d2e28.b2e4f.df23.3fcdefdef23.cf2def2ef23.df2def2ef23.
		+dfd2ef2ef23.efcdefe2f23.efcdefe2f23.2f2de4f23.3f2.3f27.2f399./363.a30.bca28.bc2da27.b2d2e28.b2e4f.d24.3fcdefde24.cf2d2efe24.2dfdecef24.2d2fc2def23.edfdfcdef23.ed4f2.f23.8
		+f24.8f460./395.a30.bca28.bc2da27.b2d2e28.b2e4f.df23.3fcdefdef23.cf2def2ef23.df2def2ef23.dfd2ef2ef23.efcdefe2f23.efcdefe2f23.2f2de4f23.3f2.3f27.2f399./362.a30.bca28.bc2fa2
		+7.bf2.f28.cde2f3.df21.cd2ef2dc2def20.d2ef3dcd2ef20.2def4d3ef22.f2d4f2ef23.edf3de2f23.ed4fe2f23.9f24.7f461./395.ba29.bcda27.bc2dea26.b2d2ef27.b2e5fdf23.4fcde3f23.cdf2de2c2
		+d22.3df2e2d2e22.2d7f23.edf3de2f23.ed4fe2f23.9f23.8f428./363.a30.bca6.2f20.bc2da4.f22.b2d2e.3fcde21.b2e2fcdede23.4f2de3f23.c2df2efef23.4d2f2ef23.2d4f2ef23.edf3de2f23.ed4fe
		+2f23.9f23.8f460./363.a30.bca28.bc2da27.b2d2e28.b2e5fdf23.4fcde6f20.cdf2de2c2d2.f19.3df2e2d2e2.f19.2d7f23.edf3def24.ed4fef24.8f24.8f460./459.f8.f22.c8fd20.2c2dc4dc2d2e18.c
		+3dc4dcdf2e18.cdf8dfcd18.cdf2d4f2dfcd18.cdfedf2dfdefcd18.cdf2e4f2efcd18.2d10fde21.8f23.10f21.f10.f394.
		polarBear|52|26|23|18|a212633,bEFEBE2,c707984,dE9E5D7,eA1A4A6,fFFFFFF,g1A1316,h1E1519,i3E4349,j8992A6,k3A3A43,lEFEAD9,m834248|idle:0;walk:1,2,3,4;strike:5
		+112.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce
		+9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.c5dc11dc5dce2c7e4a13.a5dc11ec5d2c2e3c4a17.a4de13c4dec4eca21.a4de7c5ac4dec4eca21.a3d2ec3e2ca5.a3d2ec3e2ca21.a3d2ec3e2ca5.a3d2ec3
		+e2ca21.a4d2ec3e2ca4.a4d2ec3e2ca20.a5dec4eca4.a5dec4eca20.ajkjkjkckjkjka4.ajkjkjkckjkjka21.12a6.12a71./112.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12
		+.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.aec5dc7dc5dc3e2c7e4a14.ac
		+5dc7ec5dc4ae5c2a19.a4de9c4dec3.a4eca21.a4de3c5ac4dea3.a4eca21.a3d2e2ca5.a3d2ea3.a3e2ca21.a3d2e2ca5.a3d2ea3.a3e2ca21.a4d2e2ca4.a4d2ea2.a4e2ca20.a5de2ca4.a5dea2.a5eca20.ajk
		+jkjkcka4.ajkjkjka2.ajkjkjka21.2a4c2a6.6a4.6a69./60.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5d
		+b2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.a2e15dc5dce2c7e4a13.a5dc11ec5d2c2e3c4a17.a5d13c4dec5ea21.a4de7c5ac4dec4eca21.a4d
		+ec3e2ca5.a3d2ec4eca21.a3d2ec3e2ca5.a3d2ec3e2ca21.a3d2ec4e2ca4.a4d2ec2e2ca21.a4d2ec4eca4.a5dec3e2ca20.a5deckjkjka4.ajkjkjkc4eca20.ajkjkjkc5a6.5acjkjkjka21.6a18.6a71./112.1
		+5a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23dcd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7d
		+a7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a9.a5dc15dc5d2c7e4a11.a5dc15ec5dcec6a15.a4de17c4de2ca21.a4de4a7c5ac4de2ca21.a3d2ea3.a3e2ca5.a3d2e2ca21.a3d2ea3.a3e2ca5.a3d2e2ca21.a4d2ea
		+2.a4e2ca4.a4d2e2ca20.a5dea2.a5eca4.a5de2ca20.ajkjkjka2.ajkjkjka4.ajkjkjkcka21.6a4.6a6.2a4c2a73./60.15a34.3a15b3a2.2a25.2a21bac2da23.a23bcd2ed7a15.a4b20dcde2d7b3a12.a2b23d
		+cd12ba10.a2b19de3dc3b4d3e4dba9.ab20de2dc2b7dfg5db2a7.ab21dedcb8d2g6d2ha6.a22dedc17d2ha6.ae23dce9de7da7.ae24dce7d2e6ia9.ae24dc2e5d2e4d2a11.c5dc16d3e2c7e4a13.a5dc11ec5d2c2e
		+3c4a17.a4de13c5dc4eca21.a4de7c5ac4dec4eca21.a3d2ec4eca5.a4dec3e2ca21.a3d2ec3e2ca5.a3d2ec3e2ca21.a4d2ec2e2ca5.a3d2ec4e2ca20.a5dec3e2ca4.a4d2ec4eca20.ajkjkjkc4eca4.a5deckjk
		+jka21.5acjkjkjka4.ajkjkjkc5a28.6a6.6a77./112.15a34.3a15b3a4.2a23.2a21b2a.a2da21.a25bcd2ed7a13.a4b20d2bcde2d7b3a10.a2b25dcd12ba8.a2b19de5dc3b4d3e4dba7.ab20de4dc2b7dfg5db2a
		+5.ab21de3dcb8d2g6d2ha4.a22de3dc17d2ha4.ae25dce9dedldldl2a5.ae26dce7d2e6ma7.ae19dc5d2ce6d2e6ma7.a5dc14dc5d3ce5d2edldldla7.a5dc14ec4dec2ec2e3d2e5da8.a4de16c4decec3a7e3a9.a4
		+dec2a7c5ac3d2ececa2.7a12.a3d2ea2.a3e2ca5.a3d2e3ca21.a3d2ea2.a4e2ca4.a4d2e2ca21.a4d2ea.a5eca4.a5de3ca20.a5dea.ajkjkjka4.ajkjkjkceca20.ajkjkjka2.6a6.2a4ckjka21.6a18.6a72.
		rex|130|84|79|62|a11140D,bE4DCC9,cDAD1B9,d9D9585,e727B56,f4E5739,gD87967,hECC7A2,i141010,j252C21,k353D2B,lEFEAD9,mD0CAAA,n87816A,o10140C,p2C3225,q242C20,rE3DBC9,s978E7F,t834248,u552930|idle:0;walk:1,2,3,4;windup:5;strike:6
		+2816.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae
		+23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka73.9o13.a8fj23ka67.7op7ep4o7.2ok9f3
		+j20a65.3o6e2p7f2p3e7o2e2k8fmka84.o2pe6f2p7f2p3f4e2pe2f2k7f2mka82.2oe2p7f2p7f2p7f2p3f3k5fmnka81.2o2ef2p6f2p7f3p7f2p4f3k3fmnka80.2o2e3fp7f2p7f2p8f2p5f6k2a75.6o2e4f2p7f2p7f2
		+p7f2p7f5k74.3o4e2p6fp7f2p8f2p7f2p9f2ko72.2o3e4f2p6fp7f2p7f2p8f2p7f2k2mo70.2o2p6f2p6f2p4f6k6f2p7f2p7fk4mo68.2o2e2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo65.3o2e2fp6f2p6fkf3k2e6f2ek1
		+2f2p4f2k4m2no58.7o3e3fp5f14ke10f2k16f2k3m4no54.4o5e2p5f2p2f17k11f18k4m5no50.4o2p2e4f2p6f17kj3k10f3k5m10k5m3n2o46.5o4fp6f2p5f6k16j2k9f3k19m2n2o47.o2p5f2p4f10k23j2k7f3k19m2
		+nq49.o5f15k9j14o4j2k5f3k19m3nqj2a46.o23j6o14.5o2k3f3k2n17m3nqj2fka46.23o26.3a3k22nqkj2fka100.o21noarkj2fka100.2o18no.arajrfka102.o16no3.a.jrara103.16o7.a.a93.a5fkj2kja118
		+.a5fkj2kja119.a4fkj2kja119.a4fkj2kja119.a3f2kjk2ja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja119.a4fkj2kja118.a6fkj2kja116.a8fkj2kja114.a10fkj2kja113.arsrsrsrsrs
		+jsrsa115.4a6j4a456./2816.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e
		+2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka75.7o13.a8fj23k
		+a68.8o6ep4o7.2ok9f3j20a66.3o5e2pe6f2p3e7o2e2k8fmka84.2op2e5f2p7f2p3f4e2pe2f2k7f2mka83.oe2p7f2p7f2p7f2p3f3k5fmnka82.2oef2p6f3p6f3p7f2p4f3k3fmnka81.2o2e2fp7f2p7f2p8f2p5f6k2
		+a80.2o2e3f2p7f2p7f2p7f2p7f5k76.6ope5f2p6f2p8f2p7f2p9f2ko74.2o5e2p6fp7f2p7f2p8f2p7f2k2mo72.2o2e5fp6f2p5f6k5f2p7f2p7fk4mo70.2o2p6f2p6fp4f2k6e2k3f2p7f2p6fk5mo68.2o2e2p5f2p8f
		+4k2e6f2ek11f2p4f2k4m2no66.2o2e2fp6f2p5f6ke10f2k15f2k3m4no60.6o2e3fp4f16k11f17k4m5no56.4o3e2pe4f2p2f18k10f3k4m10k5m3n2o54.3o4e2f2p6f16k5j2k9f3k18m2n2o52.4oe2p5f2p5f6k18j2k
		+7f3k18m2nq50.4o4f2p5f8k25j2k5f3k18m3nqj2a46.o2p5fp3f10k8j20o2k3f3kn17m3nqj2fka45.o4f8k11j6o21.2a4k21nqkj2fka45.o12j11o31.o21noarkj2fka45.12o43.o19no.arajrfka101.2o16no3.a
		+.jrara103.16o7.a.a95.j5fkj121.akj5fka120.a2kj5fka119.a3kj5fka118.a4kj4fka119.a3kj4fka119.a2kj4fka121.akj4fka121.aj4fka123.j4fkj122.a6fkj120.a8fkj118.a10fkj117.arsrsrsrsrs
		+j119.3a7j457./2686.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.
		+ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka73.9o13.a8fj23ka67.7o
		+p7ep4o7.2ok9f3j20a65.3o6e2p7f2p3e7o2e2k8fmka84.o2pe6f2p7f2p3f4e2pe2f2k7f2mka82.2oe2p7f2p7f2p7f2p3f3k5fmnka81.2o2ef2p6f2p7f3p7f2p4f3k3fmnka80.2o2e3fp7f2p7f2p8f2p5f6k2a75.6
		+o2e4f2p7f2p7f2p7f2p7f5k74.3o4e2p6fp7f2p8f2p7f2p9f2ko72.2o3e4f2p6fp7f2p7f2p8f2p7f2k2mo70.2o2p6f2p6f2p4f6k6f2p7f2p7fk4mo68.2o2e2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo65.3o2e2fp6f2p
		+6fkf3k2e6f2ek12f2p4f2k4m2no58.7o3e3fp5f14ke10f2k16f2k3m4no54.4o5e2p5f2p2f17k11f18k4m5no50.4o2p2e4f2p6f17kj3k10f3k5m10k5m3n2o46.5o4fp6f2p5f6k16j2k9f3k19m2n2o47.o2p5f2p4f10
		+k23j2k7f3k19m2nq49.o5f15k9j14o4j2k5f3k19m3nqj2a46.o23j6o14.5o2k3f3k2n17m3nqj2fka46.23o26.3a3k22nqkj2fka100.o21noarkj2fka100.2o18no.arajrfka102.o16no3.a.jrara103.16o7.a.a2
		+23.a5fkj2kja118.a5fkj2kja119.a4fkj2kja119.a4fkj2kja119.a3f2kjk2ja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kja119.a4fkj2kja118.a6fkj2kja116.a8fkj2kja114.a10fkj2kja
		+113.arsrsrsrsrsjsrsa115.4a6j4a456./2816.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16
		+e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2efj2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka
		+71.12o12.a8fj23ka66.6oe2p7e2p3o7.2ok9f3j20a65.2o6ef2p7f2p3e7o2e2k8fmka83.2o2p7f2p7f2p3f4e2pe2f2k7f2mka81.2o2e2p6f3p7f2p7f2p3f3k5fmnka80.2o2e2f2p6f2p7f2p8f2p4f3k3fmnka75.6
		+o2e4fp7f2p7f2p8f2p5f6k2a73.3o3e2pe5f2p7f2p7f2p7f2p7f5k72.3o3e3f2p6fp7f2p8f2p7f2p9f2ko70.2o2pe5f2p6f2p7f2p7f2p8f2p7f2k2mo68.2o2e2p5f2p7f2p3f6k7f2p7f2p7fk4mo65.3o2e2fp6f2p9
		+f3k6e2k5f2p7f2p6fk5mo55.10o3e3fp6f5k3f5k2e6f2ek13f2p4f2k4m2no51.4op7e2p5f2p3f15ke10f3k16f2k3m4no45.6o3fp7f2p6f20k11f19k4m5no44.o2p5f2p7f2p4f9k7j3k3jk10f3k7m8k6m3n2o45.o6f
		+17k21j2k9f3k20m2n2o47.o12j8k11j7o7j2k7f3k20m2nq50.12o10j9o7.8o2k5f3kn19m3nqj2a59.10o25.2k3f3k4n16m3nqj2fka94.5ak23nqkj2fka100.2o20noarkj2fka101.o18no.arajrfka102.2o14n2o3
		+.a.jrara104.14o8.a.a91.a5fk2a5kja113.a5fka2.a5kja112.a4fka4.a5kja111.a4fka5.a5kja110.a4fka6.a4kja111.a3fka6.a4kja111.a4fka4.a4kja113.a3fka4.a4kja113.a4fka2.a4kja115.a4fka
		+.a4kja115.a5fkj6kja114.a6fkj6kja113.a7fkj6kja112.arsrsrsrjsrsrsrsa114.5a2j8a453./2686.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2c
		+b5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa99.ajk16f11ka97.2aejk16filililililia96.a2ef
		+j2k15fklklklklklka95.ae4fjk25mka94.ae6fjk23nka73.9o13.a8fj23ka67.7op7ep4o7.2ok9f3j20a65.3o6e2p7f2p3e7o2e2k8fmka84.o2pe6f2p7f2p3f4e2pe2f2k7f2mka82.2oe2p7f2p7f2p7f2p3f3k5fm
		+nka81.2o2ef2p6f2p7f3p7f2p4f3k3fmnka80.2o2e3fp7f2p7f2p8f2p5f6k2a75.6o2e4f2p7f2p7f2p7f2p7f5k74.3o4e2p6fp7f2p8f2p7f2p9f2ko72.2o3e4f2p6fp7f2p7f2p8f2p7f2k2mo70.2o2p6f2p6f2p4f6
		+k6f2p7f2p7fk4mo68.2o2e2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo65.3o2e2fp6f2p6fkf3k2e6f2ek12f2p4f2k4m2no58.7o3e3fp5f14ke10f2k16f2k3m4no54.4o5e2p5f2p2f17k11f18k4m5no50.4o2p2e4f2p6f1
		+7kj3k10f3k5m10k5m3n2o46.5o4fp6f2p5f6k16j2k9f3k19m2n2o47.o2p5f2p4f10k23j2k7f3k19m2nq49.o5f15k9j14o4j2k5f3k19m3nqj2a46.o23j6o14.5o2k3f3k2n17m3nqj2fka46.23o26.3a3k22nqkj2fka
		+100.o21noarkj2fka100.2o18no.arajrfka102.o16no3.a.jrara103.16o7.a.a223.a5fkj2kja118.a5fkj2kja119.a4fkj2kja119.a4fkj2kja119.a3f2kjk2ja120.a3fkj2kja120.a3fkj2kja120.a3fkj2kj
		+a120.a3fkj2kja119.a4fkj2kja118.a6fkj2kja116.a8fkj2kja114.a10fkj2kja113.arsrsrsrsrsjsrsa115.4a6j4a456./2423.a7.a120.aba5.aba4.a114.acba3.abca3.aba114.acba.ab2ca2.abca114.a
		+2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia100.ae13f2g12fa100.a28fa100.ak16f11ka100.jk16f
		+lililililila98.2ajk14f12ta98.a2ej2k12f2t10ua98.ae3fjk11f2t9u2a98.ae5fjk9f2t10u2a98.a7fjk9m13ta97.a8fjk8nlililililililia77.8o11.ak8fjk21na69.8o7ep4o7.2k7f2mj20ka68.2o6e2p7
		+f2p3e7o3k5fmnk21a67.2ope6f2p7f2p3f4e2pef3k3fmnka86.2oe2p7f2p7f2p7f2p3f8k86.o2ef2p6f3p6f3p7f2p4f5kfo84.2oe3fp7f2p7f2p8f2p10fo79.5o2e3f2p7f2p7f2p7f2p11fo76.3o2e2pe5f2p6f2p8
		+f2p7f2p9f2ko73.3o3e2f2p6fp7f2p7f2p8f2p7f2k2mo71.2op2e4f2p6f2p4f6k6f2p7f2p7fk4mo69.2oe2p5f2p7fp3f2k6e2k4f2p7f2p6fk5mo67.2o2efp6f2p8f3k2e6f2ek12f2p4f2k4m2no64.3o2e2f2p6f5k2
		+f5ke10f2k16f2k3m4no57.7op2e4fp4f15k11f18k4m5no54.3o6ep6fpf19k10f3k5m10k5m3n2o51.4o2pe5f2p5f9k6j2k4j2k9f3k19m2n2o48.5o4fp6f2p3f6k19j2k7f3k19m2nq49.o2p5f2p3f10k11j6o8j2k5f3
		+k19m3nqj2a46.o5f14k8j6o6.9o2k3f3k2n17m3nqj2fka45.o21j6o22.3a3k22nqkj2fka46.21o33.o21noarkj2fka100.o19no.arajrfka101.2o16no3.a.jrara103.16o7.a.a93.a5fk2ja120.a5fkja122.j4f
		+kj123.j4fkj123.j3f2kj124.j3fkj124.j3fkja123.a3fkja123.a3fk2ja121.a4fkjkja119.a6fkjkja117.a8fkjkja115.a10fkjkja114.arsrsrsrsrsjsra116.6a4j3a457./3341.a7.a120.aba5.aba4.a11
		+4.acba3.abca3.aba114.acba.ab2ca2.abca114.a2cbab3cb2ab2ca115.a2cb5c2b2cda116.6a6d2b2a118.2a2b2c2b2c2b4a113.a16e3a109.a2e15f3e2a106.ae20f2ea104.ae23fe2a101.ae13fgh11fia96.4
		+aje13f2g12fa94.2a4ej28fa93.a2e4fjk16f11ka92.ke6fjk16flililililila66.10o14.oke7fjk14f12ta60.7o2p7ep4o7.3oek8fj2k12f2t10ua59.2o7e2p7f2p3e7o3efk9fjk11f2t9u2a58.2o2p7f2p7f2p3
		+f4e2pe4f2k8fmjk9f2t10u2a56.2o2e2p7f2p7f2p7f2p5f2k7f2mkjk9m13ta54.o2e2f2p6f2p7f3p7f2p5f3k5fmnka.ak8nlililililililia50.3oe4fp7f2p7f2p8f2p6f3k3fmnka3.ak21na44.6op2e4f2p7f2p7
		+f2p7f2p8f6k2a5.a20ka42.3o5e2p6fp7f2p8f2p7f2p9f3k2a8.20a41.2op2e5fp6f2p7f2p7f2p8f2p7f2k2mo69.2oe2p6f2p6f2p5f6k5f2p7f2p7fk4mo66.3o2efp6f2p11f3k6e2k3f2p7f2p6fk5mo59.7o3e2f2p
		+6f2p5f7k2e6f2ek11f2p4f2k4m2no54.5o4e2pe5fp4f16ke10f2k15f2k3m4no49.5o2p3e3f2p6fp21k11f17k4m5no45.4o5fp6f2p6f17k4j2k10f3k4m10k5m3n2o45.o2p5f2p5f12k20j2k9f3k18m2n2o47.o4f17k
		+26j2k7f3k18m2nq49.o26j19o3j2k5f3k18m3nqj2a47.26o19.4o2k3f3k2n16m3nqj2fka96.3a3k21nqkj2fka100.o21noarkj2fka100.2o18no.arajrfka102.2o15no3.a.jrara94.j5fkj2.15o7.a.a94.akj5f
		+ka120.a2kj5fka119.a3kj5fka118.a4kj4fka119.a3kj4fka119.a2kj4fka121.akj4fka121.aj4fka123.j4fkj122.a6fkj120.a8fkj118.a10fkj117.arsrsrsrsrsj119.3a7j457.
		scorpion|32|19|16|13|a291B15,bC2A16E,cB28B5A,d7F613D,e381F1C,f5F4536,g816244,hD87067|idle:0;walk:1,2,3,4;strike:5
		+69.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14
		+cga.3a11.a14ga17.a12fa19.af2af2af2afa21.a2.a2.a2.a47./69.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c
		+2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.2a12f20.af2af2af2afa21.a2.a2.a2.a46./37.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea
		+20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.a12fa19.ac2ac2ac2aca20.af2af2af2afa21.a2.a2.a
		+2.a47./69.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3g
		+a9.ag14cga.3a11.a14ga17.a3fa5fa3f19.afa.afafa.afa20.a3.a.a3.a46./37.4a27.a4ba25.abcd2cba23.ab2c2a2cba22.acda2.acda22.a2ca3.acea20.abca4.a2ea9.3a8.acd5a3f10ab2ca7.a2cf2bd2
		+bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.a12fa19.ac2ac2ac2aca20.af2af2af2afa21.a2.a2.a2.a47./69.8a23.a8b2a20.abcd2cd2cdcb2a17.ab2
		+c7a2cdb2a15.acda7.2a2c2ea14.a2ca9.2a2ea13.abca12.2a3.3a8.acd18ab2ca7.a2cf2bd2bd2bd3bfb4c2aca7.afb2cd2cd2cd4c2fg5ca8.a3cd2cd2cd2ch3cfa3ga9.ag14cga.3a11.a14ga17.a12fa19.af2
		+af2af2afa21.a2.a2.a2.a47.
		sentinel|50|42|36|22|a1A1F2F,bA6C3DD,c8EB2D1,d647A96,eF2FAFD,f566882,g86D4DF,hC4F1F4,iFFFFFF,j49556F,kA8E2EE|idle:0;fly:0,1;charge:2;strike:3
		+21.a48.aba46.abcda46.ada48.a32.a48.aba46.abcda14.2a30.ada14.a2ba30.a14.aeb2ca43.aeb3cfa41.aeb4cdfa39.aeb6cdfa37.aeb8cdfa30.a4.aeb10cdfa28.aba3.aeb11cda4.a22.aecda2.a2b5c2
		+g4cda3.aba20.aeb2cda.ab5cg2hg3cda2.aecda19.ab3cda.ab4cgh2ihg2cda.aeb2cda18.ab3cda.ab4cgh2ihg2cda.ab3cda18.ab3cda.ab5cg2hg3cda.ab3cda19.abcda2.ab6c2g4cda.ab3cda20.ada3.ad1
		+2cja2.abcda22.a4.a2d10c2ja3.ada29.a2d8c2ja5.a31.a2d6c2ja39.a2d4c2ja41.a2d2c2ja43.a2d2ja32.a12.adja32.aba12.2a32.abcda46.ada48.a442./421.2a47.a2ba45.aeb2ca12.a30.aeb3cfa10
		+.aba28.aeb4cdfa8.abcda26.aeb6cdfa8.ada26.aeb8cdfa8.a26.aeb10cdfa4.a24.a4.aeb11cda3.aba22.aba3.a2b5c2g4cda2.aecda20.aecda2.ab5cg2hg3cda.aeb2cda18.aeb2cda.ab4cgh2ihg2cda.ab
		+3cda18.ab3cda.ab4cgh2ihg2cda.ab3cda18.ab3cda.ab5cg2hg3cda.ab3cda18.ab3cda.ab6c2g4cda2.abcda20.abcda2.ad12cja3.ada22.ada3.a2d10c2ja4.a24.a5.a2d8c2ja37.a2d6c2ja39.a2d4c2ja4
		+1.a2d2c2ja9.a33.a2d2ja9.aba33.adja9.abcda33.2a11.ada48.a464./271.2a47.a2ba45.aeb2ca35.a7.aeb3cfa8.a24.aba5.aeb4cdfa6.aba22.abcda3.aeb2c2g2cdfa4.abcda22.ada3.aeb2cg2hg2cdf
		+a4.ada24.a3.aeb2cgh2ihg2cdfa4.a29.aebcgh4ihg2cda33.2a2bcg6ig2cd2a31.abjbcgh6ihgcdjba29.aecjbcg8igcjecda27.aebcjbcg8igjeb2cda26.ab2cjbcgh6ihgjb3cda26.ab2cjb2cg6igcjb3cda26
		+.ab2cjd2cgh4ihgcjb3cda27.abcj2d2cgh2ihg2c2jbcda29.ad2a2d2cg2hg2c2j2ada31.a2.a2d2c2g2c2ja2.a36.a2d4c2ja41.a2d2c2ja35.a7.a2d2ja8.a26.aba7.adja8.aba24.abcda7.2a8.abcda24.ada
		+19.ada26.a21.a566./372.2a47.a2ba45.aeb2ca43.aeb3cfa41.aeb4cdfa39.aeb6cdfa37.aeb8cdfa4.2a29.aeb10cdfa2.a2b3a26.aeb11cda.aeb3cd2a24.a2b5c2g4cd2aeb6cda3.k19.ab5cg2hg3cda.ad4
		+cd2a2.k.i.k17.ab4cgh2ihg2cda2.2a2d2a5.3i18.ab4cgh2ihg2cda4.2a5.k5ik16.ab5cg2hg3cda5.2a6.3i18.ab6c2g4cda4.a2b3a2.k.i.k17.ad12cja3.aeb3cd2a2.k19.a2d10c2ja2.aeb6cda22.a2d8c2
		+ja4.ad4cd2a24.a2d6c2ja6.2a2d2a27.a2d4c2ja9.2a30.a2d2c2ja43.a2d2ja45.adja47.2a576.
		sheep|30|22|19|12|a1E1B24,bF6F2EA,c3A3541,d6B6675,e524C59,fDCD6D3,gFFFFFF,h16141A,i2A2530,jB9B1BB|idle:0;walk:1,2,3,4;alt:5
		+64.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4
		+ja2ja13.acdec3j.2acdecjca13.adececa3.adececa13.adececa3.adececa13.adececa3.adececa13.a2e3ca3.a2e3ca13.a2ic2ia3.a2ic2ia14.2a.2a5.2a.2a40./64.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2
		+ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja13.2ajcdeca.cdec.3aeca12.acd
		+ea2.adea3.aeca12.acdea2.adea3.aeca12.acdea2.adea3.aeca12.ac2ea2.a2ea3.a2ca12.ac2ia2.a2ia3.a2ia13.aca4.2a5.2a38./34.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2b
		+f14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja13.3a.4j.2acdeca15.adececa3.adececa13.adececa3.adecec
		+a13.adececa3.adececa13.ade3ca3.a2ececa13.a2ec2ia3.a2i3ca13.a2i3a5.3a2ia14.2a11.2a40./64.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.
		+a17bc8ea2.abf12bf3bc5ecia2.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja12.adec.2a2jcj2ajcdea12.adea3.aeca2.acdea12.adea3.aeca2.acdea12.adea3.aeca2.acde
		+a12.a2ea3.a2ca2.ac2ea12.a2ia3.a2ia2.ac2ia13.2a5.2a4.aca41./34.2a.3a.3a.2a2.2a11.2a2ba3ba3ba2ba3c2a8.a15b2c2d2e3a4.a2bf14bcd6ea3.a9bf7bc3egh3ea2.a17bc8ea2.abf12bf3bc5ecia2
		+.a19bc4ecia2.aj4bf13bj5ca3.a2j16b2j5a5.a3j12b3ja11.a3ja4ja4ja2ja13.acdec3a.4a.2jca13.adececa3.adececa13.adececa3.adececa13.adececa3.adececa13.a2ececa3.ade3ca13.a2i3ca3.a2
		+ec2ia14.3a2ia3.a2i3a18.2a5.2a43./64.2a.3a.3a.2a15.2a2ba3ba3ba2b2a12.a17ba10.a2bf16ba9.a9bf10ba8.a20ba8.abf12bf5ba8.a20bca7.aj4bf13b3c2a5.a2j16b2c2d2e3a3.a3j12b3jcd6ea3.a3
		+ja4ja4ja2j2a3egh3ea3.acdec3j.2acdecj2c8ea4.adececa3.adecec2a5ecia4.adececa3.adececa.a4ecia4.adececa3.adececa2.a4ca5.a2e3ca3.a2e3ca3.4a6.a2ic2ia3.a2ic2ia14.2a.2a5.2a.2a40.
		sheep_1|30|22|19|12|a1E1B24,b3A3541,c6B6675,d524C59,eEFD6C8,fFFFFFF,g16141A,hE2C3B5,i2A2530,jC4A197,kA28079|idle:0;walk:1,2,3,4;alt:5
		+79.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a16.acdb3k3abcdbdba13.acdbdba3.acdbd
		+ba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.a2d3ba3.a2d3ba13.a2ib2ia3.a2ib2ia14.2a.2a5.2a.2a40./79.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5db
		+ia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a17.kbcdb2abcdb3.adba12.abcda2.acda3.adba12.abcda2.acda3.adba12.abcda2.acda3.adba12.ab2da2.a2da3.a2ba12.ab2ia2.
		+a2ia3.a2ia13.aba4.2a5.2a38./49.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a17.2a4k
		+3abcda16.acdbdba3.acdbdba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.acd3ba3.a2dbdba13.a2db2ia3.a2i3ba13.a2i3a5.3a2ia14.2a11.2a40./79.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a
		+15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h3ja2.4a6.a15ja14.2a11k2a14.acdb3a4k2akbcda12.acda3.adba2.abcda12.acda3.adba2.abcda12.acda3.adba2.abcd
		+a12.a2da3.a2ba2.ab2da12.a2ia3.a2ia2.ab2ia13.2a5.2a4.aba41./49.2a27.a2b2a12.13ab2c2d3a7.2a12eabc6da5.a15eb3dfg3da3.a2e14hb8da3.a17hb5dbia3.a18hb4dbia3.aj15h2j2a4ba4.a2j12h
		+3ja2.4a6.a15ja14.2a11k2a16.acdb8a.adba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.acdbdba3.acdbdba13.a2dbdba3.acd3ba13.a2i3ba3.a2db2ia14.3a2ia3.a2i3a18.2a5.2a43./125.12a16.2
		+a12e2a13.a16ea11.a2e15ha11.a18ha10.a18h3a8.aj15h2j3b2a6.a2j12h3j2b2c2d3a4.a15ja.ac6da4.2a11k2a2.a3dfg3da4.acdb3k3abcdbd2b8da4.acdbdba3.acdbdb2a5dbia4.acdbdba3.acdbdba.a4d
		+bia4.acdbdba3.acdbdba2.a4ba5.a2d3ba3.a2d3ba3.4a6.a2ib2ia3.a2ib2ia14.2a.2a5.2a.2a40.
		skeleton|42|42|36|18|a17151C,bDBE1E9,cA8B0BD,d7B8391,e555C6A,fF7F3E5,gE3DBC7,hF3F6FA,i2A2732,jB2B9C7,k92DDE8,lB9B09C,mFDFDF2,n887D73,o977A49,pCCB36B,qA98960,r644933,s806044,t846547,uE6EBF5,vA6B1C3,w644A34|idle:0;walk:1,2,3,4;windup:5;strike:6;block:7;shoot:6
		+226.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9ed2a29.af9gaha28.af3g3i3gahja27.a3g3iki2gahja27.a4g3igigahja27.al9gahja28.al2gmimimlahja28.a8i2ahja29.algmimimlahja29.an6l2ahja25.
		+2a.a2f6n.ahja24.adcnfginfgn2gao2pa24.acq2afgngln2g2arsa24.act2agingl4narsa24.act2afgnf5gapa25.act2ag2in6la26.adt2af3g4n2a28.ada.aigl2in32.a.af5ga34.a6n35.aglnlna35.aglnln
		+a35.af2gn2la34.aglnlna35.aglnlna35.aglnlna35.abcdndea33.ab3cdndea33.3a2n3a188./226.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9eda.a28.af9g2aha27.af3g3i3g2ahja26.a3g3iki2g2ahja26
		+.a4g3igig2ahja26.al9g2ahja27.al2gmimiml2ahja27.a8ia.ahja28.algmimiml2ahja28.an6la.ahja24.2a.a2f6n2.ahja23.adcnfg2infgng2ao2pa23.acq2af2gnglnga.arsa23.act2ag2ingl3n2arsa23
		+.act2af2gnf5gapa24.act2ag3in6la25.adt2af4g3n3a27.ada.aigl2ia32.a.af5ga34.a6n36.aglna37.agl2n37.anf2ga36.angla36.al2ngla35.al2ngla35.acnb2cda34.acnb2cda35.2a2n2a189./268.5
		+a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9ed2a29.af9gaha28.af3g3i3gahja27.a3g3iki2gahja27.a4g3igigahja27.al9gahja28.al2gmimimlahja28.a8i2ahja29.algmimimlahja29.an6l2ahja25.2a.a2
		+f6n.ahja24.adcnfginfgn2gao2pa24.acq2afgngln2g2arsa24.act2agingl4narsa24.act2afgnf5gapa25.act2ag2in6la26.adt2af3g4n2a28.ada.aigl2in32.a.nf5ga34.a6na34.agla.alna33.af2g2ag2
		+la32.agla.alna33.agla.alna33.agl2acdea33.abcdnc2dea31.ab3cdn3a33.5a191./226.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9eda30.af8gaha29.af3g3i2gahja28.a3g3ikigahja28.a4g3igiahja2
		+8.al8gahja29.al2gmimimahja29.a8iahja30.algmimimahja30.an6lahja26.2a.a2f6nahja25.adcnfgnfgnigao2pa25.acq2afngln3garsa25.act2agngl4narsa25.act2afnf5gapa26.act2agin6la27.adt
		+2af2g5na29.ada.aigl2ina31.a.af5gn34.a6n34.agla.alna33.agla.aln2a31.af2ga2.ag2la30.agla3.alna30.agla5.alna29.agla5.alna29.abcda3.ac2dea28.ab2cda2.ac2dea29.4a4.4a186./268.5
		+a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9ed2a29.af9gaha28.af3g3i3gahja27.a3g3iki2gahja27.a4g3igigahja27.al9gahja28.al2gmimimlahja28.a8i2ahja29.algmimimlahja29.an6l2ahja25.2a.a2
		+f6n.ahja24.adcnfginfgn2gao2pa24.acq2afgngln2g2arsa24.act2agingl4narsa24.act2afgnf5gapa25.act2ag2in6la26.adt2af3g4n2a28.ada.aigl2in32.a.nf5ga35.6n37.aglna37.af2gna36.aglna
		+37.aglna36.abcdna36.ab2cdna36.4ndea36.5a188./52.2a39.apsa37.aropa36.ahproa35.ahjo4a.5a27.ahj2a.afgn5b2a24.ahja3.aglfn6ca22.ahja4.anglfn5cda21.aja5.adnglfn4eda22.a7.afngln
		+5ga30.afg2n3i3ga30.a3g3iki2ga30.a4g3igiga30.al9ga31.al2gmimimla31.a8ia33.algmimimla32.an6la29.2a.a2f6n29.adcnfg5i2ga28.acq2af7ga28.act2ag6ila28.act2af7ga28.act2ag6ila28.a
		+dt2af6ga30.ada.aigl2in32.a.af5ga35.6na35.agl2na36.agl2na36.af2gna36.aglna37.ngln38.ngln38.nbcdn36.ab3cdn36.a4n191./270.5a35.2a5b2a32.a2b7ca30.a2b8cda29.ad9eda30.af9ga30.a
		+f3g3i3ga30.a3g3iki2ga30.a4g3igiga.3u26.al9ga3.2u26.al2gmimimla4.vu25.a8ia6.vu25.algmimimla6.v24.2an6la28.2a.a2fg5na28.adcnfg2i6n11a17.acq2afgnf2gfg2ao9ja16.act2agin4lap2r
		+p9ha15.act2af2g5n2ao10a16.act2ag6ila.a26.adt2af6ga30.ada.aigl2in32.2anf5ga34.a4n2a35.agl2n37.anf2ga36.angla36.al2ngla35.al2ngla35.acnb2cda34.acnb2cda35.2a2n2a189./226.5a3
		+5.na5b2a32.n2b7ca30.a2b8cda29.ad9eda30.nf9ga30.nf3g3i3ga30.n3g3iki2ga30.n4g3igiga30.nl9ga30.anl2gmimimla30.an7i5a27.aopnlgmimad3cda27.ar2n3lad2q3tda26.an2f3nacq4tda26.nfg
		+2i2nac2tbcwea27.nfgnfgac2tcdwea27.aginglac3t2wea27.af2g2nadt4wda27.ag5iad3wda28.af6ga3da30.aigl2in.3a30.af5ga34.a6n35.aglnlna35.aglnlna35.af2gn2la34.aglnlna35.aglnlna35.a
		+glnlna35.abcdndea33.ab3cdndea33.3a2n3a188.
		slime|26|20|17|13|a1C362E,b97CC84,cFFFFFF,d7ABD6B,e548751,f15231C,g3B6241,h213724|idle:0;hop:1;strike:2
		+113.8a16.2a8b2a13.a3b2c5b2d2a10.a2b3c2b8da8.a2b2cb11dea6.a3b14dea6.ab3dfc6dfc3d2ea4.ab4d2f6d2f3d2ea4.ab17d2ea4.a17d2ega4.a7d6h4d2ega4.ae16d2ega5.a3e12d2ega7.ag14ega9.16a3
		+1./10.6a18.2a6b2a15.a3b2c3b2da13.a2b3cb6da12.ab2cb7dea11.a3b9dea11.ab2dfc4dfc2dea10.ab2d2f4d2f2dea10.ab12dea10.a12d2ea10.a5d4h3d2ea10.a12d2ea10.ae11dega11.ae9d2ega11.a2e8
		+dega13.a10ea15.a8ga17.8a61./140.8a16.2a8b3a11.2a3b2c5b3d2a8.a3b3cb10d2a5.a3b2cb6dfc5dea3.a3b7dfcd2f5dea3.ab9d2f7d2ea2.ab11d7hd2ea2.ab10dhchchc2hdega2.a11d8hdega2.ae11dhch
		+chc2dega3.a2e16d2ega4.ag17ega6.19a28.
		tiger|46|24|20|20|a1E1510,bCB925D,cD5A46E,d291D1A,e6D4937,fDBC86E,g15111A,hF5EEDF,iD4838F,j956847,k392121,lD3C8B9,mFFFFFF,n8C464E|idle:0;walk:1,2,3,4;strike:5
		+75.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ada8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia
		+8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha12.aj2bd4bd4bd4bd4b2e5j2a14.e3be12he3b3e6a16.abdbe12lebdbedja21.a2bj5e8ae2bjejea21.abdjejdea8.abdjedea
		+21.a2bje2jea8.a2bjejea21.a2bje2jea8.a2bjejea21.a3he3la8.a3he2la21.a2hle3la8.a2hle2la22.3a.3a10.6a107./75.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ad
		+a8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha
		+12.aj2bd4bd4bd4bd4b2e5j2a14.aje3be8he3be2j2ej2e3a17.aebdbe8lebdbe3ajdja21.e2bje8ae2bje2.a2jea21.ebdje8.abdja2.ajdea21.e2bje8.a2bja2.a2jea21.e2bje8.a2bja2.a2jea21.e3he8.a3
		+ha2.a3la21.e2hle8.a2hla2.a3la22.3e10.3a4.3a105./29.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ada8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3
		+bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha12.aj2bd4bd4bd4bd4b2e5j2a14.a2j14he3be2a.5a16.a3be12le
		+bdbe2ja21.abdb5e8ae2bjedja21.a2bjejdea8.abdjejea21.abdje2jea8.a2bjedea21.a2bje2jea8.a2bjejea21.a2bje3la8.a3hejea21.a3he3la8.a2hle2la21.a2hl4a10.2ae3la22.3a17.3a107./75.2a
		+5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ada8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2ae
		+c5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha12.aj2bd4bd4bd4bd4b2e5j2a12.a3be16he3be.5a14.abdbej15lebdba20.a2bj4a5e7a2e2bja20.abdja3.ajdea7.aebdja20.a2b
		+ja3.a2jea7.ae2bja20.a2bja3.a2jea7.ae2bja20.a3ha3.a3la7.ae3ha20.a2hla3.a3la7.ae2hla21.3a5.3a9.a2ea108./29.2a5.2a9.2a25.a2ba3.a2ba7.acba23.ab2db3ab2dba6.aba24.a4b3c4bca5.ad
		+a8.16a.acbd3bd4bca4.a2b2a4.2a16cec8bf3ba5.abdb4a2c2bd3bd3bd3bdbebd7bg2bha6.2abdbec4bd3bd3bd3bdbe7b5hia8.2aec5bd3bd3bd3bdbejd4b6ha11.a21bej4b2h3kha11.a3bd4bd4bd4bd3be3j6ha
		+12.aj2bd4bd4bd4bd4b2e5j2a14.e3be15h2j2e6a16.abdbe12le3bedja21.a2bj5e8aebdbejea21.abdje2jea8.a2bjedea21.a2bjejdea8.abdjejea21.a2bje2jea8.a2bjejea21.a3he2jea8.a2bje2la21.a2
		+hle3la8.a3he2la22.4a3la8.a2hle2a27.3a10.3a110./77.2a5.2a7.2a27.a2ba3.a2ba5.acba25.ab2db3ab2dba4.aba26.a4b3c4bca3.ada8.16a3.acbd3bd4bca2.a2b2a4.2a16c3ac8bf3bha2.abdb4a2c2b
		+d3bd3bd3bdb2cebd7bg2bhia3.2abdbec4bd3bd3bd3bd3be7bhmhmhma6.2aec5bd3bd3bd3bd3bejd4bh5na9.a23bej4bh5na9.a3bd4bd4bd4bd5be3jbhmhmhma9.aj2bd4bd4bd4bd4bj3a3j4ha10.a3be15he3be3.
		+7a11.abdbe15lebdbe21.a2bje2a5e8ae2bje21.abdja2.ajdea8.ebdje21.a2bja2.a2jea8.e2bje21.a2bja2.a2jea8.e2bje21.a3ha2.a3la8.e3he21.a2hla2.a3la8.e2hle22.3a4.3a10.3e108.
		warden|84|94|90|42|a120E18,b6A6F7E,c989EAD,dD6DAE3,eF3F5F9,f100C18,g57473A,h392E25,i625773,j3B3148,k292233,l0C0912,mCEA8EE,nFCEEFC,o2B2D38,p818493,q5A5E6C,r3E404D,sD9C4F4,tA481CE,u1C1825,v1B1525,wC096E9,xEFE0FA|idle:0;fly:0,1;windup:2;strike:3;cast:4
		+723.12a71.a2b2c7de5a67.a2b2c8d4e2a66.2a2b5a2c4d3ea64.fgh2a5.5a2d2ea64.fghf11.2ad2ea63.fghf13.a2ea63.fghf14.aea63.fghf15.a64.fghf80.fghf66.2a12.fghf65.a2ia11.fghf64.ai2jia
		+10.fghf63.ai4jia9.fghf62.ai6jia8.fghf61.ai8jka7.fghf60.ai6j4lka6.fghf59.ai6j6lka5.fghf59.ai5j7lka5.fghf58.ai5j5lmnlka5.fghf58.ai5j8lka5.fghf58.ai5j4lm3lka5.fghf58.ak6j6l2
		+ka5.fghf58.ak7j4l2ka6.fghf59.a2kjk2j6oa7.fghf60.ak2a2o5pq2a6.fghf61.2ao4p5qra5.fghf60.2ao2p7q3ra4.fghf59.apo2p7q2roa5.fghf58.a2po8q3r2o5.fghf58.ap2qo7r4oa5.3of57.ap4q10or
		+a4.a2qro57.a9qs4q2ra3.ap2q2ra56.ar8qt4q2ra3.a3qroa56.a2r11q2roa4.aqr2o58.a2r10q2roa4.a2qro59.a11r2oa4.ap3qoa57.2a13o6a2qr2oa56.a3i2j2k5jk5jku2ar3o56.a3i3jk5j2k5jkua.3of56
		+.a3i3j2k5jk6jkuafghf56.a3i3j2k5jk6jkuafghf55.a3i3j2k5j2k6jkuafghf55.a3i3j2k6j2k6jk2ughf55.a3i3j2k6j2k6jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k6j2k7jk
		+2uhf54.a3i4j2k6j2k7jk2uhf53.a4i3j2k7j2k7jk2uhf53.a4i3j2k7j2k7jk2uhf53.a4i4j2k6j2k8jk2uf53.a4i4j2k6j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j3k8jk2u52.a
		+4i4j2k7j3k8jk2u52.a4i4j2k7j3k8jk2u51.a4i4j3k7j2k9jk2u51.a4i4j3k7j2k9jk2u51.a4i5j2k7j3k9jkua50.a4i5j2k7j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.
		+a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua46.a5i5j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3
		+k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua43.a2ia2i2ja2j2ka4ja4ja3kja4ja4jaua43.a2iaia2jaja2kaja2jaja2jakakjaja2jaja2jaua43.a
		+i2aiaj2ajaj2akaj2ajaj2akak2ajaj2ajaj2aka43.aia.2aja.2aja.2aja.2aja.2aka.2aja.2aja.a45.a4.a4.a4.a4.a4.a4.a4.a197./807.12a71.a2b2c7de5a67.a2b2c8d4e2a66.2a2b5a2c4d3ea64.fgh2
		+a5.5a2d2ea64.fghf11.2ad2ea63.fghf13.a2ea63.fghf14.aea63.fghf15.a64.fghf80.fghf66.2a12.fghf65.a2ia11.fghf64.ai2jia10.fghf63.ai4jia9.fghf62.ai6jia8.fghf61.ai8jka7.fghf60.ai
		+6j4lka6.fghf59.ai6j6lka5.fghf59.ai5j7lka5.fghf58.ai5j5lmnlka5.fghf58.ai5j8lka5.fghf58.ai5j4lm3lka5.fghf58.ak6j6l2ka5.fghf58.ak7j4l2ka6.fghf59.a2kjk2j6oa7.fghf60.ak2a2o5pq
		+2a6.fghf61.2ao4p5qra5.fghf60.2ao2p7q3ra4.fghf59.apo2p7q2roa5.fghf58.a2po8q3r2o5.fghf58.ap2qo7r4oa5.3of57.ap4q10ora4.a2qro57.a9qs4q2ra3.ap2q2ra56.ar8qt4q2ra3.a3qroa56.a2r1
		+1q2roa4.aqr2o58.a2r10q2roa4.a2qro59.a11r2oa4.ap3qoa57.2a13o6a2qr2oa56.a3i2j2k5jk5jku2ar3o56.a3i3jk5j2k5jkua.3of56.a3i3j2k5jk6jkuafghf56.a3i3j2k5jk6jkuafghf55.a3i3j2k5j2k6
		+jkuafghf55.a3i3j2k6j2k6jk2ughf55.a3i3j2k6j2k6jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k5j2k7jk2ughf54.a3i4j2k6j2k7jk2uhf54.a3i4j2k6j2k7jk2uhf53.a4i3j2k7j2k7jk2uhf53.a4i3j2k7
		+j2k7jk2uhf53.a4i4j2k6j2k8jk2uf53.a4i4j2k6j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j2k8jk2uf52.a4i4j2k7j3k8jk2u52.a4i4j2k7j3k8jk2u52.a4i4j2k7j3k8jk2u51.a4i4j3k7j2k9jk2u51.a
		+4i4j3k7j2k9jk2u51.a4i5j2k7j3k9jkua51.a4i5j2k7j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua
		+47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua47.a5i5j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k
		+9j3k11jkua44.a5i5j3k9j3k11jkua44.a4ia4ja2k2ja4ja2j2ka4ja4jajkua44.aia2iaja2jaka2jaja2jaja2kaja2jaja2jajaua44.aiai2ajaj2akak2ajaj2ajak2ajaj2ajaj2ajaka45.2aia.2aja.2aka.2aj
		+a.2aka.2aja.2aja.2aka47.a4.a4.a4.a4.a4.a4.a4.a108./695.3a79.2a2eda76.2a2e2dca75.a2e2dc2ahf73.ae2dc2afghf72.ae2dca3.fghf70.ae2d2a4.fghf69.ae2da7.fghf68.aeda9.fghf66.aeda10
		+.fghf66.aea12.fghf66.a13.fghf5.2a74.fghf3.a2ia74.fghf.ai2jia73.fghfai4jia73.fgui6jia72.fui8jka71.ai6j4lka69.ai6j6lka68.ai5j7lka67.ai5j5lmnlka67.ai5j8lka67.ai5j4lm3lka67.a
		+k6j6l2ka67.ak7j4l2ka69.a2kjk2j6oa71.ak2a2o5pq2a71.2ao4p5qra69.2ao2p7q3ra67.apo2p7q2r2oa66.a2po8qr2o2pqa65.ap2qo7ro2p2qra64.ap4q7op2q2ra65.a9qsop2qr2o66.ar8qop2q2r2o66.a2r
		+7qo2q5of66.a2r7q4or2of67.a9r5oghf65.2a13oa4u63.a3i2j2k5jk5jkua61.a3i3jk5j2k5jk2u61.a3i3j2k5jk6jkua60.a3i3j2k5jk6jk2u59.a3i3j2k5j2k6jkua59.a3i3j2k6j2k6jkua58.a3i3j2k6j2k6j
		+kua57.a3i4j2k5j2k7jkua57.a3i4j2k5j2k7jkua57.a3i4j2k6j2k7jkua56.a3i4j2k6j2k7jkua55.a4i3j2k7j2k7jkua55.a4i3j2k7j2k7jkua55.a4i4j2k6j2k8jkua54.a4i4j2k6j2k8jkua53.a4i4j2k7j2k8
		+jkua53.a4i4j2k7j2k8jkua53.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua51.a4i4j3k7j2k9jkua51.a4i4j3k7j2k9jkua51.a4i5j2k7j3k9jkua49.a4i5j2k7j3k9jkua49.a4i5j2k8j3k
		+9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua46.a5i5
		+j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua43.a3iai3jaj3ka4ja4ja2k2ja4ja3jka45.a
		+2iaia2jaja2kaja2jaja2jaka2jaja2jajajk2a44.ai2aiaj2ajak2ajaj2ajaj2akaj2ajaj2ajaj2aua43.aia.2aja.2aka.2aja.2aja.2aja.2aja.2aja.a45.a4.a4.a4.a4.a4.a4.a4.a197./1717.2a81.a2ia
		+79.ai2jia77.ai4jia75.ai6jia73.ai8jka71.ai6j4lka69.ai6j6lka68.ai5j7lka67.ai5j5lmnlka67.ai5j8lka67.ai5j4lm3lka67.ak6j6l2ka67.ak7j4l2ka69.a2kjkj2v5oa71.ak2avghv3pq2a71.2aopv
		+ghv4qra69.2ao2pqvghv2q3ra67.apo2p3qvgh2vroa67.a2po6qv6o67.ap2qo5ro2p2q2o4a62.ap4q5op9qra61.a9qo2q4r5qoa60.ar8qt6or2oq2oa60.a2r9q2o2r6oa62.a2r10q2roafg2of63.a11r2oa2.f2ghf
		+61.2a13o4avfghf59.a3i2j2k5jk5jkuafghf57.a3i3jk5j2k5jkua.fghf56.a3i3j2k5jk6jkua.fghf55.a3i3j2k5jk6jkua2.fghf3.2w48.a3i3j2k5j2k6jkua3.fghf4.2w46.a3i3j2k6j2k6jkua3.fgh2f4.3w
		+43.a3i3j2k6j2k6jkua4.f2ghf6.4w38.a3i4j2k5j2k7jkua5.2fghf9.4w34.a3i4j2k5j2k7jkua7.fghf46.a3i4j2k6j2k7jkua7.fghf45.a3i4j2k6j2k7jkua8.fghf43.a4i3j2k7j2k7jkua9.fghf42.a4i3j2k
		+7j2k7jkua10.fgh2f40.a4i4j2k6j2k8jkua10.f2gha39.a4i4j2k6j2k8jkua11.2faea37.a4i4j2k7j2k8jkua13.a2e2a35.a4i4j2k7j2k8jkua14.a2ed3a32.a4i4j2k7j3k8jkua14.a2e3d8a24.a4i4j2k7j3k8
		+jkua15.2a6d3c2ba23.a4i4j2k7j3k8jkua17.3a2d3c3ba22.a4i4j3k7j2k9jkua20.4a2b2a23.a4i4j3k7j2k9jkua24.2a25.a4i5j2k7j3k9jkua51.a4i5j2k7j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k
		+9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j3k10jkua47.a5i5j2k9j3k10jkua45.a5i
		+5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a4ia4ja2k2ja4ja2j2ka4ja4jajkua44.aia2iaja2jaka2jaja2j
		+aja2kaja2jaja2jajaua44.aiai2ajaj2akak2ajaj2ajak2ajaj2ajaj2ajaka45.2aia.2aja.2aka.2aja.2aka.2aja.2aja.2aka47.a4.a4.a4.a4.a4.a4.a4.a108./615.12a71.a2b2c7de5a67.a2b2c8d4e2a6
		+6.2a2b5a2c4d3ea64.fgh2a5.5a2d2ea64.fghf11.2ad2ea63.fghf13.a2ea63.fghf14.aea63.fghf15.a64.fghf80.fghf80.fghf6.2a72.fghf5.a2ia71.fghf4.ai2jia70.fghf3.ai4jia69.fghf2.ai6jia6
		+8.fghf.ai8jka67.fghfai6j4lka66.fghui6j6lka65.fghui5j7lka65.fgui5j5lmnlka65.fgui5j8lka65.fgui5j4lm3lka65.fguk6j6l2ka65.fguk7j4l2ka66.fghu2kjk2j6oa67.fghfak2a2o5pq2a66.fghf
		+.2ao4p5qra65.fghf2ao2p7q3ra8.w.w53.fghopo2p7q2roa8.w3xw52.fgo2po7q3or2o7.w2xn2xw51.fgop2qo5ro2pq3o3a5.w3xw52.fop4q5op3qr5q3a3.w.w53.fo9qo2q4r5qpqa58.for8qt7o2ro2qoa58.fo2
		+r9q2o2ro3ar2oa59.fgo2r10q2roa2.3a60.fgho11r2oa66.fg2u13o5a62.fu3i2j2k5jk5jkua61.u3i3jk5j2k5jkua61.u3i3j2k5jk6jkua60.u3i3j2k5jk6jkua59.a3i3j2k5j2k6jkua59.a3i3j2k6j2k6jkua5
		+8.a3i3j2k6j2k6jkua57.a3i4j2k5j2k7jkua57.a3i4j2k5j2k7jkua57.a3i4j2k6j2k7jkua56.a3i4j2k6j2k7jkua55.a4i3j2k7j2k7jkua55.a4i3j2k7j2k7jkua55.a4i4j2k6j2k8jkua54.a4i4j2k6j2k8jkua
		+53.a4i4j2k7j2k8jkua53.a4i4j2k7j2k8jkua53.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua52.a4i4j2k7j3k8jkua51.a4i4j3k7j2k9jkua51.a4i4j3k7j2k9jkua51.a4i5j2k7j3k9jkua50.a4i5j2k7j3k9jku
		+a49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j2k8j3k9jkua49.a4i5j3k8j2k10jkua48.a4i5j3k8j2k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i4j3k8j3k10jkua47.a5i5j2k9j
		+3k10jkua46.a5i5j2k9j3k10jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k8j3k11jkua45.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua44.a5i5j3k9j3k11jkua43.a2ia2i2ja2j2ka4ja4j
		+a3kja4ja4jaua43.a2iaia2jaja2kaja2jaja2jakakjaja2jaja2jaua43.ai2aiaj2ajaj2akaj2ajaj2akak2ajaj2ajaj2aka43.aia.2aja.2aja.2aja.2aja.2aka.2aja.2aja.a45.a4.a4.a4.a4.a4.a4.a4.a2
		+81.
		wolf|34|21|18|14.5|a17171E,b898D9A,cABABAE,d5E606D,e41424F,fD8BE67,g15111A,hCBCED6,i1A1418,j888993,kFFFFFF,l8C464E|idle:0;walk:1,2,3,4;strike:5
		+21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12
		+.a2d11h2d2a16.a2be8je2beda16.abd4e5aebd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a5ea5.a4ea17.2a.2a7.4a46./21.a3.a10.2a16.aba.aba8.a2c
		+a14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a17.2e2be4je2be3a
		+2da15.aebde4aebde2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.a3ea4.a2ea2.a2ea16.aea6.2a4.2a44./2.2a16.aba.aba8.a2ca14.abdbabd
		+ba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a17.2ad8je2be18.a2b4e5aebded
		+a16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abd3ea5.a4ea16.a2e3a7.a3ea17.2a12.2a46./21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3b
		+c3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a14.a2bead9jde2ba14.abda.2a4e3a3ebda14.abda3
		+.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.a2ea3.a2ea3.a4ea15.2a5.2a5.4a46./2.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba
		+.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10be9b3ha5.aec12bebd5b4hia6.e14bed3b6ha7.a15be4d2j3a8.ad15b3e3a12.a2d11h2d2a16.a2be9jd2eda16.abd4e5ae2b2ea16.abdedea5.abd2ea16.abde
		+dea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a3edea5.abd2ea17.3a2ea5.a3ea21.2a7.2a48./23.a3.a8.2a18.aba.aba6.a2ca16.abdbabdba4.ac2bca15.a3bc3bca3.ac4ba.12a.a2c6bc2a2
		+.ad3b2e12cec5bfg3bha2.adbe2c12be9b3hi3.aec14bebd5bkhkhka4.e16bed4b5la5.a17be2d2bkhkhka5.ad16bdea2d3hja7.a2d11h2d2a2.6a7.a2bed9jde2ba15.abd3a4e4a2ebda15.abda2.adea4.aebda1
		+5.abda2.adea4.aebda15.abda2.adea4.aebda15.abda2.adea4.aebda15.a2ea2.a2ea4.a3ea16.2a4.2a6.aea46.
		wolf_1|34|21|18|14.5|a231A14,bB8976E,cC9AD88,d836950,e5F4A3B,f291D18,g15111A,hB85B5B,iE5D4B5,j864343,k1A1418,l9F8F7E,mFFFFFF,n8C464E|idle:0;walk:1,2,3,4;strike:5
		+21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a1
		+2.a2d11i2d2a16.a2be8le2beda16.abd4e5aebd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a5ea5.a4ea17.2a.2a7.4a46./21.a3.a10.2a16.aba.aba8.a2
		+ca14.abdbabdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a17.2e2be4le2be
		+3a2da15.aebde4aebde2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.aebda4.abda2.adea15.a3ea4.a2ea2.a2ea16.aea6.2a4.2a44./2.2a16.aba.aba8.a2ca14.abdba
		+bdba6.ac2bca13.a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a17.2ad8le2be18.a2b4e5aeb
		+deda16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.abd3ea5.a4ea16.a2e3a7.a3ea17.2a12.2a46./21.a3.a10.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.
		+a3bc3bca5.ac4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a14.a2bead9lde2ba14.abda.2a4e3a3ebda14.a
		+bda3.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.abda3.adea3.adebda14.a2ea3.a2ea3.a4ea15.2a5.2a5.4a46./2.2a16.aba.aba8.a2ca14.abdbabdba6.ac2bca13.a3bc3bca5.a
		+c4ba.11ae2c6bca5.ad3b2e10cec5bfg3ba5.adbe2c10beh8b3ia5.aec12behj5b4ika6.e14bed3b6ia7.a15be4d2l3a8.ad15b3e3a12.a2d11i2d2a16.a2be9ld2eda16.abd4e5ae2b2ea16.abdedea5.abd2ea16
		+.abdedea5.abd2ea16.abdedea5.abd2ea16.abdedea5.abd2ea16.a3edea5.abd2ea17.3a2ea5.a3ea21.2a7.2a48./23.a3.a8.2a18.aba.aba6.a2ca16.abdbabdba4.ac2bca15.a3bc3bca3.ac4ba.12a.a2c6
		+bc2a2.ad3b2e12cec5bfg3bia2.adbe2c12beh8b3ik3.aec14behj5bmimima4.e16bed4b5na5.a17be2d2bmimima5.ad16bdea2d3ila7.a2d11i2d2a2.6a7.a2bed9lde2ba15.abd3a4e4a2ebda15.abda2.adea4.
		+aebda15.abda2.adea4.aebda15.abda2.adea4.aebda15.abda2.adea4.aebda15.a2ea2.a2ea4.a3ea16.2a4.2a6.aea46.
		wraith|28|28|24|13|a150F1E,b826AA1,c5F4981,d100C16,eEFE9AF,fD9C769,g42325C,h2F2443,i9893AF,jD5D1E4|idle:0;fly:0,1;strike:2
		+37.6a20.2a6b2a17.a2b7cba15.ab11ca14.ab2c6d3ca13.ab3c5ded3ca12.ab3cdf3dfd3ca12.ab4c5d4cga12.a5c3d5c2ga11.a13cga11.ab13c2ga10.ab13cga11.a14cga11.a14c2ga10.a14cga11.ag13c2ga
		+10.ag13c2ga11.ag12c2ga11.ag11c2ga12.ag2ca5ca2c2ga13.agc2a3c2ac2ga14.aga.agcga.aga16.a2.ag2a3.a21.a100./65.6a20.2a6b2a17.a2b7cba15.ab11ca14.ab2c6d3ca13.ab3c5ded3ca12.ab3cd
		+f3dfd3ca12.ab4c5d4cga12.a5c3d5c2ga11.a13cga11.ab13c2ga10.ab13cga11.a14cga11.a14c2ga10.a14cga11.ag13c2ga10.ag13c2ga11.ag12c2ga11.ag12c2ga12.ag2ca5cac2ga13.agca.a3c2acga15.
		+aga.agca2.aga16.a3.aga3.a22.a70./38.6a20.2a6b2a17.a2b7cba15.ab11ca14.ab2c6d3ca13.ab3c5ded3ca12.ab3cdf3dfd3ca12.ab4c5d4cga12.a5c3d5c2gh11.a7c4h2cghia9.ab6chb3c5hia8.ab6ch6
		+c2jhia8.a7chg4c2jijh9.a8ch3g2hjhja9.a9c3h2ch2a10.ag13c2ga10.ag13c2ga11.ag12c2ga11.ag11c2ga12.ag2ca5ca2c2ga13.agc2a3c2ac2ga14.aga.agcga.aga16.a2.ag2a3.a21.a99.
		zombie|34|34|31|13.5|a17191E,b37462E,c242E1E,d9AB978,e7FA964,f3E5A3E,g5A794D,h1A1418,iD87067,j381E26,kE7E2C9,l6FA098,m4A8382,n365C60,o294248,p6C719B,q494F7D,r343858,s262940,t494048,u3A3238,v2A242C,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4
		+m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrs2rsa24.ap2qrs2rsa25.a2qrs2rsa25.a2qrs2rsa25.aq2rsr2sa
		+25.aeg2agfa26.aeg2agfa25.a4ts3ua24.a4tvs2uwa24.4as4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2
		+gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.a2p
		+2qrsrsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega
		+23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa2
		+5.a3on3oa25.spoq2orosa24.a6srsa24.ap2qrsqrsa25.a2qrsq2rsa24.a2qr2a2rsa24.aq2r2agfsa24.aega.agfa25.aeg2a3ua24.a4ts3uwa23.a4tvs3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.a
		+c2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m
		+4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrsq2rsa22.ap2qr2aq2rsa22.a2q2ra.a2r2sa20.ap2qra2.aq2rsa20.a2qra4.a2rsa20.aega5.agfa21.aeg
		+a5.agf2a20.a3ta4.a4ua19.a3tva3.a3uwa20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.
		+a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.spoq2orosa24.a6srsa24.a2pqrs2r
		+sa25.ap2qrsrsa26.a2qrsrsa26.aegr3sa26.aegsgfa26.a3tsgfa26.a3tvs2ua26.2a2s3uwa28.5a50./13.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2
		+a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na23.an5m2na24.a2n4m2na25.a2n3mnoa25.anomnmoa26.3on4o26.aoq2
		+oroa26.a6srsa24.ap2qrs2rsa24.ap2qrsrsa26.a2qr3sa26.a2qr2sa27.aq2rsa28.aegsa29.aegsa28.a4tsa27.a4tvsa27.2a3sa53./50.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.a
		+cg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa17.an3mf3no2e2d3f17.a2n3m3f2g3edfga17.a2n3mn
		+ofa2g2e2ga16.aonomnmoa2.2agaga16.ap3on3oa4.a.a17.spqoq2osoa24.a6srsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52.
		zombie_1|34|34|31|13.5|a17191E,b837451,c574D36,dC8B98B,eBCA97D,f5A5848,g81785D,h1A1418,iD6AA63,j381E26,kE7E2C9,lB1A17D,m9D8761,n6C5E49,o4B4238,p918778,q75694F,r504839,s37312C,t494048,u3A3238,v2A242C,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4
		+m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrs2rsa24.ap2qrs2rsa25.a2qrs2rsa25.a2qrs2rsa25.aq2rsr2sa
		+25.aeg2agfa26.aeg2agfa25.a4ts3ua24.a4tvs2uwa24.4as4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2
		+gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.a2p
		+2qrsrsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega
		+23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa2
		+5.a3on3oa25.spoq2orosa24.a6srsa24.ap2qrsqrsa25.a2qrsq2rsa24.a2qr2a2rsa24.aq2r2agfsa24.aega.agfa25.aeg2a3ua24.a4ts3uwa23.a4tvs3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.a
		+c2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m
		+4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrsq2rsa22.ap2qr2aq2rsa22.a2q2ra.a2r2sa20.ap2qra2.aq2rsa20.a2qra4.a2rsa20.aega5.agfa21.aeg
		+a5.agf2a20.a3ta4.a4ua19.a3tva3.a3uwa20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.
		+a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.spoq2orosa24.a6srsa24.a2pqrs2r
		+sa25.ap2qrsrsa26.a2qrsrsa26.aegr3sa26.aegsgfa26.a3tsgfa26.a3tvs2ua26.2a2s3uwa28.5a50./13.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2
		+a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na23.an5m2na24.a2n4m2na25.a2n3mnoa25.anomnmoa26.3on4o26.aoq2
		+oroa26.a6srsa24.ap2qrs2rsa24.ap2qrsrsa26.a2qr3sa26.a2qr2sa27.aq2rsa28.aegsa29.aegsa28.a4tsa27.a4tvsa27.2a3sa53./50.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.a
		+cg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa17.an3mf3no2e2d3f17.a2n3m3f2g3edfga17.a2n3mn
		+ofa2g2e2ga16.aonomnmoa2.2agaga16.ap3on3oa4.a.a17.spqoq2osoa24.a6srsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52.
		zombie_2|34|34|31|13.5|a17191E,b324955,c213038,d93B6A4,e71A09D,f3A5357,g507272,h1A1418,i78D6DF,j381E26,kE7E2C9,l789179,m506D59,n394C44,o283636,p677186,q3F4C5F,r2C3544,s212633,t494048,u3A3238,v2A242C,w1E1A20|idle:0;walk:1,2,3,4;windup:5;strike:6
		+14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4
		+m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrs2rsa24.ap2qrs2rsa25.a2qrs2rsa25.a2qrs2rsa25.aq2rsr2sa
		+25.aeg2agfa26.aeg2agfa25.a4ts3ua24.a4tvs2uwa24.4as4a50./14.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2
		+gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.a2p
		+2qrsrsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega
		+23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa2
		+5.a3on3oa25.spoq2orosa24.a6srsa24.ap2qrsqrsa25.a2qrsq2rsa24.a2qr2a2rsa24.aq2r2agfsa24.aega.agfa25.aeg2a3ua24.a4ts3uwa23.a4tvs3a25.5a54./14.5a28.a5b2a25.a8ba23.ac3b5da23.a
		+c2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m
		+4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.apoq2oro26.a6srsa24.ap2qrsq2rsa22.ap2qr2aq2rsa22.a2q2ra.a2r2sa20.ap2qra2.aq2rsa20.a2qra4.a2rsa20.aega5.agfa21.aeg
		+a5.agf2a20.a3ta4.a4ua19.a3tva3.a3uwa20.4a5.4a48./48.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.acg2e2hih2ea22.a2g7ega23.ag2ejkjkja24.a2ge5ja23.2a2fgkjk2gf2a20.
		+a3l7f2ega18.a2l2m11fa16.a2l2mf4lmfe3defa15.al3mf4m2n5ega15.a4mf3nof2g2ega2ga14.an4m4f.5ag2a15.a2n4m2na6.a18.a2n3mnoa25.onomnmoa25.a3on3oa25.spoq2orosa24.a6srsa24.a2pqrs2r
		+sa25.ap2qrsrsa26.a2qrsrsa26.aegr3sa26.aegsgfa26.a3tsgfa26.a3tvs2ua26.2a2s3uwa28.5a50./13.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fef.a21.acg2e2hih2e2fa20.a2g7e2f2
		+a21.ag2ejkj2fdeaga20.f2gej2fd2e2ga20.2o4flm2eg2a20.a2l2f2lmnfga21.a2lf2l2mnf2a21.a2lmfm2nofa23.al3m4fna23.a7m2na23.an5m2na24.a2n4m2na25.a2n3mnoa25.anomnmoa26.3on4o26.aoq2
		+oroa26.a6srsa24.ap2qrs2rsa24.ap2qrsrsa26.a2qr3sa26.a2qr2sa27.aq2rsa28.aegsa29.aegsa28.a4tsa27.a4tvsa27.2a3sa53./50.5a28.a5b2a25.a8ba23.ac3b5da23.ac2b2d4ea23.acb2e4fea23.a
		+cg2e2hih2ea22.a2g7ega23.ag2ekjkjka24.a2ge5ja22.2af2ge5ja21.a3l2fgkjk2ga20.a2l3m6fa20.a2l3m7f21.al3mf2lm2f2ea.a18.a4mf3mne3fafa17.an3mf3no2e2d3f17.a2n3m3f2g3edfga17.a2n3mn
		+ofa2g2e2ga16.aonomnmoa2.2agaga16.ap3on3oa4.a.a17.spqoq2osoa24.a6srsa25.ap2qr2sa27.a2q2rsa27.sp2qrs28.as2qra28.asega29.aseg2a28.as4ta27.as3tva28.a3sa52.
		// </art:creatures>
		"""

	/// A block is one line: "name|flips|colours|pixels" (16 x 16). The flips say how the land painter
	/// may vary the block from place to place so a wall of it is not wallpaper: "h" mirrored, "hv" also
	/// turned top to bottom, nothing for a block that must always be drawn as it is.
	static let tileText: String = """
		// <art:tiles> written by tools/art/build.py pack from tools/art/tiles: change the drawings, not this
		amethyst|hv|a8D8D97,bA3A3AD,c604180,d777783,eD8BDF2,f5C5C69,gFFFFFF,h996EC6|4a3b12abcb4a2d7acec2a2d2fc4afceghcad2fcecb2ace4hcadceghc2adc3hc4achc4adchc2b4ac7ac3b4ad3a2d3a2b2ac2dfd2a2fd5acecfd3adfcd3aceghc5acec2ace4hc2baceghcbac3hc3b2achc3bachcab5ac2ab3acd13ad2fd4a
		ashStone|hv|a493B47,b5B4A59,c3B2F3A,d2C212A|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		birchLeaves|h|a779556,b97B26B,c617C46,d50693C|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		birchLog||a79736B,bFFFFFF,cE5E2D8,dBCB6AC,e3A3632|a2b10c2d2a2b2c3e5c2d2a2b10c2d2ab8c3e2d2a2b10c2d2a2b10c2d2ab3e8c2d2a2b10c2d2a2b5c2e3c2d2a2b10c2d2ab11c2d2a2bc2e7c2d2a2b8c2e2d2a2b10c2d2a2b5c3e2c2d2a2b10c2da
		birchLogBlock||a79736B,bFFFFFF,cE5E2D8,dBCB6AC,e3A3632|a2b10c2d2a2b2c3e5c2d2a2b10c2d2ab8c3e2d2a2b10c2d2a2b10c2d2ab3e8c2d2a2b10c2d2a2b5c2e3c2d2a2b10c2d2ab11c2d2a2bc2e7c2d2a2b8c2e2d2a2b10c2d2a2b5c3e2c2d2a2b10c2da
		brick||aB57363,b898583,cBE7E6A,d9E5F53,eA7685A,f824B44|7ab7cb7db7eb7fb7f17b3cb7ab4c3eb7db4e3fb7fb4f16b7ab7ab7db7db7fb7f17b3ab7cb4a3db7eb4d3fb7fb4f16b
		chest||a291F18,bC5A374,cA9895F,d856A46,e898D96,fD3BD68,gECE0A2,h685137|81.14a.a14b2a14c2a14d2a6e2f6e2a6cfg6c2a14c2acd10cdc2a14c2a14ha.14a.
		coal|hv|a8D8D97,bA3A3AD,c16161C,d777783,e4A4A55,f2A2A32,g5C5C69|4a3b12ab3c3a2d7ace2fc2d2gd4agdc5fcgd2cb2a2gdc4fcdcefc2adgda4c2ac2fc3ad3a2b4a2c4a2ca3b4ad3adcefc2b3a2dgd2agc3fc3ad3c3adgc2fc3ace2fc3a2d2c4ac5fc5ab4ac3fc5a3b4a3c7ab3a2d13ad2gd4a
		copper|hv|a8D8D97,bA3A3AD,c7F573D,d777783,eDAA77C,fB9825C,g5C5C69|4a3b11a3cb4a2d5ac2efc2a2dg2c4ace3fcadgcefcb2ac5fcadc2fcb2adc3fc4a2cb4ad3c2b13a3ba3cd3a2d3a2bac2efcd2a2g2c4ace4fcadcefc3ac5fc2ac2fc4ac4fc3a2cab4a4cb5a3b5ab8a2c2a2d9acefcd2gd4a
		crackedBrick||aA19080,b685A4E,cAB9989,d8A7969,e938272,f6D5E52|7ab7cb7db7eb7fb7f17b3cb7ab4c3eb7db4e3fb7fb4f16b7ab7ab7db7db7fb7f17b3ab7cb4a3db7eb4d3fb7fb4f16b
		crystalOre|hv|a5E6676,b72798B,c458288,d4D5464,eE5FAFA,f90DDD7,g3C4250|4a3b12a2b2c3a2d8acefc2d2gd4agdacefcd2gd2cb2a2gce2fca2dcefc2adgc2fc4acefc3ada2c2b2ace2fc6a3b2ac2fc2a2da2c2b3ad2cd2a2gcefc3ad2gd3adgcefc3a2cd5ace2fc2acefca2b2ac2fcb2acefc3b3a2c3bce2fcb8abac2fc13a2cgd4a
		deepRock|hv|a3E3945,b4E4857,c322D39,d25202C|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		diamond|hv|a8D8D97,bA3A3AD,c42828D,d777783,eB6EDF1,f5C5C69,gFFFFFF,h6AC4C9|4a3b12abcb4a2d7acec2a2d2fc4afceghcad2fcecb2ace4hcadceghc2adc3hc4achc4adchc2b4ac7ac3b4ad3a2d3a2b2ac2dfd2a2fd5acecfd3adfcd3aceghc5acec2ace4hc2baceghcbac3hc3b2achc3bachcab5ac2ab3acd13ad2fd4a
		dirt|hv|a82614A,b70513E,c916F54,d5A4032,eA88A6A|6a2b10ac4a2b15ad3ac19a2b9a2b4abd4ae4a2b15ad7ac19a2b15abd2ac4a2b15abd22ae4ac22a2b5abd8a2b3a2b
		dryGrass|h|aCEC581,bB3A966,c928751,d70673E,e82614A,f70513E,g5A4032,h916F54,iA88A6A|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		emberOre|hv|a493B47,b5B4A59,c935940,d3B2F3A,eDFC178,fD28D5D,g2C212A|4a3b11a3cb4a2d5ac2efc2a2dg2c4ace3fcadgcefcb2ac5fcadc2fcb2adc3fc4a2cb4ad3c2b13a3ba3cd3a2d3a2bac2efcd2a2g2c4ace4fcadcefc3ac5fc2ac2fc4ac4fc3a2cab4a4cb5a3b5ab8a2c2a2d9acefcd2gd4a
		flowerR||a1C1820,bC96763,cE1897E,dDFCB78,e5E9A51,f3E733F|54.2a13.a2ba11.ab2cba9.abc2dcba9.ab2cba11.a2ba13.aea.2a8.3ae2a2ea6.a2eaeaefa8.af3e2a10.afea13.aea13.aea7.
		flowerY||a1C1820,bCDB25F,cE4D486,dBE9056,e5E9A51,f3E733F|54.2a13.a2ba11.ab2cba9.abc2dcba9.ab2cba11.a2ba13.aea.2a8.3ae2a2ea6.a2eaeaefa8.af3e2a10.afea13.aea13.aea7.
		furnace||a777783,bA3A3AD,c5C5C69,d221D24,eC37756,fD49E61,gDCBF71,hEEE3A8,i8D8D97|.14a.a14b2ab12ac2aba10cac2abac8dcac2abac2d5edcac2abacdef2gfedcac2abacdeg2hgedcac2abac2de2fe2dcac2abac8dcac2aba10cac2ab12ac2abaididididi2ac2abaididididi2ac2a14ca.14a.
		gold|hv|a8D8D97,bA3A3AD,c967B45,d777783,eFFFFFF,fE9DB96,gCFB764,h5C5C69|4a3b12a2cb4ade6acfgc2a2defe4ahc2gc2ad2he2ab2a2h2c4a2d2a2b2adhd5a2ca2b4ad3a2bcfgc5ae3a3bc3gc3aefe2a2b2ac2gcd2ahed6ad2cd3ad2hd2c3adhd5a2dcfgc2ad2a2cb4ac3gc3acfgc5a3c4ac2gc6ab3a2da2c10ad2hd4a
		grass|h|a8BAF65,b66924F,c497341,d345734,e82614A,f70513E,g5A4032,h916F54,iA88A6A|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		iron|hv|a8D8D97,bA3A3AD,c7B5B50,d777783,eDDBEA2,fBB967D,g5C5C69|4a3b10a4cb4a2d5ac2efc2a2d2g2c3ace3fcad2gcefc2agc3fc2adce2fc2adg3c4ac2fc4ad3a2b3a2c8a3b4ad3a2d2a4c2a2dgd2a2gdc2e2fcd2gd2cad2gce3fcdgdcefca2dac4fc2ac2fc5a4c3ab2c2a2ca3b5ab3acefcab3a2d5ac2fc4ad2gd4a
		jungleGrass|h|a79C470,b519C57,c3A7547,d2A5537,e534234,f46372A,g372A21,h61513F,i6A5A48|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		jungleLeaves|h|a43804D,b659B58,c366840,d2D5636|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		jungleLog||a2F2819,b7E6E4A,c625438,d463B26,e493F2A|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		jungleLogBlock||a2F2819,b7E6E4A,c625438,d463B26,e493F2A|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		leaves|h|a557F47,b739C59,c42663B,d365733|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		log||a3C2C21,b907253,c735840,d58412F,e5A4332|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		logBlock||a3C2C21,b907253,c735840,d58412F,e5A4332|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		mossBrick||a8BA174,b4D5C41,c96AC7E,d73885F,e7D9269,f576B4A|7ab7cb7db7eb7fb7f17b3cb7ab4c3eb7db4e3fb7fb4f16b7ab7ab7db7db7fb7f17b3ab7cb4a3db7eb4d3fb7fb4f16b
		mossGrass|h|a96A765,b75884D,c586A3B,d3E4D2D,e534234,f46372A,g372A21,h61513F,i6A5A48|2ab4ab4ab3aba4ba4ba22bc5bc6bcb3c3b2c5b3cde2cbcde2c2bcdcd3e3c3ed2cd7ed6ed12e2f15efg2eh4e2f15efg22ei4eh22e2f5efg8e2f3e2f
		mud|hv|a534234,b46372A,c61513F,d372A21,e6A5A48|6a2b10ac4a2b15ad3ac19a2b9a2b4abd4ae4a2b15ad7ac19a2b15abd2ac4a2b15abd22ae4ac22a2b5abd8a2b3a2b
		mythril|hv|a8D8D97,bA3A3AD,c534B98,d777783,eB5ADEF,f7F76DE,g5C5C69|4a3b12a2b2c3a2d8acefc2d2gd4agdacefcd2gd2cb2a2gce2fca2dcefc2adgc2fc4acefc3ada2c2b2ace2fc6a3b2ac2fc2a2da2c2b3ad2cd2a2gcefc3ad2gd3adgcefc3a2cd5ace2fc2acefca2b2ac2fcb2acefc3b3a2c3bce2fcb8abac2fc13a2cgd4a
		palmLog||a5A4733,bB2966E,c957B58,d776043,e7D6549|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		palmLogBlock||a5A4733,bB2966E,c957B58,d776043,e7D6549|a2b2cd3cd2c3e2a2b2cd6cd2e2ab7cd2cd2e2a2bcd4cd3c2e2a2bcd8c2e2a2bcd2cd4cd2e2ab5cd4cd2e2a2b4cd2cd2c2e2a2b2cd4cd2c2e2a2b2cd7c2e2ab3cd2cd3cd2e2a2b5cd3cd2e2a2bcd3cd4c2e2a2bcd6cdc2e2ab5cd3cdc2e2a2b4cd5c2ea
		pineLeaves|h|a3B6554,b558469,c305345,d27463A|3a2b13a2b7ac13a3c2a2b4ac5ac2a2b4a3c2.13ac3.9ab4ad.3ac4a2b9a3ca2b11ac10a2b9ac4ab9a3c8ac2.3ac9a2c3.5a2b7ac2.4ab5a2b11ac2ab2a
		planks||aC7A87D,b765C40,cB19068,d56402D,e9C7E58|5ab10a4cdb4c3e4c3ecb10c16b12ab3a3c3e5cdb11c2e2cb3c16b2ab13acdb4c3e8cb9c3ec16b9ab6a2c3e3cdb15cb2c3ec16b
		saltpeter|hv|a8D8D97,bA3A3AD,c88857B,d777783,eFFFFFF,fD9D5CA,g5C5C69|4a3b11a5c3a2d5ac2e4fcd2gd4ag6cd2gd2cb2a2gd5ad2cefc2adgd4a2c2e2fc3ad3abce4f2c6a3b5c3a2d3a2b3a2dgd2a2gd4c2ad2gd3adgc2e2f2cdgd5ace6fc3a2c3a7c2a2cefc4a3b3ace3fc5ab3a2d4c9ad2gd4a
		sand|hv|aD6C590,bE5D7A7,cAF9869,dC6B27C|18a5b7ac4a4d3a3b5ac7a3d19a3b5ac4a3b3d10a3d6a4b7ac4a4d2ac22a3b13a3d5ac14a4b2ac9a4d6a3b7ac5a3d9a
		sandstone|hv|aC3AD7C,bD3BF8F,cB09A6B,d998459|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		silver|hv|a8D8D97,bA3A3AD,c777783,d6A7381,eFFFFFF,fC2C9D5,g5C5C69|4a3b12a3b4ac2d11ac2defd3agc4a2de2fdab2a2gca2de2fd2a2b2acgcde2fd3a2b4acadfdb13ad2b4a2d2a2c3a2b3a2ded2a2gc5a2defd3acg2d2a2de2fd5adef2de2fd3a2b2adf2e2fd4a3b3a5d5ab8ab3a2c13ac2gc4a
		slate|hv|a5E6676,b72798B,c4D5464,d3C4250|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		snow|hv|aF0F6FC,bFFFFFF,cC1D1E6,dD8E4F3|18a5b7ac4a4d3a3b5ac7a3d19a3b5ac4a3b3d10a3d6a4b7ac4a4d2ac22a3b13a3d5ac14a4b2ac9a4d6a3b7ac5a3d9a
		stone|hv|a8D8D97,bA3A3AD,c777783,d5C5C69|4a3b12a3b4a2c12a2c2dc4adc5ac2dc2ab2a2dc5a2c2a2b2acdc8a2b4ac3a2b13a3b4ac3a2c3a2b3a2cdc2a2dc6ac2dc3ac2dc5acdc5a2c6ac3a2b6ab6a3b5a3b5ab8ab3a2c13ac2dc4a
		tallGrass||a8BAF65,b66924F,c497341|114.a9.a5.b3.a5.ba3.ab2.ab2.a2.ab3.ab2.ab.ab.a2b.2a2ba.2b.ab.a2baba3ba2ba2ba21bc2bc2bc3bc2bc2b16c
		tin|hv|a8D8D97,bA3A3AD,c7D8691,d777783,eF1F5F8,fC6CFD7,g5C5C69|4a3b11a3cb4a2d5ac2efc2a2dg2c4ace3fcadgcefcb2ac5fcadc2fcb2adc3fc4a2cb4ad3c2b13a3ba3cd3a2d3a2bac2efcd2a2g2c4ace4fcadcefc3ac5fc2ac2fc4ac4fc3a2cab4a4cb5a3b5ab8a2c2a2d9acefcd2gd4a
		torch||a1C1820,bE2CD81,cEEE3A8,dFFFFFF,eD49E61,f8E6E4D,g684E37|23.a14.aba12.abcba11.abdcba9.aec2dcea8.aecd2cea9.ae2cea11.a2ea12.afga12.afga12.afga12.afga12.afga12.afga12.afga6.
		voidOre|hv|a493B47,b5B4A59,c65418B,d3B2F3A,eE0B2F0,fAB6FDB,g2C212A|4a3b12a2b2c3a2d8acefc2d2gd4agdacefcd2gd2cb2a2gce2fca2dcefc2adgc2fc4acefc3ada2c2b2ace2fc6a3b2ac2fc2a2da2c2b3ad2cd2a2gcefc3ad2gd3adgcefc3a2cd5ace2fc2acefca2b2ac2fcb2acefc3b3a2c3bce2fcb8abac2fc13a2cgd4a
		workbench||a98A0AD,bCED4DD,c898D96,dC2C8D1,e9C7E58,fC7A87D,gB19068,h765C40|52.ab5.3c5.a2ba4.cdc6.2e6.e3.16f16g16h.eh10.eh2.eh.8e.eh2.eh.8h.eh2.eh10.eh2.eh10.eh2.eh10.eh2.eh10.eh.
		// </art:tiles>
		"""

	/// Colours of a picture: "aF0A0B0,b1E1418" gives each letter its colour
	static func palette(_ s: Substring) -> [UInt8: UInt32] {
		var out: [UInt8: UInt32] = [:]
		for e in s.split(separator: ",") {
			guard let k = e.utf8.first, let v = UInt32(e.dropFirst(), radix: 16) else { continue }
			out[k] = v
		}
		return out
	}

	/// Unpacks one picture of w x h pixels
	static func unpack(_ s: Substring, _ w: Int, _ h: Int, _ pal: [UInt8: UInt32]) -> PixelBuf {
		var b = PixelBuf(w: w, h: h)
		var lut: [UInt32] = [UInt32](repeating: 0, count: 128)
		for (k, v) in pal where k < 128 { lut[Int(k)] = 0xFF000000 | v }
		let n: Int = w * h
		var i: Int = 0
		var run: Int = 0
		for c in s.utf8 {
			if c >= 48 && c <= 57 {
				run = run * 10 + Int(c) - 48
				continue
			}
			let count: Int = max(1, run)
			run = 0
			let v: UInt32 = c == 46 ? 0 : lut[Int(c & 127)]
			var k: Int = 0
			while k < count && i < n {
				b.px[i] = v
				i += 1
				k += 1
			}
		}
		return b
	}
}

/// One creature's drawing as ArtSheet keeps it (its frames are unpacked when first asked for)
struct SheetArt {
	var w: Int
	var h: Int
	var foot: Int
	var cx: Double
	var pal: [UInt8: UInt32]
	var poses: [String: [Int]]
	var packed: [Substring]
}

enum CreatureSheet {
	static let arts: [String: SheetArt] = parse(ArtSheet.creatureText)

	static func parse(_ s: String) -> [String: SheetArt] {
		var out: [String: SheetArt] = [:]
		var name: String = ""
		var cur: SheetArt? = nil
		var body: String = ""
		func close() {
			guard var a = cur else { return }
			a.packed = Substring(body).split(separator: "/")
			out[name] = a
			cur = nil
			body = ""
		}
		for raw in s.split(separator: "\n") {
			let line: Substring = raw.drop(while: { (c: Character) -> Bool in c == "\t" || c == " " })
			if line.isEmpty || line.hasPrefix("//") { continue }
			if line.hasPrefix("+") {
				body.append(contentsOf: line.dropFirst())
				continue
			}
			close()
			let f: [Substring] = line.split(separator: "|", omittingEmptySubsequences: false)
			guard f.count >= 7, let w = Int(f[1]), let h = Int(f[2]), let foot = Int(f[3]), let cx = Double(f[4]) else { continue }
			var poses: [String: [Int]] = [:]
			for e in f[6].split(separator: ";") {
				let kv: [Substring] = e.split(separator: ":")
				if kv.count != 2 { continue }
				poses[String(kv[0])] = kv[1].split(separator: ",").compactMap { Int($0) }
			}
			name = String(f[0])
			cur = SheetArt(w: w, h: h, foot: foot, cx: cx, pal: ArtSheet.palette(f[5]), poses: poses, packed: [])
		}
		close()
		return out
	}

	static func has(_ name: String) -> Bool { return arts[name] != nil }

	/// A drawing's frames, unpacked
	static func frames(_ name: String) -> [PixelBuf] {
		guard let a = arts[name] else { return [] }
		return a.packed.map { ArtSheet.unpack($0, a.w, a.h, a.pal) }
	}

	/// How a drawing's frames are used: its poses by name
	static func anim(_ a: SheetArt) -> CreatureAnim {
		var an = CreatureAnim()
		an.walk = a.poses["walk"] ?? []
		if let x = a.poses["alt"]?.first { an.idleAlt = x }
		if let x = a.poses["strike"]?.first { an.attack = x }
		if let x = a.poses["hop"]?.first {
			an.hop = true
			an.hopFrame = x
		}
		if let c = a.poses["fly"] { an.cycle = c }
		for (k, v) in a.poses {
			if let f0 = v.first { an.poses[k] = f0 }
		}
		return an
	}

	/// A creature's look from its drawing (nil when it has not been drawn by hand yet)
	static func look(_ name: String) -> CreatureLook? {
		guard let a = arts[name], !a.packed.isEmpty else { return nil }
		return CreatureLook(frames: frames(name), anim: anim(a), scale: fineScale, foot: a.foot + 1, cx: a.cx, fine: true)
	}
}

/// The hand-drawn blocks, by tile number
enum TileSheet {
	static let parsed: ([UInt8: PixelBuf], [UInt8: Int]) = parse(ArtSheet.tileText)
	static var bufs: [UInt8: PixelBuf] { return parsed.0 }
	/// how each may be varied from place to place: bit 1 mirrored, bit 2 turned top to bottom
	static var flips: [UInt8: Int] { return parsed.1 }

	static func parse(_ s: String) -> ([UInt8: PixelBuf], [UInt8: Int]) {
		var byName: [String: Tile] = [:]
		for t in Tile.allCases { byName[String(describing: t)] = t }
		var out: [UInt8: PixelBuf] = [:]
		var fl: [UInt8: Int] = [:]
		for raw in s.split(separator: "\n") {
			let line: Substring = raw.drop(while: { (c: Character) -> Bool in c == "\t" || c == " " })
			if line.isEmpty || line.hasPrefix("//") { continue }
			let f: [Substring] = line.split(separator: "|", omittingEmptySubsequences: false)
			guard f.count >= 4, let t = byName[String(f[0])] else { continue }
			out[t.rawValue] = ArtSheet.unpack(f[3], tileArtPx, tileArtPx, ArtSheet.palette(f[2]))
			fl[t.rawValue] = (f[1].contains("h") ? 1 : 0) | (f[1].contains("v") ? 2 : 0)
		}
		return (out, fl)
	}
}
