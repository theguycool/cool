class_name MapPanel
extends PanelBase
## The treasure map Ursavor drops: a side view of the land from your first camp to the sealed gate,
## with the lairs, ruins and mine shafts marked, a dashed red ring the gate lies somewhere inside, where
## you are now, and written clues (plus how loudly the Portal Key hums when you carry it).

var map := {}


func setup(lv: Level) -> void:
	level = lv
	setup_frame(Vector2(880, 600), true)
	var head: HBoxContainer = UIKit.hbox(6)
	head.add_child(UIKit.ink("TREASURE MAP", 22, Color(0.29, 0.16, 0.06)))
	head.add_child(UIKit.spacer())
	head.add_child(UIKit.button("CLOSE", Color(0.63, 0.19, 0.19), close, 0.0, 36.0))
	content.add_child(head)
	map = build_map(lv.gen)
	var view := MapView.new()
	view.level = lv
	view.map = map
	view.custom_minimum_size = Vector2(0, 250)
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(view)
	var list := ScrollList.new()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.text_color = Color(0.23, 0.14, 0.06)
	list.row_bg = Color(0, 0, 0, 0)
	list.spacing = 0.0
	list.pad = 3.0
	list.font_size = 14
	content.add_child(list)
	var rows: Array = []
	for c in map["clues"]:
		rows.append({"text": "• " + String(c)})
	if lv.player.inv.total("gadget:portalKey") > 0 and lv.dim == WorldGen.DIM_OVERWORLD:
		rows.append({"text": "Key: " + portal_hint(lv), "color": Color(0.42, 0.16, 0.69)})
	if lv.portal_opened:
		rows.append({"text": "The gate has been opened.", "color": Color(0.16, 0.42, 0.16)})
	list.set_rows(rows)


## Rounds a distance the way a map maker would ("about 350", "1,200")
static func rough_distance(d: int) -> String:
	var unit: int = 50 if d < 1000 else 100
	var r: int = maxi(unit, roundi(float(d) / float(unit)) * unit)
	if r >= 1000:
		return "%d,%d00" % [r / 1000, (r % 1000) / 100]
	return str(r)


## How the Portal Key behaves at this distance from the gate
static func portal_hint(lv: Level) -> String:
	var dx: float = lv.player.global_position.x / 8.0 - float(lv.gen.portal_x)
	var dy: float = (lv.player.global_position.y / 8.0 - float(lv.gen.portal_y)) * 0.6
	var d: float = sqrt(dx * dx + dy * dy)
	if d < 45.0:
		return "The Portal Key burns in your hand. The gate is very close!"
	if d < 120.0:
		return "The Portal Key hums loudly. You are near."
	if d < 300.0:
		return "The Portal Key trembles faintly..."
	if d < 700.0:
		return "The Portal Key is cool and quiet. The gate is far."
	return "The Portal Key is silent."


## The map for this world (always the same for a seed): the land's outline, markers, ring and clues
static func build_map(g: WorldGen) -> Dictionary:
	var px: int = g.portal_x
	var py: int = g.portal_y
	var rx: int = 150
	var ry: int = 80
	# the ring is offset so the exact spot stays a mystery, but the gate is always inside it
	var ox: int = int((PRNG.hash2(11, 12, g.world_seed) - 0.5) * 2.0 * 0.55 * float(rx))
	var oy: int = int((PRNG.hash2(13, 14, g.world_seed) - 0.5) * 2.0 * 0.55 * float(ry))
	var ring_x: int = px + ox
	var ring_y: int = clampi(py + oy, 200 + ry / 2, WorldGen.H - 20 - ry / 2)
	var sx: int = g.spawn_x
	var x0: int = mini(sx, ring_x - rx) - 160
	var x1: int = maxi(sx, ring_x + rx) + 160
	if not g.infinite:
		x0 = maxi(0, x0)
		x1 = mini(g.width - 1, x1)
	var step: int = maxi(4, (x1 - x0) / 300)
	var hs: Array = []
	var bs: Array = []
	var x: int = x0
	while x <= x1:
		var c: Array = g.col(x)
		hs.append(int(c[0]))
		bs.append(int(c[1]))
		x += step
	var markers: Array = [{"x": sx, "kind": 0, "label": "Start"}]
	for lair in g.lair_centers((x0 + x1) / 2):
		var lc: int = int(lair["cx"])
		if lc < x0 or lc > x1:
			continue
		var bear: bool = String(lair["kind"]) == "bear"
		markers.append({"x": lc, "kind": 1 if bear else 2, "label": "Bear Den" if bear else "Bone Nest"})
	for r in Structures.rare_sites(g, x0, x1):
		markers.append({"x": int(r["x"]), "kind": 4, "label": Journal.ruin_name(String(r["kind"]))})
	for m in Structures.mine_sites(g, x0, x1):
		markers.append({"x": int(m["x"]) + 1, "kind": 5, "label": "Mine Shaft"})
	var clues: Array = []
	var d: int = absi(px - sx)
	clues.append("The gate lies roughly %s blocks %s of where you first woke." % [rough_distance(d), "east" if px >= sx else "west"])
	clues.append("Above it, the land is %s." % DB.biome_name(g.biome_at(px)))
	clues.append("It sleeps far below the surface, deeper than the iron veins. Dig down.")
	var best: Dictionary = {}
	var bd: int = 1 << 30
	for mk in markers:
		var md: Dictionary = mk
		if int(md["kind"]) == 0:
			continue
		var dd: int = absi(int(md["x"]) - px)
		if dd < bd and dd < 900:
			bd = dd
			best = md
	if not best.is_empty():
		clues.append("The nearest landmark, a %s, stands about %s blocks to its %s." % [String(best["label"]).to_lower(), rough_distance(bd), "west" if int(best["x"]) < px else "east"])
	for side in [-1, 1]:
		var mt: int = 0
		var oc: int = 0
		var k: int = 20
		while k <= 220:
			var b: int = g.biome_at(px + int(side) * k)
			if b == WorldGen.MOUNTAIN:
				mt += 1
			if b == WorldGen.OCEAN:
				oc += 1
			k += 20
		var sn: String = "west" if int(side) < 0 else "east"
		if mt >= 3:
			clues.append("Mountains guard its %s side." % sn)
		elif oc >= 3:
			clues.append("The sea is close on its %s side." % sn)
	clues.append("The Portal Key hums louder as you draw near.")
	return {"x0": x0, "x1": x1, "step": step, "heights": hs, "biomes": bs, "ring_x": ring_x, "ring_y": ring_y,
		"ring_rx": rx, "ring_ry": ry, "markers": markers, "clues": clues}
