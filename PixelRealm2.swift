// PIXEL REALM v2, part 2 of 5: villages and ruins, automation (turrets, the remote control, signals), the Umbral Realm, the world, light and
// physics, bodies on vehicles, flowing liquids, the land painter, helpers, walls and doors, vehicles of every kind
// (flight, weapons, damage, the assembler, the autopilot), Sparkworks (power) and the Mod Creator's data and runtime.
// The game is five files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm5.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
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

// ===== p20_assist =====

// MARK: - Action button (auto-aim), debug commands, info for the HUD

/// The attack control. `held` is true while it is down (the combat stick, or the F key). The combat stick
/// also reports where the thumb is: `power` is how far out (0 to 1), `dirX`/`dirY` the unit direction, and
/// `manual` whether it is out far enough to aim by hand. Inside the dead zone the game aims for itself.
final class ActState: @unchecked Sendable {
	var held: Bool = false
	var was: Bool = false
	var dirX: Double = 0
	var dirY: Double = 0
	var power: Double = 0
	var manual: Bool = false
	/// the dead zone, as a share of the stick's radius: a thumb has to leave `deadIn` to start aiming by
	/// hand, and come back inside `deadOut` to hand the aim back (the gap stops it flickering at the edge)
	static let deadIn: Double = 0.26
	static let deadOut: Double = 0.17

	/// A finger is on the combat stick at (x, y), measured from its centre in stick radii (any length;
	/// anything past the edge counts as the edge). Diagonals are as strong as straight lines.
	func stickAt(_ x: Double, _ y: Double) {
		let len: Double = sqrt(x * x + y * y)
		power = min(1.0, len)
		manual = power > (manual ? ActState.deadOut : ActState.deadIn)
		if manual && len > 0.0001 {
			dirX = x / len
			dirY = y / len
		}
		held = true
	}

	/// The finger left the combat stick
	func stickReleased() {
		held = false
		manual = false
		power = 0
		dirX = 0
		dirY = 0
	}
}

let actState = ActState()

extension Game {
	/// Called once per frame before tick. While the on-screen action button is held, the game aims
	/// for you: the best foe for the weapon in hand (hostile ones first, the one already locked on,
	/// in sight for ranged weapons, led and raised for the shot's drop), otherwise the block in front.
	/// A finger on the world aims for itself; then the button only keeps the action going.
	func applyActButton() {
		let held: Bool = actState.held
		defer { actState.was = held }
		if !held {
			if actState.was && !touchActive {
				useHeld = false
				useWasHeld = false
				useReleasedFlag = true
			}
			return
		}
		if dead { return }
		if touchActive {
			useHeld = true
			return
		}
		// in an armed vehicle (or one driven by remote) the attack stick aims and fires its guns
		if let v = drivenVehicle, machineGuns(v) > 0 {
			if actState.manual {
				aimX = v.px + actState.dirX * 18.0
				aimY = v.py + actState.dirY * 18.0
			} else if let a = vehicleAutoAim(v) {
				aimX = a.0
				aimY = a.1
			} else {
				aimX = v.px + Double(v.dir) * 14.0
				aimY = v.py
			}
			aimValid = true
			holdAction()
			return
		}
		let it: Item? = heldItem
		if actState.manual {
			// the thumb is out past the dead zone: aim where it points, with this weapon's own rules
			let a: (Double, Double) = stickAim(it, actState.dirX, actState.dirY, actState.power)
			aimX = a.0
			aimY = a.1
			aimValid = true
			lockTarget = nil
			if abs(actState.dirX) > 0.25 { facing = actState.dirX >= 0 ? 1 : -1 }
			holdAction()
			return
		}
		var tx: Double = pb.x + Double(facing) * 1.1
		var ty: Double = pb.y - 1.3
		var aimed: Bool = false
		var wantsMob: Bool = true
		if let i = it {
			switch i {
			case .block, .part, .mat, .food, .wall: wantsMob = false
			case .potion(let pt): wantsMob = pt.thrown && pt != .mendingSplash && pt != .regrowthSplash
			default: wantsMob = true
			}
		}
		if wantsMob, let m = autoTarget(it) {
			let a: (Double, Double) = aimPointFor(m, it)
			tx = a.0
			ty = a.1
			aimed = true
			lockTarget = m
			lockT = max(lockT, 0.5)
		}
		if case .potion(let pt)? = it, pt == .mendingSplash || pt == .regrowthSplash {
			// a helpful splash thrown with no direction bursts at the player's own feet
			tx = pb.x + Double(facing) * 0.6
			ty = pb.y - 0.3
			aimed = true
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
		holdAction()
	}

	/// Keeps the action going; the first frame of a press starts it fresh
	func holdAction() {
		if !actState.was {
			useWasHeld = false
			usePressedFlag = false
		}
		useHeld = true
	}

	/// The point the combat stick aims at, from the direction (dx, dy) (a unit vector) and how far out
	/// the thumb is (0 to 1). Each kind of item reads it its own way: a blade or spear swings along the
	/// direction, bows and guns shoot along it, slings and thrown flasks land further out the further
	/// the thumb is pushed, tools and fists work on the first creature or block along it, and blocks go
	/// down against the first surface along it.
	func stickAim(_ it: Item?, _ dx: Double, _ dy: Double, _ power: Double) -> (Double, Double) {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let reach: Double = min(reachDistance(), 5.5) - 0.3
		guard let item = it else { return stickDigPoint(dx, dy, reach) }
		switch item {
		case .sword, .spear, .hammer, .knife, .club, .relic:
			let d: Double = max(1.0, infusedMelee(item).reach)
			return (ox + dx * d, oy + dy * d)
		case .bow, .gun:
			return (ox + dx * 14.0, oy + dy * 14.0)
		case .sling:
			let d: Double = 4.0 + 9.0 * power
			return (ox + dx * d, oy + dy * d)
		case .potion(let pt) where pt.thrown:
			let d: Double = 3.0 + 9.0 * power
			return (ox + dx * d, oy + dy * d)
		case .gadget(let g):
			if g == .bomb || g == .fireFlask {
				let d: Double = 3.0 + 9.0 * power
				return (ox + dx * d, oy + dy * d)
			}
			return stickDigPoint(dx, dy, reach)
		case .tool:
			return stickDigPoint(dx, dy, reach)
		case .block, .wall, .part:
			return stickPlacePoint(dx, dy, reach)
		default:
			return (ox + dx * 1.5, oy + dy * 1.5)
		}
	}

	/// The first creature, or failing that the first block, along a direction from the shoulder within
	/// `r` blocks: what a pickaxe or a fist works on. With nothing in the way, the point at full reach.
	func stickDigPoint(_ dx: Double, _ dy: Double, _ r: Double) -> (Double, Double) {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		let near: [Mob] = mobsNear(ox - r - 1.0, ox + r + 1.0)
		var d: Double = 0.7
		while d <= r {
			let x: Double = ox + dx * d
			let y: Double = oy + dy * d
			for m in near where m.hp > 0 && !m.removed && !m.tame && !m.downed {
				if x >= m.b.left - 0.2 && x <= m.b.right + 0.2 && y >= m.b.top - 0.2 && y <= m.b.y + 0.2 { return (m.b.x, m.b.cy) }
			}
			let tx: Int = Int(floor(x))
			let ty: Int = Int(floor(y))
			let t: Tile = world.tile(tx, ty)
			if t != .air && !t.liquid { return (Double(tx) + 0.5, Double(ty) + 0.5) }
			d += 0.25
		}
		return (ox + dx * r, oy + dy * r)
	}

	/// The empty block just in front of the first solid one along a direction: where a block would go
	/// to build against what the stick points at
	func stickPlacePoint(_ dx: Double, _ dy: Double, _ r: Double) -> (Double, Double) {
		let ox: Double = shoulderX
		let oy: Double = shoulderY
		var last: (Int, Int)? = nil
		var d: Double = 0.7
		while d <= r {
			let tx: Int = Int(floor(ox + dx * d))
			let ty: Int = Int(floor(oy + dy * d))
			if world.solid(tx, ty) { break }
			last = (tx, ty)
			d += 0.25
		}
		if let l = last { return (Double(l.0) + 0.5, Double(l.1) + 0.5) }
		return (ox + dx * 1.2, oy + dy * 1.2)
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

	/// The debug menu's give: any item of the game or of the world's mods, as many as asked (what does
	/// not fit falls at the player's feet)
	func debugGive(_ it: Item, _ n: Int) {
		let count: Int = clampI(n, 1, 9999)
		giveItem(it, count, extra: gunLoad(it))
		say(joinText("Gave ", String(count), " ", it.name, "."), 1.5)
	}

	func debugGiveKit() {
		let kit: [(Item, Int)] = [
			(.tool(.pickaxe, .diamond), 1), (.tool(.axe, .diamond), 1), (.sword(.diamond), 1), (.bow, 1),
			(.ammo(.arrow), 99), (.gun(.rifle), 1), (.gun(.pistol), 1), (.ammo(.bullet), 99),
			(.block(.torch), 99), (.block(.planks), 99), (.block(.stone), 99), (.food(.cookedMeat), 30),
			(.armor(.head, .diamond), 1), (.armor(.chest, .diamond), 1), (.armor(.legs, .diamond), 1),
			(.part(.frame), 10), (.part(.wheel), 4), (.part(.engine), 2), (.part(.seat), 1), (.part(.steering), 1),
			(.part(.fuelTank), 2), (.part(.hull), 6), (.part(.propeller), 1), (.mat(.coal), 40), (.gadget(.wrench), 1),
			(.gadget(.portalKey), 1), (.gadget(.treasureMap), 1), (.gadget(.carKit), 1), (.gadget(.motorboatKit), 1),
			(.knife(.diamond), 1), (.club(.mace), 1), (.sling, 1), (.gun(.crossbow), 1), (.gun(.blunderbuss), 1),
			(.gun(.stormRod), 1), (.ammo(.bolt), 99), (.gadget(.fireFlask), 20)
		]
		for (it, n) in kit { giveItem(it, n, extra: gunLoad(it)) }
		gotMap = true
		say("Debug kit added.", 2.0)
	}

	func debugKillHostiles() {
		for m in mobs where m.def.hostile && !m.tame && m.hp > 0 { killMob(m, true) }
	}

	struct EntityCounts {
		var hostile: Int = 0
		var passive: Int = 0
		var bosses: Int = 0
		var dying: Int = 0
		var projectiles: Int = 0
		var drops: Int = 0
		var particles: Int = 0
		var falling: Int = 0
		var vehicles: Int = 0
		var ships: Int = 0
	}

	func entityCounts() -> EntityCounts {
		var c = EntityCounts()
		for m in mobs {
			if m.hp <= 0 && !m.downed { c.dying += 1 } else if m.isBoss { c.bosses += 1 } else if m.def.hostile { c.hostile += 1 } else { c.passive += 1 }
		}
		c.projectiles = projectiles.count
		c.drops = drops.count
		c.particles = particles.count
		c.falling = fallingBlocks.count
		c.vehicles = vehicles.count
		c.ships = ships.count
		return c
	}

	/// Removes every creature, boss, ship, projectile, dropped item, falling block and particle (and,
	/// if asked, vehicles). References to them are cleared so nothing keeps a removed entity alive, and
	/// nearby lair bosses stay away until the player has left the area.
	func debugDeleteAllEntities(includeVehicles: Bool) {
		if mounted != nil || (includeVehicles && inVehicle != nil) { dismount() }
		if world.dim == .overworld {
			for L in gen.lairCenters(near: Int(floor(pb.x))) where abs(Double(L.cx) - pb.x) < 180 {
				suppressedLairs.insert(lairKey(L))
			}
		}
		for m in mobs { m.removed = true }
		mobs.removeAll()
		mobGrid.rebuild(mobs)
		activeBoss = nil
		rex = nil
		mounted = nil
		debugSelected = nil
		ships.removeAll()
		projectiles.removeAll()
		drops.removeAll()
		particles.removeAll()
		flashes.removeAll()
		fallingBlocks.removeAll()
		floats.removeAll()
		playerHitStamps.removeAll()
		if includeVehicles {
			inVehicle = nil
			vehicles.removeAll()
		}
		say("All entities deleted.", 2.0)
		bumpHUD()
	}

	/// Picks the creature closest to the cursor (or to the player when there is no cursor)
	func debugSelectAtCursor() {
		let tx: Double = aimValid ? aimX : pb.x
		let ty: Double = aimValid ? aimY : pb.y - 1
		var best: Mob? = nil
		var bd: Double = 36
		for m in mobs where m.hp > 0 || m.downed {
			let dx: Double = m.b.x - tx
			let dy: Double = m.b.cy - ty
			let d: Double = dx * dx + dy * dy
			if d < bd { bd = d; best = m }
		}
		debugSelected = best
		if best == nil { say("Nothing near the cursor.", 1.2) }
		bumpHUD()
	}

	func debugRemoveSelected() {
		guard let m = debugSelected else { return }
		m.removed = true
		mobs.removeAll { $0 === m }
		if m === activeBoss { activeBoss = nil }
		if m === rex { rex = nil }
		if m === mounted { dismount(); mounted = nil }
		debugSelected = nil
		bumpHUD()
	}

	// hazard tests: each creates a hazard right next to the player so damage, immunities and
	// knockback can be checked by eye
	func debugLavaPool() {
		let x0: Int = Int(floor(pb.x)) + facing * 3
		let y: Int = Int(floor(pb.y))
		for dx in 0..<4 {
			let x: Int = x0 + (facing > 0 ? dx : -dx)
			_ = world.set(x, y, .lava)
			_ = world.set(x, y + 1, .stone)
		}
		light.valid = false
	}

	func debugExplosionAtCursor() {
		let x: Double = aimValid ? aimX : pb.x + Double(facing) * 4
		let y: Double = aimValid ? aimY : pb.y - 1
		explode(x, y, radius: 3.0, power: 20, source: .environment, breakBlocks: false)
	}

	func debugSandDrop() {
		let x: Int = Int(floor(pb.x)) + facing * 2
		let top: Int = Int(floor(pb.y)) - 8
		for k in 0..<3 where !world.solid(x, top + k) { _ = world.set(x, top + k, .sand) }
		checkFalling(x, top + 2)
	}

	func debugSpikes() {
		let x: Int = Int(floor(pb.x)) + facing * 2
		let y: Int = Int(floor(pb.y)) - 1
		if !world.solid(x, y) { _ = world.set(x, y, .spikes) }
	}

	func debugResetMultipliers() {
		speedMult = 1
		dmgOutMult = 1
		dmgInMult = 1
		mobHealthMult = 1
		bumpHUD()
	}

	func debugResetSystems() {
		pauseMobs = false
		pauseBosses = false
		pauseSpawning = false
		pauseProjectiles = false
		pauseVehicles = false
		pauseWorldTicks = false
		pauseParticles = false
		light.valid = false
		RenderCache.shared.clearAll()
		Perf.shared.genWorstMs = 0
		tickWorstMs = 0
		say("Systems reset.", 1.2)
		bumpHUD()
	}

	/// Short report of the world generator around the player
	func debugWorldgenLines() -> [String] {
		let x: Int = Int(floor(pb.x))
		var out: [String] = []
		out.append(joinText("Gen version ", String(gen.genVersion), "  sea ", String(WorldGen.sea), gen.options.flat ? "  flat" : ""))
		out.append(joinText("Biome ", biomeHere.name, "  surface y ", String(world.surfaceY(x))))
		var nearest: Int = -1
		var d: Int = 0
		while d < 3000 && nearest < 0 {
			for sx in [x - d, x + d] {
				if !gen.infinite && (sx < 0 || sx >= gen.width) { continue }
				if gen.colBase(sx).biome == .ocean { nearest = sx; break }
			}
			d += 16
		}
		if nearest >= 0 { out.append(joinText("Nearest ocean x ", String(nearest), " (", String(abs(nearest - x)), " away)")) }
		else { out.append("No ocean within 3000 blocks") }
		return out
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
		if world.dim.isCustom { return customDim?.biomeAt(pb.x) ?? .plains }
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
		let nm: String = s.item.name
		switch s.item {
		case .gun(let g):
			let ex: Int = s.extra
			let mg: Int = g.magazine
			if let a = g.ammo {
				let left: Int = inv.total(.ammo(a))
				return "\(nm)  \(ex)/\(mg) · \(left) left"
			}
			return "\(nm)  \(ex)/\(mg) charges"
		case .bow:
			let n: Int = inv.total(.ammo(.arrow))
			return "\(nm) · \(n) arrows"
		case .sling:
			var n: Int = 0
			for t in slingAmmo { n += inv.total(.block(t)) }
			return "\(nm) · \(n) stones"
		default:
			return nm
		}
	}

	func armorPieces() -> (Tier?, Tier?, Tier?) {
		var r: [Tier?] = [nil, nil, nil]
		for i in 0..<3 {
			if let s = inv.armor[i], case .armor(_, let t) = s.item { r[i] = t }
			if let s = inv.armor[i], case .custom(let k) = s.item, let m = ModRuntime.shared.item(k), m.def.kind == .armor { r[i] = Tier(rawValue: m.def.look) }
		}
		return (r[0], r[1], r[2])
	}

	var armorKey: Int {
		let a = armorPieces()
		let h: Int = a.0?.rawValue ?? 0
		let c: Int = a.1?.rawValue ?? 0
		let l: Int = a.2?.rawValue ?? 0
		return (h * 100 + c * 10 + l) &+ PlayerLookChoice(settings).key &* 1000 &+ suitDrawKey
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
	let cd: ModDimRT? = dim.isCustom ? ModRuntime.shared.dimRT(dim) : nil
	for lx in 0..<chunkW {
		let x: Int = ch.x0 + lx
		if dim.isCustom {
			ch.surf[lx] = cd?.surfaceAt(x, g.seed) ?? ch.H - 3
			ch.ceilY[lx] = (cd?.def.ceiling ?? false) ? (cd?.ceilingAt(x, g.seed) ?? 0) : 0
		} else if dim == .overworld {
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
	if let t = blockWallTile(k) { return joinText(t.def.name, " Wall") }
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
	if let t = blockWallTile(k) { return t }
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

/// A door the player walked through, waiting to close behind them
struct WalkDoor {
	var x: Int
	var y: Int
	var t: Double
}

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
		sfx(.door, at: Double(x), 0.7)
		spawnParticles(Double(x) + 0.5, Double(y) + 0.5, 0xA97B45, 2, 1.5, 0.3, 8)
	}

	/// Walking into a closed door opens it, and it closes again once the player has gone through (a door
	/// opened or shut with a tap stays as it was set)
	func doorTouch(_ ix: Double) {
		if ix != 0 {
			let sgn: Double = ix > 0 ? 1.0 : -1.0
			let reachX: Double = pb.w * 0.5 + 0.2
			let fxd: Double = pb.x + sgn * reachX
			let fx: Int = Int(floor(fxd))
			for yy in [Int(floor(pb.y - 0.5)), Int(floor(pb.y - 1.4))] {
				if world.tile(fx, yy) == .doorClosed {
					setDoor(fx, yy, open: true)
					let c: (Int, Int) = doorCells(fx, yy)
					if !walkDoors.contains(where: { $0.x == fx && $0.y == c.0 }) && walkDoors.count < 16 {
						walkDoors.append(WalkDoor(x: fx, y: c.0, t: 0))
					}
					break
				}
			}
		}
	}

	/// Closes the doors the player walked through, once they are clear of the doorway
	func updateWalkDoors(_ dt: Double) {
		if walkDoors.isEmpty { return }
		var keep: [WalkDoor] = []
		for var w in walkDoors {
			w.t += dt
			if world.tile(w.x, w.y) != .doorOpen { continue }
			let c: (Int, Int) = doorCells(w.x, w.y)
			let away: Bool = abs(pb.x - (Double(w.x) + 0.5)) > pb.w * 0.5 + 1.1 || pb.y < Double(c.0) - 0.5 || pb.top > Double(c.1) + 1.5
			if w.t > 0.5 && away && !doorBlocked(w.x, c.0, c.1) {
				setDoor(w.x, w.y, open: false)
				sfx(.door, at: Double(w.x), 0.5)
				continue
			}
			if w.t < 60 { keep.append(w) }
		}
		walkDoors = keep
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
		world.setBuilt(tx, ty - 1, true)
		world.setBuilt(tx, ty, true)
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
			swingDir = aimFacing()
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
			swingDir = aimFacing()
			facing = swingDir
			useCD = 0.26
		}
		if mineP >= mineNeed {
			mineP = 0
			mining = false
			world.setWall(tx, ty, 0)
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, shadeRGB(wallSourceTile(k).def.colors.first ?? 0x888888, 0.6), 5, 3.0, 0.4, 14)
			// a block put up as a wall comes back as the block
			let back: Item = blockWallTile(k).map { Item.block($0) } ?? .wall(k)
			if !isCreative { spawnDrop(Stack(item: back, count: 1), Double(tx) + 0.5, Double(ty) + 0.5, 0, -2) }
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

// ===== p25_hud =====

// MARK: - HUD change detection
// The HUD only redraws when something it shows has changed (checked a few times a second).

extension Game {
	func hudKey() -> Int {
		var h: Hasher = Hasher()
		// an open device panel shows live readings: it refreshes twice a second
		if showPower { h.combine(Int(clock * 2.0)) }
		// the flight instruments and the guns' reload: four times a second while driving
		if let v = inVehicle {
			h.combine(Int(clock * 4.0))
			h.combine(v.auto)
			h.combine(v.route.count)
		}
		h.combine(vehicleBuild)
		h.combine(canBuildOnVehicle)
		h.combine(Int(hp * 2.0))
		h.combine(Int(maxHP))
		h.combine(Int(hunger * 2.0))
		h.combine(Int(air * 2.0))
		h.combine(Int(totalDefense))
		// effects tick down a second at a time; the suit's energy in steps
		for e in activeEffects() {
			h.combine(e.0.rawValue)
			h.combine(Int(e.1))
		}
		h.combine(suit.worn)
		h.combine(Int(suit.energy / 3.0))
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
		// weather: the banner, what is shown in the info corner, a barometer in hand
		h.combine(wxBanner)
		h.combine(weather.kind.rawValue)
		h.combine(wxHere.snow)
		h.combine(Int(abs(wxHere.wind)))
		h.combine(weatherHereLabel)
		if case .gadget(.barometer)? = heldItem { h.combine(Int(pressureNow())) }
		if settings.showFPS { h.combine(Int(renderFPS)) }
		return h.finalize()
	}
}

// ===== p33_vehicles =====

// MARK: - Vehicles of every kind: blocks on vehicles, flight, weapons, damage, turning, assembling, the autopilot
// A vehicle is a rigid body built cell by cell (p13b_vehicles, p17_vehicles_ships). This part adds what
// makes planes, helicopters, airships, tanks and anything in between work: every cell can be any block,
// each cell weighs what it is made of, and the air acts on each cell where it is (lift on wings, drag on
// exposed faces, thrust along propellers, rotor lift, hot air in balloons), so a design flies, floats or
// tumbles because of how it is built.

/// Hitting the ground faster than this (blocks per second, straight into it) breaks parts
let vehicleCrashSpeed: Double = 21.0

/// The numbers of the flight model
enum Aero {
	/// lift per wing cell: kLift x airspeed^2 x lift coefficient (a 10-mass plane with 3 wing cells
	/// leaves the ground at about 11 blocks a second)
	static let kLift: Double = 0.8
	/// drag per exposed face: kDrag x drag coefficient x airspeed^2
	static let kDrag: Double = 0.022
	/// how much a face tucked behind another still feels the air (skin friction)
	static let shielded: Double = 0.06
	/// share of the wing drag coefficient applied (the wing's own profile drag)
	static let dragShare: Double = 1.0
	/// lift slope per radian, the angle where a wing stalls, the post-stall lift
	static let liftSlope: Double = 5.0
	static let stallAngle: Double = 0.27
	/// how far an elevator's flap turns the airflow (radians at full stick), and the elevator's size
	/// against a wing's
	static let flap: Double = 0.55
	static let elevatorArea: Double = 1.0
	/// a wing's camber: it lifts a little even meeting the air head on (radians of extra angle)
	static let camber: Double = 0.07
	/// a wing's tilt: steps of this angle (radians), up to this many either way
	static let tiltStep: Double = 0.05
	static let tiltSteps: Int = 3
	/// a flap's drop at its lowest (it drops below flapSpeed, fully by half of it), and its drag then
	static let flapDrop: Double = 0.16
	static let flapSpeed: Double = 18.0
	static let flapDrag: Double = 0.07
	/// an open air brake's drag, and how fast it opens and closes (per second)
	static let brakeDrag: Double = 1.8
	static let brakeRate: Double = 2.5
	/// a tailplane's area (a wing is 1)
	static let stabArea: Double = 0.6
	/// how fast ballast tanks fill or empty at full stick (of a tank a second)
	static let ballastRate: Double = 0.25
	/// static thrust of an air propeller per engine of power, and the airspeed where it fades out
	static let propThrust: Double = 110.0
	static let propVmax: Double = 64.0
	/// a jet's thrust (it is its own engine)
	static let jetThrust: Double = 165.0
	/// rotor lift per engine of power at full blade pitch
	static let rotorLift: Double = 265.0
	/// a heated balloon envelope's lift (mass it can hold up at full heat), and how many envelopes one burner heats
	static let envLift: Double = 1.3
	static let burnerCells: Int = 12
	/// how far the cyclic tilts a helicopter at full stick, and how firmly it holds the tilt
	static let cyclicTilt: Double = 0.3
	/// hands off, a helicopter tilts against its drift to hover in place (radians per block a second)
	static let hoverHold: Double = 0.035
	/// the turning rotor disc resists the air across it (what keeps a helicopter's speed down)
	static let rotorDrag: Double = 0.25
	/// up and down on the stick ask a helicopter for this climb or sink rate (blocks a second)
	static let climbRate: Double = 9.0
	static let cyclicP: Double = 16.0
	static let cyclicD: Double = 7.5
	/// how fast blade pitch follows the stick, and how fast a burner heats the balloon and venting cools it
	static let collectiveRate: Double = 0.9
	static let heatRate: Double = 0.14
	static let ventRate: Double = 0.22
	/// a balloon's canopy against the air going up or down through it (a cold balloon comes down slowly)
	static let canopyDrag: Double = 8.0
	/// the cyclic's trim: how fast it learns to hold the tilt against an off-centre rotor
	static let cyclicI: Double = 6.0
	/// the pitch control: full stick asks for this pitch rate (radians a second); the elevators are moved
	/// to get it (as far as they can at this speed), and the trim learns what holds the nose steady
	static let pitchRate: Double = 0.9
	static let rateGain: Double = 1.3
	static let trimRate: Double = 1.6
	/// the stall guard: past this share of the stall angle the nose is eased down instead of pulled up
	static let alphaGuard: Double = 0.75
	/// hands off, how fast the nose comes back to level (radians a second per radian)
	static let levelRate: Double = 0.4
	/// seconds a turn to face the other way takes in flight
	static let turnTime: Double = 1.4
}

/// The numbers of wheels, tracks and water propellers
enum Drive {
	/// what one engine gives its wheels (push times speed): above about 8 blocks a second its push falls
	static let power: Double = 1415.0
	/// what the wheels and gearing take, per block a second of speed; a little more for every unit of
	/// weight on them; tracks take a good deal more
	static let loss: Double = 10.0
	static let lossPerMass: Double = 0.028
	static let trackLoss: Double = 0.8
	/// what one engine gives a water propeller, how fast a paddle's stroke goes (blocks a second), and
	/// the share of the water's drag that grows with the square of the speed
	static let propPower: Double = 130.0
	static let paddleStroke: Double = 9.0
	static let waterDrag: Double = 0.002
	/// how hard a tyre can push along what it touches, for each unit it is pressed against it
	static let tyreGrip: Double = 1.0
}

/// Air thins with height: full below the hills, about half at the top of the sky
func airDensity(_ y: Double) -> Double {
	let top: Double = Double(WorldGen.sea) - 60.0
	if y >= top { return 1.0 }
	return max(0.45, 1.0 - 0.55 * (top - y) / max(1.0, top))
}

/// A wing's lift coefficient at an angle of attack (radians, folded to -pi/2...pi/2): straight up to
/// the stall, then it falls away to a flat plate's
func liftCoefficient(_ a: Double) -> Double {
	let s: Double = Aero.stallAngle
	let m: Double = abs(a)
	let sign: Double = a >= 0 ? 1.0 : -1.0
	if m <= s { return Aero.liftSlope * a }
	let peak: Double = Aero.liftSlope * s
	let flat: Double = 0.9 * sin(2.0 * m)
	let fade: Double = clampD((m - s) / 0.16, 0, 1)
	return sign * (peak * 0.85 * (1.0 - fade) + flat * fade)
}

/// A wing's drag coefficient: a little on its own, more as it lifts, a flat plate's beyond the stall
func wingDrag(_ a: Double, _ cl: Double) -> Double {
	let sa: Double = sin(a)
	return 0.012 + 0.06 * cl * cl + 1.1 * sa * sa
}

/// How much a part catches the air (a bare block is 1)
func partDrag(_ t: PartType) -> Double {
	switch t {
	case .cockpit: return 0.45
	case .jet: return 0.3
	case .airProp, .tailRotor, .rotor: return 0.4
	case .envelope: return 3.0
	case .wheel, .offroadWheel: return 0.45
	case .headlight, .steering, .autopilot, .autoGun, .propeller, .paddle: return 0.5
	default: return 1.0
	}
}

/// The mass of a block built onto a vehicle: its building weight (planks 0.6, stone 2.5)
func vehicleBlockMass(_ b: Tile, _ t: PartType) -> Double {
	if b.isMod, t != .block, let m = ModRuntime.shared.blockDef(b), m.vehMass > 0 { return m.vehMass }
	return max(0.05, tileWeight(b))
}

/// How much water a cell pushes aside when under (its buoyancy): a solid block a whole cell (so wood
/// floats and stone sinks), anything else a little
func cellDisplacement(_ v: Vehicle, _ c: PartCell, _ t: PartType) -> Double {
	if t == .block, let b = v.blocks[c] { return b.solid ? 1.0 : 0.2 }
	if t == .ballast { return 0.15 + 0.85 * (1.0 - v.ballast) }
	if let k = v.spanOf[c], k != c { return 0 }
	return partDisplacement(t)
}

/// How much damage a part takes before it breaks off
func partHP(_ t: PartType) -> Double {
	switch t {
	case .hinge, .servo, .piston: return 35
	case .receiver: return 20
	case .bigWheel: return 70
	case .railWheel, .coupler: return 30
	case .ballast: return 40
	case .flap: return 22
	case .airBrake: return 18
	case .stabilizer: return 14
	case .armor: return 160
	case .track, .jet, .drill, .diamondDrill, .voidDrill, .cannon: return 55
	case .engine, .hull, .cargo, .frame, .offroadWheel: return 40
	case .cockpit, .rotor, .autoGun, .burner, .fuelTank: return 30
	case .wheel, .seat, .wing, .airProp: return 22
	case .elevator, .propeller, .paddle, .steering, .tailRotor, .autopilot: return 14
	case .headlight: return 10
	case .envelope: return 7
	case .block: return 30
	}
}

/// How much damage one cell takes before it breaks (a block by its hardness and weight)
func vehicleCellHP(_ v: Vehicle, _ c: PartCell, _ t: PartType) -> Double {
	if let b = v.blocks[c] {
		let base: Double = 8.0 + min(90.0, b.hardness * 14.0) + tileWeight(b) * 4.0
		return t == .block ? base : max(base, partHP(t))
	}
	return partHP(t)
}

/// What a cell taken off a vehicle gives back: its block, or the part
func vehicleCellItem(_ r: VCell) -> Item {
	if let b = r.tile { return .block(b) }
	return .part(r.type == .block ? .frame : r.type)
}

/// A block turned to face the other way (stairs rise the other way, a bed's head moves)
func mirroredTile(_ t: Tile) -> Tile {
	switch t {
	case .stairWoodR: return .stairWoodL
	case .stairWoodL: return .stairWoodR
	case .stairStoneR: return .stairStoneL
	case .stairStoneL: return .stairStoneR
	case .stairBrickR: return .stairBrickL
	case .stairBrickL: return .stairBrickR
	case .bedL: return .bedR
	case .bedR: return .bedL
	default: return t
	}
}

/// Blocks the assembler leaves in the world: the ground's own, liquids, lifts and portals
func canAssemble(_ t: Tile) -> Bool {
	if t == .air || t.liquid || t == .bedrock { return false }
	switch t {
	case .liftRail, .liftButton, .liftCar, .portalOn, .portalOff: return false
	default: return true
	}
}

/// Where a shot meets a vehicle: how far along its step, which vehicle, which cell
struct VehicleHit {
	var t: Double
	var v: Vehicle
	var cell: PartCell
}

extension Game {
	// MARK: power

	/// The engines' power goes where it is needed: driving wheels on a ground vehicle, every air
	/// propeller, every rotor (a rotor takes as much as three engines' worth, a propeller one and a half).
	/// The share for the wheels (1 for a car or a tank: they get it all)
	func groundShare(_ v: Vehicle) -> Double {
		let wheels: Double = v.wings == 0 && v.rotors == 0 ? 1.0 : 0.0
		let total: Double = wheels + Double(v.airProps) * 1.5 + Double(v.rotors) * 3.0
		return total <= 0 ? 0 : wheels / total
	}

	/// Engine power each air propeller and each rotor gets (in engines); `anyway` works it out as if
	/// fuelled and crewed (for the checklist)
	func airPower(_ v: Vehicle, anyway: Bool = false) -> (Double, Double) {
		if v.engines == 0 { return (0, 0) }
		if !anyway && (!(v.fuel > 0 || isCreative) || !(v.hasSeat && v.hasSteering)) { return (0, 0) }
		let wheels: Double = v.wings == 0 && v.rotors == 0 ? 1.0 : 0.0
		let total: Double = wheels + Double(v.airProps) * 1.5 + Double(v.rotors) * 3.0
		if total <= 0 { return (0, 0) }
		let e: Double = v.enginePower
		return (e * 1.5 / total, e * 3.0 / total)
	}

	/// The most the rotors can lift (force) here, at full blade pitch
	func rotorMax(_ v: Vehicle, anyway: Bool = false) -> Double {
		let p: (Double, Double) = airPower(v, anyway: anyway)
		return Aero.rotorLift * p.1 * v.rotorLift * (0.35 + 0.65 * airDensity(v.py))
	}

	/// The most the balloons can lift (force) here, at full heat
	func balloonMax(_ v: Vehicle) -> Double {
		if v.burners == 0 || v.envelopes == 0 { return 0 }
		let heated: Double = Double(min(v.envelopes, v.burners * Aero.burnerCells))
		return gravityG * Aero.envLift * heated * airDensity(v.py)
	}

	/// The wings' lift at a speed, flying level at a good angle (for the checklist and instruments)
	func wingLiftAt(_ v: Vehicle, _ speed: Double) -> Double {
		return Aero.kLift * speed * speed * Double(v.wings) * 1.1
	}

	/// The push the propellers and jets give at a speed, at full throttle
	func thrustAt(_ v: Vehicle, _ speed: Double) -> Double {
		let p: (Double, Double) = airPower(v, anyway: true)
		let prop: Double = Aero.propThrust * p.0 * Double(v.airProps) * max(0, 1.0 - speed / Aero.propVmax)
		let jet: Double = Aero.jetThrust * Double(v.jets) * max(0.35, 1.0 - speed / 90.0)
		return prop + jet
	}

	// MARK: the flight model

	/// Forces of the air on every part, for one physics step: drag on each part's exposed faces, lift on
	/// wings and elevators from the real airflow over each one (its speed, the angle it meets the wing at,
	/// the wind), thrust from propellers and jets along the vehicle's axis, rotor lift along the rotor
	/// shaft, and the hot air in the balloons pushing straight up. Each force acts at its own part, so the
	/// layout decides how the vehicle pitches: a tail far behind steadies it, balloons above keep it
	/// upright, a heavy nose tips it forward.
	func airForces(_ v: Vehicle, _ h: Double, _ throttle: Double) {
		let c: Double = v.cosA
		let s: Double = v.sinA
		let rho: Double = airDensity(v.py)
		let power: (Double, Double) = airPower(v)
		let canFly: Bool = (v.fuel > 0 || isCreative) && v.hasSeat && v.hasSteering
		// while turning round the throttle keeps pushing toward the nose, whichever way the stick points
		let steer: Double = v.turnT > 0 ? abs(throttle) * Double(v.fwd) : throttle
		let thr: Double = canFly ? steer : 0
		// the elevators turn the nose the way the stick says (up: toward the top of the screen)
		let noseX: Double = Double(v.fwd) * c
		let noseSign: Double = noseX >= 0 ? 1.0 : -1.0
		let rateErr: Double = pitchRateWanted(v) - (-v.angVel * noseSign)
		let cmd: Double = clampD(v.trim + Aero.rateGain * rateErr, -1, 1)
		let wantSpin: Double = -cmd * noseSign
		let bank: Double = v.turnT > 0 ? 0.7 + 0.3 * abs(cos(Double.pi * v.turnT)) : 1.0
		let rotorF: Double = Aero.rotorLift * power.1 * v.collective * (0.35 + 0.65 * rho)
		let heated: Double = v.envelopes > 0 ? min(1.0, Double(v.burners * Aero.burnerCells) / Double(v.envelopes)) : 0
		let envF: Double = gravityG * Aero.envLift * v.heat * heated * rho
		var fx: Double = 0
		var fy: Double = 0
		var torque: Double = 0
		var lift: Double = 0
		var thrust: Double = 0
		var stalled: Bool = false
		var alpha: Double = 0
		for (cell, t) in v.parts {
			let lx: Double = Double(cell.dx) + 0.5 - v.comX
			let ly: Double = Double(cell.dy) + 0.5 - v.comY
			let rx: Double = lx * c - ly * s
			let ry: Double = lx * s + ly * c
			// the air going past this part (the wind, less the part's own motion), in the vehicle's frame
			let ux: Double = v.windX - (v.vx - v.angVel * ry)
			let uy: Double = -(v.vy + v.angVel * rx)
			let bx: Double = ux * c + uy * s
			let by: Double = -ux * s + uy * c
			var fbx: Double = 0
			var fby: Double = 0
			let k: Double = v.boost[cell] ?? 1.0
			if t == .wing || t == .elevator || t == .flap || t == .stabilizer {
				// (its tilt, and a flap's drop when slow, turn the wing further into the air)
				var extra: Double = Double(v.tilt[cell] ?? 0) * Aero.tiltStep
				if t == .flap { extra += Aero.flapDrop * clampD((Aero.flapSpeed - v.airspeed) / (Aero.flapSpeed * 0.5), 0, 1) }
				let wide: Bool = t == .wing || t == .flap
				let f: (Double, Double, Double, Bool, Double) = wingForce(t, bx, by, lx, rho, wantSpin, wide ? bank * k : k, extra)
				fbx = f.0
				fby = f.1
				if t == .wing || t == .flap {
					lift += f.2
					alpha = max(alpha, f.4)
				}
				if f.3 { stalled = true }
			} else {
				let d: (Double, Double) = faceDrag(v, cell, t, bx, by, rho)
				fbx = d.0
				fby = d.1
				switch t {
				case .airProp:
					if power.0 > 0 && abs(thr) > 0.05 && !v.boxed.contains(cell) {
						// along the vehicle's axis either way (the blades reverse at half strength)
						let eff: Double = max(0, 1.0 - abs(bx) / Aero.propVmax)
						let w: Double = thr > 0 ? thr : thr * 0.5
						let f: Double = Aero.propThrust * power.0 * eff * w * k * (0.4 + 0.6 * rho)
						fbx += f
						thrust += abs(f)
					}
				case .jet:
					if canFly && abs(thr) > 0.05 && !v.boxed.contains(cell) {
						// it pushes away from its exhaust; pulled back, its reverser brakes at a third
						let dirX: Double = -Double((v.face[cell] ?? (-1, 0)).0)
						let along: Double = thr * dirX
						let w: Double = along > 0 ? along : along * 0.35
						let f: Double = Aero.jetThrust * w * k * dirX * (0.7 + 0.3 * rho) * max(0.35, 1.0 - abs(bx) / 90.0)
						fbx += f
						thrust += abs(f)
					}
				case .airBrake:
					if v.brakeOpen > 0.01 {
						// a panel across the flow: drag by how far it is open
						let q: Double = Aero.brakeDrag * Aero.kDrag * rho * v.brakeOpen * k
						fbx += q * bx * abs(bx)
						fby += q * by * abs(by)
					}
				case .rotor:
					if rotorF > 0 {
						// (blades with parts in their way lift by the room they have)
						let room: Double = v.rotorRoom[cell] ?? 1.0
						fby -= rotorF * k * room
						lift += rotorF * k * room
						// the disc drags against air going across it
						fbx += Aero.rotorDrag * rho * bx * abs(bx) * min(1.0, v.collective * 1.5)
					}
				default:
					break
				}
			}
			// to the world, then onto the body at this part
			var wfx: Double = fbx * c - fby * s
			var wfy: Double = fbx * s + fby * c
			if t == .envelope && envF > 0 {
				// hot air rises: straight up, whatever the tilt (so balloons above keep it upright)
				wfy -= envF * k
				lift += envF * k
			}
			fx += wfx
			fy += wfy
			torque += rx * wfy - ry * wfx
			wfx = 0
			wfy = 0
		}
		let invM: Double = 1.0 / v.mass
		v.vx += fx * invM * h
		v.vy += fy * invM * h
		v.angVel += torque / v.inertia * h
		if v.rotors > 0 && rotorF > 0 { cyclic(v, thr, h) }
		v.liftNow = lift
		v.thrustNow = thrust
		v.stall = stalled
		v.alpha = alpha
	}

	/// The pitch rate the pilot asks for (nose up positive), eased off near the stall: past the guard
	/// angle the nose is brought down a little, so holding the stick back climbs steeply without stalling
	/// while there is speed (slow it down too far and it still sinks)
	func pitchRateWanted(_ v: Vehicle) -> Double {
		var want: Double = v.pitch * Aero.pitchRate
		// hands off in flight, the nose eases back toward level (it holds a gentle climb or dive no longer)
		if abs(v.pitch) < 0.05 && v.contacts == 0 && v.auto == 0 {
			let noseUp: Double = -Double(v.fwd) * v.sinA
			want = clampD(-noseUp * Aero.levelRate, -0.3, 0.3)
		}
		let guardA: Double = Aero.stallAngle * Aero.alphaGuard
		// the angle the wing is heading for: now, plus where the nose is still swinging
		let noseX: Double = Double(v.fwd) * v.cosA
		let upRate: Double = -v.angVel * (noseX >= 0 ? 1.0 : -1.0)
		let ahead: Double = v.alpha + max(0, upRate) * 0.3
		if v.wings > 0 && ahead > guardA && v.airspeed > 4.0 { want = min(want, -(ahead - guardA) * 5.0) }
		return want
	}

	/// One wing or elevator: lift across the airflow and drag along it, from the angle the air meets it
	/// (folded so the wing works flying either way), with an elevator's flap turned by the stick.
	/// Returns the body-frame force, the lift, and whether it has stalled.
	func wingForce(_ t: PartType, _ bx: Double, _ by: Double, _ lx: Double, _ rho: Double, _ wantSpin: Double, _ scale: Double, _ extra: Double = 0) -> (Double, Double, Double, Bool, Double) {
		let sp2: Double = bx * bx + by * by
		if sp2 < 0.09 { return (0, 0, 0, false, 0) }
		let sp: Double = sqrt(sp2)
		let dx: Double = bx / sp
		let dy: Double = by / sp
		var a: Double = atan2(-dy, -dx)
		if a > Double.pi * 0.5 { a -= Double.pi } else if a < -Double.pi * 0.5 { a += Double.pi }
		// the camber lifts toward the top of the wing whichever way the air comes; a tilt or a dropped flap
		// adds to it
		if t == .wing || t == .flap { a += dx < 0 ? Aero.camber : -Aero.camber }
		if extra != 0 { a += dx < 0 ? extra : -extra }
		var area: Double = 1.0
		if t == .stabilizer { area = Aero.stabArea }
		if t == .elevator {
			// the flap, tilted the way that turns the nose as asked (behind or ahead of the centre of mass)
			area = Aero.elevatorArea
			let flow: Double = bx < 0 ? 1.0 : -1.0
			let side: Double = lx >= 0 ? 1.0 : -1.0
			a += -wantSpin * side * flow * Aero.flap
		}
		let cl: Double = liftCoefficient(a)
		var cd: Double = wingDrag(a, cl)
		if t == .flap { cd += Aero.flapDrag * clampD(extra / Aero.flapDrop, 0, 1) }
		let q: Double = Aero.kLift * rho * sp2 * area * scale
		let fbx: Double = q * cl * -dy + q * Aero.dragShare * cd * dx
		let fby: Double = q * cl * dx + q * Aero.dragShare * cd * dy
		let stalled: Bool = (t == .wing || t == .flap) && abs(a) > Aero.stallAngle && sp > 4.0
		return (fbx, fby, abs(q * cl), stalled, sp > 4.0 ? abs(a) : 0)
	}

	/// Drag on a part's faces that meet the air (a face tucked behind another part barely feels it)
	func faceDrag(_ v: Vehicle, _ cell: PartCell, _ t: PartType, _ bx: Double, _ by: Double, _ rho: Double) -> (Double, Double) {
		let cdp: Double = partDrag(t) * Aero.kDrag * rho
		var fx: Double = 0
		var fy: Double = 0
		if abs(bx) > 0.01 {
			let up: Int = bx < 0 ? 1 : -1
			let ex: Double = v.parts[PartCell(dx: cell.dx + up, dy: cell.dy)] == nil ? 1.0 : Aero.shielded
			fx = cdp * ex * bx * abs(bx)
		}
		if abs(by) > 0.01 {
			let up: Int = by < 0 ? 1 : -1
			let ey: Double = v.parts[PartCell(dx: cell.dx, dy: cell.dy + up)] == nil ? 1.0 : Aero.shielded
			let canopy: Double = t == .envelope ? Aero.canopyDrag : 1.0
			fy = cdp * ey * canopy * by * abs(by)
		}
		return (fx, fy)
	}

	/// The cyclic: the rotor tilts the helicopter toward the stick and holds it there (so it flies
	/// that way). A single rotor needs a tail rotor for this; without one its torque swings the
	/// helicopter round and it can hardly be steered. Two rotors turn opposite ways and need none.
	func cyclic(_ v: Vehicle, _ thr: Double, _ h: Double) {
		let steady: Bool = v.openTails > 0 || v.rotors >= 2
		// the stick tilts it; hands off it leans against its drift and comes to a hover
		var target: Double = clampD(thr, -1, 1) * Aero.cyclicTilt
		if abs(thr) < 0.1 { target = clampD(-v.vx * Aero.hoverHold, -Aero.cyclicTilt, Aero.cyclicTilt) }
		let a: Double = remainder(v.angle, 2.0 * Double.pi)
		let auth: Double = (0.35 + 0.65 * v.collective) * (steady ? 1.0 : 0.2)
		// the trim builds up against a steady pull (an off-centre rotor or load) so the tilt holds
		if steady { v.cycI = clampD(v.cycI + (target - a) * Aero.cyclicI * h, -12, 12) }
		v.angVel += (Aero.cyclicP * (target - a) + v.cycI - Aero.cyclicD * v.angVel) * auth * h
		if !steady { v.angVel += sin(clock * 2.3 + Double(v.id)) * 4.0 * v.collective * h }
	}

	/// Once a frame: blade pitch and burner heat follow the stick (hands off, they hold the height), the
	/// elevator trim settles, and the nose end is worked out from the way the vehicle moves
	func flightControls(_ v: Vehicle, _ dt: Double) {
		let piloted: Bool = (v.rider || v.auto != 0) && v.hasSeat && v.hasSteering
		let airborne: Bool = v.contacts == 0 && v.submerged <= 0.02
		let along: Double = v.vx * v.cosA + v.vy * v.sinA
		if abs(along) > 3.0 { v.fwd = along > 0 ? 1 : -1 }
		else if abs(v.throttle) > 0.2 && v.rider { v.fwd = v.throttle > 0 ? 1 : -1 }
		if v.rotors > 0 {
			if !piloted || airPower(v).1 <= 0 {
				v.collective = max(0, v.collective - dt * 0.4)
			} else if airborne || v.pitch > 0.05 {
				// the stick asks for a climb or sink rate (hands off: none, a hover); the blade pitch is set
				// for it, as far as the rotor can lift
				let need: Double = max(0, v.mass * gravityG - balloonLiftNow(v))
				let hover: Double = need / max(1.0, rotorMax(v))
				let wantVy: Double = -v.pitch * Aero.climbRate
				let want: Double = clampD(hover + (v.vy - wantVy) * 0.05, 0, 1)
				let step: Double = Aero.collectiveRate * dt
				v.collective += clampD((want - v.collective) * min(1.0, 4.0 * dt), -step, step)
			} else {
				v.collective = max(0, v.collective - dt * 0.6)
			}
			if !airborne { v.cycI *= (1.0 - min(1.0, 2.0 * dt)) }
		}
		if v.burners > 0 && v.envelopes > 0 {
			let fuelOK: Bool = v.fuel > 0 || isCreative
			if !piloted || !fuelOK {
				v.heat = max(0, v.heat - dt * 0.035)
			} else if abs(v.pitch) > 0.05 {
				v.heat = clampD(v.heat + v.pitch * (v.pitch > 0 ? Aero.heatRate : Aero.ventRate) * dt, 0, 1)
			} else if airborne {
				// hands off: the burner keeps the balloon just warm enough to float (no faster than it can heat)
				let full: Double = balloonMax(v)
				let need: Double = max(0, v.mass * gravityG - v.liftNow + balloonLiftNow(v))
				let eq: Double = full > 1 ? need / full : 0
				let want: Double = clampD(eq + v.vy * 0.05, 0, 1)
				v.heat += clampD(want - v.heat, -Aero.ventRate * dt, Aero.heatRate * dt)
			} else {
				v.heat = max(0, v.heat - dt * 0.05)
			}
		}
		if v.elevators > 0 {
			if airborne && v.turnT == 0 {
				// the trim learns the elevator that gives the pitch rate asked for (hands off: none, so the
				// nose stays where it is)
				let noseX: Double = Double(v.fwd) * v.cosA
				let upRate: Double = -v.angVel * (noseX >= 0 ? 1.0 : -1.0)
				v.trim = clampD(v.trim + (pitchRateWanted(v) - upRate) * Aero.trimRate * dt, -0.9, 0.9)
			} else if !airborne {
				v.trim *= (1.0 - min(1.0, 0.8 * dt))
			}
		}
	}

	/// The balloons' lift right now (force)
	func balloonLiftNow(_ v: Vehicle) -> Double {
		return balloonMax(v) * v.heat
	}

	/// Fuel for what flies: rotors turning, jets, burners (driving and propellers already burn it)
	func airFuel(_ v: Vehicle, _ dt: Double) {
		if isCreative || v.fuel <= 0 { return }
		var use: Double = 0
		let thr: Double = abs(v.throttle)
		if v.rotors > 0 && v.collective > 0.05 && thr <= 0.1 { use += Double(v.engines) * (0.4 + 0.6 * v.collective) }
		if v.jets > 0 && thr > 0.05 && (v.rider || v.auto != 0) { use += Double(v.jets) * 2.5 * thr }
		if v.burners > 0 && v.heat > 0.05 && (v.rider || v.auto != 0) { use += Double(v.burners) * 0.6 * v.heat }
		v.fuel = max(0, v.fuel - use * dt)
	}
}

extension Game {
	// MARK: every frame

	/// What a vehicle does besides moving, once a frame (even at rest): the flight controls and fuel,
	/// the guns, the autopilot when nobody drives, a turn in progress, rotor blades striking the ground,
	/// fuel tanks that burst
	func vehicleExtras(_ v: Vehicle, _ dt: Double) {
		if v.parts.isEmpty { return }
		if v.hitT > 0 { v.hitT -= dt }
		ballastAndBrakes(v, dt)
		updateHullAir(v, dt)
		if !v.asleep || v.aero { v.windX = windAtVehicle(v) * 0.6 }
		if v.aero {
			if v.auto != 0 && !v.rider { autopilotSteer(v, 0, 0, dt) }
			flightControls(v, dt)
			airFuel(v, dt)
			if v.rotors > 0 { rotorBlades(v, dt) }
			let spin: Double = v.rotors > 0 ? v.collective : min(1.0, abs(v.throttle))
			if v.rotors + v.airProps + v.tailRotors > 0 && airPower(v).0 + airPower(v).1 > 0 { v.propRot += dt * (4.0 + 26.0 * spin) }
			v.airspeed = sqrt((v.vx - v.windX) * (v.vx - v.windX) + v.vy * v.vy)
		} else if v.auto != 0 && !v.rider {
			autopilotSteer(v, 0, 0, dt)
		}
		if v.turnT > 0 { stepTurn(v, dt) }
		if v.cannons + v.guns > 0 { runVehicleWeapons(v, dt) }
	}

	/// Fuel tanks that burst last frame go off now
	func flushVehicleBlasts() {
		if vehBlasts.isEmpty { return }
		let list: [(Double, Double)] = vehBlasts
		vehBlasts.removeAll()
		for b in list { explode(b.0, b.1, radius: 2.0, power: 14, source: .environment, breakBlocks: false) }
	}

	/// Rotor blades sweep a line two cells either side of the hub; if they cut into the ground the
	/// rotor is wrecked in a moment
	func rotorBlades(_ v: Vehicle, _ dt: Double) {
		if v.collective < 0.05 && v.propRot == 0 { return }
		if !(airPower(v).1 > 0) { return }
		var struck: PartCell? = nil
		for (c, t) in v.parts where t == .rotor {
			var k: Double = -2.4
			while k <= 2.41 {
				let p: (Double, Double) = v.toWorld(Double(c.dx) + 0.5 + k, Double(c.dy) + 0.02)
				if world.solid(Int(floor(p.0)), Int(floor(p.1))) { struck = c; break }
				k += 0.8
			}
			if struck != nil { break }
		}
		guard let c = struck else { v.bladeHit = 0; return }
		v.bladeHit += dt
		let at: (Double, Double) = v.cellCenter(c)
		if Double.random(in: 0...1) < 0.4 { spawnParticles(at.0, at.1 - 0.5, 0xFFE080, 2, 4.0, 0.25, 8) }
		damageVehicle(v, c, 40.0 * dt, at.0, at.1)
	}

	// MARK: damage

	/// A hard landing or a crash: each part that hit the ground too fast takes damage by how much too fast
	func crashDamage(_ v: Vehicle, _ crash: [PartCell: Double]) {
		if !settings.vehicleDamage { return }
		var worst: Double = 0
		for (c, over) in crash where v.parts[c] != nil {
			let at: (Double, Double) = v.cellCenter(c)
			damageVehicle(v, c, over * 3.2 * (1.0 + v.mass / 30.0), at.0, at.1)
			worst = max(worst, over)
		}
		if worst > 0 {
			addShake(min(0.8, 0.2 + worst * 0.05))
			sfx(.land, at: v.px, 0.9)
		}
	}

	/// Damage to one cell; when it has taken all it can, it breaks off
	func damageVehicle(_ v: Vehicle, _ c: PartCell, _ amount: Double, _ x: Double, _ y: Double) {
		guard let t = v.parts[c], amount > 0 else { return }
		if !settings.vehicleDamage { return }
		let hp: Double = vehicleCellHP(v, c, t) * (v.boost[c] ?? 1.0)
		let d: Double = (v.dmg[c] ?? 0) + amount
		v.dmg[c] = d
		v.hitT = 0.15
		if d >= hp { breakVehicleCell(v, c) }
	}

	/// A cell breaks off: it flies off as debris (a block keeps flying as a falling block), whatever is no
	/// longer joined to the driver's part becomes a wreck of its own, falling with its own physics, and a
	/// burst fuel tank goes off
	func breakVehicleCell(_ v: Vehicle, _ c: PartCell) {
		guard let t = v.parts[c] else { return }
		let at: (Double, Double) = v.cellCenter(c)
		let pv: (Double, Double) = (v.vx - v.angVel * (at.1 - v.py), v.vy + v.angVel * (at.0 - v.px))
		let color: UInt32 = v.blocks[c].map { $0.def.colors.first ?? 0x8A8A8A } ?? 0x8A8A94
		spawnParticles(at.0, at.1, color, 10, 4.5, 0.6, 14)
		spawnParticles(at.0, at.1, 0x5A5A5A, 6, 2.5, 0.9, -2)
		sfx(v.blocks[c] != nil && toolClass(v.blocks[c]!) == .axe ? .breakWood : .breakStone, at: at.0, 0.9)
		addShake(0.2)
		if t == .fuelTank && (v.fuel > 4 || isCreative) { vehBlasts.append(at) }
		if t == .envelope { spawnParticles(at.0, at.1, 0xF0E4D0, 6, 5.0, 0.4, 4) }
		// what the stores carried spills out of every store that comes away
		let stores: [(PartCell, (Double, Double))] = v.parts.keys.filter { vehicleStores(v, $0) }.map { ($0, v.cellCenter($0)) }
		let seat: PartCell? = seatCell(v)
		let wasDriver: Bool = v.rider && inVehicle === v
		// the transform before anything changes: the wrecks keep their place in the world
		let old: Vehicle = v
		var off: [VCell] = old.cutAway(c, keep: seat == c ? nil : seat)
		if let first = off.first, first.cell == c {
			off.removeFirst()
			if let b = first.tile, b.solid, fallingBlocks.count < 120 {
				var fb: FallingBlock = FallingBlock(x: at.0, y: at.1 + 0.5, vy: pv.1 - 3.0, tile: b, uid: newID())
				fb.vx = pv.0 + Double.random(in: -2...2)
				fb.mass = max(0.2, tileWeight(b))
				fb.spin = Double.random(in: -6...6)
				fb.flung = true
				fallingBlocks.append(fb)
			} else if Double.random(in: 0...1) < 0.35 {
				spawnDrop(Stack(item: vehicleCellItem(first), count: 1), at.0, at.1, pv.0 * 0.5, -4)
			}
		}
		if !off.isEmpty { makeWrecks(old, off) }
		for (sc, sp) in stores where v.parts[sc] == nil {
			let k: IntPair = cargoSpot(v, sc)
			if let p = openChest, p == k { openChest = nil }
			for st in world.removeChest(k.x, k.y) { spawnDrop(st, sp.0, sp.1, Double.random(in: -2...2), -3.5) }
		}
		if v.parts.isEmpty {
			if wasDriver { dismount() }
			return
		}
		v.recompute(keepAnchor: true)
		v.kit = -1
		if wasDriver && (seatCell(v) == nil || !v.hasSteering) {
			dismount()
			say("Your seat was shot away!", 2.0)
		}
		bumpHUD()
	}

	/// Pieces broken off a vehicle become wrecks: vehicles of their own (no seat, so nobody drives them)
	/// that keep the place, turn and speed they had
	func makeWrecks(_ from: Vehicle, _ cells: [VCell]) {
		var left: [PartCell: VCell] = [:]
		for r in cells { left[r.cell] = r }
		while let start = left.keys.first {
			var group: [VCell] = []
			var stack: [PartCell] = [start]
			while let cur = stack.popLast() {
				guard let r = left[cur] else { continue }
				left[cur] = nil
				group.append(r)
				let n: [PartCell] = [PartCell(dx: cur.dx + 1, dy: cur.dy), PartCell(dx: cur.dx - 1, dy: cur.dy), PartCell(dx: cur.dx, dy: cur.dy + 1), PartCell(dx: cur.dx, dy: cur.dy - 1)]
				for k in n where left[k] != nil { stack.append(k) }
			}
			if vehicles.count >= 40 {
				for r in group {
					let p: (Double, Double) = from.cellCenter(r.cell)
					if Double.random(in: 0...1) < 0.4 { spawnDrop(Stack(item: vehicleCellItem(r), count: 1), p.0, p.1, 0, -3) }
				}
				continue
			}
			let w: Vehicle = Vehicle(id: newID(), first: .frame, x: 0, y: 0)
			w.parts.removeAll()
			for r in group {
				w.parts[r.cell] = r.type
				if let b = r.tile { w.blocks[r.cell] = b }
			}
			w.recompute(keepAnchor: false)
			let p: (Double, Double) = from.toWorld(w.comX, w.comY)
			w.px = p.0
			w.py = p.1
			w.angle = from.angle
			w.vx = from.vx - from.angVel * (p.1 - from.py) + Double.random(in: -1.5...1.5)
			w.vy = from.vy + from.angVel * (p.0 - from.px) - 2.0
			w.angVel = from.angVel + Double.random(in: -1.5...1.5)
			w.updateBox()
			vehicles.append(w)
		}
	}

	/// Blasts damage every part in reach (less further out) and shove the vehicle away
	func blastVehicles(_ x: Double, _ y: Double, radius: Double, power: Double) {
		let list: [Vehicle] = vehicles
		for v in list {
			if v.b.right < x - radius - 1 || v.b.left > x + radius + 1 || v.b.y < y - radius - 1 || v.b.top > y + radius + 1 { continue }
			var hits: [(PartCell, Double)] = []
			for (c, _) in v.parts {
				let p: (Double, Double) = v.cellCenter(c)
				let d: Double = sqrt((p.0 - x) * (p.0 - x) + (p.1 - y) * (p.1 - y))
				if d > radius + 0.5 { continue }
				hits.append((c, power * 1.1 * (1.0 - 0.6 * clampD(d / max(0.5, radius), 0, 1))))
			}
			if hits.isEmpty { continue }
			let dx: Double = v.px - x
			let dy: Double = v.py - y
			let dl: Double = max(0.5, sqrt(dx * dx + dy * dy))
			let push: Double = power * 0.9 * Double(hits.count) / Double(max(1, v.parts.count)) / max(1.0, v.mass * 0.25)
			v.vx += dx / dl * min(14.0, push)
			v.vy += dy / dl * min(14.0, push) - 1.0
			v.asleep = false
			for h in hits where v.parts[h.0] != nil {
				let p: (Double, Double) = v.cellCenter(h.0)
				damageVehicle(v, h.0, h.1, p.0, p.1)
			}
		}
	}

	/// The first vehicle cell a shot's step passes through. Shots from monsters, and from other vehicles'
	/// guns, hit vehicles; the player's own shots pass their vehicles, and a gun never hits its own vehicle.
	func vehicleOnPath(_ p: Projectile, _ nx: Double, _ ny: Double, maxT: Double) -> VehicleHit? {
		let fromVehicle: Bool = p.owner >= 2_000_000
		if p.source.kind == .player && !fromVehicle { return nil }
		var best: VehicleHit? = nil
		var bt: Double = min(1.0, maxT)
		let x0: Double = min(p.x, nx)
		let x1: Double = max(p.x, nx)
		let y0: Double = min(p.y, ny)
		let y1: Double = max(p.y, ny)
		for v in vehicles {
			if fromVehicle && p.owner == 2_000_000 + machineRoot(v).id { continue }
			if x1 < v.b.left || x0 > v.b.right || y1 < v.b.top || y0 > v.b.y { continue }
			let a: (Double, Double) = v.toLocal(p.x, p.y)
			let b: (Double, Double) = v.toLocal(nx, ny)
			let len: Double = sqrt((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1))
			let n: Int = max(1, Int(ceil(len / 0.2)))
			var i: Int = 0
			while i <= n {
				let t: Double = Double(i) / Double(n)
				if t > bt { break }
				let lx: Double = a.0 + (b.0 - a.0) * t
				let ly: Double = a.1 + (b.1 - a.1) * t
				let c: PartCell = PartCell(dx: Int(floor(lx)), dy: Int(floor(ly)))
				if v.parts[c] != nil {
					bt = t
					best = VehicleHit(t: t, v: v, cell: c)
					break
				}
				i += 1
			}
		}
		return best
	}

	/// A shot strikes a vehicle part
	func shotHitsVehicle(_ p: Projectile, _ vh: VehicleHit, _ x: Double, _ y: Double) {
		if p.kind == .shell {
			shellBurst(p, x, y)
			return
		}
		if p.mod >= 0 { modShotLanded(p, x, y, mob: nil, player: false) }
		var amount: Double = p.dmg
		if p.kind == .fireball { amount *= 1.3 }
		if vh.v.parts[vh.cell] == .armor { spawnParticles(x, y, 0xFFE8A0, 4, 4.0, 0.2, 6) } else { spawnParticles(x, y, 0xC8C8C8, 3, 3.0, 0.3, 10) }
		sfx(.arrowHit, at: x, 0.5)
		damageVehicle(vh.v, vh.cell, amount, x, y)
	}

	/// A cannon shell bursts: a small blast that breaks and throws blocks like a bomb's
	func shellBurst(_ p: Projectile, _ x: Double, _ y: Double) {
		// a suit's mini cannon: a small blast that leaves the ground alone
		if p.owner == suitShellOwner {
			explode(x, y, radius: 1.4, power: p.dmg, source: p.source, breakBlocks: false)
			return
		}
		explode(x, y, radius: 2.3, power: p.dmg, source: p.source, breakBlocks: true)
	}

	// MARK: weapons

	/// The guns turn toward where the driver aims (each within its own arc) and fire while the attack
	/// stick is held. Cannons fire shells (one gunpowder each) and kick the vehicle back; machine guns
	/// fire a stream of bullets.
	func runVehicleWeapons(_ v: Vehicle, _ dt: Double) {
		for (c, cd) in v.gunCD where cd > 0 { v.gunCD[c] = cd - dt }
		// (a gun on any section of a machine answers whoever drives the machine)
		let driving: Bool = playerDrives(v)
		let firing: Bool = driving && useHeld && aimValid
		let buttons: [Bool] = machineButtonsHeld(v, driving)
		for (c, t) in v.parts where t == .cannon || t == .autoGun {
			let f: (Int, Int) = v.face[c] ?? (1, 0)
			let base: Double = v.angle + atan2(Double(f.1), Double(f.0))
			let o: (Double, Double) = v.cellCenter(c)
			var want: Double = base
			if driving && aimValid { want = atan2(aimY - o.1, aimX - o.0) }
			var shoot: Bool = firing
			let mode: GunMode = GunMode(rawValue: v.gunMode[c] ?? 0) ?? .driver
			switch mode {
			case .driver:
				break
			case .auto:
				// a turret picks its own target and fires by itself
				shoot = false
				if let tg = turretTarget(v, c, o, base) {
					want = atan2(tg.1 - o.1, tg.0 - o.0)
					shoot = true
				}
			case .buttonA, .buttonB, .buttonC:
				shoot = buttons[mode.rawValue - GunMode.buttonA.rawValue]
			case .signal:
				shoot = machineSignalOn(v)
			}
			let rel: Double = clampD(remainder(want - base, 2.0 * Double.pi), -Radio.gunArc, Radio.gunArc)
			let a: Double = base + rel
			let cur: Double = v.aimAng[c] ?? base
			let turn: Double = remainder(a - cur, 2.0 * Double.pi)
			let rate: Double = (t == .cannon ? 3.0 : 6.0) * dt
			let na: Double = cur + clampD(turn, -rate, rate)
			v.aimAng[c] = na
			if shoot && (v.gunCD[c] ?? 0) <= 0 && abs(remainder(want - na, 2.0 * Double.pi)) < 0.35 && !v.boxed.contains(c) {
				fireVehicleGun(v, c, t, na, o)
			}
		}
	}

	func fireVehicleGun(_ v: Vehicle, _ c: PartCell, _ t: PartType, _ a: Double, _ o: (Double, Double)) {
		let cannon: Bool = t == .cannon
		if !isCreative {
			let ammo: Item = cannon ? .mat(.gunpowder) : .ammo(.bullet)
			if !inv.remove(ammo, 1) {
				v.gunCD[c] = 1.0
				if vehSayT <= clock {
					vehSayT = clock + 3.0
					say(cannon ? "The cannon needs gunpowder." : "The machine gun needs bullets.", 2.0)
				}
				return
			}
		}
		let k: Double = v.boost[c] ?? 1.0
		let mx: Double = o.0 + cos(a) * 0.9
		let my: Double = o.1 + sin(a) * 0.9
		// a mod's gun block can fire its own shot, as fast, as hard and as often as its maker set
		let gun: ModGunRT = modGun(v, c)
		let speed: Double = gun.speed > 0 ? gun.speed : (cannon ? 34.0 : 44.0)
		let dmg: Double = (gun.damage > 0 ? gun.damage : (cannon ? 24 : 4.5)) * k
		var grav: Double = cannon ? 14 : 3
		var life: Double = cannon ? 4.0 : 1.3
		var kind: ProjKind = cannon ? .shell : .bullet
		var w: Double = cannon ? 0.35 : 0.15
		if gun.shot >= 0 && gun.shot < ModRuntime.shared.shots.count {
			let ms: ModProjectile = ModRuntime.shared.shots[gun.shot]
			grav = ms.gravity
			life = ms.life
			kind = .spit
			w = ms.size
		}
		var p = Projectile(kind: kind, x: mx, y: my, vx: cos(a) * speed + v.vx, vy: sin(a) * speed + v.vy, dmg: dmg, fromPlayer: true, gravity: grav)
		p.life = life
		p.w = w
		p.mod = gun.shot
		p.source = .player
		// (the shot passes every section of the machine it came from)
		p.owner = 2_000_000 + machineRoot(v).id
		p.uid = newID()
		p.knock = cannon ? 9 : 3
		projectiles.append(p)
		v.gunCD[c] = gun.rate > 0 ? 1.0 / gun.rate : (cannon ? 2.0 : 0.13)
		if cannon {
			// the recoil kicks the vehicle back, around the cannon
			let j: Double = 10.0
			let rx: Double = o.0 - v.px
			let ry: Double = o.1 - v.py
			let jx: Double = -cos(a) * j
			let jy: Double = -sin(a) * j
			v.vx += jx / v.mass
			v.vy += jy / v.mass
			v.angVel += (rx * jy - ry * jx) / v.inertia
			v.asleep = false
			spawnParticles(mx, my, 0xFFC050, 8, 5.0, 0.25, 2)
			spawnParticles(mx, my, 0x8A8A8A, 6, 2.0, 0.8, -3)
			addShake(0.25)
			sfx(.blunderbuss, at: mx, 0.9)
		} else {
			if Double.random(in: 0...1) < 0.5 { spawnParticles(mx, my, 0xFFE080, 2, 3.0, 0.12, 0) }
			sfx(.gun, at: mx, 0.3)
		}
	}

	/// Where the guns aim with the attack stick held but not pushed: the nearest foe in range and in
	/// sight, led a little for its speed (nil: none, the guns look ahead)
	func vehicleAutoAim(_ v: Vehicle) -> (Double, Double)? {
		var best: Mob? = nil
		var bd: Double = 26.0
		for m in mobsNear(v.px - 26, v.px + 26) where m.hp > 0 && !m.removed && !m.downed && isThreat(m) {
			let d: Double = abs(m.b.x - v.px) + abs(m.b.cy - v.py) * 0.7
			if d < bd && world.lineClear(v.px, v.py, m.b.x, m.b.cy) {
				bd = d
				best = m
			}
		}
		guard let m = best else { return nil }
		let lead: Double = bd / 40.0
		return (m.b.x + m.b.vx * lead, m.b.cy + m.b.vy * lead)
	}

	// MARK: repairs and storage

	/// Holding an iron bar, a tap on a damaged part mends it (the bar is used up)
	func repairVehiclePart(_ v: Vehicle, _ c: PartCell) -> Bool {
		guard let it = heldItem, it == .mat(.ironBar), let d = v.dmg[c], d > 0.5 else { return false }
		v.dmg[c] = nil
		if !isCreative { inv.removeAt(sel, 1) }
		let p: (Double, Double) = v.cellCenter(c)
		spawnParticles(p.0, p.1, 0xFFE8A0, 6, 2.5, 0.4, 4)
		sfx(.craft, at: p.0, 0.6)
		say("Mended.", 1.0)
		bumpHUD()
		return true
	}

	/// Cells that hold things: cargo crates, and chests, cabinets, wardrobes or a mod's storage built on
	func vehicleStores(_ v: Vehicle, _ c: PartCell) -> Bool {
		guard let t = v.parts[c] else { return false }
		if t == .cargo { return true }
		guard t == .block, let b = v.blocks[c] else { return false }
		if b == .chest || b == .cabinet || b == .wardrobe { return true }
		if b.isMod, ModRuntime.shared.blockDef(b)?.function == .storage { return true }
		return false
	}

	/// Puts a whole stack (infusions and all) in the bag, dropping what does not fit
	func giveStack(_ st: Stack) {
		let left: Int = inv.add(st.item, st.count, extra: st.extra, inf: st.inf)
		if left > 0 {
			var rest: Stack = st
			rest.count = left
			spawnDrop(rest, pb.x, pb.y - 1.0, Double(facing) * 3.0, -4.0)
		}
		bumpHUD()
	}

	/// What the controls do in this vehicle (said when getting in)
	func controlsHint(_ v: Vehicle) -> String {
		if v.ballasts > 0 && v.wings == 0 && v.rotors == 0 { return "Under way. Stick down floods the ballast tanks to dive, up blows them to rise; left and right: the propeller." }
		if v.rotors > 0 { return "Flying. Stick up and down: climb and sink (let go to hover). Left and right: tilt and fly that way." }
		if v.burners > 0 && v.envelopes > 0 { return "Ballooning. Stick up: heat the balloon and rise; down: let it cool and sink. Left and right: the propellers." }
		if v.wings > 0 { return "Flying. Left and right: the throttle. Up and down: pitch the nose (gather speed on the ground, then pull up). TURN turns round." }
		if v.tracks > 0 { return "Driving a tracked vehicle: slow, but it climbs anything. Jump to get up from the seat." }
		return "Driving. Hold the stick to move; in the air it tilts the vehicle. Jump to get up from the seat."
	}
}

extension Game {
	// MARK: turning round

	/// TURN is offered while driving: in flight it is a banked turn out of the screen and back; standing
	/// still (or nearly), the vehicle simply faces the other way if it has room
	var canTurnVehicle: Bool {
		guard let v = inVehicle else { return false }
		return v.turnT == 0 && (v.aero || v.speed < 2.0)
	}

	func turnVehicle() {
		guard let v = drivenVehicle, v.turnT == 0 else { return }
		if !v.joints.isEmpty || v.parentID != 0 {
			say("A machine with joints can't turn round: drive it the other way.", 2.0)
			return
		}
		let flying: Bool = v.aero && v.contacts == 0 && v.submerged <= 0.02 && v.speed > 3.0
		if flying {
			v.turnT = 0.001
			v.turnVX = v.vx
			v.turned = false
			v.asleep = false
			return
		}
		if v.speed > 2.0 {
			say("Slow down to turn round.", 1.5)
			return
		}
		if !mirrorVehicle(v, check: true) { say("No room to turn round here.", 1.8) }
	}

	/// A turn in flight: it banks round out of the screen and back (drawn narrowing to its edge and
	/// widening again), the wings lift a little less while banked, and halfway round it faces and flies
	/// the other way, keeping its airspeed less what the turn costs
	func stepTurn(_ v: Vehicle, _ dt: Double) {
		v.turnT = min(1.0, v.turnT + dt / Aero.turnTime)
		if !v.turned && v.turnT >= 0.5 {
			v.turned = true
			_ = mirrorVehicle(v, check: false)
			v.vx = -v.vx * 0.92
			for o in vehicles where o !== v && o.restOn == v.id { o.vx = v.vx; o.vy = v.vy }
		}
		if v.turnT >= 1.0 { v.turnT = 0 }
	}

	/// Mirrors a vehicle left to right about its centre of mass (it then faces the other way). With
	/// `check`, only if the mirrored vehicle fits where it is. Stores keep what they hold.
	@discardableResult
	func mirrorVehicle(_ v: Vehicle, check: Bool, depth: Int = 0) -> Bool {
		let sx: Int = v.minX + v.maxX
		if check {
			for (c, _) in v.parts {
				let p: (Double, Double) = v.cellCenter(c)
				let mx: Double = 2.0 * v.px - p.0
				if world.boxSolid(mx - 0.4, p.1 - 0.4, mx + 0.4, p.1 + 0.4) { return false }
			}
		}
		var np: [PartCell: PartType] = [:]
		var nb: [PartCell: Tile] = [:]
		var nd: [PartCell: Double] = [:]
		var moved: [(IntPair, [Stack])] = []
		for (c, t) in v.parts {
			let m: PartCell = PartCell(dx: sx - c.dx, dy: c.dy)
			np[m] = t
			if let b = v.blocks[c] { nb[m] = mirroredTile(b) }
			if let d = v.dmg[c] { nd[m] = d }
			if vehicleStores(v, c) {
				let k: IntPair = cargoSpot(v, c)
				if let p = openChest, p == k { openChest = nil }
				moved.append((cargoSpot(v, m), world.removeChest(k.x, k.y)))
			}
		}
		let cx: Double = v.px
		let cy: Double = v.py
		mirrorRiders(v, sx)
		// vehicles resting on it (a plane parked on a carrier) are turned round with it
		let carried: [Vehicle] = depth > 2 ? [] : vehicles.filter { $0 !== v && $0.restOn == v.id }
		let carriedAt: [(Double, Double)] = carried.map { v.toLocal($0.px, $0.py) }
		var nw: [PartCell: UInt8] = [:]
		for (c, k) in v.walls { nw[PartCell(dx: sx - c.dx, dy: c.dy)] = k }
		v.walls = nw
		var ns: [PartCell: PartCell] = [:]
		for (c, m) in v.spanOf { ns[PartCell(dx: sx - c.dx, dy: c.dy)] = PartCell(dx: sx - m.dx, dy: m.dy) }
		v.spanOf = ns
		for i in v.links.indices { v.links[i].cell = PartCell(dx: sx - v.links[i].cell.dx, dy: v.links[i].cell.dy) }
		if let st = v.seatAt { v.seatAt = PartCell(dx: sx - st.dx, dy: st.dy) }
		v.parts = np
		v.blocks = nb
		v.dmg = nd
		v.gunCD.removeAll()
		v.aimAng.removeAll()
		v.drillWork.removeAll()
		v.recompute(keepAnchor: false)
		v.angle = -v.angle
		v.angVel = -v.angVel
		v.px = cx
		v.py = cy
		v.dir = -v.dir
		v.fwd = -v.fwd
		v.kit = -1
		v.asleep = false
		v.updateBox()
		for m in moved { world.setChestItems(m.0.x, m.0.y, m.1) }
		for (i, o) in carried.enumerated() {
			let l: (Double, Double) = carriedAt[i]
			_ = mirrorVehicle(o, check: false, depth: depth + 1)
			let w: (Double, Double) = v.toWorld(Double(sx + 1) - l.0, l.1)
			o.px = w.0
			o.py = w.1
			o.vx = v.vx
			o.vy = v.vy
			o.updateBox()
		}
		return true
	}

	// MARK: building blocks onto vehicles

	/// The ON VEHICLE switch shows while a block is in hand near a vehicle
	var canBuildOnVehicle: Bool {
		guard inVehicle == nil, !dead, let it = heldItem, case .block(let t) = it else { return false }
		if t == .liftCar || t == .sapling || t.isPlant { return false }
		return nearestVehicle(8) != nil
	}

	func toggleVehicleBuild() {
		vehicleBuild.toggle()
		say(vehicleBuild ? "Blocks now go onto the vehicle: tap a green square." : "Blocks go into the world again.", 2.0)
		bumpHUD()
	}

	/// Builds the block in hand onto the vehicle at the aim point (it becomes one of its cells, with its
	/// weight, and moves with it). A mod block made to work as a vehicle part does that part's work.
	func attachBlockToVehicle(_ t: Tile) -> Bool {
		guard let (v, c) = vehicleCellAtAim() else {
			if nearestVehicle(8) == nil { return false }
			if placeCD <= 0 { say("Tap a green square next to the vehicle.", 1.5) }
			placeCD = 0.3
			return true
		}
		var part: PartType = .block
		if t.isMod, let d = ModRuntime.shared.blockDef(t), let p = d.vehRole.part { part = p }
		if let problem = attachProblem(v, c, part) {
			say(problem, 2.0)
			placeCD = 0.3
			return true
		}
		liftIfBuried(v, c)
		v.parts[c] = part
		v.blocks[c] = t
		v.recompute(keepAnchor: true)
		splitJointSections(v)
		v.kit = -1
		if t == .chest || t == .cabinet || t == .wardrobe { world.setChestItems(cargoSpot(v, c).x, cargoSpot(v, c).y, []) }
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.6)
		placeCD = 0.16
		swingT = 0.14
		bumpHUD()
		return true
	}

	/// Builds a door onto a vehicle at the aim point: two cells high where the cell above is free (one
	/// otherwise). True when the tap was for a vehicle.
	func attachDoorToVehicle() -> Bool {
		guard let (v, c) = vehicleCellAtAim() else { return nearestVehicle(8) != nil }
		if placeCD > 0 { return true }
		placeCD = 0.25
		if let problem = attachProblem(v, c, .block) {
			say(problem, 2.0)
			return true
		}
		v.parts[c] = .block
		v.blocks[c] = .doorClosed
		let up: PartCell = PartCell(dx: c.dx, dy: c.dy - 1)
		let down: PartCell = PartCell(dx: c.dx, dy: c.dy + 1)
		if v.parts[up] == nil { v.parts[up] = .block; v.blocks[up] = .doorClosed }
		else if v.parts[down] == nil { v.parts[down] = .block; v.blocks[down] = .doorClosed }
		v.recompute(keepAnchor: true)
		v.kit = -1
		if !isCreative { inv.removeAt(sel, 1) }
		sfx(.place, 0.6)
		swingT = 0.14
		bumpHUD()
		return true
	}

	/// The free cell next to a vehicle under the aim point (the one a block or part would go in)
	func vehicleCellAtAim() -> (Vehicle, PartCell)? {
		for v in vehicles {
			if aimX < v.b.left - 1.5 || aimX > v.b.right + 1.5 || aimY < v.b.top - 1.5 || aimY > v.b.y + 1.5 { continue }
			let c: PartCell = v.cellAt(aimX, aimY)
			if v.parts[c] == nil && v.hasNeighbor(c) { return (v, c) }
		}
		return nil
	}

	// MARK: the assembler

	/// The Vehicle Assembler: a tap on a structure you built turns it (every built block joined to it)
	/// into a vehicle, joined to a vehicle it touches if there is one; a tap on a parked vehicle puts its
	/// blocks back into the world and its parts in your bag
	func useAssembler(_ pressed: Bool) {
		if !pressed || useCD > 0 { return }
		useCD = 0.4
		swingT = 0.15
		if !inReach(aimX, aimY) {
			say("Tap closer to you.", 1.2)
			return
		}
		if let hit = vehicleAtPoint(aimX, aimY) {
			disassembleVehicle(hit.0)
			return
		}
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if !world.isBuilt(tx, ty) || !canAssemble(world.tile(tx, ty)) {
			say("Tap a block you built: it and every built block joined to it become one vehicle.", 3.0)
			return
		}
		assembleStructure(tx, ty)
	}

	/// The built blocks joined to (x, y), side by side (up to 800)
	func builtStructure(_ x: Int, _ y: Int) -> [IntPair] {
		var out: [IntPair] = []
		var seen: Set<IntPair> = []
		var stack: [IntPair] = [IntPair(x: x, y: y)]
		while let p = stack.popLast() {
			if seen.contains(p) { continue }
			seen.insert(p)
			if !world.isBuilt(p.x, p.y) || !canAssemble(world.tile(p.x, p.y)) { continue }
			out.append(p)
			if out.count >= 800 { break }
			stack.append(IntPair(x: p.x + 1, y: p.y))
			stack.append(IntPair(x: p.x - 1, y: p.y))
			stack.append(IntPair(x: p.x, y: p.y + 1))
			stack.append(IntPair(x: p.x, y: p.y - 1))
		}
		return out
	}

	func assembleStructure(_ x: Int, _ y: Int) {
		let cells: [IntPair] = builtStructure(x, y)
		if cells.isEmpty { return }
		if cells.count >= 800 {
			say("That structure is too big to move (800 blocks at most).", 2.5)
			return
		}
		// a vehicle the structure touches takes it in (it must be roughly level)
		var host: Vehicle? = nil
		for v in vehicles where abs(remainder(v.angle, 2.0 * Double.pi)) < 0.08 && !v.rider {
			for p in cells {
				let c: PartCell = v.cellAt(Double(p.x) + 0.5, Double(p.y) + 0.5)
				if v.parts[c] == nil && v.hasNeighbor(c) { host = v; break }
			}
			if host != nil { break }
		}
		var x0: Int = Int.max
		var y1: Int = Int.min
		for p in cells { x0 = min(x0, p.x); y1 = max(y1, p.y) }
		let v: Vehicle = host ?? Vehicle(id: newID(), first: .frame, x: 0, y: 0)
		if host == nil { v.parts.removeAll() }
		var stores: [(PartCell, [Stack])] = []
		var added: Int = 0
		for p in cells {
			let t: Tile = world.tile(p.x, p.y)
			let c: PartCell = host != nil ? v.cellAt(Double(p.x) + 0.5, Double(p.y) + 0.5) : PartCell(dx: p.x - x0, dy: p.y - y1)
			if v.parts[c] != nil {
				// no cell free for it in the vehicle: it goes to the bag (with what it held)
				giveItem(.block(t), 1)
				if t == .chest || t == .cabinet || t == .wardrobe { for st in world.removeChest(p.x, p.y) { giveStack(st) } }
				continue
			}
			var part: PartType = .block
			if t.isMod, let d = ModRuntime.shared.blockDef(t), let pp = d.vehRole.part { part = pp }
			v.parts[c] = part
			v.blocks[c] = t
			added += 1
			if t == .chest || t == .cabinet || t == .wardrobe || (t.isMod && ModRuntime.shared.blockDef(t)?.function == .storage) {
				stores.append((c, world.removeChest(p.x, p.y)))
			}
		}
		// the back walls of the structure go with it: behind its blocks, and behind the open cells
		// inside it (between its blocks in the same row)
		var inBlocks: Set<IntPair> = Set(cells)
		var walls: [(PartCell, UInt8)] = []
		var rows: [Int: (Int, Int)] = [:]
		for p in cells { let r: (Int, Int) = rows[p.y] ?? (p.x, p.x); rows[p.y] = (min(r.0, p.x), max(r.1, p.x)) }
		for (y, span) in rows {
			var x: Int = span.0
			while x <= span.1 {
				let k: Int = world.wallAt(x, y)
				let here: IntPair = IntPair(x: x, y: y)
				if k > 0 && (inBlocks.contains(here) || world.tile(x, y) == .air) {
					let c: PartCell = host != nil ? v.cellAt(Double(x) + 0.5, Double(y) + 0.5) : PartCell(dx: x - x0, dy: y - y1)
					if v.walls[c] == nil {
						walls.append((c, UInt8(k)))
						_ = world.setWall(x, y, 0)
					}
				}
				x += 1
			}
		}
		inBlocks.removeAll()
		for w in walls { v.walls[w.0] = w.1 }
		for p in cells {
			world.setBuilt(p.x, p.y, false)
			world.set(p.x, p.y, .air)
		}
		if host == nil {
			v.recompute(keepAnchor: false)
			v.placeBox(left: Double(x0), bottom: Double(y1 + 1))
			vehicles.append(v)
		} else {
			v.recompute(keepAnchor: true)
		}
		v.kit = -1
		v.asleep = false
		for s in stores { world.setChestItems(cargoSpot(v, s.0).x, cargoSpot(v, s.0).y, s.1) }
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0x30C0E0, 14, 4.0, 0.6, 2)
		sfx(.craft, 0.8)
		let massS: String = String(format: "%.0f", v.mass)
		let what: String = host == nil ? "a new vehicle" : "the vehicle"
		say(joinText("Assembled ", String(added), " blocks into ", what, " (mass ", massS, "). ", vehicleCheck(v).hint), 4.0)
		bumpHUD()
	}

	/// Puts a parked, level vehicle's blocks back into the world, each in the cell it is over (blocks
	/// that have no room go to the bag, as do the parts); stores keep their things as chests
	func disassembleVehicle(_ v: Vehicle) {
		if v.rider || v.speed > 1.0 || !v.upright {
			say("Park it level and get out first.", 2.0)
			return
		}
		var placed: Int = 0
		var bagged: Int = 0
		for (c, t) in v.parts {
			let p: (Double, Double) = v.cellCenter(c)
			let tx: Int = Int(floor(p.0))
			let ty: Int = Int(floor(p.1))
			var held: [Stack] = []
			if vehicleStores(v, c) {
				let k: IntPair = cargoSpot(v, c)
				if let o = openChest, o == k { openChest = nil }
				held = world.removeChest(k.x, k.y)
			}
			let here: Tile = world.tile(tx, ty)
			let free: Bool = here == .air || here.liquid || here.isPlant
			if let b = v.blocks[c], free {
				world.set(tx, ty, b)
				world.setBuilt(tx, ty, true)
				if b == .chest || b == .cabinet || b == .wardrobe || (b.isMod && ModRuntime.shared.blockDef(b)?.function == .storage) {
					world.setChestItems(tx, ty, held)
					held = []
				}
				placed += 1
			} else {
				giveItem(vehicleCellItem(VCell(cell: c, type: t, tile: v.blocks[c])), 1)
				bagged += 1
			}
			for st in held { giveStack(st) }
		}
		// its back walls go back up where there is none (or to the bag)
		for (c, k) in v.walls {
			let p: (Double, Double) = v.cellCenter(c)
			let tx: Int = Int(floor(p.0))
			let ty: Int = Int(floor(p.1))
			if world.wallAt(tx, ty) == 0 && world.setWall(tx, ty, Int(k)) { continue }
			if let t = blockWallTile(Int(k)) { giveItem(.block(t), 1) }
		}
		vehicles.removeAll { $0 === v }
		spawnParticles(v.b.x, v.b.y - v.b.h * 0.5, 0x30C0E0, 14, 4.0, 0.6, 2)
		sfx(.craft, 0.8)
		say(joinText("Taken apart: ", String(placed), " blocks back in place, ", String(bagged), " to your bag."), 3.0)
		bumpHUD()
	}

	// MARK: the autopilot

	/// AUTO cycles the autopilot: off, cruise (it holds the speed and the height you had), route (it
	/// drives the points you marked, round and round, even with nobody aboard)
	func cycleAutopilot() {
		guard let v = drivenVehicle, v.autopilots > 0 else { return }
		var next: Int = (v.auto + 1) % 3
		if next == 2 && v.route.count < 2 { next = 0 }
		v.auto = next
		v.holdThr = abs(v.throttle) > 0.1 ? v.throttle : (abs(v.vx) > 1.5 ? (v.vx > 0 ? 0.7 : -0.7) : 0)
		v.holdY = v.py
		v.holdVX = v.vx
		if next == 2 { v.routeAt = nearestWaypoint(v) }
		let names: [String] = ["Autopilot off.", "Autopilot: cruise. It holds your speed and height, even if you get up and walk about.", "Autopilot: route. It drives your marked points round and round, even if you get out."]
		say(names[next], 3.0)
		bumpHUD()
	}

	/// MARK adds where the vehicle is now to its route (up to 16 points)
	func markWaypoint() {
		guard let v = drivenVehicle, v.autopilots > 0 else { return }
		if v.route.count >= 16 { v.route.removeFirst() }
		v.route.append(VWaypoint(x: v.px, y: v.py))
		let n: Int = v.route.count
		say(n < 2 ? "Point 1 marked. Drive on and mark more." : joinText("Point ", String(n), " marked. AUTO twice to drive the route."), 2.0)
		bumpHUD()
	}

	func clearRoute() {
		guard let v = drivenVehicle else { return }
		v.route.removeAll()
		if v.auto == 2 { v.auto = 0 }
		say("Route cleared.", 1.5)
		bumpHUD()
	}

	func nearestWaypoint(_ v: Vehicle) -> Int {
		var best: Int = 0
		var bd: Double = 1e18
		for (i, w) in v.route.enumerated() {
			let d: Double = (w.x - v.px) * (w.x - v.px) + (w.y - v.py) * (w.y - v.py)
			if d < bd { bd = d; best = i }
		}
		return best
	}

	/// The autopilot's hands on the controls. The driver's own input wins while the stick is pushed
	/// (and cruise then takes up the new speed or height). Cruise holds the throttle, and in the air the
	/// height; a route steers for each point in turn.
	func autopilotSteer(_ v: Vehicle, _ ix: Double, _ up: Double, _ dt: Double) {
		if v.autopilots == 0 { v.auto = 0; return }
		let touched: Bool = abs(ix) > 0.1 || abs(up) > 0.1
		if v.auto == 1 {
			if abs(ix) > 0.1 { v.holdThr = ix } else { v.throttle = v.holdThr }
			if abs(up) > 0.1 { v.holdY = v.py } else if v.aero { v.pitch = holdHeight(v, v.holdY) }
			return
		}
		if v.auto != 2 || v.route.count < 2 { return }
		if touched && v.rider { return }
		if v.routeAt >= v.route.count { v.routeAt = 0 }
		let w: VWaypoint = v.route[v.routeAt]
		let dx: Double = w.x - v.px
		let dy: Double = w.y - v.py
		let flyer: Bool = v.aero && (v.rotors > 0 || v.envelopes > 0 || v.wings > 0)
		let arrived: Bool = abs(dx) < 2.5 && (!flyer || abs(dy) < 3.0)
		if arrived {
			v.routeAt = (v.routeAt + 1) % v.route.count
			return
		}
		if v.wings > 0 && v.rotors == 0 && v.envelopes == 0 {
			// a plane flies on at full throttle and turns round when the point is behind it
			let ahead: Double = dx * Double(v.fwd) * (v.cosA >= 0 ? 1.0 : -1.0)
			if ahead < -6.0 && v.turnT == 0 && v.contacts == 0 && v.speed > 3.0 {
				v.turnT = 0.001
				v.turnVX = v.vx
				v.turned = false
			}
			v.throttle = Double(v.fwd)
			v.pitch = holdHeight(v, w.y)
			return
		}
		let gain: Double = flyer ? 0.15 : 0.35
		var thr: Double = clampD(dx * gain, -1, 1)
		if abs(thr) < 0.35 { thr = thr >= 0 ? 0.35 : -0.35 }
		if flyer && abs(dx) < 6.0 { thr *= abs(dx) / 6.0 }
		v.throttle = thr
		v.pitch = flyer ? holdHeight(v, w.y) : 0
	}

	/// The up/down input that brings the vehicle to a height and holds it there
	func holdHeight(_ v: Vehicle, _ y: Double) -> Double {
		let err: Double = v.py - y
		if v.wings > 0 && v.rotors == 0 && v.envelopes == 0 {
			return clampD(err * 0.12 + v.vy * 0.12, -0.7, 0.7)
		}
		return clampD(err * 0.35 + v.vy * 0.3, -1, 1)
	}
}

extension Game {
	// MARK: what kind of vehicle, and is it ready

	/// What the design is, from what it is built of (a hybrid when it is more than one thing)
	func vehicleKindName(_ v: Vehicle) -> String {
		var kinds: [String] = []
		if v.rotors > 0 { kinds.append("HELICOPTER") }
		if v.envelopes > 0 && v.burners > 0 { kinds.append("AIRSHIP") }
		if v.wings > 0 && v.rotors == 0 { kinds.append(v.airProps + v.jets > 0 ? (v.jets > 0 ? "JET" : "PLANE") : "GLIDER") }
		var hulls: Int = 0
		for (_, t) in v.parts where t == .hull { hulls += 1 }
		if hulls > 0 { kinds.append("BOAT") }
		// on an aircraft, wheels are its landing gear
		let flies: Bool = v.rotors > 0 || v.wings > 0 || (v.envelopes > 0 && v.burners > 0)
		if v.wheels >= 2 {
			if v.tracks > 0 { kinds.append(v.cannons > 0 ? "TANK" : "TRACKED") }
			else if kinds.isEmpty { kinds.append(v.parts.count >= 14 || cargoCount(v) >= 2 ? "TRUCK" : "CAR") }
			else if !flies { kinds.append("WHEELS") }
		}
		if kinds.isEmpty { return v.parts.contains { $0.value == .block } ? "STRUCTURE" : "VEHICLE" }
		if kinds.count == 1 { return kinds[0] }
		return joinText(kinds.prefix(2).joined(separator: " + "), " HYBRID")
	}

	func cargoCount(_ v: Vehicle) -> Int {
		var n: Int = 0
		for c in v.parts.keys where vehicleStores(v, c) { n += 1 }
		return n
	}

	/// The checklist for anything that flies, fights or runs on tracks: what it needs, and whether its
	/// design can do it (lift against weight, a tail behind the centre of mass, power for its rotors)
	func flightCheck(_ v: Vehicle) -> VehicleCheck {
		var lines: [String] = []
		var oks: [Bool] = []
		func add(_ ok: Bool, _ s: String) {
			lines.append(s)
			oks.append(ok)
		}
		let weight: Double = v.mass * gravityG
		let massS: String = String(format: "%.1f", v.mass)
		add(v.hasSeat && v.hasSteering, v.hasCockpit ? "Cockpit" : "Seat and steering wheel (or a cockpit)")
		var hint: String = joinText("Mass ", massS, ". Refuel: hold coal or wood and tap it.")
		if v.rotors > 0 {
			let lift: Double = rotorMax(v, anyway: true) + balloonMax(v)
			let pct: Int = Int((lift / max(1, weight) * 100).rounded())
			add(v.engines > 0, joinText("Engines to turn the rotor (", String(v.engines), ")"))
			add(lift > weight * 1.05, joinText("Rotor lift ", String(pct), "% of the weight"))
			add(v.tailRotors > 0 || v.rotors >= 2, "Tail rotor (or a second main rotor)")
			hint = lift > weight * 1.05 ? joinText("Mass ", massS, ". Stick up to lift off; let go to hover.") : "Too heavy for the rotor: add engines or take weight off."
		} else if v.envelopes > 0 {
			let lift: Double = balloonMax(v)
			let pct: Int = Int((lift / max(1, weight) * 100).rounded())
			let need: Int = (v.envelopes + Aero.burnerCells - 1) / Aero.burnerCells
			add(v.burners >= need, joinText("Burners: ", String(v.burners), " of ", String(need), " (one heats 12 envelopes)"))
			add(lift > weight * 1.05, joinText("Balloon lift ", String(pct), "% of the weight (full heat)"))
			add(v.airProps > 0 && v.engines > 0, "Propeller and engine to move (optional)")
			oks[oks.count - 1] = true
			hint = lift > weight * 1.05 ? joinText("Mass ", massS, ". Stick up to heat the balloon and rise.") : "Not enough balloon for the weight: add envelopes (and burners)."
		} else if v.wings > 0 {
			let takeoff: Double = sqrt(weight / max(0.01, Aero.kLift * Double(v.wings) * 1.15))
			let thrust: Bool = (v.airProps > 0 && v.engines > 0) || v.jets > 0
			add(thrust, "Air propeller with an engine, or a jet")
			add(takeoff < 20.0, joinText("Wings lift it at ", String(Int(takeoff.rounded())), " blocks/s (", String(v.wings), " wing cells)"))
			// the push it has at that speed against its weight: under a fifth, it never gets there
			let push: Double = thrustAt(v, takeoff) / max(1, weight)
			add(push >= 0.2, joinText("Thrust ", String(Int((push * 100).rounded())), "% of the weight at take-off (20% needed)"))
			let tail: (Bool, Bool) = tailCheck(v)
			add(tail.0, "Tail elevator, well behind the centre of mass")
			add(tail.1, "Centre of mass ahead of the wings (or it flips)")
			if takeoff >= 20.0 { hint = "The wings are too small for its weight: add wing cells." }
			else if push < 0.2 { hint = "Too heavy for its engines: add engines or a jet, or take weight off." }
			else { hint = "Throttle up along the ground; at speed, stick up to lift off." }
		}
		if v.tracks > 0 || v.cannons + v.guns > 0 {
			if v.rotors == 0 && v.wings == 0 && v.envelopes == 0 {
				add(v.wheels >= 2, joinText("Tracks or wheels under the hull (", String(v.wheels), ")"))
				add(v.engines > 0, "Engine")
			}
			if v.cannons + v.guns > 0 {
				let ammo: Bool = isCreative || (v.cannons == 0 || inv.total(.mat(.gunpowder)) > 0) && (v.guns == 0 || inv.total(.ammo(.bullet)) > 0)
				add(ammo, v.cannons > 0 ? "Gunpowder in your bag (cannon shells)" : "Bullets in your bag (machine gun)")
				if v.rotors == 0 && v.wings == 0 && v.envelopes == 0 { hint = "Drive with the stick; aim and fire with the attack stick." }
			}
		}
		if v.engines > 0 || v.jets > 0 || v.burners > 0 { add(v.fuel > 0.5 || isCreative, fuelLine(v)) }
		var ready: Bool = true
		for o in oks where !o { ready = false }
		return VehicleCheck(title: vehicleKindName(v), lines: lines, oks: oks, ready: ready, hint: hint)
	}

	/// Is there a tail elevator well behind the centre of mass, and is the centre of mass ahead of the
	/// wings' middle (so the plane noses down when slow instead of flipping onto its back)?
	func tailCheck(_ v: Vehicle) -> (Bool, Bool) {
		var wingX: Double = 0
		var n: Int = 0
		var tailX: Double = 0
		var tn: Int = 0
		for (c, t) in v.parts {
			if t == .wing { wingX += Double(c.dx) + 0.5; n += 1 }
			if t == .elevator { tailX += Double(c.dx) + 0.5; tn += 1 }
		}
		if n == 0 { return (tn > 0, true) }
		wingX /= Double(n)
		// the nose: the end the thrust is at, or failing that the end away from the tail
		var front: Double = 1
		if tn > 0 { tailX /= Double(tn); front = tailX < v.comX ? 1 : -1 }
		let tailOK: Bool = tn > 0 && (tailX - v.comX) * front < -1.5
		let balanced: Bool = (v.comX - wingX) * front > -0.6
		return (tailOK, balanced)
	}

	/// The flight instruments shown while flying: speed, height, climb, lift against weight, the
	/// rotor or burner, fuel, and a stall warning
	func flightReadout(_ v: Vehicle) -> [String] {
		var out: [String] = []
		let alt: Int = Int((Double(WorldGen.sea) - v.b.y).rounded())
		let climb: Double = -v.vy
		out.append(joinText("SPD ", String(Int(v.airspeed.rounded())), "  ALT ", String(alt), "  ", climb >= 0 ? "▲" : "▼", String(format: "%.1f", abs(climb))))
		let weight: Double = max(1, v.mass * gravityG)
		let liftPct: Int = Int((v.liftNow / weight * 100).rounded())
		var l2: String = joinText("LIFT ", String(liftPct), "%")
		if v.rotors > 0 { l2 = joinText(l2, "  ROTOR ", String(Int((v.collective * 100).rounded())), "%") }
		if v.burners > 0 && v.envelopes > 0 { l2 = joinText(l2, "  HEAT ", String(Int((v.heat * 100).rounded())), "%") }
		if v.airProps + v.jets > 0 { l2 = joinText(l2, "  THR ", String(Int((abs(v.throttle) * 100).rounded())), "%") }
		out.append(l2)
		if v.engines + v.jets + v.burners > 0 && !isCreative { out.append(joinText("FUEL ", String(Int(v.fuel)), "/", String(Int(v.fuelCapacity)))) }
		if v.stall { out.append("STALL!") }
		return out
	}

	/// A line about the guns (reload) and the autopilot, while driving
	func vehicleStatusLine(_ v: Vehicle) -> String? {
		var parts: [String] = []
		if v.ballasts > 0 { parts.append(joinText("BALLAST ", String(Int((v.ballast * 100).rounded())), "%")) }
		if v.airBrakes > 0 && v.brakeOpen > 0.5 { parts.append("AIR BRAKES") }
		if v.cannons > 0 {
			var cd: Double = 0
			for (c, t) in v.parts where t == .cannon { cd = max(cd, v.gunCD[c] ?? 0) }
			parts.append(cd > 0.05 ? joinText("CANNON ", String(format: "%.1f", cd), "s") : "CANNON READY")
		}
		if v.autopilots > 0 {
			let modes: [String] = ["AUTO OFF", "AUTO CRUISE", "AUTO ROUTE"]
			var s: String = modes[max(0, min(2, v.auto))]
			if v.auto == 2 { s = joinText(s, " ", String(v.routeAt + 1), "/", String(v.route.count)) }
			else if !v.route.isEmpty { s = joinText(s, " · ", String(v.route.count), " PTS") }
			parts.append(s)
		}
		return parts.isEmpty ? nil : parts.joined(separator: "  ")
	}
}

// ===== p27_power =====

// MARK: - Sparkworks: power and automation
//
// Power (measured in sparks) runs through power cable from generators to batteries and machines.
// On/off pulses run separately through pulse wire, in two colours (amber and teal) so two circuits can
// cross. Both are an overlay over the tiles, stored per chunk like background walls, so they are saved,
// parked and reloaded with the chunk. Devices are ordinary tiles; their settings and charge live in
// World.devs. Networks are worked out again only when wiring or devices change (World.powerRev).
// Power is shared out four times a second. Pulses step twenty times a second from a queue of changes,
// and every logic part adds at least one step of delay, so a loop can never run away within a frame
// (one that flips too fast burns out for a moment instead).

/// The overlay bits on a cell
enum Wire {
	static let power: UInt8 = 1
	static let pulseA: UInt8 = 2
	static let pulseB: UInt8 = 4
	/// the bit for layer 0 (power), 1 (amber) or 2 (teal)
	static func bit(_ layer: Int) -> UInt8 { return UInt8(1 << layer) }
}

/// What a device does on the networks
enum PowerRole {
	case none, generator, storage, conductor, meter, source, logic, sensor, machine, indicator
}

func powerRole(_ t: Tile) -> PowerRole {
	switch t {
	case .crankGen, .solarPanel, .fuelGen, .waterWheel, .emberDynamo, .windTurbine: return .generator
	case .battery, .accumulator: return .storage
	case .powerSwitch, .breaker: return .conductor
	case .powerMeter: return .meter
	case .lever, .pushButton, .pressurePlate: return .source
	case .pulseTimer, .repeater, .inverter, .logicGate: return .logic
	case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor, .vehicleSensor: return .sensor
	case .gateClosed, .gateOpen, .lampOff, .lampOn, .arcTrap, .autoDrill, .conveyor, .collector, .autoCrafter, .sumpPump, .exoStation, .signalPost: return .machine
	case .signalLight: return .indicator
	default: return t.isMod ? ModRuntime.shared.powerRoleOf(t).role : .none
	}
}

/// The two forms of a device (a lamp lit or dark, a gate open or shut) are the same device
func powerFamily(_ t: Tile) -> Tile {
	switch t {
	case .lampOn: return .lampOff
	case .gateOpen: return .gateClosed
	default:
		// a mod lamp lit is the same device as unlit
		if t.isMod && ModRuntime.shared.isAlt(t), let p = ModRuntime.shared.partner(t) { return p }
		return t
	}
}

/// Parts that point a way (their output side; inputs at the back or the sides)
func powerDirectional(_ t: Tile) -> Bool {
	switch t {
	case .pulseTimer, .repeater, .inverter, .logicGate, .autoDrill, .conveyor, .autoCrafter: return true
	default: return false
	}
}

/// Plain tiles that follow a pulse on their cell without needing power: wooden doors open, storm
/// shutters close, a storm siren sounds
func pulseFollower(_ t: Tile) -> Bool {
	return t == .doorClosed || t == .doorOpen || t == .shutterClosed || t == .shutterOpen || t == .stormSiren
}

/// Steps of 90 degrees: 0 right, 1 down, 2 left, 3 up
let sideDX: [Int] = [1, 0, -1, 0]
let sideDY: [Int] = [0, 1, 0, -1]

/// A placed device: its settings and charge (saved), and what the simulation knows of it right now
final class PowerDev {
	let key: ChestKey
	var tile: Tile
	/// facing (the output side for parts that point a way)
	var dir: Int = 0
	/// a setting chosen in its panel (gate type, sensor mode, breaker rating and so on)
	var mode: Int = 0
	/// a number set in its panel (a delay, a period, a range)
	var param: Double = 0
	/// stored energy (batteries, a crank's flywheel) or fuel left in seconds (generators)
	var charge: Double = 0
	/// a lever or switch position, a breaker closed
	var on: Bool = false
	/// a second setting (a trap that hurts the player too, a breaker that has tripped)
	var flag: Bool = false
	/// an auto crafter's recipe
	var item: Int = -1
	// live state (not saved)
	var pnet: Int = -1
	/// pulse nets on its own cell (amber, teal)
	var snets: [Int] = [-1, -1]
	/// pulse nets at each side (right, down, left, up), amber then teal, for parts that point a way
	var ports: [Int] = [-1, -1, -1, -1, -1, -1, -1, -1]
	var out: Bool = false
	var pend: [(Int, Bool)] = []
	var powered: Bool = false
	var want: Double = 0
	var made: Double = 0
	var timer: Double = 0
	var flips: Int = 0
	var flipT: Double = 0
	var burnT: Double = 0
	var lastSwap: Double = -10
	var work: Double = 0
	var enabled: Bool = true
	/// index among the logic parts (for the evaluation queue)
	var li: Int = -1

	init(key: ChestKey, tile: Tile) {
		self.key = key
		self.tile = tile
		switch tile {
		case .pushButton: param = 1.0
		case .pulseTimer: param = 1.0
		case .repeater: param = 1
		case .motionSensor, .proximitySensor: param = 5
		case .vehicleSensor: param = 3
		case .breaker: mode = 1; on = true
		case .powerSwitch: on = true
		case .autoCrafter: item = -1
		default: break
		}
	}

	var x: Int { return key.x }
	var y: Int { return key.y }
	var role: PowerRole { return powerRole(tile) }
}

struct PowerDevSave: Codable {
	var d: Int
	var x: Int
	var y: Int
	var t: Int
	var dir: Int
	var mode: Int
	var param: Double
	var charge: Double
	var on: Bool
	var flag: Bool
	var item: Int
}

final class PowerNet {
	var devs: [PowerDev] = []
	var cells: Int = 0
	/// last share-out: made, used, asked for, stored and room (sparks per second and sparks)
	var made: Double = 0
	var used: Double = 0
	var asked: Double = 0
	var stored: Double = 0
	var cap: Double = 0
	var short: Bool = false
}

final class PulseNet {
	var sources: [PowerDev] = []
	var readers: [PowerDev] = []
	/// doors, shutters and sirens on its wire
	var followers: [IntPair] = []
	var cells: Int = 0
	var on: Bool = false
	var dirty: Bool = true
}

/// Everything the simulation works out from the wiring, rebuilt when the wiring changes
final class PowerSim {
	var builtRev: Int = -1
	var builtDim: Int = -1
	var pnets: [PowerNet] = []
	var snets: [PulseNet] = []
	/// net index of each wired cell, by layer and position
	var cellNet: [Int: Int] = [:]
	var devs: [PowerDev] = []
	var logic: [PowerDev] = []
	var polled: [PowerDev] = []
	var machines: [PowerDev] = []
	var conveyors: [PowerDev] = []
	var queue: Set<Int> = []
	var tickNo: Int = 0
	var powerT: Double = 0
	var pulseT: Double = 0
	var machineT: Double = 0
	/// tile swaps left this step (lamps, gates, doors), so a fast clock can't relight the world every frame
	var swaps: Int = 0
	var sirens: Set<IntPair> = []
	/// devices that flipped too fast and burnt out (for a warning)
	var burnNote: Double = 0
	var rebuilds: Int = 0
	/// after a rebuild every reader and follower is brought in line with its net once
	var settle: Bool = false

	static func cellKey(_ layer: Int, _ x: Int, _ y: Int) -> Int {
		return (((x &+ (1 << 30)) << 12) | (y & 4095)) << 2 | layer
	}
}

/// Fuel for generators: seconds of burning per item (the dynamo only takes ember)
func fuelSeconds(_ it: Item, dynamo: Bool) -> Double {
	if dynamo {
		switch it {
		case .mat(.emberBar): return 300
		case .mat(.emberOre): return 70
		default: return 0
		}
	}
	switch it {
	case .mat(.coal): return 60
	case .block(.log), .block(.jungleLog), .block(.palmLog), .block(.birchLog): return 20
	case .block(.planks): return 6
	case .mat(.stick): return 2
	default: return 0
	}
}

/// How much a device makes or uses, its storage, and a breaker's limit
enum PowerSpec {
	static func capacity(_ t: Tile) -> Double {
		switch t {
		case .battery: return 600
		case .accumulator: return 5000
		case .crankGen: return 60
		default: return modBattery(t) * 150
		}
	}
	static func rate(_ t: Tile) -> Double {
		switch t {
		case .battery: return 15
		case .accumulator: return 60
		default: return modBattery(t) * 2.5
		}
	}
	/// a mod battery's strength (0 for anything else)
	static func modBattery(_ t: Tile) -> Double {
		if !t.isMod || ModRuntime.shared.powerRoleOf(t) != .battery { return 0 }
		return ModRuntime.shared.blockDef(t)?.powerAmt ?? 0
	}
	/// sparks per second while running
	static func draw(_ t: Tile) -> Double {
		switch t {
		case .lampOff, .lampOn: return 1
		case .gateClosed, .gateOpen: return 0.5
		case .arcTrap: return 3
		case .autoDrill: return 8
		case .conveyor: return 1.5
		case .collector: return 1
		case .autoCrafter: return 5
		case .sumpPump: return 4
		case .exoStation: return 10
		case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor, .vehicleSensor: return 0.5
		case .signalPost: return 0.5
		default:
			if t.isMod && ModRuntime.shared.powerRoleOf(t) == .lamp { return ModRuntime.shared.blockDef(t)?.powerAmt ?? 0 }
			return 0
		}
	}
	static let breakerLimits: [Double] = [10, 25, 50, 100, 250]
	static let fuelRate: Double = 12
	static let dynamoRate: Double = 40
}

// MARK: - Wires in the world

extension World {
	func wireAt(_ x: Int, _ y: Int) -> UInt8 {
		if y < 0 || y >= H { return 0 }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx), c.wireCount > 0 else { return 0 }
		return c.wires[(x - cx * chunkW) * H + y]
	}

	/// Sets the wire bits on a cell; returns false if the cell is not loaded
	@discardableResult
	func setWire(_ x: Int, _ y: Int, _ bits: UInt8) -> Bool {
		if y < 1 || y >= H - 1 { return false }
		let cx: Int = floorDiv(x, chunkW)
		guard let c = chunk(cx) else { return false }
		if c.wires.isEmpty {
			if bits == 0 { return true }
			c.wires = [UInt8](repeating: 0, count: chunkW * H)
		}
		let i: Int = (x - cx * chunkW) * H + y
		let old: UInt8 = c.wires[i]
		if old == bits { return true }
		if old == 0 { c.wireCount += 1 }
		if bits == 0 { c.wireCount -= 1 }
		c.wires[i] = bits
		c.dirty = true
		c.bumpRows(y - 1, y + 1)
		powerRev &+= 1
		return true
	}

	func powerKey(_ x: Int, _ y: Int) -> ChestKey { return ChestKey(d: dim.rawValue, x: x, y: y) }

	func powerDev(_ x: Int, _ y: Int) -> PowerDev? { return devs[powerKey(x, y)] }

	/// Keeps the device list in step with the tiles (called from set): a new device gets its default
	/// settings, a removed one is forgotten, and switching between a device's two forms keeps it
	func powerTileChanged(_ x: Int, _ y: Int, _ old: Tile, _ new: Tile) {
		let k: ChestKey = powerKey(x, y)
		if new.isPower {
			if let d = devs[k], powerFamily(d.tile) == powerFamily(new) {
				d.tile = new
				return
			}
			devs[k] = PowerDev(key: k, tile: new)
		} else if old.isPower {
			devs[k] = nil
		}
		powerRev &+= 1
	}
}

// MARK: - The simulation

extension Game {
	/// Called every frame
	func updatePower(_ dt: Double) {
		let sim: PowerSim = power
		if world.devs.isEmpty && sim.devs.isEmpty { return }
		if sim.builtRev != world.powerRev || sim.builtDim != world.dim.rawValue { rebuildPower() }
		if sim.devs.isEmpty { return }
		sim.powerT += dt
		if sim.powerT >= 0.25 {
			let step: Double = min(sim.powerT, 1.0)
			sim.powerT = 0
			powerTick(step)
		}
		sim.pulseT += dt
		var n: Int = 0
		while sim.pulseT >= 0.05 && n < 3 {
			sim.pulseT -= 0.05
			n += 1
			pulseTick()
		}
		if sim.pulseT > 0.15 { sim.pulseT = 0 }
		sim.machineT += dt
		if sim.machineT >= 0.1 {
			let step: Double = min(sim.machineT, 0.3)
			sim.machineT = 0
			machineTick(step)
		}
		if !sim.conveyors.isEmpty { runConveyors(dt) }
		if sim.burnNote > 0 { sim.burnNote -= dt }
	}

	/// Works out every network from the wiring and devices in loaded chunks
	func rebuildPower() {
		let sim: PowerSim = power
		let w: World = world
		sim.builtRev = w.powerRev
		sim.builtDim = w.dim.rawValue
		sim.rebuilds += 1
		sim.pnets.removeAll()
		sim.snets.removeAll()
		sim.cellNet.removeAll(keepingCapacity: true)
		sim.devs.removeAll()
		sim.logic.removeAll()
		sim.polled.removeAll()
		sim.machines.removeAll()
		sim.conveyors.removeAll()
		sim.sirens.removeAll()
		sim.queue.removeAll()
		let dim: Int = w.dim.rawValue
		var gone: [ChestKey] = []
		for (k, d) in w.devs where k.d == dim {
			if !w.isLoaded(k.x) { continue }
			let t: Tile = w.tile(k.x, k.y)
			if !t.isPower || powerFamily(t) != powerFamily(d.tile) { gone.append(k); continue }
			d.tile = t
			d.pnet = -1
			d.snets = [-1, -1]
			d.ports = [-1, -1, -1, -1, -1, -1, -1, -1]
			sim.devs.append(d)
		}
		for k in gone { w.devs[k] = nil }
		sim.devs.sort { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
		// flood every wired cell into networks, layer by layer, in a fixed order
		let cks: [Int] = w.chunks.keys.sorted()
		for cx in cks {
			guard let c = w.chunks[cx], c.wireCount > 0 else { continue }
			let H: Int = c.H
			for lx in 0..<chunkW {
				let base: Int = lx * H
				for y in 0..<H {
					let b: UInt8 = c.wires[base + y]
					if b == 0 { continue }
					let x: Int = c.x0 + lx
					for layer in 0..<3 where b & Wire.bit(layer) != 0 {
						if sim.cellNet[PowerSim.cellKey(layer, x, y)] == nil && conducts(layer, x, y) { floodNet(layer, x, y) }
					}
				}
			}
		}
		// hook the devices onto the networks
		for d in sim.devs {
			let role: PowerRole = d.role
			if role == .generator || role == .storage || role == .meter || role == .sensor || role == .machine || role == .conductor {
				if let p = sim.cellNet[PowerSim.cellKey(0, d.x, d.y)] {
					d.pnet = p
					sim.pnets[p].devs.append(d)
				}
			}
			if role == .logic {
				// inputs and the output are the cells around it; its own cell joins nothing
				for side in 0..<4 {
					let nx: Int = d.x + sideDX[side]
					let ny: Int = d.y + sideDY[side]
					for c in 0..<2 {
						if let s = sim.cellNet[PowerSim.cellKey(c + 1, nx, ny)] {
							d.ports[side * 2 + c] = s
							if side == d.dir { sim.snets[s].sources.append(d) } else if isLogicInput(d, side) { sim.snets[s].readers.append(d) }
						}
					}
				}
				d.li = sim.logic.count
				sim.logic.append(d)
			} else {
				for c in 0..<2 {
					if let s = sim.cellNet[PowerSim.cellKey(c + 1, d.x, d.y)] {
						d.snets[c] = s
						if role == .source || role == .sensor { sim.snets[s].sources.append(d) } else { sim.snets[s].readers.append(d) }
					}
				}
			}
			if role == .sensor || d.tile == .pressurePlate || d.tile == .pushButton { sim.polled.append(d) }
			if role == .machine || role == .conductor { sim.machines.append(d) }
			if d.tile == .conveyor { sim.conveyors.append(d) }
			if d.tile == .pushButton && d.timer <= 0 { d.out = false }
			if d.tile == .lever { d.out = d.on }
		}
		// every pulse net starts dirty so its followers and readers settle on the wiring as it is now
		for n in sim.snets { n.dirty = true }
		for i in 0..<sim.logic.count { sim.queue.insert(i) }
		sim.settle = true
	}

	/// Whether a layer passes through a cell: power stops at an open switch or a tripped breaker,
	/// pulses stop at logic parts (their sides are separate inputs and an output)
	func conducts(_ layer: Int, _ x: Int, _ y: Int) -> Bool {
		let t: Tile = world.tile(x, y)
		if layer == 0 {
			if t == .powerSwitch || t == .breaker {
				return world.powerDev(x, y)?.on ?? true
			}
			return true
		}
		return powerRole(t) != .logic
	}

	func floodNet(_ layer: Int, _ sx: Int, _ sy: Int) {
		let sim: PowerSim = power
		let id: Int
		let pn: PowerNet? = layer == 0 ? PowerNet() : nil
		let sn: PulseNet? = layer == 0 ? nil : PulseNet()
		if let p = pn { id = sim.pnets.count; sim.pnets.append(p) } else { id = sim.snets.count; sim.snets.append(sn!) }
		let bit: UInt8 = Wire.bit(layer)
		var stack: [IntPair] = [IntPair(x: sx, y: sy)]
		sim.cellNet[PowerSim.cellKey(layer, sx, sy)] = id
		var n: Int = 0
		while let c = stack.popLast() {
			n += 1
			if let s = sn {
				let t: Tile = world.tile(c.x, c.y)
				if pulseFollower(t) {
					s.followers.append(c)
					if t == .stormSiren { sim.sirens.insert(c) }
				}
			}
			// a very long line still works, but stops growing past this many cells
			if n > 20000 { continue }
			for side in 0..<4 {
				let nx: Int = c.x + sideDX[side]
				let ny: Int = c.y + sideDY[side]
				if world.wireAt(nx, ny) & bit == 0 { continue }
				let k: Int = PowerSim.cellKey(layer, nx, ny)
				if sim.cellNet[k] != nil { continue }
				if !conducts(layer, nx, ny) { continue }
				sim.cellNet[k] = id
				stack.append(IntPair(x: nx, y: ny))
			}
		}
		if let p = pn { p.cells = n } else { sn!.cells = n }
	}

	/// The sides a logic part reads: the back for a relay, inverter or timer; both sides for a gate
	func isLogicInput(_ d: PowerDev, _ side: Int) -> Bool {
		if d.tile == .logicGate { return side == (d.dir + 1) % 4 || side == (d.dir + 3) % 4 }
		return side == (d.dir + 2) % 4
	}

	// MARK: power

	/// Shares the power out on every network: generators first, batteries make up the difference or
	/// take the surplus, fuel is only burnt for what is actually needed, and if there still isn't
	/// enough the machines are served in a fixed order and the rest stop
	func powerTick(_ dt: Double) {
		let sim: PowerSim = power
		for d in sim.devs where d.pnet < 0 {
			// not on any power line
			d.made = 0
			if d.powered { d.powered = false; powerChanged(d) }
			if d.tile == .crankGen { d.charge = max(0, d.charge - 6.0 * dt) }
		}
		for net in sim.pnets {
			var made: Double = 0
			var asked: Double = 0
			var room: Double = 0
			var avail: Double = 0
			var stored: Double = 0
			var cap: Double = 0
			var burners: [PowerDev] = []
			var loads: [PowerDev] = []
			var stores: [PowerDev] = []
			var breakers: [PowerDev] = []
			for d in net.devs {
				switch d.role {
				case .generator:
					if d.tile == .fuelGen || d.tile == .emberDynamo || d.tile == .windTurbine {
						burners.append(d)
					} else {
						let r: Double = generatorRate(d, dt)
						d.made = r
						made += r
					}
				case .storage:
					stores.append(d)
					let c: Double = PowerSpec.capacity(d.tile)
					let r: Double = PowerSpec.rate(d.tile)
					room += min(r, max(0, c - d.charge) / dt)
					avail += min(r, d.charge / dt)
					stored += d.charge
					cap += c
				case .conductor:
					if d.tile == .breaker { breakers.append(d) }
				case .machine, .sensor:
					d.want = d.enabled ? PowerSpec.draw(d.tile) : 0
					if d.want > 0 { loads.append(d) } else if d.powered {
						d.powered = false
						powerChanged(d)
					}
					asked += d.want
				default:
					break
				}
			}
			// generators that burn fuel cover only what the others can't (and topping up batteries); a
			// wind turbine gives from its own charge, which the wind keeps topping up (see the weather
			// devices), so what isn't needed stays in it for its Doppler station and storm rod
			var need: Double = max(0, asked + room - made)
			for f in burners {
				if f.tile == .windTurbine {
					let k: String = deviceKey(DeviceSpot(x: f.x, y: f.y, t: .windTurbine))
					let have: Double = weather.store[k] ?? 0
					let r: Double = min(8.0, have / dt, need)
					weather.store[k] = max(0, have - r * dt)
					f.made = r
					made += r
					need -= r
					continue
				}
				let top: Double = f.tile == .emberDynamo ? PowerSpec.dynamoRate : PowerSpec.fuelRate
				if f.charge > 0 && need > 0.01 {
					let r: Double = min(top, need)
					f.charge = max(0, f.charge - dt * r / top)
					f.made = r
					made += r
					need -= r
				} else {
					f.made = 0
				}
			}
			var supply: Double = made + avail
			var used: Double = 0
			for d in loads {
				let ok: Bool = supply + 1e-9 >= d.want
				if ok {
					supply -= d.want
					used += d.want
				}
				if ok != d.powered {
					d.powered = ok
					powerChanged(d)
				}
			}
			// what is left over charges the batteries; a shortfall drains them (the first ones first)
			var flow: Double = made - used
			for b in stores {
				let c: Double = PowerSpec.capacity(b.tile)
				let r: Double = PowerSpec.rate(b.tile)
				if flow > 0 {
					let take: Double = min(flow, r, max(0, c - b.charge) / dt)
					b.charge += take * dt
					flow -= take
				} else if flow < 0 {
					let give: Double = min(-flow, r, b.charge / dt)
					b.charge = max(0, b.charge - give * dt)
					flow += give
				}
			}
			net.made = made
			net.used = used
			net.asked = asked
			net.stored = stored
			net.cap = cap
			net.short = used + 1e-6 < asked
			// a breaker opens when the machines on its line ask for more than its limit
			for b in breakers where b.on {
				let limit: Double = PowerSpec.breakerLimits[clampI(b.mode, 0, PowerSpec.breakerLimits.count - 1)]
				if asked > limit {
					b.on = false
					b.flag = true
					world.powerRev &+= 1
					sfx(.zap, at: Double(b.x), 0.6)
					spawnParticles(Double(b.x) + 0.5, Double(b.y) + 0.4, 0xFFE070, 8, 3.0, 0.4, 10)
					floatText("Breaker tripped: overload", Double(b.x) + 0.5, Double(b.y) - 0.6, 0xFF8040)
				}
			}
		}
	}

	/// Sparks per second a generator makes right now (fuel burners are worked out separately)
	func generatorRate(_ d: PowerDev, _ dt: Double) -> Double {
		switch d.tile {
		case .crankGen:
			// a flywheel spun up by hand: it gives its charge back steadily
			let r: Double = min(6.0, d.charge / dt)
			d.charge = max(0, d.charge - r * dt)
			return r
		case .solarPanel:
			// needs open sky above (glass lets the light through)
			if world.dim != .overworld || d.y >= world.skyTop(d.x) { return 0 }
			let cloud: Double = settings.weatherOn ? weatherAt(Double(d.x) + 0.5, Double(d.y)).cloud : 0
			return 4.0 * dayFactor * (1.0 - 0.75 * clampD(cloud, 0, 1))
		case .waterWheel:
			var n: Int = 0
			for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0) { if world.tile(d.x + dx, d.y + dy) == .water { n += 1 } } }
			var r: Double = Double(n) * 0.75
			if settings.weatherOn && world.dim == .overworld && d.y < world.rainTop(d.x) + 1 {
				r += weatherAt(Double(d.x) + 0.5, Double(d.y)).precip * 1.5
			}
			return min(6.0, r)
		default:
			return modGeneratorRate(d)
		}
	}

	/// Sparks a second a mod's generator makes: steadily, or by daylight under the open sky
	func modGeneratorRate(_ d: PowerDev) -> Double {
		if !d.tile.isMod { return 0 }
		let role: ModPowerRole = ModRuntime.shared.powerRoleOf(d.tile)
		let amt: Double = ModRuntime.shared.blockDef(d.tile)?.powerAmt ?? 0
		if role == .generator { return amt }
		if role != .solar { return 0 }
		// open sky above it (the block itself may be the highest thing in its column)
		if d.y > world.skyTop(d.x) { return 0 }
		let cloud: Double = settings.weatherOn && world.dim == .overworld ? weatherAt(Double(d.x) + 0.5, Double(d.y)).cloud : 0
		return amt * dayFactor * (1.0 - 0.75 * clampD(cloud, 0, 1))
	}

	/// A mod's powered lamp or signal light: its lit form while it has power (and its pulse wire is on,
	/// if it has one), or while its pulse wire is on. False for anything else.
	func modPowerLamp(_ d: PowerDev, _ pulse: Bool?) -> Bool {
		if !d.tile.isMod { return false }
		let role: ModPowerRole = ModRuntime.shared.powerRoleOf(d.tile)
		if role != .lamp && role != .signal { return false }
		d.enabled = pulse ?? true
		let lit: Bool = role == .lamp ? (d.enabled && d.powered) : (pulse ?? false)
		let rt: ModRuntime = ModRuntime.shared
		guard let other = rt.partner(d.tile) else { return true }
		if lit != rt.isAlt(d.tile) && clock - d.lastSwap > 0.12 && power.swaps > 0 {
			power.swaps -= 1
			d.lastSwap = clock
			world.set(d.x, d.y, other)
		}
		return true
	}

	/// A machine just gained or lost power
	func powerChanged(_ d: PowerDev) {
		applyMachine(d)
	}

	// MARK: pulses

	func pulseTick() {
		let sim: PowerSim = power
		sim.tickNo += 1
		sim.swaps = 48
		let now: Int = sim.tickNo
		// sources that watch the world
		for d in sim.polled {
			if d.tile == .pushButton {
				if d.timer > 0 {
					d.timer -= 0.05
					if d.timer <= 0 { setOut(d, false) }
				}
				continue
			}
			if d.tile == .pressurePlate {
				if (now &+ d.x) % 2 == 0 { setOut(d, plateDown(d)) }
				continue
			}
			// sensors look four times a second, staggered, and only with power
			if (now &+ d.x &+ d.y) % 5 != 0 { continue }
			setOut(d, d.powered && sensorReads(d))
		}
		// logic outputs whose delay has run out
		for d in sim.logic {
			if d.burnT > 0 {
				d.burnT -= 0.05
				if d.burnT <= 0 { d.burnT = 0; sim.queue.insert(d.li) }
				continue
			}
			if d.tile == .pulseTimer && d.mode == 0 { clockStep(d) }
			while let p = d.pend.first, p.0 <= now {
				d.pend.removeFirst()
				setOut(d, p.1)
			}
		}
		// nets whose drivers changed
		var changed: [PulseNet] = []
		for n in sim.snets where n.dirty {
			n.dirty = false
			var on: Bool = false
			for s in n.sources where s.out && s.burnT <= 0 { on = true; break }
			if on != n.on || sim.settle {
				n.on = on
				changed.append(n)
			}
		}
		sim.settle = false
		for n in changed {
			for r in n.readers {
				if r.role == .logic {
					if r.li >= 0 { sim.queue.insert(r.li) }
				} else {
					controlChanged(r)
				}
			}
			for c in n.followers { followPulse(c, n.on) }
		}
		// logic parts whose inputs changed: work out the new output, due after its delay
		if !sim.queue.isEmpty {
			let list: [Int] = sim.queue.sorted()
			sim.queue.removeAll()
			var budget: Int = 3000
			for i in list {
				if i >= sim.logic.count { continue }
				budget -= 1
				if budget < 0 { sim.queue.insert(i); continue }
				evalLogic(sim.logic[i], now)
			}
		}
	}

	/// Whether any pulse net on a device's own cell is on (a lamp, gate or machine's control)
	func pulseHere(_ d: PowerDev) -> Bool? {
		var wired: Bool = false
		var on: Bool = false
		for c in 0..<2 where d.snets[c] >= 0 {
			wired = true
			if power.snets[d.snets[c]].on { on = true }
		}
		return wired ? on : nil
	}

	/// Reads a logic part's input on one side (either colour)
	func portOn(_ d: PowerDev, _ side: Int) -> Bool? {
		var wired: Bool = false
		var on: Bool = false
		for c in 0..<2 {
			let s: Int = d.ports[side * 2 + c]
			if s >= 0 {
				wired = true
				if power.snets[s].on { on = true }
			}
		}
		return wired ? on : nil
	}

	func evalLogic(_ d: PowerDev, _ now: Int) {
		if d.burnT > 0 { return }
		let back: Int = (d.dir + 2) % 4
		var target: Bool = d.out
		var delay: Int = 1
		switch d.tile {
		case .inverter:
			target = !(portOn(d, back) ?? false)
		case .repeater:
			target = portOn(d, back) ?? false
			delay = clampI(Int(d.param.rounded()), 1, 4)
		case .logicGate:
			let a: Bool = portOn(d, (d.dir + 1) % 4) ?? false
			let b: Bool = portOn(d, (d.dir + 3) % 4) ?? false
			switch d.mode {
			case 0: target = a && b
			case 1: target = a || b
			case 2: target = a != b
			case 3: target = !(a && b)
			default: target = !(a || b)
			}
		case .pulseTimer:
			if d.mode == 1 {
				// delay: the output repeats the input's changes after the set time
				target = portOn(d, back) ?? false
				delay = max(1, Int((d.param / 0.05).rounded()))
			} else {
				// clock: an input wired to the back switches it on and off
				return
			}
		default:
			return
		}
		let last: Bool = d.pend.last?.1 ?? d.out
		if target == last { return }
		if d.pend.count >= 16 { d.pend.removeFirst() }
		d.pend.append((now + delay, target))
	}

	/// A clock timer: on for half its period, off for the other half, while enabled
	func clockStep(_ d: PowerDev) {
		let enabled: Bool = portOn(d, (d.dir + 2) % 4) ?? true
		if !enabled {
			d.timer = 0
			if d.out { setOut(d, false) }
			return
		}
		d.timer += 0.05
		let half: Double = max(0.1, d.param * 0.5)
		if d.timer >= half - 1e-9 {
			d.timer = 0
			setOut(d, !d.out)
		}
	}

	/// Changes what a device sends out, marking the nets it drives. A part that flips more than about
	/// twenty-five times a second (a loop with no delay worth the name) burns out for three seconds.
	func setOut(_ d: PowerDev, _ v: Bool) {
		if d.out == v { return }
		let sim: PowerSim = power
		if clock - d.flipT > 1.0 {
			d.flipT = clock
			d.flips = 0
		}
		d.flips += 1
		if d.flips > 25 {
			d.burnT = 3.0
			d.out = false
			d.pend.removeAll()
			if sim.burnNote <= 0 {
				sim.burnNote = 4.0
				floatText("Circuit overloaded: flipping too fast", Double(d.x) + 0.5, Double(d.y) - 0.6, 0xFF8040)
				spawnParticles(Double(d.x) + 0.5, Double(d.y) + 0.3, 0x8A8A8A, 6, 1.5, 0.8, -4)
			}
		} else {
			d.out = v
		}
		if d.role == .logic {
			for c in 0..<2 {
				let s: Int = d.ports[d.dir * 2 + c]
				if s >= 0 { sim.snets[s].dirty = true }
			}
		} else {
			for c in 0..<2 where d.snets[c] >= 0 { sim.snets[d.snets[c]].dirty = true }
		}
	}

	/// Something stands on a pressure plate: anyone, only the player, or only creatures
	func plateDown(_ d: PowerDev) -> Bool {
		let x0: Double = Double(d.x) + 0.1
		let x1: Double = Double(d.x) + 0.9
		let y0: Double = Double(d.y) + 0.3
		let y1: Double = Double(d.y) + 1.05
		if d.mode != 2 && !dead && pb.right > x0 && pb.left < x1 && pb.y > y0 && pb.y < y1 + 0.1 { return true }
		if d.mode == 1 { return false }
		for m in mobsNear(x0 - 2, x1 + 2) where m.hp > 0 {
			if m.b.right > x0 && m.b.left < x1 && m.b.y > y0 && m.b.y < y1 + 0.1 { return true }
		}
		return false
	}

	/// What a sensor sees (it only reports with power)
	func sensorReads(_ d: PowerDev) -> Bool {
		let cx: Double = Double(d.x) + 0.5
		let cy: Double = Double(d.y) + 0.5
		switch d.tile {
		case .daySensor:
			let day: Bool = world.dim == .overworld && dayFactor > 0.5
			return d.mode == 0 ? day : !day
		case .weatherSensor:
			if !settings.weatherOn || world.dim != .overworld { return false }
			let L: LocalWeather = weatherAt(cx, cy)
			switch d.mode {
			case 0: return L.precip > 0.12
			case 1: return L.thunder > 0.3 || L.hail > 0.1
			case 2: return abs(L.wind) > 10
			default: return sirenWorthy() || L.tornado > 0.05 || L.hurricane > 0.05
			}
		case .vehicleSensor:
			return vehicleNearSensor(cx, cy, clampD(d.param, 1, 8), d.mode)
		case .motionSensor, .proximitySensor:
			// motion: 0 anything moving, 1 creatures only, 2 the player only
			// proximity: 0 the player, 1 hostile creatures, 2 any creature, 3 anyone
			let r: Double = clampD(d.param, 2, 12)
			let moving: Bool = d.tile == .motionSensor
			let player: Bool = moving ? d.mode != 1 : (d.mode == 0 || d.mode == 3)
			let creatures: Bool = moving ? d.mode != 2 : d.mode != 0
			let hostileOnly: Bool = !moving && d.mode == 1
			if player && !dead {
				let dx: Double = pb.x - cx
				let dy: Double = pb.cy - cy
				if dx * dx + dy * dy <= r * r && (!moving || abs(pb.vx) > 0.6 || abs(pb.vy) > 0.6) { return true }
			}
			if !creatures { return false }
			for m in mobsNear(cx - r, cx + r) where m.hp > 0 && !m.removed {
				let dx: Double = m.b.x - cx
				let dy: Double = m.b.cy - cy
				if dx * dx + dy * dy > r * r { continue }
				if moving && abs(m.b.vx) < 0.6 && abs(m.b.vy) < 0.6 { continue }
				if hostileOnly && !(m.def.hostile && !m.tame) { continue }
				return true
			}
			return false
		case .itemSensor:
			var n: Int = 0
			var full: Bool = false
			for side in 0..<4 {
				let nx: Int = d.x + sideDX[side]
				let ny: Int = d.y + sideDY[side]
				if world.tile(nx, ny) == .chest {
					let items: [Stack] = world.chestItems(nx, ny)
					for s in items { n += s.count }
					if items.count >= 27 && items.allSatisfy({ $0.count >= $0.item.maxStack }) { full = true }
				}
			}
			for dr in drops where abs(dr.x - cx) < 0.7 && abs(dr.y - cy) < 0.8 { n += dr.stack.count }
			switch d.mode {
			case 0: return n >= 1
			case 1: return n >= 16
			case 2: return n >= 64
			default: return full
			}
		default:
			return false
		}
	}

	/// The pulse on a machine's cell changed
	func controlChanged(_ d: PowerDev) {
		applyMachine(d)
	}

	/// Brings a machine, switch or light in line with its power and its pulse. Lamps and gates change
	/// their tile; a few such changes are allowed per step, the rest wait for the next one.
	func applyMachine(_ d: PowerDev) {
		let sim: PowerSim = power
		let pulse: Bool? = pulseHere(d)
		switch d.tile {
		case .powerSwitch:
			if let p = pulse, p != d.on {
				d.on = p
				world.powerRev &+= 1
			}
			return
		case .lampOff, .lampOn:
			d.enabled = pulse ?? true
			let lit: Bool = d.enabled && d.powered
			let want: Tile = lit ? .lampOn : .lampOff
			if d.tile != want && clock - d.lastSwap > 0.12 && sim.swaps > 0 {
				sim.swaps -= 1
				d.lastSwap = clock
				world.set(d.x, d.y, want)
			}
		case .gateClosed, .gateOpen:
			if let p = pulse {
				d.enabled = true
				d.on = p
			}
			// a powered gate needs power to move; with no pulse wire, its own setting (tap it) decides
			let open: Bool = d.on && d.powered
			let want: Tile = open ? .gateOpen : .gateClosed
			if d.tile != want && clock - d.lastSwap > 0.12 && sim.swaps > 0 {
				if want == .gateClosed && doorBlocked(d.x, d.y, d.y) { return }
				sim.swaps -= 1
				d.lastSwap = clock
				world.set(d.x, d.y, want)
				sfx(.door, at: Double(d.x), 0.4)
			}
		default:
			if modPowerLamp(d, pulse) { return }
			// a machine runs while its pulse wire is on (or always, with none); a sensor's own cell carries
			// its own output, so sensors are never switched by it
			if d.role == .machine || d.role == .indicator { d.enabled = pulse ?? true }
		}
	}

	/// A door, shutter or siren on a pulse wire
	func followPulse(_ c: IntPair, _ on: Bool) {
		let t: Tile = world.tile(c.x, c.y)
		let sim: PowerSim = power
		if sim.swaps <= 0 { return }
		switch t {
		case .doorClosed, .doorOpen:
			let open: Bool = t == .doorOpen
			if open != on {
				sim.swaps -= 1
				setDoor(c.x, c.y, open: on)
			}
		case .shutterClosed, .shutterOpen:
			let closed: Bool = t == .shutterClosed
			if closed != on {
				sim.swaps -= 1
				world.set(c.x, c.y, on ? .shutterClosed : .shutterOpen)
			}
		default:
			break
		}
	}

	/// Whether a pulse is on at a cell (sirens ask this)
	func pulseOnAt(_ x: Int, _ y: Int) -> Bool {
		let sim: PowerSim = power
		for layer in 1...2 {
			if let s = sim.cellNet[PowerSim.cellKey(layer, x, y)], s < sim.snets.count, sim.snets[s].on { return true }
		}
		return false
	}

	// MARK: machines

	/// Machines at work (ten times a second): traps, drills, collectors, crafters and pumps
	func machineTick(_ dt: Double) {
		let sim: PowerSim = power
		var posts: [Bool] = [Bool](repeating: false, count: Radio.channels)
		for d in sim.machines {
			// a signal post sends its channel while it runs
			if d.tile == .signalPost {
				applyMachine(d)
				if d.enabled && d.powered { posts[clampI(d.mode, 0, Radio.channels - 1)] = true }
				continue
			}
			// a lamp or gate that was held back by the limit on tile changes catches up
			if d.tile == .lampOff || d.tile == .lampOn || d.tile == .gateClosed || d.tile == .gateOpen || d.tile.isMod { applyMachine(d) }
			let running: Bool = d.enabled && d.powered
			if !running {
				d.work = 0
				continue
			}
			switch d.tile {
			case .arcTrap: runArcTrap(d, dt)
			case .autoDrill: runDrill(d, dt)
			case .exoStation: runSuitDock(d, dt)
			case .collector: runCollector(d, dt)
			case .autoCrafter: runCrafter(d, dt)
			case .sumpPump: runPump(d, dt)
			default: break
			}
		}
		postChannels = posts
	}

	/// An arc trap zaps whatever stands on it, once a second (the player only if set to)
	func runArcTrap(_ d: PowerDev, _ dt: Double) {
		d.work -= dt
		if d.work > 0 { return }
		let x0: Double = Double(d.x) + 0.05
		let x1: Double = Double(d.x) + 0.95
		let y0: Double = Double(d.y) - 2.0
		let y1: Double = Double(d.y) + 0.05
		var hit: Bool = false
		var info = DamageInfo(amount: 7, type: .shock, source: .environment)
		info.knock = 3.0
		info.originX = Double(d.x) + 0.5
		info.key = d.key.hashValue
		info.cooldown = 0.9
		for m in mobsNear(x0 - 2, x1 + 2) where m.hp > 0 && !m.tame {
			if m.b.right > x0 && m.b.left < x1 && m.b.y > y0 && m.b.y <= y1 + 0.1 {
				if applyMobDamage(m, info) { hit = true }
			}
		}
		if d.flag && !dead && pb.right > x0 && pb.left < x1 && pb.y > y0 && pb.y <= y1 + 0.1 {
			if hurtPlayer(info) { hit = true }
		}
		if hit {
			d.work = 1.0
			sfx(.zap, at: Double(d.x), 0.5)
			spawnParticles(Double(d.x) + 0.5, Double(d.y) - 0.3, 0x8AF0E8, 8, 4.0, 0.25, 0)
			addLightFlash(Double(d.x) + 0.5, Double(d.y) - 0.5, peak: 9, dur: 0.25, radius: 1.6, color: 0x8AF0E8)
		}
	}

	/// An auto drill bores out the block it faces, as fast as the block's hardness allows. It digs what
	/// an iron pickaxe could, and what it breaks drops as if mined by hand.
	func runDrill(_ d: PowerDev, _ dt: Double) {
		let tx: Int = d.x + sideDX[d.dir]
		let ty: Int = d.y + sideDY[d.dir]
		let t: Tile = world.tile(tx, ty)
		if t == .air || t.liquid || t.hardness >= 50 || t.def.tier > 3 || t == .chest || t.isPower || t == .portalFrame || t == .portalOn || t == .portalOff || t == .bedrock {
			d.work = 0
			return
		}
		d.work += dt
		let need: Double = 0.6 + t.hardness * 0.9
		if Int(d.work * 6.0) != Int((d.work - dt) * 6.0) {
			spawnParticles(Double(tx) + 0.5, Double(ty) + 0.5, t.def.colors.first ?? 0x888888, 1, 2.0, 0.3, 10)
		}
		if d.work >= need {
			d.work = 0
			breakTile(tx, ty, false)
			sfx(.digStone, at: Double(tx), 0.4)
		}
	}

	/// An item collector draws loose items within two blocks into a chest beside it, as far as they fit
	func runCollector(_ d: PowerDev, _ dt: Double) {
		d.work -= dt
		if d.work > 0 { return }
		d.work = 0.25
		var chest: IntPair? = nil
		for side in 0..<4 where world.tile(d.x + sideDX[side], d.y + sideDY[side]) == .chest {
			chest = IntPair(x: d.x + sideDX[side], y: d.y + sideDY[side])
			break
		}
		guard let c = chest else { return }
		let cx: Double = Double(d.x) + 0.5
		let cy: Double = Double(d.y) + 0.5
		var items: [Stack] = world.chestItems(c.x, c.y)
		var changed: Bool = false
		var i: Int = 0
		while i < drops.count {
			let dr: DropItem = drops[i]
			if abs(dr.x - cx) > 2.0 || abs(dr.y - cy) > 2.0 || dr.age < 0.3 { i += 1; continue }
			let left: Int = chestAdd(&items, dr.stack)
			if left == dr.stack.count { i += 1; continue }
			changed = true
			spawnParticles(dr.x, dr.y, 0xE8E0C0, 2, 1.5, 0.2, 0)
			if left == 0 {
				drops.remove(at: i)
			} else {
				drops[i].stack.count = left
				i += 1
			}
		}
		if changed { world.setChestItems(c.x, c.y, items) }
	}

	/// An auto crafter makes its chosen recipe every two seconds from the chest behind it into the chest
	/// in front of it, but only when every ingredient is there and the result fits
	func runCrafter(_ d: PowerDev, _ dt: Double) {
		d.work += dt
		if d.work < 2.0 { return }
		d.work = 0
		if d.item < 0 || d.item >= RecipeBook.all.count { return }
		let r: Recipe = RecipeBook.all[d.item]
		if !crafterCan(r.station) { return }
		let side: Int = d.dir == 2 ? 2 : 0
		let ix: Int = d.x - sideDX[side]
		let ox: Int = d.x + sideDX[side]
		if world.tile(ix, d.y) != .chest || world.tile(ox, d.y) != .chest { return }
		var input: [Stack] = world.chestItems(ix, d.y)
		var output: [Stack] = world.chestItems(ox, d.y)
		for c in r.cost where chestCount(input, c.item) < c.n { return }
		var trial: [Stack] = output
		if chestAdd(&trial, Stack(item: r.out, count: r.outCount)) > 0 { return }
		for c in r.cost { chestTake(&input, c.item, c.n) }
		_ = chestAdd(&output, Stack(item: r.out, count: r.outCount))
		world.setChestItems(ix, d.y, input)
		world.setChestItems(ox, d.y, output)
		sfx(.craft, at: Double(d.x), 0.4)
		spawnParticles(Double(d.x) + 0.5, Double(d.y) + 0.2, 0xC8B060, 4, 2.0, 0.3, 6)
	}

	/// The stations an auto crafter stands in for: hand work, the workbench, the anvil and the
	/// tinker's bench (not the furnace, campfire or Rift Forge, which need heat or the Umbral fire)
	func crafterCan(_ s: Station) -> Bool {
		return s == .hand || s == .bench || s == .anvil || s == .tinker
	}

	/// A sump pump drains the nearest water within four blocks, a block at a time, into a rain barrel
	/// or cistern beside it if there is one
	func runPump(_ d: PowerDev, _ dt: Double) {
		d.work += dt
		if d.work < 0.4 { return }
		d.work = 0
		// a block's worth of water a stroke, from the nearest cells first (the water flows, so a
		// part-full cell counts by what it holds)
		var cells: [(Int, IntPair)] = []
		for dy in -4...4 {
			for dx in -4...4 {
				let x: Int = d.x + dx
				let y: Int = d.y + dy
				if world.tile(x, y) != .water { continue }
				cells.append((abs(dx) + abs(dy), IntPair(x: x, y: y)))
			}
		}
		if cells.isEmpty { return }
		cells.sort { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1.y < $1.1.y) }
		var want: Int = 255
		for c in cells where want > 0 {
			let have: Int = world.liquidLevel(c.1.x, c.1.y)
			let take: Int = min(have, want)
			world.setLiquidLevel(c.1.x, c.1.y, .water, have - take)
			want -= take
		}
		let w: IntPair = cells[0].1
		spawnParticles(Double(w.x) + 0.5, Double(w.y) + 0.5, 0x3B7BE0, 3, 1.5, 0.3, 8)
		for side in 0..<4 {
			let nx: Int = d.x + sideDX[side]
			let ny: Int = d.y + sideDY[side]
			let t: Tile = world.tile(nx, ny)
			if t == .rainBarrel || t == .rainCistern {
				let k: String = deviceKey(DeviceSpot(x: nx, y: ny, t: t))
				let cap: Double = t == .rainBarrel ? 8 : 32
				weather.store[k] = min(cap, (weather.store[k] ?? 0) + 1)
				break
			}
		}
	}

	/// Running conveyor belts carry what lies on them (and walk anyone standing on them along)
	func runConveyors(_ dt: Double) {
		let sim: PowerSim = power
		var belts: [Int: Int] = [:]
		for d in sim.conveyors where d.enabled && d.powered {
			belts[PowerSim.cellKey(0, d.x, d.y)] = d.dir == 2 ? -1 : 1
		}
		if belts.isEmpty { return }
		let speed: Double = 2.4
		for i in 0..<drops.count {
			let dr: DropItem = drops[i]
			let k: Int = PowerSim.cellKey(0, Int(floor(dr.x)), Int(floor(dr.y + 0.1)))
			if let s = belts[k] {
				drops[i].x += Double(s) * speed * dt
				drops[i].vx = 0
			}
		}
		if !dead && inVehicle == nil && pb.onGround {
			let k: Int = PowerSim.cellKey(0, Int(floor(pb.x)), Int(floor(pb.y + 0.1)))
			if let s = belts[k] { pb.x += Double(s) * speed * 0.8 * dt }
		}
		for m in mobs where m.hp > 0 && m.b.onGround && !m.def.flying {
			let k: Int = PowerSim.cellKey(0, Int(floor(m.b.x)), Int(floor(m.b.y + 0.1)))
			if let s = belts[k] { m.b.x += Double(s) * speed * 0.8 * dt }
		}
	}

	/// The devices' settings and charge for the save (wiring is saved with each chunk)
	var powerDebugLine: String {
		let sim: PowerSim = power
		var short: Int = 0
		for n in sim.pnets where n.short { short += 1 }
		var on: Int = 0
		for n in sim.snets where n.on { on += 1 }
		return joinText(String(sim.devs.count), " devices live (", String(world.devs.count), " placed) · ", String(sim.pnets.count), " power lines (", String(short), " short) · ", String(sim.snets.count), " pulse lines (", String(on), " on) · rebuilt ", String(sim.rebuilds), "x")
	}

	/// Debug: one of every Sparkworks part, and plenty of wire
	func debugPowerKit() {
		let parts: [Tile] = [.crankGen, .solarPanel, .fuelGen, .waterWheel, .emberDynamo, .battery, .accumulator, .powerSwitch, .breaker, .powerMeter,
							 .lever, .pushButton, .pressurePlate, .pulseTimer, .repeater, .inverter, .logicGate, .motionSensor, .daySensor, .weatherSensor,
							 .itemSensor, .proximitySensor, .gateClosed, .lampOff, .arcTrap, .autoDrill, .conveyor, .collector, .autoCrafter, .sumpPump, .signalLight,
							 .signalPost, .vehicleSensor]
		for g in [Gadget.powerCable, .pulseWire, .pulseWireB] { giveItem(.gadget(g), 250) }
		giveItem(.gadget(.wireSnips), 1)
		giveItem(.gadget(.probe), 1)
		for t in parts { giveItem(.block(t), 8) }
		say("Power kit: every Sparkworks part, wire, snips and a probe.", 2.5)
		bumpHUD()
	}

	func debugChargeAll() {
		for (_, d) in world.devs {
			let c: Double = PowerSpec.capacity(d.tile)
			if c > 0 { d.charge = c }
			if d.tile == .fuelGen || d.tile == .emberDynamo { d.charge = 3600 }
		}
		say("Batteries charged, generators fuelled.", 1.5)
	}

	func powerSave() -> [PowerDevSave]? {
		if world.devs.isEmpty { return nil }
		var out: [PowerDevSave] = []
		for (k, d) in world.devs {
			out.append(PowerDevSave(d: k.d, x: k.x, y: k.y, t: Int(d.tile.rawValue), dir: d.dir, mode: d.mode, param: d.param, charge: d.charge, on: d.on, flag: d.flag, item: d.item))
		}
		out.sort { $0.d != $1.d ? $0.d < $1.d : ($0.x != $1.x ? $0.x < $1.x : $0.y < $1.y) }
		return out
	}

	// MARK: chests as machine storage (27 stacks, stacked up to each item's limit)

	func chestCount(_ items: [Stack], _ it: Item) -> Int {
		var n: Int = 0
		for s in items where s.item == it { n += s.count }
		return n
	}

	/// Adds a stack to a chest's contents; returns how many did not fit
	func chestAdd(_ items: inout [Stack], _ st: Stack) -> Int {
		var left: Int = st.count
		let ms: Int = st.item.maxStack
		if ms > 1 {
			for i in 0..<items.count where left > 0 && items[i].item == st.item && items[i].extra == st.extra && items[i].count < ms {
				let put: Int = min(ms - items[i].count, left)
				items[i].count += put
				left -= put
			}
		}
		while left > 0 && items.count < 27 {
			let put: Int = min(ms, left)
			items.append(Stack(item: st.item, count: put, extra: st.extra))
			left -= put
		}
		return left
	}

	func chestTake(_ items: inout [Stack], _ it: Item, _ n: Int) {
		var left: Int = n
		var i: Int = items.count - 1
		while i >= 0 && left > 0 {
			if items[i].item == it {
				let take: Int = min(items[i].count, left)
				items[i].count -= take
				left -= take
				if items[i].count <= 0 { items.remove(at: i) }
			}
			i -= 1
		}
	}
}

// MARK: - Sparkworks: wiring by touch, the probe, tapping devices

/// The network the probe last looked at, lit up on screen for a few seconds
struct PowerInspect {
	var layer: Int
	var cells: [IntPair]
	var t: Double
}

struct PanelLine {
	var text: String
	var color: UInt32
}

extension Game {
	/// A wiring tool or the probe is in hand (wiring is drawn in full)
	var holdingWiringTool: Bool {
		if case .gadget(let g)? = heldItem { return g.wiring || g == .probe }
		return false
	}

	/// A line on the HUD while a wiring tool is in hand
	var wiringHint: String? {
		guard case .gadget(let g)? = heldItem else { return nil }
		switch g {
		case .powerCable: return "Drag to lay power cable through generators, batteries and machines"
		case .pulseWire, .pulseWireB: return "Drag to lay pulse wire from switches and sensors to what they control"
		case .wireSnips: return "Drag over wire to take it back up"
		case .probe: return "Tap a device to set it up, or a wire to see its network"
		default: return nil
		}
	}

	var holdingWireSpool: Bool {
		if case .gadget(let g)? = heldItem { return g.wiring }
		return false
	}

	/// Dragging with a spool lays wire cell by cell (a fast drag leaves no gaps); snips take it back up
	func useWiring(_ g: Gadget, _ pressed: Bool) {
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		let here: IntPair = IntPair(x: tx, y: ty)
		guard let last = wireLast, !pressed else {
			wireLast = here
			_ = wireCell(g, tx, ty)
			return
		}
		if last == here { return }
		var x: Int = last.x
		var y: Int = last.y
		var n: Int = 0
		while (x != tx || y != ty) && n < 64 {
			// step along whichever way is further to go, so a diagonal drag makes a staircase
			if abs(tx - x) >= abs(ty - y) { x += tx > x ? 1 : -1 } else { y += ty > y ? 1 : -1 }
			n += 1
			if !wireCell(g, x, y) { break }
		}
		wireLast = IntPair(x: x, y: y)
	}

	/// Lays (or with snips, removes) wire on one cell; false stops the drag (out of reach or of wire)
	func wireCell(_ g: Gadget, _ x: Int, _ y: Int) -> Bool {
		let dx: Double = Double(x) + 0.5 - pb.x
		let dy: Double = Double(y) + 0.5 - (pb.y - pb.h * 0.6)
		let r: Double = reachDistance() + 2.5
		if dx * dx + dy * dy > r * r || !world.isLoaded(x) { return false }
		let cur: UInt8 = world.wireAt(x, y)
		if g == .wireSnips {
			if cur == 0 { return true }
			if !isCreative {
				let back: [Gadget] = [.powerCable, .pulseWire, .pulseWireB]
				for layer in 0..<3 where cur & Wire.bit(layer) != 0 { giveItem(.gadget(back[layer]), 1) }
			}
			world.setWire(x, y, 0)
			spawnParticles(Double(x) + 0.5, Double(y) + 0.5, 0xD2793A, 2, 1.5, 0.25, 10)
			wireSound()
			return true
		}
		let bit: UInt8 = Wire.bit(g.wireLayer)
		if cur & bit != 0 { return true }
		// a logic part's own cell takes no pulse wire: its sides are its inputs and its output
		if g.wireLayer > 0 && powerRole(world.tile(x, y)) == .logic { return true }
		if !isCreative {
			guard let st = heldStack, st.item == .gadget(g), st.count > 0 else {
				say(joinText("Out of ", g.name.lowercased(), "."), 1.5)
				return false
			}
			inv.removeAt(sel, 1)
		}
		world.setWire(x, y, cur | bit)
		wireSound()
		bumpHUD()
		return true
	}

	func wireSound() {
		if clock - wireSoundT > 0.06 {
			wireSoundT = clock
			sfx(.tap, 0.3)
		}
	}

	// MARK: the probe

	/// The probe on a device opens its panel; on a wire it lights up the whole network and says how it is
	func probeAt(_ wx: Double, _ wy: Double) {
		let tx: Int = Int(floor(wx))
		let ty: Int = Int(floor(wy))
		if let d = world.powerDev(tx, ty), world.tile(tx, ty).isPower {
			openPowerPanel(d)
			let layer: Int = d.pnet >= 0 ? 0 : (d.snets[0] >= 0 ? 1 : (d.snets[1] >= 0 ? 2 : -1))
			if layer >= 0 { inspectNet(layer, tx, ty) }
			return
		}
		let bits: UInt8 = world.wireAt(tx, ty)
		if bits == 0 {
			say("Nothing wired here. Tap a device or a wire.", 1.5)
			return
		}
		// several layers on one cell: each tap shows the next
		var layer: Int = -1
		let start: Int = (inspect?.cells.contains(IntPair(x: tx, y: ty)) ?? false) ? ((inspect?.layer ?? -1) + 1) : 0
		for k in 0..<3 {
			let l: Int = (start + k) % 3
			if bits & Wire.bit(l) != 0 { layer = l; break }
		}
		if layer < 0 { return }
		inspectNet(layer, tx, ty)
		say(netSummary(layer, tx, ty), 4.0)
		sfx(.tap, 0.5)
	}

	/// Lights up every cell of one network
	func inspectNet(_ layer: Int, _ x: Int, _ y: Int) {
		let bit: UInt8 = Wire.bit(layer)
		var seen: Set<IntPair> = [IntPair(x: x, y: y)]
		var stack: [IntPair] = [IntPair(x: x, y: y)]
		var cells: [IntPair] = []
		while let c = stack.popLast(), cells.count < 4000 {
			cells.append(c)
			if !conducts(layer, c.x, c.y) && !(c.x == x && c.y == y) { continue }
			for side in 0..<4 {
				let n: IntPair = IntPair(x: c.x + sideDX[side], y: c.y + sideDY[side])
				if seen.contains(n) || world.wireAt(n.x, n.y) & bit == 0 { continue }
				seen.insert(n)
				stack.append(n)
			}
		}
		inspect = PowerInspect(layer: layer, cells: cells, t: 8.0)
	}

	/// One line about a network: what it makes, uses and stores, or whether a pulse is on
	func netSummary(_ layer: Int, _ x: Int, _ y: Int) -> String {
		let sim: PowerSim = power
		guard let i = sim.cellNet[PowerSim.cellKey(layer, x, y)] else { return "This wire is not connected to anything yet." }
		if layer == 0 {
			if i >= sim.pnets.count { return "Power cable" }
			let n: PowerNet = sim.pnets[i]
			var s: String = joinText("Power line: makes ", sparks(n.made), ", uses ", sparks(n.used))
			if n.cap > 0 { s = joinText(s, ", stored ", String(Int(n.stored)), "/", String(Int(n.cap))) }
			if n.short { s = joinText(s, ". NOT ENOUGH POWER: machines want ", sparks(n.asked)) }
			if n.devs.isEmpty { s = "Power cable with nothing on it yet." }
			return s
		}
		if i >= sim.snets.count { return "Pulse wire" }
		let n: PulseNet = sim.snets[i]
		let col: String = layer == 1 ? "Amber" : "Teal"
		return joinText(col, " pulse line: ", n.on ? "ON" : "off", " · ", String(n.sources.count), " sending, ", String(n.readers.count + n.followers.count), " listening")
	}

	func sparks(_ v: Double) -> String { return String(format: "%.1f sparks/s", v) }

	// MARK: tapping a device

	/// A device does its own thing when tapped: levers flip, buttons press, a crank winds up, a
	/// breaker resets, fuel goes in; anything else opens its panel
	func usePowerDevice(_ x: Int, _ y: Int, _ t: Tile) {
		guard let d = world.powerDev(x, y) else { return }
		// wearing the suit, a tap on a battery fills the suit from it
		if (t == .battery || t == .accumulator) && suit.worn && chargeSuitFrom(d) { return }
		switch t {
		case .lever:
			d.on.toggle()
			setOut(d, d.on)
			sfx(.tap, at: Double(x), 0.8)
			spawnParticles(Double(x) + 0.5, Double(y) + 0.6, 0xC8CCD4, 2, 1.0, 0.2, 6)
		case .pushButton:
			d.timer = max(0.25, d.param)
			setOut(d, true)
			sfx(.tap, at: Double(x), 0.8)
		case .crankGen:
			// winding by hand is work: a little hunger for every turn
			let cap: Double = PowerSpec.capacity(.crankGen)
			if d.charge >= cap - 0.5 {
				say("The flywheel is spinning as fast as it can.", 1.2)
				return
			}
			d.charge = min(cap, d.charge + 15)
			if !isCreative { hunger = max(0, hunger - 0.08) }
			sfx(.swingLight, at: Double(x), 0.5)
			spawnParticles(Double(x) + 0.8, Double(y) + 0.2, 0xFFC020, 3, 2.0, 0.3, 6)
			floatText(joinText(String(Int(d.charge)), " / ", String(Int(cap))), Double(x) + 0.5, Double(y) - 0.4, 0xFFD060)
		case .breaker:
			if !d.on {
				d.on = true
				d.flag = false
				world.powerRev &+= 1
				say("Breaker reset. If the line is still overloaded it will trip again.", 2.0)
			} else {
				d.on = false
				world.powerRev &+= 1
				say("Breaker opened: the line is cut here.", 1.5)
			}
			sfx(.tap, at: Double(x), 0.8)
		case .powerSwitch:
			if d.snets[0] >= 0 || d.snets[1] >= 0 {
				say("This switch follows its pulse wire.", 1.5)
			} else {
				d.on.toggle()
				world.powerRev &+= 1
				sfx(.tap, at: Double(x), 0.8)
			}
		case .fuelGen, .emberDynamo:
			if let it = heldItem, fuelSeconds(it, dynamo: t == .emberDynamo) > 0 {
				let secs: Double = fuelSeconds(it, dynamo: t == .emberDynamo)
				if d.charge + secs > 3600 {
					say("It is full of fuel.", 1.2)
					return
				}
				d.charge += secs
				if !isCreative { inv.removeAt(sel, 1) }
				sfx(.place, at: Double(x), 0.5)
				floatText(joinText("Fuel: ", fuelText(d.charge)), Double(x) + 0.5, Double(y) - 0.4, 0xFFB050)
				bumpHUD()
			} else {
				openPowerPanel(d)
			}
		case .gateClosed, .gateOpen:
			if pulseHere(d) != nil {
				say("This gate follows its pulse wire.", 1.5)
			} else if !d.powered {
				say("The gate needs power to move.", 1.5)
			} else {
				d.on.toggle()
				applyMachine(d)
			}
		default:
			openPowerPanel(d)
		}
		bumpHUD()
	}

	func fuelText(_ s: Double) -> String {
		if s >= 60 { return joinText(String(Int(s / 60)), " min ", String(Int(s.truncatingRemainder(dividingBy: 60))), " s") }
		return joinText(String(Int(s)), " s")
	}

	func openPowerPanel(_ d: PowerDev) {
		powerAt = d.key
		showPower = true
		sfx(.tap, 0.6)
		bumpHUD()
	}

	var powerDevOpen: PowerDev? {
		guard let k = powerAt else { return nil }
		return world.devs[k]
	}

	// MARK: the device panel

	func modeNames(_ t: Tile) -> [String] {
		switch t {
		case .logicGate: return ["AND", "OR", "XOR", "NAND", "NOR"]
		case .pulseTimer: return ["CLOCK", "DELAY"]
		case .pressurePlate: return ["ANYONE", "PLAYER", "CREATURES"]
		case .motionSensor: return ["ANYTHING", "CREATURES", "PLAYER"]
		case .proximitySensor: return ["PLAYER", "HOSTILE", "ANY CREATURE", "ANYONE"]
		case .vehicleSensor: return ["ANY VEHICLE", "DRIVEN", "NOBODY ABOARD"]
		case .signalPost: return (1...Radio.channels).map { (n: Int) in joinText("CH ", String(n)) }
		case .daySensor: return ["ON BY DAY", "ON AT NIGHT"]
		case .weatherSensor: return ["RAIN/SNOW", "STORM", "STRONG WIND", "SEVERE"]
		case .itemSensor: return ["ANY ITEM", "16+", "64+", "FULL"]
		case .breaker: return PowerSpec.breakerLimits.map { String(Int($0)) }
		default: return []
		}
	}

	func modeTitle(_ t: Tile) -> String {
		switch t {
		case .logicGate: return "Gate type (inputs at the two sides, output where the arrow points)"
		case .pulseTimer: return "Mode"
		case .breaker: return "Trips above (sparks per second asked)"
		case .itemSensor: return "On when the chest beside it holds"
		case .signalPost: return "The channel it sends to receivers"
		default: return "Responds to"
		}
	}

	/// The number a device's panel sets: its label, range and step
	func paramSpec(_ d: PowerDev) -> (String, Double, Double, Double)? {
		switch d.tile {
		case .pushButton: return ("Pulse length (s)", 0.25, 5, 0.25)
		case .pulseTimer: return (d.mode == 0 ? "Period (s)" : "Delay (s)", 0.1, 10, 0.1)
		case .repeater: return ("Delay (steps of 0.05 s)", 1, 4, 1)
		case .motionSensor, .proximitySensor: return ("Range (blocks)", 2, 12, 1)
		case .vehicleSensor: return ("Range (blocks)", 1, 8, 1)
		default: return nil
		}
	}

	func setPowerMode(_ d: PowerDev, _ m: Int) {
		d.mode = m
		if d.role == .logic {
			d.pend.removeAll()
			if d.li >= 0 { power.queue.insert(d.li) }
		}
		if d.tile == .breaker { world.powerRev &+= 1 }
		bumpHUD()
	}

	func stepPowerParam(_ d: PowerDev, _ dir: Double) {
		guard let p = paramSpec(d) else { return }
		d.param = clampD(((d.param + dir * p.3) / p.3).rounded() * p.3, p.1, p.2)
		bumpHUD()
	}

	/// Turns a device a quarter (conveyors and crafters only turn round)
	func rotatePower(_ d: PowerDev) {
		if d.tile == .conveyor || d.tile == .autoCrafter {
			d.dir = d.dir == 0 ? 2 : 0
		} else {
			d.dir = (d.dir + 1) % 4
		}
		d.pend.removeAll()
		world.powerRev &+= 1
		bumpHUD()
	}

	/// What the panel says about a device and the line it is on
	func powerPanelLines(_ d: PowerDev) -> [PanelLine] {
		var out: [PanelLine] = []
		let good: UInt32 = 0x8AF0B0
		let bad: UInt32 = 0xFF8060
		let plain: UInt32 = 0xE8E4D8
		switch d.role {
		case .generator:
			switch d.tile {
			case .crankGen:
				out.append(PanelLine(text: joinText("Flywheel: ", String(Int(d.charge)), " / 60 sparks. Tap it to crank."), color: plain))
			case .fuelGen, .emberDynamo:
				let what: String = d.tile == .emberDynamo ? "ember bars or ember ore" : "coal, logs, planks or sticks"
				out.append(PanelLine(text: joinText("Fuel: ", fuelText(d.charge), ". Tap it holding ", what, " to add more."), color: d.charge > 0 ? plain : bad))
				out.append(PanelLine(text: "It only burns fuel for power that is actually needed.", color: plain))
			case .solarPanel:
				out.append(PanelLine(text: "Makes up to 4 sparks/s in full sun under open sky; clouds and night cut it.", color: plain))
			case .waterWheel:
				out.append(PanelLine(text: "Turns with water around it (up to 6 sparks/s), more in the rain.", color: plain))
			case .windTurbine:
				let k: String = deviceKey(DeviceSpot(x: d.x, y: d.y, t: .windTurbine))
				out.append(PanelLine(text: joinText("Charge: ", String(Int(weather.store[k] ?? 0)), " / 100 (the wind fills it)."), color: plain))
			default:
				break
			}
			out.append(PanelLine(text: joinText("Making ", sparks(d.made)), color: d.made > 0 ? good : plain))
		case .storage:
			let c: Double = PowerSpec.capacity(d.tile)
			out.append(PanelLine(text: joinText("Charge: ", String(Int(d.charge)), " / ", String(Int(c)), " sparks (", String(Int(100 * d.charge / max(1, c))), "%)"), color: d.charge > 1 ? good : plain))
			out.append(PanelLine(text: joinText("Charges and gives back up to ", String(Int(PowerSpec.rate(d.tile))), " sparks/s. Taken down, it loses its charge."), color: plain))
		case .conductor:
			if d.tile == .breaker {
				if d.flag && !d.on { out.append(PanelLine(text: "TRIPPED: too much was asked of this line. Tap it to reset.", color: bad)) }
				else { out.append(PanelLine(text: d.on ? "Closed: power passes." : "Open: the line is cut here.", color: d.on ? good : bad)) }
			} else {
				out.append(PanelLine(text: d.on ? "On: power passes." : "Off: the line is cut here.", color: d.on ? good : bad))
			}
		case .source, .sensor, .logic:
			out.append(PanelLine(text: joinText("Sending: ", d.out ? "ON" : "off"), color: d.out ? good : plain))
			if d.burnT > 0 { out.append(PanelLine(text: "Burnt out for a moment: it was flipping too fast (a loop with no delay?)", color: bad)) }
			if d.role == .logic {
				let back: Int = (d.dir + 2) % 4
				if d.tile == .logicGate {
					let a: String = (portOn(d, (d.dir + 1) % 4) ?? false) ? "ON" : "off"
					let b: String = (portOn(d, (d.dir + 3) % 4) ?? false) ? "ON" : "off"
					out.append(PanelLine(text: joinText("Inputs: ", a, " and ", b), color: plain))
				} else if let i = portOn(d, back) {
					out.append(PanelLine(text: joinText("Input: ", i ? "ON" : "off"), color: plain))
				} else if d.tile != .pulseTimer || d.mode == 1 {
					out.append(PanelLine(text: "No pulse wire at its back (the input).", color: bad))
				}
			}
		case .machine:
			let wants: Double = PowerSpec.draw(d.tile)
			if !d.enabled { out.append(PanelLine(text: "Off: its pulse wire is off.", color: plain)) }
			else if d.powered { out.append(PanelLine(text: joinText("Running on ", sparks(wants)), color: good)) }
			else { out.append(PanelLine(text: joinText("NO POWER: it needs ", sparks(wants)), color: bad)) }
			out.append(PanelLine(text: machineHelp(d.tile), color: plain))
		case .meter:
			out.append(PanelLine(text: "Reads the power line it sits on.", color: plain))
		case .indicator:
			out.append(PanelLine(text: joinText("Shows its pulse wire: ", (pulseHere(d) ?? false) ? "ON" : "off"), color: plain))
		case .none:
			break
		}
		if d.role == .sensor && !d.powered { out.append(PanelLine(text: "Sensors need a little power (0.5 sparks/s) to work.", color: bad)) }
		// the power line it is on
		let usesPower: Bool = d.role == .generator || d.role == .storage || d.role == .machine || d.role == .sensor || d.role == .meter
		if usesPower {
			if d.pnet >= 0 && d.pnet < power.pnets.count {
				let n: PowerNet = power.pnets[d.pnet]
				out.append(PanelLine(text: joinText("Line: makes ", sparks(n.made), " · uses ", sparks(n.used), n.cap > 0 ? joinText(" · stored ", String(Int(n.stored)), "/", String(Int(n.cap))) : ""), color: plain))
				if n.short { out.append(PanelLine(text: joinText("NOT ENOUGH POWER on this line: machines want ", sparks(n.asked)), color: bad)) }
			} else {
				out.append(PanelLine(text: "Not on a power line: lay power cable through it.", color: bad))
			}
		}
		if let p = pulseHere(d), d.role != .logic {
			out.append(PanelLine(text: joinText("Pulse wire here: ", p ? "ON" : "off"), color: p ? good : plain))
		}
		return out
	}

	func machineHelp(_ t: Tile) -> String {
		switch t {
		case .lampOff, .lampOn: return "Lights up while powered (and while its pulse wire is on, if it has one)."
		case .signalPost: return "Sends its channel to every receiver on it while powered (and while its pulse wire is on, if it has one)."
		case .gateClosed, .gateOpen: return "Opens while its pulse wire is on; with none, tap it. Needs power to move."
		case .arcTrap: return "Zaps whatever stands on it, once a second."
		case .autoDrill: return "Bores out the block it faces (what an iron pickaxe could). Drops land as if mined."
		case .exoStation: return "Builds suits; charges a suit worn close by from this line (10 a second, only while it charges)."
		case .conveyor: return "Carries items (and anyone) along the way the arrow points."
		case .collector: return "Draws loose items within two blocks into a chest beside it."
		case .autoCrafter: return "Makes its recipe from the chest behind it into the chest in front, every 2 s."
		case .sumpPump: return "Drains water within four blocks, into a rain barrel or cistern beside it if there is one."
		default: return ""
		}
	}

	/// Recipes an auto crafter can make
	func crafterRecipes() -> [Recipe] {
		return RecipeBook.all.filter { crafterCan($0.station) && $0.modStation == nil }
	}

	func updatePowerUI(_ dt: Double) {
		if var i = inspect {
			i.t -= dt
			inspect = i.t > 0 ? i : nil
		}
		if showPower, let k = powerAt, world.devs[k] == nil {
			showPower = false
			powerAt = nil
			bumpHUD()
		}
	}
}

// MARK: - Sparkworks drawing

extension WorldRenderer {
	/// Wiring over the tiles: copper power cable (bright when the line has power, red flashes when it is
	/// short), and thinner pulse wire in amber and teal that glows while on. Shown in full while a
	/// wiring tool is in hand, and otherwise as the settings say.
	static func drawWiring(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let mode: Int = g.settings.showWires
		let tool: Bool = g.holdingWiringTool
		if mode == 0 && !tool && g.inspect == nil { return }
		let faint: Bool = !tool && mode == 2
		let sim: PowerSim = g.power
		let x0: Int = Int(floor(v.left)) - 1
		let x1: Int = Int(ceil(v.left + v.wTiles)) + 1
		let y0: Int = max(0, Int(floor(v.top)) - 1)
		let y1: Int = min(g.world.H - 1, Int(ceil(v.top + v.hTiles)) + 1)
		let tp: Double = v.tp
		var paths: [Path] = [Path(), Path(), Path(), Path(), Path(), Path(), Path()]
		var used: [Bool] = [false, false, false, false, false, false, false]
		var cx: Int = floorDiv(x0, chunkW)
		let blink: Bool = Int(g.clock * 3.0) % 2 == 0
		while cx <= floorDiv(x1, chunkW) {
			defer { cx += 1 }
			guard let c = g.world.chunk(cx), c.wireCount > 0 else { continue }
			let H: Int = c.H
			let ax: Int = max(x0, c.x0)
			let bx: Int = min(x1, c.x0 + chunkW - 1)
			if ax > bx { continue }
			for x in ax...bx {
				let base: Int = (x - c.x0) * H
				for y in y0...y1 {
					let b: UInt8 = c.wires[base + y]
					if b == 0 { continue }
					for layer in 0..<3 where b & Wire.bit(layer) != 0 {
						let off: Double = layer == 0 ? 0 : (layer == 1 ? -0.2 : 0.2)
						let px: Double = v.sx(Double(x) + 0.5 + off)
						let py: Double = v.sy(Double(y) + 0.5 + off)
						var slot: Int = layer == 0 ? 0 : (layer == 1 ? 2 : 4)
						if let n = sim.cellNet[PowerSim.cellKey(layer, x, y)] {
							if layer == 0, n < sim.pnets.count {
								let net: PowerNet = sim.pnets[n]
								if net.short && blink { slot = 6 } else if net.made > 0 || net.stored > 1 { slot = 1 }
							} else if layer > 0, n < sim.snets.count, sim.snets[n].on {
								slot += 1
							}
						}
						let bit: UInt8 = Wire.bit(layer)
						// a stub to each wired neighbour to the right and below (each joint drawn once)
						if g.world.wireAt(x + 1, y) & bit != 0 {
							paths[slot].move(to: mkPoint(px, py))
							paths[slot].addLine(to: mkPoint(px + tp, py))
						}
						if g.world.wireAt(x, y + 1) & bit != 0 {
							paths[slot].move(to: mkPoint(px, py))
							paths[slot].addLine(to: mkPoint(px, py + tp))
						}
						let r: Double = layer == 0 ? tp * 0.11 : tp * 0.08
						paths[slot].addEllipse(in: mkRect(px - r, py - r, r * 2, r * 2))
						used[slot] = true
					}
				}
			}
		}
		let a: Double = faint ? 0.35 : 1.0
		let cols: [UInt32] = [0x8A5A30, 0xFFA040, 0x6A5010, 0xFFD040, 0x1A6A66, 0x50FFF0, 0xFF4030]
		let widths: [Double] = [0.16, 0.16, 0.09, 0.11, 0.09, 0.11, 0.16]
		for i in 0..<7 where used[i] {
			ctx.stroke(paths[i], with: .color(Color(hex: 0x14100C, alpha: 0.7 * a)), lineWidth: tp * widths[i] + 2.0)
			ctx.stroke(paths[i], with: .color(Color(hex: cols[i], alpha: a)), lineWidth: tp * widths[i])
		}
		// the network the probe is looking at
		if let ins = g.inspect {
			let pulse: Double = 0.35 + 0.25 * sin(g.clock * 6.0)
			let col: UInt32 = ins.layer == 0 ? 0xFFC060 : (ins.layer == 1 ? 0xFFE060 : 0x80FFF0)
			var hp: Path = Path()
			for c in ins.cells where v.visible(Double(c.x), Double(c.y), 2) {
				hp.addRect(v.rect(Double(c.x) + 0.12, Double(c.y) + 0.12, 0.76, 0.76))
			}
			ctx.stroke(hp, with: .color(Color(hex: col, alpha: pulse * min(1.0, ins.t))), lineWidth: 2)
		}
	}

	/// What each device in view is doing: lever handles, lights, arrows on parts that point a way,
	/// charge bars, moving parts, and a red bolt on a machine that wants power and has none
	static func drawPowerDevices(_ ctx: inout GraphicsContext, _ g: Game, _ v: View2D) {
		let sim: PowerSim = g.power
		if sim.devs.isEmpty { return }
		let tp: Double = v.tp
		let blink: Bool = Int(g.clock * 2.5) % 2 == 0
		var dark: Path = Path()
		var amber: Path = Path()
		var teal: Path = Path()
		var red: Path = Path()
		var green: Path = Path()
		var white: Path = Path()
		var fire: Path = Path()
		for d in sim.devs {
			if !v.visible(Double(d.x), Double(d.y), 2) { continue }
			let L: Double = v.sx(Double(d.x))
			let T: Double = v.sy(Double(d.y))
			let cx: Double = L + tp * 0.5
			let cy: Double = T + tp * 0.5
			func led(_ on: Bool, _ px: Double, _ py: Double, _ onPath: inout Path) {
				let r: Double = max(1.5, tp * 0.07)
				if on { onPath.addEllipse(in: mkRect(px - r, py - r, r * 2, r * 2)) } else { dark.addEllipse(in: mkRect(px - r, py - r, r * 2, r * 2)) }
			}
			func arrow(_ dir: Int, _ path: inout Path) {
				let ax: Double = Double(sideDX[dir])
				let ay: Double = Double(sideDY[dir])
				let s: Double = tp * 0.22
				let tipX: Double = cx + ax * tp * 0.34
				let tipY: Double = cy + ay * tp * 0.34
				path.move(to: mkPoint(tipX, tipY))
				path.addLine(to: mkPoint(tipX - ax * s - ay * s, tipY - ay * s + ax * s))
				path.addLine(to: mkPoint(tipX - ax * s + ay * s, tipY - ay * s - ax * s))
				path.closeSubpath()
			}
			switch d.tile {
			case .lever:
				let ang: Double = d.on ? -0.6 : -2.5
				white.move(to: mkPoint(cx, T + tp * 0.7))
				white.addLine(to: mkPoint(cx + cos(ang) * tp * 0.45, T + tp * 0.7 + sin(ang) * tp * 0.45))
				led(d.on, cx + cos(ang) * tp * 0.45, T + tp * 0.7 + sin(ang) * tp * 0.45, &amber)
			case .pushButton:
				if d.out { teal.addRect(mkRect(L + tp * 0.375, T + tp * 0.5, tp * 0.25, tp * 0.25)) }
			case .pressurePlate:
				if d.out { amber.addRect(mkRect(L + tp * 0.15, T + tp * 0.8, tp * 0.7, tp * 0.06)) }
			case .repeater, .inverter, .logicGate, .pulseTimer:
				if d.burnT > 0 { arrow(d.dir, &red) } else if d.out { arrow(d.dir, &amber) } else { arrow(d.dir, &white) }
				if d.tile == .logicGate {
					let names: [String] = ["AND", "OR", "XOR", "NAND", "NOR"]
					drawLabel(&ctx, names[clampI(d.mode, 0, 4)], cx, T + tp * 0.12, max(6.0, tp * 0.26), Color(hex: 0xC8F0E8))
				}
				if d.tile == .pulseTimer {
					let a: Double = d.mode == 0 ? g.clock * 3.0 : (d.out ? 0 : 3.14)
					white.move(to: mkPoint(cx, cy))
					white.addLine(to: mkPoint(cx + cos(a) * tp * 0.25, cy + sin(a) * tp * 0.25))
				}
			case .autoDrill:
				if d.enabled && d.powered { arrow(d.dir, &amber) } else { arrow(d.dir, &white) }
			case .conveyor, .autoCrafter:
				if d.enabled && d.powered { arrow(d.dir, &amber) } else { arrow(d.dir, &white) }
				if d.tile == .conveyor && d.enabled && d.powered {
					let shift: Double = (g.clock * 2.4).truncatingRemainder(dividingBy: 1.0) * (d.dir == 2 ? -1.0 : 1.0)
					for k in 0..<3 {
						var fx: Double = (Double(k) / 3.0 + shift).truncatingRemainder(dividingBy: 1.0)
						if fx < 0 { fx += 1.0 }
						white.addRect(mkRect(L + fx * tp, T + tp * 0.02, max(1.5, tp * 0.06), tp * 0.1))
					}
				}
			case .motionSensor, .daySensor, .weatherSensor, .itemSensor, .proximitySensor, .vehicleSensor:
				led(d.out, L + tp * 0.85, T + tp * 0.15, &teal)
			case .signalPost:
				led(d.enabled && d.powered, L + tp * 0.5, T + tp * 0.1, &amber)
			case .signalLight:
				if g.pulseHere(d) ?? false {
					let glow: Double = tp * 0.32
					teal.addEllipse(in: mkRect(cx - glow, T + tp * 0.4 - glow, glow * 2, glow * 2))
				}
			case .crankGen:
				let spin: Double = g.clock * min(12.0, d.charge * 0.4)
				white.move(to: mkPoint(L + tp * 0.8, T + tp * 0.25))
				white.addLine(to: mkPoint(L + tp * 0.8 + cos(spin) * tp * 0.2, T + tp * 0.25 + sin(spin) * tp * 0.2))
				led(d.made > 0, L + tp * 0.5, T + tp * 0.65, &green)
			case .waterWheel:
				let spin: Double = g.clock * (d.made > 0 ? 1.5 : 0)
				for k in 0..<4 {
					let a: Double = spin + Double(k) * 1.5708
					dark.move(to: mkPoint(cx, cy))
					dark.addLine(to: mkPoint(cx + cos(a) * tp * 0.45, cy + sin(a) * tp * 0.45))
				}
			case .fuelGen, .emberDynamo:
				if d.made > 0 {
					let f: Double = 0.7 + 0.3 * sin(g.clock * 17.0 + Double(d.x))
					fire.addEllipse(in: mkRect(cx - tp * 0.22 * f, T + tp * 0.45, tp * 0.44 * f, tp * 0.3 * f))
				}
				led(d.charge > 0, L + tp * 0.85, T + tp * 0.85, &green)
			case .solarPanel, .windTurbine:
				led(d.made > 0, L + tp * 0.85, T + tp * 0.92, &green)
			case .battery, .accumulator:
				let f: Double = clampD(d.charge / max(1, PowerSpec.capacity(d.tile)), 0, 1)
				let h: Double = tp * 0.6 * f
				if f > 0.01 {
					let col: Path = Path(mkRect(L + tp * 0.32, T + tp * 0.85 - h, tp * 0.36, h))
					ctx.fill(col, with: .color(Color(hex: f > 0.5 ? 0x50E070 : (f > 0.2 ? 0xE8D040 : 0xE05030), alpha: 0.9)))
				}
			case .powerMeter:
				var frac: Double = 0
				var short: Bool = false
				if d.pnet >= 0 && d.pnet < sim.pnets.count {
					let n: PowerNet = sim.pnets[d.pnet]
					frac = n.made > 0 ? clampD(n.used / n.made, 0, 1) : (n.used > 0 ? 1 : 0)
					short = n.short
				}
				let a: Double = 3.4 + frac * 2.6
				white.move(to: mkPoint(cx, T + tp * 0.6))
				white.addLine(to: mkPoint(cx + cos(a) * tp * 0.35, T + tp * 0.6 + sin(a) * tp * 0.35))
				if short { led(true, L + tp * 0.85, T + tp * 0.8, &red) } else { led(true, L + tp * 0.85, T + tp * 0.8, &green) }
			case .powerSwitch:
				let r: CGRect = mkRect(L + tp * 0.375, T + (d.on ? tp * 0.32 : tp * 0.5), tp * 0.25, tp * 0.18)
				if d.on { green.addRect(r) } else { red.addRect(r) }
			case .breaker:
				if d.on { led(true, cx, T + tp * 0.5, &green) } else { led(true, cx, T + tp * 0.5, &red) }
			default:
				break
			}
			// a machine or sensor that wants power and has none
			if (d.role == .machine || d.role == .sensor) && d.enabled && !d.powered && blink {
				let s: Double = tp * 0.18
				red.move(to: mkPoint(cx + s * 0.3, T - s * 2.2))
				red.addLine(to: mkPoint(cx - s * 0.6, T - s * 0.9))
				red.addLine(to: mkPoint(cx + s * 0.2, T - s * 0.9))
				red.addLine(to: mkPoint(cx - s * 0.4, T + s * 0.4))
			}
		}
		let lw: Double = max(1.5, tp * 0.07)
		ctx.stroke(dark, with: .color(Color(hex: 0x1A1A20, alpha: 0.9)), lineWidth: lw)
		ctx.fill(dark, with: .color(Color(hex: 0x1A1A20, alpha: 0.9)))
		ctx.stroke(white, with: .color(Color(hex: 0xE8ECF0)), lineWidth: lw)
		ctx.fill(amber, with: .color(Color(hex: 0xFFC020)))
		ctx.fill(teal, with: .color(Color(hex: 0x50FFF0, alpha: 0.9)))
		ctx.fill(green, with: .color(Color(hex: 0x50F080)))
		ctx.fill(fire, with: .color(Color(hex: 0xFF8A20, alpha: 0.85)))
		ctx.stroke(red, with: .color(Color(hex: 0xFF4030)), lineWidth: lw * 1.3)
		ctx.fill(red, with: .color(Color(hex: 0xFF4030, alpha: 0.8)))
	}
}

// MARK: - Sparkworks panel

/// A device's panel: how it is doing, the line it is on, and its settings
struct PowerPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal

	func pick(_ on: Bool, _ title: String, _ act: @escaping () -> Void) -> some View {
		SmallButton(title: title, color: on ? Color(hex: 0x3A8A7A) : Color(hex: 0x4A4E58), action: act)
	}

	var body: some View {
		let dev: PowerDev? = game.powerDevOpen
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(verbatim: dev?.tile.name.uppercased() ?? "DEVICE").font(.pixel(17)).foregroundColor(Color(hex: 0x80F0E0))
				Spacer()
				SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) {
					game.showPower = false
					game.bumpHUD()
				}
			}
			if let d = dev {
				let lines: [PanelLine] = game.powerPanelLines(d)
				ForEach(0..<lines.count, id: \.self) { i in
					Text(verbatim: lines[i].text).font(.pixel(12, .semibold)).foregroundColor(Color(hex: lines[i].color))
				}
				controls(d)
			}
		}
		.padding(16)
		.background(PixelBox(color: Color(hex: 0x182024)).opacity(0.96))
		.frame(maxWidth: 600)
		.padding(16)
	}

	@ViewBuilder
	func controls(_ d: PowerDev) -> some View {
		let modes: [String] = game.modeNames(d.tile)
		if !modes.isEmpty {
			Text(verbatim: game.modeTitle(d.tile)).font(.pixel(12)).foregroundColor(Color(hex: 0xFFE066))
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
				ForEach(0..<modes.count, id: \.self) { i in
					pick(d.mode == i, modes[i]) { game.setPowerMode(d, i) }
				}
			}
		}
		if let p = game.paramSpec(d) {
			HStack(spacing: 8) {
				Text(verbatim: joinText(p.0, ": ", String(format: p.3 < 1 ? "%.2f" : "%.0f", d.param))).font(.pixel(12)).foregroundColor(Color.white)
				SmallButton(title: "-") { game.stepPowerParam(d, -1) }
				SmallButton(title: "+") { game.stepPowerParam(d, 1) }
			}
		}
		if powerDirectional(d.tile) {
			HStack(spacing: 8) {
				Text(verbatim: joinText("Facing: ", ["right", "down", "left", "up"][clampI(d.dir, 0, 3)])).font(.pixel(12)).foregroundColor(Color.white)
				SmallButton(title: "ROTATE") { game.rotatePower(d) }
			}
		}
		if d.tile == .arcTrap {
			pick(d.flag, d.flag ? "HURTS THE PLAYER TOO" : "CREATURES ONLY") {
				d.flag.toggle()
				game.bumpHUD()
			}
		}
		if d.tile == .autoCrafter {
			let list: [Recipe] = game.crafterRecipes()
			let cur: String = (d.item >= 0 && d.item < RecipeBook.all.count) ? RecipeBook.all[d.item].out.name : "nothing yet"
			Text(verbatim: joinText("Making: ", cur, " (chest behind = ingredients, chest in front = results)")).font(.pixel(12)).foregroundColor(Color(hex: 0xFFE066))
			ScrollView {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6)], alignment: .leading, spacing: 6) {
					ForEach(0..<list.count, id: \.self) { i in
						pick(list[i].id == d.item, joinText(list[i].out.name, list[i].outCount > 1 ? joinText(" x", String(list[i].outCount)) : "")) {
							d.item = list[i].id
							d.work = 0
							game.bumpHUD()
						}
					}
				}
			}
			.frame(maxHeight: 220)
		}
	}
}

// ===== p28_mods =====

// MARK: - Mods: what a player-made mod is made of
//
// A mod is one JSON file in Documents/PixelRealmMods: who made it and the custom blocks, items,
// creatures, shots, recipes, loot tables, ores and structures it adds. Nothing in a mod is code: every
// behaviour is picked from what the game already does, and every number is held to a safe range when
// the mod is read. `ModRuntime` turns the mods a world uses into ordinary game content (tiles, items,
// creatures, recipes), so custom content is mined, fought, crafted, drawn and saved by the same code
// as everything else.

extension KeyedDecodingContainer {
	/// The value under a key, or `d` when the key is missing or holds something unreadable
	func val<T: Decodable>(_ k: Key, _ d: T) -> T {
		return (try? decodeIfPresent(T.self, forKey: k)) ?? d
	}

	/// A list where entries that cannot be read are left out (and counted in `skipped`)
	func list<T: Decodable>(_ k: Key, _ skipped: inout Int) -> [T] {
		guard let raw = try? decodeIfPresent([Lenient<T>].self, forKey: k) else { return [] }
		var out: [T] = []
		for e in raw {
			if let v = e.value { out.append(v) } else { skipped += 1 }
		}
		return out
	}
}

/// One entry of a list that may fail to decode without spoiling the rest of the list
struct Lenient<T: Decodable>: Decodable {
	let value: T?
	init(from decoder: Decoder) throws {
		value = try? T(from: decoder)
	}
}

/// Limits that keep a mod from hurting the game: how much a mod may hold, how many custom creatures
/// may be about at once, how big art and structures may be. Numbers inside content have their own
/// ranges (see `ModRange`), wider when a mod is set to sandbox mode.
enum ModLimits {
	static let maxMods: Int = 12
	/// custom blocks across every mod a world uses (each takes one of the reserved tile numbers)
	static let blockSlots: Int = 64
	static let maxBlocks: Int = 48
	static let maxItems: Int = 120
	static let maxMobs: Int = 40
	static let maxShots: Int = 16
	static let maxRecipes: Int = 240
	static let maxLoot: Int = 40
	static let maxOres: Int = 16
	static let maxStructures: Int = 16
	static let maxStructW: Int = 48
	static let maxStructH: Int = 32
	static let maxMobArt: Int = 32
	static let maxFrames: Int = 4
	/// custom creatures alive at once (spawning stops at this many; test spawning too)
	static let maxActiveMobs: Int = 24
	/// ores and structures one world generates, across all its mods (keeps new chunks quick to make)
	static let maxWorldOres: Int = 32
	static let maxWorldStructures: Int = 32
	/// shots fired by custom creatures and weapons that may be in the air at once
	static let maxShotsLive: Int = 80
	static let maxEffects: Int = 4
	static let maxAttacks: Int = 4
	static let maxDrops: Int = 8
	static let maxLootEntries: Int = 16
	static let maxCost: Int = 6
	/// phases and ways to summon one creature may have
	static let maxPhases: Int = 6
	static let maxSummons: Int = 3
}

/// The range a number may take: normal play and sandbox mode
struct ModRange {
	var lo: Double
	var hi: Double
	var sandboxHi: Double

	func clamp(_ v: Double, _ sandbox: Bool) -> Double {
		if !v.isFinite { return lo }
		return clampD(v, lo, sandbox ? sandboxHi : hi)
	}

	static let hardness: ModRange = ModRange(lo: 0.05, hi: 40, sandboxHi: 200)
	static let mobHP: ModRange = ModRange(lo: 1, hi: 400, sandboxHi: 20000)
	static let bossHP: ModRange = ModRange(lo: 50, hi: 4000, sandboxHi: 20000)
	static let damage: ModRange = ModRange(lo: 0, hi: 60, sandboxHi: 500)
	static let mobSpeed: ModRange = ModRange(lo: 0, hi: 8, sandboxHi: 20)
	static let detect: ModRange = ModRange(lo: 2, hi: 32, sandboxHi: 64)
	static let reach: ModRange = ModRange(lo: 0.5, hi: 6, sandboxHi: 12)
	static let cooldown: ModRange = ModRange(lo: 0.15, hi: 10, sandboxHi: 10)
	static let knock: ModRange = ModRange(lo: 0, hi: 16, sandboxHi: 40)
	static let scale: ModRange = ModRange(lo: 0.5, hi: 2.5, sandboxHi: 4)
	static let shotSpeed: ModRange = ModRange(lo: 4, hi: 60, sandboxHi: 90)
	static let gravity: ModRange = ModRange(lo: 0, hi: 40, sandboxHi: 60)
	static let defense: ModRange = ModRange(lo: 0, hi: 12, sandboxHi: 40)
	static let toolSpeed: ModRange = ModRange(lo: 0.3, hi: 30, sandboxHi: 200)
	static let heal: ModRange = ModRange(lo: 0, hi: 40, sandboxHi: 400)
	static let seconds: ModRange = ModRange(lo: 0, hi: 300, sandboxHi: 1800)
	static let radius: ModRange = ModRange(lo: 0.5, hi: 6, sandboxHi: 12)
	static let jump: ModRange = ModRange(lo: 0, hi: 20, sandboxHi: 30)
}

/// Pixel art stored in a mod: width, height and RGBA bytes, row by row (alpha 0 is see-through)
struct ModPixels: Codable, Equatable {
	var w: Int
	var h: Int
	var rgba: Data
	/// drawn with a dark outline in the game (nil: the usual for what it is: creatures and items yes,
	/// blocks no)
	var outline: Bool? = nil

	init(w: Int, h: Int) {
		self.w = max(1, w)
		self.h = max(1, h)
		self.rgba = Data(count: self.w * self.h * 4)
	}

	init(buf: PixelBuf) {
		self.init(w: buf.w, h: buf.h)
		for y in 0..<h {
			for x in 0..<w { setARGB(x, y, buf.px[y * buf.w + x]) }
		}
	}

	/// Big enough to draw on, small enough to stay cheap, and the bytes match the size (up to 96 for
	/// the game's big creatures, whose sprites can be edited)
	var valid: Bool { return w >= 1 && h >= 1 && w <= ModPixels.maxSide && h <= ModPixels.maxSide && rgba.count == w * h * 4 }

	static let maxSide: Int = 96

	/// The pixel as 0xAARRGGBB with its own opacity (0 outside the picture, or all but invisible)
	func argb(_ x: Int, _ y: Int) -> UInt32 {
		if x < 0 || y < 0 || x >= w || y >= h || !valid { return 0 }
		let i: Int = (y * w + x) * 4
		let a: UInt32 = UInt32(rgba[i + 3])
		if a < 8 { return 0 }
		let r: UInt32 = UInt32(rgba[i])
		let g: UInt32 = UInt32(rgba[i + 1])
		let b: UInt32 = UInt32(rgba[i + 2])
		return (a << 24) | (r << 16) | (g << 8) | b
	}

	/// Sets a pixel, keeping its opacity (pictures saved before pixels could be part see-through only
	/// ever held fully solid or fully clear ones, so they read the same)
	mutating func setARGB(_ x: Int, _ y: Int, _ c: UInt32) {
		if x < 0 || y < 0 || x >= w || y >= h || !valid { return }
		let i: Int = (y * w + x) * 4
		let a: UInt8 = UInt8((c >> 24) & 0xFF)
		rgba[i] = a == 0 ? 0 : UInt8((c >> 16) & 0xFF)
		rgba[i + 1] = a == 0 ? 0 : UInt8((c >> 8) & 0xFF)
		rgba[i + 2] = a == 0 ? 0 : UInt8(c & 0xFF)
		rgba[i + 3] = a
	}

	/// The picture as a game pixel buffer
	func buf() -> PixelBuf {
		var b = PixelBuf(w: w, h: h)
		for y in 0..<h {
			for x in 0..<w { b.px[y * w + x] = argb(x, y) }
		}
		return b
	}

	var isBlank: Bool {
		if !valid { return true }
		var i: Int = 3
		while i < rgba.count {
			if rgba[i] >= 8 { return false }
			i += 4
		}
		return true
	}

	/// The same picture at another size (cropped or padded, anchored to the bottom centre)
	func resized(_ nw: Int, _ nh: Int) -> ModPixels {
		var o = ModPixels(w: nw, h: nh)
		let ox: Int = (nw - w) / 2
		let oy: Int = nh - h
		for y in 0..<h {
			for x in 0..<w { o.setARGB(x + ox, y + oy, argb(x, y)) }
		}
		return o
	}

	/// The picture at another size, its pixels doubled or dropped to fit (nearest pixel)
	func stretched(_ nw: Int, _ nh: Int) -> ModPixels {
		var o = ModPixels(w: nw, h: nh)
		o.outline = outline
		if !valid { return o }
		for y in 0..<o.h {
			for x in 0..<o.w { o.setARGB(x, y, argb(min(w - 1, x * w / o.w), min(h - 1, y * h / o.h))) }
		}
		return o
	}
}

// MARK: blocks

enum ModBlockCategory: Int, Codable, CaseIterable {
	case terrain, building, decorative, storage, interactive, machine, light
	var name: String {
		switch self {
		case .terrain: return "Terrain"
		case .building: return "Building"
		case .decorative: return "Decorative"
		case .storage: return "Storage"
		case .interactive: return "Interactive"
		case .machine: return "Machine"
		case .light: return "Light source"
		}
	}
}

enum ModCollision: Int, Codable, CaseIterable {
	case solid, platform, none
	/// climbed like a ladder; sticky: slows what moves through it; decoration: like a flower (appended)
	case climbable, sticky, decor
	/// a liquid that flows, with the numbers in the block's LIQUID section (appended)
	case liquid
	var name: String {
		switch self {
		case .liquid: return "Liquid"
		case .solid: return "Solid"
		case .platform: return "Platform (stand on top)"
		case .none: return "Pass through"
		case .climbable: return "Climbable"
		case .sticky: return "Sticky"
		case .decor: return "Decoration"
		}
	}
	var help: String {
		switch self {
		case .solid: return "A wall and a floor: nothing passes it."
		case .platform: return "Walk and jump up through it, land on top of it (hold down to drop through)."
		case .none: return "Everything passes through it, as through a tree trunk."
		case .climbable: return "Passed through, and climbed like a ladder: jump or up to climb, down to go down."
		case .sticky: return "Passed through slowly, like a cobweb: walking, jumping and falling all slow down in it."
		case .decor: return "Like a flower or tall grass: passed through, needs ground under it, and a block built there replaces it."
		case .liquid: return "A liquid: it flows down and spreads, things swim and float in it, and it can harm, heal or harden where it meets another liquid."
		}
	}
}

/// What tapping (or touching) a block does. Doors and switches use a second tile number for their
/// other state (open, lit).
enum ModBlockFunction: Int, Codable, CaseIterable {
	case none, storage, station, lamp, door, healer, bounce, trap, sign
	/// furniture (appended): a seat to sit on, a bed to sleep in
	case seat, bed
	var name: String {
		switch self {
		case .none: return "Nothing"
		case .storage: return "Storage chest"
		case .station: return "Crafting station"
		case .lamp: return "Light switch"
		case .door: return "Door"
		case .healer: return "Healing shrine"
		case .bounce: return "Jump pad"
		case .trap: return "Damage trap"
		case .sign: return "Sign"
		case .seat: return "Seat"
		case .bed: return "Bed"
		}
	}
	var help: String {
		switch self {
		case .none: return "An ordinary block."
		case .storage: return "Tap it to store 27 stacks, like a chest."
		case .station: return "Recipes can need it nearby, or it works as a game station."
		case .lamp: return "Tap it to turn its light on and off."
		case .door: return "Tap it to open (walk through) and close."
		case .healer: return "Tap it to heal (rests between uses)."
		case .bounce: return "Throws you up when you land on it."
		case .trap: return "Hurts anything that touches it."
		case .sign: return "Tap it to read its text."
		case .seat: return "Tap it to sit down, like a chair (walk or jump to get up)."
		case .bed: return "Tap it at night to sleep until morning; it becomes where you wake up."
		}
	}
	/// functions that need a second tile number for the other state
	var paired: Bool { return self == .lamp || self == .door }
}

/// What a mod block does when it is built onto a vehicle (cases are only ever appended): nothing
/// special (it is just a block of its weight), or the work of one of the game's vehicle parts, with the
/// block's own picture, its own weight and its own strength
enum ModVehicleRole: Int, Codable, CaseIterable {
	case none, wing, elevator, propeller, jet, rotor, tailRotor, balloon, burner, engine, wheel, track, armor, fuelTank, cockpit, cannon, machineGun
	/// the game part it works as
	var part: PartType? {
		switch self {
		case .none: return nil
		case .wing: return .wing
		case .elevator: return .elevator
		case .propeller: return .airProp
		case .jet: return .jet
		case .rotor: return .rotor
		case .tailRotor: return .tailRotor
		case .balloon: return .envelope
		case .burner: return .burner
		case .engine: return .engine
		case .wheel: return .wheel
		case .track: return .track
		case .armor: return .armor
		case .fuelTank: return .fuelTank
		case .cockpit: return .cockpit
		case .cannon: return .cannon
		case .machineGun: return .autoGun
		}
	}
	var name: String {
		if self == .none { return "Just a block" }
		return part?.name ?? "Just a block"
	}
}

struct ModBlock: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Block"
	var desc: String = ""
	var category: ModBlockCategory = .building
	/// 8 x 8 picture
	var art: ModPixels = ModPixels(w: 8, h: 8)
	/// seconds of mining with bare hands is about hardness x 1.5
	var hardness: Double = 1.0
	var unbreakable: Bool = false
	/// the tool that mines it at full speed (ToolType number)
	var tool: Int = 0
	/// tool tier needed (0: anything can break it)
	var tier: Int = 0
	var collision: ModCollision = .solid
	var transparent: Bool = false
	/// light given off, 0 to 15
	var light: Int = 0
	var dropSelf: Bool = true
	/// what it drops instead of itself (nil with dropSelf off: nothing)
	var drop: Item? = nil
	var dropCount: Int = 1
	/// explosions leave it standing
	var blastProof: Bool = false
	var function: ModBlockFunction = .none
	/// station number (Station) it works as; -1: its own station for this mod's recipes
	var station: Int = -1
	/// heal amount, jump pad strength or trap damage
	var power: Double = 6
	var text: String = ""
	/// on a vehicle: the part it works as, its mass there (0: its block weight), and how strong it is at
	/// that work (lift, thrust, power, toughness: 1 is the game part's own)
	var vehRole: ModVehicleRole = .none
	var vehMass: Double = 0
	var vehPower: Double = 1.0
	/// working as a cannon or machine gun: the mod's own shot it fires (its id; "": the game's), how
	/// fast and how hard (0: the game part's own), and how many a second (0: the part's own)
	var shot: String = ""
	var shotSpeed: Double = 0
	var shotDamage: Double = 0
	var fireRate: Double = 0
	/// as building material: its weight and what it holds up (0: worked out from its hardness), and
	/// whether it falls like sand with nothing under it
	var weight: Double = 0
	var carry: Double = 0
	var falls: Bool = false
	/// what it is like to touch: how well wheels, hulls and feet grip it (1: stone; ice is 0.12) and how
	/// much of a blow it gives back (0: none, 1: all of it)
	var grip: Double = 1.0
	var bounce: Double = 0.0
	/// as a liquid (collision .liquid): density (water 1), thickness (water 1, lava 4), how far a block of
	/// it spreads, harm a second, whether it burns, how see-through it is, the block it hardens into
	/// where it meets another liquid ("" none), whether a thin film dries up, and an effect it gives
	/// whoever is in it (a ModEffectKind number, -1 none) and how strong
	var liqDensity: Double = 1.0
	var liqThick: Double = 1.0
	var liqReach: Int = 7
	var liqHarm: Double = 0
	var liqHot: Bool = false
	var liqOpacity: Double = 0.75
	var liqHardens: String = ""
	var liqDries: Bool = false
	var liqEffect: Int = -1
	var liqEffectAmt: Double = 10
	/// on Sparkworks power lines: what it does, and how strong it is at it
	var powerRole: ModPowerRole = .none
	var powerAmt: Double = 4

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Block")
		desc = c.val(.desc, "")
		category = c.val(.category, .building)
		art = c.val(.art, ModPixels(w: 8, h: 8))
		hardness = c.val(.hardness, 1.0)
		unbreakable = c.val(.unbreakable, false)
		tool = c.val(.tool, 0)
		tier = c.val(.tier, 0)
		collision = c.val(.collision, .solid)
		transparent = c.val(.transparent, false)
		light = c.val(.light, 0)
		dropSelf = c.val(.dropSelf, true)
		drop = c.val(.drop, nil)
		dropCount = c.val(.dropCount, 1)
		blastProof = c.val(.blastProof, false)
		function = c.val(.function, .none)
		station = c.val(.station, -1)
		power = c.val(.power, 6)
		text = c.val(.text, "")
		vehRole = c.val(.vehRole, .none)
		vehMass = c.val(.vehMass, 0)
		vehPower = c.val(.vehPower, 1.0)
		shot = c.val(.shot, "")
		shotSpeed = c.val(.shotSpeed, 0)
		shotDamage = c.val(.shotDamage, 0)
		fireRate = c.val(.fireRate, 0)
		weight = c.val(.weight, 0)
		carry = c.val(.carry, 0)
		falls = c.val(.falls, false)
		grip = c.val(.grip, 1.0)
		liqDensity = c.val(.liqDensity, 1.0)
		liqThick = c.val(.liqThick, 1.0)
		liqReach = c.val(.liqReach, 7)
		liqHarm = c.val(.liqHarm, 0)
		liqHot = c.val(.liqHot, false)
		liqOpacity = c.val(.liqOpacity, 0.75)
		liqHardens = c.val(.liqHardens, "")
		liqDries = c.val(.liqDries, false)
		liqEffect = c.val(.liqEffect, -1)
		liqEffectAmt = c.val(.liqEffectAmt, 10)
		bounce = c.val(.bounce, 0.0)
		powerRole = c.val(.powerRole, .none)
		powerAmt = c.val(.powerAmt, 4)
	}
}

// MARK: items

enum ModItemKind: Int, Codable, CaseIterable {
	case material, food, consumable, tool, melee, bow, gun, thrown, magic, armor, ammo, special
	var name: String {
		switch self {
		case .material: return "Material"
		case .food: return "Food"
		case .consumable: return "Potion / consumable"
		case .tool: return "Tool"
		case .melee: return "Melee weapon"
		case .bow: return "Bow"
		case .gun: return "Gun / crossbow"
		case .thrown: return "Thrown weapon"
		case .magic: return "Projectile weapon"
		case .armor: return "Armor"
		case .ammo: return "Ammunition"
		case .special: return "Special item"
		}
	}
	var help: String {
		switch self {
		case .material: return "A crafting ingredient."
		case .food: return "Eaten from the hotbar: fills hunger and can give effects."
		case .consumable: return "Used up for its effects (healing, speed, strength...)."
		case .tool: return "Mines blocks: pickaxe, axe, shovel or hoe."
		case .melee: return "Swung at foes, aimed with the attack stick."
		case .bow: return "Hold to draw, release to shoot."
		case .gun: return "Fires shots, reloads from ammunition."
		case .thrown: return "Lobs a shot in an arc, further the further you aim."
		case .magic: return "Fires its shot on every use (no ammunition)."
		case .armor: return "Worn for defense (and an effect while worn)."
		case .ammo: return "Used up by bows and guns."
		case .special: return "Gives light when held, or an effect when used."
		}
	}
	var isWeapon: Bool { return self == .melee || self == .bow || self == .gun || self == .thrown || self == .magic }
	var isRanged: Bool { return self == .bow || self == .gun || self == .thrown || self == .magic }
}

/// Effects an item can give, taken from a fixed list (no custom code)
enum ModEffectKind: Int, Codable, CaseIterable {
	case heal, feed, speed, strength, resistance, regen, glow, jump, fireproof, cure
	/// appended (potions): mining speed, water breathing, night vision, luck, slow falling, warmth
	case mining, breathing, nightVision, luck, featherfall, warmth
	var name: String {
		switch self {
		case .mining: return "Mining speed"
		case .breathing: return "Water breathing"
		case .nightVision: return "Night vision"
		case .luck: return "Luck"
		case .featherfall: return "Slow falling"
		case .warmth: return "Warmth (cold)"

		case .heal: return "Restore health"
		case .feed: return "Restore hunger"
		case .speed: return "Speed boost"
		case .strength: return "Strength boost"
		case .resistance: return "Resistance"
		case .regen: return "Regeneration"
		case .glow: return "Glow (light)"
		case .jump: return "Jump boost"
		case .fireproof: return "Fire protection"
		case .cure: return "Cure (fire, cold)"
		}
	}
	/// lasts for a while (the others act at once)
	var timed: Bool {
		switch self {
		case .heal, .feed, .cure: return false
		default: return true
		}
	}
	/// what the amount means, for the editor
	var amountLabel: String {
		switch self {
		case .heal: return "Health"
		case .feed: return "Hunger"
		case .speed, .strength, .jump: return "Extra %"
		case .resistance: return "Damage blocked %"
		case .regen: return "Health per second"
		case .glow: return "Light level"
		case .fireproof, .cure: return "Strength"
		case .mining: return "Extra %"
		case .luck: return "Chance %"
		case .breathing, .nightVision, .featherfall, .warmth: return "Strength"
		}
	}
	var amountRange: ModRange {
		switch self {
		case .heal, .feed: return ModRange.heal
		case .speed, .jump: return ModRange(lo: 0, hi: 60, sandboxHi: 200)
		case .strength: return ModRange(lo: 0, hi: 100, sandboxHi: 400)
		case .resistance: return ModRange(lo: 0, hi: 60, sandboxHi: 90)
		case .regen: return ModRange(lo: 0, hi: 4, sandboxHi: 40)
		case .glow: return ModRange(lo: 1, hi: 15, sandboxHi: 15)
		case .fireproof, .cure: return ModRange(lo: 0, hi: 1, sandboxHi: 1)
		case .mining: return ModRange(lo: 0, hi: 80, sandboxHi: 300)
		case .luck: return ModRange(lo: 0, hi: 30, sandboxHi: 60)
		case .breathing, .nightVision, .featherfall, .warmth: return ModRange(lo: 0, hi: 1, sandboxHi: 1)
		}
	}
}

struct ModEffect: Codable, Equatable {
	var kind: ModEffectKind = .heal
	var amount: Double = 6
	var seconds: Double = 20

	init() {}
	init(_ k: ModEffectKind, _ a: Double, _ s: Double) {
		kind = k
		amount = a
		seconds = s
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		kind = c.val(.kind, .heal)
		amount = c.val(.amount, 6)
		seconds = c.val(.seconds, 20)
	}
}

struct ModItem: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Item"
	var desc: String = ""
	var kind: ModItemKind = .material
	/// 16 x 16 picture; when blank, `baseIcon` (an item of the game) is drawn, tinted
	var icon: ModPixels = ModPixels(w: 16, h: 16)
	var baseIcon: Item? = nil
	var tint: UInt32 = 0xFFFFFF
	var tintAmt: Double = 0
	var stack: Int = 99
	/// 0 common, 1 uncommon, 2 rare, 3 epic, 4 legendary (the colour of its name)
	var rarity: Int = 0
	// food and consumables
	var hunger: Double = 0
	var effects: [ModEffect] = []
	var useTime: Double = 0.6
	// tools
	var toolType: Int = 0
	var toolTier: Int = 3
	var toolSpeed: Double = 4
	// melee (also how a tool swings)
	var style: Int = 0
	var damage: Double = 6
	var cooldown: Double = 0.45
	var reach: Double = 3
	/// half the swing's angle (radians)
	var arc: Double = 1.0
	var knock: Double = 6
	var maxHits: Int = 99
	var heavy: Bool = false
	var daze: Double = 0
	var burn: Double = 0
	var windup: Double = 0
	var combo: Bool = false
	var backstab: Double = 1
	var undeadMult: Double = 1
	var crit: Double = 0.1
	var trail: UInt32 = 0xFFFFFF
	// ranged
	/// a shot of this mod (empty: the game shot `shot`)
	var projectile: String = ""
	var shot: Int = 0
	var speed: Double = 30
	var gravity: Double = 0
	var pierce: Int = 0
	/// shots per use, spread in a fan
	var spread: Int = 1
	var magazine: Int = 6
	var reload: Double = 1.5
	/// what each shot uses up (nil: nothing)
	var ammo: Item? = nil
	var needsPress: Bool = false
	// armor
	var slot: Int = 0
	var defense: Double = 2
	/// the game armour tier it is drawn as
	var look: Int = 4
	var wornEffect: ModEffect? = nil
	// special
	/// light it gives when held (0: none)
	var light: Int = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Item")
		desc = c.val(.desc, "")
		kind = c.val(.kind, .material)
		icon = c.val(.icon, ModPixels(w: 16, h: 16))
		baseIcon = c.val(.baseIcon, nil)
		tint = c.val(.tint, 0xFFFFFF)
		tintAmt = c.val(.tintAmt, 0)
		stack = c.val(.stack, 99)
		rarity = c.val(.rarity, 0)
		hunger = c.val(.hunger, 0)
		effects = c.list(.effects, &skip)
		useTime = c.val(.useTime, 0.6)
		toolType = c.val(.toolType, 0)
		toolTier = c.val(.toolTier, 3)
		toolSpeed = c.val(.toolSpeed, 4)
		style = c.val(.style, 0)
		damage = c.val(.damage, 6)
		cooldown = c.val(.cooldown, 0.45)
		reach = c.val(.reach, 3)
		arc = c.val(.arc, 1.0)
		knock = c.val(.knock, 6)
		maxHits = c.val(.maxHits, 99)
		heavy = c.val(.heavy, false)
		daze = c.val(.daze, 0)
		burn = c.val(.burn, 0)
		windup = c.val(.windup, 0)
		combo = c.val(.combo, false)
		backstab = c.val(.backstab, 1)
		undeadMult = c.val(.undeadMult, 1)
		crit = c.val(.crit, 0.1)
		trail = c.val(.trail, 0xFFFFFF)
		projectile = c.val(.projectile, "")
		shot = c.val(.shot, 0)
		speed = c.val(.speed, 30)
		gravity = c.val(.gravity, 0)
		pierce = c.val(.pierce, 0)
		spread = c.val(.spread, 1)
		magazine = c.val(.magazine, 6)
		reload = c.val(.reload, 1.5)
		ammo = c.val(.ammo, nil)
		needsPress = c.val(.needsPress, false)
		slot = c.val(.slot, 0)
		defense = c.val(.defense, 2)
		look = c.val(.look, 4)
		wornEffect = c.val(.wornEffect, nil)
		light = c.val(.light, 0)
	}
}

// MARK: shots

enum ModShotShape: Int, Codable, CaseIterable {
	case orb, arrow, bolt, shard, rock
	var name: String {
		switch self {
		case .orb: return "Orb"
		case .arrow: return "Arrow"
		case .bolt: return "Bolt"
		case .shard: return "Shard"
		case .rock: return "Rock"
		}
	}
}

/// A projectile of a mod: how it looks, how it flies and what it does when it lands
struct ModProjectile: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Shot"
	var shape: ModShotShape = .orb
	var color: UInt32 = 0x8AF0FF
	var size: Double = 0.3
	var glow: Int = 6
	var gravity: Double = 0
	var pierce: Int = 0
	var life: Double = 2
	/// blast radius when it lands (0: no blast)
	var explode: Double = 0
	var breakBlocks: Bool = false
	/// seconds of fire it sets on what it hits
	var burn: Double = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Shot")
		shape = c.val(.shape, .orb)
		color = c.val(.color, 0x8AF0FF)
		size = c.val(.size, 0.3)
		glow = c.val(.glow, 6)
		gravity = c.val(.gravity, 0)
		pierce = c.val(.pierce, 0)
		life = c.val(.life, 2)
		explode = c.val(.explode, 0)
		breakBlocks = c.val(.breakBlocks, false)
		burn = c.val(.burn, 0)
	}
}

// MARK: creatures

enum ModMobCategory: Int, Codable, CaseIterable {
	case passive, neutral, hostile, boss, flying, water
	var name: String {
		switch self {
		case .passive: return "Passive animal"
		case .neutral: return "Neutral creature"
		case .hostile: return "Hostile enemy"
		case .boss: return "Boss"
		case .flying: return "Flying creature"
		case .water: return "Water creature"
		}
	}
	var help: String {
		switch self {
		case .passive: return "Never attacks; runs when hurt."
		case .neutral: return "Leaves you alone until you hit it."
		case .hostile: return "Hunts the player."
		case .boss: return "A big fight with a health bar at the top of the screen."
		case .flying: return "Flies freely."
		case .water: return "Lives in water."
		}
	}
}

enum ModAttackKind: Int, Codable, CaseIterable {
	case melee, charge, ranged, area, jump, stomp, multiHit
	var name: String {
		switch self {
		case .melee: return "Melee"
		case .charge: return "Charge"
		case .ranged: return "Ranged shot"
		case .area: return "Area burst"
		case .jump: return "Jump attack"
		case .stomp: return "Stomp"
		case .multiHit: return "Multi-hit"
		}
	}
	var help: String {
		switch self {
		case .melee: return "A blow at whatever is in front of it."
		case .charge: return "Rushes forward, hurting what it runs into."
		case .ranged: return "Fires shots at the target."
		case .area: return "Hurts everything around it."
		case .jump: return "Leaps at the target and lands on it."
		case .stomp: return "Slams the ground: a shockwave along it."
		case .multiHit: return "A flurry of quick blows."
		}
	}
}

enum ModAttackAim: Int, Codable, CaseIterable {
	case forward, atTarget, around, down
	var name: String {
		switch self {
		case .forward: return "Forward"
		case .atTarget: return "At the target"
		case .around: return "All around"
		case .down: return "Downward"
		}
	}
}

struct ModAttack: Codable, Equatable {
	var kind: ModAttackKind = .melee
	var damage: Double = 6
	var range: Double = 1.6
	var cooldown: Double = 1.2
	var aim: ModAttackAim = .forward
	/// a shot of this mod (empty: the game shot `shot`)
	var projectile: String = ""
	var shot: Int = 2
	var speed: Double = 16
	var knock: Double = 6
	var radius: Double = 2.5
	var hits: Int = 3
	/// the warning before the blow lands
	var windup: Double = 0.3

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		kind = c.val(.kind, .melee)
		damage = c.val(.damage, 6)
		range = c.val(.range, 1.6)
		cooldown = c.val(.cooldown, 1.2)
		aim = c.val(.aim, .forward)
		projectile = c.val(.projectile, "")
		shot = c.val(.shot, 2)
		speed = c.val(.speed, 16)
		knock = c.val(.knock, 6)
		radius = c.val(.radius, 2.5)
		hits = c.val(.hits, 3)
		windup = c.val(.windup, 0.3)
	}
}

/// Behaviour switches; the game's creature AI (senses, chase, search, return) does the rest
struct ModBehavior: Codable, Equatable {
	var wander: Bool = true
	var standStill: Bool = false
	var patrol: Bool = false
	var patrolRange: Double = 8
	var followPlayer: Bool = false
	var runAway: Bool = false
	var chase: Bool = false
	var attackPlayer: Bool = false
	var attackMobs: Bool = false
	var retaliate: Bool = true
	var defendArea: Bool = false
	var defendRadius: Double = 10
	/// stays beside the nearest creature of this kind ("mod:id", or a game creature's name)
	var guardKey: String = ""
	var fly: Bool = false
	var swim: Bool = false
	var stayInBiome: Bool = false
	var burnsInSun: Bool = false

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		wander = c.val(.wander, true)
		standStill = c.val(.standStill, false)
		patrol = c.val(.patrol, false)
		patrolRange = c.val(.patrolRange, 8)
		followPlayer = c.val(.followPlayer, false)
		runAway = c.val(.runAway, false)
		chase = c.val(.chase, false)
		attackPlayer = c.val(.attackPlayer, false)
		attackMobs = c.val(.attackMobs, false)
		retaliate = c.val(.retaliate, true)
		defendArea = c.val(.defendArea, false)
		defendRadius = c.val(.defendRadius, 10)
		guardKey = c.val(.guardKey, "")
		fly = c.val(.fly, false)
		swim = c.val(.swim, false)
		stayInBiome = c.val(.stayInBiome, false)
		burnsInSun = c.val(.burnsInSun, false)
	}
}

enum ModSpawnPlace: Int, Codable, CaseIterable {
	case surface, cave, ocean, umbral, sky
	var name: String {
		switch self {
		case .surface: return "Surface"
		case .cave: return "Caves"
		case .ocean: return "Ocean"
		case .umbral: return "Umbral Realm"
		case .sky: return "In the sky"
		}
	}
}

struct ModSpawn: Codable, Equatable {
	var enabled: Bool = true
	var place: ModSpawnPlace = .surface
	/// 0 any time, 1 by day, 2 at night
	var when: Int = 0
	/// Biome numbers (empty: every biome)
	var biomes: [Int] = []
	var minY: Int = 0
	var maxY: Int = 560
	/// how common it is next to the game's creatures (the zombie is 7)
	var weight: Double = 3
	var group: Int = 1
	var maxNearby: Int = 4

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		enabled = c.val(.enabled, true)
		place = c.val(.place, .surface)
		when = c.val(.when, 0)
		biomes = c.val(.biomes, [])
		minY = c.val(.minY, 0)
		maxY = c.val(.maxY, 560)
		weight = c.val(.weight, 3)
		group = c.val(.group, 1)
		maxNearby = c.val(.maxNearby, 4)
	}
}

struct ModDrop: Codable, Equatable {
	var item: Item = .mat(.string)
	var min: Int = 1
	var max: Int = 1
	var chance: Double = 0.5

	init() {}
	init(_ it: Item, _ lo: Int, _ hi: Int, _ p: Double) {
		item = it
		min = lo
		max = hi
		chance = p
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		item = c.val(.item, .mat(.string))
		min = c.val(.min, 1)
		max = c.val(.max, 1)
		chance = c.val(.chance, 0.5)
	}
}

struct ModMob: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Creature"
	var desc: String = ""
	var category: ModMobCategory = .hostile
	/// the game creature its body (and hit box) starts from
	var base: Int = MobKind.zombie.rawValue
	/// draw `frames` instead of the recoloured base body
	var customArt: Bool = false
	/// up to 4 frames: standing, two walking, attacking
	var frames: [ModPixels] = []
	/// colour changes for the base body: hue turn (degrees), saturation and brightness, and a tint
	var hue: Double = 0
	var saturation: Double = 1
	var brightness: Double = 1
	var tint: UInt32 = 0xFFFFFF
	var tintAmt: Double = 0
	var scale: Double = 1
	var hp: Double = 30
	var damage: Double = 6
	var speed: Double = 2
	var detect: Double = 14
	var jump: Double = 12
	/// share of incoming damage shrugged off (0 ... 0.9)
	var defense: Double = 0
	var knockResist: Double = 0
	var fireproof: Bool = false
	var behavior: ModBehavior = ModBehavior()
	var attacks: [ModAttack] = [ModAttack()]
	var spawn: ModSpawn = ModSpawn()
	var drops: [ModDrop] = []
	/// a loot table of this mod, rolled as well as `drops`
	var loot: String = ""
	var glow: Int = 0
	/// the stages of its fight, in order (see ModPhase)
	var phases: [ModPhase] = []
	/// ways a player can call it into the world (see ModSummon)
	var summons: [ModSummon] = []

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Creature")
		desc = c.val(.desc, "")
		category = c.val(.category, .hostile)
		base = c.val(.base, MobKind.zombie.rawValue)
		customArt = c.val(.customArt, false)
		frames = c.list(.frames, &skip)
		hue = c.val(.hue, 0)
		saturation = c.val(.saturation, 1)
		brightness = c.val(.brightness, 1)
		tint = c.val(.tint, 0xFFFFFF)
		tintAmt = c.val(.tintAmt, 0)
		scale = c.val(.scale, 1)
		hp = c.val(.hp, 30)
		damage = c.val(.damage, 6)
		speed = c.val(.speed, 2)
		detect = c.val(.detect, 14)
		jump = c.val(.jump, 12)
		defense = c.val(.defense, 0)
		knockResist = c.val(.knockResist, 0)
		fireproof = c.val(.fireproof, false)
		behavior = c.val(.behavior, ModBehavior())
		attacks = c.list(.attacks, &skip)
		spawn = c.val(.spawn, ModSpawn())
		drops = c.list(.drops, &skip)
		loot = c.val(.loot, "")
		glow = c.val(.glow, 0)
		phases = c.list(.phases, &skip)
		summons = c.list(.summons, &skip)
	}
}

// MARK: recipes, loot, ores, structures

struct ModCost: Codable, Equatable {
	var item: Item = .block(.planks)
	var n: Int = 1

	init() {}
	init(_ it: Item, _ k: Int) {
		item = it
		n = k
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		item = c.val(.item, .block(.planks))
		n = c.val(.n, 1)
	}
}

struct ModRecipe: Codable, Identifiable, Equatable {
	var id: String = ""
	var out: Item = .block(.planks)
	var count: Int = 1
	var cost: [ModCost] = []
	/// Station number; -1: near a block of this mod (`stationBlock`)
	var station: Int = 0
	var stationBlock: String = ""
	/// crafting tab (RecipeCat number)
	var cat: Int = RecipeCat.mods.rawValue

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		out = c.val(.out, .block(.planks))
		count = c.val(.count, 1)
		cost = c.list(.cost, &skip)
		station = c.val(.station, 0)
		stationBlock = c.val(.stationBlock, "")
		cat = c.val(.cat, RecipeCat.mods.rawValue)
	}
}

struct ModLootEntry: Codable, Equatable {
	var item: Item = .mat(.coal)
	var min: Int = 1
	var max: Int = 1
	/// 0 common, 1 uncommon, 2 rare, 3 very rare
	var rarity: Int = 0
	/// a weight of its own instead of the rarity's (0: use the rarity)
	var weight: Double = 0

	init() {}
	init(_ it: Item, _ lo: Int, _ hi: Int, _ r: Int) {
		item = it
		min = lo
		max = hi
		rarity = r
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		item = c.val(.item, .mat(.coal))
		min = c.val(.min, 1)
		max = c.val(.max, 1)
		rarity = c.val(.rarity, 0)
		weight = c.val(.weight, 0)
	}

	static let rarityNames: [String] = ["Common", "Uncommon", "Rare", "Very rare"]
	static let rarityWeights: [Double] = [60, 25, 10, 3]
	static let rarityColors: [UInt32] = [0xE8E8E8, 0x6AD86A, 0x5AA8FF, 0xC070FF]

	var effectiveWeight: Double {
		if weight > 0 { return weight }
		return ModLootEntry.rarityWeights[clampI(rarity, 0, 3)]
	}
}

/// A weighted loot table: each roll picks one entry (or nothing) by weight
struct ModLootTable: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Loot Table"
	var rolls: Int = 2
	/// weight of rolling nothing
	var nothing: Double = 0
	var entries: [ModLootEntry] = []
	/// chance (0 ... 1) that a chest anywhere in the world also gets a roll of this table
	var chestChance: Double = 0

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		id = c.val(.id, "")
		name = c.val(.name, "Loot")
		rolls = c.val(.rolls, 2)
		nothing = c.val(.nothing, 0)
		entries = c.list(.entries, &skip)
		chestChance = c.val(.chestChance, 0)
	}

	var totalWeight: Double {
		var t: Double = max(0, nothing)
		for e in entries { t += max(0, e.effectiveWeight) }
		return t
	}

	/// Chance (0...1) that one roll gives entry i
	func chance(_ i: Int) -> Double {
		let t: Double = totalWeight
		if t <= 0 || i < 0 || i >= entries.count { return 0 }
		return max(0, entries[i].effectiveWeight) / t
	}
}

struct ModOre: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Ore"
	/// a block of this mod
	var block: String = ""
	/// 0 overworld, 1 Umbral Realm
	var dim: Int = 0
	/// rows from the top of the world (the sea is at 120, the bottom at 559)
	var minY: Int = 150
	var maxY: Int = 330
	/// veins in an average 16-wide stretch of ground
	var veins: Double = 1.5
	/// blocks in a vein
	var size: Int = 6
	/// 0 any rock, 1 stone, 2 slate and deep rock, 3 dirt and sand, 4 any natural ground
	var host: Int = 0
	/// where in the ground: 0 inside the rock, 1 on cave walls, 2 near the surface, 3 under water
	var place: Int = 0
	/// biomes it forms under (empty: all)
	var biomes: [Int] = []
	/// the chance a chunk (16 blocks of width) has any of it at all
	var rarity: Double = 1
	/// 0 lumps, 1 streaks, 2 scattered blocks
	var shape: Int = 0
	/// another ore it forms next to ("tile:<n>" or a block key; empty: anywhere)
	var near: String = ""
	/// the exact blocks it may replace (empty: the host choice)
	var hosts: [String] = []
	/// one of this mod's dimensions (its id) instead of `dim` (empty: `dim` decides)
	var dimKey: String = ""

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Ore")
		block = c.val(.block, "")
		dim = c.val(.dim, 0)
		minY = c.val(.minY, 150)
		maxY = c.val(.maxY, 330)
		veins = c.val(.veins, 1.5)
		size = c.val(.size, 6)
		host = c.val(.host, 0)
		place = c.val(.place, 0)
		biomes = c.val(.biomes, [])
		rarity = c.val(.rarity, 1)
		shape = c.val(.shape, 0)
		near = c.val(.near, "")
		hosts = c.val(.hosts, [])
		dimKey = c.val(.dimKey, "")
	}

	static let hostNames: [String] = ["Any rock", "Stone", "Slate and deep rock", "Dirt and sand", "Any natural ground"]
}

enum ModPlacement: Int, Codable, CaseIterable {
	case surface, underground, sky
	var name: String {
		switch self {
		case .surface: return "On the surface"
		case .underground: return "Underground"
		case .sky: return "Floating in the sky"
		}
	}
}

/// A structure captured from the world: its cells, where it may appear and how often
struct ModStructure: Codable, Identifiable, Equatable {
	var id: String = ""
	var name: String = "New Structure"
	var w: Int = 0
	var h: Int = 0
	/// row by row: -1 leaves the ground as it is, 0...255 a game tile, 1000 + k the custom block palette[k]
	var cells: [Int] = []
	/// custom blocks it uses ("mod:block")
	var palette: [String] = []
	var placement: ModPlacement = .surface
	var minY: Int = 150
	var maxY: Int = 400
	var biomes: [Int] = []
	/// chance that a possible site holds one
	var chance: Double = 0.35
	/// blocks between possible sites
	var spacing: Int = 300
	var dim: Int = 0
	/// one of this mod's dimensions (its id) instead of `dim` (empty: `dim` decides)
	var dimKey: String = ""
	/// loot table of this mod for chests inside
	var loot: String = ""

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = c.val(.id, "")
		name = c.val(.name, "Structure")
		w = c.val(.w, 0)
		h = c.val(.h, 0)
		cells = c.val(.cells, [])
		palette = c.val(.palette, [])
		placement = c.val(.placement, .surface)
		minY = c.val(.minY, 150)
		maxY = c.val(.maxY, 400)
		biomes = c.val(.biomes, [])
		chance = c.val(.chance, 0.35)
		spacing = c.val(.spacing, 300)
		dim = c.val(.dim, 0)
		loot = c.val(.loot, "")
		dimKey = c.val(.dimKey, "")
	}

	func cell(_ x: Int, _ y: Int) -> Int {
		if x < 0 || y < 0 || x >= w || y >= h { return -1 }
		let i: Int = y * w + x
		return i < cells.count ? cells[i] : -1
	}
}

// MARK: the mod

struct ModPack: Codable, Identifiable, Equatable {
	static let currentFormat: Int = 1
	var format: Int = ModPack.currentFormat
	var id: String = ""
	var name: String = "My Mod"
	var desc: String = ""
	var author: String = ""
	var version: String = "1.0"
	var created: Double = 0
	var edited: Double = 0
	/// sandbox mode: wider limits on the numbers inside
	var sandbox: Bool = false
	var blocks: [ModBlock] = []
	var items: [ModItem] = []
	var mobs: [ModMob] = []
	var projectiles: [ModProjectile] = []
	var recipes: [ModRecipe] = []
	var loot: [ModLootTable] = []
	var ores: [ModOre] = []
	var structures: [ModStructure] = []
	/// the folder the mod is filed under in the Mod Creator (empty: none)
	var folder: String = ""
	/// other mods this one needs (their ids; those whose content it uses are found as well)
	var requires: [String] = []
	/// content switched off for now (by id): kept with the mod, left out of worlds
	var off: [String] = []
	/// changes to the game's own blocks, items and creatures
	var overrides: [ModOverride] = []
	/// infusions of this mod (each has a compound: an item under the same key)
	var infusions: [ModInfusion] = []
	/// dimensions of this mod
	var dims: [ModDimension] = []
	/// Logic Studio scripts and the variables they keep (optional)
	var scripts: [ModScript] = []
	var variables: [String] = []
	/// the Overworld's sun and moon as this mod draws them (nil: the game's)
	var skySun: ModSkyBody? = nil
	var skyMoon: ModSkyBody? = nil
	/// tree designs for its dimensions' regions
	var trees: [ModTree] = []
	/// suit materials, suit parts and whole suit designs
	var suitMats: [ModSuitMat] = []
	var suitParts: [ModSuitPart] = []
	var suitDesigns: [ModSuitDesign] = []
	/// rules of the game in the worlds it is in, by rule id (GameRule; a rule left out is the game's own)
	var rules: [String: Double] = [:]
	/// what a new world (not in creative) starts with in the bag
	var startItems: [ModCost] = []
	/// the Overworld's weather as this mod has it (nil: the game's)
	var weather: ModWeather? = nil
	/// whole vehicles, each also an item that builds it
	var vehicles: [ModVehicle] = []
	/// how the game's screens look (nil: the game's own)
	var theme: ModTheme? = nil
	/// entries left out because they could not be read (not saved)
	var skipped: Int = 0

	enum CodingKeys: String, CodingKey {
		case format, id, name, desc, author, version, created, edited, sandbox
		case blocks, items, mobs, projectiles, recipes, loot, ores, structures
		case folder, requires, off, overrides, infusions, dims, scripts, variables
		case skySun, skyMoon, trees
		case suitMats, suitParts, suitDesigns
		case rules, startItems, weather, vehicles, theme
	}

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		format = c.val(.format, ModPack.currentFormat)
		id = c.val(.id, "")
		name = c.val(.name, "Mod")
		desc = c.val(.desc, "")
		author = c.val(.author, "")
		version = c.val(.version, "1.0")
		created = c.val(.created, 0)
		edited = c.val(.edited, 0)
		sandbox = c.val(.sandbox, false)
		blocks = c.list(.blocks, &skip)
		items = c.list(.items, &skip)
		mobs = c.list(.mobs, &skip)
		projectiles = c.list(.projectiles, &skip)
		recipes = c.list(.recipes, &skip)
		loot = c.list(.loot, &skip)
		ores = c.list(.ores, &skip)
		structures = c.list(.structures, &skip)
		folder = c.val(.folder, "")
		requires = c.val(.requires, [])
		off = c.val(.off, [])
		overrides = c.list(.overrides, &skip)
		infusions = c.list(.infusions, &skip)
		dims = c.list(.dims, &skip)
		scripts = c.list(.scripts, &skip)
		variables = c.val(.variables, [])
		skySun = c.val(.skySun, nil)
		skyMoon = c.val(.skyMoon, nil)
		trees = c.list(.trees, &skip)
		suitMats = c.list(.suitMats, &skip)
		suitParts = c.list(.suitParts, &skip)
		suitDesigns = c.list(.suitDesigns, &skip)
		rules = c.val(.rules, [:])
		startItems = c.list(.startItems, &skip)
		weather = c.val(.weather, nil)
		vehicles = c.list(.vehicles, &skip)
		theme = c.val(.theme, nil)
		skipped = skip
	}

	/// The key other content uses for something of this mod
	func key(_ contentID: String) -> String { return id + ":" + contentID }

	var contentCount: Int {
		let counts: [Int] = [blocks.count, items.count, mobs.count, projectiles.count, recipes.count, loot.count, ores.count, structures.count, overrides.count, infusions.count, dims.count, scripts.count, trees.count, suitMats.count, suitParts.count, suitDesigns.count, vehicles.count, rules.isEmpty && startItems.isEmpty ? 0 : 1, weather == nil ? 0 : 1, theme == nil ? 0 : 1]
		var n: Int = 0
		for c in counts { n += c }
		return n
	}

	/// "3 creatures, 2 weapons, 5 blocks..." for the mod list
	var summary: String {
		var parts: [String] = []
		func add(_ n: Int, _ one: String, _ many: String) {
			if n > 0 { parts.append(String(n) + " " + (n == 1 ? one : many)) }
		}
		let weapons: Int = items.filter { $0.kind.isWeapon }.count
		add(blocks.count, "block", "blocks")
		add(items.count - weapons, "item", "items")
		add(weapons, "weapon", "weapons")
		add(mobs.count, "creature", "creatures")
		add(recipes.count, "recipe", "recipes")
		add(ores.count, "ore", "ores")
		add(structures.count, "structure", "structures")
		add(loot.count, "loot table", "loot tables")
		add(projectiles.count, "shot", "shots")
		add(overrides.count, "change to the game", "changes to the game")
		add(infusions.count, "infusion", "infusions")
		add(dims.count, "dimension", "dimensions")
		add(scripts.count, "script", "scripts")
		return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
	}

	/// A content id not used yet ("b1", "b2"...)
	func freshID(_ prefix: String) -> String {
		var used: Set<String> = []
		for b in blocks { used.insert(b.id) }
		for i in items { used.insert(i.id) }
		for m in mobs { used.insert(m.id) }
		for p in projectiles { used.insert(p.id) }
		for r in recipes { used.insert(r.id) }
		for l in loot { used.insert(l.id) }
		for o in ores { used.insert(o.id) }
		for s in structures { used.insert(s.id) }
		for o in overrides { used.insert(o.id) }
		for t in trees { used.insert(t.id) }
		for m in suitMats { used.insert(m.id) }
		for sp in suitParts { used.insert(sp.id) }
		for sd in suitDesigns { used.insert(sd.id) }
		for v in vehicles { used.insert(v.id) }
		for f in infusions { used.insert(f.id) }
		for d in dims { used.insert(d.id) }
		for sc in scripts { used.insert(sc.id) }
		var n: Int = 1
		while used.contains(prefix + String(n)) { n += 1 }
		return prefix + String(n)
	}
}

/// A new random mod id (lowercase letters and digits)
func newModID() -> String {
	let chars: [Character] = Array("abcdefghijkmnpqrstuvwxyz23456789")
	var s: String = "m"
	for _ in 0..<9 { s.append(chars[Int.random(in: 0..<chars.count)]) }
	return s
}

/// The mod and content parts of a key ("m2k4x:b3" -> ("m2k4x", "b3"))
func splitModKey(_ key: String) -> (String, String) {
	guard let i = key.firstIndex(of: ":") else { return ("", key) }
	let a: String = String(key[key.startIndex..<i])
	let b: String = String(key[key.index(after: i)...])
	return (a, b)
}

// MARK: - Mods on disk

/// Which mods are switched on for new worlds, and the order they load in (later mods win when two
/// change the same thing)
struct ModIndex: Codable {
	var order: [String] = []
	var enabled: [String] = []

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		order = c.val(.order, [])
		enabled = c.val(.enabled, [])
	}
}

/// A mod file: the mod, or why it could not be read
struct ModEntry: Identifiable {
	var id: String
	var pack: ModPack?
	var error: String
	var enabled: Bool
}

/// A mod packed for sharing: a header the importer checks, the mod, and a checksum of its content
struct ModPackage: Codable {
	var kind: String = "PixelRealmMod"
	var format: Int = ModPack.currentFormat
	var mod: ModPack
	var check: Int = 0
}

/// A cheap, stable checksum (FNV-1a) of some bytes
func modChecksum(_ d: Data) -> Int {
	var h: UInt64 = 0xcbf29ce484222325
	for b in d {
		h ^= UInt64(b)
		h = h &* 0x100000001b3
	}
	return Int(truncatingIfNeeded: h & 0x7FFF_FFFF_FFFF)
}

enum ModStore {
	/// tests point this at a scratch folder
	static var overrideDir: URL? = nil

	static var dir: URL {
		let fm = FileManager.default
		if let o = overrideDir {
			try? fm.createDirectory(at: o, withIntermediateDirectories: true)
			return o
		}
		if let d = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
			let u = d.appendingPathComponent("PixelRealmMods", isDirectory: true)
			try? fm.createDirectory(at: u, withIntermediateDirectories: true)
			return u
		}
		return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("PixelRealmMods", isDirectory: true)
	}

	/// shared mod packages are written here (and read from here to import)
	static var packageDir: URL {
		let u = dir.appendingPathComponent("Packages", isDirectory: true)
		try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
		return u
	}

	static func url(_ id: String) -> URL { return dir.appendingPathComponent(id + ".json") }
	static var indexURL: URL { return dir.appendingPathComponent("index.json") }

	static func loadIndex() -> ModIndex {
		guard let d = try? Data(contentsOf: indexURL), let ix = try? JSONDecoder().decode(ModIndex.self, from: d) else { return ModIndex() }
		return ix
	}

	static func saveIndex(_ ix: ModIndex) {
		if let d = try? JSONEncoder().encode(ix) { try? d.write(to: indexURL, options: .atomic) }
	}

	/// Ids of every mod file in the folder
	static func fileIDs() -> [String] {
		let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
		var out: [String] = []
		for n in names where n.hasSuffix(".json") && n != "index.json" {
			out.append(String(n.dropLast(5)))
		}
		return out.sorted()
	}

	static func read(_ id: String) -> ModEntry {
		let on: Bool = loadIndex().enabled.contains(id)
		guard let d = try? Data(contentsOf: url(id)) else {
			return ModEntry(id: id, pack: nil, error: "The file could not be opened.", enabled: on)
		}
		do {
			var p: ModPack = try JSONDecoder().decode(ModPack.self, from: d)
			if p.id.isEmpty { p.id = id }
			if p.id != id {
				// the file name is the mod's identity; a mismatch (a copied file) takes the file's name
				p.id = id
			}
			return ModEntry(id: id, pack: p, error: "", enabled: on)
		} catch {
			return ModEntry(id: id, pack: nil, error: "This file is not a readable mod (it may be damaged).", enabled: on)
		}
	}

	static func pack(_ id: String) -> ModPack? { return read(id).pack }

	/// Every mod, in load order (mods not in the order yet come last, by name)
	static func entries() -> [ModEntry] {
		let ix: ModIndex = loadIndex()
		let ids: [String] = fileIDs()
		var out: [ModEntry] = []
		var seen: Set<String> = []
		for id in ix.order where ids.contains(id) && !seen.contains(id) {
			out.append(read(id))
			seen.insert(id)
		}
		var rest: [ModEntry] = []
		for id in ids where !seen.contains(id) { rest.append(read(id)) }
		rest.sort { ($0.pack?.name ?? $0.id) < ($1.pack?.name ?? $1.id) }
		out.append(contentsOf: rest)
		return out
	}

	@discardableResult
	static func save(_ p0: ModPack) -> Bool {
		var p: ModPack = p0
		if p.id.isEmpty { p.id = newModID() }
		let now: Double = Date().timeIntervalSince1970
		if p.created == 0 { p.created = now }
		p.edited = now
		let enc = JSONEncoder()
		guard let d = try? enc.encode(p) else { return false }
		do {
			try d.write(to: url(p.id), options: .atomic)
		} catch {
			return false
		}
		var ix: ModIndex = loadIndex()
		if !ix.order.contains(p.id) {
			ix.order.append(p.id)
			saveIndex(ix)
		}
		return true
	}

	static func delete(_ id: String) {
		try? FileManager.default.removeItem(at: url(id))
		var ix: ModIndex = loadIndex()
		ix.order.removeAll { $0 == id }
		ix.enabled.removeAll { $0 == id }
		saveIndex(ix)
	}

	/// A copy with a new identity (its content keeps the same ids, under the new mod)
	static func duplicate(_ p: ModPack) -> ModPack? {
		var c: ModPack = p
		c.id = newModID()
		c.name = p.name + " (copy)"
		c.created = 0
		// keys inside the copy that pointed at the original now point at the copy
		c = rekey(c, from: p.id, to: c.id)
		return save(c) ? pack(c.id) : nil
	}

	static func isEnabled(_ id: String) -> Bool { return loadIndex().enabled.contains(id) }

	static func setEnabled(_ id: String, _ on: Bool) {
		var ix: ModIndex = loadIndex()
		ix.enabled.removeAll { $0 == id }
		if on { ix.enabled.append(id) }
		if !ix.order.contains(id) { ix.order.append(id) }
		saveIndex(ix)
	}

	/// Moves a mod earlier (-1) or later (+1) in the load order
	static func move(_ id: String, by delta: Int) {
		var ix: ModIndex = loadIndex()
		var order: [String] = entries().map { $0.id }
		guard let i = order.firstIndex(of: id) else { return }
		let j: Int = clampI(i + delta, 0, order.count - 1)
		if i == j { return }
		order.remove(at: i)
		order.insert(id, at: j)
		ix.order = order
		saveIndex(ix)
	}

	/// The mods switched on for new worlds, readable ones only, in load order
	static func enabledPacks() -> [ModPack] {
		var out: [ModPack] = []
		for e in entries() where e.enabled {
			if let p = e.pack { out.append(p) }
			if out.count >= ModLimits.maxMods { break }
		}
		return out
	}

	// MARK: sharing (local files only)

	/// Writes the mod as a package file and returns where it went
	static func exportPackage(_ p: ModPack) -> URL? {
		guard let body = try? JSONEncoder().encode(p) else { return nil }
		let pkg = ModPackage(mod: p, check: modChecksum(body))
		guard let d = try? JSONEncoder().encode(pkg) else { return nil }
		var safe: String = ""
		for ch in p.name where ch.isLetter || ch.isNumber { safe.append(ch) }
		if safe.isEmpty { safe = "Mod" }
		let u: URL = packageDir.appendingPathComponent(safe + "-" + p.version + ".prmod")
		do {
			try d.write(to: u, options: .atomic)
			return u
		} catch {
			return nil
		}
	}

	/// Package files waiting in the packages folder
	static func packageFiles() -> [URL] {
		let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: packageDir.path)) ?? []
		return names.filter { $0.hasSuffix(".prmod") }.sorted().map { packageDir.appendingPathComponent($0) }
	}

	/// Reads a package, checks it and installs the mod (as a copy when the id is already used).
	/// Returns the installed mod, or why it was refused.
	static func importPackage(_ data: Data) -> (ModPack?, String) {
		guard let pkg = try? JSONDecoder().decode(ModPackage.self, from: data) else {
			return (nil, "That file is not a Pixel Realm mod package.")
		}
		if pkg.kind != "PixelRealmMod" { return (nil, "That file is not a Pixel Realm mod package.") }
		if pkg.format > ModPack.currentFormat { return (nil, "This mod was made with a newer version of the game.") }
		var p: ModPack = pkg.mod
		let report: ModReport = ModValidator.check(&p, known: ModCatalog.installed().keys)
		if report.fatal { return (nil, "The mod is too damaged to use: " + (report.issues.first?.text ?? "")) }
		let oldID: String = p.id
		if p.id.isEmpty || !p.id.allSatisfy({ $0.isLetter || $0.isNumber }) || FileManager.default.fileExists(atPath: url(p.id).path) {
			p.id = newModID()
			p = rekey(p, from: oldID, to: p.id)
			if FileManager.default.fileExists(atPath: url(oldID).path) { p.name += " (imported)" }
		}
		if !save(p) { return (nil, "The mod could not be saved.") }
		return (pack(p.id), "Installed " + p.name + ".")
	}

	/// Points every key of mod `from` inside the mod at mod `to`
	static func rekey(_ p0: ModPack, from: String, to: String) -> ModPack {
		if from.isEmpty || from == to { return p0 }
		var p: ModPack = p0
		func fix(_ it: Item) -> Item {
			if case .custom(let k) = it {
				let s: (String, String) = splitModKey(k)
				if s.0 == from { return .custom(to + ":" + s.1) }
			}
			return it
		}
		func fixKey(_ k: String) -> String {
			let s: (String, String) = splitModKey(k)
			return s.0 == from ? to + ":" + s.1 : k
		}
		for i in p.blocks.indices { if let d = p.blocks[i].drop { p.blocks[i].drop = fix(d) } }
		for i in p.items.indices {
			if let a = p.items[i].ammo { p.items[i].ammo = fix(a) }
			if let b = p.items[i].baseIcon { p.items[i].baseIcon = fix(b) }
		}
		for i in p.mobs.indices {
			for k in p.mobs[i].drops.indices { p.mobs[i].drops[k].item = fix(p.mobs[i].drops[k].item) }
			p.mobs[i].behavior.guardKey = fixKey(p.mobs[i].behavior.guardKey)
		}
		for i in p.recipes.indices {
			p.recipes[i].out = fix(p.recipes[i].out)
			for k in p.recipes[i].cost.indices { p.recipes[i].cost[k].item = fix(p.recipes[i].cost[k].item) }
		}
		for i in p.loot.indices {
			for k in p.loot[i].entries.indices { p.loot[i].entries[k].item = fix(p.loot[i].entries[k].item) }
		}
		for i in p.structures.indices { p.structures[i].palette = p.structures[i].palette.map { fixKey($0) } }
		for i in p.infusions.indices { p.infusions[i].items = p.infusions[i].items.map { fix($0) } }
		func fixRef(_ k: String) -> String { return k.isEmpty || k == "air" || k.hasPrefix("tile:") ? k : fixKey(k) }
		for i in p.mobs.indices {
			for k in p.mobs[i].phases.indices { p.mobs[i].phases[k].helper = fixRef(p.mobs[i].phases[k].helper) }
			for k in p.mobs[i].summons.indices {
				if let it = p.mobs[i].summons[k].item { p.mobs[i].summons[k].item = fix(it) }
				p.mobs[i].summons[k].pattern.cells = p.mobs[i].summons[k].pattern.cells.map { fixRef($0) }
			}
		}
		for i in p.ores.indices {
			p.ores[i].hosts = p.ores[i].hosts.map { fixRef($0) }
			p.ores[i].near = fixRef(p.ores[i].near)
		}
		for i in p.mobs.indices {
			for k in p.mobs[i].summons.indices { p.mobs[i].summons[k].dimKeys = p.mobs[i].summons[k].dimKeys.map { fixRef($0) } }
		}
		for i in p.dims.indices {
			var d: ModDimension = p.dims[i]
			d.stone = fixRef(d.stone)
			d.hazard = fixRef(d.hazard)
			d.gateBlock = fixRef(d.gateBlock)
			for k in d.zones.indices {
				d.zones[k].ground = fixRef(d.zones[k].ground)
				d.zones[k].filler = fixRef(d.zones[k].filler)
				d.zones[k].plant = fixRef(d.zones[k].plant)
				d.zones[k].log = fixRef(d.zones[k].log)
				d.zones[k].leaves = fixRef(d.zones[k].leaves)
			}
			for k in d.spawns.indices { d.spawns[k].creature = fixRef(d.spawns[k].creature) }
			if let it = d.entry.item { d.entry.item = fix(it) }
			d.entry.pattern.cells = d.entry.pattern.cells.map { fixRef($0) }
			d.entry.dimKeys = d.entry.dimKeys.map { fixRef($0) }
			p.dims[i] = d
		}
		for i in p.suitMats.indices { if let it = p.suitMats[i].cost { p.suitMats[i].cost = fix(it) } }
		for i in p.suitDesigns.indices {
			for k in p.suitDesigns[i].design.pieces.indices {
				p.suitDesigns[i].design.pieces[k].modMat = fixRef(p.suitDesigns[i].design.pieces[k].modMat)
				p.suitDesigns[i].design.pieces[k].modPart = fixRef(p.suitDesigns[i].design.pieces[k].modPart)
			}
		}
		for i in p.startItems.indices { p.startItems[i].item = fix(p.startItems[i].item) }
		for i in p.vehicles.indices {
			for k in p.vehicles[i].cells.indices { p.vehicles[i].cells[k].block = fixRef(p.vehicles[i].cells[k].block) }
		}
		for i in p.trees.indices {
			p.trees[i].trunk = fixRef(p.trees[i].trunk)
			p.trees[i].branch = fixRef(p.trees[i].branch)
			p.trees[i].leaves = fixRef(p.trees[i].leaves)
			p.trees[i].ground = fixRef(p.trees[i].ground)
		}
		for i in p.scripts.indices { p.scripts[i] = LKeys.rekey(p.scripts[i], fixRef, fix) }
		return p
	}
}

extension ModValidator {
	/// Recipes that turn one thing into another, chained back to where they started (with the game's own
	/// recipes too), must never give back more than went in. Returns each mod recipe that closes such a
	/// loop, with a name for the recipe it loops with; each one found is left out before looking again.
	static func gainLoops(_ p: ModPack, _ off: Set<String>) -> [(String, String)] {
		var from: [Item] = []
		var to: [Item] = []
		var ratio: [Double] = []
		var rid: [String] = []
		var label: [String] = []
		for r in RecipeBook.base where r.cost.count == 1 && r.cost[0].n > 0 {
			from.append(r.cost[0].item)
			to.append(r.out)
			ratio.append(Double(r.outCount) / Double(r.cost[0].n))
			rid.append("")
			label.append("the game's recipe for " + r.out.name)
		}
		for r in p.recipes where !off.contains(r.id) && r.cost.count == 1 && r.cost[0].n > 0 {
			from.append(r.cost[0].item)
			to.append(r.out)
			ratio.append(Double(r.count) / Double(r.cost[0].n))
			rid.append(r.id)
			label.append("the recipe " + r.id)
		}
		var live: [Bool] = [Bool](repeating: true, count: from.count)
		var out: [(String, String)] = []
		for e in from.indices where !rid[e].isEmpty {
			// look for a way back from what it makes to what it uses, three recipes deep at most
			var stack: [(Item, Double, Int, Int)] = [(to[e], ratio[e], 0, -1)]
			var found: Int = -2
			while let top = stack.popLast(), found == -2 {
				for k in from.indices where live[k] && k != e && from[k] == top.0 {
					let gain: Double = top.1 * ratio[k]
					let first: Int = top.3 < 0 ? k : top.3
					if to[k] == from[e] {
						if gain > 1.0001 { found = first; break }
					} else if top.2 < 2 {
						stack.append((to[k], gain, top.2 + 1, first))
					}
				}
			}
			if found >= 0 {
				live[e] = false
				out.append((rid[e], label[found]))
			}
		}
		return out
	}
}

// MARK: - Every installed mod's content, by key (for checks and the editor)

struct ModCatalog {
	/// key -> what it is ("block", "item", "mob", "shot", "loot")
	var keys: [String: String] = [:]
	var names: [String: String] = [:]
	var packs: [ModPack] = []

	static func build(_ packs: [ModPack]) -> ModCatalog {
		var c = ModCatalog()
		c.packs = packs
		for p in packs {
			for b in p.blocks { c.keys[p.key(b.id)] = "block"; c.names[p.key(b.id)] = b.name }
			for i in p.items { c.keys[p.key(i.id)] = "item"; c.names[p.key(i.id)] = i.name }
			for m in p.mobs { c.keys[p.key(m.id)] = "mob"; c.names[p.key(m.id)] = m.name }
			for s in p.projectiles { c.keys[p.key(s.id)] = "shot"; c.names[p.key(s.id)] = s.name }
			for l in p.loot { c.keys[p.key(l.id)] = "loot"; c.names[p.key(l.id)] = l.name }
			for f in p.infusions { c.keys[p.key(f.id)] = "item"; c.names[p.key(f.id)] = joinText(f.name, " Compound") }
			for d in p.dims { c.keys[p.key(d.id)] = "dimension"; c.names[p.key(d.id)] = d.name }
			for sp in p.suitParts { c.keys[p.key(sp.id)] = "item"; c.names[p.key(sp.id)] = sp.name }
			for m in p.suitMats { c.keys[p.key(m.id)] = "suitmat"; c.names[p.key(m.id)] = m.name }
			for v in p.vehicles { c.keys[p.key(v.id)] = "item"; c.names[p.key(v.id)] = v.name }
		}
		return c
	}

	static func installed() -> ModCatalog {
		var ps: [ModPack] = []
		for e in ModStore.entries() { if let p = e.pack { ps.append(p) } }
		return build(ps)
	}

	func block(_ key: String) -> ModBlock? {
		let s: (String, String) = splitModKey(key)
		for p in packs where p.id == s.0 { return p.blocks.first { $0.id == s.1 } }
		return nil
	}

	func item(_ key: String) -> ModItem? {
		let s: (String, String) = splitModKey(key)
		for p in packs where p.id == s.0 { return p.items.first { $0.id == s.1 } }
		return nil
	}

	func mob(_ key: String) -> ModMob? {
		let s: (String, String) = splitModKey(key)
		for p in packs where p.id == s.0 { return p.mobs.first { $0.id == s.1 } }
		return nil
	}
}

// MARK: - Checking a mod

/// A problem found in a mod. Level 0 is a note, 1 a warning (the content still works, perhaps
/// changed), 2 an error (that content is left out until it is fixed).
struct ModIssue: Identifiable {
	var id: Int
	var level: Int
	var mod: String
	var place: String
	var text: String
}

struct ModReport {
	var issues: [ModIssue] = []
	/// content ids of this mod left out because they cannot work
	var disabled: Set<String> = []
	/// the mod as a whole cannot be used
	var fatal: Bool = false

	var errors: Int { return issues.filter { $0.level >= 2 }.count }
	var warnings: Int { return issues.filter { $0.level == 1 }.count }

	mutating func add(_ level: Int, _ mod: String, _ place: String, _ text: String) {
		issues.append(ModIssue(id: issues.count, level: level, mod: mod, place: place, text: text))
	}
}

enum ModValidator {
	/// Cleans a mod in place (numbers into their ranges, ids unique, sizes legal, broken references
	/// removed where that is safe) and reports what was wrong. Content that cannot work at all is
	/// listed in `disabled` and left out when the mod is used, so a mistake never stops the game.
	/// `known` holds every key of every installed mod (for references to other mods).
	static func check(_ p: inout ModPack, known: [String: String]) -> ModReport {
		var r = ModReport()
		let mn: String = p.name.isEmpty ? "Mod" : p.name
		let sb: Bool = p.sandbox
		if p.format > ModPack.currentFormat {
			r.add(2, mn, "Mod", "Made with a newer version of the game.")
			r.fatal = true
			return r
		}
		if p.name.trimmingCharacters(in: .whitespaces).isEmpty { p.name = "Untitled Mod"; r.add(0, mn, "Mod", "It had no name.") }
		if p.name.count > 40 { p.name = String(p.name.prefix(40)) }
		if p.author.count > 40 { p.author = String(p.author.prefix(40)) }
		if p.desc.count > 500 { p.desc = String(p.desc.prefix(500)) }
		if p.version.isEmpty { p.version = "1.0" }
		if p.version.count > 12 { p.version = String(p.version.prefix(12)) }
		if p.skipped > 0 { r.add(1, mn, "Mod", String(p.skipped) + " damaged entries could not be read and were left out.") }
		trim(&p.blocks, ModLimits.maxBlocks, "blocks", mn, &r)
		trim(&p.items, ModLimits.maxItems, "items", mn, &r)
		trim(&p.mobs, ModLimits.maxMobs, "creatures", mn, &r)
		trim(&p.projectiles, ModLimits.maxShots, "shots", mn, &r)
		trim(&p.recipes, ModLimits.maxRecipes, "recipes", mn, &r)
		trim(&p.loot, ModLimits.maxLoot, "loot tables", mn, &r)
		trim(&p.ores, ModLimits.maxOres, "ores", mn, &r)
		trim(&p.structures, ModLimits.maxStructures, "structures", mn, &r)
		uniqueIDs(&p, mn, &r)
		// what this mod's own content is, by key
		var own: [String: String] = [:]
		for b in p.blocks { own[p.key(b.id)] = "block" }
		for i in p.items { own[p.key(i.id)] = "item" }
		for m in p.mobs { own[p.key(m.id)] = "mob" }
		for s in p.projectiles { own[p.key(s.id)] = "shot" }
		for l in p.loot { own[p.key(l.id)] = "loot" }
		// an infusion's compound is an item of the mod
		for f in p.infusions { own[p.key(f.id)] = "item" }
		for d in p.dims { own[p.key(d.id)] = "dimension" }
		func exists(_ it: Item) -> Bool {
			if case .custom(let k) = it {
				let kind: String = own[k] ?? known[k] ?? ""
				return kind == "block" || kind == "item"
			}
			return true
		}
		let shotIDs: Set<String> = Set(p.projectiles.map { $0.id })
		let lootIDs: Set<String> = Set(p.loot.map { $0.id })
		// blocks
		for i in p.blocks.indices {
			var b: ModBlock = p.blocks[i]
			let place: String = "Block \u{201C}" + b.name + "\u{201D}"
			if b.name.trimmingCharacters(in: .whitespaces).isEmpty { b.name = "Block" }
			if b.name.count > 32 { b.name = String(b.name.prefix(32)) }
			if !b.art.valid || b.art.w != 8 || b.art.h != 8 {
				b.art = b.art.valid ? ModBlock.fitArt(b.art) : ModPixels(w: 8, h: 8)
				r.add(1, mn, place, "Its picture was not 8 x 8 and was fitted.")
			}
			if b.art.isBlank { r.add(0, mn, place, "It has no picture yet (it shows as grey).") }
			b.hardness = ModRange.hardness.clamp(b.hardness, sb)
			b.tool = clampI(b.tool, 0, 3)
			b.tier = clampI(b.tier, 0, 9)
			b.light = clampI(b.light, 0, 15)
			b.dropCount = clampI(b.dropCount, 1, 16)
			b.station = clampI(b.station, -1, 9)
			b.power = clampD(b.power.isFinite ? b.power : 0, 0, sb ? 400 : 40)
			b.vehMass = clampD(b.vehMass.isFinite ? b.vehMass : 0, 0, sb ? 60 : 20)
			b.vehPower = clampD(b.vehPower.isFinite ? b.vehPower : 1, 0.25, sb ? 10 : 4)
			b.shotSpeed = clampD(b.shotSpeed.isFinite ? b.shotSpeed : 0, 0, sb ? 200 : 80)
			b.shotDamage = clampD(b.shotDamage.isFinite ? b.shotDamage : 0, 0, sb ? 500 : 120)
			b.fireRate = clampD(b.fireRate.isFinite ? b.fireRate : 0, 0, sb ? 60 : 30)
			if !b.shot.isEmpty && !p.projectiles.contains(where: { $0.id == b.shot }) {
				r.add(1, mn, place, "Its gun's shot is not one of this mod's shots: it fires the game's own.")
				b.shot = ""
			}
			b.weight = clampD(b.weight.isFinite ? b.weight : 0, 0, sb ? 40 : 12)
			b.carry = clampD(b.carry.isFinite ? b.carry : 0, 0, sb ? 4000 : 400)
			b.grip = clampD(b.grip.isFinite ? b.grip : 1, 0.02, sb ? 4 : 2)
			b.bounce = clampD(b.bounce.isFinite ? b.bounce : 0, 0, sb ? 1.2 : 0.9)
			b.liqDensity = clampD(b.liqDensity.isFinite ? b.liqDensity : 1, 0.2, sb ? 12 : 5)
			b.liqThick = clampD(b.liqThick.isFinite ? b.liqThick : 1, 1, sb ? 20 : 8)
			b.liqReach = clampI(b.liqReach, 1, sb ? 30 : 12)
			b.liqHarm = clampD(b.liqHarm.isFinite ? b.liqHarm : 0, 0, sb ? 100 : 20)
			b.liqOpacity = clampD(b.liqOpacity.isFinite ? b.liqOpacity : 0.75, 0.1, 1)
			b.liqEffect = clampI(b.liqEffect, -1, ModEffectKind.allCases.count - 1)
			b.liqEffectAmt = clampD(b.liqEffectAmt.isFinite ? b.liqEffectAmt : 10, 0, sb ? 200 : 60)
			if b.liqHardens.count > 80 { b.liqHardens = "" }
			b.powerAmt = clampD(b.powerAmt.isFinite ? b.powerAmt : 4, 0.1, sb ? 200 : 40)
			if b.text.count > 200 { b.text = String(b.text.prefix(200)) }
			if let d = b.drop, !exists(d) {
				b.drop = nil
				b.dropSelf = true
				r.add(1, mn, place, "It dropped something that does not exist; it drops itself now.")
			}
			p.blocks[i] = b
		}
		// shots
		for i in p.projectiles.indices {
			var s: ModProjectile = p.projectiles[i]
			if s.name.trimmingCharacters(in: .whitespaces).isEmpty { s.name = "Shot" }
			s.size = clampD(s.size.isFinite ? s.size : 0.3, 0.1, 1.0)
			s.glow = clampI(s.glow, 0, 12)
			s.gravity = ModRange.gravity.clamp(s.gravity, sb)
			s.pierce = clampI(s.pierce, 0, 5)
			s.life = clampD(s.life.isFinite ? s.life : 2, 0.2, 6)
			s.explode = clampD(s.explode.isFinite ? s.explode : 0, 0, sb ? 12 : 6)
			s.burn = clampD(s.burn.isFinite ? s.burn : 0, 0, 10)
			p.projectiles[i] = s
		}
		// items
		for i in p.items.indices {
			var it: ModItem = p.items[i]
			let place: String = "Item \u{201C}" + it.name + "\u{201D}"
			if it.name.trimmingCharacters(in: .whitespaces).isEmpty { it.name = "Item" }
			if it.name.count > 32 { it.name = String(it.name.prefix(32)) }
			if !it.icon.valid || it.icon.w > 32 || it.icon.h > 32 {
				it.icon = ModPixels(w: 16, h: 16)
				r.add(1, mn, place, "Its picture was too big or damaged and was cleared.")
			}
			if let b = it.baseIcon, !exists(b) { it.baseIcon = nil }
			if it.icon.isBlank && it.baseIcon == nil { r.add(0, mn, place, "It has no picture yet.") }
			it.stack = clampI(it.stack, 1, sb ? 999 : 99)
			if it.kind.isWeapon || it.kind == .tool || it.kind == .armor { it.stack = 1 }
			it.rarity = clampI(it.rarity, 0, 4)
			it.tintAmt = clampD(it.tintAmt.isFinite ? it.tintAmt : 0, 0, 1)
			it.hunger = clampD(it.hunger.isFinite ? it.hunger : 0, 0, 20)
			if it.effects.count > ModLimits.maxEffects { it.effects = Array(it.effects.prefix(ModLimits.maxEffects)) }
			for k in it.effects.indices {
				it.effects[k].amount = it.effects[k].kind.amountRange.clamp(it.effects[k].amount, sb)
				it.effects[k].seconds = ModRange.seconds.clamp(it.effects[k].seconds, sb)
			}
			if var we = it.wornEffect {
				we.amount = we.kind.amountRange.clamp(we.amount, sb)
				it.wornEffect = we
			}
			it.useTime = clampD(it.useTime.isFinite ? it.useTime : 0.6, 0.1, 5)
			it.toolType = clampI(it.toolType, 0, 3)
			it.toolTier = clampI(it.toolTier, 1, 9)
			it.toolSpeed = ModRange.toolSpeed.clamp(it.toolSpeed, sb)
			it.style = clampI(it.style, 0, 4)
			it.damage = ModRange.damage.clamp(it.damage, sb)
			it.cooldown = ModRange.cooldown.clamp(it.cooldown, sb)
			it.reach = ModRange.reach.clamp(it.reach, sb)
			it.arc = clampD(it.arc.isFinite ? it.arc : 1, 0.1, 1.6)
			it.knock = ModRange.knock.clamp(it.knock, sb)
			it.maxHits = clampI(it.maxHits, 1, 99)
			it.daze = clampD(it.daze.isFinite ? it.daze : 0, 0, 3)
			it.burn = clampD(it.burn.isFinite ? it.burn : 0, 0, 8)
			it.windup = clampD(it.windup.isFinite ? it.windup : 0, 0, 0.6)
			it.backstab = clampD(it.backstab.isFinite ? it.backstab : 1, 1, 3)
			it.undeadMult = clampD(it.undeadMult.isFinite ? it.undeadMult : 1, 0.5, 3)
			it.crit = clampD(it.crit.isFinite ? it.crit : 0.1, 0, 0.6)
			it.shot = clampI(it.shot, 0, 12)
			it.speed = ModRange.shotSpeed.clamp(it.speed, sb)
			it.gravity = ModRange.gravity.clamp(it.gravity, sb)
			it.pierce = clampI(it.pierce, 0, 5)
			it.spread = clampI(it.spread, 1, sb ? 12 : 7)
			it.magazine = clampI(it.magazine, 1, sb ? 99 : 30)
			it.reload = clampD(it.reload.isFinite ? it.reload : 1.5, 0.2, 6)
			it.slot = clampI(it.slot, 0, 2)
			it.defense = ModRange.defense.clamp(it.defense, sb)
			it.look = clampI(it.look, 1, 9)
			it.light = clampI(it.light, 0, 15)
			if !it.projectile.isEmpty && !shotIDs.contains(it.projectile) {
				it.projectile = ""
				r.add(1, mn, place, "Its shot no longer exists; it fires a game shot.")
			}
			if let a = it.ammo, !exists(a) {
				it.ammo = nil
				r.add(1, mn, place, "Its ammunition does not exist; it needs none now.")
			}
			p.items[i] = it
		}
		// creatures
		for i in p.mobs.indices {
			var m: ModMob = p.mobs[i]
			let place: String = "Creature \u{201C}" + m.name + "\u{201D}"
			if m.name.trimmingCharacters(in: .whitespaces).isEmpty { m.name = "Creature" }
			if m.name.count > 32 { m.name = String(m.name.prefix(32)) }
			if MobKind(rawValue: m.base) == nil || m.base == MobKind.custom.rawValue || m.base == MobKind.villager.rawValue {
				m.base = MobKind.zombie.rawValue
				r.add(1, mn, place, "Its body was unknown; it uses the zombie body.")
			}
			var frames: [ModPixels] = []
			for f in m.frames.prefix(ModLimits.maxFrames) {
				if f.valid && f.w <= ModLimits.maxMobArt && f.h <= ModLimits.maxMobArt { frames.append(f) }
			}
			if frames.count != m.frames.count { r.add(1, mn, place, "Some of its pictures were too big or damaged and were left out.") }
			m.frames = frames
			if m.customArt && (frames.isEmpty || frames[0].isBlank) {
				m.customArt = false
				r.add(1, mn, place, "Its own picture is empty; it uses its base body.")
			}
			m.hue = clampD(m.hue.isFinite ? m.hue : 0, -180, 180)
			m.saturation = clampD(m.saturation.isFinite ? m.saturation : 1, 0, 2)
			m.brightness = clampD(m.brightness.isFinite ? m.brightness : 1, 0.4, 1.6)
			m.tintAmt = clampD(m.tintAmt.isFinite ? m.tintAmt : 0, 0, 1)
			m.scale = ModRange.scale.clamp(m.scale, sb || m.category == .boss)
			m.hp = (m.category == .boss ? ModRange.bossHP : ModRange.mobHP).clamp(m.hp, sb)
			m.damage = ModRange.damage.clamp(m.damage, sb)
			m.speed = ModRange.mobSpeed.clamp(m.speed, sb)
			m.detect = ModRange.detect.clamp(m.detect, sb)
			m.jump = ModRange.jump.clamp(m.jump, sb)
			m.defense = clampD(m.defense.isFinite ? m.defense : 0, 0, 0.9)
			m.knockResist = clampD(m.knockResist.isFinite ? m.knockResist : 0, 0, 1)
			m.glow = clampI(m.glow, 0, 10)
			m.behavior.patrolRange = clampD(m.behavior.patrolRange.isFinite ? m.behavior.patrolRange : 8, 2, 40)
			m.behavior.defendRadius = clampD(m.behavior.defendRadius.isFinite ? m.behavior.defendRadius : 10, 3, 40)
			if m.category == .flying { m.behavior.fly = true }
			if m.category == .water { m.behavior.swim = true }
			if !m.behavior.guardKey.isEmpty {
				let gk: String = m.behavior.guardKey
				let native: Bool = MobKind.allCases.contains { mobDef($0).name == gk }
				if !native && (own[gk] ?? known[gk] ?? "") != "mob" {
					m.behavior.guardKey = ""
					r.add(1, mn, place, "The creature it guarded does not exist.")
				}
			}
			if m.attacks.count > ModLimits.maxAttacks { m.attacks = Array(m.attacks.prefix(ModLimits.maxAttacks)) }
			for k in m.attacks.indices {
				var a: ModAttack = m.attacks[k]
				a.damage = ModRange.damage.clamp(a.damage, sb)
				a.range = clampD(a.range.isFinite ? a.range : 1.6, 0.5, a.kind == .ranged ? 30 : (sb ? 12 : 8))
				a.cooldown = clampD(a.cooldown.isFinite ? a.cooldown : 1.2, 0.2, 20)
				a.shot = clampI(a.shot, 0, 12)
				a.speed = ModRange.shotSpeed.clamp(a.speed, sb)
				a.knock = ModRange.knock.clamp(a.knock, sb)
				a.radius = ModRange.radius.clamp(a.radius, sb)
				a.hits = clampI(a.hits, 1, sb ? 12 : 6)
				a.windup = clampD(a.windup.isFinite ? a.windup : 0.3, 0, 2)
				if !a.projectile.isEmpty && !shotIDs.contains(a.projectile) {
					a.projectile = ""
					r.add(1, mn, place, "An attack's shot no longer exists; it fires a game shot.")
				}
				m.attacks[k] = a
			}
			if m.drops.count > ModLimits.maxDrops { m.drops = Array(m.drops.prefix(ModLimits.maxDrops)) }
			var drops: [ModDrop] = []
			for d0 in m.drops {
				var d: ModDrop = d0
				if !exists(d.item) {
					r.add(1, mn, place, "A drop that does not exist was removed.")
					continue
				}
				d.min = clampI(d.min, 0, 64)
				d.max = clampI(d.max, d.min, 64)
				d.chance = clampD(d.chance.isFinite ? d.chance : 0, 0, 1)
				drops.append(d)
			}
			m.drops = drops
			if !m.loot.isEmpty && !lootIDs.contains(m.loot) {
				m.loot = ""
				r.add(1, mn, place, "Its loot table no longer exists.")
			}
			var sp: ModSpawn = m.spawn
			sp.when = clampI(sp.when, 0, 2)
			sp.biomes = sp.biomes.filter { Biome(rawValue: $0) != nil }
			sp.minY = clampI(sp.minY, 0, 559)
			sp.maxY = clampI(sp.maxY, sp.minY, 559)
			sp.weight = clampD(sp.weight.isFinite ? sp.weight : 1, 0.1, 10)
			sp.group = clampI(sp.group, 1, m.category == .boss ? 1 : 4)
			sp.maxNearby = clampI(sp.maxNearby, 1, m.category == .boss ? 1 : 8)
			m.spawn = sp
			p.mobs[i] = m
		}
		// recipes
		for i in p.recipes.indices {
			var rc: ModRecipe = p.recipes[i]
			let place: String = "Recipe for " + itemLabel(rc.out, own: p, known: known)
			rc.count = clampI(rc.count, 1, 99)
			if rc.cost.count > ModLimits.maxCost { rc.cost = Array(rc.cost.prefix(ModLimits.maxCost)) }
			for k in rc.cost.indices { rc.cost[k].n = clampI(rc.cost[k].n, 1, 999) }
			rc.station = clampI(rc.station, -1, 9)
			rc.cat = clampI(rc.cat, 0, RecipeCat.allCases.count - 1)
			var bad: String = ""
			if !exists(rc.out) { bad = "It makes something that does not exist." }
			else if rc.cost.isEmpty { bad = "It needs at least one ingredient." }
			else if rc.cost.contains(where: { !exists($0.item) }) { bad = "One of its ingredients does not exist." }
			else if rc.cost.contains(where: { $0.item == rc.out && $0.n >= rc.count }) { bad = "It uses up as much as it makes (a loop that makes nothing)." }
			if rc.station == -1 {
				let blk: ModBlock? = p.blocks.first { $0.id == rc.stationBlock }
				if blk == nil || blk?.function != .station {
					rc.station = 0
					r.add(1, mn, place, "Its station block is missing or is not a station; it is made by hand.")
				}
			}
			if !bad.isEmpty {
				r.add(2, mn, place, bad)
				r.disabled.insert(rc.id)
			}
			p.recipes[i] = rc
		}
		for (rid, other) in gainLoops(p, r.disabled) {
			let rc: ModRecipe? = p.recipes.first { $0.id == rid }
			let place: String = "Recipe for " + itemLabel(rc?.out ?? .mat(.stick), own: p, known: known)
			r.add(2, mn, place, "Crafting it and " + other + " back and forth would make things from nothing.")
			r.disabled.insert(rid)
		}
		// loot tables
		for i in p.loot.indices {
			var lt: ModLootTable = p.loot[i]
			let place: String = "Loot table \u{201C}" + lt.name + "\u{201D}"
			lt.rolls = clampI(lt.rolls, 1, 6)
			lt.nothing = clampD(lt.nothing.isFinite ? lt.nothing : 0, 0, 1000)
			lt.chestChance = clampD(lt.chestChance.isFinite ? lt.chestChance : 0, 0, 1)
			if lt.entries.count > ModLimits.maxLootEntries { lt.entries = Array(lt.entries.prefix(ModLimits.maxLootEntries)) }
			var ents: [ModLootEntry] = []
			for e0 in lt.entries {
				var e: ModLootEntry = e0
				if !exists(e.item) {
					r.add(1, mn, place, "An entry for something that does not exist was removed.")
					continue
				}
				e.min = clampI(e.min, 1, 64)
				e.max = clampI(e.max, e.min, 64)
				e.rarity = clampI(e.rarity, 0, 3)
				e.weight = clampD(e.weight.isFinite ? e.weight : 0, 0, 1000)
				ents.append(e)
			}
			lt.entries = ents
			if lt.entries.isEmpty {
				r.add(2, mn, place, "It has nothing in it.")
				r.disabled.insert(lt.id)
			}
			p.loot[i] = lt
		}
		// ores
		for i in p.ores.indices {
			var o: ModOre = p.ores[i]
			let place: String = "Ore \u{201C}" + o.name + "\u{201D}"
			o.dim = clampI(o.dim, 0, 1)
			let bottom: Int = o.dim == 0 ? WorldGen.H - 2 : umbralH - 2
			o.minY = clampI(o.minY, 2, bottom)
			o.maxY = clampI(o.maxY, o.minY, bottom)
			o.veins = clampD(o.veins.isFinite ? o.veins : 1, 0.05, 8)
			o.size = clampI(o.size, 1, 24)
			o.host = clampI(o.host, 0, 4)
			if !p.blocks.contains(where: { $0.id == o.block }) {
				r.add(2, mn, place, "Choose which block of this mod it is made of.")
				r.disabled.insert(o.id)
			}
			p.ores[i] = o
		}
		// structures
		for i in p.structures.indices {
			var s: ModStructure = p.structures[i]
			let place: String = "Structure \u{201C}" + s.name + "\u{201D}"
			s.chance = clampD(s.chance.isFinite ? s.chance : 0.3, 0.01, 1)
			s.spacing = clampI(s.spacing, 64, 4096)
			s.dim = clampI(s.dim, 0, 1)
			s.minY = clampI(s.minY, 4, 550)
			s.maxY = clampI(s.maxY, s.minY, 550)
			s.biomes = s.biomes.filter { Biome(rawValue: $0) != nil }
			if s.w < 1 || s.h < 1 || s.w > ModLimits.maxStructW || s.h > ModLimits.maxStructH || s.cells.count != s.w * s.h {
				r.add(2, mn, place, "It has no captured blocks, or its size is wrong. Capture it again.")
				r.disabled.insert(s.id)
			} else {
				for k in s.cells.indices {
					let v: Int = s.cells[k]
					if v >= 1000 {
						let pi: Int = v - 1000
						let key: String = pi < s.palette.count ? s.palette[pi] : ""
						if (own[key] ?? known[key] ?? "") != "block" { s.cells[k] = -1 }
					} else if v > 255 || v < -1 {
						s.cells[k] = -1
					} else if v >= 0 {
						// custom blocks go by key (their numbers differ per world); machines, bedrock and the
						// rift gate (one per world) can't be copied
						if let t = Tile(rawValue: UInt8(v)), !t.isMod && modStructureTileOK(t) { continue }
						s.cells[k] = -1
					}
				}
			}
			if !s.loot.isEmpty && !lootIDs.contains(s.loot) {
				s.loot = ""
				r.add(1, mn, place, "Its loot table no longer exists.")
			}
			p.structures[i] = s
		}
		checkPlus(&p, mn, sb, known, &r)
		return r
	}

	static func trim<T>(_ a: inout [T], _ n: Int, _ what: String, _ mn: String, _ r: inout ModReport) {
		if a.count > n {
			r.add(1, mn, "Mod", "Only " + String(n) + " " + what + " fit in one mod; the rest were left out.")
			a = Array(a.prefix(n))
		}
	}

	/// Gives empty or repeated ids fresh ones
	static func uniqueIDs(_ p: inout ModPack, _ mn: String, _ r: inout ModReport) {
		var used: Set<String> = []
		var fixed: Int = 0
		func fresh(_ id: String, _ prefix: String) -> String {
			let ok: Bool = !id.isEmpty && id.count <= 24 && !id.contains(":") && !used.contains(id)
			if ok {
				used.insert(id)
				return id
			}
			var n: Int = 1
			while used.contains(prefix + String(n)) { n += 1 }
			used.insert(prefix + String(n))
			fixed += 1
			return prefix + String(n)
		}
		for i in p.blocks.indices { p.blocks[i].id = fresh(p.blocks[i].id, "b") }
		for i in p.items.indices { p.items[i].id = fresh(p.items[i].id, "i") }
		for i in p.mobs.indices { p.mobs[i].id = fresh(p.mobs[i].id, "c") }
		for i in p.projectiles.indices { p.projectiles[i].id = fresh(p.projectiles[i].id, "s") }
		for i in p.recipes.indices { p.recipes[i].id = fresh(p.recipes[i].id, "r") }
		for i in p.loot.indices { p.loot[i].id = fresh(p.loot[i].id, "l") }
		for i in p.ores.indices { p.ores[i].id = fresh(p.ores[i].id, "o") }
		for i in p.structures.indices { p.structures[i].id = fresh(p.structures[i].id, "t") }
		if fixed > 0 { r.add(1, mn, "Mod", String(fixed) + " content ids were missing or repeated and were renumbered.") }
	}

	/// A readable name for an item in a message
	static func itemLabel(_ it: Item, own: ModPack, known: [String: String]) -> String {
		if case .custom(let k) = it {
			let s: (String, String) = splitModKey(k)
			if s.0 == own.id {
				if let b = own.blocks.first(where: { $0.id == s.1 }) { return b.name }
				if let i = own.items.first(where: { $0.id == s.1 }) { return i.name }
			}
			return known[k] != nil ? k : "missing " + k
		}
		return it.name
	}
}

extension Game {
	// MARK: custom creatures in play

	/// Puts a custom creature into the world, sized and given health from its definition. Returns nil
	/// for an unknown slot, or when as many custom creatures as the limit allows are already about.
	@discardableResult
	func addCustomMob(_ slot: Int, _ x: Double, _ y: Double) -> Mob? {
		guard let r = ModRuntime.shared.mob(slot) else { return nil }
		if customMobCount() >= ModLimits.maxActiveMobs { return nil }
		let m = Mob(id: newID(), kind: .custom, x: x, y: y)
		m.cslot = slot
		let d: MobDef = r.mdef
		m.b = Body(x: x, y: y, w: d.w, h: d.h)
		m.maxHP = d.hp * mobHealthMult
		m.hp = m.maxHP
		m.modCD = [Double](repeating: 0, count: r.attacks.count)
		m.lastAtk = -1
		if world.dim == .overworld { m.homeBiome = gen.col(Int(floor(x))).biome.rawValue }
		mobs.append(m)
		if !r.key.isEmpty && !logicRT.isEmpty { fireLogic(.spawned, mob: m, key: r.key) }
		return m
	}

	/// Custom creatures alive right now
	func customMobCount() -> Int {
		var n: Int = 0
		for m in mobs where m.kind == .custom && m.hp > 0 && !m.removed { n += 1 }
		return n
	}

	/// Custom creatures don't feel fire when their maker made them fireproof
	func heatImmune(_ m: Mob) -> Bool {
		if m.kind == .custom { return ModRuntime.shared.mob(m.cslot)?.def.fireproof ?? false }
		return isHeatImmune(m.kind)
	}

	/// A custom creature's turn. Its behaviour switches (see ModBehavior) decide what it does; the game's
	/// creature AI gives it senses and memory (`think`), and every attack it makes hurts through the shared
	/// damage system, so armour, sides, knockback and hit cooldowns work as they do for the game's own.
	func updateCustomMob(_ m: Mob, _ dt: Double) {
		guard let r = ModRuntime.shared.mob(m.cslot) else {
			m.removed = true
			return
		}
		if m.summoned && summonedLeaves(m, dt) { return }
		if !r.def.phases.isEmpty || m.phaseShield > 0 { stepPhases(m, r, dt) }
		let bh: ModBehavior = r.def.behavior
		if m.modCD.count != r.attacks.count { m.modCD = [Double](repeating: 0, count: r.attacks.count) }
		var i: Int = 0
		while i < m.modCD.count {
			if m.modCD[i] > 0 { m.modCD[i] -= dt }
			i += 1
		}
		if bh.burnsInSun && !r.def.fireproof && inSunlight(m) { m.burn = 2.0 }
		if r.guards { followWard(m, r, dt) }
		if r.aquatic && !m.b.inWater {
			// out of the water it flops about and slowly suffocates
			m.dryT += dt
			if m.dryT > 1.0 { m.dryT = 0; hurtMob(m, 1, 0, 0, false) }
		}
		// an attack under way plays out to its end (the warning it showed has to be honest)
		if m.st >= 3 {
			stepCustomAttack(m, r, dt)
			customPhysics(m, r, dt)
			return
		}
		let dist: Double = abs(pb.x - m.b.x)
		let dyP: Double = (pb.y - pb.h * 0.5) - m.b.cy
		let armed: Bool = r.canAttack
		let calm: Bool = dead || settings.peaceful || !armed
		// after the player: hunting them, paying them back for a hit, or keeping them out of its area
		let provoked: Bool = bh.retaliate && clock - m.lastHitByPlayer < 12.0
		var wants: Bool = !calm && (bh.attackPlayer || provoked)
		if !calm && bh.defendArea {
			let rr: Double = bh.defendRadius * (m.ai == .chase ? 1.5 : 1.0)
			wants = abs(pb.x - m.homeX) < rr && abs(pb.y - m.homeY) < rr
		}
		var engaged: Bool = false
		if wants {
			engaged = think(m, dt, dist, dyP)
			// one that holds its ground is never "stuck against a wall" (no leaps, no backing off)
			if bh.standStill || !(bh.chase || provoked || bh.defendArea) {
				m.leapReq = false
				m.blockedT = 0
				m.progX = m.b.x
			}
		} else {
			if m.ai != .idle { m.ai = .idle; m.aiT = 0 }
			m.why = calm && !armed ? .none : (settings.peaceful ? .peaceful : .none)
		}
		let onPlayer: Bool = engaged && (m.ai == .chase || m.ai == .alert)
		// a creature it fights (guardians go for monsters near them)
		var foe: Mob? = nil
		if bh.attackMobs && armed && !onPlayer {
			if let f = m.foe, f.hp <= 0 || f.removed || f.downed || abs(f.b.x - m.b.x) > max(8.0, r.mdef.aggro) * 1.5 { m.foe = nil }
			m.foeT -= dt
			if m.foe == nil && m.foeT <= 0 {
				m.foeT = 0.5
				m.foe = findFoe(m, r)
			}
			foe = m.foe
		}
		// where it heads this frame: 0 stand, 1 go to (gx, gy), 2 run from gx, 3 wander, 4 patrol
		var mode: Int = 0
		var gx: Double = m.b.x
		var gy: Double = m.b.y
		var spd: Double = 1.0
		var tgtX: Double = 0
		var tgtY: Double = 0
		var hasTarget: Bool = false
		if onPlayer {
			tgtX = pb.x
			tgtY = pb.y - pb.h * 0.55
			hasTarget = true
		} else if let f = foe {
			tgtX = f.b.x
			tgtY = f.b.cy
			hasTarget = true
		}
		if m.t2 > 0 {
			// frightened by a hit (passive creatures, see hurtMob)
			m.t2 -= dt
			mode = 2
			gx = m.tx
			spd = 1.8
		} else if hasTarget {
			let adx: Double = abs(tgtX - m.b.x)
			let shooter: Bool = r.reach.2
			let pursue: Bool = !bh.standStill && (bh.chase || provoked || bh.defendArea || foe != nil)
			if bh.runAway && shooter && adx < r.reach.0 * 0.45 {
				// keeps its distance and shoots
				mode = 2
				gx = tgtX
				spd = 1.1
			} else if shooter && adx < r.reach.0 * 0.8 && (foe != nil || m.sees) {
				mode = 0
			} else if pursue {
				mode = 1
				gx = onPlayer ? m.aimX : tgtX
				gy = tgtY
				spd = adx > 8.0 ? 1.15 : 1.0
			}
			if mode == 0 { m.dir = tgtX >= m.b.x ? 1 : -1 }
		} else if engaged {
			// searching where the player was last seen, or going home (see think)
			if !bh.standStill || m.ai == .back {
				mode = 1
				gx = m.aimX
				gy = m.seenY - 1.0
				spd = 0.85
			}
		} else if bh.runAway, let from = scaryNear(m, r, dt) {
			mode = 2
			gx = from
			spd = 1.5
		} else if bh.followPlayer && !dead && dist < 48 {
			if dist > 3.0 || abs(dyP) > 4.0 {
				mode = 1
				gx = pb.x - Double(facing) * 1.5
				gy = pb.y - 1.5
				spd = dist > 10 ? 1.4 : 1.0
			}
		} else if (r.guards && m.ward != nil) || bh.defendArea {
			// stays by the creature it guards, or in the area it defends
			let away: Double = abs(m.b.x - m.homeX)
			if away > (r.guards ? 3.0 : 4.0) {
				mode = 1
				gx = m.homeX
				gy = m.homeY - 1.0
				spd = away > 10 ? 1.2 : 0.8
			} else if !bh.standStill && bh.wander {
				mode = 3
			}
		} else if bh.standStill {
			mode = 0
		} else if bh.patrol {
			mode = 4
		} else if bh.wander {
			mode = 3
		}
		if bh.stayInBiome && (mode == 3 || mode == 4) && strayed(m, dt) {
			mode = 1
			gx = m.homeX
			gy = m.homeY - 1.0
			spd = 0.8
		}
		moveCustom(m, r, mode, gx, gy, spd * m.phaseSpeed, dt)
		// touching it hurts while it is after the player (its contact damage)
		if onPlayer && m.ai == .chase && r.def.damage > 0 { contactHurt(m, r.def.damage) }
		if hasTarget && m.cd <= 0 && m.daze <= 0, let k = pickCustomAttack(m, r, tgtX, tgtY, foe) {
			startCustomAttack(m, r, k, tgtX, tgtY, foe)
		}
		customPhysics(m, r, dt)
	}

	/// A guard keeps its home beside the creature it guards, and looks for another when that one is gone
	func followWard(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		if let w = m.ward, w.hp > 0 && !w.removed {
			m.homeX = w.b.x
			m.homeY = w.b.y
			return
		}
		m.ward = nil
		m.wardT -= dt
		if m.wardT > 0 { return }
		m.wardT = 1.0
		var best: Mob? = nil
		var bd: Double = 30.0
		for o in mobs where o !== m && o.hp > 0 && !o.removed {
			var match: Bool = false
			if r.guardSlot >= 0 { match = o.kind == .custom && o.cslot == r.guardSlot }
			else if let gk = r.guardKind { match = o.kind == gk }
			if !match { continue }
			let d: Double = abs(o.b.x - m.b.x)
			if d < bd {
				bd = d
				best = o
			}
		}
		m.ward = best
	}

	/// The nearest monster a guardian may go for: hostile to the player, within its senses, and on a
	/// side its blows can hurt
	func findFoe(_ m: Mob, _ r: ModMobRT) -> Mob? {
		let range: Double = max(8.0, r.mdef.aggro)
		let src: DamageSource = .mob(m, faction(of: m))
		var best: Mob? = nil
		var bd: Double = range * range
		for o in mobsNear(m.b.x - range, m.b.x + range) {
			if o === m || o.hp <= 0 || o.removed || o.downed || o.tame { continue }
			if !(o.def.hostile || o.isBoss) { continue }
			if o.kind == .custom && o.cslot == m.cslot { continue }
			if !canHarm(src, targetFaction: faction(of: o), targetID: o.id, area: false) { continue }
			let dx: Double = o.b.x - m.b.x
			let dy: Double = o.b.cy - m.b.cy
			let dd: Double = dx * dx + dy * dy
			if dd < bd {
				bd = dd
				best = o
			}
		}
		return best
	}

	/// What a timid creature runs from: the player close by, or (looked for twice a second) a monster
	func scaryNear(_ m: Mob, _ r: ModMobRT, _ dt: Double) -> Double? {
		if r.mdef.hostile { return nil }
		if !dead && abs(pb.x - m.b.x) < 6.0 && abs(pb.y - m.b.y) < 4.0 { return pb.x }
		m.foeT -= dt
		if m.foeT <= 0 {
			m.foeT = 0.5
			m.threat = nearestHostileTo(m.b.x, m.b.cy, 7.0)
		}
		if let t = m.threat, t.hp > 0 && !t.removed && t !== m && abs(t.b.x - m.b.x) < 9.0 { return t.b.x }
		return nil
	}

	/// True when a creature that keeps to its biome has wandered out of it (checked twice a second)
	func strayed(_ m: Mob, _ dt: Double) -> Bool {
		if world.dim != .overworld || m.homeBiome < 0 { return false }
		m.biomeT -= dt
		if m.biomeT <= 0 {
			m.biomeT = 0.5
			let ahead: Int = Int(floor(m.b.x + Double(m.dir) * 2.0))
			m.strayed = gen.col(ahead).biome.rawValue != m.homeBiome
		}
		return m.strayed
	}

	/// Moves a custom creature by the plan made in updateCustomMob: walking, flying or swimming
	func moveCustom(_ m: Mob, _ r: ModMobRT, _ mode: Int, _ gx: Double, _ gy: Double, _ spd: Double, _ dt: Double) {
		let d: MobDef = r.mdef
		let bh: ModBehavior = r.def.behavior
		let swimming: Bool = m.b.inWater && (r.aquatic || bh.swim)
		if d.flying || swimming {
			// free movement: a point to head for (a new one now and then when idle)
			var tx: Double = m.b.x
			var ty: Double = m.b.y
			var sp: Double = d.speed * spd
			switch mode {
			case 1:
				tx = gx
				ty = gy + (d.flying ? sin(clock * 3.0 + Double(m.id)) * 0.8 : 0)
			case 2:
				tx = m.b.x + (m.b.x >= gx ? 6.0 : -6.0)
				ty = m.b.y - (d.flying ? 3.0 : 0)
			case 3, 4:
				m.t1 -= dt
				if m.t1 <= 0 || mode == 4 && abs(m.b.x - m.tx) < 1.0 {
					m.t1 = Double.random(in: 1.5...4.0)
					if mode == 4 {
						m.goal = m.goal >= 0 ? -1 : 1
						m.tx = m.homeX + Double(m.goal) * bh.patrolRange
						m.ty = m.homeY
					} else {
						m.tx = m.homeX + Double.random(in: -8...8)
						m.ty = m.homeY + Double.random(in: -4...3)
					}
				}
				tx = m.tx
				ty = m.ty
				sp *= 0.6
			default:
				sp = 0
			}
			var ax: Double = tx - m.b.x
			var ay: Double = ty - m.b.y
			let len: Double = sqrt(ax * ax + ay * ay)
			if len < 0.4 || sp <= 0 {
				ax = 0
				ay = 0
			} else {
				ax /= len
				ay /= len
			}
			let k: Double = min(1.0, dt * (swimming ? 3.0 : 4.0))
			m.b.vx += (ax * sp - m.b.vx) * k
			m.b.vy += (ay * sp * (swimming ? 0.7 : 1.0) - m.b.vy) * k
			if abs(m.b.vx) > 0.3 { m.dir = m.b.vx > 0 ? 1 : -1 }
			return
		}
		switch mode {
		case 1:
			chase(m, gx, spd, dt)
		case 2:
			flee(m, gx, dt, spd)
		case 3:
			wander(m, dt, 0.5)
		case 4:
			if m.goal == 0 { m.goal = m.dir }
			let end: Double = m.homeX + Double(m.goal) * bh.patrolRange
			if (m.goal > 0 && m.b.x >= end) || (m.goal < 0 && m.b.x <= end) || cliffAhead(m, m.goal) || (m.b.hitWall && m.b.onGround) {
				m.goal = -m.goal
			}
			m.dir = m.goal
			accelX(m, Double(m.goal) * d.speed * 0.6, 14, dt)
		default:
			accelX(m, 0, 18, dt)
		}
	}

	/// Steps a custom creature's body: swimmers glide through water (and never leave it on their own),
	/// fliers bounce off what they hit, walkers use the game's usual physics
	func customPhysics(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		if r.aquatic && m.b.inWater {
			let nx: Double = m.b.x + m.b.vx * dt
			let ny: Double = m.b.y + m.b.vy * dt
			let hw: Double = m.b.w * 0.45
			let ix: Int = Int(floor(nx))
			let midWet: Bool = world.tile(ix, Int(floor(ny - m.b.h * 0.5))) == .water
			let topWet: Bool = world.tile(ix, Int(floor(ny - m.b.h + 0.1))).liquid
			let sides: Bool = !world.solid(Int(floor(nx - hw)), Int(floor(ny - m.b.h * 0.5))) && !world.solid(Int(floor(nx + hw)), Int(floor(ny - m.b.h * 0.5)))
			let floorOK: Bool = !world.solid(ix, Int(floor(ny - 0.05)))
			if midWet && topWet && sides && floorOK {
				m.b.x = nx
				m.b.y = ny
			} else {
				m.t1 = 0
				m.b.vx = -m.b.vx * 0.5
				m.b.vy = -m.b.vy * 0.5
			}
			let fw: Double = m.b.w * 0.5
			m.b.inWater = world.liquidFraction(m.b.x - fw, m.b.y - m.b.h, m.b.x + fw, m.b.y, false) > 0.3
			m.anim += dt * 6.0
			return
		}
		if r.def.behavior.swim && m.b.inWater && !r.mdef.flying {
			let sm: Double = m.speedMul
			if sm < 0.999 { m.b.vx *= sm }
			world.moveBody(&m.b, dt, stepUp: 1.0, dropThrough: false, decks: decksCache)
			if sm < 0.999 { m.b.vx /= sm }
			m.anim += dt * 4.0
			return
		}
		stepMob(m, dt)
		if r.mdef.flying {
			m.anim += dt * 6.0
			if m.st < 3 && (m.b.hitWall || m.b.hitCeil || m.b.onGround) {
				m.b.vy = -1.0
				m.t1 = 0
			}
		}
	}

	/// Which of its attacks could reach a target this far away now; one is picked at random (not the
	/// same one twice running when there is a choice)
	func pickCustomAttack(_ m: Mob, _ r: ModMobRT, _ tx: Double, _ ty: Double, _ foe: Mob?) -> Int? {
		let dx: Double = abs(tx - m.b.x)
		let dy: Double = abs(ty - m.b.cy)
		let hw: Double = m.b.w * 0.5
		let footing: Bool = m.b.onGround || r.mdef.flying || m.b.inWater
		var seesFoe: Bool? = nil
		var opts: [Int] = []
		var i: Int = 0
		while i < r.attacks.count && i < m.modCD.count {
			let a: ModAttack = r.attacks[i].def
			if m.modCD[i] > 0 || !phaseAllows(m, r, i) {
				i += 1
				continue
			}
			var ok: Bool = false
			switch a.kind {
			case .melee, .multiHit:
				ok = dx <= a.range + hw + 0.3 && dy <= max(1.8, m.b.h * 0.7 + 0.6)
			case .charge:
				ok = footing && dx >= 2.0 && dx <= max(4.0, a.range * 3.0) && dy < max(2.5, m.b.h)
			case .ranged:
				if dx <= a.range && dy <= a.range * 0.7 + 1.0 {
					if let f = foe {
						if seesFoe == nil { seesFoe = world.lineClear(m.b.x, shotY(m), f.b.x, f.b.cy) }
						ok = seesFoe ?? false
					} else {
						ok = m.sees
					}
				}
			case .area:
				ok = sqrt(dx * dx + dy * dy) <= a.radius + hw
			case .jump:
				ok = footing && dx >= 1.5 && dx <= max(5.0, a.range * 3.0) && dy < 6.0
			case .stomp:
				ok = footing && dx <= max(a.radius * 1.5, a.range + 3.0) && dy < max(2.5, m.b.h)
			}
			if ok { opts.append(i) }
			i += 1
		}
		if opts.isEmpty { return nil }
		if opts.count > 1, let k = opts.firstIndex(of: m.lastAtk) { opts.remove(at: k) }
		return opts[Int.random(in: 0..<opts.count)]
	}

	/// Begins an attack: it turns to the target, starts the attack's cooldown and shows the warning
	func startCustomAttack(_ m: Mob, _ r: ModMobRT, _ i: Int, _ tx: Double, _ ty: Double, _ foe: Mob?) {
		let a: ModAttack = r.attacks[i].def
		m.atk = i
		m.lastAtk = i
		m.modCD[i] = max(0.2, a.cooldown * m.phaseCD)
		m.st = 3
		m.t3 = max(0, a.windup)
		m.atkX = tx
		m.atkY = ty
		m.vsPlayer = foe == nil
		m.dir = tx >= m.b.x ? 1 : -1
		m.atkKey = newID()
		// short wind-ups go unannounced (a warning every fraction of a second would be noise)
		if a.windup >= 0.25 { warnCustomAttack(m, a) }
	}

	/// The red (or orange) box where an attack is about to land
	func warnCustomAttack(_ m: Mob, _ a: ModAttack) {
		let dirD: Double = Double(m.dir)
		let hw: Double = m.b.w * 0.5
		switch a.kind {
		case .melee, .multiHit:
			let reach: Double = a.range + hw + 0.3
			if a.aim == .around {
				warn(m.b.x - reach, m.b.top - 0.3, m.b.x + reach, m.b.y, a.windup)
			} else {
				warn(m.b.x, m.b.top - 0.3, m.b.x + dirD * reach, m.b.y, a.windup)
			}
		case .charge:
			let len: Double = max(4.0, a.range * 3.0) + hw
			warn(m.b.x, m.b.top, m.b.x + dirD * len, m.b.y, a.windup, 0xFFB030)
		case .area:
			let rr: Double = a.radius + hw
			warn(m.b.x - rr, m.b.cy - rr, m.b.x + rr, m.b.cy + rr, a.windup)
		case .stomp:
			let len: Double = max(a.radius * 1.5, a.range + 3.0)
			warn(m.b.x - len, m.b.y - 1.2, m.b.x + len, m.b.y, a.windup, 0xFF8A2A)
		case .jump:
			let rr: Double = max(1.4, hw + 0.9)
			warn(m.atkX - rr, m.atkY - 1.2, m.atkX + rr, m.atkY + 1.2, a.windup)
		case .ranged:
			break
		}
	}

	/// Where the target of the attack under way is now (the player, or the creature it fights)
	func customTargetNow(_ m: Mob) -> (Double, Double)? {
		if m.vsPlayer { return dead ? nil : (pb.x, pb.y - pb.h * 0.55) }
		if let f = m.foe, f.hp > 0 && !f.removed { return (f.b.x, f.b.cy) }
		return nil
	}

	/// Slows a creature that is winding up or recovering (a flyer or swimmer hangs where it is)
	func brakeCustom(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		if r.mdef.flying || (m.b.inWater && (r.aquatic || r.def.behavior.swim)) {
			let k: Double = max(0, 1.0 - dt * 6.0)
			m.b.vx *= k
			m.b.vy *= k
		} else {
			accelX(m, 0, 40, dt)
		}
	}

	/// The states of an attack: 3 the wind-up, 4 recovering, 5 charging, 6 a flurry, 7 a leap
	func stepCustomAttack(_ m: Mob, _ r: ModMobRT, _ dt: Double) {
		guard m.atk >= 0 && m.atk < r.attacks.count else {
			m.st = 0
			return
		}
		let ar: ModAttackRT = r.attacks[m.atk]
		let a: ModAttack = ar.def
		switch m.st {
		case 3:
			m.t3 -= dt
			brakeCustom(m, r, dt)
			if a.kind == .ranged, let p = customTargetNow(m) { m.dir = p.0 >= m.b.x ? 1 : -1 }
			if m.t3 <= 0 { releaseCustomAttack(m, r, ar) }
		case 4:
			m.t3 -= dt
			brakeCustom(m, r, dt)
			if m.t3 <= 0 {
				m.st = 0
				m.cd = 0.3
			}
		case 5:
			// a straight rush that hurts what it runs into (each thing once)
			m.t3 -= dt
			let cs: Double = max(8.0, r.mdef.speed * 3.2)
			m.b.vx = Double(m.dir) * cs
			if r.mdef.flying { m.b.vy += ((m.atkY - m.b.cy) * 2.0 - m.b.vy) * min(1.0, dt * 4.0) }
			var info = DamageInfo(amount: a.damage, type: .melee, source: .mob(m, faction(of: m)))
			info.dirX = Double(m.dir)
			info.knock = a.knock
			info.originX = m.b.x
			info.key = m.atkKey
			info.cooldown = 1.5
			damageBox(m.b.left - 0.2, m.b.top - 0.1, m.b.right + 0.2, m.b.y + 0.1, info)
			if Double.random(in: 0...1) < 0.4 { spawnParticles(m.b.x - Double(m.dir) * m.b.w * 0.5, m.b.y - 0.1, 0xA08860, 1, 1.5, 0.3, 6) }
			if m.b.hitWall {
				// into a wall: it reels for a moment, a chance to hit back
				addShake(abs(pb.x - m.b.x) < 12 ? 0.15 : 0.04)
				spawnParticles(m.b.x + Double(m.dir) * m.b.w * 0.5, m.b.cy, 0xC0B090, 8, 3.5, 0.4, 10)
				m.b.vx = -Double(m.dir) * 2.0
				m.daze = 0.8
				m.st = 4
				m.t3 = 0.2
			} else if m.t3 <= 0 {
				m.st = 4
				m.t3 = 0.35
			}
		case 6:
			// a flurry: a blow every 0.16 s
			m.t3 -= dt
			brakeCustom(m, r, dt)
			if m.t3 <= 0 {
				customBlow(m, a)
				m.phase -= 1
				m.t3 = 0.16
				if m.phase <= 0 {
					m.st = 4
					m.t3 = 0.3
				}
			}
		case 7:
			// in the air on a leap (or a flyer's dive): it comes down on the spot it went for
			m.t3 -= dt
			let landed: Bool = r.mdef.flying ? abs(m.b.x - m.atkX) < 0.8 && abs(m.b.cy - m.atkY) < 1.2 : (m.b.onGround && m.t3 < 1.85)
			if landed || m.t3 <= 0 || (r.mdef.flying && (m.b.hitWall || m.b.onGround)) {
				var info = DamageInfo(amount: a.damage, type: .stomp, source: .mob(m, faction(of: m)))
				info.knock = a.knock
				info.key = m.atkKey
				info.cooldown = 1.0
				info.originX = m.b.x
				let rr: Double = max(1.4, m.b.w * 0.5 + 0.9)
				damageArea(m.b.x, m.b.y - min(0.8, m.b.h * 0.5), radius: rr, info, falloff: false, lineOfSight: false)
				spawnParticles(m.b.x, m.b.y - 0.1, 0xA08860, 10, 4.0, 0.45, 14)
				addShake(abs(pb.x - m.b.x) < 12 ? 0.18 : 0.04)
				sfx(.land, at: m.b.x, 0.8)
				m.st = 4
				m.t3 = 0.35
			}
		default:
			m.st = 0
		}
	}

	/// The moment an attack lands (or sets off)
	func releaseCustomAttack(_ m: Mob, _ r: ModMobRT, _ ar: ModAttackRT) {
		let a: ModAttack = ar.def
		// shots and leaps aim at where the target is now; blows land where the warning showed
		if a.kind == .ranged || a.kind == .jump, let p = customTargetNow(m) {
			m.atkX = p.0
			m.atkY = p.1
		}
		m.atkT = Mob.atkDur
		switch a.kind {
		case .melee:
			customBlow(m, a)
			m.st = 4
			m.t3 = 0.25
		case .multiHit:
			m.phase = max(1, a.hits)
			m.st = 6
			m.t3 = 0
		case .charge:
			let cs: Double = max(8.0, r.mdef.speed * 3.2)
			m.st = 5
			m.t3 = clampD((max(4.0, a.range * 3.0) + m.b.w * 0.5) / cs, 0.3, 2.0)
			sfx(.roar, at: m.b.x, 0.5)
		case .ranged:
			fireCustomShots(m, r, ar)
			m.st = 4
			m.t3 = 0.25
		case .area:
			var info = DamageInfo(amount: a.damage, type: .impact, source: .mob(m, faction(of: m)))
			info.knock = a.knock
			info.key = m.atkKey
			info.cooldown = 1.0
			damageArea(m.b.x, m.b.cy, radius: a.radius + m.b.w * 0.5, info, falloff: false, lineOfSight: true)
			spawnParticles(m.b.x, m.b.cy, 0xFFD070, 18, 6.5, 0.45, 0)
			addShake(abs(pb.x - m.b.x) < 14 ? 0.2 : 0.05)
			sfx(.explosion, at: m.b.x, 0.5)
			m.st = 4
			m.t3 = 0.35
		case .jump:
			if r.mdef.flying {
				// a flyer dives at the target instead
				let dx: Double = m.atkX - m.b.x
				let dy: Double = m.atkY - m.b.cy
				let len: Double = max(0.001, sqrt(dx * dx + dy * dy))
				let sp: Double = max(9.0, r.mdef.speed * 3.0)
				m.b.vx = dx / len * sp
				m.b.vy = dy / len * sp
				m.t3 = clampD(len / sp + 0.25, 0.3, 1.6)
			} else {
				let vy: Double = -max(10.0, r.mdef.jump * 1.1)
				let flight: Double = max(0.3, 2.0 * abs(vy) / gravityG)
				m.b.vy = vy
				m.b.vx = clampD((m.atkX - m.b.x) / flight, -14, 14)
				m.t3 = 2.0
			}
			m.st = 7
		case .stomp:
			var info = DamageInfo(amount: a.damage, type: .stomp, source: .mob(m, faction(of: m)))
			info.knock = a.knock
			info.key = m.atkKey
			info.cooldown = 1.0
			info.originX = m.b.x
			damageArea(m.b.x, m.b.y - 0.4, radius: a.radius + m.b.w * 0.5, info, falloff: true, lineOfSight: false)
			// shockwaves run along the ground: both ways, or only forward
			let len: Double = max(a.radius * 1.5, a.range + 3.0)
			let sp: Double = 12.0
			let dirs: [Double] = a.aim == .forward ? [Double(m.dir)] : [-1.0, 1.0]
			for sgn in dirs where projectiles.count < 400 {
				var p = Projectile(kind: .shock, x: m.b.x + sgn * (m.b.w * 0.5), y: m.b.y - 0.5, vx: sgn * sp, vy: 0, dmg: a.damage * 0.8, fromPlayer: false, gravity: 0)
				p.life = len / sp
				p.w = 0.6
				p.owner = m.id
				p.source = .mob(m, faction(of: m))
				p.uid = newID()
				projectiles.append(p)
			}
			addShake(abs(pb.x - m.b.x) < 16 ? 0.35 : 0.08)
			spawnParticles(m.b.x, m.b.y - 0.1, 0xA08860, 16, 6.0, 0.55, 12)
			sfx(.land, at: m.b.x, 1.0)
			m.st = 4
			m.t3 = 0.4
		}
	}

	/// A melee blow over the box the warning showed
	func customBlow(_ m: Mob, _ a: ModAttack) {
		let hw: Double = m.b.w * 0.5
		let reach: Double = a.range + hw + 0.3
		let top: Double = m.b.top - 0.3
		let bottom: Double = m.b.y + 0.1
		m.atkT = Mob.atkDur
		switch a.aim {
		case .around:
			mobAttackBox(m, m.b.x - reach, top, m.b.x + reach, bottom, dmg: a.damage, knock: a.knock)
		case .down:
			mobAttackBox(m, m.b.x - hw - 0.3, m.b.cy, m.b.x + hw + 0.3, m.b.y + reach, dmg: a.damage, knock: a.knock)
		default:
			mobAttackBox(m, m.b.x - Double(m.dir) * 0.3, top, m.b.x + Double(m.dir) * reach, bottom, dmg: a.damage, knock: a.knock)
		}
		sfx(.swing, at: m.b.x, 0.5)
	}

	/// Shots of a custom creature's ranged attack: one aimed or straight ahead, a ring, or one dropped
	/// straight down. Custom shots behave as their maker set them up.
	func fireCustomShots(_ m: Mob, _ r: ModMobRT, _ ar: ModAttackRT) {
		let a: ModAttack = ar.def
		var live: Int = 0
		for p in projectiles where p.mod >= 0 || p.owner >= 0 { live += 1 }
		if live >= ModLimits.maxShotsLive { return }
		let ox: Double = m.b.x + Double(m.dir) * (m.b.w * 0.5 + 0.1)
		let oy: Double = r.mdef.flying ? m.b.cy : shotY(m)
		let speed: Double = max(4.0, a.speed)
		var grav: Double = 0
		var life: Double = clampD(a.range / speed * 1.5 + 0.2, 0.3, 6.0)
		var kind: ProjKind = .bullet
		if ModGameShots.kinds.contains(a.shot), let k = ProjKind(rawValue: a.shot) { kind = k }
		var w: Double = 0.3
		var pierce: Int = 0
		var modIdx: Int = -1
		if ar.shot >= 0 && ar.shot < ModRuntime.shared.shots.count {
			let s: ModProjectile = ModRuntime.shared.shots[ar.shot]
			grav = s.gravity
			life = s.life
			kind = .spit
			w = s.size
			pierce = s.pierce
			modIdx = ar.shot
		} else {
			switch kind {
			case .arrow, .quarrel: grav = 15
			case .rock: grav = 22; w = 0.6
			case .pebble: grav = 12
			default: grav = 0
			}
		}
		var angles: [Double] = []
		switch a.aim {
		case .forward:
			angles = [m.dir > 0 ? 0 : Double.pi]
		case .atTarget:
			angles = [lobAngle(m.atkX - ox, m.atkY - oy, speed, grav)]
		case .around:
			let n: Int = clampI(a.hits, 3, 12)
			for k in 0..<n { angles.append(Double(k) / Double(n) * 2.0 * Double.pi) }
		case .down:
			angles = [Double.pi * 0.5]
		}
		for ang in angles {
			if live >= ModLimits.maxShotsLive { break }
			var p = Projectile(kind: kind, x: ox, y: oy, vx: cos(ang) * speed, vy: sin(ang) * speed, dmg: a.damage, fromPlayer: false, gravity: grav)
			p.life = life
			p.owner = m.id
			p.source = .mob(m, faction(of: m))
			p.uid = newID()
			p.knock = a.knock
			p.w = w
			p.pierce = pierce
			p.mod = modIdx
			projectiles.append(p)
			live += 1
		}
		spawnParticles(ox, oy, kind == .fireball ? 0xFF7020 : 0xFFE080, 3, 2.0, 0.18, 0)
		switch kind {
		case .arrow, .quarrel: sfx(.bow, at: m.b.x, 0.5)
		case .bullet, .pellet: sfx(.gun, at: m.b.x, 0.5)
		case .rock, .pebble: sfx(.sling, at: m.b.x, 0.5)
		default: sfx(.zap, at: m.b.x, 0.45)
		}
	}

	/// A custom creature's drops and its loot table, when it dies
	func dropModLoot(_ m: Mob, _ rng: inout RNG) {
		guard let r = ModRuntime.shared.mob(m.cslot) else { return }
		for d in r.drops {
			if rng.double() >= d.chance { continue }
			let lo: Int = max(1, d.min)
			let n: Int = lo + rng.int(max(1, d.max - lo + 1))
			spawnDrop(Stack(item: d.item, count: n), m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2...2), -4.5)
		}
		if !r.loot.isEmpty {
			for s in ModRuntime.shared.roll(r.loot, &rng) {
				spawnDrop(s, m.b.x, m.b.y - m.b.h * 0.5, Double.random(in: -2.5...2.5), -5.0)
			}
		}
		if r.boss {
			say(joinText(r.def.name, " is defeated!"), 3.0)
			sfx(.discovery, 0.8)
		}
	}
}

// MARK: - The mods a world uses, turned into game content

/// Which mods a world was made with, and which tile number each of their blocks has in it. Saved with
/// the world, so its blocks keep their numbers whatever else is installed.
struct ModWorldInfo: Codable, Equatable {
	var mods: [ModDep] = []
	/// block key ("mod:id", or "mod:id#alt" for a door's open or a lamp's lit state) -> tile number
	var blocks: [String: Int] = [:]
	/// custom infusion key -> its number on items
	var infusions: [String: Int] = [:]
	/// custom dimension key -> its slot (0 to 2)
	var dims: [String: Int] = [:]

	init() {}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		var skip: Int = 0
		mods = c.list(.mods, &skip)
		blocks = c.val(.blocks, [:])
		infusions = c.val(.infusions, [:])
		dims = c.val(.dims, [:])
	}
}

/// A mod a world depends on
struct ModDep: Codable, Equatable, Identifiable {
	var id: String
	var name: String
	var author: String
	var version: String
}

/// A custom item ready to use: its checked definition plus everything worked out once
final class ModItemRT {
	let key: String
	let def: ModItem
	let modName: String
	var melee: MeleeProfile
	var ammo: Item? = nil
	/// index into ModRuntime.shots, or -1 for a game shot
	var shot: Int = -1
	var icon: PixelBuf

	init(key: String, def: ModItem, modName: String) {
		self.key = key
		self.def = def
		self.modName = modName
		let st: SwingStyle = SwingStyle(rawValue: def.style) ?? .slash
		var p = MeleeProfile(damage: def.damage, cooldown: def.cooldown, reach: def.reach, halfArc: def.arc, style: st)
		p.band = 0.55
		p.maxHits = def.maxHits
		p.knock = def.knock
		p.heavy = def.heavy
		p.daze = def.daze
		p.windup = def.windup
		p.swingTime = clampD(def.cooldown * 0.6, 0.14, 0.5)
		p.moveScale = def.heavy ? 0.6 : 1.0
		p.critChance = def.crit
		p.burn = def.burn
		p.undeadMult = def.undeadMult
		p.combo = def.combo
		p.backstab = def.backstab
		p.trail = def.trail
		if def.kind != .melee && def.kind != .tool {
			// bows, guns and the rest only bash when swung
			p = MeleeProfile(damage: 2.0, cooldown: 0.4, reach: 1.9, halfArc: 0.7, style: .bash, knock: 4, swingTime: 0.22, trail: 0xD0D0D0)
		}
		melee = p
		icon = PixelBuf(w: 16, h: 16)
	}
}

extension ModItemRT {
	/// where it sorts in the bag (weapons first, materials last), like the game's own items
	var sortGroup: Int {
		switch def.kind {
		case .melee: return 0
		case .bow, .gun, .thrown, .magic: return 1
		case .ammo: return 2
		case .tool: return 3
		case .armor: return 4
		case .food, .consumable: return 5
		case .special: return 6
		case .material: return 10
		}
	}

	/// Tooltip lines: what it is, its numbers, and which mod it comes from
	var infoLines: [String] {
		let d: ModItem = def
		var lines: [String] = [d.desc.isEmpty ? d.kind.name : d.desc]
		switch d.kind {
		case .melee:
			lines.append(String(format: "Damage %.1f · every %.2f s · reach %.1f", d.damage, d.cooldown, d.reach))
		case .bow, .gun, .thrown, .magic:
			var l: String = String(format: "Damage %.1f · every %.2f s", d.damage, d.cooldown)
			if d.kind == .gun { l += " · " + String(d.magazine) + " loaded" }
			lines.append(l)
			if let a = ammo { lines.append("Uses " + a.name) }
		case .tool:
			let tt: ToolType = ToolType(rawValue: d.toolType) ?? .pickaxe
			lines.append(tt.name + String(format: " · tier %d · speed x%.1f", d.toolTier, d.toolSpeed))
		case .armor:
			let sl: ArmorSlot = ArmorSlot(rawValue: d.slot) ?? .head
			lines.append(sl.name + String(format: " · defense +%.1f", d.defense))
		case .food, .consumable:
			var parts: [String] = []
			if d.hunger > 0 { parts.append(String(format: "+%.0f hunger", d.hunger)) }
			for e in d.effects { parts.append(e.kind.name) }
			if !parts.isEmpty { lines.append(parts.joined(separator: " · ")) }
		default:
			break
		}
		lines.append("From " + modName)
		return lines
	}
}

/// A resolved attack of a custom creature
struct ModAttackRT {
	var def: ModAttack
	var shot: Int
}

/// A custom creature ready to use
final class ModMobRT {
	let key: String
	let def: ModMob
	let modName: String
	var mdef: MobDef
	var base: MobKind
	var attacks: [ModAttackRT] = []
	var drops: [ModDrop] = []
	var loot: String = ""
	var faction: Faction = .hostile
	var boss: Bool = false
	/// kind it guards: a game creature, or a custom one (slot)
	var guardKind: MobKind? = nil
	var guardSlot: Int = -1

	init(key: String, def: ModMob, modName: String) {
		self.key = key
		self.def = def
		self.modName = modName
		let b: MobKind = MobKind(rawValue: def.base) ?? .zombie
		base = b
		let bd: MobDef = mobDef(b)
		var beh: Behavior = .hostile
		switch def.category {
		case .passive: beh = .passive
		case .neutral: beh = .defensive
		case .hostile: beh = .hostile
		case .boss: beh = .boss
		case .flying: beh = .flyer
		case .water: beh = .swimmer
		}
		// a creature that goes for the player unprovoked counts as a monster (limits, despawning, pets)
		let hostile: Bool = def.category == .hostile || def.category == .boss || (def.category != .passive && def.behavior.attackPlayer)
		let fly: Bool = def.behavior.fly || def.category == .flying
		mdef = MobDef(name: def.name, w: clampD(bd.w * def.scale, 0.3, 8), h: clampD(bd.h * def.scale, 0.3, 8), hp: def.hp, speed: def.speed,
						dmg: def.damage, behavior: beh, flying: fly, aggro: def.detect, jump: def.jump, hostile: hostile)
		boss = def.category == .boss
		// a guardian that fights monsters but never the player is on the player's side
		if boss { faction = .boss }
		else if hostile { faction = .hostile }
		else if def.behavior.attackMobs { faction = .ally }
		else { faction = .wild }
	}

	/// how far its attacks reach (across, up or down) and whether the longest is a shot (see think)
	var reach: (Double, Double, Bool) = (1.0, 1.4, false)
	/// creatures that live in water (they flop about on land)
	var aquatic: Bool { return def.category == .water }
	/// it can hurt something: it has attacks, or hurts by touch
	var canAttack: Bool { return !attacks.isEmpty || def.damage > 0 }
	/// it stays beside another kind of creature
	var guards: Bool { return guardSlot >= 0 || guardKind != nil }

	/// Works out what its attacks reach, once they are known
	func finish() {
		var across: Double = mdef.w * 0.5 + 0.5
		var up: Double = 1.4
		var shot: Bool = false
		for a in attacks {
			let d: ModAttack = a.def
			var r: Double = 0
			var h: Double = 1.4
			switch d.kind {
			case .ranged:
				if d.range > across || !shot {
					across = max(d.range, shot ? across : 0)
					up = d.range * 0.7 + 1.0
					shot = true
				}
				continue
			case .charge, .jump:
				r = max(4.0, d.range * 3.0)
				h = 2.5
			case .area, .stomp:
				r = d.radius + mdef.w * 0.5
				h = max(1.4, d.radius)
			case .melee, .multiHit:
				r = d.range + mdef.w * 0.5 + 0.3
				h = max(1.8, mdef.h * 0.7 + 0.6)
			}
			if !shot && r > across {
				across = r
				up = h
			}
		}
		reach = (across, up, shot)
	}

	/// Share of a hit of this kind that gets through its hide
	func resist(_ t: DamageType) -> Double {
		let tough: Double = 1.0 - clampD(def.defense, 0, 0.9)
		switch t {
		case .fire, .lava: return def.fireproof ? 0 : tough
		case .fall: return mdef.flying || aquatic ? 0 : tough
		case .drown: return aquatic || def.behavior.swim ? 0 : 1
		default: return tough
		}
	}
}

/// A custom ore, resolved to its tile
struct ModOreRT {
	var tile: Tile
	var dim: Int
	var minY: Int
	var maxY: Int
	var veins: Double
	var size: Int
	var host: Int
	var salt: UInt64
	var place: Int = 0
	var biomes: Set<Int> = []
	var rarity: Double = 1
	var shape: Int = 0
	var nearTile: Tile? = nil
	var hostTiles: Set<UInt8> = []
}

/// A custom structure with its cells turned into tile numbers (-1: leave the ground as it is)
struct ModStructRT {
	var key: String
	var def: ModStructure
	var cells: [Int]
	var salt: UInt64
	var loot: String
}

/// A custom creature's spawning, resolved
struct ModSpawnRT {
	var slot: Int
	var spawn: ModSpawn
}

final class ModRuntime {
	/// what the current world uses (empty in the menu and in worlds without mods)
	static var shared: ModRuntime = ModRuntime()

	var packs: [ModPack] = []
	var reports: [ModReport] = []
	/// mods the world needs that are not installed
	var missing: [ModDep] = []
	/// content left out by the checks, by key
	var disabled: Set<String> = []
	// blocks: per reserved slot (0 ..< blockSlots) its key, definition and art
	var slotKey: [String?] = [String?](repeating: nil, count: ModLimits.blockSlots)
	var slotDef: [ModBlock?] = [ModBlock?](repeating: nil, count: ModLimits.blockSlots)
	/// true for the second state of a door (open) or a lamp (lit)
	var slotAlt: [Bool] = [Bool](repeating: false, count: ModLimits.blockSlots)
	var slotArt: [PixelBuf?] = [PixelBuf?](repeating: nil, count: ModLimits.blockSlots)
	var slotDrop: [Stack?] = [Stack?](repeating: nil, count: ModLimits.blockSlots)
	var slotTool: [ToolType] = [ToolType](repeating: .pickaxe, count: ModLimits.blockSlots)
	/// a pass-through tree form of a solid block (for trees in custom dimensions): the block it stands
	/// for, and the part it plays (0 not a tree form, 1 trunk or branch, 2 leaves)
	var slotTreeBase: [Tile?] = [Tile?](repeating: nil, count: ModLimits.blockSlots)
	var slotTreeRole: [UInt8] = [UInt8](repeating: 0, count: ModLimits.blockSlots)
	/// mod blocks climbed like a ladder, and those that slow what moves through them
	var climbTiles: Set<UInt8> = []
	var stickyTiles: Set<UInt8> = []
	/// the mods' liquids by tile number (see p12c_fluids)
	var liquidDefs: [UInt8: LiquidDef] = [:]
	var tileForKey: [String: Tile] = [:]
	var items: [String: ModItemRT] = [:]
	var itemOrder: [String] = []
	var mobs: [ModMobRT] = []
	var mobSlot: [String: Int] = [:]
	var shots: [ModProjectile] = []
	var shotIndex: [String: Int] = [:]
	var loot: [String: ModLootTable] = [:]
	/// loot tables that also turn up in the world's chests
	var chestTables: [String] = []
	var recipes: [Recipe] = []
	var ores: [ModOreRT] = []
	var structures: [ModStructRT] = []
	var spawns: [ModSpawnRT] = []
	/// the custom creatures' spawning as rules beside the game's own (see updateSpawning)
	var spawnRules: [SpawnRule] = []
	/// names of missing mods by id (for "Missing block" labels)
	var missingNames: [String: String] = [:]
	/// custom infusions by their number on items, and the numbers by key
	var infusionDefs: [Int: ModInfusionRT] = [:]
	var infusionNumber: [String: Int] = [:]
	/// every way to summon a custom creature, ready for play
	var summons: [ModSummonRT] = []
	/// the Logic Studio scripts of the world's mods, compiled
	var logic: LogicRT = LogicRT()
	/// the world's three custom dimension slots, and the key each holds (kept for missing mods)
	var dimSlots: [ModDimRT?] = [nil, nil, nil]
	/// mods' suit materials and suit parts, by key
	var suitMats: [String: SuitMatInfo] = [:]
	var suitParts: [String: SuitPartInfo] = [:]
	/// the mods' whole suit designs, with their names (to start from at an Assembly Station)
	var suitDesigns: [(String, SuitDesign)] = []
	/// the Overworld's sun and moon as the mods draw them (the last mod that sets one wins)
	var overSun: ModSkyBody? = nil
	var overMoon: ModSkyBody? = nil
	var dimSlotKey: [String?] = [nil, nil, nil]
	/// the rules of the game as the mods set them (by GameRule number), what a new world starts with,
	/// the Overworld's weather and the screens' look as the last mod that sets them has them
	var rules: [Double] = GameRule.specs.map { $0.def }
	var startItems: [Stack] = []
	var weather: ModWeather? = nil
	var theme: ModTheme? = nil
	/// the mods' vehicles by key
	var vehicles: [String: ModVehicle] = [:]
	/// mod blocks that fall like sand, seats, beds, and those on power lines
	var fallTiles: Set<UInt8> = []
	var seatTiles: Set<UInt8> = []
	var bedTiles: Set<UInt8> = []
	var powerTiles: [UInt8: ModPowerRole] = [:]

	var active: Bool { return !packs.isEmpty || !missing.isEmpty }
	var hasWorldGen: Bool { return !ores.isEmpty || !structures.isEmpty }

	// MARK: switching mods on

	/// Builds the runtime for these mods (in load order) and installs it: tiles, recipes and art all
	/// change to match. `world` is the saved mapping of an existing world (nil for a new world).
	/// Nothing here can stop the game: broken content is left out and reported.
	@discardableResult
	static func activate(_ list: [ModPack], world: ModWorldInfo?) -> ModRuntime {
		let rt = ModRuntime()
		let known: [String: String] = ModCatalog.build(list).keys
		var seen: Set<String> = []
		for p0 in list {
			if rt.packs.count >= ModLimits.maxMods { break }
			if p0.id.isEmpty || seen.contains(p0.id) { continue }
			seen.insert(p0.id)
			var p: ModPack = p0
			let rep: ModReport = ModValidator.check(&p, known: known)
			rt.reports.append(rep)
			if rep.fatal { continue }
			rt.packs.append(p)
			for d in rep.disabled { rt.disabled.insert(p.key(d)) }
			// content the maker switched off for now
			for d in p.off { rt.disabled.insert(p.key(d)) }
		}
		// a mod that needs another that is not on: say so (what it uses from it is left out)
		for p in rt.packs {
			for dep in ModStore.dependencies(p) where !rt.packs.contains(where: { $0.id == dep }) {
				var dr = ModReport()
				let name: String = ModStore.pack(dep)?.name ?? dep
				dr.add(2, p.name, "Mod", joinText("Needs the mod \u{201C}", name, "\u{201D}, which is not on: what it uses from it is left out."))
				rt.reports.append(dr)
			}
		}
		if let w = world {
			for d in w.mods where !rt.packs.contains(where: { $0.id == d.id }) {
				rt.missing.append(d)
				rt.missingNames[d.id] = d.name
			}
		}
		rt.assignBlocks(world)
		rt.buildShots()
		rt.buildItems()
		rt.buildSuits()
		rt.buildInfusions(world)
		rt.buildLoot()
		rt.buildMobs()
		rt.buildSummons()
		rt.buildDims(world)
		rt.buildWorldRules()
		for p in rt.packs {
			if let b = p.skySun { rt.overSun = b }
			if let b = p.skyMoon { rt.overMoon = b }
		}
		rt.logic = LogicRT.build(rt.packs, rt.disabled)
		rt.buildRecipes()
		rt.buildOres()
		rt.buildStructures()
		OverrideRT.shared = OverrideRT.build(rt.packs, rt.disabled)
		shared = rt
		rt.install()
		return rt
	}

	/// Back to no mods (the menu, a world without mods)
	static func deactivate() {
		activate([], world: nil)
	}

	/// Every issue of every active mod
	var issues: [ModIssue] {
		var out: [ModIssue] = []
		for r in reports { out.append(contentsOf: r.issues) }
		return out
	}

	/// What a world made now should remember
	func worldInfo() -> ModWorldInfo {
		var w = ModWorldInfo()
		for p in packs { w.mods.append(ModDep(id: p.id, name: p.name, author: p.author, version: p.version)) }
		for d in missing { w.mods.append(d) }
		for i in 0..<ModLimits.blockSlots {
			if let k = slotKey[i] { w.blocks[k] = Int(Tile.modBase) + i }
		}
		for (k, n) in infusionNumber { w.infusions[k] = n }
		for i in 0..<dimSlotKey.count { if let k = dimSlotKey[i] { w.dims[k] = i } }
		return w
	}

	// MARK: blocks

	func assignBlocks(_ world: ModWorldInfo?) {
		// the keys each mod block needs: one, or two for doors and lamps
		var wanted: [(String, ModBlock, Bool)] = []
		for p in packs {
			for b in p.blocks where !disabled.contains(p.key(b.id)) {
				wanted.append((p.key(b.id), b, false))
				if b.function.paired { wanted.append((p.key(b.id) + "#alt", b, true)) }
			}
		}
		var taken: [Bool] = [Bool](repeating: false, count: ModLimits.blockSlots)
		let base: Int = Int(Tile.modBase)
		// first the numbers the world already gave them (and the slots of blocks that are missing now)
		if let w = world {
			for (k, raw) in w.blocks {
				let i: Int = raw - base
				if i < 0 || i >= ModLimits.blockSlots || taken[i] { continue }
				taken[i] = true
				slotKey[i] = k
			}
		}
		var free: Int = 0
		var overflow: Int = 0
		for (k, b, alt) in wanted {
			var i: Int = -1
			if let found = slotKey.firstIndex(where: { $0 == k }) { i = found }
			if i < 0 {
				while free < ModLimits.blockSlots && taken[free] { free += 1 }
				if free >= ModLimits.blockSlots {
					overflow += 1
					continue
				}
				i = free
				taken[i] = true
				slotKey[i] = k
			}
			slotDef[i] = b
			slotAlt[i] = alt
			slotTool[i] = ToolType(rawValue: b.tool) ?? .pickaxe
			if let t = Tile(rawValue: UInt8(base + i)) { tileForKey[k] = t }
		}
		// pass-through forms of the solid blocks trees in custom dimensions are made of (after every
		// block, so blocks keep the numbers they had). A world keeps the forms it has, even once its
		// mod no longer needs them, so the trees already grown there stay as they were.
		var forms: [(String, Tile, Int)] = treeFormsWanted()
		if let w = world {
			for k in w.blocks.keys.sorted() where (k.hasSuffix("#tree") || k.hasSuffix("#leaf")) && !forms.contains(where: { $0.0 == k }) {
				guard let bt = ModGround.resolve(String(k.dropLast(5)), self), bt != .air, !bt.liquid else { continue }
				if let bi = slot(bt), slotDef[bi] == nil { continue }
				forms.append((k, bt, k.hasSuffix("#leaf") ? 2 : 1))
			}
		}
		for (k, bt, role) in forms {
			var i: Int = -1
			if let found = slotKey.firstIndex(where: { $0 == k }) { i = found }
			if i < 0 {
				while free < ModLimits.blockSlots && taken[free] { free += 1 }
				if free >= ModLimits.blockSlots {
					overflow += 1
					continue
				}
				i = free
				taken[i] = true
				slotKey[i] = k
			}
			slotTreeBase[i] = bt
			slotTreeRole[i] = UInt8(role)
			if let bi = slot(bt), let b0 = slotDef[bi] {
				var b: ModBlock = b0
				b.function = .none
				b.vehRole = .none
				b.collision = role == 2 ? .platform : .none
				slotDef[i] = b
				slotTool[i] = slotTool[bi]
			} else {
				slotDef[i] = nil
				slotTool[i] = toolClass(bt)
			}
			if let t = Tile(rawValue: UInt8(base + i)) { tileForKey[k] = t }
		}
		if overflow > 0 {
			var rep = ModReport()
			rep.add(2, "Mods", "Blocks", String(overflow) + " custom blocks did not fit (a world holds " + String(ModLimits.blockSlots) + ") and were left out.")
			reports.append(rep)
		}
	}

	/// The tile of a block key (nil if it has none in this world)
	func tile(_ key: String) -> Tile? { return tileForKey[key] }

	/// The solid blocks the trees of the custom dimensions are made of, each with the part it plays
	/// (1 trunk or branch, 2 leaves): each gets a pass-through tree form, so no tree is a wall
	func treeFormsWanted() -> [(String, Tile, Int)] {
		var out: [(String, Tile, Int)] = []
		var seen: Set<String> = []
		func want(_ k: String, _ role: Int) {
			if k.isEmpty { return }
			let fk: String = k + (role == 2 ? "#leaf" : "#tree")
			if seen.contains(fk) { return }
			guard let t = ModGround.resolve(k, self), t != .air, !t.liquid, t.trunkForm == t else { return }
			if let i = slot(t) {
				guard let b = slotDef[i], b.collision == .solid, !slotAlt[i] else { return }
			} else if !t.solid {
				return
			}
			seen.insert(fk)
			out.append((fk, t, role))
		}
		for p in packs {
			for d in p.dims where !disabled.contains(p.key(d.id)) {
				for z in d.zones {
					want(z.log, 1)
					want(z.leaves, 2)
					for tid in z.treeKinds {
						guard let tr = p.trees.first(where: { $0.id == tid }), !disabled.contains(p.key(tid)) else { continue }
						want(tr.trunk, 1)
						want(tr.branch, 1)
						want(tr.leaves, 2)
					}
				}
			}
		}
		return out
	}

	/// The part a tile plays as a tree form: 1 trunk or branch, 2 leaves, 0 not a tree form
	func treeRole(_ t: Tile) -> UInt8 {
		guard let i = slot(t) else { return 0 }
		return slotTreeRole[i]
	}

	/// The tile a tree is made of for a block key: the block's pass-through tree form when it is solid
	/// (role 1 trunk or branch, 2 leaves), the tree trunk of a log block, or the block itself
	func treeTile(_ key: String, _ role: Int) -> Tile? {
		if let t = tileForKey[key + (role == 2 ? "#leaf" : "#tree")] { return t }
		guard let t = ModGround.resolve(key, self) else { return nil }
		return t.trunkForm
	}

	/// Slot index of a tile (nil for game tiles)
	@inline(__always) func slot(_ t: Tile) -> Int? {
		let i: Int = Int(t.rawValue) - Int(Tile.modBase)
		return i >= 0 && i < ModLimits.blockSlots ? i : nil
	}

	func blockDef(_ t: Tile) -> ModBlock? {
		guard let i = slot(t) else { return nil }
		return slotDef[i]
	}

	/// The mod shot a mod's gun block fires (its number among the shots; -1: the game's own)
	func blockShot(_ t: Tile) -> Int {
		guard let i = slot(t), let k = slotKey[i], let d = slotDef[i], !d.shot.isEmpty else { return -1 }
		let modID: String = String(k.split(separator: ":").first ?? "")
		return shotIndex[joinText(modID, ":", d.shot)] ?? -1
	}

	func isAlt(_ t: Tile) -> Bool {
		guard let i = slot(t) else { return false }
		return slotAlt[i]
	}

	/// The other state of a door or lamp tile
	func partner(_ t: Tile) -> Tile? {
		guard let i = slot(t), let k = slotKey[i] else { return nil }
		if slotAlt[i] { return tileForKey[String(k.dropLast(4))] }
		return tileForKey[k + "#alt"]
	}

	/// A game item for a mod reference: blocks become their tile, items stay custom
	func resolve(_ it: Item) -> Item {
		if case .custom(let k) = it, let t = tileForKey[k] { return .block(t) }
		return it
	}

	/// The tile definition the game uses for a slot
	func tileDef(_ i: Int) -> TileDef {
		if slotTreeRole[i] != 0, let bt = slotTreeBase[i] {
			// a tree form: the block it stands for, passed through (leaves can be stood on, as the game's)
			var d: TileDef = Tile.makeDef(bt)
			if let bi = slot(bt) { d = tileDef(bi) }
			d.solid = false
			d.opaque = false
			d.platform = slotTreeRole[i] == 2
			d.plant = false
			d.hurt = false
			d.liquid = false
			d.drop = nil
			d.noDrop = false
			return d
		}
		guard let b = slotDef[i] else {
			var d = TileDef(name: missingLabel(i))
			d.hard = 9999
			d.style = .custom
			d.colors = [0xFF00FF, 0x200020, 0xFF00FF, 0x200020, 0xFF00FF]
			d.noDrop = true
			return d
		}
		let alt: Bool = slotAlt[i]
		var d = TileDef(name: b.name)
		d.hard = b.unbreakable ? 9999 : b.hardness
		d.tier = b.tier
		d.solid = b.collision == .solid
		d.platform = b.collision == .platform
		d.plant = b.collision == .decor
		d.liquid = b.collision == .liquid
		d.opaque = d.solid && !b.transparent
		d.light = b.light
		d.hurt = b.function == .trap
		d.style = .custom
		if b.function == .door && alt {
			d.solid = false
			d.opaque = false
		}
		if b.function == .lamp {
			d.light = alt ? max(b.light, 12) : 0
		}
		let art: PixelBuf = b.art.buf()
		d.colors = [averageColor(art), averageColor(art), averageColor(art), averageColor(art), averageColor(art)]
		d.noDrop = !b.dropSelf && b.drop == nil
		if alt { d.drop = .block(tileForKey[String((slotKey[i] ?? "").dropLast(4))] ?? .stone) }
		return d
	}

	func missingLabel(_ i: Int) -> String {
		guard let k = slotKey[i] else { return "Unused Mod Block" }
		let m: String = splitModKey(k).0
		return "Missing block (" + (missingNames[m] ?? "a mod") + ")"
	}

	/// What breaking a custom block drops (nil: the game's usual rule)
	func blockDrops(_ t: Tile) -> [Stack]? {
		guard let i = slot(t) else { return nil }
		if slotTreeRole[i] != 0 {
			// a tree form gives what the block it stands for gives
			guard let bt = slotTreeBase[i] else { return [] }
			if slot(bt) != nil { return blockDrops(bt) ?? [] }
			let bd: TileDef = Tile.makeDef(bt)
			if bd.noDrop { return [] }
			return [Stack(item: bd.drop ?? .block(bt), count: 1)]
		}
		guard let b = slotDef[i] else { return [] }
		if slotAlt[i] {
			if let main = partner(t) { return [Stack(item: .block(main), count: 1)] }
			return []
		}
		if b.dropSelf { return [Stack(item: .block(t), count: max(1, b.dropCount))] }
		if let d = b.drop { return [Stack(item: resolve(d), count: max(1, b.dropCount))] }
		return []
	}

	// MARK: items

	func buildItems() {
		for p in packs {
			for it in p.items where !disabled.contains(p.key(it.id)) {
				let k: String = p.key(it.id)
				let r = ModItemRT(key: k, def: it, modName: p.name)
				if let a = it.ammo { r.ammo = resolve(a) }
				if !it.projectile.isEmpty { r.shot = shotIndex[p.key(it.projectile)] ?? -1 }
				r.icon = itemIconBuf(it)
				items[k] = r
				itemOrder.append(k)
			}
			// a suit part is an item too
			for sp in p.suitParts where !disabled.contains(p.key(sp.id)) {
				let k: String = p.key(sp.id)
				let it: ModItem = suitPartItem(p, sp)
				let r = ModItemRT(key: k, def: it, modName: p.name)
				r.icon = itemIconBuf(it)
				items[k] = r
				itemOrder.append(k)
			}
			// a vehicle's kit is an item too
			for v in p.vehicles where !disabled.contains(p.key(v.id)) {
				let k: String = p.key(v.id)
				let it: ModItem = vehicleItem(p, v)
				let r = ModItemRT(key: k, def: it, modName: p.name)
				r.icon = itemIconBuf(it)
				items[k] = r
				itemOrder.append(k)
			}
		}
	}

	func item(_ key: String) -> ModItemRT? { return items[key] }

	/// The icon of a custom item: its own picture, or the chosen game item's icon tinted
	func itemIconBuf(_ it: ModItem) -> PixelBuf {
		if !it.icon.isBlank {
			var b: PixelBuf = it.icon.buf()
			b = padBuf(b)
			if it.icon.outlined(true) { b.outline(0x1A1410) }
			return b
		}
		if let base = it.baseIcon {
			var b: PixelBuf = itemBuf(resolve(base))
			if it.tintAmt > 0.01 { b = b.tinted(it.tint & 0xFFFFFF, it.tintAmt) }
			return b
		}
		var b = PixelBuf(w: 12, h: 12)
		b.rect(2, 2, 8, 8, 0x9A8A70)
		b.rect(4, 4, 4, 4, 0xC8B898)
		b.outline(0x1A1410)
		return b
	}

	// MARK: shots, loot, creatures, recipes, ores, structures

	func buildShots() {
		for p in packs {
			for s in p.projectiles {
				shotIndex[p.key(s.id)] = shots.count
				shots.append(s)
			}
		}
	}

	func buildLoot() {
		for p in packs {
			for l0 in p.loot where !disabled.contains(p.key(l0.id)) {
				var l: ModLootTable = l0
				for k in l.entries.indices { l.entries[k].item = resolve(l.entries[k].item) }
				loot[p.key(l.id)] = l
				if l.chestChance > 0 { chestTables.append(p.key(l.id)) }
			}
		}
	}

	/// A chest's contents with the world's mods: the tables set to turn up in chests each get their
	/// chance, rolled from the chest's position (the same chest always holds the same), up to a full chest
	func addChestLoot(_ base: [Stack], _ g: WorldGen, _ dim: Dimension, _ x: Int, _ y: Int) -> [Stack] {
		var out: [Stack] = base
		for key in chestTables {
			guard let l = loot[key] else { continue }
			let salt: UInt64 = UInt64(truncatingIfNeeded: modChecksum(Data(key.utf8)))
			var rng = RNG(hashU(x, y &+ dim.rawValue &* 7_919, g.seed &+ salt))
			if rng.double() >= l.chestChance { continue }
			for st in roll(key, &rng) where out.count < 27 { out.append(st) }
		}
		return out
	}

	/// Rolls a loot table: each roll picks one entry (or nothing) by weight
	func roll(_ key: String, _ rng: inout RNG) -> [Stack] {
		guard let l = loot[key] else { return [] }
		let total: Double = l.totalWeight
		if total <= 0 { return [] }
		var out: [Stack] = []
		for _ in 0..<l.rolls {
			var r: Double = rng.double() * total
			r -= max(0, l.nothing)
			if r < 0 { continue }
			for e in l.entries {
				r -= max(0, e.effectiveWeight)
				if r < 0 {
					let n: Int = e.min + rng.int(max(1, e.max - e.min + 1))
					out.append(Stack(item: e.item, count: max(1, n)))
					break
				}
			}
		}
		return out
	}

	func buildMobs() {
		for p in packs {
			for m in p.mobs where !disabled.contains(p.key(m.id)) {
				let k: String = p.key(m.id)
				let r = ModMobRT(key: k, def: m, modName: p.name)
				for a in m.attacks {
					let si: Int = a.projectile.isEmpty ? -1 : (shotIndex[p.key(a.projectile)] ?? -1)
					r.attacks.append(ModAttackRT(def: a, shot: si))
				}
				for d0 in m.drops {
					var d: ModDrop = d0
					d.item = resolve(d.item)
					r.drops.append(d)
				}
				if !m.loot.isEmpty && loot[p.key(m.loot)] != nil { r.loot = p.key(m.loot) }
				mobSlot[k] = mobs.count
				mobs.append(r)
				if m.spawn.enabled { spawns.append(ModSpawnRT(slot: mobs.count - 1, spawn: m.spawn)) }
			}
		}
		// who guards whom (custom kinds are known only now)
		for r in mobs where !r.def.behavior.guardKey.isEmpty {
			let gk: String = r.def.behavior.guardKey
			if let s = mobSlot[gk] { r.guardSlot = s } else { r.guardKind = MobKind.allCases.first { mobDef($0).name == gk } }
		}
		for r in mobs { r.finish() }
		buildSpawnRules()
	}

	/// Turns each custom creature's spawning settings into a rule the game's spawner understands
	func buildSpawnRules() {
		spawnRules = []
		for s in spawns {
			guard let r = mob(s.slot) else { continue }
			let sp: ModSpawn = s.spawn
			var place: SpawnPlace = .surface
			switch sp.place {
			case .surface, .sky: place = .surface
			case .cave: place = .cave
			case .ocean: place = .ocean
			case .umbral: place = .umbral
			}
			let when: SpawnWhen = sp.when == 1 ? .day : (sp.when == 2 ? .night : .any)
			var biomes: [Biome] = []
			for b in sp.biomes {
				if let bb = Biome(rawValue: b) { biomes.append(bb) }
			}
			var rule = SpawnRule(kind: .custom, weight: max(0, sp.weight), place: place, when: when, biomes: biomes, group: max(1, sp.group), minY: sp.minY, maxY: sp.maxY)
			rule.slot = s.slot
			rule.maxNearby = max(1, sp.maxNearby)
			rule.sky = sp.place == .sky && r.mdef.flying
			if rule.weight > 0 { spawnRules.append(rule) }
		}
	}

	func mob(_ slot: Int) -> ModMobRT? { return slot >= 0 && slot < mobs.count ? mobs[slot] : nil }

	func buildRecipes() {
		var list: [Recipe] = []
		var nextID: Int = RecipeBook.base.count
		for p in packs {
			for r in p.recipes where !disabled.contains(p.key(r.id)) {
				let out: Item = resolve(r.out)
				var lines: [CostLine] = []
				for c in r.cost { lines.append(CostLine(item: resolve(c.item), n: c.n)) }
				let st: Station = Station(rawValue: max(0, r.station)) ?? .hand
				var rec = Recipe(id: nextID, out: out, outCount: r.count, cost: lines, station: r.station < 0 ? .hand : st, cat: RecipeCat(rawValue: r.cat) ?? .mods)
				if r.station < 0 { rec.modStation = tileForKey[p.key(r.stationBlock)] }
				list.append(rec)
				nextID += 1
			}
		}
		recipes = list
	}

	func buildOres() {
		var skipped: Int = 0
		defer { capNote(skipped, "ores", ModLimits.maxWorldOres) }
		for p in packs {
			for o in p.ores where !disabled.contains(p.key(o.id)) {
				guard let t = tileForKey[p.key(o.block)] else { continue }
				if ores.count >= ModLimits.maxWorldOres {
					skipped += 1
					continue
				}
				let salt: UInt64 = UInt64(truncatingIfNeeded: modChecksum(Data((p.id + o.id).utf8)))
				var hostTiles: Set<UInt8> = []
				for k in o.hosts { if let h = ModGround.resolve(k, self) { hostTiles.insert(h.rawValue) } }
				let near: Tile? = o.near.isEmpty ? nil : ModGround.resolve(o.near, self)
				let od: Int = dimNumber(o.dim, o.dimKey.isEmpty ? "" : p.key(o.dimKey))
				if od < 0 { continue }
				ores.append(ModOreRT(tile: t, dim: od, minY: o.minY, maxY: o.maxY, veins: o.veins, size: o.size, host: o.host, salt: salt,
									 place: o.place, biomes: Set(o.biomes), rarity: o.rarity, shape: o.shape, nearTile: near, hostTiles: hostTiles))
			}
		}
	}

	/// A note when the world's mods together have more ores or structures than one world makes
	func capNote(_ skipped: Int, _ what: String, _ cap: Int) {
		if skipped <= 0 { return }
		var rep = ModReport()
		rep.add(1, "Mods", "World", joinText(String(skipped), " ", what, " were left out: a world makes at most ", String(cap), " (from all its mods together)."))
		reports.append(rep)
	}

	func buildStructures() {
		var skipped: Int = 0
		defer { capNote(skipped, "structures", ModLimits.maxWorldStructures) }
		for p in packs {
			for s in p.structures where !disabled.contains(p.key(s.id)) {
				if structures.count >= ModLimits.maxWorldStructures {
					skipped += 1
					continue
				}
				var cells: [Int] = []
				cells.reserveCapacity(s.cells.count)
				for v in s.cells {
					if v >= 1000 {
						let pi: Int = v - 1000
						let k: String = pi < s.palette.count ? s.palette[pi] : ""
						if let t = tileForKey[k] { cells.append(Int(t.rawValue)) } else { cells.append(-1) }
					} else {
						cells.append(v)
					}
				}
				let salt: UInt64 = UInt64(truncatingIfNeeded: modChecksum(Data((p.id + s.id).utf8)))
				var sd: ModStructure = s
				sd.dim = dimNumber(s.dim, s.dimKey.isEmpty ? "" : p.key(s.dimKey))
				if sd.dim < 0 { continue }
				structures.append(ModStructRT(key: p.key(s.id), def: sd, cells: cells, salt: salt, loot: s.loot.isEmpty ? "" : p.key(s.loot)))
			}
		}
	}

	// MARK: installing

	/// Puts this runtime's blocks into the tile tables and art, and its recipes into the recipe book
	func install() {
		let base: Int = Int(Tile.modBase)
		climbTiles = []
		stickyTiles = []
		liquidDefs = [:]
		for i in 0..<ModLimits.blockSlots {
			guard let t = Tile(rawValue: UInt8(base + i)) else { continue }
			slotArt[i] = slotArtBuf(i)
			Tile.patch(t, tileDef(i), tool: slotTool[i])
			Liquids.hotTable[Int(t.rawValue)] = false
			if let b = slotDef[i], slotTreeRole[i] == 0 {
				if b.collision == .climbable { climbTiles.insert(t.rawValue) }
				if b.collision == .sticky { stickyTiles.insert(t.rawValue) }
				if b.collision == .liquid {
					liquidDefs[t.rawValue] = modLiquid(b, t, slotArt[i] ?? PixelBuf(w: 8, h: 8))
					Liquids.hotTable[Int(t.rawValue)] = b.liqHot
				}
			}
			if let b = slotDef[i], !slotAlt[i], !b.dropSelf, let d = b.drop {
				slotDrop[i] = Stack(item: resolve(d), count: b.dropCount)
			}
		}
		RecipeBook.all = RecipeBook.base + recipes
		OverrideRT.shared.install()
		SectionPainter.shared.refreshModTiles()
		Art.shared.refreshModArt()
	}

	/// A mod block that is a liquid, as the flow sees it (its colour from its picture)
	func modLiquid(_ b: ModBlock, _ t: Tile, _ art: PixelBuf) -> LiquidDef {
		var d: LiquidDef = LiquidDef(tile: t)
		d.color = averageColor(art)
		d.opacity = b.liqOpacity
		d.density = b.liqDensity
		d.thick = b.liqThick
		d.reach = b.liqReach
		d.harm = b.liqHarm
		d.hot = b.liqHot
		d.dries = b.liqDries
		d.effect = b.liqEffect
		d.effectAmt = b.liqEffectAmt
		if !b.liqHardens.isEmpty {
			if b.liqHardens.hasPrefix("tile:"), let n = Int(b.liqHardens.dropFirst(5)), n >= 0, n < 256, let gt = Tile(rawValue: UInt8(n)), gt.solid { d.hardens = gt }
			else if let mt = tileForKey[b.liqHardens] { d.hardens = mt }
		}
		return d
	}

	/// The picture a slot draws: the block's art (an open door shows its edge, an unlit lamp is darker)
	func slotArtBuf(_ i: Int) -> PixelBuf {
		if slotTreeRole[i] != 0, let bt = slotTreeBase[i] {
			if let bi = slot(bt) { return slotArtBuf(bi) }
			return tileBuf(bt)
		}
		guard let b = slotDef[i] else { return missingTileBuf() }
		var art: PixelBuf = b.art.isBlank ? greyTileBuf() : b.art.buf()
		if b.art.outlined(false) { art.outline(0x101010) }
		if b.function == .door && slotAlt[i] {
			// an open door shows its edge: the left quarter of its picture
			var o = PixelBuf(w: art.w, h: art.h)
			for y in 0..<art.h {
				for x in 0..<max(1, art.w / 4) { o.px[y * art.w + x] = art.px[y * art.w + x] }
			}
			art = o
		}
		if b.function == .lamp && !slotAlt[i] {
			for k in 0..<art.px.count where (art.px[k] >> 24) != 0 {
				art.px[k] = (art.px[k] & 0xFF000000) | shadeRGB(art.px[k] & 0xFFFFFF, 0.55)
			}
		}
		return art
	}
}

extension ModRuntime {
	/// The custom blocks and items the creative palette and the test tools offer
	func paletteItems() -> [Item] {
		var out: [Item] = []
		for i in 0..<ModLimits.blockSlots where slotDef[i] != nil && !slotAlt[i] && slotTreeRole[i] == 0 {
			if let t = Tile(rawValue: UInt8(Int(Tile.modBase) + i)) { out.append(.block(t)) }
		}
		for k in itemOrder { out.append(.custom(k)) }
		return out
	}
}

/// Whether a saved world's mods are all installed (checked before it is loaded)
struct ModLoadCheck {
	var save: SaveData
	var packs: [ModPack] = []
	var missing: [ModDep] = []
	/// mods installed in a different version than the world was made with
	var changed: [String] = []

	static func check(_ s: SaveData) -> ModLoadCheck {
		var c = ModLoadCheck(save: s)
		guard let info = s.mods else { return c }
		for d in info.mods {
			if let p = ModStore.pack(d.id) {
				c.packs.append(p)
				if p.version != d.version { c.changed.append(p.name) }
			} else {
				c.missing.append(d)
			}
		}
		return c
	}
}

/// Mod testing: a flat creative world with the mod switched on, separate from real worlds and never
/// saved, with tools to spawn, give, place and clear things
enum ModTest {
	static let seed: UInt64 = 777_000_111

	static func makeWorld(_ p: ModPack, settings: Settings) -> Game {
		var list: [ModPack] = [p]
		for e in ModStore.enabledPacks() where e.id != p.id { list.append(e) }
		ModRuntime.activate(list, world: nil)
		var opts: WorldOptions = .standard
		opts.flat = true
		opts.trees = true
		opts.ponds = true
		opts.structures = true
		opts.caves = true
		let g = Game(mode: .creative, infinite: true, seed: seed, settings: settings, options: opts)
		g.testMod = p.id
		g.slot = -1
		g.worldName = "Mod test: " + p.name
		g.modInfo = ModRuntime.shared.worldInfo()
		g.timeOfDay = 0.3
		return g
	}
}

/// The magenta and black checks of a block whose mod is missing
func missingTileBuf() -> PixelBuf {
	var b = PixelBuf(w: 8, h: 8)
	for y in 0..<8 {
		for x in 0..<8 { b.set(x, y, ((x / 4) + (y / 4)) % 2 == 0 ? 0xFF00FF : 0x200020) }
	}
	return b
}

/// A plain grey block (a custom block nobody has painted yet)
func greyTileBuf() -> PixelBuf {
	var b = PixelBuf(w: 8, h: 8)
	for y in 0..<8 {
		for x in 0..<8 { b.set(x, y, (x == 0 || y == 0) ? 0x9A9A9A : ((x == 7 || y == 7) ? 0x5A5A5A : 0x7A7A7A)) }
	}
	return b
}

/// The average colour of a picture's visible pixels (for particles and maps)
func averageColor(_ b: PixelBuf) -> UInt32 {
	var r: Int = 0
	var g: Int = 0
	var bl: Int = 0
	var n: Int = 0
	for c in b.px where (c >> 24) != 0 {
		r += Int((c >> 16) & 0xFF)
		g += Int((c >> 8) & 0xFF)
		bl += Int(c & 0xFF)
		n += 1
	}
	if n == 0 { return 0x8A8A8A }
	return UInt32(r / n) << 16 | UInt32(g / n) << 8 | UInt32(bl / n)
}

// MARK: - Custom creature art

/// Red, green and blue (0...1) to hue (0...1), saturation and value
func rgbToHSV(_ c: UInt32) -> (Double, Double, Double) {
	let r: Double = Double((c >> 16) & 0xFF) / 255.0
	let g: Double = Double((c >> 8) & 0xFF) / 255.0
	let b: Double = Double(c & 0xFF) / 255.0
	let mx: Double = max(r, max(g, b))
	let mn: Double = min(r, min(g, b))
	let d: Double = mx - mn
	var h: Double = 0
	if d > 0.00001 {
		if mx == r { h = (g - b) / d } else if mx == g { h = 2.0 + (b - r) / d } else { h = 4.0 + (r - g) / d }
		h /= 6.0
		if h < 0 { h += 1.0 }
	}
	let s: Double = mx <= 0 ? 0 : d / mx
	return (h, s, mx)
}

func hsvToRGB(_ h0: Double, _ s: Double, _ v: Double) -> UInt32 {
	let h: Double = (h0 - floor(h0)) * 6.0
	let i: Int = Int(floor(h)) % 6
	let f: Double = h - floor(h)
	let p: Double = v * (1 - s)
	let q: Double = v * (1 - s * f)
	let t: Double = v * (1 - s * (1 - f))
	var r: Double = v
	var g: Double = t
	var b: Double = p
	switch i {
	case 1: r = q; g = v; b = p
	case 2: r = p; g = v; b = t
	case 3: r = p; g = q; b = v
	case 4: r = t; g = p; b = v
	case 5: r = v; g = p; b = q
	default: break
	}
	let ri: UInt32 = UInt32(clampD(r * 255.0, 0, 255).rounded())
	let gi: UInt32 = UInt32(clampD(g * 255.0, 0, 255).rounded())
	let bi: UInt32 = UInt32(clampD(b * 255.0, 0, 255).rounded())
	return (ri << 16) | (gi << 8) | bi
}

/// Turns the hue, scales saturation and brightness, then mixes in a tint, on every visible pixel.
/// Near-black pixels (outlines) stay dark so the creature keeps its shape.
func recolorBuf(_ b: PixelBuf, hue: Double, sat: Double, bright: Double, tint: UInt32, amt: Double) -> PixelBuf {
	if abs(hue) < 0.5 && abs(sat - 1) < 0.01 && abs(bright - 1) < 0.01 && amt < 0.01 { return b }
	var o: PixelBuf = b
	let turn: Double = hue / 360.0
	for i in 0..<o.px.count {
		let c: UInt32 = o.px[i]
		if (c >> 24) == 0 { continue }
		let hsv: (Double, Double, Double) = rgbToHSV(c & 0xFFFFFF)
		if hsv.2 < 0.14 { continue }
		let s2: Double = clampD(hsv.1 * sat, 0, 1)
		let v2: Double = clampD(hsv.2 * bright, 0, 1)
		var rgb: UInt32 = hsvToRGB(hsv.0 + turn, s2, v2)
		if amt > 0.01 { rgb = mixRGB(rgb, tint & 0xFFFFFF, amt) }
		// a part see-through pixel stays as see-through
		o.px[i] = (c & 0xFF000000) | rgb
	}
	return o
}

/// A custom creature's frames: its own pictures (outlined, all the size of the first), or its base
/// creature's frames recoloured
func modMobFrames(_ m: ModMob) -> ([PixelBuf], CreatureAnim) {
	if m.customArt && !m.frames.isEmpty && !m.frames[0].isBlank {
		let w0: Int = m.frames[0].w
		let h0: Int = m.frames[0].h
		var out: [PixelBuf] = []
		for f in m.frames.prefix(ModLimits.maxFrames) {
			let same: ModPixels = (f.w == w0 && f.h == h0) ? f : f.resized(w0, h0)
			var b: PixelBuf = padBuf(same.buf())
			if f.outlined(true) { b.outline(0x101010) }
			out.append(b)
		}
		var a = CreatureAnim()
		if out.count >= 4 { a.attack = 3 }
		if m.behavior.fly || m.behavior.swim || m.category == .flying || m.category == .water {
			if out.count >= 3 { a.cycle = [0, 1, 2, 1] } else if out.count == 2 { a.cycle = [0, 1] }
		}
		return (out, a)
	}
	let base: MobKind = MobKind(rawValue: m.base) ?? .zombie
	let art: ([PixelBuf], CreatureAnim) = creatureArt(base == .custom ? .zombie : base, 0)
	var out: [PixelBuf] = []
	for f in art.0 { out.append(recolorBuf(f, hue: m.hue, sat: m.saturation, bright: m.brightness, tint: m.tint, amt: m.tintAmt)) }
	return (out, art.1)
}

/// The game creature a custom creature takes its body from
func modMobBase(_ m: ModMob) -> MobKind {
	let base: MobKind = MobKind(rawValue: m.base) ?? .zombie
	return base == .custom ? .zombie : base
}

/// A custom creature's frames as a sprite set: its own art sized to its hit box, or its game
/// creature's look (in that look's own pixel size) grown by the creature's scale
func modMobSet(_ m: ModMob, _ frames: [PixelBuf], _ anim: CreatureAnim) -> SpriteSet {
	let base: MobKind = modMobBase(m)
	let h: Double = clampD(mobDef(base).h * m.scale, 0.3, 8)
	if m.customArt && !m.frames.isEmpty && !m.frames[0].isBlank, let f0 = frames.first {
		let bb: (Int, Int, Int, Int) = opaqueBounds(f0)
		let oh: Double = Double(bb.3 - bb.1 + 1)
		return makeSpriteSet(frames, hitH: h, fixedScale: h * 1.05 / max(1.0, oh), anim: anim)
	}
	let look: CreatureLook = creatureLook(base, 0)
	return makeSpriteSet(frames, hitH: h, fixedScale: look.scale * m.scale, anim: anim, foot: look.foot, cx: look.cx)
}

/// The sprites of a custom creature, sized to its hit box
func modMobSpriteSet(_ m: ModMob) -> SpriteSet {
	let fr: ([PixelBuf], CreatureAnim) = modMobFrames(m)
	return modMobSet(m, fr.0, fr.1)
}

// MARK: - Custom content in play

/// Effects on the player from potions, food and the armour worn: each kind has a strength and the
/// seconds it has left. The strongest of the same kind wins.
struct PlayerEffects {
	var amount: [Double] = [Double](repeating: 0, count: ModEffectKind.allCases.count)
	var time: [Double] = [Double](repeating: 0, count: ModEffectKind.allCases.count)
	var regenAcc: Double = 0

	func value(_ k: ModEffectKind) -> Double {
		let i: Int = k.rawValue
		return time[i] > 0 ? amount[i] : 0
	}

	mutating func add(_ k: ModEffectKind, _ a: Double, _ secs: Double) {
		let i: Int = k.rawValue
		if time[i] <= 0 || a >= amount[i] { amount[i] = a }
		time[i] = max(time[i], secs)
	}

	mutating func tick(_ dt: Double) {
		for i in 0..<time.count where time[i] > 0 { time[i] = max(0, time[i] - dt) }
	}

	mutating func clear() {
		for i in 0..<time.count { time[i] = 0 }
	}

	/// What is active, for the HUD: name and seconds left (worn effects show no time)
	var list: [(String, Double)] {
		var out: [(String, Double)] = []
		for k in ModEffectKind.allCases where k.timed && time[k.rawValue] > 0 {
			out.append((k.name, time[k.rawValue]))
		}
		return out
	}
}

/// Reloading data for a gun of a mod: magazine, time and ammunition (nil: it needs none)
struct ModGunSpec {
	var magazine: Int
	var time: Double
	var ammo: Item?
}

extension Game {
	/// Once a frame in a world with mods: worn mod armour keeps its effect up and jump pads throw the
	/// player up (effects themselves run down in updateEffects, in every world)
	func updateModPlay(_ dt: Double) {
		if healerCD > 0 { healerCD -= dt }
		let rt: ModRuntime = ModRuntime.shared
		if !rt.active { return }
		for i in 0..<min(3, inv.armor.count) {
			if let s = inv.armor[i], case .custom(let k) = s.item, let r = rt.item(k), r.def.kind == .armor, let e = r.def.wornEffect {
				effects.add(e.kind, e.amount, 0.3)
			}
		}
		// a jump pad under the feet
		if pb.onGround && !dead && inVehicle == nil {
			let under: Tile = world.tile(Int(floor(pb.x)), Int(floor(pb.y + 0.05)))
			if under.isMod, let b = rt.blockDef(under), b.function == .bounce {
				pb.vy = -max(4.0, b.power)
				pb.onGround = false
				fallPeak = 0
				sfx(.land, 0.7)
				spawnParticles(pb.x, pb.y, averageColor(b.art.buf()), 6, 3.0, 0.4, 10)
			}
		}
	}

	// MARK: using custom items

	func useModItem(_ k: String, _ dt: Double, _ pressed: Bool) {
		guard let r = ModRuntime.shared.item(k) else {
			if pressed { say("This item's mod is not installed.", 1.5) }
			return
		}
		let d: ModItem = r.def
		if pressed && !logicRT.isEmpty { fireLogic(.itemUsed, key: k) }
		// a vehicle's kit builds the vehicle
		if ModRuntime.shared.vehicles[k] != nil {
			if pressed && useCD <= 0 { placeModVehicle(k) }
			return
		}
		switch d.kind {
		case .tool: useModTool(r, dt, pressed)
		case .melee: useMeleeWeapon(.custom(k), pressed)
		case .gun: useModGun(r, pressed)
		case .thrown, .magic: useModShooter(r, pressed)
		case .bow: break
		case .food, .consumable: useModConsumable(r, pressed)
		case .armor:
			if pressed {
				quickEquip(sel)
				say("Equipped.", 1.0)
			}
		case .special:
			if pressed && !d.effects.isEmpty && useCD <= 0 {
				applyEffects(d.effects)
				useCD = max(2.0, d.cooldown)
				sfx(.zap, 0.5)
				spawnParticles(pb.x, pb.y - 1.0, 0xC8E8FF, 8, 3.0, 0.5, -2)
			}
		case .material, .ammo: break
		}
	}

	/// A custom tool: fights a creature under the aim, tills with a hoe, otherwise mines with its own
	/// tier and speed
	func useModTool(_ r: ModItemRT, _ dt: Double, _ pressed: Bool) {
		let it: Item = .custom(r.key)
		let tx: Int = Int(floor(aimX))
		let ty: Int = Int(floor(aimY))
		if let m = mobUnderAim(infusedMelee(it)) {
			if pressed || (useCD <= 0 && !meleeCandidates(infusedMelee(it)).isEmpty) { startMelee(it, target: m) }
			return
		}
		let tt: ToolType = ToolType(rawValue: r.def.toolType) ?? .pickaxe
		if tt == .hoe && useCD <= 0 {
			let t: Tile = world.tile(tx, ty)
			if (t == .grass || t == .dirt || t == .dryGrass || t == .mossGrass) && inReach(Double(tx) + 0.5, Double(ty) + 0.5) && !world.tile(tx, ty - 1).solid {
				world.set(tx, ty, .farmland)
				if world.tile(tx, ty - 1).isPlant { world.set(tx, ty - 1, .air) }
				useCD = 0.25
				swingT = 0.2
				swingDir = facing
				return
			}
		}
		let tier: Tier = Tier(rawValue: clampI(r.def.toolTier, 1, 9)) ?? .wood
		mineStep(tx, ty, tt, tier, dt, speed: r.def.toolSpeed)
	}

	/// What reloading a custom gun takes
	func modGunSpec(_ r: ModItemRT) -> ModGunSpec {
		return ModGunSpec(magazine: max(1, r.def.magazine), time: r.def.reload, ammo: r.ammo)
	}

	func useModGun(_ r: ModItemRT, _ pressed: Bool) {
		guard var st = inv.slots[sel] else { return }
		if reloadT > 0 { return }
		if st.extra <= 0 {
			if pressed || useCD <= 0 { startReload() }
			return
		}
		if useCD > 0 { return }
		if r.def.needsPress && !pressed { return }
		st.extra -= 1
		inv.slots[sel] = st
		fireModShots(r, charge: 1.0, useAmmo: false)
		if st.extra <= 0 {
			let spec: ModGunSpec = modGunSpec(r)
			if spec.ammo == nil || isCreative || inv.total(spec.ammo!) > 0 { startReload() }
		}
		bumpHUD()
	}

	func startModReload(_ r: ModItemRT, _ st: Stack) {
		let spec: ModGunSpec = modGunSpec(r)
		if reloadT > 0 || st.extra >= spec.magazine { return }
		if let a = spec.ammo, !isCreative && inv.total(a) <= 0 {
			say("Out of " + a.name.lowercased() + "!", 1.5)
			return
		}
		reloadT = spec.time
		reloadSlot = sel
		if spec.magazine > 1 { say("Reloading...", 1.0) }
	}

	/// The end of a custom gun's reload: the magazine fills from the bag (or freely without ammunition)
	func finishModReload(_ r: ModItemRT) {
		guard var st = inv.slots[sel] else { return }
		let spec: ModGunSpec = modGunSpec(r)
		let need: Int = spec.magazine - st.extra
		var take: Int = need
		if let a = spec.ammo, !isCreative {
			take = min(need, inv.total(a))
			_ = inv.remove(a, take)
		}
		st.extra += max(0, take)
		inv.slots[sel] = st
		sfx(.tap, 0.5)
		bumpHUD()
	}

	/// Thrown weapons and projectile weapons: one use, one volley
	func useModShooter(_ r: ModItemRT, _ pressed: Bool) {
		if useCD > 0 { return }
		if r.def.needsPress && !pressed { return }
		if let a = r.ammo, !isCreative && inv.total(a) <= 0 {
			if pressed { say("No " + a.name.lowercased() + "!", 1.2) }
			return
		}
		fireModShots(r, charge: 1.0, useAmmo: true)
		if r.def.kind == .thrown && r.ammo == nil && !isCreative { inv.removeAt(sel, 1) }
		bumpHUD()
	}

	/// A custom bow: hold to draw, release to shoot (a full draw keeps firing while held)
	func handleModBow(_ r: ModItemRT, _ dt: Double, _ pressed: Bool, _ released: Bool) {
		var hasAmmo: Bool = true
		if let a = r.ammo, !isCreative { hasAmmo = inv.total(a) > 0 }
		if useHeld {
			if !hasAmmo {
				if pressed { say("No " + (r.ammo?.name.lowercased() ?? "ammunition") + "!", 1.2) }
				bowCharge = 0
				return
			}
			if useCD > 0 && bowCharge == 0 { return }
			bowCharge = min(1.0, max(bowCharge, 0.01) + dt / 0.55)
			facing = aimFacing()
			if bowCharge >= 1.0 && useCD <= 0 {
				fireModShots(r, charge: 1.0, useAmmo: true)
				bowCharge = 0.3
			}
		} else if released && bowCharge > 0 && hasAmmo {
			fireModShots(r, charge: max(0.45, bowCharge), useAmmo: true)
			bowCharge = 0
		} else {
			bowCharge = 0
		}
	}

	/// Fires a custom weapon's volley toward the aim, through the game's projectiles (so its shots
	/// hurt, pierce and knock back like every other shot)
	func fireModShots(_ r: ModItemRT, charge: Double, useAmmo: Bool) {
		let d: ModItem = r.def
		if useAmmo, let a = r.ammo, !isCreative { _ = inv.remove(a, 1) }
		facing = aimFacing()
		let bow: Bool = d.kind == .bow
		let speed: Double = d.speed * (bow ? 0.55 + 0.45 * charge : 1.0)
		let dmg: Double = d.damage * (bow ? 0.4 + 0.6 * charge : 1.0)
		var grav: Double = d.gravity
		var life: Double = 3.0
		var kind: ProjKind = ProjKind(rawValue: d.shot) ?? .arrow
		var w: Double = 0.24
		if r.shot >= 0 && r.shot < ModRuntime.shared.shots.count {
			let s: ModProjectile = ModRuntime.shared.shots[r.shot]
			grav = s.gravity
			life = s.life
			kind = .spit
			w = s.size
		}
		let ox: Double = pb.x + Double(facing) * 0.6
		let oy: Double = pb.y - 1.2
		let base: Double = lobAngle(aimX - ox, aimY - oy, speed, grav)
		let n: Int = max(1, d.spread)
		let live: Int = projectiles.filter { $0.mod >= 0 }.count
		if live >= ModLimits.maxShotsLive { return }
		for i in 0..<n {
			var a: Double = base
			if n > 1 { a += (Double(i) / Double(n - 1) - 0.5) * min(1.2, 0.18 * Double(n)) }
			var p = Projectile(kind: kind, x: ox, y: oy, vx: cos(a) * speed, vy: sin(a) * speed, dmg: dmg, fromPlayer: true, gravity: grav)
			p.life = life
			p.source = .player
			p.uid = newID()
			p.pierce = d.pierce
			p.knock = d.knock
			p.w = w
			p.mod = r.shot
			if r.shot < 0 && kind == .fireball { p.life = 2.5 }
			infuseShot(&p, heldItem)
			projectiles.append(p)
		}
		useCD = d.cooldown * quickMul()
		swingT = 0.14
		swingDir = facing
		switch d.kind {
		case .bow: sfx(.bow, 0.7); bowRecoil = 0.12
		case .gun: sfx(kind == .quarrel ? .crossbow : .gun, 0.75); muzzleT = 0.08; addShake(0.08)
		case .thrown: sfx(.sling, 0.6)
		default: sfx(.zap, 0.6)
		}
	}

	/// Food, potions and other consumables: hunger, effects, then one is used up
	func useModConsumable(_ r: ModItemRT, _ pressed: Bool) {
		if !pressed || eatT > 0 { return }
		let d: ModItem = r.def
		if d.kind == .food && d.effects.isEmpty && hunger >= 19.5 && hp >= maxHP && !isCreative {
			say("You're not hungry.", 1.2)
			return
		}
		if d.hunger > 0 {
			hunger = min(20, hunger + d.hunger)
			floatText("+" + String(Int(d.hunger)), pb.x, pb.y - pb.h - 0.4, 0xE0A040)
		}
		applyEffects(d.effects)
		if !isCreative { inv.removeAt(sel, 1) }
		eatT = d.useTime
		useCD = d.useTime
		sfx(.eat, 0.6)
		spawnParticles(pb.x + Double(facing) * 0.4, pb.y - 1.4, 0xC8A0E0, 6, 2.0, 0.4, 6)
		bumpHUD()
	}

	/// Applies effects: healing, food and cures at once, the rest for their time
	func applyEffects(_ list: [ModEffect]) {
		for e in list {
			switch e.kind {
			case .heal: heal(e.amount)
			case .feed: hunger = min(20, hunger + e.amount)
			case .cure:
				playerBurn = 0
				bodyCold = 0
			default: effects.add(e.kind, e.amount, e.seconds)
			}
		}
		bumpHUD()
	}

	// MARK: custom blocks

	/// Tapping a custom block: storage opens, doors and lamps switch, shrines heal, signs speak.
	/// Returns false for blocks that do nothing when tapped.
	func interactModBlock(_ tx: Int, _ ty: Int, _ t: Tile) -> Bool {
		guard let b = ModRuntime.shared.blockDef(t) else {
			say(t.name + ": its mod is not installed.", 2.0)
			return true
		}
		switch b.function {
		case .storage:
			sfx(.chestOpen, 0.7)
			if world.chests[world.chestKey(tx, ty)] == nil { world.setChestItems(tx, ty, []) }
			openChest = IntPair(x: tx, y: ty)
			showInventory = true
			bumpHUD()
		case .station:
			if b.station >= 1, let s = Station(rawValue: b.station) { craftStation = s } else { craftStation = .hand }
			showInventory = true
			bumpHUD()
		case .lamp, .door:
			guard let other = ModRuntime.shared.partner(t) else { return false }
			if b.function == .door && ModRuntime.shared.isAlt(t) {
				// closing a door the player stands in would trap them
				if pb.right > Double(tx) && pb.left < Double(tx + 1) && pb.y > Double(ty) && pb.top < Double(ty + 1) { return true }
			}
			world.set(tx, ty, other)
			sfx(b.function == .door ? .door : .tap, 0.6)
		case .healer:
			if healerCD > 0 {
				say("The shrine is resting.", 1.2)
			} else {
				heal(b.power)
				healerCD = 5
				sfx(.discovery, 0.5)
				spawnParticles(Double(tx) + 0.5, Double(ty) + 0.2, 0x80FF90, 12, 3.0, 0.8, -3)
			}
		case .sign:
			say(b.text.isEmpty ? b.name : b.text, 4.0)
		case .seat:
			sitOn(tx, ty)
		case .bed:
			sleepIn(tx, ty)
		default:
			return false
		}
		return true
	}

	/// True if a recipe's station (a game station or a mod block) is close enough
	func recipeStationOK(_ r: Recipe) -> Bool {
		if let ms = r.modStation {
			if isCreative { return true }
			let px: Int = Int(floor(pb.x))
			let py: Int = Int(floor(pb.y - 1))
			for dy in -4...3 {
				for dx in -5...5 where world.tile(px + dx, py + dy) == ms { return true }
			}
			return false
		}
		return stationAvailable(r.station)
	}

	func recipeStationName(_ r: Recipe) -> String {
		if let ms = r.modStation { return ms.name }
		return r.station.name
	}

	// MARK: custom shots

	/// A custom shot came down (on a creature, the player or a block): its blast and its fire
	func modShotLanded(_ p: Projectile, _ x: Double, _ y: Double, mob: Mob?, player: Bool) {
		guard p.mod >= 0 && p.mod < ModRuntime.shared.shots.count else { return }
		let s: ModProjectile = ModRuntime.shared.shots[p.mod]
		if s.burn > 0 {
			if let m = mob { m.burn = max(m.burn, s.burn) }
			if player && effects.value(.fireproof) <= 0 { playerBurn = max(playerBurn, s.burn * 0.5) }
		}
		if s.explode > 0 {
			// (only the player's own shots may break blocks; a creature's never wrecks the world)
			explode(x, y, radius: s.explode, power: p.dmg, source: p.source, breakBlocks: s.breakBlocks && p.source.kind == .player)
		} else {
			spawnParticles(x, y, s.color & 0xFFFFFF, 5, 3.0, 0.3, 6)
		}
	}
}

extension Game {
	// MARK: Mod Test tools

	/// Spawns a custom creature a few blocks in front of the player. It stays put (persistent) until
	/// cleared. Returns what to tell the player.
	func testSpawn(_ slot: Int) -> String {
		guard let r = ModRuntime.shared.mob(slot) else { return "That creature is not in this world." }
		let x: Double = pb.x + Double(facing) * max(3.0, r.mdef.w + 2.0)
		var y: Double = pb.y
		if r.mdef.flying {
			y = pb.y - 3.0
		} else if !r.aquatic {
			y = Double(world.groundBelow(Int(floor(x)), Int(floor(pb.y)) - 8))
		}
		guard let m = addCustomMob(slot, x, y) else {
			return joinText("No more than ", String(ModLimits.maxActiveMobs), " custom creatures at once: clear some first.")
		}
		m.homeX = x
		m.homeY = y
		m.persistent = true
		m.dir = pb.x >= x ? 1 : -1
		var note: String = joinText("Spawned ", r.def.name, ".")
		if r.aquatic && !m.b.inWater { note = joinText(note, " It lives in water: put it in a pool.") }
		return note
	}

	/// One of the game's own creatures to try the mod's creatures and weapons on
	func testSpawnGame(_ k: MobKind) -> String {
		let x: Double = pb.x + Double(facing) * 4.0
		let y: Double = Double(world.groundBelow(Int(floor(x)), Int(floor(pb.y)) - 8))
		let m: Mob = addMob(k, x, y)
		m.homeX = x
		m.homeY = y
		m.persistent = true
		return joinText("Spawned a ", mobDef(k).name.lowercased(), ".")
	}

	/// Removes every creature (pets stay), every shot and every warning
	func clearCreatures() {
		mobs.removeAll { !$0.tame }
		projectiles.removeAll()
		dangerZones.removeAll()
		activeBoss = nil
		bumpHUD()
	}

	/// Gives what a recipe needs and, if it needs a station, puts that station beside the player, so it
	/// can be tried in the crafting panel straight away
	func testIngredients(_ r: Recipe) -> String {
		for c in r.cost { giveItem(c.item, c.n) }
		var station: Tile? = r.modStation
		if station == nil {
			switch r.station {
			case .hand: station = nil
			case .bench: station = .workbench
			case .furnace, .campfire: station = .furnace
			case .anvil: station = .anvil
			case .tinker: station = .tinkerBench
			case .forge: station = .riftForge
			case .still: station = .alchemyStill
			case .infuser: station = .infuser
			case .assembly: station = .exoStation
			}
		}
		var placed: String = ""
		if let st = station {
			let px: Int = Int(floor(pb.x))
			let py: Int = Int(floor(pb.y)) - 1
			var done: Bool = stationNear(st)
			for dx in [-2, 2, -3, 3] where !done {
				let x: Int = px + dx
				if world.tile(x, py) == .air && world.solid(x, py + 1) {
					world.set(x, py, st)
					done = true
					placed = joinText(" and a ", st.name, " beside you")
				}
			}
		}
		bumpHUD()
		return joinText("Here is what ", r.out.name, " needs", placed, ".")
	}

	/// A station tile within reach of the player already
	func stationNear(_ t: Tile) -> Bool {
		let px: Int = Int(floor(pb.x))
		let py: Int = Int(floor(pb.y - 1))
		for dy in -4...3 {
			for dx in -5...5 where world.tile(px + dx, py + dy) == t { return true }
		}
		return stationAboard(t)
	}

	/// Survival rules in the test world: hunger, damage and using things up (off: creative)
	var testSurvival: Bool {
		get { return mode == .survival }
		set {
			mode = newValue ? .survival : .creative
			if newValue && hp <= 0 { hp = maxHP }
			bumpHUD()
		}
	}
}
