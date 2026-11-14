// PIXEL REALM v2, part 2 of 10: villages and ruins, automation (turrets, the remote control, signals), the Umbral Realm, the world, light and
// physics, bodies on vehicles, flowing liquids and the land painter.
// The game is 10 files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm10.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 3 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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

// ===== p35_automation =====

// MARK: - Automation: guns that fire by themselves, remote control, signals

/// How a vehicle's gun fires (saved by number: only add at the end)
enum GunMode: Int, CaseIterable {
	case driver, auto, buttonA, buttonB, buttonC, signal
	var name: String {
		switch self {
		case .driver: return "fires with its driver's attack"
		case .auto: return "a turret: fires by itself at monsters it can see"
		case .buttonA: return "fires while button A is held"
		case .buttonB: return "fires while button B is held"
		case .buttonC: return "fires while button C is held"
		case .signal: return "fires while its receiver's channel is on"
		}
	}
}

/// What a vehicle's receivers do while their channel is on (saved by number: only add at the end)
enum RadioAct: Int, CaseIterable {
	case forward, back, route, buttonA, buttonB, buttonC
	var name: String {
		switch self {
		case .forward: return "Drive forward"
		case .back: return "Drive back"
		case .route: return "Run its route"
		case .buttonA: return "Hold button A"
		case .buttonB: return "Hold button B"
		case .buttonC: return "Hold button C"
		}
	}
}

/// A mod gun block's own shot (its number among the mod shots, -1: the game's), speed, damage and
/// shots a second (0: the game part's own)
struct ModGunRT {
	var shot: Int = -1
	var speed: Double = 0
	var damage: Double = 0
	var rate: Double = 0
}

/// The numbers of automation
enum Radio {
	/// how far a turret looks for something to shoot (blocks)
	static let turretRange: Double = 16.0
	/// how far either side of its own way a gun can turn (radians)
	static let gunArc: Double = 1.4
	/// how far a remote control reaches its vehicle (blocks)
	static let remoteRange: Double = 200.0
	/// how many signal channels there are
	static let channels: Int = 8
	/// how many vehicles at work far from the player keep their land loaded, and how many chunks of
	/// land may be loaded for them in a frame
	static let farVehicles: Int = 8
	static let farLoads: Int = 2
}

extension Game {
	/// The vehicle the player has their hands on: the one they sit in, or the one their remote drives
	var drivenVehicle: Vehicle? { return inVehicle ?? remoteVehicle }

	/// Whether the player drives this vehicle (from its seat or by remote), or the machine it is a section of
	func playerDrives(_ v: Vehicle) -> Bool {
		guard let d = drivenVehicle else { return false }
		if d === v { return true }
		if v.parentID == 0 && v.joints.isEmpty { return false }
		return machineRoot(v) === machineRoot(d)
	}

	/// The guns on a vehicle and every section of the machine it belongs to
	func machineGuns(_ v: Vehicle) -> Int {
		if v.parentID == 0 && v.joints.isEmpty { return v.cannons + v.guns }
		var n: Int = 0
		for p in machineSections(machineRoot(v)) { n += p.cannons + p.guns }
		return n
	}

	// MARK: signals

	/// Once a frame, before the vehicles move: the channels as the posts and the Logic Studio set them,
	/// and every vehicle with receivers doing what its channel says
	func radioControls(_ dt: Double) {
		for i in 0..<Radio.channels {
			let on: Bool = postChannels[i] || logicChannels[i]
			if on && !channels[i] { fireLogic(.channelOn, number: Double(i + 1)) }
			channels[i] = on
		}
		for v in vehicles where v.receivers > 0 || v.signalOn || v.signalDrive {
			let listening: Bool = v.receivers > 0 && v.channel > 0
			let on: Bool = listening && channels[clampI(v.channel - 1, 0, Radio.channels - 1)]
			let was: Bool = v.signalOn
			v.signalOn = on
			let act: RadioAct = RadioAct(rawValue: v.radioAct) ?? .forward
			// (a driver at the controls has the say over a signal)
			let free: Bool = !v.rider
			var drive: Bool = false
			if on && free && (act == .forward || act == .back) {
				drive = true
				v.throttle = act == .forward ? 1.0 : -1.0
				v.asleep = false
			}
			if v.signalDrive && !drive && free && v.auto == 0 { v.throttle = 0 }
			v.signalDrive = drive
			if act == .route && listening {
				if on && !was && v.autopilots > 0 && v.route.count >= 2 {
					v.auto = 2
					v.routeAt = nearestWaypoint(v)
					v.asleep = false
				}
				if !on && was && v.auto == 2 {
					v.auto = 0
					if free {
						v.throttle = 0
						v.pitch = 0
					}
				}
			}
			if on != was { v.asleep = false }
		}
	}

	/// The receiver panel sets the vehicle's channel and what its receivers do
	func setRadio(channel: Int, act: RadioAct) {
		guard let v = vehicleByID(radioEdit) else { return }
		v.channel = clampI(channel, 0, Radio.channels)
		v.radioAct = act.rawValue
		v.asleep = false
		bumpHUD()
	}

	/// DONE on the receiver panel
	func closeRadio() {
		showRadio = false
		radioEdit = 0
		bumpHUD()
	}

	/// Whether a signal channel (1 to 8) is on
	func channelIsOn(_ n: Int) -> Bool {
		if n < 1 || n > Radio.channels { return false }
		return channels[n - 1] || postChannels[n - 1] || logicChannels[n - 1]
	}

	/// The Logic Studio turns a channel (1 to 8) on or off
	func setLogicChannel(_ n: Int, _ on: Bool) {
		if n < 1 || n > Radio.channels { return }
		logicChannels[n - 1] = on
	}

	/// The buttons A, B and C held for a vehicle or its machine: the driver's own, and any a receiver's
	/// signal holds
	func machineButtonsHeld(_ v: Vehicle, _ driving: Bool) -> [Bool] {
		var out: [Bool] = driving ? jointButtons : [false, false, false]
		let parts: [Vehicle] = v.parentID == 0 && v.joints.isEmpty ? [v] : machineSections(machineRoot(v))
		for p in parts where p.signalOn {
			let i: Int = p.radioAct - RadioAct.buttonA.rawValue
			if i >= 0 && i < 3 { out[i] = true }
		}
		return out
	}

	/// Whether a receiver on a vehicle or its machine has its channel on
	func machineSignalOn(_ v: Vehicle) -> Bool {
		if v.parentID == 0 && v.joints.isEmpty { return v.signalOn }
		return machineSections(machineRoot(v)).contains { (p: Vehicle) in p.signalOn }
	}

	/// What a vehicle sensor sees: a vehicle with a cell within its range (any, one being driven, or one
	/// with nobody at its controls)
	func vehicleNearSensor(_ cx: Double, _ cy: Double, _ r: Double, _ mode: Int) -> Bool {
		for v in vehicles {
			if v.b.right < cx - r - 1 || v.b.left > cx + r + 1 || v.b.y < cy - r - 1 || v.b.top > cy + r + 1 { continue }
			let driven: Bool = machineRoot(v).rider || v.rider
			if mode == 1 && !driven { continue }
			if mode == 2 && driven { continue }
			for (c, _) in v.parts {
				let p: (Double, Double) = v.cellCenter(c)
				if hypot(p.0 - cx, p.1 - cy) <= r + 0.5 { return true }
			}
		}
		return false
	}

	// MARK: vehicles at work far away

	/// A vehicle at work on its own: an autopilot with nobody at the controls, or a remote driving it
	func vehicleWorking(_ v: Vehicle) -> Bool {
		let root: Vehicle = machineRoot(v)
		if root.id == remoteID || root.signalDrive || v.signalDrive { return true }
		return root.auto != 0 && !root.rider
	}

	/// The land round each vehicle at work stays loaded however far it goes from the player, and the land
	/// ahead of it is loaded as it goes (a little each frame), so an autopilot runs its route anywhere
	func keepWorkingLand(_ keep: inout Set<Int>) {
		var budget: Int = Radio.farLoads
		var n: Int = 0
		for v in vehicles where vehicleWorking(v) {
			n += 1
			if n > Radio.farVehicles { break }
			let reach: Double = 8.0 + abs(v.vx) * 1.5
			let c0: Int = floorDiv(Int(floor(v.b.left - reach)), chunkW)
			let c1: Int = floorDiv(Int(floor(v.b.right + reach)), chunkW)
			var c: Int = c0
			while c <= c1 {
				keep.insert(c)
				if budget > 0 && world.chunks[c] == nil && world.inRange(c) {
					world.loadChunk(c)
					budget -= 1
				}
				c += 1
			}
		}
	}

	// MARK: the remote control

	/// The vehicle the remote drives now
	var remoteVehicle: Vehicle? { return remoteID == 0 ? nil : vehicleByID(remoteID) }

	/// Receivers on a vehicle and every section of its machine
	func machineReceivers(_ v: Vehicle) -> Int {
		if v.parentID == 0 && v.joints.isEmpty { return v.receivers }
		var n: Int = 0
		for p in machineSections(machineRoot(v)) { n += p.receivers }
		return n
	}

	/// Whether the remote still reaches a vehicle: it is here, it has a receiver, and it is near enough
	func remoteCanReach(_ v: Vehicle) -> Bool {
		if v.parts.isEmpty || machineReceivers(v) == 0 { return false }
		return hypot(v.px - pb.x, v.py - pb.y) <= Radio.remoteRange
	}

	/// The remote in use: on a vehicle within reach it pairs with it (if it has a receiver); anywhere else
	/// it takes the paired vehicle's controls
	func useRemote() {
		if useCD > 0 { return }
		useCD = 0.3
		if let (v, _) = vehicleAtPoint(aimX, aimY), inReach(aimX, aimY) {
			let root: Vehicle = machineRoot(v)
			if machineReceivers(root) == 0 {
				say("It needs a receiver to answer a remote: build one onto it.", 2.5)
				return
			}
			remotePair = root.id
			sfx(.tap, 0.6)
			say("Paired. Use the remote away from it to drive it from afar; JUMP lets go.", 3.0)
			return
		}
		startRemote()
	}

	/// Takes the paired vehicle's controls from where the player stands
	func startRemote() {
		guard let v = vehicleByID(remotePair) else {
			say(remotePair == 0 ? "Pair the remote first: use it on a vehicle with a receiver." : "The paired vehicle is not here.", 2.5)
			return
		}
		if inVehicle != nil || mounted != nil {
			say("Get out first: the remote drives from outside.", 2.0)
			return
		}
		if !remoteCanReach(v) {
			say(machineReceivers(v) == 0 ? "Its receiver is gone." : "Too far away for the remote.", 2.0)
			return
		}
		remoteID = v.id
		v.rider = true
		v.asleep = false
		v.holdY = v.py
		say("Driving by remote. JUMP lets go.", 2.5)
		bumpHUD()
	}

	/// The stick drives the vehicle the remote holds, as if from its seat; JUMP lets go
	func driveRemote(_ v: Vehicle, _ ix: Double, _ jump: Bool, _ dt: Double) {
		if jump {
			endRemote("Remote off.")
			return
		}
		v.throttle = ix
		var up: Double = -stickY
		if abs(up) < 0.15 { up = 0 }
		v.pitch = clampD(up, -1, 1)
		if v.auto != 0 { autopilotSteer(v, ix, up, dt) }
		if abs(v.throttle) > 0.05 || abs(v.pitch) > 0.05 { v.asleep = false }
	}

	/// Lets go of the remote (the vehicle keeps its autopilot, if it is on)
	func endRemote(_ why: String? = nil) {
		if let v = vehicleByID(remoteID), inVehicle !== v {
			v.rider = false
			if v.auto == 0 {
				v.throttle = 0
				v.pitch = 0
			}
		}
		remoteID = 0
		if let w = why { say(w, 2.0) }
		bumpHUD()
	}

	/// A gun cell's own shot, speed, damage and rate when it is a mod's gun block (none: the game part's own)
	func modGun(_ v: Vehicle, _ c: PartCell) -> ModGunRT {
		guard let b = v.blocks[c], b.isMod, let d = ModRuntime.shared.blockDef(b) else { return ModGunRT() }
		return ModGunRT(shot: ModRuntime.shared.blockShot(b), speed: d.shotSpeed, damage: d.shotDamage, rate: d.fireRate)
	}

	/// A tap on a gun (not while driving): the next way of firing, round and back to the driver's
	func cycleGunMode(_ v: Vehicle, _ c: PartCell) {
		let n: Int = GunMode.allCases.count
		let next: Int = ((v.gunMode[c] ?? 0) + 1) % n
		if next == 0 { v.gunMode[c] = nil } else { v.gunMode[c] = next }
		let m: GunMode = GunMode(rawValue: next) ?? .driver
		say(joinText(v.parts[c] == .cannon ? "Cannon: " : "Machine gun: ", m.name, "."), 2.5)
		sfx(.tap, 0.5)
		v.asleep = false
		bumpHUD()
	}

	/// What a turret shoots at: the nearest threat it can see within its reach and its arc, where it
	/// will be when the shot gets there
	func turretTarget(_ v: Vehicle, _ c: PartCell, _ o: (Double, Double), _ base: Double) -> (Double, Double)? {
		let r: Double = Radio.turretRange
		var best: Mob? = nil
		var bd: Double = r * r
		for m in mobsNear(o.0 - r, o.0 + r) where m.hp > 0 && !m.removed && !m.downed && !m.tame && isThreat(m) {
			let dx: Double = m.b.x - o.0
			let dy: Double = m.b.cy - o.1
			let d: Double = dx * dx + dy * dy
			if d >= bd { continue }
			if abs(remainder(atan2(dy, dx) - base, 2.0 * Double.pi)) > Radio.gunArc + 0.05 { continue }
			if !world.lineClear(o.0, o.1, m.b.x, m.b.cy) { continue }
			bd = d
			best = m
		}
		guard let m = best else { return nil }
		let lead: Double = sqrt(bd) / 40.0
		return (m.b.x + m.b.vx * lead, m.b.cy + m.b.vy * lead)
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
