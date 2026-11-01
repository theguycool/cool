class_name Inventory
extends RefCounted
## The player's bag: 40 slots (the first 10 are the hotbar), three armour slots (head, chest, legs)
## and two gear slots. A slot is null or {"id": item id, "n": count, "x": extra (shots loaded)}.

const SIZE := 40
const HOTBAR := 10
const ARMOR_SLOTS := 5

signal changed

var slots: Array = []
## 0 head, 1 chest, 2 legs, 3-4 gear
var armor: Array = []


func _init() -> void:
	slots.resize(SIZE)
	armor.resize(ARMOR_SLOTS)


static func make(id: String, n: int, extra: int = 0) -> Dictionary:
	return {"id": id, "n": n, "x": extra}


static func count_of(s) -> int:
	if s == null:
		return 0
	return int(s["n"])


func notify() -> void:
	changed.emit()


## Adds n of an item (filling partly full stacks first, then the hotbar, then the bag); returns
## how many did not fit
func add(id: String, n: int, extra: int = 0) -> int:
	if id == "" or n <= 0:
		return 0
	var left: int = n
	var ms: int = DB.max_stack(id)
	if ms > 1:
		for i in range(SIZE):
			var s = slots[i]
			if s != null and String(s["id"]) == id and int(s["n"]) < ms:
				var put: int = mini(ms - int(s["n"]), left)
				s["n"] = int(s["n"]) + put
				left -= put
				if left <= 0:
					break
	var i2: int = 0
	while left > 0 and i2 < SIZE:
		if slots[i2] == null:
			var put2: int = mini(ms, left)
			slots[i2] = make(id, put2, extra)
			left -= put2
		i2 += 1
	if left != n:
		notify()
	return left


func total(id: String) -> int:
	var t: int = 0
	for s in slots:
		if s != null and String(s["id"]) == id:
			t += int(s["n"])
	return t


func can_fit(id: String, n: int) -> bool:
	var room: int = 0
	var ms: int = DB.max_stack(id)
	for s in slots:
		if s == null:
			room += ms
		elif String(s["id"]) == id:
			room += ms - int(s["n"])
		if room >= n:
			return true
	return false


## Takes up to n of an item from anywhere in the bag; returns how many were taken
func remove(id: String, n: int) -> int:
	var need: int = n
	for i in range(SIZE - 1, -1, -1):
		var s = slots[i]
		if s == null or String(s["id"]) != id:
			continue
		var take: int = mini(need, int(s["n"]))
		s["n"] = int(s["n"]) - take
		need -= take
		if int(s["n"]) <= 0:
			slots[i] = null
		if need <= 0:
			break
	if need != n:
		notify()
	return n - need


func remove_at(i: int, n: int) -> void:
	var s = slots[i]
	if s == null:
		return
	s["n"] = int(s["n"]) - n
	if int(s["n"]) <= 0:
		slots[i] = null
	notify()


## cost: [[item id, count], ...]
func can_afford(cost: Array) -> bool:
	for c in cost:
		if total(String(c[0])) < int(c[1]):
			return false
	return true


func pay(cost: Array) -> void:
	for c in cost:
		remove(String(c[0]), int(c[1]))


## Total armour defence from the three armour slots
func defense() -> float:
	var d: float = 0.0
	for i in range(3):
		var s = armor[i]
		if s != null:
			d += float(DB.item(String(s["id"])).get("defense", 0.0))
	return d


func wearing(gear_id: String) -> bool:
	for i in range(3, ARMOR_SLOTS):
		var s = armor[i]
		if s != null and String(s["id"]) == gear_id:
			return true
	return false


## The armour tier worn in a slot (0 head, 1 chest, 2 legs), or 0
func armor_tier(slot: int) -> int:
	var s = armor[slot]
	if s == null:
		return 0
	return DB.tier_of(String(s["id"]))


## Which armour slot an item goes in (0-2), 3 for gear, or -1
static func equip_slot(id: String) -> int:
	var k: String = DB.kind_of(id)
	if k == "armor":
		match id.get_slice(":", 1):
			"head": return 0
			"chest": return 1
			"legs": return 2
	if k == "gear":
		return 3
	return -1


## Puts the item from bag slot i into its armour or gear slot (swapping out what was there)
func equip_from(i: int) -> bool:
	var s = slots[i]
	if s == null:
		return false
	var e: int = equip_slot(String(s["id"]))
	if e < 0:
		return false
	if e == 3:
		e = 3 if armor[3] == null else (4 if armor[4] == null else 3)
	var old = armor[e]
	armor[e] = s
	slots[i] = old
	notify()
	return true


func unequip(e: int) -> bool:
	var s = armor[e]
	if s == null:
		return false
	if add(String(s["id"]), int(s["n"]), int(s.get("x", 0))) > 0:
		return false
	armor[e] = null
	notify()
	return true


## Sorts the bag (not the hotbar): weapons first, then tools, armour, food... building blocks, materials
func sort_bag() -> void:
	var items: Array = []
	for i in range(HOTBAR, SIZE):
		if slots[i] != null:
			items.append(slots[i])
			slots[i] = null
	# merge stacks of the same item
	var merged: Array = []
	for s in items:
		var placed: bool = false
		var ms: int = DB.max_stack(String(s["id"]))
		for m in merged:
			if String(m["id"]) == String(s["id"]) and int(m["n"]) < ms and ms > 1:
				var put: int = mini(ms - int(m["n"]), int(s["n"]))
				m["n"] = int(m["n"]) + put
				s["n"] = int(s["n"]) - put
				if int(s["n"]) <= 0:
					placed = true
					break
		if not placed:
			merged.append(s)
	merged.sort_custom(_sort_cmp)
	var k: int = HOTBAR
	for s in merged:
		if k >= SIZE:
			break
		slots[k] = s
		k += 1
	notify()


func _sort_cmp(a: Dictionary, b: Dictionary) -> bool:
	var ga: int = int(DB.item(String(a["id"])).get("sortGroup", 10))
	var gb: int = int(DB.item(String(b["id"])).get("sortGroup", 10))
	if ga != gb:
		return ga < gb
	return String(a["id"]) < String(b["id"])


func to_save() -> Dictionary:
	return {"slots": slots.duplicate(true), "armor": armor.duplicate(true)}


func from_save(d: Dictionary) -> void:
	var s: Array = d.get("slots", [])
	var a: Array = d.get("armor", [])
	for i in range(SIZE):
		slots[i] = _clean(s[i]) if i < s.size() else null
	for i in range(ARMOR_SLOTS):
		armor[i] = _clean(a[i]) if i < a.size() else null
	notify()


static func _clean(v) -> Variant:
	if v == null or not (v is Dictionary):
		return null
	var d: Dictionary = v
	if not d.has("id") or not DB.has_item(String(d["id"])):
		return null
	return make(String(d["id"]), int(d.get("n", 1)), int(d.get("x", 0)))
