// PIXEL REALM v2, part 1 of 10: utilities, tiles, items, recipes, the older creature pictures made in code, world generation and chunks.
// The game is 10 files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm10.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 3 (a01_artsheet).

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
	/// automation (appended): a signal post that turns its channel on while it has power (and its pulse
	/// wire, if it has one, is on), and a sensor that sends a pulse while a vehicle is near it
	case signalPost, vehicleSensor

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
		signalPost|Signal Post|hard=0.8|solid=0|opaque=0|style=custom|colors=C84A3A
		vehicleSensor|Vehicle Sensor|hard=0.7|solid=0|opaque=0|style=custom|colors=E8C040
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
		signalPost ...rr...,.k.rr.k.,..k..k..,...kk...,...mk...,...mk...,.kkkkkk.,.kmmmmk. k=2E323A m=6A7280 r=E04A3A
		vehicleSensor ...yy...,........,..kkkk..,.k.mm.k.,.km..mk.,.k.mm.k.,..kkkk..,kkkkkkkk k=2E323A m=8A94A4 y=E8C040
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
	/// appended (automation): lets a remote control drive the vehicle, and picks up a signal channel
	case receiver
	var name: String {
		switch self {
		case .receiver: return "Receiver"
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
		case .receiver: return 0.3
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
		case .receiver: return "Lets a remote control drive the vehicle from afar, and picks up a signal channel. Tap it to set it up."
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
	/// appended (automation): a remote control, paired with a vehicle that has a receiver
	case remote

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
		case .remote: return "Remote Control"
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
		case .remote:
			// a hand set with its aerial, a little screen and two buttons
			b.rect(3, 4, 6, 8, 0x3A3F4A); b.rect(3, 4, 6, 1, 0x5A606C); b.rect(4, 5, 4, 3, 0x1A2A2A); b.set(5, 6, 0x50F070)
			b.set(4, 9, 0xE04A3A); b.set(7, 9, 0xE8C040); b.line(8, 4, 10, 0, 0x9AA0AC); b.set(10, 0, 0xE04A3A)
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
		add(.part(.receiver), 1, [(.mat(.copperBar), 3), (.mat(.ironBar), 1), (.mat(.goldBar), 1)], .tinker, .vehicle)
		add(.gadget(.remote), 1, [(.mat(.copperBar), 2), (.mat(.goldBar), 1), (.block(.glass), 1)], .tinker, .tools)
		add(.block(.signalPost), 1, [(.mat(.copperBar), 3), (.mat(.ironBar), 2)], .tinker, .power)
		add(.block(.vehicleSensor), 1, [(.mat(.copperBar), 2), (.mat(.ironBar), 2), (.mat(.amethyst), 1)], .tinker, .power)
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
	case .receiver:
		// a box with a whip aerial and a green lamp
		b.rect(0, 4, 8, 4, 0x4A5060); b.rect(0, 4, 8, 1, 0x6A7080); b.rect(1, 5, 3, 2, 0x1A2A2A); b.set(2, 6, 0x50F070)
		b.line(6, 4, 6, 0, 0x9AA0AC); b.set(5, 1, 0x9AA0AC); b.set(7, 1, 0x9AA0AC); b.set(6, 0, 0xE04A3A)
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
