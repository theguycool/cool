// PIXEL REALM v2, part 6 of 6: the potion and exosuit screens, the Mod Creator+ screens (with the sprite editor, the sun and
// moon editor and the tree designer), and the app itself.
// The game is six files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm6.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). The hand-drawn pictures are kept as text in part 1 (a01_artsheet).

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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

// ===== u09_modplus =====

// MARK: - Mod Creator+: changing game content (screens)

/// The game's own blocks, items or creatures to pick from (for a change, or to start from)
struct GamePickerView: View {
	let kind: ModOverrideKind
	var title: String = "PICK FROM THE GAME"
	var pick: (Int, Item?) -> Void
	var cancel: () -> Void
	@State var filter: String = ""

	var body: some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 92), spacing: 6)]
		return VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text(verbatim: title).font(.pixel(15)).foregroundColor(ModUI.gold)
				Spacer()
				SmallButton(title: "CANCEL", color: ModUI.red) { cancel() }
			}
			ModTextField(label: "Search", text: $filter, placeholder: "name")
			LazyVGrid(columns: cols, spacing: 6) {
				switch kind {
				case .block:
					ForEach(tiles, id: \.self) { t in
						cell(pixImage(tileBuf(t)), t.name) { pick(Int(t.rawValue), nil) }
					}
				case .item:
					ForEach(0..<items.count, id: \.self) { i in
						cell(Art.shared.icon(items[i]), items[i].name) { pick(0, items[i]) }
					}
				case .creature:
					ForEach(mobs, id: \.self) { k in
						cell(mobIcon(k), mobDef(k).name) { pick(k.rawValue, nil) }
					}
				}
			}
		}
		.padding(10)
		.background(PixelBox(color: ModUI.panel))
	}

	func match(_ name: String) -> Bool {
		let f: String = filter.trimmingCharacters(in: .whitespaces).lowercased()
		return f.isEmpty || name.lowercased().contains(f)
	}
	var tiles: [Tile] { return ModOverrideCheck.tiles().filter { match($0.name) } }
	var items: [Item] { return ModOverrideCheck.items().filter { match($0.name) } }
	var mobs: [MobKind] { return ModOverrideCheck.mobs().filter { match(mobDef($0).name) } }

	func mobIcon(_ k: MobKind) -> Image {
		let s: SpriteSet = Art.shared.creaturePreview(k)
		return s.frame(0, left: false, hurt: false)
	}

	func cell(_ img: Image, _ name: String, _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 3) {
				img.resizable().interpolation(.none).frame(width: 40, height: 40)
				Text(verbatim: name).font(.pixel(9, .semibold)).foregroundColor(Color.white).lineLimit(2).multilineTextAlignment(.center)
			}
			.frame(maxWidth: .infinity, minHeight: 76)
			.background(ModUI.card)
		}
		.buttonStyle(.plain)
	}
}

/// The GAME CONTENT tab: every change this mod makes to the game's own content
struct GameContentList: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void
	@State var picking: ModOverrideKind? = nil
	@State var showSky: Bool = false
	@State var skyPick: Int = 0

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Change the game's own blocks, items and creatures: only the numbers you set change, the originals are kept, and switching a change off (or the whole mod) puts the game back as it was.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			skyPart
			if let k = picking {
				GamePickerView(kind: k, title: joinText("CHANGE A ", k.name.uppercased()), pick: { raw, it in add(k, raw, it) }, cancel: { picking = nil })
			} else {
				HStack(spacing: 6) {
					PixelButton(title: "+ BLOCK", color: ModUI.accent) { picking = .block }
					PixelButton(title: "+ ITEM", color: ModUI.accent) { picking = .item }
					PixelButton(title: "+ CREATURE", color: ModUI.accent) { picking = .creature }
				}
			}
			if s.mod.overrides.isEmpty && picking == nil {
				Text("No changes to game content yet.").font(.pixel(12)).foregroundColor(ModUI.dim)
			}
			ForEach(s.mod.overrides) { o in row(o) }
		}
	}

	/// The Overworld's sun and moon as this mod draws them
	var skyPart: some View {
		let shown: Bool = showSky
		let pick: Int = clampI(skyPick, 0, 1)
		let sun: String = s.mod.skySun == nil ? "the game's" : "its own"
		let moon: String = s.mod.skyMoon == nil ? "the game's" : "its own"
		let line: String = joinText("The Overworld's sky: ", sun, " sun, ", moon, " moon")
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				Text(verbatim: line).font(.pixel(12, .bold)).foregroundColor(Color.white)
				Spacer(minLength: 0)
				SmallButton(title: shown ? "CLOSE" : "SUN AND MOON...", color: ModUI.blue) { self.showSky.toggle() }
			}
			if shown {
				ChoiceRows(options: DimensionEditorView.bodyNames, selected: $skyPick, columns: 2)
				if pick == 0 {
					SkyBodyEditor(sky: s.modBind(\.skySun), moon: false)
				} else {
					SkyBodyEditor(sky: s.modBind(\.skyMoon), moon: true, skyTop: 0x060A1E, skyBottom: 0x18223E)
				}
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func add(_ k: ModOverrideKind, _ raw: Int, _ it: Item?) {
		var o = ModOverride()
		o.id = s.mod.freshID("g")
		o.kind = k
		if k == .block { o.tile = raw }
		if k == .item { o.item = it }
		if k == .creature { o.mob = raw }
		// one change per thing: open the one there is
		if let same = s.mod.overrides.first(where: { $0.kind == k && (k == .block ? $0.tile == raw : (k == .item ? $0.item == it : $0.mob == raw)) }) {
			picking = nil
			open(same.id)
			return
		}
		s.mod.overrides.append(o)
		s.touch()
		picking = nil
		open(o.id)
	}

	func row(_ o: ModOverride) -> some View {
		let on: Binding<Bool> = s.bind(\.overrides, o.id, \.enabled, true)
		return HStack(spacing: 8) {
			overrideIcon(o).resizable().interpolation(.none).frame(width: 38, height: 38).background(Color.black.opacity(0.4))
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: o.targetName).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: joinText(o.kind.name, " · ", String(o.changedCount), o.changedCount == 1 ? " change" : " changes")).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: o.enabled ? "ON" : "OFF", color: o.enabled ? ModUI.accent : Color(ui: 0x555555)) { on.wrappedValue.toggle() }
			SmallButton(title: "EDIT", color: ModUI.blue) { open(o.id) }
			SmallButton(title: "✕", color: ModUI.red) {
				s.mod.overrides.removeAll { $0.id == o.id }
				s.touch()
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}
}

func overrideIcon(_ o: ModOverride) -> Image {
	switch o.kind {
	case .block: return pixImage(tileBuf(Tile(rawValue: UInt8(clampI(o.tile, 0, 255))) ?? .stone))
	case .item: return Art.shared.icon(o.item ?? .mat(.stick))
	case .creature: return Art.shared.creaturePreview(MobKind(rawValue: o.mob) ?? .zombie).frame(0, left: false, hurt: false)
	}
}

/// One number of a change: the game's value, a switch to change it, the new value, and RESTORE
struct OverrideField: View {
	let label: String
	let original: Double
	@Binding var value: Double?
	let range: ClosedRange<Double>
	var step: Double = 0
	var format: String = "%.1f"

	var body: some View {
		let changed: Bool = value != nil
		let bind: Binding<Double> = Binding<Double>(get: { value ?? original }, set: { value = $0 })
		return VStack(alignment: .leading, spacing: 4) {
			HStack {
				Text(verbatim: label).font(.pixel(12)).foregroundColor(Color.white)
				Spacer()
				Text(verbatim: joinText("game: ", String(format: format, original))).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				if changed {
					SmallButton(title: "RESTORE", color: Color(ui: 0x6A5A3A)) { value = nil }
				} else {
					SmallButton(title: "CHANGE", color: ModUI.blue) { value = original }
				}
			}
			if changed {
				StatSlider(label: "New value", value: bind, range: range, step: step, format: format)
			}
		}
		.padding(6)
		.background(Color.black.opacity(changed ? 0.3 : 0.15))
	}
}

/// A game creature's own sprite, repainted by a mod: its frames copied from the game to paint over (the
/// game then draws them in place of its own, timed the same), put back to the game's, or saved as a new
/// custom creature that starts from it
struct CreatureSpriteEditor: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var frame: Int = 0
	@State var note: String = ""

	var override: ModOverride { return s.mod.overrides.first { $0.id == id } ?? ModOverride() }
	var kind: MobKind { return MobKind(rawValue: override.mob) ?? .zombie }

	var body: some View {
		let fr: [ModPixels] = override.frames ?? []
		let help: String = fr.isEmpty ? "Paint over the game's own sprite: every frame, pixel by pixel." : "The game draws these frames instead of its own (standing, walking, then the rest, in the game's order)."
		return ModSection(title: "ITS SPRITE", help: help) {
			if fr.isEmpty { startRow } else { editor(fr) }
			if !note.isEmpty { Text(verbatim: note).font(.pixel(11, .semibold)).foregroundColor(ModUI.gold) }
		}
	}

	var startRow: some View {
		let bufs: [PixelBuf] = GameSprites.creatureFrames(kind)
		return HStack(spacing: 8) {
			ForEach(0..<min(6, bufs.count), id: \.self) { (i: Int) in
				pixImage(bufs[i]).resizable().interpolation(.none).frame(width: 44, height: 44).background(Color.black.opacity(0.35))
			}
			Spacer()
			SmallButton(title: "EDIT ITS SPRITE", color: ModUI.accent) { self.startEditing() }
		}
	}

	func editor(_ fr: [ModPixels]) -> some View {
		let i: Int = min(frame, fr.count - 1)
		return VStack(alignment: .leading, spacing: 8) {
			frameRow(fr.count)
			PixelEditorView(pixels: frameBind(i), maxSide: 360, frames: fr, frameIndex: i, sizes: [], outlineDefault: false)
			HStack(spacing: 6) {
				SmallButton(title: "BACK TO THE GAME'S SPRITE", color: ModUI.red) { self.setFrames(nil) }
				SmallButton(title: "SAVE AS A NEW CREATURE", color: ModUI.blue) { self.saveAsCreature() }
			}
		}
	}

	func frameRow(_ n: Int) -> some View {
		HStack(spacing: 6) {
			ForEach(0..<n, id: \.self) { (i: Int) in
				SmallButton(title: joinText("FRAME ", String(i + 1)), color: self.frame == i ? ModUI.accent : Color(ui: 0x555555)) { self.frame = i }
			}
			if n < 12 { SmallButton(title: "+ FRAME", color: ModUI.blue) { self.copyFrame() } }
			if n > 1 { SmallButton(title: "DELETE FRAME", color: ModUI.red) { self.deleteFrame() } }
		}
	}

	func frameBind(_ i: Int) -> Binding<ModPixels> {
		return Binding<ModPixels>(get: {
			let fr: [ModPixels] = self.override.frames ?? []
			return i < fr.count ? fr[i] : ModPixels(w: 24, h: 24)
		}, set: { (v: ModPixels) in
			var fr: [ModPixels] = self.override.frames ?? []
			if i < fr.count {
				fr[i] = v
				self.setFrames(fr)
			}
		})
	}

	func setFrames(_ fr: [ModPixels]?) {
		guard let k = s.mod.overrides.firstIndex(where: { $0.id == id }) else { return }
		s.mod.overrides[k].frames = fr
		s.touch()
		if fr == nil { frame = 0 }
	}

	/// The game's own frames, copied in to paint over (they already have the game's outline)
	func startEditing() {
		let bufs: [PixelBuf] = GameSprites.creatureFrames(kind)
		guard let f0 = bufs.first else { return }
		if f0.w > ModPixels.maxSide || f0.h > ModPixels.maxSide {
			note = joinText("Its sprite is too big to paint here (", String(f0.w), " x ", String(f0.h), ").")
			return
		}
		var fr: [ModPixels] = []
		for b in bufs {
			var p: ModPixels = ModPixels(buf: b)
			p.outline = false
			fr.append(p)
		}
		frame = 0
		setFrames(fr)
		// the repaint follows the drawing it starts from: its size and the order of its frames
		if let k = s.mod.overrides.firstIndex(where: { $0.id == id }) {
			s.mod.overrides[k].fine = creatureLook(kind, 0).fine
			s.touch()
		}
	}

	func copyFrame() {
		var fr: [ModPixels] = override.frames ?? []
		if fr.isEmpty || fr.count >= 12 { return }
		let i: Int = min(frame, fr.count - 1)
		fr.insert(fr[i], at: i + 1)
		setFrames(fr)
		frame = i + 1
	}

	func deleteFrame() {
		var fr: [ModPixels] = override.frames ?? []
		if fr.count <= 1 { return }
		fr.remove(at: min(frame, fr.count - 1))
		setFrames(fr)
		frame = max(0, min(frame, fr.count - 1))
	}

	/// A new custom creature with this sprite and the game creature's numbers (its body and hit box
	/// come from the game creature): standing, two walking frames, and its attack
	func saveAsCreature() {
		let fr: [ModPixels] = override.frames ?? []
		if fr.isEmpty { return }
		let k: MobKind = kind
		let d: MobDef = makeMobDef(k)
		let anim: CreatureAnim = override.fine ? creatureLook(k, 0).anim : olderCreatureArt(k, 0).1
		var m = ModMob()
		m.id = s.mod.freshID("m")
		m.name = String(joinText(d.name, " (own look)").prefix(32))
		m.base = k.rawValue
		m.customArt = true
		// standing, two frames of the walk (the first and one half a stride on), and the attack
		let w0: Int = anim.walk.first ?? 1
		let w1: Int = anim.walk.count > 2 ? anim.walk[anim.walk.count / 2] : (anim.walk.last ?? 2)
		var pick: [Int] = [0, min(w0, fr.count - 1), min(w1, fr.count - 1)]
		let hit: Int = anim.attack >= 0 ? anim.attack : anim.pose("strike", fr.count - 1)
		pick.append(hit >= 0 && hit < fr.count ? hit : fr.count - 1)
		m.frames = pick.map { fr[$0] }
		m.hp = d.hp
		m.damage = d.dmg
		m.speed = d.speed
		m.detect = d.aggro
		m.jump = d.jump
		m.category = d.hostile ? .hostile : (d.flying ? .flying : .passive)
		s.mod.mobs.append(m)
		s.touch()
		note = joinText("Saved as a new creature, \u{201C}", m.name, "\u{201D}, in CREATURES.")
	}
}

/// Editing one change to game content, with what it does before and after
struct OverrideEditorView: View {
	@ObservedObject var s: ModSession
	let id: String

	var body: some View {
		guard let o = s.mod.overrides.first(where: { $0.id == id }) else {
			return AnyView(Text("This change no longer exists.").font(.pixel(13)).foregroundColor(ModUI.dim))
		}
		return AnyView(VStack(alignment: .leading, spacing: 10) {
			header(o)
			ModToggle(label: "This change is on", help: "Off: the game's own numbers, kept with the mod for later", isOn: s.bind(\.overrides, id, \.enabled, true))
			fields(o)
			preview(o)
		})
	}

	func header(_ o: ModOverride) -> some View {
		HStack(spacing: 10) {
			overrideIcon(o).resizable().interpolation(.none).frame(width: 56, height: 56).background(Color.black.opacity(0.4))
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: o.targetName).font(.pixel(18)).foregroundColor(Color.white)
				Text(verbatim: o.kind.name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: "RESTORE ALL", color: Color(ui: 0x6A5A3A)) { self.restoreAll() }
		}
	}

	func preview(_ o: ModOverride) -> some View {
		let rows: [(String, String, String)] = previewRows(o)
		return ModSection(title: "BEFORE AND AFTER", help: "Worked out with the game's own rules") {
			ForEach(0..<rows.count, id: \.self) { i in PreviewRow(name: rows[i].0, before: rows[i].1, after: rows[i].2) }
		}
	}

	func restoreAll() {
		guard let i = s.mod.overrides.firstIndex(where: { $0.id == id }) else { return }
		var o: ModOverride = s.mod.overrides[i]
		let keep: ModOverride = o
		o = ModOverride()
		o.id = keep.id
		o.kind = keep.kind
		o.tile = keep.tile
		o.item = keep.item
		o.mob = keep.mob
		o.enabled = keep.enabled
		s.mod.overrides[i] = o
		s.touch()
	}

	func b(_ kp: WritableKeyPath<ModOverride, Double?>) -> Binding<Double?> {
		return s.bind(\.overrides, id, kp, nil)
	}

	func bi(_ kp: WritableKeyPath<ModOverride, Int?>) -> Binding<Double?> {
		let inner: Binding<Int?> = s.bind(\.overrides, id, kp, nil)
		return Binding<Double?>(get: { inner.wrappedValue.map { Double($0) } }, set: { v in inner.wrappedValue = v.map { Int($0.rounded()) } })
	}

	func unbreakableBind() -> Binding<Bool> {
		let inner: Binding<Bool?> = s.bind(\.overrides, id, \.unbreakable, nil)
		return Binding<Bool>(get: { inner.wrappedValue ?? false }, set: { v in inner.wrappedValue = v ? true : nil })
	}

	func fields(_ o: ModOverride) -> AnyView {
		switch o.kind {
		case .block: return blockFields(o)
		case .item: return itemFields(o)
		case .creature: return creatureFields(o)
		}
	}

	func blockFields(_ o: ModOverride) -> AnyView {
		let sb: Bool = s.mod.sandbox
		let t: Tile = Tile(rawValue: UInt8(clampI(o.tile, 0, 255))) ?? .stone
		let d: TileDef = Tile.makeDef(t)
		let top: Double = sb ? 200 : 40
		let tier: Double = Double(d.tier)
		let light: Double = Double(d.light)
		return AnyView(VStack(alignment: .leading, spacing: 8) {
			OverrideField(label: "Hardness", original: min(d.hard, top), value: b(\.hardness), range: 0.05...top, step: 0.05, format: "%.2f")
			OverrideField(label: "Tool tier needed", original: tier, value: bi(\.tier), range: 0.0...9.0, step: 1, format: "%.0f")
			OverrideField(label: "Light given off", original: light, value: bi(\.light), range: 0.0...15.0, step: 1, format: "%.0f")
			ModToggle(label: "Unbreakable", help: "Nothing can mine it", isOn: unbreakableBind())
		})
	}

	func itemFields(_ o: ModOverride) -> AnyView {
		let sb: Bool = s.mod.sandbox
		let it: Item = o.item ?? .sword(.iron)
		let p: MeleeProfile = it.baseMelee
		let dmgR: ClosedRange<Double> = sbRange(0, 60, 500, sb)
		switch it {
		case .armor(let sl, let tr):
			let d0: Double = tr.defense * sl.weight
			return AnyView(OverrideField(label: "Defence", original: d0, value: b(\.defense), range: sbRange(0, 12, 40, sb), step: 0.1))
		case .food(let f):
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Hunger restored", original: f.hunger, value: b(\.hunger), range: 0.0...20.0, step: 0.5)
				OverrideField(label: "Health restored", original: f.heal, value: b(\.heal), range: sbRange(0, 40, 400, sb), step: 0.5)
			})
		case .gun(let g):
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Shot damage", original: g.damage, value: b(\.damage), range: dmgR, step: 0.5)
				OverrideField(label: "Time between shots", original: g.cooldown, value: b(\.cooldown), range: 0.15...10.0, step: 0.05, format: "%.2f")
			})
		case .bow, .sling:
			let base: Double = it == .bow ? 14 : 4.5
			return AnyView(OverrideField(label: "Shot damage (full draw)", original: base, value: b(\.damage), range: dmgR, step: 0.5))
		case .tool(_, let tr):
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Mining speed", original: tr.mineSpeed, value: b(\.mineSpeed), range: sbRange(0.3, 30, 200, sb), step: 0.1)
				OverrideField(label: "Damage when swung", original: p.damage, value: b(\.damage), range: dmgR, step: 0.5)
			})
		default:
			return AnyView(VStack(alignment: .leading, spacing: 8) {
				OverrideField(label: "Damage", original: p.damage, value: b(\.damage), range: dmgR, step: 0.5)
				OverrideField(label: "Time between swings", original: p.cooldown, value: b(\.cooldown), range: 0.15...10.0, step: 0.01, format: "%.2f")
				OverrideField(label: "Reach", original: p.reach, value: b(\.reach), range: sbRange(0.5, 6, 12, sb), step: 0.1)
				OverrideField(label: "Knockback", original: p.knock, value: b(\.knock), range: sbRange(0, 16, 40, sb), step: 0.5)
				OverrideField(label: "Critical chance", original: p.critChance, value: b(\.crit), range: 0.0...1.0, step: 0.01, format: "%.2f")
			})
		}
	}

	func creatureFields(_ o: ModOverride) -> AnyView {
		let sb: Bool = s.mod.sandbox
		let k: MobKind = MobKind(rawValue: o.mob) ?? .zombie
		let d: MobDef = makeMobDef(k)
		return AnyView(VStack(alignment: .leading, spacing: 8) {
			OverrideField(label: "Health", original: d.hp, value: b(\.hp), range: sbRange(1, 4000, 20000, sb), step: 1, format: "%.0f")
			OverrideField(label: "Damage", original: d.dmg, value: b(\.mobDamage), range: sbRange(0, 60, 500, sb), step: 0.5)
			OverrideField(label: "Speed", original: d.speed, value: b(\.speed), range: sbRange(0, 8, 20, sb), step: 0.1)
			OverrideField(label: "Notices you from", original: d.aggro, value: b(\.detect), range: sbRange(2, 32, 64, sb), step: 1, format: "%.0f")
			OverrideField(label: "Jump", original: d.jump, value: b(\.jump), range: sbRange(0, 20, 30, sb), step: 0.5)
			CreatureSpriteEditor(s: s, id: id)
		})
	}

	/// Before-and-after numbers for the preview
	func previewRows(_ o: ModOverride) -> [(String, String, String)] {
		switch o.kind {
		case .block: return blockRows(o)
		case .item: return itemRows(o)
		case .creature: return creatureRows(o)
		}
	}

	func blockRows(_ o: ModOverride) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let t: Tile = Tile(rawValue: UInt8(clampI(o.tile, 0, 255))) ?? .stone
		let d: TileDef = Tile.makeDef(t)
		let hard1: Double = o.unbreakable == true ? 9999 : (o.hardness ?? d.hard)
		let tier1: Int = o.tier ?? d.tier
		let cls: ToolType = toolClass(t)
		let toolName: String = cls.name.lowercased()
		let tools: [(String, ToolType?, Tier)] = [("Bare hands", nil, .wood), (joinText("Wooden ", toolName), cls, .wood),
												   (joinText("Iron ", toolName), cls, .iron), (joinText("Diamond ", toolName), cls, .diamond)]
		for (name, k, tr) in tools {
			let tierN: Int = k == nil ? 0 : tr.rawValue
			let speed: Double = tr.mineSpeed
			let a: Double? = miningSecondsFor(hardness: d.hard, tier: d.tier, blockTool: cls, unbreakable: d.hard >= 9999, k, tierN, toolSpeed: speed)
			let bb: Double? = miningSecondsFor(hardness: hard1, tier: tier1, blockTool: cls, unbreakable: hard1 >= 9999, k, tierN, toolSpeed: speed)
			rows.append((name, secondsText(a), secondsText(bb)))
		}
		let l1: Int = o.light ?? d.light
		rows.append(("Light", String(d.light), String(l1)))
		return rows
	}

	func itemRows(_ o: ModOverride) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let it: Item = o.item ?? .sword(.iron)
		let p0: MeleeProfile = it.baseMelee
		let p1: MeleeProfile = o.apply(p0)
		switch it {
		case .armor(let sl, let tr):
			let d0: Double = tr.defense * sl.weight
			let d1: Double = o.defense ?? d0
			rows.append(("Defence", oneDecimal(d0), oneDecimal(d1)))
		case .food(let f):
			let h1: Double = o.hunger ?? f.hunger
			let l1: Double = o.heal ?? f.heal
			rows.append(("Hunger", oneDecimal(f.hunger), oneDecimal(h1)))
			rows.append(("Health", oneDecimal(f.heal), oneDecimal(l1)))
		case .tool(_, let tr):
			let speed: Double = o.mineSpeed ?? tr.mineSpeed
			let s0: Double? = miningSeconds(.stone, .pickaxe, tr)
			let s1: Double? = miningSeconds(.stone, .pickaxe, tr, toolSpeed: speed)
			rows.append(("Stone takes (as a pickaxe)", secondsText(s0), secondsText(s1)))
		case .gun(let g):
			let dmg1: Double = o.damage ?? g.damage
			let cd1: Double = o.cooldown ?? g.cooldown
			let dps0: Double = g.damage / max(0.05, g.cooldown)
			let dps1: Double = dmg1 / max(0.05, cd1)
			rows.append(("Damage a second", oneDecimal(dps0), oneDecimal(dps1)))
		default:
			let dps0: Double = p0.damage / max(0.05, p0.cooldown)
			let dps1: Double = p1.damage / max(0.05, p1.cooldown)
			let z: Double = mobDef(.zombie).hp
			let blows0: Int = Int(ceil(z / max(0.1, p0.damage)))
			let blows1: Int = Int(ceil(z / max(0.1, p1.damage)))
			rows.append(("Damage", oneDecimal(p0.damage), oneDecimal(p1.damage)))
			rows.append(("Damage a second", oneDecimal(dps0), oneDecimal(dps1)))
			rows.append(("Blows to fell a zombie", String(blows0), String(blows1)))
		}
		return rows
	}

	func creatureRows(_ o: ModOverride) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let k: MobKind = MobKind(rawValue: o.mob) ?? .zombie
		let d: MobDef = makeMobDef(k)
		let sword: Double = Item.sword(.iron).baseMelee.damage
		let hp1: Double = o.hp ?? d.hp
		let blows0: Int = Int(ceil(d.hp / sword))
		let blows1: Int = Int(ceil(hp1 / sword))
		rows.append(("Iron sword blows to fell it", String(blows0), String(blows1)))
		rows.append(("Its blow (before armour)", oneDecimal(d.dmg), oneDecimal(o.mobDamage ?? d.dmg)))
		rows.append(("Speed", oneDecimal(d.speed), oneDecimal(o.speed ?? d.speed)))
		return rows
	}
}

/// A slider's range: its top in normal play, or in sandbox mode
func sbRange(_ lo: Double, _ hi: Double, _ sbHi: Double, _ sb: Bool) -> ClosedRange<Double> {
	let top: Double = sb ? sbHi : hi
	return lo...top
}

/// A number with one decimal place ("4.5")
func oneDecimal(_ v: Double) -> String { return String(format: "%.1f", v) }

/// Folders, saved versions and the mods this one needs (on the INFO tab)
struct ModOrganizeSection: View {
	@ObservedObject var s: ModSession
	@State var label: String = ""
	@State var versions: [ModVersionInfo] = []
	@State var note: String = ""
	@State var loaded: Bool = false
	@State var confirmFile: String = ""
	/// the other installed mods (read when the section opens and after a change)
	@State var entries: [ModEntry] = []
	@State var folders: [String] = []

	var body: some View {
		VStack(spacing: 10) {
			folderSection
			needsSection
			versionsSection
		}
		.onAppear { self.load() }
	}

	func load() {
		if loaded { return }
		loaded = true
		refresh()
	}

	func refresh() {
		versions = ModStore.versions(s.mod.id)
		let me: String = s.mod.id
		entries = ModStore.entries().filter { $0.id != me }
		folders = ModStore.folders()
	}

	var folderSection: some View {
		let names: [String] = Array(folders.prefix(6))
		return ModSection(title: "FOLDER", help: "Mods in the same folder are listed together") {
			ModTextField(label: "Folder", text: s.modBind(\.folder), placeholder: "e.g. Monsters")
			if !names.isEmpty {
				HStack(spacing: 6) {
					ForEach(names, id: \.self) { f in self.folderButton(f) }
				}
			}
		}
	}

	func folderButton(_ f: String) -> some View {
		let col: Color = s.mod.folder == f ? ModUI.accent : Color(ui: 0x4A4A50)
		return SmallButton(title: f, color: col) {
			self.s.mod.folder = f
			self.s.touch()
		}
	}

	var needsSection: some View {
		let deps: [String] = ModStore.dependencies(s.mod)
		let others: [ModEntry] = Array(entries.filter { e in !deps.contains(e.id) && e.pack != nil }.prefix(5))
		return ModSection(title: "NEEDS OTHER MODS", help: "A world using this mod needs these too. Mods whose blocks or items this one uses are found by themselves.") {
			if deps.isEmpty { Text("None.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim) }
			ForEach(deps, id: \.self) { d in self.depRow(d) }
			if !others.isEmpty {
				Text("Add a mod it needs:").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				HStack(spacing: 6) {
					ForEach(others) { e in self.addDepButton(e) }
				}
			}
		}
	}

	func depRow(_ d: String) -> some View {
		let e: ModEntry? = entries.first { $0.id == d }
		let name: String = e?.pack?.name ?? joinText("Missing mod (", d, ")")
		var state: String = "not installed"
		if let x = e { state = x.enabled ? "on" : "off" }
		let col: Color = e == nil ? Color(ui: 0xFF9A7A) : Color.white
		let mine: Bool = s.mod.requires.contains(d)
		return HStack {
			Text(verbatim: name).font(.pixel(12)).foregroundColor(col)
			Text(verbatim: state).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			if mine {
				SmallButton(title: "REMOVE", color: ModUI.red) { self.removeDep(d) }
			}
		}
	}

	func removeDep(_ d: String) {
		s.mod.requires.removeAll { $0 == d }
		s.touch()
	}

	func addDepButton(_ e: ModEntry) -> some View {
		let name: String = e.pack?.name ?? e.id
		return SmallButton(title: name, color: ModUI.blue) {
			self.s.mod.requires.append(e.id)
			self.s.touch()
		}
	}

	var versionsSection: some View {
		let hint: String = joinText("Version ", s.mod.version)
		return ModSection(title: "SAVED VERSIONS", help: "Keep a copy of the mod as it is now, and go back to it later (the last 12 are kept)") {
			HStack(spacing: 6) {
				ModTextField(label: "Name for this version", text: $label, placeholder: hint)
				SmallButton(title: "SAVE VERSION", color: ModUI.accent) { self.saveVersion() }
			}
			if !note.isEmpty { Text(verbatim: note).font(.pixel(11, .semibold)).foregroundColor(ModUI.gold) }
			ForEach(versions) { v in self.versionRow(v) }
		}
	}

	func saveVersion() {
		_ = s.save()
		let name: String = label.isEmpty ? joinText("Version ", s.mod.version) : label
		note = ModStore.saveVersion(s.mod, label: name) ? "Version saved." : "It could not be saved."
		label = ""
		versions = ModStore.versions(s.mod.id)
	}

	func versionRow(_ v: ModVersionInfo) -> some View {
		let sure: Bool = confirmFile == v.file
		let when: String = joinText("v", v.version, " \u{00B7} ", shortDate(v.time))
		let col: Color = Color(ui: sure ? 0xC04030 : 0x6A5A3A)
		return HStack {
			VStack(alignment: .leading, spacing: 1) {
				Text(verbatim: v.label).font(.pixel(12)).foregroundColor(Color.white)
				Text(verbatim: when).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: sure ? "SURE?" : "RESTORE", color: col) { self.restore(v) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.deleteVersion(v) }
		}
	}

	func restore(_ v: ModVersionInfo) {
		if confirmFile != v.file {
			confirmFile = v.file
			note = "Restoring replaces the mod as it is now (a copy of it is kept first). Tap SURE? to go ahead."
			return
		}
		confirmFile = ""
		if let p = ModStore.restoreVersion(s.mod.id, v.file) {
			s.mod = p
			s.dirty = false
			s.recheck()
			note = joinText("Restored ", v.label, ".")
		} else {
			note = "That version could not be read."
		}
		versions = ModStore.versions(s.mod.id)
	}

	func deleteVersion(_ v: ModVersionInfo) {
		ModStore.deleteVersion(v.file)
		versions = ModStore.versions(s.mod.id)
	}
}

extension ModCreatorView {
	/// The folders the mods are filed under: tap one to see only those mods
	var folderChips: some View {
		let names: [String] = ModStore.folders()
		return Group {
			if !names.isEmpty {
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						SmallButton(title: "ALL MODS", color: folder.isEmpty ? ModUI.accent : Color(ui: 0x4A4A50)) { folder = "" }
						ForEach(names, id: \.self) { f in
							SmallButton(title: f.uppercased(), color: folder == f ? ModUI.accent : Color(ui: 0x4A4A50)) { folder = f }
						}
					}
				}
			}
		}
	}
}

extension ModEditorView {
	/// Starting a new block, item or creature from one of the game's own (its picture and numbers)
	@ViewBuilder
	func fromGame(_ k: ModOverrideKind) -> some View {
		if gamePick == k {
			GamePickerView(kind: k, title: joinText("START FROM A ", k.name.uppercased()), pick: { raw, it in startFromGame(k, raw, it) }, cancel: { gamePick = nil })
		} else {
			SmallButton(title: joinText("+ START FROM A ", k.name.uppercased()), color: ModUI.blue) { gamePick = k }
		}
	}

	func startFromGame(_ k: ModOverrideKind, _ raw: Int, _ it: Item?) {
		gamePick = nil
		switch k {
		case .block:
			guard let t = Tile(rawValue: UInt8(clampI(raw, 0, 255))) else { return }
			var b: ModBlock = ModBlock.fromGame(t)
			b.id = session.mod.freshID("b")
			session.mod.blocks.append(b)
			session.touch()
			target = .block(b.id)
		case .item:
			guard let i = it else { return }
			var m: ModItem = ModItem.fromGame(i)
			m.id = session.mod.freshID("i")
			session.mod.items.append(m)
			session.touch()
			target = .item(m.id)
		case .creature:
			guard let kind = MobKind(rawValue: raw) else { return }
			var m: ModMob = ModMob.fromGame(kind)
			m.id = session.mod.freshID("c")
			session.mod.mobs.append(m)
			session.touch()
			target = .mob(m.id)
		}
	}

	/// Switches a piece of content off for now (it stays in the mod) or back on
	func toggleOff(_ id: String) {
		if session.mod.off.contains(id) {
			session.mod.off.removeAll { $0 == id }
		} else {
			session.mod.off.append(id)
		}
		session.touch()
	}
}

// MARK: - Mod Creator+: ore controls, the generation preview and the hardness reference

/// More ore controls: where in the ground, what shape, how often, which biomes, which host blocks,
/// near which other ore, and a preview made by the real world generator
struct OreControlsView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var preview: PixelBuf? = nil
	@State var previewCount: Int = 0
	@State var previewRev: Int = -1

	func b<T>(_ kp: WritableKeyPath<ModOre, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.ores, id, kp, d) }
	var ore: ModOre { return s.mod.ores.first { $0.id == id } ?? ModOre() }

	var body: some View {
		let o: ModOre = ore
		return VStack(spacing: 10) {
			whereSection(o)
			ModSection(title: "HOST BLOCKS", help: "Pick the exact blocks it may replace (none picked: the \u{201C}Forms in\u{201D} choice above)") {
				hostChips(o)
			}
			ModSection(title: "NEAR ANOTHER ORE", help: "Veins only start within three blocks of this one") {
				nearChips(o)
			}
			previewSection
		}
	}

	func whereSection(_ o: ModOre) -> some View {
		let help: String = ModOre.placeHelp[clampI(o.place, 0, 3)]
		return ModSection(title: "WHERE IT FORMS") {
			ChoiceRow(options: ModOre.placeNames, selected: b(\.place, 0), columns: 2)
			Text(verbatim: help).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Text("Vein shape").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			ChoiceRow(options: ModOre.shapeNames, selected: b(\.shape, 0), columns: 3)
			StatSlider(label: "Chance a stretch of ground has it", value: b(\.rarity, 1), range: 0.02...1.0, step: 0.01, format: "%.2f")
			ModBiomePicker(biomes: b(\.biomes, []))
		}
	}

	var previewSection: some View {
		ModSection(title: "PREVIEW", help: "A slice of a sample world, made by the game's own generator: the pink is your ore") {
			HStack(alignment: .top, spacing: 12) {
				previewImage
				previewNotes
			}
		}
	}

	var previewImage: AnyView {
		guard let img = preview else { return AnyView(EmptyView()) }
		let w: CGFloat = CGFloat(img.w * 2)
		let h: CGFloat = CGFloat(img.h)
		return AnyView(pixImage(img).resizable().interpolation(.none).frame(width: w, height: h)
			.overlay(Rectangle().stroke(Color.white.opacity(0.3), lineWidth: 1)))
	}

	var previewNotes: some View {
		let made: Bool = preview != nil
		let title: String = made ? "MAKE IT AGAIN" : "MAKE PREVIEW"
		let count: String = joinText(String(previewCount), " blocks in ", String(ModOrePreview.chunks * chunkW), " columns")
		let fresh: String = previewRev == s.rev ? "Up to date." : "Settings changed since: make it again."
		return VStack(alignment: .leading, spacing: 6) {
			SmallButton(title: title, color: ModUI.blue) { self.makePreview() }
			if made {
				Text(verbatim: count).font(.pixel(11, .semibold)).foregroundColor(Color.white)
				Text(verbatim: fresh).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				Text("Sky blue, caves black, water blue, lava orange.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
		}
	}

	func makePreview() {
		let r: (PixelBuf, Int) = ModOrePreview.render(ore, s.mod)
		preview = r.0
		previewCount = r.1
		previewRev = s.rev
	}

	func hostChips(_ o: ModOre) -> some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 6)]
		var keys: [String] = ModGround.hosts.map { ModGround.key($0) }
		for blk in s.mod.blocks where blk.id != o.block { keys.append(s.mod.key(blk.id)) }
		let chosen: [String] = o.hosts
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(keys, id: \.self) { k in
				ToggleChip(title: ModGround.name(k, self.s.mod), on: chosen.contains(k)) { self.flipHost(k) }
			}
		}
	}

	func flipHost(_ k: String) {
		let hosts: Binding<[String]> = b(\.hosts, [])
		if hosts.wrappedValue.contains(k) {
			hosts.wrappedValue.removeAll { $0 == k }
		} else if hosts.wrappedValue.count < 8 {
			hosts.wrappedValue.append(k)
		}
	}

	func nearChips(_ o: ModOre) -> some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 100), spacing: 6)]
		var keys: [String] = [""] + ModGround.ores.map { ModGround.key($0) }
		for blk in s.mod.blocks where blk.id != o.block { keys.append(s.mod.key(blk.id)) }
		let cur: String = o.near
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(keys, id: \.self) { k in
				ToggleChip(title: k.isEmpty ? "ANYWHERE" : ModGround.name(k, self.s.mod), on: cur == k) { self.b(\.near, "").wrappedValue = k }
			}
		}
	}
}

/// How long a mod block takes to break with each tool, worked out with the game's own mining rules
struct BlockMiningTimes: View {
	let block: ModBlock
	let tools: [ModItem]

	var body: some View {
		let cls: ToolType = ToolType(rawValue: block.tool) ?? .pickaxe
		let tiers: [Tier] = [.wood, .stone, .iron, .diamond, .voidium]
		return ModSection(title: "MINING TIMES", help: "From the game's own mining rules") {
			row("Bare hands", miningSecondsFor(hardness: block.hardness, tier: block.tier, blockTool: cls, unbreakable: block.unbreakable, nil, 0, toolSpeed: 1))
			ForEach(tiers, id: \.self) { t in
				row(joinText(t.name, " ", cls.name.lowercased()), miningSecondsFor(hardness: block.hardness, tier: block.tier, blockTool: cls, unbreakable: block.unbreakable, cls, t.rawValue, toolSpeed: t.mineSpeed))
			}
			ForEach(tools) { it in
				let k: ToolType = ToolType(rawValue: it.toolType) ?? .pickaxe
				row(joinText(it.name, " (yours)"), miningSecondsFor(hardness: block.hardness, tier: block.tier, blockTool: cls, unbreakable: block.unbreakable, k, it.toolTier, toolSpeed: it.toolSpeed))
			}
		}
	}

	func row(_ name: String, _ t: Double?) -> some View {
		HStack {
			Text(verbatim: name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			Text(verbatim: secondsText(t)).font(.pixel(11)).foregroundColor(t == nil ? Color(ui: 0xFF9A7A) : Color.white)
		}
	}
}

/// Every game block with its hardness, the tool that mines it, the tier it needs, and how long each
/// tool takes (the mod's own tools too), all from the game's mining rules
struct HardnessReferenceView: View {
	@ObservedObject var s: ModSession
	@State var filter: String = ""
	@State var picked: Int = Int(Tile.stone.rawValue)

	var body: some View {
		let tiles: [Tile] = ModOverrideCheck.tiles().filter { t in filter.isEmpty || t.name.lowercased().contains(filter.lowercased()) }
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 120), spacing: 6)]
		let t: Tile = Tile(rawValue: UInt8(clampI(picked, 0, 255))) ?? .stone
		return VStack(alignment: .leading, spacing: 10) {
			Text("The game's blocks and how hard they are. Tap one to see every tool's mining time.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			detail(t)
			ModTextField(label: "Search", text: $filter, placeholder: "block name")
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(tiles, id: \.self) { tile in
					Button { picked = Int(tile.rawValue) } label: {
						HStack(spacing: 6) {
							pixImage(tileBuf(tile)).resizable().interpolation(.none).frame(width: 26, height: 26)
							VStack(alignment: .leading, spacing: 1) {
								Text(verbatim: tile.name).font(.pixel(10)).foregroundColor(Color.white).lineLimit(1)
								Text(verbatim: tile.def.hard >= 9999 ? "unbreakable" : String(format: "hardness %.2f", tile.def.hard)).font(.pixel(9, .semibold)).foregroundColor(ModUI.dim)
							}
							Spacer(minLength: 0)
						}
						.padding(4)
						.background(picked == Int(tile.rawValue) ? ModUI.accent : ModUI.card)
					}
					.buttonStyle(.plain)
				}
			}
		}
	}

	func detail(_ t: Tile) -> some View {
		let cls: ToolType = toolClass(t)
		let d: TileDef = t.def
		let tools: [ModItem] = s.mod.items.filter { $0.kind == .tool }
		return ModSection(title: t.name.uppercased()) {
			HStack(spacing: 10) {
				pixImage(tileBuf(t)).resizable().interpolation(.none).frame(width: 48, height: 48)
				VStack(alignment: .leading, spacing: 2) {
					Text(verbatim: d.hard >= 9999 ? "Unbreakable" : String(format: "Hardness %.2f", d.hard)).font(.pixel(12)).foregroundColor(Color.white)
					Text(verbatim: joinText("Best tool: ", cls.name.lowercased(), d.tier > 0 ? joinText(" · needs tier ", String(d.tier), " (", Tier(rawValue: d.tier)?.name ?? "", ")") : " · any tool")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				}
			}
			row("Bare hands", miningSeconds(t, nil, nil))
			ForEach(Tier.allCases, id: \.self) { tr in
				row(joinText(tr.name, " ", cls.name.lowercased()), miningSeconds(t, cls, tr))
			}
			let wrong: ToolType = cls == .pickaxe ? .axe : .pickaxe
			row(joinText("Iron ", wrong.name.lowercased(), " (wrong tool)"), miningSeconds(t, wrong, .iron))
			ForEach(tools) { it in
				let k: ToolType = ToolType(rawValue: it.toolType) ?? .pickaxe
				let tier: Tier = Tier(rawValue: clampI(it.toolTier, 1, 9)) ?? .wood
				row(joinText(it.name, " (yours)"), miningSeconds(t, k, tier, toolSpeed: it.toolSpeed))
			}
		}
	}

	func row(_ name: String, _ v: Double?) -> some View {
		HStack {
			Text(verbatim: name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			Text(verbatim: secondsText(v)).font(.pixel(11)).foregroundColor(v == nil ? Color(ui: 0xFF9A7A) : Color.white)
		}
	}
}

// MARK: - Mod Creator+: the Sprite Studio

/// The Sprite Studio's tools
enum SpriteTool: Int, CaseIterable {
	case pen, erase, fill, pick, line, box, circle, select, shade, dither, pan
	var name: String {
		switch self {
		case .pen: return "PEN"
		case .erase: return "ERASE"
		case .fill: return "FILL"
		case .pick: return "PICK"
		case .line: return "LINE"
		case .box: return "BOX"
		case .circle: return "CIRCLE"
		case .select: return "SELECT"
		case .shade: return "SHADE"
		case .dither: return "DITHER"
		case .pan: return "PAN"
		}
	}
	/// tools that paint with the brush as the finger moves
	var brush: Bool { return self == .pen || self == .erase || self == .shade || self == .dither }
	/// tools drawn from where the finger went down to where it lifts
	var shape: Bool { return self == .line || self == .box || self == .circle }
}

/// A rectangle of pixels the SELECT tool has chosen (inclusive corners)
struct SpriteSel: Equatable {
	var x0: Int
	var y0: Int
	var x1: Int
	var y1: Int
	var w: Int { return x1 - x0 + 1 }
	var h: Int { return y1 - y0 + 1 }
	func contains(_ x: Int, _ y: Int) -> Bool { return x >= x0 && x <= x1 && y >= y0 && y <= y1 }
	static func from(_ a: (Int, Int), _ b: (Int, Int)) -> SpriteSel {
		return SpriteSel(x0: min(a.0, b.0), y0: min(a.1, b.1), x1: max(a.0, b.0), y1: max(a.1, b.1))
	}
}

/// One pixel painted in the current stroke, and what it was before (pixel-perfect lines put back the
/// corner pixel of an L, and shading touches each pixel once a stroke)
struct StrokeCell {
	var x: Int
	var y: Int
	var before: UInt32
}

/// How the Sprite Studio paints: brushes, opacity and blending, shading, shapes and selections. Pure
/// functions on a picture, so they are the same in the editor and the tests.
enum SpritePaint {
	/// the pixels a brush of this size and shape covers, centred on (x, y)
	static func brushCells(_ x: Int, _ y: Int, _ size: Int, _ round: Bool) -> [(Int, Int)] {
		let s: Int = clampI(size, 1, 8)
		if s == 1 { return [(x, y)] }
		var out: [(Int, Int)] = []
		let lo: Int = -(s - 1) / 2
		let hi: Int = s / 2
		let r: Double = Double(s) * 0.5
		for dy in lo...hi {
			for dx in lo...hi {
				if round {
					let fx: Double = Double(dx) - Double(lo + hi) * 0.5
					let fy: Double = Double(dy) - Double(lo + hi) * 0.5
					if fx * fx + fy * fy > r * r + 0.25 { continue }
				}
				out.append((x + dx, y + dy))
			}
		}
		return out
	}

	/// `src` laid over `dst` (both 0xAARRGGBB, not premultiplied)
	static func over(_ src: UInt32, _ dst: UInt32) -> UInt32 {
		let sa: Double = Double(src >> 24) / 255.0
		if sa >= 0.999 { return src }
		let da: Double = Double(dst >> 24) / 255.0
		let oa: Double = sa + da * (1.0 - sa)
		if oa <= 0.001 { return 0 }
		let k: Double = da * (1.0 - sa)
		let r: Double = (Double((src >> 16) & 0xFF) * sa + Double((dst >> 16) & 0xFF) * k) / oa
		let g: Double = (Double((src >> 8) & 0xFF) * sa + Double((dst >> 8) & 0xFF) * k) / oa
		let b: Double = (Double(src & 0xFF) * sa + Double(dst & 0xFF) * k) / oa
		let a: UInt32 = UInt32(clampD(oa * 255.0, 0, 255).rounded())
		return (a << 24) | (UInt32(clampD(r, 0, 255).rounded()) << 16) | (UInt32(clampD(g, 0, 255).rounded()) << 8) | UInt32(clampD(b, 0, 255).rounded())
	}

	/// The colour as the pen lays it: its opacity scaled by the pen's
	static func penColor(_ c: UInt32, _ opacity: Double) -> UInt32 {
		let a: Double = Double(c >> 24) * clampD(opacity, 0.05, 1)
		return (UInt32(clampD(a, 8, 255).rounded()) << 24) | (c & 0xFFFFFF)
	}

	/// One pixel painted: laid over what is there (blend), or set as it is (then a part see-through
	/// colour makes a part see-through pixel)
	static func paint(_ px: inout ModPixels, _ x: Int, _ y: Int, _ c: UInt32, _ blend: Bool) {
		if blend { px.setARGB(x, y, over(c, px.argb(x, y))) } else { px.setARGB(x, y, c) }
	}

	/// Rubbing out: all of it at full strength, some of its opacity at less
	static func erase(_ px: inout ModPixels, _ x: Int, _ y: Int, _ opacity: Double) {
		if opacity >= 0.99 { px.setARGB(x, y, 0); return }
		let c: UInt32 = px.argb(x, y)
		if c == 0 { return }
		let a: Double = Double(c >> 24) * (1.0 - clampD(opacity, 0, 1))
		px.setARGB(x, y, a < 8 ? 0 : ((UInt32(a.rounded()) << 24) | (c & 0xFFFFFF)))
	}

	/// Shading: a shade darker or lighter, its opacity kept
	static func shade(_ px: inout ModPixels, _ x: Int, _ y: Int, _ darker: Bool) {
		let c: UInt32 = px.argb(x, y)
		if c == 0 { return }
		px.setARGB(x, y, (c & 0xFF000000) | shadeRGB(c & 0xFFFFFF, darker ? 0.82 : 1.2))
	}

	/// A box, its edge or filled
	static func boxCells(_ a: (Int, Int), _ b: (Int, Int), _ filled: Bool) -> [(Int, Int)] {
		var out: [(Int, Int)] = []
		let x0: Int = min(a.0, b.0)
		let x1: Int = max(a.0, b.0)
		let y0: Int = min(a.1, b.1)
		let y1: Int = max(a.1, b.1)
		for y in y0...y1 {
			for x in x0...x1 where filled || x == x0 || x == x1 || y == y0 || y == y1 { out.append((x, y)) }
		}
		return out
	}

	/// An ellipse fitted in the box from a to b, its edge or filled
	static func ellipseCells(_ a: (Int, Int), _ b: (Int, Int), _ filled: Bool) -> [(Int, Int)] {
		let x0: Int = min(a.0, b.0)
		let x1: Int = max(a.0, b.0)
		let y0: Int = min(a.1, b.1)
		let y1: Int = max(a.1, b.1)
		let cx: Double = Double(x0 + x1 + 1) * 0.5
		let cy: Double = Double(y0 + y1 + 1) * 0.5
		let rx: Double = Double(x1 - x0 + 1) * 0.5
		let ry: Double = Double(y1 - y0 + 1) * 0.5
		func inside(_ x: Int, _ y: Int) -> Bool {
			if x < x0 || x > x1 || y < y0 || y > y1 { return false }
			let dx: Double = (Double(x) + 0.5 - cx) / rx
			let dy: Double = (Double(y) + 0.5 - cy) / ry
			return dx * dx + dy * dy <= 1.0 + 0.12 / max(1.0, min(rx, ry))
		}
		var out: [(Int, Int)] = []
		for y in y0...y1 {
			for x in x0...x1 where inside(x, y) {
				let edge: Bool = !inside(x - 1, y) || !inside(x + 1, y) || !inside(x, y - 1) || !inside(x, y + 1)
				if filled || edge { out.append((x, y)) }
			}
		}
		return out
	}

	/// Pixel-perfect lines: when the newest pixel makes an L with the two before it, the corner
	/// pixel is put back (single-pixel lines stay one pixel thick)
	static func perfectCorner(_ stroke: [StrokeCell], _ x: Int, _ y: Int) -> Bool {
		if stroke.count < 2 { return false }
		let a: StrokeCell = stroke[stroke.count - 2]
		let b: StrokeCell = stroke[stroke.count - 1]
		if abs(a.x - x) != 1 || abs(a.y - y) != 1 { return false }
		return (b.x == a.x && b.y == y) || (b.y == a.y && b.x == x)
	}

	/// The pixels of a selection, lifted out of the picture
	static func cut(_ px: ModPixels, _ s: SpriteSel) -> ModPixels {
		var o = ModPixels(w: max(1, s.w), h: max(1, s.h))
		for y in 0..<s.h {
			for x in 0..<s.w { o.setARGB(x, y, px.argb(s.x0 + x, s.y0 + y)) }
		}
		return o
	}

	/// Pixels laid into the picture at (ox, oy); clear pixels leave what is under them
	static func drop(_ px: inout ModPixels, _ part: ModPixels, _ ox: Int, _ oy: Int) {
		for y in 0..<part.h {
			for x in 0..<part.w {
				let c: UInt32 = part.argb(x, y)
				if c != 0 { px.setARGB(ox + x, oy + y, over(c, px.argb(ox + x, oy + y))) }
			}
		}
	}

	static func clearSel(_ px: inout ModPixels, _ s: SpriteSel) {
		for y in s.y0...s.y1 {
			for x in s.x0...s.x1 { px.setARGB(x, y, 0) }
		}
	}
}

/// Colour sets for the Sprite Studio, and the player's own saved colours (kept on this iPad)
enum SpritePalettes {
	static let names: [String] = ["GAME", "EARTH", "METAL", "SKIN", "SKY", "FIRE", "GREYS", "MINE"]
	static let sets: [[UInt32]] = [
		modPalette,
		[0x2A1A10, 0x4A2E1A, 0x6A4224, 0x8A5A30, 0xAA7A44, 0xC89A5C, 0xE0BC80, 0xF0DCA8, 0x3A4A1E, 0x4E6A26, 0x5DAA3A, 0x8ACA5A,
		 0x5A5048, 0x7A7064, 0x9A9080, 0xC0B8A4],
		[0x1E2028, 0x3A3E4A, 0x5A606E, 0x7E8696, 0xA8B0BE, 0xD0D8E4, 0x6A4A20, 0xA8783A, 0xE0B050, 0xFFE08A, 0x4A1E1E, 0x8A3A2A,
		 0x2AA8A0, 0x6FE6EC, 0x8A3CD0, 0xD8A8FF],
		[0x3A2014, 0x6A3A24, 0x9A5A3A, 0xC88660, 0xE8B090, 0xF8D8C0, 0x7A2A3A, 0xC04A5A, 0x2A3A6A, 0x4A6AAA, 0x2A5A3A, 0x5A9A5A,
		 0xD8C8A0, 0xF0E8D0, 0x6A4A8A, 0xA88AC8],
		[0x0A1030, 0x1D2B53, 0x2A4A8A, 0x3E86D8, 0x6AA8F0, 0xB4DCFF, 0xF0F8FF, 0xFFFFFF, 0x0A3A4A, 0x1A6A7A, 0x3AA0B0, 0x7AD0D8,
		 0xF08A4A, 0xF0B06A, 0x8A6AB0, 0xC8A8E0],
		[0x3A0A0A, 0x7A1A0A, 0xB0300A, 0xE0601A, 0xFF8A30, 0xFFC050, 0xFFE88A, 0xFFFFD0, 0x2A0A3A, 0x5A1A8A, 0x9A3AE0, 0xC880FF,
		 0x0A3A2A, 0x1A8A5A, 0x3AE0A0, 0xA0FFD8],
		[0x000000, 0x111111, 0x222222, 0x333333, 0x444444, 0x555555, 0x666666, 0x777777, 0x888888, 0x999999, 0xAAAAAA, 0xBBBBBB,
		 0xCCCCCC, 0xDDDDDD, 0xEEEEEE, 0xFFFFFF]
	]
	static let key: String = "pr.sprite.myColours"

	/// The player's own colours (0xAARRGGBB, opacity kept)
	static func loadMine() -> [UInt32] {
		guard let list = UserDefaults.standard.array(forKey: key) as? [Int] else { return [] }
		return list.prefix(32).map { UInt32(truncatingIfNeeded: $0) }
	}

	static func saveMine(_ list: [UInt32]) {
		UserDefaults.standard.set(list.prefix(32).map { Int($0) }, forKey: key)
	}
}

/// The pixel editor used for every picture in the Mod Creator: zoom and pan, brushes of any size
/// (square or round) with opacity and blending, pixel-perfect lines, eraser, fill, colour picker,
/// lines, boxes and circles (open or filled), selections (move, copy, paste, flip, delete), shading
/// and dithering, mirror drawing, undo and redo, flips, shifts and turns, palettes and the player's
/// own colours, a reference picture beside or under the canvas (or copied in as a starting sample),
/// the outline switch, other sizes, copying in and out as text or a picture, the sprite library, and
/// onion skin and an animation preview for sprites with frames.
struct PixelEditorView: View {
	@Binding var pixels: ModPixels
	var maxSide: CGFloat = 320
	/// the sprite's other frames (onion skin and the animation preview)
	var frames: [ModPixels] = []
	var frameIndex: Int = 0
	/// sizes it may change to (empty: its size is fixed here)
	var sizes: [Int] = []
	/// the outline it has when none is chosen (creatures and items yes, blocks no)
	var outlineDefault: Bool = true
	/// called instead of resizing just this picture (a creature resizes all its frames together)
	var onResize: ((Int, Int) -> Void)? = nil

	@State var color: UInt32 = 0xFF5DAA3A
	@State var tool: Int = 0
	@State var mirror: Bool = false
	@State var undo: [ModPixels] = []
	@State var redo: [ModPixels] = []
	@State var stroking: Bool = false
	@State var lastCell: Int = -1
	@State var lastXY: (Int, Int)? = nil
	@State var mixR: Double = 120
	@State var mixG: Double = 160
	@State var mixB: Double = 90
	@State var showMixer: Bool = false
	@State var zoom: CGFloat = 0
	@State var panX: CGFloat = 0
	@State var panY: CGFloat = 0
	@State var panStart: CGPoint = .zero
	@State var shapeA: (Int, Int)? = nil
	@State var shapeB: (Int, Int)? = nil
	@State var recent: [UInt32] = []
	@State var showGrid: Bool = true
	@State var onion: Bool = true
	@State var ref: PixelBuf? = nil
	@State var refName: String = ""
	@State var refMode: Int = 1
	@State var refOpacity: Double = 0.45
	@State var panel: Int = 0
	@State var note: String = ""
	@State var codeText: String = ""
	@State var libName: String = ""
	@State var library: [SpriteProject] = []
	// brushes, opacity, shapes, shading
	@State var brushSize: Int = 1
	@State var brushRound: Bool = false
	@State var perfect: Bool = true
	@State var filled: Bool = false
	@State var opacity: Double = 1.0
	@State var blend: Bool = true
	@State var darken: Bool = true
	@State var stroke: [StrokeCell] = []
	/// pixels already painted this stroke (each once: lingering does not pile up see-through paint)
	@State var touched: Set<Int> = []
	// selections
	@State var sel: SpriteSel? = nil
	@State var floating: ModPixels? = nil
	@State var floatX: Int = 0
	@State var floatY: Int = 0
	@State var moveFrom: (Int, Int)? = nil
	// palettes
	@State var paletteIx: Int = 0
	@State var mine: [UInt32] = SpritePalettes.loadMine()
	@State var removing: Bool = false

	/// what COPY in a selection keeps, shared by every picture (copy from one, paste into another)
	static var clip: ModPixels? = nil

	var current: SpriteTool { return SpriteTool(rawValue: tool) ?? .pen }

	/// pixels per picture pixel on screen
	var cell: CGFloat {
		let fit: CGFloat = max(3, floor(maxSide / CGFloat(max(pixels.w, pixels.h))))
		return zoom > 0 ? zoom : fit
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .top, spacing: 12) {
				VStack(alignment: .leading, spacing: 6) {
					viewport
					zoomBar
				}
				VStack(alignment: .leading, spacing: 6) {
					toolGrid
					editButtons
					previewBox
					if refMode == 1, let r = ref { refBeside(r) }
				}
			}
			toolOptions
			if sel != nil { selectionBar }
			palette
			if showMixer { mixer }
			panelTabs
			panelBody
			if !note.isEmpty { Text(verbatim: note).font(.pixel(11, .semibold)).foregroundColor(ModUI.gold) }
		}
	}

	// MARK: canvas

	var viewW: CGFloat { return min(maxSide, cell * CGFloat(pixels.w)) }
	var viewH: CGFloat { return min(maxSide, cell * CGFloat(pixels.h)) }

	var viewport: some View {
		let c: CGFloat = cell
		let px: ModPixels = pixels
		let under: PixelBuf? = refMode == 2 ? ref : nil
		let op: Double = refOpacity
		let onionFrame: ModPixels? = (onion && frameIndex > 0 && frameIndex - 1 < frames.count) ? frames[frameIndex - 1] : nil
		let grid: Bool = showGrid
		let ox: CGFloat = panX
		let oy: CGFloat = panY
		let preview: [(Int, Int)] = shapePreview
		let col: UInt32 = SpritePaint.penColor(color, opacity)
		let s: SpriteSel? = sel
		let fl: ModPixels? = floating
		let fx: Int = floatX
		let fy: Int = floatY
		return Canvas { ctx, size in
			PixelEditorView.paintCanvas(&ctx, px, c, ox, oy, under, op, onionFrame, grid)
			PixelEditorView.paintOverlay(&ctx, c, ox, oy, preview, col, s, fl, fx, fy)
		}
		.frame(width: viewW, height: viewH)
		.clipped()
		.overlay(Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 1))
		.contentShape(Rectangle())
		.gesture(DragGesture(minimumDistance: 0).onChanged { v in dragged(v.startLocation, v.location) }.onEnded { v in ended(v.location) })
	}

	/// the cells of the line, box or circle being drawn
	var shapePreview: [(Int, Int)] {
		guard let a = shapeA, let b = shapeB, current.shape else { return [] }
		return shapeCells(a, b)
	}

	func shapeCells(_ a: (Int, Int), _ b: (Int, Int)) -> [(Int, Int)] {
		switch current {
		case .line: return PixelEditorView.lineCells(a, b)
		case .box: return SpritePaint.boxCells(a, b, filled)
		default: return SpritePaint.ellipseCells(a, b, filled)
		}
	}

	static func paintCanvas(_ ctx: inout GraphicsContext, _ px: ModPixels, _ c: CGFloat, _ ox: CGFloat, _ oy: CGFloat, _ under: PixelBuf?, _ op: Double, _ onionFrame: ModPixels?, _ grid: Bool) {
		let w: Int = px.w
		let h: Int = px.h
		for y in 0..<h {
			for x in 0..<w {
				let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
				let checker: Bool = (x + y) % 2 == 0
				ctx.fill(Path(r), with: .color(Color(hex: checker ? 0x3A3A3A : 0x2A2A2A)))
			}
		}
		if let u = under {
			// the reference, stretched to the canvas, under the drawing
			for y in 0..<h {
				for x in 0..<w {
					let sx: Int = min(u.w - 1, x * u.w / max(1, w))
					let sy: Int = min(u.h - 1, y * u.h / max(1, h))
					let v: UInt32 = u.px[sy * u.w + sx]
					if (v >> 24) == 0 { continue }
					let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
					ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(op)))
				}
			}
		}
		if let f = onionFrame {
			for y in 0..<min(h, f.h) {
				for x in 0..<min(w, f.w) {
					let v: UInt32 = f.argb(x, y)
					if (v >> 24) == 0 { continue }
					let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
					ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(0.25)))
				}
			}
		}
		for y in 0..<h {
			for x in 0..<w {
				let v: UInt32 = px.argb(x, y)
				if (v >> 24) == 0 { continue }
				let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
				let a: Double = Double(v >> 24) / 255.0
				ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(a)))
			}
		}
		if grid && c >= 8 {
			for x in 0...w {
				var p = Path()
				p.move(to: CGPoint(x: CGFloat(x) * c - ox, y: -oy))
				p.addLine(to: CGPoint(x: CGFloat(x) * c - ox, y: CGFloat(h) * c - oy))
				ctx.stroke(p, with: .color(Color.white.opacity(x % 8 == 0 ? 0.25 : 0.1)), lineWidth: 1)
			}
			for y in 0...h {
				var p = Path()
				p.move(to: CGPoint(x: -ox, y: CGFloat(y) * c - oy))
				p.addLine(to: CGPoint(x: CGFloat(w) * c - ox, y: CGFloat(y) * c - oy))
				ctx.stroke(p, with: .color(Color.white.opacity(y % 8 == 0 ? 0.25 : 0.1)), lineWidth: 1)
			}
		}
	}

	/// The shape being drawn, the lifted pixels of a selection being moved, and the selection's edge
	static func paintOverlay(_ ctx: inout GraphicsContext, _ c: CGFloat, _ ox: CGFloat, _ oy: CGFloat, _ preview: [(Int, Int)], _ col: UInt32, _ s: SpriteSel?, _ fl: ModPixels?, _ fx: Int, _ fy: Int) {
		let a: Double = Double(col >> 24) / 255.0 * 0.85
		for (x, y) in preview {
			let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
			ctx.fill(Path(r), with: .color(Color(hex: col & 0xFFFFFF).opacity(a)))
		}
		if let f = fl {
			for y in 0..<f.h {
				for x in 0..<f.w {
					let v: UInt32 = f.argb(x, y)
					if v == 0 { continue }
					let r: CGRect = CGRect(x: CGFloat(fx + x) * c - ox, y: CGFloat(fy + y) * c - oy, width: c, height: c)
					ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF).opacity(Double(v >> 24) / 255.0)))
				}
			}
		}
		if let s0 = s {
			let r: CGRect = CGRect(x: CGFloat(s0.x0) * c - ox, y: CGFloat(s0.y0) * c - oy, width: CGFloat(s0.w) * c, height: CGFloat(s0.h) * c)
			ctx.stroke(Path(r), with: .color(Color.black), lineWidth: 3)
			ctx.stroke(Path(r), with: .color(Color.white), lineWidth: 1)
		}
	}

	func cellAt(_ p: CGPoint) -> (Int, Int)? {
		let c: CGFloat = cell
		let x: Int = Int(floor((p.x + panX) / c))
		let y: Int = Int(floor((p.y + panY) / c))
		if x < 0 || y < 0 || x >= pixels.w || y >= pixels.h { return nil }
		return (x, y)
	}

	/// the cell under the finger, kept inside the picture (for selections dragged past the edge)
	func cellClamped(_ p: CGPoint) -> (Int, Int) {
		let c: CGFloat = cell
		let x: Int = clampI(Int(floor((p.x + panX) / c)), 0, pixels.w - 1)
		let y: Int = clampI(Int(floor((p.y + panY) / c)), 0, pixels.h - 1)
		return (x, y)
	}

	func remember() {
		undo.append(pixels)
		if undo.count > 80 { undo.removeFirst() }
		redo.removeAll()
	}

	// MARK: drawing with the finger

	func dragged(_ start: CGPoint, _ p: CGPoint) {
		switch current {
		case .pan:
			panDrag(start, p)
		case .select:
			selectDrag(start, p)
		case .line, .box, .circle:
			guard let xy = cellAt(p) else { return }
			if shapeA == nil, let s = cellAt(start) { shapeA = s }
			shapeB = xy
		case .fill, .pick:
			guard let xy = cellAt(p), !stroking else { return }
			stroking = true
			if current == .pick {
				let picked: UInt32 = pixels.argb(xy.0, xy.1)
				if (picked >> 24) != 0 { pickColor(picked) }
				tool = SpriteTool.pen.rawValue
				return
			}
			remember()
			var px: ModPixels = pixels
			PixelEditorView.floodFill(&px, xy.0, xy.1, SpritePaint.penColor(color, opacity))
			pixels = px
			useColor(color)
		default:
			guard let xy = cellAt(p) else { return }
			brushDrag(xy)
		}
	}

	func panDrag(_ start: CGPoint, _ p: CGPoint) {
		if !stroking {
			stroking = true
			panStart = CGPoint(x: panX, y: panY)
		}
		let maxX: CGFloat = max(0, cell * CGFloat(pixels.w) - viewW)
		let maxY: CGFloat = max(0, cell * CGFloat(pixels.h) - viewH)
		panX = min(maxX, max(0, panStart.x - (p.x - start.x)))
		panY = min(maxY, max(0, panStart.y - (p.y - start.y)))
	}

	/// The brush tools: each pixel the finger crosses (fast strokes are joined up), the brush laid
	/// around it, the mirror copy too
	func brushDrag(_ xy: (Int, Int)) {
		let idx: Int = xy.1 * pixels.w + xy.0
		if !stroking {
			stroking = true
			remember()
			stroke = []
			touched = []
			lastXY = nil
		} else if idx == lastCell {
			return
		}
		lastCell = idx
		var px: ModPixels = pixels
		let path: [(Int, Int)] = lastXY.map { PixelEditorView.lineCells($0, xy).dropFirst().map { $0 } } ?? [xy]
		for (x, y) in path { brushAt(&px, x, y) }
		lastXY = xy
		pixels = px
		if current == .pen || current == .dither { useColor(color) }
	}

	func brushAt(_ px: inout ModPixels, _ x: Int, _ y: Int) {
		let t: SpriteTool = current
		let col: UInt32 = SpritePaint.penColor(color, opacity)
		let single: Bool = t == .pen && brushSize == 1 && perfect && !mirror
		// pixel-perfect: a one-pixel pen stroke never leaves L-shaped corners
		if single && SpritePaint.perfectCorner(stroke, x, y) {
			let b: StrokeCell = stroke.removeLast()
			px.setARGB(b.x, b.y, b.before)
			touched.remove(b.y * px.w + b.x)
		}
		var cells: [(Int, Int)] = SpritePaint.brushCells(x, y, brushSize, brushRound)
		if mirror { cells += cells.map { (px.w - 1 - $0.0, $0.1) } }
		for (cx, cy) in cells {
			if cx < 0 || cy < 0 || cx >= px.w || cy >= px.h { continue }
			let k: Int = cy * px.w + cx
			if touched.contains(k) { continue }
			touched.insert(k)
			let before: UInt32 = px.argb(cx, cy)
			switch t {
			case .erase: SpritePaint.erase(&px, cx, cy, opacity)
			case .shade: SpritePaint.shade(&px, cx, cy, darken)
			case .dither: if (cx + cy) % 2 == 0 { SpritePaint.paint(&px, cx, cy, col, blend) }
			default: SpritePaint.paint(&px, cx, cy, col, blend)
			}
			if single && cx == x && cy == y { stroke.append(StrokeCell(x: cx, y: cy, before: before)) }
		}
	}

	func ended(_ p: CGPoint) {
		if current.shape, let a = shapeA {
			let b: (Int, Int) = cellAt(p) ?? shapeB ?? a
			remember()
			var px: ModPixels = pixels
			let col: UInt32 = SpritePaint.penColor(color, opacity)
			for (x, y) in shapeCells(a, b) {
				SpritePaint.paint(&px, x, y, col, blend)
				if mirror { SpritePaint.paint(&px, px.w - 1 - x, y, col, blend) }
			}
			pixels = px
			useColor(color)
		}
		if current == .select { selectEnded() }
		shapeA = nil
		shapeB = nil
		stroking = false
		lastCell = -1
		lastXY = nil
		stroke = []
		touched = []
	}

	// MARK: selections

	/// Dragging inside the selection lifts its pixels and moves them; anywhere else chooses a new one
	func selectDrag(_ start: CGPoint, _ p: CGPoint) {
		let s0: (Int, Int) = cellClamped(start)
		let cur: (Int, Int) = cellClamped(p)
		if !stroking {
			stroking = true
			if let s = sel, s.contains(s0.0, s0.1) {
				if floating == nil {
					// lift the chosen pixels off the picture to move them
					remember()
					var px: ModPixels = pixels
					floating = SpritePaint.cut(px, s)
					SpritePaint.clearSel(&px, s)
					pixels = px
					floatX = s.x0
					floatY = s.y0
				}
				moveFrom = (s0.0 - floatX, s0.1 - floatY)
			} else {
				dropFloating()
				moveFrom = nil
				sel = SpriteSel.from(s0, s0)
			}
		}
		if let m = moveFrom, let f = floating {
			floatX = cur.0 - m.0
			floatY = cur.1 - m.1
			sel = SpriteSel(x0: floatX, y0: floatY, x1: floatX + f.w - 1, y1: floatY + f.h - 1)
		} else {
			sel = SpriteSel.from(s0, cur)
		}
	}

	func selectEnded() {
		if floating != nil { dropFloating() }
		moveFrom = nil
	}

	/// Puts moved pixels down where they are now
	func dropFloating() {
		guard let f = floating else { return }
		var px: ModPixels = pixels
		SpritePaint.drop(&px, f, floatX, floatY)
		pixels = px
		floating = nil
	}

	var selectionBar: some View {
		HStack(spacing: 4) {
			Text("SELECTION").font(.pixel(10)).foregroundColor(ModUI.dim)
			SmallButton(title: "COPY", color: ModUI.blue) { copySel() }
			SmallButton(title: "PASTE", color: ModUI.blue) { pasteSel() }
			SmallButton(title: "FLIP ↔") { flipSel() }
			SmallButton(title: "DELETE", color: ModUI.red) { deleteSel() }
			SmallButton(title: "DONE") { dropFloating(); sel = nil }
		}
	}

	func copySel() {
		guard let s = sel else { return }
		PixelEditorView.clip = floating ?? SpritePaint.cut(pixels, s)
		note = "Copied. PASTE puts it here or in another picture."
	}

	func pasteSel() {
		guard let c = PixelEditorView.clip else { note = "Copy a selection first."; return }
		dropFloating()
		remember()
		let ox: Int = sel?.x0 ?? 0
		let oy: Int = sel?.y0 ?? 0
		floating = c
		floatX = ox
		floatY = oy
		sel = SpriteSel(x0: ox, y0: oy, x1: ox + c.w - 1, y1: oy + c.h - 1)
		tool = SpriteTool.select.rawValue
		note = "Pasted: drag it where you want it, then DONE."
	}

	func flipSel() {
		guard let s = sel else { return }
		remember()
		if let f = floating {
			floating = f.flippedH()
			return
		}
		var px: ModPixels = pixels
		let part: ModPixels = SpritePaint.cut(px, s).flippedH()
		SpritePaint.clearSel(&px, s)
		SpritePaint.drop(&px, part, s.x0, s.y0)
		pixels = px
	}

	func deleteSel() {
		guard let s = sel else { return }
		remember()
		if floating != nil {
			floating = nil
		} else {
			var px: ModPixels = pixels
			SpritePaint.clearSel(&px, s)
			pixels = px
		}
		sel = nil
	}

	static func lineCells(_ a: (Int, Int), _ b: (Int, Int)) -> [(Int, Int)] {
		var out: [(Int, Int)] = []
		var x0: Int = a.0
		var y0: Int = a.1
		let dx: Int = abs(b.0 - x0)
		let dy: Int = -abs(b.1 - y0)
		let sx: Int = x0 < b.0 ? 1 : -1
		let sy: Int = y0 < b.1 ? 1 : -1
		var err: Int = dx + dy
		var guardN: Int = 0
		while guardN < 512 {
			guardN += 1
			out.append((x0, y0))
			if x0 == b.0 && y0 == b.1 { break }
			let e2: Int = 2 * err
			if e2 >= dy { err += dy; x0 += sx }
			if e2 <= dx { err += dx; y0 += sy }
		}
		return out
	}

	static func boxCells(_ a: (Int, Int), _ b: (Int, Int)) -> [(Int, Int)] {
		return SpritePaint.boxCells(a, b, false)
	}

	static func floodFill(_ px: inout ModPixels, _ sx: Int, _ sy: Int, _ col: UInt32) {
		let target: UInt32 = px.argb(sx, sy)
		if target == col { return }
		var stack: [(Int, Int)] = [(sx, sy)]
		var guardN: Int = 0
		while let cur = stack.popLast() {
			guardN += 1
			if guardN > 40000 { break }
			let (x, y) = cur
			if x < 0 || y < 0 || x >= px.w || y >= px.h { continue }
			if px.argb(x, y) != target { continue }
			px.setARGB(x, y, col)
			stack.append((x + 1, y))
			stack.append((x - 1, y))
			stack.append((x, y + 1))
			stack.append((x, y - 1))
		}
	}

	// MARK: tools

	var zoomBar: some View {
		HStack(spacing: 6) {
			SmallButton(title: "−") { setZoom(cell - (cell > 16 ? 8 : 2)) }
			Text(verbatim: joinText(String(Int(cell)), " px")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			SmallButton(title: "+") { setZoom(cell + (cell >= 16 ? 8 : 2)) }
			SmallButton(title: "FIT") { zoom = 0; panX = 0; panY = 0 }
			SmallButton(title: showGrid ? "GRID ON" : "GRID OFF", color: showGrid ? ModUI.accent : Color(ui: 0x555555)) { showGrid.toggle() }
			if frameIndex > 0 {
				SmallButton(title: onion ? "ONION ON" : "ONION OFF", color: onion ? ModUI.accent : Color(ui: 0x555555)) { onion.toggle() }
			}
		}
	}

	func setZoom(_ z: CGFloat) {
		zoom = min(48, max(3, z))
		panX = 0
		panY = 0
	}

	var toolGrid: some View {
		PlainGrid(count: SpriteTool.allCases.count + 1, per: 3, spacing: 4) { (i: Int) in self.toolButton(i) }
			.frame(width: 250)
	}

	func toolButton(_ i: Int) -> some View {
		if i >= SpriteTool.allCases.count {
			return SmallButton(title: mirror ? "MIRROR ON" : "MIRROR", color: mirror ? ModUI.accent : Color(ui: 0x555555)) { mirror.toggle() }
		}
		let name: String = SpriteTool.allCases[i].name
		return SmallButton(title: name, color: tool == i ? ModUI.accent : Color(ui: 0x555555)) { selectTool(i) }
	}

	func selectTool(_ i: Int) {
		if tool == SpriteTool.select.rawValue && i != tool { dropFloating(); sel = nil }
		tool = i
	}

	/// The chosen tool's settings: brush size and shape, pixel-perfect, filled shapes, darker or lighter
	@ViewBuilder
	var toolOptions: some View {
		let t: SpriteTool = current
		if t.brush || t == .line {
			HStack(spacing: 6) {
				if t.brush {
					Text(verbatim: joinText("BRUSH ", String(brushSize))).font(.pixel(11)).foregroundColor(Color.white)
					SmallButton(title: "−") { brushSize = max(1, brushSize - 1) }
					SmallButton(title: "+") { brushSize = min(8, brushSize + 1) }
					SmallButton(title: brushRound ? "ROUND" : "SQUARE") { brushRound.toggle() }
				}
				if t == .pen && brushSize == 1 {
					SmallButton(title: perfect ? "PIXEL-PERFECT ON" : "PIXEL-PERFECT OFF", color: perfect ? ModUI.accent : Color(ui: 0x555555)) { perfect.toggle() }
				}
				if t == .shade {
					SmallButton(title: darken ? "DARKER" : "LIGHTER", color: darken ? Color(ui: 0x3A3A5A) : Color(ui: 0x8A8A5A)) { darken.toggle() }
				}
			}
		} else if t == .box || t == .circle {
			HStack(spacing: 6) {
				SmallButton(title: filled ? "FILLED" : "OUTLINE", color: filled ? ModUI.accent : Color(ui: 0x555555)) { filled.toggle() }
			}
		} else if t == .select && sel == nil {
			Text("Drag to choose pixels; drag inside the choice to move them.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
		}
	}

	var editButtons: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				SmallButton(title: "UNDO", color: undo.isEmpty ? Color(ui: 0x444444) : Color(ui: 0x5A5A70)) { undoStep() }
				SmallButton(title: "REDO", color: redo.isEmpty ? Color(ui: 0x444444) : Color(ui: 0x5A5A70)) { redoStep() }
				SmallButton(title: "CLEAR", color: ModUI.red) {
					remember()
					var e = ModPixels(w: pixels.w, h: pixels.h)
					e.outline = pixels.outline
					pixels = e
				}
			}
			HStack(spacing: 4) {
				SmallButton(title: "FLIP ↔") { change { $0.flippedH() } }
				SmallButton(title: "FLIP ↕") { change { $0.flippedV() } }
				if pixels.w == pixels.h { SmallButton(title: "TURN") { change { $0.rotated() } } }
			}
			HStack(spacing: 4) {
				SmallButton(title: "◀") { change { $0.shifted(-1, 0) } }
				SmallButton(title: "▶") { change { $0.shifted(1, 0) } }
				SmallButton(title: "▲") { change { $0.shifted(0, -1) } }
				SmallButton(title: "▼") { change { $0.shifted(0, 1) } }
			}
			outlineButton
		}
	}

	var outlineButton: some View {
		let on: Bool = pixels.outlined(outlineDefault)
		return SmallButton(title: on ? "OUTLINE ON" : "OUTLINE OFF", color: on ? ModUI.accent : Color(ui: 0x555555)) {
			var p: ModPixels = pixels
			p.outline = !on
			pixels = p
		}
	}

	func undoStep() {
		floating = nil
		if let last = undo.popLast() {
			redo.append(pixels)
			pixels = last
		}
	}

	func redoStep() {
		if let next = redo.popLast() {
			undo.append(pixels)
			pixels = next
		}
	}

	func change(_ f: (ModPixels) -> ModPixels) {
		dropFloating()
		remember()
		pixels = f(pixels)
	}

	/// what it looks like in the game: actual pixels, outlined or not as chosen
	var previewBox: some View {
		let on: Bool = pixels.outlined(outlineDefault)
		var b: PixelBuf = pixels.buf()
		if on {
			b = padBuf(b)
			b.outline(0x101010)
		}
		let scale: CGFloat = max(1, floor(96 / CGFloat(max(b.w, b.h))))
		return VStack(alignment: .leading, spacing: 4) {
			Text("IN THE GAME").font(.pixel(10)).foregroundColor(ModUI.dim)
			HStack(alignment: .bottom, spacing: 8) {
				pixImage(b).resizable().interpolation(.none).frame(width: CGFloat(b.w) * scale, height: CGFloat(b.h) * scale)
					.background(Color(ui: 0x6AA0D8).opacity(0.5))
				if frames.count > 1 { animation }
			}
			currentSwatch
		}
	}

	/// The colour in use, over a checker so its opacity shows
	var currentSwatch: some View {
		let a: Double = Double(SpritePaint.penColor(color, opacity) >> 24) / 255.0
		let pct: Int = Int((a * 100).rounded())
		return HStack(spacing: 6) {
			ZStack {
				HStack(spacing: 0) {
					Rectangle().fill(Color(hex: 0xC8C8C8)).frame(width: 13, height: 26)
					Rectangle().fill(Color(hex: 0x6A6A6A)).frame(width: 13, height: 26)
				}
				Rectangle().fill(Color(hex: color & 0xFFFFFF).opacity(a)).frame(width: 26, height: 26)
			}
			.overlay(Rectangle().stroke(Color.white, lineWidth: 2))
			Text(verbatim: joinText(String(pixels.w), " x ", String(pixels.h), "  ", String(pct), "%")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
		}
	}

	/// the frames played in a loop (about six a second)
	var animation: some View {
		let fr: [ModPixels] = frames.isEmpty ? [pixels] : frames
		let i: Int = frameIndex
		let cur: ModPixels = pixels
		return TimelineView(.animation) { context in
			let n: Int = max(1, fr.count)
			let k: Int = Int(context.date.timeIntervalSinceReferenceDate * 6.0) % n
			let f: ModPixels = k == i ? cur : fr[k]
			pixImage(f.buf()).resizable().interpolation(.none).frame(width: 56, height: 56 * CGFloat(f.h) / CGFloat(max(1, f.w)))
		}
	}

	func refBeside(_ r: PixelBuf) -> some View {
		let scale: CGFloat = max(1, floor(120 / CGFloat(max(r.w, r.h))))
		return VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: joinText("REFERENCE: ", refName)).font(.pixel(10)).foregroundColor(ModUI.dim).lineLimit(1)
			pixImage(r).resizable().interpolation(.none).frame(width: CGFloat(r.w) * scale, height: CGFloat(r.h) * scale)
				.background(Color.black.opacity(0.35))
		}
	}

	// MARK: colours

	var paletteColors: [UInt32] {
		if paletteIx >= SpritePalettes.sets.count { return mine }
		return SpritePalettes.sets[paletteIx]
	}

	var palette: some View {
		let cols: [UInt32] = paletteColors
		return VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				ForEach(0..<SpritePalettes.names.count, id: \.self) { (i: Int) in self.paletteChip(i) }
			}
			if cols.isEmpty {
				Text("Your own colours go here: mix one, then SAVE COLOUR.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			} else {
				PlainGrid(count: cols.count, per: 16, spacing: 4) { (i: Int) in self.swatch(cols[i]) }
			}
			if !recent.isEmpty {
				HStack(spacing: 4) {
					Text("RECENT").font(.pixel(9)).foregroundColor(ModUI.dim)
					ForEach(0..<recent.count, id: \.self) { (i: Int) in self.swatch(recent[i]) }
				}
			}
			HStack(spacing: 6) {
				SmallButton(title: showMixer ? "HIDE COLOUR MIXER" : "MIX A COLOUR...") { showMixer.toggle() }
				SmallButton(title: "SAVE COLOUR", color: ModUI.blue) { saveColour() }
				if paletteIx >= SpritePalettes.sets.count && !mine.isEmpty {
					SmallButton(title: removing ? "TAP ONE TO REMOVE" : "REMOVE...", color: removing ? ModUI.red : Color(ui: 0x555555)) { removing.toggle() }
				}
			}
		}
	}

	func paletteChip(_ i: Int) -> some View {
		let on: Bool = paletteIx == i
		return SmallButton(title: SpritePalettes.names[i], color: on ? ModUI.blue : Color(ui: 0x4A4A50)) {
			paletteIx = i
			removing = false
		}
	}

	func swatch(_ c0: UInt32) -> some View {
		let c: UInt32 = (c0 >> 24) == 0 ? (0xFF000000 | c0) : c0
		let on: Bool = (color & 0xFFFFFF) == (c & 0xFFFFFF)
		let a: Double = Double(c >> 24) / 255.0
		return Rectangle().fill(Color(hex: c & 0xFFFFFF).opacity(a))
			.frame(width: 30, height: 30)
			.background(Color(ui: 0x8A8A8A))
			.overlay(Rectangle().stroke(on ? Color.white : Color.black, lineWidth: on ? 3 : 1))
			.onTapGesture { self.tapSwatch(c) }
	}

	func tapSwatch(_ c: UInt32) {
		if removing {
			mine.removeAll { $0 == c }
			SpritePalettes.saveMine(mine)
			if mine.isEmpty { removing = false }
			return
		}
		pickColor(0xFF000000 | (c & 0xFFFFFF))
		if (c >> 24) < 255 { opacity = Double(c >> 24) / 255.0 }
		let t: SpriteTool = current
		if t == .erase || t == .pick || t == .pan || t == .select || t == .shade { selectTool(SpriteTool.pen.rawValue) }
	}

	func saveColour() {
		let c: UInt32 = SpritePaint.penColor(color, opacity)
		if mine.contains(c) { note = "That colour is saved already."; return }
		mine.append(c)
		if mine.count > 32 { mine.removeFirst() }
		SpritePalettes.saveMine(mine)
		paletteIx = SpritePalettes.sets.count
		note = "Saved to MINE (kept on this iPad)."
	}

	func pickColor(_ c: UInt32) {
		color = 0xFF000000 | (c & 0xFFFFFF)
		mixR = Double((c >> 16) & 0xFF)
		mixG = Double((c >> 8) & 0xFF)
		mixB = Double(c & 0xFF)
	}

	func useColor(_ c: UInt32) {
		if modPalette.contains(c & 0xFFFFFF) { return }
		recent.removeAll { $0 == c }
		recent.insert(c, at: 0)
		if recent.count > 8 { recent.removeLast() }
	}

	var mixer: some View {
		VStack(spacing: 4) {
			StatSlider(label: "Red", value: mixBind(0), range: 0...255, step: 1, format: "%.0f")
			StatSlider(label: "Green", value: mixBind(1), range: 0...255, step: 1, format: "%.0f")
			StatSlider(label: "Blue", value: mixBind(2), range: 0...255, step: 1, format: "%.0f")
			StatSlider(label: "Opacity (pen)", value: $opacity, range: 0.05...1.0, step: 0.05, format: "%.2f")
			HStack(spacing: 6) {
				SmallButton(title: blend ? "BLEND ON" : "BLEND OFF", color: blend ? ModUI.accent : Color(ui: 0x555555)) { blend.toggle() }
				Text(verbatim: blend ? "See-through paint mixes with what is under it." : "See-through paint makes see-through pixels.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
		}
	}

	func mixBind(_ k: Int) -> Binding<Double> {
		return Binding<Double>(get: {
			k == 0 ? mixR : (k == 1 ? mixG : mixB)
		}, set: { v in
			if k == 0 { mixR = v } else if k == 1 { mixG = v } else { mixB = v }
			let r: UInt32 = UInt32(clampD(mixR, 0, 255))
			let g: UInt32 = UInt32(clampD(mixG, 0, 255))
			let b: UInt32 = UInt32(clampD(mixB, 0, 255))
			color = 0xFF000000 | (r << 16) | (g << 8) | b
			let t: SpriteTool = current
			if !(t == .pen || t == .fill || t.shape || t == .dither) { selectTool(SpriteTool.pen.rawValue) }
		})
	}

	// MARK: panels: reference, size, copy in and out, library

	var panelTabs: some View {
		HStack(spacing: 6) {
			ForEach(0..<4, id: \.self) { i in
				SmallButton(title: ["REFERENCE", "SIZE", "COPY & PASTE", "SPRITE LIBRARY"][i], color: panel == i + 1 ? ModUI.blue : Color(ui: 0x4A4A50)) {
					panel = panel == i + 1 ? 0 : i + 1
					if panel == 4 { library = SpriteLibrary.load() }
				}
			}
		}
	}

	@ViewBuilder
	var panelBody: some View {
		switch panel {
		case 1: referencePanel
		case 2: sizePanel
		case 3: copyPanel
		case 4: libraryPanel
		default: EmptyView()
		}
	}

	var referencePanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("Pick any picture from the game, your library or the clipboard. Show it beside the canvas or under it as a guide, or copy it in as a starting sample (the original never changes).")
				.font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			if ref != nil {
				HStack(spacing: 6) {
					SmallButton(title: "BESIDE", color: refMode == 1 ? ModUI.accent : Color(ui: 0x555555)) { refMode = 1 }
					SmallButton(title: "UNDER", color: refMode == 2 ? ModUI.accent : Color(ui: 0x555555)) { refMode = 2 }
					SmallButton(title: "HIDE", color: refMode == 0 ? ModUI.accent : Color(ui: 0x555555)) { refMode = 0 }
					SmallButton(title: "USE AS SAMPLE", color: ModUI.blue) { useSample() }
					SmallButton(title: "REMOVE", color: ModUI.red) { ref = nil; refName = "" }
				}
				if refMode == 2 { StatSlider(label: "See-through", value: $refOpacity, range: 0.1...0.9, step: 0.05, format: "%.2f") }
			}
			SpriteRefPicker(pick: { b, name in
				ref = b
				refName = name
				if refMode == 0 { refMode = 1 }
				note = joinText("Reference: ", name, ".")
			}, pasteNote: { note = $0 }, size: (pixels.w, pixels.h))
		}
	}

	/// Copies the reference into the canvas as a starting point (fitted to the canvas, or the canvas
	/// sized to it where that is allowed)
	func useSample() {
		guard let r = ref else { return }
		remember()
		var p: ModPixels
		if !sizes.isEmpty && onResize == nil && r.w <= 64 && r.h <= 64 && (sizes.contains(r.w) && sizes.contains(r.h)) {
			p = ModPixels(buf: r)
		} else {
			p = ModPixels.fitted(r, pixels.w, pixels.h)
		}
		p.outline = pixels.outline
		pixels = p
		note = joinText("Copied ", refName, " in to start from. The original is unchanged.")
	}

	var sizePanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			if sizes.isEmpty {
				Text(verbatim: joinText("This picture is always ", String(pixels.w), " x ", String(pixels.h), ".")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			} else {
				Text("New size (KEEP keeps the picture as it is, centred at the bottom; STRETCH scales it)").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				ForEach(sizes, id: \.self) { sz in
					HStack(spacing: 6) {
						Text(verbatim: joinText(String(sz), " x ", String(sz))).font(.pixel(11)).foregroundColor(Color.white).frame(width: 70, alignment: .leading)
						SmallButton(title: "KEEP") { resize(sz, sz, false) }
						SmallButton(title: "STRETCH") { resize(sz, sz, true) }
						if sz != pixels.h && pixels.w != sz {
							SmallButton(title: joinText(String(sz), " x ", String(pixels.h))) { resize(sz, pixels.h, false) }
						}
					}
				}
			}
		}
	}

	func resize(_ w: Int, _ h: Int, _ stretch: Bool) {
		if let f = onResize {
			f(w, h)
			return
		}
		remember()
		var p: ModPixels = stretch ? pixels.scaled(w, h) : pixels.resized(w, h)
		p.outline = pixels.outline
		pixels = p
		zoom = 0
		panX = 0
		panY = 0
	}

	var copyPanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("A sprite code copies a picture exactly (paste it into another mod, or send it to a friend). A picture copied from Photos or a drawing app is shrunk to this size.")
				.font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			HStack(spacing: 6) {
				SmallButton(title: "COPY CODE", color: ModUI.blue) {
					SpriteClipboard.copy(pixels)
					codeText = pixels.spriteCode()
					note = "The sprite code is on the clipboard."
				}
				SmallButton(title: "PASTE CODE", color: ModUI.blue) {
					if let p = SpriteClipboard.pasteCode() ?? ModPixels.fromSpriteCode(codeText) { pasteIn(p) } else { note = "No sprite code on the clipboard (or in the box below)." }
				}
				SmallButton(title: "PASTE PICTURE", color: ModUI.blue) {
					if let p = SpriteClipboard.pasteImage(pixels.w, pixels.h) { pasteIn(p) } else { note = "No picture on the clipboard: copy one first." }
				}
			}
			ModTextField(label: "Sprite code", text: $codeText, placeholder: "PRSPR1:...")
		}
	}

	func pasteIn(_ p0: ModPixels) {
		remember()
		var p: ModPixels = p0
		if p.w != pixels.w || p.h != pixels.h {
			if sizes.contains(p.w) && sizes.contains(p.h) && onResize == nil {
				// fits a size this picture may take: keep it as it is
			} else {
				p = ModPixels.fitted(p0.buf(), pixels.w, pixels.h)
				p.outline = p0.outline
			}
		}
		pixels = p
		note = "Pasted."
	}

	var libraryPanel: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 6) {
				ModTextField(label: "Save as", text: $libName, placeholder: "My sprite")
				SmallButton(title: "SAVE TO LIBRARY", color: ModUI.accent) {
					var pr = SpriteProject()
					pr.name = libName.isEmpty ? "Sprite" : libName
					pr.frames = frames.count > 1 ? frames.enumerated().map { $0.offset == frameIndex ? pixels : $0.element } : [pixels]
					let saved: SpriteProject = SpriteLibrary.put(pr)
					library = SpriteLibrary.load()
					note = joinText("Saved ", saved.name, " to the library.")
				}
			}
			if library.isEmpty { Text("The library is empty.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim) }
			ForEach(library) { pr in
				HStack(spacing: 8) {
					pixImage(pr.frames[0].buf()).resizable().interpolation(.none).frame(width: 36, height: 36).background(Color.black.opacity(0.35))
					VStack(alignment: .leading, spacing: 1) {
						Text(verbatim: pr.name).font(.pixel(12)).foregroundColor(Color.white)
						Text(verbatim: joinText(String(pr.frames[0].w), " x ", String(pr.frames[0].h), pr.frames.count > 1 ? joinText(" · ", String(pr.frames.count), " frames") : "")).font(.pixel(9, .semibold)).foregroundColor(ModUI.dim)
					}
					Spacer()
					SmallButton(title: "OPEN") { pasteIn(pr.frames[min(frameIndex, pr.frames.count - 1)]) }
					SmallButton(title: "REFERENCE") {
						ref = pr.frames[0].buf()
						refName = pr.name
						if refMode == 0 { refMode = 1 }
					}
					SmallButton(title: "✕", color: ModUI.red) {
						SpriteLibrary.delete(pr.id)
						library = SpriteLibrary.load()
					}
				}
			}
		}
	}
}

/// Choosing a reference picture: a game creature (any of its frames), item or block, a sprite from
/// the library, or a picture from the clipboard
struct SpriteRefPicker: View {
	var pick: (PixelBuf, String) -> Void
	var pasteNote: (String) -> Void
	var size: (Int, Int)
	@State var tab: Int = 0
	@State var filter: String = ""
	@State var creature: Int = -1

	static let tabNames: [String] = ["CREATURES", "ITEMS", "BLOCKS", "LIBRARY"]

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			tabRow
			ModTextField(label: "Search", text: $filter, placeholder: "name")
			grid
		}
		.padding(8)
		.background(Color.black.opacity(0.25))
	}

	var tabRow: some View {
		HStack(spacing: 6) {
			ForEach(0..<4, id: \.self) { i in self.tabButton(i) }
			SmallButton(title: "PASTE PICTURE", color: ModUI.blue) { self.paste() }
		}
	}

	func tabButton(_ i: Int) -> some View {
		let col: Color = tab == i ? ModUI.accent : Color(ui: 0x555555)
		return SmallButton(title: SpriteRefPicker.tabNames[i], color: col) {
			self.tab = i
			self.creature = -1
		}
	}

	func paste() {
		let w: Int = min(64, max(16, size.0 * 2))
		let h: Int = min(64, max(16, size.1 * 2))
		if let p = SpriteClipboard.pasteImage(w, h) {
			pick(p.buf(), "Pasted picture")
		} else if let p = SpriteClipboard.pasteCode() {
			pick(p.buf(), "Pasted sprite")
		} else {
			pasteNote("No picture on the clipboard: copy one first.")
		}
	}

	/// A picture to offer: what it shows, its name, and the creature it opens (-1: it is picked)
	struct RefEntry {
		let buf: PixelBuf
		let name: String
		let opens: Int
	}

	/// What the chosen tab offers
	var entries: [RefEntry] {
		var out: [RefEntry] = []
		switch tab {
		case 0:
			if creature >= 0, let k = MobKind(rawValue: creature) {
				let frs: [PixelBuf] = GameSprites.creatureFrames(k)
				let name: String = mobDef(k).name
				for (i, f) in frs.enumerated() { out.append(RefEntry(buf: f, name: joinText(name, " ", String(i + 1)), opens: -1)) }
			} else {
				for k in GameSprites.creatures where match(mobDef(k).name) {
					let f: PixelBuf = GameSprites.creatureFrames(k).first ?? PixelBuf(w: 1, h: 1)
					out.append(RefEntry(buf: f, name: mobDef(k).name, opens: k.rawValue))
				}
			}
		case 1:
			for it in GameSprites.items() where match(it.name) { out.append(RefEntry(buf: itemBuf(it), name: it.name, opens: -1)) }
		case 2:
			for t in GameSprites.tiles() where match(t.name) { out.append(RefEntry(buf: tileBuf(t), name: t.name, opens: -1)) }
		default:
			for pr in SpriteLibrary.load() where match(pr.name) { out.append(RefEntry(buf: pr.frames[0].buf(), name: pr.name, opens: -1)) }
		}
		return out
	}

	var grid: some View {
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 64), spacing: 6)]
		let list: [RefEntry] = entries
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(0..<list.count, id: \.self) { i in self.entryCell(list[i]) }
		}
	}

	func entryCell(_ e: RefEntry) -> some View {
		Button(action: { self.tapped(e) }) { self.label(e.buf, e.name) }.buttonStyle(.plain)
	}

	func tapped(_ e: RefEntry) {
		if e.opens >= 0 { creature = e.opens } else { pick(e.buf, e.name) }
	}

	func match(_ n: String) -> Bool {
		let f: String = filter.trimmingCharacters(in: .whitespaces).lowercased()
		return f.isEmpty || n.lowercased().contains(f)
	}

	func cell(_ b: PixelBuf, _ name: String) -> some View {
		Button { pick(b, name) } label: { label(b, name) }.buttonStyle(.plain)
	}

	func label(_ b: PixelBuf, _ name: String) -> some View {
		VStack(spacing: 2) {
			pixImage(b).resizable().interpolation(.none).frame(width: 40, height: 40 * CGFloat(b.h) / CGFloat(max(1, b.w)))
				.frame(height: 44)
			Text(verbatim: name).font(.pixel(8, .semibold)).foregroundColor(Color.white).lineLimit(1)
		}
		.frame(maxWidth: .infinity, minHeight: 64)
		.background(ModUI.card)
	}
}

/// The sprite library on its own: every saved sprite, to make, open, copy, rename and delete
struct SpriteLibraryScreen: View {
	var back: () -> Void
	@State var list: [SpriteProject] = []
	@State var editing: SpriteProject? = nil
	@State var frame: Int = 0
	@State var loaded: Bool = false

	static let sizes: [Int] = [8, 16, 24, 32]

	var body: some View {
		VStack(spacing: 10) {
			topBar
			ScrollView {
				VStack(spacing: 10) {
					if editing != nil { editor } else { listPage }
				}
				.padding(.bottom, 30)
			}
		}
		.padding(14)
		.frame(maxWidth: 1000)
		.onAppear { self.load() }
	}

	/// Stays at the top while the page scrolls, so there is always a way back
	var topBar: some View {
		HStack(spacing: 8) {
			if editing != nil {
				SmallButton(title: "< LIBRARY", color: ModUI.blue) { self.done() }
				SmallButton(title: "SAVE", color: ModUI.accent) { self.save() }
			} else {
				SmallButton(title: "< MODS") { self.back() }
			}
			Spacer()
			Text("SPRITE LIBRARY").font(.pixel(22)).foregroundColor(ModUI.gold)
			Spacer()
		}
	}

	func load() {
		if loaded { return }
		loaded = true
		list = SpriteLibrary.load()
	}

	var listPage: some View {
		VStack(spacing: 10) {
			Text("Sprites kept here belong to no mod: finish them later, use them as references, or copy them into any mod's content.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			HStack(spacing: 6) {
				ForEach(SpriteLibraryScreen.sizes, id: \.self) { sz in self.newButton(sz) }
			}
			VStack(spacing: 6) {
				ForEach(list) { pr in self.row(pr) }
			}
		}
	}

	func newButton(_ sz: Int) -> some View {
		let title: String = joinText("+ NEW ", String(sz), " x ", String(sz))
		return PixelButton(title: title, color: ModUI.accent) { self.makeNew(sz) }
	}

	func makeNew(_ sz: Int) {
		var p = SpriteProject()
		p.name = joinText("Sprite ", String(list.count + 1))
		p.frames = [ModPixels(w: sz, h: sz)]
		editing = SpriteLibrary.put(p)
		frame = 0
	}

	func row(_ pr: SpriteProject) -> some View {
		let f0: ModPixels = pr.frames[0]
		let frames: String = pr.frames.count == 1 ? " frame \u{00B7} " : " frames \u{00B7} "
		let line: String = joinText(String(f0.w), " x ", String(f0.h), " \u{00B7} ", String(pr.frames.count), frames, shortDate(pr.edited))
		let img: Image = pixImage(f0.buf())
		return HStack(spacing: 8) {
			img.resizable().interpolation(.none).frame(width: 44, height: 44).background(Color.black.opacity(0.35))
			VStack(alignment: .leading, spacing: 1) {
				Text(verbatim: pr.name).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer()
			SmallButton(title: "EDIT", color: ModUI.blue) { self.open(pr) }
			SmallButton(title: "COPY") { self.copy(pr) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.delete(pr) }
		}
		.padding(6)
		.background(PixelBox(color: ModUI.card))
	}

	func open(_ pr: SpriteProject) {
		editing = pr
		frame = 0
	}

	func copy(_ pr: SpriteProject) {
		_ = SpriteLibrary.duplicate(pr.id)
		list = SpriteLibrary.load()
	}

	func delete(_ pr: SpriteProject) {
		SpriteLibrary.delete(pr.id)
		list = SpriteLibrary.load()
	}

	var nameBind: Binding<String> {
		return Binding<String>(get: { self.editing?.name ?? "" }, set: { (v: String) in self.editing?.name = v })
	}

	var pixBind: Binding<ModPixels> {
		return Binding<ModPixels>(get: { self.currentFrame() }, set: { (v: ModPixels) in self.setFrame(v) })
	}

	func currentFrame() -> ModPixels {
		guard let e = editing, frame < e.frames.count else { return ModPixels(w: 16, h: 16) }
		return e.frames[frame]
	}

	func setFrame(_ v: ModPixels) {
		guard var e = editing, frame < e.frames.count else { return }
		e.frames[frame] = v
		editing = e
	}

	var editor: some View {
		let pr: SpriteProject = editing ?? SpriteProject()
		return VStack(alignment: .leading, spacing: 8) {
			ModTextField(label: "Name", text: nameBind, placeholder: "Sprite")
			frameRow(pr.frames.count)
			PixelEditorView(pixels: pixBind, maxSide: 420, frames: pr.frames, frameIndex: frame, sizes: [8, 12, 16, 24, 32, 48, 64], outlineDefault: true,
							onResize: { (w: Int, h: Int) in self.resizeAll(w, h) })
		}
	}

	func frameRow(_ count: Int) -> some View {
		let canAdd: Bool = count < ModLimits.maxFrames
		let canDelete: Bool = count > 1
		return HStack(spacing: 6) {
			ForEach(0..<count, id: \.self) { i in self.frameButton(i) }
			if canAdd { SmallButton(title: "+ FRAME", color: ModUI.blue) { self.addFrame() } }
			if canDelete { SmallButton(title: "DELETE FRAME", color: ModUI.red) { self.deleteFrame() } }
		}
	}

	func frameButton(_ i: Int) -> some View {
		let col: Color = frame == i ? ModUI.accent : Color(ui: 0x555555)
		return SmallButton(title: joinText("FRAME ", String(i + 1)), color: col) { self.frame = i }
	}

	func addFrame() {
		guard var e = editing else { return }
		e.frames.append(e.frames[min(frame, e.frames.count - 1)])
		editing = e
		frame = e.frames.count - 1
	}

	func deleteFrame() {
		guard var e = editing, e.frames.count > 1 else { return }
		e.frames.remove(at: min(frame, e.frames.count - 1))
		editing = e
		frame = max(0, min(frame, e.frames.count - 1))
	}

	func resizeAll(_ w: Int, _ h: Int) {
		guard var e = editing else { return }
		e.frames = e.frames.map { $0.resized(w, h) }
		editing = e
	}

	func done() {
		save()
		editing = nil
	}

	func save() {
		guard let e = editing else { return }
		editing = SpriteLibrary.put(e)
		list = SpriteLibrary.load()
	}
}

// MARK: - Mod Creator+: the infusion editor

/// The INFUSIONS tab: the mod's own infusions
struct InfusionListView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void

	var body: some View {
		VStack(spacing: 8) {
			Text("Infusions are worked into equipment at an Infusion Crucible. Each one has a compound: make a recipe for it so players can craft it.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			PixelButton(title: "+ NEW INFUSION", color: ModUI.accent) { self.makeNew() }
			ForEach(s.mod.infusions) { f in self.row(f) }
		}
	}

	func makeNew() {
		var f = ModInfusion()
		f.id = s.mod.freshID("f")
		f.name = joinText("Infusion ", String(s.mod.infusions.count + 1))
		f.damagePct = 10
		s.mod.infusions.append(f)
		s.touch()
		open(f.id)
	}

	func row(_ f: ModInfusion) -> some View {
		let img: Image = pixImage(ModRuntime.shared.compoundIcon(f))
		let isOff: Bool = s.mod.off.contains(f.id)
		let fid: String = f.id
		return ModRow(image: img, title: f.name, sub: f.blurb, open: { self.open(fid) }, copy: { self.copy(f) },
					  delete: { self.delete(fid) }, off: isOff, toggle: { self.toggle(fid) })
	}

	func copy(_ f: ModInfusion) {
		var c: ModInfusion = f
		c.id = s.mod.freshID("f")
		c.name = String(joinText(f.name, " copy").prefix(32))
		s.mod.infusions.append(c)
		s.touch()
	}

	func delete(_ fid: String) {
		s.mod.infusions.removeAll { $0.id == fid }
		s.touch()
	}

	func toggle(_ fid: String) {
		if s.mod.off.contains(fid) { s.mod.off.removeAll { $0 == fid } } else { s.mod.off.append(fid) }
		s.touch()
	}
}

/// Editing one custom infusion
/// A slider of an editor, as data: its label, the number it changes, its range (and the top in sandbox
/// mode), its step and how it is shown. Editors with many numbers list them like this, which keeps them
/// quick for the compiler (one row type instead of a long chain of views).
struct DSlider<Root> {
	let label: String
	let kp: WritableKeyPath<Root, Double>
	let lo: Double
	let hi: Double
	let sbHi: Double
	let step: Double
	let format: String
}

/// A before-and-after line of a preview
struct PreviewRow: View {
	let name: String
	let before: String
	let after: String
	var body: some View {
		let changed: Bool = before != after
		let col: Color = changed ? Color(ui: 0x7AF08A) : Color.white
		return HStack {
			Text(verbatim: name).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Spacer()
			Text(verbatim: before).font(.pixel(11)).foregroundColor(Color.white.opacity(0.7))
			Text("\u{2192}").font(.pixel(11)).foregroundColor(ModUI.dim)
			Text(verbatim: after).font(.pixel(11)).foregroundColor(col)
		}
	}
}

struct InfusionEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	var openRecipe: (String) -> Void
	@State var pickingItem: Bool = false

	func b<T>(_ kp: WritableKeyPath<ModInfusion, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.infusions, id, kp, d) }
	var inf: ModInfusion { return s.mod.infusions.first { $0.id == id } ?? ModInfusion() }

	static let numbers: [DSlider<ModInfusion>] = [
		DSlider(label: "Damage %", kp: \.damagePct, lo: -50, hi: 100, sbHi: 400, step: 1, format: "%.0f"),
		DSlider(label: "Extra damage", kp: \.damageFlat, lo: 0, hi: 20, sbHi: 100, step: 0.5, format: "%.1f"),
		DSlider(label: "Attack speed %", kp: \.attackSpeedPct, lo: -50, hi: 60, sbHi: 60, step: 1, format: "%.0f"),
		DSlider(label: "Extra reach", kp: \.reach, lo: 0, hi: 1.5, sbHi: 4, step: 0.1, format: "%.1f"),
		DSlider(label: "Critical chance %", kp: \.critPct, lo: 0, hi: 40, sbHi: 100, step: 1, format: "%.0f"),
		DSlider(label: "Knockback %", kp: \.knockPct, lo: -80, hi: 100, sbHi: 400, step: 1, format: "%.0f"),
		DSlider(label: "Mining speed %", kp: \.miningPct, lo: 0, hi: 100, sbHi: 400, step: 1, format: "%.0f"),
		DSlider(label: "Defence (armour)", kp: \.defense, lo: 0, hi: 4, sbHi: 20, step: 0.1, format: "%.1f"),
		DSlider(label: "Run speed % (armour)", kp: \.moveSpeedPct, lo: 0, hi: 15, sbHi: 50, step: 1, format: "%.0f"),
		DSlider(label: "Less fire and lava harm %", kp: \.fireCut, lo: 0, hi: 60, sbHi: 60, step: 1, format: "%.0f"),
		DSlider(label: "Less cold %", kp: \.coldCut, lo: 0, hi: 75, sbHi: 75, step: 1, format: "%.0f"),
		DSlider(label: "Less lightning and hail %", kp: \.stormCut, lo: 0, hi: 60, sbHi: 60, step: 1, format: "%.0f"),
		DSlider(label: "Healing a minute (armour)", kp: \.regen, lo: 0, hi: 12, sbHi: 60, step: 0.5, format: "%.1f"),
		DSlider(label: "Less suit energy %", kp: \.energyPct, lo: 0, hi: 50, sbHi: 50, step: 1, format: "%.0f"),
	]
	static let strikes: [DSlider<ModInfusion>] = [
		DSlider(label: "Sets alight (seconds)", kp: \.burn, lo: 0, hi: 8, sbHi: 8, step: 0.5, format: "%.1f"),
		DSlider(label: "Slows (seconds)", kp: \.slow, lo: 0, hi: 8, sbHi: 8, step: 0.5, format: "%.1f"),
		DSlider(label: "Poisons (seconds)", kp: \.poison, lo: 0, hi: 10, sbHi: 10, step: 0.5, format: "%.1f"),
		DSlider(label: "Spark chance", kp: \.sparkChance, lo: 0, hi: 0.4, sbHi: 1, step: 0.01, format: "%.2f"),
		DSlider(label: "Little blast (damage)", kp: \.blast, lo: 0, hi: 8, sbHi: 40, step: 0.5, format: "%.1f"),
		DSlider(label: "Health stolen %", kp: \.lifeSteal, lo: 0, hi: 15, sbHi: 50, step: 1, format: "%.0f"),
		DSlider(label: "Blow returned % (armour)", kp: \.thorns, lo: 0, hi: 40, sbHi: 40, step: 1, format: "%.0f"),
	]

	var body: some View {
		VStack(spacing: 10) {
			aboutSection
			iconSection
			goesOnSection
			ModSection(title: "NUMBERS", help: "Percentages of what the item already does, so a good item stays better than a poor one") {
				ModToggle(label: "Percentages multiply", help: "Off: they add to those of other infusions", isOn: b(\.multiply, false))
				sliders(InfusionEditorView.numbers)
			}
			ModSection(title: "WHEN IT STRIKES", help: "What happens to what a weapon or shot hits") {
				sliders(InfusionEditorView.strikes)
			}
			effectSection
			ModSection(title: "STACKING AND LOOKS") {
				IntSlider(label: "Times one item may hold it", value: b(\.stack, 1), range: 1...3)
				ModToggle(label: "Sparks of its colour when it works", isOn: b(\.particles, true))
			}
			recipeSection
			previewSection
		}
	}

	var aboutSection: some View {
		ModSection(title: "ABOUT") {
			ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Thunderstrike")
			ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
			Text("Rarity").font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			ChoiceRow(options: InfusionEditorView.rarityNames, selected: b(\.rarity, 1), columns: 5)
			ModColorRow(label: "Its colour (sparks and marks on items)", color: b(\.color, 0x60E0FF))
		}
	}
	static let rarityNames: [String] = Rarity.allCases.map { $0.name }

	var iconSection: some View {
		ModSection(title: "COMPOUND ICON", help: "Leave it blank for a phial in its colour") {
			PixelEditorView(pixels: b(\.icon, ModPixels(w: 12, h: 12)), maxSide: 240, sizes: [12, 16], outlineDefault: true)
		}
	}

	var goesOnSection: some View {
		let f: ModInfusion = inf
		return ModSection(title: "GOES ON", help: "Kinds of equipment, or (if any are picked below) only certain items") {
			classChips(f)
			itemList(f)
		}
	}

	var effectSection: some View {
		let on: Bool = inf.trigger != .none
		return ModSection(title: "EFFECT ON YOU", help: "A timed effect for the player, given now and then") {
			ChoiceRow(options: InfusionEditorView.triggerNames, selected: triggerBind, columns: 3)
			if on {
				effectEditor
				StatSlider(label: "Rests between (seconds)", value: b(\.effectCooldown, 10), range: 2...300, step: 1, format: "%.0f")
			}
		}
	}
	static let triggerNames: [String] = ModInfuseTrigger.allCases.map { $0.name }

	var recipeSection: some View {
		let key: String = s.mod.key(inf.id)
		let recs: [ModRecipe] = s.mod.recipes.filter { $0.out == .custom(key) }
		return ModSection(title: "ITS COMPOUND'S RECIPE") {
			ForEach(recs) { r in self.recipeRow(r) }
			SmallButton(title: "+ MAKE A RECIPE FOR IT", color: ModUI.accent) { self.makeRecipe(key) }
		}
	}

	func recipeRow(_ r: ModRecipe) -> some View {
		let names: String = r.cost.map { $0.item.name }.joined(separator: ", ")
		let line: String = joinText("Recipe ", r.id, ": ", names)
		return HStack {
			Text(verbatim: line).font(.pixel(11, .semibold)).foregroundColor(Color.white).lineLimit(1)
			Spacer()
			SmallButton(title: "EDIT", color: ModUI.blue) { self.openRecipe(r.id) }
		}
	}

	func makeRecipe(_ key: String) {
		var r = ModRecipe()
		r.id = s.mod.freshID("r")
		r.out = .custom(key)
		r.count = 1
		r.cost = [ModCost(.mat(.waterVial), 1), ModCost(.mat(.crystalShard), 1)]
		r.station = Station.infuser.rawValue
		s.mod.recipes.append(r)
		s.touch()
		openRecipe(r.id)
	}

	var previewSection: some View {
		let f: ModInfusion = inf
		let rows: [(String, String, String)] = previewRows(f)
		return ModSection(title: "PREVIEW", help: "What it would do to a sample item of the first kind it goes on") {
			ForEach(0..<rows.count, id: \.self) { i in PreviewRow(name: rows[i].0, before: rows[i].1, after: rows[i].2) }
			Text(verbatim: f.blurb).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
		}
	}

	func sliders(_ list: [DSlider<ModInfusion>]) -> some View {
		let sb: Bool = s.mod.sandbox
		return VStack(alignment: .leading, spacing: 8) {
			ForEach(0..<list.count, id: \.self) { i in self.slider(list[i], sb) }
		}
	}

	func slider(_ d: DSlider<ModInfusion>, _ sb: Bool) -> StatSlider {
		let top: Double = sb ? d.sbHi : d.hi
		let r: ClosedRange<Double> = d.lo...top
		return StatSlider(label: d.label, value: b(d.kp, 0), range: r, step: d.step, format: d.format)
	}

	var triggerBind: Binding<Int> {
		let inner: Binding<ModInfuseTrigger> = b(\.trigger, .none)
		return Binding<Int>(get: { inner.wrappedValue.rawValue }, set: { inner.wrappedValue = ModInfuseTrigger(rawValue: $0) ?? .none })
	}

	var effectEditor: some View {
		let e: Binding<ModEffect> = b(\.effect, ModEffect(.speed, 20, 8))
		let timed: [ModEffectKind] = ModEffectKind.allCases.filter { $0.timed }
		let kindB: Binding<Int> = Binding<Int>(get: { timed.firstIndex(of: e.wrappedValue.kind) ?? 0 }, set: { v in
			var x: ModEffect = e.wrappedValue
			x.kind = timed[clampI(v, 0, timed.count - 1)]
			x.amount = x.kind.amountRange.clamp(x.amount, s.mod.sandbox)
			e.wrappedValue = x
		})
		let amount: Binding<Double> = Binding<Double>(get: { e.wrappedValue.amount }, set: { v in var x: ModEffect = e.wrappedValue; x.amount = v; e.wrappedValue = x })
		let secs: Binding<Double> = Binding<Double>(get: { e.wrappedValue.seconds }, set: { v in var x: ModEffect = e.wrappedValue; x.seconds = v; e.wrappedValue = x })
		let range: ModRange = e.wrappedValue.kind.amountRange
		return VStack(alignment: .leading, spacing: 6) {
			ChoiceRow(options: timed.map { $0.name }, selected: kindB, columns: 4)
			StatSlider(label: e.wrappedValue.kind.amountLabel, value: amount, range: range.lo...(s.mod.sandbox ? range.sandboxHi : range.hi), step: 0.5)
			StatSlider(label: "Seconds", value: secs, range: 1...120, step: 1, format: "%.0f")
		}
	}

	func classChips(_ f: ModInfusion) -> some View {
		let names: [String] = ["Melee weapons", "Bows, slings and guns", "Tools", "Armour and suit plating", "Suit cores and modules"]
		let cls: Binding<[Int]> = b(\.classes, [0])
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 6)]
		return LazyVGrid(columns: cols, spacing: 6) {
			ForEach(0..<names.count, id: \.self) { i in
				let on: Bool = cls.wrappedValue.contains(i)
				SmallButton(title: names[i], color: on ? ModUI.accent : Color(ui: 0x555555)) {
					if on { cls.wrappedValue.removeAll { $0 == i } } else { cls.wrappedValue.append(i) }
				}
			}
		}
	}

	func itemList(_ f: ModInfusion) -> some View {
		let items: Binding<[Item]> = b(\.items, [])
		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: f.items.isEmpty ? "Any item of the kinds picked" : "Only these items:").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<f.items.count, id: \.self) { i in
				HStack {
					Art.shared.icon(f.items[i]).resizable().interpolation(.none).frame(width: 24, height: 24)
					Text(verbatim: f.items[i].name).font(.pixel(11)).foregroundColor(Color.white)
					Spacer()
					SmallButton(title: "✕", color: ModUI.red) { if i < items.wrappedValue.count { items.wrappedValue.remove(at: i) } }
				}
			}
			if pickingItem {
				GamePickerView(kind: .item, title: "ONLY ON THIS ITEM", pick: { _, it in
					if let x = it, !items.wrappedValue.contains(x) { items.wrappedValue.append(x) }
					pickingItem = false
				}, cancel: { pickingItem = false })
			} else if f.items.count < 12 {
				SmallButton(title: "+ ONLY ON A CERTAIN ITEM", color: ModUI.blue) { pickingItem = true }
			}
		}
	}

	/// Before-and-after numbers on a sample item of its first kind
	func previewRows(_ f: ModInfusion) -> [(String, String, String)] {
		var rows: [(String, String, String)] = []
		let first: Int = f.classes.first ?? 0
		func f1(_ v: Double) -> String { return String(format: "%.1f", v) }
		switch first {
		case 0, 1:
			let it: Item = first == 0 ? .sword(.iron) : .gun(.pistol)
			let p0: MeleeProfile = first == 0 ? it.melee : MeleeProfile(damage: GunType.pistol.damage, cooldown: GunType.pistol.cooldown, reach: 14, halfArc: 0)
			let p1: MeleeProfile = f.apply(p0)
			rows.append((joinText(it.name, " damage"), f1(p0.damage), f1(p1.damage)))
			rows.append(("Time between attacks", String(format: "%.2f s", p0.cooldown), String(format: "%.2f s", p1.cooldown)))
			if first == 0 {
				rows.append(("Reach", f1(p0.reach), f1(p1.reach)))
				rows.append(("Critical chance", joinText(String(Int(p0.critChance * 100)), "%"), joinText(String(Int(p1.critChance * 100)), "%")))
			}
		case 2:
			let s0: Double? = miningSeconds(.stone, .pickaxe, .iron)
			let s1: Double? = s0.map { $0 / max(0.01, 1.0 + f.miningPct / 100.0) }
			rows.append(("Iron pickaxe on stone", secondsText(s0), secondsText(s1)))
		default:
			let d0: Double = Tier.iron.defense * ArmorSlot.chest.weight
			rows.append(("Iron chestplate defence", f1(d0), f1(d0 + f.defense)))
			rows.append(("Run speed", "100%", joinText(String(Int((100 + f.moveSpeedPct).rounded())), "%")))
		}
		return rows
	}
}

extension InfusionPanel {
	/// The world's custom infusions (from its mods), in the crucible beside the game's own
	var customRows: some View {
		let list: [ModInfusionRT] = ModRuntime.shared.infusionDefs.values.sorted { $0.number < $1.number }
		return VStack(spacing: 4) {
			if !list.isEmpty {
				Text("FROM MODS").font(.pixel(11)).foregroundColor(Color(ui: 0xB8A8D8)).frame(maxWidth: .infinity, alignment: .leading)
			}
			ForEach(list, id: \.number) { r in customRow(r) }
		}
	}

	func customRow(_ r: ModInfusionRT) -> some View {
		let compound: Item = .custom(r.key)
		let owned: Int = game.inv.total(compound)
		let chosen: Bool = customChoice == r.number
		return Button(action: {
			customChoice = r.number
			choice = -1
			note = ""
		}) {
			HStack(spacing: 6) {
				SlotView(stack: Stack(item: compound, count: max(1, owned)), selected: chosen, size: 34, dim: owned == 0)
				VStack(alignment: .leading, spacing: 1) {
					Text(verbatim: r.def.name).font(.pixel(12)).foregroundColor(Color(ui: (Rarity(rawValue: r.def.rarity) ?? .uncommon).color))
					Text(verbatim: r.def.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8)).lineLimit(2)
				}
				Spacer(minLength: 0)
				Text(verbatim: owned > 0 ? joinText("x", String(owned)) : "none").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
			}
			.padding(4)
			.background(chosen ? Color(ui: 0x4A3A6A) : Color.black.opacity(0.2))
		}
		.buttonStyle(.plain)
	}

	func customPreview(_ s: Stack, _ r: ModInfusionRT) -> some View {
		let problem: String? = s.customProblem(r)
		let owned: Int = game.inv.total(.custom(r.key))
		let ok: Bool = problem == nil && (owned > 0 || game.isCreative)
		let p0: MeleeProfile = s.item.melee
		let p1: MeleeProfile = r.def.apply(p0)
		return VStack(alignment: .leading, spacing: 5) {
			Text(verbatim: joinText(s.item.name, " + ", r.def.name)).font(.pixel(12))
			Text(verbatim: r.def.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8))
			if infuseClasses(s.item).contains(.melee) {
				Text(verbatim: joinText("Damage ", String(format: "%.1f", p0.damage), " → ", String(format: "%.1f", p1.damage))).font(.pixel(11)).foregroundColor(Color.white)
			}
			if let p = problem { Text(verbatim: p).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9A7A)) }
			PixelButton(title: ok ? "CONFIRM INFUSION" : "CAN'T INFUSE", color: ok ? Color(ui: 0x6A4AA8) : Color(ui: 0x444444)) {
				if !ok { return }
				note = game.infuseCustom(slot: pick, r.number)
				customChoice = -1
			}
		}
		.padding(6)
		.background(Color.black.opacity(0.25))
	}
}

// MARK: - Mod Creator+: boss phases and summoning (screens)

/// The PHASES page of a creature: the stages of its fight, shown along its health bar
struct BossPhasesPage: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var open: Int = 0

	static let gameHelpers: [MobKind] = [.zombie, .skeleton, .slime, .bat, .scorpion, .wraith, .imp, .emberSlime, .cinderBat, .crawler, .archer, .pirate]

	var mob: ModMob { return s.mod.mobs.first { $0.id == id } ?? ModMob() }
	var phases: Binding<[ModPhase]> { return s.bind(\ModPack.mobs, id, \ModMob.phases, []) }
	var sb: Bool { return s.mod.sandbox }

	func pb<T>(_ i: Int, _ kp: WritableKeyPath<ModPhase, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModPhase]> = phases
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModPhase] = base.wrappedValue
			if i < list.count {
				list[i][keyPath: kp] = v
				base.wrappedValue = list
			}
		})
	}

	var body: some View {
		VStack(spacing: 10) {
			Text("A fight in stages. Each phase begins when its moment comes and changes the creature for the rest of the fight; phases follow one another in order. They work for any creature, and bosses show the phase on their health bar.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			timeline
			ForEach(0..<mob.phases.count, id: \.self) { i in phaseCard(i) }
			if mob.phases.count < ModLimits.maxPhases {
				PixelButton(title: "+ ADD PHASE", color: ModUI.accent) { add() }
			}
		}
	}

	/// The fight along the health bar: where each health phase begins, then the others in order
	var timeline: some View {
		let segs: [(Double, UInt32, String)] = segments
		let others: [String] = laterPhases
		return VStack(alignment: .leading, spacing: 4) {
			Text("THE FIGHT, FULL HEALTH TO NONE").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
			HStack(spacing: 2) {
				ForEach(0..<segs.count, id: \.self) { k in BossPhasesPage.segmentView(segs[k]) }
			}
			ForEach(0..<others.count, id: \.self) { k in
				Text(verbatim: others[k]).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	static func segmentView(_ seg: (Double, UInt32, String)) -> some View {
		let w: CGFloat = CGFloat(max(10.0, seg.0 * 420.0))
		let col: Color = Color(ui: seg.1)
		return VStack(spacing: 2) {
			Rectangle().fill(col).frame(width: w, height: 16)
			Text(verbatim: seg.2).font(.pixel(9, .semibold)).foregroundColor(Color.white).lineLimit(1).frame(width: w)
		}
	}

	/// Stretches of the health bar: (share, colour, the phase's name)
	var segments: [(Double, UInt32, String)] {
		var out: [(Double, UInt32, String)] = []
		var from: Double = 1.0
		var col: UInt32 = 0x5AA85A
		var name: String = "Start"
		for p in mob.phases where p.when == .health && p.value < from {
			out.append((from - p.value, col, name))
			from = p.value
			col = p.tintAmt > 0.05 ? p.tint : 0xA05050
			name = p.name
		}
		out.append((from, col, name))
		return out
	}

	var laterPhases: [String] {
		var out: [String] = []
		for (i, p) in mob.phases.enumerated() where p.when != .health {
			out.append(joinText("Phase ", String(i + 1), " \u{201C}", p.name, "\u{201D} begins ", p.whenText, "."))
		}
		return out
	}

	func phaseCard(_ i: Int) -> some View {
		let p: ModPhase = i < mob.phases.count ? mob.phases[i] : ModPhase()
		let isOpen: Bool = open == i
		return VStack(alignment: .leading, spacing: 8) {
			cardHeader(i, p)
			Text(verbatim: summary(p)).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			if isOpen { editor(i, p) }
		}
		.padding(10)
		.background(PixelBox(color: ModUI.card))
	}

	func cardHeader(_ i: Int, _ p: ModPhase) -> some View {
		let title: String = joinText(String(i + 1), ". ", p.name, " \u{2014} ", p.whenText)
		let toggle: String = open == i ? "CLOSE" : "EDIT"
		let canUp: Bool = i > 0
		let canDown: Bool = i < mob.phases.count - 1
		return HStack(spacing: 6) {
			Rectangle().fill(Color(hex: p.tint)).frame(width: 14, height: 14)
			Text(verbatim: title).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: toggle, color: ModUI.blue) { self.toggleOpen(i) }
			if canUp { SmallButton(title: "UP") { self.move(i, -1) } }
			if canDown { SmallButton(title: "DOWN") { self.move(i, 1) } }
			SmallButton(title: "DELETE", color: ModUI.red) { self.remove(i) }
		}
	}

	func toggleOpen(_ i: Int) { open = open == i ? -1 : i }

	func summary(_ p: ModPhase) -> String {
		var parts: [String] = []
		parts.append(String(format: "speed x%.2f", p.speedMul))
		parts.append(String(format: "damage x%.2f", p.damageMul))
		if abs(p.cooldownMul - 1) > 0.01 { parts.append(String(format: "attacks rest x%.2f", p.cooldownMul)) }
		if p.defense > 0.01 { parts.append(joinText("shrugs off ", String(Int((p.defense * 100).rounded())), "%")) }
		if p.heal > 0.01 { parts.append(joinText("heals ", String(Int((p.heal * 100).rounded())), "%")) }
		if p.helpers > 0 && !p.helper.isEmpty { parts.append(joinText("calls ", String(p.helpers), " helpers")) }
		if !p.attacks.isEmpty { parts.append(joinText("uses ", String(p.attacks.count), " of its attacks")) }
		return parts.joined(separator: " \u{00B7} ")
	}

	func editor(_ i: Int, _ p: ModPhase) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			ModTextField(label: "Name", text: pb(i, \.name, ""), placeholder: "Enraged")
			whenSection(i, p)
			changeSection(i)
			if !mob.attacks.isEmpty { attacksSection(i) }
			lookSection(i, p)
			helpersSection(i, p)
			ModTextField(label: "Message", text: pb(i, \.message, ""), placeholder: "The ground splits open!")
		}
	}

	static let whenNames: [String] = ModPhaseWhen.allCases.map { $0.name }

	func whenSection(_ i: Int, _ p: ModPhase) -> some View {
		let health: Bool = p.when == .health
		let time: Bool = p.when == .time
		return ModSection(title: "WHEN IT BEGINS", help: p.when.help) {
			ChoiceRow(options: BossPhasesPage.whenNames, selected: whenBind(i), columns: 3)
			if health {
				StatSlider(label: "Health", value: percent(pb(i, \.value, 0.5)), range: 5.0...95.0, step: 1, format: "%.0f", unit: "%")
			}
			if time {
				StatSlider(label: "Seconds of fighting", value: pb(i, \.value, 30), range: 3.0...600.0, step: 1, format: "%.0f", unit: " s")
			}
		}
	}

	func changeSection(_ i: Int) -> some View {
		let sb: Bool = self.sb
		return ModSection(title: "HOW IT CHANGES", help: "Multipliers of its own numbers, for the rest of the fight.") {
			StatSlider(label: "Speed", value: pb(i, \.speedMul, 1), range: sbRange(0.5, 2, 3, sb), step: 0.05, format: "x%.2f")
			StatSlider(label: "Damage", value: pb(i, \.damageMul, 1), range: sbRange(0.5, 3, 6, sb), step: 0.05, format: "x%.2f")
			StatSlider(label: "Rest between attacks", value: pb(i, \.cooldownMul, 1), range: 0.3...2.0, step: 0.05, format: "x%.2f")
			StatSlider(label: "Hits shrugged off", value: percent(pb(i, \.defense, 0)), range: sbRange(0, 60, 90, sb), step: 1, format: "%.0f", unit: "%")
			StatSlider(label: "Heals as it begins", value: percent(pb(i, \.heal, 0)), range: 0.0...50.0, step: 1, format: "%.0f", unit: "%")
			StatSlider(label: "Can't be hurt while changing", value: pb(i, \.shield, 1), range: 0.0...5.0, step: 0.25, format: "%.2f", unit: " s")
		}
	}

	func attacksSection(_ i: Int) -> some View {
		let names: [String] = mob.attacks.enumerated().map { (j: Int, a: ModAttack) -> String in joinText("Attack ", String(j + 1), ": ", a.kind.name) }
		return ModSection(title: "ATTACKS IN THIS PHASE", help: "All on: it uses every attack it has.") {
			ForEach(0..<names.count, id: \.self) { j in ModToggle(label: names[j], isOn: self.attackBind(i, j)) }
		}
	}

	func lookSection(_ i: Int, _ p: ModPhase) -> some View {
		let img: Image = tinted(p)
		return ModSection(title: "LOOK") {
			HStack(spacing: 12) {
				img.resizable().interpolation(.none).frame(width: 72, height: 72).background(Color(ui: 0x5A7A9A).opacity(0.6))
				VStack(alignment: .leading, spacing: 6) {
					StatSlider(label: "Colour strength", value: pb(i, \.tintAmt, 0.25), range: 0.0...1.0, step: 0.05, format: "%.2f")
					ModToggle(label: "Roars as it begins", isOn: pb(i, \.roar, true))
				}
			}
			ModColorRow(label: "Colour", color: pb(i, \.tint, 0xFF4030))
		}
	}

	func helpersSection(_ i: Int, _ p: ModPhase) -> some View {
		let names: [String] = helperChoices.0
		let has: Bool = !p.helper.isEmpty
		let most: ClosedRange<Int> = 0...(sb ? 10 : 6)
		return ModSection(title: "HELPERS", help: "Creatures it calls to its side as this phase begins.") {
			ChoiceRow(options: names, selected: helperBind(i), columns: 4)
			if has { IntSlider(label: "How many", value: pb(i, \.helpers, 0), range: most) }
		}
	}

	func percent(_ b: Binding<Double>) -> Binding<Double> {
		return Binding<Double>(get: { b.wrappedValue * 100.0 }, set: { b.wrappedValue = $0 / 100.0 })
	}

	func whenBind(_ i: Int) -> Binding<Int> {
		let base: Binding<ModPhaseWhen> = pb(i, \.when, .health)
		let val: Binding<Double> = pb(i, \.value, 0.5)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { n in
			let w: ModPhaseWhen = ModPhaseWhen(rawValue: n) ?? .health
			if w != base.wrappedValue {
				base.wrappedValue = w
				val.wrappedValue = w == .time ? 30 : 0.5
			}
		})
	}

	/// One attack switched on or off for a phase (all on is stored as "every attack")
	func attackBind(_ i: Int, _ j: Int) -> Binding<Bool> {
		let base: Binding<[Int]> = pb(i, \.attacks, [])
		let n: Int = mob.attacks.count
		return Binding<Bool>(get: { base.wrappedValue.isEmpty || base.wrappedValue.contains(j) }, set: { on in
			var l: [Int] = base.wrappedValue.isEmpty ? Array(0..<n) : base.wrappedValue
			if on {
				if !l.contains(j) { l.append(j) }
			} else {
				// at least one attack stays on
				if l.count <= 1 { return }
				l.removeAll { $0 == j }
			}
			l.sort()
			base.wrappedValue = l.count >= n ? [] : l
		})
	}

	var helperChoices: ([String], [String]) {
		var names: [String] = ["Nobody"]
		var keys: [String] = [""]
		for o in s.mod.mobs where o.id != id {
			names.append(o.name)
			keys.append(s.mod.key(o.id))
		}
		for k in BossPhasesPage.gameHelpers {
			names.append(mobDef(k).name)
			keys.append(mobDef(k).name)
		}
		return (names, keys)
	}

	func helperBind(_ i: Int) -> Binding<Int> {
		let base: Binding<String> = pb(i, \.helper, "")
		let count: Binding<Int> = pb(i, \.helpers, 0)
		let keys: [String] = helperChoices.1
		return Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { n in
			base.wrappedValue = keys[clampI(n, 0, keys.count - 1)]
			if base.wrappedValue.isEmpty { count.wrappedValue = 0 } else if count.wrappedValue == 0 { count.wrappedValue = 2 }
		})
	}

	/// The creature as it looks in this phase
	func tinted(_ p: ModPhase) -> Image {
		let fr: ([PixelBuf], CreatureAnim) = modMobFrames(mob)
		guard let f = fr.0.first else { return pixImage(PixelBuf(w: 1, h: 1)) }
		return pixImage(recolorBuf(f, hue: 0, sat: 1, bright: 1, tint: p.tint, amt: p.tintAmt))
	}

	func add() {
		var list: [ModPhase] = mob.phases
		var p = ModPhase()
		let health: [Double] = list.filter { $0.when == .health }.map { $0.value }
		let lowest: Double = health.min() ?? 1.0
		let next: Double = (lowest - 0.25).rounded(toPlaces: 2)
		p.value = max(0.1, next)
		p.name = list.isEmpty ? "Enraged" : joinText("Phase ", String(list.count + 1))
		list.append(p)
		phases.wrappedValue = list
		open = list.count - 1
	}

	func move(_ i: Int, _ d: Int) {
		var list: [ModPhase] = mob.phases
		let j: Int = i + d
		if i < 0 || j < 0 || i >= list.count || j >= list.count { return }
		list.swapAt(i, j)
		phases.wrappedValue = list
		open = j
	}

	func remove(_ i: Int) {
		var list: [ModPhase] = mob.phases
		if i < 0 || i >= list.count { return }
		list.remove(at: i)
		phases.wrappedValue = list
		open = -1
	}
}

extension Double {
	func rounded(toPlaces n: Int) -> Double {
		let f: Double = pow(10.0, Double(n))
		return (self * f).rounded() / f
	}
}

/// A summoning shape as a grid of big cells to paint
struct PatternGrid: View {
	@Binding var pattern: ModPattern
	let brush: String
	let catalog: ModCatalog

	var body: some View {
		VStack(spacing: 2) {
			ForEach(0..<pattern.h, id: \.self) { y in
				HStack(spacing: 2) {
					ForEach(0..<pattern.w, id: \.self) { x in
						Button(action: {
							var p: ModPattern = pattern
							p.set(x, y, p.cell(x, y) == brush ? "" : brush)
							pattern = p
						}) {
							PatternGrid.cellImage(pattern.cell(x, y), catalog).resizable().interpolation(.none)
								.frame(width: 46, height: 46)
								.background(Color.black.opacity(0.35))
						}
						.buttonStyle(.plain)
					}
				}
			}
		}
		.padding(6)
		.background(Color(ui: 0x6A8AAA).opacity(0.5))
	}

	/// The picture of a cell: a block, a cross for "empty", or a faint dot for "anything"
	static func cellImage(_ k: String, _ cat: ModCatalog) -> Image {
		if k.isEmpty {
			var b = PixelBuf(w: 8, h: 8)
			b.set(3, 3, 0xFF707070)
			b.set(4, 4, 0xFF707070)
			b.set(3, 4, 0xFF707070)
			b.set(4, 3, 0xFF707070)
			return pixImage(b)
		}
		if k == "air" {
			var b = PixelBuf(w: 8, h: 8)
			for i in 1..<7 {
				b.set(i, i, 0xFFE04040)
				b.set(7 - i, i, 0xFFE04040)
			}
			return pixImage(b)
		}
		if k.hasPrefix("tile:"), let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) { return pixImage(tileBuf(t)) }
		return ModPreview.icon(.custom(k), cat)
	}
}

// MARK: - Mod Creator+: summoning rules and custom dimensions (screens)

/// A chip that is on or off (tap to change it)
struct ToggleChip: View {
	let title: String
	let on: Bool
	var action: () -> Void
	var body: some View {
		let bg: Color = on ? ModUI.accent : Color.black.opacity(0.4)
		return Button(action: action) {
			Text(verbatim: title).font(.pixel(11, .bold)).foregroundColor(Color.white)
				.frame(maxWidth: .infinity, minHeight: 40)
				.background(bg)
		}
		.buttonStyle(.plain)
	}
}

/// One way to summon (or a dimension's way in): what the player does, the item, the shape, and when
/// and where it works. Used by the SUMMON page and the dimension editor.
struct SummonRuleEditor: View {
	@ObservedObject var s: ModSession
	@Binding var rule: ModSummon
	var forDimension: Bool = false
	@State var pickingItem: Bool = false
	@State var pickingBlock: Bool = false
	/// what a tap on the shape paints: "" anything, "air" empty, or a block key
	@State var brush: String = "air"
	@State var recent: [String] = []

	func rb<T>(_ kp: WritableKeyPath<ModSummon, T>) -> Binding<T> {
		return Binding<T>(get: { rule[keyPath: kp] }, set: { rule[keyPath: kp] = $0 })
	}

	var body: some View {
		ZStack {
			VStack(alignment: .leading, spacing: 8) {
				ModToggle(label: forDimension ? "Players can get in this way" : "Works in play", isOn: rb(\.enabled))
				howSection
				if rule.usesItem { itemSection }
				if rule.usesPattern { shapeSection }
				whereSection
				if !forDimension { entranceSection }
			}
		}
		.modCover(s, pickingItem ? 1 : nil) { self.itemPicker }
		.modCover(s, pickingBlock ? 2 : nil) { self.blockPicker }
	}

	static let howNames: [String] = ModSummonHow.allCases.map { $0.name }

	var howSection: some View {
		ModSection(title: "WHAT THE PLAYER DOES", help: rule.how.help) {
			ChoiceRows(options: SummonRuleEditor.howNames, selected: howBind, columns: 3)
		}
	}

	var itemSection: some View {
		let title: String = forDimension ? "THE KEY ITEM" : "THE ITEM"
		let help: String = forDimension ? "Using it again inside the dimension brings the player back." : ""
		let used: String = forDimension ? "Used up on the way in" : "Used up when the creature comes"
		return ModSection(title: title, help: help) {
			itemRow
			ModToggle(label: used, isOn: rb(\.consume))
		}
	}

	var itemRow: some View {
		HStack(spacing: 10) {
			if let it = rule.item {
				ModPreview.icon(it, s.catalog).resizable().interpolation(.none).frame(width: 36, height: 36)
			}
			Text(verbatim: itemName).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: "CHOOSE", color: ModUI.blue) { self.pickingItem = true }
		}
	}

	var shapeSection: some View {
		let title: String = forDimension ? "THE GATEWAY SHAPE" : "THE SHAPE"
		return ModSection(title: title, help: "Tap a cell to paint it. ANY: the cell can hold anything. EMPTY: it must be clear. It is built facing the way it is drawn.") {
			palette
			PatternGrid(pattern: rb(\.pattern), brush: brush, catalog: s.catalog)
			sizeRow
			ModToggle(label: "The shape's blocks are used up", isOn: rb(\.clearPattern))
		}
	}

	var sizeRow: some View {
		let side: ClosedRange<Int> = 1...ModPattern.maxSide
		return HStack(spacing: 10) {
			IntSlider(label: "Width", value: sizeBind(true), range: side)
			IntSlider(label: "Height", value: sizeBind(false), range: side)
		}
	}

	var whereSection: some View {
		ModSection(title: "WHEN AND WHERE", help: "Weather conditions are skipped for players who switch the weather off.") {
			ChoiceRows(options: ModSummonText.times, selected: rb(\.time), columns: 3)
			ChoiceRows(options: ModSummonText.weathers, selected: rb(\.weather), columns: 5)
			ChoiceRows(options: ModSummonText.places, selected: rb(\.place), columns: 3)
			ModBiomePicker(biomes: rb(\.biomes))
			Text("Dimensions (none chosen: any)").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			chips(SummonRuleEditor.gameDims, rb(\.dims))
			if !s.mod.dims.isEmpty { keyChips(modDims, rb(\.dimKeys)) }
		}
	}

	static let gameDims: [(Int, String)] = [(0, "Overworld"), (1, "Umbral Realm")]

	var modDims: [(String, String)] {
		var out: [(String, String)] = []
		for d in s.mod.dims { out.append((s.mod.key(d.id), d.name)) }
		return out
	}

	var entranceSection: some View {
		ModSection(title: "ITS ENTRANCE") {
			ChoiceRows(options: ModSummonText.appears, selected: rb(\.appear), columns: 2)
			ModTextField(label: "Message", text: rb(\.message), placeholder: "The Frost King answers your call!")
		}
	}

	var itemPicker: some View {
		let title: String = forDimension ? "THE KEY ITEM" : "THE SUMMONING ITEM"
		return ItemPickerView(catalog: s.catalog, title: title, pick: { (it: Item) in
			self.rule.item = it
			self.pickingItem = false
		}, cancel: { self.pickingItem = false })
	}

	var blockPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "A BLOCK FOR THE SHAPE", blocksOnly: true, pick: { (it: Item) in
			self.useBlock(it)
		}, cancel: { self.pickingBlock = false })
	}

	func useBlock(_ it: Item) {
		let k: String = SummonRuleEditor.key(it)
		if !k.isEmpty {
			brush = k
			recent.removeAll { $0 == k }
			recent.insert(k, at: 0)
			if recent.count > 8 { recent = Array(recent.prefix(8)) }
		}
		pickingBlock = false
	}

	static func key(_ it: Item) -> String {
		switch it {
		case .block(let t): return t.isMod || t == .air ? "" : ModGround.key(t)
		case .custom(let k): return k
		default: return ""
		}
	}

	var itemName: String {
		guard let i = rule.item else { return "None chosen" }
		return ModPreview.name(i, s.catalog)
	}

	var palette: some View {
		let n: Int = recent.count + 3
		return PlainGrid(count: n, per: 6) { (i: Int) in self.paletteCell(i) }
	}

	/// ANY, EMPTY, the blocks used lately, then + BLOCK
	@ViewBuilder
	func paletteCell(_ i: Int) -> some View {
		if i == 0 {
			brushButton("", "ANY")
		} else if i == 1 {
			brushButton("air", "EMPTY")
		} else if i - 2 < recent.count {
			brushButton(recent[i - 2], ModGround.name(recent[i - 2], s.mod))
		} else {
			Button(action: { self.pickingBlock = true }) {
				Text("+ BLOCK").font(.pixel(11, .bold)).foregroundColor(Color.white)
					.frame(maxWidth: .infinity, minHeight: 52)
					.background(ModUI.blue)
			}
			.buttonStyle(.plain)
		}
	}

	func brushButton(_ k: String, _ label: String) -> some View {
		let on: Bool = brush == k
		let bg: Color = on ? ModUI.accent : Color.black.opacity(0.4)
		let img: Image = PatternGrid.cellImage(k, s.catalog)
		return Button(action: { self.brush = k }) {
			VStack(spacing: 2) {
				img.resizable().interpolation(.none).frame(width: 28, height: 28)
				Text(verbatim: label).font(.pixel(8, .semibold)).foregroundColor(Color.white).lineLimit(1)
			}
			.frame(maxWidth: .infinity, minHeight: 52)
			.background(bg)
		}
		.buttonStyle(.plain)
	}

	func chips(_ opts: [(Int, String)], _ b: Binding<[Int]>) -> some View {
		let chosen: [Int] = b.wrappedValue
		return PlainGrid(count: opts.count, per: 4) { (k: Int) in
			ToggleChip(title: opts[k].1, on: chosen.contains(opts[k].0)) { SummonRuleEditor.flip(b, opts[k].0) }
		}
	}

	func keyChips(_ opts: [(String, String)], _ b: Binding<[String]>) -> some View {
		let chosen: [String] = b.wrappedValue
		return PlainGrid(count: opts.count, per: 4) { (k: Int) in
			ToggleChip(title: opts[k].1, on: chosen.contains(opts[k].0)) { SummonRuleEditor.flipKey(b, opts[k].0) }
		}
	}

	static func flip(_ b: Binding<[Int]>, _ v: Int) {
		var l: [Int] = b.wrappedValue
		if let j = l.firstIndex(of: v) { l.remove(at: j) } else { l.append(v) }
		b.wrappedValue = l.sorted()
	}

	static func flipKey(_ b: Binding<[String]>, _ v: String) {
		var l: [String] = b.wrappedValue
		if let j = l.firstIndex(of: v) { l.remove(at: j) } else { l.append(v) }
		b.wrappedValue = l
	}

	var howBind: Binding<Int> {
		return Binding<Int>(get: { rule.how.rawValue }, set: { rule.how = ModSummonHow(rawValue: $0) ?? .useItem })
	}

	func sizeBind(_ across: Bool) -> Binding<Int> {
		return Binding<Int>(get: { across ? rule.pattern.w : rule.pattern.h }, set: { n in
			let p: ModPattern = rule.pattern
			rule.pattern = across ? p.resized(n, p.h) : p.resized(p.w, n)
		})
	}
}

/// The SUMMON page of a creature: the ways a player can call it into the world
struct SummonPage: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var open: Int = 0

	var mob: ModMob { return s.mod.mobs.first { $0.id == id } ?? ModMob() }
	var summons: Binding<[ModSummon]> { return s.bind(\ModPack.mobs, id, \ModMob.summons, []) }

	func rule(_ i: Int) -> Binding<ModSummon> {
		let base: Binding<[ModSummon]> = summons
		return Binding<ModSummon>(get: { i < base.wrappedValue.count ? base.wrappedValue[i] : ModSummon() }, set: { v in
			var list: [ModSummon] = base.wrappedValue
			if i < list.count {
				list[i] = v
				base.wrappedValue = list
			}
		})
	}

	var body: some View {
		VStack(spacing: 10) {
			Text("Ways for a player to call this creature into the world in normal play: with an item, a shape of blocks, or both, where and when you say. Every condition you set must hold at once.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<mob.summons.count, id: \.self) { i in card(i) }
			if mob.summons.count < ModLimits.maxSummons {
				PixelButton(title: "+ ADD A WAY TO SUMMON", color: ModUI.accent) { add() }
			}
		}
	}

	func itemName(_ it: Item?) -> String {
		guard let i = it else { return "an item (none chosen)" }
		return ModPreview.name(i, s.catalog)
	}

	func card(_ i: Int) -> some View {
		let sm: ModSummon = i < mob.summons.count ? mob.summons[i] : ModSummon()
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				Text(verbatim: joinText(String(i + 1), ". ", sm.how.name)).font(.pixel(13, .bold)).foregroundColor(sm.enabled ? Color.white : ModUI.dim)
				Spacer(minLength: 0)
				SmallButton(title: open == i ? "CLOSE" : "EDIT", color: ModUI.blue) { open = open == i ? -1 : i }
				SmallButton(title: "DELETE", color: ModUI.red) { remove(i) }
			}
			Text(verbatim: joinText(ModSummonText.describe(sm, itemName(sm.item)), sm.enabled ? "." : " (switched off).")).font(.pixel(10, .semibold)).foregroundColor(ModUI.gold)
			if open == i { SummonRuleEditor(s: s, rule: rule(i)) }
		}
		.padding(10)
		.background(PixelBox(color: ModUI.card))
	}

	func add() {
		var list: [ModSummon] = mob.summons
		var sm = ModSummon()
		sm.time = 2
		sm.message = joinText(mob.name, " answers the call!")
		list.append(sm)
		summons.wrappedValue = list
		open = list.count - 1
	}

	func remove(_ i: Int) {
		var list: [ModSummon] = mob.summons
		if i < 0 || i >= list.count { return }
		list.remove(at: i)
		summons.wrappedValue = list
		open = -1
	}
}

/// The DIMENSIONS tab: the mod's dimensions
struct DimensionListView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Whole new places to travel to: their own sky, light, land, regions, weather and creatures, and a way in that you design (a key item, a gateway shape, or both). A world holds up to three custom dimensions.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if s.mod.dims.count < 3 {
				PixelButton(title: "+ NEW DIMENSION", color: ModUI.accent) { add() }
			}
			ForEach(s.mod.dims) { d in
				Button(action: { open(d.id) }) {
					HStack(spacing: 10) {
						SkySwatch(top: d.skyTop, bottom: d.skyBottom).frame(width: 44, height: 44)
						VStack(alignment: .leading, spacing: 3) {
							Text(verbatim: d.name).font(.pixel(14)).foregroundColor(Color.white)
							Text(verbatim: summary(d)).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
						}
						Spacer(minLength: 0)
						if s.mod.off.contains(d.id) { Text("OFF").font(.pixel(11, .bold)).foregroundColor(ModUI.red) }
					}
					.padding(8)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(PixelBox(color: ModUI.card))
				}
				.buttonStyle(.plain)
			}
		}
	}

	func summary(_ d: ModDimension) -> String {
		var parts: [String] = []
		parts.append(d.ceiling ? "a cavern world" : "open sky")
		parts.append(joinText(String(d.zones.count), d.zones.count == 1 ? " region" : " regions"))
		if d.sea > 0 { parts.append(d.liquid == 1 ? "lava seas" : "seas") }
		if d.islands > 0.05 { parts.append("floating islands") }
		parts.append(joinText(String(d.spawns.count), d.spawns.count == 1 ? " creature" : " creatures"))
		parts.append(d.entry.enabled ? d.entry.how.name.lowercased() : "no way in yet")
		return parts.joined(separator: " \u{00B7} ")
	}

	func add() {
		var d = ModDimension()
		d.id = s.mod.freshID("d")
		d.name = joinText("Dimension ", String(s.mod.dims.count + 1))
		s.mod.dims.append(d)
		s.touch()
		open(d.id)
	}
}

/// Editing one dimension: its sky and light, its land, its regions, its creatures, the way in and out,
/// and a preview made by the game's own generator
/// A mod's own sun or moon: switched on, its picture (or the round one in its colour), how big it is,
/// its glow, rays, turning and pulsing, how it moves across the sky and how much light it gives. Used by
/// the dimension editor and, for the Overworld, by the GAME CONTENT tab.
struct SkyBodyEditor: View {
	@Binding var sky: ModSkyBody?
	let moon: Bool
	/// the sky's colour behind it in the preview
	var skyTop: UInt32 = 0x3E86D8
	var skyBottom: UInt32 = 0xB4DCFF
	@State var colorPick: Int = 0

	static let colorNames: [String] = ["Its colour", "Its glow"]
	static let pathNames: [String] = ["Rises and sets", "Stays in one place"]
	static let numbers: [DSlider<ModSkyBody>] = [
		DSlider(label: "Size (times the game's)", kp: \.size, lo: 0.3, hi: 3, sbHi: 3, step: 0.05, format: "%.2f"),
		DSlider(label: "Glow", kp: \.glow, lo: 0, hi: 1, sbHi: 1, step: 0.05, format: "%.2f"),
		DSlider(label: "Pulsing glow", kp: \.pulse, lo: 0, hi: 1, sbHi: 1, step: 0.05, format: "%.2f"),
		DSlider(label: "Turning (degrees a second)", kp: \.spin, lo: -180, hi: 180, sbHi: 180, step: 1, format: "%.0f"),
		DSlider(label: "Light it gives (1 = the game's)", kp: \.bright, lo: 0, hi: 2, sbHi: 2, step: 0.05, format: "%.2f")
	]
	static let pathNumbers: [DSlider<ModSkyBody>] = [
		DSlider(label: "How high it climbs", kp: \.arc, lo: 0.2, hi: 1.2, sbHi: 1.2, step: 0.05, format: "%.2f")
	]
	static let placeNumbers: [DSlider<ModSkyBody>] = [
		DSlider(label: "Across (left ... right)", kp: \.posX, lo: 0, hi: 1, sbHi: 1, step: 0.01, format: "%.2f"),
		DSlider(label: "Down (top ... horizon)", kp: \.posY, lo: 0, hi: 1, sbHi: 1, step: 0.01, format: "%.2f")
	]

	var fresh: ModSkyBody { return moon ? ModSkyBody.moon() : ModSkyBody() }

	func f<T>(_ kp: WritableKeyPath<ModSkyBody, T>) -> Binding<T> {
		let base: Binding<ModSkyBody?> = $sky
		let start: ModSkyBody = fresh
		return Binding<T>(get: { (base.wrappedValue ?? start)[keyPath: kp] }, set: { v in
			var b: ModSkyBody = base.wrappedValue ?? start
			b[keyPath: kp] = v
			base.wrappedValue = b
		})
	}

	var onBind: Binding<Bool> {
		let base: Binding<ModSkyBody?> = $sky
		let start: ModSkyBody = fresh
		return Binding<Bool>(get: { base.wrappedValue != nil }, set: { on in base.wrappedValue = on ? start : nil })
	}

	var body: some View {
		let own: Bool = sky != nil
		let word: String = moon ? "moon" : "sun"
		return VStack(alignment: .leading, spacing: 8) {
			ModToggle(label: joinText("Its own ", word), help: joinText("Off: the game's ", word, " as it always was"), isOn: onBind)
			if own { fields }
		}
	}

	var fields: some View {
		let b: ModSkyBody = sky ?? fresh
		let pick: Int = clampI(colorPick, 0, 1)
		let fixed: Bool = b.path == 1
		let pictured: Bool = !b.art.isBlank
		return VStack(alignment: .leading, spacing: 8) {
			SkyBodyPreview(b: b, moon: moon, top: skyTop, bottom: skyBottom).frame(height: 130)
			Text("Its picture (leave it blank for a round one in its colour)").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			PixelEditorView(pixels: f(\.art), maxSide: 240, sizes: [16, 24, 32], outlineDefault: false)
			if pictured { SmallButton(title: "BACK TO A ROUND ONE", color: ModUI.red) { self.f(\.art).wrappedValue = ModPixels(w: 16, h: 16) } }
			ChoiceRows(options: SkyBodyEditor.colorNames, selected: $colorPick, columns: 2)
			ModColorRow(label: SkyBodyEditor.colorNames[pick], color: pick == 0 ? f(\.color) : f(\.glowColor))
			ModToggle(label: "Rays", help: "Short rays all round it, in its glow's colour", isOn: f(\.rays))
			sliderRows(SkyBodyEditor.numbers)
			ChoiceRows(options: SkyBodyEditor.pathNames, selected: f(\.path), columns: 2)
			if fixed {
				Text("It hangs there day and night.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				sliderRows(SkyBodyEditor.placeNumbers)
			} else {
				sliderRows(SkyBodyEditor.pathNumbers)
			}
		}
	}

	func sliderRows(_ list: [DSlider<ModSkyBody>]) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			ForEach(0..<list.count, id: \.self) { (i: Int) in self.slider(list[i]) }
		}
	}

	func slider(_ d: DSlider<ModSkyBody>) -> StatSlider {
		let r: ClosedRange<Double> = d.lo...d.hi
		return StatSlider(label: d.label, value: f(d.kp), range: r, step: d.step, format: d.format)
	}
}

/// A strip of sky with a sun or moon in it, as the game draws it (at the top of its path, or where it stays)
struct SkyBodyPreview: View {
	let b: ModSkyBody
	let moon: Bool
	let top: UInt32
	let bottom: UInt32

	var body: some View {
		let body: ModSkyBody = b
		let isMoon: Bool = moon
		let t0: UInt32 = top
		let b0: UInt32 = bottom
		return Canvas { ctx, size in
			let w: Double = Double(size.width)
			let h: Double = Double(size.height)
			let full: CGRect = CGRect(x: 0, y: 0, width: w, height: h)
			vGradient(&ctx, full, [rgbColor(t0), rgbColor(b0)], 0, h)
			// noon for a sun, midnight for a moon: the top of its path
			WorldRenderer.drawSkyBody(&ctx, w, h * 1.6, 0, body, isMoon ? 0.75 : 0.25, isMoon, isMoon ? 44.0 : 56.0, false, t0)
		}
		.background(Color.black)
	}
}

/// A tree design's cells as a small picture: three of them, short, middling and tall, in the colours of
/// the blocks they are made of
enum TreePreview {
	static func colour(_ k: String, _ p: ModPack, _ d: UInt32) -> UInt32 {
		if k.isEmpty { return d }
		if k.hasPrefix("tile:") {
			guard let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) else { return d }
			return t.def.colors.first ?? d
		}
		let s: (String, String) = splitModKey(k)
		if let b = p.blocks.first(where: { $0.id == s.1 }) { return ModDimPreview.averageColor(b.art) }
		return d
	}

	static func render(_ t: ModTree, _ p: ModPack) -> PixelBuf {
		let px: Int = 3
		let cellsW: Int = 3 * (treeReach * 2 + 1)
		let rows: Int = 34
		var b = PixelBuf(w: cellsW * px, h: (rows + 2) * px)
		let sky: UInt32 = 0x8AC0F0
		for i in 0..<b.px.count { b.px[i] = 0xFF000000 | sky }
		let trunk: UInt32 = colour(t.trunk, p, 0x6B4A2A)
		let branch: UInt32 = t.branch.isEmpty ? shadeRGB(trunk, 0.85) : colour(t.branch, p, trunk)
		let leaves: UInt32 = colour(t.leaves, p, 0x3E8A2E)
		let ground: UInt32 = colour(t.ground.isEmpty ? ModGround.key(.grass) : t.ground, p, 0x5DAA3A)
		func plot(_ cx: Int, _ cy: Int, _ c: UInt32) {
			if cx < 0 || cy < 0 || cx >= cellsW || cy >= rows + 2 { return }
			for y in 0..<px {
				for x in 0..<px { b.px[(cy * px + y) * b.w + cx * px + x] = 0xFF000000 | c }
			}
		}
		for x in 0..<cellsW {
			plot(x, rows, ground)
			plot(x, rows + 1, shadeRGB(ground, 0.7))
		}
		let lo: Int = clampI(t.minHeight, 1, 24)
		let hi: Int = max(lo, clampI(t.maxHeight, 1, 24))
		let heights: [Int] = [lo, (lo + hi) / 2, hi]
		for k in 0..<3 {
			let root: Int = treeReach + k * (treeReach * 2 + 1)
			let cells: [TreeCell] = TreeShapes.cells(t, heights[k], UInt64(1234 + k * 977))
			for c in cells {
				let col: UInt32 = c.part == 1 ? trunk : (c.part == 2 ? branch : leaves)
				plot(root + c.dx, rows - c.dy, col)
			}
		}
		return b
	}
}

/// Painting a tree cell by cell: empty, trunk, branch or leaves. Its root is the middle of the bottom row.
struct TreeGridEditor: View {
	@Binding var grid: ModTreeGrid
	@State var brush: Int = 3

	static let brushes: [String] = ["EMPTY", "TRUNK", "BRANCH", "LEAVES"]
	static let colours: [UInt32] = [0x1A2030, 0x7A5230, 0xA07040, 0x3E9A30]

	var body: some View {
		let g: ModTreeGrid = grid
		let cell: CGFloat = min(26, 300 / CGFloat(max(1, g.w)))
		let cw: CGFloat = cell * CGFloat(g.w)
		let ch: CGFloat = cell * CGFloat(g.h)
		return VStack(alignment: .leading, spacing: 8) {
			ChoiceRows(options: TreeGridEditor.brushes, selected: $brush, columns: 4)
			canvas(g, cell).frame(width: cw, height: ch)
			IntSlider(label: "Width", value: sizeBind(true), range: 3...15)
			IntSlider(label: "Height", value: sizeBind(false), range: 3...24)
			HStack(spacing: 8) {
				SmallButton(title: "CLEAR", color: ModUI.red) { self.clear() }
				SmallButton(title: "START FROM THE SAMPLE", color: ModUI.blue) { self.sample() }
			}
		}
	}

	func canvas(_ g: ModTreeGrid, _ cell: CGFloat) -> some View {
		let cols: [UInt32] = TreeGridEditor.colours
		return Canvas { ctx, size in
			for y in 0..<g.h {
				for x in 0..<g.w {
					let v: Int = Int(g.at(x, y))
					let r: CGRect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell - 1, height: cell - 1)
					ctx.fill(Path(r), with: .color(Color(hex: cols[clampI(v, 0, 3)])))
				}
			}
			// the root, where it stands on the ground
			let mid: CGFloat = CGFloat(g.w / 2) * cell
			ctx.fill(Path(CGRect(x: mid, y: CGFloat(g.h) * cell - 3, width: cell - 1, height: 3)), with: .color(Color(hex: 0xFFE066)))
		}
		.gesture(DragGesture(minimumDistance: 0).onChanged { (v: DragGesture.Value) in self.paint(v.location, cell) })
	}

	func paint(_ p: CGPoint, _ cell: CGFloat) {
		let x: Int = Int(floor(p.x / cell))
		let y: Int = Int(floor(p.y / cell))
		var g: ModTreeGrid = grid
		if x < 0 || y < 0 || x >= g.w || y >= g.h || !g.valid { return }
		let v: UInt8 = UInt8(clampI(brush, 0, 3))
		if g.cells[y * g.w + x] == v { return }
		g.cells[y * g.w + x] = v
		grid = g
	}

	func sizeBind(_ wide: Bool) -> Binding<Int> {
		let base: Binding<ModTreeGrid> = $grid
		return Binding<Int>(get: { wide ? base.wrappedValue.w : base.wrappedValue.h }, set: { v in
			let g: ModTreeGrid = base.wrappedValue
			if (wide ? g.w : g.h) == v { return }
			base.wrappedValue = wide ? g.resized(v, g.h) : g.resized(g.w, v)
		})
	}

	func clear() {
		var g: ModTreeGrid = grid
		g.cells = [UInt8](repeating: 0, count: g.w * g.h)
		grid = g
	}

	func sample() {
		var g: ModTreeGrid = grid
		g.cells = ModTreeGrid.sample(g.w, g.h)
		grid = g
	}
}

/// Editing one tree design: its name and shape, the blocks it is made of, its sizes and how often it grows,
/// and for a painted design the picture of it
struct TreeDesignEditor: View {
	@ObservedObject var s: ModSession
	let id: String
	var pickBlock: (String) -> Void
	var done: () -> Void

	func b<T>(_ kp: WritableKeyPath<ModTree, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.trees, id, kp, d) }
	var tree: ModTree { return s.mod.trees.first { $0.id == id } ?? ModTree() }

	static let shapeNames: [String] = ModTreeShape.allCases.map { $0.name }

	var body: some View {
		let t: ModTree = tree
		let painted: Bool = t.shape == .painted
		let pic: Image = pixImage(TreePreview.render(t, s.mod))
		return ModSection(title: t.name.uppercased(), help: "Its trunk, branches and leaves are always passed through, like the game's trees.") {
			pic.resizable().interpolation(.none).frame(width: 237, height: 150)
			ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Crystal Oak")
			Text("Shape").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: TreeDesignEditor.shapeNames, selected: shapeBind, columns: 3)
			blocksPart(t)
			if painted {
				TreeGridEditor(grid: b(\.grid, ModTreeGrid()))
			} else {
				sizesPart(t)
			}
			StatSlider(label: "How often it grows (among the region's designs)", value: b(\.weight, 1), range: 0.1...20.0, step: 0.1, format: "%.1f")
			SmallButton(title: "DONE", color: ModUI.accent) { self.done() }
		}
	}

	func blocksPart(_ t: ModTree) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			blockRow("Trunk", t.trunk, "trunk", "")
			blockRow("Branches", t.branch, "branch", t.branch.isEmpty ? "" : "SAME AS THE TRUNK")
			blockRow("Leaves", t.leaves, "leaves", "")
			blockRow("Grows only on", t.ground, "ground", t.ground.isEmpty ? "" : "ANY GROUND")
		}
	}

	func sizesPart(_ t: ModTree) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			IntSlider(label: "Shortest trunk", value: b(\.minHeight, 4), range: 1...24)
			IntSlider(label: "Tallest trunk", value: b(\.maxHeight, 7), range: 1...24)
			IntSlider(label: "Crown (how far the leaves reach)", value: b(\.crown, 2), range: 0...6)
			IntSlider(label: "Branches", value: b(\.branches, 1), range: 0...4)
			StatSlider(label: "Fullness of the leaves", value: b(\.density, 0.9), range: 0.2...1.0, step: 0.05, format: "%.2f")
			ModToggle(label: "A thick trunk", help: "Two blocks wide", isOn: b(\.thick, false))
		}
	}

	func blockRow(_ label: String, _ key: String, _ field: String, _ clear: String) -> some View {
		let img: Image = PatternGrid.cellImage(key, s.catalog)
		let name: String = key.isEmpty ? (field == "branch" ? "The trunk's block" : "Any") : ModGround.name(key, s.mod)
		let canClear: Bool = !clear.isEmpty
		return HStack(spacing: 10) {
			img.resizable().interpolation(.none).frame(width: 32, height: 32)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: label).font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
				Text(verbatim: name).font(.pixel(13, .bold)).foregroundColor(Color.white)
			}
			Spacer(minLength: 0)
			if canClear { SmallButton(title: clear) { self.clearField(field) } }
			SmallButton(title: "CHOOSE", color: ModUI.blue) { self.pickBlock(field) }
		}
	}

	func clearField(_ field: String) {
		if field == "branch" { b(\.branch, "").wrappedValue = "" }
		if field == "ground" { b(\.ground, "").wrappedValue = "" }
	}

	var shapeBind: Binding<Int> {
		let base: Binding<ModTreeShape> = b(\.shape, .round)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModTreeShape(rawValue: $0) ?? .round })
	}
}

struct DimensionEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var page: Int = 0
	@State var picking: String = ""
	@State var zonePick: Int = 0
	@State var preview: PixelBuf? = nil
	@State var previewOf: ModDimension? = nil
	/// which sky colour the palette sets (see skyColorNames)
	@State var skyPick: Int = 0
	/// the sun (0) or the moon (1) on the SUN & MOON page
	@State var bodyPick: Int = 0
	/// the tree design open on the TREES page
	@State var treeEdit: String = ""

	static let pages: [String] = ["BASICS", "SKY", "SUN & MOON", "LAND", "REGIONS", "TREES", "LIFE", "WAY IN", "PREVIEW"]
	static let bodyNames: [String] = ["SUN", "MOON"]
	static let skyColorNames: [String] = ["Day: top", "Day: bottom", "Night: top", "Night: bottom", "Sun"]

	func b<T>(_ kp: WritableKeyPath<ModDimension, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.dims, id, kp, d) }
	var dim: ModDimension { return s.mod.dims.first { $0.id == id } ?? ModDimension() }

	var body: some View {
		ZStack {
			VStack(spacing: 10) {
				header
				ChoiceRows(options: DimensionEditorView.pages, selected: $page, columns: 5)
				pageView
			}
		}
		.modCover(s, picking.isEmpty ? nil : picking) { self.blockPicker }
	}

	var blockPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE A BLOCK", blocksOnly: true, pick: { (it: Item) in
			self.setBlock(self.picking, SummonRuleEditor.key(it))
			self.picking = ""
		}, cancel: { self.picking = "" })
	}

	var header: some View {
		let d: ModDimension = dim
		let way: String = d.entry.enabled ? joinText("Way in: ", d.entry.how.name.lowercased()) : "No way in yet (visit it from the Mod Test tools)"
		let col: Color = d.entry.enabled ? ModUI.gold : Color(ui: 0xFF9060)
		return HStack(spacing: 12) {
			SkySwatch(top: d.skyTop, bottom: d.skyBottom).frame(width: 64, height: 64)
			VStack(alignment: .leading, spacing: 4) {
				Text(verbatim: d.name).font(.pixel(20)).foregroundColor(Color.white)
				Text(verbatim: way).font(.pixel(11, .semibold)).foregroundColor(col)
			}
			Spacer(minLength: 0)
		}
		.padding(10)
		.background(PixelBox(color: ModUI.card))
	}

	/// The page shown: a plain switch, as the creature editor's pages (wrapping each page in AnyView
	/// crashed on the iPad)
	@ViewBuilder
	var pageView: some View {
		switch page {
		case 1: skyPage
		case 2: bodiesPage
		case 3: landPage
		case 4: zonesPage
		case 5: treesPage
		case 6: lifePage
		case 7: entryPage
		case 8: previewPage
		default: basicsPage
		}
	}

	var bodiesPage: some View {
		let d: ModDimension = dim
		let pick: Int = clampI(bodyPick, 0, 1)
		let roof: Bool = d.ceiling
		return ModSection(title: "SUN AND MOON", help: "Give the dimension a sun and a moon of its own: a picture or a round one in your colour, its size and glow, how it crosses the sky, and how much light it gives (it lights the land as the game's do).") {
			if roof { Text("This is a cavern world: it has no sky, so they are never seen.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9060)) }
			ChoiceRows(options: DimensionEditorView.bodyNames, selected: $bodyPick, columns: 2)
			if pick == 0 {
				SkyBodyEditor(sky: b(\.sunBody, nil), moon: false, skyTop: d.skyTop, skyBottom: d.skyBottom)
			} else {
				SkyBodyEditor(sky: b(\.moonBody, nil), moon: true, skyTop: d.nightTop, skyBottom: d.nightBottom)
			}
		}
	}

	var treesPage: some View {
		let list: [ModTree] = s.mod.trees
		let editing: Bool = !treeEdit.isEmpty && list.contains { $0.id == treeEdit }
		let canAdd: Bool = list.count < ModTree.maxDesigns
		return VStack(spacing: 10) {
			Text("Tree designs belong to the whole mod: choose which grow in each region on the REGIONS page. Their trunks, branches and leaves are always passed through, like the game's trees: a solid block chosen for them grows as a pass-through form of itself (each such block uses one of a world's 64 mod block numbers).")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if editing {
				TreeDesignEditor(s: s, id: treeEdit, pickBlock: { (f: String) in self.picking = joinText("t:", f) }, done: { self.treeEdit = "" })
			} else {
				ForEach(list) { (t: ModTree) in self.treeRow(t) }
				if canAdd { SmallButton(title: "+ TREE DESIGN", color: ModUI.accent) { self.addTree() } }
			}
		}
	}

	func treeRow(_ t: ModTree) -> some View {
		let pic: Image = pixImage(TreePreview.render(t, s.mod))
		let uses: Int = treeUses(t.id)
		let where0: String = uses == 0 ? "not grown in any region yet" : joinText("grows in ", String(uses), uses == 1 ? " region" : " regions")
		let line: String = joinText(t.shape.name, " \u{00B7} ", where0)
		return HStack(spacing: 8) {
			pic.resizable().interpolation(.none).frame(width: 111, height: 70)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: t.name).font(.pixel(13)).foregroundColor(Color.white)
				Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			}
			Spacer(minLength: 0)
			SmallButton(title: "EDIT", color: ModUI.blue) { self.treeEdit = t.id }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.deleteTree(t.id) }
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func treeUses(_ tid: String) -> Int {
		var n: Int = 0
		for d in s.mod.dims {
			for z in d.zones where z.treeKinds.contains(tid) { n += 1 }
		}
		return n
	}

	func addTree() {
		var t = ModTree()
		t.id = s.mod.freshID("tree")
		t.name = joinText("Tree ", String(s.mod.trees.count + 1))
		s.mod.trees.append(t)
		s.touch()
		treeEdit = t.id
	}

	func deleteTree(_ tid: String) {
		s.mod.trees.removeAll { $0.id == tid }
		for i in s.mod.dims.indices {
			for k in s.mod.dims[i].zones.indices { s.mod.dims[i].zones[k].treeKinds.removeAll { $0 == tid } }
		}
		s.touch()
	}

	var basicsPage: some View {
		ModSection(title: "BASICS") {
			ModTextField(label: "Name", text: b(\.name, ""), placeholder: "The Frostlands")
			ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
			ModTextField(label: "Message on arrival", text: b(\.arriveMessage, ""), placeholder: "Snow crunches underfoot.")
		}
	}

	var skyPage: some View {
		VStack(spacing: 10) {
			skySection
			lightSection
			airSection
		}
	}

	var skySection: some View {
		let pick: Int = clampI(skyPick, 0, DimensionEditorView.skyColorNames.count - 1)
		return ModSection(title: "SKY", help: "Colours at the top and the bottom of the sky, by day and by night, and the sun's. Choose one, then tap a colour.") {
			ModToggle(label: "A rock roof overhead (a cavern world)", help: "No sky, sun or rain; like the Umbral Realm", isOn: b(\.ceiling, false))
			skyPictures
			ChoiceRows(options: DimensionEditorView.skyColorNames, selected: $skyPick, columns: 5)
			ModColorRow(label: DimensionEditorView.skyColorNames[pick], color: skyColorBind(pick))
		}
	}

	/// The day sky, the night sky and the sun, as they are now
	var skyPictures: some View {
		let d: ModDimension = dim
		let sun: Color = Color(ui: d.sunColor & 0xFFFFFF)
		return HStack(alignment: .bottom, spacing: 12) {
			skyPicture("DAY", d.skyTop, d.skyBottom)
			skyPicture("NIGHT", d.nightTop, d.nightBottom)
			VStack(spacing: 2) {
				Rectangle().fill(sun).frame(width: 28, height: 28).overlay(Rectangle().stroke(Color.black, lineWidth: 1))
				Text("SUN").font(.pixel(10)).foregroundColor(ModUI.dim)
			}
		}
	}

	func skyPicture(_ name: String, _ top: UInt32, _ bottom: UInt32) -> some View {
		VStack(spacing: 2) {
			SkySwatch(top: top, bottom: bottom).frame(width: 96, height: 54)
			Text(verbatim: name).font(.pixel(10)).foregroundColor(ModUI.dim)
		}
	}

	/// The sky colour the palette sets
	func skyColorBind(_ pick: Int) -> Binding<UInt32> {
		switch pick {
		case 1: return b(\.skyBottom, 0xC07AB0)
		case 2: return b(\.nightTop, 0x080614)
		case 3: return b(\.nightBottom, 0x241A3A)
		case 4: return b(\.sunColor, 0xFFE8A0)
		default: return b(\.skyTop, 0x3A2A6A)
		}
	}

	var lightSection: some View {
		let fixed: Bool = !dim.cycle
		let word: String = timeWord(dim.fixedTime)
		return ModSection(title: "LIGHT AND TIME") {
			StatSlider(label: "Daylight", value: b(\.light, 0.8), range: 0.0...1.0, step: 0.05, format: "%.2f")
			ModToggle(label: "Day and night", help: "Off: it is always the same time there", isOn: b(\.cycle, true))
			if fixed {
				StatSlider(label: "The time it always is", value: b(\.fixedTime, 0.25), range: 0.0...1.0, step: 0.01, format: "%.2f")
				Text(verbatim: word).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
			ModToggle(label: "Sun", isOn: b(\.sun, true))
			ModToggle(label: "Moon", isOn: b(\.moon, true))
			ModToggle(label: "Stars", isOn: b(\.stars, true))
		}
	}

	var airSection: some View {
		ModSection(title: "AIR AND WEATHER") {
			Text("Motes in the air").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: ModDimText.ambients, selected: b(\.ambient, 0), columns: 6)
			Text("Weather").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: ModDimText.weathers, selected: b(\.weather, 0), columns: 5)
			StatSlider(label: "Cold", value: b(\.chill, 0), range: 0.0...1.0, step: 0.05, format: "%.2f")
			ModToggle(label: "Hot", isOn: b(\.hot, false))
		}
	}

	func timeWord(_ t: Double) -> String {
		if t < 0.04 || t > 0.95 { return "Dawn" }
		if t < 0.46 { return "Day" }
		if t < 0.6 { return "Dusk" }
		return "Night"
	}

	var landPage: some View {
		VStack(spacing: 10) {
			groundSection
			ModSection(title: "UNDERGROUND") {
				StatSlider(label: "Caves", value: b(\.caves, 0.4), range: 0.0...1.0, step: 0.05, format: "%.2f")
				ModToggle(label: "Pools deep in the caves", isOn: b(\.pools, true))
			}
			seaSection
			hazardSection
		}
	}

	var groundSection: some View {
		let low: Int = dim.ceiling ? 80 : 40
		let rows: ClosedRange<Int> = low...260
		let rock: String = dim.stone
		return ModSection(title: "THE GROUND", help: "Rows count down from the top of the dimension (320 rows deep).") {
			IntSlider(label: "Ground level (row)", value: b(\.surface, 150), range: rows)
			StatSlider(label: "Hills", value: b(\.hills, 12), range: 0.0...40.0, step: 1, format: "%.0f")
			StatSlider(label: "Roughness", value: b(\.roughness, 1), range: 0.2...3.0, step: 0.1, format: "%.1f")
			StatSlider(label: "Mountains", value: b(\.mountains, 0.2), range: 0.0...1.0, step: 0.05, format: "%.2f")
			blockRow("Rock", rock, "stone")
		}
	}

	var seaSection: some View {
		let seas: Bool = dim.sea > 0
		return ModSection(title: "SEAS AND SKY") {
			ModToggle(label: "Seas", isOn: seaOn)
			if seas { IntSlider(label: "Sea level (row)", value: b(\.sea, 160), range: 60...280) }
			ChoiceRows(options: ModDimText.liquids, selected: b(\.liquid, 0), columns: 2)
			StatSlider(label: "Floating islands", value: b(\.islands, 0), range: 0.0...1.0, step: 0.05, format: "%.2f")
		}
	}

	var hazardSection: some View {
		let hz: String = dim.hazard
		let has: Bool = !hz.isEmpty
		return ModSection(title: "HAZARDS", help: "A block scattered on the ground, such as spikes or one of your own.") {
			blockRow("Hazard", hz, "hazard")
			if has {
				StatSlider(label: "How often", value: b(\.hazardChance, 0.02), range: 0.0...0.3, step: 0.01, format: "%.2f")
				SmallButton(title: "NO HAZARD", color: ModUI.red) { self.setBlock("hazard", "") }
			}
		}
	}

	var seaOn: Binding<Bool> {
		let base: Binding<Int> = b(\.sea, 0)
		let surf: Int = dim.surface
		return Binding<Bool>(get: { base.wrappedValue > 0 }, set: { on in base.wrappedValue = on ? clampI(surf + 6, 60, 280) : 0 })
	}

	func blockRow(_ label: String, _ key: String, _ field: String) -> some View {
		let img: Image = PatternGrid.cellImage(key, s.catalog)
		let name: String = key.isEmpty ? "None" : ModGround.name(key, s.mod)
		return HStack(spacing: 10) {
			img.resizable().interpolation(.none).frame(width: 32, height: 32)
			VStack(alignment: .leading, spacing: 2) {
				Text(verbatim: label).font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
				Text(verbatim: name).font(.pixel(13, .bold)).foregroundColor(Color.white)
			}
			Spacer(minLength: 0)
			SmallButton(title: "CHOOSE", color: ModUI.blue) { self.picking = field }
		}
	}

	/// A block chosen in the picker goes where it was asked for (a region's blocks are "z<n>:<field>",
	/// the open tree design's "t:<field>")
	func setBlock(_ field: String, _ key: String) {
		if field.hasPrefix("t:") {
			guard let ti = s.mod.trees.firstIndex(where: { $0.id == treeEdit }) else { return }
			var t: ModTree = s.mod.trees[ti]
			let part: String = String(field.dropFirst(2))
			switch part {
			case "trunk": if !key.isEmpty { t.trunk = key }
			case "branch": t.branch = key
			case "leaves": if !key.isEmpty { t.leaves = key }
			case "ground": t.ground = key
			default: break
			}
			s.mod.trees[ti] = t
			s.touch()
			return
		}
		guard let i = s.mod.dims.firstIndex(where: { $0.id == id }) else { return }
		var d: ModDimension = s.mod.dims[i]
		if field.hasPrefix("z") {
			let parts: [Substring] = field.dropFirst().split(separator: ":")
			guard parts.count == 2, let zi = Int(parts[0]), zi >= 0 && zi < d.zones.count else { return }
			switch parts[1] {
			case "ground": if !key.isEmpty { d.zones[zi].ground = key }
			case "filler": if !key.isEmpty { d.zones[zi].filler = key }
			case "plant": d.zones[zi].plant = key
			case "log": if !key.isEmpty { d.zones[zi].log = key }
			case "leaves": if !key.isEmpty { d.zones[zi].leaves = key }
			default: break
			}
		} else {
			switch field {
			case "stone": if !key.isEmpty { d.stone = key }
			case "hazard": d.hazard = key
			case "gate": d.gateBlock = key.hasPrefix("tile:") ? "" : key
			default: break
			}
		}
		s.mod.dims[i] = d
		s.touch()
	}

	func zb<T>(_ i: Int, _ kp: WritableKeyPath<ModDimZone, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModDimZone]> = b(\.zones, [])
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModDimZone] = base.wrappedValue
			if i < list.count {
				list[i][keyPath: kp] = v
				base.wrappedValue = list
			}
		})
	}

	var zonesPage: some View {
		let zones: [ModDimZone] = dim.zones
		let zi: Int = clampI(zonePick, 0, max(0, zones.count - 1))
		let names: [String] = zones.map { $0.name }
		let many: Bool = zones.count > 1
		return VStack(spacing: 10) {
			Text("Regions lie side by side, each with its own ground, plants and trees: the dimension's biomes. Each counts as one of the game's biomes for ores, structures, summoning and creature rules.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: names, selected: $zonePick, columns: 4)
			zoneButtons(zones.count, zi)
			if zi < zones.count { zoneEditor(zi, zones[zi]) }
			if many { IntSlider(label: "Width of each region (blocks)", value: b(\.zoneWidth, 300), range: 40...2000) }
		}
	}

	func zoneButtons(_ count: Int, _ zi: Int) -> some View {
		let canAdd: Bool = count < 4
		let canDelete: Bool = count > 1
		return HStack(spacing: 8) {
			if canAdd { SmallButton(title: "+ REGION", color: ModUI.accent) { self.addZone() } }
			if canDelete { SmallButton(title: "DELETE THIS REGION", color: ModUI.red) { self.deleteZone(zi) } }
		}
	}

	func addZone() {
		var l: [ModDimZone] = dim.zones
		var z = ModDimZone()
		z.name = joinText("Region ", String(l.count + 1))
		l.append(z)
		b(\.zones, []).wrappedValue = l
		zonePick = l.count - 1
	}

	func deleteZone(_ zi: Int) {
		var l: [ModDimZone] = dim.zones
		if zi < l.count { l.remove(at: zi) }
		b(\.zones, []).wrappedValue = l
		zonePick = 0
	}

	static let biomeNames: [String] = ModBiomePicker.all.map { $0.name }

	func zoneEditor(_ zi: Int, _ z: ModDimZone) -> some View {
		let tag: String = joinText("z", String(zi), ":")
		let plants: Bool = !z.plant.isEmpty
		let trees: Bool = z.trees > 0
		return ModSection(title: z.name.uppercased()) {
			ModTextField(label: "Name", text: zb(zi, \.name, ""), placeholder: "Frozen Wastes")
			Text("Counts as").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: DimensionEditorView.biomeNames, selected: biomeBind(zi), columns: 5)
			blockRow("Ground", z.ground, joinText(tag, "ground"))
			blockRow("Under the ground", z.filler, joinText(tag, "filler"))
			blockRow("Plants", z.plant, joinText(tag, "plant"))
			if plants { StatSlider(label: "How many plants", value: zb(zi, \.plantChance, 0.1), range: 0.0...0.8, step: 0.02, format: "%.2f") }
			Text("Trees").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			ChoiceRows(options: ModDimText.trees, selected: zb(zi, \.trees, 1), columns: 3)
			if trees { treeKindsPart(zi, z) }
			if trees && z.treeKinds.isEmpty {
				blockRow("Trunk", z.log, joinText(tag, "log"))
				blockRow("Leaves", z.leaves, joinText(tag, "leaves"))
			}
		}
	}

	func treeKindsPart(_ zi: Int, _ z: ModDimZone) -> some View {
		let list: [ModTree] = s.mod.trees
		let none: Bool = list.isEmpty
		return VStack(alignment: .leading, spacing: 6) {
			Text("Tree designs that grow here (none chosen: simple trees of the trunk and leaves below)").font(.pixel(11, .bold)).foregroundColor(ModUI.dim)
			if none {
				Text("Make designs on the TREES page.").font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			} else {
				PlainGrid(count: list.count, per: 3) { (i: Int) in self.treeChip(zi, z, list[i]) }
			}
		}
	}

	func treeChip(_ zi: Int, _ z: ModDimZone, _ t: ModTree) -> some View {
		let on: Bool = z.treeKinds.contains(t.id)
		return ToggleChip(title: t.name, on: on) { self.toggleTree(zi, t.id) }
	}

	func toggleTree(_ zi: Int, _ tid: String) {
		let bind: Binding<[String]> = zb(zi, \.treeKinds, [])
		var l: [String] = bind.wrappedValue
		if let k = l.firstIndex(of: tid) {
			l.remove(at: k)
		} else if l.count < ModTree.maxDesigns {
			l.append(tid)
		}
		bind.wrappedValue = l
	}

	func biomeBind(_ zi: Int) -> Binding<Int> {
		let base: Binding<Int> = zb(zi, \.biome, Biome.plains.rawValue)
		let all: [Biome] = ModBiomePicker.all
		return Binding<Int>(get: { all.firstIndex { $0.rawValue == base.wrappedValue } ?? 0 }, set: { v in base.wrappedValue = all[clampI(v, 0, all.count - 1)].rawValue })
	}

	func sp<T>(_ i: Int, _ kp: WritableKeyPath<ModDimSpawn, T>, _ d: T) -> Binding<T> {
		let base: Binding<[ModDimSpawn]> = b(\.spawns, [])
		return Binding<T>(get: { i < base.wrappedValue.count ? base.wrappedValue[i][keyPath: kp] : d }, set: { v in
			var list: [ModDimSpawn] = base.wrappedValue
			if i < list.count {
				list[i][keyPath: kp] = v
				base.wrappedValue = list
			}
		})
	}

	static let gameCreatures: [MobKind] = [.pig, .cow, .sheep, .wolf, .bat, .zombie, .skeleton, .slime, .wraith, .imp, .emberSlime, .cinderBat, .crawler, .golem]

	var creatureChoices: ([String], [String]) {
		var names: [String] = []
		var keys: [String] = []
		for m in s.mod.mobs {
			names.append(m.name)
			keys.append(s.mod.key(m.id))
		}
		for k in DimensionEditorView.gameCreatures {
			names.append(mobDef(k).name)
			keys.append(mobDef(k).name)
		}
		return (names, keys)
	}

	var lifePage: some View {
		let ch: ([String], [String]) = creatureChoices
		let n: Int = dim.spawns.count
		let canAdd: Bool = n < 8
		return VStack(spacing: 10) {
			Text("The creatures of this dimension (the game's own creatures don't come here unless you list them). Bosses are best called with a SUMMON rule that only works in this dimension.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ForEach(0..<n, id: \.self) { i in self.spawnCard(i, ch) }
			if canAdd { PixelButton(title: "+ ADD A CREATURE", color: ModUI.accent) { self.addSpawn(ch.1) } }
		}
	}

	func spawnCard(_ i: Int, _ ch: ([String], [String])) -> some View {
		let who: String = i < dim.spawns.count ? nameOf(dim.spawns[i].creature) : ""
		let title: String = joinText(String(i + 1), ". ", who)
		return VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(verbatim: title).font(.pixel(13, .bold)).foregroundColor(Color.white)
				Spacer(minLength: 0)
				SmallButton(title: "DELETE", color: ModUI.red) { self.deleteSpawn(i) }
			}
			ChoiceRows(options: ch.0, selected: creatureBind(i, ch.1), columns: 4)
			ChoiceRows(options: ModDimText.places, selected: sp(i, \.place, 0), columns: 3)
			ChoiceRows(options: ModDimText.times, selected: sp(i, \.when, 0), columns: 3)
			StatSlider(label: "How common", value: sp(i, \.weight, 5), range: 0.1...20.0, step: 0.1, format: "%.1f")
			IntSlider(label: "Group", value: sp(i, \.group, 1), range: 1...4)
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func deleteSpawn(_ i: Int) {
		var l: [ModDimSpawn] = dim.spawns
		if i < l.count { l.remove(at: i) }
		b(\.spawns, []).wrappedValue = l
	}

	func addSpawn(_ keys: [String]) {
		var l: [ModDimSpawn] = dim.spawns
		var n = ModDimSpawn()
		n.creature = keys.first ?? mobDef(.zombie).name
		l.append(n)
		b(\.spawns, []).wrappedValue = l
	}

	func nameOf(_ key: String) -> String {
		if let m = s.mod.mobs.first(where: { s.mod.key($0.id) == key }) { return m.name }
		return key
	}

	func creatureBind(_ i: Int, _ keys: [String]) -> Binding<Int> {
		let base: Binding<String> = sp(i, \.creature, "")
		return Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { v in if !keys.isEmpty { base.wrappedValue = keys[clampI(v, 0, keys.count - 1)] } })
	}

	var entryPage: some View {
		VStack(spacing: 10) {
			ModSection(title: "THE WAY BACK") {
				ModToggle(label: "A gate where the player arrives", help: "Tapping it takes them back to where they came in", isOn: b(\.returnGate, true))
				if dim.returnGate {
					blockRow("The gate's block (one of this mod's)", dim.gateBlock, "gate")
					if dim.gateBlock.isEmpty {
						Text("None chosen: a glowing crystal.").font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
					}
				}
			}
			ModSection(title: "THE WAY IN", help: "For a portal, draw a frame of your gateway block with EMPTY inside, and use a key item on it.") {
				SummonRuleEditor(s: s, rule: b(\.entry, ModDimension.defaultEntry), forDimension: true)
			}
		}
	}

	var previewPage: some View {
		VStack(spacing: 10) {
			Text("Six chunks of the dimension, from the top to the bottom, made by the same generator the game uses (a sample world). Make the preview again after changing something.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			PixelButton(title: preview == nil ? "MAKE PREVIEW" : "MAKE IT AGAIN", color: ModUI.blue) {
				preview = ModDimPreview.render(dim, s.mod)
				previewOf = dim
			}
			if let p = preview {
				pixImage(p).resizable().interpolation(.none)
					.frame(width: CGFloat(p.w) * 1.5, height: CGFloat(p.h) * 1.5)
					.background(Color.black)
				if previewOf != dim {
					Text("Changed since this preview was made.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFF9060))
				}
			}
		}
	}
}

/// The dimension an ore or structure is made in: the game's two, or one of the mod's own
struct ModDimChoice: View {
	@ObservedObject var s: ModSession
	@Binding var dim: Int
	@Binding var dimKey: String

	var body: some View {
		let names: [String] = ["Overworld", "Umbral Realm"] + s.mod.dims.map { $0.name }
		let ids: [String] = s.mod.dims.map { $0.id }
		let sel: Binding<Int> = Binding<Int>(get: {
			if !dimKey.isEmpty, let i = ids.firstIndex(of: dimKey) { return 2 + i }
			return dim == 1 ? 1 : 0
		}, set: { v in
			if v >= 2 && v - 2 < ids.count {
				dimKey = ids[v - 2]
			} else {
				dimKey = ""
				dim = v == 1 ? 1 : 0
			}
		})
		return ChoiceRow(options: names, selected: sel, columns: min(5, names.count))
	}
}

/// A little square of a dimension's sky (its two colours and the step between)
struct SkySwatch: View {
	let top: UInt32
	let bottom: UInt32
	var body: some View {
		VStack(spacing: 0) {
			Rectangle().fill(Color(hex: top))
			Rectangle().fill(Color(hex: mixRGB(top, bottom, 0.5)))
			Rectangle().fill(Color(hex: bottom))
		}
	}
}

// MARK: - Mod Creator+: Logic Studio (screens)

/// Finding, changing and moving blocks inside a script. A path is a block's place: its index at the top
/// level, then for each block it sits in, which part (0 inside, 1 else) and its index there.
enum LPath {
	static func get(_ list: [LNode], _ path: [Int]) -> LNode? {
		guard let i = path.first, i >= 0, i < list.count else { return nil }
		if path.count == 1 { return list[i] }
		let rest: [Int] = Array(path.dropFirst(2))
		return path[1] == 0 ? get(list[i].body, rest) : get(list[i].alt, rest)
	}

	static func update(_ list: inout [LNode], _ path: [Int], _ f: (inout LNode) -> Void) {
		guard let i = path.first, i >= 0, i < list.count else { return }
		if path.count == 1 {
			f(&list[i])
			return
		}
		if path.count < 3 { return }
		let rest: [Int] = Array(path.dropFirst(2))
		if path[1] == 0 { update(&list[i].body, rest, f) } else { update(&list[i].alt, rest, f) }
	}

	/// the list a block sits in, changed by f
	static func updateList(_ list: inout [LNode], _ parent: [Int], _ f: (inout [LNode]) -> Void) {
		if parent.isEmpty {
			f(&list)
			return
		}
		let container: [Int] = Array(parent.dropLast())
		let br: Int = parent.last ?? 0
		update(&list, container) { n in
			if br == 0 { f(&n.body) } else { f(&n.alt) }
		}
	}

	static func remove(_ list: inout [LNode], _ path: [Int]) {
		guard let i = path.last else { return }
		updateList(&list, Array(path.dropLast())) { l in if i >= 0 && i < l.count { l.remove(at: i) } }
	}

	static func move(_ list: inout [LNode], _ path: [Int], _ d: Int) {
		guard let i = path.last else { return }
		updateList(&list, Array(path.dropLast())) { l in
			let j: Int = i + d
			if i >= 0 && i < l.count && j >= 0 && j < l.count { l.swapAt(i, j) }
		}
	}

	/// `into` is a block's path and a part (0 inside, 1 else); nil adds to the end of the script
	static func insert(_ list: inout [LNode], _ into: [Int]?, _ node: LNode) {
		guard let p = into, p.count >= 2 else {
			list.append(node)
			return
		}
		updateList(&list, p) { l in l.append(node) }
	}

	static func exprUpdate(_ e: inout LExpr, _ path: [Int], _ f: (inout LExpr) -> Void) {
		if path.isEmpty {
			f(&e)
			return
		}
		let i: Int = path[0]
		if i < 0 || i >= e.args.count { return }
		exprUpdate(&e.args[i], Array(path.dropFirst()), f)
	}
}

/// The LOGIC STUDIO tab: the mod's variables and scripts (optional: everything else works without it)
struct LogicStudioView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void
	@State var newVar: String = ""

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Optional. Every part of the Mod Creator works without scripts. Scripts are stacks of blocks run by the game's own safe interpreter: they can only use the blocks shown here, loops that go on must wait, and nothing outside the game can be reached.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			variablesSection
			addRow
			ForEach(s.mod.scripts) { sc in self.scriptRow(sc) }
		}
	}

	var variablesSection: some View {
		let vars: [String] = s.mod.variables
		let room: Bool = vars.count < LLimits.maxVariables
		return ModSection(title: "VARIABLES", help: "Numbers your scripts keep, one set per world (saved with it).") {
			ForEach(vars, id: \.self) { v in self.variableRow(v) }
			if room {
				HStack(spacing: 8) {
					ModTextField(label: "New variable", text: $newVar, placeholder: "score")
					SmallButton(title: "+ ADD", color: ModUI.accent) { self.addVariable() }
				}
			}
		}
	}

	func variableRow(_ v: String) -> some View {
		HStack {
			Text(verbatim: v).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: "DELETE", color: ModUI.red) { self.deleteVariable(v) }
		}
	}

	func deleteVariable(_ v: String) {
		s.mod.variables.removeAll { $0 == v }
		s.touch()
	}

	func addVariable() {
		let n: String = String(newVar.trimmingCharacters(in: .whitespaces).prefix(20))
		if !n.isEmpty && !s.mod.variables.contains(n) {
			s.mod.variables.append(n)
			s.touch()
		}
		newVar = ""
	}

	var addRow: some View {
		let room: Bool = s.mod.scripts.count < LLimits.maxScripts
		return HStack(spacing: 8) {
			if room {
				PixelButton(title: "+ NEW SCRIPT", color: ModUI.accent) { self.add(.worldStart) }
				PixelButton(title: "+ NEW GROUP", color: Color(ui: 0x8A6A2A)) { self.add(.group) }
			}
		}
	}

	func scriptRow(_ sc: ModScript) -> some View {
		let bar: Color = Color(ui: sc.event == .group ? 0xC08A3A : 0xE8C040)
		let nameCol: Color = sc.enabled ? Color.white : ModUI.dim
		let blocks: String = String(LogicStudioView.count(sc.blocks))
		let line: String = joinText(sc.event.name, " \u{00B7} ", blocks, " blocks", sc.enabled ? "" : " \u{00B7} off")
		return Button(action: { self.open(sc.id) }) {
			HStack(spacing: 10) {
				Rectangle().fill(bar).frame(width: 10, height: 44)
				VStack(alignment: .leading, spacing: 3) {
					Text(verbatim: sc.name).font(.pixel(14)).foregroundColor(nameCol)
					Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
				}
				Spacer(minLength: 0)
			}
			.padding(8)
			.frame(maxWidth: .infinity, alignment: .leading)
			.background(PixelBox(color: ModUI.card))
		}
		.buttonStyle(.plain)
	}

	static func count(_ l: [LNode]) -> Int {
		var n: Int = 0
		for b in l { n += 1 + count(b.body) + count(b.alt) }
		return n
	}

	func add(_ e: LEvent) {
		var sc = ModScript()
		sc.id = s.mod.freshID("sc")
		sc.event = e
		let number: String = String(s.mod.scripts.count + 1)
		let word: String = e == .group ? "Group " : "Script "
		sc.name = joinText(word, number)
		if e == .worldStart {
			var hi = LNode(.say)
			hi.s = "My mod is on!"
			sc.blocks = [hi]
		}
		s.mod.scripts.append(sc)
		s.touch()
		open(sc.id)
	}
}

/// Editing one script, Scratch-style: what starts it (the hat), then its blocks. Tap a block in the
/// palette to add it at the end, or inside the block chosen with IN.
struct ScriptEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var cat: Int = 0
	/// where new blocks go: a block's path and part, or nil for the end of the script
	@State var into: [Int]? = nil
	@State var exprPick: ([Int], Int, [Int])? = nil
	@State var itemPick: [Int]? = nil
	@State var exprItemPick: ([Int], Int, [Int])? = nil
	@State var blockPick: [Int]? = nil

	var script: ModScript { return s.mod.scripts.first { $0.id == id } ?? ModScript() }
	func b<T>(_ kp: WritableKeyPath<ModScript, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.scripts, id, kp, d) }

	var body: some View {
		ZStack {
			VStack(alignment: .leading, spacing: 10) {
				hat
				palette
				whereNote
				blockList(script.blocks, [])
				if script.blocks.isEmpty {
					Text("No blocks yet: tap one in the palette above.").font(.pixel(12)).foregroundColor(ModUI.dim)
				}
				issues
			}
		}
		.modCover(s, coverKey) { self.overlay }
	}

	/// which picker is open (nil: none)
	var coverKey: Int? {
		if exprPick != nil { return 1 }
		if itemPick != nil { return 2 }
		if exprItemPick != nil { return 3 }
		if blockPick != nil { return 4 }
		return nil
	}

	var whereNote: some View {
		let atEnd: Bool = into == nil
		let text: String = atEnd ? "New blocks go at the end of the script." : joinText("New blocks go inside \u{201C}", intoTitle, "\u{201D}.")
		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: text).font(.pixel(11, .bold)).foregroundColor(ModUI.gold)
			if !atEnd { SmallButton(title: "ADD AT THE END INSTEAD", color: ModUI.blue) { self.into = nil } }
		}
	}

	/// The picker that is open, if any
	var overlay: AnyView {
		if let ep = exprPick { return AnyView(reporterPicker(ep)) }
		if let ip = itemPick { return AnyView(itemPicker(ip)) }
		if let ep = exprItemPick { return AnyView(exprItemPicker(ep)) }
		if let bp = blockPick { return AnyView(blockPicker(bp)) }
		return AnyView(EmptyView())
	}

	func reporterPicker(_ ep: ([Int], Int, [Int])) -> some View {
		ReporterPicker(s: s, pick: { (e: LExpr) in
			self.setExpr(ep.0, ep.1, ep.2) { $0 = e }
			self.exprPick = nil
		}, cancel: { self.exprPick = nil })
	}

	func itemPicker(_ ip: [Int]) -> some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE AN ITEM", pick: { (it: Item) in
			self.edit(ip) { $0.item = it }
			self.itemPick = nil
		}, cancel: { self.itemPick = nil })
	}

	func exprItemPicker(_ ep: ([Int], Int, [Int])) -> some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE AN ITEM", pick: { (it: Item) in
			self.setExpr(ep.0, ep.1, ep.2) { $0.item = it }
			self.exprItemPick = nil
		}, cancel: { self.exprItemPick = nil })
	}

	func blockPicker(_ bp: [Int]) -> some View {
		ItemPickerView(catalog: s.catalog, title: "CHOOSE A BLOCK", blocksOnly: true, pick: { (it: Item) in
			let k: String = SummonRuleEditor.key(it)
			self.edit(bp) { $0.s = k }
			self.blockPick = nil
		}, cancel: { self.blockPick = nil })
	}

	var intoTitle: String {
		guard let p = into, p.count >= 2, let n = LPath.get(script.blocks, Array(p.dropLast())) else { return "the script" }
		return LSpec.of(n.op).title + (p.last == 1 ? " (else)" : "")
	}

	// MARK: the hat block

	var hat: some View {
		let sc: ModScript = script
		let group: Bool = sc.event == .group
		let bg: Color = Color(ui: group ? 0xC08A3A : 0xE8C040)
		return VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Boss rage")
				ModToggle(label: "On", isOn: b(\.enabled, true))
			}
			if group { groupInputs } else { eventPart(sc) }
		}
		.padding(10)
		.background(bg)
		.cornerRadius(10)
	}

	var groupInputs: some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("A GROUP: other scripts run it with \u{201C}run a group\u{201D}, giving it up to three inputs (read them with \u{201C}group input\u{201D}).")
				.font(.pixel(11, .semibold)).foregroundColor(Color.black)
			ForEach(0..<3, id: \.self) { k in self.inputField(k) }
		}
	}

	func inputField(_ k: Int) -> ModTextField {
		let label: String = joinText("Input ", String(k + 1))
		let hint: String = k == 0 ? "damage" : ""
		return ModTextField(label: label, text: paramBind(k), placeholder: hint)
	}

	static let eventList: [LEvent] = LEvent.allCases.filter { $0 != .group }
	static let eventNames: [String] = ScriptEditorView.eventList.map { $0.name }

	func eventPart(_ sc: ModScript) -> some View {
		VStack(alignment: .leading, spacing: 6) {
			Text("WHEN").font(.pixel(12, .bold)).foregroundColor(Color.black)
			ChoiceRow(options: ScriptEditorView.eventNames, selected: eventBind, columns: 2)
			eventDetail(sc)
			eventTarget(sc)
		}
	}

	var eventBind: Binding<Int> {
		let base: Binding<LEvent> = b(\.event, .worldStart)
		let list: [LEvent] = LEvent.allCases.filter { $0 != .group }
		return Binding<Int>(get: { list.firstIndex(of: base.wrappedValue) ?? 0 }, set: { base.wrappedValue = list[clampI($0, 0, list.count - 1)] })
	}

	func paramBind(_ k: Int) -> Binding<String> {
		let base: Binding<[String]> = b(\.params, [])
		return Binding<String>(get: { k < base.wrappedValue.count ? base.wrappedValue[k] : "" }, set: { v in
			var l: [String] = base.wrappedValue
			while l.count <= k { l.append("") }
			l[k] = String(v.prefix(16))
			base.wrappedValue = l
		})
	}

	func eventDetail(_ sc: ModScript) -> AnyView {
		switch sc.event {
		case .every, .creatureEvery:
			return AnyView(StatSlider(label: "Seconds between", value: b(\.ev, 5), range: 0.25...120.0, step: 0.25, format: "%.2f", unit: " s"))
		case .phase:
			return AnyView(StatSlider(label: "Phase", value: b(\.ev, 1), range: 1.0...6.0, step: 1, format: "%.0f"))
		case .custom:
			return AnyView(ModTextField(label: "Message name", text: b(\.evText, ""), placeholder: "open the gate"))
		case .enterDim:
			let names: [String] = ["Any dimension"] + s.mod.dims.map { $0.name }
			return AnyView(ChoiceRow(options: names, selected: dimEventBind, columns: 3))
		default:
			return AnyView(EmptyView())
		}
	}

	func eventTarget(_ sc: ModScript) -> AnyView {
		var opts: [(String, String)] = []
		var label: String = ""
		switch sc.event.subject {
		case 1:
			label = "Which creature"
			for m in s.mod.mobs { opts.append((m.name, s.mod.key(m.id))) }
		case 2:
			label = "Which item"
			for m in s.mod.items { opts.append((m.name, s.mod.key(m.id))) }
		case 3:
			label = "Which block"
			for m in s.mod.blocks { opts.append((m.name, s.mod.key(m.id))) }
		default:
			return AnyView(EmptyView())
		}
		return AnyView(targetRow(label, opts))
	}

	var dimEventBind: Binding<Int> {
		let base: Binding<String> = b(\.evText, "")
		let keys: [String] = [""] + s.mod.dims.map { s.mod.key($0.id) }
		return Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? 0 }, set: { base.wrappedValue = keys[clampI($0, 0, keys.count - 1)] })
	}

	func targetRow(_ label: String, _ opts: [(String, String)]) -> some View {
		let base: Binding<String> = b(\.target, "")
		let keys: [String] = opts.map { $0.1 }
		let sel: Binding<Int> = Binding<Int>(get: { keys.firstIndex(of: base.wrappedValue) ?? -1 }, set: { v in if !keys.isEmpty { base.wrappedValue = keys[clampI(v, 0, keys.count - 1)] } })
		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: label).font(.pixel(11, .bold)).foregroundColor(Color.black)
			if opts.isEmpty {
				Text("Make one in this mod first.").font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0x7A1A1A))
			} else {
				ChoiceRow(options: opts.map { $0.0 }, selected: sel, columns: 3)
			}
		}
	}

	// MARK: the palette

	static let catNames: [String] = LCat.allCases.map { $0.name }

	var palette: some View {
		let cats: [LCat] = LCat.allCases
		let c: LCat = cats[clampI(cat, 0, cats.count - 1)]
		let specs: [LSpec] = LSpec.all.filter { $0.cat == c }
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 6)]
		let col: Color = Color(ui: c.color)
		return VStack(alignment: .leading, spacing: 6) {
			ChoiceRow(options: ScriptEditorView.catNames, selected: $cat, columns: 4)
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(0..<specs.count, id: \.self) { k in self.paletteButton(specs[k], col) }
			}
		}
		.padding(8)
		.background(PixelBox(color: ModUI.card))
	}

	func paletteButton(_ sp: LSpec, _ col: Color) -> some View {
		Button(action: { self.addBlock(sp.op) }) {
			Text(verbatim: sp.title).font(.pixel(11, .bold)).foregroundColor(Color.white)
				.multilineTextAlignment(.center)
				.frame(maxWidth: .infinity, minHeight: 44)
				.background(col)
				.cornerRadius(8)
		}
		.buttonStyle(.plain)
	}

	func addBlock(_ op: LOp) {
		var list: [LNode] = script.blocks
		if LogicStudioView.count(list) >= LLimits.maxBlocks { return }
		LPath.insert(&list, into, LNode(op))
		b(\.blocks, []).wrappedValue = list
	}

	// MARK: the script

	func blockList(_ list: [LNode], _ base: [Int]) -> AnyView {
		return AnyView(VStack(alignment: .leading, spacing: 4) {
			ForEach(0..<list.count, id: \.self) { i in
				self.blockRow(list[i], base + [i])
			}
		})
	}

	func blockRow(_ n: LNode, _ path: [Int]) -> AnyView {
		let sp: LSpec = LSpec.of(n.op)
		let col: Color = Color(ui: sp.cat.color)
		return AnyView(VStack(alignment: .leading, spacing: 6) {
			rowHeader(sp, path)
			fields(n, path, sp)
			if sp.inside >= 1 { inner(n.body, path + [0], col, "(empty: choose IN, then add blocks)") }
			if sp.inside == 2 {
				Text("else").font(.pixel(12, .bold)).foregroundColor(Color.white)
				inner(n.alt, path + [1], col, "(empty: choose ELSE, then add blocks)")
			}
		}
		.padding(8)
		.background(col.opacity(0.92))
		.cornerRadius(8))
	}

	func rowHeader(_ sp: LSpec, _ path: [Int]) -> some View {
		let dark: Color = Color.black.opacity(0.35)
		let inTitle: String = isInto(path, 0) ? "IN \u{2713}" : "IN"
		let elseTitle: String = isInto(path, 1) ? "ELSE \u{2713}" : "ELSE"
		let hasIn: Bool = sp.inside >= 1
		let hasElse: Bool = sp.inside == 2
		return HStack(spacing: 6) {
			Text(verbatim: sp.title).font(.pixel(13, .bold)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			if hasIn { SmallButton(title: inTitle, color: dark) { self.into = path + [0] } }
			if hasElse { SmallButton(title: elseTitle, color: dark) { self.into = path + [1] } }
			SmallButton(title: "\u{2191}", color: dark) { self.moveBlock(path, -1) }
			SmallButton(title: "\u{2193}", color: dark) { self.moveBlock(path, 1) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.removeBlock(path) }
		}
	}

	func inner(_ list: [LNode], _ path: [Int], _ col: Color, _ empty: String) -> some View {
		let none: Bool = list.isEmpty
		return HStack(alignment: .top, spacing: 6) {
			Rectangle().fill(col).frame(width: 8)
			VStack(alignment: .leading, spacing: 4) {
				blockList(list, path)
				if none { Text(verbatim: empty).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8)) }
			}
		}
	}

	func moveBlock(_ path: [Int], _ d: Int) {
		mutate { LPath.move(&$0, path, d) }
	}

	func removeBlock(_ path: [Int]) {
		if let p = into, p.starts(with: path) { into = nil }
		mutate { LPath.remove(&$0, path) }
	}

	func isInto(_ path: [Int], _ part: Int) -> Bool { return into == path + [part] }

	func mutate(_ f: (inout [LNode]) -> Void) {
		var list: [LNode] = script.blocks
		f(&list)
		b(\.blocks, []).wrappedValue = list
	}

	func edit(_ path: [Int], _ f: (inout LNode) -> Void) {
		mutate { LPath.update(&$0, path, f) }
	}

	func setExpr(_ path: [Int], _ arg: Int, _ sub: [Int], _ f: (inout LExpr) -> Void) {
		edit(path) { n in
			while n.args.count <= arg { n.args.append(LExpr(0)) }
			LPath.exprUpdate(&n.args[arg], sub, f)
		}
	}

	// MARK: a block's inputs

	func fields(_ n: LNode, _ path: [Int], _ sp: LSpec) -> AnyView {
		return AnyView(VStack(alignment: .leading, spacing: 4) {
			ForEach(0..<sp.fields.count, id: \.self) { k in
				self.field(n, path, sp.fields[k])
			}
		})
	}

	func field(_ n: LNode, _ path: [Int], _ f: LField) -> AnyView {
		switch f.kind {
		case .number:
			return AnyView(LNumBox(label: f.label, value: numBind(path, f.slot), lo: f.lo, hi: f.hi))
		case .text:
			return AnyView(ModTextField(label: f.label, text: strBind(path), placeholder: ""))
		case .choice:
			let names: [String] = ScriptEditorView.choiceNames(f.list)
			return labelled(f.label, AnyView(ChoiceRow(options: names, selected: choiceBind(path, f.slot), columns: 4)))
		case .item:
			return itemField(n, path, f.label)
		case .key:
			return keyField(n, path, f)
		case .expr:
			let e: LExpr = f.slot < n.args.count ? n.args[f.slot] : LExpr(0)
			return AnyView(HStack(spacing: 6) {
				Text(verbatim: f.label).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.85))
				exprView(e, path, f.slot, [])
			})
		}
	}

	/// A small label above an input
	func labelled(_ label: String, _ content: AnyView) -> AnyView {
		return AnyView(VStack(alignment: .leading, spacing: 2) {
			Text(verbatim: label).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.85))
			content
		})
	}

	func choiceBind(_ path: [Int], _ slot: Int) -> Binding<Int> {
		return Binding<Int>(get: { Int(self.num(path, slot)) }, set: { (v: Int) in
			let d: Double = Double(v)
			self.edit(path) { n in
				if slot == 0 { n.a = d } else if slot == 1 { n.b = d } else { n.c = d }
			}
		})
	}

	func itemField(_ n: LNode, _ path: [Int], _ label: String) -> AnyView {
		let name: String = n.item.map { ModPreview.name($0, s.catalog) } ?? "none"
		let line: String = joinText(label, ": ", name)
		return AnyView(HStack(spacing: 8) {
			Text(verbatim: line).font(.pixel(11, .bold)).foregroundColor(Color.white)
			SmallButton(title: "CHOOSE", color: Color.black.opacity(0.35)) { self.itemPick = path }
		})
	}

	func num(_ path: [Int], _ slot: Int) -> Double {
		guard let n = LPath.get(script.blocks, path) else { return 0 }
		return slot == 0 ? n.a : (slot == 1 ? n.b : n.c)
	}

	func numBind(_ path: [Int], _ slot: Int) -> Binding<Double> {
		return Binding<Double>(get: { self.num(path, slot) }, set: { v in self.edit(path) { n in
			if slot == 0 { n.a = v } else if slot == 1 { n.b = v } else { n.c = v }
		} })
	}

	func strBind(_ path: [Int]) -> Binding<String> {
		return Binding<String>(get: { LPath.get(self.script.blocks, path)?.s ?? "" }, set: { v in self.edit(path) { $0.s = String(v.prefix(80)) } })
	}

	static func choiceNames(_ list: Int) -> [String] {
		switch list {
		case 0: return LReporters.soundNames
		case 1: return ModEffectKind.allCases.map { $0.name }
		default: return ModGameShots.names
		}
	}

	func keyField(_ n: LNode, _ path: [Int], _ f: LField) -> AnyView {
		switch f.list {
		case 1: return blockField(n, path, f.label)
		case 3: return AnyView(ModTextField(label: f.label, text: strBind(path), placeholder: "open the gate"))
		default: break
		}
		let opts: ([String], [String]) = keyOptions(f.list)
		if opts.0.isEmpty {
			let what: String = ScriptEditorView.missingWhat(f.list)
			let line: String = joinText(f.label, ": ", what)
			return AnyView(Text(verbatim: line).font(.pixel(10, .semibold)).foregroundColor(Color.white))
		}
		return labelled(f.label, AnyView(ChoiceRow(options: opts.0, selected: keyBind(path, opts.1), columns: 4)))
	}

	static func missingWhat(_ list: Int) -> String {
		if list == 4 { return "Add a variable in the Logic Studio list first." }
		if list == 5 { return "Make a group first (+ NEW GROUP)." }
		return "Make one in this mod first."
	}

	/// What a key input may be set to: (names, keys)
	func keyOptions(_ list: Int) -> ([String], [String]) {
		var names: [String] = []
		var keys: [String] = []
		switch list {
		case 0:
			for m in s.mod.mobs {
				names.append(m.name)
				keys.append(s.mod.key(m.id))
			}
			for k in ScriptEditorView.gameCreatures {
				names.append(mobDef(k).name)
				keys.append(mobDef(k).name)
			}
		case 2:
			names.append("Game shot")
			keys.append("")
			for p in s.mod.projectiles {
				names.append(p.name)
				keys.append(s.mod.key(p.id))
			}
		case 4:
			for v in s.mod.variables {
				names.append(v)
				keys.append(v)
			}
		case 5:
			for g in s.mod.scripts where g.event == .group && g.id != id {
				names.append(g.name)
				keys.append(s.mod.key(g.id))
			}
		default:
			for d in s.mod.dims {
				names.append(d.name)
				keys.append(s.mod.key(d.id))
			}
		}
		return (names, keys)
	}

	static let gameCreatures: [MobKind] = BossPhasesPage.gameHelpers + [MobKind.pig, .cow, .wolf]

	func keyBind(_ path: [Int], _ keys: [String]) -> Binding<Int> {
		return Binding<Int>(get: {
			let cur: String = LPath.get(self.script.blocks, path)?.s ?? ""
			return keys.firstIndex(of: cur) ?? -1
		}, set: { (v: Int) in
			let k: String = keys[clampI(v, 0, keys.count - 1)]
			self.edit(path) { $0.s = k }
		})
	}

	func blockField(_ n: LNode, _ path: [Int], _ label: String) -> AnyView {
		let name: String = n.s.isEmpty ? "none" : ModGround.name(n.s, s.mod)
		let line: String = joinText(label, ": ", name)
		return AnyView(HStack(spacing: 8) {
			Text(verbatim: line).font(.pixel(11, .bold)).foregroundColor(Color.white)
			SmallButton(title: "CHOOSE", color: Color.black.opacity(0.35)) { self.blockPick = path }
		})
	}

	// MARK: values

	/// A value as a chip: a number to type, or a reporter (tap its name to swap it for another) with
	/// its own inputs inside
	func exprView(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		if e.op == .num { return numberChip(e, path, arg, sub) }
		return AnyView(HStack(spacing: 4) {
			reporterButton(e.op, path, arg, sub)
			exprDetail(e, path, arg, sub)
			ForEach(0..<e.args.count, id: \.self) { k in self.exprView(e.args[k], path, arg, sub + [k]) }
		}
		.padding(4)
		.background(Color.black.opacity(0.2))
		.cornerRadius(10))
	}

	func numberChip(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		let vb: Binding<Double> = exprNum(e.v, path, arg, sub)
		return AnyView(HStack(spacing: 4) {
			LNumBox(label: "", value: vb, lo: -100000, hi: 100000, compact: true)
			SmallButton(title: "\u{25BE}", color: Color.black.opacity(0.35)) { self.exprPick = (path, arg, sub) }
		}
		.padding(4)
		.background(Color.white.opacity(0.25))
		.cornerRadius(10))
	}

	func reporterButton(_ op: LEOp, _ path: [Int], _ arg: Int, _ sub: [Int]) -> some View {
		Button(action: { self.exprPick = (path, arg, sub) }) {
			Text(verbatim: LReporters.name(op)).font(.pixel(11, .bold)).foregroundColor(Color.black)
				.padding(.horizontal, 8)
				.frame(minHeight: 34)
				.background(Color(ui: 0x9AE070))
				.cornerRadius(10)
		}
		.buttonStyle(.plain)
	}

	/// A value's number, read and set through its place in the script
	func exprNum(_ cur: Double, _ path: [Int], _ arg: Int, _ sub: [Int]) -> Binding<Double> {
		return Binding<Double>(get: { cur }, set: { (v: Double) in self.setExpr(path, arg, sub) { $0.v = v } })
	}

	/// A value's choice among keys, read and set through its place in the script
	func exprKey(_ cur: String, _ keys: [String], _ path: [Int], _ arg: Int, _ sub: [Int]) -> Binding<Int> {
		return Binding<Int>(get: { keys.firstIndex(of: cur) ?? -1 }, set: { (v: Int) in
			let k: String = keys[clampI(v, 0, keys.count - 1)]
			self.setExpr(path, arg, sub) { $0.s = k }
		})
	}

	/// The setting a reporter needs (which variable, input, item, distance, dimension or biome)
	func exprDetail(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		switch e.op {
		case .variable:
			let vars: [String] = s.mod.variables
			if vars.isEmpty { return AnyView(Text("(no variables)").font(.pixel(10)).foregroundColor(Color.white)) }
			let cols: Int = min(4, vars.count)
			return AnyView(ChoiceRow(options: vars, selected: exprKey(e.s, vars, path, arg, sub), columns: cols).frame(maxWidth: 360))
		case .param:
			return AnyView(LNumBox(label: "", value: exprNum(e.v, path, arg, sub), lo: 1, hi: 3, compact: true))
		case .nearby:
			return AnyView(HStack(spacing: 2) {
				LNumBox(label: "", value: exprNum(e.v, path, arg, sub), lo: 1, hi: 30, compact: true)
				Text("blocks").font(.pixel(10)).foregroundColor(Color.white)
			})
		case .itemCount:
			let name: String = e.item.map { ModPreview.name($0, s.catalog) } ?? "CHOOSE ITEM"
			return AnyView(SmallButton(title: name, color: Color.black.opacity(0.35)) { self.exprItemPick = (path, arg, sub) })
		case .inDim:
			let keys: [String] = ["overworld", "umbral"] + s.mod.dims.map { s.mod.key($0.id) }
			let names: [String] = ["Overworld", "Umbral Realm"] + s.mod.dims.map { $0.name }
			return AnyView(ChoiceRow(options: names, selected: exprKey(e.s, keys, path, arg, sub), columns: 3).frame(maxWidth: 360))
		case .inBiome:
			return biomeChoice(e, path, arg, sub)
		default:
			return AnyView(EmptyView())
		}
	}

	func biomeChoice(_ e: LExpr, _ path: [Int], _ arg: Int, _ sub: [Int]) -> AnyView {
		let all: [Biome] = ModBiomePicker.all
		let cur: Int = Int(e.v)
		let sel: Binding<Int> = Binding<Int>(get: { all.firstIndex { $0.rawValue == cur } ?? -1 }, set: { (v: Int) in
			let raw: Double = Double(all[clampI(v, 0, all.count - 1)].rawValue)
			self.setExpr(path, arg, sub) { $0.v = raw }
		})
		return AnyView(ChoiceRow(options: DimensionEditorView.biomeNames, selected: sel, columns: 5).frame(maxWidth: 420))
	}

	/// What the checks found in this script
	var issues: some View {
		let place: String = joinText("Script \u{201C}", script.name, "\u{201D}")
		let mine: [ModIssue] = s.report.issues.filter { $0.place == place }
		return VStack(alignment: .leading, spacing: 4) {
			if !mine.isEmpty {
				Text("CHECKS").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
				ForEach(mine) { i in
					Text(verbatim: joinText("\u{2022} ", i.text)).font(.pixel(11, .semibold)).foregroundColor(Color(ui: 0xFFB070))
				}
			}
		}
	}
}

/// A number with big minus and plus buttons (and typing)
struct LNumBox: View {
	let label: String
	@Binding var value: Double
	let lo: Double
	let hi: Double
	var compact: Bool = false

	var step: Double { return hi - lo <= 2.01 ? 0.05 : (hi - lo <= 20.01 ? 0.5 : 1) }

	var text: Binding<String> {
		return Binding<String>(get: {
			let v: Double = value
			return v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
		}, set: { t in
			if let v = Double(t.trimmingCharacters(in: .whitespaces)) { value = clampD(v, lo, hi) }
		})
	}

	var body: some View {
		HStack(spacing: 4) {
			if !label.isEmpty { Text(verbatim: label).font(.pixel(10, .bold)).foregroundColor(Color.white.opacity(0.85)) }
			SmallButton(title: "\u{2212}", color: Color.black.opacity(0.35)) { value = clampD(value - step, lo, hi) }
			TextField("0", text: text)
				.font(.pixel(13, .bold))
				.foregroundColor(Color.white)
				.frame(width: compact ? 64 : 80)
				.padding(4)
				.background(Color.black.opacity(0.35))
			SmallButton(title: "+", color: Color.black.opacity(0.35)) { value = clampD(value + step, lo, hi) }
		}
	}
}

/// Choosing a reporter for a value
struct ReporterPicker: View {
	@ObservedObject var s: ModSession
	var pick: (LExpr) -> Void
	var cancel: () -> Void

	static let groups: [(String, [LEOp])] = [
		("NUMBERS", [.num, .random, .variable, .param]),
		("MATHS", [.add, .sub, .mul, .div, .mod]),
		("TESTS", [.lt, .gt, .eq, .and, .or, .not]),
		("THE PLAYER", [.playerHP, .playerMaxHP, .playerX, .playerY, .itemCount, .distance]),
		("MY CREATURE OR BLOCK", [.selfHP, .selfHPPct, .selfX, .selfY, .nearby]),
		("THE WORLD", [.timeOfDay, .isNight, .raining, .inDim, .inBiome]),
	]

	var body: some View {
		ZStack {
			Color.black.opacity(0.7).ignoresSafeArea()
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("CHOOSE A VALUE").font(.pixel(18)).foregroundColor(ModUI.gold)
					Spacer()
					SmallButton(title: "CANCEL", color: ModUI.red) { self.cancel() }
				}
				ScrollView {
					VStack(alignment: .leading, spacing: 8) {
						ForEach(0..<ReporterPicker.groups.count, id: \.self) { g in self.group(g) }
					}
				}
			}
			.padding(14)
			.frame(maxWidth: 820, maxHeight: 640)
			.background(PixelBox(color: ModUI.panel))
			.padding(10)
		}
	}

	func group(_ g: Int) -> some View {
		let title: String = ReporterPicker.groups[g].0
		let ops: [LEOp] = ReporterPicker.groups[g].1
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 150), spacing: 6)]
		return VStack(alignment: .leading, spacing: 6) {
			Text(verbatim: title).font(.pixel(12, .bold)).foregroundColor(ModUI.dim)
			LazyVGrid(columns: cols, spacing: 6) {
				ForEach(0..<ops.count, id: \.self) { k in self.opButton(ops[k]) }
			}
		}
	}

	func opButton(_ op: LEOp) -> some View {
		Button(action: { self.pick(ReporterPicker.make(op)) }) {
			Text(verbatim: LReporters.name(op)).font(.pixel(11, .bold)).foregroundColor(Color.black)
				.frame(maxWidth: .infinity, minHeight: 44)
				.background(Color(ui: 0x9AE070))
				.cornerRadius(10)
		}
		.buttonStyle(.plain)
	}

	static func make(_ op: LEOp) -> LExpr {
		var e = LExpr(op: op)
		for _ in 0..<LReporters.arity(op) { e.args.append(LExpr(0)) }
		if op == .param { e.v = 1 }
		if op == .nearby { e.v = 6 }
		if op == .random {
			e.args = [LExpr(1), LExpr(10)]
		}
		if op == .inDim { e.s = "overworld" }
		if op == .inBiome { e.v = Double(Biome.plains.rawValue) }
		return e
	}
}

/// The Mod Test tools' LOGIC tab: what is running, the variables, the log, messages to send, and the
/// step debugger (pause every script, then run them one step at a time)
struct LogicDebugView: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var rev: Int = 0

	var body: some View {
		let rt: LogicRT = ModRuntime.shared.logic
		let none: Bool = rt.isEmpty
		return VStack(alignment: .leading, spacing: 8) {
			if none { Text("This world's mods have no scripts.").font(.pixel(12)).foregroundColor(ModUI.dim) }
			controls
			counts
			running
			variables
			messages
			logLines
		}
	}

	var controls: some View {
		let vm: LogicVM = game.logic
		let paused: Bool = vm.paused
		let runTitle: String = paused ? "RUN" : "PAUSE"
		let runCol: Color = paused ? ModUI.accent : Color(ui: 0x8A6A2A)
		return HStack(spacing: 8) {
			SmallButton(title: runTitle, color: runCol) { self.pause() }
			if paused { SmallButton(title: "STEP", color: ModUI.blue) { self.step() } }
			SmallButton(title: "WORLD START AGAIN", color: ModUI.blue) { self.restart() }
			SmallButton(title: "REFRESH", color: Color(ui: 0x555555)) { self.rev += 1 }
		}
	}

	func pause() {
		game.logicPauseToggle()
		rev += 1
	}

	func step() {
		game.logicStepOnce()
		rev += 1
	}

	func restart() {
		game.logic.started = false
		rev += 1
	}

	var counts: some View {
		let vm: LogicVM = game.logic
		let line: String = joinText("Started ", String(vm.ran), " times \u{00B7} problems ", String(vm.errors))
		let head: String = joinText("RUNNING (", String(vm.threads.count), ")")
		return VStack(alignment: .leading, spacing: 4) {
			Text(verbatim: line).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			Text(verbatim: head).font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
		}
	}

	var running: some View {
		let lines: [String] = game.logic.threads.map { LogicDebugView.threadLine($0) }
		return ForEach(0..<lines.count, id: \.self) { i in
			Text(verbatim: lines[i]).font(.pixel(11, .semibold)).foregroundColor(Color.white)
		}
	}

	static func threadLine(_ t: LThread) -> String {
		let wait: String = t.waitT > 0 ? String(format: " \u{00B7} waiting %.1f s", t.waitT) : ""
		let who: String = t.hasMob ? " \u{00B7} creature" : ""
		return joinText(t.whereText, wait, who)
	}

	var variables: some View {
		let keys: [String] = game.logicVars.keys.sorted()
		let lines: [String] = keys.map { k in joinText(k, " = ", String(format: "%.2f", self.game.logicVars[k] ?? 0)) }
		return VStack(alignment: .leading, spacing: 4) {
			if !lines.isEmpty {
				Text("VARIABLES").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
				ForEach(0..<lines.count, id: \.self) { i in
					Text(verbatim: lines[i]).font(.pixel(11, .semibold)).foregroundColor(Color.white)
				}
			}
		}
	}

	var messages: some View {
		let msgs: [String] = Array(Set(ModRuntime.shared.logic.listeners(.custom).map { $0.def.evText })).sorted()
		return VStack(alignment: .leading, spacing: 4) {
			if !msgs.isEmpty {
				Text("SEND A MESSAGE").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
				HStack(spacing: 6) {
					ForEach(msgs, id: \.self) { m in self.messageButton(m) }
				}
			}
		}
	}

	func messageButton(_ m: String) -> some View {
		let title: String = m.isEmpty ? "(unnamed)" : m
		return SmallButton(title: title, color: Color(ui: 0x8A6A2A)) {
			self.game.fireLogic(.custom, text: m)
			self.rev += 1
		}
	}

	var logLines: some View {
		let log: [String] = Array(game.logic.log.suffix(30).reversed())
		return VStack(alignment: .leading, spacing: 2) {
			Text("LOG (newest first)").font(.pixel(12, .bold)).foregroundColor(ModUI.gold)
			ForEach(0..<log.count, id: \.self) { i in
				Text(verbatim: log[i]).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.85))
			}
		}
	}
}

// MARK: - Mod Creator: rules, weather, vehicles and the look of the screens

/// The WORLD tab: the rules of the game, what a new world starts with, and the Overworld's weather
struct WorldRulesView: View {
	@ObservedObject var s: ModSession
	@State var picking: Bool = false

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Change how the game plays in the worlds this mod is in. Each rule stays the game's own until you change it; when two mods change the same rule, the one lower in the mod list wins.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			rulesSection
			startSection
			WeatherRulesEditor(s: s)
		}
		.modCover(s, picking ? 1 : nil) { self.itemPicker }
	}

	var rulesSection: some View {
		ModSection(title: "RULES OF THE GAME") {
			ForEach(GameRule.allCases, id: \.self) { (r: GameRule) in self.ruleRow(r) }
		}
	}

	func ruleRow(_ r: GameRule) -> some View {
		let sp: GameRule.Spec = r.spec
		let v: Double? = s.mod.rules[sp.id]
		let set: Bool = v != nil
		let shown: String = WorldRulesView.valueText(sp, v ?? sp.def)
		let label: String = set ? shown : joinText("game's: ", shown)
		return VStack(alignment: .leading, spacing: 3) {
			HStack(spacing: 8) {
				Text(verbatim: sp.name).font(.pixel(13, .bold)).foregroundColor(Color.white)
				Spacer(minLength: 0)
				Text(verbatim: label).font(.pixel(12)).foregroundColor(set ? ModUI.gold : ModUI.dim)
				SmallButton(title: set ? "GAME'S" : "CHANGE", color: set ? ModUI.red : ModUI.blue) { self.toggleRule(sp) }
			}
			Text(verbatim: sp.help).font(.pixel(10, .semibold)).foregroundColor(ModUI.dim)
			if set { ruleControl(sp) }
		}
		.padding(.vertical, 3)
	}

	@ViewBuilder
	func ruleControl(_ sp: GameRule.Spec) -> some View {
		if sp.unit == "on" {
			ModToggle(label: sp.name, isOn: onBind(sp))
		} else {
			Slider(value: ruleBind(sp), in: sp.lo...sp.hi, step: sp.step).frame(minHeight: 34)
		}
	}

	static func valueText(_ sp: GameRule.Spec, _ v: Double) -> String {
		switch sp.unit {
		case "on": return v >= 0.5 ? "ON" : "OFF"
		case "x": return String(format: "x%.1f", v)
		case "min": return String(format: "%.0f min", v)
		default: return String(format: "%.0f", v)
		}
	}

	func toggleRule(_ sp: GameRule.Spec) {
		if s.mod.rules[sp.id] != nil { s.mod.rules[sp.id] = nil } else { s.mod.rules[sp.id] = sp.def }
		s.touch()
	}

	func ruleBind(_ sp: GameRule.Spec) -> Binding<Double> {
		let ses: ModSession = s
		let id: String = sp.id
		let d: Double = sp.def
		return Binding<Double>(get: { ses.mod.rules[id] ?? d }, set: { (v: Double) in
			ses.mod.rules[id] = v
			ses.touch()
		})
	}

	func onBind(_ sp: GameRule.Spec) -> Binding<Bool> {
		let base: Binding<Double> = ruleBind(sp)
		return Binding<Bool>(get: { base.wrappedValue >= 0.5 }, set: { (on: Bool) in base.wrappedValue = on ? 1 : 0 })
	}

	var startSection: some View {
		let can: Bool = s.mod.startItems.count < ModWorldLimits.startItems
		return ModSection(title: "A NEW WORLD STARTS WITH", help: "Put in the bag of every new world (not in creative), beside the game's four torches.") {
			ForEach(0..<s.mod.startItems.count, id: \.self) { (i: Int) in self.startRow(i) }
			if can { SmallButton(title: "+ ADD AN ITEM", color: ModUI.accent) { self.picking = true } }
		}
	}

	func startRow(_ i: Int) -> some View {
		let c: ModCost = s.mod.startItems[i]
		let name: String = ModPreview.name(c.item, s.catalog)
		return HStack(spacing: 8) {
			ModPreview.icon(c.item, s.catalog).resizable().interpolation(.none).frame(width: 32, height: 32)
			Text(verbatim: name).font(.pixel(13)).foregroundColor(Color.white).lineLimit(1)
			Spacer(minLength: 0)
			SmallButton(title: "-", color: ModUI.blue) { self.addCount(i, c.n >= 20 ? -10 : -1) }
			Text(verbatim: String(c.n)).font(.pixel(14)).foregroundColor(ModUI.gold).frame(minWidth: 34)
			SmallButton(title: "+", color: ModUI.blue) { self.addCount(i, c.n >= 10 ? 10 : 1) }
			SmallButton(title: "\u{2715}", color: ModUI.red) { self.removeStart(i) }
		}
	}

	func addCount(_ i: Int, _ d: Int) {
		if i < 0 || i >= s.mod.startItems.count { return }
		s.mod.startItems[i].n = clampI(s.mod.startItems[i].n + d, 1, 999)
		s.touch()
	}

	func removeStart(_ i: Int) {
		if i < 0 || i >= s.mod.startItems.count { return }
		s.mod.startItems.remove(at: i)
		s.touch()
	}

	var itemPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "A NEW WORLD STARTS WITH...", pick: { (it: Item) in
			self.s.mod.startItems.append(ModCost(it, 1))
			self.s.touch()
			self.picking = false
		}, cancel: { self.picking = false })
	}
}

/// The Overworld's weather as the mod has it: how often each kind comes, how strong and how long
struct WeatherRulesEditor: View {
	@ObservedObject var s: ModSession

	var body: some View {
		let on: Bool = s.mod.weather != nil
		return ModSection(title: "THE OVERWORLD'S WEATHER", help: "How often each kind of weather comes (1: as the game, 0: never), how hard it rains and blows, and how long each spell lasts. The weather switches in Settings still apply.") {
			ModToggle(label: "Change the weather", help: on ? "This mod's weather is used" : "The game's weather", isOn: onBind)
			if on { controls }
		}
	}

	var controls: some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(WeatherKind.allCases, id: \.self) { (k: WeatherKind) in
				StatSlider(label: k.name, value: self.chanceBind(k), range: 0.0...5.0, step: 0.25, format: "x%.2f")
			}
			StatSlider(label: "Rain and snow", value: numBind(\ModWeather.rain), range: 0.0...3.0, step: 0.1, format: "x%.1f")
			StatSlider(label: "Wind", value: numBind(\ModWeather.wind), range: 0.0...3.0, step: 0.1, format: "x%.1f")
			StatSlider(label: "How long spells last", value: numBind(\ModWeather.length), range: 0.25...6.0, step: 0.25, format: "x%.2f")
			ModColorRow(label: "Colour of the rain", color: rainBind)
			SmallButton(title: "THE GAME'S RAIN COLOUR") { self.edit { (w: inout ModWeather) in w.rainColor = 0 } }
		}
	}

	func edit(_ f: (inout ModWeather) -> Void) {
		var w: ModWeather = s.mod.weather ?? ModWeather()
		f(&w)
		s.mod.weather = w
		s.touch()
	}

	var onBind: Binding<Bool> {
		let ses: ModSession = s
		return Binding<Bool>(get: { ses.mod.weather != nil }, set: { (on: Bool) in
			ses.mod.weather = on ? (ses.mod.weather ?? ModWeather()) : nil
			ses.touch()
		})
	}

	func chanceBind(_ k: WeatherKind) -> Binding<Double> {
		let ses: ModSession = s
		return Binding<Double>(get: { ses.mod.weather?.chanceOf(k) ?? 1 }, set: { (v: Double) in
			var w: ModWeather = ses.mod.weather ?? ModWeather()
			while w.chance.count < WeatherKind.allCases.count { w.chance.append(1) }
			w.chance[k.rawValue] = v
			ses.mod.weather = w
			ses.touch()
		})
	}

	func numBind(_ kp: WritableKeyPath<ModWeather, Double>) -> Binding<Double> {
		let ses: ModSession = s
		return Binding<Double>(get: { (ses.mod.weather ?? ModWeather())[keyPath: kp] }, set: { (v: Double) in
			var w: ModWeather = ses.mod.weather ?? ModWeather()
			w[keyPath: kp] = v
			ses.mod.weather = w
			ses.touch()
		})
	}

	var rainBind: Binding<UInt32> {
		let ses: ModSession = s
		return Binding<UInt32>(get: { ses.mod.weather?.rainColor ?? 0 }, set: { (v: UInt32) in
			var w: ModWeather = ses.mod.weather ?? ModWeather()
			w.rainColor = v
			ses.mod.weather = w
			ses.touch()
		})
	}
}

extension BlockEditorView {
	/// As building material, and on power lines
	var buildSection: some View {
		let p: ModBlock = block
		let auto: BlockPhys = blockPhysFrom(TileDef(name: p.name, hard: p.hardness, solid: p.collision == .solid))
		let weightNote: String = String(format: "0 = worked out from its hardness (%.1f, holds %.0f)", auto.weight, auto.carry)
		return VStack(spacing: 10) {
			ModSection(title: "AS BUILDING MATERIAL", help: weightNote) {
				StatSlider(label: "Weight (stone is 2.5)", value: b(\.weight, 0), range: 0.0...(s.mod.sandbox ? 40 : 12), step: 0.1, format: "%.1f")
				StatSlider(label: "Weight it holds up", value: b(\.carry, 0), range: 0.0...(s.mod.sandbox ? 4000 : 400), step: 5, format: "%.0f")
				ModToggle(label: "Falls like sand", help: "With nothing under it, it drops and lands", isOn: b(\.falls, false))
			}
			ModSection(title: "ON POWER LINES", help: p.powerRole.help) {
				ChoiceRows(options: ModPowerRole.allCases.map { $0.name }, selected: powerBind, columns: 3)
				if p.powerRole != .none && p.powerRole != .signal {
					StatSlider(label: "Strength (sparks a second)", value: b(\.powerAmt, 4), range: 0.1...(s.mod.sandbox ? 200 : 40), step: 0.1, format: "%.1f")
				}
			}
		}
	}

	var powerBind: Binding<Int> {
		let base: Binding<ModPowerRole> = b(\.powerRole, .none)
		return Binding<Int>(get: { base.wrappedValue.rawValue }, set: { base.wrappedValue = ModPowerRole(rawValue: $0) ?? .none })
	}
}

/// The VEHICLES tab: whole vehicles, each also an item (its kit) that builds it
struct VehicleListView: View {
	@ObservedObject var s: ModSession
	var open: (String) -> Void

	var body: some View {
		let can: Bool = s.mod.vehicles.count < ModWorldLimits.vehicles
		return VStack(alignment: .leading, spacing: 8) {
			Text("A vehicle kept in the mod is built from its kit: an item your recipes make. Use the kit on open ground (or water, for a boat) and the vehicle is there to drive. Paint it part by part here, or build it in a TEST world and keep it with SAVE VEHICLE on the TEST panel.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			if can { PixelButton(title: "+ NEW VEHICLE", color: ModUI.accent) { self.add() } }
			ForEach(s.mod.vehicles) { (v: ModVehicle) in self.row(v) }
		}
	}

	func row(_ v: ModVehicle) -> some View {
		let pic: Image = pixImage(ModRuntime.shared.vehicleIconBuf(v))
		let line: String = joinText(String(v.cells.count), " parts", v.water ? " · a boat" : "")
		return ModRow(image: pic, title: v.name, sub: line, open: { self.open(v.id) }, copy: { self.copy(v) },
					  delete: { self.s.mod.vehicles.removeAll { $0.id == v.id }; self.s.touch() },
					  off: s.mod.off.contains(v.id), toggle: { self.toggleOff(v.id) })
	}

	func add() {
		var v = ModVehicle()
		v.id = s.mod.freshID("veh")
		v.name = joinText("Vehicle ", String(s.mod.vehicles.count + 1))
		v.cells = [ModVehicleCell(1, 0, .seat), ModVehicleCell(2, 0, .steering), ModVehicleCell(0, 1, .fuelTank), ModVehicleCell(1, 1, .frame),
				   ModVehicleCell(2, 1, .frame), ModVehicleCell(3, 1, .engine), ModVehicleCell(0, 2, .wheel), ModVehicleCell(3, 2, .wheel)]
		s.mod.vehicles.append(v)
		s.touch()
		open(v.id)
	}

	func copy(_ v: ModVehicle) {
		if s.mod.vehicles.count >= ModWorldLimits.vehicles { return }
		var c: ModVehicle = v
		c.id = s.mod.freshID("veh")
		c.name = joinText(v.name, " copy")
		s.mod.vehicles.append(c)
		s.touch()
	}

	func toggleOff(_ id: String) {
		if s.mod.off.contains(id) { s.mod.off.removeAll { $0 == id } } else { s.mod.off.append(id) }
		s.touch()
	}
}

/// Editing one vehicle: its name, whether it is a boat, its fuel, and its parts painted on a grid
struct VehicleEditorView: View {
	@ObservedObject var s: ModSession
	let id: String
	@State var brush: Int = 0
	@State var block: String = ""
	@State var picking: Bool = false

	func b<T>(_ kp: WritableKeyPath<ModVehicle, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.vehicles, id, kp, d) }
	var veh: ModVehicle { return s.mod.vehicles.first { $0.id == id } ?? ModVehicle() }

	/// what the brush can paint: every part but a plain block, then a block, then nothing
	static let parts: [PartType] = PartType.allCases.filter { $0 != .block }
	static var brushNames: [String] { return parts.map { $0.name.uppercased() } + ["BLOCK", "ERASE"] }

	var body: some View {
		let v: ModVehicle = veh
		return VStack(spacing: 10) {
			ModSection(title: v.name.uppercased(), help: "Its kit is an item: give it a recipe on the RECIPES tab.") {
				ModTextField(label: "Name", text: b(\.name, ""), placeholder: "Sky Hauler")
				ModTextField(label: "Description", text: b(\.desc, ""), placeholder: "Optional")
				ModToggle(label: "A boat", help: "Put down on water instead of on the ground", isOn: b(\.water, false))
				StatSlider(label: "Fuel it comes with", value: b(\.fuel, 40), range: 0.0...400.0, step: 5, format: "%.0f")
			}
			ModSection(title: "PARTS", help: brushHelp) {
				ChoiceRows(options: VehicleEditorView.brushNames, selected: $brush, columns: 5)
				if brush == VehicleEditorView.parts.count { blockChoice }
				grid(v)
				Text(verbatim: joinText(String(v.cells.count), " of ", String(ModVehicle.maxCells), " cells")).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				SmallButton(title: "CLEAR", color: ModUI.red) { self.b(\.cells, []).wrappedValue = [] }
			}
			ModSection(title: "ICON", help: "Blank: drawn from its parts.") {
				PixelEditorView(pixels: b(\.icon, ModPixels(w: 12, h: 12)), maxSide: 220, outlineDefault: true)
			}
		}
		.modCover(s, picking ? 1 : nil) { self.blockPicker }
	}

	var brushHelp: String {
		if brush < VehicleEditorView.parts.count { return joinText("Tap or drag to place: ", VehicleEditorView.parts[brush].name, ". Wheels go at the bottom, a seat or cockpit is where the driver sits.") }
		if brush == VehicleEditorView.parts.count { return "Tap or drag to place the chosen block (a mod block that works as a vehicle part works as one)." }
		return "Tap or drag to take parts away."
	}

	var blockChoice: some View {
		let label: String = block.isEmpty ? "No block chosen" : blockName(block)
		return HStack(spacing: 8) {
			Text(verbatim: label).font(.pixel(12)).foregroundColor(Color.white)
			Spacer(minLength: 0)
			SmallButton(title: "CHOOSE A BLOCK...", color: ModUI.blue) { self.picking = true }
		}
	}

	func blockName(_ k: String) -> String {
		if k.hasPrefix("tile:"), let n = Int(k.dropFirst(5)), let t = Tile(rawValue: UInt8(clampI(n, 0, 255))) { return t.name }
		return s.catalog.names[k] ?? k
	}

	var blockPicker: some View {
		ItemPickerView(catalog: s.catalog, title: "BUILD WITH...", blocksOnly: true, pick: { (it: Item) in
			switch it {
			case .block(let t): self.block = joinText("tile:", String(t.rawValue))
			case .custom(let k): self.block = k
			default: break
			}
			self.picking = false
		}, cancel: { self.picking = false })
	}

	func grid(_ v: ModVehicle) -> some View {
		let n: Int = ModVehicle.maxSize
		let cell: CGFloat = 13
		let side: CGFloat = cell * CGFloat(n)
		var colours: [Int: UInt32] = [:]
		for c in v.cells { colours[c.y * n + c.x] = ModRuntime.shared.vehicleCellColor(c) }
		return Canvas { ctx, size in
			for y in 0..<n {
				for x in 0..<n {
					let r: CGRect = CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell - 1, height: cell - 1)
					let col: UInt32 = colours[y * n + x] ?? 0x1A2030
					ctx.fill(Path(r), with: .color(Color(hex: col)))
				}
			}
		}
		.frame(width: side, height: side)
		.gesture(DragGesture(minimumDistance: 0).onChanged { (g: DragGesture.Value) in self.paint(g.location, cell) })
	}

	func paint(_ p: CGPoint, _ cell: CGFloat) {
		let x: Int = Int(floor(p.x / cell))
		let y: Int = Int(floor(p.y / cell))
		let n: Int = ModVehicle.maxSize
		if x < 0 || y < 0 || x >= n || y >= n { return }
		var cells: [ModVehicleCell] = veh.cells
		let had: Int? = cells.firstIndex { $0.x == x && $0.y == y }
		let partCount: Int = VehicleEditorView.parts.count
		if brush > partCount {
			guard let i = had else { return }
			cells.remove(at: i)
		} else {
			var c = ModVehicleCell(x, y, .frame)
			if brush < partCount {
				c.part = VehicleEditorView.parts[brush].rawValue
			} else {
				if block.isEmpty { return }
				c.block = block
			}
			if let i = had {
				if cells[i] == c { return }
				cells[i] = c
			} else {
				if cells.count >= ModVehicle.maxCells { return }
				cells.append(c)
			}
		}
		b(\.cells, []).wrappedValue = cells
	}
}

extension ModTestPanel {
	/// In a TEST world: keeps the vehicle the player drives (or stands by) in the mod as a design
	func saveVehicle() -> String {
		let mid: String = game.testMod
		guard !mid.isEmpty, var p = ModStore.pack(mid) else { return "Only in a TEST world." }
		guard let v = game.inVehicle ?? game.nearestVehicle(3) else { return "Stand by a vehicle (or drive one) first." }
		if p.vehicles.count >= ModWorldLimits.vehicles { return joinText(p.name, " already holds the most vehicles a mod can.") }
		var mv: ModVehicle = game.vehicleDesign(v)
		mv.id = p.freshID("veh")
		mv.name = joinText("Vehicle ", String(p.vehicles.count + 1))
		p.vehicles.append(mv)
		return ModStore.save(p) ? joinText("Saved as \u{201C}", mv.name, "\u{201D} in ", p.name, ": give its kit a recipe in the Mod Creator.") : "The mod could not be saved."
	}
}

/// The LOOK tab: how the game's screens look while this mod is on (the theme of the last mod in the
/// list that has one is used, on the title screen too)
struct ThemeEditorView: View {
	@ObservedObject var s: ModSession

	var body: some View {
		let on: Bool = s.mod.theme != nil
		return VStack(alignment: .leading, spacing: 10) {
			Text("Change the colours of the game's screens and buttons, the letters, how round the buttons are, the title screen, and the size and sides of the touch controls. It shows once the mod is switched on, from the title screen.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			ModToggle(label: "Change how the game looks", help: on ? "This mod's look" : "The game's own look", isOn: onBind)
			if on { sections }
		}
	}

	var sections: some View {
		let t: ModTheme = s.mod.theme ?? ModTheme()
		return VStack(alignment: .leading, spacing: 10) {
			ThemePreview(theme: t)
			ModSection(title: "COLOURS", help: "Each takes the place of the game's colour for that part of every screen (other shades follow it).") {
				ForEach(ThemeRole.allCases, id: \.self) { (r: ThemeRole) in self.roleRow(r) }
				StatSlider(label: "How much everything else leans to the tint", value: numBind(\ModTheme.tintAmt), range: 0.0...1.0, step: 0.05, format: "%.2f")
			}
			ModSection(title: "LETTERS AND BUTTONS") {
				ChoiceRows(options: ModTheme.fonts, selected: intBind(\ModTheme.font), columns: 4)
				StatSlider(label: "Rounded corners", value: numBind(\ModTheme.corner), range: 0.0...16.0, step: 1, format: "%.0f")
				ModColorRow(label: "Outline", color: colorBind(\ModTheme.outline))
			}
			ModSection(title: "TITLE SCREEN", help: "Blank: the game's own title and the sky behind it.") {
				ModTextField(label: "Title", text: textBind(\ModTheme.title), placeholder: "PIXEL REALM")
				ModTextField(label: "Words under it", text: textBind(\ModTheme.subtitle), placeholder: "A new splash line each time")
				PixelEditorView(pixels: backBind, maxSide: 300, outlineDefault: false)
				HStack(spacing: 8) {
					SmallButton(title: "PAINT A BACKGROUND", color: ModUI.blue) { self.backBind.wrappedValue = ModPixels(w: 48, h: 27) }
					SmallButton(title: "NO PICTURE", color: ModUI.red) { self.backBind.wrappedValue = ModPixels(w: 1, h: 1) }
				}
			}
			ModSection(title: "TOUCH CONTROLS") {
				StatSlider(label: "Size", value: numBind(\ModTheme.hudScale), range: 0.6...1.5, step: 0.05, format: "x%.2f")
				StatSlider(label: "How solid", value: numBind(\ModTheme.hudAlpha), range: 0.3...1.0, step: 0.05, format: "%.2f")
				ModToggle(label: "Swap sides", help: "Attack stick and JUMP on the left, the walking stick on the right", isOn: boolBind(\ModTheme.swapSides))
			}
		}
	}

	func roleRow(_ r: ThemeRole) -> some View {
		let c: UInt32 = (s.mod.theme ?? ModTheme()).color(r)
		return VStack(alignment: .leading, spacing: 4) {
			ModColorRow(label: c == 0 ? joinText(r.name, " (the game's)") : r.name, color: roleBind(r))
			if c != 0 { SmallButton(title: "THE GAME'S", color: ModUI.red) { self.edit { (t: inout ModTheme) in t.colors[r.rawValue] = 0 } } }
		}
	}

	func edit(_ f: (inout ModTheme) -> Void) {
		var t: ModTheme = s.mod.theme ?? ModTheme()
		while t.colors.count < ThemeRole.allCases.count { t.colors.append(0) }
		f(&t)
		s.mod.theme = t
		s.touch()
	}

	var onBind: Binding<Bool> {
		let ses: ModSession = s
		return Binding<Bool>(get: { ses.mod.theme != nil }, set: { (on: Bool) in
			ses.mod.theme = on ? (ses.mod.theme ?? ModTheme()) : nil
			ses.touch()
		})
	}

	func roleBind(_ r: ThemeRole) -> Binding<UInt32> {
		let ses: ModSession = s
		return Binding<UInt32>(get: { (ses.mod.theme ?? ModTheme()).color(r) }, set: { (v: UInt32) in
			var t: ModTheme = ses.mod.theme ?? ModTheme()
			while t.colors.count < ThemeRole.allCases.count { t.colors.append(0) }
			t.colors[r.rawValue] = v
			ses.mod.theme = t
			ses.touch()
		})
	}

	func field<T>(_ kp: WritableKeyPath<ModTheme, T>) -> Binding<T> {
		let ses: ModSession = s
		return Binding<T>(get: { (ses.mod.theme ?? ModTheme())[keyPath: kp] }, set: { (v: T) in
			var t: ModTheme = ses.mod.theme ?? ModTheme()
			t[keyPath: kp] = v
			ses.mod.theme = t
			ses.touch()
		})
	}

	func numBind(_ kp: WritableKeyPath<ModTheme, Double>) -> Binding<Double> { return field(kp) }
	func intBind(_ kp: WritableKeyPath<ModTheme, Int>) -> Binding<Int> { return field(kp) }
	func textBind(_ kp: WritableKeyPath<ModTheme, String>) -> Binding<String> { return field(kp) }
	func boolBind(_ kp: WritableKeyPath<ModTheme, Bool>) -> Binding<Bool> { return field(kp) }
	func colorBind(_ kp: WritableKeyPath<ModTheme, UInt32>) -> Binding<UInt32> { return field(kp) }
	var backBind: Binding<ModPixels> { return field(\ModTheme.background) }
}

/// A few buttons and a title in a theme's colours (drawn from the theme itself, before it is switched on)
struct ThemePreview: View {
	let theme: ModTheme

	func col(_ r: ThemeRole) -> Color {
		let c: UInt32 = theme.color(r)
		return Color(hex: c != 0 ? c : r.gameColor)
	}

	var body: some View {
		let design: Font.Design = [Font.Design.monospaced, .rounded, .serif, .default][clampI(theme.font, 0, 3)]
		let r: CGFloat = CGFloat(theme.corner)
		let title: String = theme.title.isEmpty ? "PIXEL REALM" : theme.title
		return VStack(spacing: 8) {
			Text(verbatim: title).font(.system(size: 22, weight: .black, design: design)).foregroundColor(col(.titles))
			HStack(spacing: 6) {
				sample("PLAY", col(.accept), r, design)
				sample("BAG", col(.buttons), r, design)
				sample("INFO", col(.info), r, design)
				sample("QUIT", col(.danger), r, design)
			}
		}
		.padding(10)
		.frame(maxWidth: .infinity)
		.background(RoundedRectangle(cornerRadius: r).fill(col(.panels)))
	}

	func sample(_ t: String, _ c: Color, _ r: CGFloat, _ d: Font.Design) -> some View {
		return Text(verbatim: t)
			.font(.system(size: 13, weight: .heavy, design: d))
			.foregroundColor(Color.white)
			.padding(.horizontal, 10)
			.padding(.vertical, 8)
			.background(RoundedRectangle(cornerRadius: r).fill(c))
			.overlay(RoundedRectangle(cornerRadius: r).stroke(Color(hex: theme.outline), lineWidth: 2))
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
			if !game.showInventory && !game.showMap && !game.showJournal && !game.showWeather && !game.showPower && !game.showCapture && !game.showModTest && !game.showInfuse && !game.showExo && !game.dead {
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
