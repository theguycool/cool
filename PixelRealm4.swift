// PIXEL REALM v2, part 4 of 4: the Mod Creator screens, the potion and exosuit screens, the Mod Creator+ screens, and the app itself.
// The game is four files that go together in one Swift Playgrounds app: PixelRealm1.swift to
// PixelRealm4.swift. Each goes in its own file in the app (delete ContentView.swift; MyApp.swift can
// hold part 1). All art is generated in code.

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

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
	static let panel: Color = Color(hex: 0x2C2C30)
	static let card: Color = Color(hex: 0x3A3A40)
	static let accent: Color = Color(hex: 0x4E8A3E)
	static let blue: Color = Color(hex: 0x3E6FAA)
	static let red: Color = Color(hex: 0xA03030)
	static let gold: Color = Color(hex: 0xFFE066)
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
		let col: Color = on ? ModUI.accent : Color(hex: 0x555555)
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
		let col: Color = on ? ModUI.accent : Color(hex: 0x555555)
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
					.background(PixelBox(color: isOn ? ModUI.accent : Color(hex: 0x555555)))
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
				Text("MODS MISSING").font(.pixel(22)).foregroundColor(Color(hex: 0xFF9060))
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
					PixelButton(title: "LOAD ANYWAY", color: Color(hex: 0x8A5A2E)) { load() }
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
			Color(hex: 0x1C1C22).ignoresSafeArea()
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
				Text(verbatim: "Damaged mod: " + entry.id).font(.pixel(14)).foregroundColor(Color(hex: 0xFF8060))
				Text(verbatim: entry.error).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
				SmallButton(title: "DELETE", color: ModUI.red) { actions.delete() }
			}
		}
		.padding(12)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(PixelBox(color: entry.enabled ? Color(hex: 0x34503A) : ModUI.card))
	}

	func header(_ p: ModPack) -> some View {
		HStack(alignment: .top, spacing: 10) {
			Button { actions.toggle() } label: {
				Text(verbatim: entry.enabled ? "ON" : "OFF")
					.font(.pixel(13))
					.foregroundColor(Color.white)
					.frame(width: 58, height: 44)
					.background(PixelBox(color: entry.enabled ? ModUI.accent : Color(hex: 0x555555)))
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
					Text(verbatim: e.error).font(.pixel(13)).foregroundColor(Color(hex: 0xFF8060))
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
						.foregroundColor(Color(hex: i.level >= 2 ? 0xFF6060 : (i.level == 1 ? 0xFFC040 : 0x90C0FF)))
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
	case info, blocks, items, mobs, shots, recipes, loot, ores, structures, infusions, dims, logic, game, reference, check
	var name: String {
		switch self {
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
				.background(PixelBox(color: on ? ModUI.accent : Color(hex: 0x4A4A50)))
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
			if let t = toggle { SmallButton(title: off ? "OFF" : "ON", color: off ? Color(hex: 0x555555) : ModUI.accent) { t() } }
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

	var body: some View {
		ZStack {
			VStack(spacing: 10) {
				ModSection(title: "PICTURE", help: "8 x 8 pixels. Paint with your finger, or start from a game block.") {
					PixelEditorView(pixels: b(\.art, ModPixels(w: 8, h: 8)), maxSide: 280, outlineDefault: false)
					SmallButton(title: "START FROM A GAME BLOCK...") { copyFrom = true }
				}
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
				ModSection(title: "BODY") {
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
			b(\.art, ModPixels(w: 8, h: 8)).wrappedValue = ModPixels(buf: pic).resized(8, 8)
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
		let now: Color = Color(hex: color & 0xFFFFFF)
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
				.background(Color(hex: 0x5A7A9A).opacity(0.6))
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
					SmallButton(title: ["STAND", "WALK 1", "WALK 2", "ATTACK"][min(i, 3)], color: frame == i ? ModUI.accent : Color(hex: 0x555555)) { frame = i }
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
				.background(PixelBox(color: on ? ModUI.accent : Color(hex: 0x555555)))
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
				Text("Make a block whose 'When tapped' is Crafting station first.").font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xFF9060))
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
					Text(verbatim: ModLootEntry.rarityNames[clampI(e.rarity, 0, 3)] + String(format: " · %.1f%% per roll", pct)).font(.pixel(11)).foregroundColor(Color(hex: col))
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
					Text("Make the ore's block in the BLOCKS tab first.").font(.pixel(12)).foregroundColor(Color(hex: 0xFF9060))
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
				Text("CAPTURE").font(.pixel(14)).foregroundColor(Color(hex: 0x60E0FF))
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
				if !note.isEmpty { Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(hex: 0xFFB060)) }
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
				Text("MOD TEST").font(.pixel(20)).foregroundColor(Color(hex: 0x60E0FF))
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
				Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(hex: 0xFFE070))
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
					RecipeRow(game: game, recipe: r)
					VStack(spacing: 4) {
						SmallButton(title: "INGREDIENTS", color: ModUI.blue) { note = game.testIngredients(r) }
						SmallButton(title: "CRAFT", color: game.canCraft(r) ? ModUI.accent : Color(hex: 0x555555)) {
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
						SmallButton(title: game.world.dim == d.dim ? joinText("LEAVE ", d.def.name.uppercased()) : joinText("VISIT ", d.def.name.uppercased()), color: Color(hex: 0x6A4AAA)) {
							note = game.testVisitDim(i)
						}
					}
				}
			}
			ModToggle(label: "God mode", help: "Nothing can hurt you", isOn: god)
			ModToggle(label: "Survival rules", help: "Hunger, damage, stations and using things up, as in a real game", isOn: surv)
			ModToggle(label: "Creatures spawn by themselves", help: "Off: only what you spawn here appears", isOn: spawns)
			HStack(spacing: 8) {
				PixelButton(title: "CLEAR CREATURES", color: ModUI.red) {
					game.clearCreatures()
					note = "Every creature is gone."
				}
				PixelButton(title: "RESET WORLD", color: Color(hex: 0x8A5A2E)) { reset() }
			}
			PixelButton(title: "EXIT TEST", color: Color(hex: 0x6A3A8A)) { exit() }
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

// ===== u08_alchemy =====

// MARK: - HUD: effects and suit energy

/// The potion effects on the player: a small flask in the effect's colour and the seconds left
struct EffectStrip: View {
	let game: Game
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
			OutlinedText(text: label, size: 10, color: secs < 6 ? Color(hex: 0xFFB060) : Color.white)
		}
		.padding(.horizontal, 3)
		.padding(.vertical, 2)
		.background(Color.black.opacity(0.35))
	}
}

/// The worn suit's energy, and the PACK button when it carries a cargo pack
struct SuitBar: View {
	let game: Game
	var body: some View {
		let st: ExoStats = game.suitStats
		let cap: Double = max(1, st.capacity)
		let f: Double = clampD(game.suit.energy / cap, 0, 1)
		let col: Color = f > 0.25 ? Color(hex: 0x60E0FF) : Color(hex: 0xFF8A40)
		return HStack(spacing: 6) {
			OutlinedText(text: "SUIT", size: 10, color: Color(hex: 0x9AD8F0))
			ZStack(alignment: .leading) {
				Rectangle().fill(Color.black.opacity(0.6)).frame(width: 110, height: 9)
				Rectangle().fill(col).frame(width: CGFloat(110.0 * f), height: 9)
			}
			.overlay(Rectangle().stroke(Color.white.opacity(0.4), lineWidth: 1))
			OutlinedText(text: joinText(String(Int(game.suit.energy)), "/", String(Int(cap))), size: 10)
			if st.has(.cargo) {
				SmallButton(title: "PACK", color: Color(hex: 0x7A5A2A)) { game.openPack() }
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
				Text("INFUSION CRUCIBLE").font(.pixel(20)).foregroundColor(Color(hex: 0xC07CFF))
				Spacer()
				SmallButton(title: "MAKE COMPOUNDS", color: Color(hex: 0x5A4A8A)) { game.openCrafting(.infuser) }
				SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) { close() }
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
				Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(hex: 0xFFE070))
			}
		}
		.foregroundColor(Color.white)
		.padding(14)
		.background(PixelBox(color: Color(hex: 0x2C2834)).opacity(0.97))
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
			Text("EQUIPMENT").font(.pixel(13)).foregroundColor(Color(hex: 0xB8A8D8))
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
					SmallButton(title: "REMOVE", color: Color(hex: 0x5A4A4A)) { note = game.removeCustomInfusion(slot: pick, n) }
				}
			}
			ForEach(0..<have.count, id: \.self) { k in
				HStack(spacing: 6) {
					Rectangle().fill(Color(hex: have[k].color)).frame(width: 10, height: 10)
					Text(verbatim: have[k].name).font(.pixel(11)).foregroundColor(Color(hex: have[k].rarity.color))
					Spacer(minLength: 0)
					SmallButton(title: removing == have[k].rawValue ? "SURE?" : "REMOVE", color: Color(hex: removing == have[k].rawValue ? 0xC04030 : 0x5A4A4A)) {
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
			Text("INFUSIONS").font(.pixel(13)).foregroundColor(Color(hex: 0xB8A8D8))
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
						Text(verbatim: inf.name).font(.pixel(12)).foregroundColor(Color(hex: inf.rarity.color))
						Text(verbatim: inf.rarity.name).font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.5))
					}
					Text(verbatim: inf.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(usable ? 0.85 : 0.5)).lineLimit(2)
				}
				Spacer(minLength: 0)
				Text(verbatim: owned > 0 ? joinText("x", String(owned)) : "none").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
			}
			.padding(4)
			.background(chosen ? Color(hex: 0x4A3A6A) : Color.black.opacity(0.2))
		}
		.buttonStyle(.plain)
	}

	var previewColumn: some View {
		let inf: Infusion? = Infusion(rawValue: choice)
		return VStack(alignment: .leading, spacing: 6) {
			Text("WHAT CHANGES").font(.pixel(13)).foregroundColor(Color(hex: 0xB8A8D8))
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
					Text(verbatim: rows[k].2).font(.pixel(11)).foregroundColor(rows[k].1 == rows[k].2 ? Color.white : Color(hex: 0x7AF08A))
				}
			}
			if let p = problem {
				Text(verbatim: p).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xFF9A7A))
			} else if owned == 0 && !game.isCreative {
				Text(verbatim: joinText("You have no ", i.name, " compound: make one with MAKE COMPOUNDS.")).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xFF9A7A))
			}
			PixelButton(title: ok ? "CONFIRM INFUSION" : "CAN'T INFUSE", color: ok ? Color(hex: 0x6A4AA8) : Color(hex: 0x444444)) {
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

// MARK: - Assembly Station: the visual suit builder

/// Where each place on the suit and the parts tray sit on screen, so a drag can find its target
final class ExoFrames: @unchecked Sendable {
	var slots: [Int: CGRect] = [:]
	var tray: CGRect = .zero

	func slot(at p: CGPoint) -> ExoSlot? {
		for (k, r) in slots where r.contains(p) { return ExoSlot(rawValue: k) }
		return nil
	}
}

/// A part that can be fitted: one from the bag, or one taken off the suit in this plan (it goes back
/// to the bag when the plan is applied, unless it is fitted again)
struct TrayPart: Identifiable {
	var id: Int
	var stack: Stack
	var fromSuit: Bool
}

/// The Assembly Station: the suit drawn large with its places marked on it. Drag parts from the tray
/// onto the suit (or tap a part, then a place), drag them off again, swap metals, add plates and
/// modules, and watch the numbers change before anything is fitted. APPLY fits it all at once.
struct ExoAssemblyPanel: View {
	@ObservedObject var game: Game
	@ObservedObject var hud: HUDSignal
	@State var plan: ExoSuit = ExoSuit()
	@State var started: Bool = false
	@State var view: Int = 0
	@State var sel: Int = -1
	@State var trayPick: Int = -1
	@State var dragging: TrayPart? = nil
	@State var dragSlot: Int = -1
	@State var dragPoint: CGPoint = .zero
	@State var hover: Int = -1
	@State var note: String = ""
	@State var frames: ExoFrames = ExoFrames()

	var body: some View {
		ZStack(alignment: .topLeading) {
			VStack(spacing: 8) {
				header
				HStack(alignment: .top, spacing: 10) {
					builder
					VStack(spacing: 8) {
						statsBox
						detailBox
					}
					.frame(width: 270)
					trayColumn.frame(width: 250)
				}
				if !note.isEmpty {
					Text(verbatim: note).font(.pixel(12, .semibold)).foregroundColor(Color(hex: 0xFFE070))
				}
			}
			.foregroundColor(Color.white)
			.padding(12)
			.background(PixelBox(color: Color(hex: 0x262A32)).opacity(0.97))
			if let d = dragging {
				SlotView(stack: d.stack, size: 46)
					.opacity(0.9)
					.position(x: dragPoint.x, y: dragPoint.y)
					.allowsHitTesting(false)
			} else if dragSlot >= 0, let s = plan[ExoSlot(rawValue: dragSlot) ?? .helmet] {
				SlotView(stack: s, size: 46)
					.opacity(0.9)
					.position(x: dragPoint.x, y: dragPoint.y)
					.allowsHitTesting(false)
			}
		}
		.coordinateSpace(name: "exo")
		.frame(maxWidth: 1000)
		.padding(8)
		.onAppear {
			if started { return }
			started = true
			plan = game.suit
		}
	}

	var changed: Bool { return plan.parts != game.suit.parts }

	var header: some View {
		HStack(spacing: 8) {
			Text("ASSEMBLY STATION").font(.pixel(20)).foregroundColor(Color(hex: 0x60E0FF))
			Spacer()
			ForEach(0..<3, id: \.self) { v in
				SmallButton(title: ["FRONT", "BACK", "SIDE"][v], color: view == v ? Color(hex: 0x2E6A8A) : Color(hex: 0x3A3E48)) { view = v }
			}
			SmallButton(title: "MAKE PARTS", color: Color(hex: 0x4A5A3A)) { game.openCrafting(.assembly) }
			SmallButton(title: "CLOSE", color: Color(hex: 0xA03030)) { close() }
		}
	}

	func close() {
		if changed { note = "" }
		game.showExo = false
		game.bumpHUD()
	}

	// MARK: the suit and its places

	var builder: some View {
		HStack(alignment: .top, spacing: 6) {
			VStack(spacing: 5) {
				Text("PLATES").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
				ForEach([ExoSlot.plateHead, .plateShoulders, .plateChest, .plateArms, .plateLegs], id: \.self) { s in socket(s) }
			}
			figure
			VStack(spacing: 5) {
				Text("CORE").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
				socket(.core)
				Text("MODULES").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
				ForEach([ExoSlot.mod1, .mod2, .mod3, .mod4], id: \.self) { s in socket(s) }
			}
		}
	}

	/// The suit picture with its frame places laid over it (front and back), or the suit as worn (side)
	var figure: some View {
		let img: Image = SuitArt.shared.image(plan, view)
		let w: CGFloat = 240
		let h: CGFloat = 336
		return ZStack(alignment: .topLeading) {
			Rectangle().fill(Color.black.opacity(0.35)).frame(width: w, height: h)
			if view == 2 {
				img.resizable().interpolation(.none).frame(width: w * 22.0 / 22.0, height: w * 17.0 / 22.0)
					.offset(x: 0, y: (h - w * 17.0 / 22.0) * 0.5)
				VStack {
					Spacer()
					Text("As it looks when worn").font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.6))
				}
				.frame(width: w, height: h - 8)
				ForEach([ExoSlot.helmet, .chest, .armL, .armR, .legs, .boots], id: \.self) { s in hiddenTarget(s) }
			} else {
				img.resizable().interpolation(.none).frame(width: w, height: h)
				ForEach([ExoSlot.helmet, .chest, .armL, .armR, .legs, .boots], id: \.self) { s in partTarget(s, w / 40.0) }
			}
		}
		.frame(width: w, height: h)
	}

	/// where each frame part sits on the 40 x 56 picture (front; the back swaps the arms)
	func partRect(_ s: ExoSlot) -> (Double, Double, Double, Double) {
		let back: Bool = view == 1
		switch s {
		case .helmet: return (13, 1, 14, 12)
		case .chest: return (10, 13, 20, 18)
		case .armR: return back ? (29, 15, 7, 23) : (4, 15, 7, 23)
		case .armL: return back ? (4, 15, 7, 23) : (29, 15, 7, 23)
		case .legs: return (12, 32, 16, 16)
		case .boots: return (11, 48, 18, 8)
		default: return (0, 0, 0, 0)
		}
	}

	func partTarget(_ s: ExoSlot, _ k: CGFloat) -> some View {
		let r: (Double, Double, Double, Double) = partRect(s)
		let x: CGFloat = CGFloat(r.0) * k
		let y: CGFloat = CGFloat(r.1) * k
		let w: CGFloat = CGFloat(r.2) * k
		let h: CGFloat = CGFloat(r.3) * k
		return target(s, w, h, showIcon: false)
			.offset(x: x, y: y)
	}

	/// in the side view the frame places are still there, stacked at the edge, so drops still work
	func hiddenTarget(_ s: ExoSlot) -> some View {
		let i: Int = [ExoSlot.helmet, .chest, .armL, .armR, .legs, .boots].firstIndex(of: s) ?? 0
		return target(s, 74, 44, showIcon: true)
			.offset(x: i % 2 == 0 ? 4 : 162, y: CGFloat(8 + (i / 2) * 50))
	}

	/// a module, plate or core place beside the picture
	func socket(_ s: ExoSlot) -> some View {
		return target(s, 64, 50, showIcon: true)
	}

	/// One place on the suit: shows what is fitted (or that it is empty), lights up when what is being
	/// dragged or picked would fit, and takes drops and taps
	func target(_ s: ExoSlot, _ w: CGFloat, _ h: CGFloat, showIcon: Bool) -> some View {
		let box: ExoFrames = frames
		let fitted: Stack? = plan[s]
		let cand: Stack? = candidateStack
		let fits: Bool = cand.map { s.fits($0.item) } ?? false
		let locked: Bool = s.isModule && (s.rawValue - ExoSlot.mod1.rawValue) >= plan.sockets
		let isSel: Bool = sel == s.rawValue
		let isHover: Bool = hover == s.rawValue
		var edge: Color = Color.white.opacity(0.25)
		if fits { edge = Color(hex: 0x60E0FF) }
		if isHover && fits { edge = Color(hex: 0x7AF08A) }
		if isSel { edge = Color.white }
		let g: Game = game
		return ZStack {
			Rectangle().fill(fits ? Color(hex: 0x1E4A5A).opacity(0.55) : Color.black.opacity(showIcon ? 0.35 : 0.01))
			if showIcon {
				VStack(spacing: 1) {
					if let f = fitted {
						Art.shared.icon(f.item).resizable().interpolation(.none).frame(width: 26, height: 26)
					}
					Text(verbatim: locked ? "locked" : (fitted == nil ? s.name : shortName(fitted!))).font(.pixel(8, .semibold))
						.foregroundColor(Color.white.opacity(fitted == nil ? 0.55 : 0.9)).lineLimit(1).minimumScaleFactor(0.6)
				}
			}
		}
		.frame(width: w, height: h)
		.overlay(Rectangle().stroke(edge, lineWidth: isSel || fits ? 2 : 1))
		.background(GeometryReader { gp -> Color in
			box.slots[s.rawValue] = gp.frame(in: .named("exo"))
			return Color.clear
		})
		.contentShape(Rectangle())
		.onTapGesture { tapSlot(s) }
		.gesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("exo"))
			.onChanged { v in
				if dragSlot < 0 && dragging == nil {
					if plan[s] == nil { return }
					dragSlot = s.rawValue
					sel = s.rawValue
				}
				dragPoint = v.location
				hover = box.slot(at: v.location)?.rawValue ?? -1
			}
			.onEnded { v in
				if dragSlot >= 0, let from = ExoSlot(rawValue: dragSlot) {
					if let to = box.slot(at: v.location) {
						moveSlot(from, to)
					} else if box.tray.contains(v.location) {
						unfit(from)
					}
				}
				dragSlot = -1
				hover = -1
				_ = g
			})
	}

	func shortName(_ s: Stack) -> String {
		switch s.item {
		case .exoPart(_, let m), .exoPlate(let m): return m.name
		case .exoCore(let c): return c.name
		case .exoModule(let m): return m.name
		default: return s.item.name
		}
	}

	/// what is being dragged or has been picked from the tray
	var candidateStack: Stack? {
		if let d = dragging { return d.stack }
		if dragSlot >= 0 { return plan[ExoSlot(rawValue: dragSlot) ?? .helmet] }
		if trayPick >= 0, let t = tray.first(where: { $0.id == trayPick }) { return t.stack }
		return nil
	}

	// MARK: changing the plan

	func tapSlot(_ s: ExoSlot) {
		if trayPick >= 0, let t = tray.first(where: { $0.id == trayPick }) {
			fit(t.stack, s)
			trayPick = -1
			return
		}
		sel = sel == s.rawValue ? -1 : s.rawValue
		note = ""
	}

	func fit(_ st: Stack, _ s: ExoSlot) {
		if !s.fits(st.item) {
			note = joinText(st.item.name, " doesn't go in the ", s.name.lowercased(), ".")
			return
		}
		if s.isModule && (s.rawValue - ExoSlot.mod1.rawValue) >= plan.sockets {
			note = plan.sockets == 0 ? "Fit a chest frame first: module sockets are in it." : joinText("This chest frame has ", String(plan.sockets), " module sockets: a better metal has more.")
			return
		}
		if case .exoModule(let m) = st.item, plan.modules.contains(m) {
			note = joinText("The suit already has ", m.name, ".")
			return
		}
		plan[s] = st
		sel = s.rawValue
		note = joinText("Planned: ", st.item.name, " in the ", s.name.lowercased(), ". APPLY to fit it.")
	}

	func unfit(_ s: ExoSlot) {
		guard let st = plan[s] else { return }
		plan[s] = nil
		note = joinText(st.item.name, " comes off (back to your bag on APPLY).")
	}

	func moveSlot(_ a: ExoSlot, _ b: ExoSlot) {
		if a == b { return }
		guard let st = plan[a] else { return }
		if !b.fits(st.item) {
			note = joinText(st.item.name, " doesn't go in the ", b.name.lowercased(), ".")
			return
		}
		let other: Stack? = plan[b]
		plan[b] = st
		plan[a] = (other != nil && a.fits(other!.item)) ? other : nil
		sel = b.rawValue
	}

	// MARK: the parts tray

	/// The parts that can go on: suit parts in the bag (less those the plan already uses), and parts the
	/// plan has taken off the suit
	var tray: [TrayPart] {
		var pool: [Stack] = Array(game.suit.parts.values)
		var fromBag: [Stack] = []
		for s in ExoSlot.allCases {
			guard let st = plan[s] else { continue }
			if let j = pool.firstIndex(of: st) { pool.remove(at: j) } else { fromBag.append(st) }
		}
		var out: [TrayPart] = []
		for (k, st) in pool.enumerated() { out.append(TrayPart(id: 1000 + k, stack: st, fromSuit: true)) }
		for i in 0..<game.inv.slots.count {
			guard let st = game.inv.slots[i] else { continue }
			if !isExoItem(st.item) { continue }
			if let j = fromBag.firstIndex(of: st) {
				fromBag.remove(at: j)
				continue
			}
			out.append(TrayPart(id: i, stack: st, fromSuit: false))
		}
		return out
	}

	func isExoItem(_ it: Item) -> Bool {
		switch it {
		case .exoPart, .exoPlate, .exoCore, .exoModule: return true
		default: return false
		}
	}

	var trayColumn: some View {
		let list: [TrayPart] = tray
		let box: ExoFrames = frames
		let cols: [GridItem] = [GridItem(.adaptive(minimum: 50), spacing: 4)]
		return VStack(alignment: .leading, spacing: 6) {
			Text("PARTS").font(.pixel(13)).foregroundColor(Color(hex: 0x9AD8F0))
			Text("Drag onto the suit, or tap one and then a place. Drag a fitted part here to take it off.")
				.font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.6))
			ScrollView {
				LazyVGrid(columns: cols, spacing: 4) {
					ForEach(list) { t in trayItem(t) }
				}
				if list.isEmpty {
					Text("No suit parts in your bag. MAKE PARTS shows what can be made here.")
						.font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.55))
				}
			}
			.frame(height: 230)
			.background(Color.black.opacity(dragSlot >= 0 ? 0.45 : 0.2))
			.overlay(Rectangle().stroke(dragSlot >= 0 ? Color(hex: 0xFFB060) : Color.clear, lineWidth: 2))
			.background(GeometryReader { gp -> Color in
				box.tray = gp.frame(in: .named("exo"))
				return Color.clear
			})
			actions
		}
	}

	func trayItem(_ t: TrayPart) -> some View {
		let box: ExoFrames = frames
		return SlotView(stack: t.stack, selected: trayPick == t.id, size: 46)
			.overlay(Rectangle().stroke(t.fromSuit ? Color(hex: 0xFFB060) : Color.clear, lineWidth: 2))
			.opacity(dragging?.id == t.id ? 0.35 : 1.0)
			.onTapGesture {
				trayPick = trayPick == t.id ? -1 : t.id
				sel = -1
				note = t.fromSuit ? joinText(t.stack.item.name, " (taken off in this plan)") : t.stack.item.name
			}
			.gesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("exo"))
				.onChanged { v in
					if dragging == nil { dragging = t }
					dragPoint = v.location
					hover = box.slot(at: v.location)?.rawValue ?? -1
				}
				.onEnded { v in
					if let d = dragging, let s = box.slot(at: v.location) { fit(d.stack, s) }
					dragging = nil
					hover = -1
				})
	}

	var actions: some View {
		let st: ExoStats = ExoStats.of(plan)
		let wornNow: Bool = game.suit.worn
		return VStack(spacing: 6) {
			PixelButton(title: changed ? "APPLY" : "NOTHING TO APPLY", color: changed ? Color(hex: 0x2E8A5A) : Color(hex: 0x444444)) {
				if !changed { return }
				note = game.applySuit(plan)
				plan = game.suit
				sel = -1
				trayPick = -1
			}
			HStack(spacing: 6) {
				SmallButton(title: "UNDO PLAN", color: Color(hex: 0x5A4A3A)) {
					plan = game.suit
					note = "Back to the suit as it is."
				}
				SmallButton(title: wornNow ? "TAKE OFF" : "WEAR", color: wornNow ? Color(hex: 0x8A5A2A) : Color(hex: 0x2E6A8A)) {
					if changed {
						note = "APPLY or undo your plan first."
						return
					}
					note = wornNow ? game.takeOffSuit() : game.wearSuit()
				}
			}
			if !st.complete {
				Text("To wear it: a chest frame and a power core.").font(.pixel(9, .semibold)).foregroundColor(Color(hex: 0xFFB060))
			}
		}
	}

	// MARK: numbers

	/// the plan with the dragged or picked part dropped where it is hovering (or where it would go)
	var previewSuit: ExoSuit? {
		guard let c = candidateStack else { return nil }
		var target: ExoSlot? = hover >= 0 ? ExoSlot(rawValue: hover) : nil
		if target == nil {
			target = ExoSlot.allCases.first { s in s.fits(c.item) && plan[s] == nil && !(s.isModule && (s.rawValue - ExoSlot.mod1.rawValue) >= plan.sockets) }
		}
		guard let t = target, t.fits(c.item) else { return nil }
		var p: ExoSuit = plan
		p[t] = c
		return p
	}

	var statsBox: some View {
		let now: ExoStats = ExoStats.of(game.suit)
		let pl: ExoStats = ExoStats.of(plan)
		let pv: ExoStats? = previewSuit.map { ExoStats.of($0) }
		let rows: [(String, Double, Double, Double?, Bool)] = [
			("Defence", now.defense, pl.defense, pv?.defense, true),
			("Weight", now.weight, pl.weight, pv?.weight, false),
			("Strength", now.strength, pl.strength, pv?.strength, true),
			("Speed %", now.speedMul * 100, pl.speedMul * 100, pv.map { $0.speedMul * 100 }, true),
			("Jump %", now.jumpMul * 100, pl.jumpMul * 100, pv.map { $0.jumpMul * 100 }, true),
			("Energy", now.capacity, pl.capacity, pv?.capacity, true),
			("Output /s", now.output, pl.output, pv?.output, true),
			("Recharge /s", now.recharge, pl.recharge, pv?.recharge, true),
			("Energy use %", now.drainMul * 100, pl.drainMul * 100, pv.map { $0.drainMul * 100 }, false)
		]
		return VStack(alignment: .leading, spacing: 3) {
			HStack {
				Text("SUIT").font(.pixel(13)).foregroundColor(Color(hex: 0x9AD8F0))
				Spacer()
				Text(verbatim: changed ? "now → plan" : "now").font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.6))
			}
			ForEach(0..<rows.count, id: \.self) { i in statRow(rows[i]) }
			let mods: [ExoModule] = (pv ?? pl).modules
			Text(verbatim: mods.isEmpty ? "No working modules" : joinText("Modules: ", mods.map { $0.name }.joined(separator: ", ")))
				.font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.8)).lineLimit(3)
			if pl.fireCut > 0 || pl.coldCut > 0 || pl.stormCut > 0 {
				Text(verbatim: joinText("Resists: fire ", String(Int(pl.fireCut * 100)), "%, cold ", String(Int(pl.coldCut * 100)), "%, lightning ", String(Int(pl.stormCut * 100)), "%"))
					.font(.pixel(9, .semibold)).foregroundColor(Color(hex: 0xFFC890))
			}
			ForEach(0..<min(3, pl.notes.count), id: \.self) { i in
				Text(verbatim: pl.notes[i]).font(.pixel(9, .semibold)).foregroundColor(Color(hex: 0xFFB060)).lineLimit(2)
			}
		}
		.padding(6)
		.background(Color.black.opacity(0.25))
	}

	func statRow(_ r: (String, Double, Double, Double?, Bool)) -> some View {
		let shown: Double = r.3 ?? r.2
		let diff: Double = shown - r.1
		let better: Bool = r.4 ? diff > 0 : diff < 0
		let col: Color = abs(diff) < 0.05 ? Color.white : (better ? Color(hex: 0x7AF08A) : Color(hex: 0xFF8A7A))
		return HStack(spacing: 4) {
			Text(verbatim: r.0).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.75))
			Spacer(minLength: 2)
			Text(verbatim: String(format: "%.1f", r.1)).font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
			if abs(diff) >= 0.05 {
				Text(verbatim: joinText("→ ", String(format: "%.1f", shown))).font(.pixel(10)).foregroundColor(col)
			}
		}
	}

	/// what the selected place holds, with a button to take it off
	var detailBox: some View {
		let s: ExoSlot? = sel >= 0 ? ExoSlot(rawValue: sel) : nil
		return VStack(alignment: .leading, spacing: 4) {
			if let slot = s {
				Text(verbatim: slot.name.uppercased()).font(.pixel(12)).foregroundColor(Color(hex: 0x9AD8F0))
				if let st = plan[slot] {
					Text(verbatim: st.item.name).font(.pixel(11))
					ForEach(0..<st.item.infoLines.count, id: \.self) { k in
						Text(verbatim: st.item.infoLines[k]).font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.75)).lineLimit(2)
					}
					if !st.infusionNames.isEmpty {
						Text(verbatim: joinText("Infused: ", st.infusionNames.joined(separator: ", "))).font(.pixel(9, .semibold)).foregroundColor(Color(hex: 0xC07CFF))
					}
					SmallButton(title: "TAKE OFF", color: Color(hex: 0x8A4A3A)) { unfit(slot) }
				} else {
					Text(verbatim: slotHelp(slot)).font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.7))
				}
			} else {
				Text("Tap a place on the suit to see what is in it.").font(.pixel(9, .semibold)).foregroundColor(Color.white.opacity(0.6))
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(6)
		.background(Color.black.opacity(0.25))
	}

	func slotHelp(_ s: ExoSlot) -> String {
		if s.isPlate { return joinText("Takes an armour plate of any metal. Needs the ", (s.plateBase ?? .chest).name.lowercased(), ".") }
		if s.isModule {
			let k: Int = s.rawValue - ExoSlot.mod1.rawValue
			return k < plan.sockets ? "Takes a module. Each needs certain parts (see its notes)." : "Locked: the chest frame's metal decides how many module sockets there are."
		}
		if s == .core { return "Takes a power core: it holds the energy every module runs on." }
		return "Takes a suit part made at this station."
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

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text("Change the game's own blocks, items and creatures: only the numbers you set change, the originals are kept, and switching a change off (or the whole mod) puts the game back as it was.")
				.font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
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
			SmallButton(title: o.enabled ? "ON" : "OFF", color: o.enabled ? ModUI.accent : Color(hex: 0x555555)) { on.wrappedValue.toggle() }
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
					SmallButton(title: "RESTORE", color: Color(hex: 0x6A5A3A)) { value = nil }
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
			SmallButton(title: "RESTORE ALL", color: Color(hex: 0x6A5A3A)) { self.restoreAll() }
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
		let col: Color = s.mod.folder == f ? ModUI.accent : Color(hex: 0x4A4A50)
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
		let col: Color = e == nil ? Color(hex: 0xFF9A7A) : Color.white
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
		let col: Color = Color(hex: sure ? 0xC04030 : 0x6A5A3A)
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
						SmallButton(title: "ALL MODS", color: folder.isEmpty ? ModUI.accent : Color(hex: 0x4A4A50)) { folder = "" }
						ForEach(names, id: \.self) { f in
							SmallButton(title: f.uppercased(), color: folder == f ? ModUI.accent : Color(hex: 0x4A4A50)) { folder = f }
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
			Text(verbatim: secondsText(t)).font(.pixel(11)).foregroundColor(t == nil ? Color(hex: 0xFF9A7A) : Color.white)
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
			Text(verbatim: secondsText(v)).font(.pixel(11)).foregroundColor(v == nil ? Color(hex: 0xFF9A7A) : Color.white)
		}
	}
}

// MARK: - Mod Creator+: the Sprite Studio

/// The pixel editor used for every picture in the Mod Creator: zoom and pan, pen, eraser, fill, colour
/// picker, lines and boxes, mirror drawing, undo and redo, flips, shifts and turns, a reference picture
/// beside or under the canvas (or copied in as a starting sample), the outline switch, other sizes,
/// copying in and out as text or a picture, the sprite library, and onion skin and an animation preview
/// for sprites with frames.
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

	static let toolNames: [String] = ["PEN", "ERASE", "FILL", "PICK", "LINE", "BOX", "MOVE"]

	/// pixels per picture pixel on screen
	var cell: CGFloat {
		let fit: CGFloat = max(4, floor(maxSide / CGFloat(max(pixels.w, pixels.h))))
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
		let a: (Int, Int)? = shapeA
		let b: (Int, Int)? = shapeB
		let t: Int = tool
		let col: UInt32 = color
		return Canvas { ctx, size in
			PixelEditorView.paintCanvas(&ctx, px, c, ox, oy, under, op, onionFrame, grid)
			if let s0 = a, let s1 = b, t == 4 || t == 5 {
				let cells: [(Int, Int)] = t == 4 ? PixelEditorView.lineCells(s0, s1) : PixelEditorView.boxCells(s0, s1)
				for (x, y) in cells {
					let r: CGRect = CGRect(x: CGFloat(x) * c - ox, y: CGFloat(y) * c - oy, width: c, height: c)
					ctx.fill(Path(r), with: .color(Color(hex: col & 0xFFFFFF).opacity(0.75)))
				}
			}
		}
		.frame(width: viewW, height: viewH)
		.clipped()
		.overlay(Rectangle().stroke(Color.white.opacity(0.35), lineWidth: 1))
		.contentShape(Rectangle())
		.gesture(DragGesture(minimumDistance: 0).onChanged { v in dragged(v.startLocation, v.location) }.onEnded { v in ended(v.location) })
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
				ctx.fill(Path(r), with: .color(Color(hex: v & 0xFFFFFF)))
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

	func cellAt(_ p: CGPoint) -> (Int, Int)? {
		let c: CGFloat = cell
		let x: Int = Int(floor((p.x + panX) / c))
		let y: Int = Int(floor((p.y + panY) / c))
		if x < 0 || y < 0 || x >= pixels.w || y >= pixels.h { return nil }
		return (x, y)
	}

	func remember() {
		undo.append(pixels)
		if undo.count > 50 { undo.removeFirst() }
		redo.removeAll()
	}

	func dragged(_ start: CGPoint, _ p: CGPoint) {
		if tool == 6 {
			if !stroking {
				stroking = true
				panStart = CGPoint(x: panX, y: panY)
			}
			let maxX: CGFloat = max(0, cell * CGFloat(pixels.w) - viewW)
			let maxY: CGFloat = max(0, cell * CGFloat(pixels.h) - viewH)
			panX = min(maxX, max(0, panStart.x - (p.x - start.x)))
			panY = min(maxY, max(0, panStart.y - (p.y - start.y)))
			return
		}
		guard let (x, y) = cellAt(p) else { return }
		if tool == 4 || tool == 5 {
			if shapeA == nil, let s = cellAt(start) { shapeA = s }
			shapeB = (x, y)
			return
		}
		let idx: Int = y * pixels.w + x
		if !stroking {
			stroking = true
			if tool != 3 { remember() }
		} else if idx == lastCell {
			return
		}
		lastCell = idx
		var px: ModPixels = pixels
		switch tool {
		case 1:
			px.setARGB(x, y, 0)
			if mirror { px.setARGB(px.w - 1 - x, y, 0) }
		case 2:
			PixelEditorView.floodFill(&px, x, y, color)
		case 3:
			let picked: UInt32 = px.argb(x, y)
			if (picked >> 24) != 0 { pickColor(picked) }
			tool = 0
			return
		default:
			px.setARGB(x, y, color)
			if mirror { px.setARGB(px.w - 1 - x, y, color) }
		}
		pixels = px
		useColor(color)
	}

	func ended(_ p: CGPoint) {
		if (tool == 4 || tool == 5), let a = shapeA {
			let b: (Int, Int) = cellAt(p) ?? shapeB ?? a
			remember()
			var px: ModPixels = pixels
			let cells: [(Int, Int)] = tool == 4 ? PixelEditorView.lineCells(a, b) : PixelEditorView.boxCells(a, b)
			for (x, y) in cells {
				px.setARGB(x, y, color)
				if mirror { px.setARGB(px.w - 1 - x, y, color) }
			}
			pixels = px
			useColor(color)
		}
		shapeA = nil
		shapeB = nil
		stroking = false
		lastCell = -1
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
		var out: [(Int, Int)] = []
		let x0: Int = min(a.0, b.0)
		let x1: Int = max(a.0, b.0)
		let y0: Int = min(a.1, b.1)
		let y1: Int = max(a.1, b.1)
		for x in x0...x1 {
			out.append((x, y0))
			out.append((x, y1))
		}
		for y in y0...y1 {
			out.append((x0, y))
			out.append((x1, y))
		}
		return out
	}

	static func floodFill(_ px: inout ModPixels, _ sx: Int, _ sy: Int, _ col: UInt32) {
		let target: UInt32 = px.argb(sx, sy)
		if target == col { return }
		var stack: [(Int, Int)] = [(sx, sy)]
		var guardN: Int = 0
		while let cur = stack.popLast() {
			guardN += 1
			if guardN > 8000 { break }
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
			SmallButton(title: showGrid ? "GRID ON" : "GRID OFF", color: showGrid ? ModUI.accent : Color(hex: 0x555555)) { showGrid.toggle() }
			if frameIndex > 0 {
				SmallButton(title: onion ? "ONION ON" : "ONION OFF", color: onion ? ModUI.accent : Color(hex: 0x555555)) { onion.toggle() }
			}
		}
	}

	func setZoom(_ z: CGFloat) {
		zoom = min(48, max(4, z))
		panX = 0
		panY = 0
	}

	var toolGrid: some View {
		let cols: [GridItem] = [GridItem(.fixed(78), spacing: 4), GridItem(.fixed(78), spacing: 4)]
		return LazyVGrid(columns: cols, spacing: 4) {
			ForEach(0..<PixelEditorView.toolNames.count, id: \.self) { i in
				SmallButton(title: PixelEditorView.toolNames[i], color: tool == i ? ModUI.accent : Color(hex: 0x555555)) { tool = i }
			}
			SmallButton(title: mirror ? "MIRROR ON" : "MIRROR", color: mirror ? ModUI.accent : Color(hex: 0x555555)) { mirror.toggle() }
		}
	}

	var editButtons: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				SmallButton(title: "UNDO", color: undo.isEmpty ? Color(hex: 0x444444) : Color(hex: 0x5A5A70)) {
					if let last = undo.popLast() {
						redo.append(pixels)
						pixels = last
					}
				}
				SmallButton(title: "REDO", color: redo.isEmpty ? Color(hex: 0x444444) : Color(hex: 0x5A5A70)) {
					if let next = redo.popLast() {
						undo.append(pixels)
						pixels = next
					}
				}
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
			let on: Bool = pixels.outlined(outlineDefault)
			SmallButton(title: on ? "OUTLINE ON" : "OUTLINE OFF", color: on ? ModUI.accent : Color(hex: 0x555555)) {
				var p: ModPixels = pixels
				p.outline = !on
				pixels = p
			}
		}
	}

	func change(_ f: (ModPixels) -> ModPixels) {
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
					.background(Color(hex: 0x6AA0D8).opacity(0.5))
				if frames.count > 1 { animation }
			}
			HStack(spacing: 6) {
				Rectangle().fill(Color(hex: color & 0xFFFFFF)).frame(width: 26, height: 26).overlay(Rectangle().stroke(Color.white, lineWidth: 2))
				Text(verbatim: joinText(String(pixels.w), " x ", String(pixels.h))).font(.pixel(11, .semibold)).foregroundColor(ModUI.dim)
			}
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

	var palette: some View {
		let cols: [GridItem] = [GridItem](repeating: GridItem(.fixed(34), spacing: 4), count: 16)
		return VStack(alignment: .leading, spacing: 4) {
			LazyVGrid(columns: cols, spacing: 4) {
				ForEach(0..<modPalette.count, id: \.self) { i in swatch(modPalette[i]) }
			}
			if !recent.isEmpty {
				HStack(spacing: 4) {
					Text("RECENT").font(.pixel(9)).foregroundColor(ModUI.dim)
					ForEach(0..<recent.count, id: \.self) { i in swatch(recent[i] & 0xFFFFFF) }
				}
			}
			SmallButton(title: showMixer ? "HIDE COLOUR MIXER" : "MIX A COLOUR...") { showMixer.toggle() }
		}
	}

	func swatch(_ c: UInt32) -> some View {
		let on: Bool = (color & 0xFFFFFF) == c
		return Rectangle().fill(Color(hex: c))
			.frame(width: 34, height: 34)
			.overlay(Rectangle().stroke(on ? Color.white : Color.black, lineWidth: on ? 3 : 1))
			.onTapGesture {
				color = 0xFF000000 | c
				if tool == 1 || tool == 3 || tool == 6 { tool = 0 }
			}
	}

	func pickColor(_ c: UInt32) {
		color = c
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
			if tool != 0 && tool != 2 && tool != 4 && tool != 5 { tool = 0 }
		})
	}

	// MARK: panels: reference, size, copy in and out, library

	var panelTabs: some View {
		HStack(spacing: 6) {
			ForEach(0..<4, id: \.self) { i in
				SmallButton(title: ["REFERENCE", "SIZE", "COPY & PASTE", "SPRITE LIBRARY"][i], color: panel == i + 1 ? ModUI.blue : Color(hex: 0x4A4A50)) {
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
					SmallButton(title: "BESIDE", color: refMode == 1 ? ModUI.accent : Color(hex: 0x555555)) { refMode = 1 }
					SmallButton(title: "UNDER", color: refMode == 2 ? ModUI.accent : Color(hex: 0x555555)) { refMode = 2 }
					SmallButton(title: "HIDE", color: refMode == 0 ? ModUI.accent : Color(hex: 0x555555)) { refMode = 0 }
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
		let col: Color = tab == i ? ModUI.accent : Color(hex: 0x555555)
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
		let col: Color = frame == i ? ModUI.accent : Color(hex: 0x555555)
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
		let col: Color = changed ? Color(hex: 0x7AF08A) : Color.white
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
				SmallButton(title: names[i], color: on ? ModUI.accent : Color(hex: 0x555555)) {
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
				Text("FROM MODS").font(.pixel(11)).foregroundColor(Color(hex: 0xB8A8D8)).frame(maxWidth: .infinity, alignment: .leading)
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
					Text(verbatim: r.def.name).font(.pixel(12)).foregroundColor(Color(hex: (Rarity(rawValue: r.def.rarity) ?? .uncommon).color))
					Text(verbatim: r.def.blurb).font(.pixel(10, .semibold)).foregroundColor(Color.white.opacity(0.8)).lineLimit(2)
				}
				Spacer(minLength: 0)
				Text(verbatim: owned > 0 ? joinText("x", String(owned)) : "none").font(.pixel(10)).foregroundColor(Color.white.opacity(0.6))
			}
			.padding(4)
			.background(chosen ? Color(hex: 0x4A3A6A) : Color.black.opacity(0.2))
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
			if let p = problem { Text(verbatim: p).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xFF9A7A)) }
			PixelButton(title: ok ? "CONFIRM INFUSION" : "CAN'T INFUSE", color: ok ? Color(hex: 0x6A4AA8) : Color(hex: 0x444444)) {
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
		let col: Color = Color(hex: seg.1)
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
				img.resizable().interpolation(.none).frame(width: 72, height: 72).background(Color(hex: 0x5A7A9A).opacity(0.6))
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
		.background(Color(hex: 0x6A8AAA).opacity(0.5))
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

	static let pages: [String] = ["BASICS", "SKY", "LAND", "REGIONS", "LIFE", "WAY IN", "PREVIEW"]
	static let skyColorNames: [String] = ["Day: top", "Day: bottom", "Night: top", "Night: bottom", "Sun"]

	func b<T>(_ kp: WritableKeyPath<ModDimension, T>, _ d: T) -> Binding<T> { return s.bind(\ModPack.dims, id, kp, d) }
	var dim: ModDimension { return s.mod.dims.first { $0.id == id } ?? ModDimension() }

	var body: some View {
		ZStack {
			VStack(spacing: 10) {
				header
				ChoiceRows(options: DimensionEditorView.pages, selected: $page, columns: 7)
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
		let col: Color = d.entry.enabled ? ModUI.gold : Color(hex: 0xFF9060)
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
		case 2: landPage
		case 3: zonesPage
		case 4: lifePage
		case 5: entryPage
		case 6: previewPage
		default: basicsPage
		}
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
		let sun: Color = Color(hex: d.sunColor & 0xFFFFFF)
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

	/// A block chosen in the picker goes where it was asked for (a region's blocks are "z<n>:<field>")
	func setBlock(_ field: String, _ key: String) {
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
			if trees {
				blockRow("Trunk", z.log, joinText(tag, "log"))
				blockRow("Leaves", z.leaves, joinText(tag, "leaves"))
			}
		}
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
					Text("Changed since this preview was made.").font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xFF9060))
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
				PixelButton(title: "+ NEW GROUP", color: Color(hex: 0x8A6A2A)) { self.add(.group) }
			}
		}
	}

	func scriptRow(_ sc: ModScript) -> some View {
		let bar: Color = Color(hex: sc.event == .group ? 0xC08A3A : 0xE8C040)
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
		let bg: Color = Color(hex: group ? 0xC08A3A : 0xE8C040)
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
				Text("Make one in this mod first.").font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0x7A1A1A))
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
		let col: Color = Color(hex: c.color)
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
		let col: Color = Color(hex: sp.cat.color)
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
				.background(Color(hex: 0x9AE070))
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
					Text(verbatim: joinText("\u{2022} ", i.text)).font(.pixel(11, .semibold)).foregroundColor(Color(hex: 0xFFB070))
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
				.background(Color(hex: 0x9AE070))
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
		let runCol: Color = paused ? ModUI.accent : Color(hex: 0x8A6A2A)
		return HStack(spacing: 8) {
			SmallButton(title: runTitle, color: runCol) { self.pause() }
			if paused { SmallButton(title: "STEP", color: ModUI.blue) { self.step() } }
			SmallButton(title: "WORLD START AGAIN", color: ModUI.blue) { self.restart() }
			SmallButton(title: "REFRESH", color: Color(hex: 0x555555)) { self.rev += 1 }
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
		return SmallButton(title: title, color: Color(hex: 0x8A6A2A)) {
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
