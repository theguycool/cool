// PIXEL REALM v2, part 1 of 5: utilities, tiles, items, recipes, the older creature pictures made in code, world generation and chunks,
// tools and items in use, ships, the vehicle screens' logic, the art store and the player's look, sound, weather,
// ambient and animal life, the journal, the menus and the receiver panel.
// The game is five files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm5.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
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

// ===== p14d_tools =====

// MARK: - Item use: mining, placing, melee, ranged weapons, eating, farming

func toolClass(_ t: Tile) -> ToolType {
	if t.isMod { return Tile.modToolTable[Int(t.rawValue - Tile.modBase)] }
	switch t {
	case .log, .jungleLog, .palmLog, .logBlock, .jungleLogBlock, .palmLogBlock, .planks, .workbench, .chest, .platform, .leaves, .jungleLeaves, .cactus, .hay, .reed, .lantern, .torch, .ladder, .tinkerBench,
		 .birchLog, .birchLogBlock, .birchLeaves, .pineLeaves, .weatherStation, .rainBarrel, .shutterClosed, .shutterOpen:
		return .axe
	case .chair, .table, .bedL, .bedR, .cabinet, .wardrobe, .shelf, .bookshelf, .sofa, .stairWoodR, .stairWoodL:
		return .axe
	case .dirt, .grass, .sand, .snow, .mud, .dryGrass, .jungleGrass, .mossGrass, .farmland, .sandbag:
		return .shovel
	default:
		return .pickaxe
	}
}

func isLogTile(_ t: Tile) -> Bool {
	// a mod tree's pass-through trunk counts too (felled by an axe, keeping its leaves alive)
	if t.isMod { return ModRuntime.shared.treeRole(t) == 1 }
	return t == .log || t == .jungleLog || t == .palmLog || t == .birchLog
}

func isLeafTile(_ t: Tile) -> Bool {
	if t.isMod { return ModRuntime.shared.treeRole(t) == 2 }
	return t == .leaves || t == .jungleLeaves || t == .birchLeaves || t == .pineLeaves
}

/// Which way a stair rises: 1 to the right, 2 to the left, 0 for anything that is not a stair
func stairSide(_ t: Tile) -> UInt8 {
	switch t {
	case .stairWoodR, .stairStoneR, .stairBrickR: return 1
	case .stairWoodL, .stairStoneL, .stairBrickL: return 2
	default: return 0
	}
}

/// The stair facing the other way (the same tile for anything else)
func stairMirror(_ t: Tile) -> Tile {
	switch t {
	case .stairWoodR: return .stairWoodL
	case .stairWoodL: return .stairWoodR
	case .stairStoneR: return .stairStoneL
	case .stairStoneL: return .stairStoneR
	case .stairBrickR: return .stairBrickL
	case .stairBrickL: return .stairBrickR
	default: return t
	}
}

/// Furniture that stores things like a chest (its contents live in World.chests)
func isStorageFurniture(_ t: Tile) -> Bool { return t == .cabinet || t == .wardrobe }

/// Furniture the player can sit on
func isSeat(_ t: Tile) -> Bool { return t == .chair || t == .sofa || (t.isMod && ModRuntime.shared.seatTiles.contains(t.rawValue)) }

/// Sand, and the mod blocks that fall like it
func fallsLikeSand(_ t: Tile) -> Bool { return t == .sand || (t.isMod && ModRuntime.shared.fallTiles.contains(t.rawValue)) }

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
				if isLeafTile(t) && !logNear(x, y, 4) { breakTile(x, y, false) }
			}
			if z.t > 0 { keep.append(z) }
		}
		decayZones = keep
	}
}

extension Game {
	func updateUse(_ dt: Double) {
		if useCD > 0 { useCD -= dt }
		if swingT > 0 { swingT -= dt } else { swingDur = 0.25 }
		if muzzleT > 0 { muzzleT -= dt }
		if bowRecoil > 0 { bowRecoil -= dt }
		if eatT > 0 { eatT -= dt }
		if placeCD > 0 { placeCD -= dt }
		if lockT > 0 { lockT -= dt }
		if let t = lockTarget, t.hp <= 0 || t.removed { lockTarget = nil }
		// (driving, or with the hands on a remote, nothing in hand is used)
		if dead || inVehicle != nil || remoteID != 0 {
			mining = false
			usePressedFlag = false
			useReleasedFlag = false
			strikeT = 0
			return
		}
		// a heavy blow lands at the end of its wind-up, if the same weapon is still in hand
		if strikeT > 0 {
			strikeT -= dt
			if strikeT <= 0 {
				strikeT = 0
				if sel == strikeSel && heldItem == strikeItem { resolveMelee(strikeItem) }
			}
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
			wireLast = nil
		}
		// bow release logic works on edges
		if case .bow? = held {
			handleBow(dt, pressed, released)
			return
		} else if case .custom(let k)? = held, let r = ModRuntime.shared.item(k), r.def.kind == .bow {
			handleModBow(r, dt, pressed, released)
			return
		} else if bowCharge > 0 {
			bowCharge = 0
		}
		if !useHeld {
			handEmptied = false
			lastUsedItem = nil
			return
		}
		guard let it = held else {
			// a stack used up while the button is held (the last ladder or block placed) does not turn
			// the hold into mining with bare hands: that waits for the next press
			if lastUsedItem != nil { handEmptied = true }
			lastUsedItem = nil
			if !handEmptied { useBareHand(dt, pressed) }
			return
		}
		lastUsedItem = it
		// a custom dimension's gate, then a mod's summoning item (tried before the item's own use)
		if pressed && world.dim.isCustom && tryReturnGate() { return }
		if pressed && !logicRT.isEmpty && tryLogicTap() { return }
		if pressed && !ModRuntime.shared.summons.isEmpty && trySummonWith(it) { return }
		switch it {
		case .block(let t): usePlaceBlock(t, dt)
		case .tool(let k, let tr): useToolItem(k, tr, dt, pressed)
		case .sword, .spear, .hammer, .knife, .club, .relic: useMeleeWeapon(it, pressed)
		case .gun(let g): useGun(g, pressed)
		case .sling: useSling(pressed)
		case .food(let f): useFood(f, pressed)
		case .mat(let m):
			if m == .seeds { usePlant(.wheat1, it, pressed) }
			if m == .vial { useVial(pressed) }
		case .part(let p): usePart(p, pressed)
		case .gadget(let g): useGadget(g, pressed)
		case .wall(let k): usePlaceWall(k)
		case .armor, .gear:
			if pressed { quickEquip(sel); say("Equipped.", 1.0) }
		case .custom(let k): useModItem(k, dt, pressed)
		case .potion(let p): usePotion(p, pressed)
		case .compound:
			if pressed { say("Work it into equipment at an Infusion Crucible.", 1.8) }
		case .exoPart, .exoPlate, .exoCore, .exoModule:
			if pressed { say("Fit it to your suit at an Assembly Station.", 1.8) }
		default: break
		}
	}

	// MARK: bare hands & tools

	func useBareHand(_ dt: Double, _ pressed: Bool) {
		if pressed && world.dim.isCustom && tryReturnGate() { return }
		if pressed && !logicRT.isEmpty && tryLogicTap() { return }
		if let m = mobUnderAim(Item.bareHands) {
			if pressed || (useCD <= 0 && !meleeCandidates(Item.bareHands).isEmpty) { startMelee(nil, target: m) }
			return
		}
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		mineStep(tx, ty, nil, nil, dt)
	}

	func useToolItem(_ k: ToolType, _ tr: Tier, _ dt: Double, _ pressed: Bool) {
		let it: Item = .tool(k, tr)
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		// pointing at a creature means fighting it, not digging the block behind it
		if let m = mobUnderAim(infusedMelee(it)) {
			if pressed || (useCD <= 0 && !meleeCandidates(infusedMelee(it)).isEmpty) { startMelee(it, target: m) }
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
		mineStep(tx, ty, k, tr, dt, speed: OverrideRT.shared.toolSpeed(.tool(k, tr)))
	}

	/// A melee weapon in hand. A fresh press always swings (toward the aim, or the foe under it); held
	/// down it keeps swinging, but only while a foe is actually in reach, so holding on empty ground or
	/// on a foe that is still too far away never wastes swings.
	func useMeleeWeapon(_ it: Item, _ pressed: Bool) {
		let p: MeleeProfile = infusedMelee(it)
		let target: Mob? = mobUnderAim(p)
		if let t = target {
			// the touch landed on (or close to) a foe: the blow goes at it
			aimX = t.b.x
			aimY = t.b.cy
		}
		if !pressed {
			// held: nothing to do while the weapon recovers (this runs every frame). Held on the attack
			// stick it swings again as soon as the weapon is ready; a finger held on the world swings
			// only while something is actually in reach
			if useCD > 0 || strikeT > 0 { return }
			let onStick: Bool = actState.held && !touchActive
			if !onStick && meleeCandidates(p).isEmpty { return }
		}
		startMelee(it, target: target)
	}

	/// Swings the item right now, ignoring its cooldown and wind-up (used by debug tools and tests)
	func swingEmpty(_ it: Item?) {
		useCD = 0
		strikeT = 0
		if startMelee(it) && strikeT > 0 {
			strikeT = 0
			resolveMelee(it)
		}
	}

	/// The foe the player is pointing at: under the aim, or close to it (fingers are not precise),
	/// near enough to be worth swinging at
	func mobUnderAim(_ p: MeleeProfile) -> Mob? {
		if !aimValid { return nil }
		let pad: Double = 0.9
		var best: Mob? = nil
		var bd: Double = 1e9
		for m in mobsNear(aimX - 6, aimX + 6) {
			if m.hp <= 0 || m.removed || m.tame || m.downed { continue }
			let x0: Double = m.b.left - pad
			let x1: Double = m.b.right + pad
			let y0: Double = m.b.top - pad
			let y1: Double = m.b.y + pad
			if aimX < x0 || aimX > x1 || aimY < y0 || aimY > y1 { continue }
			let reach: Double = boxDistance(m, shoulderX, shoulderY)
			if reach > max(p.reach + 1.5, 4.0) { continue }
			var d: Double = abs(aimX - m.b.x) + abs(aimY - m.b.cy)
			if !isThreat(m) { d += 2.0 }
			if d < bd { bd = d; best = m }
		}
		return best
	}

	// MARK: mining & breaking

	func mineStep(_ tx: Int, _ ty: Int, _ kind: ToolType?, _ tier: Tier?, _ dt: Double, speed toolSpeed: Double? = nil) {
		let t: Tile = world.tile(tx, ty)
		if t == .air && mineWall(tx, ty, kind, tier, dt) { return }
		if t == .air || t.liquid {
			mining = false
			mineP = 0
			if useCD <= 0 && kind != nil && kind != .hoe {
				swingT = 0.2
				swingDir = aimFacing()
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
		// a suit's drill arm bores anything up to its metal's tier, whatever is in hand
		let drill: Int = suitDrillTier()
		if def.tier > 0 && !isCreative {
			// a tier asks for a strong enough tool of the block's own kind (a pickaxe for the game's ores)
			var pt: Int = (kind == cls) ? (tier?.rawValue ?? 0) : 0
			if drill > pt { pt = drill }
			if pt < def.tier {
				mining = false
				if useCD <= 0 {
					let tn: String = cls.name.lowercased()
					say(kind == cls ? "This needs a stronger " + tn + "." : "You need a " + tn + " for that.", 1.5)
					useCD = 0.8
					swingT = 0.2
					swingDir = aimFacing()
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
		if let k = kind, let tr = tier { speed = (toolSpeed ?? tr.mineSpeed) * (k == cls ? 1.0 : 0.35) }
		if drill > 0 {
			let ds: Double = (Tier(rawValue: drill)?.mineSpeed ?? 4.0) * 1.25
			if ds > speed && suitRun(.drill, 4.0, dt) { speed = ds }
		}
		if isCreative { speed = 1000 }
		mineNeed = max(0.05, def.hard * 1.5)
		mineP += dt * speed * mineBoost(kind) * ModRuntime.shared.rule(.mining)
		if useCD <= 0 {
			swingT = 0.22
			swingDir = aimFacing()
			facing = swingDir
			useCD = 0.26
			let col: UInt32 = def.colors.first ?? 0x888888
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, col, 3, 3.0, 0.4, 14)
			digSound(t, broke: false)
		}
		if mineP >= mineNeed {
			mineP = 0
			mining = false
			digSound(t, broke: true)
			let fell: Bool = isLogTile(t) && kind == .axe
			if fell {
				fellTree(tx, ty)
			} else {
				breakTile(tx, ty, true)
				if let k = kind, let tr = tier, k == cls { quarryAround(tx, ty, t, k, tr) }
			}
		}
	}

	func tileDropStacks(_ t: Tile, _ x: Int, _ y: Int) -> [Stack] {
		if t.isMod, let st = ModRuntime.shared.blockDrops(t) {
			var mod: [Stack] = st
			// a mod tree's leaves give saplings as the game's do (they grow its designs where they belong)
			if isLeafTile(t) && Double.random(in: 0...1) < 0.085 { mod.append(Stack(item: .block(.sapling), count: 1)) }
			// a custom storage block spills what it held
			if ModRuntime.shared.blockDef(t)?.function == .storage, world.chests[world.chestKey(x, y)] != nil {
				mod.append(contentsOf: world.removeChest(x, y))
			}
			return mod
		}
		var out: [Stack] = []
		let r: Double = Double.random(in: 0...1)
		switch t {
		case .tallGrass:
			if r < 0.14 { out.append(Stack(item: .mat(.seeds), count: 1)) }
		case .leaves, .jungleLeaves, .birchLeaves, .pineLeaves:
			if (t == .leaves || t == .jungleLeaves) && r < 0.05 { out.append(Stack(item: .food(.apple), count: 1)) }
			// about one leaf block in twelve gives a sapling (a felled tree's leaves fall by themselves)
			if Double.random(in: 0...1) < 0.085 { out.append(Stack(item: .block(.sapling), count: 1)) }
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
		case .saltpeter:
			out.append(Stack(item: .mat(.saltpeter), count: 1 + (r < 0.35 ? 1 : 0)))
		case .amethyst:
			out.append(Stack(item: .mat(.amethyst), count: 1 + (r < 0.5 ? 1 : 0)))
		case .oreCart:
			// an abandoned cart still holds a little of what was being hauled out (fixed by its spot)
			for st in oreCartLoad(x, y) { out.append(st) }
		case .chest:
			for s in world.removeChest(x, y) { out.append(s) }
			out.append(Stack(item: .block(.chest), count: 1))
		case .cabinet, .wardrobe:
			for s in world.removeChest(x, y) { out.append(s) }
			out.append(Stack(item: .block(t), count: 1))
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
		// a bed is taken down whole (it drops once)
		if t == .bedL && world.tile(x + 1, y) == .bedR { world.set(x + 1, y, .air) }
		if t == .bedR && world.tile(x - 1, y) == .bedL { world.set(x - 1, y, .air) }
		if world.set(x, y, .air) == .air && t != .air { return }
		if byPlayer && t.isMod && !logicRT.isEmpty, let k = modBlockKey(t) { fireLogic(.blockBroken, x: x, y: y, block: true, key: k) }
		if isLogTile(t) && decayZones.count < 24 { decayZones.append(DecayZone(x: x, y: y, t: 30)) }
		if isLeafTile(t) {
			for _ in 0..<3 { dropLeaf(Double(x) + Double.random(in: 0.1...0.9), Double(y) + Double.random(in: 0.2...0.8), t) }
		}
		let col: UInt32 = t.def.colors.first ?? 0x888888
		spawnParticles(Double(x) + 0.5, Double(y) + 0.5, col, 6, 3.5, 0.5, 16)
		if !(byPlayer && isCreative) {
			for s in minedDrops(t, x, y, byPlayer) {
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
		if fallsLikeSand(world.tile(x, y - 1)) { checkFalling(x, y - 1) }
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
				if isLeafTile(lt) {
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
		// needs an adjacent tile to attach to, or a wall behind it
		let n: [Tile] = [world.tile(tx - 1, ty), world.tile(tx + 1, ty), world.tile(tx, ty - 1), world.tile(tx, ty + 1)]
		for k in n {
			if k != .air && !k.liquid && !(k.isPlant && k != .torch) { return true }
		}
		return world.wallAt(tx, ty) != 0
	}

	func usePlaceBlock(_ t: Tile, _ dt: Double) {
		if placeCD > 0 { return }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if vehicleBuild && wallMode && canBeWall(t.placedForm) && attachWallToVehicle(t.placedForm) { return }
		if t == .doorClosed || t == .doorOpen {
			if vehicleBuild && attachDoorToVehicle() { return }
			if placeDoor(tx, ty) {
				if !isCreative { inv.removeAt(sel, 1) }
				placeCD = 0.25
				swingT = 0.14
				bumpHUD()
			}
			return
		}
		// the ON VEHICLE switch: the block is built onto the vehicle instead
		if vehicleBuild && attachBlockToVehicle(t.placedForm) { return }
		// the WALL switch: the block goes up as a passable wall instead
		if wallMode && canBeWall(t.placedForm) {
			placeBlockAsWall(t.placedForm)
			return
		}
		// aiming at a ladder with ladders in hand builds it on; beds, stairs and lift cars place their own way
		if t == .ladder && extendLadder(tx, ty) { return }
		if placeSpecial(t, tx, ty) { return }
		// a log item builds a solid log block (tree trunks themselves have no collision)
		let placed: Tile = t.placedForm
		if !canPlaceAt(tx, ty, placed) { return }
		// plants / crops need special support handled in canPlaceAt through needsSupport
		world.set(tx, ty, placed)
		world.setBuilt(tx, ty, true)
		if t == .chest { world.setChestItems(tx, ty, []) }
		if placed.isMod, ModRuntime.shared.blockDef(placed)?.function == .storage { world.setChestItems(tx, ty, []) }
		// parts that point a way face the way the player does
		if powerDirectional(placed), let d = world.powerDev(tx, ty) { d.dir = facing >= 0 ? 0 : 2 }
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.6)
		// the last block of a summoning shape
		if !ModRuntime.shared.summons.isEmpty { summonByBuilding(tx, ty) }
		if placed.isMod && !logicRT.isEmpty, let k = modBlockKey(placed) { fireLogic(.blockPlaced, x: tx, y: ty, block: true, key: k) }
		placeCD = 0.11
		swingT = 0.14
		swingDir = aimFacing()
		facing = swingDir
		bumpHUD()
	}

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
		let fo: ModOverride? = OverrideRT.shared.items[.food(f)]
		let fh: Double = fo?.hunger ?? f.hunger
		let fl: Double = fo?.heal ?? f.heal
		hunger = min(20, hunger + fh)
		if fl > 0 { heal(fl) }
		if !isCreative { inv.removeAt(sel, 1) }
		eatT = 0.5
		useCD = 0.5
		sfx(.eat, 0.6)
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
			facing = aimFacing()
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
		// a little of the archer's own motion carries into the arrow, so shots on the run still land;
		// all of the speed of a vehicle that carries the archer does (the arrow was going that fast already)
		let cv: (Double, Double) = carrierVel()
		let own: Double = inVehicle == nil ? pb.vx : 0
		return (ox + dx * 0.4, oy + dy * 0.4, dx * speed + own * 0.3 + cv.0, dy * speed + min(0, inVehicle == nil ? pb.vy : 0) * 0.2 + cv.1)
	}

	func fireArrow(_ charge: Double) {
		if !isCreative { _ = inv.remove(.ammo(.arrow), 1) }
		let st: BowStats = bowStats(.bow)
		let l: (Double, Double, Double, Double) = arrowLaunch(charge)
		var dmg: Double = st.baseDamage + st.chargeDamage * charge
		// a mod may change the bow's full-draw damage
		if let o = OverrideRT.shared.items[.bow], let v = o.damage { dmg *= v / max(0.1, st.baseDamage + st.chargeDamage) }
		if charge >= 0.99 && Double.random(in: 0...1) < 0.15 { dmg *= 1.5 }
		var p = Projectile(kind: .arrow, x: l.0, y: l.1, vx: l.2, vy: l.3, dmg: dmg, fromPlayer: true, gravity: st.gravity)
		p.life = 6.0
		p.w = 0.22
		p.source = .player
		p.uid = newID()
		infuseShot(&p, heldItem)
		projectiles.append(p)
		sfx(.bow, 0.7)
		useCD = st.useTime * quickMul()
		swingT = 0.18
		swingDir = facing
		bowRecoil = 0.12
		bumpHUD()
	}

	/// Sample points of the shot's flight for the aiming arc: the bow while it is drawn, the sling and
	/// bolt throwers while the aim is held
	func arrowPreview() -> [(Double, Double)] {
		var l: (Double, Double, Double, Double)
		var grav: Double
		if bowCharge > 0 {
			let st: BowStats = bowStats(.bow)
			l = arrowLaunch(max(0.45, bowCharge))
			grav = st.gravity
		} else if useHeld && aimValid && inVehicle == nil, let it = heldItem {
			var speed: Double = 0
			var ox: Double = pb.x + Double(facing) * 0.4
			var oy: Double = pb.y - 1.3
			switch it {
			case .sling: speed = 23; grav = 16
			case .gun(let g) where g.isBoltThrower:
				speed = g.speed; grav = g.gravity
				ox = pb.x + Double(facing) * 0.7
				oy = pb.y - 1.2
			case .gadget(let gd) where gd == .bomb || gd == .fireFlask: speed = throwSpeed; grav = throwGravity
			case .potion(let pt) where pt.thrown: speed = throwSpeed; grav = throwGravity
			default: return []
			}
			let a: Double = lobAngle(aimX - ox, aimY - oy, speed, grav)
			l = (ox, oy, cos(a) * speed, sin(a) * speed)
		} else {
			return []
		}
		var x: Double = l.0
		var y: Double = l.1
		let vx: Double = l.2
		var vy: Double = l.3
		var out: [(Double, Double)] = []
		let step: Double = 0.03
		var i: Int = 0
		while i < 40 {
			vy = min(vy + grav * step, 40)
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
			if var st = inv.slots[sel], case .gun(let g) = st.item, let a = g.ammo {
				let need: Int = g.magazine - st.extra
				var take: Int = need
				if !isCreative {
					take = min(need, inv.total(.ammo(a)))
					_ = inv.remove(.ammo(a), take)
				}
				st.extra += take
				inv.slots[sel] = st
				if g.isBoltThrower { sfx(.tap, 0.5) }
				bumpHUD()
			} else if let st = inv.slots[sel], case .custom(let k) = st.item, let r = ModRuntime.shared.item(k), r.def.kind == .gun {
				finishModReload(r)
			}
			reloadSlot = -1
		}
	}

	func startReload() {
		if let st = heldStack, case .custom(let k) = st.item, let r = ModRuntime.shared.item(k), r.def.kind == .gun {
			startModReload(r, st)
			return
		}
		guard let st = heldStack, case .gun(let g) = st.item, let a = g.ammo else { return }
		if reloadT > 0 || st.extra >= g.magazine { return }
		if !isCreative && inv.total(.ammo(a)) <= 0 {
			say("Out of " + a.name.lowercased() + "s!", 1.5)
			return
		}
		reloadT = g.reloadTime
		reloadSlot = sel
		// a crossbow is cocked after every bolt: no need to announce that each time
		if g.magazine > 1 { say("Reloading...", 1.0) }
	}

	/// Fires a loaded weapon: bullets, bolts, a spread of pellets, or the storm rod's lightning. Heavy
	/// weapons need a fresh press per shot; the rest keep firing while held. Empty ones reload by
	/// themselves when there is ammunition.
	func useGun(_ g: GunType, _ pressed: Bool) {
		guard var st = inv.slots[sel] else { return }
		if reloadT > 0 { return }
		if st.extra <= 0 {
			if g == .stormRod {
				if pressed { say("The rod is still gathering its charge.", 1.2) }
				return
			}
			if pressed || useCD <= 0 { startReload() }
			return
		}
		if useCD > 0 { return }
		if g.needsPress && !pressed { return }
		if !isCreative || g != .stormRod { st.extra -= 1 }
		inv.slots[sel] = st
		useCD = (OverrideRT.shared.items[.gun(g)]?.cooldown ?? g.cooldown) * quickMul()
		if g == .stormRod {
			fireStormRod()
			bumpHUD()
			return
		}
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.7
		let oy: Double = pb.y - 1.2
		// bolts drop a little: they are raised just enough to fly through the spot aimed at
		let base: Double = lobAngle(aimX - ox, aimY - oy, g.speed, g.gravity)
		let n: Int = g == .blunderbuss ? 7 : 1
		for i in 0..<n {
			var a: Double = base
			// an even fan of pellets, so the spread always covers the same cone
			if n > 1 { a += (Double(i) / Double(n - 1) - 0.5) * 0.6 }
			let dx: Double = cos(a)
			let dy: Double = sin(a)
			let kind: ProjKind = g == .blunderbuss ? .pellet : (g.isBoltThrower ? .quarrel : .bullet)
			var p = Projectile(kind: kind, x: ox, y: oy, vx: dx * g.speed, vy: dy * g.speed, dmg: OverrideRT.shared.items[.gun(g)]?.damage ?? g.damage, fromPlayer: true, gravity: g.gravity)
			p.life = g.shotLife * (n > 1 ? Double.random(in: 0.85...1.1) : 1.0)
			p.source = .player
			p.uid = newID()
			p.pierce = g.pierce
			p.knock = g.knock
			if kind == .pellet { p.w = 0.16 }
			if kind == .quarrel { p.w = 0.22 }
			infuseShot(&p, heldItem)
			projectiles.append(p)
		}
		let heavyShot: Bool = g == .rifle || g == .arbalest || g == .blunderbuss
		switch g {
		case .blunderbuss: sfx(.blunderbuss, 0.9)
		case .crossbow, .arbalest, .repeater: sfx(.crossbow, 0.75)
		default: sfx(.gun, 0.8)
		}
		muzzleT = g.isBoltThrower ? 0 : 0.08
		swingT = 0.1
		swingDir = facing
		addShake(heavyShot ? 0.16 : 0.07)
		pb.vx -= Double(facing) * (g == .blunderbuss ? 4.0 : (heavyShot ? 2.5 : 1.0))
		let dx0: Double = cos(base)
		let dy0: Double = sin(base)
		if g.isFirearm { spawnParticles(ox + dx0 * 0.4, oy + dy0 * 0.4, 0xFFE080, g == .blunderbuss ? 9 : 4, 3.0, 0.15, 0) }
		if st.extra <= 0, let am = g.ammo, isCreative || inv.total(.ammo(am)) > 0 { startReload() }
		bumpHUD()
	}

	// MARK: gadgets & vehicle parts

	func useGadget(_ g: Gadget, _ pressed: Bool) {
		switch g {
		case .bucket:
			if pressed { useBucket() }
		case .remote:
			if pressed { useRemote() }
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
			if pressed, useCD <= 0, inReach(aimX, aimY), let (v, c) = vehicleWallAtPoint(aimX, aimY), removeVehicleWall(v, c) {
				useCD = 0.3
			} else if pressed, useCD <= 0, let (v, c) = vehicleAtPoint(aimX, aimY), inReach(aimX, aimY) {
				removeVehiclePart(v, c)
				useCD = 0.3
			}
		case .portalKey:
			if pressed { say("Use the key on the sealed portal.", 2.0) }
		case .carKit, .boatKit, .motorboatKit, .planeKit, .heliKit, .airshipKit, .tankKit, .truckKit:
			if pressed && useCD <= 0 { placeKit(g) }
		case .assembler:
			useAssembler(pressed)
		case .bomb:
			if pressed { throwBomb() }
		case .fireFlask:
			if pressed { throwFlask() }
		case .barometer:
			if pressed { say(barometerReading(), 2.5) }
		case .waterFlask:
			useWaterFlask(pressed)
		case .powerCable, .pulseWire, .pulseWireB, .wireSnips:
			useWiring(g, pressed)
		case .probe:
			if pressed { probeAt(aimX, aimY) }
		}
	}

	/// A cargo crate's storage lives with the other chests, under a key no block can have (built from
	/// the vehicle's saved id and the crate's cell), so it is saved and loaded like any chest
	func cargoSpot(_ v: Vehicle, _ c: PartCell) -> IntPair {
		if c.dx >= -32 && c.dx < 32 && c.dy >= -32 && c.dy < 32 {
			return IntPair(x: -1_000_000_000 + v.id * 4096 + (c.dx + 32) * 64 + (c.dy + 32), y: -77)
		}
		// a cell further out on a big vehicle (an assembled ship): the cell goes in the second number
		return IntPair(x: -1_000_000_000 + v.id, y: -100_000 - ((c.dx + 2048) * 4096 + (c.dy + 2048)))
	}

	func isCargoSpot(_ p: IntPair) -> Bool { return (p.y == -77 || p.y <= -100_000) && p.x < -900_000_000 }

	func removeVehiclePart(_ v: Vehicle, _ c: PartCell) {
		if v.rider { dismount() }
		let crates: [PartCell] = v.parts.keys.filter { vehicleStores(v, $0) }
		let spills: [(PartCell, (Double, Double))] = crates.map { ($0, v.cellCenter($0)) }
		let returned: [VCell] = v.cutAway(c)
		// a crate that comes off tips its contents onto the ground
		for (cell, at) in spills where v.parts[cell] == nil {
			let k: IntPair = cargoSpot(v, cell)
			if let p = openChest, p == k { openChest = nil }
			for st in world.removeChest(k.x, k.y) { spawnDrop(st, at.0, at.1, Double.random(in: -2...2), -3.5) }
		}
		for r in returned { giveItem(vehicleCellItem(r), 1) }
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
		if p == .bigWheel {
			if !attachBigWheel() { say("Tap next to a vehicle: the cell you tap is the big wheel's middle.", 2.0) }
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
			splitJointSections(v)
			if !isCreative { inv.removeAt(sel, 1) }
			useCD = 0.2
			swingT = 0.15
			let check: VehicleCheck = vehicleCheck(v)
			if check.ready && !wasReady {
				let kind: String = check.title.lowercased()
				say("Your \(kind) is ready! Stand next to it and press DRIVE.", 3.5)
			} else if let note = partNote(v, c, p) {
				say(note, 3.0)
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

// MARK: - Combat: melee strikes, aim, weapon switching, ranged and special weapons, feedback

/// A melee swing, drawn for a moment after it is made: the trail covers exactly the space it swept
struct SlashFX {
	var x: Double
	var y: Double
	var ang: Double
	var reach: Double
	var halfArc: Double
	var style: SwingStyle
	var color: UInt32
	var life: Double
	var maxLife: Double
	var hit: Bool
}

/// A lightning arc from the storm rod: a jagged line through these points
struct ArcFX {
	var pts: [(Double, Double)]
	var life: Double
}

/// Ground set alight by a fire flask; it burns whatever stands in it
struct FireZone {
	var x: Double
	/// the ground the flames stand on
	var y: Double
	var r: Double
	var t: Double
	var tick: Double = 0
	var uid: Int
	/// started by lightning, not by a thrown flask (it then answers to the weather damage settings)
	var env: Bool = false
}

func isUndead(_ k: MobKind) -> Bool {
	switch k {
	case .zombie, .skeleton, .archer, .wraith: return true
	default: return false
	}
}

/// signed difference between two angles, in -pi...pi
func angleDiff(_ a: Double, _ b: Double) -> Double {
	var d: Double = a - b
	while d > Double.pi { d -= 2.0 * Double.pi }
	while d < -Double.pi { d += 2.0 * Double.pi }
	return d
}

/// Rock blocks a sling can throw
let slingAmmo: [Tile] = [.stone, .slate, .deepRock, .sandstone, .ashStone]

/// The direction (radians, y pointing down) to launch a shot of speed `v` falling under gravity `g`
/// so that it passes through the point (dx, dy) from where it starts, on the lower, flatter of the two
/// arcs. Out of reach: the longest-reaching throw toward it (45 degrees up).
func lobAngle(_ dx: Double, _ dy: Double, _ v: Double, _ g: Double) -> Double {
	if g <= 0.001 { return atan2(dy, dx) }
	let x: Double = max(0.001, abs(dx))
	let up: Double = -dy
	let v2: Double = v * v
	let disc: Double = v2 * v2 - g * (g * x * x + 2.0 * up * v2)
	let th: Double = disc < 0 ? Double.pi * 0.25 : atan((v2 - sqrt(disc)) / (g * x))
	return dx >= 0 ? -th : Double.pi + th
}

/// Thrown and lobbed weapons are aimed at the spot itself: the game works out the arc
let throwSpeed: Double = 15.0
let throwGravity: Double = 22.0

extension Game {
	// MARK: geometry

	/// The way the player turns to face the aim: toward it, but aiming straight up or down (within a third
	/// of a block of the player's own column) keeps the way they already face
	func aimFacing() -> Int {
		let d: Double = aimX - pb.x
		if abs(d) < 0.3 { return facing }
		return d >= 0 ? 1 : -1
	}

	/// where melee blows start from
	var shoulderX: Double { return pb.x }
	var shoulderY: Double { return pb.y - pb.h * 0.55 }

	/// The way an attack goes: toward the aim, or straight ahead when there is no aim (or the aim is on
	/// the player's own body, where its direction would be noise)
	func attackAngle() -> Double {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		if aimValid {
			let dx: Double = aimX - ox
			let dy: Double = aimY - oy
			if dx * dx + dy * dy > 0.36 { return atan2(dy, dx) }
		}
		return facing >= 0 ? 0 : Double.pi
	}

	/// distance from a point to the nearest edge of a creature's box (0 inside it)
	func boxDistance(_ m: Mob, _ ox: Double, _ oy: Double) -> Double {
		let nx: Double = clampD(ox, m.b.left, m.b.right)
		let ny: Double = clampD(oy, m.b.top, m.b.y)
		let dx: Double = nx - ox
		let dy: Double = ny - oy
		return sqrt(dx * dx + dy * dy)
	}

	/// Whether a swing with profile `p` aimed along (dirx, diry) from the shoulder reaches `m`; returns
	/// how far away it is. The same test serves every way of attacking, so reach never depends on how
	/// the attack was started.
	func meleeReach(_ m: Mob, _ dirx: Double, _ diry: Double, _ p: MeleeProfile) -> Double? {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let hw: Double = m.b.w * 0.5
		let hh: Double = m.b.h * 0.5
		let cx: Double = m.b.x
		let cy: Double = m.b.y - hh
		let nx: Double = clampD(ox, cx - hw, cx + hw)
		let ny: Double = clampD(oy, cy - hh, cy + hh)
		let ddx: Double = nx - ox
		let ddy: Double = ny - oy
		let dist: Double = sqrt(ddx * ddx + ddy * ddy)
		if dist > p.reach { return nil }
		let vx: Double = cx - ox
		let vy: Double = cy - oy
		if p.style == .thrust {
			// a straight band along the aim
			let along: Double = vx * dirx + vy * diry
			let ext: Double = hw * abs(dirx) + hh * abs(diry)
			if along + ext < 0 || along - ext > p.reach { return nil }
			let perp: Double = abs(vx * diry - vy * dirx)
			let pext: Double = hw * abs(diry) + hh * abs(dirx)
			if perp - pext > p.band { return nil }
		} else if dist > 0.45 {
			// inside the arc: the angle to the box centre, widened by how wide the box looks from here
			let cd: Double = max(0.2, sqrt(vx * vx + vy * vy))
			let off: Double = abs(angleDiff(atan2(vy, vx), atan2(diry, dirx)))
			let ext: Double = hw * abs(vy / cd) + hh * abs(vx / cd)
			if off > p.halfArc + atan(ext / cd) { return nil }
		} else if vx * dirx < -0.3 && abs(dirx) > 0.3 {
			// pressed right up against the player: anything on the side being swung at
			return nil
		}
		// blades do not pass through walls
		let ix: Double = nx + (cx - nx) * 0.25
		let iy: Double = ny + (cy - ny) * 0.25
		if !world.lineClear(ox, oy, ix, iy) && !world.lineClear(ox, oy, cx, cy) { return nil }
		return dist
	}

	/// every creature the current aim would catch, nearest first, at most the weapon's limit
	func meleeCandidates(_ p: MeleeProfile) -> [(Mob, Double)] {
		let ang: Double = attackAngle()
		let dirx: Double = cos(ang)
		let diry: Double = sin(ang)
		let ox: Double = shoulderX
		var out: [(Mob, Double)] = []
		for m in mobsNear(ox - p.reach - 4, ox + p.reach + 4) {
			if m.hp <= 0 || m.removed || m.tame || m.downed { continue }
			if let d = meleeReach(m, dirx, diry, p) { out.append((m, d)) }
		}
		if out.count > 1 { out.sort { $0.1 < $1.1 } }
		if out.count > p.maxHits { out.removeLast(out.count - p.maxHits) }
		return out
	}

	// MARK: melee

	/// Starts a melee attack with the held item (nil: bare hands). A heavy weapon winds up first and
	/// its blow lands a moment later; everything else strikes at once. False while still recovering.
	@discardableResult
	func startMelee(_ it: Item?, target: Mob? = nil) -> Bool {
		if useCD > 0 || strikeT > 0 { return false }
		let p: MeleeProfile = infusedMelee(it)
		useCD = p.cooldown
		swingDur = p.swingTime
		swingT = p.swingTime
		let ang: Double = attackAngle()
		// a blow straight up or down keeps the way the player already faces
		swingDir = abs(cos(ang)) < 0.25 ? facing : (cos(ang) >= 0 ? 1 : -1)
		facing = swingDir
		strikeItem = it
		strikeSel = sel
		strikeTarget = target
		if p.windup > 0 {
			strikeT = p.windup
		} else {
			resolveMelee(it)
		}
		return true
	}

	/// The blow itself: everything inside the swing's shape is hit, with the weapon's knockback,
	/// crits, combo, backstab, daze and fire; then the trail, sound and hit feedback
	func resolveMelee(_ it: Item?) {
		let p: MeleeProfile = infusedMelee(it)
		let infs: [Int] = heldInfusions(it)
		if suitHas(.servo) { _ = suitSpend(.servo, 1.0) }
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let ang: Double = attackAngle()
		let swingKey: Int = newID()
		let targets: [(Mob, Double)] = meleeCandidates(p)
		var hits: Int = 0
		var crits: Int = 0
		var undead: Bool = false
		for (m, _) in targets {
			var d: Double = p.damage
			var crit: Bool = false
			if p.combo {
				comboN = clock - comboT < 0.7 ? comboN + 1 : 1
				comboT = clock
				if comboN % 3 == 0 { d *= 2.0; crit = true }
			}
			if !crit && Double.random(in: 0...1) < p.critChance { d *= 1.5; crit = true }
			if p.backstab > 1 && (pb.x - m.b.x) * Double(m.dir) < 0 && !m.isBoss {
				d *= p.backstab
				crit = true
			}
			if p.undeadMult != 1 && isUndead(m.kind) { d *= p.undeadMult; undead = true }
			let dx: Double = m.b.x - ox
			var info = DamageInfo(amount: d, type: .melee, source: .player)
			info.dirX = abs(dx) > 0.2 ? (dx > 0 ? 1.0 : -1.0) : Double(swingDir)
			info.knock = p.knock
			info.originX = ox
			info.originY = oy
			info.key = swingKey
			info.cooldown = 0.3
			info.heavy = p.heavy
			info.crit = crit
			if applyMobDamage(m, info) {
				hits += 1
				if crit { crits += 1 }
				if p.burn > 0 && !heatImmune(m) { m.burn = max(m.burn, p.burn) }
				if p.daze > 0 { dazeMob(m, p.daze) }
				meleeInfusionHit(m, infs, d)
				suitMeleeHit(m)
				spawnSparks(m.b.x - info.dirX * m.b.w * 0.3, m.b.cy, info.dirX, p.trail, crit ? 7 : 4)
				lockTarget = m
				lockT = 2.0
			}
		}
		// pirate ships
		for sh in ships {
			let dx: Double = abs(sh.x - ox)
			let dy: Double = abs(sh.deckY(Double(WorldGen.sea)) - pb.y)
			if dx < 5.0 + p.reach * 0.3 && dy < 3.5 {
				sh.hp -= p.damage * 0.6
				sh.hitT = 0.2
				hits += 1
			}
		}
		if p.shockwave {
			// the maul's blow runs along the ground as a quake
			var q = Projectile(kind: .shock, x: pb.x + Double(swingDir) * 1.2, y: pb.y - 0.5, vx: Double(swingDir) * 15.0, vy: 0, dmg: 12, fromPlayer: true, gravity: 0)
			q.life = 0.55
			q.source = .player
			q.uid = newID()
			projectiles.append(q)
			addShake(0.3)
			spawnParticles(pb.x + Double(swingDir) * 1.4, pb.y - 0.1, 0xA08860, 10, 4.0, 0.5, 12)
		}
		lastStrikeHits = hits
		if slashes.count > 8 { slashes.removeFirst() }
		let life: Double = max(0.12, p.swingTime * 0.7)
		slashes.append(SlashFX(x: ox, y: oy, ang: ang, reach: p.reach, halfArc: p.halfArc, style: p.style, color: p.trail, life: life, maxLife: life, hit: hits > 0))
		switch p.style {
		case .stab: sfx(.swingLight, 0.5)
		case .thrust: sfx(.thrust, 0.55)
		case .smash, .bash: sfx(p.heavy || p.daze > 0 ? .swingHeavy : .swing, 0.6)
		case .slash: sfx(.swing, 0.5)
		}
		if hits > 0 {
			hitStopT = max(hitStopT, p.heavy ? 0.07 : (crits > 0 ? 0.05 : 0.03))
			addShake(p.heavy ? 0.18 : (crits > 0 ? 0.12 : 0.07))
			sfx(crits > 0 ? .crit : .hit, p.heavy ? 1.0 : 0.75)
			if hits >= 2 {
				floatText("x" + String(hits), pb.x, pb.y - pb.h - 0.9, 0xFFD060)
				sfx(.multiHit, 0.6)
			}
			if undead && p.undeadMult > 1 { spawnParticles(pb.x + Double(swingDir) * 1.2, pb.y - 1.2, 0xC8E8FF, 5, 2.5, 0.4, -2) }
		} else if let t = strikeTarget ?? (lockT > 0 ? lockTarget : nil), t.hp > 0, !t.removed {
			// aimed at something and missed: say so, where it is
			floatText("miss", t.b.x, t.b.top - 0.3, 0xA8A8A8)
		}
		strikeTarget = nil
	}

	/// Leaves a creature reeling: it cannot move or attack for a moment, then cannot be dazed again
	/// right away (no stun-locking). Bosses shrug it off; the golem only half feels it.
	func dazeMob(_ m: Mob, _ t: Double) {
		if m.isBoss || m.dazeGuard > 0 || m.hp <= 0 { return }
		let k: Double = m.kind == .golem ? 0.5 : 1.0
		m.daze = max(m.daze, t * k)
		m.atkT = 0
		m.blocking = false
		sfx(.daze, at: m.b.x, 0.5)
	}

	/// sparks thrown back along the line of a blow
	func spawnSparks(_ x: Double, _ y: Double, _ dirX: Double, _ color: UInt32, _ n: Int) {
		if particles.count > 160 { return }
		for _ in 0..<n {
			let a: Double = Double.random(in: -0.9...0.9) + (dirX >= 0 ? 0 : Double.pi)
			let sp: Double = Double.random(in: 4.0...8.0)
			let c: UInt32 = Double.random(in: 0...1) < 0.5 ? color : 0xFFF4D0
			particles.append(Particle(x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp - 2.0, life: Double.random(in: 0.12...0.25), maxLife: 0.25, color: c, size: Double.random(in: 0.07...0.13), gravity: 20))
		}
	}

	// MARK: aim assist for the action button

	/// The creature the action button should go for: hostile ones first (and the one already locked
	/// on), in sight for ranged weapons, within reach for melee (a little beyond it, so the player
	/// turns to face what is coming). Animals only when nothing hostile is near and a weapon is out.
	func autoTarget(_ it: Item?) -> Mob? {
		let ranged: Bool = it?.isRanged ?? false
		let weapon: Bool = it?.isWeapon ?? false
		let p: MeleeProfile = infusedMelee(it)
		let range: Double = ranged ? 22.0 : p.reach + 3.0
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		var best: Mob? = nil
		var bs: Double = 1e9
		for m in mobsNear(ox - range - 4, ox + range + 4) {
			if m.hp <= 0 || m.removed || m.tame || m.downed { continue }
			let foe: Bool = isThreat(m)
			if !foe && !weapon { continue }
			let d: Double = boxDistance(m, ox, oy)
			if d > range { continue }
			var score: Double = d
			if !foe { score += 8.0 }
			if !world.lineClear(ox, oy, m.b.x, m.b.cy) {
				if ranged { continue }
				score += 6.0
			}
			if m === lockTarget { score -= 1.5 }
			if score < bs { bs = score; best = m }
		}
		return best
	}

	/// launch speed and gravity of what the held item fires (0 speed: not a projectile weapon)
	func shotBallistics(_ it: Item?) -> (Double, Double) {
		guard let i = it else { return (0, 0) }
		switch i {
		case .bow: let st: BowStats = bowStats(.bow); return (st.maxSpeed, st.gravity)
		case .gun(let g): return (g.speed, g.gravity)
		case .sling: return (23.0, 16.0)
		case .gadget(let g): return (g == .bomb || g == .fireFlask) ? (throwSpeed, throwGravity) : (0, 0)
		case .potion(let p): return p.thrown ? (throwSpeed, throwGravity) : (0, 0)
		default: return (0, 0)
		}
	}

	/// Where to aim to hit `m`: its centre, led by its speed and raised to allow for the drop
	func aimPointFor(_ m: Mob, _ it: Item?) -> (Double, Double) {
		var tx: Double = m.b.x
		var ty: Double = m.b.cy
		let (spd, grav) = shotBallistics(it)
		if spd > 0 {
			let dx: Double = tx - pb.x
			let dy: Double = ty - (pb.y - 1.2)
			let t: Double = sqrt(dx * dx + dy * dy) / spd
			tx += m.b.vx * t
			// the bow is drawn and loosed along the aim, so it is aimed above the target; everything
			// else works its own arc out to the point it is aimed at
			if case .bow? = it { ty -= 0.5 * grav * t * t }
		}
		return (tx, ty)
	}

	// MARK: weapon switching

	/// The hotbar slot "next weapon" would pick: the weapon used last when something else is in hand,
	/// otherwise the next weapon along the hotbar
	func nextWeaponSlot() -> Int? {
		let n: Int = Inventory.hotbarCount
		let holdingWeapon: Bool = heldItem?.isWeapon ?? false
		if !holdingWeapon && lastWeaponSel >= 0 && lastWeaponSel < n && lastWeaponSel != sel {
			if let s = inv.slots[lastWeaponSel], s.item.isWeapon { return lastWeaponSel }
		}
		var k: Int = 1
		while k < n {
			let i: Int = (sel + k) % n
			if let s = inv.slots[i], s.item.isWeapon { return i }
			k += 1
		}
		return nil
	}

	/// One tap to the next weapon (or back to the weapon from a tool); the HUD button and the Q key
	func cycleWeapon() {
		guard let i = nextWeaponSlot() else {
			say("No other weapon in your hotbar.", 1.2)
			return
		}
		setSel(i)
		sfx(.swap, 0.6)
		floatText(inv.slots[i]?.item.name ?? "", pb.x, pb.y - pb.h - 0.6, 0xE8E8E8)
	}

	/// What the action button does with the item in hand
	var useLabel: String {
		if let v = drivenVehicle, machineGuns(v) > 0 { return "FIRE" }
		guard let it = heldItem else { return "PUNCH" }
		if it.isWeapon { return "ATTACK" }
		switch it {
		case .tool: return "MINE"
		case .block, .wall: return "BUILD"
		case .food: return "EAT"
		default: return "USE"
		}
	}

	// MARK: input safety

	/// Drops every held control. Panels, the pause menu and death take the on-screen controls away
	/// mid-press, and a button that disappears never hears its finger lift, so without this an attack,
	/// a walk or a jump could carry on by itself once the panel closes.
	func releaseAllInput() {
		suitFireHeld = false
		jointButtons = [false, false, false]
		actState.stickReleased()
		actState.was = false
		stick = 0
		stickY = 0
		jumpHeld = false
		downHeld = false
		keyL = false
		keyR = false
		useHeld = false
		useWasHeld = false
		usePressedFlag = false
		useReleasedFlag = false
		touchActive = false
		pendingInteract = false
		bowCharge = 0
		mining = false
	}

	/// Once a frame: releases the controls when something covers them
	func updateInputGate() {
		let blocked: Bool = paused || showInventory || showMap || showJournal || showWeather || showPower || showCapture || showModTest || showInfuse || showExo || showJoint || showRadio || dead
		if blocked && !inputBlocked { releaseAllInput() }
		inputBlocked = blocked
	}

	// MARK: sling

	func useSling(_ pressed: Bool) {
		if useCD > 0 { return }
		var ammo: Tile? = nil
		if !isCreative {
			for t in slingAmmo where inv.total(.block(t)) > 0 { ammo = t; break }
			if ammo == nil {
				if pressed { say("The sling needs stones: any stone or slate in your bag.", 1.8) }
				return
			}
		}
		if let t = ammo { _ = inv.remove(.block(t), 1) }
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.3
		// the stone is lobbed so that it comes down on the spot aimed at
		let a: Double = lobAngle(aimX - ox, aimY - oy, 23.0, 16.0)
		var p = Projectile(kind: .pebble, x: ox, y: oy, vx: cos(a) * 23.0, vy: sin(a) * 23.0, dmg: 4.5, fromPlayer: true, gravity: 16)
		p.life = 3.0
		p.w = 0.22
		p.knock = 7.5
		p.source = .player
		p.uid = newID()
		infuseShot(&p, heldItem)
		projectiles.append(p)
		useCD = 0.55 * quickMul()
		swingDur = 0.2
		swingT = 0.2
		swingDir = facing
		sfx(.sling, 0.6)
		bumpHUD()
	}

	// MARK: fire flask

	func throwFlask() {
		if useCD > 0 { return }
		if !isCreative { inv.removeAt(sel, 1) }
		facing = aimFacing()
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.3
		let a: Double = lobAngle(aimX - ox, aimY - oy, throwSpeed, throwGravity)
		var p = Projectile(kind: .flask, x: ox, y: oy, vx: cos(a) * throwSpeed, vy: sin(a) * throwSpeed, dmg: 2, fromPlayer: true, gravity: throwGravity)
		p.life = 2.5
		p.w = 0.3
		p.source = .player
		p.uid = newID()
		projectiles.append(p)
		useCD = 0.45
		swingT = 0.18
		swingDir = facing
		bumpHUD()
	}

	/// A flask breaks: a patch of fire on the ground below, and everything in it starts burning
	func burstFlask(_ x: Double, _ y: Double, _ src: DamageSource) {
		let gx: Int = Int(floor(x))
		var gy: Double = y
		let ground: Int = world.groundBelow(gx, Int(floor(y)))
		if Double(ground) - y < 4.0 { gy = Double(ground) }
		if fireZones.count >= 6 { fireZones.removeFirst() }
		var z = FireZone(x: x, y: gy, r: 2.2, t: 3.5, uid: newID())
		z.tick = 0.35
		fireZones.append(z)
		sfx(.flask, at: x, 0.9)
		spawnParticles(x, gy - 0.4, 0xFF8030, 14, 5.0, 0.6, -2)
		spawnParticles(x, y, 0xB8E0F0, 6, 4.0, 0.3, 18)
		addLightFlash(x, gy - 0.8, peak: 12, dur: 0.5, radius: 3.0)
		_ = src
	}

	// MARK: storm rod

	/// Lightning down the aim to the first creature in its path, then leaping to up to three more
	/// close by (each strike a little weaker); creatures standing in water take half as much again
	func fireStormRod() {
		let ox: Double = pb.x + Double(facing) * 0.4
		let oy: Double = pb.y - 1.25
		facing = aimFacing()
		let ang: Double = atan2(aimY - oy, aimX - ox)
		let dx: Double = cos(ang)
		let dy: Double = sin(ang)
		let maxL: Double = 14.0
		let ex: Double = ox + dx * maxL
		let ey: Double = oy + dy * maxL
		var endT: Double = 1.0
		if let w = world.segmentSolidT(ox, oy, ex, ey) { endT = w.2 }
		var first: Mob? = nil
		var ft: Double = endT
		for m in mobsNear(min(ox, ex) - 3, max(ox, ex) + 3) {
			if m.hp <= 0 || m.removed || m.downed { continue }
			if !canHarm(.player, targetFaction: faction(of: m), targetID: m.id, area: false) { continue }
			if let t = segmentBoxT(ox, oy, ex, ey, m.b.left - 0.15, m.b.top - 0.15, m.b.right + 0.15, m.b.y + 0.15), t < ft {
				ft = t
				first = m
			}
		}
		var anchors: [(Double, Double)] = [(ox, oy)]
		if let m0 = first {
			var chain: [Mob] = [m0]
			while chain.count < 4 {
				guard let cur = chain.last else { break }
				var next: Mob? = nil
				var nd: Double = 5.5 * 5.5
				for o in mobsNear(cur.b.x - 6, cur.b.x + 6) {
					if o.hp <= 0 || o.removed || o.downed || chain.contains(where: { $0 === o }) { continue }
					if !canHarm(.player, targetFaction: faction(of: o), targetID: o.id, area: false) { continue }
					let ddx: Double = o.b.x - cur.b.x
					let ddy: Double = o.b.cy - cur.b.cy
					let d2: Double = ddx * ddx + ddy * ddy
					if d2 < nd && world.lineClear(cur.b.x, cur.b.cy, o.b.x, o.b.cy) { nd = d2; next = o }
				}
				guard let n = next else { break }
				chain.append(n)
			}
			var dmg: Double = GunType.stormRod.damage
			var px: Double = ox
			for c in chain {
				var info = DamageInfo(amount: c.b.inWater ? dmg * 1.5 : dmg, type: .shock, source: .player)
				info.knock = 2.5
				info.originX = px
				info.originY = c.b.cy
				info.key = newID()
				if applyMobDamage(c, info) {
					lockTarget = c
					lockT = 2.0
				}
				anchors.append((c.b.x, c.b.cy))
				addLightFlash(c.b.x, c.b.cy, peak: 9, dur: 0.22, radius: 1.0, color: 0x6AA8FF)
				spawnParticles(c.b.x, c.b.cy, 0xD8F0FF, 4, 4.0, 0.2, 0)
				px = c.b.x
				dmg *= 0.8
			}
			if chain.count >= 2 {
				floatText("x" + String(chain.count), pb.x, pb.y - pb.h - 0.9, 0xB8E0FF)
				sfx(.multiHit, 0.5)
			}
		} else {
			anchors.append((ox + dx * maxL * endT, oy + dy * maxL * endT))
		}
		// a jagged line between the strikes
		var pts: [(Double, Double)] = [anchors[0]]
		var k: Int = 1
		while k < anchors.count {
			let a: (Double, Double) = anchors[k - 1]
			let b: (Double, Double) = anchors[k]
			let sx: Double = b.0 - a.0
			let sy: Double = b.1 - a.1
			let len: Double = max(0.01, sqrt(sx * sx + sy * sy))
			let steps: Int = max(2, Int(len / 1.2))
			for j in 1..<steps {
				let f: Double = Double(j) / Double(steps)
				let off: Double = Double.random(in: -0.35...0.35)
				pts.append((a.0 + sx * f - sy / len * off, a.1 + sy * f + sx / len * off))
			}
			pts.append(b)
			k += 1
		}
		if arcs.count > 6 { arcs.removeFirst() }
		arcs.append(ArcFX(pts: pts, life: 0.2))
		addLightFlash(ox + dx * 0.6, oy + dy * 0.6, peak: 8, dur: 0.15, radius: 0.7, color: 0x6AA8FF)
		sfx(.zap, 0.8)
		muzzleT = 0.08
		swingT = 0.12
		swingDir = facing
	}

	// MARK: effects, fire and recharge, once a frame

	func updateCombatFX(_ dt: Double) {
		if !slashes.isEmpty {
			for i in 0..<slashes.count { slashes[i].life -= dt }
			slashes.removeAll { $0.life <= 0 }
		}
		if !arcs.isEmpty {
			for i in 0..<arcs.count { arcs[i].life -= dt }
			arcs.removeAll { $0.life <= 0 }
		}
		if !fireZones.isEmpty { updateFireZones(dt) }
		// storm rods gather their charge back, one strike every few seconds, wherever they are carried
		rodT += dt
		if rodT >= GunType.stormRod.reloadTime {
			rodT = 0
			for i in 0..<inv.slots.count {
				if var st = inv.slots[i], case .gun(.stormRod) = st.item, st.extra < GunType.stormRod.magazine {
					st.extra += 1
					inv.slots[i] = st
					if i == sel { bumpHUD() }
				}
			}
		}
	}

	func updateFireZones(_ dt: Double) {
		var keep: [FireZone] = []
		for z0 in fireZones {
			var z: FireZone = z0
			z.t -= dt
			// rain puts fires out sooner
			let rain: Double = abs(z.x - pb.x) < 40 ? wxHere.precip : precipAt(z.x)
			if rain > 0.05 && !wxHere.snow { z.t -= dt * 2.0 * rain }
			z.tick += dt
			if z.tick >= 0.35 {
				z.tick = 0
				let src: DamageSource = z.env ? .environment : .player
				let hurtsMobs: Bool = !z.env || settings.weatherHurtsCreatures
				for m in mobsNear(z.x - z.r - 2, z.x + z.r + 2) where hurtsMobs {
					if m.hp <= 0 || m.removed { continue }
					if abs(m.b.x - z.x) > z.r + m.b.w * 0.5 { continue }
					if m.b.y < z.y - 2.4 || m.b.top > z.y + 0.4 { continue }
					if !canHarm(src, targetFaction: faction(of: m), targetID: m.id, area: true) { continue }
					var info = DamageInfo(amount: 2.0, type: .fire, source: src)
					info.originX = z.x
					info.key = z.uid
					info.cooldown = 0.3
					if applyMobDamage(m, info) && !heatImmune(m) { m.burn = max(m.burn, 2.5) }
				}
				// the thrower is not spared if they stand in it
				let hurtsPlayer: Bool = !z.env || settings.weatherHurtsPlayer
				if hurtsPlayer && !dead && abs(pb.x - z.x) < z.r + pb.w * 0.5 && pb.y > z.y - 2.0 && pb.top < z.y + 0.3 && !wearing(.emberCharm) {
					playerBurn = max(playerBurn, 0.8)
				}
				if z.t > 0.3 { spawnParticles(z.x + Double.random(in: -z.r...z.r), z.y - 0.3, 0xFFA030, 2, 1.5, 0.45, -5) }
			}
			if z.t > 0 { keep.append(z) }
		}
		fireZones = keep
	}

	/// What an abandoned ore cart still holds: a little ore, fixed by where it stands
	func oreCartLoad(_ x: Int, _ y: Int) -> [Stack] {
		var rng = RNG(hashU(x, y, gen.seed &+ 991))
		let deep: Bool = y > 230
		let kinds: [Mat] = deep ? [.ironOre, .silverOre, .coal, .tinOre, .goldOre] : [.coal, .copperOre, .tinOre, .coal, .ironOre]
		var out: [Stack] = []
		let a: Mat = kinds[rng.int(kinds.count)]
		out.append(Stack(item: .mat(a), count: 2 + rng.int(4)))
		if rng.double() < 0.5 {
			let b: Mat = kinds[rng.int(kinds.count)]
			if b != a { out.append(Stack(item: .mat(b), count: 1 + rng.int(3))) }
		}
		return out
	}
}

// ===== p17_vehicles_ships =====

// MARK: - Vehicle driving and rigid-body physics

/// One collision sample on a vehicle part: where it is on the part (vehicle space), whether it
/// belongs to a wheel (wheels roll and push), and whether block corners act as ramps for it
/// (wheels and the underside of hulls, so cars climb steps and boats slide on and off beaches)
struct VSample {
	var lx: Double
	var ly: Double
	var wheel: Bool
	var ramp: Bool
	var hull: Bool
	/// a track (grips harder than a wheel and rolls less freely)
	var track: Bool = false
	/// a rail wheel (rolls almost freely on rails, drags elsewhere)
	var rail: Bool = false
	/// the cell it belongs to (a hard crash damages that part)
	var cx: Int = 0
	var cy: Int = 0
}

/// Water a part displaces when fully under (in tiles of water). Every part floats a little; hulls a
/// lot. Parts without displacement (the old model) made engines and propellers drag boats under.
func partDisplacement(_ p: PartType) -> Double {
	switch p {
	case .hinge, .servo, .piston: return 0.5
	case .receiver: return 0.2
	case .railWheel: return 0.5
	case .coupler: return 0.3
	case .bigWheel: return 3.0
	case .flap: return 0.3
	case .airBrake, .stabilizer: return 0.2
	case .ballast: return 1.0
	case .hull: return 4.0
	case .fuelTank: return 1.0
	case .frame: return 0.8
	case .seat: return 0.5
	case .wheel: return 0.5
	case .engine: return 0.7
	case .steering: return 0.2
	case .propeller: return 0.25
	case .paddle: return 0.3
	case .drill, .diamondDrill, .voidDrill: return 0.3
	case .offroadWheel: return 0.5
	case .headlight: return 0.2
	case .cargo: return 0.9
	case .block: return 1.0
	case .cockpit: return 0.6
	case .wing: return 0.3
	case .elevator: return 0.2
	case .airProp: return 0.25
	case .jet: return 0.6
	case .rotor: return 0.3
	case .tailRotor: return 0.2
	case .envelope: return 0.15
	case .burner: return 0.4
	case .track: return 0.6
	case .armor: return 0.5
	case .cannon: return 0.6
	case .autoGun: return 0.3
	case .autopilot: return 0.2
	}
}

/// Fixed physics step for vehicles (seconds). Simulating in fixed steps makes boats and cars behave
/// the same at 30 and 60 frames per second.
let vehicleStep: Double = 1.0 / 120.0

/// One place a vehicle touches the land in a physics step: where (from its centre of mass), which way
/// the surface faces, how hard a push there turns and moves it, how fast it must be leaving the surface
/// afterwards (its bounce), its grip, and the pushes given so far along the surface's face and along it
struct VContact {
	var rx: Double
	var ry: Double
	var nx: Double
	var ny: Double
	var rn: Double
	var kn: Double
	var rt: Double
	var kt: Double
	var want: Double
	var mu: Double
	var jn: Double = 0
	var jt: Double = 0
	/// a wheel's contact, and the grip of what it touches (for driving along it)
	var wheel: Bool = false
	var grip: Double = 1
	/// another vehicle it touches (nil: the land): where the place is from that one's centre of mass, how
	/// hard a push there turns it, and how easily it moves (0 while it is at rest or not being stepped)
	var other: Vehicle? = nil
	var ox: Double = 0
	var oy: Double = 0
	var on: Double = 0
	var ot: Double = 0
	var oInvM: Double = 0
	var oInvI: Double = 0
}

/// Per-frame contact summary gathered over the fixed steps
struct VStepStats {
	var anyHits: Int = 0
	var wheelHits: Int = 0
	var wet: Double = 0
	var nearWater: Bool = false
	var rammed: [(Int, Int)] = []
	/// the hardest hit each part took (speed into the ground beyond what it shrugs off)
	var crash: [PartCell: Double] = [:]
	/// hard hits on other vehicles' cells (their id, the cell, the speed beyond a landing)
	var crashOther: [(Int, PartCell, Double)] = []
	/// the vehicle it last stood on (0: none)
	var restOn: Int = 0
}

/// How far a vehicle met by another in one step is to be moved out of it (the most each way)
struct VPush {
	let o: Vehicle
	var right: Double = 0
	var left: Double = 0
	var down: Double = 0
	var up: Double = 0
}

/// What a vehicle met of the other vehicles in one step
struct VMeet {
	var hits: Int = 0
	/// its wheels standing on another vehicle, and the one most of them stand on (it takes the
	/// push back when they drive)
	var wheelsUnder: Int = 0
	var wheelOn: Vehicle? = nil
	var wheelOnN: Int = 0
	var right: Double = 0
	var left: Double = 0
	var down: Double = 0
	var up: Double = 0
	var pushes: [VPush] = []
}

/// One vehicle's frame of physics while all of them are stepped together
final class VRun {
	let v: Vehicle
	let samples: [VSample]
	let throttle: Double
	let airBusy: Bool
	let n: Int
	var stats: VStepStats = VStepStats()
	/// the other vehicles near enough to meet it this frame
	var near: [Vehicle] = []
	/// where it was at the start of the frame (a machine's sections judge stillness by how far they went)
	let x0: Double
	let y0: Double
	let a0: Double

	init(_ v: Vehicle, _ samples: [VSample], _ throttle: Double, _ airBusy: Bool, _ n: Int) {
		self.v = v
		self.samples = samples
		self.throttle = throttle
		self.airBusy = airBusy
		self.n = n
		self.x0 = v.px
		self.y0 = v.py
		self.a0 = v.angle
	}
}

extension Game {
	func updateVehicles(_ dt: Double) {
		let t0: Double = perfNow()
		radioControls(dt)
		jointControls(dt)
		stepVehicles(vehicles, dt)
		formCouplings(dt)
		// weapons, the autopilot, turns and damage (also for a vehicle at rest)
		for v in vehicles { vehicleExtras(v, dt) }
		flushVehicleBlasts()
		if vehicles.contains(where: { $0.parts.isEmpty }) { vehicles.removeAll { $0.parts.isEmpty } }
		Perf.shared.physMs = Perf.smooth(Perf.shared.physMs, perfNow() - t0)
	}

	/// What the player weighs on whatever they stand on (a vehicle frame is 1)
	var playerMass: Double { return Phys.playerMass }

	/// The seat the driver sits in: the one they got in by, or else the first (topmost, then leftmost)
	func seatCell(_ v: Vehicle) -> PartCell? {
		if let c = v.seatAt, let t = v.parts[c], t == .seat || t == .cockpit { return c }
		var best: PartCell? = nil
		for (c, t) in v.parts where t == .seat || t == .cockpit {
			if let b = best, b.dy < c.dy || (b.dy == c.dy && b.dx < c.dx) { continue }
			best = c
		}
		return best
	}

	/// Collision samples: the four corners and edge midpoints of square parts; a ring for wheels.
	/// Hull samples follow the visible hull (its art leaves the top quarter of the cell empty).
	func vehicleSamples(_ v: Vehicle) -> [VSample] {
		// (worked out again only when the vehicle changes: a big ship has thousands)
		if v.sampleKey == v.artRev && !v.sampleCache.isEmpty { return v.sampleCache }
		let made: [VSample] = makeVehicleSamples(v)
		v.sampleCache = made
		v.sampleKey = v.artRev
		return made
	}

	func makeVehicleSamples(_ v: Vehicle) -> [VSample] {
		var out: [VSample] = []
		out.reserveCapacity(v.parts.count * 8)
		// on a boat every part slides like a hull (engine and propeller included)
		let boat: Bool = v.buoyancy > 0 && v.wheels < 2
		for (c, t) in v.parts {
			let x0: Double = Double(c.dx)
			let y0: Double = Double(c.dy)
			if isWheelPart(t) {
				if let m = v.spanOf[c], m != c { continue }
				var k: Int = 0
				let tr: Bool = t == .track
				// (a big wheel: one ring three cells across round its middle)
				let big: Bool = t == .bigWheel
				let r: Double = big ? 1.47 : 0.47
				let n: Int = big ? 22 : 10
				while k < n {
					let a: Double = Double(k) / Double(n) * 2.0 * Double.pi
					var smp: VSample = VSample(lx: x0 + 0.5 + cos(a) * r, ly: y0 + 0.5 + sin(a) * r, wheel: true, ramp: true, hull: false, track: tr, cx: c.dx, cy: c.dy)
					smp.rail = t == .railWheel
					out.append(smp)
					k += 1
				}
			} else {
				let isHull: Bool = t == .hull
				let top: Double = isHull ? 0.25 : 0.02
				let mid: Double = isHull ? 0.6 : 0.5
				let pts: [(Double, Double)] = [(0.02, top), (0.5, isHull ? 0.25 : 0.0), (0.98, top), (1.0, mid), (0.98, 0.98), (0.5, 1.0), (0.02, 0.98), (0.0, mid)]
				for p in pts {
					// only outer edges can touch the world
					let nx: Int = p.0 < 0.25 ? -1 : (p.0 > 0.75 ? 1 : 0)
					let ny: Int = p.1 < 0.3 ? -1 : (p.1 > 0.75 ? 1 : 0)
					let openX: Bool = nx == 0 || v.parts[PartCell(dx: c.dx + nx, dy: c.dy)] == nil
					let openY: Bool = ny == 0 || v.parts[PartCell(dx: c.dx, dy: c.dy + ny)] == nil
					if openX || openY {
						out.append(VSample(lx: x0 + p.0, ly: y0 + p.1, wheel: false, ramp: (isHull || boat) && p.1 > 0.75, hull: isHull || boat, cx: c.dx, cy: c.dy))
					}
				}
			}
		}
		return out
	}

	/// How far a point is inside solid ground and which way is out (the exposed face it is nearest).
	/// For ramp samples (wheels, hull bottoms), the top corner of a block with open space above acts
	/// like a slope, so cars roll up one-block steps and boats slide over beach steps instead of jamming.
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

	/// How much of a 1x1 part centred at (x, cy) is under water, 0...1, from the real water surface
	/// in that column (continuous, so buoyancy changes smoothly instead of in jumps)
	func submergedFraction(_ x: Double, _ cy: Double, reach: Double = 0) -> Double {
		let tx: Int = Int(floor(x))
		let bottom: Double = cy + 0.5 + reach
		let start: Int = Int(floor(cy - 0.5))
		let end: Int = Int(floor(bottom))
		var y: Int = start
		while y <= end {
			let t: Tile = world.tile(tx, y)
			if t.liquid {
				var top: Int = y
				if y == start {
					// already under at the part's top: find the surface above
					var k: Int = 0
					while k < 6 && world.tile(tx, top - 1).liquid { top -= 1; k += 1 }
				}
				// (the top cell may be only part full: its surface is lower)
				let surface: Double = Double(top) + 1.0 - world.liquidAmount(tx, top)
				return clampD(bottom - surface, 0, 1)
			}
			y += 1
		}
		return 0
	}

	/// How dense the liquid at a point is (water 1; no liquid: water's)
	func liquidDensity(_ x: Double, _ y: Double) -> Double {
		let t: Tile = world.tile(Int(floor(x)), Int(floor(y + 0.4)))
		if !t.liquid || t == .water { return 1.0 }
		return Liquids.def(t)?.density ?? 1.0
	}

	/// True when every chunk under (and next to) the vehicle is loaded. Otherwise the vehicle waits:
	/// unloaded chunks read as stone, which used to shove boats and cars around at chunk edges.
	func vehicleAreaLoaded(_ v: Vehicle) -> Bool {
		let c0: Int = floorDiv(Int(floor(v.b.left)) - 2, chunkW)
		let c1: Int = floorDiv(Int(floor(v.b.right)) + 2, chunkW)
		var c: Int = c0
		while c <= c1 {
			if world.chunks[c] == nil && world.inRange(c) { return false }
			c += 1
		}
		return true
	}

	/// One vehicle's frame of physics (the others it meets are pushed, but not stepped)
	func stepVehicle(_ v: Vehicle, _ dt: Double) {
		stepVehicles([v], dt)
	}

	/// Every vehicle's physics for one frame, in step with each other: fixed step k of every vehicle is
	/// done before step k + 1 of any, so vehicles that meet push each other at the same moment. Each one
	/// still splits its own steps as finely as its speed (and how fast it closes on the others) needs.
	func stepVehicles(_ list: [Vehicle], _ dt: Double) {
		var runs: [VRun] = []
		var resting: [Vehicle] = []
		for v in list {
			if let r = startVehicleFrame(v, dt) { runs.append(r) } else if v.asleep && v.restOn != 0 { resting.append(v) }
		}
		// a vehicle at rest on another that moves now wakes with it (it is carried, or slides off)
		for v in resting {
			guard let o = vehicleByID(v.restOn), runs.contains(where: { $0.v === o }) else { continue }
			v.asleep = false
			v.sleepT = 0
			if let r = startVehicleFrame(v, dt) { runs.append(r) }
		}
		if runs.isEmpty { return }
		for r in runs { r.v.inStep = true }
		if vehicles.count > 1 {
			for r in runs { r.near = vehiclesNear(r.v, dt) }
		}
		var most: Int = 0
		for r in runs { most = max(most, r.n) }
		var k: Int = 0
		let linked: Bool = vehicles.contains { !$0.links.isEmpty }
		let jointed: Bool = vehicles.contains { !$0.joints.isEmpty }
		while k < most {
			for r in runs where k < r.n { vehicleFixedStep(r) }
			if linked { solveCouplings(vehicleStep) }
			if jointed { solveJoints(vehicleStep) }
			k += 1
		}
		for r in runs { r.v.inStep = false }
		for r in runs { finishVehicleFrame(r, dt) }
	}

	/// The other vehicles a vehicle could meet this frame (boxes within what both can travel)
	func vehiclesNear(_ v: Vehicle, _ dt: Double) -> [Vehicle] {
		var out: [Vehicle] = []
		let t: Double = min(dt, 0.1)
		let mine: Double = (v.speed + abs(v.angVel) * v.radius) * t + 0.6
		for o in vehicles where o !== v && !o.parts.isEmpty {
			let r: Double = mine + (o.speed + abs(o.angVel) * o.radius) * t
			if o.b.right < v.b.left - r || o.b.left > v.b.right + r || o.b.y < v.b.top - r || o.b.top > v.b.y + r { continue }
			out.append(o)
		}
		return out
	}

	/// Before a vehicle's fixed steps: whether it moves at all this frame (a vehicle at rest stays at rest
	/// until something wakes it), and how many fixed steps it takes
	func startVehicleFrame(_ v: Vehicle, _ dt: Double) -> VRun? {
		if !vehicleAreaLoaded(v) { return nil }
		let throttle: Double = v.rider || v.auto != 0 || v.signalDrive ? v.throttle : 0
		let airBusy: Bool = v.aero && (abs(v.pitch) > 0.05 || v.heat > 0.02 || v.collective > 0.02 || v.turnT > 0)
		if v.asleep && abs(throttle) < 0.05 && !v.drilling && !airBusy {
			// resting vehicles cost nothing until something wakes them (one resting on another vehicle
			// sleeps while that one does)
			var held: Bool = world.boxSolid(v.b.left + 0.05, v.b.y + 0.02, v.b.right - 0.05, v.b.y + 0.2) || v.submerged > 0
			if v.restOn != 0 { held = vehicleByID(v.restOn)?.asleep ?? false }
			// (a section of a machine is held by the one it hangs from)
			if v.parentID != 0 { held = vehicleByID(v.parentID)?.asleep ?? false }
			if held { return nil }
		}
		v.asleep = false
		let samples: [VSample] = vehicleSamples(v)
		// fixed steps: the same motion whatever the frame rate (leftover time carries to the next frame)
		v.physAccum += min(dt, 0.1)
		var n: Int = Int(v.physAccum / vehicleStep)
		if n > 12 { n = 12; v.physAccum = 0 } else { v.physAccum -= Double(n) * vehicleStep }
		return VRun(v, samples, throttle, airBusy, n)
	}

	/// One fixed step of a vehicle, split as often as its speed needs
	func vehicleFixedStep(_ r: VRun) {
		let v: Vehicle = r.v
		// Nothing may move further than Phys.maxStep between collision checks, however fast it goes:
		// the step is split as often as the speed needs. With no land or water anywhere it could
		// reach in this step there is nothing to check against, and one step does (open sky is free).
		let fast: Double = v.speed + abs(v.angVel) * v.radius
		let travel: Double = fast * vehicleStep
		var split: Int = 1
		var open: Bool = false
		if travel > Phys.maxStep * 0.5 || v.contacts == 0 {
			let rr: Double = travel + 1.0
			open = world.boxOpen(v.b.left - rr, v.b.top - rr, v.b.right + rr, v.b.y + rr)
			if !open { split = min(Phys.maxSplit, max(1, Int(ceil(travel / Phys.maxStep)))) }
		}
		if !r.near.isEmpty {
			// another vehicle is near: as fine as the two close on each other
			var other: Double = 0
			for o in r.near { other = max(other, o.speed + abs(o.angVel) * o.radius) }
			let closing: Double = (fast + other) * vehicleStep
			split = max(split, min(Phys.maxSplit, max(1, Int(ceil(closing / Phys.maxStep)))))
		}
		var s: Int = 0
		while s < split {
			vehicleSubstep(v, vehicleStep / Double(split), r.samples, r.throttle, &r.stats, open: open, near: r.near)
			s += 1
		}
		if split > 1 || open || !r.near.isEmpty { v.updateBox() }
	}

	/// After a vehicle's fixed steps: blocks it rammed, what it touched, crashes, fuel, exhaust, drills,
	/// creatures it hit, and whether it can rest now
	func finishVehicleFrame(_ r: VRun, _ dt: Double) {
		let v: Vehicle = r.v
		let throttle: Double = r.throttle
		let airBusy: Bool = r.airBusy
		let n: Int = r.n
		let stats: VStepStats = r.stats
		for rm in stats.rammed where world.tile(rm.0, rm.1).solid {
			breakTile(rm.0, rm.1, v.rider)
			addShake(0.25)
			v.vx *= 0.6
		}
		if n > 0 {
			v.wheelContacts = stats.wheelHits
			// (what other vehicles met of it counts as touching too)
			v.contacts = stats.anyHits + v.touched
			v.submerged = stats.wet / Double(n)
			v.restOn = stats.restOn != 0 ? stats.restOn : v.leanOn
		}
		v.touched = 0
		v.leanOn = 0
		if !stats.crash.isEmpty { crashDamage(v, stats.crash) }
		for hit in stats.crashOther {
			if let o = vehicleByID(hit.0) { crashDamage(o, [hit.1: hit.2]) }
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
		v.propRot += (abs(throttle) > 0.1 && v.submerged > 0 ? 18.0 : 3.0) * dt
		v.updateBox()
		if v.drills > 0 { runDrills(v, dt) }
		vehicleImpacts(v, dt)
		// resting (on the ground, or floating calmly): let it sleep so it stops costing time and cannot jitter
		var calm: Bool = v.speed < 0.08 && abs(v.angVel) < 0.03 && abs(throttle) < 0.05 && !v.drilling && !airBusy
		if v.parentID != 0 || !v.joints.isEmpty {
			// (a section's joints leave it a little speed each step that its next step takes away again:
			// what counts is how far it really went this frame)
			let went: Double = hypot(v.px - r.x0, v.py - r.y0) / max(dt, 1e-6)
			let turned: Double = abs(v.angle - r.a0) / max(dt, 1e-6)
			calm = went < 0.08 && turned < 0.03 && abs(throttle) < 0.05 && !v.drilling && !airBusy
		}
		// (a section of a machine is held up by the one it hangs from: the machine rests as one)
		if calm && (v.contacts > 0 || v.submerged > 0 || v.parentID != 0) {
			v.sleepT += dt
			if v.sleepT > (v.submerged > 0 ? 1.5 : 0.6) { v.asleep = true; v.vx = 0; v.vy = 0; v.angVel = 0 }
		} else {
			v.sleepT = 0
		}
		if v.py > Double(world.H) + 5 {
			v.py = Double(world.H) - 6
			v.vy = 0
		}
	}

	/// One fixed physics step: gravity, buoyancy and water drag per part, propulsion, contacts with
	/// impulses and friction, positional correction, stability assists
	func vehicleSubstep(_ v: Vehicle, _ h: Double, _ samples: [VSample], _ throttle: Double, _ stats: inout VStepStats, open: Bool = false, near: [Vehicle] = []) {
		let steerOK: Bool = v.hasSeat && v.hasSteering
		let hasFuel: Bool = v.fuel > 0 || isCreative
		let invM: Double = 1.0 / v.mass
		let invI: Double = 1.0 / v.inertia
		v.vy += gravityG * h
		let c: Double = v.cosA
		let s: Double = v.sinA
		// buoyancy and water drag, part by part, from how deep each part really is: boats settle at
		// the waterline, tilt back level by themselves and stop bobbing quickly
		var wetSum: Double = 0
		var hullWet: Double = 0
		var hullN: Int = 0
		var nearWater: Bool = false
		for (cell, t) in v.parts {
			if open { break }
			let lx: Double = Double(cell.dx) + 0.5 - v.comX
			let ly: Double = Double(cell.dy) + 0.5 - v.comY
			let wx: Double = v.px + lx * c - ly * s
			let wy: Double = v.py + lx * s + ly * c
			let f: Double = submergedFraction(wx, wy)
			if t == .hull { hullN += 1; hullWet += f }
			if f <= 0 {
				if t == .hull && !nearWater && submergedFraction(wx, wy, reach: 1.5) > 0 { nearWater = true }
				continue
			}
			nearWater = true
			wetSum += f
			// (what it floats in: lava holds things up three times as hard as water)
			let disp: Double = cellDisplacement(v, cell, t) * liquidDensity(wx, wy)
			let rx: Double = wx - v.px
			let ry: Double = wy - v.py
			let pvx: Double = v.vx - v.angVel * ry
			let pvy: Double = v.vy + v.angVel * rx
			// (a share of the water's drag grows with the square of the speed: what holds a fast boat back)
			let fx: Double = -pvx * (0.35 + 0.3 * disp + Drive.waterDrag * disp * abs(pvx)) * f
			let fy: Double = -gravityG * disp * f - pvy * 4.5 * disp * f
			v.vx += fx * invM * h
			v.vy += fy * invM * h
			v.angVel += (rx * fy - ry * fx) * invI * h
		}
		if !open && !v.hullAir.isEmpty { hullAirForces(v, h, c, s) }
		if v.railWheels > 0 && !open { railHold(v, h) }
		let sub: Double = wetSum / Double(max(1, v.parts.count))
		// how deep the hulls sit: about 0.4 when floating freely, falling as a boat runs aground
		let hullDepth: Double = hullN > 0 ? hullWet / Double(hullN) : sub
		stats.wet += sub
		if nearWater { stats.nearWater = true }
		if sub > 0 {
			// water resists rotation, and a keel keeps a floating hull level with the surface
			let grip: Double = min(1.0, hullDepth * 4.0)
			let a: Double = remainder(v.angle, 2.0 * Double.pi)
			if abs(a) < 2.6 { v.angVel -= sin(a) * 36.0 * grip * h }
			v.angVel *= (1.0 - min(1.0, 3.5 * grip * h))
		}
		// boat propulsion along the water (horizontal, so a tilted hull cannot dive or climb on thrust).
		// A boat grounded at the edge of the water can still push itself back off.
		if steerOK && abs(throttle) > 0.1 && v.buoyancy > 0 && (sub > 0 || (nearWater && stats.anyHits > 0)) {
			// a propeller pushes with the engines' power (so its push falls as the boat gains speed); a
			// paddle's stroke only goes so fast. What a boat reaches is where that meets the water's drag.
			var thrust: Double = 0
			let going: Double = v.vx * throttle > 0 ? abs(v.vx) : 0
			if v.engines > 0 && v.openProps > 0 && hasFuel {
				thrust = min(Double(v.engines) * 16.0, Double(v.engines) * Drive.propPower / max(going, 0.1))
			} else if v.openPaddles > 0 {
				thrust = Double(v.openPaddles) * 9.0 * max(0, 1.0 - going / Drive.paddleStroke)
			}
			if sub <= 0 { thrust *= 0.45 }
			// touching the bottom: thrust fades as the hull comes out of the water, so a boat runs
			// aground at the shoreline instead of motoring up the beach (reversing off still works)
			if stats.anyHits > 0 && throttle * v.vx >= 0 {
				let landward: Bool = submergedFraction(v.px + Double(throttle > 0 ? 1 : -1) * (v.b.w * 0.5 + 0.5), v.py) <= 0
				if landward { thrust *= clampD((hullDepth - 0.12) / 0.25, 0, 1) }
			}
			v.vx += thrust * throttle * invM * h
		}
		// lift, drag and thrust in the air, part by part (wings, rotors, balloons, propellers, jets)
		if v.aero { airForces(v, h, throttle) }
		// integrate
		v.px += v.vx * h
		v.py += v.vy * h
		v.angle += v.angVel * h
		// contacts
		let c2: Double = v.cosA
		let s2: Double = v.sinA
		// deepest penetration per direction; pushing out by the maximum (not the sum) keeps many
		// simultaneous contacts from launching the vehicle, and the push per step is capped so a
		// vehicle never jumps when it ends up overlapping blocks (chunk loads, placed blocks)
		var outUp: Double = 0
		var outDown: Double = 0
		var outLeft: Double = 0
		var outRight: Double = 0
		var stepWheel: Int = 0
		var hits: Int = 0
		vContacts.removeAll(keepingCapacity: true)
		for smp in samples {
			if open { break }
			let lx: Double = smp.lx - v.comX
			let ly: Double = smp.ly - v.comY
			let rx: Double = lx * c2 - ly * s2
			let ry: Double = lx * s2 + ly * c2
			let wx: Double = v.px + rx
			let wy: Double = v.py + ry
			// (a rail wheel rides the rails' smooth surface where there are rails)
			let found: (Double, Double, Double)? = smp.rail ? railPenetration(wx, wy) : penetration(wx, wy, wheel: smp.ramp)
			guard let pen = found else { continue }
			let depth: Double = pen.0
			let nx: Double = pen.1
			let ny: Double = pen.2
			hits += 1
			if smp.wheel && ny < -0.5 { stepWheel += 1 }
			// velocity of the contact point
			let pvx: Double = v.vx - v.angVel * ry
			let pvy: Double = v.vy + v.angVel * rx
			let vn: Double = pvx * nx + pvy * ny
			// ramming: a hard hit knocks out weak wooden builds (planks, log blocks). Terrain (dirt,
			// sand, stone) never gets dug out, and tree trunks have no collision, so they never get here.
			if vn < -5.5 && v.mass * -vn > 25.0 {
				let tt: Tile = world.tile(Int(floor(wx)), Int(floor(wy)))
				if tt.hardness <= 1.0 && tt != .doorClosed && toolClass(tt) == .axe { stats.rammed.append((Int(floor(wx)), Int(floor(wy)))) }
			}
			// a crash: hitting the ground far faster than any landing breaks the part that hits (wheels and
			// tracks take a harder landing first)
			let crashAt: Double = smp.wheel ? vehicleCrashSpeed + 5.0 : vehicleCrashSpeed
			if vn < -crashAt {
				let pc: PartCell = PartCell(dx: smp.cx, dy: smp.cy)
				stats.crash[pc] = max(stats.crash[pc] ?? 0, -vn - crashAt)
			}
			// what it touches: ice grips far less than stone, hay gives a little back
			let ground: BlockPhys = blockPhys(world.tile(Int(floor(wx)), Int(floor(wy))))
			let rn: Double = rx * ny - ry * nx
			let tx: Double = -ny
			let ty: Double = nx
			let rt: Double = rx * ty - ry * tx
			let vt: Double = pvx * tx + pvy * ty
			// friction along the surface; wheels roll unless braking, hulls slide on sand and stone.
			// A boat's parts slide on sand and stone, very easily while it is still partly afloat (so it
			// eases off a beach under its own power); car bodies grip
			var mu: Double = smp.hull ? (sub > 0 ? 0.05 : 0.22) : 0.7
			if smp.wheel {
				// an aircraft's wheels roll free on the throttle and brake without it
				let braking: Bool = abs(throttle) < 0.1 || (throttle * vt < 0 && !v.aero)
				mu = braking ? (v.rider ? 0.9 : 0.25) : (v.aero ? 0.02 : 0.06)
				if smp.track { mu = braking ? (v.rider ? 1.1 : 0.4) : 0.14 }
				if smp.rail {
					// (a rail wheel coasts unless the driver pulls against the motion)
					let pulling: Bool = v.rider && abs(throttle) > 0.1 && throttle * vt < 0
					mu = railGrip(Int(floor(wx)), Int(floor(wy)), pulling, v.rider)
				}
			}
			let leave: Double = vn < 0 ? -max(0.04, ground.bounce) * vn : 0
			var kc: VContact = VContact(rx: rx, ry: ry, nx: nx, ny: ny, rn: rn, kn: invM + rn * rn * invI, rt: rt, kt: invM + rt * rt * invI, want: leave, mu: mu * ground.grip)
			kc.wheel = smp.wheel
			kc.grip = ground.grip
			vContacts.append(kc)
			let d: Double = min(0.12, max(0, depth - 0.01))
			if ny < -0.5 { outUp = max(outUp, d) } else if ny > 0.5 { outDown = max(outDown, d) }
			else if nx < -0.5 { outLeft = max(outLeft, d) } else { outRight = max(outRight, d) }
		}
		// other vehicles' cells it is inside: contacts that push both
		var meet: VMeet = VMeet()
		if !near.isEmpty { meetVehicleCells(v, samples, near, throttle, sub, &meet, &stats) }
		// The blows at every place it touches, worked out together: each is given what stops it going
		// into the surface there (and the little the surface gives back), then friction up to its grip,
		// and the round is gone through a few times so that what one place gives is taken into account
		// at the others. (One pass, as it used to be, gave a block landing flat far too much at its first
		// corner: it bounced high and spun, differently every time.)
		if !vContacts.isEmpty {
			var round: Int = 0
			while round < 4 {
				var i: Int = 0
				while i < vContacts.count {
					var k: VContact = vContacts[i]
					// (against another vehicle: the speed of one place against the other, and both pushed)
					let o: Vehicle? = k.oInvM > 0 ? k.other : nil
					var vn: Double = (v.vx - v.angVel * k.ry) * k.nx + (v.vy + v.angVel * k.rx) * k.ny
					if let ov = o { vn -= (ov.vx - ov.angVel * k.oy) * k.nx + (ov.vy + ov.angVel * k.ox) * k.ny }
					let jn0: Double = k.jn
					k.jn = max(0, jn0 + (k.want - vn) / k.kn)
					let dn: Double = k.jn - jn0
					if dn != 0 {
						v.vx += dn * k.nx * invM
						v.vy += dn * k.ny * invM
						v.angVel += k.rn * dn * invI
						if let ov = o {
							ov.vx -= dn * k.nx * k.oInvM
							ov.vy -= dn * k.ny * k.oInvM
							ov.angVel -= k.on * dn * k.oInvI
						}
					}
					let tx: Double = -k.ny
					let ty: Double = k.nx
					var vt: Double = (v.vx - v.angVel * k.ry) * tx + (v.vy + v.angVel * k.rx) * ty
					if let ov = o { vt -= (ov.vx - ov.angVel * k.oy) * tx + (ov.vy + ov.angVel * k.ox) * ty }
					let lim: Double = k.mu * k.jn
					let jt0: Double = k.jt
					k.jt = clampD(jt0 - vt / k.kt, -lim, lim)
					let dtn: Double = k.jt - jt0
					if dtn != 0 {
						v.vx += dtn * tx * invM
						v.vy += dtn * ty * invM
						v.angVel += k.rt * dtn * invI
						if let ov = o {
							ov.vx -= dtn * tx * k.oInvM
							ov.vy -= dtn * ty * k.oInvM
							ov.angVel -= k.ot * dtn * k.oInvI
						}
					}
					vContacts[i] = k
					i += 1
				}
				round += 1
			}
		}
		// (a machine's sections keep theirs: the joints are worked out with them, so a servo's turning
		// push on a section standing on the ground is held by its grip, not slid along)
		if v.parentID != 0 || !v.joints.isEmpty {
			v.heldContacts.removeAll(keepingCapacity: true)
			for k in vContacts where k.oInvM == 0 { v.heldContacts.append(k) }
		}
		v.px += (outRight - outLeft) * 0.8
		v.py += (outDown - outUp) * 0.8
		if meet.hits > 0 { settleVehicleMeet(v, meet) }
		hits += meet.hits
		stepWheel += meet.wheelsUnder
		stats.anyHits += hits
		stats.wheelHits = max(stats.wheelHits, stepWheel)
		let wrapped: Double = remainder(v.angle, 2.0 * Double.pi)
		// grounded stability assist: a tilted vehicle resting on something is eased back toward
		// upright, and rotation that would tip it further is damped. Flips stay possible in the air.
		if hits > 0 && abs(wrapped) > 0.4 && abs(wrapped) < 2.5 {
			v.angVel -= sin(wrapped) * 11.0 * h
			if v.angVel * wrapped > 0 { v.angVel *= (1.0 - min(1.0, 8.0 * h)) }
		}
		// engine drive through wheels that are on the ground
		// (only while roughly upright: a car on its nose or roof cannot push itself along)
		if stepWheel > 0 && v.canDriveOnLand && steerOK && hasFuel && abs(throttle) > 0.1 && abs(wrapped) < 1.0 && v.rotors == 0 {
			// tracks are slow but pull like nothing else
			let trackShare: Double = Double(v.tracks) / Double(max(1, v.wheels))
			let along: Double = v.vx * c2 + v.vy * s2
			// heavier builds accelerate and climb slower; more engines help, and offroad wheels pull
			// harder (their extra weight is the price)
			let grip: Double = 1.0 + 0.7 * Double(v.offroadWheels) / Double(max(1, v.wheels)) + 1.4 * trackShare
			let share: Double = groundShare(v)
			var push: Double = v.enginePower * 135.0 * grip * min(1.0, Double(stepWheel) / 4.0 + 0.5) * share
			// An engine gives so much power, so the push it can give falls as the speed rises (power is
			// push times speed), and the wheels, the gearing and the weight on them take a share that
			// grows with the speed. There is no top speed built in: a vehicle reaches the speed where
			// the two meet, so more engines or less weight is faster.
			let going: Double = along * throttle > 0 ? abs(along) : 0
			if going > 0.1 { push = min(push, v.enginePower * Drive.power * share / going) }
			let loss: Double = Drive.loss * (1.0 + Drive.lossPerMass * v.mass) * (1.0 + Drive.trackLoss * trackShare) * along * share
			let f: Double = push * throttle - loss
			v.vx += c2 * f * invM * h
			v.vy += s2 * f * invM * h
			// wheels driving on another vehicle push it back as hard
			if let o = meet.wheelOn, o.inStep && !o.asleep {
				let part: Double = Double(meet.wheelOnN) / Double(max(1, stepWheel))
				o.vx -= c2 * f * part / o.mass * h
				o.vy -= s2 * f * part / o.mass * h
			}
		} else if v.canDriveOnLand && steerOK && hasFuel && abs(throttle) > 0.1 && v.rotors == 0 {
			// not upright, or the wheels touch something beside or above it: each wheel that touches
			// pushes along what it touches, as hard as its grip there lets it
			wheelsAlongContacts(v, throttle, h)
		}
		if !v.aero {
			// the air against a vehicle with no wings (aircraft work theirs out part by part): it grows
			// with the square of the speed, on the faces that meet it
			let rho: Double = airDensity(v.py)
			// (the air moves too: a gale leans on a balloon of planks or a parked raft)
			let ax: Double = v.vx - v.windX
			v.vx -= Aero.kDrag * rho * Double(v.gridH) * ax * abs(ax) * invM * h
			v.vy -= Aero.kDrag * rho * Double(v.gridW) * v.vy * abs(v.vy) * invM * h
		}
		if hits == 0 && sub <= 0 && v.wheels > 0 && !v.aero {
			// airborne wheeled vehicles slowly level out and shed spin (arcade suspension: driving off a
			// ledge at speed no longer guarantees a nosedive)
			if abs(wrapped) < 2.0 { v.angVel -= sin(wrapped) * 4.0 * h }
			v.angVel *= (1.0 - min(1.0, 1.5 * h))
		}
		if hits == 0 && sub <= 0 && v.rider && abs(throttle) > 0.1 && !v.aero {
			// in the air the driver can lean the vehicle: gentle and capped, so holding the throttle over a
			// jump leans the car rather than spinning it (throttle leans back, reverse tips the nose down)
			if abs(v.angVel) < 2.5 || v.angVel * throttle > 0 { v.angVel -= throttle * 2.5 * h }
		}
		// a little rolling drag and air resistance
		v.vx *= (1.0 - min(1.0, 0.05 * h))
		v.angVel *= (1.0 - min(1.0, (hits > 0 ? 1.2 : 0.3) * h))
		// No limit on speed or spin: the sub-steps above keep fast things from passing through the land.
		// Only numbers that are no longer numbers are put right (they would spread to everything).
		if !(v.vx.isFinite && v.vy.isFinite && v.angVel.isFinite && v.px.isFinite && v.py.isFinite && v.angle.isFinite) {
			v.vx = 0
			v.vy = 0
			v.angVel = 0
			if !v.px.isFinite { v.px = v.b.x }
			if !v.py.isFinite { v.py = v.b.y - v.b.h * 0.5 }
			if !v.angle.isFinite { v.angle = 0 }
		}
	}

	/// Where a vehicle's collision samples are inside another vehicle's cells. Each becomes a contact
	/// that pushes both, by their masses, the way out of the other's nearest open face: a plane comes to
	/// rest on a carrier's deck and is carried by it (its grip there), a tank pushes a car, two cars that
	/// meet head on trade their speed. A vehicle at rest (or not moving this frame) is pushed against as
	/// if it were the land, and is woken by a hard enough blow.
	func meetVehicleCells(_ v: Vehicle, _ samples: [VSample], _ near: [Vehicle], _ throttle: Double, _ sub: Double, _ meet: inout VMeet, _ stats: inout VStepStats) {
		let c: Double = v.cosA
		let s: Double = v.sinA
		let invM: Double = 1.0 / v.mass
		let invI: Double = 1.0 / v.inertia
		let mine: Int = v.parentID != 0 || !v.joints.isEmpty ? machineRoot(v).id : -1
		for o in near {
			if o.parts.isEmpty { continue }
			// (the sections of one jointed machine pass each other: the joints hold them)
			if mine >= 0 && (o.parentID != 0 || !o.joints.isEmpty) && machineRoot(o).id == mine { continue }
			let gx: Double = o.px - v.px
			let gy: Double = o.py - v.py
			let reach: Double = v.radius + o.radius + 0.3
			if gx * gx + gy * gy > reach * reach { continue }
			let oDyn: Bool = o.inStep && !o.asleep
			let oInvM: Double = oDyn ? 1.0 / o.mass : 0
			let oInvI: Double = oDyn ? 1.0 / o.inertia : 0
			let oc: Double = o.cosA
			let os: Double = o.sinA
			// how much of the way out each one takes (all of it against one at rest)
			let mine: Double = oDyn ? o.mass / (v.mass + o.mass) : 1.0
			var push: VPush = VPush(o: o)
			var underHere: Int = 0
			for smp in samples {
				let lx: Double = smp.lx - v.comX
				let ly: Double = smp.ly - v.comY
				let rx: Double = lx * c - ly * s
				let ry: Double = lx * s + ly * c
				let dx: Double = v.px + rx - o.px
				let dy: Double = v.py + ry - o.py
				let ol: Double = dx * oc + dy * os + o.comX
				let om: Double = -dx * os + dy * oc + o.comY
				let cx: Int = Int(floor(ol))
				let cy: Int = Int(floor(om))
				let kind: UInt8 = o.meetAt(cx, cy)
				if kind == cellOpen { continue }
				guard let pen = cellPenetration(o, cx, cy, ol - Double(cx), om - Double(cy), kind, smp.ramp) else { continue }
				let nx: Double = pen.1 * oc - pen.2 * os
				let ny: Double = pen.1 * os + pen.2 * oc
				let pvx: Double = v.vx - v.angVel * ry - (oDyn ? o.vx - o.angVel * dy : 0)
				let pvy: Double = v.vy + v.angVel * rx - (oDyn ? o.vy + o.angVel * dx : 0)
				let vn: Double = pvx * nx + pvy * ny
				// a crash breaks the parts that meet, on both
				let crashAt: Double = smp.wheel ? vehicleCrashSpeed + 5.0 : vehicleCrashSpeed
				if vn < -crashAt {
					let pc: PartCell = PartCell(dx: smp.cx, dy: smp.cy)
					stats.crash[pc] = max(stats.crash[pc] ?? 0, -vn - crashAt)
					stats.crashOther.append((o.id, PartCell(dx: cx, dy: cy), (-vn - crashAt) * min(1.0, v.mass / o.mass)))
				}
				let here: BlockPhys = o.blocks[PartCell(dx: cx, dy: cy)].map { blockPhys($0) } ?? BlockPhys(weight: 1, carry: 1, span: 1)
				var mu: Double = smp.hull ? (sub > 0 ? 0.05 : 0.22) : 0.7
				if smp.wheel {
					let braking: Bool = abs(throttle) < 0.1
					mu = braking ? (v.rider ? 0.9 : 0.25) : (v.aero ? 0.02 : 0.06)
					if smp.track { mu = braking ? (v.rider ? 1.1 : 0.4) : 0.14 }
				}
				let rn: Double = rx * ny - ry * nx
				let on: Double = dx * ny - dy * nx
				let tx: Double = -ny
				let ty: Double = nx
				let rt: Double = rx * ty - ry * tx
				let ot: Double = dx * ty - dy * tx
				let kn: Double = invM + rn * rn * invI + oInvM + on * on * oInvI
				let kt: Double = invM + rt * rt * invI + oInvM + ot * ot * oInvI
				let leave: Double = vn < 0 ? -max(0.04, here.bounce) * vn : 0
				var k: VContact = VContact(rx: rx, ry: ry, nx: nx, ny: ny, rn: rn, kn: kn, rt: rt, kt: kt, want: leave, mu: mu * here.grip)
				k.wheel = smp.wheel
				k.grip = here.grip
				k.other = o
				k.ox = dx
				k.oy = dy
				k.on = on
				k.ot = ot
				k.oInvM = oInvM
				k.oInvI = oInvI
				vContacts.append(k)
				meet.hits += 1
				o.touched += 1
				if ny < -0.5 {
					stats.restOn = o.id
					if smp.wheel { meet.wheelsUnder += 1; underHere += 1 }
				} else if ny > 0.5 {
					// it is under the other one: that one rests on it
					o.leanOn = v.id
				}
				// out of each other: this one by its share, the other by the rest
				let d: Double = min(0.12, max(0, pen.0 - 0.01))
				let a: Double = d * mine
				let b: Double = d - a
				if nx > 0 { meet.right = max(meet.right, nx * a) } else { meet.left = max(meet.left, -nx * a) }
				if ny > 0 { meet.down = max(meet.down, ny * a) } else { meet.up = max(meet.up, -ny * a) }
				if oDyn && b > 0 {
					if nx > 0 { push.left = max(push.left, nx * b) } else { push.right = max(push.right, -nx * b) }
					if ny > 0 { push.up = max(push.up, ny * b) } else { push.down = max(push.down, -ny * b) }
				}
			}
			if oDyn && (push.right + push.left + push.up + push.down) > 0 { meet.pushes.append(push) }
			if underHere > meet.wheelOnN {
				meet.wheelOn = o
				meet.wheelOnN = underHere
			}
		}
	}

	/// How far a point is inside a vehicle's cell (fx, fy: where in the cell, 0...1) and which way is
	/// out, in that vehicle's own frame: the nearest face with no solid cell beyond it. A cell stood on
	/// from above only (a platform) is met near its top. For wheels and hull bottoms the top corner of a
	/// cell with open space above acts as a slope, as on the land (a car drives up onto a flatbed).
	func cellPenetration(_ o: Vehicle, _ cx: Int, _ cy: Int, _ fx: Double, _ fy: Double, _ kind: UInt8, _ ramp: Bool) -> (Double, Double, Double)? {
		if kind == cellRound {
			// a wheel: out from its middle
			let ex: Double = fx - 0.5
			let ey: Double = fy - 0.5
			let d: Double = sqrt(ex * ex + ey * ey)
			if d >= 0.47 { return nil }
			if d < 1e-6 { return (0.47, 0, -1) }
			return (0.47 - d, ex / d, ey / d)
		}
		let topOpen: Bool = o.meetAt(cx, cy - 1) != cellSolid
		if kind == cellPlatform { return topOpen && fy < 0.3 ? (fy, 0, -1) : nil }
		let leftOpen: Bool = o.meetAt(cx - 1, cy) != cellSolid
		let rightOpen: Bool = o.meetAt(cx + 1, cy) != cellSolid
		if ramp && topOpen && fy < 0.8 {
			if leftOpen && fx < fy { return (fy * 0.75, -0.6, -0.8) }
			if rightOpen && 1.0 - fx < fy { return (fy * 0.75, 0.6, -0.8) }
			return (fy, 0, -1)
		}
		if topOpen && fy < 0.3 { return (fy, 0, -1) }
		var best: Double = 9
		var nx: Double = 0
		var ny: Double = -1
		if topOpen { best = fy }
		if leftOpen && fx < best { best = fx; nx = -1; ny = 0 }
		if rightOpen && 1.0 - fx < best { best = 1.0 - fx; nx = 1; ny = 0 }
		if o.meetAt(cx, cy + 1) != cellSolid && 1.0 - fy < best { best = 1.0 - fy; nx = 0; ny = 1 }
		if best > 8 { return nil }
		return (best, nx, ny)
	}

	/// Moves two vehicles that overlap out of each other, each by its share (from meetVehicleCells),
	/// and wakes one at rest that was hit hard
	func settleVehicleMeet(_ v: Vehicle, _ meet: VMeet) {
		// (each vehicle also meets the other's samples, so each pair is settled from both sides: half each)
		v.px += (meet.right - meet.left) * 0.5
		v.py += (meet.down - meet.up) * 0.5
		for p in meet.pushes {
			p.o.px += (p.right - p.left) * 0.5
			p.o.py += (p.down - p.up) * 0.5
		}
		for k in vContacts where k.oInvM == 0 {
			guard let o = k.other, o.asleep else { continue }
			if k.jn / o.mass > 0.25 {
				o.asleep = false
				o.sleepT = 0
			}
		}
	}

	/// Wheels driving along whatever they touch (a wall the vehicle leans on, the ground when it lies on
	/// its side or roof): the engines' push is shared between the wheels that touch, each giving no more
	/// than its grip there allows. Upright on the ground the drive above is used instead.
	func wheelsAlongContacts(_ v: Vehicle, _ throttle: Double, _ h: Double) {
		var n: Int = 0
		for k in vContacts where k.wheel && k.jn > 0 { n += 1 }
		if n == 0 { return }
		let push: Double = v.enginePower * 135.0 * groundShare(v) * throttle / Double(n)
		let invM: Double = 1.0 / v.mass
		for k in vContacts where k.wheel && k.jn > 0 {
			let tx: Double = -k.ny
			let ty: Double = k.nx
			let lim: Double = Drive.tyreGrip * k.grip * k.jn
			let j: Double = clampD(push * h, -lim, lim)
			v.vx += tx * j * invM
			v.vy += ty * j * invM
			if let o = k.other, k.oInvM > 0 {
				o.vx -= tx * j * k.oInvM
				o.vy -= ty * j * k.oInvM
			}
		}
	}

	/// Hitting creatures (or the player) at speed hurts them according to speed and weight
	func vehicleImpacts(_ v: Vehicle, _ dt: Double) {
		let sp: Double = v.speed
		if sp < 4.0 { return }
		let src: DamageSource = v.rider ? .player : .environment
		let nudge: Double = 0.15
		// (the way it came this frame: at a few hundred blocks a second that is several blocks)
		let backX: Double = sp * dt > 0.6 ? v.vx * dt : 0
		let backY: Double = sp * dt > 0.6 ? v.vy * dt : 0
		let sweptL: Double = v.b.left - max(0, backX)
		let sweptR: Double = v.b.right - min(0, backX)
		let sweptT: Double = v.b.top - max(0, backY)
		let sweptB: Double = v.b.y - min(0, backY)
		for m in mobsNear(sweptL - 1, sweptR + 1) {
			if m.hp <= 0 || m.tame || m.b.ride == v.id { continue }
			if m.b.right < sweptL - nudge || m.b.left > sweptR + nudge || m.b.y < sweptT || m.b.top > sweptB { continue }
			// must actually touch a part, not just the box
			let cell: PartCell = v.cellAt(m.b.x, m.b.cy)
			var touching: Bool = v.parts[cell] != nil || backX != 0 || backY != 0
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
				// the creature's weight slows the vehicle (when the vehicle's cells push it along, that
				// push already takes it: see meetVehicles; this is for a blow in passing at high speed)
				if backX != 0 || backY != 0 { v.vx *= v.mass / (v.mass + mobMass(m) * 0.5) }
				addShake(0.12)
			}
		}
		if !v.rider && !dead && inVehicle !== v && pb.ride != v.id {
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
		for (cell, d) in v.drillDir where !v.boxed.contains(cell) {
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
			for m in mobsNear(tip.0 - 1, tip.0 + 1) where m.hp > 0 && !m.tame {
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
		// up and down on the stick: the elevators, the rotor's pitch, the burner
		var up: Double = -stickY
		if abs(up) < 0.15 { up = 0 }
		v.pitch = clampD(up, -1, 1)
		if v.auto != 0 { autopilotSteer(v, ix, up, dt) }
		if abs(v.throttle) > 0.05 || abs(v.pitch) > 0.05 { v.asleep = false }
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
			} else {
				leaveSeat(v)
			}
		}
	}

	/// Getting up from the seat. With a floor under the seat the player stands up where they sat, at any
	/// speed, and can walk about the vehicle while it carries on (the autopilot keeps its hands on the
	/// controls; without one the engines idle). With nothing to stand on they hop out as before, which
	/// only a slow vehicle allows.
	func leaveSeat(_ v: Vehicle) {
		if let c = seatCell(v) {
			let floorK: UInt8 = v.walkAt(c.dx, c.dy + 1)
			let headK: UInt8 = v.walkAt(c.dx, c.dy - 1)
			if floorK != cellOpen && headK != cellSolid {
				v.rider = false
				if v.auto == 0 {
					v.throttle = 0
					v.pitch = 0
				}
				inVehicle = nil
				boardFrame(&pb, v, Double(c.dx) + 0.5, Double(c.dy) + 1.0)
				pb.onGround = true
				fallPeak = 0
				if v.speed > 2.5 { say(v.auto != 0 ? "You stand up. The autopilot flies on." : "You stand up. Nobody is at the controls.", 2.5) }
				bumpHUD()
				return
			}
		}
		if v.speed < 2.5 {
			dismount()
		} else if v.contacts == 0 && v.submerged <= 0.02 {
			say("Nothing to stand on here. Put a floor under the seat to walk about in flight.", 3.0)
		} else {
			say("Slow down to get out (or put a floor under the seat).", 2.5)
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
				if isLogTile(t) { add = 14 }
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
		if repairVehiclePart(v, c) { return }
		if useVehicleBlock(v, c) { return }
		if let t = v.parts[c], t == .hinge || t == .servo || t == .piston, v.joints.contains(where: { $0.cell == c }), inVehicle == nil {
			jointEdit = JointRef(vid: v.id, cell: c)
			showJoint = true
			bumpHUD()
			return
		}
		if let t = v.parts[c], t == .cannon || t == .autoGun, inVehicle == nil {
			cycleGunMode(v, c)
			return
		}
		if v.parts[c] == .receiver && inVehicle == nil {
			radioEdit = v.id
			showRadio = true
			bumpHUD()
			return
		}
		if v.parts[c] == .coupler && v.links.contains(where: { $0.cell == c }) {
			uncouple(v, c)
			say("Uncoupled.", 1.2)
			return
		}
		if let t = v.parts[c], t == .seat || t == .steering || t == .cockpit {
			mountVehicle(v, at: t == .steering ? nil : c)
			return
		}
		if v.parts[c] != nil && vehicleStores(v, c) {
			let k: IntPair = cargoSpot(v, c)
			if world.chests[world.chestKey(k.x, k.y)] == nil { world.setChestItems(k.x, k.y, []) }
			openChest = k
			showInventory = true
			bumpHUD()
			return
		}
		if let t = v.parts[c], t == .wing || t == .flap || t == .elevator || t == .stabilizer, !v.rider, heldItem == nil || heldItem == .gadget(.wrench) {
			tiltWing(v, c)
			return
		}
		let massS: String = String(format: "%.1f", v.mass)
		let fuelA: Int = Int(v.fuel)
		let fuelB: Int = Int(v.fuelCapacity)
		var info: String = "Vehicle: mass \(massS), fuel \(fuelA)/\(fuelB)"
		if let d = v.dmg[c], d > 0.5, let t = v.parts[c] {
			let hpS: Int = Int(max(0, vehicleCellHP(v, c, t) - d))
			info = joinText(t == .block ? (v.blocks[c]?.name ?? "Block") : t.name, " damaged: ", String(hpS), " left. Hold an iron bar and tap it to mend it.")
			say(info, 3.0)
			return
		}
		if v.aero { say(joinText(info, ". ", vehicleCheck(v).hint), 3.5); return }
		if !v.hasSeat { info += ". Needs a seat." }
		else if !v.hasSteering { info += ". Needs a steering wheel." }
		else if v.buoyancy > 0 && !v.canSail && v.wheels < 2 { info += ". Add engine + propeller (or a paddle)." }
		else if v.wheels >= 2 && v.engines == 0 { info += ". Add an engine." }
		else { info += ". Tap the seat to drive." }
		say(info, 3.5)
	}

	/// Gets in to drive: in the seat tapped (with several seats), or the one sat in last
	func mountVehicle(_ v: Vehicle, at seatTapped: PartCell? = nil) {
		if !v.hasSeat || !v.hasSteering {
			say(v.hasSeat ? "Add a steering wheel (anywhere on it)." : "Add a seat or a cockpit first.", 2.5)
			return
		}
		if mounted != nil { dismount() }
		if let c = seatTapped { v.seatAt = c }
		seat = nil
		seatAboard = nil
		inVehicle = v
		pb.ride = 0
		v.rider = true
		v.asleep = false
		v.holdY = v.py
		let drillTip: String = v.drills > 0 ? " Drills spin while the engine runs." : ""
		let armed: String = v.cannons + v.guns > 0 ? " The attack stick fires the guns." : ""
		say(joinText(controlsHint(v), drillTip, armed), 4.0)
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
		// the engine sits on the hull (not out past its end, which tipped the old layout stern-down)
		return [KitPart(dx: 1, dy: 0, p: .engine), KitPart(dx: 2, dy: 0, p: .seat), KitPart(dx: 3, dy: 0, p: .steering), KitPart(dx: 4, dy: 0, p: .fuelTank),
				KitPart(dx: 0, dy: 1, p: .propeller), KitPart(dx: 1, dy: 1, p: .hull), KitPart(dx: 2, dy: 1, p: .hull), KitPart(dx: 3, dy: 1, p: .hull), KitPart(dx: 4, dy: 1, p: .hull)]
	case .planeKit:
		// a light plane, nose to the right: tail elevator, wings under the cockpit, engine and propeller in front
		return [KitPart(dx: 0, dy: 0, p: .elevator), KitPart(dx: 4, dy: 0, p: .cockpit),
				KitPart(dx: 0, dy: 1, p: .frame), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .wing), KitPart(dx: 3, dy: 1, p: .wing), KitPart(dx: 4, dy: 1, p: .wing),
				KitPart(dx: 5, dy: 1, p: .fuelTank), KitPart(dx: 6, dy: 1, p: .engine), KitPart(dx: 7, dy: 1, p: .airProp),
				KitPart(dx: 3, dy: 2, p: .wheel), KitPart(dx: 6, dy: 2, p: .wheel)]
	case .heliKit:
		// two engines under one rotor, a tail rotor on the boom, skids below
		return [KitPart(dx: 3, dy: 0, p: .rotor),
				KitPart(dx: 0, dy: 1, p: .tailRotor), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .frame), KitPart(dx: 3, dy: 1, p: .engine), KitPart(dx: 4, dy: 1, p: .cockpit),
				KitPart(dx: 3, dy: 2, p: .engine), KitPart(dx: 4, dy: 2, p: .fuelTank),
				KitPart(dx: 2, dy: 3, p: .frame), KitPart(dx: 3, dy: 3, p: .frame), KitPart(dx: 4, dy: 3, p: .frame)]
	case .airshipKit:
		// a balloon of 20 envelopes, two burners under it, a gondola with propellers at both ends
		var out: [KitPart] = []
		for x in 1...6 { out.append(KitPart(dx: x, dy: 0, p: .envelope)) }
		for x in 0...7 { out.append(KitPart(dx: x, dy: 1, p: .envelope)) }
		for x in 1...6 { out.append(KitPart(dx: x, dy: 2, p: .envelope)) }
		out.append(contentsOf: [KitPart(dx: 2, dy: 3, p: .frame), KitPart(dx: 3, dy: 3, p: .burner), KitPart(dx: 4, dy: 3, p: .burner), KitPart(dx: 5, dy: 3, p: .frame),
								KitPart(dx: 0, dy: 4, p: .airProp), KitPart(dx: 1, dy: 4, p: .frame), KitPart(dx: 2, dy: 4, p: .cockpit), KitPart(dx: 3, dy: 4, p: .engine),
								KitPart(dx: 4, dy: 4, p: .fuelTank), KitPart(dx: 5, dy: 4, p: .frame), KitPart(dx: 6, dy: 4, p: .airProp)])
		return out
	case .tankKit:
		// armour all round, a cannon on the turret, two engines, tracks the whole length
		var out: [KitPart] = [KitPart(dx: 3, dy: 0, p: .armor), KitPart(dx: 4, dy: 0, p: .cannon),
							  KitPart(dx: 1, dy: 1, p: .armor), KitPart(dx: 2, dy: 1, p: .seat), KitPart(dx: 3, dy: 1, p: .steering), KitPart(dx: 4, dy: 1, p: .armor),
							  KitPart(dx: 0, dy: 2, p: .armor), KitPart(dx: 1, dy: 2, p: .engine), KitPart(dx: 2, dy: 2, p: .fuelTank), KitPart(dx: 3, dy: 2, p: .engine),
							  KitPart(dx: 4, dy: 2, p: .frame), KitPart(dx: 5, dy: 2, p: .armor)]
		for x in 0...5 { out.append(KitPart(dx: x, dy: 3, p: .track)) }
		return out
	case .truckKit:
		// a cab with two engines and a headlight, a bed of three cargo crates, three axles
		return [KitPart(dx: 0, dy: 0, p: .cargo), KitPart(dx: 1, dy: 0, p: .cargo), KitPart(dx: 2, dy: 0, p: .cargo), KitPart(dx: 4, dy: 0, p: .seat), KitPart(dx: 5, dy: 0, p: .steering), KitPart(dx: 6, dy: 0, p: .headlight),
				KitPart(dx: 0, dy: 1, p: .frame), KitPart(dx: 1, dy: 1, p: .frame), KitPart(dx: 2, dy: 1, p: .frame), KitPart(dx: 3, dy: 1, p: .frame), KitPart(dx: 4, dy: 1, p: .fuelTank),
				KitPart(dx: 5, dy: 1, p: .engine), KitPart(dx: 6, dy: 1, p: .engine),
				KitPart(dx: 0, dy: 2, p: .wheel), KitPart(dx: 2, dy: 2, p: .wheel), KitPart(dx: 5, dy: 2, p: .wheel)]
	default:
		return []
	}
}

/// Earlier layouts of a kit, so vehicles placed by older versions still pack back into their kit
func legacyKitLayouts(_ g: Gadget) -> [[KitPart]] {
	if g == .motorboatKit {
		return [[KitPart(dx: 1, dy: 0, p: .fuelTank), KitPart(dx: 2, dy: 0, p: .seat), KitPart(dx: 3, dy: 0, p: .steering),
				 KitPart(dx: 0, dy: 1, p: .propeller), KitPart(dx: 1, dy: 1, p: .engine), KitPart(dx: 2, dy: 1, p: .hull), KitPart(dx: 3, dy: 1, p: .hull), KitPart(dx: 4, dy: 1, p: .hull)]]
	}
	return []
}

func isKit(_ g: Gadget) -> Bool {
	switch g {
	case .carKit, .boatKit, .motorboatKit, .planeKit, .heliKit, .airshipKit, .tankKit, .truckKit: return true
	default: return false
	}
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
		if v.engines > 0 || v.jets > 0 || v.burners > 0 { v.fuel = min(v.fuelCapacity, 40.0) }
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
		case .gadget(let g): return g == .wrench || g == .assembler || isKit(g)
		case .block: return vehicleBuild
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
		// any part goes anywhere it touches: how well it works there is physics (see partNote)
		let wp: (Double, Double) = v.cellPos(c)
		if world.boxSolid(wp.0 + 0.02, wp.1 + 0.02, wp.0 + 0.98, wp.1 + 0.98) {
			// a part under a vehicle that sits on the ground: lift the vehicle one block to make room
			if c.dy > v.maxY && canLift(v, c) { return nil }
			return "Something is in the way."
		}
		return nil
	}

	/// How a part will work where it has just been put, when that is not the usual way (said after
	/// attaching it; nil when there is nothing to say)
	func partNote(_ v: Vehicle, _ c: PartCell, _ p: PartType) -> String? {
		if p == .rotor {
			let room: Double = v.rotorRoom[c] ?? 1.0
			if room < 0.99 { return joinText("Its blades have ", String(Int((room * 100).rounded())), "% of their room: it lifts that much.") }
		}
		if v.boxed.contains(c) {
			if isDrill(p) { return "Boxed in: it bores once one side is open." }
			if p == .cannon || p == .autoGun { return "Boxed in: it fires once one side is open." }
			return "Boxed in on both sides: it pushes once one side is open."
		}
		if isWheelPart(p) && v.parts[PartCell(dx: c.dx, dy: c.dy + 1)] != nil { return "A wheel drives wherever it touches the ground (or a wall)." }
		if p == .steering, let seat = seatCell(v), abs(seat.dx - c.dx) + abs(seat.dy - c.dy) > 1 { return "It steers from any seat on the vehicle." }
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
		case .block(let t):
			// with ON VEHICLE: where the block can go on the nearest vehicle
			if vehicleBuild, let v = nearestVehicle(8) {
				var part: PartType = .block
				if t.isMod, let d = ModRuntime.shared.blockDef(t), let pp = d.vehRole.part { part = pp }
				for c in attachSpots(v, part) {
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
		if v.aero || v.tracks > 0 || v.cannons + v.guns > 0 || v.hasCockpit { return flightCheck(v) }
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
		let title: String = isBoat ? (v.engines > 0 ? "MOTORBOAT" : "BOAT") : vehicleKindName(v)
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
			for (c, t) in v.parts { back.append(vehicleCellItem(VCell(cell: c, type: t, tile: v.blocks[c]))) }
		}
		// what the vehicle carried comes back too
		for c in v.parts.keys where vehicleStores(v, c) {
			let k: IntPair = cargoSpot(v, c)
			if let p = openChest, p == k { openChest = nil }
			for st in world.removeChest(k.x, k.y) { giveStack(st) }
		}
		for it in back { giveItem(it, 1) }
		vehicles.removeAll { $0.id == v.id }
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0xC8C8C8, 8, 3.0, 0.4, 6)
		say("Packed up. Place it again any time.", 2.0)
		bumpHUD()
	}

	func kitMatches(_ v: Vehicle, _ g: Gadget) -> Bool {
		for layout in [kitLayout(g)] + legacyKitLayouts(g) {
			if layout.count != v.parts.count { continue }
			var same: Bool = true
			for k in layout where v.parts[PartCell(dx: k.dx, dy: k.dy)] != k.p { same = false }
			if same { return true }
		}
		return false
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
	var anim: CreatureAnim = CreatureAnim()

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

func makeSpriteSet(_ frames: [PixelBuf], hitH: Double, fixedScale: Double? = nil, anim: CreatureAnim = CreatureAnim(), foot footRow: Int? = nil, cx: Double? = nil) -> SpriteSet {
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
		// hit frames flash white (reads clearly on every creature, and is not a red full-body tint)
		let t: PixelBuf = f.whiteFlash()
		hr.append(pixImage(t))
		hl.append(pixImage(t.flipped()))
	}
	// the outline under the soles sits on the ground line; a hand-drawn creature says where its soles
	// and its middle are (a long tail or a raised arm must not move the body off its place)
	let foot: Int = footRow ?? bb.3
	let cc: Double = cx ?? Double(bb.0 + bb.2 + 1) * 0.5
	return SpriteSet(right: r, left: l, hurtR: hr, hurtL: hl, w: f0.w, h: f0.h, footRow: foot, centerCol: cc, scale: sc, anim: anim)
}

// MARK: - Suits drawn piece by piece

/// A picture three times finer, every pixel a 3 x 3 block
func upscale3(_ b: PixelBuf) -> PixelBuf {
	let u: Int = suitUnit
	var o = PixelBuf(w: b.w * u, h: b.h * u)
	for y in 0..<b.h {
		for x in 0..<b.w {
			let c: UInt32 = b.px[y * b.w + x]
			if c == 0 { continue }
			for yy in 0..<u {
				let row: Int = (y * u + yy) * o.w + x * u
				for xx in 0..<u { o.px[row + xx] = c }
			}
		}
	}
	return o
}

/// Lays a suit's working pieces over one frame of the figure drawn three times finer (`frame`: 0
/// standing, 1-2 walking, 3 winding up, 4 striking, 5 blocking, 6 shooting). Each piece moves with its
/// part of the body, shows its colour with lit and shaded edges and its part's marks, and cracks as it
/// wears; broken pieces are gone. `pick` (a piece id) is drawn brighter. A dark line is drawn round
/// what sticks out past the body.
func paintSuitPieces(_ cv: inout PixelBuf, _ d: SuitDesign, frame: Int, pick: Int = -1) {
	let ox: Double = Double(humanOX * suitUnit)
	var mine: [Bool] = [Bool](repeating: false, count: cv.w * cv.h)
	let order: [Int] = d.pieces.indices.sorted { (a: Int, b: Int) -> Bool in
		let la: Int = d.pieces[a].bone.layer
		let lb: Int = d.pieces[b].bone.layer
		return la != lb ? la < lb : a < b
	}
	for i in order {
		let p: SuitPiece = d.pieces[i]
		if p.broken { continue }
		let mv: BoneMove = BoneMove.of(p.bone, frame)
		// the piece's box in the frame, roomy enough for any turn
		let c: (Double, Double) = mv.apply(p.x, p.y)
		let r: Double = sqrt(p.w * p.w + p.h * p.h) * 0.5 + 1.0
		let x0: Int = max(0, Int(floor(c.0 + ox - r)))
		let x1: Int = min(cv.w - 1, Int(ceil(c.0 + ox + r)))
		let y0: Int = max(0, Int(floor(c.1 - r)))
		let y1: Int = min(cv.h - 1, Int(ceil(c.1 + r)))
		if x1 < x0 || y1 < y0 { continue }
		let ww: Int = x1 - x0 + 1
		let hh: Int = y1 - y0 + 1
		// which pixels it covers (tested back on the body standing still)
		var on: [Bool] = [Bool](repeating: false, count: ww * hh)
		let back: BoneMove = BoneMove(dx: -mv.dx, dy: -mv.dy, turn: 0, px: 0, py: 0)
		for yy in 0..<hh {
			for xx in 0..<ww {
				var bx: Double = Double(x0 + xx) + 0.5 - ox
				var by: Double = Double(y0 + yy) + 0.5
				let s: (Double, Double) = back.apply(bx, by)
				bx = s.0
				by = s.1
				if mv.turn != 0 {
					let cs: Double = cos(-mv.turn)
					let sn: Double = sin(-mv.turn)
					let rx: Double = bx - mv.px
					let ry: Double = by - mv.py
					bx = mv.px + rx * cs - ry * sn
					by = mv.py + rx * sn + ry * cs
				}
				if p.covers(bx, by) { on[yy * ww + xx] = true }
			}
		}
		var base: UInt32 = suitColor(p)
		if p.id == pick { base = mixRGB(base, 0xFFFFFF, 0.35) }
		let accent: UInt32 = suitAccent(p)
		for yy in 0..<hh {
			for xx in 0..<ww where on[yy * ww + xx] {
				let up: Bool = yy > 0 && on[(yy - 1) * ww + xx]
				let down: Bool = yy < hh - 1 && on[(yy + 1) * ww + xx]
				let left: Bool = xx > 0 && on[yy * ww + xx - 1]
				let right: Bool = xx < ww - 1 && on[yy * ww + xx + 1]
				var col: UInt32 = base
				if !up || !left { col = shadeRGB(base, 1.22) }
				if !down || !right { col = shadeRGB(base, 0.68) }
				let gx: Int = x0 + xx
				let gy: Int = y0 + yy
				// cracks as it wears
				if p.dmg > 0.3 {
					let hsh: Double = hash2(gx * 7 + p.id, gy * 13, 9091)
					if hsh < (p.dmg - 0.25) * 0.5 { col = shadeRGB(col, 0.45) }
				}
				cv.px[gy * cv.w + gx] = 0xFF000000 | col
				mine[gy * cv.w + gx] = true
			}
		}
		// its marks: a core glows at its heart, a working part shows its colour at its working end
		if accent != 0 {
			let a: Double = (p.rot + mv.turn * 180.0 / Double.pi) * Double.pi / 180.0
			let tip: (Double, Double)
			if p.kind == .core {
				tip = (c.0, c.1)
			} else {
				tip = (c.0 + cos(a) * p.w * 0.32, c.1 + sin(a) * p.w * 0.32)
			}
			let tx: Int = Int(floor(tip.0 + ox))
			let ty: Int = Int(floor(tip.1))
			for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
				let px: Int = tx + dx - 1
				let py: Int = ty + dy - 1
				if px < 0 || py < 0 || px >= cv.w || py >= cv.h { continue }
				if mine[py * cv.w + px] { cv.px[py * cv.w + px] = 0xFF000000 | accent }
			}
		}
	}
	// a dark edge round the pieces where they stand against nothing
	var edge: [Int] = []
	for y in 0..<cv.h {
		for x in 0..<cv.w where cv.px[y * cv.w + x] == 0 {
			var near: Bool = false
			for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
				let nx: Int = x + dx
				let ny: Int = y + dy
				if nx >= 0 && ny >= 0 && nx < cv.w && ny < cv.h && mine[ny * cv.w + nx] { near = true }
			}
			if near { edge.append(y * cv.w + x) }
		}
	}
	for k in edge { cv.px[k] = 0xFF1A1410 }
}

/// The mark a working part shows (0: none): a core's glow, a jet's flame, a lamp, a lens
func suitAccent(_ p: SuitPiece) -> UInt32 {
	if p.kind == .core, let c = p.core { return shadeRGB(c.color, 1.4) }
	guard p.kind == .module, let m = p.module else { return 0 }
	switch m {
	case .hover: return 0xFF9A3A
	case .lamp: return 0xFFF4C0
	case .laser: return 0xFF4A6A
	case .turret, .cannon: return 0x1E2028
	case .solar: return 0x2A4A8A
	case .magnet: return 0xD83A3A
	case .battery: return 0x8AE85A
	case .barrier: return 0xC07CFF
	case .gauntlet: return 0xFFF07A
	default: return shadeRGB(m.color, 1.3)
	}
}

/// The player's frames with a suit on: the figure drawn three times finer with the suit's pieces over
/// it, frame by frame
func suitFrames(_ plain: [PixelBuf], _ d: SuitDesign, pick: Int = -1) -> [PixelBuf] {
	var out: [PixelBuf] = []
	for (f, b) in plain.enumerated() {
		var cv: PixelBuf = upscale3(b)
		paintSuitPieces(&cv, d, frame: f, pick: pick)
		out.append(cv)
	}
	return out
}

/// Pictures of suit designs for the Assembly Station (drawn again only when the design changes)
final class SuitPictures: @unchecked Sendable {
	static let shared: SuitPictures = SuitPictures()
	var cache: [Int: Image] = [:]
	let plain: [PixelBuf] = humanoidFrames(playerStyle(hairIdx: 0, scarfIdx: 0, head: nil, chest: nil, legs: nil))

	/// the design worn by a plain figure, in one frame, with a piece shown picked
	func image(_ d: SuitDesign, _ frame: Int, _ pick: Int) -> Image {
		var h: Hasher = Hasher()
		h.combine(d)
		h.combine(frame)
		h.combine(pick)
		let key: Int = h.finalize()
		if let i = cache[key] { return i }
		let f: Int = clampI(frame, 0, plain.count - 1)
		var cv: PixelBuf = upscale3(plain[f])
		paintSuitPieces(&cv, d, frame: f, pick: pick)
		let img: Image = pixImage(cv)
		if cache.count > 48 { cache.removeAll() }
		cache[key] = img
		return img
	}
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

// MARK: - The player's look

/// The marker colours of the player's drawing (tools/art/creatures/player.py, MARK): the game swaps
/// each set, light to deep, for the chosen colour's tones. Keep them the same as the drawing's.
enum PlayerInk {
	static let hair: [UInt32] = [0xF00001, 0xF00002, 0xF00003, 0xF00004]
	static let shirt: [UInt32] = [0x00F001, 0x00F002, 0x00F003, 0x00F004]
	static let pants: [UInt32] = [0x0000F1, 0x0000F2, 0x0000F3, 0x0000F4]
	static let shoe: [UInt32] = [0xF0F001, 0xF0F002, 0xF0F003, 0xF0F004]
	static let scarf: [UInt32] = [0x00F0F1, 0x00F0F2, 0x00F0F3, 0x00F0F4]
	static let helm: [UInt32] = [0xF000F1, 0xF000F2, 0xF000F3, 0xF000F4]
	/// the shoes' own colour (leg armour makes them a darker shade of its metal)
	static let shoeColor: UInt32 = 0x24242E
}

/// Four tones of a colour, as the drawings shade with (`ramp` in tools/art/artlib.py): a warm light,
/// the colour, a shadow and a deep shadow that both lean cool
func artRamp(_ c: UInt32, light: UInt32 = 0xFFF0C8, dark: UInt32 = 0x241A38) -> [UInt32] {
	let s1: UInt32 = mixRGB(mixRGB(c, 0x000000, 0.22), dark, 0.18)
	let s2: UInt32 = mixRGB(mixRGB(c, 0x000000, 0.42), dark, 0.30)
	return [mixRGB(c, light, 0.28), c, s1, s2]
}

/// A chosen colour's tones through the game's grade, ready to swap for a set of markers
func lookRamp(_ c: UInt32) -> [UInt32] {
	return artRamp(c).map { artGrade($0) }
}

/// A picture with some colours swapped for others (exact matches only)
func swapColors(_ b: PixelBuf, _ map: [UInt32: UInt32]) -> PixelBuf {
	if map.isEmpty { return b }
	var o: PixelBuf = b
	for i in 0..<o.px.count {
		let c: UInt32 = o.px[i]
		if (c >> 24) == 0 { continue }
		if let n = map[c & 0xFFFFFF] { o.px[i] = (c & 0xFF000000) | n }
	}
	return o
}

/// What the player chose to look like (Settings), and the armour worn over it
struct PlayerLookChoice {
	var hair: Int = 0
	var hairStyle: Int = 0
	var shirt: Int = 0
	var shirtStyle: Int = 0
	var pants: Int = 0
	var pantsStyle: Int = 0
	var scarf: Int = 0
	var head: Tier? = nil
	var chest: Tier? = nil
	var legs: Tier? = nil

	init(_ s: Settings, head: Tier? = nil, chest: Tier? = nil, legs: Tier? = nil) {
		hair = clampI(s.hair, 0, hairChoices.count - 1)
		hairStyle = clampI(s.hairStyle, 0, hairStyleNames.count - 1)
		shirt = clampI(s.shirtColor, 0, shirtChoices.count - 1)
		shirtStyle = clampI(s.shirtStyle, 0, shirtStyleNames.count - 1)
		pants = clampI(s.pantsColor, 0, pantsChoices.count - 1)
		pantsStyle = clampI(s.pantsStyle, 0, pantsStyleNames.count - 1)
		scarf = clampI(s.scarf, 0, scarfChoices.count - 1)
		self.head = head
		self.chest = chest
		self.legs = legs
	}

	/// One number for the whole choice (the sprite caches are keyed by it)
	var key: Int {
		let looks: Int = (((((hair * 8 + hairStyle) * 16 + shirt) * 8 + shirtStyle) * 16 + pants) * 8 + pantsStyle) * 8 + scarf
		let worn: Int = ((head?.rawValue ?? 15) * 16 + (chest?.rawValue ?? 15)) * 16 + (legs?.rawValue ?? 15)
		return looks &* 4096 &+ worn
	}
}

/// The colour armour of a tier is drawn in
func armorLookColor(_ t: Tier) -> UInt32 {
	return t == .wood ? 0x9A5A2A : t.color
}

/// The player's frames: the bare figure with the chosen trousers, shirt, scarf and hair laid over it
/// (each a drawing of only what it changes), then every marker swapped for the chosen colour's
/// tones. Armour takes the place of the clothes: a chest piece is a long-sleeved top of its metal,
/// leg pieces are trousers of it (with darker boots), a helmet goes over the hair.
func playerFrames(_ c: PlayerLookChoice) -> [PixelBuf] {
	var frames: [PixelBuf] = CreatureSheet.frames("player")
	if frames.isEmpty { return frames }
	var map: [UInt32: UInt32] = [:]
	func tone(_ markers: [UInt32], _ col: UInt32) {
		let r: [UInt32] = lookRamp(col)
		for i in 0..<min(markers.count, r.count) { map[markers[i]] = r[i] }
	}
	func lay(_ name: String) {
		let over: [PixelBuf] = CreatureSheet.frames(name)
		for i in 0..<min(frames.count, over.count) { frames[i].blit(over[i], 0, 0) }
	}
	var pantsStyle: Int = c.pantsStyle
	var pantsCol: UInt32 = pantsChoices[c.pants]
	var shoeCol: UInt32 = PlayerInk.shoeColor
	if let t = c.legs {
		pantsStyle = 0
		pantsCol = shadeRGB(armorLookColor(t), 0.85)
		shoeCol = shadeRGB(armorLookColor(t), 0.6)
	}
	var shirtStyle: Int = c.shirtStyle
	var shirtCol: UInt32 = shirtChoices[c.shirt]
	if let t = c.chest {
		shirtStyle = 1
		shirtCol = armorLookColor(t)
	}
	lay(joinText("player_pants_", String(pantsStyle)))
	lay(joinText("player_shirt_", String(shirtStyle)))
	if c.scarf != 0 { lay("player_scarf") }
	lay(joinText("player_hair_", String(c.hairStyle)))
	if c.head != nil { lay("player_helm") }
	tone(PlayerInk.pants, pantsCol)
	tone(PlayerInk.shoe, shoeCol)
	tone(PlayerInk.shirt, shirtCol)
	tone(PlayerInk.hair, hairChoices[c.hair])
	if c.scarf != 0 { tone(PlayerInk.scarf, scarfChoices[c.scarf]) }
	if let t = c.head { tone(PlayerInk.helm, armorLookColor(t)) }
	return frames.map { swapColors($0, map) }
}

/// The player's look for a choice of clothes and armour
func playerLook(_ c: PlayerLookChoice) -> CreatureLook {
	guard let a = CreatureSheet.arts["player"] else {
		let st: HumanStyle = playerStyle(hairIdx: c.hair, scarfIdx: c.scarf, head: c.head, chest: c.chest, legs: c.legs)
		return CreatureLook(frames: humanoidFrames(st), anim: CreatureAnim(), scale: creatureScale)
	}
	return CreatureLook(frames: playerFrames(c), anim: CreatureSheet.anim(a), scale: fineScale, foot: a.foot + 1, cx: a.cx, fine: true)
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
	/// the parts' pictures as pixels (for vehicles drawn from one picture), and a count of art changes
	var partBufs: [PixelBuf] = []
	var gen: Int = 0
	private var icons: [Item: Image] = [:]
	/// weather symbols (see weatherIcon)
	var wxIcons: [Int: Image] = [:]
	var mobSets: [Int: SpriteSet] = [:]
	/// sprites of custom creatures, by slot (rebuilt when the mods change)
	var modMobSets: [Int: SpriteSet] = [:]
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
		let bt: PixelBuf = gradeBuf(spritePirateBoat())
		boat = pixImage(bt)
		boatL = pixImage(bt.flipped())
		var ps: [Image] = []
		var pb: [PixelBuf] = []
		for p in PartType.allCases {
			let b: PixelBuf = gradeBuf(partBuf(p))
			pb.append(b)
			ps.append(pixImage(b))
		}
		parts = ps
		partBufs = pb
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

	/// After a world's mods change: new pictures for the reserved tiles, and forget every cached icon
	/// and sprite of custom content
	func refreshModArt() {
		gen &+= 1
		let painter: SectionPainter = SectionPainter.shared
		let base: Int = Int(Tile.modBase)
		for i in 0..<ModLimits.blockSlots where base + i < tiles.count && base + i < painter.tileBufs.count {
			tiles[base + i] = pixImage(painter.tileBufs[base + i])
			tileBufs[base + i] = painter.tileBufs[base + i]
		}
		var keep: [Item: Image] = [:]
		for (k, v) in icons {
			switch k {
			case .custom: continue
			case .block(let t): if t.isMod { continue }
			default: break
			}
			keep[k] = v
		}
		icons = keep
		modMobSets.removeAll()
		// game creatures a mod repaints (or stops repainting) are drawn afresh
		mobSets.removeAll()
	}

	func icon(_ it: Item) -> Image {
		if let i = icons[it] { return i }
		var b: PixelBuf = itemBuf(it)
		switch it {
		case .block, .custom: break
		default: b = gradeBuf(b)
		}
		let img: Image = pixImage(b)
		icons[it] = img
		return img
	}

	func playerSet(_ g: Game) -> SpriteSet {
		let key: Int = g.armorKey
		if let s = playerSets[key] { return s }
		let a = g.armorPieces()
		var s: SpriteSet
		if g.suit.worn && !g.suit.d.pieces.isEmpty {
			// a suit is built on the older figure, drawn three times finer: it stands where it always does
			let st: HumanStyle = playerStyle(hairIdx: g.settings.hair, scarfIdx: g.settings.scarf, head: a.0, chest: a.1, legs: a.2)
			let plain: [PixelBuf] = humanoidFrames(st)
			s = makeSpriteSet(suitFrames(plain, g.suit.d).map { gradeBuf($0) }, hitH: 1.8, fixedScale: 0.125 / Double(suitUnit))
			let bb: (Int, Int, Int, Int) = opaqueBounds(plain[0])
			s.footRow = bb.3 * suitUnit
			s.centerCol = Double(bb.0 + bb.2 + 1) * 0.5 * Double(suitUnit)
		} else {
			s = lookSpriteSet(playerLook(PlayerLookChoice(g.settings, head: a.0, chest: a.1, legs: a.2)), hitH: 1.8)
		}
		if playerSets.count > 24 { playerSets.removeAll() }
		playerSets[key] = s
		return s
	}

	/// The player as chosen on the character screen: from the front and from the side
	func previewPlayer(_ s: Settings) -> (Image, Image) {
		let l: CreatureLook = playerLook(PlayerLookChoice(s))
		let i: Int = l.anim.pose("front", 0)
		let front: Image = pixImage(l.frames[min(i, l.frames.count - 1)])
		let side: Image = pixImage(l.frames[0])
		return (front, side)
	}

	func mobSet(_ m: Mob) -> SpriteSet {
		if m.kind == .custom { return customMobSet(m.cslot, m.mphase) }
		var variant: Int = 0
		switch m.kind {
		case .zombie: variant = m.variant
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

	func buildMobSet(_ k: MobKind, _ v: Int) -> SpriteSet {
		if let fr = OverrideRT.shared.creatureArt(k, v) {
			// a mod's repainted sprite, timed like the drawing it was painted over: the hand-drawn one,
			// or the older one for repaints made before the creature was redrawn
			let look: CreatureLook = creatureLook(k, v)
			if look.fine && OverrideRT.shared.mobFine[k.rawValue] == true {
				return makeSpriteSet(fr, hitH: mobDef(k).h, fixedScale: look.scale, anim: look.anim)
			}
			return makeSpriteSet(fr, hitH: mobDef(k).h, fixedScale: creatureScale, anim: olderCreatureArt(k, v).1)
		}
		return creatureSpriteSet(k, v)
	}

	/// A custom creature's sprites (made once per world; refreshModArt clears them)
	func customMobSet(_ slot: Int) -> SpriteSet {
		if let s = modMobSets[slot] { return s }
		guard let r = ModRuntime.shared.mob(slot) else { return creaturePreview(.zombie) }
		let s: SpriteSet = modMobSpriteSet(r.def)
		modMobSets[slot] = s
		return s
	}

	/// A game creature's sprites (the Mod Creator's body picker)
	func creaturePreview(_ k: MobKind) -> SpriteSet {
		let key: Int = k.rawValue * 16
		if let s = mobSets[key] { return s }
		let s: SpriteSet = buildMobSet(k, 0)
		mobSets[key] = s
		return s
	}
}

/// True for creatures drawn with the shared humanoid frames




// MARK: - Sound: every effect is synthesised at first use (no audio files), short and soft, in one style

enum SoundID: Int, CaseIterable {
	case digStone, digDirt, digWood, digSand, digCrystal, digLeaves
	case breakStone, breakDirt, breakWood, breakCrystal
	case place, pickup, craft, chestOpen, door
	case swing, hit, hurt, bow, arrowHit, gun, explosion, land, eat, splash
	case discovery, warn, roar, portal, tap
	/// combat (appended): a knife's flick, a heavy blow, a thrust, a critical hit, several foes at once,
	/// crossbow, sling, blunderbuss, lightning, a fire flask, a dazed foe, a weapon swap, a rare find
	case swingLight, swingHeavy, thrust, crit, multiHit, crossbow, sling, blunderbuss, zap, flask, daze, swap, rareLoot
	/// weather (appended): a close thunderclap, far-off rolling thunder, the crackle before a strike,
	/// an alert chime, a hailstone's tick
	case thunderNear, thunderFar, strikeWarn, weatherAlert, hailTick
	/// alchemy and the suit (appended): a sip, a flask breaking, an infusion taking hold, a suit closing
	case drink, potionBreak, infuse, suitUp
}

enum LoopID: Int, CaseIterable {
	case engine, drill, rain, wind
	/// weather beds (appended): a heavy downpour, a howling gale, hail on everything, a tornado's roar,
	/// a storm siren
	case heavyRain, gale, hail, tornado, siren
}

/// The sound a block makes when dug or broken
func soundMaterial(_ t: Tile) -> Int {
	if isLeafTile(t) || t.isPlant || t == .cobweb { return 5 }
	switch t {
	case .glass, .ice, .glowCrystal, .crystalOre, .diamond: return 4
	case .sand: return 3
	default: break
	}
	switch toolClass(t) {
	case .axe: return 2
	case .shovel, .hoe: return 1
	case .pickaxe: return 0
	}
}

/// Small additive synthesiser: tones with pitch sweeps, filtered noise and plucked strings, each with an
/// attack and an exponential decay, mixed and normalised
struct Synth {
	static let rate: Double = 22050
	var out: [Float]
	var seed: UInt64

	init(_ seconds: Double, seed: UInt64) {
		out = [Float](repeating: 0, count: max(1, Int(seconds * Synth.rate)))
		self.seed = seed &* 2862933555777941757 &+ 3037000493
	}

	static func env(_ t: Double, _ attack: Double, _ decay: Double) -> Double {
		return t < attack ? t / max(attack, 0.0001) : exp(-(t - attack) / max(decay, 0.0001))
	}

	/// wave: 0 sine, 1 triangle, 2 saw, 3 soft square
	mutating func tone(_ f0: Double, _ f1: Double, _ dur: Double, _ attack: Double, _ decay: Double, _ amp: Double, wave: Int = 0, at: Double = 0, vibrato: Double = 0) {
		let n0: Int = Int(at * Synth.rate)
		let n: Int = min(out.count - n0, Int(dur * Synth.rate))
		if n <= 0 { return }
		var ph: Double = 0
		for i in 0..<n {
			let t: Double = Double(i) / Synth.rate
			let k: Double = t / max(dur, 0.0001)
			var f: Double = f0 + (f1 - f0) * k
			if vibrato > 0 { f *= 1.0 + 0.012 * sin(t * vibrato * 2.0 * Double.pi) }
			ph += f / Synth.rate
			let x: Double = ph - floor(ph)
			var v: Double
			switch wave {
			case 1: v = 4.0 * abs(x - 0.5) - 1.0
			case 2: v = 2.0 * x - 1.0
			case 3: v = tanh(sin(x * 2.0 * Double.pi) * 3.0)
			default: v = sin(x * 2.0 * Double.pi)
			}
			out[n0 + i] += Float(v * amp * Synth.env(t, attack, decay))
		}
	}

	mutating func rnd() -> Double {
		seed = seed &* 6364136223846793005 &+ 1442695040888963407
		return Double((seed >> 33) & 0xFFFFFF) / Double(0xFFFFFF) * 2.0 - 1.0
	}

	/// noise through a one-pole low-pass (lp) and high-pass (hp); lp can sweep to lp1
	mutating func noise(_ dur: Double, _ attack: Double, _ decay: Double, _ amp: Double, lp: Double, hp: Double, lp1: Double = -1, at: Double = 0) {
		let n0: Int = Int(at * Synth.rate)
		let n: Int = min(out.count - n0, Int(dur * Synth.rate))
		if n <= 0 { return }
		var low: Double = 0
		var low2: Double = 0
		let ah: Double = 1.0 - exp(-2.0 * Double.pi * hp / Synth.rate)
		for i in 0..<n {
			let t: Double = Double(i) / Synth.rate
			let cut: Double = lp1 > 0 ? lp + (lp1 - lp) * (t / dur) : lp
			let al: Double = 1.0 - exp(-2.0 * Double.pi * cut / Synth.rate)
			low += al * (rnd() - low)
			low2 += ah * (low - low2)
			out[n0 + i] += Float((low - low2) * amp * 2.2 * Synth.env(t, attack, decay))
		}
	}

	/// a plucked string (Karplus-Strong)
	mutating func pluck(_ f: Double, _ dur: Double, _ amp: Double, at: Double = 0) {
		let period: Int = max(2, Int(Synth.rate / f))
		var ring: [Double] = (0..<period).map { _ in rnd() }
		let n0: Int = Int(at * Synth.rate)
		let n: Int = min(out.count - n0, Int(dur * Synth.rate))
		if n <= 0 { return }
		var k: Int = 0
		for i in 0..<n {
			let a: Double = ring[k]
			let b: Double = ring[(k + 1) % period]
			ring[k] = (a + b) * 0.497
			out[n0 + i] += Float(a * amp)
			k = (k + 1) % period
		}
	}

	/// peak-normalise and fade the ends so nothing clicks
	mutating func finish(_ peak: Float) {
		var m: Float = 0
		for v in out { m = max(m, abs(v)) }
		let g: Float = m > 0 ? peak / m : 0
		let fade: Int = min(out.count / 2, 66)
		for i in 0..<out.count {
			var v: Float = out[i] * g
			if i < fade { v *= Float(i) / Float(fade) }
			if i > out.count - 1 - fade { v *= Float(out.count - 1 - i) / Float(fade) }
			out[i] = v
		}
	}
}

enum SoundBank {
	static func effect(_ id: SoundID, _ variant: Int) -> [Float] {
		let p: Double = [0.94, 1.0, 1.06][variant % 3]
		let seed: UInt64 = UInt64(id.rawValue * 31 + variant + 1)
		var s: Synth
		var peak: Float = 0.75
		switch id {
		case .digStone, .breakStone:
			let big: Bool = id == .breakStone
			s = Synth(big ? 0.22 : 0.08, seed: seed)
			s.noise(big ? 0.2 : 0.06, 0.002, big ? 0.06 : 0.02, 0.6, lp: 6000, hp: 1500)
			s.tone(900 * p, 700 * p, 0.06, 0.001, 0.015, 0.3)
			if big { s.noise(0.18, 0.01, 0.06, 0.4, lp: 1500, hp: 200, at: 0.03) }
		case .digDirt, .breakDirt:
			let big: Bool = id == .breakDirt
			s = Synth(big ? 0.2 : 0.09, seed: seed)
			s.noise(big ? 0.18 : 0.08, 0.003, big ? 0.06 : 0.03, 0.8, lp: 900, hp: 80)
			s.tone(140 * p, 90 * p, 0.08, 0.002, 0.03, 0.4)
		case .digWood, .breakWood:
			let big: Bool = id == .breakWood
			s = Synth(big ? 0.25 : 0.09, seed: seed)
			s.tone(320 * p, 300 * p, 0.08, 0.001, 0.025, 0.6, wave: 1)
			s.tone(640 * p, 600 * p, 0.06, 0.001, 0.015, 0.25)
			s.noise(0.03, 0.001, 0.01, 0.3, lp: 3000, hp: 400)
			if big { s.tone(240 * p, 200 * p, 0.2, 0.002, 0.06, 0.5, wave: 1, at: 0.04); s.noise(0.15, 0.01, 0.05, 0.3, lp: 1200, hp: 150, at: 0.05) }
		case .digSand:
			s = Synth(0.1, seed: seed)
			s.noise(0.09, 0.005, 0.04, 0.6, lp: 2500, hp: 300)
		case .digCrystal, .breakCrystal:
			let big: Bool = id == .breakCrystal
			s = Synth(big ? 0.45 : 0.3, seed: seed)
			s.tone(1500 * p, 1500 * p, 0.3, 0.002, 0.12, 0.4)
			s.tone(2310 * p, 2300 * p, 0.25, 0.002, 0.08, 0.25)
			s.noise(0.02, 0.001, 0.006, 0.2, lp: 8000, hp: 2000)
			if big { for k in 0..<4 { s.tone((1800 + Double(k) * 420) * p, 1700 * p, 0.2, 0.002, 0.06, 0.18, at: 0.03 * Double(k)) } }
			peak = 0.55
		case .digLeaves:
			s = Synth(0.08, seed: seed)
			s.noise(0.07, 0.01, 0.025, 0.35, lp: 4000, hp: 1200)
			peak = 0.4
		case .place:
			s = Synth(0.09, seed: seed)
			s.tone(200 * p, 120 * p, 0.08, 0.002, 0.025, 0.7)
			s.noise(0.04, 0.001, 0.012, 0.3, lp: 1200, hp: 100)
		case .pickup:
			s = Synth(0.14, seed: seed)
			s.tone(660 * p, 660 * p, 0.06, 0.002, 0.03, 0.4, wave: 1)
			s.tone(990 * p, 990 * p, 0.08, 0.002, 0.04, 0.35, wave: 1, at: 0.05)
			peak = 0.4
		case .craft:
			s = Synth(0.4, seed: seed)
			s.tone(1180 * p, 1180 * p, 0.35, 0.001, 0.1, 0.4)
			s.tone(1770 * p, 1770 * p, 0.3, 0.001, 0.06, 0.3)
			s.tone(2900 * p, 2900 * p, 0.2, 0.001, 0.03, 0.15)
			s.noise(0.02, 0.001, 0.005, 0.3, lp: 7000, hp: 1500)
			peak = 0.5
		case .chestOpen:
			s = Synth(0.3, seed: seed)
			s.tone(150 * p, 130 * p, 0.26, 0.02, 0.12, 0.4, wave: 1, vibrato: 18)
			s.tone(95 * p, 80 * p, 0.08, 0.002, 0.03, 0.4, at: 0.2)
			peak = 0.5
		case .door:
			s = Synth(0.12, seed: seed)
			s.tone(240 * p, 180 * p, 0.08, 0.001, 0.025, 0.6, wave: 1)
			s.noise(0.05, 0.001, 0.015, 0.4, lp: 2000, hp: 150)
		case .swing:
			s = Synth(0.16, seed: seed)
			s.noise(0.15, 0.04, 0.05, 0.4, lp: 700 * p, hp: 250, lp1: 3200 * p)
			peak = 0.35
		case .hit:
			s = Synth(0.12, seed: seed)
			s.noise(0.08, 0.001, 0.025, 0.7, lp: 1800, hp: 100)
			s.tone(120 * p, 70 * p, 0.1, 0.001, 0.04, 0.8)
		case .hurt:
			s = Synth(0.2, seed: seed)
			s.tone(230 * p, 150 * p, 0.17, 0.005, 0.07, 0.5, wave: 1)
			s.noise(0.08, 0.002, 0.03, 0.3, lp: 1200, hp: 100)
		case .bow:
			s = Synth(0.3, seed: seed)
			s.pluck(196 * p, 0.28, 0.6)
			s.noise(0.03, 0.001, 0.01, 0.2, lp: 3000, hp: 600)
			peak = 0.5
		case .arrowHit:
			s = Synth(0.08, seed: seed)
			s.noise(0.04, 0.001, 0.012, 0.5, lp: 2500, hp: 300)
			s.tone(260 * p, 200 * p, 0.05, 0.001, 0.02, 0.4, wave: 1)
			peak = 0.45
		case .gun:
			s = Synth(0.16, seed: seed)
			s.noise(0.12, 0.001, 0.035, 0.9, lp: 7000, hp: 200)
			s.tone(90 * p, 50 * p, 0.12, 0.001, 0.05, 0.7)
			peak = 0.7
		case .explosion:
			s = Synth(1.0, seed: seed)
			s.noise(0.95, 0.003, 0.28, 1.0, lp: 700 * p, hp: 20)
			s.tone(60 * p, 35 * p, 0.8, 0.003, 0.3, 0.8)
			peak = 0.85
		case .land:
			s = Synth(0.09, seed: seed)
			s.noise(0.07, 0.002, 0.025, 0.7, lp: 600, hp: 40)
			s.tone(90 * p, 60 * p, 0.06, 0.001, 0.025, 0.4)
			peak = 0.5
		case .eat:
			s = Synth(0.3, seed: seed)
			for k in 0..<3 { s.noise(0.05, 0.002, 0.015, 0.4, lp: 2500, hp: 500, at: Double(k) * 0.09) }
			peak = 0.4
		case .splash:
			s = Synth(0.3, seed: seed)
			s.noise(0.28, 0.005, 0.1, 0.6, lp: 3000, hp: 400)
			peak = 0.45
		case .discovery:
			s = Synth(0.75, seed: seed)
			for (k, f) in [523.0, 659.0, 784.0, 1047.0].enumerated() { s.tone(f, f, 0.4, 0.004, 0.16, 0.3, wave: 1, at: Double(k) * 0.09) }
			peak = 0.45
		case .warn:
			s = Synth(0.5, seed: seed)
			s.tone(110, 165, 0.45, 0.05, 0.25, 0.35, wave: 3)
			peak = 0.4
		case .roar:
			s = Synth(1.1, seed: seed)
			s.noise(1.0, 0.08, 0.4, 0.8, lp: 500, hp: 40)
			s.tone(75 * p, 55 * p, 1.0, 0.06, 0.4, 0.5, wave: 2, vibrato: 7)
			peak = 0.7
		case .portal:
			s = Synth(1.0, seed: seed)
			for f in [440.0, 660.0, 880.0] { s.tone(f, f * 1.02, 0.9, 0.15, 0.4, 0.25, vibrato: 5) }
			peak = 0.45
		case .tap:
			s = Synth(0.04, seed: seed)
			s.tone(1400, 1300, 0.03, 0.001, 0.008, 0.3)
			peak = 0.25
		case .swingLight:
			s = Synth(0.1, seed: seed)
			s.noise(0.09, 0.01, 0.025, 0.4, lp: 1800 * p, hp: 700, lp1: 6000 * p)
			peak = 0.3
		case .swingHeavy:
			s = Synth(0.3, seed: seed)
			s.noise(0.28, 0.06, 0.08, 0.6, lp: 300 * p, hp: 60, lp1: 1400 * p)
			s.tone(95 * p, 60 * p, 0.25, 0.04, 0.08, 0.4)
			peak = 0.45
		case .thrust:
			s = Synth(0.12, seed: seed)
			s.noise(0.1, 0.005, 0.03, 0.5, lp: 2500 * p, hp: 500, lp1: 7000 * p)
			s.tone(500 * p, 900 * p, 0.05, 0.002, 0.02, 0.15)
			peak = 0.35
		case .crit:
			s = Synth(0.25, seed: seed)
			s.noise(0.08, 0.001, 0.025, 0.7, lp: 2400, hp: 100)
			s.tone(130 * p, 70 * p, 0.12, 0.001, 0.045, 0.8)
			s.tone(1480 * p, 1320 * p, 0.2, 0.001, 0.07, 0.3)
			s.tone(2220 * p, 2000 * p, 0.14, 0.001, 0.04, 0.15)
			peak = 0.75
		case .multiHit:
			s = Synth(0.3, seed: seed)
			s.tone(660 * p, 660 * p, 0.12, 0.002, 0.05, 0.35, wave: 1)
			s.tone(990 * p, 990 * p, 0.16, 0.002, 0.07, 0.35, wave: 1, at: 0.07)
			peak = 0.45
		case .crossbow:
			s = Synth(0.24, seed: seed)
			s.pluck(110 * p, 0.2, 0.7)
			s.noise(0.03, 0.001, 0.008, 0.5, lp: 4000, hp: 800)
			s.tone(180 * p, 120 * p, 0.06, 0.001, 0.02, 0.4, wave: 1, at: 0.01)
			peak = 0.55
		case .sling:
			s = Synth(0.26, seed: seed)
			s.noise(0.2, 0.02, 0.06, 0.35, lp: 900 * p, hp: 200, lp1: 2600 * p)
			for i in 0..<s.out.count { s.out[i] *= Float(0.6 + 0.4 * sin(Double(i) / Synth.rate * 38.0 * 2.0 * Double.pi)) }
			s.noise(0.05, 0.001, 0.015, 0.4, lp: 3500, hp: 600, at: 0.18)
			peak = 0.4
		case .blunderbuss:
			s = Synth(0.5, seed: seed)
			s.noise(0.45, 0.001, 0.12, 1.0, lp: 4500 * p, hp: 60, lp1: 900)
			s.tone(70 * p, 32 * p, 0.4, 0.001, 0.14, 0.9)
			peak = 0.85
		case .zap:
			s = Synth(0.3, seed: seed)
			for k in 0..<5 { s.noise(0.03, 0.001, 0.01, 0.6, lp: 9000, hp: 2200, at: Double(k) * 0.045) }
			s.tone(1900 * p, 420 * p, 0.25, 0.001, 0.08, 0.35, wave: 2)
			peak = 0.6
		case .flask:
			s = Synth(0.6, seed: seed)
			s.noise(0.06, 0.001, 0.02, 0.6, lp: 9000, hp: 3000)
			for k in 0..<3 { s.tone((2600 + Double(k) * 700) * p, 2400 * p, 0.08, 0.001, 0.03, 0.15, at: 0.01 * Double(k)) }
			s.noise(0.5, 0.08, 0.2, 0.7, lp: 400, hp: 60, lp1: 1600, at: 0.04)
			peak = 0.6
		case .daze:
			s = Synth(0.35, seed: seed)
			for (k, f) in [1500.0, 1900.0, 1700.0].enumerated() { s.tone(f * p, f * 1.05 * p, 0.08, 0.004, 0.03, 0.25, at: Double(k) * 0.09) }
			peak = 0.3
		case .swap:
			s = Synth(0.1, seed: seed)
			s.tone(900 * p, 850 * p, 0.04, 0.001, 0.012, 0.35, wave: 1)
			s.tone(1300 * p, 1250 * p, 0.04, 0.001, 0.012, 0.3, wave: 1, at: 0.045)
			s.noise(0.02, 0.001, 0.006, 0.2, lp: 6000, hp: 1500)
			peak = 0.3
		case .rareLoot:
			s = Synth(0.9, seed: seed)
			for (k, f) in [784.0, 988.0, 1175.0, 1568.0, 1976.0].enumerated() { s.tone(f, f, 0.45, 0.003, 0.18, 0.28, wave: 1, at: Double(k) * 0.07) }
			for k in 0..<6 { s.tone(3000 + Double(k) * 310, 2900, 0.1, 0.001, 0.04, 0.08, at: 0.35 + Double(k) * 0.05) }
			peak = 0.5
		case .thunderNear:
			// a sharp crack, then the long rumble rolling away under it
			s = Synth(2.4, seed: seed)
			s.noise(0.09, 0.001, 0.03, 1.0, lp: 9000, hp: 900)
			s.noise(0.25, 0.004, 0.09, 0.8, lp: 2600 * p, hp: 120, at: 0.02)
			s.noise(2.3, 0.03, 0.75, 0.9, lp: 420 * p, hp: 25, lp1: 160, at: 0.05)
			s.noise(1.2, 0.05, 0.35, 0.5, lp: 300 * p, hp: 25, at: 0.6 + 0.2 * Double(variant))
			s.tone(48 * p, 34 * p, 1.6, 0.02, 0.6, 0.35)
			peak = 0.9
		case .thunderFar:
			// rolls of low rumble, no crack (the high notes are lost on the way)
			s = Synth(3.0, seed: seed)
			s.noise(2.6, 0.25, 0.9, 0.7, lp: 260 * p, hp: 22, lp1: 140)
			s.noise(1.0, 0.1, 0.35, 0.55, lp: 220 * p, hp: 22, at: 0.5 + 0.3 * Double(variant))
			s.noise(1.0, 0.1, 0.35, 0.45, lp: 200 * p, hp: 22, at: 1.4)
			s.tone(40 * p, 30 * p, 2.4, 0.3, 0.8, 0.25)
			peak = 0.6
		case .strikeWarn:
			// the buzz and crackle in the air just before a strike
			s = Synth(0.7, seed: seed)
			for k in 0..<9 { s.noise(0.035, 0.001, 0.012, 0.45 + 0.05 * Double(k), lp: 9000, hp: 2600, at: Double(k) * 0.07) }
			s.tone(120 * p, 180 * p, 0.65, 0.2, 0.3, 0.2, wave: 2, vibrato: 30)
			peak = 0.5
		case .weatherAlert:
			s = Synth(0.9, seed: seed)
			s.tone(880, 880, 0.3, 0.005, 0.12, 0.35, wave: 1)
			s.tone(660, 660, 0.4, 0.005, 0.18, 0.35, wave: 1, at: 0.28)
			s.tone(880, 880, 0.3, 0.005, 0.12, 0.25, wave: 1, at: 0.56)
			peak = 0.45
		case .hailTick:
			s = Synth(0.05, seed: seed)
			s.noise(0.03, 0.0005, 0.008, 0.6, lp: 9000, hp: 2500)
			s.tone(2600 * p, 2400 * p, 0.02, 0.0005, 0.006, 0.3)
			peak = 0.3
		case .drink:
			// three soft gulps
			s = Synth(0.5, seed: seed)
			for k in 0..<3 { s.tone(320 * p, 220 * p, 0.09, 0.01, 0.04, 0.35, wave: 0, at: Double(k) * 0.14) }
			s.noise(0.4, 0.02, 0.15, 0.12, lp: 900, hp: 200)
			peak = 0.4
		case .potionBreak:
			// glass, then a hiss
			s = Synth(0.55, seed: seed)
			s.noise(0.05, 0.0008, 0.015, 0.7, lp: 9500, hp: 3500)
			for k in 0..<4 { s.tone((2900 + Double(k) * 520) * p, 2500 * p, 0.07, 0.001, 0.025, 0.14, at: 0.008 * Double(k)) }
			s.noise(0.45, 0.04, 0.16, 0.45, lp: 2600, hp: 500, at: 0.05)
			peak = 0.55
		case .infuse:
			// a rising shimmer
			s = Synth(0.8, seed: seed)
			for (k, f) in [440.0, 554.0, 659.0, 880.0].enumerated() { s.tone(f * p, f * 1.01 * p, 0.45, 0.04, 0.2, 0.22, wave: 1, at: Double(k) * 0.08, vibrato: 6) }
			peak = 0.45
		case .suitUp:
			// servos and a latch
			s = Synth(0.45, seed: seed)
			s.tone(180 * p, 420 * p, 0.25, 0.01, 0.1, 0.3, wave: 3)
			s.noise(0.06, 0.001, 0.02, 0.6, lp: 4000, hp: 800, at: 0.28)
			s.tone(1200 * p, 1100 * p, 0.05, 0.001, 0.02, 0.25, at: 0.3)
			peak = 0.45
		}
		s.finish(peak)
		return s.out
	}

	/// Seamless loops: whole numbers of cycles per loop, and noise cross-faded into its own start
	static func loop(_ id: LoopID) -> [Float] {
		var s: Synth
		switch id {
		case .engine:
			s = Synth(1.0, seed: 101)
			s.tone(55, 55, 1.0, 0.0001, 1000, 0.5, wave: 2)
			s.tone(110, 110, 1.0, 0.0001, 1000, 0.25, wave: 3)
			for i in 0..<s.out.count { s.out[i] *= Float(0.75 + 0.25 * sin(Double(i) / Synth.rate * 9.0 * 2.0 * Double.pi)) }
		case .drill:
			s = Synth(1.0, seed: 102)
			s.tone(180, 180, 1.0, 0.0001, 1000, 0.4, wave: 3)
			s.noise(1.0, 0.0001, 1000, 0.2, lp: 2000, hp: 300)
			for i in 0..<s.out.count { s.out[i] *= Float(0.7 + 0.3 * sin(Double(i) / Synth.rate * 30.0 * 2.0 * Double.pi)) }
		case .rain:
			s = Synth(2.2, seed: 103)
			s.noise(2.2, 0.0001, 1000, 0.6, lp: 3000, hp: 500)
		case .wind:
			s = Synth(3.2, seed: 104)
			s.noise(3.2, 0.0001, 1000, 0.6, lp: 300, hp: 40)
			for i in 0..<s.out.count { s.out[i] *= Float(0.6 + 0.4 * sin(Double(i) / Synth.rate / 3.0 * 2.0 * Double.pi)) }
		case .heavyRain:
			// denser and deeper than light rain, with slow surges
			s = Synth(3.0, seed: 105)
			s.noise(3.0, 0.0001, 1000, 0.7, lp: 1800, hp: 120)
			s.noise(3.0, 0.0001, 1000, 0.3, lp: 5000, hp: 1500)
			for i in 0..<s.out.count { s.out[i] *= Float(0.8 + 0.2 * sin(Double(i) / Synth.rate / 1.4 * 2.0 * Double.pi)) }
		case .gale:
			// a howl: band-limited noise whose loudness rises and falls in gusts
			s = Synth(4.2, seed: 106)
			s.noise(4.2, 0.0001, 1000, 0.6, lp: 900, hp: 250)
			s.noise(4.2, 0.0001, 1000, 0.4, lp: 260, hp: 60)
			for i in 0..<s.out.count {
				let t: Double = Double(i) / Synth.rate
				s.out[i] *= Float(0.55 + 0.3 * sin(t / 2.0 * 2.0 * Double.pi) + 0.15 * sin(t / 0.5 * 2.0 * Double.pi))
			}
		case .hail:
			// countless small stones ticking on everything
			s = Synth(2.2, seed: 107)
			s.noise(2.2, 0.0001, 1000, 0.15, lp: 6000, hp: 1800)
			var k: Int = 0
			while k < 110 {
				let at: Double = s.rnd() * 0.5 + 0.5
				s.noise(0.02, 0.0005, 0.006, 0.6, lp: 9000, hp: 2400, at: at * 2.0)
				k += 1
			}
		case .tornado:
			// a deep, steady roar like a train that does not pass
			s = Synth(3.4, seed: 108)
			s.noise(3.4, 0.0001, 1000, 0.8, lp: 180, hp: 25)
			s.noise(3.4, 0.0001, 1000, 0.3, lp: 700, hp: 200)
			for i in 0..<s.out.count { s.out[i] *= Float(0.75 + 0.25 * sin(Double(i) / Synth.rate / 0.85 * 2.0 * Double.pi)) }
		case .siren:
			// a siren's slow rise and fall: the pitch's swing averages out over the loop, so the wave
			// ends exactly where it began
			s = Synth(4.0, seed: 109)
			var ph: Double = 0
			for i in 0..<s.out.count {
				let t: Double = Double(i) / Synth.rate
				let f: Double = 640.0 + 220.0 * sin(t / 4.0 * 2.0 * Double.pi)
				ph += f / Synth.rate
				let x: Double = ph - floor(ph)
				s.out[i] = Float(tanh(sin(x * 2.0 * Double.pi) * 2.0) * 0.5)
			}
		}
		if id == .siren {
			// the siren's wave already joins up end to start: no fades, which would dip at the seam
			var m: Float = 0
			for v in s.out { m = max(m, abs(v)) }
			if m > 0 { for i in 0..<s.out.count { s.out[i] *= 0.6 / m } }
		} else {
			s.finish(0.6)
		}
		if id == .rain || id == .wind || id == .heavyRain || id == .gale || id == .hail || id == .tornado {
			// fold the extra 0.2 s back over the start so the loop point is seamless
			let tail: Int = Int(0.2 * Synth.rate)
			let n: Int = s.out.count - tail
			for i in 0..<tail {
				let k: Float = Float(i) / Float(tail)
				s.out[i] = s.out[i] * k + s.out[n + i] * (1 - k)
			}
			s.out.removeLast(tail)
		}
		return s.out
	}
}

/// Plays the effects: a small pool of voices (the oldest is cut off when all are busy), a minimum gap
/// between repeats of the same effect, and four looping beds whose volume follows the game.
final class Sound {
	static let shared: Sound = Sound()
	private let engine: AVAudioEngine = AVAudioEngine()
	private var format: AVAudioFormat? = nil
	private var voices: [AVAudioPlayerNode] = []
	private var loopNodes: [AVAudioPlayerNode] = []
	private var buffers: [Int: [AVAudioPCMBuffer]] = [:]
	private var lastPlay: [Int: Double] = [:]
	private var nextVoice: Int = 0
	private(set) var running: Bool = false
	private var started: Bool = false
	var enabled: Bool = true
	var sfxVolume: Float = 0.7
	var ambienceVolume: Float = 0.5

	/// Call once the game is on screen
	func start() {
		if started { return }
		started = true
		#if os(iOS)
		// ambient: mixes with the player's own music and respects the silent switch
		try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
		try? AVAudioSession.sharedInstance().setActive(true)
		#endif
		guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Synth.rate, channels: 1) else { return }
		format = fmt
		for _ in 0..<8 {
			let n = AVAudioPlayerNode()
			engine.attach(n)
			engine.connect(n, to: engine.mainMixerNode, format: fmt)
			voices.append(n)
		}
		for _ in LoopID.allCases {
			let n = AVAudioPlayerNode()
			engine.attach(n)
			engine.connect(n, to: engine.mainMixerNode, format: fmt)
			n.volume = 0
			loopNodes.append(n)
		}
		engine.prepare()
		do { try engine.start() } catch { return }
		running = true
		for v in voices { v.play() }
		for l in LoopID.allCases {
			let n: AVAudioPlayerNode = loopNodes[l.rawValue]
			if let b = makeBuffer(SoundBank.loop(l)) {
				n.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
				n.play()
			}
		}
	}

	private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
		guard let fmt = format, let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
		b.frameLength = AVAudioFrameCount(samples.count)
		if let ch = b.floatChannelData {
			for i in 0..<samples.count { ch[0][i] = samples[i] }
		}
		return b
	}

	static func minGap(_ id: SoundID) -> Double {
		switch id {
		case .pickup, .tap: return 0.05
		case .digStone, .digDirt, .digWood, .digSand, .digCrystal, .digLeaves: return 0.09
		case .hit, .arrowHit: return 0.06
		case .land, .place, .door: return 0.08
		case .warn: return 0.35
		case .roar, .portal, .discovery, .explosion, .rareLoot: return 0.25
		case .thunderNear: return 0.3
		case .thunderFar: return 0.5
		case .strikeWarn: return 0.6
		case .weatherAlert: return 2.0
		case .hailTick: return 0.07
		case .crit, .multiHit, .swingLight: return 0.05
		case .daze, .flask: return 0.15
		default: return 0.04
		}
	}

	func play(_ id: SoundID, _ volume: Double = 1.0) {
		guard running && enabled && sfxVolume > 0 && volume > 0.02 else { return }
		let now: Double = Date().timeIntervalSinceReferenceDate
		if let t = lastPlay[id.rawValue], now - t < Sound.minGap(id) { return }
		lastPlay[id.rawValue] = now
		if buffers[id.rawValue] == nil {
			var list: [AVAudioPCMBuffer] = []
			for v in 0..<3 { if let b = makeBuffer(SoundBank.effect(id, v)) { list.append(b) } }
			buffers[id.rawValue] = list
		}
		guard let list = buffers[id.rawValue], !list.isEmpty else { return }
		let b: AVAudioPCMBuffer = list[Int.random(in: 0..<list.count)]
		let v: AVAudioPlayerNode = voices[nextVoice]
		nextVoice = (nextVoice + 1) % voices.count
		v.volume = Float(min(1.0, volume)) * sfxVolume
		v.scheduleBuffer(b, at: nil, options: .interrupts, completionHandler: nil)
		if !v.isPlaying { v.play() }
	}

	/// Silences every loop at once: leaving a world (nothing sets their volumes any more after that)
	func silenceLoops() {
		for n in loopNodes { n.volume = 0 }
	}

	func setLoop(_ id: LoopID, _ volume: Double) {
		guard running else { return }
		let target: Float = enabled ? Float(max(0, min(1, volume))) * ambienceVolume : 0
		let n: AVAudioPlayerNode = loopNodes[id.rawValue]
		// ease toward the target so loops fade in and out instead of popping
		n.volume += (target - n.volume) * 0.15
	}
}

extension Game {
	/// A sound effect; world events further than ~32 blocks from the player are not heard
	func sfx(_ id: SoundID, at x: Double? = nil, _ volume: Double = 1.0) {
		var v: Double = volume
		if let wx = x { v *= max(0, 1.0 - abs(wx - pb.x) / 32.0) }
		Sound.shared.play(id, v)
	}

	func digSound(_ t: Tile, broke: Bool) {
		let m: Int = soundMaterial(t)
		let id: SoundID
		switch m {
		case 0: id = broke ? .breakStone : .digStone
		case 1: id = broke ? .breakDirt : .digDirt
		case 2: id = broke ? .breakWood : .digWood
		case 3: id = broke ? .breakDirt : .digSand
		case 4: id = broke ? .breakCrystal : .digCrystal
		default: id = .digLeaves
		}
		sfx(id, broke ? 0.9 : 0.6)
	}

	/// Once a frame: settings into the mixer, and the looping beds (engine, drill, rain, wind)
	func updateAudio() {
		let snd: Sound = Sound.shared
		snd.enabled = settings.soundOn
		snd.sfxVolume = Float(settings.sfxVolume)
		snd.ambienceVolume = Float(settings.ambienceVolume)
		if !snd.running { return }
		var engineV: Double = 0
		var drillV: Double = 0
		if let v = inVehicle, v.engines > 0, v.fuel > 0 || isCreative {
			engineV = 0.3 + 0.5 * abs(v.throttle)
			if v.drilling { drillV = 0.7 }
		}
		snd.setLoop(.engine, engineV)
		snd.setLoop(.drill, drillV)
		// the weather beds, layered: light and heavy rain, wind and gale, hail, a tornado, a siren. They
		// all run from the start and only their volumes move, so nothing restarts or clicks. Under a roof
		// the rain and wind are muffled rather than cut.
		let L: LocalWeather = wxHere
		let ow: Bool = world.dim == .overworld && settings.weatherOn
		let muffle: Double = shelterLevel == 0 ? 1.0 : (shelterLevel == 1 ? 0.55 : (shelterLevel == 2 ? 0.3 : 0.08))
		let rainV: Double = ow && !L.snow ? L.precip : 0
		snd.setLoop(.rain, min(1.0, rainV * 1.1) * muffle)
		snd.setLoop(.heavyRain, clampD((rainV - 0.45) * 1.6, 0, 1) * muffle)
		let aw: Double = ow ? abs(L.wind) : 0
		let high: Double = world.dim == .overworld && shelterLevel == 0 && pb.y < 80 ? 0.35 : 0
		snd.setLoop(.wind, world.dim == .umbral ? 0.6 : max(high, clampD(aw / 10.0, 0, 0.8) * muffle))
		snd.setLoop(.gale, clampD((aw - 8.0) / 8.0, 0, 1) * muffle)
		snd.setLoop(.hail, ow ? clampD(L.hail * 1.2, 0, 1) * muffle : 0)
		var roar: Double = 0
		if ow, let e = weather.tornado { roar = clampD(1.0 - abs(e.x - pb.x) / 90.0, 0, 1) * e.funnel * max(muffle, 0.4) }
		snd.setLoop(.tornado, roar)
		snd.setLoop(.siren, sirenLevel * 0.7)
	}
}


// MARK: - Weather: one simulation for the whole overworld
// The weather is a single saved simulation (WeatherSim), stepped once a frame by the game clock. It
// holds the state over the region (clear, rain, a storm...), the plan of what comes next (the forecast
// devices read it directly), amounts that ease toward whatever the state and the settings allow (cloud,
// rain, wind, lightning, hail, cold) and the two rare events (a tornado, a hurricane). What a place
// actually gets is worked out from that and the place itself: storm cells drift over the land with the
// wind (a noise field in world space, so it is the same whichever chunks happen to be loaded), deserts
// stay dry, cold country gets snow and the coast takes the brunt of a hurricane. Nothing keeps a timer
// of its own: rain, lightning, hail, cold and the weather devices all read the simulation.

enum WeatherKind: Int, Codable, CaseIterable {
	case clear, partlyCloudy, overcast, lightRain, heavyRain, thunderstorm, strongWind, windstorm, hailstorm, snowfall, blizzard, tornado, hurricane

	var name: String {
		switch self {
		case .clear: return "Clear"
		case .partlyCloudy: return "Partly cloudy"
		case .overcast: return "Overcast"
		case .lightRain: return "Light rain"
		case .heavyRain: return "Heavy rain"
		case .thunderstorm: return "Thunderstorm"
		case .strongWind: return "Strong wind"
		case .windstorm: return "Windstorm"
		case .hailstorm: return "Hailstorm"
		case .snowfall: return "Snowfall"
		case .blizzard: return "Blizzard"
		case .tornado: return "Tornado"
		case .hurricane: return "Hurricane"
		}
	}

	var severe: Bool {
		switch self {
		case .thunderstorm, .windstorm, .hailstorm, .blizzard, .tornado, .hurricane: return true
		default: return false
		}
	}


	/// What a spell of it brings at full strength (before the settings and the place are applied)
	var profile: WeatherProfile {
		switch self {
		case .clear: return WeatherProfile(cloud: 0.04, wind: 1.2, gust: 0.25)
		case .partlyCloudy: return WeatherProfile(cloud: 0.35, wind: 2.4, gust: 0.35)
		case .overcast: return WeatherProfile(cloud: 0.72, wind: 3.0, gust: 0.35)
		case .lightRain: return WeatherProfile(cloud: 0.78, precip: 0.38, wind: 3.0, gust: 0.4, cover: 0.55)
		case .heavyRain: return WeatherProfile(cloud: 0.9, precip: 0.85, wind: 5.0, gust: 0.5, cover: 0.8)
		case .thunderstorm: return WeatherProfile(cloud: 1.0, precip: 0.9, wind: 7.0, gust: 0.7, thunder: 6.0, cover: 0.75)
		case .strongWind: return WeatherProfile(cloud: 0.4, wind: 9.0, gust: 0.6, cover: 0.3)
		case .windstorm: return WeatherProfile(cloud: 0.7, precip: 0.15, wind: 14.0, gust: 0.8, cover: 0.4)
		case .hailstorm: return WeatherProfile(cloud: 0.95, precip: 0.55, wind: 6.0, gust: 0.6, thunder: 2.0, hail: 1.0, cover: 0.6)
		case .snowfall: return WeatherProfile(cloud: 0.8, precip: 0.6, wind: 2.5, gust: 0.4, cover: 0.85, chill: 0.2)
		case .blizzard: return WeatherProfile(cloud: 1.0, precip: 1.0, wind: 13.0, gust: 0.7, cover: 1.0, chill: 1.0)
		case .tornado: return WeatherProfile(cloud: 1.0, precip: 0.75, wind: 8.0, gust: 0.8, thunder: 5.0, hail: 0.25, cover: 0.7)
		case .hurricane: return WeatherProfile(cloud: 1.0, precip: 1.0, wind: 15.0, gust: 0.8, thunder: 2.0, cover: 1.0)
		}
	}

	/// How long a spell of it lasts, in seconds of play (a day is 720)
	var spell: ClosedRange<Double> {
		switch self {
		case .clear: return 180...420
		case .partlyCloudy: return 150...300
		case .overcast: return 120...240
		case .lightRain: return 90...200
		case .heavyRain: return 70...150
		case .thunderstorm: return 80...150
		case .strongWind: return 70...140
		case .windstorm: return 60...110
		case .hailstorm: return 35...70
		case .snowfall: return 120...240
		case .blizzard: return 80...150
		case .tornado: return 95...120
		case .hurricane: return 330...440
		}
	}
}

struct WeatherProfile {
	var cloud: Double = 0
	var precip: Double = 0
	/// typical air speed over open ground, in blocks per second
	var wind: Double = 0
	/// how far the wind gusts above and below that (0 steady ... 1 wild)
	var gust: Double = 0
	/// lightning strikes per minute over the land around the player
	var thunder: Double = 0
	var hail: Double = 0
	/// how much of the land the rain covers at once (0 scattered showers ... 1 everywhere)
	var cover: Double = 0
	/// how much colder it makes the land
	var chill: Double = 0
}

struct WeatherStep: Codable {
	var kind: WeatherKind
	var dur: Double
}

/// A tornado: it forms far off (the warning), touches down and crosses the land with the wind, then
/// ropes out. Its strength never changes on the way, so its danger can be judged from afar.
struct TornadoEvent: Codable {
	var x: Double
	/// which way it travels (-1 west, 1 east) and how fast
	var dir: Double
	var speed: Double
	/// 0 forming (the warning), 1 on the ground, 2 roping out
	var phase: Int = 0
	var t: Double = 0
	var warnDur: Double
	var groundDur: Double
	var strength: Double
	var wander: Double
	/// blocks it has torn loose so far (it stops tearing at a limit)
	var broken: Int = 0
	var uid: Int = 0
	/// closest it came to the player (for the journal)
	var closest: Double = 1e9

	static let ropeDur: Double = 8.0

	/// 0...1: how much of a funnel there is (grows while forming, thins as it ropes out)
	var funnel: Double {
		switch phase {
		case 0: return clampD((t - warnDur + 12.0) / 12.0, 0, 1) * 0.55
		case 1: return min(1.0, 0.55 + t / 4.0)
		default: return max(0, 1.0 - t / TornadoEvent.ropeDur)
		}
	}
	/// how hard it blows and tears (0 while it is only forming)
	var force: Double {
		switch phase {
		case 0: return 0
		case 1: return strength * min(1.0, t / 4.0)
		default: return strength * max(0, 1.0 - t / TornadoEvent.ropeDur)
		}
	}
}

enum HurricaneStage: Int, Codable, CaseIterable {
	case approaching, intensifying, peak, eye, backside, weakening, clearing

	var name: String {
		switch self {
		case .approaching: return "approaching"
		case .intensifying: return "intensifying"
		case .peak: return "at its height"
		case .eye: return "the eye is passing"
		case .backside: return "back wall of the storm"
		case .weakening: return "weakening"
		case .clearing: return "clearing"
		}
	}
	/// how hard it blows in this stage (0...1 of its strength)
	var force: Double {
		switch self {
		case .approaching: return 0.35
		case .intensifying: return 0.7
		case .peak: return 1.0
		case .eye: return 0.12
		case .backside: return 0.95
		case .weakening: return 0.55
		case .clearing: return 0.2
		}
	}
	/// share of the whole storm's length
	var share: Double {
		switch self {
		case .approaching: return 0.26
		case .intensifying: return 0.15
		case .peak: return 0.13
		case .eye: return 0.05
		case .backside: return 0.12
		case .weakening: return 0.15
		case .clearing: return 0.14
		}
	}
}

/// A hurricane comes in off the sea in stages, blowing onshore until the eye passes and offshore
/// after it. It is felt hardest at the coast and fades inland.
struct HurricaneEvent: Codable {
	var stage: HurricaneStage = .approaching
	var t: Double = 0
	var total: Double
	/// the side the sea (and the storm) is on: -1 west, 1 east
	var side: Double
	/// where it comes ashore
	var coastX: Double
	var strength: Double
	/// eased 0...1 force now
	var force: Double = 0
	var broken: Int = 0
	var closest: Double = 1e9

	var stageDur: Double { return total * stage.share }
	/// seconds from now until the end of each stage, then the time it is over
	func timeLeft() -> Double {
		var left: Double = stageDur - t
		var k: Int = stage.rawValue + 1
		while k < HurricaneStage.allCases.count {
			left += total * HurricaneStage.allCases[k].share
			k += 1
		}
		return max(0, left)
	}
}

/// Wet ground and lying snow over a 48-block stretch of land
struct GroundCell: Codable {
	var wet: Double = 0
	var snow: Double = 0
	var t: Double = 0
}

struct SurgeCell: Codable, Hashable {
	var x: Int
	var y: Int
}

/// A storm the player lived through, for the journal
struct StormRecord: Codable {
	var kind: Int
	var day: Int
	var note: String
}

struct WeatherSim: Codable {
	var kind: WeatherKind = .clear
	var stateT: Double = 0
	var stateDur: Double = 300
	/// what comes after the present spell, in order (kept four steps long)
	var plan: [WeatherStep] = []
	/// smoothed amounts (see WeatherProfile); wind is signed, positive blowing east
	var cloud: Double = 0.04
	var precip: Double = 0
	var wind: Double = 1.0
	var gust: Double = 0.25
	var thunder: Double = 0
	var hail: Double = 0
	var chill: Double = 0
	var cover: Double = 0
	/// which way the wind is set to blow (-1 / 1); it may turn round between spells
	var windDir: Double = 1
	/// how far the storm cells and the clouds have drifted with the wind, in blocks
	var drift: Double = 0
	var cloudDrift: Double = 0
	/// weather clock: seconds of play since the simulation began
	var t: Double = 0
	var rngS: UInt64 = 0x51ED_2701
	/// a second stream for what the weather does (where bolts fall, what the wind tears loose), so
	/// those never change what the weather itself does next
	var fxS: UInt64 = 0xFACE_0FF5
	/// severe weather (and tornadoes and hurricanes, more rarely still) may not begin before these
	/// times: each severe spell is followed by a calm (a new world starts with one)
	var calmUntil: Double = 600
	var tornadoUntil: Double = 1200
	var hurricaneUntil: Double = 1800
	var bigHail: Bool = false
	var tornado: TornadoEvent? = nil
	var hurricane: HurricaneEvent? = nil
	var cells: [Int: GroundCell] = [:]
	/// what weather devices hold (rain collectors, turbines), by place
	var store: [String: Double] = [:]
	/// sea water a storm surge pushed ashore, taken away again when the storm passes
	var surge: [SurgeCell] = []
	/// the settings the plan was made under (a change makes it again)
	var planSig: Int = -1
	/// whether the master switch was on last frame
	var wasOn: Bool = true

	init() {}

	enum CodingKeys: String, CodingKey {
		case kind, stateT, stateDur, plan, cloud, precip, wind, gust, thunder, hail, chill, cover, windDir, drift, cloudDrift, t, rngS, fxS
		case calmUntil, tornadoUntil, hurricaneUntil, bigHail, tornado, hurricane, cells, store, surge, planSig, wasOn
	}

	/// Missing or damaged fields fall back to their defaults, so a weather record never stops a world
	/// from loading
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		kind = (try? c.decodeIfPresent(WeatherKind.self, forKey: .kind)) ?? .clear
		stateT = (try? c.decodeIfPresent(Double.self, forKey: .stateT)) ?? 0
		stateDur = (try? c.decodeIfPresent(Double.self, forKey: .stateDur)) ?? 300
		plan = (try? c.decodeIfPresent([WeatherStep].self, forKey: .plan)) ?? []
		cloud = (try? c.decodeIfPresent(Double.self, forKey: .cloud)) ?? 0.04
		precip = (try? c.decodeIfPresent(Double.self, forKey: .precip)) ?? 0
		wind = (try? c.decodeIfPresent(Double.self, forKey: .wind)) ?? 1.0
		gust = (try? c.decodeIfPresent(Double.self, forKey: .gust)) ?? 0.25
		thunder = (try? c.decodeIfPresent(Double.self, forKey: .thunder)) ?? 0
		hail = (try? c.decodeIfPresent(Double.self, forKey: .hail)) ?? 0
		chill = (try? c.decodeIfPresent(Double.self, forKey: .chill)) ?? 0
		cover = (try? c.decodeIfPresent(Double.self, forKey: .cover)) ?? 0
		windDir = (try? c.decodeIfPresent(Double.self, forKey: .windDir)) ?? 1
		drift = (try? c.decodeIfPresent(Double.self, forKey: .drift)) ?? 0
		cloudDrift = (try? c.decodeIfPresent(Double.self, forKey: .cloudDrift)) ?? 0
		t = (try? c.decodeIfPresent(Double.self, forKey: .t)) ?? 0
		rngS = (try? c.decodeIfPresent(UInt64.self, forKey: .rngS)) ?? 0x51ED_2701
		fxS = (try? c.decodeIfPresent(UInt64.self, forKey: .fxS)) ?? 0xFACE_0FF5
		calmUntil = (try? c.decodeIfPresent(Double.self, forKey: .calmUntil)) ?? 600
		tornadoUntil = (try? c.decodeIfPresent(Double.self, forKey: .tornadoUntil)) ?? 1200
		hurricaneUntil = (try? c.decodeIfPresent(Double.self, forKey: .hurricaneUntil)) ?? 1800
		bigHail = (try? c.decodeIfPresent(Bool.self, forKey: .bigHail)) ?? false
		tornado = (try? c.decodeIfPresent(TornadoEvent.self, forKey: .tornado)) ?? nil
		hurricane = (try? c.decodeIfPresent(HurricaneEvent.self, forKey: .hurricane)) ?? nil
		cells = (try? c.decodeIfPresent([Int: GroundCell].self, forKey: .cells)) ?? [:]
		store = (try? c.decodeIfPresent([String: Double].self, forKey: .store)) ?? [:]
		surge = (try? c.decodeIfPresent([SurgeCell].self, forKey: .surge)) ?? []
		planSig = (try? c.decodeIfPresent(Int.self, forKey: .planSig)) ?? -1
		wasOn = (try? c.decodeIfPresent(Bool.self, forKey: .wasOn)) ?? true
		// a record from a broken save must not leave the simulation stuck
		if !stateDur.isFinite || stateDur <= 0 { stateDur = 120 }
		if !stateT.isFinite || stateT < 0 { stateT = 0 }
		if !wind.isFinite { wind = 1 }
	}

	/// The simulation's own random numbers (saved with it, so a reloaded world carries on the same way)
	mutating func rand() -> Double {
		rngS = rngS &+ 0x9E3779B97F4A7C15
		var z: UInt64 = rngS
		z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
		z = z ^ (z >> 31)
		return Double(z >> 11) / 9007199254740992.0
	}

	mutating func pick(_ r: ClosedRange<Double>) -> Double {
		let u: Double = rand()
		return r.lowerBound + (r.upperBound - r.lowerBound) * u
	}

	/// The effects' stream (see fxS)
	mutating func fx() -> Double {
		fxS = fxS &+ 0x9E3779B97F4A7C15
		var z: UInt64 = fxS
		z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
		z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
		z = z ^ (z >> 31)
		return Double(z >> 11) / 9007199254740992.0
	}

	mutating func fxPick(_ r: ClosedRange<Double>) -> Double {
		let u: Double = fx()
		return r.lowerBound + (r.upperBound - r.lowerBound) * u
	}
}

/// The weather at one place, after the storm cells, the land and the height have had their say
struct LocalWeather {
	var cloud: Double = 0
	/// how hard it is falling here (0...1)
	var precip: Double = 0
	var snow: Bool = false
	/// signed air speed (blocks per second), gusts included
	var wind: Double = 0
	var thunder: Double = 0
	var hail: Double = 0
	/// 0 warm ... 1 bitter (snow falls from 0.5)
	var chill: Double = 0
	var hot: Bool = false
	/// how much the air is thick with rain or snow (0 clear ... 1 a whiteout)
	var fog: Double = 0
	var wet: Double = 0
	var snowCover: Double = 0
	/// 0...1: how hard a tornado or hurricane is felt here
	var tornado: Double = 0
	var hurricane: Double = 0
}

/// Where the weather is judged when picking what comes next
struct WeatherContext {
	var cold: Bool = false
	var dry: Bool = false
	var tornadoCountry: Bool = false
	/// the sea is that way (-1 west, 1 east) and near enough for a hurricane; 0 when too far inland
	var seaSide: Double = 0
	var coastX: Double = 0
}

/// Walks forward through the present spell and the plan, keeping track of when severe weather may
/// next begin (the planner and the simulation use the same rules, so the forecast holds)
struct PlanCursor {
	var T: Double
	var calm: Double
	var tor: Double
	var hur: Double
	var last: WeatherKind

	mutating func note(_ k: WeatherKind, _ end: Double, _ gaps: (Double, Double, Double)) {
		if k.severe { calm = max(calm, end + gaps.0) }
		if k == .tornado { tor = max(tor, end + gaps.1) }
		if k == .hurricane { hur = max(hur, end + gaps.2) }
		last = k
		T = end
	}
}

/// A bolt of lightning on screen: the main channel, a few forks, and how long it shows
struct LightningBolt {
	var pts: [(Double, Double)]
	var forks: [[(Double, Double)]]
	var life: Double
	var maxLife: Double
}

/// A strike about to land near the player: shown and heard first, so it can be dodged
struct StrikeMark {
	var x: Double
	var y: Double
	var t: Double
	var total: Double
}

struct PendingThunder {
	var t: Double
	var vol: Double
	var near: Bool
}

/// One hailstone of the small pool the hail is drawn from (it bounces once, then breaks)
struct HailStone {
	var x: Double = 0
	var y: Double = 0
	var vx: Double = 0
	var vy: Double = 0
	var bounces: Int = 0
	var size: Double = 0.12
	var on: Bool = false
}

struct ForecastLine {
	var kind: WeatherKind
	var startsIn: Double
	var dur: Double
}

// MARK: - Weather simulation: states, the plan, smoothing and the weather at a place

/// how wet a biome's weather is (deserts mostly stay dry under passing storms)
func biomeWetness(_ b: Biome) -> Double {
	switch b {
	case .desert: return 0.1
	case .savanna: return 0.5
	case .jungle: return 1.15
	case .swamp: return 1.1
	default: return 1.0
	}
}

/// width of the strips of land that remember wet ground and lying snow
let groundCellW: Double = 48.0

extension Game {
	/// Calm kept between severe spells, and the longer gaps between tornadoes and between hurricanes,
	/// by the frequency setting
	func weatherGaps() -> (Double, Double, Double) {
		switch settings.severeFrequency {
		case 0: return (900, 3600, 5400)
		case 2: return (150, 600, 900)
		default: return (420, 1800, 2700)
		}
	}

	/// How much more (or less) often severe weather is picked when it may come
	func severeWeight() -> Double {
		switch settings.severeFrequency {
		case 0: return 0.4
		case 2: return 2.2
		default: return 1.0
		}
	}

	var weatherIntensity: Double { return clampD(settings.weatherIntensity, 0.25, 1.5) }

	func weatherAllowed(_ k: WeatherKind) -> Bool {
		let s: Settings = settings
		switch k {
		case .lightRain, .heavyRain, .snowfall: return s.allowRain
		case .thunderstorm: return s.allowThunder
		case .strongWind, .windstorm: return s.allowWind
		case .hailstorm: return s.allowHail
		case .blizzard: return s.allowBlizzard
		case .tornado: return s.allowTornado
		case .hurricane: return s.allowHurricane
		default: return true
		}
	}

	/// The settings the forecast depends on; when they change the plan is made again
	func planSignature() -> Int {
		let s: Settings = settings
		var k: Int = s.severeFrequency
		let flags: [Bool] = [s.allowRain, s.allowThunder, s.allowWind, s.allowTornado, s.allowHurricane, s.allowBlizzard, s.allowHail]
		for f in flags { k = k * 2 + (f ? 1 : 0) }
		return k
	}

	/// What a state brings once the switched-off kinds of weather are taken out and the intensity is
	/// applied. Blizzards and hurricanes bring their own snow, rain and wind (their switches decide).
	func allowedProfile(_ k: WeatherKind) -> WeatherProfile {
		let s: Settings = settings
		if !s.weatherOn { return WeatherProfile() }
		var kk: WeatherKind = k
		if kk == .blizzard && !s.allowBlizzard { kk = .snowfall }
		if kk == .hurricane && !s.allowHurricane { kk = .windstorm }
		if kk == .tornado && !s.allowTornado { kk = .thunderstorm }
		var p: WeatherProfile = kk.profile
		let own: Bool = kk == .blizzard || kk == .hurricane
		if !s.allowRain && !own { p.precip = 0 }
		if !s.allowWind && !own {
			p.wind = 0
			p.gust = 0
		}
		if !s.allowThunder { p.thunder = 0 }
		if !s.allowHail { p.hail = 0 }
		let I: Double = weatherIntensity
		let mw: ModWeather? = ModRuntime.shared.weather
		p.precip = min(1.0, p.precip * I * (mw?.rain ?? 1))
		p.wind *= I * (mw?.wind ?? 1)
		p.thunder *= I
		p.hail = min(1.0, p.hail * I)
		return p
	}

	/// Where the weather is judged: the player in the overworld, or where they left it
	var weatherX: Double { return world.dim == .overworld ? pb.x : wxHomeX }

	func weatherContext() -> WeatherContext {
		var c = WeatherContext()
		let x: Int = Int(floor(weatherX))
		let col: Col = gen.col(x)
		let b: Biome = col.biome
		c.cold = b == .tundra || (b == .mountain && col.h < 84)
		c.dry = b == .desert
		c.tornadoCountry = b == .plains || b == .savanna || b == .forest || b == .swamp || b == .desert
		if let sea = seaNear(x) {
			c.seaSide = sea.0
			c.coastX = sea.1
		}
		return c
	}

	/// The nearest open sea within 280 blocks: which side it is on, and where its shore is
	func seaNear(_ x: Int) -> (Double, Double)? {
		let key: Int = floorDiv(x, 32)
		if let c = coastCache[key] { return c.0 == 0 ? nil : c }
		var found: (Double, Double) = (0, 0)
		var d: Int = 0
		while d <= 280 {
			if gen.col(x + d).biome == .ocean { found = (1, Double(x + d)); break }
			if gen.col(x - d).biome == .ocean { found = (-1, Double(x - d)); break }
			d += 8
		}
		if coastCache.count > 256 { coastCache.removeAll() }
		coastCache[key] = found
		return found.0 == 0 ? nil : found
	}

	// MARK: the plan (the forecast is read straight from it)

	/// Where the present spell and the plan end, and when severe weather may next begin after them
	func planCursor() -> PlanCursor {
		let gaps: (Double, Double, Double) = weatherGaps()
		var cur = PlanCursor(T: weather.t, calm: weather.calmUntil, tor: weather.tornadoUntil, hur: weather.hurricaneUntil, last: weather.kind)
		cur.note(weather.kind, weather.t + max(0, weather.stateDur - weather.stateT), gaps)
		for s in weather.plan { cur.note(s.kind, cur.T + s.dur, gaps) }
		return cur
	}

	func fillPlan() {
		if weather.plan.count >= 4 { return }
		let ctx: WeatherContext = weatherContext()
		let gaps: (Double, Double, Double) = weatherGaps()
		var cur: PlanCursor = planCursor()
		while weather.plan.count < 4 {
			let step: WeatherStep = planStep(cur, ctx)
			weather.plan.append(step)
			cur.note(step.kind, cur.T + step.dur, gaps)
		}
	}

	/// Picks the spell that follows `cur.last`, beginning at `cur.T`. Weather moves to its neighbours
	/// (clear to cloud to rain to storm and back), so it changes gradually; severe spells may only
	/// begin once the calm after the last one is over, and a thunderstorm may grow hail or spin up a
	/// tornado as part of the same storm.
	func planStep(_ cur: PlanCursor, _ ctx: WeatherContext) -> WeatherStep {
		let s: Settings = settings
		let fw: Double = severeWeight()
		let sev: Double = cur.T >= cur.calm ? fw : 0
		var opts: [(WeatherKind, Double)] = []
		let modWx: ModWeather? = ModRuntime.shared.weather
		func add(_ k: WeatherKind, _ w: Double) {
			let m: Double = modWx?.chanceOf(k) ?? 1
			if w > 0 && m > 0 && weatherAllowed(k) { opts.append((k, w * m)) }
		}
		let rain: WeatherKind = ctx.cold ? .snowfall : .lightRain
		let heavy: WeatherKind = ctx.cold ? .snowfall : .heavyRain
		let hurricaneOK: Bool = ctx.seaSide != 0 && !ctx.cold && cur.T >= cur.hur
		// with rain switched off the wet spells drop out; storms can still come, dry
		let dryFill: Double = s.allowRain ? 0 : 3.0
		switch cur.last {
		case .clear:
			add(.clear, 2.2)
			add(.partlyCloudy, 4.0)
			add(.strongWind, ctx.dry ? 1.2 : 0.5)
		case .partlyCloudy:
			add(.clear, 3.0)
			add(.partlyCloudy, 1.2)
			add(.overcast, 3.0)
			add(.strongWind, 0.6)
		case .overcast:
			add(.partlyCloudy, 2.5)
			add(.overcast, 0.6)
			add(rain, ctx.dry ? 0.7 : 3.0)
			add(heavy, ctx.dry ? 0.2 : 0.7)
			add(.windstorm, 0.35 * sev)
			if !ctx.cold { add(.hailstorm, 0.25 * sev) }
			if !s.allowRain && !ctx.cold { add(.thunderstorm, 0.6 * sev) }
			if hurricaneOK { add(.hurricane, 0.22 * sev) }
		case .lightRain:
			add(.overcast, 2.0)
			add(.lightRain, 1.0)
			add(.heavyRain, 2.4)
		case .heavyRain:
			add(.lightRain, 2.6)
			add(.heavyRain, 0.6)
			if !ctx.cold { add(.thunderstorm, 1.6 * sev) }
		case .thunderstorm:
			add(.heavyRain, 3.0)
			add(.overcast, dryFill)
			add(.hailstorm, 0.5 * fw)
			if ctx.tornadoCountry && cur.T >= cur.tor { add(.tornado, 0.45 * fw) }
		case .strongWind:
			add(.partlyCloudy, 2.4)
			add(.clear, 1.0)
			add(.strongWind, 0.6)
			add(.windstorm, 0.8 * sev)
			if hurricaneOK { add(.hurricane, 0.12 * sev) }
		case .windstorm:
			add(.strongWind, 2.5)
			add(.overcast, 1.5)
		case .hailstorm:
			add(.heavyRain, 2.5)
			add(.lightRain, 1.0)
			add(.overcast, dryFill)
		case .snowfall:
			add(.overcast, 2.4)
			add(.snowfall, 1.0)
			if ctx.cold { add(.blizzard, 0.9 * sev) }
		case .blizzard:
			add(.snowfall, 3.0)
			add(.overcast, dryFill)
		case .tornado, .hurricane:
			add(.heavyRain, 2.0)
			add(.lightRain, 1.0)
			add(.overcast, s.allowRain ? 0.3 : 3.0)
		}
		if opts.isEmpty, let mw = modWx {
			// a mod that rules out every usual next spell: any kind it allows comes straight in
			for k in WeatherKind.allCases where mw.chanceOf(k) > 0 && weatherAllowed(k) && (!k.severe || sev > 0) { opts.append((k, mw.chanceOf(k))) }
		}
		if opts.isEmpty { opts.append((.partlyCloudy, 1.0)) }
		var total: Double = 0
		for o in opts { total += o.1 }
		var r: Double = weather.rand() * total
		var k: WeatherKind = opts[opts.count - 1].0
		for o in opts {
			if r < o.1 {
				k = o.0
				break
			}
			r -= o.1
		}
		let dur: Double = weather.pick(k.spell) * (modWx?.length ?? 1)
		return WeatherStep(kind: k, dur: dur)
	}

	/// The present spell is over: the next one in the plan begins (and the plan is topped up)
	func advanceWeather() {
		let prev: WeatherKind = weather.kind
		let gaps: (Double, Double, Double) = weatherGaps()
		if prev.severe { weather.calmUntil = max(weather.calmUntil, weather.t + gaps.0) }
		if prev == .tornado { weather.tornadoUntil = max(weather.tornadoUntil, weather.t + gaps.1) }
		if prev == .hurricane { weather.hurricaneUntil = max(weather.hurricaneUntil, weather.t + gaps.2) }
		// a severe spell the player was out in goes in the journal (tornadoes and hurricanes keep their own)
		if prev.severe && prev != .tornado && prev != .hurricane && stormFelt && world.dim == .overworld {
			recordStorm(prev, weatherLabel(prev, snow: wxHere.snow).lowercased() == prev.name.lowercased() ? "weathered it" : weatherLabel(prev, snow: wxHere.snow).lowercased())
		}
		stormFelt = false
		if weather.plan.isEmpty { fillPlan() }
		var step: WeatherStep = weather.plan.removeFirst()
		let ctx: WeatherContext = weatherContext()
		// the land may have changed under the forecast (the player travelled): no hurricane far from
		// the sea, no tornado in the mountains or the snow
		if step.kind == .hurricane && ctx.seaSide == 0 { step.kind = settings.allowWind ? .windstorm : .overcast }
		if step.kind == .tornado && !ctx.tornadoCountry { step.kind = settings.allowThunder ? .thunderstorm : .heavyRain }
		weather.kind = step.kind
		weather.stateT = 0
		weather.stateDur = step.dur
		// calm spells can bring the wind round
		if (step.kind == .clear || step.kind == .partlyCloudy) && weather.rand() < 0.35 { weather.windDir = -weather.windDir }
		switch step.kind {
		case .tornado: spawnTornado()
		case .hurricane: spawnHurricane(ctx)
		case .hailstorm:
			weather.bigHail = weather.rand() < 0.15
			hailBroken = 0
		default: break
		}
		fillPlan()
		announceWeather(prev, step.kind)
	}

	/// Weather switched off: everything it was doing stops at once and leaves nothing behind (storm
	/// surge water is taken away as its ground loads; see updateSurge)
	func weatherShutdown() {
		weather.wasOn = false
		weather.tornado = nil
		weather.hurricane = nil
		weather.kind = .clear
		weather.stateT = 0
		weather.stateDur = 120
		weather.plan.removeAll()
		weather.cloud = 0
		weather.precip = 0
		weather.wind = 0
		weather.gust = 0
		weather.thunder = 0
		weather.hail = 0
		weather.chill = 0
		weather.cover = 0
		weather.cells.removeAll()
		clearWeatherFX()
		// fires lightning started go out with it
		fireZones.removeAll { $0.env }
	}

	/// The short-lived things weather puts in the world: bolts, thunder still on its way, a strike
	/// about to land, hailstones, alerts and the forces on the player
	func clearWeatherFX() {
		bolts.removeAll()
		thunderQueue.removeAll()
		strikeMark = nil
		strikeAcc = 0
		skyFlash = 0
		for i in 0..<hailPool.count { hailPool[i].on = false }
		hailAcc = 0
		wxBanner = ""
		wxBannerLevel = 0
		wxWalk = 0
		wxAirDrift = 0
		wxRest = 0
		wxAccelX = 0
		wxAccelY = 0
		wxSlip = 0
		wxSlow = 1
		weatherRain = 0
		weatherSnow = false
		wxHere = LocalWeather()
		tornadoAcc = 0
		hurricaneAcc = 0
	}

	/// Weather switched back on: it starts fair, with a calm before anything severe
	func weatherRestart() {
		weather.wasOn = true
		weather.kind = .clear
		weather.stateT = 0
		weather.stateDur = weather.pick(60...120)
		weather.calmUntil = max(weather.calmUntil, weather.t + 300)
		weather.plan.removeAll()
		weather.planSig = planSignature()
		fillPlan()
	}

	func easeTo(_ v: Double, _ to: Double, _ tau: Double, _ dt: Double) -> Double {
		let k: Double = 1.0 - exp(-dt / max(0.05, tau))
		return v + (to - v) * k
	}

	/// One step of the simulation (the regional state; what that means at a place is weatherAt)
	func stepWeatherSim(_ dt: Double) {
		if world.dim == .overworld { wxHomeX = pb.x }
		if !settings.weatherOn {
			if weather.wasOn { weatherShutdown() }
			// the scenery clouds still drift by as they always have
			weather.cloudDrift += CloudField.wind * dt
			return
		}
		if !weather.wasOn { weatherRestart() }
		weather.t += dt
		let sig: Int = planSignature()
		if sig != weather.planSig {
			weather.planSig = sig
			weather.plan.removeAll()
			// an event whose switch went off ends at once
			if weather.tornado != nil && !settings.allowTornado { endTornado(survived: false) }
			if weather.hurricane != nil && !settings.allowHurricane { endHurricane(survived: false) }
			fillPlan()
		}
		weather.stateT += dt
		let held: Bool = weather.tornado != nil || weather.hurricane != nil
		if weather.stateT >= weather.stateDur && !held { advanceWeather() }
		if weather.plan.count < 4 { fillPlan() }
		// ease toward what the state brings; anything switched off fades out within a second
		var p: WeatherProfile = allowedProfile(weather.kind)
		let raw: WeatherProfile = weather.kind.profile
		if let h = weather.hurricane {
			p.wind *= h.force
			p.precip *= clampD(h.force * 1.2, 0.2, 1.0)
			p.cloud = 0.55 + 0.45 * min(1.0, h.force * 1.6)
			p.thunder *= h.force
		}
		func tau(_ target: Double, _ rv: Double, _ normal: Double) -> Double {
			return (target <= 0.0001 && rv > 0.0001) ? 0.8 : normal
		}
		weather.cloud = easeTo(weather.cloud, p.cloud, 20, dt)
		weather.precip = easeTo(weather.precip, p.precip, tau(p.precip, raw.precip, 14), dt)
		weather.thunder = easeTo(weather.thunder, p.thunder, tau(p.thunder, raw.thunder, 8), dt)
		weather.hail = easeTo(weather.hail, p.hail, tau(p.hail, raw.hail, 6), dt)
		weather.chill = easeTo(weather.chill, p.chill, 25, dt)
		weather.cover = easeTo(weather.cover, p.cover, 18, dt)
		weather.gust = easeTo(weather.gust, p.gust, 10, dt)
		// the wind eases through calm when it turns round, never flipping in a frame
		if let h = weather.hurricane {
			// onshore until the eye has passed, offshore after it
			weather.windDir = h.stage.rawValue <= HurricaneStage.eye.rawValue ? -h.side : h.side
		}
		let wt: Double = p.wind * weather.windDir
		weather.wind = easeTo(weather.wind, wt, tau(abs(wt), raw.wind, 9), dt)
		weather.drift += weather.wind * 0.55 * dt
		weather.cloudDrift += (weather.wind * 0.16 + (abs(weather.wind) < 0.05 ? CloudField.wind : 0)) * dt
	}

	// MARK: the weather at a place

	/// How much of the land at x a storm cell covers just now (0 a dry gap ... 1 under the storm).
	/// The cells are a noise field in world space that drifts with the wind.
	func coverAt(_ x: Double) -> Double {
		let c: Double = weather.cover
		if c >= 0.99 { return 1 }
		if c <= 0.001 { return 0 }
		let n: Double = fbm1((x - weather.drift) / 170.0, gen.seed &+ 0x57A2, 2)
		let thr: Double = 1.0 - c - 0.11
		return smooth(clampD((n - thr) / 0.22, 0, 1))
	}

	/// The wind's gusting right now (the same everywhere; it rises and falls over a few seconds)
	func gustNow() -> Double {
		let g: Double = weather.gust
		if g <= 0.001 { return 1 }
		let n: Double = fbm1(weather.t * 0.23, gen.seed &+ 0x6057, 3)
		return clampD(1.0 + (n - 0.5) * 2.0 * g, 0.35, 1.6)
	}

	/// How cold it is: the land, the height, the night and the weather (snow falls from 0.5)
	func chillAt(_ y: Double, _ col: Col) -> Double {
		var c: Double
		switch col.biome {
		case .tundra: c = 0.75
		case .mountain: c = col.h < 84 ? 0.62 : 0.3
		case .desert, .savanna, .jungle: c = 0.0
		case .ocean: c = 0.2
		default: c = 0.18
		}
		if y < 76 { c += (76.0 - y) / 50.0 }
		let hot: Bool = col.biome == .desert || col.biome == .savanna || col.biome == .jungle
		if isNight && !hot { c += 0.12 }
		c += weather.chill * 0.4 + weather.precip * 0.05
		return clampD(c, 0, 1.2)
	}

	/// The weather at a place. Only reads the simulation and the world's (deterministic) biomes, so a
	/// place has the same weather whichever chunks are loaded.
	func weatherAt(_ x: Double, _ y: Double) -> LocalWeather {
		var L = LocalWeather()
		if let d = customDim, settings.weatherOn { return customWeather(d, x, y) }
		if world.dim != .overworld || !settings.weatherOn { return L }
		let ix: Int = Int(floor(x))
		let col: Col = gen.col(ix)
		let cov: Double = coverAt(x)
		// blended from one column to the next, so rain changes gradually over a biome border
		let wa: Double = landWetness(ix)
		let wetF: Double = wa + (landWetness(ix + 1) - wa) * (x - Double(ix))
		L.chill = chillAt(y, col)
		L.snow = L.chill >= 0.5
		L.hot = col.biome == .desert || col.biome == .savanna || col.biome == .jungle
		L.precip = clampD(weather.precip * cov * wetF, 0, 1)
		L.cloud = weather.cloud * (0.6 + 0.4 * cov)
		L.thunder = weather.thunder * cov
		// up in the cold, hail falls as snow
		L.hail = L.snow ? 0 : weather.hail * cov
		L.wind = weather.wind * gustNow()
		if let e = weather.tornado {
			let d: Double = abs(x - e.x)
			L.tornado = e.funnel * clampD(1.0 - (d - 4.0) / 40.0, 0, 1)
			L.cloud = max(L.cloud, min(1.0, 0.25 + e.funnel * clampD(1.0 - d / 120.0, 0, 1)))
		}
		if let h = weather.hurricane {
			let f: Double = hurricaneReach(x, h)
			L.hurricane = h.force * f
			L.wind *= 0.3 + 0.7 * f
			L.precip *= 0.5 + 0.5 * f
		}
		let blow: Double = clampD(abs(L.wind) / 14.0, 0, 1)
		L.fog = L.snow ? L.precip * (0.25 + 0.6 * blow) : L.precip * 0.3
		L.wet = groundValue(x, false)
		L.snowCover = groundValue(x, true)
		return L
	}

	/// How readily rain falls at column x: its biome's wetness, with the land 14 columns either side
	func landWetness(_ x: Int) -> Double {
		let w0: Double = biomeWetness(gen.col(x - 14).biome)
		let w1: Double = biomeWetness(gen.col(x).biome)
		let w2: Double = biomeWetness(gen.col(x + 14).biome)
		return (w0 + w1 * 2.0 + w2) * 0.25
	}

	/// How hard a hurricane is felt at x: fully over the sea and at the coast, fading inland
	func hurricaneReach(_ x: Double, _ h: HurricaneEvent) -> Double {
		let inland: Double = (h.coastX - x) * h.side
		return clampD(1.0 - (inland - 40.0) / 300.0, 0.25, 1.0)
	}

	/// Wet ground or lying snow at x (interpolated between the strips' centres)
	func groundValue(_ x: Double, _ snow: Bool) -> Double {
		let f: Double = x / groundCellW - 0.5
		let c0: Int = Int(floor(f))
		let u: Double = f - Double(c0)
		let a: GroundCell? = weather.cells[c0]
		let b: GroundCell? = weather.cells[c0 + 1]
		let va: Double = snow ? (a?.snow ?? 0) : (a?.wet ?? 0)
		let vb: Double = snow ? (b?.snow ?? 0) : (b?.wet ?? 0)
		return va + (vb - va) * u
	}

	/// Rain soaks the ground and snow lies on it, strip by strip around the player; strips the player
	/// has been away from catch up as if the weather had been fair meanwhile (cheap, and close enough)
	func updateGroundCells(_ dt: Double) {
		wxCellT += dt
		if wxCellT < 0.5 { return }
		let step: Double = wxCellT
		wxCellT = 0
		// the strips are the Overworld's ground: another dimension's weather never lies on them
		if !settings.weatherOn || world.dim != .overworld { return }
		let c0: Int = Int(floor(weatherX / groundCellW))
		for c in (c0 - 4)...(c0 + 4) {
			let cx: Double = (Double(c) + 0.5) * groundCellW
			var cell: GroundCell = weather.cells[c] ?? GroundCell(wet: 0, snow: 0, t: weather.t)
			let away: Double = max(0, weather.t - cell.t - step)
			let surf: Double = Double(gen.col(Int(cx)).h)
			let L: LocalWeather = weatherAt(cx, surf)
			if away > 0 {
				cell.wet *= exp(-away / 150.0)
				if L.chill < 0.5 { cell.snow *= exp(-away / 300.0) }
			}
			if L.precip > 0.03 && !L.snow {
				cell.wet = min(1.0, cell.wet + L.precip * step / 35.0)
			} else {
				let dryT: Double = L.hot ? 60 : (weather.cloud > 0.6 ? 220 : 110)
				cell.wet = max(0, cell.wet - step / dryT)
			}
			if L.snow && L.precip > 0.03 {
				cell.snow = min(1.0, cell.snow + L.precip * step / 50.0)
			} else if L.chill < 0.45 {
				let melt: Double = L.precip > 0.05 ? 50 : 140
				cell.snow = max(0, cell.snow - step / melt)
			}
			cell.t = weather.t
			weather.cells[c] = cell
		}
		if weather.cells.count > 40 {
			weather.cells = weather.cells.filter { abs($0.key - c0) <= 12 || $0.value.wet > 0.02 || $0.value.snow > 0.02 }
		}
	}

	// MARK: words for it: names, the forecast, pressure, alerts

	/// The name of a spell as it will actually be felt: with some kinds of weather switched off, a
	/// thunderstorm may be dry or a blizzard plain snow; up in the cold, rain is snow
	func weatherLabel(_ k: WeatherKind, snow: Bool) -> String {
		let s: Settings = settings
		if !s.weatherOn { return "No weather" }
		let p: WeatherProfile = allowedProfile(k)
		switch k {
		case .lightRain: return p.precip <= 0 ? "Overcast" : (snow ? "Light snow" : "Light rain")
		case .heavyRain: return p.precip <= 0 ? "Overcast" : (snow ? "Heavy snow" : "Heavy rain")
		case .snowfall: return p.precip <= 0 ? "Overcast" : (snow ? "Snowfall" : "Cold rain")
		case .thunderstorm:
			if p.thunder <= 0 { return p.precip > 0 ? (snow ? "Heavy snow" : "Heavy rain") : "Overcast" }
			return p.precip > 0 ? "Thunderstorm" : "Dry thunderstorm"
		case .hailstorm:
			if p.hail <= 0 { return p.thunder > 0 ? "Thunderstorm" : (p.precip > 0 ? "Heavy rain" : "Overcast") }
			return weather.bigHail && k == weather.kind ? "Large hail" : "Hailstorm"
		case .strongWind: return p.wind <= 0.01 ? "Partly cloudy" : "Strong wind"
		case .windstorm: return p.wind <= 0.01 ? "Overcast" : "Windstorm"
		case .blizzard: return s.allowBlizzard ? (snow ? "Blizzard" : "Gale and cold rain") : weatherLabel(.snowfall, snow: snow)
		case .tornado: return s.allowTornado ? "Tornado" : weatherLabel(.thunderstorm, snow: snow)
		case .hurricane: return s.allowHurricane ? "Hurricane" : weatherLabel(.windstorm, snow: snow)
		default: return k.name
		}
	}

	/// What the weather is doing where the player is, in a few words
	var weatherHereLabel: String {
		if world.dim != .overworld { return "" }
		if !settings.weatherOn { return "" }
		let L: LocalWeather = wxHere
		var name: String = weatherLabel(weather.kind, snow: L.snow)
		// a storm cell that has not reached here yet (or has passed) shows as such
		let p: WeatherProfile = allowedProfile(weather.kind)
		if p.precip > 0.2 && L.precip < 0.05 && weather.kind != .tornado && weather.kind != .hurricane { name = joinText(name, " nearby") }
		return name
	}

	/// The present spell, then the plan: what comes, when, and for how long
	func forecast() -> [ForecastLine] {
		var out: [ForecastLine] = []
		var t: Double = max(0, weather.stateDur - weather.stateT)
		if let h = weather.hurricane { t = max(t, h.timeLeft()) }
		out.append(ForecastLine(kind: weather.kind, startsIn: 0, dur: t))
		for s in weather.plan {
			out.append(ForecastLine(kind: s.kind, startsIn: t, dur: s.dur))
			t += s.dur
		}
		return out
	}

	/// Air pressure (hPa) from the simulation: low under storms, lowest near a hurricane's eye
	func pressureNow() -> Double {
		var p: Double = 1018.0 - 12.0 * weather.cloud - 9.0 * weather.precip - 0.8 * abs(weather.wind)
		if let h = weather.hurricane {
			let core: Double = h.stage == .eye ? 1.15 : h.force
			p -= 42.0 * core * h.strength * hurricaneReach(weatherX, h)
		}
		if let e = weather.tornado { p -= 8.0 * e.funnel }
		return p
	}

	/// The pressure the next spell will settle at (for the barometer's trend)
	func pressureNext() -> Double {
		let k: WeatherKind = weather.plan.first?.kind ?? weather.kind
		let p: WeatherProfile = allowedProfile(k)
		var v: Double = 1018.0 - 12.0 * p.cloud - 9.0 * p.precip - 0.8 * p.wind
		if k == .hurricane && settings.allowHurricane { v -= 40 }
		if k == .tornado && settings.allowTornado { v -= 8 }
		return v
	}

	/// A line in the message box when the weather turns (only for changes worth knowing about)
	func announceWeather(_ prev: WeatherKind, _ k: WeatherKind) {
		if !settings.weatherAlerts || world.dim != .overworld { return }
		let p: WeatherProfile = allowedProfile(k)
		let snow: Bool = wxHere.snow
		var line: String = ""
		switch k {
		case .lightRain:
			if prev != .heavyRain && p.precip > 0 { line = snow ? "Snow is beginning to fall." : "It's starting to rain." }
		case .heavyRain:
			if prev == .lightRain && p.precip > 0 { line = snow ? "The snow is getting heavier." : "The rain is getting heavier." }
		case .thunderstorm:
			if p.thunder > 0 { line = "A thunderstorm is rolling in. Lightning finds high, open ground." }
		case .strongWind:
			if (prev == .clear || prev == .partlyCloudy) && p.wind > 0 { line = "The wind is picking up." }
		case .windstorm:
			if p.wind > 0 { line = "Windstorm! Strong gusts will push you around." }
		case .hailstorm:
			if p.hail > 0 { line = weather.bigHail ? "Large hail! Get under a roof." : "Hail is falling." }
		case .snowfall:
			if p.precip > 0 && prev != .blizzard { line = snow ? "Snow is falling." : "A cold rain is falling." }
		case .blizzard:
			if settings.allowBlizzard { line = "A blizzard is blowing in. Find shelter and warmth." }
		case .clear, .partlyCloudy:
			if prev.severe || prev == .heavyRain { line = "The weather is clearing." }
		default:
			break
		}
		if !line.isEmpty {
			say(line, 3.5)
			if k.severe { sfx(.weatherAlert, 0.6) }
		}
	}

	/// The warning strip under the top bar while something dangerous is going on
	func updateWeatherBanner() {
		var text: String = ""
		var level: Int = 0
		let on: Bool = settings.weatherOn && world.dim == .overworld
		if on, let e = weather.tornado {
			let d: Double = e.x - pb.x
			let side: String = d > 0 ? "east" : "west"
			let dist: String = String(Int(abs(d).rounded()))
			switch e.phase {
			case 0:
				let left: Int = Int(max(0, e.warnDur - e.t).rounded())
				text = joinText("TORNADO WARNING · forming ", dist, " blocks ", side, " · take shelter (", String(left), " s)")
				level = 2
			case 1:
				text = joinText("TORNADO ON THE GROUND · ", dist, " blocks ", side, " · moving ", e.dir > 0 ? "east" : "west")
				level = 2
			default:
				text = "The tornado is lifting"
				level = 1
			}
		} else if on, let h = weather.hurricane {
			text = joinText("HURRICANE · ", h.stage.name)
			level = (h.stage == .approaching || h.stage == .clearing || h.stage == .eye) ? 1 : 2
		} else if on && strikeMark != nil {
			text = "LIGHTNING IS ABOUT TO STRIKE NEAR YOU · move or take cover"
			level = 2
		} else if on && weather.kind == .blizzard && settings.allowBlizzard && wxHere.snow {
			text = "BLIZZARD · stay sheltered and keep warm"
			level = 1
		} else if on && weather.kind == .hailstorm && weather.bigHail && wxHere.hail > 0.1 {
			text = "LARGE HAIL · get under a roof"
			level = 1
		} else if on && weather.kind == .thunderstorm && wxHere.thunder > 0.5 {
			text = "Thunderstorm · keep off high, open ground"
			level = 1
		} else if bodyCold > 0.45 && on {
			text = "Freezing · find a fire, shelter or warm clothes"
			level = 1
		}
		if !settings.weatherAlerts {
			text = ""
			level = 0
		}
		wxBanner = text
		wxBannerLevel = level
	}
}

// MARK: - Weather in the world: lightning, hail, cold, the wind's push, tornadoes and hurricanes

/// How readily wind tears a block loose (0: never). The ground itself, stone and anything built to
/// stand up to storms never goes; plants, leaves and light building blocks go first.
func windBreak(_ t: Tile) -> Double {
	if isLeafTile(t) { return 0.85 }
	if isLogTile(t) { return 0.18 }
	switch t {
	case .tallGrass, .flowerR, .flowerY, .deadBush, .reed, .mushroom: return 0.9
	case .wheat1, .wheat2, .wheat3, .carrot1, .carrot2, .carrot3: return 0.55
	case .torch, .cobweb: return 0.8
	case .hay: return 0.6
	case .glass: return 0.5
	case .cactus: return 0.3
	case .platform, .ladder: return 0.45
	case .planks: return 0.3
	case .doorClosed, .doorOpen: return 0.25
	case .logBlock, .jungleLogBlock, .palmLogBlock, .birchLogBlock: return 0.15
	case .workbench, .lantern, .crate: return 0.2
	case .crackedBrick: return 0.08
	case .brick, .mossBrick, .amethystBlock: return 0.02
	default: return 0
	}
}

/// Things lightning can set alight
func isFlammable(_ t: Tile) -> Bool {
	if isLeafTile(t) || isLogTile(t) { return true }
	switch t {
	case .tallGrass, .flowerR, .flowerY, .deadBush, .reed, .hay, .planks, .platform, .ladder, .dryGrass, .logBlock, .jungleLogBlock, .palmLogBlock, .birchLogBlock, .workbench, .crate, .cactus:
		return true
	default:
		return false
	}
}

/// How much a shot of each kind is carried by the wind (heavy and fast shots hardly at all)
func windCatch(_ k: ProjKind) -> Double {
	switch k {
	case .arrow: return 0.22
	case .quarrel, .bolt: return 0.15
	case .pebble, .spit: return 0.25
	case .bomb, .flask: return 0.3
	case .fireball: return 0.12
	case .rock, .shard: return 0.08
	case .pellet, .shell: return 0.05
	case .bullet, .shock: return 0
	}
}

/// Light creatures the wind carries along
func isWindBlown(_ k: MobKind) -> Bool {
	switch k {
	case .crow, .bat, .chicken: return true
	default: return false
	}
}

extension Game {
	/// How much of the open weather reaches someone at a given level of shelter
	func shelterExposure(_ level: Int) -> Double {
		switch level {
		case 0: return 1.0
		case 1: return 0.55
		default: return 0
		}
	}

	/// True when rain falls on the head of a body standing at (x, feet y) with the given height
	func rainReaches(_ x: Double, _ feetY: Double, _ h: Double) -> Bool {
		if world.dim != .overworld { return false }
		let tx: Int = Int(floor(x))
		return Int(floor(feetY - h)) < world.rainTop(tx)
	}

	/// 0 out in the open, 1 under a roof, 2 indoors (a roof and walls on both sides), 3 underground or
	/// in a reinforced storm shelter
	func shelterAt(_ x: Double, _ feetY: Double) -> Int {
		if world.dim != .overworld { return 3 }
		let tx: Int = Int(floor(x))
		let head: Int = Int(floor(feetY - 1.6))
		if head < world.rainTop(tx) { return 0 }
		var reinforced: Bool = false
		// count the solid cover overhead (four blocks or more is underground)
		var solidAbove: Int = 0
		var y: Int = head - 1
		var n: Int = 0
		while n < 24 && y > 0 {
			let t: Tile = world.tile(tx, y)
			if t.solid {
				solidAbove += 1
				if isStormproof(t) { reinforced = true }
			}
			y -= 1
			n += 1
		}
		if solidAbove >= 4 && !reinforced { return 3 }
		// walls on both sides, at head or body height
		func wall(_ dir: Int) -> Bool {
			var k: Int = 1
			while k <= 8 {
				let a: Tile = world.tile(tx + dir * k, head)
				let b: Tile = world.tile(tx + dir * k, head + 1)
				if a.solid || b.solid {
					if isStormproof(a) || isStormproof(b) { reinforced = true }
					return true
				}
				k += 1
			}
			return false
		}
		let left: Bool = wall(-1)
		let right: Bool = wall(1)
		if left && right { return reinforced ? 3 : 2 }
		return 1
	}

	// MARK: lightning

	func updateLightning(_ dt: Double) {
		if !bolts.isEmpty {
			for i in 0..<bolts.count { bolts[i].life -= dt }
			bolts.removeAll { $0.life <= 0 }
		}
		if skyFlash > 0 { skyFlash = max(0, skyFlash - dt * (settings.reduceFlashes ? 0.9 : 2.6)) }
		if playerStrikeCD > 0 { playerStrikeCD -= dt }
		if !thunderQueue.isEmpty {
			for i in 0..<thunderQueue.count { thunderQueue[i].t -= dt }
			for q in thunderQueue where q.t <= 0 { Sound.shared.play(q.near ? .thunderNear : .thunderFar, q.vol) }
			thunderQueue.removeAll { $0.t <= 0 }
		}
		let on: Bool = settings.weatherOn && settings.allowThunder && world.dim == .overworld
		if var m = strikeMark {
			if !on {
				strikeMark = nil
			} else {
				m.t -= dt
				if m.t <= 0 {
					strikeMark = nil
					lightningStrike(m.x, m.y, rod: false)
				} else {
					strikeMark = m
					if frameNo % 6 == 0 { spawnParticles(m.x + Double.random(in: -0.6...0.6), m.y - 0.3, 0xCFE4FF, 1, 2.0, 0.3, -4) }
				}
			}
		}
		if !on || weather.thunder < 0.01 {
			strikeAcc = 0
			return
		}
		strikeAcc += dt * weather.thunder / 60.0
		if strikeAcc >= 1.0 {
			strikeAcc = weather.fxPick(-0.4...0.2)
			pickStrike()
		}
	}

	/// Where the next bolt goes. Most land away from the player and some only light up the clouds;
	/// one landing near the player is marked first, and the next one near them waits a good while
	/// (lightning never singles a player out).
	func pickStrike() {
		let px: Double = pb.x
		var x: Double = px + weather.fxPick(-75...75)
		if coverAt(x) < 0.3 || weather.fx() < 0.3 {
			cloudFlash(x)
			return
		}
		if abs(x - px) < 12 && playerStrikeCD > 0 {
			x = px + (x >= px ? 1.0 : -1.0) * weather.fxPick(16...40)
		}
		guard let spot = strikeSpot(x) else {
			cloudFlash(x)
			return
		}
		if spot.2 {
			lightningStrike(spot.0, spot.1, rod: true)
			return
		}
		if abs(spot.0 - px) < 12 {
			// where it actually comes down decides: near the player again so soon, it stays in the cloud
			if playerStrikeCD > 0 {
				cloudFlash(spot.0)
				return
			}
			playerStrikeCD = 45
			strikeMark = StrikeMark(x: spot.0, y: spot.1, t: 1.5, total: 1.5)
			sfx(.strikeWarn, 0.8)
			return
		}
		lightningStrike(spot.0, spot.1, rod: false)
	}

	/// Lightning that stays in the cloud: a soft flicker and far-off thunder
	func cloudFlash(_ x: Double) {
		let d: Double = abs(x - pb.x)
		let k: Double = clampD(1.0 - d / 160.0, 0.2, 1.0)
		skyFlash = max(skyFlash, (settings.reduceFlashes ? 0.05 : 0.2) * k)
		thunderQueue.append(PendingThunder(t: 0.6 + d / 45.0, vol: 0.35 * k, near: false))
	}

	/// Where a bolt aimed at x comes down: a lightning rod in reach takes it, otherwise the highest
	/// exposed point close by (a tree top, a roof, a hill). Returns (x, top y, taken by a rod).
	func strikeSpot(_ x: Double) -> (Double, Double, Bool)? {
		if let r = rodCovering(x) { return (Double(r.x) + 0.5, Double(r.y), true) }
		var best: Int = Int.max
		let x0: Int = Int(floor(x))
		var bx: Int = x0
		for k in -3...3 {
			let cx: Int = x0 + k
			if !world.isLoaded(cx) { continue }
			let top: Int = world.rainTop(cx)
			if top < best {
				best = top
				bx = cx
			}
		}
		if best == Int.max || best >= world.H - 2 { return nil }
		// the highest point may lie within a rod's reach even if the aim did not
		if let r = rodCovering(Double(bx) + 0.5) { return (Double(r.x) + 0.5, Double(r.y), true) }
		return (Double(bx) + 0.5, Double(best), false)
	}

	func lightningStrike(_ x: Double, _ y: Double, rod: Bool) {
		let soft: Bool = settings.reduceFlashes
		makeBolt(x, y)
		stormEssenceAt(x, y, rod: rod)
		skyFlash = max(skyFlash, soft ? 0.12 : 0.55)
		addLightFlash(x, y - 0.5, peak: soft ? 11 : 15, dur: soft ? 0.7 : 0.35, radius: 1.4, color: 0xC8DCFF)
		// thunder: at once up close, later the further off it was (light is quick, sound is slow)
		let d: Double = abs(x - pb.x) + abs(y - pb.y) * 0.3
		let vol: Double = clampD(1.15 - d / 140.0, 0.12, 1.0)
		if d < 14 {
			Sound.shared.play(.thunderNear, vol)
		} else {
			thunderQueue.append(PendingThunder(t: d / 45.0, vol: vol, near: d < 40))
		}
		spawnParticles(x, y - 0.2, 0xE8F0FF, 8, 6.0, 0.35, 10)
		if d < 24 { addShake(0.35) }
		if rod {
			// the rod carries it safely into the ground
			spawnParticles(x, y + 0.2, 0xFFE8A0, 10, 4.0, 0.4, 14)
			return
		}
		let I: Double = weatherIntensity
		if settings.weatherHurtsPlayer && !dead && abs(pb.x - x) < 1.8 && pb.y > y - 0.5 && pb.top < y + 0.6 {
			var info = DamageInfo(amount: 7.0 * I, type: .shock, source: .environment)
			info.originX = x
			info.knock = 7
			info.key = newID()
			if hurtPlayer(info) && settings.weatherAlerts { say("Struck by lightning!", 1.5) }
		}
		if settings.weatherHurtsCreatures {
			for m in mobsNear(x - 3, x + 3) where m.hp > 0 && !m.removed {
				if abs(m.b.x - x) < 2.0 && m.b.y > y - 0.5 && m.b.top < y + 0.6 {
					var info = DamageInfo(amount: 12.0 * I, type: .shock, source: .environment)
					info.originX = x
					info.knock = 5
					info.key = newID()
					applyMobDamage(m, info)
				}
			}
		}
		if settings.weatherHurtsBlocks { lightningFire(Int(floor(x)), Int(floor(y))) }
	}

	/// A jagged bolt from the cloud base down to the strike, with a few forks
	func makeBolt(_ x: Double, _ y: Double) {
		let top: Double = min(y - 24.0, camY - viewTilesH * 0.5 - 3.0)
		var pts: [(Double, Double)] = []
		var cx: Double = x + weather.fxPick(-4...4)
		let n: Int = max(6, Int((y - top) / 1.6))
		for i in 0...n {
			let f: Double = Double(i) / Double(n)
			let cy: Double = top + (y - top) * f
			cx += weather.fxPick(-0.9...0.9)
			cx += (x - cx) * f * 0.35
			if i == n { cx = x }
			pts.append((cx, cy))
		}
		var forks: [[(Double, Double)]] = []
		let nf: Int = 1 + Int(weather.fx() * 3.0)
		for _ in 0..<nf {
			let k: Int = clampI(Int(weather.fxPick(0.15...0.6) * Double(n)), 1, n - 1)
			var fx: Double = pts[k].0
			var fy: Double = pts[k].1
			let side: Double = weather.fx() < 0.5 ? -1.0 : 1.0
			var f: [(Double, Double)] = [(fx, fy)]
			let len: Int = 3 + Int(weather.fx() * 4.0)
			for _ in 0..<len {
				fx += side * weather.fxPick(0.4...1.3)
				fy += weather.fxPick(0.8...1.6)
				f.append((fx, fy))
			}
			forks.append(f)
		}
		if bolts.count >= 4 { bolts.removeFirst() }
		bolts.append(LightningBolt(pts: pts, forks: forks, life: 0.32, maxLife: 0.32))
	}

	/// A strike on something that burns: leaves and plants go up, and a short fire burns where it hit
	/// (it dies sooner in the rain)
	func lightningFire(_ tx: Int, _ ty: Int) {
		let t: Tile = world.tile(tx, ty)
		if !isFlammable(t) { return }
		if isLeafTile(t) || t.isPlant || t == .hay { breakTile(tx, ty, false, dropChance: 0.3) }
		let rain: Double = weatherAt(Double(tx) + 0.5, Double(ty)).precip
		let ground: Int = world.groundBelow(tx, ty)
		if fireZones.count >= 6 { fireZones.removeFirst() }
		var z = FireZone(x: Double(tx) + 0.5, y: Double(ground), r: 1.6, t: max(1.5, 6.0 - 4.5 * rain), uid: newID())
		z.tick = 0.35
		z.env = true
		fireZones.append(z)
		spawnParticles(Double(tx) + 0.5, Double(ty), 0xFF8030, 10, 4.0, 0.6, -3)
	}

	// MARK: hail

	func updateHail(_ dt: Double) {
		let on: Bool = settings.weatherOn && settings.allowHail && world.dim == .overworld
		let h: Double = on ? wxHere.hail : 0
		if hailPool.isEmpty { hailPool = [HailStone](repeating: HailStone(), count: 56) }
		let density: Double = clampD(settings.weatherParticles, 0.2, 1.0)
		if h > 0.02 {
			hailAcc += dt * h * 70.0 * density
			let halfW: Double = viewTilesW * 0.5 + 3.0
			let topY: Double = camY - viewTilesH * 0.5 - 1.0
			while hailAcc >= 1.0 {
				hailAcc -= 1.0
				guard let i = hailPool.firstIndex(where: { !$0.on }) else {
					hailAcc = 0
					break
				}
				var s = HailStone()
				s.on = true
				s.x = camX + Double.random(in: -halfW...halfW)
				s.y = topY - Double.random(in: 0...3)
				s.vy = Double.random(in: 18...24)
				s.vx = wxHere.wind * 0.25
				s.size = weather.bigHail ? Double.random(in: 0.18...0.26) : Double.random(in: 0.09...0.14)
				hailPool[i] = s
			}
		} else {
			hailAcc = 0
		}
		let bottom: Double = camY + viewTilesH * 0.5 + 2.0
		for i in 0..<hailPool.count where hailPool[i].on {
			var s: HailStone = hailPool[i]
			s.vy = min(s.vy + 30.0 * dt, 26)
			s.vx += (wxHere.wind * 0.25 - s.vx) * min(1.0, dt * 2.0)
			s.x += s.vx * dt
			s.y += s.vy * dt
			let tx: Int = Int(floor(s.x))
			let ty: Int = Int(floor(s.y))
			if s.vy > 0 && ty >= world.rainTop(tx) && Tile.rainStopTable[world.tile(tx, ty).idx] {
				if s.bounces == 0 {
					// a bounce off whatever it hit, then it breaks
					s.y = Double(ty) - 0.02
					s.vy = -s.vy * 0.32
					s.vx += Double.random(in: -2.5...2.5)
					s.bounces = 1
					if abs(s.x - pb.x) < 6 && frameNo % 3 == 0 { sfx(.hailTick, 0.25) }
				} else {
					s.on = false
					if particles.count < 120 && abs(s.x - pb.x) < 20 { spawnParticles(s.x, s.y, 0xE8F4FF, 2, 2.0, 0.25, 22) }
				}
			}
			if s.y > bottom { s.on = false }
			hailPool[i] = s
		}
		if h < 0.05 { return }
		// what hail does: large stones sting whoever is out in it; crops, flowers and glass suffer
		hailHitT -= dt
		if hailHitT > 0 { return }
		hailHitT = weather.bigHail ? 1.6 : 2.4
		let I: Double = weatherIntensity
		if weather.bigHail && h > 0.3 {
			if settings.weatherHurtsPlayer && !dead && rainReaches(pb.x, pb.y, pb.h) {
				// a helmet turns most of the stones
				let helmet: Bool = inv.armor[0] != nil || suitHelmet
				if !helmet || Double.random(in: 0...1) < 0.35 {
					var info = DamageInfo(amount: 1.0 * I * (1.0 - armorInf.stormCut) * (suitHas(.seal) ? 0.5 : 1.0), type: .impact, source: .environment)
					info.originX = pb.x
					info.key = newID()
					_ = hurtPlayer(info)
				}
			}
			if settings.weatherHurtsCreatures {
				for m in mobsNear(pb.x - 30, pb.x + 30) where m.hp > 0 && !m.removed && !m.isBoss && m.kind != .fish {
					if Double.random(in: 0...1) < 0.3 && rainReaches(m.b.x, m.b.y, m.b.h) {
						var info = DamageInfo(amount: 1.0 * I, type: .impact, source: .environment)
						info.originX = m.b.x
						info.key = newID()
						applyMobDamage(m, info)
					}
				}
			}
		}
		if settings.weatherHurtsBlocks { hailDamage(h) }
	}

	/// Hail beats down crops a stage, shreds flowers and (large hail) breaks glass left open to the
	/// sky. A roof over anything protects it, and only a few panes go in one storm.
	func hailDamage(_ h: Double) {
		for _ in 0..<3 {
			let tx: Int = Int(floor(pb.x)) + Int.random(in: -30...30)
			if !world.isLoaded(tx) { continue }
			let ty: Int = world.rainTop(tx)
			// the first thing the hail hits, or a crop or plant standing on it
			var y: Int = ty
			var t: Tile = world.tile(tx, y)
			let above: Tile = world.tile(tx, y - 1)
			if above.isPlant {
				y -= 1
				t = above
			}
			let r: Double = Double.random(in: 0...1)
			switch t {
			case .wheat3: if r < 0.4 * h { world.set(tx, y, .wheat2) }
			case .wheat2: if r < 0.3 * h { world.set(tx, y, .wheat1) }
			case .carrot3: if r < 0.4 * h { world.set(tx, y, .carrot2) }
			case .carrot2: if r < 0.3 * h { world.set(tx, y, .carrot1) }
			case .tallGrass, .flowerR, .flowerY:
				if r < 0.25 * h { breakTile(tx, y, false, dropChance: 0.5) }
			case .glass:
				if weather.bigHail && hailBroken < 6 && r < 0.15 * h {
					hailBroken += 1
					breakTile(tx, y, false, dropChance: 0)
					sfx(.breakCrystal, at: Double(tx), 0.6)
				}
			default:
				break
			}
		}
	}

	// MARK: cold

	/// Heat from fires, furnaces, lamps and heaters close by (0...1)
	func heatNear() -> Double {
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y - 1.0))
		var best: Double = 0
		for dy in -3...3 {
			for dx in -5...5 {
				let t: Tile = world.tile(px + dx, py + dy)
				var heat: Double = 0
				switch t {
				case .campfire, .heater: heat = 1.0
				case .furnace: heat = 0.7
				case .lantern: heat = 0.3
				case .torch: heat = 0.2
				case .lava: heat = 0.8
				default: break
				}
				if heat > 0 {
					let d: Double = sqrt(Double(dx * dx + dy * dy))
					best = max(best, heat * clampD(1.0 - d / 6.5, 0, 1))
				}
			}
		}
		return best
	}

	/// Cold country in bad weather draws the warmth out of a player who is out in it; shelter, heat
	/// and warm clothes keep it in. Far gone, the cold slows them and then starts to hurt (never to
	/// the death outside hardcore, like hunger).
	func updateCold(_ dt: Double) {
		warmthT -= dt
		if warmthT <= 0 {
			warmthT = 0.5
			warmthNear = heatNear()
			shelterLevel = shelterAt(pb.x, pb.y)
		}
		let L: LocalWeather = wxHere
		var loss: Double = 0
		if settings.weatherOn && world.dim == .overworld && mode != .creative && !dead {
			let cold: Double = clampD((L.chill - 0.5) * 2.0, 0, 1)
			if cold > 0 {
				loss = cold * (0.55 + 0.45 * clampD(abs(L.wind) / 12.0, 0, 1)) + L.precip * 0.15 * cold
				switch shelterLevel {
				case 1: loss *= 0.6
				case 2: loss *= 0.25
				case 3: loss *= 0.05
				default: break
				}
				if wearing(.winterCoat) { loss *= 0.35 }
				if wearing(.snowBoots) { loss *= 0.8 }
				if pb.inWater { loss += 0.6 * cold }
				loss *= coldGuard()
			}
		}
		let gain: Double = warmthNear * 0.12 + (loss <= 0.001 ? 0.05 : 0)
		// bare in a full blizzard a player freezes in about half a minute; a coat triples that
		bodyCold = clampD(bodyCold + (loss * 0.03 - gain) * dt, 0, 1)
		if !settings.weatherOn { bodyCold = max(0, bodyCold - dt * 0.2) }
		var slow: Double = 1.0 - 0.3 * clampD((bodyCold - 0.5) * 2.0, 0, 1)
		// deep snow drags at the feet (snow boots stay on top of it)
		if settings.weatherOn && pb.onGround && L.snowCover > 0.5 && shelterLevel == 0 && !wearing(.snowBoots) {
			slow *= 1.0 - 0.15 * clampD((L.snowCover - 0.5) * 2.0, 0, 1)
		}
		wxSlow = slow
		if bodyCold > 0.4 && !coldWarned {
			coldWarned = true
			if settings.weatherAlerts { say("You're getting cold. Get out of the wind, near a fire, or into warm clothes.", 3.5) }
		}
		if bodyCold < 0.2 { coldWarned = false }
		if bodyCold >= 0.97 && settings.weatherHurtsPlayer && settings.weatherOn {
			coldHurtT += dt
			if coldHurtT >= 4.0 {
				coldHurtT = 0
				if hp > 1 || mode == .hardcore {
					damagePlayer(1, from: pb.x, knock: 0, ignoreArmor: true)
					floatText("Freezing", pb.x, pb.y - pb.h - 0.6, 0xA8D8FF)
				}
			}
		} else {
			coldHurtT = 0
		}
	}

	// MARK: the wind's push

	/// The wind's (and a tornado's) hold on the player this frame: how it shifts walking, drifting in
	/// the air and standing still, how slippery the ground is, and a tornado's pull. Every part of it
	/// is bounded, and all of it is zero with the weather off.
	func updateWeatherForces(_ dt: Double) {
		wxWalk = 0
		wxAirDrift = 0
		wxRest = 0
		wxAccelX = 0
		wxAccelY = 0
		wxSlip = 0
		if flingT > 0 { flingT -= dt }
		if !settings.weatherOn || world.dim != .overworld || inVehicle != nil || mounted != nil || flying || noclip || dead { return }
		let expo: Double = shelterExposure(shelterLevel)
		// a breeze (under 3 blocks a second) moves nobody: calm weather leaves movement exactly as it was
		let raw: Double = wxHere.wind
		let w: Double = (raw > 0 ? 1.0 : -1.0) * max(0, abs(raw) - 3.0) * expo
		wxWalk = w * 0.1
		wxAirDrift = w * 0.3
		// a player standing still braces against the wind; only hurricane-force gusts shuffle them
		// along, slowly (at most 0.8 blocks a second), so nobody is blown across the map
		if abs(w) > 18.0 { wxRest = clampD((w - (w > 0 ? 18.0 : -18.0)) * 0.15, -0.8, 0.8) }
		if pb.onGround && expo > 0.5 {
			var slip: Double = clampD((wxHere.snowCover - 0.35) * 1.4, 0, 0.6)
			if wxHere.chill > 0.7 && wxHere.snowCover > 0.2 { slip = max(slip, 0.35) }
			if wxHere.precip > 0.4 && !wxHere.snow { slip = max(slip, 0.2 * wxHere.wet) }
			if wearing(.snowBoots) { slip *= 0.15 }
			wxSlip = slip
		}
		let tf: (Double, Double, Double) = tornadoField(pb.x, pb.y - pb.h * 0.5)
		if tf.2 > 0 {
			let k: Double = shelterLevel >= 3 ? 0 : (shelterLevel == 2 ? 0.3 : (shelterLevel == 1 ? 0.6 : 1.0))
			if k > 0 {
				wxAccelX = clampD((tf.0 - pb.vx) * 3.5, -40, 40) * k
				if tf.1 < -1.0 {
					let lift: Double = clampD(-tf.1 / 12.0, 0, 1)
					wxAccelY = (-gravityG * 1.05 * lift + clampD((tf.1 - pb.vy) * 2.5, -30, 30)) * k
					if wxAccelY < -8 { flingT = 2.5 }
				}
			}
		}
	}

	/// Light things in the open drift with the wind: shots in flight, items on the ground, small
	/// birds and bats
	func updateWindOnThings(_ dt: Double) {
		if !settings.weatherOn || world.dim != .overworld { return }
		let w: Double = wxHere.wind
		if abs(w) < 2.5 { return }
		for i in 0..<projectiles.count {
			let k: Double = windCatch(projectiles[i].kind)
			if k <= 0 || projectiles[i].stuck > 0 { continue }
			let px: Double = projectiles[i].x
			if projectiles[i].y >= Double(world.skyTop(Int(floor(px)))) { continue }
			projectiles[i].vx += w * k * dt
		}
		if abs(w) > 7.0 {
			for i in 0..<drops.count {
				let d: DropItem = drops[i]
				if d.y >= Double(world.skyTop(Int(floor(d.x)))) { continue }
				drops[i].vx = clampD(d.vx + (w * 0.45 - d.vx) * min(1.0, 0.8 * dt), -6, 6)
			}
		}
		for m in mobsNear(pb.x - 40, pb.x + 40) where isWindBlown(m.kind) && m.hp > 0 && !m.removed {
			if m.b.y >= Double(world.skyTop(Int(floor(m.b.x)))) { continue }
			m.b.vx = clampD(m.b.vx + w * 0.35 * dt, -9, 9)
		}
		// rough water tosses boats about
		let rough: Double = max(wxHere.hurricane, abs(w) > 9.0 ? (abs(w) - 9.0) / 10.0 : 0)
		if rough > 0.05 {
			for v in vehicles where v.isBoat && v.submerged > 0.05 && abs(v.px - pb.x) < 80 {
				v.asleep = false
				v.sleepT = 0
				let ph: Double = sin(weather.t * 1.7 + v.px * 0.3)
				v.vy = clampD(v.vy + ph * 10.0 * rough * dt, -6, 6)
				v.vx = clampD(v.vx + w * 0.15 * rough * dt, -10, 10)
				v.angVel = clampD(v.angVel + cos(weather.t * 1.3 + v.px * 0.2) * 1.4 * rough * dt, -1.5, 1.5)
			}
			// at a hurricane's height an open boat is swamped now and then
			if let v = inVehicle, v.isBoat, wxHere.hurricane > 0.7, settings.weatherHurtsPlayer {
				swampT += dt
				if swampT > 9.0 {
					swampT = 0
					if weather.fx() < 0.35 {
						dismount()
						pb.vy = -6
						sfx(.splash, 0.9)
						if settings.weatherAlerts { say("A wave swamps the boat and throws you into the sea!", 2.5) }
					}
				}
			} else {
				swampT = 0
			}
		}
	}

	// MARK: tornadoes

	func spawnTornado() {
		let dir: Double = weather.windDir
		let warn: Double = weather.pick(30...40)
		let ground: Double = max(30, weather.stateDur - warn - TornadoEvent.ropeDur)
		let dist: Double = weather.pick(85...110)
		let px: Double = weatherX
		let e = TornadoEvent(x: px - dir * dist, dir: dir, speed: weather.pick(2.6...3.4), warnDur: warn, groundDur: ground, strength: weather.pick(0.55...1.0), wander: weather.rand() * 6.283, uid: newID())
		weather.tornado = e
		tornadoAcc = 0
		if settings.weatherAlerts && world.dim == .overworld {
			say(joinText("Tornado warning! A funnel is forming to the ", dir > 0 ? "west" : "east", ". Get underground or into a shelter."), 4.5)
			sfx(.weatherAlert, 0.9)
		}
	}

	func endTornado(survived: Bool) {
		guard let e = weather.tornado else { return }
		weather.tornado = nil
		tornadoAcc = 0
		if weather.kind == .tornado { weather.stateT = max(weather.stateT, weather.stateDur) }
		if survived && e.closest < 120 {
			let d: Int = Int(e.closest.rounded())
			recordStorm(.tornado, e.closest < 30 ? joinText("passed within ", String(d), " blocks of you") : joinText("seen ", String(d), " blocks away"))
			if settings.weatherAlerts && world.dim == .overworld { say("The tornado has lifted. Look around for anything it scattered.", 3.5) }
		}
	}

	func updateTornado(_ dt: Double) {
		guard var e = weather.tornado else { return }
		e.t += dt
		switch e.phase {
		case 0:
			e.x += e.dir * 0.8 * dt
			if e.t >= e.warnDur {
				e.phase = 1
				e.t = 0
				if settings.weatherAlerts && world.dim == .overworld {
					say("A tornado has touched down!", 3.0)
					sfx(.weatherAlert, 0.9)
				}
			}
		case 1:
			e.x += (e.dir * e.speed + sin(e.wander + e.t * 0.35) * 1.3) * dt
			if e.t >= e.groundDur {
				e.phase = 2
				e.t = 0
			}
		default:
			e.x += e.dir * e.speed * 0.6 * dt
			if e.t >= TornadoEvent.ropeDur {
				weather.tornado = e
				endTornado(survived: true)
				return
			}
		}
		if world.dim == .overworld { e.closest = min(e.closest, abs(e.x - pb.x)) }
		weather.tornado = e
		// only near the player is it simulated in detail (beyond that it only moves)
		if world.dim == .overworld && abs(e.x - pb.x) < 100 && world.isLoaded(Int(floor(e.x))) {
			tornadoGround = Double(world.surfaceY(Int(floor(e.x))))
			tornadoEffects(dt)
		}
	}

	/// The air a tornado moves at a point: drawn in toward the funnel, lifted near it and swirled about
	/// it, strongest at the edge of its core and fading with distance; at the top of the funnel things
	/// are thrown outward. Returns (vx, vy, nearness 0...1). Speeds never exceed 16 blocks a second.
	func tornadoField(_ x: Double, _ y: Double) -> (Double, Double, Double) {
		guard let e = weather.tornado, world.dim == .overworld, settings.weatherOn else { return (0, 0, 0) }
		let f: Double = e.force * weatherIntensity
		if f <= 0.01 { return (0, 0, 0) }
		let dx: Double = x - e.x
		let ad: Double = abs(dx)
		let reach: Double = 24.0
		if ad > reach { return (0, 0, 0) }
		let core: Double = 3.2
		let height: Double = tornadoGround - y
		let near: Double = ad < core ? 1.0 : pow(max(0, (reach - ad) / (reach - core)), 1.6)
		let s: Double = dx >= 0 ? 1.0 : -1.0
		var vx: Double = -s * 9.0 * near * f
		if ad < core * 1.8 { vx += sin(weather.t * 4.2 + y * 0.7) * 7.0 * f }
		var vy: Double = 0
		if ad < core * 2.2 {
			let lift: Double = height < 18 ? 1.0 : max(0, 1.0 - (height - 18.0) / 6.0)
			vy = -12.0 * f * lift * (ad < core ? 1.0 : 0.6)
			if height >= 18 { vx = s * 10.0 * f }
		}
		let mag: Double = sqrt(vx * vx + vy * vy)
		if mag > 16.0 {
			vx *= 16.0 / mag
			vy *= 16.0 / mag
		}
		return (vx, vy, near)
	}

	/// What a tornado near the player does: it draws in and flings creatures, items, shots and
	/// vehicles, its debris hurts, and it tears loose plants, leaves and light building blocks (up to a
	/// limit; never the ground). Shelter keeps the player out of most of it.
	func tornadoEffects(_ dt: Double) {
		guard let e = weather.tornado else { return }
		let f: Double = e.force
		if f <= 0.01 { return }
		let I: Double = weatherIntensity
		for m in mobsNear(e.x - 24, e.x + 24) where m.hp > 0 && !m.removed && !m.isBoss && m.kind != .fish {
			let tf: (Double, Double, Double) = tornadoField(m.b.x, m.b.y - m.b.h * 0.5)
			if tf.2 <= 0 { continue }
			if !rainReaches(m.b.x, m.b.y, m.b.h) && shelterAt(m.b.x, m.b.y) >= 2 { continue }
			let light: Double = 1.0 / (1.0 + m.b.w * m.b.h * 0.6)
			m.b.vx = clampD(m.b.vx + clampD((tf.0 - m.b.vx) * 3.0, -40, 40) * light * dt, -16, 16)
			if tf.1 < -1.0 {
				m.b.vy = clampD(m.b.vy + (-gravityG * 1.05 + clampD((tf.1 - m.b.vy) * 2.5, -30, 30)) * light * dt, -14, 26)
				m.b.onGround = false
			}
			if !settings.weatherHurtsCreatures { m.fallPeak = 0 }
			if settings.weatherHurtsCreatures && abs(m.b.x - e.x) < 4.5 {
				var info = DamageInfo(amount: 2.0 * f * I, type: .impact, source: .environment)
				info.originX = e.x
				info.key = e.uid
				info.cooldown = 1.4
				applyMobDamage(m, info)
			}
		}
		for i in 0..<drops.count where abs(drops[i].x - e.x) < 24 {
			let tf: (Double, Double, Double) = tornadoField(drops[i].x, drops[i].y)
			if tf.2 <= 0 { continue }
			drops[i].vx = clampD(drops[i].vx + (tf.0 - drops[i].vx) * 2.0 * dt, -14, 14)
			if tf.1 < -1.0 { drops[i].vy = clampD(drops[i].vy + (tf.1 - drops[i].vy) * 2.5 * dt - gravityG * 0.8 * dt, -12, 18) }
		}
		for i in 0..<projectiles.count where abs(projectiles[i].x - e.x) < 24 && projectiles[i].stuck <= 0 {
			let tf: (Double, Double, Double) = tornadoField(projectiles[i].x, projectiles[i].y)
			projectiles[i].vx += tf.0 * 0.6 * dt
			projectiles[i].vy += tf.1 * 0.6 * dt
		}
		for v in vehicles where abs(v.px - e.x) < 24 {
			let tf: (Double, Double, Double) = tornadoField(v.px, v.py)
			if tf.2 <= 0 { continue }
			let heavy: Double = 1.0 / max(1.0, v.mass * 0.15)
			v.asleep = false
			v.sleepT = 0
			v.vx = clampD(v.vx + clampD((tf.0 - v.vx) * 0.8, -12, 12) * heavy * dt, -12, 12)
			v.angVel = clampD(v.angVel + tf.0 * 0.05 * heavy * dt, -2, 2)
		}
		// its debris
		if settings.weatherHurtsPlayer && !dead && abs(pb.x - e.x) < 4.5 && shelterLevel < 2 {
			wxDebrisT -= dt
			if wxDebrisT <= 0 {
				wxDebrisT = 1.4
				var info = DamageInfo(amount: 2.0 * f * I, type: .impact, source: .environment)
				info.originX = e.x
				info.knock = 3
				info.key = newID()
				_ = hurtPlayer(info)
			}
		}
		// the dust and wreckage thrown up at its foot
		if particles.count < 140 && abs(e.x - pb.x) < 50 && frameNo % 2 == 0 {
			let col: UInt32 = [0x8A7A60, 0x6A5A44, 0x5E8A4A, 0x9A8A70][frameNo % 4]
			spawnParticles(e.x + Double.random(in: -3...3), tornadoGround - 0.3, col, 2, 7.0, 0.8, 8)
		}
		if settings.weatherHurtsBlocks && e.broken < 90 {
			tornadoAcc += dt * 7.0 * f * I
			var broken: Int = e.broken
			while tornadoAcc >= 1.0 && broken < 90 {
				tornadoAcc -= 1.0
				let hit: Bool = weather.fx() < 0.7 ? tearAt(e.x + weather.fxPick(-4.8...4.8), f) : tearFace(e.x, e.dir, f)
				if hit { broken += 1 }
			}
			weather.tornado?.broken = broken
		} else {
			tornadoAcc = 0
		}
	}

	/// Tears one block loose at column x, working down from the first thing the wind reaches (plants
	/// and leaves give way; a solid roof or the ground stops it)
	@discardableResult
	func tearAt(_ x: Double, _ f: Double) -> Bool {
		let tx: Int = Int(floor(x))
		if !world.isLoaded(tx) { return false }
		var y: Int = max(1, world.rainTop(tx) - 1)
		var n: Int = 0
		while n < 4 {
			let t: Tile = world.tile(tx, y)
			if t == .air {
				y += 1
				n += 1
				continue
			}
			if weather.fx() < windBreak(t) * f {
				let c: UInt32 = t.def.colors.first ?? 0x8A7A60
				stormTear(tx, y, weather.wind >= 0 ? 1.0 : -1.0)
				spawnParticles(Double(tx) + 0.5, Double(y) + 0.5, c, 4, 7.0, 0.7, 6)
				return true
			}
			if t.solid { return false }
			y += 1
			n += 1
		}
		return false
	}

	/// Tears loose the first block the wind meets coming from `fromDir` at a random height near the
	/// surface around x: walls take the wind side-on (a closed storm shutter or a stone wall in front
	/// of a window keeps the glass whole)
	@discardableResult
	func tearFace(_ x: Double, _ fromDir: Double, _ f: Double) -> Bool {
		let cx: Int = Int(floor(x + weather.fxPick(-6...6)))
		if !world.isLoaded(cx) { return false }
		let ground: Int = world.surfaceY(cx)
		let y: Int = ground - 1 - Int(weather.fx() * 7.0)
		let step: Int = fromDir > 0 ? 1 : -1
		var tx: Int = cx - step * 12
		var k: Int = 0
		while k < 24 {
			let t: Tile = world.tile(tx, y)
			if t != .air && !t.liquid {
				if weather.fx() < windBreak(t) * f {
					stormTear(tx, y, fromDir)
					return true
				}
				return false
			}
			tx += step
			k += 1
		}
		return false
	}

	// MARK: hurricanes

	func spawnHurricane(_ ctx: WeatherContext) {
		let side: Double = ctx.seaSide != 0 ? ctx.seaSide : 1
		let h = HurricaneEvent(total: weather.stateDur, side: side, coastX: ctx.coastX, strength: weather.pick(0.7...1.0))
		weather.hurricane = h
		hurricaneAcc = 0
		if settings.weatherAlerts && world.dim == .overworld {
			say(joinText("Hurricane warning: a hurricane is coming in off the sea to the ", side > 0 ? "east" : "west", ". Close your shutters, then get to high ground or a shelter."), 5.0)
			sfx(.weatherAlert, 0.9)
		}
	}

	func endHurricane(survived: Bool) {
		guard let h = weather.hurricane else { return }
		weather.hurricane = nil
		hurricaneAcc = 0
		if weather.kind == .hurricane { weather.stateT = max(weather.stateT, weather.stateDur) }
		if survived && h.closest < 400 {
			recordStorm(.hurricane, h.closest < 80 ? "rode it out on the coast" : "felt it inland")
		}
	}

	func updateHurricane(_ dt: Double) {
		guard var h = weather.hurricane else { return }
		h.t += dt
		if h.t >= h.stageDur {
			h.t = 0
			if h.stage == .clearing {
				weather.hurricane = h
				endHurricane(survived: true)
				if settings.weatherAlerts && world.dim == .overworld { say("The hurricane has passed. The sea is going back down.", 3.5) }
				return
			}
			h.stage = HurricaneStage(rawValue: h.stage.rawValue + 1) ?? .clearing
			if settings.weatherAlerts && world.dim == .overworld {
				var line: String = ""
				switch h.stage {
				case .intensifying: line = "The hurricane is strengthening. The sea is rising."
				case .peak: line = "The hurricane is at its height!"
				case .eye: line = "The eye of the hurricane: a sudden calm. The far wall is coming, and the wind will turn."
				case .backside: line = "The wind is back, from the other side!"
				case .weakening: line = "The hurricane is weakening."
				case .clearing: line = "The hurricane is moving on."
				default: break
				}
				if !line.isEmpty { say(line, 3.5) }
			}
		}
		h.force = easeTo(h.force, h.stage.force * h.strength, 8, dt)
		if world.dim == .overworld { h.closest = min(h.closest, abs(pb.x - h.coastX)) }
		weather.hurricane = h
		if world.dim != .overworld { return }
		let reach: Double = hurricaneReach(pb.x, h)
		if settings.weatherHurtsBlocks && h.broken < 60 && h.force > 0.6 && reach > 0.4 {
			hurricaneAcc += dt * 1.2 * h.force * reach * weatherIntensity
			var broken: Int = h.broken
			while hurricaneAcc >= 1.0 && broken < 60 {
				hurricaneAcc -= 1.0
				let x: Double = pb.x + weather.fxPick(-40...40)
				let fromDir: Double = weather.wind >= 0 ? 1 : -1
				let hit: Bool = weather.fx() < 0.5 ? tearAt(x, h.force * 0.6) : tearFace(x, fromDir, h.force * 0.6)
				if hit { broken += 1 }
			}
			weather.hurricane?.broken = broken
		} else {
			hurricaneAcc = 0
		}
	}

	// MARK: storm surge

	/// At a hurricane's height the sea climbs a block or two up the shore near the player (sandbags
	/// hold it back). Every flooded spot is remembered, and saved, until the water has been taken
	/// away again once the storm eases; that also happens if the weather is switched off.
	func updateSurge(_ dt: Double) {
		surgeT -= dt
		if surgeT > 0 { return }
		surgeT = 0.5
		var rising: Bool = false
		var level: Int = WorldGen.sea - 1
		if settings.weatherOn && settings.allowHurricane && settings.weatherHurtsBlocks, let h = weather.hurricane, world.dim == .overworld {
			if h.stage == .peak || h.stage == .backside || h.stage == .intensifying {
				rising = true
				if h.stage == .peak || h.stage == .backside { level = WorldGen.sea - 2 }
			}
			if rising && weather.surge.count < 90 && abs(h.coastX - pb.x) < 140 { floodShore(h, level) }
		}
		if rising || weather.surge.isEmpty { return }
		// ebbing: a few spots at a time, wherever the ground is loaded (the rest waits for it). (The surge's
		// water is the storm's: it neither flows nor wakes the water round it.)
		var keep: [SurgeCell] = []
		var drained: Int = 0
		world.flowHold = true
		for c in weather.surge {
			if world.dim == .overworld && drained < 12 && world.isLoaded(c.x) {
				if world.tile(c.x, c.y) == .water { world.set(c.x, c.y, .air) }
				drained += 1
				continue
			}
			keep.append(c)
		}
		world.flowHold = false
		weather.surge = keep
	}

	/// Floods the low shore next to the sea, one strip of columns at a time
	func floodShore(_ h: HurricaneEvent, _ level: Int) {
		let inland: Int = h.side > 0 ? -1 : 1
		let sea: Int = WorldGen.sea
		// walk in from the open sea to the first column whose surface row is not sea water
		var x: Int = Int(floor(h.coastX)) - inland * 8
		var k: Int = 0
		while k < 60 && world.isLoaded(x) && world.tile(x, sea) == .water {
			x += inland
			k += 1
		}
		if !world.isLoaded(x) || k >= 60 { return }
		var added: Int = 0
		var col: Int = 0
		world.flowHold = true
		defer { world.flowHold = false }
		while col < 30 && added < 8 && weather.surge.count < 90 {
			let cx: Int = x + inland * col
			if !world.isLoaded(cx) { return }
			var y: Int = level
			var blocked: Bool = false
			while y < sea {
				let t: Tile = world.tile(cx, y)
				if t == .sandbag { blocked = true; break }
				if t == .air {
					world.set(cx, y, .water)
					weather.surge.append(SurgeCell(x: cx, y: y))
					added += 1
				}
				y += 1
			}
			// the surge stops at higher ground or at a sandbag wall
			if blocked || world.tile(cx, level).solid { return }
			col += 1
		}
	}

	// MARK: everything, once a frame

	func updateWeather(_ dt: Double) {
		if landT > 0 { landT -= dt }
		if pb.inWater && !wasInWater && pb.vy > 4.0 {
			sfx(.splash, clampD(pb.vy / 14.0, 0.3, 1.0))
			spawnParticles(pb.x, pb.y - 0.4, 0xB8D8F8, 8, 3.5, 0.45, 14)
		}
		wasInWater = pb.inWater
		stepWeatherSim(dt)
		wxHere = weatherAt(pb.x, pb.y - pb.h)
		weatherRain = wxHere.precip
		weatherSnow = wxHere.snow
		updateGroundCells(dt)
		updateTornado(dt)
		updateHurricane(dt)
		updateSurge(dt)
		updateLightning(dt)
		updateHail(dt)
		updateCold(dt)
		updateWeatherForces(dt)
		updateWindOnThings(dt)
		updateWeatherDevices(dt)
		updateWeatherBanner()
		wxNoteT -= dt
		if wxNoteT <= 0 {
			wxNoteT = 1.0
			checkWeatherNotes()
			let L: LocalWeather = wxHere
			if L.precip > 0.3 || abs(L.wind) > 8 || L.thunder > 0.5 || L.hail > 0.2 { stormFelt = true }
		}
		// rain puts out a burning player standing in it
		if weatherRain > 0.5 && !weatherSnow && playerBurn > 0 && rainReaches(pb.x, pb.y, pb.h) { playerBurn = 0 }
	}

	/// How hard it is raining at x (cheap: for checks made for many creatures)
	func precipAt(_ x: Double) -> Double {
		if world.dim != .overworld || !settings.weatherOn || weather.precip < 0.01 { return 0 }
		return weather.precip * coverAt(x) * biomeWetness(gen.col(Int(floor(x))).biome)
	}

	/// Keeps a storm the player lived through in the journal
	func recordStorm(_ k: WeatherKind, _ note: String) {
		var list: [StormRecord] = journal.storms ?? []
		list.append(StormRecord(kind: k.rawValue, day: dayCount, note: note))
		if list.count > 40 { list.removeFirst(list.count - 40) }
		journal.storms = list
	}
}

// MARK: - Weather on screen: storm skies, rain and snow, hail, wind, the funnel, lightning, waves
// Everything here is drawn from the simulation and a hash of each drop's index (no per-particle
// state), batched into one path per colour; only hailstones come from a small pool.

/// Small pixel-art weather symbols for the HUD and the station's screen
func weatherIconBuf(_ k: WeatherKind, _ snow: Bool) -> PixelBuf {
	var b = PixelBuf(w: 12, h: 12)
	let cloudL: UInt32 = 0xE8EEF4
	let cloudD: UInt32 = 0x8A929E
	let cloudS: UInt32 = 0x5A606C
	func cloud(_ c: UInt32, _ y: Int) {
		b.ellipse(4.5, Double(y) + 0.5, 2.6, 2.0, c)
		b.ellipse(7.5, Double(y) - 0.5, 3.0, 2.6, c)
		b.rect(2, y, 8, 2, c)
	}
	func drops(_ c: UInt32, _ n: Int) {
		for i in 0..<n {
			let x: Int = 2 + (i * 3) % 9
			let y: Int = 8 + (i % 2)
			b.set(x, y, c)
			b.set(x - 1, y + 2, c)
		}
	}
	func flakes() {
		for (x, y) in [(2, 9), (5, 10), (8, 9), (10, 11), (4, 11)] {
			b.set(x, y, 0xFFFFFF)
		}
	}
	switch k {
	case .clear:
		b.ellipse(6, 6, 3.0, 3.0, 0xFFD84A)
		b.ellipse(5.5, 5.5, 1.6, 1.6, 0xFFF2A0)
		for (x, y) in [(6, 0), (6, 11), (0, 6), (11, 6), (2, 2), (9, 2), (2, 9), (9, 9)] { b.set(x, y, 0xFFD84A) }
	case .partlyCloudy:
		b.ellipse(4, 4, 2.6, 2.6, 0xFFD84A)
		cloud(cloudL, 7)
	case .overcast:
		cloud(cloudD, 5)
		cloud(cloudL, 7)
	case .lightRain, .snowfall:
		cloud(cloudD, 4)
		if snow || k == .snowfall { flakes() } else { drops(0x7AB0F0, 3) }
	case .heavyRain:
		cloud(cloudS, 4)
		if snow { flakes() } else { drops(0x5A98F0, 6) }
	case .thunderstorm:
		cloud(cloudS, 4)
		b.line(7, 6, 5, 9, 0xFFE060)
		b.line(5, 9, 7, 9, 0xFFE060)
		b.line(7, 9, 5, 11, 0xFFE060)
		drops(0x5A98F0, 2)
	case .strongWind, .windstorm:
		b.line(1, 3, 8, 3, 0xE8EEF4)
		b.line(8, 3, 9, 2, 0xE8EEF4)
		b.line(0, 6, 10, 6, 0xE8EEF4)
		b.line(10, 6, 11, 5, 0xE8EEF4)
		b.line(2, 9, 7, 9, 0xE8EEF4)
		if k == .windstorm { b.set(9, 9, 0x8A6A3A); b.set(4, 11, 0x5E8A4A) }
	case .hailstorm:
		cloud(cloudS, 4)
		for (x, y) in [(3, 8), (6, 10), (9, 8), (4, 11)] { b.rect(x, y, 2, 1, 0xF4FAFF) }
	case .blizzard:
		cloud(cloudD, 3)
		flakes()
		b.line(0, 8, 6, 8, 0xC8D8E8)
	case .tornado:
		b.rect(1, 0, 10, 2, cloudS)
		b.rect(3, 2, 7, 2, 0x6E727B)
		b.rect(4, 4, 5, 2, 0x55585F)
		b.rect(5, 6, 3, 2, 0x6E727B)
		b.rect(5, 8, 2, 2, 0x55585F)
		b.rect(4, 10, 2, 1, 0x8A7A60)
	case .hurricane:
		b.ellipse(6, 6, 4.6, 4.6, 0x8A929E)
		b.ellipse(6, 6, 3.0, 3.0, 0xE8EEF4)
		b.ellipse(6, 6, 1.2, 1.2, 0x3A70C8)
		b.line(6, 1, 10, 2, 0xE8EEF4)
		b.line(6, 11, 2, 10, 0xE8EEF4)
	}
	b.outline(0x1A1410)
	return b
}

extension Art {
	func weatherIcon(_ k: WeatherKind, _ snow: Bool) -> Image {
		let key: Int = k.rawValue * 2 + (snow ? 1 : 0)
		if let i = wxIcons[key] { return i }
		let img: Image = pixImage(weatherIconBuf(k, snow))
		wxIcons[key] = img
		return img
	}
}

extension WorldRenderer {
	/// The sky's share of the weather: cloud cover and storm darkness, stars and sun hidden, the
	/// glow of lightning, and a hurricane's wall of cloud coming in off the sea
	static func drawSkyWeather(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D, _ day: Double) {
		let L: LocalWeather = g.wxHere
		let full: CGRect = mkRect(0, 0, W, H)
		let cl: Double = L.cloud
		if cl > 0.05 { fillRect(&ctx, full, Color(hex: 0x66707C, alpha: 0.7 * cl * max(0.3, day))) }
		let storm: Double = clampD((cl - 0.65) * 2.5, 0, 1) * (0.5 + 0.5 * L.precip)
		if storm > 0.02 { fillRect(&ctx, full, Color(hex: 0x262C36, alpha: 0.42 * storm * max(0.4, day))) }
		if L.snow && L.precip > 0.4 { fillRect(&ctx, full, Color(hex: 0xD8E0EA, alpha: 0.3 * L.precip * day)) }
	}

	/// The weather on the horizon: a hurricane's wall of cloud coming in off the sea
	static func drawSkyWeatherFront(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game) {
		if let h = g.weather.hurricane, h.stage.rawValue <= HurricaneStage.intensifying.rawValue {
			drawStormWall(&ctx, W, H, g, h)
		}
	}

	/// A towering wall of dark cloud on the sea-side horizon, growing as a hurricane comes in, with
	/// curtains of rain hanging under it
	static func drawStormWall(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ h: HurricaneEvent) {
		var prog: Double = clampD(h.t / max(1, h.stageDur), 0, 1)
		if h.stage == .intensifying { prog = 1.0 + prog }
		let width: Double = W * (0.22 + 0.3 * prog)
		let east: Bool = h.side > 0
		let step: Double = 8.0
		var wall: Path = Path()
		var shafts: Path = Path()
		var sx: Double = 0
		while sx < width {
			let x: Double = east ? W - sx - step : sx
			let n: Double = fbm1(sx / 60.0 + g.weather.t * 0.05, 4411, 3)
			// the wall rises toward the open sea, its top billowing
			let rise: Double = 0.35 + 0.5 * pow(1.0 - sx / width, 0.6) + 0.12 * n
			let top: Double = floor(H * (0.7 - rise * 0.75) / 4.0) * 4.0
			let base: Double = H * 0.7
			wall.addRect(mkRect(x, top, step + 1.0, base - top))
			if hash2(Int(sx / step), 3, 91) < 0.5 { shafts.addRect(mkRect(x + 2, base, 3, H * 0.2)) }
			sx += step
		}
		ctx.fill(wall, with: .color(Color(hex: 0x2E333C, alpha: 0.88)))
		ctx.fill(shafts, with: .color(Color(hex: 0x4A5464, alpha: 0.35)))
	}

	/// Lying snow (deeper where the wind drifts it), wet ground and puddles on the open surfaces in
	/// view. Drawn over the terrain and under everything else, so the light map shades it like the ground.
	static func drawGroundWeather(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld || !g.settings.weatherOn { return }
		if g.weather.cells.isEmpty { return }
		let x0: Int = Int(floor(v.left)) - 1
		let x1: Int = Int(ceil(v.left + v.wTiles)) + 1
		let tp: Double = v.tp
		var snowP: Path = Path()
		var wetP: Path = Path()
		var pudP: Path = Path()
		var anySnow: Bool = false
		var anyWet: Bool = false
		var wetSum: Double = 0
		var wetN: Double = 0
		let lee: Double = g.weather.wind >= 0 ? 1 : -1
		let raining: Bool = g.wxHere.precip > 0.1 && !g.wxHere.snow
		var ripples: Path = Path()
		for x in x0...x1 {
			let top: Int = g.world.rainTop(x)
			if top <= 0 || top >= g.world.H - 2 { continue }
			let wy: Double = Double(top)
			if wy < v.top - 1 || wy > v.top + v.hTiles + 1 { continue }
			let t: Tile = g.world.tile(x, top)
			if t.liquid { continue }
			let wx: Double = Double(x) + 0.5
			let sc: Double = g.groundValue(wx, true)
			let wet: Double = g.groundValue(wx, false)
			let sx: Double = v.sx(Double(x))
			let sy: Double = v.sy(wy)
			if sc > 0.05 {
				let h0: Double = hash2(x, 41, 3)
				let dr: Double = 0.5 + 0.5 * sin(Double(x) * 0.37 * lee)
				let hh: Double = tp * min(0.45, sc * (0.12 + 0.22 * h0 + 0.15 * dr))
				let snapH: Double = max(2.0, floor(hh / 2.0) * 2.0)
				snowP.addRect(mkRect(sx, sy - snapH + 2.0, tp + 0.5, snapH))
				anySnow = true
			}
			if wet > 0.08 && t.solid && !isLeafTile(t) && sc < 0.3 {
				wetP.addRect(mkRect(sx, sy, tp + 0.5, max(2.0, tp * 0.14)))
				wetSum += wet
				wetN += 1
				anyWet = true
				let level: Bool = g.world.rainTop(x - 1) == top && g.world.rainTop(x + 1) == top
				if wet > 0.35 && t != .sand && level && hash2(x, 43, 5) < (wet - 0.3) * 0.9 {
					pudP.addRect(mkRect(sx + 1.0, sy - 2.0, tp - 2.0, 4.0))
					if raining && hash2(x, Int(g.clock * 3.0), 47) < 0.5 {
						let rx: Double = sx + tp * (0.2 + 0.6 * hash2(x, Int(g.clock * 3.0), 48))
						ripples.addRect(mkRect(rx - 2.0, sy - 3.0, 4.0, 1.0))
					}
				}
			}
		}
		if anyWet {
			let a: Double = 0.22 * clampD(wetSum / max(1, wetN), 0, 1)
			ctx.fill(wetP, with: .color(Color(hex: 0x10203A, alpha: a)))
			ctx.fill(pudP, with: .color(Color(hex: 0x6A9AD0, alpha: 0.62)))
			ctx.fill(ripples, with: .color(Color(hex: 0xD8ECFF, alpha: 0.7)))
		}
		if anySnow { ctx.fill(snowP, with: .color(Color(hex: 0xF4F8FF, alpha: 0.95))) }
	}

	/// Rain and snow falling in world space, slanted and carried by the wind and stopping on the first
	/// thing in their way; splashes where rain lands; hail from the pool; blown dust and grass bent
	/// over in the wind
	static func drawPrecip(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if (g.world.dim != .overworld && g.customDim == nil) || !g.settings.weatherOn { return }
		let dens: Double = clampD(g.settings.weatherParticles, 0.2, 1.0)
		let tp: Double = v.tp
		let bands: Int = 8
		var amt: [Double] = [Double](repeating: 0, count: bands)
		var cold: [Bool] = [Bool](repeating: false, count: bands)
		var anyP: Double = 0
		let midY: Double = v.top + v.hTiles * 0.5
		for b in 0..<bands {
			let x: Double = v.left + v.wTiles * (Double(b) + 0.5) / Double(bands)
			let L: LocalWeather = g.weatherAt(x, midY)
			amt[b] = L.precip
			cold[b] = L.snow
			anyP = max(anyP, L.precip)
		}
		let wind: Double = g.wxHere.wind
		let clock: Double = g.clock
		if anyP > 0.02 {
			let n: Int = Int(300.0 * dens)
			let span: Double = v.hTiles + 6.0
			let cell: Double = v.wTiles + 8.0
			let x0: Double = v.left - 4.0
			var rain: Path = Path()
			var heavy: Path = Path()
			var snow: Path = Path()
			var streak: Path = Path()
			for i in 0..<n {
				let fx: Double = hash2(i, 11, 77)
				let fy: Double = hash2(i, 12, 77)
				let fz: Double = hash2(i, 13, 77)
				let fw: Double = hash2(i, 14, 77)
				// which band it falls in decides whether it falls at all (storm cells have edges)
				let guess: Double = x0 + fx * cell
				let bi: Int = clampI(Int((guess - v.left) / v.wTiles * Double(bands)), 0, bands - 1)
				let a: Double = amt[bi]
				if fw > a { continue }
				let isSnow: Bool = cold[bi]
				let speed: Double = isSnow ? 2.6 + fz * 1.6 : 19.0 + fz * 7.0
				let vx: Double = isSnow ? wind * 0.85 : wind * 0.75
				let fallen: Double = (fy * span + clock * speed).truncatingRemainder(dividingBy: span)
				let wy: Double = v.top - 3.0 + fallen
				var raw: Double = fx * cell + vx * (fallen / speed)
				if isSnow { raw += sin(clock * 1.3 + Double(i)) * 0.5 }
				let rel: Double = raw.truncatingRemainder(dividingBy: cell)
				let wx: Double = x0 + (rel < 0 ? rel + cell : rel)
				if wy >= Double(g.world.rainTop(Int(floor(wx)))) { continue }
				let sx: Double = v.sx(wx)
				let sy: Double = v.sy(wy)
				if isSnow {
					if abs(vx) > 7.0 {
						let l: Double = tp * 0.45
						streak.move(to: mkPoint(sx, sy))
						streak.addLine(to: mkPoint(sx - (vx > 0 ? l : -l), sy - l * 0.25))
					} else {
						let s: Double = fz > 0.7 ? 3.0 : 2.0
						snow.addRect(mkRect(sx, sy, s, s))
					}
				} else {
					let len: Double = (a > 0.6 ? 0.75 : 0.5) * tp
					let dx: Double = vx / speed * len
					if a > 0.6 && fz < 0.5 {
						heavy.move(to: mkPoint(sx, sy))
						heavy.addLine(to: mkPoint(sx - dx, sy - len))
					} else {
						rain.move(to: mkPoint(sx, sy))
						rain.addLine(to: mkPoint(sx - dx, sy - len))
					}
				}
			}
			// a mod's rain colour (the Overworld's), else the game's
			let rc: UInt32 = g.world.dim == .overworld ? (ModRuntime.shared.weather?.rainColor ?? 0) : 0
			ctx.stroke(rain, with: .color(Color(hex: rc != 0 ? rc : 0xA8C8F0, alpha: 0.45)), lineWidth: 1.5)
			ctx.stroke(heavy, with: .color(Color(hex: rc != 0 ? shadeRGB(rc, 0.9) : 0x9CBCE4, alpha: 0.55)), lineWidth: 2.0)
			ctx.fill(snow, with: .color(Color.white.opacity(0.85)))
			ctx.stroke(streak, with: .color(Color.white.opacity(0.7)), lineWidth: 2.0)
			drawSplashes(&ctx, g, v, amt, cold)
		}
		drawHail(&ctx, g, v)
		drawWindFX(&ctx, g, v)
	}

	/// Little crowns of spray where rain is landing on open ground
	static func drawSplashes(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ amt: [Double], _ cold: [Bool]) {
		let x0: Int = Int(floor(v.left))
		let x1: Int = Int(ceil(v.left + v.wTiles))
		let bands: Int = amt.count
		let tick: Int = Int(g.clock * 7.0)
		var p: Path = Path()
		var x: Int = x0
		while x <= x1 {
			let bi: Int = clampI(Int((Double(x) - v.left) / v.wTiles * Double(bands)), 0, bands - 1)
			let a: Double = amt[bi]
			if a > 0.05 && !cold[bi] && hash2(x, tick, 9) < a * 0.3 {
				let top: Int = g.world.rainTop(x)
				let wy: Double = Double(top)
				if top > 0 && v.visible(Double(x), wy, 1) && !g.world.tile(x, top).liquid {
					let ph: Double = (g.clock * 7.0).truncatingRemainder(dividingBy: 1.0)
					let sx: Double = v.sx(Double(x) + 0.2 + 0.6 * hash2(x, tick, 10))
					let sy: Double = v.sy(wy)
					let up: Double = 3.0 + 4.0 * ph
					p.addRect(mkRect(sx - 3.0 - ph * 2.0, sy - up, 2, 2))
					p.addRect(mkRect(sx + 1.0 + ph * 2.0, sy - up, 2, 2))
				}
			}
			x += 1
		}
		ctx.fill(p, with: .color(Color(hex: 0xC8DCF4, alpha: 0.6)))
	}

	static func drawHail(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.hailPool.isEmpty { return }
		var p: Path = Path()
		var any: Bool = false
		for s in g.hailPool where s.on {
			if !v.visible(s.x, s.y, 1) { continue }
			let r: Double = max(2.0, s.size * v.tp)
			p.addRect(mkRect(v.sx(s.x) - r * 0.5, v.sy(s.y) - r * 0.5, r, r))
			any = true
		}
		if !any { return }
		ctx.fill(p, with: .color(Color(hex: 0xF0F8FF, alpha: 0.95)))
		ctx.stroke(p, with: .color(Color(hex: 0x9AB0C8, alpha: 0.6)), lineWidth: 1)
	}

	/// Streaks of blown air (dust in dry country) and the grass bending over in the wind
	static func drawWindFX(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let wind: Double = g.wxHere.wind
		let aw: Double = abs(wind)
		if aw < 2.5 { return }
		let tp: Double = v.tp
		let dens: Double = clampD(g.settings.weatherParticles, 0.2, 1.0)
		if aw > 5.0 {
			let n: Int = min(48, Int((aw - 5.0) * 4.0 * dens))
			let cell: Double = v.wTiles + 8.0
			let x0: Double = v.left - 4.0
			let dry: Bool = g.biomeHere == .desert || g.biomeHere == .savanna
			var p: Path = Path()
			for i in 0..<n {
				let fx: Double = hash2(i, 21, 55)
				let fy: Double = hash2(i, 22, 55)
				let fz: Double = hash2(i, 23, 55)
				let raw: Double = (fx * cell + g.clock * wind * (1.1 + fz)).truncatingRemainder(dividingBy: cell)
				let wx: Double = x0 + (raw < 0 ? raw + cell : raw)
				let wy: Double = v.top + fy * v.hTiles
				if wy >= Double(g.world.rainTop(Int(floor(wx)))) { continue }
				let l: Double = tp * (0.8 + 1.2 * fz) * min(1.6, aw / 10.0)
				let sx: Double = v.sx(wx)
				let sy: Double = floor(v.sy(wy))
				p.addRect(mkRect(wind > 0 ? sx - l : sx, sy, l, dry ? 2 : 1))
			}
			ctx.fill(p, with: .color(dry ? Color(hex: 0xD8C890, alpha: 0.4) : Color.white.opacity(0.22)))
		}
		// grass bent over by the wind on open ground near the surface
		let x0: Int = Int(floor(v.left))
		let x1: Int = Int(ceil(v.left + v.wTiles))
		let lean: Double = clampD(wind / 14.0, -1, 1) * 0.3
		var blades: Path = Path()
		var any: Bool = false
		for x in x0...x1 {
			let top: Int = g.world.rainTop(x)
			if top <= 0 || !v.visible(Double(x), Double(top), 1) { continue }
			let t: Tile = g.world.tile(x, top)
			if t != .grass && t != .dryGrass && t != .jungleGrass && t != .mossGrass { continue }
			let sx: Double = v.sx(Double(x))
			let sy: Double = v.sy(Double(top))
			for k in 0..<2 {
				let bx: Double = sx + tp * (0.25 + 0.5 * Double(k))
				let sway: Double = (lean + sin(g.clock * 3.1 + Double(x) * 0.9 + Double(k)) * 0.06 * g.weather.gust) * tp
				blades.move(to: mkPoint(bx, sy + 1.0))
				blades.addLine(to: mkPoint(bx + sway, sy - tp * 0.26))
				any = true
			}
		}
		if any { ctx.stroke(blades, with: .color(Color(hex: 0x6EB848, alpha: 0.9)), lineWidth: max(1.5, tp * 0.07)) }
	}

	/// The tornado: a swaying funnel of grey bands that turn as they rise, debris flung round it and
	/// a skirt of dust at its foot. While forming it only reaches part of the way down.
	static func drawTornado(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		guard let e = g.weather.tornado, g.world.dim == .overworld, g.settings.weatherOn else { return }
		let fn: Double = e.funnel
		if fn <= 0.02 { return }
		let ground: Double = g.tornadoGround > 0 ? g.tornadoGround : Double(g.world.surfaceY(Int(floor(e.x))))
		let cloudBase: Double = ground - 32.0
		if !v.visible(e.x, ground - 22.0, 40) { return }
		let tp: Double = v.tp
		let px: Double = tp / 8.0
		let reach: Double = e.phase == 0 ? cloudBase + (ground - cloudBase) * min(1.0, fn / 0.55) * 0.75 : ground
		var dark: Path = Path()
		var light: Path = Path()
		var y: Double = cloudBase
		let bandH: Double = 0.5
		while y < reach {
			let hf: Double = (ground - y) / (ground - cloudBase)
			let w: Double = (0.6 + 6.8 * pow(hf, 1.35)) * (0.5 + 0.5 * fn)
			let sway: Double = sin(g.clock * 1.6 + hf * 3.0) * (0.4 + hf * 1.6)
			let cx: Double = e.x + sway
			let sx: Double = floor(v.sx(cx - w) / px) * px
			let ex: Double = floor(v.sx(cx + w) / px) * px
			let sy: Double = floor(v.sy(y) / px) * px
			let stripe: Int = Int(floor(hf * 30.0 - g.clock * 5.0)) & 3
			let r: CGRect = mkRect(sx, sy, max(px, ex - sx), bandH * tp + 1.0)
			if stripe == 0 { light.addRect(r) } else { dark.addRect(r) }
			y += bandH
		}
		let a: Double = min(1.0, fn * 1.2)
		ctx.fill(dark, with: .color(Color(hex: 0x40434A, alpha: 0.95 * a)))
		ctx.fill(light, with: .color(Color(hex: 0x5E626B, alpha: 0.95 * a)))
		if e.phase == 0 { return }
		// debris whirling round it, and dust at the foot
		var deb: Path = Path()
		var leaf: Path = Path()
		for i in 0..<30 {
			let hf: Double = hash2(i, 61, 7) * 0.7
			let wy: Double = ground - hf * (ground - cloudBase)
			let w: Double = (0.6 + 6.8 * pow(hf, 1.35)) * 1.2 + 0.7
			let ang: Double = g.clock * (3.0 + hash2(i, 62, 7) * 2.0) + Double(i) * 1.7
			let wx: Double = e.x + cos(ang) * w + sin(g.clock * 1.6 + hf * 3.0) * (0.4 + hf * 1.6)
			let s: Double = max(2.0, tp * (0.12 + 0.12 * hash2(i, 63, 7)))
			let r: CGRect = mkRect(v.sx(wx), v.sy(wy), s, s)
			if i % 3 == 0 { leaf.addRect(r) } else { deb.addRect(r) }
		}
		ctx.fill(deb, with: .color(Color(hex: 0x6A5A44, alpha: 0.9 * a)))
		ctx.fill(leaf, with: .color(Color(hex: 0x4E7A3A, alpha: 0.9 * a)))
		var dust: Path = Path()
		for k in 0..<5 {
			let off: Double = (Double(k) - 2.0) * 1.6 + sin(g.clock * 2.0 + Double(k)) * 0.5
			let rw: Double = (2.2 + hash2(k, 64, 7) * 1.4) * tp
			let rh: Double = rw * 0.45
			dust.addEllipse(in: mkRect(v.sx(e.x + off) - rw * 0.5, v.sy(ground) - rh * 0.9, rw, rh))
		}
		ctx.fill(dust, with: .color(Color(hex: 0x8A7A60, alpha: 0.45 * a)))
	}

	/// Storm waves along the open sea's surface (a hurricane or a strong wind), with foam on the crests
	static func drawWaves(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld || !g.settings.weatherOn { return }
		let aw: Double = abs(g.weather.wind)
		let rough: Double = max(g.wxHere.hurricane, clampD((aw - 6.0) / 10.0, 0, 1) * 0.6)
		if rough < 0.05 { return }
		let sea: Int = WorldGen.sea
		if Double(sea) < v.top - 3.0 || Double(sea) > v.top + v.hTiles + 3.0 { return }
		let tp: Double = v.tp
		let dir: Double = g.weather.wind >= 0 ? 1 : -1
		var body: Path = Path()
		var foam: Path = Path()
		let x0: Int = Int(floor(v.left))
		let x1: Int = Int(ceil(v.left + v.wTiles))
		for x in x0...x1 {
			// the water's surface at sea level, or a block or two above it where a surge has come in
			var top: Int = -1
			for y in (sea - 2)...sea where g.world.tile(x, y) == .water && g.world.tile(x, y - 1) == .air {
				top = y
				break
			}
			if top < 0 { continue }
			let sy: Double = v.sy(Double(top))
			let ph: Double = Double(x) * 0.42 - g.clock * 2.6 * dir
			let s: Double = sin(ph)
			let hgt: Double = floor(rough * 1.6 * (0.55 + 0.45 * s) * tp / 2.0) * 2.0
			let sx: Double = v.sx(Double(x))
			body.addRect(mkRect(sx, sy - hgt, tp + 0.5, hgt))
			if s > 0.55 { foam.addRect(mkRect(sx, sy - hgt - 2.0, tp + 0.5, 3.0)) }
		}
		ctx.fill(body, with: .color(Color(hex: artGrade(0x3B6FC8), alpha: 0.78)))
		ctx.fill(foam, with: .color(Color.white.opacity(0.75)))
	}

	/// Lightning (drawn over the darkness, so it lights up the night) and the warning glow where a
	/// strike is about to land
	static func drawBolts(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let tp: Double = v.tp
		if let m = g.strikeMark {
			let k: Double = clampD(1.0 - m.t / max(0.01, m.total), 0, 1)
			let pulse: Double = 0.5 + 0.5 * sin(g.clock * 18.0)
			let a: Double = (0.25 + 0.5 * k) * (g.settings.reduceFlashes ? 0.7 : (0.6 + 0.4 * pulse))
			let cx: Double = v.sx(m.x)
			let cy: Double = v.sy(m.y)
			fillRect(&ctx, mkRect(cx - tp * 0.15, cy - tp * 6.0, tp * 0.3, tp * 6.0), Color(hex: 0xCFE4FF, alpha: a * 0.35))
			fillOval(&ctx, mkRect(cx - tp * 1.2, cy - tp * 0.4, tp * 2.4, tp * 0.8), Color(hex: 0xCFE4FF, alpha: a * 0.6))
		}
		if g.bolts.isEmpty { return }
		let soft: Bool = g.settings.reduceFlashes
		for b in g.bolts {
			let k: Double = clampD(b.life / b.maxLife, 0, 1)
			// a double flicker (steady when flashes are turned down)
			let flick: Double = soft ? 0.8 : ((b.life > b.maxLife * 0.55 || b.life < b.maxLife * 0.3) ? 1.0 : 0.45)
			var main: Path = Path()
			for (i, p) in b.pts.enumerated() {
				let pt: CGPoint = mkPoint(v.sx(p.0), v.sy(p.1))
				if i == 0 { main.move(to: pt) } else { main.addLine(to: pt) }
			}
			var forks: Path = Path()
			for f in b.forks {
				for (i, p) in f.enumerated() {
					let pt: CGPoint = mkPoint(v.sx(p.0), v.sy(p.1))
					if i == 0 { forks.move(to: pt) } else { forks.addLine(to: pt) }
				}
			}
			ctx.stroke(main, with: .color(Color(hex: 0x9EC0FF, alpha: 0.35 * k * flick)), lineWidth: max(4.0, tp * 0.45))
			ctx.stroke(main, with: .color(Color.white.opacity(k * flick)), lineWidth: 2.5)
			ctx.stroke(forks, with: .color(Color(hex: 0xDDE8FF, alpha: 0.8 * k * flick)), lineWidth: 1.5)
		}
	}

	/// The air itself: a whiteout in a blizzard, grey murk in heavy rain, the dark under a tornado,
	/// frost creeping in at the edges when the player is freezing, and lightning's flash
	static func drawWeatherOverlay(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld { return }
		let L: LocalWeather = g.wxHere
		let full: CGRect = mkRect(0, 0, W, H)
		// heavy cloud dims the daylight evenly over everything (a storm by day is dark)
		let dim: Double = clampD((L.cloud - 0.55) * 2.2, 0, 1) * g.dayFactor
		if g.settings.weatherOn && dim > 0.02 { fillRect(&ctx, full, Color(hex: 0x0A0E16, alpha: 0.22 * dim)) }
		if g.settings.weatherOn && g.shelterLevel <= 1 {
			if L.fog > 0.02 {
				if L.snow {
					fillRect(&ctx, full, Color(hex: 0xDDE5EE, alpha: min(0.55, L.fog * 0.6)))
				} else {
					fillRect(&ctx, full, Color(hex: 0x7A8696, alpha: min(0.25, L.fog * 0.35)))
				}
			}
			if L.tornado > 0.05 { fillRect(&ctx, full, Color(hex: 0x1E2228, alpha: 0.22 * L.tornado)) }
			// blowing dust in dry country
			let aw: Double = abs(L.wind)
			let b: Biome = g.biomeHere
			if aw > 6 && (b == .desert || b == .savanna) {
				fillRect(&ctx, full, Color(hex: 0xD2B47A, alpha: 0.3 * clampD((aw - 6.0) / 8.0, 0, 1) * max(0.35, g.dayFactor)))
			}
		}
		if g.bodyCold > 0.3 { edgeVignette(&ctx, W, H, 0xCFEFFF, (g.bodyCold - 0.3) * 0.7) }
		if g.skyFlash > 0.01 {
			let inside: Double = g.shelterLevel >= 3 ? 0.3 : 1.0
			let a: Double = g.skyFlash * (g.settings.reduceFlashes ? 0.25 : 0.38) * inside
			fillRect(&ctx, full, Color(hex: 0xEEF4FF, alpha: a))
		}
	}
}

// MARK: - Weather devices: station, siren, lightning rod, turbine, rain barrels, vane, heater
// Every device reads the simulation itself (a station's forecast is the simulation's own plan, a vane
// points where the wind actually blows, a barrel fills with the rain that actually falls on it). Their
// places come from a per-chunk list that is rebuilt only when the chunk changes.

struct DeviceSpot {
	var x: Int
	var y: Int
	var t: Tile
}

/// Blocks built to stand up to storms: the wind never moves them, and walls or a roof of them make a
/// storm shelter
func isStormproof(_ t: Tile) -> Bool {
	switch t {
	case .stormBrick, .sandbag, .shutterClosed, .shingles: return true
	default: return false
	}
}

func isWeatherDevice(_ t: Tile) -> Bool {
	switch t {
	case .weatherStation, .dopplerStation, .stormSiren, .lightningRod, .windTurbine, .rainBarrel, .rainCistern, .weatherVane: return true
	default: return false
	}
}

/// How far a lightning rod draws strikes (blocks to either side)
let rodReach: Double = 14.0
/// How far a turbine's charge reaches a Doppler station
let turbineReach: Double = 10.0

extension World {
	/// Re-reads a chunk's weather facts if it has changed since: per column, the row rain first stops
	/// at (anything solid, glass, leaves, platforms, water), and where its weather devices are
	func weatherScan(_ c: Chunk) {
		if c.wxRev == c.rev && c.wxTop.count == chunkW { return }
		c.wxRev = c.rev
		if c.wxTop.count != chunkW { c.wxTop = [Int](repeating: c.H, count: chunkW) }
		c.wxDev.removeAll(keepingCapacity: true)
		let H: Int = c.H
		for lx in 0..<chunkW {
			let base: Int = lx * H
			var top: Int = H
			var y: Int = 0
			while y < H {
				let raw: Int = Int(c.tiles[base + y])
				if raw != 0 {
					if top == H && Tile.rainStopTable[raw] { top = y }
					if Tile.deviceTable[raw] { c.wxDev.append(DeviceSpot(x: c.x0 + lx, y: y, t: Tile.make(UInt8(raw)))) }
				}
				y += 1
			}
			c.wxTop[lx] = c.hasSky ? top : 0
		}
	}

	/// The first row rain (or hail, or lightning) stops at in column x; 0 where nothing is loaded
	func rainTop(_ x: Int) -> Int {
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return 0 }
		weatherScan(c)
		return c.wxTop[x - cx * chunkW]
	}

	/// Weather devices of the given kinds between columns x0 and x1 (loaded chunks only)
	func devices(_ x0: Int, _ x1: Int, _ kinds: [Tile]) -> [DeviceSpot] {
		var out: [DeviceSpot] = []
		let c0: Int = floorDiv(x0, chunkW)
		let c1: Int = floorDiv(x1, chunkW)
		if c1 < c0 { return out }
		for cx in c0...c1 {
			guard let c = chunks[cx] else { continue }
			weatherScan(c)
			for d in c.wxDev where d.x >= x0 && d.x <= x1 && kinds.contains(d.t) { out.append(d) }
		}
		return out
	}
}

/// What a weather station's screen shows, a line at a time
struct StationLine {
	var kind: WeatherKind?
	var snow: Bool = false
	var text: String
	var sub: String = ""
	var color: UInt32 = 0xE8F0E8
}

func roughWhen(_ s: Double) -> String {
	if s < 90 { return "soon" }
	if s < 300 { return "in a few minutes" }
	if s < 600 { return "later on" }
	return "much later"
}

func minutesText(_ s: Double) -> String {
	let m: Int = Int((s / 60.0).rounded())
	if m <= 0 { return "under a minute" }
	return m == 1 ? "about 1 min" : joinText("about ", String(m), " min")
}

func windWords(_ w: Double) -> String {
	let a: Double = abs(w)
	let from: String = w > 0 ? "west" : "east"
	let speed: String = String(Int(a.rounded()))
	var how: String = "calm"
	if a >= 13 { how = "gale" } else if a >= 8 { how = "strong" } else if a >= 4 { how = "breezy" } else if a >= 1.5 { how = "light" }
	if a < 0.8 { return "Calm" }
	return joinText("Wind ", speed, " blocks/s from the ", from, " (", how, ")")
}

extension Game {
	/// The nearest lightning rod whose reach covers column x
	func rodCovering(_ x: Double) -> DeviceSpot? {
		let ix: Int = Int(floor(x))
		let r: Int = Int(rodReach)
		var best: DeviceSpot? = nil
		var bd: Int = Int.max
		for d in world.devices(ix - r, ix + r, [.lightningRod]) {
			let dd: Int = abs(d.x - ix)
			// a rod buried under a roof is no use: it has to stand in the open
			if d.y >= world.rainTop(d.x) && d.y > 0 { continue }
			if dd < bd {
				bd = dd
				best = d
			}
		}
		return best
	}

	func deviceKey(_ d: DeviceSpot) -> String { return joinText(String(d.x), ",", String(d.y)) }

	/// Rain barrels fill with the rain that falls on them, turbines store the wind's energy (and run
	/// Doppler stations near them), and sirens sound when a storm worth warning of is near
	func updateWeatherDevices(_ dt: Double) {
		wxDevT -= dt
		if wxDevT > 0 { return }
		let step: Double = 0.5 - wxDevT
		wxDevT = 0.5
		sirenLevel = 0
		if world.dim != .overworld { return }
		let px: Int = Int(floor(pb.x))
		let list: [DeviceSpot] = world.devices(px - 96, px + 96, [.rainBarrel, .rainCistern, .windTurbine, .stormSiren, .dopplerStation])
		if list.isEmpty { return }
		let warn: Bool = settings.weatherOn && sirenWorthy()
		for d in list {
			let k: String = deviceKey(d)
			switch d.t {
			case .rainBarrel, .rainCistern:
				let cap: Double = d.t == .rainBarrel ? 8 : 32
				let open: Bool = d.y < world.rainTop(d.x)
				let L: LocalWeather = weatherAt(Double(d.x) + 0.5, Double(d.y))
				if open && L.precip > 0.02 {
					let rate: Double = (L.snow ? 0.012 : 0.04) * (d.t == .rainCistern ? 2.0 : 1.0)
					weather.store[k] = min(cap, (weather.store[k] ?? 0) + L.precip * rate * step)
				}
			case .windTurbine:
				let open: Bool = d.y - 1 < world.rainTop(d.x) || world.tile(d.x, d.y - 1) == .air
				if open && settings.weatherOn {
					// like a real turbine it needs some wind before it turns (2 blocks a second)
					let w: Double = abs(weatherAt(Double(d.x) + 0.5, Double(d.y)).wind)
					weather.store[k] = min(100, (weather.store[k] ?? 0) + max(0, w - 2.0) * 0.35 * step)
				}
			case .dopplerStation:
				// the radar draws a little charge from a turbine close by
				if let t = poweringTurbine(d) {
					let tk: String = deviceKey(t)
					weather.store[tk] = max(0, (weather.store[tk] ?? 0) - 0.1 * step)
				}
			case .stormSiren:
				// sounds by itself for a dangerous storm, or whenever a pulse wire through it is on
				if warn || pulseOnAt(d.x, d.y) {
					let dist: Double = abs(Double(d.x) - pb.x)
					sirenLevel = max(sirenLevel, clampD(1.0 - dist / 64.0, 0, 1))
				}
			default:
				break
			}
		}
	}

	/// Storms a siren sounds for: a tornado forming or on the ground, a hurricane, a blizzard
	func sirenWorthy() -> Bool {
		if let e = weather.tornado, e.phase < 2, abs(e.x - pb.x) < 200 { return true }
		if let h = weather.hurricane, h.stage != .clearing { return true }
		if weather.kind == .blizzard && settings.allowBlizzard && wxHere.snow { return true }
		return false
	}

	/// A turbine with charge to spare close enough to run a Doppler station
	func poweringTurbine(_ d: DeviceSpot) -> DeviceSpot? {
		let r: Int = Int(turbineReach)
		for t in world.devices(d.x - r, d.x + r, [.windTurbine]) where abs(t.y - d.y) <= r {
			if (weather.store[deviceKey(t)] ?? 0) > 2 { return t }
		}
		return nil
	}

	/// Tapping a weather device
	func useWeatherDevice(_ tx: Int, _ ty: Int, _ t: Tile) {
		let d = DeviceSpot(x: tx, y: ty, t: t)
		let k: String = deviceKey(d)
		switch t {
		case .weatherStation, .dopplerStation:
			stationAt = d
			showWeather = true
			sfx(.tap, 0.6)
			bumpHUD()
		case .stormSiren:
			let on: Bool = settings.weatherOn && sirenWorthy()
			say(on ? "The siren is sounding: a dangerous storm is near. Take shelter!" : "Storm siren: it sounds by itself when a tornado, hurricane or blizzard comes near.", 3.0)
		case .lightningRod:
			let open: Bool = ty < world.rainTop(tx)
			say(open ? "Lightning rod: strikes within 14 blocks either side come down here, harmlessly." : "This rod is under cover. A lightning rod only works out in the open, on top of things.", 3.0)
		case .windTurbine:
			let charge: Double = weather.store[k] ?? 0
			if let st = heldStack, case .gun(.stormRod) = st.item, charge >= 50 {
				var n: Int = 0
				for i in 0..<inv.slots.count {
					if var s = inv.slots[i], case .gun(.stormRod) = s.item, s.extra < GunType.stormRod.magazine {
						s.extra = GunType.stormRod.magazine
						inv.slots[i] = s
						n += 1
					}
				}
				if n > 0 {
					weather.store[k] = charge - 50
					sfx(.zap, 0.6)
					say("The turbine's charge fills your storm rod.", 2.0)
					bumpHUD()
					return
				}
			}
			let w: Double = abs(weatherAt(Double(tx) + 0.5, Double(ty)).wind)
			say(joinText("Wind turbine: ", String(Int(charge.rounded())), "% charged (", w > 0.5 ? joinText("turning at ", String(Int(w.rounded())), " blocks/s of wind") : "becalmed", "). Runs a Doppler station within 10 blocks; tap it holding a storm rod to recharge the rod."), 3.5)
		case .rainBarrel, .rainCistern:
			let cap: Double = t == .rainBarrel ? 8 : 32
			let have: Double = weather.store[k] ?? 0
			if have >= 1.0 {
				weather.store[k] = have - 1.0
				giveItem(.gadget(.waterFlask), 1)
				sfx(.splash, 0.5)
				say(joinText("You fill a flask. ", String(Int(have - 1.0)), " of ", String(Int(cap)), " left."), 2.0)
			} else {
				say(joinText(t == .rainBarrel ? "Rain barrel" : "Rain cistern", ": ", String(format: "%.1f", have), " of ", String(Int(cap)), ". It fills when rain falls on it."), 2.5)
			}
		case .weatherVane:
			let w: Double = weatherAt(Double(tx) + 0.5, Double(ty)).wind
			say(joinText("Weather vane: ", windWords(w), "."), 2.5)
		case .shutterClosed, .shutterOpen:
			world.set(tx, ty, t == .shutterClosed ? .shutterOpen : .shutterClosed)
			sfx(.door, 0.6)
			light.valid = false
		case .heater:
			say("Heater: keeps you warm when you stand close to it, without the smoke of a fire.", 2.5)
		default:
			break
		}
	}

	/// What the station that was tapped shows (a Doppler station near a charged turbine shows more,
	/// and more exactly)
	func stationReport() -> [StationLine] {
		var out: [StationLine] = []
		guard let st = stationAt else { return out }
		let doppler: Bool = st.t == .dopplerStation
		let powered: Bool = doppler && poweringTurbine(st) != nil
		if !settings.weatherOn {
			out.append(StationLine(kind: .clear, text: "The weather is switched off", sub: "Turn it on in Settings (WEATHER) to see forecasts."))
			return out
		}
		let L: LocalWeather = weatherAt(Double(st.x) + 0.5, Double(st.y))
		let fc: [ForecastLine] = forecast()
		let now: ForecastLine = fc[0]
		out.append(StationLine(kind: weather.kind, snow: L.snow, text: joinText("Now: ", weatherLabel(weather.kind, snow: L.snow)), sub: joinText(powered ? minutesText(now.dur) : roughWhen(now.dur), " more"), color: 0xFFFFFF))
		let p: Double = pressureNow()
		let trend: Double = pressureNext() - p
		let tr: String = trend < -6 ? "falling fast" : (trend < -2 ? "falling" : (trend > 2 ? "rising" : "steady"))
		let temp: String = L.chill > 0.8 ? "freezing" : (L.chill > 0.5 ? "cold" : (L.chill > 0.25 ? "cool" : (L.hot ? "hot" : "mild")))
		out.append(StationLine(text: windWords(L.wind), sub: joinText("Pressure ", String(Int(p.rounded())), " hPa, ", tr, " · ", temp)))
		// warnings from the simulation's events
		if let e = weather.tornado {
			let d: Double = e.x - pb.x
			var line: String = joinText(e.phase == 0 ? "TORNADO FORMING " : "TORNADO ", String(Int(abs(d).rounded())), " blocks ", d > 0 ? "east" : "west")
			var sub: String = joinText("Moving ", e.dir > 0 ? "east" : "west")
			if powered {
				let coming: Bool = (d > 0) != (e.dir > 0)
				if coming && e.phase <= 1 {
					let eta: Double = abs(d) / max(0.5, e.speed) + (e.phase == 0 ? max(0, e.warnDur - e.t) : 0)
					sub = joinText(sub, " · reaches you in ", minutesText(eta))
				} else {
					sub = joinText(sub, " · moving away from you")
				}
				line = joinText(line, String(format: " · strength %d", Int((e.strength * 5.0).rounded())))
			}
			out.append(StationLine(kind: .tornado, text: line, sub: sub, color: 0xFF7060))
		}
		if let h = weather.hurricane {
			let sub: String = powered ? joinText("Over in ", minutesText(h.timeLeft()), " · sea to the ", h.side > 0 ? "east" : "west") : "Stay off the coast and out of boats"
			out.append(StationLine(kind: .hurricane, text: joinText("HURRICANE: ", h.stage.name), sub: sub, color: 0xFF7060))
		}
		if doppler && !powered { out.append(StationLine(text: "Radar unpowered", sub: "Put a charged wind turbine within 10 blocks for the full forecast", color: 0xFFC060)) }
		// the rain that is on its way (radar)
		if powered && L.precip < 0.05 && weather.precip > 0.15 {
			let up: Double = weather.wind >= 0 ? -1 : 1
			var dx: Double = 8
			while dx <= 240 {
				if coverAt(pb.x + up * dx) > 0.4 {
					let speed: Double = max(0.3, abs(weather.wind) * 0.55)
					out.append(StationLine(text: joinText("Rain ", String(Int(dx)), " blocks upwind"), sub: joinText("Reaches you in ", minutesText(dx / speed))))
					break
				}
				dx += 8
			}
		}
		// the plan
		let n: Int = powered ? fc.count : min(3, fc.count)
		if n > 1 {
			for i in 1..<n {
				let f: ForecastLine = fc[i]
				let when: String = powered ? joinText("In ", minutesText(f.startsIn), ", for ", minutesText(f.dur)) : roughWhen(f.startsIn).capitalized
				let warnCol: UInt32 = f.kind.severe ? 0xFFB060 : 0xE8F0E8
				out.append(StationLine(kind: f.kind, snow: L.snow, text: weatherLabel(f.kind, snow: L.snow), sub: when, color: warnCol))
			}
		}
		// devices close by
		let rods: Int = world.devices(st.x - 40, st.x + 40, [.lightningRod]).count
		let sirens: Int = world.devices(st.x - 64, st.x + 64, [.stormSiren]).count
		out.append(StationLine(text: joinText("Lightning rods nearby: ", String(rods), " · sirens: ", String(sirens)), sub: doppler ? "Doppler station" : "Weather station (craft a Doppler station for exact times)"))
		return out
	}

	/// A barometer in hand: less than a station tells, but always with you
	func barometerReading() -> String {
		if !settings.weatherOn { return "Barometer: steady (no weather)" }
		let p: Double = pressureNow()
		let trend: Double = pressureNext() - p
		var look: String = "fair"
		if trend < -6 || p < 995 { look = "storm likely" } else if trend < -2 { look = "unsettled" } else if trend > 2 { look = "clearing" }
		let arrow: String = trend < -2 ? "▼" : (trend > 2 ? "▲" : "▶")
		return joinText("Barometer ", String(Int(p.rounded())), " hPa ", arrow, " ", look)
	}

	/// Pouring a water flask: a crop grows a stage, a fire goes out, a burning player is doused
	func useWaterFlask(_ pressed: Bool) {
		if !pressed || useCD > 0 { return }
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		func spend() {
			if !isCreative { inv.removeAt(sel, 1) }
			useCD = 0.4
			swingT = 0.18
			sfx(.splash, 0.5)
			spawnParticles(aimX, aimY, 0x8DBBFF, 8, 2.5, 0.4, 14)
			bumpHUD()
		}
		if inReach(aimX, aimY) {
			let t: Tile = world.tile(tx, ty)
			var grown: Tile? = nil
			switch t {
			case .wheat1: grown = .wheat2
			case .wheat2: grown = .wheat3
			case .carrot1: grown = .carrot2
			case .carrot2: grown = .carrot3
			default: break
			}
			if let g = grown {
				world.set(tx, ty, g)
				spend()
				return
			}
			if let i = fireZones.firstIndex(where: { abs($0.x - aimX) < $0.r + 0.6 && abs($0.y - aimY) < 2.5 }) {
				fireZones.remove(at: i)
				spawnParticles(aimX, aimY, 0xC8C8C8, 10, 2.0, 0.8, -3)
				spend()
				return
			}
		}
		if playerBurn > 0 {
			playerBurn = 0
			spend()
			return
		}
		say("Pour it on a young crop to help it grow, or on a fire to put it out.", 2.0)
	}
}

extension WorldRenderer {
	/// The moving parts of weather devices in view: turbine blades turning with the wind, the vane
	/// pointing downwind, a siren's beacon, the water in a barrel, a station's blinking screen
	static func drawWeatherDevices(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim != .overworld { return }
		let x0: Int = Int(floor(v.left)) - 2
		let x1: Int = Int(ceil(v.left + v.wTiles)) + 2
		let list: [DeviceSpot] = g.world.devices(x0, x1, [.windTurbine, .weatherVane, .stormSiren, .rainBarrel, .rainCistern, .weatherStation, .dopplerStation])
		if list.isEmpty { return }
		let tp: Double = v.tp
		var blades: Path = Path()
		var vane: Path = Path()
		var water: Path = Path()
		var glow: Path = Path()
		var beacon: Path = Path()
		for d in list {
			if !v.visible(Double(d.x), Double(d.y), 3) { continue }
			let cx: Double = v.sx(Double(d.x) + 0.5)
			let top: Double = v.sy(Double(d.y))
			switch d.t {
			case .windTurbine:
				// three blades round the hub, turning with the local wind
				let w: Double = g.settings.weatherOn ? g.weatherAt(Double(d.x) + 0.5, Double(d.y)).wind : 0
				let ang: Double = g.clock * clampD(w * 0.6, -9, 9)
				let hx: Double = cx
				let hy: Double = top + tp * 0.18
				let len: Double = tp * 0.95
				for k in 0..<3 {
					let a: Double = ang + Double(k) * 2.0944
					blades.move(to: mkPoint(hx, hy))
					blades.addLine(to: mkPoint(hx + cos(a) * len, hy + sin(a) * len))
				}
			case .weatherVane:
				let w: Double = g.settings.weatherOn ? g.weatherAt(Double(d.x) + 0.5, Double(d.y)).wind : 0
				let s: Double = w >= 0 ? 1.0 : -1.0
				let wob: Double = sin(g.clock * 5.0) * min(0.15, abs(w) * 0.01)
				let y: Double = top + tp * 0.22
				vane.move(to: mkPoint(cx - s * tp * 0.45, y + wob * tp))
				vane.addLine(to: mkPoint(cx + s * tp * 0.45, y - wob * tp))
				vane.move(to: mkPoint(cx + s * tp * 0.45, y))
				vane.addLine(to: mkPoint(cx + s * tp * 0.25, y - tp * 0.15))
				vane.move(to: mkPoint(cx + s * tp * 0.45, y))
				vane.addLine(to: mkPoint(cx + s * tp * 0.25, y + tp * 0.15))
			case .stormSiren:
				if g.sirenLevel > 0.01 || (g.settings.weatherOn && g.sirenWorthy()) {
					let on: Bool = Int(g.clock * 3.0) % 2 == 0
					if on { beacon.addEllipse(in: mkRect(cx - tp * 0.7, top - tp * 0.5, tp * 1.4, tp * 1.0)) }
				}
			case .rainBarrel, .rainCistern:
				let cap: Double = d.t == .rainBarrel ? 8 : 32
				let f: Double = clampD((g.weather.store[g.deviceKey(d)] ?? 0) / cap, 0, 1)
				if f > 0.02 {
					let inner: Double = tp * 0.7
					let h: Double = max(2.0, tp * 0.75 * f)
					water.addRect(mkRect(cx - inner * 0.5, top + tp - h - tp * 0.05, inner, h))
				}
			case .weatherStation, .dopplerStation:
				if Int(g.clock * 1.5) % 3 != 0 { glow.addRect(mkRect(cx - tp * 0.32, top + tp * 0.55, tp * 0.64, tp * 0.2)) }
			default:
				break
			}
		}
		ctx.stroke(blades, with: .color(Color(hex: 0xF0F2F4)), lineWidth: max(2.0, tp * 0.12))
		ctx.stroke(vane, with: .color(Color(hex: 0xD2793A)), lineWidth: max(1.5, tp * 0.08))
		ctx.fill(water, with: .color(Color(hex: 0x3B7BE0, alpha: 0.85)))
		ctx.fill(glow, with: .color(Color(hex: 0x70F0B0, alpha: 0.5)))
		ctx.fill(beacon, with: .color(Color(hex: 0xFF3020, alpha: 0.45)))
	}
}

// MARK: - Weather settings, the station's screen, the journal's weather pages

/// Weather options, shared by the main settings screen and the pause menu. Every kind of weather
/// has its own switch; the first switch turns all of it off at once.
struct WeatherSettingsSection: View {
	@Binding var settings: Settings
	var onChange: () -> Void = {}

	func label(_ s: String, _ v: String) -> some View {
		Text(verbatim: joinText(s, ": ", v)).font(.pixel(12, .bold))
	}

	var freqName: String {
		switch settings.severeFrequency {
		case 0: return "rare"
		case 2: return "frequent"
		default: return "normal"
		}
	}

	func freqButton(_ i: Int, _ title: String) -> some View {
		SmallButton(title: title, color: settings.severeFrequency == i ? Color(hex: 0x4E8A3E) : Color(hex: 0x555555)) {
			settings.severeFrequency = i
			onChange()
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("WEATHER").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			Toggle("Weather (all of it)", isOn: $settings.weatherOn)
			if settings.weatherOn {
				Toggle("Rain and snow", isOn: $settings.allowRain)
				Toggle("Thunderstorms and lightning", isOn: $settings.allowThunder)
				Toggle("Wind", isOn: $settings.allowWind)
				Toggle("Hail", isOn: $settings.allowHail)
				Toggle("Blizzards", isOn: $settings.allowBlizzard)
				Toggle("Tornadoes", isOn: $settings.allowTornado)
				Toggle("Hurricanes (near the sea)", isOn: $settings.allowHurricane)
				Text("WEATHER DAMAGE").font(.pixel(12)).foregroundColor(Color(hex: 0xFFE066))
				Toggle("Hurts the player", isOn: $settings.weatherHurtsPlayer)
				Toggle("Damages blocks and buildings", isOn: $settings.weatherHurtsBlocks)
				Toggle("Hurts creatures", isOn: $settings.weatherHurtsCreatures)
				label("Intensity", joinText(String(Int((settings.weatherIntensity * 100.0).rounded())), "%"))
				Slider(value: $settings.weatherIntensity, in: 0.25...1.5, step: 0.05)
				label("Severe weather", freqName)
				HStack(spacing: 6) {
					freqButton(0, "RARE")
					freqButton(1, "NORMAL")
					freqButton(2, "FREQUENT")
				}
				Toggle("Weather alerts and warnings", isOn: $settings.weatherAlerts)
				label("Rain, snow and hail drawn", joinText(String(Int((settings.weatherParticles * 100.0).rounded())), "%"))
				Slider(value: $settings.weatherParticles, in: 0.2...1.0, step: 0.05)
				Toggle("Gentler lightning flashes", isOn: $settings.reduceFlashes)
			}
			SmallButton(title: "RESET WEATHER DEFAULTS") {
				settings.resetWeather()
				onChange()
			}
		}
		.font(.pixel(13, .bold))
		.foregroundColor(Color.white)
	}
}

/// How dangerous nights are, and when wiring is drawn
struct NightSettingsSection: View {
	@Binding var settings: Settings

	func choice(_ title: String, _ on: Bool, _ act: @escaping () -> Void) -> some View {
		SmallButton(title: title, color: on ? Color(hex: 0x4E8A3E) : Color(hex: 0x555555), action: act)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("NIGHTS").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			Text("How many monsters come out at night, and how quickly").font(.pixel(11, .semibold))
			HStack(spacing: 6) {
				choice("CALM", settings.nightDanger == 0) { settings.nightDanger = 0 }
				choice("NORMAL", settings.nightDanger == 1) { settings.nightDanger = 1 }
				choice("DEADLY", settings.nightDanger == 2) { settings.nightDanger = 2 }
			}
			Text("POWER WIRING").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			HStack(spacing: 6) {
				choice("WHEN BUILDING", settings.showWires == 0) { settings.showWires = 0 }
				choice("ALWAYS", settings.showWires == 1) { settings.showWires = 1 }
				choice("FAINT", settings.showWires == 2) { settings.showWires = 2 }
			}
			buildingPart
		}
		.font(.pixel(13, .bold))
		.foregroundColor(Color.white)
	}

	var buildingPart: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("BUILDINGS").font(.pixel(15)).foregroundColor(Color(hex: 0xFFE066))
			Toggle("Structural physics", isOn: $settings.structural)
			Text("Blocks you build need support: each holds up so much weight and reaches out so far (shown in its info). Too far out or too heavy, it cracks and falls. The land itself never falls.").font(.pixel(11, .semibold))
			Toggle("Vehicle damage", isOn: $settings.vehicleDamage)
			Text("Shots, blasts and crashes damage vehicles: parts crack and break off. Hold an iron bar and tap a part to mend it.").font(.pixel(11, .semibold))
		}
	}
}

/// A weather station's screen, read live from the simulation
struct WeatherPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var body: some View {
		let lines: [StationLine] = game.stationReport()
		let title: String = game.stationAt?.t == .dopplerStation ? "DOPPLER STATION" : "WEATHER STATION"
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(verbatim: title).font(.pixel(17)).foregroundColor(Color(hex: 0x70F0B0))
				Spacer()
				SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) {
					game.showWeather = false
					game.bumpHUD()
				}
			}
			ForEach(0..<lines.count, id: \.self) { i in
				HStack(alignment: .top, spacing: 8) {
					if let k = lines[i].kind {
						Art.shared.weatherIcon(k, lines[i].snow).resizable().frame(width: 24, height: 24)
					} else {
						Color.clear.frame(width: 24, height: 24)
					}
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: lines[i].text).font(.pixel(13)).foregroundColor(Color(hex: lines[i].color))
						if !lines[i].sub.isEmpty {
							Text(verbatim: lines[i].sub).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xA8C8B8))
						}
					}
				}
			}
		}
		.padding(16)
		.background(PixelBox(color: Color(hex: 0x14201C)).opacity(0.96))
		.frame(maxWidth: 560)
		.padding(16)
	}
}

/// The weather a player has lived through, and the notes they have made about it
struct WeatherJournalPage: View {
	let game: Game
	let ink: Color
	var body: some View {
		let storms: [StormRecord] = game.journal.storms ?? []
		let notes: [String] = game.journal.lore.filter { $0.hasPrefix("wx.") }
		return VStack(alignment: .leading, spacing: 8) {
			Text("STORMS WEATHERED").font(.pixel(13)).foregroundColor(ink)
			if storms.isEmpty {
				Text("None yet. Severe weather is rare; a weather station shows what is coming.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<storms.count, id: \.self) { i in
				let s: StormRecord = storms[storms.count - 1 - i]
				let name: String = (WeatherKind(rawValue: s.kind) ?? .thunderstorm).name
				HStack {
					Text(verbatim: name).font(.pixel(12)).foregroundColor(ink)
					Text(verbatim: s.note).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0x6A4A2A))
					Spacer()
					Text(verbatim: joinText("day ", String(s.day))).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0x6A4A2A))
				}
			}
			Text("WEATHER NOTES").font(.pixel(13)).foregroundColor(ink).padding(.top, 6)
			if notes.isEmpty {
				Text("What you learn about lightning, wind, hail and storms is written down here as you meet them.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<notes.count, id: \.self) { i in
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: loreEntry(notes[i]).0).font(.pixel(12)).foregroundColor(ink)
					Text(verbatim: loreEntry(notes[i]).1).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0x5A3A1A))
				}
			}
		}
	}
}

extension Game {
	/// Writes a weather note into the journal the first time the player meets that kind of weather
	func learnWeather(_ key: String) {
		if journal.lore.contains(key) { return }
		journal.lore.append(key)
		if settings.weatherAlerts { floatText("New note in your journal", pb.x, pb.y - pb.h - 1.0, 0xE8D8A0) }
	}

	/// Notes worth writing down from what is happening now (checked about once a second)
	func checkWeatherNotes() {
		if !settings.weatherOn || world.dim != .overworld { return }
		let L: LocalWeather = wxHere
		if let e = weather.tornado, e.phase >= 1, abs(e.x - pb.x) < 120 { learnWeather("wx.tornado") }
		if L.hurricane > 0.3 { learnWeather("wx.hurricane") }
		if weather.kind == .blizzard && settings.allowBlizzard && L.snow && L.precip > 0.4 { learnWeather("wx.blizzard") }
		if L.hail > 0.2 { learnWeather("wx.hail") }
		if abs(L.wind) > 9 { learnWeather("wx.wind") }
		if L.thunder > 1.0 { learnWeather("wx.lightning") }
		if bodyCold > 0.5 { learnWeather("wx.cold") }
	}

	/// Debug: make a kind of weather begin now (an event starts with its usual warning)
	func debugForceWeather(_ k: WeatherKind) {
		if !settings.weatherOn {
			say("Weather is switched off in Settings.", 2.0)
			return
		}
		weather.tornado = nil
		weather.hurricane = nil
		weather.kind = k
		weather.stateT = 0
		weather.stateDur = weather.pick(k.spell)
		weather.plan.removeAll()
		clearWeatherFX()
		if k == .tornado {
			if settings.allowTornado { spawnTornado() } else { say("Tornadoes are switched off in Settings.", 2.0) }
		}
		if k == .hurricane {
			if settings.allowHurricane {
				var ctx: WeatherContext = weatherContext()
				// debug storms come in anywhere: with no sea in reach, the "coast" is put to the east
				if ctx.seaSide == 0 {
					ctx.seaSide = 1
					ctx.coastX = pb.x + 60
				}
				spawnHurricane(ctx)
			} else {
				say("Hurricanes are switched off in Settings.", 2.0)
			}
		}
		if k == .hailstorm { weather.bigHail = true }
		// the amounts jump most of the way there, so the change can be seen at once
		let p: WeatherProfile = allowedProfile(k)
		weather.cloud = p.cloud
		weather.precip = p.precip * 0.8
		weather.cover = max(p.cover, 0.6)
		weather.thunder = p.thunder
		weather.hail = p.hail
		weather.chill = p.chill
		weather.wind = p.wind * weather.windDir
		fillPlan()
		say(joinText("Weather: ", weatherLabel(k, snow: wxHere.snow)), 1.5)
	}

	/// Counts the monsters that hold a place right now (the same count the spawner uses)
	func monstersAbout() -> Int {
		var n: Int = 0
		for m in mobs where m.hp > 0 && !m.removed && m.def.hostile && !m.kind.isPredator && !m.tame && !m.persistent && !m.isBoss && m.boat < 0 && m.lair == 0 {
			if abs(m.b.x - pb.x) <= 72 && abs(m.b.y - pb.y) <= 56 { n += 1 }
		}
		return n
	}

	func spawnDebugLines() -> [String] {
		var out: [String] = []
		let place: String = world.dim == .umbral ? "umbral" : (Int(pb.y) - gen.col(Int(floor(pb.x))).h > 18 ? "cave" : "surface")
		let cap: Int = monsterCap(place == "surface" ? .surface : .cave)
		out.append(joinText(isNight ? "Night" : "Day", "  ", place, "  monsters ", String(monstersAbout()), " / ", String(cap), String(format: "  next in %.1fs", max(0, monsterSpawnCD))))
		if !spawnLast.isEmpty { out.append(joinText("Last attempt: ", spawnLast)) }
		let top: [(String, Int)] = spawnLog.sorted { $0.value > $1.value }.prefix(6).map { ($0.key, $0.value) }
		for t in top { out.append(joinText("  ", t.0, " ×", String(t.1))) }
		return out
	}

	/// Debug: makes it night and runs forty spawn attempts at once (the pacing between monsters is
	/// skipped), then reports what came out and what stopped the rest
	func debugSpawnTest() {
		if world.dim == .overworld { debugSetTime(0.62) }
		spawnLog = [:]
		let before: Set<Int> = Set(mobs.map { $0.id })
		for _ in 0..<40 {
			spawnTimer = 0
			monsterSpawnCD = 0
			updateSpawning(0.0)
		}
		var made: [String: Int] = [:]
		for m in mobs where !before.contains(m.id) && m.def.hostile { made[m.def.name, default: 0] += 1 }
		let list: String = made.isEmpty ? "no monsters" : made.sorted { $0.value > $1.value }.map { joinText(String($0.value), " ", $0.key) }.joined(separator: ", ")
		say(joinText("Spawn test: ", list), 4.0)
		bumpHUD()
	}

	func debugStrikeNearby() {
		if !settings.weatherOn || !settings.allowThunder {
			say("Lightning is switched off in Settings.", 2.0)
			return
		}
		let x: Double = pb.x + Double(facing) * 6.0
		if let s = strikeSpot(x) { lightningStrike(s.0, s.1, rod: s.2) }
	}

	var weatherDebugLine: String {
		let k: WeatherKind = weather.kind
		let left: Int = Int(max(0, weather.stateDur - weather.stateT))
		let next: String = weather.plan.first?.kind.name ?? "-"
		return joinText(k.name, " ", String(left), "s → ", next, String(format: "  rain %.2f wind %.1f cl %.2f", weather.precip, weather.wind, weather.cloud))
	}
}

// MARK: - Ambient life

extension WorldRenderer {
	/// Fireflies over grass on clear nights; embers drifting up through the Umbral Realm. Drawn after
	/// the lighting so they glow in the dark. A handful of shapes, no particles.
	static func drawAmbientLife(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.world.dim == .umbral {
			var path: Path = Path()
			for i in 0..<24 {
				let fx: Double = hash2(i, 31, 13)
				let rise: Double = 1.2 + hash2(i, 32, 13) * 1.6
				let span: Double = v.hTiles + 4.0
				let wy: Double = v.top + span - 2.0 - (hash2(i, 33, 13) * span + g.clock * rise).truncatingRemainder(dividingBy: span)
				let wx: Double = v.left + fx * v.wTiles + sin(g.clock * 0.8 + Double(i) * 1.9) * 0.8
				let s: Double = i % 5 == 0 ? 3.0 : 2.0
				path.addRect(mkRect(v.sx(wx), v.sy(wy), s, s))
			}
			ctx.fill(path, with: .color(Color(hex: 0xFF9A4A, alpha: 0.55)))
			return
		}
		let tp: Double = v.tp
		for f in fireflySpots(g, v) {
			let x: Double = v.sx(f.0)
			let y: Double = v.sy(f.1)
			let blink: Double = f.2
			fillOval(&ctx, mkRect(x - tp * 0.22, y - tp * 0.22, tp * 0.44, tp * 0.44), Color(hex: 0xE8FF8A, alpha: 0.18 * blink))
			fillRect(&ctx, mkRect(x - 1.5, y - 1.5, 3, 3), Color(hex: 0xF4FFC0, alpha: 0.9 * blink))
		}
	}

	/// Where the fireflies are now (x and y in blocks, and how bright): at most one for every 6 columns,
	/// each at a place of its own in the world (it drifts a little around it, but never follows the
	/// player), over grass on clear nights in the overworld
	static func fireflySpots(_ g: Game, _ v: View2D) -> [(Double, Double, Double)] {
		var out: [(Double, Double, Double)] = []
		if g.dayFactor > 0.3 || g.weatherRain > 0.5 || g.world.dim != .overworld { return out }
		let c0: Int = Int(floor(v.left / 6.0)) - 1
		let c1: Int = Int(floor((v.left + v.wTiles) / 6.0)) + 1
		for cell in c0...max(c0, c1) {
			if hash2(cell, 20, 9) > 0.55 { continue }
			let i: Int = cell
			let wx: Double = Double(cell) * 6.0 + hash2(cell, 21, 9) * 6.0 + sin(g.clock * 0.4 + Double(i)) * 1.2
			let ix: Int = Int(floor(wx))
			let b: Biome = g.gen.col(ix).biome
			if !(b == .forest || b == .plains || b == .swamp || b == .jungle) { continue }
			let ground: Double = Double(g.world.surfaceY(ix))
			let wy: Double = ground - 1.0 - hash2(i, 22, 9) * 4.0 + sin(g.clock * 0.7 + Double(i) * 1.7) * 0.6
			if wy >= Double(g.world.skyTop(ix)) || !v.visible(wx, wy, 1) { continue }
			let blink: Double = 0.5 + 0.5 * sin(g.clock * 2.2 + Double(i) * 1.3)
			if blink < 0.25 { continue }
			out.append((wx, wy, blink))
		}
		return out
	}
}

// MARK: - Journal: places found, what they tell, and goals worth chasing

struct JournalPlace: Codable {
	var key: String
	var name: String
	var x: Int
	var day: Int
	var dim: Int
}

/// What the player has found and learned. Saved with the world (older saves start with an empty one).
struct Journal: Codable {
	var places: [JournalPlace] = []
	/// lore entries unlocked, in the order they were found
	var lore: [String] = []
	var relics: Int = 0
	/// names of things the player has crafted (for the goals list)
	var crafted: [String] = []
	/// storms lived through (nil in journals saved before the weather)
	var storms: [StormRecord]? = nil

	func has(_ key: String) -> Bool { return places.contains { $0.key == key } }
	func hasKind(_ prefix: String) -> Bool { return places.contains { $0.key.hasPrefix(prefix) } }
	func count(_ prefix: String) -> Int { return places.filter { $0.key.hasPrefix(prefix) }.count }
}

/// The story each kind of place tells, a line or two each
func loreEntry(_ key: String) -> (String, String) {
	switch key {
	case "ruin.house": return ("A Ruined House", "A cellar ladder, a cold hearth, a child's carving of a bear above the door. Whoever lived here left in a hurry, and went down rather than out.")
	case "ruin.tower": return ("A Ruined Tower", "The watch log's last entry: 'Lights under the hill again. Nobody goes down there now.'")
	case "ruin.fort": return ("An Old Fort", "Every arrowhead in these walls points outward and down. Whatever they fought came up out of the caves.")
	case "ruin.camp": return ("An Abandoned Camp", "Bedrolls for four, supplies for one. The tracks lead toward the mountains and do not come back.")
	case "ruin.overgrown": return ("An Overgrown Ruin", "Roots have split a shrine stone. Its carving shows a door torn open in the sky, and a hooded figure standing in it.")
	case "ruin.bunker": return ("A Buried Bunker", "Iron doors, rusted from the inside. Someone hoarded powder and shot for a war that never reached them.")
	case "mine": return ("An Old Mine", "A tally scratched into a support beam stops at forty-one. Under it, in a different hand: 'The rock sings this deep.'")
	case "grotto": return ("A Crystal Grotto", "The crystals hum when you stand still. Something set them here, and something keeps them.")
	case "lair.bear": return ("The Bear's Den", "Claw marks ring the stones. The great bear sleeps on a seal it was set to guard, and the key to that seal sleeps with it.")
	case "lair.rex": return ("The Bone Nest", "Ribs older than the hills. Whatever crowned itself with these bones still nests among them.")
	case "portal": return ("The Sealed Gate", "A chamber built around a door, deep under the earth, and a key-shaped hollow worn smooth by many hands.")
	case "umbral": return ("The Umbral Realm", "No sky, no sun, only ash and ember. The rift hums behind you. It is not the only door that was opened.")
	case "citadel": return ("The Warden's Citadel", "Carved over the gate: HERE THE WARDEN KEEPS THE DOOR, HOLLOW SINCE THE RIFT TORE OPEN.")
	case "sentinel": return ("The Sentinel", "It came apart into shards that still glow. It was not alive, but it was waiting, and it was told what to guard.")
	case "warden": return ("The Hollow Warden", "There was nothing inside the armour. Its heart is warm and beats slowly. A rift forge could bind it into something worn.")
	case "wx.lightning": return ("Notes on Lightning", "It strikes the highest thing near it: a tree top, a roof, a hill. There is a moment first, when the air crackles and your hair stands up. A copper rod standing high takes every strike within fourteen blocks safely into the ground.")
	case "wx.wind": return ("Notes on Wind", "A strong wind carries arrows and loose things with it and leans on you as you walk. A vane shows where it blows from; a turbine stores it up.")
	case "wx.hail": return ("Notes on Hail", "Most hail only bruises crops and flowers. Now and then it falls as big as eggs: then glass breaks and bare heads ache. A roof, or a helmet, is enough.")
	case "wx.blizzard": return ("Notes on Blizzards", "It is the wind on you that does the harm. A fire or a heater, a roof and walls, a good coat: any of them buys time. Snow boots keep you on your feet.")
	case "wx.cold": return ("Notes on the Cold", "Cold country, high ground and night all draw the warmth out of you, the wind and wet most of all. Stand by a fire to get it back.")
	case "wx.tornado": return ("Notes on Tornadoes", "They grow out of the worst thunderstorms and travel with the wind. Underground, or behind reinforced walls, you will hear it pass and little more. Out in the open it will pick you up.")
	case "wx.hurricane": return ("Notes on Hurricanes", "They come off the sea in walls of wind and rain. The calm in the middle is the eye; then the wind comes back from the other side. Sandbags hold back the sea, shutters save the windows.")
	default: return ("", "")
	}
}

struct JournalAim {
	var title: String
	var hint: String
	var done: Bool
}

extension Game {
	/// Goals the world offers, in roughly the order they open up. None is required; each says how to
	/// get going on it.
	func journalAims() -> [JournalAim] {
		let j: Journal = journal
		let bear: Bool = defeated.contains { $0 >= 0 && $0 < 1_000_000 }
		let rexDown: Bool = defeated.contains { $0 >= 1_000_000 && $0 < 2_000_000 }
		let sentinel: Bool = defeated.contains { $0 >= 6_000_000 && $0 < 8_000_000 }
		let sigil: Bool = j.crafted.contains(Gear.wardenSigil.name) || wearing(.wardenSigil) || inv.total(.gear(.wardenSigil)) > 0
		return [
			JournalAim(title: "Set up a workbench", hint: "Eight planks. Chop a tree with your hands or an axe, then make planks from the logs.", done: j.crafted.contains("Workbench")),
			JournalAim(title: "Forge iron on an anvil", hint: "Smelt iron ore in a furnace, then build an anvil (6 iron bars, 4 stone) at the workbench.", done: j.crafted.contains("Anvil")),
			JournalAim(title: "Explore an old mine", hint: "Look for a timber headframe over a covered shaft. The treasure map marks them.", done: j.hasKind("mine:")),
			JournalAim(title: "Find a crystal grotto", hint: "Deep underground, sometimes with a cave mouth leading down.", done: j.hasKind("grotto:")),
			JournalAim(title: "Defeat Ursavor", hint: "The great bear's den holds the Portal Key.", done: bear),
			JournalAim(title: "Open the sealed gate", hint: "The Portal Key opens the rift chamber far below the surface. The treasure map narrows it down.", done: portalOpened),
			JournalAim(title: "Defeat Tyrannax", hint: "Something nests among enormous bones in the jungle.", done: rexDown),
			JournalAim(title: "Silence a Crystal Sentinel", hint: "Each grotto has a guardian. Its shards are worth the fight.", done: sentinel),
			JournalAim(title: "Reach the Warden's citadel", hint: "In the Umbral Realm, several hundred blocks from the rift.", done: j.has("citadel")),
			JournalAim(title: "Defeat the Hollow Warden", hint: "Watch the ground: its strikes are marked before they land.", done: defeated.contains(WorldGen.wardenKey)),
			JournalAim(title: "Forge the Warden's Sigil", hint: "The Warden's heart, 4 voidium bars and 4 crystal shards at a rift forge.", done: sigil),
			JournalAim(title: "Recover relic fragments (\(min(j.relics, 10))/10)", hint: "Found in ruins, mines, grottos and with the bosses.", done: j.relics >= 10),
		]
	}

	func discover(_ key: String, _ name: String, _ x: Int, lore: String) {
		if journal.has(key) { return }
		journal.places.append(JournalPlace(key: key, name: name, x: x, day: dayCount, dim: world.dim.rawValue))
		var line: String = "Discovered: " + name + "."
		if !lore.isEmpty && !journal.lore.contains(lore) {
			journal.lore.append(lore)
			line += " (New journal entry)"
		}
		say(line, 3.5)
		sfx(.discovery, 0.8)
		spawnParticles(pb.x, pb.y - pb.h - 0.4, 0xFFE070, 10, 2.5, 0.8, -3)
		bumpHUD()
	}

	func addLore(_ key: String) {
		if !journal.lore.contains(key) { journal.lore.append(key) }
	}

	/// Checks twice a second whether the player has walked into a place worth noting
	func updateDiscoveries(_ dt: Double) {
		discoverT -= dt
		if discoverT > 0 || dead { return }
		discoverT = 0.5
		let px: Int = Int(floor(pb.x))
		let py: Double = pb.y
		if world.dim == .umbral {
			if !journal.has("umbral") { discover("umbral", "The Umbral Realm", px, lore: "umbral") }
			if let c = gen.citadel, abs(px - c.x) < 42 && abs(py - Double(c.floor)) < 14 {
				discover("citadel", "The Warden's Citadel", c.x, lore: "citadel")
			}
			return
		}
		if world.dim != .overworld { return }
		for r in gen.rareSites(overlapping: px - 20, px + 20) where abs(px - r.x) < 14 && abs(py - Double(gen.col(r.x).h)) < 14 {
			let k: String = "\(r.kind)"
			discover("ruin:\(r.cell)", rareName(r.kind), r.x, lore: "ruin." + k)
		}
		for m in gen.mineSites(overlapping: px - 6, px + 6) where px >= m.x - 3 && px <= m.x + 5 && py > Double(m.ground - 6) && py < Double(m.bottom + 2) {
			discover("mine:\(m.cell)", "Old Mine", m.x, lore: "mine")
		}
		for gs in gen.grottoSites(overlapping: px - 2, px + 2) where abs(px - gs.x) < gs.rx && abs(py - Double(gs.floorY)) < Double(gs.ry + 2) {
			discover("grotto:\(gs.cell)", "Crystal Grotto", gs.x, lore: "grotto")
		}
		for L in gen.lairCenters(near: px) where abs(px - L.cx) < 40 {
			discover("lair:\(L.kind):\(L.k)", L.kind == .bear ? "The Bear's Den" : "The Bone Nest", L.cx, lore: L.kind == .bear ? "lair.bear" : "lair.rex")
		}
		if abs(px - gen.portalX) < 12 && abs(py - Double(gen.portalY)) < 10 {
			discover("portal", "The Sealed Gate", gen.portalX, lore: "portal")
		}
	}
}

// MARK: - Animal life: herds, rest, water, predators and prey

/// Animals that predators hunt
func isPrey(_ k: MobKind) -> Bool {
	switch k {
	case .pig, .cow, .sheep, .chicken, .giraffe, .frog: return true
	default: return false
	}
}

extension Game {
	/// Herding, sleeping at night, walking to water to drink and running from hunting predators. It
	/// looks around about once a second (not every frame) and uses the creature grid for neighbours.
	/// Returns true when it moved the animal this frame (the caller then skips plain wandering).
	func animalLife(_ m: Mob, _ dt: Double) -> Bool {
		if m.poseT > 0 { m.poseT -= dt }
		if m.drinkT > 0 { m.drinkT -= dt }
		m.thinkT -= dt
		if m.thinkT <= 0 {
			m.thinkT = Double.random(in: 0.8...1.4)
			// a hunting predator close by: run
			for o in mobsNear(m.b.x - 10, m.b.x + 10) where o.hp > 0 && o !== m && o.preyID != 0 && !o.tame {
				if abs(o.b.x - m.b.x) < 10 && abs(o.b.y - m.b.y) < 4 {
					m.t2 = 3.0
					m.tx = o.b.x
					m.goal = 0
					return false
				}
			}
			// in a downpour, hail or a gale, animals out in the open head for cover (a tree, a roof)
			if m.goal == 0 && world.dim == .overworld && settings.weatherOn && abs(m.b.x - pb.x) < 60 {
				let bad: Bool = precipAt(m.b.x) > 0.55 || wxHere.hail > 0.2 || abs(wxHere.wind) > 11 || weather.tornado != nil
				if bad && rainReaches(m.b.x, m.b.y, m.b.h), let cx = coverNear(m, 14) {
					m.goal = 3
					m.goalX = cx
				}
			}
			// the herd and the water hole wait for daylight; at night animals settle where they are
			if m.goal == 0 && !(isNight && world.dim == .overworld) {
				if m.drinkT <= 0 && Double.random(in: 0...1) < 0.15, let wx = waterNear(m, 12) {
					m.goal = 1
					m.goalX = wx
				} else if Double.random(in: 0...1) < 0.3 {
					// drift back toward the rest of the herd
					var sum: Double = 0
					var n: Int = 0
					for o in mobsNear(m.b.x - 18, m.b.x + 18) where o.kind == m.kind && o !== m && o.hp > 0 && !o.tame {
						sum += o.b.x
						n += 1
					}
					if n > 0 {
						let cx: Double = sum / Double(n)
						if abs(cx - m.b.x) > 7 { m.goal = 2; m.goalX = cx }
					}
				}
			}
		}
		if m.goal != 0 {
			let dx: Double = m.goalX - m.b.x
			if (abs(dx) < 1.2 && m.goal != 3) || abs(dx) < 0.5 || (m.goal == 2 && abs(dx) < 4) {
				if m.goal == 3 {
					// sheltering: stand still under cover a while
					m.poseT = 6.0
					m.st = 0
				}
				if m.goal == 1 {
					// drinking: head down for a few seconds
					m.drinkT = Double.random(in: 25...45)
					m.poseT = 3.0
					m.st = 0
					m.t1 = 3.2
				}
				m.goal = 0
			} else {
				m.dir = dx > 0 ? 1 : -1
				// the water itself reads as a drop just before the edge; that is where it was going
				let edge: Bool = m.goal == 1 && abs(dx) < 2.5
				if (cliffAhead(m, m.dir) && !edge) || (m.b.hitWall && !m.b.onGround) {
					m.goal = 0
				} else {
					accelX(m, Double(m.dir) * m.def.speed * 0.6, 14, dt)
					if m.b.hitWall && m.b.onGround { m.b.vy = -m.def.jump }
					return true
				}
			}
		}
		if m.poseT > 0 {
			accelX(m, 0, 18, dt)
			return true
		}
		// at night farm animals mostly settle down and sleep
		if isNight && world.dim == .overworld && m.kind != .frog {
			if m.st == 1 && Double.random(in: 0...1) < 0.02 { m.st = 0; m.t1 = Double.random(in: 4...9) }
			if m.st == 0 {
				m.t1 -= dt
				if m.t1 <= 0 { m.st = 1; m.t1 = Double.random(in: 0.8...1.6); m.dir = Bool.random() ? 1 : -1 }
				accelX(m, 0, 18, dt)
				return true
			}
		}
		return false
	}

	/// The nearest column with cover overhead (leaves, a roof) at about the animal's own level
	func coverNear(_ m: Mob, _ r: Int) -> Double? {
		let x0: Int = Int(floor(m.b.x))
		let feet: Double = m.b.y
		var k: Int = 1
		while k <= r {
			for side in [1, -1] {
				let x: Int = x0 + side * k
				if !rainReaches(Double(x) + 0.5, feet, m.b.h) && world.groundBelow(x, Int(floor(feet)) - 1) <= Int(floor(feet)) + 1 {
					// a step further in, if that is covered too, so the whole body is under it
					let deeper: Int = x + side
					if !rainReaches(Double(deeper) + 0.5, feet, m.b.h) { return Double(deeper) + 0.5 }
					return Double(x) + 0.5
				}
			}
			k += 1
		}
		return nil
	}

	/// The nearest surface water within reach, as the column to stand at beside it
	func waterNear(_ m: Mob, _ r: Int) -> Double? {
		let x0: Int = Int(floor(m.b.x))
		let gy: Int = Int(floor(m.b.y))
		var k: Int = 1
		while k <= r {
			for side in [1, -1] {
				let x: Int = x0 + side * k
				for dy in -2...2 where world.tile(x, gy + dy) == .water {
					return Double(x - side) + 0.5
				}
			}
			k += 2
		}
		return nil
	}

	/// Predators (wolves at night, big cats and bears any time the player isn't their target) run down
	/// prey nearby, bite it, and rest after a kill. Returns true while it has prey to chase.
	func hunt(_ m: Mob, _ dt: Double, _ allowed: Bool) -> Bool {
		if m.poseT > 0 {
			// resting after a meal
			m.poseT -= dt
			accelX(m, 0, 18, dt)
			return true
		}
		var prey: Mob? = nil
		if m.preyID != 0 {
			if let o = m.prey, o.id == m.preyID, o.hp > 0, !o.removed { prey = o }
			if prey == nil {
				// the prey is gone: rest, and stay sated for a while
				m.preyID = 0
				m.poseT = 4.0
				m.drinkT = 60.0
				return true
			}
		}
		m.thinkT -= dt
		if prey == nil && allowed && m.thinkT <= 0 {
			m.thinkT = Double.random(in: 1.5...3.0)
			var bd: Double = 14
			for o in mobsNear(m.b.x - 14, m.b.x + 14) where isPrey(o.kind) && o.hp > 0 && !o.tame && abs(o.b.y - m.b.y) < 4 {
				let d: Double = abs(o.b.x - m.b.x)
				if d < bd { bd = d; prey = o }
			}
			if let p = prey { m.preyID = p.id; m.prey = p }
		}
		guard let p = prey else { return false }
		if !allowed || abs(p.b.x - m.b.x) > 26 { m.preyID = 0; return false }
		chase(m, p.b.x, 1.05, dt)
		if m.kind == .wolf && m.b.onGround && abs(p.b.x - m.b.x) < 4 && Double.random(in: 0...1) < 0.03 { m.b.vy = -11; m.b.vx = Double(m.dir) * 7 }
		if m.cd <= 0 && abs(p.b.x - m.b.x) < m.b.w * 0.5 + p.b.w * 0.5 + 0.4 && abs(p.b.y - m.b.y) < 1.4 {
			m.cd = 0.9
			m.atkT = Mob.atkDur
			hurtMob(p, m.def.dmg, Double(m.dir), 5, false)
			// the herd scatters
			for o in mobsNear(p.b.x - 10, p.b.x + 10) where o.kind == p.kind && o.hp > 0 { o.t2 = 3.0; o.tx = m.b.x }
		}
		return true
	}
}

// MARK: - Telegraphed attacks and the newer creatures' behaviour

/// Ground an attack is about to strike. Drawn as a pulsing warning that fills from the bottom as the
/// moment comes, so every telegraphed blow reads the same way and can be stepped out of.
struct DangerZone {
	var x0: Double
	var y0: Double
	var x1: Double
	var y1: Double
	/// seconds until the strike, and the whole wind-up
	var t: Double
	var dur: Double
	var color: UInt32
}

enum WardenAtk: Int {
	case none, sweep, bolts, blink, pillars, summon
}

extension WorldGen {
	/// the Hollow Warden's entry in the list of defeated bosses
	static let wardenKey: Int = 9_000_001
	/// a grotto's Crystal Sentinel in that list
	static func sentinelKey(_ cell: Int) -> Int { return 7_000_000 + cell }
}

extension Game {
	func warn(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ dur: Double, _ color: UInt32 = 0xFF3A2A) {
		if dangerZones.count >= 24 { dangerZones.removeFirst() }
		sfx(.warn, at: (x0 + x1) * 0.5, 0.6)
		dangerZones.append(DangerZone(x0: min(x0, x1), y0: min(y0, y1), x1: max(x0, x1), y1: max(y0, y1), t: dur, dur: max(0.05, dur), color: color))
	}

	func updateDangerZones(_ dt: Double) {
		if dangerZones.isEmpty { return }
		for i in dangerZones.indices { dangerZones[i].t -= dt }
		dangerZones.removeAll { $0.t <= 0 }
	}

	/// A creature's blow over a box; targets are pushed away from the creature
	func mobAttackBox(_ m: Mob, _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, dmg: Double, knock: Double, type: DamageType = .melee) {
		var info = DamageInfo(amount: dmg, type: type, source: .mob(m, faction(of: m)))
		info.knock = knock
		info.originX = m.b.x
		info.originY = m.b.cy
		info.key = newID()
		damageBox(min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1), info)
	}

	// MARK: cave crawler: fast, crouches and pounces

	func updateCrawler(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		switch m.st {
		case 3:
			// a short crouch before the pounce
			m.t3 -= dt
			accelX(m, 0, 50, dt)
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.7
				m.cd = 0
				m.b.vy = -8.5
				m.b.vx = Double(m.dir) * 10.5
				m.atkT = Mob.atkDur
			}
		case 4:
			m.t3 -= dt
			contactHurt(m, d.dmg * 1.3)
			if (m.b.onGround && m.t3 < 0.55) || m.t3 <= 0 {
				m.st = 0
				m.cd = 1.3
			}
		default:
			if aggro {
				chase(m, m.aimX, 1.0, dt)
				// scrambles up ledges
				if m.b.hitWall && m.b.onGround { m.b.vy = -11.5 }
				if m.ai == .chase && m.b.onGround && m.cd <= 0 && dist > 1.8 && dist < 4.6 && abs(dyP) < 2.0 {
					m.st = 3
					m.t3 = 0.28
				}
				if m.ai == .chase { contactHurt(m, d.dmg) }
			} else {
				wander(m, dt, 0.6)
			}
		}
		stepMob(m, dt)
	}

	// MARK: stone golem: slow, armoured, slams the ground and throws rocks

	func updateGolem(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		switch m.st {
		case 3:
			// fists raised: the slam lands where the warning shows
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.35
				let x0: Double = m.dir > 0 ? m.b.x - 0.6 : m.b.x - 3.9
				let x1: Double = m.dir > 0 ? m.b.x + 3.9 : m.b.x + 0.6
				mobAttackBox(m, x0, m.b.y - 2.4, x1, m.b.y + 0.1, dmg: d.dmg, knock: 10)
				m.atkT = Mob.atkDur
				addShake(dist < 10 ? 0.2 : 0.06)
				spawnParticles(m.b.x + Double(m.dir) * 2.2, m.b.y - 0.1, 0x8A8680, 10, 4.0, 0.5, 14)
			}
		case 4:
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 { m.st = 0; m.cd = 1.6 }
		case 5:
			// a boulder held overhead
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.t3 <= 0 {
				throwRock(m)
				m.st = 4
				m.t3 = 0.3
				m.cd = 2.8
			}
		default:
			if aggro {
				chase(m, m.aimX, 1.0, dt)
				if m.ai == .chase && m.cd <= 0 && m.b.onGround {
					if dist < 3.3 && abs(dyP) < 2.4 {
						m.st = 3
						m.t3 = 0.75
						m.dir = pb.x >= m.b.x ? 1 : -1
						let x0: Double = m.dir > 0 ? m.b.x - 0.6 : m.b.x - 3.9
						let x1: Double = m.dir > 0 ? m.b.x + 3.9 : m.b.x + 0.6
						warn(x0, m.b.y - 2.4, x1, m.b.y, 0.75, 0xFF8A2A)
					} else if dist > 4.5 && dist < 11 && Double.random(in: 0...(m.blockedT > 0 ? 0.3 : 1.0)) < 0.02
								&& world.lineClear(m.b.x, m.b.top - 1.5, pb.x, pb.y - pb.h * 0.6) {
						// lobbed, so it clears a low wall: thrown over anything it can see over
						m.st = 5
						m.t3 = 0.6
					}
				}
				if m.ai == .chase { contactHurt(m, d.dmg * 0.5) }
			} else {
				wander(m, dt, 0.35)
			}
		}
		stepMob(m, dt, stepUp: 1.0)
	}

	/// A lobbed boulder, aimed so its arc comes down on the player
	func throwRock(_ m: Mob) {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		let oy: Double = m.b.top + 0.2
		let dx: Double = pb.x - ox
		let t: Double = clampD(abs(dx) / 9.0, 0.5, 1.3)
		let grav: Double = 22.0
		let vx: Double = dx / t
		let vy: Double = ((pb.y - 0.8) - oy - 0.5 * grav * t * t) / t
		var p = Projectile(kind: .rock, x: ox, y: oy, vx: vx, vy: vy, dmg: m.def.dmg * 0.8, fromPlayer: false, gravity: grav)
		p.w = 0.6
		p.life = 3.0
		p.owner = m.id
		p.source = .mob(m, faction(of: m))
		p.uid = newID()
		projectiles.append(p)
		m.atkT = Mob.atkDur
	}

	// MARK: skeleton archer: keeps its distance and shoots arced arrows

	func updateArcher(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		switch m.st {
		case 3:
			// the draw: a clear moment to close in or take cover
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.t3 <= 0 {
				if clearShot(m) {
					shootArrowAtPlayer(m)
					m.st = 6
					m.t3 = 0.25
				} else if m.t3 < -0.8 {
					// the target went behind cover: the draw is let down, and next time it climbs for a
					// better spot (see think)
					m.st = 0
					m.cd = 0.4
					m.blockedT += 0.6
				}
			}
		case 6:
			m.t3 -= dt
			accelX(m, 0, 40, dt)
			if m.t3 <= 0 { m.st = 0; m.cd = Double.random(in: 1.4...2.2) }
		default:
			if aggro {
				// keeps its distance from the moment it notices the player; shoots once it is fighting
				let sees: Bool = m.sees && (m.ai == .chase || m.ai == .alert)
				if dist < 5.0 && sees {
					// too close: back off, hopping away now and then
					flee(m, pb.x, dt, 1.1)
					if m.b.onGround && Double.random(in: 0...1) < 0.025 { m.b.vy = -10; m.b.vx = Double(m.dir) * 5.5 }
				} else if dist > 12.0 || !sees || m.blockedT > 0.5 || !m.b.onGround {
					chase(m, m.aimX, 0.9, dt)
				} else {
					accelX(m, 0, 20, dt)
					m.dir = pb.x >= m.b.x ? 1 : -1
				}
				if m.ai == .chase && m.cd <= 0 && sees && m.b.onGround && dist >= 3.0 && dist < 18 && abs(dyP) < 10 {
					m.st = 3
					m.t3 = 0.6
				}
			} else {
				wander(m, dt, 0.4)
			}
		}
		stepMob(m, dt)
	}

	/// A clear line from where a shot leaves to the player's chest, checked at the moment of release
	func clearShot(_ m: Mob) -> Bool {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		return world.lineClear(ox, shotY(m), pb.x, shotAimY(m))
	}

	/// Where a creature's shot leaves (its shoulder) and the part of the player it aims for: the chest,
	/// or the head when only the head shows over cover
	func shotY(_ m: Mob) -> Double { return m.b.top + 0.45 }

	func shotAimY(_ m: Mob) -> Double {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		let chest: Double = pb.y - pb.h * 0.55
		if world.lineClear(ox, shotY(m), pb.x, chest) { return chest }
		return pb.top + 0.25
	}

	func shootArrowAtPlayer(_ m: Mob) {
		let ox: Double = m.b.x + Double(m.dir) * 0.6
		let oy: Double = shotY(m)
		let tx: Double = pb.x + pb.vx * 0.2
		let ty: Double = shotAimY(m)
		let grav: Double = 15.0
		let dx: Double = tx - ox
		let dy: Double = ty - oy
		let flight: Double = max(0.15, sqrt(dx * dx + dy * dy) / 19.0)
		var p = Projectile(kind: .arrow, x: ox, y: oy, vx: dx / flight, vy: dy / flight - 0.5 * grav * flight, dmg: m.def.dmg, fromPlayer: false, gravity: grav)
		p.life = 3.0
		p.w = 0.22
		p.owner = m.id
		p.source = .mob(m, faction(of: m))
		p.uid = newID()
		projectiles.append(p)
	}

	// MARK: mimic: a chest that bites

	func updateMimic(_ m: Mob, _ dt: Double, _ aggro: Bool, _ dist: Double, _ dyP: Double) {
		let d: MobDef = m.def
		m.t1 -= dt
		m.angry = aggro
		if m.st == 3 {
			// jaws wide before the lunge
			m.t3 -= dt
			accelX(m, 0, 30, dt)
			if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.6
				m.cd = 0
				m.b.vy = -9.5
				m.b.vx = Double(m.dir) * 9.0
				m.atkT = Mob.atkDur
			}
		} else if m.st == 4 {
			m.t3 -= dt
			if abs(dyP) < 1.4 { contactHurt(m, d.dmg * 1.2) }
			if (m.b.onGround && m.t3 < 0.45) || m.t3 <= 0 {
				m.st = 0
				m.cd = m.hp < m.maxHP * 0.4 ? 0.7 : 1.1
			}
		} else if aggro {
			m.dir = pb.x >= m.b.x ? 1 : -1
			if m.b.onGround {
				m.b.vx *= 0.8
				if m.cd <= 0 && dist < 5.0 && abs(dyP) < 2.2 {
					m.st = 3
					m.t3 = 0.3
				} else if m.t1 <= 0 {
					m.b.vy = -8.0
					m.b.vx = Double(m.dir) * 5.0
					m.t1 = 0.45
				}
			}
			if abs(dyP) < 1.4 { contactHurt(m, d.dmg * 0.6) }
		} else {
			// sits still and passes for a chest again
			accelX(m, 0, 20, dt)
		}
		stepMob(m, dt)
	}

	/// Some unopened chests underground in newer worlds are mimics: opening one wakes it instead
	func tryMimic(_ x: Int, _ y: Int) -> Bool {
		if world.dim != .overworld || gen.genVersion < 3 { return false }
		if y < WorldGen.sea + 20 { return false }
		// opened before, or placed by the player
		if world.chests[world.chestKey(x, y)] != nil { return false }
		if hash2(x, y, gen.seed &+ 909) >= 0.08 { return false }
		// a grotto's altar chest has its own guardian
		for s in gen.grottoSites(overlapping: x - 2, x + 2) where abs(x - s.x) <= 1 && abs(y - (s.floorY - 2)) <= 1 { return false }
		let loot: [Stack] = world.removeChest(x, y)
		world.set(x, y, .air)
		let m: Mob = addMob(.mimic, Double(x) + 0.5, Double(y) + 1.0)
		m.loot = loot
		m.persistent = true
		m.homeX = Double(x) + 0.5
		m.homeY = Double(y) + 1.0
		m.dir = pb.x >= m.b.x ? 1 : -1
		m.st = 3
		m.t3 = 0.45
		m.angry = true
		addShake(0.12)
		spawnParticles(m.b.x, m.b.y - 0.5, 0xB98A4E, 8, 4.0, 0.4, 12)
		say("The chest was a Mimic!", 2.5)
		return true
	}

	// MARK: crystal sentinel: the grotto's guardian

	func updateGuardians() {
		let px: Int = Int(floor(pb.x))
		for s in gen.grottoSites(overlapping: px - 60, px + 60) {
			let key: Int = WorldGen.sentinelKey(s.cell)
			if defeated.contains(key) { continue }
			var existing: Mob? = nil
			for m in mobs where m.kind == .sentinel && m.lair == key && m.hp > 0 { existing = m }
			let dx: Double = abs(Double(s.x) + 0.5 - pb.x)
			let dy: Double = abs(Double(s.floorY) - pb.y)
			if existing == nil {
				if dx < Double(s.rx) + 1 && dy < Double(s.ry) + 3 && !dead && world.isLoaded(s.x) {
					let m: Mob = addMob(.sentinel, Double(s.x) + 0.5, Double(s.floorY) - 3.0)
					m.lair = key
					m.homeX = Double(s.x) + 0.5
					m.homeY = Double(s.floorY)
					m.persistent = true
					m.phase = 1
					m.t1 = 1.5
					m.dir = pb.x >= m.b.x ? 1 : -1
					say("A Crystal Sentinel wakes to guard the grotto!", 3.0)
				}
			} else if let e = existing, dx > 90 || dy > 60 {
				// leaving resets the fight
				e.hp = 0
				e.removed = true
			}
		}
	}

	func updateSentinel(_ m: Mob, _ dt: Double) {
		let floorY: Double = m.homeY
		let toP: Double = pb.x - m.b.x
		let dist: Double = abs(toP)
		let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
		m.anim += dt * 2.5
		if m.phase < 2 && m.hp < m.maxHP * 0.55 && m.st != 1 {
			m.phase = 2
			say("The Crystal Sentinel flares with light!", 2.5)
			spawnParticles(m.b.x, m.b.cy, 0xD8FFFA, 24, 6.0, 0.7, 0)
		}
		var tx: Double = m.b.x
		var ty: Double = floorY - 2.8 + sin(clock * 1.7 + Double(m.id % 7)) * 0.5
		switch m.st {
		case 1:
			m.t2 -= dt
			m.tele = m.t2
			// dropping to the player's level before a dash
			if m.atk == 3 { ty = m.ty }
			if m.t2 <= 0 { m.tele = 0; executeSentinel(m) }
		case 2:
			m.t2 -= dt
			if m.t2 <= 0 { m.st = 0; m.t1 = m.phase == 2 ? Double.random(in: 0.9...1.4) : Double.random(in: 1.4...2.2) }
		case 5:
			// dashing straight through
			m.t2 -= dt
			m.b.vx = Double(m.dir) * 15.0
			m.b.vy = (m.ty - m.b.y) * 2.0
			if abs(dyP) < 1.8 { contactHurt(m, m.def.dmg * 1.3) }
			world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
			if m.t2 <= 0 || m.b.hitWall || abs(m.b.x - m.homeX) > 24 {
				m.st = 2
				m.t2 = 0.6
				m.b.vx *= 0.3
			}
			return
		default:
			m.dir = toP >= 0 ? 1 : -1
			if dead {
				tx = m.homeX
			} else {
				// keeps a few blocks off the player
				tx = pb.x - Double(m.dir) * 4.5
			}
			m.t1 -= dt
			if m.t1 <= 0 && !dead && dist < 28 { chooseSentinelAttack(m, dist) }
		}
		tx = clampD(tx, m.homeX - 20, m.homeX + 20)
		let sp: Double = m.def.speed * (m.phase == 2 ? 1.25 : 1.0)
		m.b.vx += (clampD((tx - m.b.x) * 1.8, -sp, sp) - m.b.vx) * min(1.0, dt * 3.0)
		m.b.vy += (clampD((ty - m.b.y) * 2.0, -sp * 1.5, sp * 1.5) - m.b.vy) * min(1.0, dt * 3.0)
		world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
		if !dead && abs(dyP) < 1.6 { contactHurt(m, m.def.dmg * 0.5) }
	}

	func chooseSentinelAttack(_ m: Mob, _ dist: Double) {
		let r: Double = Double.random(in: 0...1)
		let fy: Double = m.homeY
		m.dir = pb.x >= m.b.x ? 1 : -1
		if m.phase == 2 && r < 0.4 {
			// crystal spikes burst from the floor around the player
			m.atk = 2
			m.t2 = 0.95
			var xs: [Double] = []
			for k in -1...1 {
				let sx: Double = clampD(pb.x + Double(k) * 3.0 + Double.random(in: -0.5...0.5), m.homeX - 24, m.homeX + 24)
				xs.append(sx)
				warn(sx - 0.7, fy - 3.0, sx + 0.7, fy, 0.95, 0x5AF0F0)
			}
			m.spots = xs
		} else if r < 0.72 || dist > 9 {
			// a fan of shards
			m.atk = 1
			m.t2 = 0.6
		} else {
			// a dash along the player's level
			m.atk = 3
			m.t2 = 0.6
			m.ty = pb.y - 0.1
			warn(m.b.x, m.ty - 2.1, m.b.x + Double(m.dir) * 14.0, m.ty, 0.6, 0x5AF0F0)
		}
		m.st = 1
	}

	func executeSentinel(_ m: Mob) {
		let fy: Double = m.homeY
		switch m.atk {
		case 2:
			for sx in m.spots {
				mobAttackBox(m, sx - 0.7, fy - 3.0, sx + 0.7, fy + 0.1, dmg: 14, knock: 6, type: .impact)
				spawnParticles(sx, fy - 0.5, 0x8AF0E8, 8, 5.0, 0.5, 6)
			}
			m.spots = []
			addShake(0.12)
			m.st = 2
			m.t2 = 0.6
		case 3:
			m.st = 5
			m.t2 = 0.75
			m.atkT = Mob.atkDur
		default:
			let n: Int = m.phase == 2 ? 5 : 3
			let ox: Double = m.b.x + Double(m.dir) * 0.8
			let oy: Double = m.b.cy
			let aim: Double = atan2((pb.y - pb.h * 0.55) - oy, pb.x - ox)
			for k in 0..<n {
				let a: Double = aim + (Double(k) - Double(n - 1) * 0.5) * 0.17
				var p = Projectile(kind: .shard, x: ox, y: oy, vx: cos(a) * 13.0, vy: sin(a) * 13.0, dmg: 9, fromPlayer: false, gravity: 0)
				p.life = 3.0
				p.w = 0.25
				p.owner = m.id
				p.source = .mob(m, faction(of: m))
				p.uid = newID()
				projectiles.append(p)
			}
			m.atkT = Mob.atkDur
			spawnParticles(ox, oy, 0xD8FFFA, 6, 3.0, 0.25, 0)
			m.st = 2
			m.t2 = 0.5
		}
	}

	func onGuardianDefeated(_ m: Mob) {
		if m.lair != 0 { defeated.insert(m.lair) }
		dangerZones.removeAll()
		addShake(m.kind == .warden ? 0.6 : 0.35)
		spawnParticles(m.b.x, m.b.cy, m.kind == .warden ? 0xD8A8FF : 0x8AF0E8, 36, 8.0, 1.1, 6)
		addLore(m.kind == .warden ? "warden" : "sentinel")
		if m.kind == .warden {
			say("The Hollow Warden falls. Its heart still beats - a rift forge could bind it into a sigil.", 7.0)
		} else {
			say("The Crystal Sentinel shatters. The grotto is yours.", 4.5)
		}
	}

	// MARK: the Hollow Warden

	func updateWardenSpawn() {
		guard let c = gen.citadel else { return }
		let key: Int = WorldGen.wardenKey
		if defeated.contains(key) { return }
		var existing: Mob? = nil
		for m in mobs where m.kind == .warden && m.hp > 0 { existing = m }
		let dx: Double = abs(Double(c.x) + 0.5 - pb.x)
		let dy: Double = abs(Double(c.floor) - pb.y)
		if existing == nil {
			if dx < 30 && dy < 16 && !dead && world.isLoaded(c.throneX) {
				let m: Mob = addMob(.warden, Double(c.throneX) + 0.5, Double(c.floor) - 0.4)
				m.lair = key
				m.homeX = Double(c.x) + 0.5
				m.homeY = Double(c.floor)
				m.persistent = true
				m.phase = 1
				m.t1 = 2.0
				m.dir = pb.x >= m.b.x ? 1 : -1
				say("The Hollow Warden rises from its throne.", 4.0)
				sfx(.roar, at: m.b.x, 1.0)
			}
		} else if let e = existing, dx > 140 {
			e.hp = 0
			e.removed = true
			dangerZones.removeAll()
		}
	}

	func updateWarden(_ m: Mob, _ dt: Double) {
		let floorY: Double = m.homeY
		let toP: Double = pb.x - m.b.x
		let dist: Double = abs(toP)
		let dirP: Int = toP >= 0 ? 1 : -1
		m.anim += dt * 2.0
		let hpf: Double = m.hp / m.maxHP
		let want: Int = hpf > 0.66 ? 1 : (hpf > 0.33 ? 2 : 3)
		if want > m.phase && (m.st == 0 || m.st == 2) {
			m.phase = want
			m.st = 1
			m.atk = WardenAtk.summon.rawValue
			m.t2 = 1.3
			m.spots = []
			say(want == 2 ? "The Hollow Warden calls up its servants!" : "The Warden's lights burn white. The floor trembles.", 3.0)
			addShake(0.3)
		}
		let quick: Double = m.phase == 3 ? 0.72 : (m.phase == 2 ? 0.86 : 1.0)
		var tx: Double = m.b.x
		let ty: Double = floorY - 0.4 + sin(clock * 1.4) * 0.25
		switch m.st {
		case 1:
			m.t2 -= dt
			m.tele = m.t2
			if m.t2 <= 0 { m.tele = 0; executeWarden(m) }
		case 2:
			m.t2 -= dt
			if m.t2 <= 0 { m.st = 0; m.t1 = Double.random(in: 1.0...1.7) * quick }
		case 3:
			// bolts, one after another
			m.t2 -= dt
			m.dir = dirP
			if m.t2 <= 0 {
				fireWardenBolt(m)
				m.t3 -= 1
				if m.t3 <= 0 { m.st = 2; m.t2 = 0.5 } else { m.t2 = m.phase == 1 ? 0.2 : 0.15 }
			}
		default:
			m.dir = dirP
			if dead { tx = m.homeX } else if dist > 4.2 { tx = pb.x - Double(dirP) * 3.6 } else if dist < 2.2 { tx = pb.x - Double(dirP) * 3.0 }
			m.t1 -= dt
			if m.t1 <= 0 && !dead && dist < 44 { chooseWardenAttack(m, dist) }
		}
		tx = clampD(tx, m.homeX - 37, m.homeX + 37)
		let sp: Double = m.def.speed * (m.phase == 1 ? 1.0 : (m.phase == 2 ? 1.2 : 1.4))
		m.b.vx += (clampD((tx - m.b.x) * 2.0, -sp, sp) - m.b.vx) * min(1.0, dt * 4.0)
		m.b.vy += ((ty - m.b.y) * 3.0 - m.b.vy) * min(1.0, dt * 4.0)
		world.moveBody(&m.b, dt, stepUp: 0, dropThrough: false, decks: [])
		if !dead && dist < m.b.w * 0.5 + 0.5 && abs((pb.y - pb.h * 0.5) - m.b.cy) < 2.6 { contactHurt(m, 10) }
	}

	func startWardenSweep(_ m: Mob, _ tele: Double) {
		m.atk = WardenAtk.sweep.rawValue
		m.t2 = tele
		let reach: Double = 7.0
		let x0: Double = m.dir > 0 ? m.b.x - 0.8 : m.b.x - reach
		let x1: Double = m.dir > 0 ? m.b.x + reach : m.b.x + 0.8
		m.tx = x0
		m.ty = x1
		warn(x0, m.homeY - 3.6, x1, m.homeY, tele)
		m.st = 1
	}

	func chooseWardenAttack(_ m: Mob, _ dist: Double) {
		var r: Double = Double.random(in: 0...1)
		let fy: Double = m.homeY
		m.dir = pb.x >= m.b.x ? 1 : -1
		// variety: in the last phase the void pillars come at least every third attack, and no attack
		// is used three times running
		if m.phase == 3 && m.sinceSignature >= 2 { r = 0 }
		if m.repeatN >= 2 && m.lastAtk == WardenAtk.bolts.rawValue && dist >= 7.5 { r = m.phase >= 2 ? 0.4 : 0.0 }
		if m.phase == 3 && r < 0.35 {
			// void pillars erupt in a row across the hall
			m.atk = WardenAtk.pillars.rawValue
			m.t2 = 1.0
			var xs: [Double] = []
			for k in -2...2 {
				let sx: Double = clampD(pb.x + Double(k) * 4.0, m.homeX - 38, m.homeX + 38)
				xs.append(sx)
				warn(sx - 0.8, fy - 8.0, sx + 0.8, fy, 1.0, 0xB060FF)
			}
			m.spots = xs
			m.st = 1
		} else if m.phase >= 2 && r < 0.62 && dist > 4.5 {
			// vanishes and reappears on the far side of the player
			m.atk = WardenAtk.blink.rawValue
			m.t2 = 0.7
			let side: Double = pb.x >= m.b.x ? 1.0 : -1.0
			let dest: Double = clampD(pb.x + side * 3.2, m.homeX - 36, m.homeX + 36)
			m.tx = dest
			warn(dest - 1.6, fy - 4.6, dest + 1.6, fy, 0.7, 0xB060FF)
			m.st = 1
		} else if dist < 7.5 {
			startWardenSweep(m, m.phase == 3 ? 0.6 : 0.8)
		} else {
			m.atk = WardenAtk.bolts.rawValue
			m.t2 = 0.55
			m.st = 1
		}
	}

	func executeWarden(_ m: Mob) {
		let fy: Double = m.homeY
		if m.atk != WardenAtk.summon.rawValue {
			m.repeatN = m.atk == m.lastAtk ? m.repeatN + 1 : 1
			m.lastAtk = m.atk
			m.sinceSignature = m.atk == WardenAtk.pillars.rawValue ? 0 : m.sinceSignature + 1
		}
		switch WardenAtk(rawValue: m.atk) ?? .none {
		case .sweep:
			mobAttackBox(m, m.tx, fy - 3.6, m.ty, fy + 0.1, dmg: m.def.dmg, knock: 12)
			m.atkT = 0.45
			addShake(0.16)
			spawnParticles((m.tx + m.ty) * 0.5, fy - 1.0, 0xC8C8E0, 10, 6.0, 0.3, 4)
			m.st = 2
			m.t2 = 0.55
		case .bolts:
			m.st = 3
			m.t3 = Double(m.phase == 1 ? 3 : 4)
			m.t2 = 0
		case .blink:
			spawnParticles(m.b.x, m.b.cy, 0x8A4AE0, 16, 4.0, 0.6, -2)
			m.b.x = m.tx
			m.b.vx = 0
			spawnParticles(m.b.x, m.b.cy, 0xD8A8FF, 16, 4.0, 0.6, -2)
			m.dir = pb.x >= m.b.x ? 1 : -1
			startWardenSweep(m, 0.42)
		case .pillars:
			for sx in m.spots {
				mobAttackBox(m, sx - 0.8, fy - 8.0, sx + 0.8, fy + 0.1, dmg: 20, knock: 9, type: .impact)
				for k in 0..<4 { spawnParticles(sx, fy - Double(k) * 2.0, 0xB070FF, 3, 2.5, 0.5, -6) }
			}
			m.spots = []
			addShake(0.22)
			m.st = 2
			m.t2 = 0.8
		case .summon:
			for side in [-1.0, 1.0] {
				let sx: Double = m.homeX + side * 28.0
				_ = addMob(.imp, sx, fy - 0.05)
				spawnParticles(sx, fy - 1.0, 0x8A4AE0, 14, 4.0, 0.6, -3)
			}
			m.st = 2
			m.t2 = 0.6
		case .none:
			m.st = 0
		}
	}

	func fireWardenBolt(_ m: Mob) {
		let ox: Double = m.b.x + Double(m.dir) * 1.6
		let oy: Double = m.b.y - 2.6
		let aim: Double = atan2((pb.y - pb.h * 0.55) - oy, pb.x - ox)
		// the last phase throws each bolt as a fan of three
		let fan: [Double] = m.phase == 3 ? [-0.2, 0, 0.2] : [Double.random(in: -0.06...0.06)]
		for off in fan {
			let a: Double = aim + off
			var p = Projectile(kind: .bolt, x: ox, y: oy, vx: cos(a) * 12.0, vy: sin(a) * 12.0, dmg: 13, fromPlayer: false, gravity: 0)
			p.life = 3.5
			p.w = 0.4
			p.owner = m.id
			p.source = .mob(m, faction(of: m))
			p.uid = newID()
			projectiles.append(p)
		}
		m.atkT = Mob.atkDur
		spawnParticles(ox, oy, 0xD8A8FF, 4, 2.0, 0.25, 0)
	}
}

func isHumanoid(_ k: MobKind) -> Bool {
	switch k {
	case .zombie, .skeleton, .pirate, .pirateGunner, .pirateCaptain, .imp, .archer: return true
	default: return false
	}
}

// ===== u05_menu =====

extension DebugPanel {
	/// Night monsters: what the spawner is doing and why, a forced test, and the AI overlay
	var nightSection: some View {
		let lines: [String] = game.spawnDebugLines()
		return VStack(alignment: .leading, spacing: 6) {
			section("MONSTERS")
			Toggle("AI overlay (state, sight, range, why not attacking)", isOn: $game.showAI)
			ForEach(0..<lines.count, id: \.self) { i in
				Text(verbatim: lines[i]).font(.pixel(10, .semibold))
			}
			HStack(spacing: 6) {
				SmallButton(title: "Night + spawn test") { game.debugSpawnTest() }
				SmallButton(title: "Clear log") { game.spawnLog = [:]; game.bumpHUD() }
			}
		}
	}

	/// Sparkworks: what the simulation holds, and a kit of every part to try things out
	var powerSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			section("POWER")
			Text(verbatim: game.powerDebugLine).font(.pixel(10, .semibold))
			HStack(spacing: 6) {
				SmallButton(title: "Power kit") { game.debugPowerKit() }
				SmallButton(title: "Charge batteries") { game.debugChargeAll() }
				SmallButton(title: "Show wiring") {
					game.settings.showWires = game.settings.showWires == 1 ? 0 : 1
					game.bumpHUD()
				}
			}
		}
	}

	/// Make any kind of weather start now (events come with their usual warning), or call down a bolt
	var weatherSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			section("WEATHER")
			Text(verbatim: game.weatherDebugLine).font(.pixel(10, .semibold))
			HStack(spacing: 6) {
				SmallButton(title: "Clear") { game.debugForceWeather(.clear) }
				SmallButton(title: "Rain") { game.debugForceWeather(.heavyRain) }
				SmallButton(title: "Storm") { game.debugForceWeather(.thunderstorm) }
				SmallButton(title: "Hail") { game.debugForceWeather(.hailstorm) }
			}
			HStack(spacing: 6) {
				SmallButton(title: "Wind") { game.debugForceWeather(.windstorm) }
				SmallButton(title: "Snow") { game.debugForceWeather(.snowfall) }
				SmallButton(title: "Blizzard") { game.debugForceWeather(.blizzard) }
			}
			HStack(spacing: 6) {
				SmallButton(title: "Tornado", color: Color(ui: 0x8A3A3A)) { game.debugForceWeather(.tornado) }
				SmallButton(title: "Hurricane", color: Color(ui: 0x8A3A3A)) { game.debugForceWeather(.hurricane) }
				SmallButton(title: "Strike") { game.debugStrikeNearby() }
			}
		}
	}
}

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
		player = lookSpriteSet(playerLook(PlayerLookChoice(Settings())), hitH: 1.8)
		wolf = creatureSpriteSet(.wolf, 1)
		zombie = creatureSpriteSet(.zombie, 0)
		slime = creatureSpriteSet(.slime, 0)
		pig = creatureSpriteSet(.pig, 0)
		bat = creatureSpriteSet(.bat, 0)
		skeleton = creatureSpriteSet(.skeleton, 0)
	}

	func setPlayer(_ s: Settings) {
		let c: PlayerLookChoice = PlayerLookChoice(s)
		if c.key == key { return }
		key = c.key
		player = lookSpriteSet(playerLook(c), hitH: 1.8)
	}
}

struct MenuBackground: View {
	var settings: Settings
	var body: some View {
		TimelineView(.animation) { tl in
			Canvas { ctx, size in
				MenuBackground.paint(&ctx, size, tl.date.timeIntervalSinceReferenceDate, settings)
			}
		}
		.ignoresSafeArea()
	}

	static func paint(_ ctx: inout GraphicsContext, _ size: CGSize, _ t: Double, _ settings: Settings) {
		let art: Art = Art.shared
		let ma: MenuArt = MenuArt.shared
		ma.setPlayer(settings)
		let W: Double = Double(size.width)
		let H: Double = Double(size.height)
		let full: CGRect = mkRect(0, 0, W, H)
		vGradient(&ctx, full, [Color(hex: 0x3E86D8), Color(hex: 0xC4E6FF)], 0, H)
		let sunX: Double = W * 0.78
		fillRect(&ctx, mkRect(sunX, 70, 56, 56), Color(hex: 0xFFD84A))
		fillRect(&ctx, mkRect(sunX + 12.0, 82, 32, 32), Color(hex: 0xFFF2A0))
		// a handful of the game's own clouds drifting past at different sizes and speeds
		let clouds: CloudArt = CloudArt.shared
		let pool: [Int] = clouds.classes[0] + clouds.classes[1] + clouds.classes[2] + clouds.classes[3]
		let span: Double = W + 900.0
		for i in 0..<7 {
			let speed: Double = 8.0 + Double(i) * 3.0
			var cx: Double = hash2(i, 1, 9) * span + t * speed
			cx = cx.truncatingRemainder(dividingBy: span) - 450.0
			let cy: Double = 30.0 + hash2(i, 2, 9) * H * 0.32
			let kind: Int = pool[(i * 5 + 2) % pool.count]
			let b: PixelBuf = clouds.shapes[kind]
			let scale: Double = i % 2 == 0 ? 2.0 : 3.0
			var cc: GraphicsContext = ctx
			cc.opacity = 0.92
			cc.draw(clouds.images[kind], in: mkRect((cx / scale).rounded() * scale, (cy / scale).rounded() * scale, Double(b.w) * scale, Double(b.h) * scale))
		}
		let ground: Double = H - 130.0
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
		let stride: Double = t * 2.4
		let gy: Double = ground / ts
		let px: Double = W * 0.32 / ts
		let zx: Double = px - 7.0 + sin(t) * 0.4
		let kx: Double = px - 10.0 + sin(t * 0.7) * 0.3
		WorldRenderer.drawSet(&ctx, v, ma.player, ma.player.anim.walkFrame(stride), false, false, px, gy)
		WorldRenderer.drawSet(&ctx, v, ma.wolf, ma.wolf.anim.walkFrame(stride), false, false, px - 2.6, gy)
		WorldRenderer.drawSet(&ctx, v, ma.zombie, ma.zombie.anim.walkFrame(stride), false, false, zx, gy)
		WorldRenderer.drawSet(&ctx, v, ma.skeleton, ma.skeleton.anim.walkFrame(stride), false, false, kx, gy)
		let hop: Double = abs(sin(t * 3.0)) * 0.7
		let slimeFrame: Int = hop > 0.1 ? 1 : 0
		WorldRenderer.drawSet(&ctx, v, ma.slime, slimeFrame, true, false, px + 7.5, gy - hop)
		WorldRenderer.drawSet(&ctx, v, ma.pig, ma.pig.anim.walkFrame(stride), true, false, px + 4.0, gy)
		let bx: Double = W * 0.55 / ts + sin(t * 0.8) * 3.5
		let byy: Double = 5.5 + sin(t * 2.0) * 0.8
		WorldRenderer.drawSet(&ctx, v, ma.bat, Int(t * 10.0), false, false, bx, byy)
	}
}

// MARK: - Main menu

enum MenuScreen {
	case main, newWorld, load, character, settings, help
	/// the Mod Creator (shown full screen)
	case mods
}

struct MenuView: View {
	@Binding var settings: Settings
	/// open on the Mod Creator (coming back from a test world)
	var openMods: Bool = false
	var start: (Game) -> Void
	@State var screen: MenuScreen = .main
	@State var seedText: String = ""
	@State var nameText: String = "My World"
	@State var mode: GameMode = .survival
	@State var infinite: Bool = false
	@State var flat: Bool = false
	@State var flatTrees: Bool = true
	@State var flatStructures: Bool = true
	@State var flatCaves: Bool = true
	@State var splash: String = ""
	@State var metas: [SaveMeta] = []
	/// a world whose mods are not all installed, waiting for the player's choice
	@State var missingMods: ModLoadCheck? = nil
	let splashes: [String] = ["Now with pirates!", "Beware the Bear!", "Find the hidden gate!", "Ride a T-Rex!",
							  "Build a car. Then a boat.", "Torches keep the dark away!", "Infinite worlds!", "Make your own mods!"]

	var body: some View {
		ZStack {
			if screen == .mods {
				ModCreatorView(test: { p in start(ModTest.makeWorld(p, settings: settings)) }, done: {
					ThemeRT.refresh()
					screen = .main
				})
			} else {
				menuBody
			}
			if let mc = missingMods {
				ModMissingView(check: mc, load: { loadAnyway(mc) }, cancel: { missingMods = nil })
			}
		}
		.onAppear { if openMods { screen = .mods } }
	}

	var menuBody: some View {
		ZStack {
			menuBackdrop
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
			ThemeRT.refresh()
			splash = splashes.randomElement() ?? ""
			refreshSaves()
		}
	}

	/// the game's sky and character, or a theme's own picture
	@ViewBuilder
	var menuBackdrop: some View {
		if let bg = ThemeRT.current?.background, bg.valid, !bg.isBlank {
			pixImage(bg.buf()).resizable().interpolation(.none).ignoresSafeArea()
		} else {
			MenuBackground(settings: settings)
		}
	}

	var titleText: String {
		let t: String = ThemeRT.current?.title ?? ""
		return t.trimmingCharacters(in: .whitespaces).isEmpty ? "PIXEL REALM" : t
	}

	var subtitleText: String {
		let t: String = ThemeRT.current?.subtitle ?? ""
		return t.trimmingCharacters(in: .whitespaces).isEmpty ? splash : t
	}

	var title: some View {
		VStack(spacing: 0) {
			Text(verbatim: titleText)
				.font(.system(size: 52, weight: .black, design: ThemeRT.design))
				.foregroundColor(Color(ui: 0xFFE066))
				.shadow(color: Color(ui: 0x7A4A00), radius: 0, x: 4, y: 4)
				.shadow(color: Color.black, radius: 0, x: 6, y: 6)
				.minimumScaleFactor(0.5)
				.lineLimit(1)
			Text(verbatim: subtitleText)
				.font(.pixel(15))
				.foregroundColor(Color(ui: 0xFFF58A))
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
		case .mods: EmptyView()
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
				PixelButton(title: continueTitle, color: Color(ui: 0x4E8A3E)) { load(m.slot) }
			}
			PixelButton(title: "NEW WORLD", color: Color(ui: 0x3E6FAA)) { screen = .newWorld }
			if !metas.isEmpty {
				PixelButton(title: "LOAD WORLD") { refreshSaves(); screen = .load }
			}
			HStack(spacing: 10) {
				PixelButton(title: "CHARACTER", color: Color(ui: 0x8A5A2E)) { screen = .character }
				PixelButton(title: "SETTINGS") { screen = .settings }
			}
			HStack(spacing: 10) {
				PixelButton(title: "HOW TO PLAY") { screen = .help }
				PixelButton(title: "MOD CREATOR", color: Color(ui: 0x6A3AA0)) { screen = .mods }
			}
		}
	}

	var worldBlurb: String {
		if infinite { return "Endless world that streams in as you explore." }
		if flat { return "A large world (4096 wide) with every biome." }
		return "A large world (4096 wide) with every biome and ocean edges."
	}

	var terrainBlurb: String {
		if !flat { return "Hills, mountains, caves and seas." }
		return "Level ground everywhere, the same layers below: topsoil, stone, slate and deep rock with ores, on bedrock. The portal chamber is still buried deep below."
	}

	var flatDetail: String {
		var parts: [String] = []
		parts.append(flatTrees ? "Trees, plants and ponds (water level with the ground)." : "Bare ground: no trees, plants or ponds.")
		parts.append(flatStructures ? "Ruins, old mines and the two boss lairs (open arenas)." : "No ruins, mines or boss lairs.")
		parts.append(flatCaves ? "Caves open only deep below an unbroken crust." : "Solid underground: dig your own tunnels.")
		return parts.joined(separator: " ")
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
			HStack(spacing: 6) {
				PixelButton(title: "NORMAL", color: pick(!flat, 0x4E7A3A, 0x555555)) { flat = false }
				PixelButton(title: "FLAT", color: pick(flat, 0x4E7A3A, 0x555555)) { flat = true }
			}
			Text(verbatim: terrainBlurb)
				.font(.pixel(11, .bold)).foregroundColor(Color.white).shadow(color: Color.black, radius: 0, x: 1, y: 1)
				.multilineTextAlignment(.center)
			if flat {
				HStack(spacing: 6) {
					PixelButton(title: flatTrees ? "NATURE ON" : "NATURE OFF", color: pick(flatTrees, 0x4E7A3A, 0x555555)) { flatTrees.toggle() }
					PixelButton(title: flatStructures ? "BUILDINGS ON" : "BUILDINGS OFF", color: pick(flatStructures, 0x4E7A3A, 0x555555)) { flatStructures.toggle() }
					PixelButton(title: flatCaves ? "CAVES ON" : "CAVES OFF", color: pick(flatCaves, 0x4E7A3A, 0x555555)) { flatCaves.toggle() }
				}
				Text(verbatim: flatDetail)
					.font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.85)).shadow(color: Color.black, radius: 0, x: 1, y: 1)
					.multilineTextAlignment(.center)
			}
			TextField("Seed (optional)", text: $seedText)
				.font(.pixel(15, .bold))
				.padding(10)
				.background(Color.black.opacity(0.75))
				.foregroundColor(Color.white)
			PixelButton(title: "CREATE", color: Color(ui: 0x4E8A3E)) { create() }
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
		let flatS: String = (m.options?.flat ?? false) ? " Flat" : ""
		let kindS: String = joinText(m.infinite ? "Infinite" : "Classic", flatS)
		let modeS: String = m.mode.title
		let dayS: Int = Int(m.day)
		let detail: String = "\(modeS) · \(kindS) · Day \(dayS) · \(mins) min"
		return HStack(spacing: 8) {
			VStack(alignment: .leading, spacing: 2) {
				Text(m.name).font(.pixel(15)).foregroundColor(Color.white)
				Text(detail).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.8))
			}
			Spacer()
			SmallButton(title: "PLAY", color: Color(ui: 0x4E8A3E)) { load(m.slot) }
			SmallButton(title: "DEL", color: Color(ui: 0xA03030)) {
				SaveStore.delete(m.slot)
				refreshSaves()
			}
		}
		.padding(8)
		.background(PixelBox(color: Color(ui: 0x3A3A3A)).opacity(0.92))
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
		var opts: WorldOptions = .standard
		if flat {
			opts.flat = true
			opts.trees = flatTrees
			opts.ponds = flatTrees
			opts.structures = flatStructures
			opts.caves = flatCaves
		}
		// the mods switched on now become part of the world (it remembers them from here on)
		ModRuntime.activate(ModStore.enabledPacks(), world: nil)
		let g = Game(mode: mode, infinite: infinite, seed: seed, settings: settings, options: opts)
		g.worldName = nm
		g.slot = SaveStore.freeSlot()
		g.modInfo = ModRuntime.shared.active ? ModRuntime.shared.worldInfo() : nil
		_ = g.saveNow()
		start(g)
	}

	func load(_ slot: Int) {
		if let s = SaveStore.read(slot) {
			let mc: ModLoadCheck = ModLoadCheck.check(s)
			if !mc.missing.isEmpty {
				// never load a world without its mods behind the player's back
				missingMods = mc
				return
			}
			ModRuntime.activate(mc.packs, world: s.mods)
			let g: Game = Game.load(s, settings: settings)
			if !mc.changed.isEmpty {
				g.say(joinText("Updated since this world was last played: ", mc.changed.joined(separator: ", "), ". New content appears in places not visited yet."), 6.0)
			}
			start(g)
		} else {
			refreshSaves()
		}
	}

	/// Loads a world even though some of its mods are missing: their blocks and items are kept as
	/// placeholders (nothing is deleted), so the world is whole again once the mods are back
	func loadAnyway(_ mc: ModLoadCheck) {
		missingMods = nil
		ModRuntime.activate(mc.packs, world: mc.save.mods)
		let g: Game = Game.load(mc.save, settings: settings)
		start(g)
	}
}

// MARK: - Character, settings, help

struct CharacterView: View {
	@Binding var settings: Settings
	var done: () -> Void
	var body: some View {
		VStack(spacing: 10) {
			topBar
			ScrollView {
				VStack(spacing: 12) {
					preview
					styleRow("HAIR", hairStyleNames, settings.hairStyle) { (i: Int) in settings.hairStyle = i }
					colorRow("", hairChoices, settings.hair) { (i: Int) in settings.hair = i }
					styleRow("SHIRT", shirtStyleNames, settings.shirtStyle) { (i: Int) in settings.shirtStyle = i }
					colorRow("", shirtChoices, settings.shirtColor) { (i: Int) in settings.shirtColor = i }
					styleRow("TROUSERS", pantsStyleNames, settings.pantsStyle) { (i: Int) in settings.pantsStyle = i }
					colorRow("", pantsChoices, settings.pantsColor) { (i: Int) in settings.pantsColor = i }
					colorRow("SCARF", scarfChoices, settings.scarf) { (i: Int) in settings.scarf = i }
				}
				.padding(.bottom, 20)
			}
		}
	}

	var topBar: some View {
		HStack(spacing: 10) {
			Text("CHARACTER").font(.pixel(20)).foregroundColor(Color.white).shadow(color: Color.black, radius: 0, x: 2, y: 2)
			Spacer()
			PixelButton(title: "DONE", color: Color(ui: 0x4E8A3E)) { done() }
		}
		.padding(.horizontal, 12)
	}

	/// The look as chosen, from the front and from the side, a few times its size
	var preview: some View {
		let imgs: (Image, Image) = Art.shared.previewPlayer(settings)
		return HStack(spacing: 18) {
			imgs.0.resizable().interpolation(.none).frame(width: 128, height: 152)
			imgs.1.resizable().interpolation(.none).frame(width: 128, height: 152)
		}
		.padding(10)
		.background(PixelBox(color: Color(ui: 0x5A7A9A)).opacity(0.9))
	}

	/// A colour to pick; colour 0 is "none" (no scarf), shown as a dark box with a cross
	func swatch(_ c: UInt32, _ on: Bool) -> some View {
		let edge: Color = pick(on, 0xFFFFFF, 0x000000)
		let w: CGFloat = on ? 4 : 2
		let none: Bool = c == 0
		let fill: Color = Color(hex: none ? 0x2A2A32 : artGrade(c))
		let mark: String = none ? "X" : ""
		return Rectangle().fill(fill)
			.frame(width: 38, height: 38)
			.overlay(Text(verbatim: mark).font(.pixel(14, .bold)).foregroundColor(Color(hex: 0x9A9AA8)))
			.overlay(Rectangle().stroke(edge, lineWidth: w))
	}

	func colorRow(_ label: String, _ cols: [UInt32], _ sel: Int, _ pick: @escaping (Int) -> Void) -> some View {
		HStack(spacing: 6) {
			Text(label).font(.pixel(13)).foregroundColor(Color.white).frame(width: 96, alignment: .leading)
			ForEach(0..<cols.count, id: \.self) { (i: Int) in
				Button {
					pick(i)
				} label: {
					swatch(cols[i], i == sel)
				}
				.buttonStyle(.plain)
			}
			Spacer()
		}
		.padding(.horizontal, 12)
	}

	func styleRow(_ label: String, _ names: [String], _ sel: Int, _ pick: @escaping (Int) -> Void) -> some View {
		HStack(spacing: 6) {
			Text(label).font(.pixel(13)).foregroundColor(Color.white).frame(width: 96, alignment: .leading)
			ForEach(0..<names.count, id: \.self) { (i: Int) in
				SmallButton(title: names[i].uppercased(), color: i == sel ? Color(ui: 0x4E8A3E) : Color(ui: 0x555560)) { pick(i) }
			}
			Spacer()
		}
		.padding(.horizontal, 12)
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
			CameraSettingsSection(settings: $settings)
			WeatherSettingsSection(settings: $settings)
			NightSettingsSection(settings: $settings)
			PixelButton(title: "DONE", color: Color(ui: 0x4E8A3E)) { done() }
		}
		.font(.pixel(14, .bold))
		.foregroundColor(Color.white)
		.padding(18)
		.background(PixelBox(color: Color(ui: 0x2C2C30)).opacity(0.95))
	}
}

/// Camera and comfort options, shared by the main settings screen and the pause menu
struct CameraSettingsSection: View {
	@Binding var settings: Settings
	var onChange: () -> Void = {}

	func label(_ s: String, _ v: Double) -> some View {
		Text(verbatim: joinText(s, ": ", String(format: "%.2f", v))).font(.pixel(12, .bold))
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("CAMERA & COMFORT").font(.pixel(15)).foregroundColor(Color(ui: 0xFFE066))
			Toggle("Smooth camera", isOn: $settings.camSmoothOn)
			if settings.camSmoothOn {
				label("Follow tightness", settings.camFollow)
				Slider(value: $settings.camFollow, in: 0.0...1.0, step: 0.05)
			}
			label("Dead zone (blocks)", settings.camDeadZone)
			Slider(value: $settings.camDeadZone, in: 0.0...3.0, step: 0.1)
			Toggle("Follow the player directly", isOn: $settings.camDirect)
			Text("On: the camera stays right on the player, with no dead zone or look-ahead.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.7))
			if !settings.camDirect {
				Toggle("Look ahead while moving", isOn: $settings.camLookAhead)
			}
			Toggle("Screen shake", isOn: $settings.shakeOn)
			if settings.shakeOn {
				label("Shake intensity", settings.shakeIntensity)
				Slider(value: $settings.shakeIntensity, in: 0.0...1.0, step: 0.05)
			}
			Toggle("Bow trajectory preview", isOn: $settings.showTrajectory)
			Text("SOUND").font(.pixel(15)).foregroundColor(Color(ui: 0xFFE066))
			Toggle("Sound", isOn: $settings.soundOn)
			if settings.soundOn {
				label("Effects volume", settings.sfxVolume)
				Slider(value: $settings.sfxVolume, in: 0.0...1.0, step: 0.05)
				label("Ambience volume", settings.ambienceVolume)
				Slider(value: $settings.ambienceVolume, in: 0.0...1.0, step: 0.05)
			}
			SmallButton(title: "RESET CAMERA DEFAULTS") {
				settings.resetCamera()
				onChange()
			}
		}
		.font(.pixel(13, .bold))
		.foregroundColor(Color.white)
	}
}

struct HelpView: View {
	var done: () -> Void
	let lines: [String] = [
		"Move with the left stick (or A/D). JUMP button (W/Space). Pull the stick down to drop through platforms.",
		"Touch the world to mine, attack, place or use the item in your hand. A blow goes where you touch: tap a foe (or near it) to hit it, tap above you to swing up. Hold to keep attacking a foe in reach.",
		"The round attack stick on the right: touch and hold to attack, and let go to stop. With your thumb in the middle it aims for you: it picks the nearest hostile creature (not the cow beside it), turns you to face it and keeps hitting while it is in reach. Slide your thumb out to aim yourself in any direction, up, down or diagonal: blades swing that way, bows and guns shoot that way, slings and thrown flasks land further the further you push, pickaxes dig the first block that way and blocks go against it. It works at the same time as the walking stick and JUMP.",
		"The ⇄ button (or Q) switches to the next weapon in your hotbar; from a tool it goes straight back to the weapon you used last.",
		"Hotbar: tap a slot. BAG opens your inventory, armor and crafting. Hold a slot to split a stack.",
		"Craft a workbench, then a furnace. Near the top you find coal, copper, saltpeter and (in some lands) tin; iron and silver lie deeper, gold, diamond and mythril deepest. Amethyst geodes are rare.",
		"Smelt copper and tin ore together into bronze: crossbows, bolts, maces and lanterns. Saltpeter makes strong gunpowder and fire flasks. Silver makes a charm against the undead and, with amethyst, the storm rod.",
		"Iron and better gear is forged on an anvil; machinery and vehicle parts at a tinker's bench; Umbral metals only at a rift forge. Tap a station to craft at it.",
		"Weapons: swords sweep everything in front; spears reach far and run through two; hammers are slow and heavy and slow you as they swing; knives are quick, every third stab in a run hits double, and they cut deep from behind; clubs leave foes dazed.",
		"Ranged: the bow is drawn and loosed; the sling throws any stone you carry; crossbows fire with a tap and reload themselves; the blunderbuss blasts a cone of pellets up close; the storm rod's lightning leaps between foes and recharges by itself. Thrown flasks and slung stones come down where you tap.",
		"Two gear slots hold a headlamp, swift boots, a diving mask, a silver charm and more.",
		"LOG (or J) opens your journal: places you have found, their stories and goals worth chasing.",
		"Some old chests underground are not what they seem.",
		"Torches, lanterns and campfires light the dark. Caves get darker and more dangerous the deeper you go.",
		"Old mines (a timber headframe on the surface) run deep: galleries, storage rooms up short ladders, drifts down and up, dead ends, sometimes a great chamber. Look for chests in rooms and at dead ends; the best are hidden behind fallen rock.",
		"Eat to stay fed. Cook meat at a campfire. Hunger at zero hurts you.",
		"Skeleton knights block with shields. Pirates sail the seas and raid the coast.",
		"Defeat Ursavor the giant bear to get a Portal Key and a Treasure Map. The map hints where the hidden gate is.",
		"Beat Tyrannax the T-Rex and it becomes your companion. Tap it to ride.",
		"Vehicles, the easy way: craft a Car Kit, Rowboat Kit or Motorboat Kit (Vehicles tab at a workbench) and tap the ground to place it. Stand next to it and press DRIVE. PACK UP puts it back in your bag.",
		"Your own designs: place a Frame (car) or Hull Float (boat), then hold a part - green squares show where it fits. A checklist shows what is still missing. Coal or wood is fuel: hold it and tap the vehicle.",
		"Planes, helicopters, airships, tanks and trucks: kits in the Vehicles tab, or build your own. Wings lift with speed (and stall when tilted too far), a tail elevator behind steers the nose, rotors need engines and a tail rotor, a balloon needs burners. Every part and block has weight: too heavy, and it will not fly.",
		"Build anything onto a vehicle: hold a block near one and switch ON VEHICLE, then tap the green squares. Or build a whole ship from blocks in the world and tap it with the Vehicle Assembler: it becomes one vehicle (tap it parked to put it back).",
		"Armed vehicles: cannons (gunpowder) and machine guns (bullets) aim with the attack stick. Shots, blasts and crashes break parts off; hold an iron bar and tap a part to mend it. An Autopilot holds speed and height (AUTO), or drives the points you MARK.",
		"Zoom with + and −. The DBG button opens the debug menu. II pauses and saves.",
		"Watch the ground in big fights: an attack's area pulses and fills up just before it lands. Step out of it.",
		"Weather comes and goes: showers drift over the land with the wind, deserts stay dry, the cold country gets snow. A strong wind carries arrows and jumps with it and slows you walking into it.",
		"In a thunderstorm keep off high, open ground. When the air crackles and the ground glows, lightning is about to strike there: move. A copper lightning rod standing in the open takes every strike within 14 blocks.",
		"Tornadoes and hurricanes are rare and always come with a warning. Get underground or behind reinforced walls; sandbags hold back a hurricane's surge, shutters keep the wind off your windows.",
		"In a blizzard the cold gets into you: a fire, a heater, a roof and walls or a winter coat keep you warm; snow boots stop you slipping. Large hail hurts: a roof or a helmet stops it.",
		"Weather tab (workbench and up): a weather station shows the forecast (a Doppler station next to a charged wind turbine gives exact times and tracks tornadoes), a barometer reads the pressure, sirens sound for dangerous storms and rain barrels collect water for your crops. Every kind of weather can be switched off in Settings.",
		"Nights are dangerous: monsters come out after dark and come looking for you, more of them on the Deadly setting (Settings, Nights). They keep away from lamplight and never spawn on the floors or roofs of buildings; a monster that sees you shouts (!) and charges. Undead burn at sunrise.",
		"Sparkworks (Power tab): generators (a hand crank, a water wheel, solar panels, a fuel generator, a wind turbine, the Ember Dynamo) make power, measured in sparks. Power cable carries it to batteries and machines: hold a spool and drag to lay it through them. Nothing runs for free: when a line can't supply what is asked, machines stop and show a red bolt.",
		"Pulse wire (amber or teal) carries on/off signals, separately from power: from levers, buttons, pressure plates, timers and sensors to lamps, steel gates, machines, wooden doors, storm shutters and sirens. Logic parts (relays, inverters, AND/OR/XOR/NAND/NOR gates, timers) point a way: they read the wire at their back or sides and send on the wire their arrow points to.",
		"The Spark Probe: tap a device to see how it is doing and set it up (gate type, sensor range, timer period, a breaker's limit, a crafter's recipe, which way it faces); tap a wire to light up its whole network and see what it makes, uses and stores. Wire snips take wire back up. Settings, Power Wiring chooses when wiring is drawn.",
		"Ideas: a proximity sensor set to the player opens a steel gate for you and not for monsters; a weather sensor closes the shutters when a storm comes; a daylight sensor lights the lamps at dusk; an auto drill, conveyor and collector bring ore to a chest; a breaker keeps one line from draining your batteries.",
		"Keyboard: A/D move, W jump, S down, 1-0 hotbar, Q next weapon, E bag, M map, J journal, F attack/use, R reload, X dismount, +/- zoom, Esc pause."
	]
	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("HOW TO PLAY").font(.pixel(20))
			ForEach(0..<lines.count, id: \.self) { i in
				Text(verbatim: joinText("• ", lines[i])).font(.pixel(12, .semibold))
			}
			PixelButton(title: "GOT IT", color: Color(ui: 0x4E8A3E)) { done() }
		}
		.foregroundColor(Color.white)
		.padding(18)
		.background(PixelBox(color: Color(ui: 0x2C2C30)).opacity(0.95))
	}
}

// ===== u10_automation =====

// MARK: - The receiver panel

/// Setting up a vehicle's receivers (tap one): the channel they pick up from signal posts and the Logic
/// Studio, and what the vehicle does while it is on. A remote control pairs with any vehicle that has one.
struct ReceiverPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal

	var body: some View {
		VStack(spacing: 8) {
			topBar
			ScrollView { content }
		}
		.foregroundColor(Color(ui: 0xFFFFFF))
		.padding(14)
		.background(PixelBox(color: Color(ui: 0x2C2834)).opacity(0.97))
		.frame(maxWidth: 620)
		.padding(10)
	}

	var vehicle: Vehicle? { return game.vehicleByID(game.radioEdit) }

	var topBar: some View {
		HStack {
			Text("RECEIVER").font(.pixel(20)).foregroundColor(Color(ui: 0xE8C040))
			Spacer()
			SmallButton(title: "DONE", color: Color(ui: 0x3A6A3A)) { game.closeRadio() }
		}
	}

	@ViewBuilder
	var content: some View {
		if let v = vehicle {
			VStack(alignment: .leading, spacing: 8) {
				Text(verbatim: ReceiverPanel.help).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xB8B0C8))
				Text("Channel").font(.pixel(13, .bold))
				ChoiceRows(options: ReceiverPanel.channelNames, selected: channelBind(v), columns: 5)
				Text("While its channel is on").font(.pixel(13, .bold))
				ChoiceRows(options: ReceiverPanel.actNames, selected: actBind(v), columns: 3)
			}
		} else {
			Text("This vehicle is gone.").font(.pixel(13)).foregroundColor(Color(ui: 0xFFE070))
		}
	}

	static let help: String = "Signal posts on the same channel (and the Logic Studio) turn it on. A remote control pairs with any vehicle that has a receiver."
	static let channelNames: [String] = ["NONE"] + (1...Radio.channels).map { (n: Int) in String(n) }
	static let actNames: [String] = RadioAct.allCases.map { (a: RadioAct) in a.name }

	func channelBind(_ v: Vehicle) -> Binding<Int> {
		let me: ReceiverPanel = self
		return Binding<Int>(get: { v.channel }, set: { (n: Int) in me.game.setRadio(channel: n, act: RadioAct(rawValue: v.radioAct) ?? .forward) })
	}

	func actBind(_ v: Vehicle) -> Binding<Int> {
		let me: ReceiverPanel = self
		return Binding<Int>(get: { v.radioAct }, set: { (n: Int) in me.game.setRadio(channel: v.channel, act: RadioAct(rawValue: n) ?? .forward) })
	}
}
