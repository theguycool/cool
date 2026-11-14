// PIXEL REALM v2, part 7 of 8: drawing the world, the Mod Creator screens, joints and mechs (with their panel), and the app itself.
// The game is eight files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm8.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 2 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

// ===== u02_render =====

// MARK: - World renderer (Canvas)

struct SectionEntry {
	var img: Image
	var rev: Int
	var used: Int
	/// the chunk it was drawn from (Chunk.serial)
	var chunk: Int = 0
}

final class RenderCache: @unchecked Sendable {
	static let shared: RenderCache = RenderCache()
	var owner: Int = -1
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
		let id: Int = g.serial
		if owner != id {
			owner = id
			sections.removeAll()
			lightRev = -1
			lightImg = nil
			glowImg = nil
		}
	}

	/// One number for each 16-row section of each chunk in each dimension: room for 64 sections a
	/// chunk (the tallest dimension has 36) and 8 dimensions (5 are used). It once had room for two
	/// dimensions only, so the custom dimensions shared numbers with Overworld and Umbral sections a
	/// section lower, and each showed the other's pictures (ghost land).
	func key(_ dim: Int, _ cx: Int, _ sy: Int) -> Int {
		return ((cx &* 64) &+ (sy & 63)) &* 8 &+ (dim & 7)
	}

	/// Drops every cached picture (debug "reset systems"); they are rebuilt as needed
	func clearAll() {
		sections.removeAll()
		lightRev = -1
		lightImg = nil
		glowImg = nil
	}

	func evict() {
		// a picture is 256 x 256 pixels (a quarter of a megabyte): some screens' worth are kept
		if sections.count < 200 { return }
		var keep: [Int: SectionEntry] = [:]
		for (k, e) in sections where frame - e.used < 240 { keep[k] = e }
		sections = keep
	}
}

/// Builds one 16x16-tile section as an image (tiles over a dark backdrop wall where underground).
func buildSection(_ g: Game, _ ch: Chunk, _ sy: Int) -> Image {
	let px: [UInt32] = SectionPainter.shared.paint(g.world, ch, sy)
	if let cg = makeCGImagePremul(px, chunkW * tileArtPx, 16 * tileArtPx) {
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

/// Darkens or tints the screen edges, fading to nothing toward the middle
func edgeVignette(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ c: UInt32, _ a: Double) {
	let band: Double = min(W, H) * 0.24
	let on: Color = rgbColor(c, a)
	let off: Color = rgbColor(c, 0)
	let g: Gradient = Gradient(colors: [on, off])
	ctx.fill(Path(mkRect(0, 0, W, band)), with: .linearGradient(g, startPoint: mkPoint(0, 0), endPoint: mkPoint(0, band)))
	ctx.fill(Path(mkRect(0, H - band, W, band)), with: .linearGradient(g, startPoint: mkPoint(0, H), endPoint: mkPoint(0, H - band)))
	ctx.fill(Path(mkRect(0, 0, band, H)), with: .linearGradient(g, startPoint: mkPoint(0, 0), endPoint: mkPoint(band, 0)))
	ctx.fill(Path(mkRect(W - band, 0, band, H)), with: .linearGradient(g, startPoint: mkPoint(W, 0), endPoint: mkPoint(W - band, 0)))
}

/// The sky's clouds, in four layers. A layer is a row of cells along the sky; a cell holds nothing, a
/// single cloud, or now and then a loose formation of several. Far layers are small, pale and slow and
/// follow the camera least; near layers are big and quick and follow it most, so the sky has depth.
/// Clouds are drawn behind the terrain and everything else, and have no collision. The fourth layer is
/// the low storm deck, which only builds under a heavy sky.
enum CloudField {
	/// blocks per second: slow enough not to pull the eye
	static let wind: Double = 0.25
	/// art pixels per block (the same grid as terrain, creatures and the player)
	static let pxPerTile: Double = 8.0

	struct Cloud {
		/// top-left corner in the layer's own sideways blocks, and blocks below the top of the sky band
		var x: Double
		var y: Double
		var kind: Int
		var flip: Bool
		/// fades a cloud in and out as the weather changes how many cells are filled
		var alpha: Double = 1.0
	}

	struct Layer {
		/// how much of the camera's sideways travel the layer follows (1 would be fixed to the world)
		let par: Double
		/// how fast it drifts compared with the wind
		let speed: Double
		/// blocks between cells
		let cell: Double
		/// the band the clouds sit in, in blocks below the top of the sky band
		let rowTop: Double
		let rows: Double
		/// which sizes it uses (indices into CloudArt.classes)
		let pool: [Int]
		/// the share of cells that hold a formation instead of one cloud
		let groups: Double
		/// how much the layer follows the camera going up and down
		let lift: Double
		/// haze toward the sky colour (far clouds are paler) and the layer's base opacity
		let haze: Double
		let opacity: Double
	}

	static let layers: [Layer] = [
		Layer(par: 0.30, speed: 0.45, cell: 7.0, rowTop: 0.0, rows: 9.0, pool: [0, 1, 2], groups: 0.14, lift: 0.05, haze: 0.30, opacity: 0.80),
		Layer(par: 0.55, speed: 0.75, cell: 12.0, rowTop: 1.0, rows: 12.0, pool: [1, 2, 3], groups: 0.20, lift: 0.08, haze: 0.14, opacity: 0.90),
		Layer(par: 0.80, speed: 1.00, cell: 22.0, rowTop: 3.0, rows: 12.0, pool: [1, 3, 4, 4], groups: 0.25, lift: 0.12, haze: 0.0, opacity: 0.96),
		Layer(par: 0.70, speed: 1.35, cell: 16.0, rowTop: -2.0, rows: 7.0, pool: [2, 4, 4], groups: 0.30, lift: 0.10, haze: 0.0, opacity: 0.94)
	]

	/// Every cloud of one layer overlapping the layer's sideways range [x0, x1]. `d` is how far the sky
	/// has drifted (the weather keeps it, moving with the wind); `fill` is the share of cells with
	/// something in them (more under a grey sky).
	static func clouds(_ seed: UInt64, _ layer: Int, _ d: Double, _ x0: Double, _ x1: Double, fill: Double) -> [Cloud] {
		let L: Layer = layers[layer]
		let shift: Double = d * L.speed
		let reach: Double = 60.0
		let c0: Int = Int(floor((x0 - shift - reach) / L.cell))
		let c1: Int = Int(floor((x1 - shift) / L.cell))
		var out: [Cloud] = []
		if c1 < c0 { return out }
		let art: CloudArt = CloudArt.shared
		let s: UInt64 = seed &+ UInt64(layer + 1) &* 7919
		for ci in c0...c1 {
			let presence: Double = hash2(ci, 11, s) - (1.0 - fill)
			if presence <= 0 { continue }
			let alpha: Double = clampD(presence / 0.1, 0, 1)
			let formation: Bool = hash2(ci, 21, s) < L.groups
			let n: Int = formation ? 3 + Int(hash2(ci, 22, s) * 3.0) : 1
			let bx: Double = Double(ci) * L.cell + hash2(ci, 12, s) * L.cell * 0.8 + shift
			let by: Double = L.rowTop + hash2(ci, 13, s) * L.rows
			for k in 0..<n {
				let cls: Int = L.pool[Int(hash2(ci, 30 + k, s) * Double(L.pool.count)) % L.pool.count]
				let ids: [Int] = art.classes[cls]
				let kind: Int = ids[Int(hash2(ci, 50 + k, s) * Double(ids.count)) % ids.count]
				let dx: Double = k == 0 ? 0 : (hash2(ci, 60 + k, s) - 0.35) * 26.0
				let dy: Double = k == 0 ? 0 : (hash2(ci, 70 + k, s) - 0.5) * 7.0
				out.append(Cloud(x: bx + dx, y: by + dy, kind: kind, flip: hash2(ci, 80 + k, s) < 0.5, alpha: alpha))
			}
		}
		return out
	}
}

/// The cloud templates: soft silhouettes built from round lobes sitting on a flat base, in five size
/// classes (small puffs, ordinary cumulus, long low banks, towering heaps and huge formations), several
/// variants of each, shaded with a few restrained tones (bright top, body, cool underside), no outline.
final class CloudArt: @unchecked Sendable {
	static let shared: CloudArt = CloudArt()
	let shapes: [PixelBuf]
	let images: [Image]
	let flipped: [Image]
	/// shape indices by size class: 0 small, 1 ordinary, 2 long and low, 3 towering, 4 huge
	let classes: [[Int]]

	init() {
		var out: [PixelBuf] = []
		var cls: [[Int]] = []
		let counts: [Int] = [5, 6, 5, 4, 4]
		for c in 0..<counts.count {
			var ids: [Int] = []
			for n in 0..<counts[c] {
				ids.append(out.count)
				out.append(CloudArt.build(c, n))
			}
			cls.append(ids)
		}
		shapes = out
		classes = cls
		images = out.map { pixImage($0) }
		flipped = out.map { pixImage($0.flipped()) }
	}

	/// One template: variant `n` of size class `cls`. The same numbers always give the same cloud.
	static func build(_ cls: Int, _ n: Int) -> PixelBuf {
		let seed: UInt64 = UInt64(0xC10D + cls * 97)
		func r(_ k: Int) -> Double { return hash2(n, k, seed) }
		// (width range, height range, flat base height)
		let spec: [(Double, Double, Double, Double, Double)] = [
			(28, 46, 12, 17, 4),
			(54, 88, 20, 28, 5),
			(110, 170, 14, 20, 4),
			(68, 100, 38, 52, 6),
			(190, 260, 36, 52, 6)
		]
		let sp: (Double, Double, Double, Double, Double) = spec[cls]
		let w: Int = Int(sp.0 + (sp.1 - sp.0) * r(1))
		let h: Int = Int(sp.2 + (sp.3 - sp.2) * r(2))
		let baseH: Double = sp.4 * (0.8 + 0.4 * r(4))
		let wd: Double = Double(w)
		let bl: Double = Double(h) - baseH
		var mask = PixelBuf(w: w, h: h)
		// the flat base: one long ellipse, so the underside is level and slightly rounded at the ends
		mask.ellipse(wd * 0.5, Double(h) - baseH, wd * 0.5 - 1.0, baseH, 0xFFFFFF)
		// the heaps: round lobes walked along the base, tallest toward the middle (a long bank stays
		// low), each a little different in size, so the top reads as separate puffs
		let maxR: Double = (bl - 1.0) / 1.35 * (cls == 2 ? 0.45 : 1.0)
		var x: Double = wd * 0.06
		var i: Int = 0
		while x < wd * 0.94 && i < 40 {
			let u: Double = x / wd
			let env: Double = sin(Double.pi * min(0.98, max(0.02, u)))
			var rr: Double = maxR * (0.30 + 0.70 * env * (0.45 + 0.55 * r(20 + i)))
			rr = max(2.5, rr)
			let rx: Double = rr * (0.92 + 0.28 * r(60 + i))
			let cx: Double = x + rx * 0.5
			let rxc: Double = max(2.0, min(rx, min(cx, wd - cx) - 1.0))
			// a lobe squeezed by the end of the template stays round instead of becoming a slab
			rr = min(rr, rxc * 1.2)
			mask.ellipse(cx, bl - rr * 0.35, rxc, rr, 0xFFFFFF)
			x += rxc * (0.9 + 0.5 * r(100 + i))
			i += 1
		}
		// small bumps along the top edge
		let bumps: Int = max(2, w / 30)
		for k in 0..<bumps {
			let bx: Int = Int(wd * (0.08 + 0.84 * r(140 + k)))
			var topY: Int = -1
			for yy in 0..<h where (mask.get(bx, yy) >> 24) != 0 { topY = yy; break }
			if topY < 0 { continue }
			let br: Double = max(2.0, maxR * (0.16 + 0.20 * r(180 + k)))
			mask.ellipse(Double(bx), Double(topY) + br * 0.55, br * 1.1, br, 0xFFFFFF)
		}
		// nothing hangs below the base line: a flat bottom
		for x in 0..<w { mask.clear(x, h - 1) }
		let edge: UInt32 = 0xFFFFFF
		let body: UInt32 = 0xF6F9FC
		let mid: UInt32 = 0xE7EEF6
		let under: UInt32 = 0xD8E1EC
		let rim: UInt32 = 0xC8D3E1
		var b = PixelBuf(w: w, h: h)
		func filled(_ x: Int, _ y: Int) -> Bool { return (mask.get(x, y) >> 24) != 0 }
		let midRow: Int = Int(Double(h) * 0.6)
		for y in 0..<h {
			for x in 0..<w where filled(x, y) {
				var c: UInt32 = y >= midRow ? mid : body
				if y == midRow - 1 && (x + y) % 2 == 0 { c = mid }
				if !filled(x, y - 1) { c = edge }
				if !filled(x, y + 1) { c = rim } else if !filled(x, y + 2) || !filled(x, y + 3) { c = under }
				b.set(x, y, c)
			}
		}
		return b
	}
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
		let drawT0: Double = perfNow()
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
		drawLiquids(&ctx, g, v)
		if !g.stress.isEmpty { drawStress(&ctx, g, v) }
		drawGroundWeather(&ctx, g, v)
		drawWaves(&ctx, g, v)
		drawRift(&ctx, g, v)
		drawWiring(&ctx, g, v)
		drawPowerDevices(&ctx, g, v)
		drawShips(&ctx, g, v)
		drawVehicles(&ctx, g, v)
		drawLifts(&ctx, g, v)
		drawDrops(&ctx, g, v)
		drawFlyingBlocks(&ctx, g, v)
		drawMobs(&ctx, g, v)
		drawPlayer(&ctx, g, v)
		drawProjectiles(&ctx, g, v)
		drawCombatFX(&ctx, g, v)
		drawSuitBeams(&ctx, g, v)
		drawLeafFall(&ctx, g, v)
		drawParticles(&ctx, g, v)
		if !g.smokes.isEmpty || !g.rings.isEmpty { drawPotionFX(&ctx, g, v) }
		drawWeatherDevices(&ctx, g, v)
		drawTornado(&ctx, g, v)
		drawPrecip(&ctx, g, v)
		drawLight(&ctx, g, v, cache)
		drawAmbientLife(&ctx, g, v)
		drawBolts(&ctx, g, v)
		drawFlashes(&ctx, g, v)
		drawTrajectory(&ctx, g, v)
		drawOverlays(&ctx, W, H, g, v)
		drawWeatherOverlay(&ctx, W, H, g, v)
		drawFloats(&ctx, g, v)
		if g.capturing { drawCapture(&ctx, g, v) }
		if g.showChunks || g.showHitboxes || g.showAI { drawDebug(&ctx, H, g, v) }
		if g.settings.showFPS {
			let fpsN: Int = Int(g.renderFPS.rounded())
			let pf: Perf = Perf.shared
			let line1: String = String(format: "FPS %d  tick %.1f ms  draw %.1f ms", fpsN, g.tickMs, pf.renderMs)
			let line2: String = String(format: "ai %.2f  phys %.2f  light %.2f  gen %.1f ms", pf.aiMs, pf.physMs, pf.lightMs, pf.genMs)
			fillRect(&ctx, mkRect(W * 0.5 - 130.0, 4, 260, 36), Color.black.opacity(0.55))
			drawLabel(&ctx, line1, W * 0.5, 14, 11, Color.yellow)
			drawLabel(&ctx, line2, W * 0.5, 30, 10, Color(hex: 0xD8D0A0))
		}
		cache.evict()
		// note: this measures building the Canvas command list; SwiftUI rasterises it afterwards
		Perf.shared.renderMs = Perf.smooth(Perf.shared.renderMs, perfNow() - drawT0)
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

	/// pictures of mods' suns and moons, by their pixels
	static var skyBodyImages: [Int: Image] = [:]

	static func skyBodyImage(_ art: ModPixels) -> Image {
		let key: Int = art.rgba.hashValue &+ art.w &* 131 &+ art.h
		if let im = skyBodyImages[key] { return im }
		if skyBodyImages.count > 16 { skyBodyImages = [:] }
		let im: Image = pixImage(art.buf())
		skyBodyImages[key] = im
		return im
	}

	/// A sun or a moon of a mod's own: its glow and rays, then its picture (or the game's own shape in
	/// its colour), on its path across the sky with the time of day or where it stays. `base` is the
	/// game's size for it in pixels, `round` draws discs (custom dimensions) rather than squares, and
	/// `sky` is the colour behind it (for the moon's shadowed side).
	static func drawSkyBody(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ clock: Double, _ b: ModSkyBody, _ t: Double, _ moon: Bool, _ base: Double, _ round: Bool, _ sky: UInt32) {
		var bx: Double = clampD(b.posX, 0, 1) * W
		var by: Double = clampD(b.posY, 0, 1) * H * 0.6
		if b.path == 0 {
			let up: Bool = moon ? t >= 0.5 : t < 0.5
			if !up { return }
			let ang: Double = t < 0.5 ? (t / 0.5) : ((t - 0.5) / 0.5)
			bx = (0.1 + 0.8 * ang) * W
			by = H * (0.55 - 0.42 * clampD(b.arc, 0.2, 1.2) * sin(ang * Double.pi))
		}
		let size: Double = base * clampD(b.size, 0.3, 3)
		let pulse: Double = b.pulse > 0.001 ? 1.0 + 0.14 * b.pulse * sin(clock * 2.4) : 1.0
		let gc: Color = rgbColor(b.glowColor & 0xFFFFFF)
		if b.glow > 0.01 {
			let gs: Double = size * (1.2 + 0.7 * b.glow) * pulse
			let ga: Double = 0.1 + 0.18 * b.glow
			if round {
				ctx.fill(Path(ellipseIn: mkRect(bx - gs * 0.5, by - gs * 0.5, gs, gs)), with: .color(gc.opacity(ga)))
			} else {
				fillRect(&ctx, mkRect(bx - gs * 0.5, by - gs * 0.5, gs, gs), gc.opacity(ga))
			}
		}
		var c: GraphicsContext = ctx
		c.translateBy(x: CGFloat(bx), y: CGFloat(by))
		if abs(b.spin) > 0.001 { c.rotate(by: Angle(degrees: (clock * b.spin).truncatingRemainder(dividingBy: 360))) }
		if b.rays {
			var rays: Path = Path()
			let len: Double = size * 0.32 * pulse
			let wd: Double = max(2.0, size * 0.08)
			for k in 0..<8 {
				let a: Double = Double(k) * Double.pi / 4.0
				let r0: Double = size * 0.62
				let x: Double = cos(a) * (r0 + len * 0.5)
				let y: Double = sin(a) * (r0 + len * 0.5)
				let horiz: Bool = k % 4 == 0
				let vert: Bool = k % 4 == 2
				let rw: Double = horiz ? len : (vert ? wd : wd * 1.2)
				let rh: Double = horiz ? wd : (vert ? len : wd * 1.2)
				rays.addRect(mkRect(x - rw * 0.5, y - rh * 0.5, rw, rh))
			}
			c.fill(rays, with: .color(gc.opacity(0.8)))
		}
		let col: UInt32 = b.color & 0xFFFFFF
		if !b.art.isBlank {
			let aw: Double = Double(b.art.w)
			let ah: Double = Double(b.art.h)
			let k: Double = size / max(aw, ah)
			c.draw(skyBodyImage(b.art), in: mkRect(-aw * k * 0.5, -ah * k * 0.5, aw * k, ah * k))
		} else if moon {
			let r: Double = size * 0.5
			if round {
				c.fill(Path(ellipseIn: mkRect(-r, -r, size, size)), with: .color(rgbColor(col)))
				c.fill(Path(ellipseIn: mkRect(-r * 0.4, -r * 1.1, size * 0.85, size * 0.85)), with: .color(rgbColor(sky).opacity(0.85)))
			} else {
				fillRect(&c, mkRect(-r, -r, size, size), rgbColor(col))
				fillRect(&c, mkRect(-r * 0.36, -r * 0.55, size * 0.23, size * 0.23), rgbColor(shadeRGB(col, 0.82)))
				fillRect(&c, mkRect(r * 0.27, r * 0.18, size * 0.18, size * 0.18), rgbColor(shadeRGB(col, 0.82)))
			}
		} else {
			let r: Double = size * 0.5
			if round {
				c.fill(Path(ellipseIn: mkRect(-r, -r, size, size)), with: .color(rgbColor(col)))
				c.fill(Path(ellipseIn: mkRect(-r * 0.62, -r * 0.62, size * 0.62, size * 0.62)), with: .color(rgbColor(mixRGB(col, 0xFFFFFF, 0.45))))
			} else {
				fillRect(&c, mkRect(-r, -r, size, size), rgbColor(col))
				fillRect(&c, mkRect(-r * 0.64, -r * 0.64, size * 0.64, size * 0.64), rgbColor(mixRGB(col, 0xFFFFFF, 0.45)))
			}
		}
	}

	static func drawSky(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D) {
		if let d = g.customDim {
			drawCustomSky(&ctx, W, H, g, v, d)
			return
		}
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
		topC = artGrade(topC)
		botC = artGrade(botC)
		vGradient(&ctx, full, [rgbColor(topC), rgbColor(botC)], 0, H)
		// cloud cover and storm darkness (see drawSkyWeather)
		let cover: Double = g.wxHere.cloud
		if g.settings.weatherOn { drawSkyWeather(&ctx, W, H, g, v, day) }
		// stars (hidden behind cloud)
		if day < 0.6 && cover < 0.95 {
			let a: Double = (0.6 - day) / 0.6 * (1.0 - cover)
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
		// cloud hides the sun and moon
		var sc: GraphicsContext = ctx
		sc.opacity = 1.0 - 0.9 * cover
		let rt: ModRuntime = ModRuntime.shared
		if let sb = rt.overSun { drawSkyBody(&sc, W, H, g.clock, sb, t, false, 56.0, false, topC) }
		if let mb = rt.overMoon { drawSkyBody(&sc, W, H, g.clock, mb, t, true, 44.0, false, topC) }
		// the game's own, unless a mod gave one in its place
		let own: Bool = t < 0.5 ? rt.overSun != nil : rt.overMoon != nil
		if !own && t < 0.5 {
			fillRect(&sc, mkRect(bx - 36.0, by - 36.0, 72.0, 72.0), Color(hex: artGrade(0xFFE680), alpha: 0.25))
			fillRect(&sc, mkRect(bx - 28.0, by - 28.0, 56.0, 56.0), Color(hex: artGrade(0xFFD84A)))
			fillRect(&sc, mkRect(bx - 18.0, by - 18.0, 36.0, 36.0), Color(hex: artGrade(0xFFF2A0)))
		} else if !own {
			fillRect(&sc, mkRect(bx - 22.0, by - 22.0, 44.0, 44.0), Color(hex: 0xE8ECF4))
			fillRect(&sc, mkRect(bx - 8.0, by - 12.0, 10.0, 10.0), Color(hex: 0xC0C6D0))
			fillRect(&sc, mkRect(bx + 6.0, by + 4.0, 8.0, 8.0), Color(hex: 0xC0C6D0))
		}
		// clouds drift in front of the sun and moon and behind everything else
		if g.world.dim == .overworld { drawClouds(&ctx, W, H, g, v, day, dusk) }
		// lightning lights up the whole sky
		if g.skyFlash > 0.01 { fillRect(&ctx, full, Color(hex: 0xDDE8FF, alpha: g.skyFlash * (g.settings.reduceFlashes ? 0.3 : 0.5))) }
		if g.settings.weatherOn { drawSkyWeatherFront(&ctx, W, H, g) }
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
				// a picture is only reused for the chunk it was drawn from: up to date, or for a frame or two
				// while the pictures that changed are redrawn a few at a time
				if var e = cache.sections[k], e.chunk == ch.serial {
					if e.rev == srev || cache.builtThisFrame >= cap {
						e.used = cache.frame
						cache.sections[k] = e
						img = e.img
					}
				}
				if img == nil {
					let im: Image = buildSection(g, ch, sy)
					cache.sections[k] = SectionEntry(img: im, rev: srev, used: cache.frame, chunk: ch.serial)
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

	/// drawSet with a rotation and vertical squash about the feet (for leaning, breathing and falling over)
	/// and a horizontal scale (for turning round)
	static func drawSetPosed(_ ctx: inout GraphicsContext, _ v: View2D, _ s: SpriteSet, _ frame: Int, _ left: Bool, _ hurt: Bool, _ x: Double, _ y: Double, _ alpha: Double, _ shade: Double, _ rot: Double, _ squash: Double, scaleX: Double = 1.0) {
		let px: Double = s.scale * v.tp
		let sw: Double = Double(s.w)
		let shh: Double = Double(s.h)
		let cc: Double = left ? (sw - s.centerCol) : s.centerCol
		let foot: Double = Double(s.footRow)
		var c: GraphicsContext = ctx
		c.opacity = alpha
		if shade < 0.98 { c.addFilter(.colorMultiply(shadeColor(shade))) }
		c.translateBy(x: CGFloat(v.sx(x)), y: CGFloat(v.sy(y)))
		if rot != 0 { c.rotate(by: Angle(radians: rot)) }
		if squash != 1.0 || scaleX != 1.0 { c.scaleBy(x: CGFloat((1.0 + (1.0 - squash) * 0.5) * scaleX), y: CGFloat(squash)) }
		let r: CGRect = mkRect(-cc * px, -foot * px, sw * px, shh * px)
		c.draw(s.frame(frame, left: left, hurt: hurt), in: r)
	}

	static func walkFrame(_ m: Mob, _ s: SpriteSet) -> Int {
		return s.anim.walkFrame(m.anim)
	}

	/// Standing creatures with an idle variation (grazing, pecking) show it about a quarter of the time,
	/// in bursts of a second or so, staggered by id
	static func idleVariant(_ m: Mob, _ clock: Double) -> Bool {
		let p: Double = (clock * 0.22 + Double(m.id % 97) * 0.137).truncatingRemainder(dividingBy: 1.0)
		return p > 0.74
	}

	static func mobFrame(_ m: Mob, _ s: SpriteSet, _ clock: Double) -> Int {
		if m.kind == .custom { return customMobFrame(m, s) }
		let moving: Bool = abs(m.b.vx) > 0.3
		let an: CreatureAnim = s.anim
		if isHumanoid(m.kind) {
			if m.st == 3 {
				if m.kind == .pirateGunner || m.kind == .imp || m.kind == .archer { return an.pose("shoot", 6) }
				return an.pose("windup", 3)
			}
			if m.st == 4 { return an.pose("strike", 4) }
			// just fired: the hand-drawn gunner shows the flash of the shot
			if m.st == 6 { return an.pose("fire", an.pose("shoot", 6)) }
			if m.blocking { return an.pose("block", 5) }
			// clawing creatures raise their arms as a hit lands
			if m.atkT > 0 && (m.kind == .zombie || m.kind == .imp) { return an.pose("strike", 4) }
			return moving ? walkFrame(m, s) : 0
		}
		let slow: Int = Int(m.anim * 1.5)
		// the hand-drawn bosses walk on four frames and stand still between steps; the older drawings
		// keep their two frames, shown all the time
		let fourStep: Bool = an.walk.count > 2
		switch m.kind {
		case .bearBoss:
			if m.st == 1 { return an.pose("rear", 2) }
			if m.st == 2 {
				let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
				if a == .melee || a == .sweep { return an.pose("strike", 3) }
				if a == .slam || a == .roar { return an.pose("rear", 2) }
			}
			if fourStep { return moving ? walkFrame(m, s) : 0 }
			return slow % 2
		case .rex:
			if m.st == 2 { return an.pose("strike", 2) }
			if m.st == 1 {
				let a: BossAtk = BossAtk(rawValue: m.atk) ?? .melee
				if a == .melee || a == .sweep { return an.pose("windup", 2) }
			}
			if fourStep { return moving ? walkFrame(m, s) : 0 }
			return slow % 2
		case .golem:
			if m.st == 3 { return an.pose("windup", 3) }
			if m.st == 4 { return an.pose("strike", 4) }
			if m.st == 5 { return an.pose("throw", 5) }
			return moving ? walkFrame(m, s) : 0
		case .sentinel:
			if m.st == 1 { return an.pose("charge", 2) }
			if m.st == 5 || m.atkT > 0 { return an.pose("strike", 3) }
			return Int(m.anim * 2.0) % 2
		case .mimic:
			if m.st == 3 || m.st == 4 { return 3 }
			if !m.b.onGround { return 1 + Int(m.anim * 6.0) % 2 }
			return m.angry ? 1 : 0
		case .warden:
			let wa: Int = m.atk
			if m.st == 1 && wa == WardenAtk.sweep.rawValue { return an.pose("windup", 2) }
			if m.st == 2 && wa == WardenAtk.sweep.rawValue && m.atkT > 0 { return an.pose("strike", 3) }
			if (m.st == 1 || m.st == 3) && wa != WardenAtk.sweep.rawValue { return an.pose("cast", 4) }
			return Int(m.anim * 1.2) % 2
		default:
			break
		}
		let a: CreatureAnim = s.anim
		if a.attack >= 0 && m.atkT > 0 { return a.attack }
		if a.hop { return m.b.onGround ? 0 : a.hopFrame }
		if !a.cycle.isEmpty { return a.cycle[slow % a.cycle.count] }
		if moving { return walkFrame(m, s) }
		if a.idleAlt >= 0 && m.b.onGround && (m.poseT > 0 || idleVariant(m, clock)) { return a.idleAlt }
		return 0
	}

	/// A custom creature's frame: a humanoid body moves like the game's humanoids; other bodies use their
	/// own animation, and custom art shows standing, two walking frames and an attack frame
	static func customMobFrame(_ m: Mob, _ s: SpriteSet) -> Int {
		let moving: Bool = abs(m.b.vx) > 0.3
		guard let r = ModRuntime.shared.mob(m.cslot) else { return 0 }
		if !r.def.customArt && isHumanoid(r.base) {
			if m.st == 3 {
				let ranged: Bool = m.atk >= 0 && m.atk < r.attacks.count && r.attacks[m.atk].def.kind == .ranged
				return ranged ? s.anim.pose("shoot", 6) : s.anim.pose("windup", 3)
			}
			if m.st == 4 || m.st == 6 || m.atkT > 0 { return s.anim.pose("strike", 4) }
			return moving ? walkFrame(m, s) : 0
		}
		let a: CreatureAnim = s.anim
		if a.attack >= 0 && (m.atkT > 0 || m.st == 3 || m.st == 5 || m.st == 6) { return a.attack }
		if a.hop { return m.b.onGround ? 0 : a.hopFrame }
		if !a.cycle.isEmpty { return a.cycle[Int(m.anim * 1.5) % a.cycle.count] }
		if moving && s.right.count > 1 { return walkFrame(m, s) }
		return 0
	}

	/// Telegraphed attacks: the struck area pulses faster as the moment nears, and fills up from the
	/// ground to show how long is left
	static func drawDangerZones(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		for z in g.dangerZones {
			if !v.visible((z.x0 + z.x1) * 0.5, z.y1, (z.x1 - z.x0) * 0.5 + 6.0) { continue }
			let p: Double = clampD(1.0 - z.t / z.dur, 0, 1)
			let pulse: Double = 0.5 + 0.5 * sin(g.clock * (10.0 + 14.0 * p))
			let r: CGRect = v.rect(z.x0, z.y0, z.x1 - z.x0, z.y1 - z.y0)
			fillRect(&ctx, r, Color(hex: z.color, alpha: 0.08 + 0.08 * pulse))
			let h: Double = (z.y1 - z.y0) * p
			fillRect(&ctx, v.rect(z.x0, z.y1 - h, z.x1 - z.x0, h), Color(hex: z.color, alpha: 0.2))
			ctx.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(Color(hex: z.color, alpha: 0.5 + 0.3 * pulse)), lineWidth: 2)
		}
	}

	/// The area being captured as a structure: a box from the first corner to the second (or to the
	/// finger), with its size
	static func drawCapture(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		guard let r = g.captureRect() else { return }
		let w: Double = Double(r.2 - r.0 + 1)
		let h: Double = Double(r.3 - r.1 + 1)
		let box: CGRect = v.rect(Double(r.0), Double(r.1), w, h)
		let pulse: Double = 0.55 + 0.25 * sin(g.clock * 6.0)
		fillRect(&ctx, box, Color(hex: 0x60E0FF, alpha: 0.12))
		strokeRect(&ctx, box, Color(hex: 0x60E0FF, alpha: pulse), 3)
		drawLabel(&ctx, joinText(String(Int(w)), " x ", String(Int(h))), v.sx(Double(r.0) + w * 0.5), v.sy(Double(r.1)) - 12.0, 13, Color(hex: 0x60E0FF))
	}

	static func drawMobs(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let art: Art = Art.shared
		if !g.dangerZones.isEmpty { drawDangerZones(&ctx, g, v) }
		for m in g.mobs {
			let dying: Bool = m.hp <= 0 && !m.downed
			if dying && (m.deathT < 0 || m.removed) { continue }
			if !v.visible(m.b.x, m.b.y, 8 + m.b.w) { continue }
			var s: SpriteSet = art.mobSet(m)
			if m.mut > 0 {
				// a mutated creature: its colours turned, drawn as large as its body has grown
				s = art.mutantSet(m)
				s.scale *= g.drawScale(m)
			}
			var left: Bool = m.dir < 0
			// turning round: the sprite narrows to a sliver and widens again facing the other way
			var scaleX: Double = 1.0
			if m.turnT > 0 && !dying {
				let p: Double = 1.0 - m.turnT / Mob.turnDur
				scaleX = max(0.2, abs(1.0 - 2.0 * p))
				if p < 0.5 { left = m.face < 0 }
			}
			// an attack that lands throws the body forward a little
			var drawX: Double = m.b.x
			if m.atkT > 0 && !dying && !m.isBoss {
				let p: Double = 1.0 - m.atkT / Mob.atkDur
				drawX += Double(m.dir) * 0.18 * sin(p * Double.pi)
			}
			var alpha: Double = 1.0
			if m.kind == .wraith { alpha = 0.82 }
			if m.downed { alpha = 0.55 }
			let warn: Bool = (m.kind == .bearBoss || m.kind == .rex) && m.isBoss && m.st == 1 && !dying
			if warn { drawTelegraph(&ctx, g, v, m) }
			let shade: Double = openShade(g, m.b.x, m.b.cy)
			// animation layer on top of the frames: knockback lean, idle breathing, death topple
			var rot: Double = m.lean * 0.22
			var squash: Double = 1.0
			if abs(m.b.vx) < 0.3 && m.b.onGround && !dying {
				squash = 1.0 + 0.022 * sin(g.clock * 2.6 + Double(m.id % 17))
			}
			if dying {
				let t: Double = m.deathT
				let blob: Bool = m.kind == .slime || m.kind == .emberSlime || m.def.flying || m.kind == .fish
				if blob {
					squash = max(0.2, 1.0 - t * 1.1)
				} else {
					let fall: Double = min(1.0, t / 0.4)
					let side: Double = m.dir > 0 ? -1.0 : 1.0
					rot = side * fall * fall * 1.45
				}
				alpha *= clampD(1.0 - (t - 0.3) / 0.4, 0, 1)
			}
			let flash: Bool = m.flash > 0 || (dying && m.deathT < 0.08)
			let fr: Int = mobFrame(m, s, g.clock)
			if abs(rot) > 0.01 || abs(squash - 1.0) > 0.004 || scaleX < 0.999 {
				drawSetPosed(&ctx, v, s, fr, left, flash, drawX, m.b.y, alpha, shade, rot, squash, scaleX: scaleX)
			} else {
				drawSet(&ctx, v, s, fr, left, flash, drawX, m.b.y, alpha, shade: shade)
			}
			if dying { continue }
			if m.burn > 0 {
				let fl: Double = 0.25 + 0.15 * sin(g.clock * 20.0)
				let r: CGRect = v.rect(m.b.left, m.b.top + m.b.h * 0.3, m.b.w, m.b.h * 0.7)
				fillRect(&ctx, r, Color(hex: 0xFF7020, alpha: fl))
			}
			if m.hasStatus { drawMobStatus(&ctx, g, v, m) }
			if m.tame {
				drawLabel(&ctx, "♥", v.sx(m.b.x), v.sy(m.b.top) - 10.0, 12, Color(hex: 0xFF5A7A))
			}
			if m.daze > 0 {
				// little stars circling the head while it reels
				for k in 0..<3 {
					let a: Double = g.clock * 6.0 + Double(k) * 2.094
					let sx: Double = m.b.x + cos(a) * max(0.45, m.b.w * 0.45)
					let sy: Double = m.b.top - 0.25 + sin(a) * 0.12
					let sz: Double = max(3.0, v.tp * 0.14)
					fillRect(&ctx, mkRect(v.sx(sx) - sz * 0.5, v.sy(sy) - sz * 0.5, sz, sz), Color(hex: k == 1 ? 0xFFFFFF : 0xFFE060))
				}
			}
			let damaged: Bool = m.hp < m.maxHP && m.hp > 0
			if !m.isBoss && damaged {
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
			// the moment a monster notices the player
			if m.ai == .alert {
				let pop: Double = min(1.0, m.aiT / 0.12)
				drawLabel(&ctx, "!", v.sx(m.b.x), v.sy(m.b.top) - 14.0 - 6.0 * pop, 22, Color(hex: 0xFFD838))
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
		let doing: Int = g.playerFrame()
		let pose: Bool = doing >= 3
		let fr: Int = playerSpriteFrame(s, g, doing)
		var showItem: Bool = g.heldItem != nil
		if g.mounted != nil || g.inVehicle != nil { showItem = false }
		if showItem && !pose { drawHeldItem(&ctx, g, v) }
		let shade: Double = openShade(g, g.pb.x, g.pb.cy)
		if g.seat != nil || g.seatAboard != nil {
			// sitting: lower on the seat
			drawSetPosed(&ctx, v, s, 0, left, g.hurtT > 0, g.pb.x, g.pb.y - 0.12, alpha, shade, 0, 0.74)
		} else if g.landT > 0 {
			// a brief squash on landing from a fall
			let k: Double = g.landT / 0.12
			drawSetPosed(&ctx, v, s, fr, left, g.hurtT > 0, g.pb.x, g.pb.y, alpha, shade, 0, 1.0 - 0.1 * k)
		} else {
			drawSet(&ctx, v, s, fr, left, g.hurtT > 0, g.pb.x, g.pb.y, alpha, shade: shade)
		}
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

	/// The frame of the player's sprite set for what the player is doing (Game.playerFrame: 0 standing,
	/// 1-2 walking or in the air, 3 winding up, 4 striking, 5 blocking, 6 shooting). A hand-drawn figure
	/// has a four-step walk and, after standing still a moment, turns to face out of the screen.
	static func playerSpriteFrame(_ s: SpriteSet, _ g: Game, _ doing: Int) -> Int {
		let a: CreatureAnim = s.anim
		switch doing {
		case 1, 2:
			if !g.pb.onGround && !g.pb.inWater { return a.walk.first ?? 1 }
			return a.walkFrame(g.walkAnim)
		case 3: return a.pose("windup", 3)
		case 4: return a.pose("strike", 4)
		case 5: return a.pose("block", 5)
		case 6: return a.pose("shoot", 6)
		default:
			if g.restT > 0.9 && g.mounted == nil && g.inVehicle == nil, let f = a.poses["front"] { return f }
			return 0
		}
	}

	/// Blocks on the move (falling sand, blocks thrown by blasts and storms, a structure coming down),
	/// turning as they fly
	static func drawFlyingBlocks(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.fallingBlocks.isEmpty { return }
		let art: Art = Art.shared
		let s: Double = v.tp
		for fb in g.fallingBlocks {
			if !v.visible(fb.x, fb.y - 0.5, 2) { continue }
			let img: Image = art.icon(.block(fb.tile))
			if abs(fb.ang) < 0.01 {
				ctx.draw(img, in: v.rect(fb.x - 0.5, fb.y - 1.0, 1.0, 1.0))
			} else {
				var c: GraphicsContext = ctx
				c.translateBy(x: CGFloat(v.sx(fb.x)), y: CGFloat(v.sy(fb.y - 0.5)))
				c.rotate(by: Angle(radians: fb.ang))
				c.draw(img, in: mkRect(-s * 0.5, -s * 0.5, s, s))
			}
		}
	}

	/// Lift cars: a floor plate, two posts and a roof bar, the cable up the rails, and a lamp lit
	/// while it moves
	static func drawLifts(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		for l in g.lifts {
			if !v.visible(Double(l.x) + 0.5, l.y - 1.5, 4) { continue }
			let x0: Double = l.x0 + 0.05
			let w: Double = 2.9
			fillRect(&ctx, v.rect(x0, l.y, w, 0.3), Color(hex: 0x4A5260))
			fillRect(&ctx, v.rect(x0, l.y, w, 0.1), Color(hex: 0x9AA4B0))
			fillRect(&ctx, v.rect(x0, l.y - 3.0, 0.15, 3.0), Color(hex: 0x5A6270))
			fillRect(&ctx, v.rect(x0 + w - 0.15, l.y - 3.0, 0.15, 3.0), Color(hex: 0x5A6270))
			fillRect(&ctx, v.rect(x0, l.y - 3.05, w, 0.18), Color(hex: 0x5A6270))
			fillRect(&ctx, v.rect(Double(l.x) + 0.47, l.y - 6.0, 0.06, 2.95), Color(hex: 0x2A2A2A))
			let lamp: Color = l.target != nil ? Color(hex: 0x6AF06A) : Color(hex: 0x8A3030)
			fillRect(&ctx, v.rect(Double(l.x) + 0.35, l.y - 2.85, 0.3, 0.2), lamp)
		}
	}

	/// Cracks in built blocks under strain (structural physics): fine ones, heavy ones past 90%
	static func drawStress(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if !g.settings.structural { return }
		var fine: Path = Path()
		var heavy: Path = Path()
		let s: Double = v.tp
		for (k, f) in g.stress {
			let x: Int = floorDiv(k, 4096)
			let y: Int = k - x * 4096
			if !v.visible(Double(x) + 0.5, Double(y) + 0.5, 1) { continue }
			let px: Double = v.sx(Double(x))
			let py: Double = v.sy(Double(y))
			if f > 0.9 {
				crackLines(&heavy, px, py, s, true)
			} else {
				crackLines(&fine, px, py, s, false)
			}
		}
		ctx.stroke(fine, with: .color(Color.black.opacity(0.45)), lineWidth: 1)
		ctx.stroke(heavy, with: .color(Color.black.opacity(0.75)), lineWidth: 2)
	}

	/// One crack across a block at screen (px, py), s pixels wide (a branch on heavy ones)
	static func crackLines(_ p: inout Path, _ px: Double, _ py: Double, _ s: Double, _ branch: Bool) {
		p.move(to: CGPoint(x: px + s * 0.22, y: py + s * 0.08))
		p.addLine(to: CGPoint(x: px + s * 0.48, y: py + s * 0.38))
		p.addLine(to: CGPoint(x: px + s * 0.34, y: py + s * 0.62))
		p.addLine(to: CGPoint(x: px + s * 0.66, y: py + s * 0.92))
		if branch {
			p.move(to: CGPoint(x: px + s * 0.48, y: py + s * 0.38))
			p.addLine(to: CGPoint(x: px + s * 0.8, y: py + s * 0.3))
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
		case .spear:
			// a straight thrust: the spear levels out and drives forward, then draws back
			ang = Double.pi * 0.25 - 0.15
			rect = mkRect(-sz * 0.35, -sz * 0.9, sz * 1.25, sz * 1.25)
			if g.swingT > 0 {
				let t: Double = 1.0 - g.swingT / max(0.01, g.swingDur)
				let push: Double = sin(min(1.0, t * 1.6) * Double.pi) * 0.55 * v.tp
				c.rotate(by: Angle(radians: clampD(aimAng, -1.1, 1.1)))
				c.translateBy(x: CGFloat(push), y: 0)
				ang = Double.pi * 0.25
			} else if g.mining {
				ang = Double.pi * 0.25 - 0.15 * abs(sin(g.clock * 9.0))
			}
		case .knife, .relic(.moonDagger):
			// a quick jab forward toward the aim, held low and ready between blows
			ang = Double.pi * 0.25 + 0.2
			rect = mkRect(-sz * 0.2, -sz * 0.7, sz * 0.85, sz * 0.85)
			if g.swingT > 0 {
				let t: Double = 1.0 - g.swingT / max(0.01, g.swingDur)
				let push: Double = sin(min(1.0, t * 1.8) * Double.pi) * 0.4 * v.tp
				c.rotate(by: Angle(radians: clampD(aimAng, -1.2, 1.2)))
				c.translateBy(x: CGFloat(push), y: 0)
				ang = Double.pi * 0.25
			}
		case .club, .relic(.quakeMaul):
			// raised over the shoulder during the wind-up, then brought down hard
			rect = mkRect(-sz * 0.2, -sz * 0.95, sz * 1.1, sz * 1.1)
			if g.swingT > 0 {
				let t: Double = 1.0 - g.swingT / max(0.01, g.swingDur)
				let e: Double = 1.0 - pow(1.0 - t, 3.0)
				ang = (-120.0 + 200.0 * e) * Double.pi / 180.0 + clampD(aimAng, -0.8, 0.8) * 0.6
			} else {
				ang = -0.3
			}
		case .sling:
			rect = mkRect(-sz * 0.2, -sz * 0.6, sz * 0.8, sz * 0.8)
			ang = g.swingT > 0 ? g.clock * 30.0 : -0.2
		case .hammer:
			// wound up high, then brought down hard past level
			rect = mkRect(-sz * 0.2, -sz * 1.0, sz * 1.15, sz * 1.15)
			if g.swingT > 0 {
				let t: Double = 1.0 - g.swingT / max(0.01, g.swingDur)
				// the head comes down fast (the blow lands at the start), then the swing settles
				let e: Double = 1.0 - pow(1.0 - t, 3.0)
				let deg: Double = -130.0 + 215.0 * e
				ang = deg * Double.pi / 180.0 + clampD(aimAng, -0.8, 0.8) * 0.6
			} else if g.mining {
				let wob: Double = abs(sin(g.clock * 7.0))
				ang = (-40.0 + 60.0 * wob) * Double.pi / 180.0
			} else {
				ang = -0.35
			}
		case .block, .mat, .food, .ammo, .part, .gadget, .wall, .gear:
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
				// the arc swings round the aim, so a blow aimed upward sweeps up there
				ang = deg * Double.pi / 180.0 + clampD(aimAng, -1.0, 1.0) * 0.8
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
		for veh in g.vehicles {
			if !v.visible(veh.b.x, veh.b.y, 10) { continue }
			drawVehicle(&ctx, g, v, veh)
		}
		// where the held part can go (green), or where a kit would land
		let tp: Double = v.tp
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

	/// One vehicle. Every cell is drawn at its rotated position with the vehicle's rotation, exactly where
	/// its collision samples are (a block cell shows its block). While it turns round in flight it is
	/// drawn narrowing to its edge and widening again, facing the other way.
	static func drawVehicle(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ veh: Vehicle) {
		let art: Art = Art.shared
		let tp: Double = v.tp
		let shade: Double = openShade(g, veh.b.x, veh.b.cy)
		let squash: Double = veh.turnT > 0 ? max(0.12, abs(cos(Double.pi * veh.turnT))) : 1.0
		let cx: Double = v.sx(veh.px)
		var cracks: Path = Path()
		var cracked: Bool = false
		// a big vehicle, or one with back walls, is drawn from one picture of its cells that do not move
		// (made again only when it changes); its wheels, propellers and drills are drawn over it
		let baked: Bool = VehicleArt.wanted(veh) && drawVehiclePicture(&ctx, v, veh, shade, squash, cx)
		for (cell, t) in veh.parts {
			// (a part bigger than one cell is drawn once, from its middle)
			if let m = veh.spanOf[cell], m != cell { continue }
			let inPicture: Bool = baked && VehicleArt.still(t)
			if inPicture && veh.hitT <= 0 && (veh.dmg[cell] ?? 0) <= 0.5 && !VehicleArt.working(veh, t) { continue }
			let p: (Double, Double) = veh.cellCenter(cell)
			var c: GraphicsContext = ctx
			if shade < 0.98 { c.addFilter(.colorMultiply(shadeColor(shade))) }
			let sx: Double = cx + (v.sx(p.0) - cx) * squash
			c.translateBy(x: CGFloat(sx), y: CGFloat(v.sy(p.1)))
			if squash < 0.999 { c.scaleBy(x: CGFloat(squash), y: 1) }
			var rot: Double = veh.angle
			var jitter: Double = 0
			var flip: Bool = false
			if isWheelPart(t) && t != .track { rot += veh.wheelRot }
			if t == .propeller { rot += veh.propRot }
			if isDrill(t), let d = veh.drillDir[cell] {
				rot += atan2(Double(d.1), Double(d.0))
				if veh.drilling { jitter = sin(veh.drillRot * 3.0) * tp * 0.03 }
			}
			if (t == .airProp || t == .jet || t == .tailRotor), let f = veh.face[cell], f.0 < 0 { flip = true }
			// (a piston points the way it pushes)
			if t == .piston, let j = veh.joints.first(where: { $0.cell == cell }) { rot += atan2(j.axis[1], j.axis[0]) }
			c.rotate(by: Angle(radians: rot))
			if flip { c.scaleBy(x: -1, y: 1) }
			let w: Double = tp * 1.02 * Double(partSpan(t))
			if t == .bigWheel {
				drawBigWheel(&c, w)
			} else if !inPicture {
				let img: Image = veh.blocks[cell].map { art.tile($0) } ?? art.parts[t.rawValue]
				c.draw(img, in: mkRect(-w * 0.5 + jitter, -w * 0.5, w, w))
			}
			if isDrill(t) && veh.drilling {
				// spinning bit: alternating highlight bands
				let band: Double = (veh.drillRot.truncatingRemainder(dividingBy: 1.0)) * w * 0.4
				fillRect(&c, mkRect(w * 0.0 + band - w * 0.1, -w * 0.25, w * 0.08, w * 0.5), Color.white.opacity(0.35))
			}
			if t == .envelope { envelopeEdges(&c, veh, cell, w) }
			if veh.aero || t == .burner { drawPartWorking(&c, veh, cell, t, w, g.clock) }
			if let d = veh.dmg[cell], d > 0.5 {
				let hp: Double = vehicleCellHP(veh, cell, t)
				if d > hp * 0.3 {
					crackLines(&cracks, sx - w * 0.5, v.sy(p.1) - w * 0.5, w, d > hp * 0.7)
					cracked = true
				}
			}
			if veh.hitT > 0 { fillRect(&c, mkRect(-w * 0.5, -w * 0.5, w, w), Color(hex: 0xFF3020, alpha: 0.3)) }
		}
		if cracked { ctx.stroke(cracks, with: .color(Color.black.opacity(0.7)), lineWidth: 1.5) }
		if veh.cannons + veh.guns > 0 { drawBarrels(&ctx, v, veh, squash, cx) }
		if !veh.links.isEmpty { drawCouplings(&ctx, g, v, veh) }
		if !veh.joints.isEmpty { drawPistonRods(&ctx, g, v, veh) }
	}

	/// A piston's rod, from its head out to the section it pushes, as long as it is pushed out
	static func drawPistonRods(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ veh: Vehicle) {
		for j in veh.joints where j.kind == 2 {
			guard let o = g.vehicleByID(j.child) else { continue }
			let ux: Double = j.axis[0]
			let uy: Double = j.axis[1]
			let a: (Double, Double) = veh.toWorld(j.pa[0] + ux * 0.45, j.pa[1] + uy * 0.45)
			let b: (Double, Double) = o.toWorld(j.pb[0] + ux * 0.5, j.pb[1] + uy * 0.5)
			let dx: Double = b.0 - a.0
			let dy: Double = b.1 - a.1
			if dx * dx + dy * dy < 0.0025 { continue }
			strokeLine(&ctx, v.sx(a.0), v.sy(a.1), v.sx(b.0), v.sy(b.1), Color(hex: 0x1E1E24), v.tp * 0.34)
			strokeLine(&ctx, v.sx(a.0), v.sy(a.1), v.sx(b.0), v.sy(b.1), Color(hex: 0x9AA0AA), v.tp * 0.22)
			strokeLine(&ctx, v.sx(a.0), v.sy(a.1), v.sx(b.0), v.sy(b.1), Color(hex: 0xC8CCD4), v.tp * 0.07)
		}
	}

	/// A big wheel, round at any size: a treaded tyre, the rim and four spokes (the context is already
	/// turned with the wheel)
	static func drawBigWheel(_ c: inout GraphicsContext, _ w: Double) {
		let r: Double = w * 0.49
		fillOval(&c, mkRect(-r, -r, r * 2, r * 2), Color(hex: 0x1A1A1E))
		let t: Double = r * 0.86
		fillOval(&c, mkRect(-t, -t, t * 2, t * 2), Color(hex: 0x2E2E34))
		let rim: Double = r * 0.56
		fillOval(&c, mkRect(-rim, -rim, rim * 2, rim * 2), Color(hex: artGrade(0x8A8A94)))
		let hub: Double = r * 0.18
		var k: Int = 0
		while k < 4 {
			let a: Double = Double(k) * Double.pi * 0.5
			strokeLine(&c, 0, 0, cos(a) * rim, sin(a) * rim, Color(hex: 0x4A4A52), max(1.5, w * 0.05))
			k += 1
		}
		// tread blocks round the tyre
		k = 0
		while k < 12 {
			let a: Double = Double(k) * Double.pi / 6.0
			let x: Double = cos(a) * r * 0.93
			let y: Double = sin(a) * r * 0.93
			fillOval(&c, mkRect(x - w * 0.035, y - w * 0.035, w * 0.07, w * 0.07), Color(hex: 0x3A3A42))
			k += 1
		}
		fillOval(&c, mkRect(-hub, -hub, hub * 2, hub * 2), Color(hex: artGrade(0xD8D8E0)))
	}

	/// The bar between two coupled vehicles' couplers (drawn by the one with the lower number)
	static func drawCouplings(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D, _ veh: Vehicle) {
		for l in veh.links where veh.id < l.other {
			guard let o = g.vehicleByID(l.other) else { continue }
			let a: (Double, Double) = veh.cellCenter(l.cell)
			let b: (Double, Double) = o.cellCenter(l.oc)
			strokeLine(&ctx, v.sx(a.0), v.sy(a.1), v.sx(b.0), v.sy(b.1), Color(hex: 0x1E1E24), v.tp * 0.22)
			strokeLine(&ctx, v.sx(a.0), v.sy(a.1), v.sx(b.0), v.sy(b.1), Color(hex: 0x6A6E78), v.tp * 0.12)
		}
	}

	/// Draws a vehicle's still cells and back walls from its cached picture (true when it did)
	static func drawVehiclePicture(_ ctx: inout GraphicsContext, _ v: View2D, _ veh: Vehicle, _ shade: Double, _ squash: Double, _ cx: Double) -> Bool {
		guard let img = VehicleArt.picture(veh) else { return false }
		let tp: Double = v.tp
		var c: GraphicsContext = ctx
		if shade < 0.98 { c.addFilter(.colorMultiply(shadeColor(shade))) }
		if squash < 0.999 {
			c.translateBy(x: CGFloat(cx), y: 0)
			c.scaleBy(x: CGFloat(squash), y: 1)
			c.translateBy(x: CGFloat(-cx), y: 0)
		}
		let corner: (Double, Double) = veh.toWorld(Double(veh.minX), Double(veh.minY))
		c.translateBy(x: CGFloat(v.sx(corner.0)), y: CGFloat(v.sy(corner.1)))
		c.rotate(by: Angle(radians: veh.angle))
		c.draw(img, in: mkRect(0, 0, Double(veh.gridW) * tp, Double(veh.gridH) * tp))
		return true
	}

	/// Moving parts at work: rotor blades and propeller discs spinning, a jet's flame, a burner's flame
	static func drawPartWorking(_ c: inout GraphicsContext, _ veh: Vehicle, _ cell: PartCell, _ t: PartType, _ w: Double, _ clock: Double) {
		switch t {
		case .rotor:
			// two blades seen from the side: a bar that sweeps out and back, blurred when fast
			let spin: Double = veh.collective
			let half: Double = w * 2.4
			if spin > 0.05 || veh.propRot > 0 {
				fillRect(&c, mkRect(-half, -w * 0.56, half * 2.0, w * 0.1), Color(hex: 0x30303A, alpha: 0.18 + 0.2 * spin))
			}
			let reach: Double = half * max(0.15, abs(cos(veh.propRot)))
			fillRect(&c, mkRect(-reach, -w * 0.58, reach * 2.0, w * 0.12), Color(hex: 0x2A2A30))
		case .airProp:
			let k: Double = abs(veh.throttle)
			if k > 0.05 {
				let h: Double = w * 0.85 * max(0.2, abs(cos(veh.propRot)))
				fillOval(&c, mkRect(w * 0.3, -w * 0.85, w * 0.35, w * 1.7), Color(hex: 0xC8C8D0, alpha: 0.25))
				fillRect(&c, mkRect(w * 0.4, -h, w * 0.14, h * 2.0), Color(hex: 0x8F6732))
			}
		case .tailRotor:
			if veh.collective > 0.05 {
				fillOval(&c, mkRect(w * 0.25, -w * 0.5, w * 0.35, w), Color(hex: 0xC8C8D0, alpha: 0.3))
			}
		case .jet:
			let k: Double = abs(veh.throttle)
			if k > 0.08 && (veh.rider || veh.auto != 0) {
				let flick: Double = 0.75 + 0.25 * sin(clock * 40.0 + Double(cell.dx))
				let len: Double = w * (0.4 + 0.9 * k) * flick
				fillOval(&c, mkRect(w * 0.45, -w * 0.22, len, w * 0.44), Color(hex: 0xFF8A30, alpha: 0.8))
				fillOval(&c, mkRect(w * 0.45, -w * 0.12, len * 0.6, w * 0.24), Color(hex: 0xFFF0A0, alpha: 0.9))
			}
		case .burner:
			if veh.heat > 0.05 {
				let flick: Double = 0.7 + 0.3 * sin(clock * 30.0 + Double(cell.dx) * 2.0)
				let hgt: Double = w * (0.3 + 0.8 * veh.heat) * flick
				fillOval(&c, mkRect(-w * 0.18, -w * 0.5 - hgt, w * 0.36, hgt), Color(hex: 0xFF8A30, alpha: 0.85))
				fillOval(&c, mkRect(-w * 0.09, -w * 0.5 - hgt * 0.6, w * 0.18, hgt * 0.6), Color(hex: 0x80B0FF, alpha: 0.9))
			}
		default:
			break
		}
	}

	/// A darker seam where the balloon's canvas meets the open air, so the envelope reads as one shape
	static func envelopeEdges(_ c: inout GraphicsContext, _ veh: Vehicle, _ cell: PartCell, _ w: Double) {
		let h: Double = w * 0.5
		let col: Color = Color(hex: 0x7A2A20, alpha: 0.8)
		let lw: Double = max(1.0, w / 12.0)
		if veh.parts[PartCell(dx: cell.dx, dy: cell.dy - 1)] != .envelope { fillRect(&c, mkRect(-h, -h, w, lw), col) }
		if veh.parts[PartCell(dx: cell.dx, dy: cell.dy + 1)] != .envelope { fillRect(&c, mkRect(-h, h - lw, w, lw), col) }
		if veh.parts[PartCell(dx: cell.dx - 1, dy: cell.dy)] != .envelope { fillRect(&c, mkRect(-h, -h, lw, w), col) }
		if veh.parts[PartCell(dx: cell.dx + 1, dy: cell.dy)] != .envelope { fillRect(&c, mkRect(h - lw, -h, lw, w), col) }
	}

	/// The barrels of a vehicle's guns, turned to where each one aims
	static func drawBarrels(_ ctx: inout GraphicsContext, _ v: View2D, _ veh: Vehicle, _ squash: Double, _ cx: Double) {
		let tp: Double = v.tp
		for (cell, t) in veh.parts where t == .cannon || t == .autoGun {
			let p: (Double, Double) = veh.cellCenter(cell)
			let f: (Int, Int) = veh.face[cell] ?? (1, 0)
			let a: Double = veh.aimAng[cell] ?? (veh.angle + atan2(Double(f.1), Double(f.0)))
			let len: Double = t == .cannon ? 1.0 : 0.75
			let x0: Double = cx + (v.sx(p.0) - cx) * squash
			let y0: Double = v.sy(p.1)
			let x1: Double = x0 + cos(a) * len * tp * squash
			let y1: Double = y0 + sin(a) * len * tp
			let thick: Double = (t == .cannon ? 0.24 : 0.12) * tp
			strokeLine(&ctx, x0, y0, x1, y1, Color(hex: 0x1E1E24), thick + 2.0)
			strokeLine(&ctx, x0, y0, x1, y1, Color(hex: t == .cannon ? 0x4A5040 : 0x3A3A42), thick)
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

	/// The rift: one composite shape over its tiles. States read at a glance:
	/// dormant (dark, cracked, shards resting), open (teal swirl ringed by amber shards), charging
	/// (brightens and spins up while you stand inside) and resting after a trip (dim until you step out).
	static func drawRift(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let c: (Double, Double) = g.riftCenter
		if !v.visible(c.0, c.1, 7) { return }
		let core: Tile = g.world.tile(Int(floor(c.0)), Int(floor(c.1)))
		if core != .portalOn && core != .portalOff { return }
		let open: Bool = core == .portalOn
		let t: Double = g.clock
		let tp: Double = v.tp
		let cx: Double = v.sx(c.0)
		let cy: Double = v.sy(c.1)
		let rx: Double = 2.55 * tp
		let ry: Double = 3.55 * tp
		let charge: Double = min(1.0, g.portalT / 1.1)
		let resting: Bool = open && (g.portalNeedsExit || g.portalCool > 0)
		let teal: UInt32 = 0x3FCFC0
		let amber: UInt32 = 0xF0A848
		if !open {
			// dormant: a dark seam with a faint amber crack and shards lying at its foot
			fillOval(&ctx, mkRect(cx - rx * 0.9, cy - ry * 0.95, rx * 1.8, ry * 1.9), Color(hex: 0x0C0E14, alpha: 0.82))
			ctx.stroke(Path(ellipseIn: mkRect(cx - rx * 0.9, cy - ry * 0.95, rx * 1.8, ry * 1.9)), with: .color(Color(hex: 0x4A4E5C)), lineWidth: max(1.5, tp * 0.08))
			let pulse: Double = 0.25 + 0.15 * sin(t * 1.3)
			strokeLine(&ctx, cx, cy - ry * 0.7, cx - tp * 0.3, cy - ry * 0.2, Color(hex: amber, alpha: pulse), max(1.0, tp * 0.06))
			strokeLine(&ctx, cx - tp * 0.3, cy - ry * 0.2, cx + tp * 0.2, cy + ry * 0.3, Color(hex: amber, alpha: pulse), max(1.0, tp * 0.06))
			strokeLine(&ctx, cx + tp * 0.2, cy + ry * 0.3, cx, cy + ry * 0.75, Color(hex: amber, alpha: pulse), max(1.0, tp * 0.06))
			for i in 0..<6 {
				let fx: Double = cx + (Double(i) - 2.5) * tp * 0.7
				let fy: Double = cy + ry * 0.92 - abs(Double(i) - 2.5) * tp * 0.12 + sin(t * 0.8 + Double(i)) * tp * 0.04
				shard(&ctx, fx, fy, tp * 0.22, Color(hex: 0x6A5A48))
			}
			return
		}
		let dim: Double = resting ? 0.45 : 1.0
		let glow: Double = (0.55 + 0.45 * charge) * dim
		// soft halo, then the body in nested ovals (light toward the middle)
		fillOval(&ctx, mkRect(cx - rx * 1.25, cy - ry * 1.18, rx * 2.5, ry * 2.36), Color(hex: teal, alpha: 0.10 * glow))
		let layers: [(Double, UInt32, Double)] = [(1.0, 0x0B2E36, 0.92), (0.82, 0x12505A, 0.9), (0.62, 0x1F7F84, 0.85), (0.42, 0x3FB8B0, 0.8), (0.22, 0xA8F0E4, 0.75)]
		for (k, layer) in layers.enumerated() {
			let wob: Double = 1.0 + 0.03 * sin(t * 2.0 + Double(k))
			let sx: Double = rx * layer.0 * wob * (1.0 + charge * 0.06)
			let sy: Double = ry * layer.0 * wob * (1.0 + charge * 0.04)
			let a: Double = layer.2 * (k < 2 ? 1.0 : glow)
			fillOval(&ctx, mkRect(cx - sx, cy - sy, sx * 2.0, sy * 2.0), Color(hex: layer.1, alpha: a))
		}
		// swirl arcs drawn as short polylines along the oval, spinning faster while charging
		let spin: Double = t * (resting ? 0.4 : 1.1 + charge * 4.0)
		let lw: Double = max(1.5, tp * 0.09)
		for arm in 0..<3 {
			let base: Double = spin + Double(arm) * 2.094
			var px0: Double = 0
			var py0: Double = 0
			for s in 0...8 {
				let f: Double = Double(s) / 8.0
				let ang: Double = base + f * 1.5
				let r: Double = 0.85 - f * 0.45
				let x1: Double = cx + cos(ang) * rx * r
				let y1: Double = cy + sin(ang) * ry * r
				if s > 0 {
					let col: UInt32 = arm == 0 ? amber : 0xC8FFF4
					strokeLine(&ctx, px0, py0, x1, y1, Color(hex: col, alpha: (1.0 - f) * 0.7 * glow), lw)
				}
				px0 = x1
				py0 = y1
			}
		}
		// orbiting amber shards
		for i in 0..<8 {
			let ang: Double = spin * 0.6 + Double(i) * 0.785
			let r: Double = 1.18 + 0.05 * sin(t * 3.0 + Double(i))
			let sx: Double = cx + cos(ang) * rx * r
			let sy: Double = cy + sin(ang) * ry * r
			shard(&ctx, sx, sy, tp * (0.2 + 0.06 * charge), Color(hex: amber, alpha: 0.5 + 0.5 * dim))
		}
	}

	static func shard(_ ctx: inout GraphicsContext, _ x: Double, _ y: Double, _ s: Double, _ c: Color) {
		var p: Path = Path()
		p.move(to: mkPoint(x, y - s))
		p.addLine(to: mkPoint(x + s * 0.55, y))
		p.addLine(to: mkPoint(x, y + s))
		p.addLine(to: mkPoint(x - s * 0.55, y))
		p.closeSubpath()
		ctx.fill(p, with: .color(c))
	}

	/// The sky's clouds: a few layers of cached cloud images, drawn behind the terrain. Far layers are
	/// small and pale and follow the camera least. A clear sky keeps a scattering of cloud; the heavier
	/// the weather, the more cells fill, the clouds turn storm-grey, and a low, dark deck of big cloud
	/// builds across the top of the sky. Dusk warms the clouds and night cools them.
	static func drawClouds(_ ctx: inout GraphicsContext, _ W: Double, _ H: Double, _ g: Game, _ v: View2D, _ day: Double, _ dusk: Double) {
		let seed: UInt64 = g.gen.seed
		let drift: Double = g.weather.cloudDrift
		let cover: Double = g.settings.weatherOn ? g.wxHere.cloud : 0
		let wet: Double = g.settings.weatherOn ? g.wxHere.precip : 0
		// white by day, cool blue-grey at night, warm at dusk, storm-grey under heavy cloud
		var tint: UInt32 = mixRGB(0x58628A, 0xFFFFFF, day)
		tint = mixRGB(tint, 0xFFC4A0, dusk * 0.5)
		let storm: Double = clampD((cover - 0.4) * 1.7, 0, 0.85) * (0.75 + 0.25 * wet)
		if storm > 0 { tint = mixRGB(tint, mixRGB(0x262B33, 0x6C727E, day), storm) }
		let sky: UInt32 = mixRGB(0x18223E, 0xB4DCFF, day)
		let camMid: Double = v.top + v.hTiles * 0.5
		// the sky is far away: zooming in past the usual size does not bring the clouds down to the
		// player, they keep the size and place they have at the usual zoom
		let ctp: Double = min(v.tp, 24.0)
		let px: Double = ctp / CloudField.pxPerTile
		let art: CloudArt = CloudArt.shared
		let fills: [Double] = [0.46 + 0.45 * cover, 0.40 + 0.52 * cover, 0.26 + 0.60 * cover, clampD((cover - 0.35) / 0.5, 0, 1) * 0.95]
		for li in 0..<CloudField.layers.count {
			let L: CloudField.Layer = CloudField.layers[li]
			if fills[li] <= 0.02 { continue }
			let left: Double = v.left * L.par
			let list: [CloudField.Cloud] = CloudField.clouds(seed, li, drift, left, left + W / ctp, fill: fills[li])
			if list.isEmpty { continue }
			var layerTint: UInt32 = mixRGB(tint, sky, L.haze)
			if li == 3 { layerTint = mixRGB(layerTint, 0x30363E, 0.4) }
			// the sky band follows the camera up and down a little, so clouds stay in view on hills
			let rise: Double = clampD((112.0 - camMid) * L.lift, -3.0, 9.0)
			var c: GraphicsContext = ctx
			c.addFilter(.colorMultiply(rgbColor(layerTint)))
			for cl in list {
				let b: PixelBuf = art.shapes[cl.kind]
				let sx: Double = ((cl.x - left) * ctp / px).rounded() * px
				let sy: Double = ((cl.y + rise) * ctp / px).rounded() * px
				let cw: Double = Double(b.w) * px
				if sx > W || sx + cw < 0 || sy > H || sy + Double(b.h) * px < 0 { continue }
				c.opacity = L.opacity * cl.alpha
				let img: Image = cl.flip ? art.flipped[cl.kind] : art.images[cl.kind]
				c.draw(img, in: mkRect(sx, sy, cw, Double(b.h) * px))
			}
		}
	}

	/// The visible burst of an explosion: warm additive glow rings over the light layer. In the dark the
	/// light map already brightens the surrounding blocks; this makes the burst readable in daylight
	/// too, where everything is already at full light and the light map cannot get any brighter.
	static func drawFlashes(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.flashes.isEmpty { return }
		var c: GraphicsContext = ctx
		c.blendMode = .plusLighter
		for f in g.flashes {
			if !v.visible(f.x, f.y, f.radius + 2) { continue }
			let k: Double = f.strength
			if k <= 0.01 { continue }
			let cx: Double = v.sx(f.x)
			let cy: Double = v.sy(f.y)
			// three soft rings: wide and dim, middle, small bright core (amber for fire, blue for lightning)
			let mid: UInt32 = mixRGB(f.color, 0xFFFFFF, 0.25)
			let core: UInt32 = mixRGB(f.color, 0xFFFFFF, 0.7)
			let rings: [(Double, UInt32, Double)] = [(1.0, f.color, 0.16), (0.6, mid, 0.22), (0.28, core, 0.34)]
			for ring in rings {
				let r: Double = f.radius * ring.0 * v.tp * (0.85 + 0.15 * k)
				fillOval(&c, mkRect(cx - r, cy - r, r * 2.0, r * 2.0), rgbColor(ring.1, ring.2 * k))
			}
		}
	}

	/// Dotted flight path while drawing a bow (fades along its length; stops at the first block)
	static func drawTrajectory(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if !g.settings.showTrajectory || g.inVehicle != nil { return }
		let pts: [(Double, Double)] = g.arrowPreview()
		if pts.isEmpty { return }
		let r: Double = max(1.5, v.tp * 0.07)
		let n: Double = Double(pts.count)
		let strength: Double = g.bowCharge > 0 ? min(1.0, g.bowCharge * 1.6) : 0.7
		for (i, p) in pts.enumerated() {
			let a: Double = 0.55 * (1.0 - Double(i) / n) * strength
			fillRect(&ctx, mkRect(v.sx(p.0) - r, v.sy(p.1) - r, r * 2.0, r * 2.0), Color.white.opacity(a))
		}
	}

	/// A mod's shot: its shape in its colour, with a faint trail
	static func drawModShot(_ ctx: inout GraphicsContext, _ p: Projectile, _ x: Double, _ y: Double, _ tp: Double) {
		let rt: ModRuntime = ModRuntime.shared
		guard p.mod >= 0 && p.mod < rt.shots.count else { return }
		let s: ModProjectile = rt.shots[p.mod]
		let col: Color = Color(hex: s.color & 0xFFFFFF)
		let hi: Color = Color(hex: mixRGB(s.color & 0xFFFFFF, 0xFFFFFF, 0.5))
		let ang: Double = atan2(p.vy, p.vx)
		let dx: Double = cos(ang)
		let dy: Double = sin(ang)
		let r: Double = max(3.0, s.size * tp * 0.5)
		strokeLine(&ctx, x - dx * r * 3.0, y - dy * r * 3.0, x, y, Color(hex: s.color & 0xFFFFFF, alpha: 0.3), max(2.0, r * 0.8))
		switch s.shape {
		case .orb:
			fillOval(&ctx, mkRect(x - r, y - r, r * 2, r * 2), col)
			fillOval(&ctx, mkRect(x - r * 0.5, y - r * 0.6, r * 0.8, r * 0.8), hi)
		case .arrow, .bolt:
			let len: Double = r * (s.shape == .arrow ? 3.2 : 2.2)
			strokeLine(&ctx, x - dx * len, y - dy * len, x + dx * len * 0.3, y + dy * len * 0.3, s.shape == .arrow ? Color(hex: 0x8A6A40) : col, max(2.0, r * 0.6))
			strokeLine(&ctx, x, y, x + dx * len * 0.5, y + dy * len * 0.5, hi, max(2.5, r * 0.9))
		case .shard:
			strokeLine(&ctx, x - dx * r * 2.0, y - dy * r * 2.0, x + dx * r * 1.5, y + dy * r * 1.5, col, max(2.5, r))
			strokeLine(&ctx, x - dx * r, y - dy * r, x + dx * r, y + dy * r, hi, max(1.5, r * 0.4))
		case .rock:
			fillRect(&ctx, mkRect(x - r, y - r, r * 2, r * 2), col)
			fillRect(&ctx, mkRect(x - r, y - r, r, r * 0.8), hi)
		}
	}

	static func drawProjectiles(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let tp: Double = v.tp
		for p in g.projectiles {
			if !v.visible(p.x, p.y, 2) { continue }
			let x: Double = v.sx(p.x)
			let y: Double = v.sy(p.y)
			if p.mod >= 0 {
				drawModShot(&ctx, p, x, y, tp)
				continue
			}
			switch p.kind {
			case .quarrel:
				// a short, heavy bolt with a bronze head
				let ang: Double = p.stuck > 0 ? p.stuckAngle : atan2(p.vy, p.vx)
				let dx: Double = cos(ang)
				let dy: Double = sin(ang)
				let hx: Double = dx * tp * 0.32
				let hy: Double = dy * tp * 0.32
				let lw: Double = max(2.5, tp / 9.0)
				if p.stuck <= 0 {
					strokeLine(&ctx, x - hx - dx * tp * 0.7, y - hy - dy * tp * 0.7, x - hx, y - hy, Color.white.opacity(0.2), lw)
				}
				strokeLine(&ctx, x - hx, y - hy, x + hx, y + hy, Color(hex: 0x6A4A26), lw)
				strokeLine(&ctx, x + hx * 0.5, y + hy * 0.5, x + hx * 1.1, y + hy * 1.1, Color(hex: 0xC89040), lw + 1.5)
			case .pellet:
				let ang: Double = atan2(p.vy, p.vx)
				strokeLine(&ctx, x - cos(ang) * tp * 0.5, y - sin(ang) * tp * 0.5, x, y, Color(hex: 0xFFE8A0, alpha: 0.35), 2)
				fillRect(&ctx, mkRect(x - 2.0, y - 2.0, 4, 4), Color(hex: 0xFFF2C0))
			case .pebble:
				let sz: Double = max(4.0, p.w * tp)
				let h: Double = sz * 0.5
				fillRect(&ctx, mkRect(x - h, y - h, sz, sz), Color(hex: 0x8A8A8A))
				fillRect(&ctx, mkRect(x - h, y - h, sz * 0.5, sz * 0.45), Color(hex: 0xB0B0B0))
			case .flask:
				let r: Double = tp * 0.26
				let pot: Potion? = p.potion >= 0 ? Potion(rawValue: p.potion) : nil
				fillOval(&ctx, mkRect(x - r, y - r, r * 2.0, r * 2.0), Color(hex: 0xB8E0F0))
				fillOval(&ctx, mkRect(x - r * 0.75, y - r * 0.55, r * 1.5, r * 1.3), Color(hex: pot?.color ?? 0xFF7A1E))
				fillRect(&ctx, mkRect(x - r * 0.3, y - r * 1.6, r * 0.6, r * 0.7), Color(hex: 0xB8E0F0))
				if pot == nil {
					let flick: Bool = Int(p.life * 12.0) % 2 == 0
					fillRect(&ctx, mkRect(x - 2.0, y - r * 2.2, 4, 4), flick ? Color(hex: 0xFFD040) : Color(hex: 0xFF8030))
				} else {
					fillRect(&ctx, mkRect(x - r * 0.3, y - r * 2.0, r * 0.6, r * 0.4), Color(hex: 0x8A5A2A))
				}
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
				fillOval(&ctx, mkRect(x - tp * 0.34, y - tp * 0.34, tp * 0.68, tp * 0.68), Color(hex: 0x8A4AE0, alpha: 0.45))
				fillOval(&ctx, mkRect(x - 5.0, y - 5.0, 10, 10), Color(hex: 0xC080FF))
				fillOval(&ctx, mkRect(x - 2.0, y - 2.0, 4, 4), Color(hex: 0xF4E8FF))
			case .shard:
				// a slim crystal pointing along its flight
				let ang: Double = atan2(p.vy, p.vx)
				let dx: Double = cos(ang) * tp * 0.36
				let dy: Double = sin(ang) * tp * 0.36
				strokeLine(&ctx, x - dx, y - dy, x + dx, y + dy, Color(hex: 0x3AB8C0), max(3.0, tp / 6.0))
				strokeLine(&ctx, x - dx * 0.2, y - dy * 0.2, x + dx * 0.9, y + dy * 0.9, Color(hex: 0xD8FFFA), max(1.5, tp / 14.0))
			case .shell:
				// a dark shell with a faint smoke trail behind it
				let ang: Double = atan2(p.vy, p.vx)
				let r: Double = tp * 0.2
				strokeLine(&ctx, x - cos(ang) * tp * 0.9, y - sin(ang) * tp * 0.9, x, y, Color(hex: 0xC8C8C8, alpha: 0.35), max(2.0, tp / 8.0))
				fillOval(&ctx, mkRect(x - r, y - r, r * 2.0, r * 2.0), Color(hex: 0x2A2A30))
				fillOval(&ctx, mkRect(x - r * 0.5, y - r * 0.6, r * 0.6, r * 0.5), Color(hex: 0x7A7A84))
			}
		}
	}

	/// Fire from flasks, the trails of melee swings and the storm rod's lightning
	static func drawCombatFX(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let tp: Double = v.tp
		for z in g.fireZones {
			if !v.visible(z.x, z.y, z.r + 2) { continue }
			let fade: Double = clampD(z.t / 0.6, 0, 1)
			var x: Double = z.x - z.r
			var k: Int = 0
			while x <= z.x + z.r {
				// flickering tongues of flame along the patch, tallest in the middle
				let mid: Double = 1.0 - abs(x - z.x) / (z.r + 0.4)
				let flick: Double = 0.6 + 0.4 * sin(g.clock * 17.0 + Double(k) * 1.7)
				let h: Double = (0.35 + 0.75 * mid) * flick * fade
				fillRect(&ctx, v.rect(x - 0.17, z.y - h, 0.34, h), Color(hex: 0xFF6A1E, alpha: 0.75))
				fillRect(&ctx, v.rect(x - 0.09, z.y - h * 0.6, 0.18, h * 0.6), Color(hex: 0xFFD060, alpha: 0.85))
				x += 0.4
				k += 1
			}
		}
		for sl in g.slashes {
			let t: Double = 1.0 - sl.life / max(0.01, sl.maxLife)
			let a: Double = (sl.hit ? 0.9 : 0.65) * (1.0 - t * t)
			// chunky pixel blocks laid edge to edge, so the trail reads as one solid band
			let sz: Double = max(4.0, tp * 0.2)
			let stepPx: Double = sz * 0.75
			switch sl.style {
			case .thrust, .stab:
				// a straight jab out along the aim, its tip brightest
				let len: Double = sl.reach * (sl.style == .stab ? 0.9 : 1.0) * min(1.0, 0.4 + t * 1.6)
				let n: Int = max(3, Int((len - 0.35) * tp / stepPx))
				for i in 0..<n {
					let f: Double = Double(i) / Double(max(1, n - 1))
					let d: Double = 0.35 + f * (len - 0.35)
					let px: Double = sl.x + cos(sl.ang) * d
					let py: Double = sl.y + sin(sl.ang) * d
					let c: Color = f > 0.85 ? rgbColor(0xFFFFFF, a) : rgbColor(sl.color, a * (0.3 + 0.7 * f))
					fillRect(&ctx, mkRect(v.sx(px) - sz * 0.5, v.sy(py) - sz * 0.5, sz, sz), c)
				}
			case .slash, .smash, .bash:
				// a crescent swept round the aim from the top of the swing down: brightest at its leading
				// edge, a pale inner edge, fading toward where the swing began
				let r: Double = sl.reach * 0.85
				let sweep: Double = min(1.0, 0.3 + t * 2.2)
				let a0: Double = sl.ang - sl.halfArc
				let span: Double = sl.halfArc * 2.0 * sweep
				let n: Int = max(6, Int(span * r * tp / stepPx))
				for i in 0...n {
					let f: Double = Double(i) / Double(n)
					let aa: Double = a0 + span * f
					let k: Double = 0.25 + 0.75 * f
					let ox: Double = cos(aa)
					let oy: Double = sin(aa)
					fillRect(&ctx, mkRect(v.sx(sl.x + ox * r) - sz * 0.5, v.sy(sl.y + oy * r) - sz * 0.5, sz, sz), rgbColor(sl.color, a * k))
					let r2: Double = r - sz / tp * 0.9
					fillRect(&ctx, mkRect(v.sx(sl.x + ox * r2) - sz * 0.4, v.sy(sl.y + oy * r2) - sz * 0.4, sz * 0.8, sz * 0.8), rgbColor(0xFFFFFF, a * k * 0.7))
				}
			}
		}
		for arc in g.arcs {
			if arc.pts.count < 2 { continue }
			let a: Double = clampD(arc.life / 0.2, 0, 1)
			var path = Path()
			path.move(to: mkPoint(v.sx(arc.pts[0].0), v.sy(arc.pts[0].1)))
			for p in arc.pts.dropFirst() { path.addLine(to: mkPoint(v.sx(p.0), v.sy(p.1))) }
			ctx.stroke(path, with: .color(Color(hex: 0x6AB0FF, alpha: 0.55 * a)), lineWidth: max(4.0, tp * 0.22))
			ctx.stroke(path, with: .color(Color(hex: 0xF0F8FF, alpha: a)), lineWidth: max(1.5, tp * 0.07))
		}
	}

	/// Corner brackets round the foe the attacks are going at
	static func drawTargetMarker(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		guard let m = g.lockTarget, m.hp > 0, !m.removed, !g.dead else { return }
		if !(actState.held || g.lockT > 0) { return }
		if !v.visible(m.b.x, m.b.y, 4) { return }
		let pad: Double = 0.2
		let x0: Double = v.sx(m.b.left - pad)
		let x1: Double = v.sx(m.b.right + pad)
		let y0: Double = v.sy(m.b.top - pad)
		let y1: Double = v.sy(m.b.y + pad)
		let l: Double = max(5.0, min(x1 - x0, y1 - y0) * 0.28)
		let a: Double = actState.held ? 0.9 : clampD(g.lockT, 0, 1) * 0.7
		let c: Color = Color(hex: 0xFFE060, alpha: a)
		let w: Double = 2.0
		strokeLine(&ctx, x0, y0, x0 + l, y0, c, w); strokeLine(&ctx, x0, y0, x0, y0 + l, c, w)
		strokeLine(&ctx, x1, y0, x1 - l, y0, c, w); strokeLine(&ctx, x1, y0, x1, y0 + l, c, w)
		strokeLine(&ctx, x0, y1, x0 + l, y1, c, w); strokeLine(&ctx, x0, y1, x0, y1 - l, c, w)
		strokeLine(&ctx, x1, y1, x1 - l, y1, c, w); strokeLine(&ctx, x1, y1, x1, y1 - l, c, w)
	}

	/// Four short dashes leading away from the player along the way the combat stick is aiming
	static func drawStickAim(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if !actState.manual || g.dead || g.inVehicle != nil { return }
		let dx: Double = actState.dirX
		let dy: Double = actState.dirY
		let ox: Double = g.shoulderX
		let oy: Double = g.shoulderY
		for k in 0..<4 {
			let d0: Double = 1.5 + Double(k) * 0.65
			let a: Double = 0.85 - Double(k) * 0.16
			strokeLine(&ctx, v.sx(ox + dx * d0), v.sy(oy + dy * d0), v.sx(ox + dx * (d0 + 0.3)), v.sy(oy + dy * (d0 + 0.3)), Color(hex: 0xFFE080, alpha: a), 3)
		}
	}

	/// Falling leaves: two or three art pixels each, turning over as they sway
	static func drawLeafFall(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		if g.leafFlakes.isEmpty { return }
		let p: Double = max(1.0, (v.tp / Double(tileArtPx)).rounded())
		for f in g.leafFlakes {
			if !v.visible(f.x, f.y, 1) { continue }
			let a: Double = f.landed ? clampD(f.life / 2.5, 0, 1) : 1.0
			let x: Double = (v.sx(f.x) / p).rounded() * p
			let y: Double = (v.sy(f.y) / p).rounded() * p
			let lc: Color = rgbColor(f.light, a)
			let dc: Color = rgbColor(f.dark, a)
			// four ways round as it tumbles: flat, tipped one way, on edge, tipped the other way
			let turn: Int = f.landed ? 0 : Int(f.phase * 1.3) & 3
			switch turn {
			case 0:
				fillRect(&ctx, mkRect(x - p, y, p * 2.0, p), lc)
				fillRect(&ctx, mkRect(x + p, y, p, p), dc)
			case 1:
				fillRect(&ctx, mkRect(x - p, y - p, p, p), lc)
				fillRect(&ctx, mkRect(x, y, p, p), lc)
				fillRect(&ctx, mkRect(x + p, y + p, p, p), dc)
			case 2:
				fillRect(&ctx, mkRect(x, y - p, p, p), lc)
				fillRect(&ctx, mkRect(x, y, p, p), dc)
			default:
				fillRect(&ctx, mkRect(x + p, y - p, p, p), lc)
				fillRect(&ctx, mkRect(x, y, p, p), lc)
				fillRect(&ctx, mkRect(x - p, y + p, p, p), dc)
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
		// placement preview: a see-through copy of the held block where it would go, outlined green
		// when it can be placed there and red when it cannot (out of reach, occupied, unsupported)
		if g.aimValid && !g.dead && g.inVehicle == nil, let it = g.heldItem, case .block(let t) = it, t != .doorClosed, t != .doorOpen {
			let tx: Int = Int(floor(g.aimX))
			let ty: Int = Int(floor(g.aimY))
			let ok: Bool = g.canPlaceAt(tx, ty, t.placedForm)
			var c: GraphicsContext = ctx
			c.opacity = ok ? 0.5 : 0.28
			c.draw(art.icon(it), in: v.rect(Double(tx), Double(ty), 1, 1))
			strokeRect(&ctx, v.rect(Double(tx), Double(ty), 1, 1), ok ? Color(hex: 0x70E080, alpha: 0.9) : Color(hex: 0xFF5050, alpha: 0.75), 2)
		} else if g.aimValid && !g.dead && aiming && !(g.heldItem?.isWeapon ?? false) {
			// (a weapon shows the foe it is going for instead: see drawTargetMarker)
			let tx: Double = floor(g.aimX)
			let ty: Double = floor(g.aimY)
			let ok: Bool = g.inReach(g.aimX, g.aimY)
			let col: Color = ok ? Color.white.opacity(0.8) : Color(hex: 0xFF5050, alpha: 0.6)
			strokeRect(&ctx, v.rect(tx, ty, 1, 1), col, 2)
		}
		drawTargetMarker(&ctx, g, v)
		drawStickAim(&ctx, g, v)
		let full: CGRect = mkRect(0, 0, W, H)
		let headY: Double = g.pb.y - g.pb.h * 0.9
		let headT: Tile = g.world.tile(Int(floor(g.pb.x)), Int(floor(headY)))
		if headT == .water { fillRect(&ctx, full, Color(hex: 0x1A4AA0, alpha: 0.28)) }
		// damage and danger read as a soft edge vignette instead of tinting the whole screen
		if g.pb.inLava { edgeVignette(&ctx, W, H, 0xFF5010, 0.55) }
		if g.hurtT > 0 { edgeVignette(&ctx, W, H, 0xC01818, min(0.6, g.hurtT * 0.9)) }
		if !g.dead && g.hp < g.maxHP * 0.25 {
			// low health: a slow, faint pulse (well under any flashing threshold)
			let pulse: Double = 0.5 + 0.5 * sin(g.clock * 2.4)
			edgeVignette(&ctx, W, H, 0x900E0E, 0.18 + 0.14 * pulse)
		}
		// portal crossing: a gentle fade to deep teal (no bright flash)
		if g.fadeT > 0 { fillRect(&ctx, full, Color(hex: 0x0A2A30, alpha: min(1.0, g.fadeT))) }
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
		if g.showAI {
			for m in g.mobs where m.def.hostile && m.hp > 0 && v.visible(m.b.x, m.b.y, 4) {
				let dist: Double = abs(g.pb.x - m.b.x)
				var st: String = m.ai.name
				if m.st == 3 || m.st == 5 { st = "attack" } else if m.st == 4 || m.st == 6 { st = "recover" }
				if !m.kind.thinks { st = m.angry ? "angry" : "wild" }
				let reach: (Double, Double, Bool) = g.attackReach(m)
				let line1: String = joinText(st, String(format: "  %.1fm", dist), m.sees ? "  sees" : "  blind", m.cd > 0 ? String(format: "  cd %.1f", m.cd) : "")
				let line2: String = joinText(dist <= reach.0 ? "in range" : "out of range", m.why == .none ? "" : joinText(" | ", m.why.name))
				let x: Double = v.sx(m.b.x)
				let y: Double = v.sy(m.b.top) - 30.0
				let col: Color = m.ai == .chase ? Color(hex: 0xFF7060) : (m.ai == .search ? Color(hex: 0xFFD060) : Color(hex: 0xC0C0C0))
				fillRect(&ctx, mkRect(x - 78.0, y - 9.0, 156.0, 26.0), Color.black.opacity(0.55))
				drawLabel(&ctx, line1, x, y - 1.0, 10, col)
				drawLabel(&ctx, line2, x, y + 10.0, 9, Color.white)
				if m.ai == .search || m.ai == .back {
					strokeLine(&ctx, x, v.sy(m.b.cy), v.sx(m.aimX), v.sy(m.b.cy), Color(hex: 0xFFD060, alpha: 0.5), 1)
				}
			}
		}
	}
}

// ===== u07_mods =====

// MARK: - Mod Creator: shared pieces

/// The Mod Creator's working copy of one mod. Every edit marks it changed; it is written to disk
/// when you leave the editor, press SAVE, or test it.
final class ModSession: ObservableObject, @unchecked Sendable {
	@Published var mod: ModPack
	@Published var dirty: Bool = false
	@Published var report: ModReport = ModReport()
	/// bumped on every edit (previews key their caches on it)
	@Published var rev: Int = 0
	/// a picker shown over the whole editor, above the page that scrolls (see `modCover`)
	@Published var cover: AnyView? = nil

	init(_ p: ModPack) {
		mod = p
		recheck()
	}

	func touch() {
		dirty = true
		rev &+= 1
	}

	@discardableResult
	func save() -> Bool {
		let ok: Bool = ModStore.save(mod)
		if ok {
			if let p = ModStore.pack(mod.id) { mod = p }
			dirty = false
		}
		recheck()
		return ok
	}

	func recheck() {
		var p: ModPack = mod
		report = ModValidator.check(&p, known: ModCatalog.installed().keys)
	}

	/// A binding to one field of one piece of content (looked up by id each time, so lists can change)
	func bind<C: Identifiable, T>(_ list: WritableKeyPath<ModPack, [C]>, _ id: String, _ kp: WritableKeyPath<C, T>, _ fallback: T) -> Binding<T> where C.ID == String {
		return Binding<T>(get: {
			guard let i = self.mod[keyPath: list].firstIndex(where: { $0.id == id }) else { return fallback }
			return self.mod[keyPath: list][i][keyPath: kp]
		}, set: { v in
			guard let i = self.mod[keyPath: list].firstIndex(where: { $0.id == id }) else { return }
			self.mod[keyPath: list][i][keyPath: kp] = v
			self.touch()
		})
	}

	/// A binding to a field of the mod itself
	func modBind<T>(_ kp: WritableKeyPath<ModPack, T>) -> Binding<T> {
		return Binding<T>(get: { self.mod[keyPath: kp] }, set: { v in
			self.mod[keyPath: kp] = v
			self.touch()
		})
	}

	var catalog: ModCatalog {
		var ps: [ModPack] = [mod]
		for e in ModStore.entries() where e.id != mod.id { if let p = e.pack { ps.append(p) } }
		return ModCatalog.build(ps)
	}
}

/// Colours and sizes shared by the Mod Creator screens
enum ModUI {
	static var panel: Color { return Color(ui: 0x2C2C30) }
	static var card: Color { return Color(ui: 0x3A3A40) }
	static var accent: Color { return Color(ui: 0x4E8A3E) }
	static var blue: Color { return Color(ui: 0x3E6FAA) }
	static var red: Color { return Color(ui: 0xA03030) }
	static var gold: Color { return Color(ui: 0xFFE066) }
	static let dim: Color = Color.white.opacity(0.7)
	static let rarityColors: [UInt32] = [0xE8E8E8, 0x6AD86A, 0x5AA8FF, 0xC070FF, 0xFFB030]
	static let rarityNames: [String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
}

/// A titled block of controls
struct ModSection<C: View>: View {
	let title: String
	var help: String = ""
	@ViewBuilder var content: () -> C
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(verbatim: title).font(.pixel(15)).foregroundColor(ModUI.gold)
			if !help.isEmpty {
				Text(verbatim: help).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			content()
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(PixelBox(color: ModUI.card).opacity(0.95))
	}
}

/// A number with a big slider: its name, its value, and the range it may take
struct StatSlider: View {
	let label: String
	@Binding var value: Double
	let range: ClosedRange<Double>
	var step: Double = 0
	var format: String = "%.1f"
	var unit: String = ""
	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(verbatim: label).font(.pixel(13, .bold)).foregroundColor(Color.white)
				Spacer()
				Text(verbatim: String(format: format, value) + unit).font(.pixel(13)).foregroundColor(ModUI.gold)
			}
			Slider(value: clamped, in: range, step: step)
				.frame(minHeight: 34)
		}
	}

	var clamped: Binding<Double> {
		let r: ClosedRange<Double> = range
		let b: Binding<Double> = $value
		return Binding<Double>(get: { clampD(b.wrappedValue, r.lowerBound, r.upperBound) }, set: { b.wrappedValue = $0 })
	}
}

/// A whole number on a slider
struct IntSlider: View {
	let label: String
	@Binding var value: Int
	let range: ClosedRange<Int>
	var unit: String = ""
	var body: some View {
		StatSlider(label: label, value: asDouble, range: Double(range.lowerBound)...Double(range.upperBound), step: 1, format: "%.0f", unit: unit)
	}

	var asDouble: Binding<Double> {
		let b: Binding<Int> = $value
		return Binding<Double>(get: { Double(b.wrappedValue) }, set: { b.wrappedValue = Int($0.rounded()) })
	}
}

// MARK: - Mod Creator: shared pieces (continued; the session and the first pieces are at the end of part 3)

/// A row of large choices (one is picked)
struct ChoiceRow: View {
	let options: [String]
	@Binding var selected: Int
	var columns: Int = 3
	var body: some View {
		let cols: [GridItem] = [GridItem](repeating: GridItem(.flexible(), spacing: 6), count: max(1, min(columns, options.count)))
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(0..<options.count, id: \.self) { i in
				chip(i)
			}
		}
	}

	func chip(_ i: Int) -> some View {
		let on: Bool = selected == i
		let col: Color = on ? ModUI.accent : Color(ui: 0x555555)
		return Button {
			selected = i
		} label: {
			Text(verbatim: options[i])
				.font(.pixel(12))
				.foregroundColor(Color.white)
				.lineLimit(2)
				.minimumScaleFactor(0.7)
				.frame(maxWidth: .infinity, minHeight: 40)
				.background(PixelBox(color: col))
		}
		.buttonStyle(.plain)
	}
}

/// Rows of equal-width cells, `per` to a row: a plain stand-in for a lazy grid (the dimension editor
/// crashed on the iPad with lazy grids on its pages)
struct PlainGrid<Cell: View>: View {
	let count: Int
	let per: Int
	var spacing: CGFloat = 6
	let cell: (Int) -> Cell

	var body: some View {
		let k: Int = max(1, per)
		let rows: Int = (count + k - 1) / k
		return VStack(spacing: spacing) {
			ForEach(0..<rows, id: \.self) { (r: Int) in self.row(r, k) }
		}
	}

	func row(_ r: Int, _ k: Int) -> some View {
		let start: Int = r * k
		let end: Int = min(count, start + k)
		let blanks: Int = max(0, k - (end - start))
		return HStack(spacing: spacing) {
			ForEach(start..<end, id: \.self) { (i: Int) in self.cell(i) }
			ForEach(0..<blanks, id: \.self) { (_: Int) in Color.clear.frame(maxWidth: .infinity, minHeight: 1) }
		}
	}
}

/// The same choices as ChoiceRow, laid out in plain rows (no lazy grid)
struct ChoiceRows: View {
	let options: [String]
	@Binding var selected: Int
	var columns: Int = 3

	var body: some View {
		let per: Int = max(1, min(columns, options.count))
		return PlainGrid(count: options.count, per: per) { (i: Int) in self.chip(i) }
	}

	func chip(_ i: Int) -> some View {
		let on: Bool = selected == i
		let col: Color = on ? ModUI.accent : Color(ui: 0x555555)
		return Button {
			selected = i
		} label: {
			Text(verbatim: options[i])
				.font(.pixel(12))
				.foregroundColor(Color.white)
				.lineLimit(2)
				.minimumScaleFactor(0.7)
				.frame(maxWidth: .infinity, minHeight: 40)
				.background(PixelBox(color: col))
		}
		.buttonStyle(.plain)
	}
}

/// An on/off switch with a line of explanation
struct ModToggle: View {
	let label: String
	var help: String = ""
	@Binding var isOn: Bool
	var body: some View {
		Button {
			isOn.toggle()
		} label: {
			HStack(spacing: 10) {
				Text(verbatim: isOn ? "ON" : "OFF")
					.font(.pixel(12))
					.foregroundColor(Color.white)
					.frame(width: 50, height: 32)
					.background(PixelBox(color: isOn ? ModUI.accent : Color(ui: 0x555555)))
				VStack(alignment: .leading, spacing: 1) {
					Text(verbatim: label).font(.pixel(13, .bold)).foregroundColor(Color.white)
					if !help.isEmpty { Text(verbatim: help).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim) }
				}
				Spacer(minLength: 0)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}

/// A labelled text box
struct ModTextField: View {
	let label: String
	@Binding var text: String
	var placeholder: String = ""
	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(verbatim: label).font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			TextField(placeholder, text: $text)
				.font(.pixel(15, .bold))
				.foregroundColor(Color.white)
				.padding(10)
				.background(Color.black.opacity(0.6))
		}
	}
}

/// "Are you sure?" over the screen
struct ModConfirm: View {
	let title: String
	let text: String
	let yes: String
	let yesAction: () -> Void
	let noAction: () -> Void
	var body: some View {
		ZStack {
			Color.black.opacity(0.6).ignoresSafeArea()
			VStack(spacing: 12) {
				Text(verbatim: title).font(.pixel(18)).foregroundColor(Color.white)
				Text(verbatim: text).font(.pixel(12, .semibold)).foregroundColor(ModUI.dim).multilineTextAlignment(.center)
				HStack(spacing: 10) {
					PixelButton(title: "CANCEL") { noAction() }
					PixelButton(title: yes, color: ModUI.red) { yesAction() }
				}
			}
			.padding(18)
			.frame(maxWidth: 420)
			.background(PixelBox(color: ModUI.panel))
		}
	}
}

/// Picture of a mod pixel grid, drawn crisp at any size
func modImage(_ p: ModPixels) -> Image {
	return pixImage(p.buf())
}

func shortDate(_ t: Double) -> String {
	if t <= 0 { return "never" }
	let f = DateFormatter()
	f.dateStyle = .medium
	f.timeStyle = .short
	return f.string(from: Date(timeIntervalSince1970: t))
}

// MARK: - Mod Creator: pickers over the whole screen

extension View {
	/// Shows `cover` (a picker) over the whole Mod Creator screen while `key` is not nil. It sits above
	/// the page that scrolls, so it is always on screen with its CANCEL in reach, however far the page
	/// was scrolled; a new key shows it again with the new state.
	func modCover<K: Equatable, C: View>(_ s: ModSession, _ key: K?, @ViewBuilder _ cover: @escaping () -> C) -> some View {
		return self.modifier(ModCoverLink<K>(session: s, key: key, make: { AnyView(cover()) }))
	}
}

/// Keeps the session's cover in step with one editor's picker
struct ModCoverLink<K: Equatable>: ViewModifier {
	let session: ModSession
	let key: K?
	let make: () -> AnyView

	func body(content: Content) -> some View {
		content
			.modifier(ModChangeWatch(value: key, changed: { (k: K?) in self.show(k) }))
			.onDisappear { if self.key != nil { self.session.cover = nil } }
	}

	func show(_ k: K?) {
		session.cover = k == nil ? nil : make()
	}
}

/// Runs `changed` when `value` changes (the iOS 17 form of onChange when there is one)
struct ModChangeWatch<V: Equatable>: ViewModifier {
	let value: V
	let changed: (V) -> Void

	func body(content: Content) -> some View {
		if #available(iOS 17.0, macOS 14.0, *) {
			content.onChange(of: value) { _, v in changed(v) }
		} else {
			content.onChange(of: value) { v in changed(v) }
		}
	}
}

/// Shown before loading a world whose mods are not all installed
struct ModMissingView: View {
	let check: ModLoadCheck
	var load: () -> Void
	var cancel: () -> Void
	var body: some View {
		ZStack {
			Color.black.opacity(0.75).ignoresSafeArea()
			VStack(alignment: .leading, spacing: 10) {
				Text("MODS MISSING").font(.pixel(22)).foregroundColor(Color(ui: 0xFF9060))
				Text(verbatim: "\u{201C}" + check.save.meta.name + "\u{201D} was made with mods that are not on this iPad:").font(.pixel(13, .semibold)).foregroundColor(Color.white)
				if check.missing.count > 6 {
					ScrollView { missingList }.frame(height: 200)
				} else {
					missingList
				}
				Text("You can load it anyway: their blocks show as magenta placeholders that cannot be broken, and their items wait in your bag. Nothing is deleted, so it all comes back when the mods are installed again.")
					.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				HStack(spacing: 10) {
					PixelButton(title: "BACK") { cancel() }
					PixelButton(title: "LOAD ANYWAY", color: Color(ui: 0x8A5A2E)) { load() }
				}
			}
			.padding(18)
			.frame(maxWidth: 560)
			.background(PixelBox(color: ModUI.panel))
		}
	}

	var missingList: some View {
		VStack(alignment: .leading, spacing: 4) {
			ForEach(check.missing) { d in
				Text(verbatim: joinText("• ", d.name, " v", d.version, d.author.isEmpty ? "" : " by " + d.author)).font(.pixel(13)).foregroundColor(ModUI.gold)
			}
		}
	}
}

// MARK: - Mod Creator: the list of mods

enum ModScreen: Equatable {
	case list
	case edit(String)
	case info(String)
	case packages
	case sprites
}

struct ModCreatorView: View {
	/// starts a test world for a mod (see ModTest)
	var test: (ModPack) -> Void
	var done: () -> Void
	@State var screen: ModScreen = .list
	@State var entries: [ModEntry] = []
	@State var confirmDelete: String? = nil
	@State var note: String = ""
	@State var session: ModSession? = nil
	/// the folder shown ("": every mod)
	@State var folder: String = ""

	var body: some View {
		ZStack {
			Color(ui: 0x1C1C22).ignoresSafeArea()
			content
			if let id = confirmDelete {
				ModConfirm(title: "DELETE MOD?", text: "This removes the mod from this iPad. Worlds that use it will warn that it is missing.", yes: "DELETE",
						   yesAction: { deleteMod(id) }, noAction: { confirmDelete = nil })
			}
		}
		.onAppear { refresh() }
	}

	@ViewBuilder
	var content: some View {
		switch screen {
		case .list: listScreen
		case .edit:
			if let s = session {
				ModEditorView(session: s, test: { p in test(p) }, close: { closeEditor() })
			} else {
				listScreen
			}
		case .info(let id): ModInfoScreen(id: id, back: { screen = .list })
		case .packages: ModPackagesScreen(back: { refresh(); screen = .list })
		case .sprites: SpriteLibraryScreen(back: { screen = .list })
		}
	}

	var listScreen: some View {
		VStack(spacing: 10) {
			HStack(spacing: 8) {
				SmallButton(title: "< MENU") { done() }
				Spacer()
				Text("MOD CREATOR").font(.pixel(24)).foregroundColor(ModUI.gold)
				Spacer()
				SmallButton(title: "SPRITE LIBRARY", color: ModUI.blue) { screen = .sprites }
				SmallButton(title: "IMPORT / SHARE", color: ModUI.blue) { screen = .packages }
			}
			Text("Make your own blocks, items, weapons, creatures, bosses, ores, recipes and structures. Mods switched on are used by new worlds; every world remembers the mods it was made with.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim).multilineTextAlignment(.center)
			if !note.isEmpty { Text(verbatim: note).font(.pixel(12)).foregroundColor(ModUI.gold) }
			ScrollView {
				VStack(spacing: 8) {
					PixelButton(title: "+ CREATE NEW MOD", color: ModUI.accent) { createMod() }
					folderChips
					ForEach(entries.filter { folder.isEmpty || ($0.pack?.folder ?? "") == folder }) { e in
						ModCard(entry: e, actions: cardActions(e))
					}
					if entries.isEmpty {
						Text("No mods yet. Create one to start!").font(.pixel(13)).foregroundColor(ModUI.dim).padding(.top, 20)
					}
				}
				.padding(.bottom, 20)
			}
		}
		.padding(14)
		.frame(maxWidth: 900)
	}

	func cardActions(_ e: ModEntry) -> ModCardActions {
		return ModCardActions(edit: { openEditor(e.id) }, test: { testMod(e.id) }, copy: { duplicateMod(e.id) },
							  delete: { confirmDelete = e.id }, info: { screen = .info(e.id) },
							  toggle: { toggleMod(e.id) }, up: { moveMod(e.id, -1) }, down: { moveMod(e.id, 1) })
	}

	func refresh() {
		entries = ModStore.entries()
	}

	func createMod() {
		var p = ModPack()
		p.id = newModID()
		p.name = "My Mod " + String(entries.count + 1)
		if ModStore.save(p) {
			refresh()
			openEditor(p.id)
		} else {
			note = "The mod could not be saved."
		}
	}

	func openEditor(_ id: String) {
		guard let p = ModStore.pack(id) else {
			note = "That mod could not be opened."
			return
		}
		session = ModSession(p)
		screen = .edit(id)
	}

	func closeEditor() {
		if let s = session, s.dirty { _ = s.save() }
		session = nil
		refresh()
		screen = .list
	}

	func testMod(_ id: String) {
		guard let p = ModStore.pack(id) else { return }
		test(p)
	}

	func duplicateMod(_ id: String) {
		guard let p = ModStore.pack(id) else { return }
		if let c = ModStore.duplicate(p) { note = "Made " + c.name + "." } else { note = "The copy could not be saved." }
		refresh()
	}

	func deleteMod(_ id: String) {
		ModStore.delete(id)
		confirmDelete = nil
		note = "Mod deleted."
		refresh()
	}

	func toggleMod(_ id: String) {
		let on: Bool = !ModStore.isEnabled(id)
		if on && ModStore.enabledPacks().count >= ModLimits.maxMods {
			note = "At most " + String(ModLimits.maxMods) + " mods can be on at once."
			return
		}
		ModStore.setEnabled(id, on)
		refresh()
	}

	func moveMod(_ id: String, _ d: Int) {
		ModStore.move(id, by: d)
		refresh()
	}
}

struct ModCardActions {
	var edit: () -> Void
	var test: () -> Void
	var copy: () -> Void
	var delete: () -> Void
	var info: () -> Void
	var toggle: () -> Void
	var up: () -> Void
	var down: () -> Void
}

/// One mod in the list: what it is, whether it is on, and what you can do with it
struct ModCard: View {
	let entry: ModEntry
	let actions: ModCardActions
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let p = entry.pack {
				header(p)
				Text(verbatim: p.summary).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				buttons
			} else {
				Text(verbatim: "Damaged mod: " + entry.id).font(.pixel(14)).foregroundColor(Color(ui: 0xFF8060))
				Text(verbatim: entry.error).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				SmallButton(title: "DELETE", color: ModUI.red) { actions.delete() }
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(PixelBox(color: entry.enabled ? Color(ui: 0x34503A) : ModUI.card))
	}

	func header(_ p: ModPack) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Button { actions.toggle() } label: {
				Text(verbatim: entry.enabled ? "ON" : "OFF")
					.font(.pixel(13))
					.foregroundColor(Color.white)
					.frame(width: 58, height: 44)
					.background(PixelBox(color: entry.enabled ? ModUI.accent : Color(ui: 0x555555)))
			}
			.buttonStyle(.plain)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: p.name).font(.pixel(17)).foregroundColor(Color.white)
				Text(verbatim: byline(p)).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 4)
			VStack(spacing: 4) {
				SmallButton(title: "▲") { actions.up() }
				SmallButton(title: "▼") { actions.down() }
			}
		}
	}

	func byline(_ p: ModPack) -> String {
		let who: String = p.author.isEmpty ? "unknown author" : p.author
		return joinText("v", p.version, " · by ", who, " · edited ", shortDate(p.edited))
	}

	var buttons: some View {
		HStack(spacing: 6) {
			SmallButton(title: "EDIT", color: ModUI.blue) { actions.edit() }
			SmallButton(title: "TEST", color: ModUI.accent) { actions.test() }
			SmallButton(title: "INFO") { actions.info() }
			SmallButton(title: "COPY") { actions.copy() }
			Spacer(minLength: 0)
			SmallButton(title: "DELETE", color: ModUI.red) { actions.delete() }
		}
	}
}

/// Everything about one mod: details, content, and the problems the checks found
struct ModInfoScreen: View {
	let id: String
	var back: () -> Void
	var body: some View {
		let e: ModEntry = ModStore.read(id)
		return VStack(spacing: 10) {
			HStack {
				SmallButton(title: "< BACK") { back() }
				Spacer()
				Text("MOD INFO").font(.pixel(20)).foregroundColor(ModUI.gold)
				Spacer()
			}
			ScrollView {
				if let p = e.pack {
					ModInfoBody(pack: p)
				} else {
					Text(verbatim: e.error).font(.pixel(13)).foregroundColor(Color(ui: 0xFF8060))
				}
			}
		}
		.padding(14)
		.frame(maxWidth: 900)
	}
}

struct ModInfoBody: View {
	let pack: ModPack
	var body: some View {
		var copy: ModPack = pack
		let rep: ModReport = ModValidator.check(&copy, known: ModCatalog.installed().keys)
		return VStack(alignment: .leading, spacing: 10) {
			ModSection(title: pack.name) {
				infoLine("Author", pack.author.isEmpty ? "unknown" : pack.author)
				infoLine("Version", pack.version)
				infoLine("Created", shortDate(pack.created))
				infoLine("Last edited", shortDate(pack.edited))
				infoLine("Sandbox limits", pack.sandbox ? "on" : "off")
				if !pack.desc.isEmpty { Text(verbatim: pack.desc).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			}
			ModSection(title: "CONTENT") {
				contentList
			}
			ModIssueList(report: rep)
		}
	}

	func infoLine(_ a: String, _ b: String) -> some View {
		HStack {
			Text(verbatim: a).font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			Spacer()
			Text(verbatim: b).font(.pixel(12)).foregroundColor(Color.white)
		}
	}

	var contentList: some View {
		VStack(alignment: .leading, spacing: 3) {
			ForEach(pack.blocks) { b in Text(verbatim: "Block: " + b.name).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			ForEach(pack.items) { i in Text(verbatim: i.kind.name + ": " + i.name).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			ForEach(pack.mobs) { m in Text(verbatim: m.category.name + ": " + m.name).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			ForEach(pack.projectiles) { s in Text(verbatim: "Shot: " + s.name).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			ForEach(pack.ores) { o in Text(verbatim: "Ore: " + o.name).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			ForEach(pack.structures) { s in Text(verbatim: "Structure: " + s.name).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			ForEach(pack.loot) { l in Text(verbatim: "Loot table: " + l.name).font(.pixel(12, .semibold)).foregroundColor(Color.white) }
			Text(verbatim: String(pack.recipes.count) + " recipes").font(.pixel(12, .semibold)).foregroundColor(Color.white)
		}
	}
}

/// The checks' findings, worst first
struct ModIssueList: View {
	let report: ModReport
	var body: some View {
		let list: [ModIssue] = report.issues.sorted { $0.level > $1.level }
		return ModSection(title: report.issues.isEmpty ? "NO PROBLEMS FOUND" : "PROBLEMS (" + String(report.errors) + " errors, " + String(report.warnings) + " warnings)",
						  help: report.issues.isEmpty ? "Everything in this mod checks out." : "Errors switch that content off until it is fixed; warnings were fixed for you.") {
			ForEach(list) { i in
				HStack(alignment: .top, spacing: 8) {
					Text(verbatim: i.level >= 2 ? "✕" : (i.level == 1 ? "!" : "i"))
						.font(.pixel(14))
						.foregroundColor(Color(ui: i.level >= 2 ? 0xFF6060 : (i.level == 1 ? 0xFFC040 : 0x90C0FF)))
						.frame(width: 18)
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: i.place).font(.pixel(12, .bold)).foregroundColor(Color.white)
						Text(verbatim: i.text).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
					}
				}
			}
		}
	}
}

/// Exporting a mod as a package file, and installing packages found in the packages folder
struct ModPackagesScreen: View {
	var back: () -> Void
	@State var note: String = ""
	@State var files: [URL] = []
	@State var mods: [ModEntry] = []
	var body: some View {
		VStack(spacing: 10) {
			HStack {
				SmallButton(title: "< BACK") { back() }
				Spacer()
				Text("SHARE MODS").font(.pixel(20)).foregroundColor(ModUI.gold)
				Spacer()
			}
			Text("Exported mods are saved as .prmod files in the PixelRealmMods/Packages folder of this app's documents. Put a .prmod file there to install it. Every package is checked before it is installed.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim).multilineTextAlignment(.center)
			if !note.isEmpty { Text(verbatim: note).font(.pixel(12)).foregroundColor(ModUI.gold) }
			ScrollView {
				VStack(spacing: 8) {
					ModSection(title: "EXPORT A MOD") {
						ForEach(mods) { e in exportRow(e) }
					}
					ModSection(title: "INSTALL A PACKAGE", help: files.isEmpty ? "No package files found." : "") {
						ForEach(files, id: \.self) { u in importRow(u) }
					}
				}
			}
		}
		.padding(14)
		.frame(maxWidth: 900)
		.onAppear { reload() }
	}

	func reload() {
		files = ModStore.packageFiles()
		mods = ModStore.entries().filter { $0.pack != nil }
	}

	func exportRow(_ e: ModEntry) -> some View {
		HStack {
			Text(verbatim: e.pack?.name ?? e.id).font(.pixel(13)).foregroundColor(Color.white)
			Spacer()
			SmallButton(title: "EXPORT", color: ModUI.blue) {
				if let p = e.pack, let u = ModStore.exportPackage(p) {
					note = "Saved " + u.lastPathComponent
				} else {
					note = "Export failed."
				}
				reload()
			}
		}
	}

	func importRow(_ u: URL) -> some View {
		HStack {
			Text(verbatim: u.lastPathComponent).font(.pixel(13)).foregroundColor(Color.white)
			Spacer()
			SmallButton(title: "INSTALL", color: ModUI.accent) {
				if let d = try? Data(contentsOf: u) {
					let r: (ModPack?, String) = ModStore.importPackage(d)
					note = r.1
				} else {
					note = "That file could not be read."
				}
				reload()
			}
		}
	}
}

// MARK: - Mod Creator: editing a mod

enum ModTab: Int, CaseIterable {
	case info, blocks, items, mobs, shots, recipes, loot, ores, structures, infusions, suits, vehicles, dims, world, theme, logic, game, reference, check
	var name: String {
		switch self {
		case .suits: return "SUITS"
		case .vehicles: return "VEHICLES"
		case .world: return "WORLD & RULES"
		case .theme: return "LOOK"
		case .logic: return "LOGIC STUDIO"

		case .dims: return "DIMENSIONS"

		case .infusions: return "INFUSIONS"

		case .reference: return "BLOCK REFERENCE"

		case .game: return "GAME CONTENT"
		case .info: return "INFO"
		case .blocks: return "BLOCKS"
		case .items: return "ITEMS & WEAPONS"
		case .mobs: return "CREATURES"
		case .shots: return "SHOTS"
		case .recipes: return "RECIPES"
		case .loot: return "LOOT"
		case .ores: return "ORES"
		case .structures: return "STRUCTURES"
		case .check: return "CHECK"
		}
	}
}

/// What the editor is showing: a tab's list, or one piece of content
enum ModEditTarget: Equatable {
	case none
	case block(String)
	case item(String)
	case mob(String)
	case shot(String)
	case recipe(String)
	case loot(String)
	case ore(String)
	case structure(String)
	case override(String)
	case infusion(String)
	case dimension(String)
	case script(String)
	case suitMat(String)
	case suitPart(String)
	case suitDesign(String)
	case vehicle(String)
}

struct ModEditorView: View {
	@ObservedObject var session: ModSession
	var test: (ModPack) -> Void
	var close: () -> Void
	@State var tab: ModTab = .info
	@State var target: ModEditTarget = .none
	@State var confirm: (String, () -> Void)? = nil
	/// picking a game block, item or creature to start a new one from
	@State var gamePick: ModOverrideKind? = nil

	var body: some View {
		ZStack {
			VStack(spacing: 8) {
				topBar
				if target == .none { tabBar }
				ScrollView {
					VStack(spacing: 10) {
						page
					}
					.padding(.bottom, 30)
				}
			}
			.padding(12)
			.frame(maxWidth: 1000)
			if let cv = session.cover { cv }
			if let c = confirm {
				ModConfirm(title: "DELETE?", text: c.0, yes: "DELETE", yesAction: { c.1(); confirm = nil }, noAction: { confirm = nil })
			}
		}
	}

	var topBar: some View {
		HStack(spacing: 8) {
			if target == .none {
				SmallButton(title: "< MODS") { close() }
			} else {
				SmallButton(title: "< " + tab.name) { target = .none; session.recheck() }
			}
			Spacer()
			Text(verbatim: session.mod.name).font(.pixel(18)).foregroundColor(Color.white).lineLimit(1)
			Spacer()
			Text(verbatim: session.dirty ? "unsaved" : "saved").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			SmallButton(title: "SAVE", color: ModUI.blue) { _ = session.save() }
			SmallButton(title: "TEST", color: ModUI.accent) {
				_ = session.save()
				test(session.mod)
			}
		}
	}

	var tabBar: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 6) {
				ForEach(ModTab.allCases, id: \.self) { t in
					tabButton(t)
				}
			}
		}
	}

	func tabButton(_ t: ModTab) -> some View {
		let on: Bool = tab == t
		var label: String = t.name
		if t == .check && session.report.errors > 0 { label += " (" + String(session.report.errors) + ")" }
		return Button {
			tab = t
			target = .none
			if t == .check { session.recheck() }
		} label: {
			Text(verbatim: label)
				.font(.pixel(12))
				.foregroundColor(Color.white)
				.padding(.horizontal, 12)
				.frame(minHeight: 40)
				.background(PixelBox(color: on ? ModUI.accent : Color(ui: 0x4A4A50)))
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	var page: some View {
		switch target {
		case .none: tabPage
		case .block(let id): BlockEditorView(s: session, id: id)
		case .item(let id): ItemEditorView(s: session, id: id)
		case .mob(let id): MobEditorView(s: session, id: id)
		case .shot(let id): ShotEditorView(s: session, id: id)
		case .recipe(let id): RecipeEditorView(s: session, id: id)
		case .loot(let id): LootEditorView(s: session, id: id)
		case .ore(let id): OreEditorView(s: session, id: id)
		case .structure(let id): StructureEditorView(s: session, id: id)
		case .override(let id): OverrideEditorView(s: session, id: id)
		case .infusion(let id): InfusionEditorView(s: session, id: id, openRecipe: { rid in target = .recipe(rid) })
		case .dimension(let id): DimensionEditorView(s: session, id: id)
		case .script(let id): ScriptEditorView(s: session, id: id)
		case .suitMat(let id): SuitMatEditorView(s: session, id: id)
		case .suitPart(let id): SuitPartEditorView(s: session, id: id)
		case .suitDesign(let id): SuitDesignEditorView(s: session, id: id)
		case .vehicle(let id): VehicleEditorView(s: session, id: id)
		}
	}

	@ViewBuilder
	var tabPage: some View {
		switch tab {
		case .info: ModInfoEditor(s: session)
		case .blocks: blockList
		case .items: itemList
		case .mobs: mobList
		case .shots: shotList
		case .recipes: recipeList
		case .loot: lootList
		case .ores: oreList
		case .structures: structureList
		case .game: GameContentList(s: session, open: { id in target = .override(id) })
		case .reference: HardnessReferenceView(s: session)
		case .infusions: InfusionListView(s: session, open: { id in target = .infusion(id) })
		case .suits: SuitListView(s: session, openMat: { (id: String) in target = .suitMat(id) }, openPart: { (id: String) in target = .suitPart(id) }, openDesign: { (id: String) in target = .suitDesign(id) })
		case .vehicles: VehicleListView(s: session, open: { (id: String) in target = .vehicle(id) })
		case .world: WorldRulesView(s: session)
		case .theme: ThemeEditorView(s: session)
		case .dims: DimensionListView(s: session, open: { id in target = .dimension(id) })
		case .logic: LogicStudioView(s: session, open: { id in target = .script(id) })
		case .check: ModIssueList(report: session.report)
		}
	}

	// MARK: lists

	func addButton(_ title: String, _ action: @escaping () -> Void) -> some View {
		PixelButton(title: title, color: ModUI.accent, action: action)
	}

	var blockList: some View {
		VStack(spacing: 8) {
			addButton("+ NEW BLOCK") {
				var b = ModBlock()
				b.id = session.mod.freshID("b")
				b.name = "Block " + String(session.mod.blocks.count + 1)
				b.art = ModPixels(buf: tileBuf(.stone))
				session.mod.blocks.append(b)
				session.touch()
				target = .block(b.id)
			}
			fromGame(.block)
			ForEach(session.mod.blocks) { b in
				ModRow(image: modImage(b.art), title: b.name, sub: b.category.name + " · hardness " + String(format: "%.1f", b.hardness),
					   open: { target = .block(b.id) }, copy: { copyBlock(b) },
					   delete: { ask("Delete the block " + b.name + "?") { session.mod.blocks.removeAll { $0.id == b.id }; session.touch() } },
					   off: session.mod.off.contains(b.id), toggle: { toggleOff(b.id) })
			}
		}
	}

	var itemList: some View {
		VStack(spacing: 8) {
			ItemTemplateRow { kind in addItem(kind) }
			fromGame(.item)
			ForEach(session.mod.items) { it in
				ModRow(image: ModPreview.itemIcon(it, session.catalog), title: it.name, sub: it.kind.name,
					   open: { target = .item(it.id) }, copy: { copyItem(it) },
					   delete: { ask("Delete " + it.name + "?") { session.mod.items.removeAll { $0.id == it.id }; session.touch() } },
					   off: session.mod.off.contains(it.id), toggle: { toggleOff(it.id) })
			}
		}
	}

	var mobList: some View {
		VStack(spacing: 8) {
			addButton("+ NEW CREATURE") {
				var m = ModMob()
				m.id = session.mod.freshID("c")
				m.name = "Creature " + String(session.mod.mobs.count + 1)
				m.behavior.chase = true
				m.behavior.attackPlayer = true
				session.mod.mobs.append(m)
				session.touch()
				target = .mob(m.id)
			}
			fromGame(.creature)
			ForEach(session.mod.mobs) { m in
				ModRow(image: ModPreview.mobImage(m), title: m.name, sub: m.category.name + " · " + String(format: "%.0f HP", m.hp),
					   open: { target = .mob(m.id) }, copy: { copyMob(m) },
					   delete: { ask("Delete " + m.name + "?") { session.mod.mobs.removeAll { $0.id == m.id }; session.touch() } },
					   off: session.mod.off.contains(m.id), toggle: { toggleOff(m.id) })
			}
		}
	}

	var shotList: some View {
		VStack(spacing: 8) {
			Text("Shots are what bows, guns, wands and creatures fire: how they look, fly and land.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			addButton("+ NEW SHOT") {
				var s = ModProjectile()
				s.id = session.mod.freshID("s")
				s.name = "Shot " + String(session.mod.projectiles.count + 1)
				session.mod.projectiles.append(s)
				session.touch()
				target = .shot(s.id)
			}
			ForEach(session.mod.projectiles) { s in
				ModRow(image: ModPreview.shotImage(s), title: s.name, sub: s.shape.name + (s.explode > 0 ? " · explodes" : ""),
					   open: { target = .shot(s.id) }, copy: nil,
					   delete: { ask("Delete the shot " + s.name + "?") { session.mod.projectiles.removeAll { $0.id == s.id }; session.touch() } })
			}
		}
	}

	var recipeList: some View {
		let cat: ModCatalog = session.catalog
		return VStack(spacing: 8) {
			addButton("+ NEW RECIPE") {
				var r = ModRecipe()
				r.id = session.mod.freshID("r")
				if let it = session.mod.items.first { r.out = .custom(session.mod.key(it.id)) }
				else if let b = session.mod.blocks.first { r.out = .custom(session.mod.key(b.id)) }
				r.cost = [ModCost(.block(.planks), 2)]
				session.mod.recipes.append(r)
				session.touch()
				target = .recipe(r.id)
			}
			ForEach(session.mod.recipes) { r in
				ModRow(image: ModPreview.icon(r.out, cat), title: ModPreview.name(r.out, cat) + (r.count > 1 ? " x" + String(r.count) : ""),
					   sub: recipeLine(r, cat), open: { target = .recipe(r.id) }, copy: nil,
					   delete: { ask("Delete this recipe?") { session.mod.recipes.removeAll { $0.id == r.id }; session.touch() } })
			}
		}
	}

	func recipeLine(_ r: ModRecipe, _ cat: ModCatalog) -> String {
		var parts: [String] = []
		for c in r.cost { parts.append(String(c.n) + " " + ModPreview.name(c.item, cat)) }
		return parts.joined(separator: " + ")
	}

	var lootList: some View {
		VStack(spacing: 8) {
			addButton("+ NEW LOOT TABLE") {
				var l = ModLootTable()
				l.id = session.mod.freshID("l")
				l.name = "Loot " + String(session.mod.loot.count + 1)
				l.entries = [ModLootEntry(.mat(.coal), 1, 3, 0)]
				session.mod.loot.append(l)
				session.touch()
				target = .loot(l.id)
			}
			ForEach(session.mod.loot) { l in
				ModRow(image: nil, title: l.name, sub: String(l.entries.count) + " entries · " + String(l.rolls) + " rolls",
					   open: { target = .loot(l.id) }, copy: nil,
					   delete: { ask("Delete the loot table " + l.name + "?") { session.mod.loot.removeAll { $0.id == l.id }; session.touch() } })
			}
		}
	}

	var oreList: some View {
		VStack(spacing: 8) {
			Text("An ore is one of this mod's blocks that forms in veins underground. Make the block first (BLOCKS), then add its ore here.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			addButton("+ NEW ORE") {
				var o = ModOre()
				o.id = session.mod.freshID("o")
				o.name = "Ore " + String(session.mod.ores.count + 1)
				o.block = session.mod.blocks.first(where: { $0.category == .terrain })?.id ?? (session.mod.blocks.first?.id ?? "")
				session.mod.ores.append(o)
				session.touch()
				target = .ore(o.id)
			}
			ForEach(session.mod.ores) { o in
				let blk: ModBlock? = session.mod.blocks.first { $0.id == o.block }
				ModRow(image: blk.map { modImage($0.art) }, title: o.name, sub: "rows " + String(o.minY) + "-" + String(o.maxY) + String(format: " · %.1f veins per chunk", o.veins),
					   open: { target = .ore(o.id) }, copy: nil,
					   delete: { ask("Delete the ore " + o.name + "?") { session.mod.ores.removeAll { $0.id == o.id }; session.touch() } })
			}
		}
	}

	var structureList: some View {
		VStack(spacing: 8) {
			Text("To make a structure: build it in a world (a test world is easiest), pause, choose CAPTURE STRUCTURE, tap two corners around it, and save it to this mod. Its settings are edited here.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(session.mod.structures) { st in
				ModRow(image: nil, title: st.name, sub: String(st.w) + " x " + String(st.h) + " · " + st.placement.name,
					   open: { target = .structure(st.id) }, copy: nil,
					   delete: { ask("Delete the structure " + st.name + "?") { session.mod.structures.removeAll { $0.id == st.id }; session.touch() } })
			}
			if session.mod.structures.isEmpty {
				Text("No structures captured yet.").font(.pixel(13)).foregroundColor(ModUI.dim)
			}
		}
	}

	// MARK: actions

	func ask(_ text: String, _ action: @escaping () -> Void) {
		confirm = (text, action)
	}

	func copyBlock(_ b: ModBlock) {
		var c: ModBlock = b
		c.id = session.mod.freshID("b")
		c.name = b.name + " copy"
		session.mod.blocks.append(c)
		session.touch()
	}

	func copyItem(_ it: ModItem) {
		var c: ModItem = it
		c.id = session.mod.freshID("i")
		c.name = it.name + " copy"
		session.mod.items.append(c)
		session.touch()
	}

	func copyMob(_ m: ModMob) {
		var c: ModMob = m
		c.id = session.mod.freshID("c")
		c.name = m.name + " copy"
		session.mod.mobs.append(c)
		session.touch()
	}

	func addItem(_ kind: ModItemKind) {
		var it: ModItem = ModItem.template(kind)
		it.id = session.mod.freshID("i")
		it.name = "New " + kind.name
		session.mod.items.append(it)
		session.touch()
		target = .item(it.id)
	}
}

/// One piece of content in a list
struct ModRow: View {
	let image: Image?
	let title: String
	let sub: String
	let open: () -> Void
	let copy: (() -> Void)?
	let delete: () -> Void
	/// switched off for now (left out of worlds, kept in the mod)
	var off: Bool = false
	var toggle: (() -> Void)? = nil
	var body: some View {
		HStack(spacing: 10) {
			Button { open() } label: {
				HStack(spacing: 10) {
					ZStack {
						Rectangle().fill(Color.black.opacity(0.4))
						if let img = image { img.resizable().interpolation(.none).frame(width: 38, height: 38) }
					}
					.frame(width: 46, height: 46)
					VStack(alignment: .leading, spacing: 2) {
						Text(verbatim: title).font(.pixel(14)).foregroundColor(Color.white).lineLimit(1)
						Text(verbatim: sub).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim).lineLimit(2)
					}
					Spacer(minLength: 0)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			if let t = toggle { SmallButton(title: off ? "OFF" : "ON", color: off ? Color(ui: 0x555555) : ModUI.accent) { t() } }
			if let c = copy { SmallButton(title: "COPY") { c() } }
			SmallButton(title: "EDIT", color: ModUI.blue) { open() }
			SmallButton(title: "✕", color: ModUI.red) { delete() }
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}
}

/// Buttons to start a new item from a sensible template of each kind
struct ItemTemplateRow: View {
	var add: (ModItemKind) -> Void
	var body: some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 6)]
		return VStack(alignment: .leading, spacing: 4) {
			Text("NEW ITEM:").font(.pixel(13)).foregroundColor(ModUI.gold)
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(ModItemKind.allCases, id: \.self) { k in
					SmallButton(title: "+ " + k.name, color: ModUI.accent) { add(k) }
				}
			}
		}
	}
}

extension ModItem {
	/// A ready-to-use starting point for each kind of item
	static func template(_ k: ModItemKind) -> ModItem {
		var it = ModItem()
		it.kind = k
		switch k {
		case .material:
			it.baseIcon = .mat(.diamond)
			it.tintAmt = 0.4
			it.tint = 0xFF60A0
		case .food:
			it.baseIcon = .food(.apple)
			it.hunger = 6
			it.effects = [ModEffect(.heal, 2, 0)]
		case .consumable:
			it.baseIcon = .gadget(.waterFlask)
			it.tint = 0xFF4060
			it.tintAmt = 0.5
			it.effects = [ModEffect(.heal, 8, 0), ModEffect(.speed, 30, 20)]
			it.stack = 20
		case .tool:
			it.baseIcon = .tool(.pickaxe, .iron)
			it.toolType = 0
			it.toolTier = 5
			it.toolSpeed = 6
			it.damage = 5
			it.stack = 1
		case .melee:
			it.baseIcon = .sword(.iron)
			it.damage = 9
			it.cooldown = 0.42
			it.reach = 3
			it.arc = 1.1
			it.stack = 1
		case .bow:
			it.baseIcon = .bow
			it.damage = 9
			it.cooldown = 0.6
			it.speed = 30
			it.gravity = 12
			it.ammo = .ammo(.arrow)
			it.stack = 1
			it.shot = ProjKind.arrow.rawValue
		case .gun:
			it.baseIcon = .gun(.pistol)
			it.damage = 10
			it.cooldown = 0.35
			it.speed = 36
			it.magazine = 6
			it.reload = 1.3
			it.ammo = .ammo(.bullet)
			it.stack = 1
			it.shot = ProjKind.bullet.rawValue
		case .thrown:
			it.baseIcon = .gadget(.bomb)
			it.damage = 8
			it.cooldown = 0.6
			it.speed = 20
			it.gravity = 18
			it.stack = 30
			it.shot = ProjKind.rock.rawValue
		case .magic:
			it.baseIcon = .gun(.stormRod)
			it.damage = 7
			it.cooldown = 0.5
			it.speed = 26
			it.stack = 1
			it.shot = ProjKind.fireball.rawValue
		case .armor:
			it.baseIcon = .armor(.chest, .iron)
			it.slot = 1
			it.defense = 3
			it.look = 4
			it.stack = 1
		case .ammo:
			it.baseIcon = .ammo(.arrow)
			it.stack = 99
		case .special:
			it.baseIcon = .block(.glowCrystal)
			it.light = 12
			it.stack = 1
		}
		return it
	}
}

/// The mod's name, author, version, description and sandbox switch
struct ModInfoEditor: View {
	@ObservedObject var s: ModSession
	var body: some View {
		VStack(spacing: 10) {
			ModSection(title: "ABOUT THIS MOD") {
				ModTextField(label: "Mod name", text: s.modBind(\.name), placeholder: "My Mod")
				ModTextField(label: "Author", text: s.modBind(\.author), placeholder: "Your name")
				ModTextField(label: "Version", text: s.modBind(\.version), placeholder: "1.0")
				ModTextField(label: "Description (optional)", text: s.modBind(\.desc), placeholder: "What does it add?")
			}
			ModSection(title: "LIMITS", help: "Normal limits keep numbers fair for survival. Sandbox mode allows much bigger numbers (giant bosses, huge damage) for creative play.") {
				ModToggle(label: "Sandbox mode (fewer limits)", help: "Health up to 20000, damage up to 500, faster creatures", isOn: s.modBind(\.sandbox))
			}
			ModSection(title: "CONTENT") {
				Text(verbatim: s.mod.summary).font(.pixel(13, .semibold)).foregroundColor(Color.white)
				Text(verbatim: joinText("Created ", shortDate(s.mod.created), " · edited ", shortDate(s.mod.edited))).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			ModOrganizeSection(s: s)
		}
	}
}

// MARK: - Mod Creator: previews, the pixel editor and the item picker

/// Pictures and names of content in the editor (no world needs to be running)
enum ModPreview {
	static func itemIconBuf(_ it: ModItem, _ cat: ModCatalog) -> PixelBuf {
		if !it.icon.isBlank {
			var b: PixelBuf = padBuf(it.icon.buf())
			if it.icon.outlined(true) { b.outline(0x1A1410) }
			return b
		}
		if let base = it.baseIcon {
			var b: PixelBuf = buf(base, cat, depth: 1)
			if it.tintAmt > 0.01 { b = b.tinted(it.tint & 0xFFFFFF, it.tintAmt) }
			return b
		}
		return missingItemBuf()
	}

	static func itemIcon(_ it: ModItem, _ cat: ModCatalog) -> Image {
		return pixImage(itemIconBuf(it, cat))
	}

	/// The picture of any item reference: the game's items, or a mod's block or item
	static func buf(_ it: Item, _ cat: ModCatalog, depth: Int = 0) -> PixelBuf {
		if case .custom(let k) = it {
			if let b = cat.block(k) { return b.art.isBlank ? greyTileBuf() : b.art.buf() }
			if let i = cat.item(k), depth < 2 {
				if !i.icon.isBlank { return itemIconBuf(i, cat) }
				if let base = i.baseIcon {
					var b: PixelBuf = buf(base, cat, depth: depth + 1)
					if i.tintAmt > 0.01 { b = b.tinted(i.tint & 0xFFFFFF, i.tintAmt) }
					return b
				}
			}
			return missingItemBuf()
		}
		return itemBuf(it)
	}

	static func icon(_ it: Item, _ cat: ModCatalog) -> Image {
		if case .custom = it { return pixImage(buf(it, cat)) }
		return Art.shared.icon(it)
	}

	static func name(_ it: Item, _ cat: ModCatalog) -> String {
		if case .custom(let k) = it {
			if let n = cat.names[k] { return n }
			return "Missing (" + k + ")"
		}
		return it.name
	}

	static func mobImage(_ m: ModMob) -> Image {
		let fr: ([PixelBuf], CreatureAnim) = modMobFrames(m)
		return pixImage(fr.0.first ?? PixelBuf(w: 1, h: 1))
	}

	static func shotBuf(_ s: ModProjectile) -> PixelBuf {
		var b = PixelBuf(w: 12, h: 12)
		let c: UInt32 = s.color & 0xFFFFFF
		let hi: UInt32 = mixRGB(c, 0xFFFFFF, 0.5)
		switch s.shape {
		case .orb:
			b.ellipse(6, 6, 4, 4, c)
			b.ellipse(5, 5, 1.6, 1.6, hi)
		case .arrow:
			b.line(1, 6, 9, 6, 0x8A6A40)
			b.line(9, 4, 11, 6, c); b.line(9, 8, 11, 6, c)
			b.set(1, 5, 0xE0E0E0); b.set(1, 7, 0xE0E0E0)
		case .bolt:
			b.rect(2, 5, 8, 2, c)
			b.rect(9, 4, 2, 4, hi)
		case .shard:
			b.line(2, 9, 10, 2, c); b.line(3, 9, 10, 3, hi); b.line(2, 8, 9, 2, c)
		case .rock:
			b.ellipse(6, 6, 3.4, 3.0, c)
			b.set(5, 5, hi)
		}
		b.outline(0x101010)
		return b
	}

	static func shotImage(_ s: ModProjectile) -> Image { return pixImage(shotBuf(s)) }
}

/// A pixel-art palette that suits the game: earth, stone, metals, gems, plants and skin tones
let modPalette: [UInt32] = [
	0x000000, 0x1D2B53, 0x7E2553, 0x008751, 0xAB5236, 0x5F574F, 0xC2C3C7, 0xFFF1E8,
	0xFF004D, 0xFFA300, 0xFFEC27, 0x00E436, 0x29ADFF, 0x83769C, 0xFF77A8, 0xFFCCAA,
	0x5DAA3A, 0x4B9230, 0x7A5230, 0x5A3A1E, 0x8A8A8A, 0x6A6A6A, 0x3A3A3E, 0xE8E0C8,
	0xD2793A, 0xD0D4DA, 0xF5D142, 0x4FE3E8, 0x8A7CFF, 0xFF6A1E, 0xB04CFF, 0xC02040
]

/// Paints a ModPixels grid with a finger: pen, eraser, fill and colour picker, with a mirror switch,
/// undo, clear, a palette and a colour mixer
/// Every item a mod may refer to: the game's own and the content of installed mods
struct ItemPickerView: View {
	let catalog: ModCatalog
	var title: String = "CHOOSE AN ITEM"
	var blocksOnly: Bool = false
	var pick: (Item) -> Void
	var cancel: () -> Void
	@State var search: String = ""
	@State var group: Int = 0

	static let groups: [String] = ["All", "Blocks", "Tools", "Weapons", "Armor", "Materials", "Food", "Mods"]

	var body: some View {
		ZStack {
			Color.black.opacity(0.7).ignoresSafeArea()
			VStack(spacing: 8) {
				HStack {
					Text(verbatim: title).font(.pixel(18)).foregroundColor(ModUI.gold)
					Spacer()
					SmallButton(title: "CANCEL", color: ModUI.red) { cancel() }
				}
				TextField("Search", text: $search)
					.font(.pixel(15, .bold))
					.foregroundColor(Color.white)
					.padding(10)
					.background(Color.black.opacity(0.6))
				if !blocksOnly { ChoiceRow(options: ItemPickerView.groups, selected: $group, columns: 8) }
				ScrollView {
					grid
				}
			}
			.padding(14)
			.frame(maxWidth: 900, maxHeight: 700)
			.background(PixelBox(color: ModUI.panel))
			.padding(10)
		}
	}

	var grid: some View {
		let list: [Item] = filtered()
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 82), spacing: 6)]
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(0..<list.count, id: \.self) { i in
				cell(list[i])
			}
		}
	}

	func cell(_ it: Item) -> some View {
		Button {
			pick(it)
		} label: {
			VStack(spacing: 2) {
				ModPreview.icon(it, catalog).resizable().interpolation(.none).frame(width: 36, height: 36)
				Text(verbatim: ModPreview.name(it, catalog)).font(.pixel(9, .semibold)).foregroundColor(Color.white).lineLimit(2).multilineTextAlignment(.center)
			}
			.frame(width: 82, height: 74)
			.background(PixelBox(color: ModUI.card))
		}
		.buttonStyle(.plain)
	}

	func filtered() -> [Item] {
		var all: [Item] = []
		var modItems: [Item] = []
		for p in catalog.packs {
			for b in p.blocks { modItems.append(.custom(p.key(b.id))) }
			if !blocksOnly { for i in p.items { modItems.append(.custom(p.key(i.id))) } }
		}
		let game: [Item] = allGameItems()
		switch blocksOnly ? 1 : group {
		case 1:
			for it in game { if case .block = it { all.append(it) } }
			for it in modItems { if case .custom(let k) = it, catalog.keys[k] == "block" { all.append(it) } }
		case 2:
			for it in game { if case .tool = it { all.append(it) } }
		case 3:
			all = game.filter { $0.isWeapon }
		case 4:
			for it in game { if case .armor = it { all.append(it) } else if case .gear = it { all.append(it) } }
		case 5:
			for it in game {
				switch it {
				case .mat, .ammo, .part: all.append(it)
				default: break
				}
			}
		case 6:
			for it in game { if case .food = it { all.append(it) } }
		case 7:
			all = modItems
		default:
			all = modItems + game
		}
		let q: String = search.trimmingCharacters(in: .whitespaces).lowercased()
		if q.isEmpty { return all }
		return all.filter { ModPreview.name($0, catalog).lowercased().contains(q) }
	}
}

// MARK: - Mod Creator: block, shot and item editors

/// Editing one custom block: picture, name, what it is, how it mines, collision, light, drops and
/// what it does when tapped
struct BlockEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var picking: Bool = false
	@State var copyFrom: Bool = false

	func b<T>(_ kp: WritableKeyPath<ModBlock, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.blocks, id, kp, d) }

	var block: ModBlock { return s.mod.blocks.first { $0.id == id } ?? ModBlock() }

	/// The block's picture: 8 x 8, or 16 x 16 like the game's own blocks
	var pictureSection: some View {
		let fine: Bool = block.art.w == tileArtPx
		let sizeTitle: String = fine ? "MAKE IT 8 x 8" : "MAKE IT 16 x 16"
		return ModSection(title: "PICTURE", help: "8 x 8 or 16 x 16 pixels (the game's own blocks are 16 x 16). Paint with your finger, or start from a game block.") {
			PixelEditorView(pixels: b(\.art, ModPixels(w: 8, h: 8)), maxSide: 280, outlineDefault: false)
			HStack(spacing: 6) {
				SmallButton(title: "START FROM A GAME BLOCK...") { copyFrom = true }
				SmallButton(title: sizeTitle, color: ModUI.blue) { self.changeArtSize() }
			}
		}
	}

	/// Switches the picture between 8 x 8 and 16 x 16, keeping what is painted (doubled, or every
	/// other pixel)
	func changeArtSize() {
		let a: ModPixels = block.art
		let n: Int = a.w == tileArtPx ? 8 : tileArtPx
		b(\.art, ModPixels(w: 8, h: 8)).wrappedValue = a.stretched(n, n)
	}

	var body: some View {
		ZStack {
			VStack(spacing: 10) {
				pictureSection
				ModSection(title: "ABOUT") {
					ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Ruby Ore")
					ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
					ChoiceRow(options: ModBlockCategory.allCases.map { $0.name }, selected: catBind, columns: 4)
				}
				ModSection(title: "MINING", help: "Hardness sets how long it takes to break; a tier asks for a strong enough tool of that kind.") {
					ModToggle(label: "Unbreakable", help: "Like bedrock: nothing can break it", isOn: b(\.unbreakable, false))
					StatSlider(label: "Hardness", value: b(\.hardness, 1), range: 0.05...(s.mod.sandbox ? 200 : 40), step: 0.05, format: "%.2f")
					Text("Best tool").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
					ChoiceRow(options: ToolType.allCases.map { $0.name }, selected: b(\.tool, 0), columns: 4)
					IntSlider(label: "Tool tier needed (0 = any)", value: b(\.tier, 0), range: 0...9)
					Text(verbatim: tierLine).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
					ModToggle(label: "Blast proof", help: "Explosions do not break it", isOn: b(\.blastProof, false))
				}
				BlockMiningTimes(block: block, tools: s.mod.items.filter { $0.kind == .tool })
				ModSection(title: "BODY", help: block.collision.help) {
					ChoiceRow(options: ModCollision.allCases.map { $0.name }, selected: collisionBind, columns: 3)
					ModToggle(label: "See-through", help: "Light passes it and you see the wall behind", isOn: b(\.transparent, false))
					IntSlider(label: "Light given off", value: b(\.light, 0), range: 0...15)
				}
				ModSection(title: "DROPS", help: "What you get when you break it.") {
					ModToggle(label: "Drops itself", isOn: b(\.dropSelf, true))
					if !block.dropSelf {
						HStack(spacing: 10) {
							if let d = block.drop {
								ModPreview.icon(d, s.catalog).resizable().interpolation(.none).frame(width: 36, height: 36)
								Text(verbatim: ModPreview.name(d, s.catalog)).font(.pixel(13)).foregroundColor(Color.white)
							} else {
								Text("Drops nothing").font(.pixel(13)).foregroundColor(ModUI.dim)
							}
							Spacer()
							SmallButton(title: "CHOOSE...", color: ModUI.blue) { picking = true }
							SmallButton(title: "NOTHING") { b(\.drop, nil).wrappedValue = nil }
						}
					}
					IntSlider(label: "How many", value: b(\.dropCount, 1), range: 1...16)
				}
				ModSection(title: "WHEN TAPPED", help: block.function.help) {
					ChoiceRow(options: ModBlockFunction.allCases.map { $0.name }, selected: functionBind, columns: 3)
					functionSettings
				}
				vehicleSection
				buildSection
			}
		}
		.modCover(s, picking ? 1 : nil) { self.dropPicker }
		.modCover(s, copyFrom ? 2 : nil) { self.copyPicker }
	}

	var dropPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "IT DROPS...", pick: { it in
			b(\.drop, nil).wrappedValue = it
			picking = false
		}, cancel: { picking = false })
	}

	var copyPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "COPY A BLOCK'S PICTURE", blocksOnly: true, pick: { it in
			let pic: PixelBuf = ModPreview.buf(it, s.catalog)
			b(\.art, ModPixels(w: 8, h: 8)).wrappedValue = ModBlock.fitArt(ModPixels(buf: pic))
			copyFrom = false
		}, cancel: { copyFrom = false })
	}

	var tierLine: String {
		let t: Int = block.tier
		if t <= 0 { return "Any tool (or bare hands) can break it." }
		let tier: Tier = Tier(rawValue: t) ?? .wood
		return "Needs a " + tier.name + " " + (ToolType(rawValue: block.tool) ?? .pickaxe).name.lowercased() + " or better."
	}

	var catBind: Binding<Int> {
		let base: Binding<ModBlockCategory> = b(\.category, .building)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModBlockCategory(rawValue: $0) ?? .building })
	}

	var collisionBind: Binding<Int> {
		let base: Binding<ModCollision> = b(\.collision, .solid)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModCollision(rawValue: $0) ?? .solid })
	}

	var functionBind: Binding<Int> {
		let base: Binding<ModBlockFunction> = b(\.function, .none)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModBlockFunction(rawValue: $0) ?? .none })
	}

	@ViewBuilder
	var functionSettings: some View {
		switch block.function {
		case .station:
			Text("Works as").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			ChoiceRow(options: ["Its own station", "Workbench", "Furnace", "Campfire", "Anvil", "Tinker's Bench", "Rift Forge", "Alchemy Still", "Infusion Crucible", "Assembly Station"], selected: stationBind, columns: 4)
		case .healer:
			StatSlider(label: "Health restored", value: b(\.power, 6), range: 1...40, step: 1, format: "%.0f")
		case .bounce:
			StatSlider(label: "Bounce strength", value: b(\.power, 6), range: 4...30, step: 1, format: "%.0f")
		case .trap:
			StatSlider(label: "Damage", value: b(\.power, 6), range: 1...40, step: 1, format: "%.0f")
		case .sign:
			ModTextField(label: "Sign text", text: b(\.text, ""), placeholder: "Welcome!")
		default:
			EmptyView()
		}
	}

	/// On a vehicle: the part this block works as, its mass there and how strong it is at the work
	var vehicleSection: some View {
		let role: ModVehicleRole = block.vehRole
		let help: String = role == .none ? "Built onto a vehicle (ON VEHICLE, or the Vehicle Assembler) it is just a block of its weight." : joinText("Built onto a vehicle it works as a ", role.name.lowercased(), ", with this picture.")
		return ModSection(title: "ON A VEHICLE", help: help) {
			ChoiceRows(options: ModVehicleRole.allCases.map { $0.name }, selected: roleBind, columns: 3)
			if role != .none {
				StatSlider(label: "Mass on the vehicle (0: from its hardness)", value: b(\.vehMass, 0), range: 0.0...(s.mod.sandbox ? 60.0 : 20.0), step: 0.05, format: "%.2f")
				StatSlider(label: "Strength at its work (1 = the game's part)", value: b(\.vehPower, 1), range: 0.25...(s.mod.sandbox ? 10.0 : 4.0), step: 0.05, format: "%.2f")
			}
			if role == .cannon || role == .machineGun { gunFields }
		}
	}

	/// A gun block: the mod's own shot it fires (or the game's), and how fast, how hard and how often
	@ViewBuilder
	var gunFields: some View {
		Text("Its shot").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
		ChoiceRows(options: ["GAME'S OWN"] + s.mod.projectiles.map { (p: ModProjectile) in p.name }, selected: shotBind, columns: 3)
		StatSlider(label: "Shot speed (0: the part's own)", value: b(\.shotSpeed, 0), range: 0.0...(s.mod.sandbox ? 200.0 : 80.0), step: 1, format: "%.0f")
		StatSlider(label: "Damage (0: the part's own)", value: b(\.shotDamage, 0), range: 0.0...(s.mod.sandbox ? 500.0 : 120.0), step: 0.5, format: "%.1f")
		StatSlider(label: "Shots a second (0: the part's own)", value: b(\.fireRate, 0), range: 0.0...(s.mod.sandbox ? 60.0 : 30.0), step: 0.5, format: "%.1f")
	}

	var shotBind: Binding<Int> {
		let base: Binding<String> = b(\.shot, "")
		let ids: [String] = s.mod.projectiles.map { (p: ModProjectile) in p.id }
		return Binding<Int>(get: { (ids.firstIndex(of: base.wrappedValue) ?? -1) + 1 }, set: { (k: Int) in base.wrappedValue = k <= 0 || k > ids.count ? "" : ids[k - 1] })
	}

	var roleBind: Binding<Int> {
		let base: Binding<ModVehicleRole> = b(\.vehRole, .none)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModVehicleRole(rawValue: $0) ?? .none })
	}

	var stationBind: Binding<Int> {
		let base: Binding<Int> = b(\.station, -1)
		// -1 own, 1 bench, 2 furnace, 3 campfire, 4 anvil, 5 tinker, 6 forge
		return Binding<Int>(get: { base.wrappedValue < 1 ? 0 : base.wrappedValue }, set: { base.wrappedValue = $0 == 0 ? -1 : $0 })
	}
}

/// Editing a shot: looks, flight and what happens when it lands
struct ShotEditorView: View {
	@ObservedObject var s: ModSession
	let id: String

	func b<T>(_ kp: WritableKeyPath<ModProjectile, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.projectiles, id, kp, d) }
	var shot: ModProjectile { return s.mod.projectiles.first { $0.id == id } ?? ModProjectile() }

	var body: some View {
		VStack(spacing: 10) {
			ModSection(title: "LOOK") {
				HStack(spacing: 12) {
					ModPreview.shotImage(shot).resizable().interpolation(.none).frame(width: 72, height: 72).background(Color.black.opacity(0.5))
					VStack(alignment: .leading) {
						ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Fire Bolt")
					}
				}
				ChoiceRow(options: ModShotShape.allCases.map { $0.name }, selected: shapeBind, columns: 5)
				ModColorRow(label: "Colour", color: b(\.color, 0x8AF0FF))
				StatSlider(label: "Size", value: b(\.size, 0.3), range: 0.1...1.0, step: 0.05, format: "%.2f")
				IntSlider(label: "Glow (light)", value: b(\.glow, 6), range: 0...12)
			}
			ModSection(title: "FLIGHT") {
				StatSlider(label: "Drop (gravity)", value: b(\.gravity, 0), range: 0...40, step: 1, format: "%.0f")
				StatSlider(label: "Flies for (seconds)", value: b(\.life, 2), range: 0.2...6, step: 0.1, format: "%.1f")
				IntSlider(label: "Passes through foes", value: b(\.pierce, 0), range: 0...5)
			}
			ModSection(title: "ON HIT") {
				StatSlider(label: "Blast radius (0 = none)", value: b(\.explode, 0), range: 0...(s.mod.sandbox ? 12 : 6), step: 0.5, format: "%.1f")
				ModToggle(label: "Blast breaks blocks", isOn: b(\.breakBlocks, false))
				StatSlider(label: "Sets on fire (seconds)", value: b(\.burn, 0), range: 0...10, step: 0.5, format: "%.1f")
			}
		}
	}

	var shapeBind: Binding<Int> {
		let base: Binding<ModShotShape> = b(\.shape, .orb)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModShotShape(rawValue: $0) ?? .orb })
	}
}

/// A colour chosen from the palette
struct ModColorRow: View {
	let label: String
	@Binding var color: UInt32

	/// swatches in each row of the palette
	static let perRow: Int = 8

	var body: some View {
		let rows: Int = (modPalette.count + ModColorRow.perRow - 1) / ModColorRow.perRow
		let now: Color = Color(ui: color & 0xFFFFFF)
		return VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 8) {
				Text(verbatim: label).font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
				Rectangle().fill(now).frame(width: 22, height: 22).overlay(Rectangle().stroke(Color.white, lineWidth: 1))
			}
			ForEach(0..<rows, id: \.self) { (r: Int) in self.paletteRow(r) }
		}
	}

	/// One row of the palette (plain rows, not a lazy grid)
	func paletteRow(_ r: Int) -> some View {
		let start: Int = r * ModColorRow.perRow
		let end: Int = min(modPalette.count, start + ModColorRow.perRow)
		return HStack(spacing: 4) {
			ForEach(start..<end, id: \.self) { (i: Int) in self.swatch(modPalette[i]) }
		}
	}

	func swatch(_ c: UInt32) -> some View {
		let on: Bool = (color & 0xFFFFFF) == c
		return Rectangle().fill(Color(hex: c)).frame(width: 30, height: 30)
			.overlay(Rectangle().stroke(on ? Color.white : Color.black, lineWidth: on ? 3 : 1))
			.onTapGesture { color = c }
	}
}

/// Editing one custom item; the sections shown depend on what kind of item it is
struct ItemEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var picker: Int = 0

	func b<T>(_ kp: WritableKeyPath<ModItem, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.items, id, kp, d) }
	var item: ModItem { return s.mod.items.first { $0.id == id } ?? ModItem() }
	var sb: Bool { return s.mod.sandbox }

	var body: some View {
		ZStack {
			VStack(spacing: 10) {
				header
				ModSection(title: "KIND", help: item.kind.help) {
					ChoiceRow(options: ModItemKind.allCases.map { $0.name }, selected: kindBind, columns: 4)
				}
				kindSections
				ModSection(title: "ICON", help: "Paint 16 x 16 pixels, or leave it empty to use a game item's icon in a colour of your choice.") {
					PixelEditorView(pixels: b(\.icon, ModPixels(w: 16, h: 16)), maxSide: 300, sizes: [8, 12, 16, 24, 32], outlineDefault: true)
					HStack {
						Text("Base icon:").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
						if let bi = item.baseIcon {
							ModPreview.icon(bi, s.catalog).resizable().interpolation(.none).frame(width: 30, height: 30)
						}
						SmallButton(title: "CHOOSE...", color: ModUI.blue) { picker = 1 }
					}
					ModColorRow(label: "Tint colour", color: b(\.tint, 0xFFFFFF))
					StatSlider(label: "Tint amount", value: b(\.tintAmt, 0), range: 0...1, step: 0.05, format: "%.2f")
				}
			}
		}
		.modCover(s, picker == 0 ? nil : picker) { self.pickerCover }
	}

	@ViewBuilder
	var pickerCover: some View {
		if picker == 1 {
			ItemPickerView(catalog: s.catalog, title: "ICON BASED ON...", pick: { it in
				b(\.baseIcon, nil).wrappedValue = it
				picker = 0
			}, cancel: { picker = 0 })
		}
		if picker == 2 {
			ItemPickerView(catalog: s.catalog, title: "AMMUNITION", pick: { it in
				b(\.ammo, nil).wrappedValue = it
				picker = 0
			}, cancel: { picker = 0 })
		}
	}

	var header: some View {
		ModSection(title: "ABOUT") {
			HStack(spacing: 12) {
				ModPreview.itemIcon(item, s.catalog).resizable().interpolation(.none).frame(width: 64, height: 64).background(Color.black.opacity(0.4))
				VStack(spacing: 6) {
					ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Ruby Sword")
					ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
				}
			}
			Text("Rarity").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			ChoiceRow(options: ModUI.rarityNames, selected: b(\.rarity, 0), columns: 5)
			if !item.kind.isWeapon && item.kind != .tool && item.kind != .armor {
				IntSlider(label: "Stack size", value: b(\.stack, 99), range: 1...(sb ? 999 : 99))
			}
		}
	}

	var kindBind: Binding<Int> {
		let base: Binding<ModItemKind> = b(\.kind, .material)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModItemKind(rawValue: $0) ?? .material })
	}

	@ViewBuilder
	var kindSections: some View {
		switch item.kind {
		case .food, .consumable: useSection
		case .tool: toolSection
		case .melee: meleeSection
		case .bow, .gun, .thrown, .magic: rangedSection
		case .armor: armorSection
		case .special: specialSection
		default: EmptyView()
		}
	}

	var useSection: some View {
		ModSection(title: "WHEN USED", help: "Effects come from a fixed list, so they always work safely.") {
			StatSlider(label: "Hunger restored", value: b(\.hunger, 0), range: 0...20, step: 1, format: "%.0f")
			StatSlider(label: "Time to use (seconds)", value: b(\.useTime, 0.6), range: 0.1...5, step: 0.1, format: "%.1f")
			ModEffectsEditor(effects: b(\.effects, []), sandbox: sb)
		}
	}

	var toolSection: some View {
		ModSection(title: "TOOL") {
			ChoiceRow(options: ToolType.allCases.map { $0.name }, selected: b(\.toolType, 0), columns: 4)
			IntSlider(label: "Tier (what it can break)", value: b(\.toolTier, 3), range: 1...9)
			Text(verbatim: "Breaks what a " + (Tier(rawValue: item.toolTier) ?? .wood).name + " tool breaks").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			StatSlider(label: "Mining speed", value: b(\.toolSpeed, 4), range: 0.3...(sb ? 200 : 30), step: 0.1, format: "x%.1f")
			StatSlider(label: "Damage when swung", value: b(\.damage, 4), range: 0...(sb ? 500 : 60), step: 0.5, format: "%.1f")
		}
	}

	var meleeSection: some View {
		ModSection(title: "MELEE", help: "Aimed with the attack stick like the game's own weapons.") {
			ChoiceRow(options: ["Slash (sword)", "Thrust (spear)", "Smash (hammer)", "Stab (knife)", "Bash (club)"], selected: b(\.style, 0), columns: 5)
			StatSlider(label: "Damage", value: b(\.damage, 6), range: 0...(sb ? 500 : 60), step: 0.5, format: "%.1f")
			StatSlider(label: "Time between swings", value: b(\.cooldown, 0.45), range: 0.15...3, step: 0.01, format: "%.2f s")
			StatSlider(label: "Reach", value: b(\.reach, 3), range: 0.5...(sb ? 12 : 6), step: 0.1, format: "%.1f")
			StatSlider(label: "Swing width", value: b(\.arc, 1), range: 0.1...1.6, step: 0.05, format: "%.2f")
			StatSlider(label: "Knockback", value: b(\.knock, 6), range: 0...(sb ? 40 : 16), step: 0.5, format: "%.1f")
			IntSlider(label: "Foes hit per swing", value: b(\.maxHits, 99), range: 1...99)
			StatSlider(label: "Wind-up before the blow", value: b(\.windup, 0), range: 0...0.6, step: 0.02, format: "%.2f s")
			ModToggle(label: "Heavy (breaks guards, cracks stone)", isOn: b(\.heavy, false))
			StatSlider(label: "Dazes for", value: b(\.daze, 0), range: 0...3, step: 0.1, format: "%.1f s")
			StatSlider(label: "Sets on fire for", value: b(\.burn, 0), range: 0...8, step: 0.5, format: "%.1f s")
			StatSlider(label: "Critical chance", value: b(\.crit, 0.1), range: 0...0.6, step: 0.01, format: "%.2f")
			ModToggle(label: "Combo (every 3rd blow hits twice)", isOn: b(\.combo, false))
			StatSlider(label: "Blow from behind", value: b(\.backstab, 1), range: 1...3, step: 0.1, format: "x%.1f")
			StatSlider(label: "Against the undead", value: b(\.undeadMult, 1), range: 0.5...3, step: 0.1, format: "x%.1f")
			ModColorRow(label: "Swing trail colour", color: b(\.trail, 0xFFFFFF))
		}
	}

	var rangedSection: some View {
		ModSection(title: "SHOOTING", help: rangedHelp) {
			StatSlider(label: "Damage", value: b(\.damage, 6), range: 0...(sb ? 500 : 60), step: 0.5, format: "%.1f")
			StatSlider(label: "Time between shots", value: b(\.cooldown, 0.45), range: 0.15...3, step: 0.01, format: "%.2f s")
			StatSlider(label: "Shot speed", value: b(\.speed, 30), range: 4...(sb ? 90 : 60), step: 1, format: "%.0f")
			StatSlider(label: "Shot drop", value: b(\.gravity, 0), range: 0...40, step: 1, format: "%.0f")
			StatSlider(label: "Knockback", value: b(\.knock, 6), range: 0...(sb ? 40 : 16), step: 0.5, format: "%.1f")
			IntSlider(label: "Shots per use (a fan)", value: b(\.spread, 1), range: 1...(sb ? 12 : 7))
			IntSlider(label: "Passes through foes", value: b(\.pierce, 0), range: 0...5)
			shotChoice
			if item.kind == .gun {
				IntSlider(label: "Magazine", value: b(\.magazine, 6), range: 1...(sb ? 99 : 30))
				StatSlider(label: "Reload time", value: b(\.reload, 1.5), range: 0.2...6, step: 0.1, format: "%.1f s")
				ModToggle(label: "Tap for every shot", help: "Off: holding keeps firing", isOn: b(\.needsPress, false))
			}
			ammoRow
		}
	}

	var rangedHelp: String {
		switch item.kind {
		case .bow: return "Hold to draw, release to shoot; a longer draw flies further and hits harder."
		case .gun: return "Fires while loaded, then reloads from its ammunition."
		case .thrown: return "Lobbed in an arc to where you aim. Each throw uses one from the stack."
		default: return "Fires on every use and needs no ammunition unless you pick one."
		}
	}

	var shotChoice: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text("Shot").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			let opts: [String] = ["Game shot"] + s.mod.projectiles.map { $0.name }
			ChoiceRow(options: opts, selected: shotIndexBind, columns: 4)
			if item.projectile.isEmpty {
				ChoiceRow(options: ModGameShots.names, selected: gameShotBind, columns: 5)
			}
		}
	}

	var shotIndexBind: Binding<Int> {
		let base: Binding<String> = b(\.projectile, "")
		let list: [String] = s.mod.projectiles.map { $0.id }
		return Binding<Int>(get: {
			guard let i = list.firstIndex(of: base.wrappedValue) else { return 0 }
			return i + 1
		}, set: { v in base.wrappedValue = v <= 0 || v > list.count ? "" : list[v - 1] })
	}

	var gameShotBind: Binding<Int> {
		let base: Binding<Int> = b(\.shot, 0)
		return Binding<Int>(get: { ModGameShots.kinds.firstIndex(of: base.wrappedValue) ?? 0 }, set: { base.wrappedValue = ModGameShots.kinds[clampI($0, 0, ModGameShots.kinds.count - 1)] })
	}

	var ammoRow: some View {
		HStack(spacing: 8) {
			Text("Ammunition:").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			if let a = item.ammo {
				ModPreview.icon(a, s.catalog).resizable().interpolation(.none).frame(width: 30, height: 30)
				Text(verbatim: ModPreview.name(a, s.catalog)).font(.pixel(12)).foregroundColor(Color.white)
			} else {
				Text(item.kind == .thrown ? "itself" : "none").font(.pixel(12)).foregroundColor(Color.white)
			}
			Spacer()
			SmallButton(title: "CHOOSE...", color: ModUI.blue) { picker = 2 }
			SmallButton(title: "NONE") { b(\.ammo, nil).wrappedValue = nil }
		}
	}

	var armorSection: some View {
		ModSection(title: "ARMOR") {
			ChoiceRow(options: ArmorSlot.allCases.map { $0.name }, selected: b(\.slot, 0), columns: 3)
			StatSlider(label: "Defense", value: b(\.defense, 2), range: 0...(sb ? 40 : 12), step: 0.5, format: "%.1f")
			IntSlider(label: "Looks like (tier)", value: b(\.look, 4), range: 1...9)
			Text(verbatim: "Drawn as " + (Tier(rawValue: item.look) ?? .iron).armorName + " armour").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ModOptionalEffect(label: "While worn", effect: b(\.wornEffect, nil), sandbox: sb)
		}
	}

	var specialSection: some View {
		ModSection(title: "SPECIAL") {
			IntSlider(label: "Light when held", value: b(\.light, 0), range: 0...15)
			ModEffectsEditor(effects: b(\.effects, []), sandbox: sb)
		}
	}
}

/// The game's own shots a mod item or attack can fire
enum ModGameShots {
	static let kinds: [Int] = [ProjKind.arrow.rawValue, ProjKind.bullet.rawValue, ProjKind.fireball.rawValue, ProjKind.rock.rawValue,
							   ProjKind.spit.rawValue, ProjKind.bolt.rawValue, ProjKind.shard.rawValue, ProjKind.quarrel.rawValue,
							   ProjKind.pellet.rawValue, ProjKind.pebble.rawValue]
	static let names: [String] = ["Arrow", "Bullet", "Fireball", "Rock", "Spit", "Bolt", "Shard", "Crossbow bolt", "Pellet", "Pebble"]
}

/// A list of up to four effects, each with its strength and length
struct ModEffectsEditor: View {
	@Binding var effects: [ModEffect]
	var sandbox: Bool
	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			ForEach(0..<effects.count, id: \.self) { i in
				effectRow(i)
			}
			if effects.count < ModLimits.maxEffects {
				SmallButton(title: "+ ADD EFFECT", color: ModUI.accent) { effects.append(ModEffect(.heal, 6, 20)) }
			}
		}
	}

	func effectRow(_ i: Int) -> some View {
		let e: ModEffect = i < effects.count ? effects[i] : ModEffect()
		let r: ModRange = e.kind.amountRange
		return VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(verbatim: "Effect " + String(i + 1)).font(.pixel(12)).foregroundColor(ModUI.gold)
				Spacer()
				SmallButton(title: "REMOVE", color: ModUI.red) { if i < effects.count { effects.remove(at: i) } }
			}
			ChoiceRow(options: ModEffectKind.allCases.map { $0.name }, selected: kindBind(i), columns: 5)
			if r.hi > r.lo {
				StatSlider(label: e.kind.amountLabel, value: field(i, \.amount), range: r.lo...(sandbox ? r.sandboxHi : r.hi), step: r.hi <= 4 ? 0.1 : 1, format: r.hi <= 4 ? "%.1f" : "%.0f")
			}
			if e.kind.timed {
				StatSlider(label: "Lasts (seconds)", value: field(i, \.seconds), range: 1...(sandbox ? 1800 : 300), step: 1, format: "%.0f")
			}
		}
		.padding(8)
		.background(Color.black.opacity(0.25))
	}

	func field(_ i: Int, _ kp: WritableKeyPath<ModEffect, Double>) -> Binding<Double> {
		let b: Binding<[ModEffect]> = $effects
		return Binding<Double>(get: { i < b.wrappedValue.count ? b.wrappedValue[i][keyPath: kp] : 0 }, set: { v in
			var list: [ModEffect] = b.wrappedValue
			if i < list.count { list[i][keyPath: kp] = v; b.wrappedValue = list }
		})
	}

	func kindBind(_ i: Int) -> Binding<Int> {
		let b: Binding<[ModEffect]> = $effects
		return Binding<Int>(get: { i < b.wrappedValue.count ? b.wrappedValue[i].kind.rawValue : 0 }, set: { v in
			var list: [ModEffect] = b.wrappedValue
			if i < list.count {
				let k: ModEffectKind = ModEffectKind(rawValue: v) ?? .heal
				list[i].kind = k
				list[i].amount = clampD(list[i].amount, k.amountRange.lo, k.amountRange.hi)
				b.wrappedValue = list
			}
		})
	}
}

/// An effect that may be switched off (armour's effect while worn)
struct ModOptionalEffect: View {
	let label: String
	@Binding var effect: ModEffect?
	var sandbox: Bool
	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			ModToggle(label: label, help: effect == nil ? "No effect" : (effect?.kind.name ?? ""), isOn: onBind)
			if effect != nil {
				ModEffectsEditor(effects: listBind, sandbox: sandbox)
			}
		}
	}

	var onBind: Binding<Bool> {
		let b: Binding<ModEffect?> = $effect
		return Binding<Bool>(get: { b.wrappedValue != nil }, set: { v in b.wrappedValue = v ? ModEffect(.speed, 15, 0) : nil })
	}

	var listBind: Binding<[ModEffect]> {
		let b: Binding<ModEffect?> = $effect
		return Binding<[ModEffect]>(get: { b.wrappedValue.map { [$0] } ?? [] }, set: { v in b.wrappedValue = v.first })
	}
}

// MARK: - Mod Creator: creature editor

/// The game creatures a custom creature's body can start from
let modBodyKinds: [MobKind] = [.zombie, .skeleton, .pirate, .imp, .archer, .golem, .pig, .cow, .sheep, .chicken, .wolf, .bear, .tiger,
							   .cat, .frog, .crow, .bat, .slime, .emberSlime, .scorpion, .crawler, .wraith, .fish, .elephant,
							   .giraffe, .mimic, .bearBoss, .rex, .sentinel, .warden]

struct MobEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var page: Int = 0
	@State var picking: Int = -1
	@State var frame: Int = 0

	func b<T>(_ kp: WritableKeyPath<ModMob, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.mobs, id, kp, d) }
	var mob: ModMob { return s.mod.mobs.first { $0.id == id } ?? ModMob() }
	var sb: Bool { return s.mod.sandbox }

	static let pages: [String] = ["BASICS", "LOOK", "STATS", "BEHAVIOUR", "ATTACKS", "SPAWNING", "DROPS", "PHASES", "SUMMON"]

	var body: some View {
		ZStack {
			VStack(spacing: 10) {
				previewHeader
				ChoiceRow(options: MobEditorView.pages, selected: $page, columns: 5)
				pageView
			}
		}
		.modCover(s, picking >= 0 ? picking : nil) { self.pickerCover }
	}

	var pickerCover: some View {
		ItemPickerView(catalog: s.catalog, title: "DROPS...", pick: { it in
			var list: [ModDrop] = mob.drops
			if picking < list.count { list[picking].item = it } else { list.append(ModDrop(it, 1, 1, 0.5)) }
			b(\.drops, []).wrappedValue = list
			picking = -1
		}, cancel: { picking = -1 })
	}

	var previewHeader: some View {
		let set: SpriteSet = modMobSpriteSet(mob)
		let img: Image = set.frame(0, left: false, hurt: false)
		let hb: (Double, Double) = hitBox
		return HStack(spacing: 14) {
			img.resizable().interpolation(.none).frame(width: CGFloat(set.w) * 2.0, height: CGFloat(set.h) * 2.0)
				.frame(width: 140, height: 140)
				.background(Color(ui: 0x5A7A9A).opacity(0.6))
			VStack(alignment: .leading, spacing: 4) {
				Text(verbatim: mob.name).font(.pixel(20)).foregroundColor(Color.white)
				Text(verbatim: mob.category.name).font(.pixel(12)).foregroundColor(ModUI.gold)
				Text(verbatim: String(format: "%.0f health · %.1f damage · speed %.1f", mob.hp, mob.damage, mob.speed)).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				Text(verbatim: String(format: "Size %.1f x %.1f blocks", hb.0, hb.1)).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 0)
		}
		.padding(10)
		.background(PixelBox(color: ModUI.card))
	}

	var hitBox: (Double, Double) {
		let base: MobKind = MobKind(rawValue: mob.base) ?? .zombie
		let d: MobDef = mobDef(base)
		return (d.w * mob.scale, d.h * mob.scale)
	}

	@ViewBuilder
	var pageView: some View {
		switch page {
		case 1: lookPage
		case 2: statsPage
		case 3: behaviourPage
		case 4: attacksPage
		case 5: spawnPage
		case 6: dropsPage
		case 7: BossPhasesPage(s: s, id: id)
		case 8: SummonPage(s: s, id: id)
		default: basicsPage
		}
	}

	var basicsPage: some View {
		VStack(spacing: 10) {
			ModSection(title: "BASICS") {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Crystal Wolf")
				ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
			}
			ModSection(title: "CATEGORY", help: mob.category.help) {
				ChoiceRow(options: ModMobCategory.allCases.map { $0.name }, selected: categoryBind, columns: 3)
				SmallButton(title: "USE TYPICAL SETTINGS FOR THIS CATEGORY", color: ModUI.blue) { applyPreset() }
			}
		}
	}

	var categoryBind: Binding<Int> {
		let base: Binding<ModMobCategory> = b(\.category, .hostile)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModMobCategory(rawValue: $0) ?? .hostile })
	}

	/// Behaviour and numbers that suit the category (a quick start for beginners)
	func applyPreset() {
		var m: ModMob = mob
		var bh = ModBehavior()
		switch m.category {
		case .passive:
			bh.wander = true; bh.runAway = true; bh.retaliate = false
			m.hp = 12; m.damage = 0; m.speed = 1.6; m.attacks = []
		case .neutral:
			bh.wander = true; bh.retaliate = true; bh.chase = true
			m.hp = 30; m.damage = 6; m.speed = 2.6; m.attacks = [ModAttack()]
		case .hostile:
			bh.wander = true; bh.chase = true; bh.attackPlayer = true
			m.hp = 30; m.damage = 7; m.speed = 2.2; m.attacks = [ModAttack()]
			m.spawn.when = 2
		case .boss:
			bh.wander = false; bh.chase = true; bh.attackPlayer = true; bh.defendArea = true; bh.defendRadius = 24
			m.hp = 800; m.damage = 18; m.speed = 2.6; m.scale = 2.2
			var slam = ModAttack(); slam.kind = .stomp; slam.damage = 14; slam.radius = 4; slam.cooldown = 4; slam.windup = 0.8
			var hit = ModAttack(); hit.kind = .melee; hit.damage = 18; hit.range = 2.4; hit.cooldown = 1.6
			m.attacks = [hit, slam]
			m.spawn.enabled = false
			if m.phases.isEmpty {
				var rage = ModPhase()
				rage.name = "Enraged"
				rage.message = joinText(m.name, " flies into a rage!")
				m.phases = [rage]
			}
		case .flying:
			bh.wander = true; bh.fly = true; bh.chase = true; bh.attackPlayer = true
			m.base = MobKind.bat.rawValue; m.hp = 12; m.damage = 4; m.speed = 4
			m.attacks = [ModAttack()]
		case .water:
			bh.wander = true; bh.swim = true; bh.runAway = true
			m.base = MobKind.fish.rawValue; m.hp = 6; m.damage = 0; m.attacks = []
			m.spawn.place = .ocean
		}
		m.behavior = bh
		if let i = s.mod.mobs.firstIndex(where: { $0.id == id }) {
			s.mod.mobs[i] = m
			s.touch()
		}
	}

	var lookPage: some View {
		VStack(spacing: 10) {
			ModSection(title: "BODY", help: "The body sets the shape, animations and hit box. Pick one, then change its colours and size.") {
				bodyGrid
				StatSlider(label: "Size", value: b(\.scale, 1), range: 0.5...((sb || mob.category == .boss) ? 4 : 2.5), step: 0.05, format: "x%.2f")
			}
			ModSection(title: "COLOURS") {
				StatSlider(label: "Hue turn", value: b(\.hue, 0), range: -180...180, step: 5, format: "%.0f°")
				StatSlider(label: "Colour strength", value: b(\.saturation, 1), range: 0...2, step: 0.05, format: "%.2f")
				StatSlider(label: "Brightness", value: b(\.brightness, 1), range: 0.4...1.6, step: 0.05, format: "%.2f")
				ModColorRow(label: "Tint", color: b(\.tint, 0xFFFFFF))
				StatSlider(label: "Tint amount", value: b(\.tintAmt, 0), range: 0...1, step: 0.05, format: "%.2f")
				IntSlider(label: "Glow (light)", value: b(\.glow, 0), range: 0...10)
			}
			ModSection(title: "OWN PIXEL ART (OPTIONAL)", help: "Draw up to 4 frames (standing, two walking, attacking) of up to 32 x 32 pixels. The body above still sets the hit box.") {
				ModToggle(label: "Use my own pictures", isOn: customArtBind)
				if mob.customArt { frameEditor }
			}
		}
	}

	var bodyGrid: some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 76), spacing: 6)]
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(0..<modBodyKinds.count, id: \.self) { i in
				bodyCell(modBodyKinds[i])
			}
		}
	}

	func bodyCell(_ k: MobKind) -> some View {
		let on: Bool = mob.base == k.rawValue
		let set: SpriteSet = Art.shared.creaturePreview(k)
		return Button {
			b(\.base, MobKind.zombie.rawValue).wrappedValue = k.rawValue
		} label: {
			VStack(spacing: 1) {
				set.frame(0, left: false, hurt: false).resizable().interpolation(.none).frame(width: 52, height: 52)
				Text(verbatim: mobDef(k).name).font(.pixel(8, .semibold)).foregroundColor(Color.white).lineLimit(1).minimumScaleFactor(0.6)
			}
			.frame(width: 76, height: 72)
			.background(PixelBox(color: on ? ModUI.accent : ModUI.card))
		}
		.buttonStyle(.plain)
	}

	var customArtBind: Binding<Bool> {
		let base: Binding<Bool> = b(\.customArt, false)
		let fr: Binding<[ModPixels]> = b(\.frames, [])
		return Binding<Bool>(get: { base.wrappedValue }, set: { v in
			if v && fr.wrappedValue.isEmpty { fr.wrappedValue = [ModPixels(w: 24, h: 24)] }
			base.wrappedValue = v
		})
	}

	var frameEditor: some View {
		let n: Int = mob.frames.count
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				ForEach(0..<n, id: \.self) { i in
					SmallButton(title: ["STAND", "WALK 1", "WALK 2", "ATTACK"][min(i, 3)], color: frame == i ? ModUI.accent : Color(ui: 0x555555)) { frame = i }
				}
				if n < ModLimits.maxFrames {
					SmallButton(title: "+ FRAME", color: ModUI.blue) {
						var list: [ModPixels] = mob.frames
						list.append(list.last ?? ModPixels(w: 24, h: 24))
						b(\.frames, []).wrappedValue = list
						frame = list.count - 1
					}
				}
			}
			HStack(spacing: 6) {
				Text("Size:").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
				ForEach([16, 24, 32], id: \.self) { sz in
					SmallButton(title: String(sz) + " x " + String(sz)) { resizeFrames(sz) }
				}
			}
			if frame < n {
				HStack(spacing: 6) {
					SmallButton(title: "COPY FRAME") {
						var list: [ModPixels] = mob.frames
						if list.count < ModLimits.maxFrames && frame < list.count {
							list.insert(list[frame], at: frame + 1)
							b(\.frames, []).wrappedValue = list
							frame += 1
						}
					}
					if n > 1 {
						SmallButton(title: "DELETE FRAME", color: ModUI.red) {
							var list: [ModPixels] = mob.frames
							if list.count > 1 && frame < list.count {
								list.remove(at: frame)
								b(\.frames, []).wrappedValue = list
								frame = max(0, min(frame, list.count - 1))
							}
						}
						SmallButton(title: "◀ MOVE") {
							var list: [ModPixels] = mob.frames
							if frame > 0 && frame < list.count {
								list.swapAt(frame, frame - 1)
								b(\.frames, []).wrappedValue = list
								frame -= 1
							}
						}
						SmallButton(title: "MOVE ▶") {
							var list: [ModPixels] = mob.frames
							if frame + 1 < list.count {
								list.swapAt(frame, frame + 1)
								b(\.frames, []).wrappedValue = list
								frame += 1
							}
						}
					}
				}
				PixelEditorView(pixels: frameBind(frame), maxSide: 360, frames: mob.frames, frameIndex: frame, sizes: [12, 16, 24, 32], outlineDefault: true,
								onResize: { w, h in b(\.frames, []).wrappedValue = mob.frames.map { $0.resized(w, h) } })
			}
		}
	}

	func frameBind(_ i: Int) -> Binding<ModPixels> {
		let fr: Binding<[ModPixels]> = b(\.frames, [])
		return Binding<ModPixels>(get: { i < fr.wrappedValue.count ? fr.wrappedValue[i] : ModPixels(w: 24, h: 24) }, set: { v in
			var list: [ModPixels] = fr.wrappedValue
			if i < list.count { list[i] = v; fr.wrappedValue = list }
		})
	}

	func resizeFrames(_ sz: Int) {
		let list: [ModPixels] = mob.frames.map { $0.resized(sz, sz) }
		b(\.frames, []).wrappedValue = list
	}

	var statsPage: some View {
		let hpR: ModRange = mob.category == .boss ? ModRange.bossHP : ModRange.mobHP
		return ModSection(title: "STATS", help: "Numbers are held to fair ranges (sandbox mode allows more).") {
			StatSlider(label: "Health", value: b(\.hp, 30), range: hpR.lo...(sb ? hpR.sandboxHi : hpR.hi), step: 1, format: "%.0f")
			StatSlider(label: "Contact damage", value: b(\.damage, 6), range: 0...(sb ? 500 : 60), step: 0.5, format: "%.1f")
			StatSlider(label: "Speed", value: b(\.speed, 2), range: 0...(sb ? 20 : 8), step: 0.1, format: "%.1f")
			StatSlider(label: "Notices you within", value: b(\.detect, 14), range: 2...(sb ? 64 : 32), step: 1, format: "%.0f blocks")
			StatSlider(label: "Jump", value: b(\.jump, 12), range: 0...(sb ? 30 : 20), step: 0.5, format: "%.1f")
			StatSlider(label: "Toughness (damage shrugged off)", value: b(\.defense, 0), range: 0...0.9, step: 0.05, format: "%.2f")
			StatSlider(label: "Knockback resistance", value: b(\.knockResist, 0), range: 0...1, step: 0.05, format: "%.2f")
			ModToggle(label: "Fireproof", help: "Fire and lava do not hurt it", isOn: b(\.fireproof, false))
		}
	}

	func bh<T>(_ kp: WritableKeyPath<ModBehavior, T>, _ d: T) -> Binding<T> {
		let base: Binding<ModBehavior> = b(\.behavior, ModBehavior())
		return Binding<T>(get: { base.wrappedValue[keyPath: kp] }, set: { v in
			var x: ModBehavior = base.wrappedValue
			x[keyPath: kp] = v
			base.wrappedValue = x
		})
	}

	var behaviourPage: some View {
		VStack(spacing: 10) {
			ModSection(title: "MOVING", help: "Switch on what it should do; the game's creature AI handles senses, paths and memory.") {
				ModToggle(label: "Wander", help: "Strolls around its home", isOn: bh(\.wander, true))
				ModToggle(label: "Stand still", help: "Stays where it is until something happens", isOn: bh(\.standStill, false))
				ModToggle(label: "Patrol", help: "Walks back and forth", isOn: bh(\.patrol, false))
				if mob.behavior.patrol { StatSlider(label: "Patrol distance", value: bh(\.patrolRange, 8), range: 2...40, step: 1, format: "%.0f blocks") }
				ModToggle(label: "Follow the player", help: "Keeps close to you without attacking", isOn: bh(\.followPlayer, false))
				ModToggle(label: "Run away", help: "From the player and from monsters", isOn: bh(\.runAway, false))
				ModToggle(label: "Fly", isOn: bh(\.fly, false))
				ModToggle(label: "Swim", isOn: bh(\.swim, false))
				ModToggle(label: "Stay in its biome", isOn: bh(\.stayInBiome, false))
				ModToggle(label: "Burns in sunlight", isOn: bh(\.burnsInSun, false))
			}
			ModSection(title: "FIGHTING") {
				ModToggle(label: "Chase the player", isOn: bh(\.chase, false))
				ModToggle(label: "Attack the player", isOn: bh(\.attackPlayer, false))
				ModToggle(label: "Fight back when hit", isOn: bh(\.retaliate, true))
				ModToggle(label: "Attack monsters nearby", help: "Hunts hostile creatures (a guardian)", isOn: bh(\.attackMobs, false))
				ModToggle(label: "Defend an area", help: "Attacks anyone who comes near its home", isOn: bh(\.defendArea, false))
				if mob.behavior.defendArea { StatSlider(label: "Area radius", value: bh(\.defendRadius, 10), range: 3...40, step: 1, format: "%.0f blocks") }
				guardRow
			}
		}
	}

	var guardRow: some View {
		let others: [ModMob] = s.mod.mobs.filter { $0.id != id }
		var names: [String] = ["Nobody"]
		var keys: [String] = [""]
		for o in others { names.append(o.name); keys.append(s.mod.key(o.id)) }
		for k in [MobKind.pig, .cow, .sheep, .villager] where k != .villager { names.append(mobDef(k).name); keys.append(mobDef(k).name) }
		let base: Binding<String> = bh(\.guardKey, "")
		let sel: Binding<Int> = Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { base.wrappedValue = keys[clampI($0, 0, keys.count - 1)] })
		return VStack(alignment: .leading, spacing: 4) {
			Text("Guards (stays beside)").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			ChoiceRow(options: names, selected: sel, columns: 4)
		}
	}

	var attacksPage: some View {
		VStack(spacing: 10) {
			Text("Attacks use the same damage rules as every weapon and monster in the game.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<mob.attacks.count, id: \.self) { i in
				attackEditor(i)
			}
			if mob.attacks.count < ModLimits.maxAttacks {
				PixelButton(title: "+ ADD ATTACK", color: ModUI.accent) {
					var list: [ModAttack] = mob.attacks
					list.append(ModAttack())
					b(\.attacks, []).wrappedValue = list
				}
			}
		}
	}

	func at<T>(_ i: Int, _ kp: WritableKeyPath<ModAttack, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModAttack]> = b(\.attacks, [])
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModAttack] = base.wrappedValue
			if i < list.count { list[i][keyPath: kp] = v; base.wrappedValue = list }
		})
	}

	func attackEditor(_ i: Int) -> some View {
		let a: ModAttack = i < mob.attacks.count ? mob.attacks[i] : ModAttack()
		let kindB: Binding<Int> = Binding<Int>(get: { a.kind.rawValue }, set: { v in at(i, \.kind, .melee).wrappedValue = ModAttackKind(rawValue: v) ?? .melee })
		let aimB: Binding<Int> = Binding<Int>(get: { a.aim.rawValue }, set: { v in at(i, \.aim, .forward).wrappedValue = ModAttackAim(rawValue: v) ?? .forward })
		return ModSection(title: "ATTACK " + String(i + 1) + ": " + a.kind.name.uppercased(), help: a.kind.help) {
			ChoiceRow(options: ModAttackKind.allCases.map { $0.name }, selected: kindB, columns: 4)
			StatSlider(label: "Damage", value: at(i, \.damage, 6), range: 0...(sb ? 500 : 60), step: 0.5, format: "%.1f")
			StatSlider(label: a.kind == .ranged ? "Range" : "Reach", value: at(i, \.range, 1.6), range: 0.5...(a.kind == .ranged ? 30 : 8), step: 0.1, format: "%.1f")
			StatSlider(label: "Time between attacks", value: at(i, \.cooldown, 1.2), range: 0.2...20, step: 0.1, format: "%.1f s")
			StatSlider(label: "Warning before it lands", value: at(i, \.windup, 0.3), range: 0...2, step: 0.05, format: "%.2f s")
			StatSlider(label: "Knockback", value: at(i, \.knock, 6), range: 0...(sb ? 40 : 16), step: 0.5, format: "%.1f")
			if a.kind == .area || a.kind == .stomp {
				StatSlider(label: "Area radius", value: at(i, \.radius, 2.5), range: 0.5...(sb ? 12 : 6), step: 0.1, format: "%.1f")
			}
			if a.kind == .multiHit {
				IntSlider(label: "Blows", value: at(i, \.hits, 3), range: 1...(sb ? 12 : 6))
			}
			if a.kind == .charge || a.kind == .jump {
				Text(verbatim: joinText(a.kind == .charge ? "Rushes up to " : "Leaps up to ", String(format: "%.0f", max(4.0, a.range * 3.0)), " blocks"))
					.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			if a.kind == .melee || a.kind == .multiHit || a.kind == .stomp {
				Text(a.kind == .stomp ? "Shockwaves (Forward: one way; otherwise both ways)" : "Where the blow lands").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
				ChoiceRow(options: ModAttackAim.allCases.map { $0.name }, selected: aimB, columns: 4)
			}
			if a.kind == .ranged {
				Text("Aim").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
				ChoiceRow(options: ModAttackAim.allCases.map { $0.name }, selected: aimB, columns: 4)
				StatSlider(label: "Shot speed", value: at(i, \.speed, 16), range: 4...(sb ? 90 : 60), step: 1, format: "%.0f")
				attackShot(i, a)
			}
			SmallButton(title: "REMOVE ATTACK", color: ModUI.red) {
				var list: [ModAttack] = mob.attacks
				if i < list.count { list.remove(at: i) }
				b(\.attacks, []).wrappedValue = list
			}
		}
	}

	func attackShot(_ i: Int, _ a: ModAttack) -> some View {
		let ids: [String] = s.mod.projectiles.map { $0.id }
		let opts: [String] = ["Game shot"] + s.mod.projectiles.map { $0.name }
		let pb: Binding<String> = at(i, \.projectile, "")
		let sel: Binding<Int> = Binding<Int>(get: { (ids.firstIndex(of: pb.wrappedValue) ?? -1) + 1 }, set: { v in pb.wrappedValue = v <= 0 || v > ids.count ? "" : ids[v - 1] })
		let gs: Binding<Int> = at(i, \.shot, 2)
		let gsel: Binding<Int> = Binding<Int>(get: { ModGameShots.kinds.firstIndex(of: gs.wrappedValue) ?? 0 }, set: { gs.wrappedValue = ModGameShots.kinds[clampI($0, 0, ModGameShots.kinds.count - 1)] })
		return VStack(alignment: .leading, spacing: 4) {
			ChoiceRow(options: opts, selected: sel, columns: 4)
			if a.projectile.isEmpty { ChoiceRow(options: ModGameShots.names, selected: gsel, columns: 5) }
		}
	}

	func sp<T>(_ kp: WritableKeyPath<ModSpawn, T>, _ d: T) -> Binding<T> {
		let base: Binding<ModSpawn> = b(\.spawn, ModSpawn())
		return Binding<T>(get: { base.wrappedValue[keyPath: kp] }, set: { v in
			var x: ModSpawn = base.wrappedValue
			x[keyPath: kp] = v
			base.wrappedValue = x
		})
	}

	var spawnPage: some View {
		let placeB: Binding<Int> = Binding<Int>(get: { mob.spawn.place.rawValue }, set: { v in sp(\.place, .surface).wrappedValue = ModSpawnPlace(rawValue: v) ?? .surface })
		return ModSection(title: "SPAWNING", help: "Where and when it appears by itself. It also counts towards the game's limits on monsters.") {
			ModToggle(label: "Appears in the world", help: mob.category == .boss ? "Bosses are best placed with the test tools or a structure" : "", isOn: sp(\.enabled, true))
			if mob.spawn.enabled {
				ChoiceRow(options: ModSpawnPlace.allCases.map { $0.name }, selected: placeB, columns: 5)
				ChoiceRow(options: ["Any time", "By day", "At night"], selected: sp(\.when, 0), columns: 3)
				ModBiomePicker(biomes: sp(\.biomes, []))
				IntSlider(label: "Highest row", value: sp(\.minY, 0), range: 0...559)
				IntSlider(label: "Lowest row", value: sp(\.maxY, 559), range: 0...559)
				StatSlider(label: "How common (zombie = 7)", value: sp(\.weight, 3), range: 0.1...10, step: 0.1, format: "%.1f")
				IntSlider(label: "Group size", value: sp(\.group, 1), range: 1...(mob.category == .boss ? 1 : 4))
				IntSlider(label: "At most nearby", value: sp(\.maxNearby, 4), range: 1...(mob.category == .boss ? 1 : 8))
			}
		}
	}

	var dropsPage: some View {
		let lootIDs: [String] = [""] + s.mod.loot.map { $0.id }
		let lootNames: [String] = ["No loot table"] + s.mod.loot.map { $0.name }
		let lb: Binding<String> = b(\.loot, "")
		let lsel: Binding<Int> = Binding<Int>(get: { lootIDs.firstIndex(of: lb.wrappedValue) ?? 0 }, set: { lb.wrappedValue = lootIDs[clampI($0, 0, lootIDs.count - 1)] })
		return VStack(spacing: 10) {
			ModSection(title: "DROPS", help: "Each drop has its own chance.") {
				ForEach(0..<mob.drops.count, id: \.self) { i in
					dropRow(i)
				}
				if mob.drops.count < ModLimits.maxDrops {
					SmallButton(title: "+ ADD DROP", color: ModUI.accent) { picking = mob.drops.count }
				}
			}
			ModSection(title: "LOOT TABLE", help: "Also rolled when it dies (make tables in the LOOT tab).") {
				ChoiceRow(options: lootNames, selected: lsel, columns: 3)
			}
		}
	}

	func dr<T>(_ i: Int, _ kp: WritableKeyPath<ModDrop, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModDrop]> = b(\.drops, [])
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModDrop] = base.wrappedValue
			if i < list.count { list[i][keyPath: kp] = v; base.wrappedValue = list }
		})
	}

	func dropRow(_ i: Int) -> some View {
		let d: ModDrop = i < mob.drops.count ? mob.drops[i] : ModDrop()
		return VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 8) {
				ModPreview.icon(d.item, s.catalog).resizable().interpolation(.none).frame(width: 30, height: 30)
				Text(verbatim: ModPreview.name(d.item, s.catalog)).font(.pixel(13)).foregroundColor(Color.white)
				Spacer()
				SmallButton(title: "CHANGE", color: ModUI.blue) { picking = i }
				SmallButton(title: "✕", color: ModUI.red) {
					var list: [ModDrop] = mob.drops
					if i < list.count { list.remove(at: i) }
					b(\.drops, []).wrappedValue = list
				}
			}
			IntSlider(label: "At least", value: dr(i, \.min, 1), range: 0...64)
			IntSlider(label: "At most", value: dr(i, \.max, 1), range: 0...64)
			StatSlider(label: "Chance", value: dr(i, \.chance, 0.5), range: 0...1, step: 0.01, format: "%.2f")
		}
		.padding(8)
		.background(Color.black.opacity(0.25))
	}
}

/// Biomes to pick from (none picked means every biome)
struct ModBiomePicker: View {
	@Binding var biomes: [Int]
	static let all: [Biome] = [.plains, .forest, .desert, .tundra, .jungle, .savanna, .swamp, .mountain, .ocean, .umbral]
	var body: some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 110), spacing: 6)]
		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: biomes.isEmpty ? "Biomes: every biome" : "Biomes: only those picked").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(0..<ModBiomePicker.all.count, id: \.self) { i in
					chip(ModBiomePicker.all[i])
				}
			}
		}
	}

	func chip(_ bi: Biome) -> some View {
		let on: Bool = biomes.contains(bi.rawValue)
		return Button {
			if on { biomes.removeAll { $0 == bi.rawValue } } else { biomes.append(bi.rawValue) }
		} label: {
			Text(verbatim: bi.name).font(.pixel(11)).foregroundColor(Color.white).frame(maxWidth: .infinity, minHeight: 36)
				.background(PixelBox(color: on ? ModUI.accent : Color(ui: 0x555555)))
		}
		.buttonStyle(.plain)
	}
}

// MARK: - Mod Creator: recipes, loot, ores and structures

struct RecipeEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var picking: Int = -2

	func b<T>(_ kp: WritableKeyPath<ModRecipe, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.recipes, id, kp, d) }
	var rec: ModRecipe { return s.mod.recipes.first { $0.id == id } ?? ModRecipe() }

	static let stations: [String] = ["By hand", "Workbench", "Furnace", "Campfire", "Anvil", "Tinker's Bench", "Rift Forge", "A block of this mod"]

	var body: some View {
		let cat: ModCatalog = s.catalog
		return ZStack {
			VStack(spacing: 10) {
				ModSection(title: "MAKES") {
					HStack(spacing: 10) {
						ModPreview.icon(rec.out, cat).resizable().interpolation(.none).frame(width: 48, height: 48)
						Text(verbatim: ModPreview.name(rec.out, cat)).font(.pixel(15)).foregroundColor(Color.white)
						Spacer()
						SmallButton(title: "CHOOSE...", color: ModUI.blue) { picking = -1 }
					}
					IntSlider(label: "How many", value: b(\.count, 1), range: 1...99)
				}
				ModSection(title: "INGREDIENTS", help: "Up to " + String(ModLimits.maxCost) + ".") {
					ForEach(0..<rec.cost.count, id: \.self) { i in costRow(i, cat) }
					if rec.cost.count < ModLimits.maxCost {
						SmallButton(title: "+ ADD INGREDIENT", color: ModUI.accent) { picking = rec.cost.count }
					}
				}
				ModSection(title: "WHERE") {
					ChoiceRow(options: RecipeEditorView.stations, selected: stationBind, columns: 4)
					if rec.station == -1 { stationBlockRow }
					Text("Crafting tab").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
					ChoiceRow(options: RecipeCat.allCases.map { $0.name }, selected: b(\.cat, RecipeCat.mods.rawValue), columns: 6)
				}
				ModIssueList(report: recipeReport)
			}
		}
		.modCover(s, picking >= -1 ? picking : nil) { self.pickerCover }
	}

	var pickerCover: some View {
		let title: String = picking == -1 ? "IT MAKES..." : "INGREDIENT"
		return ItemPickerView(catalog: s.catalog, title: title, pick: { it in
			if picking == -1 {
				b(\.out, .block(.planks)).wrappedValue = it
			} else {
				var list: [ModCost] = rec.cost
				if picking < list.count { list[picking].item = it } else { list.append(ModCost(it, 1)) }
				b(\.cost, []).wrappedValue = list
			}
			picking = -2
		}, cancel: { picking = -2 })
	}

	var recipeReport: ModReport {
		var p: ModPack = s.mod
		p.recipes = [rec]
		let full: ModReport = ModValidator.check(&p, known: s.catalog.keys)
		var r = ModReport()
		for i in full.issues where i.place.hasPrefix("Recipe") { r.issues.append(i) }
		return r
	}

	var stationBind: Binding<Int> {
		let base: Binding<Int> = b(\.station, 0)
		return Binding<Int>(get: { base.wrappedValue < 0 ? 7 : base.wrappedValue }, set: { base.wrappedValue = $0 == 7 ? -1 : $0 })
	}

	var stationBlockRow: some View {
		let blocks: [ModBlock] = s.mod.blocks.filter { $0.function == .station }
		let ids: [String] = blocks.map { $0.id }
		let base: Binding<String> = b(\.stationBlock, "")
		let sel: Binding<Int> = Binding<Int>(get: { ids.firstIndex(of: base.wrappedValue) ?? 0 }, set: { v in if !ids.isEmpty { base.wrappedValue = ids[clampI(v, 0, ids.count - 1)] } })
		return VStack(alignment: .leading, spacing: 4) {
			if blocks.isEmpty {
				Text("Make a block whose 'When tapped' is Crafting station first.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9060))
			} else {
				ChoiceRow(options: blocks.map { $0.name }, selected: sel, columns: 3)
			}
		}
	}

	func costRow(_ i: Int, _ cat: ModCatalog) -> some View {
		let c: ModCost = i < rec.cost.count ? rec.cost[i] : ModCost()
		let nB: Binding<Int> = Binding<Int>(get: { c.n }, set: { v in
			var list: [ModCost] = rec.cost
			if i < list.count { list[i].n = v; b(\.cost, []).wrappedValue = list }
		})
		return VStack(spacing: 4) {
			HStack(spacing: 8) {
				ModPreview.icon(c.item, cat).resizable().interpolation(.none).frame(width: 30, height: 30)
				Text(verbatim: ModPreview.name(c.item, cat)).font(.pixel(13)).foregroundColor(Color.white)
				Spacer()
				SmallButton(title: "CHANGE", color: ModUI.blue) { picking = i }
				SmallButton(title: "✕", color: ModUI.red) {
					var list: [ModCost] = rec.cost
					if i < list.count { list.remove(at: i) }
					b(\.cost, []).wrappedValue = list
				}
			}
			IntSlider(label: "Amount", value: nB, range: 1...99)
		}
		.padding(8)
		.background(Color.black.opacity(0.25))
	}
}

struct LootEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var picking: Int = -1

	func b<T>(_ kp: WritableKeyPath<ModLootTable, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.loot, id, kp, d) }
	var table: ModLootTable { return s.mod.loot.first { $0.id == id } ?? ModLootTable() }
	/// the chest chance shown as a percentage
	var pctB: Binding<Double> {
		let base: Binding<Double> = b(\.chestChance, 0)
		return Binding<Double>(get: { base.wrappedValue * 100.0 }, set: { base.wrappedValue = clampD($0 / 100.0, 0, 1) })
	}

	var body: some View {
		let cat: ModCatalog = s.catalog
		return ZStack {
			VStack(spacing: 10) {
				ModSection(title: "LOOT TABLE", help: "Each roll picks one entry by weight. Rarer entries have smaller weights.") {
					ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Treasure")
					IntSlider(label: "Rolls", value: b(\.rolls, 2), range: 1...6)
					StatSlider(label: "Weight of 'nothing'", value: b(\.nothing, 0), range: 0...200, step: 1, format: "%.0f")
					StatSlider(label: "Also in the world's chests", value: pctB, range: 0...100, step: 1, format: "%.0f%% of chests")
				}
				ModSection(title: "ENTRIES") {
					ForEach(0..<table.entries.count, id: \.self) { i in entryRow(i, cat) }
					if table.entries.count < ModLimits.maxLootEntries {
						SmallButton(title: "+ ADD ENTRY", color: ModUI.accent) { picking = table.entries.count }
					}
				}
			}
		}
		.modCover(s, picking >= 0 ? picking : nil) { self.pickerCover }
	}

	var pickerCover: some View {
		ItemPickerView(catalog: s.catalog, title: "LOOT ENTRY", pick: { it in
			var list: [ModLootEntry] = table.entries
			if picking < list.count { list[picking].item = it } else { list.append(ModLootEntry(it, 1, 1, 0)) }
			b(\.entries, []).wrappedValue = list
			picking = -1
		}, cancel: { picking = -1 })
	}

	func en<T>(_ i: Int, _ kp: WritableKeyPath<ModLootEntry, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModLootEntry]> = b(\.entries, [])
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModLootEntry] = base.wrappedValue
			if i < list.count { list[i][keyPath: kp] = v; base.wrappedValue = list }
		})
	}

	func entryRow(_ i: Int, _ cat: ModCatalog) -> some View {
		let e: ModLootEntry = i < table.entries.count ? table.entries[i] : ModLootEntry()
		let pct: Double = table.chance(i) * 100.0
		let col: UInt32 = ModLootEntry.rarityColors[clampI(e.rarity, 0, 3)]
		return VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 8) {
				ModPreview.icon(e.item, cat).resizable().interpolation(.none).frame(width: 30, height: 30)
				VStack(alignment: .leading, spacing: 1) {
					Text(verbatim: ModPreview.name(e.item, cat)).font(.pixel(13)).foregroundColor(Color.white)
					Text(verbatim: ModLootEntry.rarityNames[clampI(e.rarity, 0, 3)] + String(format: " · %.1f%% per roll", pct)).font(.pixel(11)).foregroundColor(Color(ui: col))
				}
				Spacer()
				SmallButton(title: "CHANGE", color: ModUI.blue) { picking = i }
				SmallButton(title: "✕", color: ModUI.red) {
					var list: [ModLootEntry] = table.entries
					if i < list.count { list.remove(at: i) }
					b(\.entries, []).wrappedValue = list
				}
			}
			ChoiceRow(options: ModLootEntry.rarityNames, selected: en(i, \.rarity, 0), columns: 4)
			IntSlider(label: "At least", value: en(i, \.min, 1), range: 1...64)
			IntSlider(label: "At most", value: en(i, \.max, 1), range: 1...64)
			StatSlider(label: "Own weight (0 = by rarity)", value: en(i, \.weight, 0), range: 0...200, step: 1, format: "%.0f")
		}
		.padding(8)
		.background(Color.black.opacity(0.25))
	}
}

struct OreEditorView: View {
	@ObservedObject var s: ModSession
	let id: String

	func b<T>(_ kp: WritableKeyPath<ModOre, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.ores, id, kp, d) }
	var ore: ModOre { return s.mod.ores.first { $0.id == id } ?? ModOre() }

	var body: some View {
		let blocks: [ModBlock] = s.mod.blocks
		let ids: [String] = blocks.map { $0.id }
		let bb: Binding<String> = b(\.block, "")
		let bsel: Binding<Int> = Binding<Int>(get: { ids.firstIndex(of: bb.wrappedValue) ?? 0 }, set: { v in if !ids.isEmpty { bb.wrappedValue = ids[clampI(v, 0, ids.count - 1)] } })
		return VStack(spacing: 10) {
			ModSection(title: "ORE") {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Ruby veins")
				if blocks.isEmpty {
					Text("Make the ore's block in the BLOCKS tab first.").font(.pixel(12)).foregroundColor(Color(ui: 0xFF9060))
				} else {
					Text("Made of").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
					ChoiceRow(options: blocks.map { $0.name }, selected: bsel, columns: 3)
				}
				ModDimChoice(s: s, dim: b(\.dim, 0), dimKey: b(\.dimKey, ""))
			}
			ModSection(title: "DEPTH", help: "Drag the two sliders: the green band shows where veins form. The sea is at row 120.") {
				HStack(alignment: .top, spacing: 14) {
					OreDepthBar(minY: ore.minY, maxY: ore.maxY, bottom: ore.dim == 0 ? WorldGen.H : umbralH, dim: ore.dim)
						.frame(width: 120, height: 300)
					VStack(spacing: 6) {
						IntSlider(label: "Highest row", value: b(\.minY, 150), range: 2...((ore.dim == 0 ? WorldGen.H : umbralH) - 2))
						IntSlider(label: "Lowest row", value: b(\.maxY, 330), range: 2...((ore.dim == 0 ? WorldGen.H : umbralH) - 2))
						Text(verbatim: depthWords).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
					}
				}
			}
			ModSection(title: "RARITY") {
				StatSlider(label: "Veins per 16 blocks of width", value: b(\.veins, 1.5), range: 0.05...8, step: 0.05, format: "%.2f")
				Text(verbatim: rarityWords).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				IntSlider(label: "Blocks per vein", value: b(\.size, 6), range: 1...24)
				Text("Forms in").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
				ChoiceRow(options: ModOre.hostNames, selected: b(\.host, 0), columns: 3)
			}
			OreControlsView(s: s, id: id)
		}
	}

	var depthWords: String {
		let mid: Int = (ore.minY + ore.maxY) / 2
		if ore.dim == 1 {
			// the realm is rock above row 40 and below row 200, an open cavern between
			if ore.maxY < 40 || ore.minY > 200 { return "In the Umbral Realm's ash rock." }
			if ore.minY >= 40 && ore.maxY <= 200 { return "Mostly open cavern here: few veins will find rock." }
			return "Partly in the open cavern (rows 40 to 200), where there is little rock."
		}
		if mid < 130 { return "Near the surface." }
		if mid < 220 { return "In the upper caves (like coal and copper)." }
		if mid < 360 { return "Deep underground (like iron and silver)." }
		if mid < 460 { return "Very deep (like gold)." }
		return "In the abyss (like diamond and mythril)."
	}

	var rarityWords: String {
		let v: Double = ore.veins
		if v < 0.2 { return "Very rare" }
		if v < 0.6 { return "Rare" }
		if v < 1.5 { return "Uncommon" }
		if v < 3.5 { return "Common" }
		return "Everywhere"
	}
}

/// The world's layers from the sky down, with the band where an ore forms
struct OreDepthBar: View {
	let minY: Int
	let maxY: Int
	let bottom: Int
	var dim: Int = 0
	var body: some View {
		Canvas { ctx, size in
			let w: Double = Double(size.width)
			let h: Double = Double(size.height)
			let fb: Double = Double(max(1, bottom))
			let over: [(Int, UInt32, String)] = [(0, 0x7AB0E8, "sky"), (110, 0x6A8A40, "surface"), (130, 0x8A6A40, "earth"),
												 (200, 0x7A7A7A, "caves"), (330, 0x5A5A68, "deep"), (450, 0x3A3448, "abyss")]
			// the Umbral Realm: a rock ceiling, the open cavern, then ash rock over lava
			let umbral: [(Int, UInt32, String)] = [(0, 0x5A4446, "ceiling"), (40, 0x1A1018, "cavern"), (200, 0x6A4A40, "ash rock"), (240, 0x8A3A20, "lava")]
			let layers: [(Int, UInt32, String)] = dim == 1 ? umbral : over
			for (i, l) in layers.enumerated() where l.0 < bottom {
				let y0: Double = Double(l.0) / fb * h
				let y1: Double = i + 1 < layers.count ? min(h, Double(layers[i + 1].0) / fb * h) : h
				ctx.fill(Path(CGRect(x: 0, y: y0, width: w, height: max(0, y1 - y0))), with: .color(Color(hex: l.1)))
			}
			let a: Double = Double(minY) / fb * h
			let b: Double = Double(maxY) / fb * h
			ctx.fill(Path(CGRect(x: w * 0.15, y: a, width: w * 0.7, height: max(3, b - a))), with: .color(Color(hex: 0x50E070, alpha: 0.75)))
			ctx.stroke(Path(CGRect(x: w * 0.15, y: a, width: w * 0.7, height: max(3, b - a))), with: .color(Color.white), lineWidth: 2)
		}
		.overlay(Rectangle().stroke(Color.white.opacity(0.5), lineWidth: 2))
	}
}

/// The strip shown while picking a structure's corners
struct CaptureBar: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var body: some View {
		let step: String = game.capA == nil ? "Tap the first corner of what you built" : "Now tap the opposite corner"
		return VStack {
			HStack(spacing: 10) {
				Text("CAPTURE").font(.pixel(14)).foregroundColor(Color(ui: 0x60E0FF))
				Text(verbatim: step).font(.pixel(12, .semibold)).foregroundColor(Color.white)
				SmallButton(title: "CANCEL", color: ModUI.red) { game.cancelCapture() }
			}
			.padding(10)
			.background(Color.black.opacity(0.7))
			.cornerRadius(6)
			.padding(.top, 58)
			Spacer()
		}
	}
}

/// Saving a captured structure: its name, the mod it goes into, where it appears
struct CapturePanel: View {
	@ObservedObject var game: Game
	@State var name: String = "My Structure"
	@State var target: Int = 0
	@State var newModName: String = "My Structures"
	@State var clearAir: Bool = true
	@State var placement: Int = 0
	@State var entries: [ModEntry] = []
	@State var note: String = ""
	@State var started: Bool = false

	var body: some View {
		let cap: (ModStructure, Int) = game.captureStructure(clearAir: clearAir)
		let cat: ModCatalog = ModCatalog.installed()
		let names: [String] = ["New mod"] + entries.map { $0.pack?.name ?? $0.id }
		return ScrollView {
			VStack(spacing: 10) {
				Text("SAVE STRUCTURE").font(.pixel(22)).foregroundColor(Color.white)
				StructurePreview(st: cap.0, catalog: cat).frame(height: 200)
				Text(verbatim: joinText(String(cap.0.w), " x ", String(cap.0.h), " blocks", cap.1 > 0 ? joinText(" · ", String(cap.1), " left out (machines, bedrock, the rift gate)") : ""))
					.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				ModTextField(label: "Name", text: $name, placeholder: "Ruined Hut")
				Text("Save into").font(.pixel(12, .bold)).foregroundColor(ModUI.dim).frame(maxWidth: .infinity, alignment: .leading)
				ChoiceRow(options: names, selected: $target, columns: 3)
				if target == 0 { ModTextField(label: "New mod's name", text: $newModName, placeholder: "My Structures") }
				Text("Where it appears").font(.pixel(12, .bold)).foregroundColor(ModUI.dim).frame(maxWidth: .infinity, alignment: .leading)
				ChoiceRow(options: ModPlacement.allCases.map { $0.name }, selected: $placement, columns: 3)
				ModToggle(label: "Empty space clears the ground", help: "Off: only its blocks are placed and the ground around them stays", isOn: $clearAir)
				if !note.isEmpty { Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(ui: 0xFFB060)) }
				HStack(spacing: 10) {
					PixelButton(title: "SAVE", color: ModUI.accent) {
						let id: String = target > 0 && target - 1 < entries.count ? entries[target - 1].id : ""
						let msg: String = game.saveCapture(name: name, modID: id, newModName: newModName, placement: ModPlacement(rawValue: placement) ?? .surface, clearAir: clearAir)
						if game.capturing { note = msg } else { game.say(msg, 5.0) }
					}
					PixelButton(title: "PICK AGAIN", color: ModUI.blue) {
						game.capA = nil
						game.capB = nil
						game.showCapture = false
						game.bumpHUD()
					}
					PixelButton(title: "CANCEL", color: ModUI.red) { game.cancelCapture() }
				}
			}
			.padding(16)
			.frame(maxWidth: 620)
			.background(ModUI.panel)
			.cornerRadius(10)
			.padding(20)
		}
		.onAppear {
			if started { return }
			started = true
			entries = ModStore.entries().filter { $0.pack != nil }
			placement = cap.0.placement.rawValue
		}
	}
}

/// The Mod Test tools, opened from the TEST button: the creatures, items and recipes of the world's mods,
/// the time of day, god mode, survival rules, clearing creatures, starting again and leaving
struct ModTestPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var reset: () -> Void
	var exit: () -> Void
	@State var tab: Int = 0
	@State var note: String = ""

	var body: some View {
		let rt: ModRuntime = ModRuntime.shared
		let title: String = rt.packs.first { $0.id == game.testMod }?.name ?? "Mod"
		return VStack(spacing: 10) {
			HStack {
				Text("MOD TEST").font(.pixel(20)).foregroundColor(Color(ui: 0x60E0FF))
				Text(verbatim: title).font(.pixel(14)).foregroundColor(Color.white).lineLimit(1)
				Spacer()
				SmallButton(title: "CLOSE", color: ModUI.accent) { game.showModTest = false }
			}
			Text("A test world: nothing here is saved.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				.frame(maxWidth: .infinity, alignment: .leading)
			ChoiceRow(options: ["CREATURES", "ITEMS", "RECIPES", "WORLD", "PROBLEMS", "LOGIC"], selected: $tab, columns: 6)
			ScrollView {
				VStack(spacing: 10) {
					if tab == 0 { creatures }
					if tab == 1 { items }
					if tab == 2 { recipes }
					if tab == 3 { worldTools }
					if tab == 4 { problems }
					if tab == 5 { LogicDebugView(game: game, hud: hud) }
				}
			}
			.frame(maxHeight: 420)
			if !note.isEmpty {
				Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(ui: 0xFFE070))
			}
		}
		.padding(16)
		.frame(maxWidth: 720)
		.background(ModUI.panel)
		.cornerRadius(10)
		.padding(16)
	}

	var creatures: some View {
		let rt: ModRuntime = ModRuntime.shared
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 120), spacing: 8)]
		return VStack(alignment: .leading, spacing: 8) {
			if rt.mobs.isEmpty {
				Text("This mod has no creatures yet.").font(.pixel(12)).foregroundColor(ModUI.dim)
			}
			LazyVGrid(columns: cols, spacing: 8) {
				ForEach(0..<rt.mobs.count, id: \.self) { i in
					Button(action: { note = game.testSpawn(i) }) {
						VStack(spacing: 4) {
							creatureImage(i)
							Text(verbatim: rt.mobs[i].def.name).font(.pixel(11)).foregroundColor(Color.white).lineLimit(1)
							Text(verbatim: rt.mobs[i].def.category.name).font(.pixel(9)).foregroundColor(ModUI.dim).lineLimit(1)
						}
						.frame(maxWidth: .infinity, minHeight: 96)
						.background(ModUI.card)
						.cornerRadius(6)
					}
				}
			}
			Text("Targets from the game").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			HStack(spacing: 8) {
				ForEach([MobKind.zombie, .skeleton, .pig, .cow], id: \.self) { k in
					SmallButton(title: mobDef(k).name.uppercased(), color: ModUI.blue) { note = game.testSpawnGame(k) }
				}
			}
			PixelButton(title: "CLEAR ALL CREATURES", color: ModUI.red) {
				game.clearCreatures()
				note = "Every creature is gone."
			}
		}
	}

	/// A creature's standing frame, 56 points high at its own width
	func creatureImage(_ slot: Int) -> some View {
		let set: SpriteSet = Art.shared.customMobSet(slot)
		let ratio: Double = Double(set.w) / Double(max(1, set.h))
		return set.frame(0, left: false, hurt: false).resizable().interpolation(.none)
			.frame(width: CGFloat(clampD(56.0 * ratio, 16, 112)), height: 56)
	}

	var items: some View {
		let list: [Item] = ModRuntime.shared.paletteItems()
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 64), spacing: 8)]
		return VStack(alignment: .leading, spacing: 8) {
			Text("Tap to put a stack in your bag.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if list.isEmpty { Text("This mod has no items or blocks yet.").font(.pixel(12)).foregroundColor(ModUI.dim) }
			LazyVGrid(columns: cols, spacing: 8) {
				ForEach(0..<list.count, id: \.self) { i in
					Button(action: {
						game.creativeGive(list[i])
						note = joinText("Took ", list[i].name, ".")
					}) {
						VStack(spacing: 2) {
							SlotView(stack: Stack(item: list[i], count: 1), size: 44)
							Text(verbatim: list[i].name).font(.pixel(9)).foregroundColor(Color.white).lineLimit(1)
						}
						.frame(maxWidth: .infinity, minHeight: 70)
					}
				}
			}
		}
	}

	var recipes: some View {
		let list: [Recipe] = ModRuntime.shared.recipes
		return VStack(alignment: .leading, spacing: 8) {
			Text("Take the ingredients (and the station), then craft it here or in the crafting panel. With survival rules on, the station is needed as it would be in play.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if list.isEmpty { Text("This mod has no recipes yet.").font(.pixel(12)).foregroundColor(ModUI.dim) }
			ForEach(list) { r in
				HStack(spacing: 8) {
					RecipeRow.live(game, r)
					VStack(spacing: 4) {
						SmallButton(title: "INGREDIENTS", color: ModUI.blue) { note = game.testIngredients(r) }
						SmallButton(title: "CRAFT", color: game.canCraft(r) ? ModUI.accent : Color(ui: 0x555555)) {
							let before: Int = game.inv.total(r.out)
							game.craft(r)
							note = game.inv.total(r.out) > before ? joinText("Made ", r.out.name, ".") : "Not yet: something is missing."
						}
					}
				}
			}
		}
	}

	var worldTools: some View {
		let god: Binding<Bool> = Binding<Bool>(get: { game.godMode }, set: { game.godMode = $0; game.bumpHUD() })
		let surv: Binding<Bool> = Binding<Bool>(get: { game.testSurvival }, set: { game.testSurvival = $0 })
		let spawns: Binding<Bool> = Binding<Bool>(get: { !game.pauseSpawning }, set: { game.pauseSpawning = !$0; game.bumpHUD() })
		return VStack(alignment: .leading, spacing: 10) {
			Text("Time of day").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			HStack(spacing: 8) {
				SmallButton(title: "MORNING", color: ModUI.blue) { setTime(0.02, "Morning.") }
				SmallButton(title: "NOON", color: ModUI.blue) { setTime(0.25, "Noon.") }
				SmallButton(title: "DUSK", color: ModUI.blue) { setTime(0.53, "Dusk.") }
				SmallButton(title: "MIDNIGHT", color: ModUI.blue) { setTime(0.75, "Midnight.") }
			}
			if ModRuntime.shared.dimSlots.contains(where: { $0 != nil }) {
				Text("Dimensions").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
				ForEach(0..<3, id: \.self) { i in
					if let d = ModRuntime.shared.dimSlots[i] {
						SmallButton(title: game.world.dim == d.dim ? joinText("LEAVE ", d.def.name.uppercased()) : joinText("VISIT ", d.def.name.uppercased()), color: Color(ui: 0x6A4AAA)) {
							note = game.testVisitDim(i)
						}
					}
				}
			}
			ModToggle(label: "God mode", help: "Nothing can hurt you", isOn: god)
			ModToggle(label: "Survival rules", help: "Hunger, damage, stations and using things up, as in a real game", isOn: surv)
			ModToggle(label: "Creatures spawn by themselves", help: "Off: only what you spawn here appears", isOn: spawns)
			SmallButton(title: "SAVE VEHICLE TO THE MOD", color: ModUI.accent) { note = saveVehicle() }
			HStack(spacing: 8) {
				PixelButton(title: "CLEAR CREATURES", color: ModUI.red) {
					game.clearCreatures()
					note = "Every creature is gone."
				}
				PixelButton(title: "RESET WORLD", color: Color(ui: 0x8A5A2E)) { reset() }
			}
			PixelButton(title: "EXIT TEST", color: Color(ui: 0x6A3A8A)) { exit() }
		}
	}

	func setTime(_ t: Double, _ what: String) {
		game.timeOfDay = t
		game.light.valid = false
		game.bumpHUD()
		note = what
	}

	var problems: some View {
		let reps: [ModReport] = ModRuntime.shared.reports
		return VStack(spacing: 8) {
			if reps.isEmpty { Text("No mods are active.").font(.pixel(12)).foregroundColor(ModUI.dim) }
			ForEach(0..<reps.count, id: \.self) { i in ModIssueList(report: reps[i]) }
		}
	}
}

struct StructureEditorView: View {
	@ObservedObject var s: ModSession
	let id: String

	func b<T>(_ kp: WritableKeyPath<ModStructure, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.structures, id, kp, d) }
	var st: ModStructure { return s.mod.structures.first { $0.id == id } ?? ModStructure() }

	var body: some View {
		let lootIDs: [String] = [""] + s.mod.loot.map { $0.id }
		let lootNames: [String] = ["Normal chest loot"] + s.mod.loot.map { $0.name }
		let lb: Binding<String> = b(\.loot, "")
		let lsel: Binding<Int> = Binding<Int>(get: { lootIDs.firstIndex(of: lb.wrappedValue) ?? 0 }, set: { lb.wrappedValue = lootIDs[clampI($0, 0, lootIDs.count - 1)] })
		let placeB: Binding<Int> = Binding<Int>(get: { st.placement.rawValue }, set: { v in b(\.placement, .surface).wrappedValue = ModPlacement(rawValue: v) ?? .surface })
		return VStack(spacing: 10) {
			ModSection(title: "STRUCTURE") {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Ruined Hut")
				StructurePreview(st: st, catalog: s.catalog).frame(height: 220)
				Text(verbatim: String(st.w) + " x " + String(st.h) + " blocks").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			ModSection(title: "WHERE IT APPEARS", help: "It never cuts into bedrock or the rift gate, and keeps away from the world's own landmarks.") {
				ChoiceRow(options: ModPlacement.allCases.map { $0.name }, selected: placeB, columns: 3)
				ModDimChoice(s: s, dim: b(\.dim, 0), dimKey: b(\.dimKey, ""))
				if st.placement == .underground {
					IntSlider(label: "Highest row", value: b(\.minY, 150), range: 4...550)
					IntSlider(label: "Lowest row", value: b(\.maxY, 400), range: 4...550)
				}
				ModBiomePicker(biomes: b(\.biomes, []))
			}
			ModSection(title: "HOW OFTEN") {
				StatSlider(label: "Chance at each site", value: b(\.chance, 0.35), range: 0.01...1, step: 0.01, format: "%.2f")
				IntSlider(label: "Blocks between sites", value: b(\.spacing, 300), range: 64...2048)
				Text(verbatim: String(format: "About one every %.0f blocks", Double(st.spacing) / max(0.01, st.chance))).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			ModSection(title: "CHESTS INSIDE") {
				ChoiceRow(options: lootNames, selected: lsel, columns: 3)
			}
		}
	}
}

/// A side view of a captured structure, drawn with the blocks' pictures
struct StructurePreview: View {
	let st: ModStructure
	let catalog: ModCatalog
	var body: some View {
		let w: Int = max(1, st.w)
		let h: Int = max(1, st.h)
		let palette: [Image] = st.palette.map { k in pixImage(catalog.block(k).map { $0.art.isBlank ? greyTileBuf() : $0.art.buf() } ?? missingTileBuf()) }
		let cells: [Int] = st.cells
		return Canvas { ctx, size in
			let c: Double = min(Double(size.width) / Double(w), Double(size.height) / Double(h))
			let ox: Double = (Double(size.width) - c * Double(w)) * 0.5
			ctx.fill(Path(CGRect(x: ox, y: 0, width: c * Double(w), height: c * Double(h))), with: .color(Color(hex: 0x6A90B8)))
			for y in 0..<h {
				for x in 0..<w {
					let i: Int = y * w + x
					if i >= cells.count { continue }
					let v: Int = cells[i]
					let r: CGRect = CGRect(x: ox + Double(x) * c, y: Double(y) * c, width: c + 0.5, height: c + 0.5)
					if v >= 1000 {
						let pi: Int = v - 1000
						if pi < palette.count { ctx.draw(palette[pi], in: r) }
					} else if v > 0, let t = Tile(rawValue: UInt8(v)), !t.isMod {
						ctx.draw(Art.shared.tile(t), in: r)
					}
				}
			}
		}
		.background(Color.black.opacity(0.4))
	}
}

extension WorldRenderer {
	/// Liquid cells that are only part full (flowing water, a spreading pool of lava), drawn over the
	/// land each frame at their level, with a lighter line along the surface
	static func drawLiquids(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let w: World = g.world
		let x0: Int = Int(floor(v.left)) - 1
		let x1: Int = Int(ceil(v.left + v.wTiles)) + 1
		let y0: Int = max(0, Int(floor(v.top)) - 1)
		let y1: Int = min(w.H - 1, Int(ceil(v.top + v.hTiles)) + 1)
		if y1 < y0 { return }
		let tp: Double = v.tp
		var cx: Int = floorDiv(x0, chunkW)
		while cx * chunkW <= x1 {
			if let c = w.chunks[cx], c.partials > 0 {
				let lev: [UInt8] = c.level
				let tiles: [UInt8] = c.tiles
				for lx in 0..<chunkW {
					let x: Int = cx * chunkW + lx
					if x < x0 || x > x1 { continue }
					for y in y0...y1 {
						let i: Int = lx * w.H + y
						let l: UInt8 = lev[i]
						if l == 0 || !Tile.liquidTable[Int(tiles[i])] { continue }
						guard let t = Tile(rawValue: tiles[i]), let L = Liquids.def(t) else { continue }
						let a: Double = Double(l) / 255.0
						let top: Double = Double(y) + 1.0 - a
						let r: CGRect = mkRect(v.sx(Double(x)), v.sy(top), tp + 0.5, a * tp + 0.5)
						// the colour of the liquid's own block (so a part-full cell matches a full one)
						let col: UInt32 = liquidShade(t, L)
						fillRect(&ctx, r, Color(hex: col, alpha: L.opacity))
						if !w.tile(x, y - 1).liquid {
							fillRect(&ctx, mkRect(v.sx(Double(x)), v.sy(top), tp + 0.5, max(1.0, tp * 0.08)), Color(hex: shadeRGB(col, 1.3), alpha: min(1.0, L.opacity + 0.15)))
						}
					}
				}
			}
			cx += 1
		}
	}
}

/// The colour a liquid is drawn in where a cell is only part full: the average of its block's picture
func liquidShade(_ t: Tile, _ L: LiquidDef) -> UInt32 {
	let i: Int = Int(t.rawValue)
	let bufs: [PixelBuf] = Art.shared.tileBufs
	if i < bufs.count, t.isMod == false { return averageColor(bufs[i]) & 0xFFFFFF }
	return artGrade(L.color)
}

/// A vehicle's picture of its cells that do not move (blocks, frames, hulls, wings...) and its back
/// walls, at 16 pixels a cell, kept on the vehicle and made again only when it changes. A ship of
/// hundreds of cells is then one picture to draw instead of hundreds.
enum VehicleArt {
	/// vehicles at least this big are drawn from their picture (and any with back walls)
	static let cells: Int = 24

	static func wanted(_ veh: Vehicle) -> Bool {
		return veh.parts.count >= cells || !veh.walls.isEmpty
	}

	/// Parts that look the same whatever the vehicle does (wheels, propellers and drills turn)
	static func still(_ t: PartType) -> Bool {
		switch t {
		case .wheel, .offroadWheel, .propeller, .drill, .diamondDrill, .voidDrill, .railWheel, .bigWheel, .piston: return false
		default: return true
		}
	}

	/// Parts with something drawn over them while they work (rotor blades, flames, a balloon's seams)
	static func working(_ veh: Vehicle, _ t: PartType) -> Bool {
		if t == .envelope || t == .burner { return true }
		return veh.aero && (t == .rotor || t == .airProp || t == .tailRotor || t == .jet)
	}

	static func picture(_ veh: Vehicle) -> Image? {
		let key: Int = veh.artRev &* 1_000_003 &+ Art.shared.gen
		if let img = veh.artImage, veh.artKey == key { return img }
		let n: Int = tileArtPx
		let w: Int = veh.gridW * n
		let h: Int = veh.gridH * n
		if w <= 0 || h <= 0 || w * h > 4_000_000 { return nil }
		var buf: PixelBuf = PixelBuf(w: w, h: h)
		let painter: SectionPainter = SectionPainter.shared
		let art: Art = Art.shared
		for (c, k) in veh.walls {
			let ox: Int = (c.dx - veh.minX) * n
			let oy: Int = (c.dy - veh.minY) * n
			let base: Int = (Int(k) - 1) * n * n
			if base < 0 || base + n * n > painter.wallPx.count { continue }
			for y in 0..<n {
				for x in 0..<n { over(&buf, ox + x, oy + y, painter.wallPx[base + y * n + x]) }
			}
		}
		for (c, t) in veh.parts where still(t) {
			let ox: Int = (c.dx - veh.minX) * n
			let oy: Int = (c.dy - veh.minY) * n
			var flip: Bool = false
			if (t == .airProp || t == .jet || t == .tailRotor), let f = veh.face[c], f.0 < 0 { flip = true }
			if let b = veh.blocks[c], Int(b.rawValue) < art.tileBufs.count {
				let src: PixelBuf = art.tileBufs[Int(b.rawValue)]
				stamp(&buf, src, ox, oy, n, flip)
			} else if t.rawValue < art.partBufs.count {
				stamp(&buf, art.partBufs[t.rawValue], ox, oy, n, flip)
			}
		}
		let img: Image = pixImage(buf)
		veh.artImage = img
		veh.artKey = key
		return img
	}

	/// Lays a picture over a cell, scaled to n pixels (8x8 part art is doubled), mirrored if asked
	static func stamp(_ buf: inout PixelBuf, _ src: PixelBuf, _ ox: Int, _ oy: Int, _ n: Int, _ flip: Bool) {
		if src.w <= 0 || src.h <= 0 { return }
		for y in 0..<n {
			let sy: Int = y * src.h / n
			for x in 0..<n {
				var sx: Int = x * src.w / n
				if flip { sx = src.w - 1 - sx }
				over(&buf, ox + x, oy + y, src.px[sy * src.w + sx])
			}
		}
	}

	/// One pixel laid over another (non-premultiplied colours)
	static func over(_ buf: inout PixelBuf, _ x: Int, _ y: Int, _ c: UInt32) {
		let a: UInt32 = (c >> 24) & 0xFF
		if a == 0 || x < 0 || y < 0 || x >= buf.w || y >= buf.h { return }
		let i: Int = y * buf.w + x
		if a == 255 || buf.px[i] == 0 {
			buf.px[i] = c
			return
		}
		let d: UInt32 = buf.px[i]
		let ia: UInt32 = 255 - a
		let r: UInt32 = (((c >> 16) & 0xFF) * a + ((d >> 16) & 0xFF) * ia) / 255
		let g: UInt32 = (((c >> 8) & 0xFF) * a + ((d >> 8) & 0xFF) * ia) / 255
		let b: UInt32 = ((c & 0xFF) * a + (d & 0xFF) * ia) / 255
		let da: UInt32 = max(a, (d >> 24) & 0xFF)
		buf.px[i] = (da << 24) | (r << 16) | (g << 8) | b
	}
}

// ===== p34_joints =====

// MARK: - Joints, servos and mechs
// A machine with moving parts is several sections, each a vehicle of its own (a rigid body), joined at
// hinges, servos and pistons. A joint part is built into a section; whatever is built on beyond it (the
// side away from the seat, or the smaller side) becomes a section of its own, joined there. The joints
// are worked out with the contacts, a few times each step: a hinge or servo keeps the two sections
// together at its middle and lets them turn; a servo also turns them toward where it is told, as fast
// and as hard as it can; a piston keeps them lined up and pushes the outer one out or pulls it back.
// What moves a joint is set on it (tap it): the stick, one of the buttons A, B and C on the screen, or a
// walk. A machine with walking joints (a mech) swings its hips and bends its knees in step as the
// stick says, and its feet on the ground carry it along.

/// Which joint a panel is setting up: the section it is built into, and its cell
struct JointRef {
	var vid: Int
	var cell: PartCell
}

/// A joint between a section and the one beyond it (the parent keeps it)
struct VJoint: Codable {
	/// the joint part's cell in the parent, and the section beyond it
	var cell: PartCell
	var child: Int
	/// the point they turn about, in the parent's cells and in the child's
	var pa: [Double]
	var pb: [Double]
	/// 0 hinge, 1 servo, 2 piston
	var kind: Int
	/// the child's turn against the parent when it was built (a hinge or servo measures from there)
	var base: Double
	/// a piston's direction in the parent's cells
	var axis: [Double]
	/// how far it may go: an angle either way (radians) or how far a piston reaches out (blocks)
	var lo: Double
	var hi: Double
	/// how fast it moves (radians or blocks a second) and how hard (1: a servo's own strength)
	var speed: Double
	var strength: Double
	/// what moves it (JointInput's number), turned the other way round if asked
	var input: Int
	var invert: Bool
	/// for a walk: the part it plays (JointRole's number) and which leg it is in
	var role: Int
	var leg: Int
	/// where it is being taken
	var target: Double
}

/// What moves a joint
enum JointInput: Int, CaseIterable {
	case none, stickUpDown, stickLeftRight, buttonA, buttonB, buttonC, walk
	var name: String {
		switch self {
		case .none: return "Nothing (holds)"
		case .stickUpDown: return "Stick up/down"
		case .stickLeftRight: return "Stick left/right"
		case .buttonA: return "Button A"
		case .buttonB: return "Button B"
		case .buttonC: return "Button C"
		case .walk: return "Walking"
		}
	}
}

/// The part a joint plays in a mech's walk
enum JointRole: Int, CaseIterable {
	case none, hip, knee, shoulder, elbow, neck, tail
	var name: String {
		switch self {
		case .none: return "None"
		case .hip: return "Hip"
		case .knee: return "Knee"
		case .shoulder: return "Shoulder"
		case .elbow: return "Elbow"
		case .neck: return "Neck"
		case .tail: return "Tail"
		}
	}
}

/// The numbers of joints
enum Joints {
	/// a servo's strength (the most it turns with, per strength), a piston's (the most it pushes with)
	static let torque: Double = 900.0
	static let force: Double = 900.0
	/// how firmly a joint holds its sections together (of the gap closed each step) and how many times
	/// the joints are worked out each step
	static let firm: Double = 0.25
	static let rounds: Int = 6
	/// a gap at a joint up to this is left to the joint's pull; past it the sections are moved together
	static let slack: Double = 0.02
	/// how fast a mech's walk goes round (a step a second at full stick), how fast it walks, and how
	/// quickly its feet bring it up to that speed
	static let gaitRate: Double = 5.0
	static let walkSpeed: Double = 3.2
	static let walkGrip: Double = 6.0
	/// how fast a walking machine may be turned back toward upright (radians a second, each second),
	/// and how quickly it is brought there
	static let balance: Double = 10.0
	static let level: Double = 5.0
	/// a joint's reach from the middle each way at most
	static let maxAngle: Double = 3.0
	static let maxReach: Double = 4.0
}

extension Game {
	// MARK: building

	/// After a section changes: every joint part with a side built beyond it that is not yet a section of
	/// its own splits that side off and joins it there
	func splitJointSections(_ v: Vehicle) {
		var guardCount: Int = 0
		var again: Bool = true
		while again && guardCount < 8 {
			again = false
			guardCount += 1
			for (c, t) in v.parts where t == .hinge || t == .servo || t == .piston {
				if v.joints.contains(where: { $0.cell == c }) { continue }
				if splitAt(v, c, t) {
					again = true
					break
				}
			}
		}
	}

	/// Splits off what is beyond a joint part (true when it did)
	func splitAt(_ v: Vehicle, _ j: PartCell, _ t: PartType) -> Bool {
		let near: [PartCell] = [PartCell(dx: j.dx + 1, dy: j.dy), PartCell(dx: j.dx - 1, dy: j.dy), PartCell(dx: j.dx, dy: j.dy + 1), PartCell(dx: j.dx, dy: j.dy - 1)]
		var sides: [Set<PartCell>] = []
		for n in near where v.parts[n] != nil {
			if sides.contains(where: { $0.contains(n) }) { continue }
			var seen: Set<PartCell> = [n]
			var stack: [PartCell] = [n]
			while let cur = stack.popLast() {
				let next: [PartCell] = [PartCell(dx: cur.dx + 1, dy: cur.dy), PartCell(dx: cur.dx - 1, dy: cur.dy), PartCell(dx: cur.dx, dy: cur.dy + 1), PartCell(dx: cur.dx, dy: cur.dy - 1)]
				for k in next where k != j && v.parts[k] != nil && !seen.contains(k) {
					seen.insert(k)
					stack.append(k)
				}
			}
			sides.append(seen)
		}
		if sides.count < 2 { return false }
		// the side that goes: not the one joined to the section it hangs from, nor the one with the seat;
		// else the lighter (a lift's heavy base stays, its platform moves)
		let keep: PartCell? = jointAnchor(v) ?? seatCell(v)
		var weights: [Double] = []
		for side in sides {
			var m: Double = 0
			for c in side { if let t = v.parts[c] { m += v.cellMass(c, t) } }
			weights.append(m)
		}
		var outIdx: Int = -1
		for (i, side) in sides.enumerated() {
			if let st = keep, side.contains(st) { continue }
			if outIdx < 0 || weights[i] < weights[outIdx] - 1e-9 { outIdx = i }
		}
		if outIdx < 0 { return false }
		let out: Set<PartCell> = sides[outIdx]
		// (a big part beyond it goes whole, or the split waits)
		for c in out { if let m = v.spanOf[c], !out.contains(m) { return false } }
		// joints built into the side that goes go with it, and what hangs from them hangs from it
		var moved: [VJoint] = []
		for jt in v.joints where out.contains(jt.cell) { moved.append(jt) }
		v.joints.removeAll { (jt: VJoint) in out.contains(jt.cell) }
		let b: Vehicle = Vehicle(id: newID(), first: .frame, x: 0, y: 0)
		b.parts.removeAll()
		for c in out {
			b.parts[c] = v.parts[c]
			if let k = v.blocks[c] { b.blocks[c] = k }
			if let d = v.dmg[c] { b.dmg[c] = d }
			if let w = v.walls[c] { b.walls[c] = w }
			if let m = v.spanOf[c] { b.spanOf[c] = m }
			if let k = v.tilt[c] { b.tilt[c] = k }
			v.parts[c] = nil
			v.blocks[c] = nil
			v.dmg[c] = nil
			v.walls[c] = nil
			v.spanOf[c] = nil
		}
		b.fuel = 0
		b.recompute(keepAnchor: false)
		b.angle = v.angle
		let at: (Double, Double) = v.toWorld(b.comX, b.comY)
		b.px = at.0
		b.py = at.1
		b.vx = v.vx
		b.vy = v.vy
		b.angVel = v.angVel
		b.updateBox()
		v.recompute(keepAnchor: true)
		// the side it joins on: the neighbour of the joint part in the new section
		var dir: (Double, Double) = (1, 0)
		for n in near where out.contains(n) { dir = (Double(n.dx - j.dx), Double(n.dy - j.dy)) }
		let mid: [Double] = [Double(j.dx) + 0.5, Double(j.dy) + 0.5]
		let kind: Int = t == .hinge ? 0 : (t == .servo ? 1 : 2)
		let lo: Double = kind == 2 ? 0 : -1.2
		let hi: Double = kind == 2 ? 3.0 : 1.2
		let jt: VJoint = VJoint(cell: j, child: b.id, pa: mid, pb: mid, kind: kind, base: 0, axis: [dir.0, dir.1], lo: lo, hi: hi, speed: kind == 2 ? 2.0 : 1.6, strength: 1.0, input: 0, invert: false, role: 0, leg: 0, target: 0)
		v.joints.append(jt)
		b.parentID = v.id
		// (the new section's cells lie where they did in this one, so a moved joint's points and turn hold)
		for mj in moved {
			b.joints.append(mj)
			if let c = vehicleByID(mj.child) { c.parentID = b.id }
		}
		vehicles.append(b)
		v.asleep = false
		b.asleep = false
		// (joint parts inside the new section split it further: a knee below a hip)
		splitJointSections(b)
		return true
	}

	/// Where a section is joined to the one it hangs from: its own cell beside that joint part
	func jointAnchor(_ v: Vehicle) -> PartCell? {
		guard v.parentID != 0, let p = vehicleByID(v.parentID), let j = p.joints.first(where: { $0.child == v.id }) else { return nil }
		let c: PartCell = j.cell
		let near: [PartCell] = [PartCell(dx: c.dx + 1, dy: c.dy), PartCell(dx: c.dx - 1, dy: c.dy), PartCell(dx: c.dx, dy: c.dy + 1), PartCell(dx: c.dx, dy: c.dy - 1)]
		for n in near where v.parts[n] != nil { return n }
		return nil
	}

	/// Every section of a machine, from the top one down
	func machineSections(_ root: Vehicle) -> [Vehicle] {
		var parts: [Vehicle] = [root]
		var k: Int = 0
		while k < parts.count && k < 40 {
			for j in parts[k].joints {
				if let c = vehicleByID(j.child), !parts.contains(where: { $0 === c }) { parts.append(c) }
			}
			k += 1
		}
		return parts
	}

	/// The section at the top of a jointed machine (where the controls are)
	func machineRoot(_ v: Vehicle) -> Vehicle {
		var cur: Vehicle = v
		var n: Int = 0
		while cur.parentID != 0 && n < 16, let p = vehicleByID(cur.parentID) {
			cur = p
			n += 1
		}
		return cur
	}

	// MARK: controls

	/// Once a frame, before the vehicles move: each joint's target from what drives it (the stick and the
	/// buttons of whoever drives the machine, or its walk), and a mech's feet carrying it along
	func jointControls(_ dt: Double) {
		// a section whose parent no longer holds it (its joint part gone with a change) is free
		for c in vehicles where c.parentID != 0 {
			let held: Bool = vehicleByID(c.parentID)?.joints.contains(where: { $0.child == c.id }) ?? false
			if !held { c.parentID = 0 }
		}
		var any: Bool = false
		for v in vehicles where !v.joints.isEmpty { any = true; break }
		if !any { return }
		// a section whose joint part is gone (broken off or taken away) goes free, and so does a joint
		// whose section is gone
		for v in vehicles where !v.joints.isEmpty {
			for (i, j) in v.joints.enumerated().reversed() {
				let part: PartType? = v.parts[j.cell]
				let still: Bool = part == .hinge || part == .servo || part == .piston
				guard let c = vehicleByID(j.child), c.parentID == v.id, still else {
					if let c = vehicleByID(j.child), c.parentID == v.id { c.parentID = 0 }
					v.joints.remove(at: i)
					continue
				}
			}
		}
		for root in vehicles where root.parentID == 0 && !root.joints.isEmpty {
			machineControls(root, dt)
		}
	}

	/// One machine's frame: its sections wake and step together, its joints take their targets from
	/// whoever drives it (in any of its seats), and its walk goes on
	func machineControls(_ root: Vehicle, _ dt: Double) {
		let all: [Vehicle] = machineSections(root)
		// (a joint between a section that moves and one that does not would come apart)
		if all.contains(where: { !$0.asleep }) {
			for p in all {
				p.asleep = false
				p.physAccum = root.physAccum
			}
		}
		// they go to rest together too: none is let rest before all have been still a while
		if !all.allSatisfy({ (p: Vehicle) in p.sleepT >= 0.45 }) {
			for p in all where p.sleepT > 0.45 { p.sleepT = 0.45 }
		}
		let drv: Vehicle? = all.first { (p: Vehicle) in p.rider || p.auto != 0 || p.signalDrive }
		let buttons: [Bool] = machineButtonsHeld(root, playerDrives(root))
		let sx: Double = drv?.throttle ?? 0
		let sy: Double = drv?.pitch ?? 0
		var walking: Bool = false
		var moved: Bool = false
		for v in all {
			for i in v.joints.indices {
				var j: VJoint = v.joints[i]
				let was: Double = j.target
				let dir: Double = j.invert ? -1.0 : 1.0
				let input: JointInput = JointInput(rawValue: j.input) ?? .none
				switch input {
				case .none:
					break
				case .stickUpDown:
					j.target += sy * dir * stickSense(j, true) * j.speed * dt
				case .stickLeftRight:
					j.target += sx * dir * stickSense(j, false) * j.speed * dt
				case .buttonA, .buttonB, .buttonC:
					let held: Bool = buttons[j.input - JointInput.buttonA.rawValue]
					let want: Double = held != j.invert ? j.hi : j.lo
					j.target += clampD(want - j.target, -j.speed * dt, j.speed * dt)
				case .walk:
					walking = true
					j.target = gaitTarget(root, j)
				}
				j.target = clampD(j.target, j.lo, j.hi)
				if abs(j.target - was) > 1e-6 { moved = true }
				v.joints[i] = j
			}
		}
		// a joint told to move wakes the machine
		if moved {
			for p in all {
				p.asleep = false
				p.sleepT = 0
			}
		}
		if walking {
			if abs(sx) > 0.1 {
				root.gait += sx * Joints.gaitRate * dt
				root.gaitDir = sx > 0 ? 1.0 : -1.0
			}
			let want: Double = abs(sx) > 0.1 ? 1.0 : 0.0
			root.gaitAmp += clampD(want - root.gaitAmp, -2.0 * dt, 2.0 * dt)
			if let d = drv { walkMachine(root, all, d.throttle, dt) }
		}
	}

	/// Which way a joint goes for the stick pushed up (or right): what sticks out beside it goes up, what
	/// stands on it or hangs from it goes right; a piston pushes out
	func stickSense(_ j: VJoint, _ upDown: Bool) -> Double {
		if j.kind == 2 { return 1.0 }
		if upDown { return abs(j.axis[0]) > 0.5 ? -j.axis[0] : 1.0 }
		return abs(j.axis[1]) > 0.5 ? -j.axis[1] : 1.0
	}

	/// Where a walking joint is in its stride: hips swing to and fro, knees bend while the leg swings
	/// forward (so the foot clears the ground) and are straight while it pushes back; legs take turns
	/// (each leg half a stride after the other). Standing, the legs come back straight.
	func gaitTarget(_ root: Vehicle, _ j: VJoint) -> Double {
		let ph: Double = root.gait + Double(j.leg) * Double.pi
		let mid: Double = (j.lo + j.hi) * 0.5
		let amp: Double = (j.hi - j.lo) * 0.5 * root.gaitAmp
		let role: JointRole = JointRole(rawValue: j.role) ?? .none
		let dir: Double = j.invert ? -1.0 : 1.0
		switch role {
		case .hip, .shoulder:
			// (a hip turning the leg clockwise puts the foot back)
			return mid + amp * sin(ph) * dir
		case .knee, .elbow:
			// the hip swings the foot forward while the hip's angle falls: then the knee bends
			let swing: Double = -cos(ph) * root.gaitDir
			let straight: Double = j.invert ? j.hi : j.lo
			let bent: Double = j.invert ? j.lo : j.hi
			return straight + (bent - straight) * max(0, swing) * root.gaitAmp
		case .tail, .neck:
			return mid + amp * 0.4 * sin(ph * 2.0)
		case .none:
			return mid
		}
	}

	/// A mech's feet carry it: while the stick says walk and some of its walking sections touch the
	/// ground, the machine is brought toward its walking speed (the legs' swing is what is seen; the
	/// grip of the feet on the ground is what moves it)
	func walkMachine(_ root: Vehicle, _ parts: [Vehicle], _ throttle: Double, _ dt: Double) {
		var legs: Int = 0
		var down: Int = 0
		for p in parts {
			for j in p.joints where j.input == JointInput.walk.rawValue {
				guard let c = vehicleByID(j.child) else { continue }
				legs += 1
				if c.contacts > 0 { down += 1 }
			}
		}
		if legs == 0 || down == 0 { return }
		balanceMachine(root, parts, dt)
		// (let go, the feet bring it to a stop just as smoothly: planted at speed, it would trip)
		let walking: Bool = abs(throttle) >= 0.1
		if !walking && abs(root.vx) < 0.05 { return }
		let want: Double = walking ? throttle * Joints.walkSpeed : 0
		let share: Double = min(1.0, Double(down) / Double(max(1, legs)) * 2.0)
		let dv: Double = (want - root.vx) * min(1.0, Joints.walkGrip * dt) * share
		for p in parts {
			p.vx += dv
			p.asleep = false
		}
	}


	/// A walking machine with a driver keeps its body upright, as the driver leans (a two-legged mech
	/// stands on one foot while the other swings): the whole machine is turned back toward level, no
	/// faster than Joints.balance allows
	func balanceMachine(_ root: Vehicle, _ parts: [Vehicle], _ dt: Double) {
		var m: Double = 0
		var cx: Double = 0
		var cy: Double = 0
		for p in parts {
			m += p.mass
			cx += p.px * p.mass
			cy += p.py * p.mass
		}
		if m <= 0 { return }
		cx /= m
		cy /= m
		let tilt: Double = remainder(root.angle, 2.0 * Double.pi)
		// (upright and still enough: left alone)
		if abs(tilt) < 0.02 && abs(root.angVel) < 0.05 { return }
		let want: Double = clampD(-tilt * Joints.level, -2.0, 2.0)
		let dw: Double = clampD(want - root.angVel, -Joints.balance * dt, Joints.balance * dt)
		if abs(dw) < 1e-6 { return }
		for p in parts {
			p.angVel += dw
			p.vx -= dw * (p.py - cy)
			p.vy += dw * (p.px - cx)
			p.asleep = false
		}
	}

	// MARK: the joints at work

	/// Every joint, worked out together a few times (called between the vehicles' fixed steps)
	func solveJoints(_ h: Double) {
		var round: Int = 0
		while round < Joints.rounds {
			for a in vehicles where !a.joints.isEmpty {
				for j in a.joints {
					// (a machine at rest is left alone: what is not being stepped would gather pushes)
					guard let b = vehicleByID(j.child), a.inStep || b.inStep else { continue }
					if j.kind == 2 { pistonStep(a, b, j, h, round == 0) } else { pivotStep(a, b, j, h, round == 0) }
				}
			}
			// and where the sections stand on the land, their footing again with what the joints did (not a
			// mech's in mid-stride: its feet are carried along by its walk)
			for v in vehicles where v.inStep && !v.heldContacts.isEmpty && (v.parentID != 0 || !v.joints.isEmpty) {
				if v.parentID != 0 && machineRoot(v).gaitAmp > 0.01 { continue }
				if v.parentID == 0 && v.gaitAmp > 0.01 { continue }
				footingPass(v)
			}
			round += 1
		}
		// what gap is left is closed by moving the sections themselves most of the way (a joint driven
		// hard against the land opens a little each step; this keeps it from showing)
		for a in vehicles where !a.joints.isEmpty {
			for j in a.joints {
				guard let b = vehicleByID(j.child), a.inStep || b.inStep else { continue }
				closeJointGap(a, b, j)
			}
		}
	}

	/// One more pass over the places a section stands on the land (kept from its last step): each place
	/// stops it going into the ground and holds it by its grip, adding to what that place already gave
	func footingPass(_ v: Vehicle) {
		let invM: Double = 1.0 / v.mass
		let invI: Double = 1.0 / v.inertia
		var i: Int = 0
		while i < v.heldContacts.count {
			var k: VContact = v.heldContacts[i]
			let vn: Double = (v.vx - v.angVel * k.ry) * k.nx + (v.vy + v.angVel * k.rx) * k.ny
			let jn0: Double = k.jn
			k.jn = max(0, jn0 + (k.want - vn) / k.kn)
			let dn: Double = k.jn - jn0
			v.vx += dn * k.nx * invM
			v.vy += dn * k.ny * invM
			v.angVel += k.rn * dn * invI
			let tx: Double = -k.ny
			let ty: Double = k.nx
			let vt: Double = (v.vx - v.angVel * k.ry) * tx + (v.vy + v.angVel * k.rx) * ty
			let lim: Double = k.mu * k.jn
			let jt0: Double = k.jt
			k.jt = clampD(jt0 - vt / k.kt, -lim, lim)
			let dtn: Double = k.jt - jt0
			v.vx += dtn * tx * invM
			v.vy += dtn * ty * invM
			v.angVel += k.rt * dtn * invI
			v.heldContacts[i] = k
			i += 1
		}
	}

	/// Moves two joined sections toward each other (the lighter one more) to close most of the gap at a
	/// pivot, or a piston's drift off its line
	func closeJointGap(_ a: Vehicle, _ b: Vehicle, _ j: VJoint) {
		let pa: (Double, Double) = a.toWorld(j.pa[0], j.pa[1])
		let pb: (Double, Double) = b.toWorld(j.pb[0], j.pb[1])
		var gx: Double = pb.0 - pa.0
		var gy: Double = pb.1 - pa.1
		if j.kind == 2 {
			// (a piston only off its line: along it is its reach)
			let ux: Double = j.axis[0] * a.cosA - j.axis[1] * a.sinA
			let uy: Double = j.axis[0] * a.sinA + j.axis[1] * a.cosA
			let along: Double = gx * ux + gy * uy
			gx -= along * ux
			gy -= along * uy
		}
		// (only a real gap: a small one is closed by the joint's pull, which the ground's grip can hold
		// against; moving a section at rest by hand would creep it along the ground)
		let len: Double = sqrt(gx * gx + gy * gy)
		if len < Joints.slack { return }
		let part: Double = (len - Joints.slack) / len
		gx *= part
		gy *= part
		let ia: Double = 1.0 / a.mass
		let ib: Double = 1.0 / b.mass
		let wa: Double = ia / (ia + ib) * 0.6
		let wb: Double = ib / (ia + ib) * 0.6
		a.px += gx * wa
		a.py += gy * wa
		b.px -= gx * wb
		b.py -= gy * wb
		a.updateBox()
		b.updateBox()
	}

	/// A hinge or servo: the two sections held together at the pivot, free to turn; a servo turns them
	/// toward its target. (The turn is worked out first and the pivot last, so each round ends with the
	/// two held together: a servo's last hard turn would otherwise open the pivot for a step.)
	func pivotStep(_ a: Vehicle, _ b: Vehicle, _ j: VJoint, _ h: Double, _ drive: Bool) {
		let ia: Double = 1.0 / a.mass
		let ib: Double = 1.0 / b.mass
		let iia: Double = 1.0 / a.inertia
		let iib: Double = 1.0 / b.inertia
		// turning: a servo drives toward its target; a hinge only stops at its limits (with a little friction)
		let rel: Double = remainder(b.angle - a.angle - j.base, 2.0 * Double.pi)
		let w: Double = b.angVel - a.angVel
		let kk: Double = iia + iib
		if kk > 0 {
			var want: Double = w
			var most: Double = Double.infinity
			if j.kind == 1 {
				want = clampD((j.target - rel) * 8.0, -j.speed, j.speed)
				most = Joints.torque * j.strength * h
				if abs(j.target - rel) > 0.01 && drive {
					a.asleep = false
					b.asleep = false
				}
			} else {
				want = w * 0.96
				if rel < j.lo { want = max(w, (j.lo - rel) * 4.0) } else if rel > j.hi { want = min(w, (j.hi - rel) * 4.0) }
			}
			let lam: Double = clampD((want - w) / kk, -most, most)
			a.angVel -= lam * iia
			b.angVel += lam * iib
		}
		// the pivot: the speed of the pivot on each made the same, and the gap between them closed
		let pa: (Double, Double) = a.toWorld(j.pa[0], j.pa[1])
		let pb: (Double, Double) = b.toWorld(j.pb[0], j.pb[1])
		let rax: Double = pa.0 - a.px
		let ray: Double = pa.1 - a.py
		let rbx: Double = pb.0 - b.px
		let rby: Double = pb.1 - b.py
		let va: (Double, Double) = (a.vx - a.angVel * ray, a.vy + a.angVel * rax)
		let vb: (Double, Double) = (b.vx - b.angVel * rby, b.vy + b.angVel * rbx)
		let cx: Double = pb.0 - pa.0
		let cy: Double = pb.1 - pa.1
		let k11: Double = ia + ib + iia * ray * ray + iib * rby * rby
		let k12: Double = -iia * rax * ray - iib * rbx * rby
		let k22: Double = ia + ib + iia * rax * rax + iib * rbx * rbx
		let det: Double = k11 * k22 - k12 * k12
		if abs(det) > 1e-12 {
			let rx: Double = -((vb.0 - va.0) + Joints.firm * cx / h)
			let ry: Double = -((vb.1 - va.1) + Joints.firm * cy / h)
			let lx: Double = (k22 * rx - k12 * ry) / det
			let ly: Double = (k11 * ry - k12 * rx) / det
			a.vx -= lx * ia
			a.vy -= ly * ia
			a.angVel -= (rax * ly - ray * lx) * iia
			b.vx += lx * ib
			b.vy += ly * ib
			b.angVel += (rbx * ly - rby * lx) * iib
		}
	}

	/// A piston: the outer section is pushed out or pulled back toward the target; the two keep their
	/// turn and stay on its line (worked out last, so each round ends with them lined up)
	func pistonStep(_ a: Vehicle, _ b: Vehicle, _ j: VJoint, _ h: Double, _ drive: Bool) {
		let iia: Double = 1.0 / a.inertia
		let iib: Double = 1.0 / b.inertia
		let c: Double = a.cosA
		let s: Double = a.sinA
		let ux: Double = j.axis[0] * c - j.axis[1] * s
		let uy: Double = j.axis[0] * s + j.axis[1] * c
		// along it: toward the target, as hard as it can push
		var pa: (Double, Double) = a.toWorld(j.pa[0], j.pa[1])
		var pb: (Double, Double) = b.toWorld(j.pb[0], j.pb[1])
		let e: Double = (pb.0 - pa.0) * ux + (pb.1 - pa.1) * uy
		var want: Double = clampD((j.target - e) * 8.0, -j.speed, j.speed)
		if e < j.lo { want = max(want, (j.lo - e) * 4.0) } else if e > j.hi { want = min(want, (j.hi - e) * 4.0) }
		if abs(j.target - e) > 0.01 && drive {
			a.asleep = false
			b.asleep = false
		}
		pushAlong(a, b, ux, uy, pa.0 - a.px, pa.1 - a.py, pb.0 - b.px, pb.1 - b.py, want, Joints.force * j.strength * h)
		// the same turn
		let rel: Double = remainder(b.angle - a.angle - j.base, 2.0 * Double.pi)
		let kk: Double = iia + iib
		if kk > 0 {
			let lam: Double = (-(b.angVel - a.angVel) - Joints.firm * rel / h) / kk
			a.angVel -= lam * iia
			b.angVel += lam * iib
		}
		// across the line: held on it
		pa = a.toWorld(j.pa[0], j.pa[1])
		pb = b.toWorld(j.pb[0], j.pb[1])
		let nx: Double = -uy
		let ny: Double = ux
		let off: Double = (pb.0 - pa.0) * nx + (pb.1 - pa.1) * ny
		pushAlong(a, b, nx, ny, pa.0 - a.px, pa.1 - a.py, pb.0 - b.px, pb.1 - b.py, -Joints.firm * off / h, Double.infinity)
	}

	/// One push between two sections along a direction, so that B moves away from A at `want` along it
	/// there (no harder than `most`)
	func pushAlong(_ a: Vehicle, _ b: Vehicle, _ nx: Double, _ ny: Double, _ rax: Double, _ ray: Double, _ rbx: Double, _ rby: Double, _ want: Double, _ most: Double) {
		let ia: Double = 1.0 / a.mass
		let ib: Double = 1.0 / b.mass
		let iia: Double = 1.0 / a.inertia
		let iib: Double = 1.0 / b.inertia
		let rna: Double = rax * ny - ray * nx
		let rnb: Double = rbx * ny - rby * nx
		let k: Double = ia + ib + rna * rna * iia + rnb * rnb * iib
		if k <= 0 { return }
		let va: Double = (a.vx - a.angVel * ray) * nx + (a.vy + a.angVel * rax) * ny
		let vb: Double = (b.vx - b.angVel * rby) * nx + (b.vy + b.angVel * rbx) * ny
		let lam: Double = clampD((want - (vb - va)) / k, -most, most)
		a.vx -= lam * nx * ia
		a.vy -= lam * ny * ia
		a.angVel -= rna * lam * iia
		b.vx += lam * nx * ib
		b.vy += lam * ny * ib
		b.angVel += rnb * lam * iib
	}

	// MARK: setting joints up

	/// Sets up every joint of a machine as a mech: joints whose section hangs below are hips, the joints
	/// below those knees; legs take turns by where they are along the body; all of them walk
	func autoMech(_ v: Vehicle) {
		let root: Vehicle = machineRoot(v)
		var hips: [VJoint] = []
		for j in root.joints {
			guard let c = vehicleByID(j.child) else { continue }
			if c.b.cy > root.b.cy { hips.append(j) }
		}
		// (from one end of the body to the other, so neighbouring legs take turns)
		hips.sort { (p: VJoint, q: VJoint) in p.cell.dx < q.cell.dx }
		var legIndex: Int = 0
		for j in hips { legIndex = setLeg(root, j, legIndex) }
	}

	/// Makes a joint (and the joints below it) one leg; returns the next leg's number
	func setLeg(_ parent: Vehicle, _ j0: VJoint, _ leg: Int) -> Int {
		guard let i = parent.joints.firstIndex(where: { $0.cell == j0.cell }) else { return leg }
		parent.joints[i].role = JointRole.hip.rawValue
		parent.joints[i].input = JointInput.walk.rawValue
		parent.joints[i].leg = leg % 2
		if parent.joints[i].kind != 1 { return leg + 1 }
		parent.joints[i].lo = -0.45
		parent.joints[i].hi = 0.45
		if let c = vehicleByID(j0.child) {
			for (k, kj) in c.joints.enumerated() where kj.kind == 1 {
				c.joints[k].role = JointRole.knee.rawValue
				c.joints[k].input = JointInput.walk.rawValue
				c.joints[k].leg = leg % 2
				c.joints[k].lo = 0
				c.joints[k].hi = 0.7
			}
		}
		return leg + 1
	}
}

/// Setting up a joint (tap a hinge, servo or piston on a machine): what moves it, how far each way, how
/// fast and how hard, and the part it plays in a walk. AUTO MECH sets up the whole machine to walk.
struct JointPanel: View {
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
		.frame(maxWidth: 660)
		.padding(10)
	}

	var owner: Vehicle? {
		guard let r = game.jointEdit else { return nil }
		return game.vehicleByID(r.vid)
	}

	var index: Int? {
		guard let r = game.jointEdit, let v = owner else { return nil }
		return v.joints.firstIndex { $0.cell == r.cell }
	}

	var joint: VJoint? {
		guard let v = owner, let i = index else { return nil }
		return v.joints[i]
	}

	var title: String {
		guard let j = joint else { return "JOINT" }
		return j.kind == 0 ? "HINGE" : (j.kind == 1 ? "SERVO" : "PISTON")
	}

	var topBar: some View {
		HStack {
			Text(verbatim: title).font(.pixel(20)).foregroundColor(Color(ui: 0xE8C040))
			Spacer()
			SmallButton(title: "AUTO MECH", color: Color(ui: 0x5A4A8A)) { autoMech() }
			SmallButton(title: "DONE", color: Color(ui: 0x3A6A3A)) { close() }
		}
	}

	@ViewBuilder
	var content: some View {
		if let j = joint {
			VStack(alignment: .leading, spacing: 8) {
				Text(verbatim: helpLine(j)).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xB8B0C8))
				if j.kind != 0 { driveSection(j) }
				limitSection(j)
				if j.kind == 1 { walkSection }
			}
		} else {
			Text("This joint is gone.").font(.pixel(13)).foregroundColor(Color(ui: 0xFFE070))
		}
	}

	func helpLine(_ j: VJoint) -> String {
		if j.kind == 0 { return "A hinge lets what is beyond it swing freely between its limits." }
		if j.kind == 2 { return "A piston pushes what is beyond it out and pulls it back, between its limits (in blocks)." }
		return "A servo turns what is beyond it toward where it is told, between its limits (in degrees)."
	}

	func driveSection(_ j: VJoint) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Moved by").font(.pixel(13, .bold))
			ChoiceRows(options: JointInput.allCases.map { $0.name }, selected: intBind(\VJoint.input), columns: 3)
			ModToggle(label: "The other way round", help: "Swaps which way the stick or button moves it", isOn: boolBind(\VJoint.invert))
			if j.kind == 2 {
				StatSlider(label: "Speed (blocks a second)", value: numBind(\VJoint.speed), range: 0.2...6.0, step: 0.1, format: "%.1f")
			} else {
				StatSlider(label: "Speed (degrees a second)", value: degBind(\VJoint.speed), range: 10.0...360.0, step: 5, format: "%.0f")
			}
			StatSlider(label: "Strength (1: its own)", value: numBind(\VJoint.strength), range: 0.2...5.0, step: 0.1, format: "%.1f")
		}
	}

	func limitSection(_ j: VJoint) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("How far").font(.pixel(13, .bold))
			if j.kind == 2 {
				StatSlider(label: "Pulled back to (blocks)", value: numBind(\VJoint.lo), range: 0.0...Joints.maxReach, step: 0.1, format: "%.1f")
				StatSlider(label: "Pushed out to (blocks)", value: numBind(\VJoint.hi), range: 0.0...Joints.maxReach, step: 0.1, format: "%.1f")
			} else {
				StatSlider(label: "One way (degrees)", value: degBind(\VJoint.lo), range: -170.0...0.0, step: 5, format: "%.0f")
				StatSlider(label: "The other way (degrees)", value: degBind(\VJoint.hi), range: 0.0...170.0, step: 5, format: "%.0f")
			}
		}
	}

	var walkSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("In a walk (when moved by Walking)").font(.pixel(13, .bold))
			ChoiceRows(options: JointRole.allCases.map { $0.name }, selected: intBind(\VJoint.role), columns: 4)
			ChoiceRows(options: ["Leg 1", "Leg 2"], selected: intBind(\VJoint.leg), columns: 2)
		}
	}

	// MARK: bindings into the joint

	func update(_ f: (inout VJoint) -> Void) {
		guard let v = owner, let i = index else { return }
		var j: VJoint = v.joints[i]
		f(&j)
		if j.lo > j.hi { j.lo = j.hi }
		j.target = clampD(j.target, j.lo, j.hi)
		v.joints[i] = j
		v.asleep = false
		game.bumpHUD()
	}

	func intBind(_ kp: WritableKeyPath<VJoint, Int>) -> Binding<Int> {
		let me: JointPanel = self
		return Binding<Int>(get: { me.joint?[keyPath: kp] ?? 0 }, set: { (n: Int) in me.update { $0[keyPath: kp] = n } })
	}

	func boolBind(_ kp: WritableKeyPath<VJoint, Bool>) -> Binding<Bool> {
		let me: JointPanel = self
		return Binding<Bool>(get: { me.joint?[keyPath: kp] ?? false }, set: { (b: Bool) in me.update { $0[keyPath: kp] = b } })
	}

	func numBind(_ kp: WritableKeyPath<VJoint, Double>) -> Binding<Double> {
		let me: JointPanel = self
		return Binding<Double>(get: { me.joint?[keyPath: kp] ?? 0 }, set: { (x: Double) in me.update { $0[keyPath: kp] = x } })
	}

	func degBind(_ kp: WritableKeyPath<VJoint, Double>) -> Binding<Double> {
		let me: JointPanel = self
		return Binding<Double>(get: { (me.joint?[keyPath: kp] ?? 0) * 180.0 / Double.pi }, set: { (x: Double) in me.update { $0[keyPath: kp] = x * Double.pi / 180.0 } })
	}

	func autoMech() {
		guard let v = owner else { return }
		game.autoMech(v)
		game.say("Set up to walk: hips swing, knees bend, the legs take turns. Drive it with the stick.", 3.0)
		game.bumpHUD()
	}

	func close() {
		game.showJoint = false
		game.jointEdit = nil
		game.bumpHUD()
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
		case "f": if isDown { actState.held = true } else { actState.stickReleased() }
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
		case "j": if isDown { game.showJournal.toggle() }
		case "r": if isDown { game.startReload() }
		case "q": if isDown { game.cycleWeapon() }
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
	/// swaps in a fresh world (the Mod Test's reset)
	var restart: ((Game) -> Void)? = nil
	@State var dragging: Bool = false
	@State var clock: LoopClock = LoopClock()
	let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

	var body: some View {
		ZStack {
			worldLayer
			if !game.showInventory && !game.showMap && !game.showJournal && !game.showWeather && !game.showPower && !game.showCapture && !game.showModTest && !game.showInfuse && !game.showExo && !game.showJoint && !game.showRadio && !game.dead {
				HUDView(game: game, hud: game.hud)
			}
			if game.showInfuse {
				Color.black.opacity(0.45).ignoresSafeArea()
				GeometryReader { geo in
					InfusionPanel(game: game, hud: game.hud)
						.scaleEffect(min(1.0, min(geo.size.width / 960.0, geo.size.height / 640.0)))
						.frame(width: geo.size.width, height: geo.size.height)
				}
			}
			if game.showExo {
				Color.black.opacity(0.45).ignoresSafeArea()
				// no scroll view (it would fight with dragging): it scales to fit instead
				GeometryReader { geo in
					ExoAssemblyPanel(game: game, hud: game.hud)
						.scaleEffect(min(1.0, min(geo.size.width / 1010.0, geo.size.height / 560.0)))
						.frame(width: geo.size.width, height: geo.size.height)
				}
			}
			if game.showModTest {
				Color.black.opacity(0.45).ignoresSafeArea()
				ModTestPanel(game: game, hud: game.hud, reset: { resetTest() }, exit: quit)
			}
			if game.showJoint {
				Color.black.opacity(0.45).ignoresSafeArea()
				JointPanel(game: game, hud: game.hud)
			}
			if game.showRadio {
				Color.black.opacity(0.45).ignoresSafeArea()
				ReceiverPanel(game: game, hud: game.hud)
			}
			if game.capturing && !game.showCapture && !game.paused { CaptureBar(game: game, hud: game.hud) }
			if game.showCapture {
				Color.black.opacity(0.45).ignoresSafeArea()
				CapturePanel(game: game)
			}
			if game.showWeather {
				Color.black.opacity(0.4).ignoresSafeArea()
				ScrollView {
					WeatherPanel(game: game, hud: game.hud)
				}
			}
			if game.showPower {
				Color.black.opacity(0.4).ignoresSafeArea()
				ScrollView {
					PowerPanel(game: game, hud: game.hud)
				}
			}
			if game.showInventory {
				Color.black.opacity(0.35).ignoresSafeArea()
				// no scroll view around the panel (it would fight with dragging); it scales to fit instead
				GeometryReader { geo in
					InventoryPanel(game: game, hud: game.hud)
						.scaleEffect(min(1.0, min(geo.size.width / 1000.0, geo.size.height / 600.0)))
						.frame(width: geo.size.width, height: geo.size.height)
				}
			}
			if game.showMap {
				Color.black.opacity(0.45).ignoresSafeArea()
				ScrollView {
					MapPanel(game: game, hud: game.hud)
				}
			}
			if game.showJournal {
				Color.black.opacity(0.45).ignoresSafeArea()
				JournalPanel(game: game, hud: game.hud)
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
		.onAppear { Sound.shared.start() }
		.modifier(KeyInput(game: game))
	}

	/// A fresh test world for the mod being tested (read again from the store)
	func resetTest() {
		guard let p = ModStore.pack(game.testMod), let r = restart else { return }
		let ng: Game = ModTest.makeWorld(p, settings: game.settings)
		ng.tilePx = game.tilePx
		ng.say("The test world starts again.", 2.5)
		r(ng)
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
		game.updateInputGate()
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
	/// back to the Mod Creator after a test world
	@State var reopenMods: Bool = false
	@Environment(\.scenePhase) var scenePhase

	var body: some View {
		ZStack {
			if let g = game {
				GameView(game: g, quit: { leave() }, restart: { ng in game = ng })
			} else {
				MenuView(settings: $settings, openMods: reopenMods) { g in
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
			var s: Settings = g.settings
			s.tilePx = g.tilePx
			SettingsStore.save(s)
		}
	}

	func leave() {
		if let g = game {
			_ = g.saveNow()
			// everything changed in game (toggles, camera, zoom) carries back to the menu and is persisted
			settings = g.settings
			settings.tilePx = g.tilePx
			SettingsStore.save(settings)
			if g.mode == .hardcore && g.hardcoreOver { SaveStore.delete(g.slot) }
			reopenMods = !g.testMod.isEmpty
		}
		actState.stickReleased()
		// the weather and engine loops are only kept up by the world's frames: stop them with it
		Sound.shared.silenceLoops()
		game = nil
		ModRuntime.deactivate()
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
