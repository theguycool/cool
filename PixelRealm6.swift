// PIXEL REALM v2, part 6 of 8: the art store and the player's look, sound, weather, ambient and animal life, the journal and
// telegraphed attacks, the menus, and the potion and exosuit screens.
// The game is eight files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm8.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 2 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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

// ===== u08_alchemy =====

// MARK: - HUD: effects and suit energy

/// The potion effects on the player: a small flask in the effect's colour and the seconds left
struct EffectStrip: View {
	let game: Game
	/// the HUD's tick: a new value makes SwiftUI draw the strip again (it reads the game, which it does not watch)
	var tick: Int = 0
	var body: some View {
		let list: [(ModEffectKind, Double)] = game.activeEffects()
		return HStack(spacing: 4) {
			ForEach(0..<list.count, id: \.self) { i in
				EffectChip(kind: list[i].0, secs: list[i].1)
			}
		}
	}
}

struct EffectChip: View {
	let kind: ModEffectKind
	let secs: Double
	var body: some View {
		let t: Int = Int(secs.rounded(.up))
		let label: String = t >= 60 ? joinText(String(t / 60), "m") : joinText(String(t), "s")
		return HStack(spacing: 2) {
			Rectangle().fill(Color(hex: kind.color)).frame(width: 9, height: 9)
				.overlay(Rectangle().stroke(Color.black, lineWidth: 1))
			OutlinedText(text: label, size: 10, color: secs < 6 ? Color(ui: 0xFFB060) : Color.white)
		}
		.padding(.horizontal, 3)
		.padding(.vertical, 2)
		.background(Color.black.opacity(0.35))
	}
}

/// The worn suit's energy, and the PACK button when it carries a cargo pack
struct SuitBar: View {
	let game: Game
	/// the HUD's tick, so the bar redraws as the suit's energy changes
	var tick: Int = 0
	var body: some View {
		let st: ExoStats = game.suitStats
		let cap: Double = max(1, st.capacity)
		let f: Double = clampD(game.suit.energy / cap, 0, 1)
		let col: Color = f > 0.25 ? Color(ui: 0x60E0FF) : Color(ui: 0xFF8A40)
		return HStack(spacing: 6) {
			OutlinedText(text: "SUIT", size: 10, color: Color(ui: 0x9AD8F0))
			ZStack(alignment: .leading) {
				Rectangle().fill(Color.black.opacity(0.6)).frame(width: 110, height: 9)
				Rectangle().fill(col).frame(width: CGFloat(110.0 * f), height: 9)
			}
			.overlay(Rectangle().stroke(Color.white.opacity(0.4), lineWidth: 1))
			OutlinedText(text: joinText(String(Int(game.suit.energy)), "/", String(Int(cap))), size: 10)
			if st.broken > 0 { OutlinedText(text: joinText(String(st.broken), " BROKEN"), size: 10, color: Color(ui: 0xFF8A40)) }
			if st.has(.cargo) {
				SmallButton(title: "PACK", color: Color(ui: 0x7A5A2A)) { game.openPack() }
			}
			if st.has(.cannon) || st.has(.laser) {
				HoldButton(label: "SUIT FIRE", size: 58, color: Color(ui: 0x8A3A3A)) { (on: Bool) in game.suitFireHeld = on }
			}
		}
	}
}

// MARK: - Infusion Crucible

/// The Infusion Crucible: pick a piece of equipment, pick a compound, see what will change, confirm.
/// The item never leaves its slot while this is open, so a slip of the finger can't lose it.
struct InfusionPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var pick: Int = -1
	@State var choice: Int = -1
	@State var removing: Int = -1
	@State var note: String = ""
	@State var customChoice: Int = -1

	var body: some View {
		VStack(spacing: 10) {
			HStack {
				Text("INFUSION CRUCIBLE").font(.pixel(20)).foregroundColor(Color(ui: 0xC07CFF))
				Spacer()
				SmallButton(title: "MAKE COMPOUNDS", color: Color(ui: 0x5A4A8A)) { game.openCrafting(.infuser) }
				SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { close() }
			}
			Text("1 Choose equipment  ·  2 Choose an infusion  ·  3 Check what changes, then confirm")
				.font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.7))
				.frame(maxWidth: .infinity, alignment: .leading)
			HStack(alignment: .top, spacing: 12) {
				equipmentColumn.frame(width: 250)
				infusionColumn.frame(width: 330)
				previewColumn.frame(width: 300)
			}
			if !note.isEmpty {
				Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(ui: 0xFFE070))
			}
		}
		.foregroundColor(Color.white)
		.padding(14)
		.background(PixelBox(color: Color(ui: 0x2C2834)).opacity(0.97))
		.frame(maxWidth: 940)
		.padding(10)
	}

	func close() {
		game.showInfuse = false
		game.bumpHUD()
	}

	/// bag slots holding something that takes infusions
	var candidates: [Int] {
		var out: [Int] = []
		for i in 0..<game.inv.slots.count {
			if let s = game.inv.slots[i], infusionSlots(s.item) > 0, s.item.maxStack == 1 { out.append(i) }
		}
		return out
	}

	var equipmentColumn: some View {
		let list: [Int] = candidates
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 46), spacing: 4)]
		return VStack(alignment: .leading, spacing: 6) {
			Text("EQUIPMENT").font(.pixel(13)).foregroundColor(Color(ui: 0xB8A8D8))
			if list.isEmpty {
				Text("Nothing in your bag can take an infusion yet: weapons, tools, armour and suit parts can (take worn armour off first).")
					.font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.6))
			}
			ScrollView {
				LazyVGrid(columns: cols, spacing: 4) {
					ForEach(list, id: \.self) { i in
						Button(action: {
							pick = i
							removing = -1
							note = ""
						}) {
							SlotView(stack: game.inv.slots[i], selected: pick == i, size: 44)
						}
						.buttonStyle(.plain)
					}
				}
			}
			.frame(maxHeight: 300)
			if let s = picked { pickedInfo(s) }
		}
	}

	var picked: Stack? {
		if pick < 0 || pick >= game.inv.slots.count { return nil }
		guard let s = game.inv.slots[pick], infusionSlots(s.item) > 0 else { return nil }
		return s
	}

	func pickedInfo(_ s: Stack) -> some View {
		let slots: Int = infusionSlots(s.item)
		let have: [Infusion] = s.infusions
		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: s.item.name).font(.pixel(13))
			Text(verbatim: joinText(String(s.inf?.count ?? 0), " of ", String(slots), " slots used")).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.7))
			ForEach((s.inf ?? []).filter { $0 >= customInfusionBase }, id: \.self) { n in
				HStack(spacing: 6) {
					Rectangle().fill(Color(hex: infusionColor(n))).frame(width: 10, height: 10)
					Text(verbatim: infusionName(n)).font(.pixel(11)).foregroundColor(Color.white)
					Spacer(minLength: 0)
					SmallButton(title: "REMOVE", color: Color(ui: 0x5A4A4A)) { note = game.removeCustomInfusion(slot: pick, n) }
				}
			}
			ForEach(0..<have.count, id: \.self) { k in
				HStack(spacing: 6) {
					Rectangle().fill(Color(hex: have[k].color)).frame(width: 10, height: 10)
					Text(verbatim: have[k].name).font(.pixel(11)).foregroundColor(Color(ui: have[k].rarity.color))
					Spacer(minLength: 0)
					SmallButton(title: removing == have[k].rawValue ? "SURE?" : "REMOVE", color: Color(ui: removing == have[k].rawValue ? 0xC04030 : 0x5A4A4A)) {
						if removing == have[k].rawValue {
							note = game.removeInfusion(slot: pick, have[k])
							removing = -1
						} else {
							removing = have[k].rawValue
							note = "Removing it spends the compound; the item is unharmed. Tap SURE? to go ahead."
						}
					}
				}
			}
		}
		.padding(6)
		.background(Color.black.opacity(0.25))
	}

	var infusionColumn: some View {
		let all: [Infusion] = Infusion.allCases
		return VStack(alignment: .leading, spacing: 6) {
			Text("INFUSIONS").font(.pixel(13)).foregroundColor(Color(ui: 0xB8A8D8))
			ScrollView {
				VStack(spacing: 4) {
					ForEach(all, id: \.self) { inf in infusionRow(inf) }
					customRows
				}
			}
			.frame(maxHeight: 420)
		}
	}

	func infusionRow(_ inf: Infusion) -> some View {
		let owned: Int = game.inv.total(.compound(inf))
		let problem: String? = picked?.infuseProblem(inf)
		let usable: Bool = (owned > 0 || game.isCreative) && problem == nil && picked != nil
		let chosen: Bool = choice == inf.rawValue
		return Button(action: {
			choice = inf.rawValue
			customChoice = -1
			note = ""
		}) {
			HStack(spacing: 6) {
				SlotView(stack: Stack(item: .compound(inf), count: max(1, owned)), selected: chosen, size: 34, dim: owned == 0)
				VStack(alignment: .leading, spacing: 1) {
					HStack(spacing: 4) {
						Text(verbatim: inf.name).font(.pixel(12)).foregroundColor(Color(ui: inf.rarity.color))
						Text(verbatim: inf.rarity.name).font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.5))
					}
					Text(verbatim: inf.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(usable ? 0.85 : 0.5)).lineLimit(2)
				}
				Spacer(minLength: 0)
				Text(verbatim: owned > 0 ? joinText("x", String(owned)) : "none").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
			}
			.padding(4)
			.background(chosen ? Color(ui: 0x4A3A6A) : Color.black.opacity(0.2))
		}
		.buttonStyle(.plain)
	}

	var previewColumn: some View {
		let inf: Infusion? = Infusion(rawValue: choice)
		return VStack(alignment: .leading, spacing: 6) {
			Text("WHAT CHANGES").font(.pixel(13)).foregroundColor(Color(ui: 0xB8A8D8))
			if let s = picked, customChoice >= 0, let r = ModRuntime.shared.infusion(customChoice) {
				customPreview(s, r)
			} else if let s = picked, let i = inf {
				previewBody(s, i)
			} else {
				Text("Pick a piece of equipment and an infusion to see how it changes.")
					.font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.6))
			}
		}
	}

	func previewBody(_ s: Stack, _ i: Infusion) -> some View {
		let problem: String? = s.infuseProblem(i)
		let owned: Int = game.inv.total(.compound(i))
		var after: Stack = s
		after.inf = (s.inf ?? []) + [i.rawValue]
		let rows: [(String, String, String)] = game.infusionCompare(s, after)
		let ok: Bool = problem == nil && (owned > 0 || game.isCreative)
		return VStack(alignment: .leading, spacing: 5) {
			Text(verbatim: joinText(s.item.name, " + ", i.name)).font(.pixel(12))
			Text(verbatim: i.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8))
			ForEach(0..<rows.count, id: \.self) { k in
				HStack {
					Text(verbatim: rows[k].0).font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.75))
					Spacer(minLength: 4)
					Text(verbatim: rows[k].1).font(.pixel(11)).foregroundColor(Color.white.opacity(0.6))
					Text("→").font(.pixel(11)).foregroundColor(Color.white.opacity(0.6))
					Text(verbatim: rows[k].2).font(.pixel(11)).foregroundColor(rows[k].1 == rows[k].2 ? Color.white : Color(ui: 0x7AF08A))
				}
			}
			if let p = problem {
				Text(verbatim: p).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9A7A))
			} else if owned == 0 && !game.isCreative {
				Text(verbatim: joinText("You have no ", i.name, " compound: make one with MAKE COMPOUNDS.")).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9A7A))
			}
			PixelButton(title: ok ? "CONFIRM INFUSION" : "CAN'T INFUSE", color: ok ? Color(ui: 0x6A4AA8) : Color(ui: 0x444444)) {
				if !ok { return }
				note = game.infuse(slot: pick, i)
				choice = -1
			}
		}
		.padding(6)
		.background(Color.black.opacity(0.25))
	}
}

extension Game {
	/// Before-and-after numbers for an infusion preview: what a weapon, tool or armour piece does
	func infusionCompare(_ a: Stack, _ b: Stack) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let cls: [InfuseClass] = infuseClasses(a.item)
		func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
		func pct(_ v: Double) -> String { return joinText(String(Int((v * 100).rounded())), "%") }
		if cls.contains(.melee) {
			let p0: MeleeProfile = Game.infuseProfile(a.item.melee, a.inf ?? [])
			let p1: MeleeProfile = Game.infuseProfile(a.item.melee, b.inf ?? [])
			rows.append(("Damage", f1(p0.damage), f1(p1.damage)))
			rows.append(("Swing every", joinText(String(format: "%.2f", p0.cooldown), " s"), joinText(String(format: "%.2f", p1.cooldown), " s")))
			rows.append(("Reach", f1(p0.reach), f1(p1.reach)))
			rows.append(("Critical chance", pct(p0.critChance), pct(p1.critChance)))
			rows.append(("Knockback", f1(p0.knock), f1(p1.knock)))
		}
		if cls.contains(.ranged) {
			var d0: Double = 1
			var d1: Double = 1
			if a.has(.honed) { d0 *= 1.2 }
			if a.has(.voidrend) { d0 *= 1.15 }
			if b.has(.honed) { d1 *= 1.2 }
			if b.has(.voidrend) { d1 *= 1.15 }
			rows.append(("Shot damage", pct(d0), pct(d1)))
			rows.append(("Range", a.has(.longReach) ? "125%" : "100%", b.has(.longReach) ? "125%" : "100%"))
		}
		if cls.contains(.tool) {
			rows.append(("Mining speed", a.has(.haste) ? "125%" : "100%", b.has(.haste) ? "125%" : "100%"))
			rows.append(("Extra ore chance", a.has(.bountiful) ? "20%" : "0%", b.has(.bountiful) ? "20%" : "0%"))
		}
		if cls.contains(.armor) || cls.contains(.suit) {
			var x: ArmorInf = ArmorInf()
			x.add(a)
			var y: ArmorInf = ArmorInf()
			y.add(b)
			rows.append(("Extra defence", f1(x.defense), f1(y.defense)))
			if x.fireCut != y.fireCut { rows.append(("Fire and lava", joinText("-", pct(x.fireCut)), joinText("-", pct(y.fireCut)))) }
			if x.coldCut != y.coldCut { rows.append(("Cold", joinText("-", pct(x.coldCut)), joinText("-", pct(y.coldCut)))) }
			if x.stormCut != y.stormCut { rows.append(("Lightning and hail", joinText("-", pct(x.stormCut)), joinText("-", pct(y.stormCut)))) }
			if x.speed != y.speed { rows.append(("Run speed", joinText("+", pct(x.speed)), joinText("+", pct(y.speed)))) }
			if x.thorns != y.thorns { rows.append(("Blow returned", pct(x.thorns), pct(y.thorns))) }
			if x.knockMul != y.knockMul { rows.append(("Knockback taken", pct(x.knockMul), pct(y.knockMul))) }
			if x.regen != y.regen { rows.append(("Healing a minute", f1(x.regen * 60), f1(y.regen * 60))) }
		}
		rows.append(("Slots used", String(a.inf?.count ?? 0), String(b.inf?.count ?? 0)))
		return rows
	}

	/// Opens the crafting screen at a station (the crucible's compounds, the assembly station's parts)
	func openCrafting(_ s: Station) {
		showInfuse = false
		showExo = false
		craftStation = s
		showInventory = true
		bumpHUD()
	}

	/// The effects on the player, for the HUD: kind and seconds left
	func activeEffects() -> [(ModEffectKind, Double)] {
		var out: [(ModEffectKind, Double)] = []
		for k in ModEffectKind.allCases where k.timed && effects.time[k.rawValue] > 0 {
			out.append((k, effects.time[k.rawValue]))
		}
		if mendCD > 0 { out.append((.heal, mendCD)) }
		return out
	}
}

// MARK: - Assembly Station: the suit designer

/// A material a piece can be made of: one of the game's metals, or a mod's (by key)
struct SuitMatChoice {
	var mat: Int
	var key: String
	var name: String
	var color: UInt32
}

/// The Assembly Station: the suit designer. The body is drawn large; tap with a placing tool to put
/// down a plate or a frame piece, tap a piece to pick it and drag to move it, and set its size, turn,
/// shape, thickness, metal and paint. Working parts (cores, jets, turrets...) come from the bag. The
/// bill shows what the changes cost before BUILD makes them; nothing changes until then.
struct ExoAssemblyPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var plan: SuitDesign = SuitDesign()
	@State var started: Bool = false
	@State var pick: Int = -1
	/// 0 pick and move, 1 place plates, 2 place frame pieces
	@State var tool: Int = 0
	@State var matPick: Int = 0
	@State var shapePick: Int = 0
	@State var page: Int = 0
	@State var pose: Int = 0
	@State var undo: [SuitDesign] = []
	@State var note: String = ""
	@State var grabbing: Bool = false
	@State var grabStart: CGPoint = .zero
	@State var grabFrom: CGPoint = .zero
	@State var colorOn: Bool = false
	@State var paint: UInt32 = 0xC8CCD4
	@State var templateMat: Int = 0

	/// screen points to a suit unit on the canvas, and the strip of the frame it shows (suit units)
	static let k: CGFloat = 6.5
	static let cropX: Double = 6
	static let cropW: Double = 54
	static let tools: [String] = ["PICK / MOVE", "PLACE PLATES", "PLACE FRAMES"]
	static let pages: [String] = ["PIECE", "PARTS", "SUIT"]
	static let poses: [String] = ["STAND", "WALK", "STRIDE", "WIND UP", "STRIKE", "BLOCK", "SHOOT"]
	static let thick: [String] = ["THIN", "DOUBLE", "TRIPLE"]

	var body: some View {
		VStack(spacing: 8) {
			header
			ScrollView {
				HStack(alignment: .top, spacing: 12) {
					leftColumn
					rightColumn.frame(width: 380)
				}
				.padding(.bottom, 12)
			}
		}
		.foregroundColor(Color.white)
		.padding(12)
		.background(PixelBox(color: Color(ui: 0x262A32)).opacity(0.97))
		.frame(maxWidth: 1000)
		.padding(8)
		.onAppear { self.begin() }
	}

	func begin() {
		if started { return }
		started = true
		plan = game.suit.d
	}

	var changed: Bool { return plan != game.suit.d }

	var header: some View {
		let st: ExoStats = ExoStats.of(plan)
		let line: String = joinText(String(plan.pieces.count), " pieces · weight ", String(Int(st.weight.rounded())), " / ", String(Int(st.strength)), " · guards ", String(Int((st.guardAll * 100).rounded())), "%")
		return HStack(spacing: 8) {
			Text("ASSEMBLY STATION").font(.pixel(20)).foregroundColor(Color(ui: 0x60E0FF))
			Text(verbatim: line).font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.75))
			Spacer()
			SmallButton(title: "MAKE PARTS", color: Color(ui: 0x4A5A3A)) { self.game.openCrafting(.assembly) }
			SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { self.close() }
		}
	}

	func close() {
		game.showExo = false
		game.bumpHUD()
	}

	// MARK: the body and its pieces

	var leftColumn: some View {
		VStack(alignment: .leading, spacing: 8) {
			ChoiceRows(options: ExoAssemblyPanel.tools, selected: $tool, columns: 3)
			canvas
			ChoiceRows(options: ExoAssemblyPanel.poses, selected: $pose, columns: 4)
			billBox
			buildRow
			if !note.isEmpty { Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(ui: 0xFFE070)) }
		}
	}

	/// The figure in its suit, large; touches place, pick and move pieces (on the body standing still)
	var canvas: some View {
		let k: CGFloat = ExoAssemblyPanel.k
		let w: CGFloat = CGFloat(ExoAssemblyPanel.cropW) * k
		let h: CGFloat = CGFloat(suitBodyH) * k
		let img: Image = SuitPictures.shared.image(plan, pose == 0 ? 0 : clampI(pose, 0, 6), pick)
		let fullW: CGFloat = CGFloat(humanW * suitUnit) * k
		let off: CGFloat = -CGFloat(ExoAssemblyPanel.cropX) * k
		return ZStack(alignment: .topLeading) {
			Rectangle().fill(Color.black.opacity(0.35))
			grid(w, h)
			img.resizable().interpolation(.none).frame(width: fullW, height: h).offset(x: off, y: 0)
		}
		.frame(width: w, height: h)
		.clipped()
		.overlay(Rectangle().stroke(Color.white.opacity(0.25), lineWidth: 1))
		.gesture(DragGesture(minimumDistance: 0).onChanged { (v: DragGesture.Value) in self.touchMoved(v.startLocation, v.location) }.onEnded { (v: DragGesture.Value) in self.touchEnded(v.startLocation, v.location) })
	}

	/// faint lines every sprite pixel, so pieces can be lined up
	func grid(_ w: CGFloat, _ h: CGFloat) -> some View {
		let k: CGFloat = ExoAssemblyPanel.k
		let step: CGFloat = k * CGFloat(suitUnit)
		return Canvas { ctx, size in
			var p: Path = Path()
			var x: CGFloat = 0
			while x <= w {
				p.addRect(CGRect(x: x, y: 0, width: 1, height: h))
				x += step
			}
			var y: CGFloat = 0
			while y <= h {
				p.addRect(CGRect(x: 0, y: y, width: w, height: 1))
				y += step
			}
			ctx.fill(p, with: .color(Color.white.opacity(0.06)))
		}
	}

	/// a point on the canvas as a point on the body (suit units from the figure's left edge)
	func bodyPoint(_ p: CGPoint) -> (Double, Double) {
		let k: Double = Double(ExoAssemblyPanel.k)
		let fx: Double = Double(p.x) / k + ExoAssemblyPanel.cropX
		let fy: Double = Double(p.y) / k
		return (fx - Double(humanOX * suitUnit), fy)
	}

	/// the outermost piece under a body point
	func pieceAt(_ x: Double, _ y: Double) -> Int? {
		var best: Int? = nil
		var bestKey: Int = -1
		for (i, p) in plan.pieces.enumerated() where p.covers(x, y) {
			let key: Int = p.bone.layer * 1000 + i
			if key > bestKey {
				bestKey = key
				best = i
			}
		}
		return best
	}

	func touchMoved(_ start: CGPoint, _ now: CGPoint) {
		if tool != 0 || pose != 0 { return }
		if !grabbing {
			grabbing = true
			let b: (Double, Double) = bodyPoint(start)
			if let i = pieceAt(b.0, b.1) {
				pick = plan.pieces[i].id
				remember()
				grabStart = start
				grabFrom = CGPoint(x: plan.pieces[i].x, y: plan.pieces[i].y)
			} else {
				pick = -1
				grabStart = .zero
			}
			return
		}
		guard grabStart != .zero, let i = plan.index(pick) else { return }
		let k: Double = Double(ExoAssemblyPanel.k)
		var p: SuitPiece = plan.pieces[i]
		// moves snap to whole suit units
		p.x = (Double(grabFrom.x) + Double(now.x - grabStart.x) / k).rounded()
		p.y = (Double(grabFrom.y) + Double(now.y - grabStart.y) / k).rounded()
		p.clamp()
		plan.pieces[i] = p
	}

	func touchEnded(_ start: CGPoint, _ end: CGPoint) {
		defer {
			grabbing = false
			grabStart = .zero
		}
		if pose != 0 {
			note = "Pick STAND to change the suit (the other poses show how it moves)."
			return
		}
		if tool == 0 { return }
		let b: (Double, Double) = bodyPoint(end)
		if plan.pieces.count >= SuitDesign.maxPieces {
			note = joinText("A suit holds at most ", String(SuitDesign.maxPieces), " pieces.")
			return
		}
		remember()
		var p = SuitPiece()
		p.kind = tool == 1 ? .plate : .frame
		p.x = b.0.rounded()
		p.y = b.1.rounded()
		p.w = tool == 1 ? 6 : 4
		p.h = tool == 1 ? 6 : 2
		p.shape = SuitShape(rawValue: shapePick) ?? .box
		applyMaterial(&p, matPick)
		p.bone = SuitBody.bone(p.x, p.y)
		p.id = plan.newID()
		p.clamp()
		plan.pieces.append(p)
		pick = p.id
		note = ""
	}

	func remember() {
		undo.append(plan)
		if undo.count > 60 { undo.removeFirst() }
	}

	// MARK: materials

	var materials: [SuitMatChoice] {
		var out: [SuitMatChoice] = []
		for m in ExoMat.allCases { out.append(SuitMatChoice(mat: m.rawValue, key: "", name: m.name, color: m.color)) }
		for k in ModRuntime.shared.suitMats.keys.sorted() {
			if let i = ModRuntime.shared.suitMats[k] { out.append(SuitMatChoice(mat: 0, key: k, name: i.name, color: i.color)) }
		}
		return out
	}

	func applyMaterial(_ p: inout SuitPiece, _ i: Int) {
		let list: [SuitMatChoice] = materials
		let c: SuitMatChoice = list[clampI(i, 0, list.count - 1)]
		p.mat = c.mat
		p.modMat = c.key
	}

	func materialIndex(_ p: SuitPiece) -> Int {
		let list: [SuitMatChoice] = materials
		if !p.modMat.isEmpty { return list.firstIndex { $0.key == p.modMat } ?? 0 }
		return list.firstIndex { $0.key.isEmpty && $0.mat == p.mat } ?? 0
	}

	// MARK: the right column

	var rightColumn: some View {
		VStack(alignment: .leading, spacing: 8) {
			ChoiceRows(options: ExoAssemblyPanel.pages, selected: $page, columns: 3)
			pageView
		}
	}

	@ViewBuilder
	var pageView: some View {
		switch page {
		case 1: partsPage
		case 2: suitPage
		default: piecePage
		}
	}

	var piecePage: some View {
		VStack(alignment: .leading, spacing: 8) {
			newPieceBox
			if let i = plan.index(pick) { pieceBox(i) } else {
				Text("Tap a piece to pick it, or choose PLACE PLATES and tap the body.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
		}
	}

	/// what a placing tap puts down
	var newPieceBox: some View {
		let names: [String] = materials.map { $0.name }
		return VStack(alignment: .leading, spacing: 6) {
			Text("NEW PIECES").font(.pixel(12)).foregroundColor(ModUI.gold)
			ChoiceRows(options: names, selected: $matPick, columns: 4)
			ChoiceRows(options: SuitShape.allCases.map { $0.name }, selected: $shapePick, columns: 5)
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func pb<T>(_ i: Int, _ kp: WritableKeyPath<SuitPiece, T>) -> Binding<T> {
		let id: Int = plan.pieces[i].id
		return Binding<T>(get: {
			guard let j = self.plan.index(id) else { return self.plan.pieces[0][keyPath: kp] }
			return self.plan.pieces[j][keyPath: kp]
		}, set: { v in
			guard let j = self.plan.index(id) else { return }
			var p: SuitPiece = self.plan.pieces[j]
			p[keyPath: kp] = v
			p.clamp()
			self.plan.pieces[j] = p
		})
	}

	func pieceBox(_ i: Int) -> some View {
		let p: SuitPiece = plan.pieces[i]
		let title: String = game.suitPieceName(p).uppercased()
		let wear: String = p.dmg > 0.001 ? joinText(" · worn ", String(Int((p.dmg * 100).rounded())), "%") : ""
		let made: String = p.kind == .plate || p.kind == .frame ? joinText(suitMat(p).name, " ", p.kind.name.lowercased()) : p.kind.name
		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: title).font(.pixel(13)).foregroundColor(ModUI.gold)
			Text(verbatim: joinText(made, " on the ", p.bone.name.lowercased(), wear)).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			sizeControls(i)
			if p.kind == .plate || p.kind == .frame { makeControls(i) }
			nudgeRow(i)
			actionRow(i)
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func sizeControls(_ i: Int) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			StatSlider(label: "Width", value: pb(i, \.w), range: 1.0...30.0, step: 1, format: "%.0f")
			StatSlider(label: "Height", value: pb(i, \.h), range: 1.0...30.0, step: 1, format: "%.0f")
			StatSlider(label: "Turn", value: pb(i, \.rot), range: -180.0...180.0, step: 5, format: "%.0f°")
			ChoiceRows(options: SuitShape.allCases.map { $0.name }, selected: shapeBind(i), columns: 5)
			ChoiceRows(options: SuitBone.allCases.map { $0.name }, selected: boneBind(i), columns: 4)
		}
	}

	func makeControls(_ i: Int) -> some View {
		let names: [String] = materials.map { $0.name }
		let painted: Bool = plan.pieces[i].color != 0
		return VStack(alignment: .leading, spacing: 4) {
			ChoiceRows(options: ExoAssemblyPanel.thick, selected: thickBind(i), columns: 3)
			ChoiceRows(options: names, selected: matBind(i), columns: 4)
			ModToggle(label: "Painted", help: "Off: the metal's own colour", isOn: paintedBind(i))
			if painted { ModColorRow(label: "Paint", color: pb(i, \.color)) }
		}
	}

	func nudgeRow(_ i: Int) -> some View {
		HStack(spacing: 6) {
			SmallButton(title: "\u{2190}") { self.nudge(i, -1, 0) }
			SmallButton(title: "\u{2192}") { self.nudge(i, 1, 0) }
			SmallButton(title: "\u{2191}") { self.nudge(i, 0, -1) }
			SmallButton(title: "\u{2193}") { self.nudge(i, 0, 1) }
			SmallButton(title: "TO FRONT") { self.layer(i, 1) }
			SmallButton(title: "TO BACK") { self.layer(i, -1) }
		}
	}

	func actionRow(_ i: Int) -> some View {
		HStack(spacing: 6) {
			SmallButton(title: "COPY", color: ModUI.blue) { self.duplicate(i, false) }
			SmallButton(title: "MIRROR", color: ModUI.blue) { self.duplicate(i, true) }
			SmallButton(title: "REMOVE", color: ModUI.red) { self.removePiece(i) }
		}
	}

	func shapeBind(_ i: Int) -> Binding<Int> {
		let b: Binding<SuitShape> = pb(i, \.shape)
		return Binding<Int>(get: { b.wrappedValue.rawValue }, set: { b.wrappedValue = SuitShape(rawValue: $0) ?? .box })
	}

	func boneBind(_ i: Int) -> Binding<Int> {
		let b: Binding<SuitBone> = pb(i, \.bone)
		return Binding<Int>(get: { b.wrappedValue.rawValue }, set: { b.wrappedValue = SuitBone(rawValue: $0) ?? .torso })
	}

	func thickBind(_ i: Int) -> Binding<Int> {
		let b: Binding<Int> = pb(i, \.thick)
		return Binding<Int>(get: { b.wrappedValue - 1 }, set: { b.wrappedValue = $0 + 1 })
	}

	func matBind(_ i: Int) -> Binding<Int> {
		let id: Int = plan.pieces[i].id
		return Binding<Int>(get: {
			guard let j = self.plan.index(id) else { return 0 }
			return self.materialIndex(self.plan.pieces[j])
		}, set: { v in
			guard let j = self.plan.index(id) else { return }
			var p: SuitPiece = self.plan.pieces[j]
			self.applyMaterial(&p, v)
			self.plan.pieces[j] = p
		})
	}

	func paintedBind(_ i: Int) -> Binding<Bool> {
		let b: Binding<UInt32> = pb(i, \.color)
		let base: UInt32 = suitMat(plan.pieces[i]).color
		return Binding<Bool>(get: { b.wrappedValue != 0 }, set: { on in b.wrappedValue = on ? base : 0 })
	}

	func nudge(_ i: Int, _ dx: Double, _ dy: Double) {
		remember()
		var p: SuitPiece = plan.pieces[i]
		p.x += dx
		p.y += dy
		p.clamp()
		plan.pieces[i] = p
	}

	/// moves a piece over (or under) the others on its part of the body
	func layer(_ i: Int, _ dir: Int) {
		remember()
		let p: SuitPiece = plan.pieces.remove(at: i)
		if dir > 0 { plan.pieces.append(p) } else { plan.pieces.insert(p, at: 0) }
	}

	/// a copy beside it, or mirrored to the other side of the body (the other arm or leg)
	func duplicate(_ i: Int, _ mirror: Bool) {
		if plan.pieces.count >= SuitDesign.maxPieces { return }
		var p: SuitPiece = plan.pieces[i]
		if p.kind == .core || p.kind == .module {
			note = "Working parts come from the bag: add another from PARTS."
			return
		}
		remember()
		if mirror {
			p.x = suitBodyW - p.x
			p.rot = -p.rot
			p.bone = p.bone.other
		} else {
			p.x += 3
			p.y += 3
		}
		p.id = plan.newID()
		p.dmg = 0
		p.src = 0
		p.clamp()
		plan.pieces.append(p)
		pick = p.id
	}

	func removePiece(_ i: Int) {
		remember()
		plan.pieces.remove(at: i)
		pick = -1
	}

	// MARK: working parts from the bag

	/// cores and working parts that can go on: those in the bag (all of them in creative)
	var partChoices: [Stack] {
		var out: [Stack] = []
		if game.isCreative {
			for c in ExoCore.allCases { out.append(Stack(item: .exoCore(c), count: 1)) }
			for m in ExoModule.allCases { out.append(Stack(item: .exoModule(m), count: 1)) }
			return out
		}
		let inPlan: [Stack] = Array(plan.items.values)
		var used: [Stack] = inPlan
		for s in game.inv.slots {
			guard let st = s else { continue }
			switch st.item {
			case .exoCore, .exoModule:
				if let j = used.firstIndex(of: st) { used.remove(at: j) } else { out.append(st) }
			case .custom(let k):
				if ModRuntime.shared.suitParts[k] != nil {
					if let j = used.firstIndex(of: st) { used.remove(at: j) } else { out.append(st) }
				}
			default: break
			}
		}
		return out
	}

	var partsPage: some View {
		let list: [Stack] = partChoices
		return VStack(alignment: .leading, spacing: 6) {
			Text("Cores give energy; parts work: jets lift, wings glide, turrets shoot by themselves, cannons and lasers fire with SUIT FIRE. Each goes on where you put it.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if list.isEmpty { Text("No cores or suit parts in your bag. MAKE PARTS shows what can be made here.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9060)) }
			ForEach(0..<list.count, id: \.self) { (i: Int) in self.partRow(list[i]) }
		}
	}

	func partRow(_ st: Stack) -> some View {
		let info: String = partBlurb(st.item)
		return HStack(spacing: 8) {
			SlotView(stack: st, size: 38)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: st.item.name).font(.pixel(12)).foregroundColor(Color.white)
				Text(verbatim: info).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 0)
			SmallButton(title: "ADD", color: ModUI.accent) { self.addPart(st) }
		}
		.padding(6)
		.background(PixelBox(color: ModUI.card))
	}

	func partBlurb(_ it: Item) -> String {
		switch it {
		case .exoCore(let c): return joinText("Holds ", String(Int(c.capacity)), ", gives ", String(Int(c.output)), " a second")
		case .exoModule(let m): return m.blurb
		case .custom(let k): return ModRuntime.shared.suitParts[k].map { joinText("Works as: ", $0.works.name) } ?? ""
		default: return ""
		}
	}

	func addPart(_ st: Stack) {
		if plan.pieces.count >= SuitDesign.maxPieces { return }
		var p: SuitPiece
		switch st.item {
		case .exoCore(let c): p = SuitTemplates.core(c)
		case .exoModule(let m): p = SuitTemplates.module(m)
		case .custom(let k):
			guard let mp = ModRuntime.shared.suitParts[k] else { return }
			p = SuitTemplates.module(mp.works)
			p.modPart = k
		default: return
		}
		remember()
		if !game.isCreative {
			let g: Int = plan.newGroup()
			plan.items[g] = st
			p.src = g
		}
		p.id = plan.newID()
		plan.pieces.append(p)
		pick = p.id
		page = 0
	}

	// MARK: the whole suit

	var suitPage: some View {
		let st: ExoStats = ExoStats.of(plan)
		return VStack(alignment: .leading, spacing: 8) {
			statsBox(st)
			templateBox
			modDesignBox
			repairBox
			wearRow
		}
	}

	func statsBox(_ st: ExoStats) -> some View {
		let energy: String = joinText("Energy ", String(Int(st.capacity)), " · gives ", String(Int(st.output)), "/s · refills ", String(format: "%.1f", st.recharge), "/s")
		let move: String = joinText("Speed ", String(Int((st.speedMul * 100).rounded())), "% · jump ", String(Int((st.jumpMul * 100).rounded())), "%", st.has(.hover) ? joinText(" · jets lift ", String(Int((st.thrust * 100).rounded())), "%") : "")
		let parts: String = st.modules.isEmpty ? "No working parts" : st.modules.map { $0.name }.joined(separator: ", ")
		return VStack(alignment: .leading, spacing: 4) {
			Text("HOW IT GUARDS").font(.pixel(12)).foregroundColor(ModUI.gold)
			ForEach(SuitSection.allCases, id: \.self) { (s: SuitSection) in self.coverRow(s, st) }
			Text(verbatim: energy).font(.pixel(11, .semibold)).foregroundColor(Color.white)
			Text(verbatim: move).font(.pixel(11, .semibold)).foregroundColor(Color.white)
			Text(verbatim: parts).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<st.notes.count, id: \.self) { (k: Int) in
				Text(verbatim: st.notes[k]).font(.pixel(10, .semibold)).foregroundColor(Color(ui: 0xFF9060))
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func coverRow(_ s: SuitSection, _ st: ExoStats) -> some View {
		let cov: Double = st.cover[s.rawValue]
		let g: Double = st.guardBy[s.rawValue]
		let label: String = joinText(s.name, ": covered ", String(Int((cov * 100).rounded())), "%, stops ", String(Int((g * 100).rounded())), "%")
		return VStack(alignment: .leading, spacing: 1) {
			Text(verbatim: label).font(.pixel(10, .semibold)).foregroundColor(Color.white)
			ZStack(alignment: .leading) {
				Rectangle().fill(Color.black.opacity(0.5)).frame(width: 300, height: 6)
				Rectangle().fill(Color(hex: 0x60E0FF)).frame(width: CGFloat(300.0 * clampD(g, 0, 1)), height: 6)
			}
		}
	}

	var templateBox: some View {
		let mats: [String] = ExoMat.allCases.map { $0.name }
		return VStack(alignment: .leading, spacing: 6) {
			Text("START FROM").font(.pixel(12)).foregroundColor(ModUI.gold)
			ChoiceRows(options: mats, selected: $templateMat, columns: 4)
			PlainGrid(count: SuitTemplates.names.count, per: 5) { (i: Int) in
				SmallButton(title: SuitTemplates.names[i].uppercased(), color: ModUI.blue) { self.loadTemplate(i) }
			}
			Text("Plates of the chosen metal; parts it needs come from your bag.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	/// Replaces the plan with a ready-made design (its working parts only where the bag has them)
	func loadTemplate(_ i: Int) {
		remember()
		let m: ExoMat = ExoMat(rawValue: clampI(templateMat, 0, ExoMat.allCases.count - 1)) ?? .iron
		var t: SuitDesign = SuitTemplates.design(i, m)
		var keep: [SuitPiece] = []
		var items: [Int: Stack] = [:]
		var bag: [Stack] = partChoices
		var missing: [String] = []
		for var p in t.pieces {
			if p.kind == .core || p.kind == .module {
				if !game.isCreative {
					let want: Item = p.kind == .core ? .exoCore(ExoCore(rawValue: p.part) ?? .sparkCell) : .exoModule(ExoModule(rawValue: p.part) ?? .hover)
					guard let j = bag.firstIndex(where: { $0.item == want }) else {
						missing.append(want.name)
						continue
					}
					var g: Int = 1
					while items[g] != nil { g += 1 }
					items[g] = bag.remove(at: j)
					p.src = g
				}
			}
			keep.append(p)
		}
		t.pieces = keep
		t.items = items
		// the parts already on the suit stay on (they are not lost by starting over)
		for p in plan.pieces where p.kind == .core || p.kind == .module {
			var q: SuitPiece = p
			q.id = t.newID()
			if p.src != 0, let st = plan.items[p.src] {
				let g: Int = t.newGroup()
				t.items[g] = st
				q.src = g
			}
			t.pieces.append(q)
		}
		plan = t
		pick = -1
		note = missing.isEmpty ? "" : joinText("Not in your bag (left off): ", missing.joined(separator: ", "), ".")
	}

	var repairBox: some View {
		let bill: [Item: Int] = game.suit.d.repairBill()
		let text: String = bill.isEmpty ? "Every piece is whole." : bill.map { joinText(String($0.value), " ", $0.key.name) }.sorted().joined(separator: ", ")
		let can: Bool = !bill.isEmpty
		return VStack(alignment: .leading, spacing: 6) {
			Text("MEND").font(.pixel(12)).foregroundColor(ModUI.gold)
			Text(verbatim: text).font(.pixel(11, .semibold)).foregroundColor(Color.white)
			if can { SmallButton(title: "MEND EVERY PIECE", color: ModUI.accent) { self.mend() } }
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func mend() {
		note = game.repairSuit()
		// the plan keeps up with the mended suit (pieces it still has as they are)
		var p: SuitDesign = plan
		for k in p.pieces.indices { p.pieces[k].dmg = 0 }
		plan = p
	}

	var wearRow: some View {
		let worn: Bool = game.suit.worn
		return HStack(spacing: 8) {
			SmallButton(title: worn ? "TAKE OFF" : "PUT ON", color: worn ? Color(ui: 0x6A4A3A) : ModUI.accent) { self.wear() }
		}
	}

	func wear() {
		if game.suit.worn {
			note = game.takeOffSuit()
		} else {
			if changed {
				note = "BUILD the changes first."
				return
			}
			note = game.wearSuit()
		}
	}

	// MARK: the bill and building

	var billBox: some View {
		let b: SuitBill = game.suit.d.bill(to: plan)
		let pay: String = b.payText()
		var back: [String] = []
		for (it, n) in b.back.sorted(by: { $0.key.name < $1.key.name }) { back.append(joinText(String(n), " ", it.name)) }
		for st in b.give { back.append(st.item.name) }
		let free: Bool = game.isCreative
		return VStack(alignment: .leading, spacing: 3) {
			Text(verbatim: pay.isEmpty ? "Costs nothing" : joinText("Costs: ", pay, free ? " (free in creative)" : "")).font(.pixel(11, .semibold)).foregroundColor(Color.white)
			if !back.isEmpty { Text(verbatim: joinText("Gives back: ", back.joined(separator: ", "))).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim) }
		}
	}

	var buildRow: some View {
		let can: Bool = changed
		return HStack(spacing: 8) {
			SmallButton(title: "BUILD", color: can ? ModUI.accent : Color(ui: 0x3A3E48)) { self.build() }
			SmallButton(title: "UNDO", color: undo.isEmpty ? Color(ui: 0x3A3E48) : Color(ui: 0x5A6270)) { self.undoLast() }
			SmallButton(title: "START AGAIN", color: Color(ui: 0x5A6270)) { self.reset() }
		}
	}

	func build() {
		if !changed {
			note = "Nothing has changed."
			return
		}
		note = game.applyDesign(plan)
		plan = game.suit.d
		if plan.index(pick) == nil { pick = -1 }
	}

	func undoLast() {
		guard let u = undo.popLast() else { return }
		plan = u
		if plan.index(pick) == nil { pick = -1 }
	}

	func reset() {
		remember()
		plan = game.suit.d
		pick = -1
		note = ""
	}
}

// MARK: - Mod Creator: suits (materials, parts, designs)

/// The SUITS tab: a mod's suit materials, its working parts (items placed on suits) and whole suit
/// designs to start from
struct SuitListView: View {
	@ObservedObject var s: ModSession
	var openMat: (String) -> Void
	var openPart: (String) -> Void
	var openDesign: (String) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Suits are built piece by piece at an Assembly Station. A mod can add metals to build them from, working parts to put on them (each an item your recipes make), and whole designs to start from.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			matSection
			partSection
			designSection
		}
	}

	var matSection: some View {
		let can: Bool = s.mod.suitMats.count < ModSuitLimits.mats
		return ModSection(title: "MATERIALS") {
			if can { SmallButton(title: "+ NEW MATERIAL", color: ModUI.accent) { self.addMat() } }
			ForEach(s.mod.suitMats) { (m: ModSuitMat) in self.matRow(m) }
		}
	}

	func matRow(_ m: ModSuitMat) -> some View {
		let line: String = String(format: "Guards x%.1f · weight x%.1f · lasts x%.1f", m.protect, m.weight, m.durability)
		return HStack(spacing: 8) {
			Rectangle().fill(Color(hex: m.color & 0xFFFFFF)).frame(width: 28, height: 28).overlay(Rectangle().stroke(Color.black, lineWidth: 1))
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: m.name).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 0)
			SmallButton(title: "EDIT", color: ModUI.blue) { self.openMat(m.id) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.s.mod.suitMats.removeAll { $0.id == m.id }; self.s.touch() }
		}
	}

	var partSection: some View {
		let can: Bool = s.mod.suitParts.count < ModSuitLimits.parts
		return ModSection(title: "WORKING PARTS", help: "Each is an item: give it a recipe on the RECIPES tab, then place it on a suit.") {
			if can { SmallButton(title: "+ NEW PART", color: ModUI.accent) { self.addPart() } }
			ForEach(s.mod.suitParts) { (p: ModSuitPart) in self.partRow(p) }
		}
	}

	func partRow(_ p: ModSuitPart) -> some View {
		let line: String = joinText("Works as a ", p.works.name.lowercased(), String(format: " · strength x%.1f · weight %.0f", p.power, p.weight))
		return HStack(spacing: 8) {
			Rectangle().fill(Color(hex: p.color & 0xFFFFFF)).frame(width: 28, height: 28).overlay(Rectangle().stroke(Color.black, lineWidth: 1))
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: p.name).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 0)
			SmallButton(title: "EDIT", color: ModUI.blue) { self.openPart(p.id) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.s.mod.suitParts.removeAll { $0.id == p.id }; self.s.touch() }
		}
	}

	var designSection: some View {
		ModSection(title: "DESIGNS", help: "Build a suit at an Assembly Station in a TEST world, then SAVE TO THIS MOD there. Players start from it at their own station.") {
			if s.mod.suitDesigns.isEmpty { Text("No designs yet.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim) }
			ForEach(s.mod.suitDesigns) { (d: ModSuitDesign) in self.designRow(d) }
		}
	}

	func designRow(_ d: ModSuitDesign) -> some View {
		let pic: Image = SuitPictures.shared.image(d.design, 0, -1)
		return HStack(spacing: 8) {
			pic.resizable().interpolation(.none).frame(width: 66, height: 51)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: d.name).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: joinText(String(d.design.pieces.count), " pieces")).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 0)
			SmallButton(title: "EDIT", color: ModUI.blue) { self.openDesign(d.id) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.s.mod.suitDesigns.removeAll { $0.id == d.id }; self.s.touch() }
		}
	}

	func addMat() {
		var m = ModSuitMat()
		m.id = s.mod.freshID("smat")
		m.name = joinText("Metal ", String(s.mod.suitMats.count + 1))
		s.mod.suitMats.append(m)
		s.touch()
		openMat(m.id)
	}

	func addPart() {
		var p = ModSuitPart()
		p.id = s.mod.freshID("spart")
		p.name = joinText("Part ", String(s.mod.suitParts.count + 1))
		s.mod.suitParts.append(p)
		s.touch()
		openPart(p.id)
	}
}

/// Editing a mod's suit material: name, colour, its numbers, and what it is paid with
struct SuitMatEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var picking: Bool = false

	func b<T>(_ kp: WritableKeyPath<ModSuitMat, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.suitMats, id, kp, d) }
	var mat: ModSuitMat { return s.mod.suitMats.first { $0.id == id } ?? ModSuitMat() }

	static let numbers: [DSlider<ModSuitMat>] = [
		DSlider(label: "Guards (iron 1)", kp: \.protect, lo: 0.2, hi: 3, sbHi: 6, step: 0.05, format: "%.2f"),
		DSlider(label: "Weight (iron 1)", kp: \.weight, lo: 0.2, hi: 3, sbHi: 6, step: 0.05, format: "%.2f"),
		DSlider(label: "Lasts (iron 1)", kp: \.durability, lo: 0.2, hi: 4, sbHi: 8, step: 0.05, format: "%.2f"),
		DSlider(label: "Carries energy (iron 1)", kp: \.conduct, lo: 0.5, hi: 2, sbHi: 4, step: 0.05, format: "%.2f"),
		DSlider(label: "Less fire, each piece", kp: \.fireCut, lo: 0, hi: 0.1, sbHi: 0.1, step: 0.01, format: "%.2f"),
		DSlider(label: "Less cold, each piece", kp: \.coldCut, lo: 0, hi: 0.1, sbHi: 0.1, step: 0.01, format: "%.2f"),
		DSlider(label: "Less lightning, each piece", kp: \.stormCut, lo: 0, hi: 0.1, sbHi: 0.1, step: 0.01, format: "%.2f")
	]

	var body: some View {
		let m: ModSuitMat = mat
		let costName: String = m.cost.map { ModPreview.name($0, s.catalog) } ?? "Iron Bar"
		return VStack(spacing: 10) {
			ModSection(title: m.name.uppercased()) {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Starsteel")
				ModColorRow(label: "Colour", color: b(\.color, 0x8AC8E8))
			}
			ModSection(title: "NUMBERS", help: "A plate's guard is 20% a layer times this; heavier suits are slower unless strong; lasting longer means more blows before a piece breaks.") {
				sliders
				IntSlider(label: "Drill tier (a drill of it bores up to)", value: b(\.drillTier, 4), range: 0...9)
			}
			ModSection(title: "PAID WITH", help: "Pieces cost units of this, by their size.") {
				HStack(spacing: 8) {
					Text(verbatim: costName).font(.pixel(13)).foregroundColor(Color.white)
					Spacer(minLength: 0)
					SmallButton(title: "CHOOSE...", color: ModUI.blue) { self.picking = true }
					SmallButton(title: "IRON BARS") { self.b(\.cost, nil).wrappedValue = nil }
				}
			}
		}
		.modCover(s, picking ? 1 : nil) { self.picker }
	}

	var sliders: some View {
		let sb: Bool = s.mod.sandbox
		return VStack(alignment: .leading, spacing: 8) {
			ForEach(0..<SuitMatEditorView.numbers.count, id: \.self) { (i: Int) in self.slider(SuitMatEditorView.numbers[i], sb) }
		}
	}

	func slider(_ d: DSlider<ModSuitMat>, _ sb: Bool) -> StatSlider {
		let r: ClosedRange<Double> = d.lo...(sb ? d.sbHi : d.hi)
		return StatSlider(label: d.label, value: b(d.kp, 0), range: r, step: d.step, format: d.format)
	}

	var picker: some View {
		ItemPickerView(catalog: s.catalog, title: "PAID WITH...", pick: { (it: Item) in
			self.b(\.cost, nil).wrappedValue = it
			self.picking = false
		}, cancel: { self.picking = false })
	}
}

/// Editing a mod's suit part: name and words, what it works as and how strongly, its weight, colour
/// and icon
struct SuitPartEditorView: View {
	@ObservedObject var s: ModSession
	let id: String

	func b<T>(_ kp: WritableKeyPath<ModSuitPart, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.suitParts, id, kp, d) }
	var part: ModSuitPart { return s.mod.suitParts.first { $0.id == id } ?? ModSuitPart() }

	static let works: [String] = ExoModule.allCases.map { $0.name }

	var body: some View {
		let p: ModSuitPart = part
		let top: Double = s.mod.sandbox ? 10 : 4
		return VStack(spacing: 10) {
			ModSection(title: p.name.uppercased()) {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Plasma Lance")
				ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
			}
			ModSection(title: "WORKS AS", help: p.works.blurb) {
				ChoiceRows(options: SuitPartEditorView.works, selected: worksBind, columns: 4)
				StatSlider(label: "Strength (the game's part is 1)", value: b(\.power, 1), range: 0.25...top, step: 0.05, format: "%.2f")
				StatSlider(label: "Weight", value: b(\.weight, 2), range: 0.0...10.0, step: 0.5, format: "%.1f")
			}
			ModSection(title: "LOOK", help: "Its colour on the suit, and its icon (blank: the game part's icon in this colour).") {
				ModColorRow(label: "Colour", color: b(\.color, 0x8A929E))
				PixelEditorView(pixels: b(\.icon, ModPixels(w: 12, h: 12)), maxSide: 220, outlineDefault: true)
			}
		}
	}

	var worksBind: Binding<Int> {
		let base: Binding<ExoModule> = b(\.works, .turret)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ExoModule(rawValue: $0) ?? .turret })
	}
}

/// A mod's saved suit design: its name and picture (designs are built at an Assembly Station)
struct SuitDesignEditorView: View {
	@ObservedObject var s: ModSession
	let id: String

	func b<T>(_ kp: WritableKeyPath<ModSuitDesign, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.suitDesigns, id, kp, d) }
	var design: ModSuitDesign { return s.mod.suitDesigns.first { $0.id == id } ?? ModSuitDesign() }

	var body: some View {
		let d: ModSuitDesign = design
		let st: ExoStats = ExoStats.of(d.design)
		let line: String = joinText(String(d.design.pieces.count), " pieces · weight ", String(Int(st.weight.rounded())), " · guards ", String(Int((st.guardAll * 100).rounded())), "% on average")
		let pic: Image = SuitPictures.shared.image(d.design, 0, -1)
		return ModSection(title: d.name.uppercased(), help: "To change its pieces, build it again at an Assembly Station in a TEST world and save it over this one.") {
			ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Knight of the Deep")
			pic.resizable().interpolation(.none).frame(width: 264, height: 204)
			Text(verbatim: line).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
		}
	}
}

extension ExoAssemblyPanel {
	/// the mods' designs to start from
	var modDesignBox: some View {
		let list: [(String, SuitDesign)] = ModRuntime.shared.suitDesigns
		let testing: Bool = !game.testMod.isEmpty
		return VStack(alignment: .leading, spacing: 6) {
			if !list.isEmpty {
				Text("FROM MODS").font(.pixel(12)).foregroundColor(ModUI.gold)
				ForEach(0..<list.count, id: \.self) { (i: Int) in
					SmallButton(title: list[i].0.uppercased(), color: ModUI.blue) { self.loadDesign(list[i].1) }
				}
			}
			if testing {
				Text("This is a TEST world: keep this design in the mod.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				SmallButton(title: "SAVE TO THE MOD AS A DESIGN", color: ModUI.accent) { self.saveToMod() }
			}
		}
	}

	/// Starts from a mod's design (its working parts only where the bag has them)
	func loadDesign(_ d0: SuitDesign) {
		remember()
		var t: SuitDesign = SuitDesign()
		var bag: [Stack] = partChoices
		var missing: [String] = []
		for p0 in d0.pieces {
			var p: SuitPiece = p0
			p.dmg = 0
			p.src = 0
			if (p.kind == .core || p.kind == .module) && !game.isCreative {
				let want: Item
				if !p.modPart.isEmpty { want = .custom(p.modPart) } else if p.kind == .core { want = .exoCore(ExoCore(rawValue: p.part) ?? .sparkCell) } else { want = .exoModule(ExoModule(rawValue: p.part) ?? .hover) }
				guard let j = bag.firstIndex(where: { $0.item == want }) else {
					missing.append(want.name)
					continue
				}
				let g: Int = t.newGroup()
				t.items[g] = bag.remove(at: j)
				p.src = g
			}
			p.id = t.newID()
			t.pieces.append(p)
		}
		plan = t
		pick = -1
		note = missing.isEmpty ? "" : joinText("Not in your bag (left off): ", missing.joined(separator: ", "), ".")
	}

	/// Keeps the planned design in the mod being tested
	func saveToMod() {
		let mid: String = game.testMod
		guard !mid.isEmpty, var p = ModStore.pack(mid) else { return }
		if p.suitDesigns.count >= ModSuitLimits.designs {
			note = joinText(p.name, " already holds the most suit designs a mod can.")
			return
		}
		var d = ModSuitDesign()
		d.id = p.freshID("suit")
		d.name = joinText("Suit ", String(p.suitDesigns.count + 1))
		var g: SuitDesign = plan
		g.items = [:]
		for k in g.pieces.indices {
			g.pieces[k].src = 0
			g.pieces[k].dmg = 0
		}
		d.design = g
		p.suitDesigns.append(d)
		note = ModStore.save(p) ? joinText("Saved as \u{201C}", d.name, "\u{201D} in ", p.name, ": rename it in the Mod Creator.") : "The mod could not be saved."
	}
}

extension SlotView {
	/// little squares in the corner, one in each infusion's colour
	func infusionMarks(_ l: [Int]) -> some View {
		let sz: CGFloat = max(3, size * 0.11)
		return VStack {
			HStack(spacing: 1) {
				ForEach(0..<min(3, l.count), id: \.self) { k in
					Rectangle().fill(Color(hex: infusionColor(l[k]))).frame(width: sz, height: sz)
						.overlay(Rectangle().stroke(Color.black, lineWidth: 1))
				}
				Spacer(minLength: 0)
			}
			Spacer(minLength: 0)
		}
		.padding(2)
		.frame(width: size, height: size)
	}
}

extension WorldRenderer {
	/// The suit's laser beams this frame: a bright core in a soft glow
	static func drawSuitBeams(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.suitBeams.isEmpty { return }
		for b in g.suitBeams {
			var p: Path = Path()
			p.move(to: CGPoint(x: v.sx(b.0), y: v.sy(b.1)))
			p.addLine(to: CGPoint(x: v.sx(b.2), y: v.sy(b.3)))
			ctx.stroke(p, with: .color(Color(hex: 0xFF4A6A, alpha: 0.35)), lineWidth: CGFloat(max(3.0, v.tp * 0.2)))
			ctx.stroke(p, with: .color(Color(hex: 0xFFD0DA, alpha: 0.95)), lineWidth: CGFloat(max(1.0, v.tp * 0.06)))
		}
	}

	/// What a potion is doing to a creature, kept faint: a blue film while slowed, rising green bubbles
	/// while poisoned, a grey shade while weakened, pink motes while it regenerates
	static func drawMobStatus(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ m: Mob) {
		if m.slowT > 0 {
			fillRect(&ctx, v.rect(m.b.left, m.b.top + m.b.h * 0.55, m.b.w, m.b.h * 0.45), Color(hex: 0x7AB8F0, alpha: 0.22))
		}
		if m.weakT > 0 {
			fillRect(&ctx, v.rect(m.b.left, m.b.top, m.b.w, m.b.h * 0.5), Color(hex: 0x6A6478, alpha: 0.2))
		}
		if m.poisonT > 0 {
			let sz: Double = max(3.0, v.tp * 0.12)
			for k in 0..<2 {
				let ph: Double = (g.clock * 0.9 + Double(k) * 0.5 + Double(m.id % 7) * 0.13).truncatingRemainder(dividingBy: 1.0)
				let bx: Double = m.b.x + (k == 0 ? -0.25 : 0.25) * m.b.w
				let by: Double = m.b.top + 0.2 - ph * 0.8
				fillRect(&ctx, mkRect(v.sx(bx) - sz * 0.5, v.sy(by) - sz * 0.5, sz, sz), Color(hex: 0x8AE04A, alpha: 0.8 * (1.0 - ph)))
			}
		}
		if m.regenT > 0 {
			let sz: Double = max(3.0, v.tp * 0.1)
			let ph: Double = (g.clock * 0.7 + Double(m.id % 5) * 0.2).truncatingRemainder(dividingBy: 1.0)
			fillRect(&ctx, mkRect(v.sx(m.b.x) - sz * 0.5, v.sy(m.b.top - ph * 0.6) - sz * 0.5, sz, sz), Color(hex: 0xF07AB8, alpha: 0.8 * (1.0 - ph)))
		}
	}
}
