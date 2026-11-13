// PIXEL REALM v2, part 5 of 6: drawing the world, the HUD, panels and menus, and the Mod Creator screens.
// The game is six files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm6.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 1 (a01_artsheet).

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
			c.rotate(by: Angle(radians: rot))
			if flip { c.scaleBy(x: -1, y: 1) }
			let w: Double = tp * 1.02
			if !inPicture {
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

// ===== u03_hud =====

// MARK: - Shared UI pieces

extension Font {
	static func pixel(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
		return Font.system(size: size, weight: weight, design: ThemeRT.design)
	}
}

/// How the game's screens look: the theme of the enabled mods (the last of them that has one). Its
/// colours by role take the place of the game's own (other shades of a role keep their lightness),
/// everything else leans to its tint; it sets the letters, the corners and outlines of buttons and
/// panels, the title screen and the HUD.
enum ThemeRT {
	static var current: ModTheme? = nil
	static var map: [UInt32: UInt32] = [:]
	static var design: Font.Design = .monospaced

	static func set(_ t: ModTheme?) {
		current = t
		var m: [UInt32: UInt32] = [:]
		if let th = t {
			for r in ThemeRole.allCases where r != .tint {
				let c: UInt32 = th.color(r)
				if c == 0 { continue }
				let base: Double = max(1, rgbLight(r.gameColor))
				for g in r.gameColors { m[g] = shadeRGB(c, clampD(rgbLight(g) / base, 0.3, 2.0)) }
			}
		}
		map = m
		switch t?.font ?? 0 {
		case 1: design = .rounded
		case 2: design = .serif
		case 3: design = .default
		default: design = .monospaced
		}
	}

	/// The theme of the enabled mods, read again (at the title screen, and after the Mod Creator)
	static func refresh() {
		var t: ModTheme? = nil
		for e in ModStore.entries() where e.enabled {
			if let th = e.pack?.theme { t = th }
		}
		set(t)
	}

	/// A colour of the game's screens as the theme has it
	static func color(_ hex: UInt32) -> UInt32 {
		guard let t = current else { return hex }
		if let m = map[hex] { return m }
		let tint: UInt32 = t.color(.tint)
		if tint != 0 && t.tintAmt > 0 { return mixRGB(hex, tint, t.tintAmt) }
		return hex
	}

	static var corner: CGFloat { return CGFloat(current?.corner ?? 0) }
	static var outline: Color { return Color(hex: current?.outline ?? 0) }
	static var hudScale: CGFloat { return CGFloat(current?.hudScale ?? 1) }
	static var hudAlpha: Double { return current?.hudAlpha ?? 1 }
	static var swapSides: Bool { return current?.swapSides ?? false }
}

/// How light a colour looks (0...255)
func rgbLight(_ c: UInt32) -> Double {
	let r: Double = Double((c >> 16) & 255)
	let g: Double = Double((c >> 8) & 255)
	let b: Double = Double(c & 255)
	return r * 0.3 + g * 0.59 + b * 0.11
}

extension Color {
	/// A colour of the game's screens (not of the world), as the enabled mods' theme has it
	init(ui hex: UInt32, alpha: Double = 1.0) {
		self.init(hex: ThemeRT.color(hex), alpha: alpha)
	}
}

/// Joins strings without long '+' chains (keeps the type checker fast)
func joinText(_ parts: String...) -> String {
	return parts.joined()
}

func pick(_ on: Bool, _ a: UInt32, _ b: UInt32) -> Color {
	if on { return Color(ui: a) }
	return Color(ui: b)
}

struct PixelBox: View {
	var color: Color = Color(ui: 0x6B6B6B)
	@ViewBuilder
	var body: some View {
		if ThemeRT.corner > 0 { rounded } else { square }
	}

	var square: some View {
		ZStack {
			Rectangle().fill(ThemeRT.outline)
			Rectangle().fill(color).padding(3)
			VStack(spacing: 0) {
				Rectangle().fill(Color.white.opacity(0.3)).frame(height: 3)
				Spacer(minLength: 0)
				Rectangle().fill(Color.black.opacity(0.35)).frame(height: 3)
			}
			.padding(3)
		}
	}

	/// a theme's rounded box: its outline, then the colour
	var rounded: some View {
		let r: CGFloat = ThemeRT.corner
		return ZStack {
			RoundedRectangle(cornerRadius: r).fill(ThemeRT.outline)
			RoundedRectangle(cornerRadius: max(1, r - 2)).fill(color).padding(3)
		}
	}
}

struct PixelButton: View {
	let title: String
	var color: Color = Color(ui: 0x6B6B6B)
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
	var color: Color = Color(ui: 0x6B6B6B)
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
	var color: Color = Color(ui: 0x6B6B6B)
	var onChange: (Bool) -> Void
	@State var pressed: Bool = false
	var fontSize: CGFloat { return size * (label.count > 4 ? 0.2 : 0.3) }
	var fill: Color { return pressed ? Color(ui: 0x3A3A3A) : color }
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

/// One tap to the next weapon: shows the weapon it will switch to
struct WeaponSwapButton: View {
	let stack: Stack
	var action: () -> Void
	var body: some View {
		Button(action: action) {
			ZStack(alignment: .bottomTrailing) {
				Art.shared.icon(stack.item)
					.resizable()
					.frame(width: 34, height: 34)
					.frame(width: 56, height: 56)
				Text("⇄")
					.font(.pixel(14))
					.foregroundColor(Color.white)
					.shadow(color: Color.black, radius: 0, x: 1, y: 1)
					.padding(3)
			}
			.frame(width: 56, height: 56)
			.background(PixelBox(color: Color(ui: 0x5A4A7A)).opacity(0.85))
		}
		.buttonStyle(.plain)
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
						.foregroundColor(Color(ui: 0xFFE080))
						.shadow(color: Color.black, radius: 0, x: 1, y: 1)
						.padding(2)
				}
				if let l = s.inf, !l.isEmpty { infusionMarks(l) }
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

// MARK: - Combat stick

/// The attack stick, on the right beside JUMP. Touch and hold to attack; with the thumb in the middle the
/// game picks the target, and sliding it out aims by hand in any direction (what that means depends on
/// the weapon: see Game.stickAim). Letting go stops. It has its own touch, so it works at the same time
/// as the walking stick and the JUMP button, and releasing one never affects the others.
struct CombatStickView: View {
	let label: String
	var radius: CGFloat = 68
	@State var thumb: CGSize = CGSize.zero
	@State var down: Bool = false
	@State var manual: Bool = false
	var box: CGFloat { return radius * 2 + 34 }

	var body: some View {
		ZStack {
			Canvas { ctx, size in
				CombatStickView.paint(&ctx, size, Double(radius), Double(thumb.width), Double(thumb.height), down, manual)
			}
			.frame(width: box, height: box)
			if !down {
				Text(label).font(.pixel(13)).foregroundColor(Color.white.opacity(0.85))
			}
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
		var dx: Double = Double(p.x) - c
		var dy: Double = Double(p.y) - c
		let len: Double = sqrt(dx * dx + dy * dy)
		if len > r {
			dx = dx / len * r
			dy = dy / len * r
		}
		thumb = CGSize(width: CGFloat(dx), height: CGFloat(dy))
		actState.stickAt(dx / r, dy / r)
		down = true
		manual = actState.manual
	}

	func released() {
		thumb = CGSize.zero
		down = false
		manual = false
		actState.stickReleased()
	}

	/// The dial: a ring with eight notches and the dead zone marked, an arrow toward the thumb while it
	/// aims by hand, and the thumb itself (amber while attacking)
	static func paint(_ ctx: inout GraphicsContext, _ size: CGSize, _ r: Double, _ tx: Double, _ ty: Double, _ down: Bool, _ manual: Bool) {
		let cx: Double = Double(size.width) * 0.5
		let cy: Double = Double(size.height) * 0.5
		let ring: Color = down ? Color(ui: 0xFFC850, alpha: 0.75) : Color(ui: 0xE0B060, alpha: 0.45)
		fillOval(&ctx, mkRect(cx - r, cy - r, r * 2.0, r * 2.0), Color(hex: 0x2A1A0C, alpha: 0.30))
		ctx.stroke(Path(ellipseIn: mkRect(cx - r, cy - r, r * 2.0, r * 2.0)), with: .color(ring), lineWidth: 3)
		let dz: Double = r * ActState.deadIn
		ctx.stroke(Path(ellipseIn: mkRect(cx - dz, cy - dz, dz * 2.0, dz * 2.0)), with: .color(Color.white.opacity(0.22)), lineWidth: 2)
		for k in 0..<8 {
			let a: Double = Double(k) * Double.pi / 4.0
			let c: Double = cos(a)
			let s: Double = sin(a)
			strokeLine(&ctx, cx + c * r * 0.80, cy + s * r * 0.80, cx + c * r * 0.95, cy + s * r * 0.95, Color.white.opacity(0.30), 2)
		}
		if manual {
			let len: Double = sqrt(tx * tx + ty * ty)
			if len > 1.0 {
				let ux: Double = tx / len
				let uy: Double = ty / len
				let arrow: Color = Color(ui: 0xFFE080, alpha: 0.9)
				strokeLine(&ctx, cx + ux * dz, cy + uy * dz, cx + ux * r * 0.78, cy + uy * r * 0.78, arrow, 4)
				var head: Path = Path()
				let bx: Double = cx + ux * r * 0.78
				let by: Double = cy + uy * r * 0.78
				head.move(to: mkPoint(cx + ux * r * 0.98, cy + uy * r * 0.98))
				head.addLine(to: mkPoint(bx - uy * 9.0, by + ux * 9.0))
				head.addLine(to: mkPoint(bx + uy * 9.0, by - ux * 9.0))
				head.closeSubpath()
				ctx.fill(head, with: .color(arrow))
			}
		}
		let tr: Double = 29.0
		let tc: Color = down ? Color(ui: 0xFFC850, alpha: 0.85) : Color.white.opacity(0.5)
		fillOval(&ctx, mkRect(cx + tx - tr, cy + ty - tr, tr * 2.0, tr * 2.0), tc)
		ctx.stroke(Path(ellipseIn: mkRect(cx + tx - tr, cy + ty - tr, tr * 2.0, tr * 2.0)), with: .color(Color.black.opacity(0.35)), lineWidth: 2)
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
		.background(PixelBox(color: Color(ui: 0x2A2A2E)).opacity(0.88))
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
			if !game.wxBanner.isEmpty { weatherBanner.padding(.top, 4) }
			if game.activeBoss != nil { bossBar.padding(.top, 4) }
			if let m = game.message {
				Text(m)
					.font(.pixel(14))
					.foregroundColor(Color.white)
					.multilineTextAlignment(.center)
					.padding(8)
					.background(PixelBox(color: Color(ui: 0x2E2E2E)).opacity(0.9))
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
					.background(PixelBox(color: Color(ui: 0x2E2E2E)).opacity(0.85))
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
						SmallButton(title: "MAP", color: Color(ui: 0x9A7A3A)) { game.showMap = true }
					}
					SmallButton(title: "LOG", color: Color(ui: 0x7A5A2A)) { game.showJournal = true }
					if !game.testMod.isEmpty {
						SmallButton(title: "TEST", color: Color(ui: 0x2E8A8A)) { game.showModTest = true }
					}
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
				if game.totalDefense > 0 {
					HStack(spacing: 4) {
						art.shieldIcon.resizable().frame(width: 16, height: 16)
						OutlinedText(text: String(Int(game.totalDefense.rounded())), size: 12)
					}
				}
				if game.suit.worn { SuitBar(game: game, tick: hud.tick) }
			}
			if !game.activeEffects().isEmpty { EffectStrip(game: game, tick: hud.tick) }
			if let v = game.inVehicle { vehicleReadout(v) }
			if game.mode == .hardcore { OutlinedText(text: "HARDCORE", size: 11, color: Color(ui: 0xFF6060)) }
			if !game.testMod.isEmpty { OutlinedText(text: "MOD TEST · NOT SAVED", size: 11, color: Color(ui: 0x60E0FF)) }
		}
	}

	/// The flight instruments while flying, and a line about the guns and the autopilot
	@ViewBuilder
	func vehicleReadout(_ v: Vehicle) -> some View {
		if v.aero {
			let lines: [String] = game.flightReadout(v)
			ForEach(0..<lines.count, id: \.self) { (i: Int) in
				OutlinedText(text: lines[i], size: 12, color: lines[i] == "STALL!" ? Color(ui: 0xFF5050) : Color(ui: 0xB8F0FF))
			}
		}
		if let st = game.vehicleStatusLine(v) {
			OutlinedText(text: st, size: 11, color: Color(ui: 0xFFE080))
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
			weatherLine
			if let hint = game.wiringHint {
				OutlinedText(text: hint, size: 11, color: Color(ui: 0x9AF0E0))
			}
		}
	}

	/// The weather where the player is: a symbol, its name and the wind (and a barometer's reading
	/// while one is held)
	@ViewBuilder
	var weatherLine: some View {
		if game.world.dim == .overworld && game.settings.weatherOn {
			HStack(spacing: 4) {
				Art.shared.weatherIcon(game.weather.kind, game.wxHere.snow).resizable().frame(width: 16, height: 16)
				OutlinedText(text: weatherText, size: 11)
			}
			if case .gadget(.barometer)? = game.heldItem {
				OutlinedText(text: game.barometerReading(), size: 11, color: Color(ui: 0xE8D090))
			}
		}
	}

	var weatherText: String {
		let w: Double = game.wxHere.wind
		let name: String = game.weatherHereLabel
		if abs(w) < 3.0 { return name }
		return joinText(name, " · wind ", String(Int(abs(w).rounded())), w > 0 ? " →" : " ←")
	}

	var weatherBanner: some View {
		let warn: Bool = game.wxBannerLevel >= 2
		return Text(verbatim: game.wxBanner)
			.font(.pixel(13))
			.foregroundColor(Color.white)
			.multilineTextAlignment(.center)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background(PixelBox(color: warn ? Color(ui: 0xA02020) : Color(ui: 0x8A6A1A)).opacity(0.92))
			.frame(maxWidth: 620)
	}

	var bossBar: some View {
		let fracD: Double = game.bossBarFrac * 356.0
		let barW: CGFloat = CGFloat(fracD)
		return VStack(spacing: 2) {
			OutlinedText(text: game.bossBarName, size: 14, color: Color(ui: 0xFFD060))
			ZStack(alignment: .leading) {
				Rectangle().fill(Color.black.opacity(0.75)).frame(width: 360, height: 14)
				Rectangle().fill(Color(hex: 0xC02828)).frame(width: barW, height: 10).padding(.leading, 2)
			}
			.overlay(Rectangle().stroke(Color.white.opacity(0.7), lineWidth: 2))
		}
	}

	var bottomArea: some View {
		let swap: Bool = ThemeRT.swapSides
		return HStack(alignment: .bottom, spacing: 8) {
			if swap { actionSide } else { moveSide }
			Spacer(minLength: 0)
			VStack(spacing: 6) {
				contextButtons
				OutlinedText(text: game.selectedName, size: 12)
				hotbar
			}
			Spacer(minLength: 0)
			if swap { moveSide } else { actionSide }
		}
		.scaleEffect(ThemeRT.hudScale, anchor: .bottom)
		.opacity(ThemeRT.hudAlpha)
	}

	/// the walking stick
	@ViewBuilder
	var moveSide: some View {
		if game.settings.touchControls { StickView(game: game) }
	}

	/// JUMP, the weapon swap and the attack stick
	@ViewBuilder
	var actionSide: some View {
		if game.settings.touchControls {
			HStack(alignment: .bottom, spacing: 6) {
				VStack(alignment: .trailing, spacing: 8) {
					if let next = game.nextWeaponSlot(), let st = game.inv.slots[next] {
						WeaponSwapButton(stack: st) { game.cycleWeapon() }
					}
					HoldButton(label: "JUMP", size: 82, color: Color(ui: 0x4E8A3E)) { down in game.jumpHeld = down }
				}
				CombatStickView(label: game.useLabel)
			}
		}
	}

	var contextButtons: some View {
		HStack(spacing: 6) {
			if game.canToggleWall {
				SmallButton(title: game.wallMode ? "AS WALL" : "AS BLOCK", color: game.wallMode ? Color(ui: 0x6A5A8A) : Color(ui: 0x4E6A3E)) { game.toggleWallMode() }
			}
			if game.canBuildOnVehicle {
				SmallButton(title: game.vehicleBuild ? "ON VEHICLE" : "IN WORLD", color: game.vehicleBuild ? Color(ui: 0x2E7A8A) : Color(ui: 0x4E6A3E)) { game.toggleVehicleBuild() }
			}
			if game.inVehicle != nil { vehicleButtons }
			if game.vehicleNearby != nil {
				SmallButton(title: "DRIVE", color: Color(ui: 0x4E8A3E)) { game.driveNearby() }
				SmallButton(title: "PACK UP", color: Color(ui: 0x6A5A2A)) { game.packUpVehicle() }
			}
			if game.mounted != nil || game.inVehicle != nil {
				SmallButton(title: "DISMOUNT", color: Color(ui: 0xA03030)) { game.dismount() }
			}
			if let s = game.heldStack, case .gun(let gt) = s.item {
				if game.reloadT > 0 {
					OutlinedText(text: gt.isBoltThrower && gt.magazine == 1 ? "COCKING" : "RELOADING", size: 12, color: Color(ui: 0xFFE080))
				} else if gt == .stormRod {
					if s.extra < gt.magazine { OutlinedText(text: "CHARGING", size: 12, color: Color(ui: 0xB8E0FF)) }
				} else if s.extra < gt.magazine {
					SmallButton(title: "RELOAD", color: Color(ui: 0x6A5A2A)) { game.startReload() }
				}
			}
			if game.flying || game.noclip {
				HoldButton(label: "▼", size: 44) { down in game.downHeld = down }
			}
		}
	}

	/// While driving: turn round, and the autopilot's buttons when the vehicle has one
	@ViewBuilder
	var vehicleButtons: some View {
		SmallButton(title: "TURN", color: Color(ui: 0x3A6AA8)) { game.turnVehicle() }
		if let v = game.inVehicle, v.autopilots > 0 {
			SmallButton(title: "AUTO", color: v.auto == 0 ? Color(ui: 0x5A5A64) : Color(ui: 0x2E8A5A)) { game.cycleAutopilot() }
			SmallButton(title: "MARK", color: Color(ui: 0x6A5A2A)) { game.markWaypoint() }
			if !v.route.isEmpty {
				SmallButton(title: "CLEAR", color: Color(ui: 0x7A3A3A)) { game.clearRoute() }
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
			// the bag opens from the end of the hotbar (replaces the old BAG text button)
			Button {
				game.showInventory = true
				game.bumpHUD()
			} label: {
				ZStack {
					Rectangle().fill(Color(hex: 0x3E5A7A, alpha: 0.85))
					Art.shared.icon(.block(.chest)).resizable().frame(width: 26, height: 26)
					Text("BAG").font(.pixel(8)).foregroundColor(Color.white).offset(y: 14)
				}
				.frame(width: 40, height: 40)
				.overlay(Rectangle().stroke(Color(hex: 0xA0C0E0), lineWidth: 1))
			}
			.buttonStyle(.plain)
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

/// Where each slot sits on screen (in the panel's "inv" space), so a drag can find what it was dropped on.
/// Filled while the slots lay out; a plain reference box keeps it out of SwiftUI state updates.
final class SlotFrames: @unchecked Sendable {
	var map: [Game.SlotRef: CGRect] = [:]

	func target(at p: CGPoint) -> Game.SlotRef? {
		for (k, r) in map where r.contains(p) { return k }
		return nil
	}
}

/// Every item, with a search box and groups to narrow it down: the creative palette and the debug menu's
/// give. Tapping an item calls `tap`; the selected one is ringed.
struct ItemBrowser: View {
	let items: [Item]
	@Binding var search: String
	@Binding var group: Int
	var selected: Item? = nil
	var height: CGFloat = 300
	var tap: (Item) -> Void

	static let groups: [String] = ["ALL", "BLOCKS", "TOOLS", "WEAPONS", "ARMOR", "MATERIALS", "FOOD", "OTHER"]

	var body: some View {
		let list: [Item] = ItemBrowser.filter(items, search, group)
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 40, maximum: 44), spacing: 3)]
		return VStack(alignment: .leading, spacing: 6) {
			TextField("Search items by name", text: $search)
				.font(.pixel(13, .bold))
				.foregroundColor(Color.white)
				.padding(8)
				.background(Color.black.opacity(0.5))
			groupRow
			Text(verbatim: joinText(String(list.count), list.count == 1 ? " item" : " items")).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.6))
			ScrollView {
				LazyVGrid(columns: cols, spacing: 3) {
					ForEach(0..<list.count, id: \.self) { (i: Int) in self.cell(list[i]) }
				}
			}
			.frame(height: height)
		}
	}

	var groupRow: some View {
		VStack(alignment: .leading, spacing: 3) {
			HStack(spacing: 3) {
				ForEach(0..<4, id: \.self) { (i: Int) in self.groupButton(i) }
			}
			HStack(spacing: 3) {
				ForEach(4..<ItemBrowser.groups.count, id: \.self) { (i: Int) in self.groupButton(i) }
			}
		}
	}

	func groupButton(_ i: Int) -> some View {
		let on: Bool = group == i
		let col: Color = on ? Color(ui: 0x4E8A3E) : Color(ui: 0x555555)
		return SmallButton(title: ItemBrowser.groups[i], color: col) { self.group = i }
	}

	func cell(_ it: Item) -> some View {
		let on: Bool = selected == it
		return SlotView(stack: Stack(item: it, count: 1), selected: on, size: 40)
			.onTapGesture { self.tap(it) }
	}

	/// The items matching a search (by name) and a group (0: all)
	static func filter(_ items: [Item], _ search: String, _ group: Int) -> [Item] {
		let q: String = search.trimmingCharacters(in: .whitespaces).lowercased()
		var out: [Item] = []
		for it in items {
			if group > 0 && it.bagGroup != group - 1 { continue }
			if !q.isEmpty && !it.name.lowercased().contains(q) { continue }
			out.append(it)
		}
		return out
	}
}

struct InventoryPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var cat: RecipeCat = .basic
	@State var creativeTab: Bool = false
	@State var onlyCraftable: Bool = false
	/// the bag filter (ItemBrowser.groups; 0 shows everything)
	@State var bagGroup: Int = 0
	/// an item picked in the creative palette or the crafting list, to read about without taking it
	@State var infoItem: Item? = nil
	@State var infoRecipe: Int = -1
	@State var search: String = ""
	@State var paletteGroup: Int = 0
	// drag and drop
	@State var dragFrom: Game.SlotRef? = nil
	@State var dragPoint: CGPoint = .zero
	@State var hoverRef: Game.SlotRef? = nil
	@State var frames: SlotFrames = SlotFrames()

	var body: some View {
		ZStack(alignment: .topLeading) {
			VStack(spacing: 8) {
				header
				HStack(alignment: .top, spacing: 12) {
					leftColumn
					rightColumn
				}
			}
			.foregroundColor(Color.white)
			.padding(14)
			.background(PixelBox(color: Color(ui: 0x2C2C30)).opacity(0.97))
			// the stack being dragged follows the finger
			if let f = dragFrom, let s = game.stackAt(f) {
				SlotView(stack: s, size: 44)
					.opacity(0.9)
					.position(x: dragPoint.x, y: dragPoint.y)
					.allowsHitTesting(false)
			}
		}
		.coordinateSpace(name: "inv")
		.frame(maxWidth: 1000)
		.padding(10)
		.onAppear {
			switch game.craftStation {
			case .still: cat = .alchemy
			case .infuser: cat = .infusion
			case .assembly: cat = .exosuit
			default: break
			}
		}
	}

	/// A slot that can be tapped (pick up / place), long-pressed, hovered for info, and dragged
	func dragSlot(_ ref: Game.SlotRef, _ stack: Stack?, size: CGFloat, selected: Bool = false, tap: @escaping () -> Void, hold: @escaping () -> Void) -> some View {
		let box: SlotFrames = frames
		let g: Game = game
		return SlotView(stack: stack, selected: selected, size: size)
			.background(GeometryReader { gp -> Color in
				box.map[ref] = gp.frame(in: .named("inv"))
				return Color.clear
			})
			.opacity(dragFrom == ref ? 0.35 : 1.0)
			.onTapGesture {
				hoverRef = ref
				tap()
			}
			.onLongPressGesture(minimumDuration: 0.35) { hold() }
			.onHover { inside in if inside { hoverRef = ref } }
			.gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("inv"))
				.onChanged { v in
					if dragFrom == nil {
						if g.carry != nil || g.stackAt(ref) == nil { return }
						dragFrom = ref
						hoverRef = ref
					}
					dragPoint = v.location
				}
				.onEnded { v in
					if let from = dragFrom {
						g.dragStack(from: from, to: box.target(at: v.location))
					}
					dragFrom = nil
				})
	}

	/// Drop zone: dragging a stack here throws it out into the world
	var dropZone: some View {
		let box: SlotFrames = frames
		let active: Bool = dragFrom != nil
		return Text(active ? "DROP HERE" : "DROP")
			.font(.pixel(11))
			.foregroundColor(Color.white.opacity(active ? 1.0 : 0.6))
			.frame(width: 84, height: 36)
			.background(Color(ui: active ? 0x7A3A2A : 0x3A2E2A).opacity(0.9))
			.overlay(Rectangle().stroke(Color(hex: 0xA06A2A), lineWidth: active ? 2 : 1))
			.background(GeometryReader { gp -> Color in
				box.map[.drop] = gp.frame(in: .named("inv"))
				return Color.clear
			})
			.onTapGesture { game.dropCarried() }
	}

	/// Name and details of the item picked in a list, else of the slot last touched or hovered
	var infoBox: some View {
		let s: Stack? = hoverRef.flatMap { game.stackAt($0) } ?? game.carry
		return VStack(alignment: .leading, spacing: 2) {
			if let it = infoItem {
				pickedInfo(it)
			} else if let st = s {
				Text(verbatim: st.count > 1 ? joinText(st.item.name, "  x", String(st.count)) : st.item.name).font(.pixel(12))
				Text(verbatim: st.item.infoLines.joined(separator: " · ")).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.75))
				if !st.infusionNames.isEmpty {
					Text(verbatim: joinText("Infused: ", st.infusionNames.joined(separator: ", "))).font(.pixel(10, .semibold)).foregroundColor(Color(ui: 0xC07CFF))
				}
			} else {
				Text("Tap or hover an item to see what it does.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.55))
			}
		}
		.frame(maxWidth: 460, minHeight: 34, alignment: .leading)
		.padding(.horizontal, 6)
		.background(Color.black.opacity(0.25))
	}

	/// An item picked in the creative palette or the crafting list: what it is, and for a recipe what it
	/// takes (and how many of each the bag holds)
	func pickedInfo(_ it: Item) -> some View {
		let lines: String = it.infoLines.joined(separator: " · ")
		let need: String = recipeNeeds()
		return VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(verbatim: it.name).font(.pixel(12))
				Spacer()
				SmallButton(title: "OK") { self.infoItem = nil; self.infoRecipe = -1 }
			}
			if !lines.isEmpty { Text(verbatim: lines).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.75)) }
			if !need.isEmpty { Text(verbatim: need).font(.pixel(10, .semibold)).foregroundColor(Color(ui: 0xFFE070)) }
		}
	}

	func recipeNeeds() -> String {
		guard infoRecipe >= 0, let r = RecipeBook.all.first(where: { $0.id == infoRecipe }) else { return "" }
		var parts: [String] = []
		for c in r.cost {
			parts.append(joinText(String(c.n), " ", c.item.name, " (have ", String(game.inv.total(c.item)), ")"))
		}
		var s: String = joinText("Needs: ", parts.joined(separator: ", "))
		if !game.recipeStationOK(r) { s = joinText(s, ". At a ", game.recipeStationName(r), ".") }
		return s
	}

	var titleText: String {
		if let p = game.openChest, game.isCargoSpot(p) { return "INVENTORY  ·  CARGO" }
		if let p = game.openChest, game.isPackSpot(p) { return "INVENTORY  ·  SUIT PACK" }
		if game.openChest != nil { return "INVENTORY  ·  CHEST" }
		return "INVENTORY"
	}

	var header: some View {
		HStack {
			Text(verbatim: titleText).font(.pixel(18))
			Spacer()
			if game.isCreative && game.openChest == nil {
				SmallButton(title: creativeTab ? "CRAFTING" : "ALL ITEMS", color: Color(ui: 0x3E6FAA)) { creativeTab.toggle() }
			}
			SmallButton(title: "SORT", color: Color(ui: 0x4E6A8A)) { game.sortBag() }
			SmallButton(title: "STACK", color: Color(ui: 0x4E6A8A)) { game.stackAll() }
			if game.openChest != nil {
				SmallButton(title: "QUICK STACK", color: Color(ui: 0x4E8A3E)) { game.quickStack() }
			}
			SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { close() }
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
			bagFilter
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
			infoBox
			Text(verbatim: holdHint)
				.font(.pixel(10, .semibold))
				.foregroundColor(Color.white.opacity(0.7))
		}
	}

	/// Show only one kind of item in the bag (the others dim, so nothing moves)
	var bagFilter: some View {
		HStack(spacing: 3) {
			ForEach(0..<ItemBrowser.groups.count, id: \.self) { (i: Int) in self.filterChip(i) }
		}
	}

	func filterChip(_ i: Int) -> some View {
		let on: Bool = bagGroup == i
		let col: Color = on ? Color(ui: 0x4E8A3E) : Color(ui: 0x4A4A50)
		return Button(action: { self.bagGroup = i }) {
			Text(verbatim: ItemBrowser.groups[i]).font(.pixel(9, .bold)).foregroundColor(Color.white)
				.padding(.horizontal, 5).padding(.vertical, 5)
				.background(col)
		}
		.buttonStyle(.plain)
	}

	/// whether a slot's stack is outside the bag filter (it is drawn dim)
	func filteredOut(_ s: Stack?) -> Bool {
		guard bagGroup > 0, let st = s else { return false }
		return st.item.bagGroup != bagGroup - 1
	}

	var holdHint: String {
		let tail: String = game.openChest != nil ? "move to chest." : "split stack, equip armor."
		return joinText("Drag to move, swap or stack (onto DROP to throw away). Tap: pick up / place. Hold: ", tail)
	}

	func invSlot(_ i: Int) -> some View {
		let isHot: Bool = i < Inventory.hotbarCount
		let selected: Bool = isHot && game.sel == i
		let ring: Color = isHot ? Color(ui: 0xFFE070, alpha: 0.35) : Color.clear
		let dimmed: Bool = filteredOut(game.inv.slots[i])
		return dragSlot(.inv(i), game.inv.slots[i], size: 40, selected: selected, tap: { game.tapSlot(i) }, hold: { longPress(i) })
			.overlay(Rectangle().stroke(ring, lineWidth: 1))
			.opacity(dimmed ? 0.25 : 1.0)
	}

	func longPress(_ i: Int) {
		if let p = game.openChest {
			game.chestStore(p.x, p.y, i)
			return
		}
		if let s = game.inv.slots[i] {
			switch s.item {
			case .armor, .gear:
				game.quickEquip(i)
				return
			default: break
			}
		}
		game.splitSlot(i)
	}

	var armorColumn: some View {
		let names: [String] = ["Head", "Body", "Legs", "Gear", "Gear"]
		let n: Int = min(names.count, game.inv.armor.count)
		return HStack(alignment: .top, spacing: 4) {
			VStack(spacing: 4) {
				ForEach(0..<min(3, n), id: \.self) { i in
					equipSlot(i, names[i])
				}
				HStack(spacing: 2) {
					Art.shared.shieldIcon.resizable().frame(width: 14, height: 14)
					Text(String(Int(game.inv.defense.rounded()))).font(.pixel(11))
				}
			}
			VStack(spacing: 4) {
				ForEach(min(3, n)..<n, id: \.self) { i in
					equipSlot(i, names[i])
				}
			}
		}
	}

	func equipSlot(_ i: Int, _ name: String) -> some View {
		VStack(spacing: 1) {
			dragSlot(.armor(i), game.inv.armor[i], size: 40, tap: { game.tapArmorSlot(i) }, hold: {})
			Text(name).font(.pixel(9, .bold)).foregroundColor(Color.white.opacity(0.7))
		}
	}

	var carryBar: some View {
		HStack(spacing: 8) {
			if let c = game.carry {
				SlotView(stack: c, size: 36)
				Text(verbatim: joinText("Holding ", c.item.name)).font(.pixel(12))
				Spacer()
				SmallButton(title: "PUT BACK") { game.returnCarried() }
			} else {
				Text("Hand empty").font(.pixel(11, .semibold)).foregroundColor(Color.white.opacity(0.6))
				Spacer()
			}
			if game.isCreative { returnZone }
			dropZone
		}
		.frame(height: 40)
	}

	/// Creative mode: drag a stack here (or tap while holding one) to put it back in the creative menu
	var returnZone: some View {
		let box: SlotFrames = frames
		let active: Bool = dragFrom != nil
		return Text(active ? "RETURN HERE" : "RETURN")
			.font(.pixel(11))
			.foregroundColor(Color.white.opacity(active ? 1.0 : 0.6))
			.frame(width: 96, height: 36)
			.background(Color(ui: active ? 0x2A4A7A : 0x2A344A).opacity(0.9))
			.overlay(Rectangle().stroke(Color(hex: 0x5A8AD0), lineWidth: active ? 2 : 1))
			.background(GeometryReader { gp -> Color in
				box.map[.trash] = gp.frame(in: .named("inv"))
				return Color.clear
			})
			.onTapGesture { game.discardCarried() }
	}

	@ViewBuilder
	var rightColumn: some View {
		if let p = game.openChest {
			chestGrid(p.x, p.y)
		} else if creativeTab && game.isCreative {
			creativePalette
		} else {
			craftingList
		}
	}

	var creativePalette: some View {
		let items: [Item] = game.creativeItems()
		return VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 6) {
				Text("ALL ITEMS").font(.pixel(15))
				Spacer()
				if let it = infoItem {
					SmallButton(title: "TAKE 1", color: Color(ui: 0x4E8A3E)) { game.giveItem(it, 1, extra: game.gunLoad(it)) }
					SmallButton(title: "TAKE STACK", color: Color(ui: 0x4E8A3E)) { game.creativeGive(it) }
				}
			}
			Text("Tap an item to read about it, tap it again to take a stack. Put things back with RETURN.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.7))
			ItemBrowser(items: items, search: $search, group: $paletteGroup, selected: infoItem, height: 260, tap: { (it: Item) in self.paletteTap(it) })
		}
		.frame(minWidth: 280, maxWidth: 420)
	}

	func paletteTap(_ it: Item) {
		if infoItem == it {
			game.creativeGive(it)
		} else {
			infoItem = it
			infoRecipe = -1
		}
	}

	var stationText: String {
		var s: [String] = ["Hand"]
		if game.stationAvailable(.bench) { s.append("Workbench") }
		if game.stationAvailable(.furnace) { s.append("Furnace") }
		else if game.stationAvailable(.campfire) { s.append("Campfire") }
		for st in [Station.anvil, .tinker, .forge] where game.stationAvailable(st) { s.append(st.name) }
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

	/// A crafting row with what the bag holds of each ingredient worked out here: the row redraws as soon
	/// as the bag changes (pick up, use, craft, drop, move)
	func recipeRow(_ r: Recipe) -> RecipeRow {
		let rid: Int = r.id
		var row: RecipeRow = RecipeRow.live(game, r)
		row.picked = infoRecipe == rid
		row.info = {
			self.infoItem = r.out
			self.infoRecipe = rid
		}
		return row
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
					ForEach(RecipeCat.allCases.filter { $0 != .mods || ModRuntime.shared.recipes.contains { r in r.cat == .mods } }, id: \.self) { c in
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
					ForEach(list) { (r: Recipe) in self.recipeRow(r) }
				}
			}
			.frame(maxHeight: 330)
		}
		.frame(minWidth: 300, maxWidth: 440)
	}
}

/// One recipe in the crafting list. What the bag holds of each ingredient, and whether it can be made,
/// come in from the panel as plain values, so the row redraws whenever they change.
struct RecipeRow: View {
	let game: Game
	let recipe: Recipe
	let have: [Int]
	let ok: Bool
	let stationOK: Bool
	var picked: Bool = false
	var info: () -> Void = {}

	/// A row with what the bag holds worked out now
	static func live(_ game: Game, _ r: Recipe) -> RecipeRow {
		var have: [Int] = []
		for c in r.cost { have.append(game.inv.total(c.item)) }
		return RecipeRow(game: game, recipe: r, have: have, ok: game.canCraft(r), stationOK: game.recipeStationOK(r))
	}

	var body: some View {
		return HStack(spacing: 6) {
			SlotView(stack: Stack(item: recipe.out, count: recipe.outCount), selected: picked, size: 34)
				.onTapGesture { self.info() }
			VStack(alignment: .leading, spacing: 2) {
				Text(recipe.out.name).font(.pixel(12)).lineLimit(1)
				HStack(spacing: 4) {
					ForEach(0..<recipe.cost.count, id: \.self) { (k: Int) in
						self.costView(recipe.cost[k], k < have.count ? have[k] : 0)
					}
				}
				if !stationOK {
					Text(verbatim: joinText("Needs ", game.recipeStationName(recipe))).font(.pixel(9, .bold)).foregroundColor(Color(ui: 0xFF8A60))
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

	/// An ingredient: its icon, then what the bag holds out of what it takes ("3/5")
	func costView(_ c: CostLine, _ held: Int) -> some View {
		let enough: Bool = held >= c.n || game.isCreative
		let text: String = joinText(String(min(held, 999)), "/", String(c.n))
		return HStack(spacing: 1) {
			Art.shared.icon(c.item).resizable().frame(width: 16, height: 16)
			Text(verbatim: text).font(.pixel(10)).foregroundColor(pick(enough, 0xFFFFFF, 0xFF6060))
		}
	}
}

/// The open chest, shown beside the bag; its slots take part in drag and drop like the bag's
extension InventoryPanel {
	func chestGrid(_ cx: Int, _ cy: Int) -> some View {
		let items: [Stack] = game.world.chestItems(cx, cy)
		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text("CHEST").font(.pixel(15))
				Spacer()
				SmallButton(title: "TAKE ALL", color: Color(ui: 0x4E8A3E)) { takeAll(cx, cy) }
			}
			VStack(spacing: 3) {
				ForEach(0..<3, id: \.self) { r in
					HStack(spacing: 3) {
						ForEach(0..<9, id: \.self) { c in
							chestSlot(cx, cy, r * 9 + c, items)
						}
					}
				}
			}
			Text("Drag between chest and bag. Tap: take / put the held stack. Hold: move into your bag.").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.7))
		}
	}

	func chestSlot(_ cx: Int, _ cy: Int, _ i: Int, _ items: [Stack]) -> some View {
		let s: Stack? = i < items.count ? items[i] : nil
		let g: Game = game
		return dragSlot(.chest(i), s, size: 40, tap: { g.chestTapSlot(cx, cy, i) }, hold: { g.chestQuickMove(cx, cy, i) })
	}

	func takeAll(_ cx: Int, _ cy: Int) {
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


// MARK: - Journal panel

let parchment: UInt32 = 0xE8D4A0
let parchmentInk: UInt32 = 0x3A2410

struct JournalPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var tab: Int = 0
	var body: some View {
		let ink: Color = Color(ui: parchmentInk)
		return VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 6) {
				Text("JOURNAL").font(.pixel(18)).foregroundColor(Color(ui: 0x4A2A10))
				Spacer()
				tabButton(0, "GOALS")
				tabButton(1, "PLACES")
				tabButton(2, "LORE")
				tabButton(3, "WEATHER")
				SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { game.showJournal = false }
			}
			ScrollView {
				VStack(alignment: .leading, spacing: 8) {
					switch tab {
					case 0: aims(ink)
					case 1: places(ink)
					case 2: lore(ink)
					default: WeatherJournalPage(game: game, ink: ink)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.frame(maxHeight: 380)
		}
		.padding(16)
		.background(Color(ui: parchment))
		.overlay(Rectangle().stroke(Color(hex: 0x5A3A1A), lineWidth: 4))
		.frame(maxWidth: 820)
		.padding(16)
	}

	func tabButton(_ i: Int, _ title: String) -> some View {
		SmallButton(title: title, color: i == tab ? Color(ui: 0x7A5A2A) : Color(ui: 0xA8906C)) { tab = i }
	}

	func aims(_ ink: Color) -> some View {
		let list: [JournalAim] = game.journalAims()
		return VStack(alignment: .leading, spacing: 7) {
			ForEach(0..<list.count, id: \.self) { i in
				HStack(alignment: .top, spacing: 8) {
					Text(list[i].done ? "✓" : "○").font(.pixel(14)).foregroundColor(list[i].done ? Color(ui: 0x2A6A2A) : ink)
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: list[i].title).font(.pixel(13)).foregroundColor(list[i].done ? Color(ui: 0x6A5A40) : ink)
						if !list[i].done {
							Text(verbatim: list[i].hint).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x6A4A2A))
						}
					}
				}
			}
		}
	}

	func places(_ ink: Color) -> some View {
		let ps: [JournalPlace] = game.journal.places
		return VStack(alignment: .leading, spacing: 6) {
			if ps.isEmpty {
				Text("Nothing yet. The world is wide: ruins, old mines and stranger places are out there.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<ps.count, id: \.self) { i in
				HStack {
					Text(verbatim: ps[i].name).font(.pixel(13)).foregroundColor(ink)
					Spacer()
					Text(verbatim: placeWhere(ps[i])).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x6A4A2A))
				}
			}
		}
	}

	func placeWhere(_ p: JournalPlace) -> String {
		let start: Int = game.gen.spawnX
		let d: Int = p.x - start
		let side: String = abs(d) < 30 ? "by your first camp" : (roughDistance(abs(d)) + (d > 0 ? " east" : " west") + " of your start")
		return (p.dim == 1 ? "Umbral, " : "") + side + ", day " + String(p.day)
	}

	func lore(_ ink: Color) -> some View {
		let keys: [String] = game.journal.lore.filter { !$0.hasPrefix("wx.") }
		return VStack(alignment: .leading, spacing: 10) {
			if keys.isEmpty {
				Text("Places you find will tell you something. Their stories collect here.").font(.pixel(12, .semibold)).foregroundColor(ink)
			}
			ForEach(0..<keys.count, id: \.self) { i in
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: loreEntry(keys[i]).0).font(.pixel(13)).foregroundColor(ink)
					Text(verbatim: loreEntry(keys[i]).1).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x5A3A1A))
				}
			}
		}
	}
}

struct MapPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	var body: some View {
		let map: TreasureMap = game.treasureMap()
		return VStack(spacing: 8) {
			HStack {
				Text("TREASURE MAP").font(.pixel(18)).foregroundColor(Color(ui: 0x4A2A10))
				Spacer()
				SmallButton(title: "CLOSE", color: Color(ui: 0xA03030)) { game.showMap = false }
			}
			Canvas { ctx, size in
				MapDrawer.draw(&ctx, size, map, game)
			}
			.frame(height: 260)
			.overlay(Rectangle().stroke(Color(hex: 0x7A5A2A), lineWidth: 3))
			VStack(alignment: .leading, spacing: 4) {
				ForEach(0..<map.clues.count, id: \.self) { i in
					Text(verbatim: joinText("• ", map.clues[i])).font(.pixel(12, .bold)).foregroundColor(Color(ui: 0x3A2410))
				}
				if game.inv.total(.gadget(.portalKey)) > 0 && game.world.dim == .overworld {
					Text(verbatim: joinText("Key: ", game.portalHintText(game.portalHintLevel())))
						.font(.pixel(12, .heavy)).foregroundColor(Color(ui: 0x6A2AB0))
				}
				if game.portalOpened {
					Text("The gate has been opened.").font(.pixel(12, .heavy)).foregroundColor(Color(ui: 0x2A6A2A))
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(16)
		.background(Color(ui: 0xE8D4A0))
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
		let water: Color = Color(ui: 0x7AA4C8)
		let soil: Color = Color(ui: 0xB89868)
		let rock: Color = Color(ui: 0xA8906C)
		let deep: Color = Color(ui: 0x988060)
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
		let lineCol: Color = Color(ui: 0x7A5A3A, alpha: 0.35)
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
			var col: Color = Color(ui: 0x3A2410)
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
			case 5:
				sym = "▼"
				col = Color(hex: 0x7A4A20)
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
		return joinText(game.worldName, " · ", game.mode.title, kind, game.gen.options.flat ? " · Flat" : "")
	}
	var quit: () -> Void
	@State var savedNote: String = ""
	var body: some View {
		ZStack {
			Color.black.opacity(0.6).ignoresSafeArea()
			// scrolls on short screens now that the camera options live here too
			ScrollView {
			VStack(spacing: 12) {
				Text("PAUSED").font(.pixel(30)).foregroundColor(Color.white)
				Text(verbatim: worldLine)
					.font(.pixel(12, .bold)).foregroundColor(Color.white.opacity(0.8))
				PixelButton(title: "RESUME", color: Color(ui: 0x4E8A3E)) {
					// settings changed here are kept on the device straight away
					SettingsStore.save(game.settings)
					game.paused = false
				}
				if game.testMod.isEmpty {
					PixelButton(title: "SAVE GAME", color: Color(ui: 0x3E6FAA)) {
						savedNote = game.saveNow() ? "Saved!" : "Could not save."
					}
				} else {
					Text("A mod test world: nothing is saved.").font(.pixel(12, .bold)).foregroundColor(Color(ui: 0x60E0FF))
					PixelButton(title: "TEST TOOLS", color: Color(ui: 0x2E8A8A)) {
						game.paused = false
						game.showModTest = true
					}
				}
				PixelButton(title: "CAPTURE STRUCTURE", color: Color(ui: 0x2E8A8A)) {
					game.paused = false
					game.startCapture()
				}
				toggles
				CameraSettingsSection(settings: settingsBinding, onChange: { game.tilePx = game.settings.tilePx })
				WeatherSettingsSection(settings: settingsBinding, onChange: { game.bumpHUD() })
				NightSettingsSection(settings: settingsBinding)
				PixelButton(title: game.testMod.isEmpty ? "SAVE & QUIT" : "EXIT TEST", color: Color(ui: 0xA03030)) { quit() }
				if !savedNote.isEmpty { Text(savedNote).font(.pixel(12)).foregroundColor(Color.white) }
			}
			.frame(maxWidth: 340)
			.padding()
			}
		}
	}

	var settingsBinding: Binding<Settings> {
		let g: Game = game
		return Binding<Settings>(get: { g.settings }, set: { v in
			g.settings = v
			g.bumpHUD()
		})
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
			Color(ui: 0x700000, alpha: 0.45).ignoresSafeArea()
			VStack(spacing: 12) {
				Text(verbatim: deathTitle).font(.pixel(34)).foregroundColor(Color.white)
					.shadow(color: Color.black, radius: 0, x: 3, y: 3)
				Text(verbatim: joinText("Kills: ", String(game.kills), "   Days: ", String(game.dayCount))).font(.pixel(14)).foregroundColor(Color.white)
				if game.mode == .hardcore {
					Text("This hardcore world has been deleted.").font(.pixel(12, .bold)).foregroundColor(Color.white)
				} else {
					PixelButton(title: "RESPAWN", color: Color(ui: 0x4E8A3E)) { game.respawn() }
				}
				PixelButton(title: "MAIN MENU", color: Color(ui: 0xA03030)) { quit() }
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
	@State var confirmDelete: Bool = false
	@State var includeVehicles: Bool = false
	@State var tpX: String = ""
	@State var tpY: String = ""
	@State var showPerf: Bool = true
	@State var showSystems: Bool = false
	@State var showWorld: Bool = false
	@State var showGive: Bool = false
	@State var giveSearch: String = ""
	@State var giveGroup: Int = 0
	@State var giveItem: Item? = nil
	@State var giveCount: Int = 1
	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("DEBUG").font(.pixel(16)).foregroundColor(Color(ui: 0xFFE066))
					Spacer()
					SmallButton(title: "X", color: Color(ui: 0xA03030)) { game.showDebug = false }
				}
				stats
				toggles
				VStack(alignment: .leading, spacing: 4) {
					Text(verbatim: joinText("Speed x", String(format: "%.1f", game.speedMult))).font(.pixel(11, .semibold))
					Slider(value: $game.speedMult, in: 0.5...4.0, step: 0.5)
				}
				actions
				entitySection
				multiplierSection
				hazardSection
				weatherSection
				nightSection
				powerSection
				if showPerf { perfSection }
				SmallButton(title: showSystems ? "Hide systems" : "Systems...") { showSystems.toggle() }
				if showSystems { systemsSection }
				SmallButton(title: showWorld ? "Hide worldgen" : "Worldgen...") { showWorld.toggle() }
				if showWorld { worldSection }
				SmallButton(title: showGive ? "Hide give item" : "Give item...") { showGive.toggle() }
				if showGive { giveSection }
				section("SPAWN MOB")
				spawnGrid
			}
			.font(.pixel(12, .bold))
			.foregroundColor(Color.white)
			.padding(12)
		}
		.background(PixelBox(color: Color(ui: 0x1E1E1E)).opacity(0.94))
	}

	static let giveCounts: [Int] = [1, 10, 64, 100, 500]

	/// Any item of the game or of the world's mods, found by name or group, as many as wanted
	var giveSection: some View {
		let items: [Item] = game.creativeItems()
		let title: String = giveItem.map { joinText("GIVE ", String(giveCount), " ", $0.name) } ?? "Pick an item"
		return VStack(alignment: .leading, spacing: 6) {
			section("GIVE ITEM")
			ItemBrowser(items: items, search: $giveSearch, group: $giveGroup, selected: giveItem, height: 220, tap: { (it: Item) in self.giveItem = it })
			HStack(spacing: 4) {
				ForEach(0..<DebugPanel.giveCounts.count, id: \.self) { (i: Int) in self.countButton(DebugPanel.giveCounts[i]) }
			}
			SmallButton(title: title, color: Color(ui: 0x4E8A3E)) {
				if let it = self.giveItem { self.game.debugGive(it, self.giveCount) }
			}
		}
	}

	func countButton(_ n: Int) -> some View {
		let on: Bool = giveCount == n
		return SmallButton(title: joinText("x", String(n)), color: on ? Color(ui: 0x4E8A3E) : Color(ui: 0x555555)) { self.giveCount = n }
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
					SmallButton(title: "Other realm", color: Color(ui: 0x6A3AA0)) { game.debugSwitchDimension() }
				}
				HStack(spacing: 6) {
					SmallButton(title: "Up 20") { game.pb.y -= 20; game.pb.vy = 0; game.fallPeak = 0 }
					SmallButton(title: "Down 20") { game.pb.y += 20; game.pb.vy = 0; game.fallPeak = 0 }
					SmallButton(title: "→ 200") { game.debugTeleport(game.pb.x + 200, game.pb.y) }
				}
				HStack(spacing: 6) {
					TextField("X", text: $tpX).frame(width: 64).padding(3).background(Color.white.opacity(0.15))
					TextField("Y", text: $tpY).frame(width: 64).padding(3).background(Color.white.opacity(0.15))
					SmallButton(title: "Go") {
						if let x = Double(tpX.trimmingCharacters(in: .whitespaces)) {
							let y: Double = Double(tpY.trimmingCharacters(in: .whitespaces)) ?? game.pb.y
							game.debugTeleport(x, y)
						}
					}
				}
			}
		}
	}

	var entitySection: some View {
		let c: Game.EntityCounts = game.entityCounts()
		return VStack(alignment: .leading, spacing: 6) {
			section("ENTITIES")
			Text(verbatim: joinText("Hostile ", String(c.hostile), "  Passive ", String(c.passive), "  Bosses ", String(c.bosses), "  Dying ", String(c.dying)))
				.font(.pixel(10, .semibold))
			Text(verbatim: joinText("Shots ", String(c.projectiles), "  Drops ", String(c.drops), "  Falling ", String(c.falling), "  FX ", String(c.particles)))
				.font(.pixel(10, .semibold))
			Text(verbatim: joinText("Vehicles ", String(c.vehicles), "  Ships ", String(c.ships)))
				.font(.pixel(10, .semibold))
			HStack(spacing: 6) {
				SmallButton(title: "Select at cursor") { game.debugSelectAtCursor() }
				if game.debugSelected != nil {
					SmallButton(title: "Remove", color: Color(ui: 0xA03030)) { game.debugRemoveSelected() }
				}
			}
			if let m = game.debugSelected {
				Text(verbatim: joinText(m.def.name, " #", String(m.id), String(format: "  HP %.0f/%.0f  ", m.hp, m.maxHP), String(format: "x %.1f y %.1f", m.b.x, m.b.y)))
					.font(.pixel(10, .semibold)).foregroundColor(Color(ui: 0xA0E0FF))
				HStack(spacing: 6) {
					SmallButton(title: "Heal") { m.hp = m.maxHP; game.bumpHUD() }
					SmallButton(title: "HP x2") { m.maxHP *= 2; m.hp = m.maxHP; game.bumpHUD() }
					SmallButton(title: "Kill") { if m.hp > 0 { game.killMob(m, false) }; game.bumpHUD() }
				}
			}
			Toggle("Include vehicles", isOn: $includeVehicles).font(.pixel(11, .bold))
			if confirmDelete {
				HStack(spacing: 6) {
					SmallButton(title: "CONFIRM DELETE ALL", color: Color(ui: 0xC02020)) {
						game.debugDeleteAllEntities(includeVehicles: includeVehicles)
						confirmDelete = false
					}
					SmallButton(title: "Cancel") { confirmDelete = false }
				}
			} else {
				SmallButton(title: "Delete all entities", color: Color(ui: 0xA03030)) { confirmDelete = true }
			}
		}
	}

	var multiplierSection: some View {
		VStack(alignment: .leading, spacing: 4) {
			section("MULTIPLIERS")
			Text(verbatim: joinText("Creature health (new spawns) x", String(format: "%.2f", game.mobHealthMult))).font(.pixel(10, .semibold))
			Slider(value: $game.mobHealthMult, in: 0.25...5.0, step: 0.25)
			Text(verbatim: joinText("Damage dealt x", String(format: "%.2f", game.dmgOutMult))).font(.pixel(10, .semibold))
			Slider(value: $game.dmgOutMult, in: 0.0...10.0, step: 0.25)
			Text(verbatim: joinText("Damage taken x", String(format: "%.2f", game.dmgInMult))).font(.pixel(10, .semibold))
			Slider(value: $game.dmgInMult, in: 0.0...5.0, step: 0.25)
			SmallButton(title: "Reset multipliers") { game.debugResetMultipliers() }
		}
	}

	var hazardSection: some View {
		VStack(alignment: .leading, spacing: 6) {
			section("HAZARD TESTS")
			HStack(spacing: 6) {
				SmallButton(title: "Lava pool") { game.debugLavaPool() }
				SmallButton(title: "Explosion") { game.debugExplosionAtCursor() }
			}
			HStack(spacing: 6) {
				SmallButton(title: "Sand drop") { game.debugSandDrop() }
				SmallButton(title: "Spikes") { game.debugSpikes() }
				SmallButton(title: "Set on fire") { game.playerBurn = 3.0; game.bumpHUD() }
			}
		}
	}

	var perfLines: [String] {
		let p: Perf = Perf.shared
		var out: [String] = []
		out.append(String(format: "Tick %.2f ms (worst %.1f)  Draw %.2f ms", game.tickMs, game.tickWorstMs, p.renderMs))
		out.append(String(format: "AI %.2f  Physics %.2f  Light %.2f ms", p.aiMs, p.physMs, p.lightMs))
		out.append(String(format: "Chunk gen %.1f ms (worst %.1f), %d made", p.genMs, p.genWorstMs, p.chunksGenerated))
		out.append(joinText("Light full/partial ", String(p.lightFull), "/", String(p.lightDyn)))
		out.append(joinText("Moves ", String(p.moveCalls), "  Box checks ", String(p.boxChecks)))
		out.append(joinText("Damage queries ", String(p.damageQueries), "  AI skipped ", String(p.aiSkipped)))
		return out
	}

	var perfSection: some View {
		let lines: [String] = perfLines
		return VStack(alignment: .leading, spacing: 2) {
			section("PERFORMANCE")
			ForEach(0..<lines.count, id: \.self) { i in
				Text(lines[i]).font(.pixel(10, .semibold))
			}
		}
	}

	var systemsSection: some View {
		VStack(alignment: .leading, spacing: 4) {
			section("PAUSE SYSTEMS")
			Toggle("Creatures", isOn: $game.pauseMobs)
			Toggle("Bosses", isOn: $game.pauseBosses)
			Toggle("Spawning", isOn: $game.pauseSpawning)
			Toggle("Projectiles", isOn: $game.pauseProjectiles)
			Toggle("Vehicles", isOn: $game.pauseVehicles)
			Toggle("World ticks (plants, sand, leaves)", isOn: $game.pauseWorldTicks)
			Toggle("Particles", isOn: $game.pauseParticles)
			HStack(spacing: 6) {
				SmallButton(title: "Reset systems") { game.debugResetSystems() }
				SmallButton(title: "Reset camera") { game.settings.resetCamera(); game.bumpHUD() }
			}
		}
		.font(.pixel(11, .bold))
	}

	var worldSection: some View {
		let lines: [String] = game.debugWorldgenLines()
		return VStack(alignment: .leading, spacing: 2) {
			section("WORLD GENERATION")
			ForEach(0..<lines.count, id: \.self) { i in
				Text(lines[i]).font(.pixel(10, .semibold))
			}
			Text(verbatim: joinText("Structures chance ", String(format: "%.2f", game.gen.rareChance))).font(.pixel(10, .semibold))
		}
	}

	func section(_ s: String) -> some View {
		return Text(s).font(.pixel(11)).foregroundColor(Color(ui: 0xFFE066)).padding(.top, 4)
	}

	var statLines: [String] {
		var out: [String] = []
		let tickS: String = String(format: "%.2f", game.tickMs)
		out.append("Tick \(tickS) ms")
		let fpsN: Int = Int(game.renderFPS.rounded())
		out.append("FPS \(fpsN)")
		let dimName: String = game.world.dim == .overworld ? "Overworld" : (game.customDim?.def.name ?? "Umbral")
		let xs: String = String(format: "%.1f", game.pb.x)
		let ys: String = String(format: "%.1f", game.pb.y)
		out.append("XY \(xs), \(ys)  \(dimName)")
		let kind: String = joinText(game.gen.infinite ? "Infinite" : "Classic", game.gen.options.flat ? " flat" : "")
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
		}
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
		case .wheel, .offroadWheel, .propeller, .drill, .diamondDrill, .voidDrill: return false
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
