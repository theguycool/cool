extends Node
## Textures and animation frames (autoload "Art"): the terrain TileSet with its collision shapes,
## item icons, creature and player SpriteFrames built from the PNG sheets in assets/.

const MiscData = preload("res://scripts/data/misc_data.gd")

## terrain atlas: column = edge variant (0 plain, 1 lit top, 2 shaded bottom, 3 both), row = tile id
const SRC_TERRAIN := 0
const SRC_WALLS := 1
const LAYER_SOLID := 1
const LAYER_PLATFORM := 2

var terrain_tex: Texture2D
var walls_tex: Texture2D
var icons_tex: Texture2D
var player_tex: Texture2D
var armor_tex := {}
var tileset: TileSet
var _icons := {}
var _creatures := {}
var _player := {}
var _textures := {}


func _init() -> void:
	terrain_tex = load("res://assets/tiles/terrain.png")
	walls_tex = load("res://assets/tiles/walls.png")
	icons_tex = load("res://assets/items/icons.png")
	player_tex = load("res://assets/player/base.png")
	for slot in ["head", "chest", "legs"]:
		armor_tex[slot] = load("res://assets/player/armor_%s.png" % slot)


func _ready() -> void:
	tileset = _build_tileset()


func tex(path: String) -> Texture2D:
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = load(path)
	_textures[path] = t
	return t


# ---------------------------------------------------------------------------------------------- tiles

func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(8, 8)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, LAYER_SOLID)
	ts.set_physics_layer_collision_mask(0, 0)
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(1, LAYER_PLATFORM)
	ts.set_physics_layer_collision_mask(1, 0)
	var src := TileSetAtlasSource.new()
	src.texture = terrain_tex
	src.texture_region_size = Vector2i(8, 8)
	ts.add_source(src, SRC_TERRAIN)
	var square := PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
	var top := PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, -1), Vector2(-4, -1)])
	var n: int = DB.tiles.size()
	for id in range(n):
		for v in range(4):
			var c := Vector2i(v, id)
			src.create_tile(c)
			var td: TileData = src.get_tile_data(c, 0)
			if DB.solid[id] == 1:
				td.add_collision_polygon(0)
				td.set_collision_polygon_points(0, 0, square)
			elif DB.platform[id] == 1:
				td.add_collision_polygon(1)
				td.set_collision_polygon_points(1, 0, top)
				td.set_collision_polygon_one_way(1, 0, true)
	var wsrc := TileSetAtlasSource.new()
	wsrc.texture = walls_tex
	wsrc.texture_region_size = Vector2i(8, 8)
	ts.add_source(wsrc, SRC_WALLS)
	for k in range(7):
		wsrc.create_tile(Vector2i(k, 0))
	return ts


## A single tile's picture (for icons of blocks and falling sand)
func tile_texture(id: int) -> AtlasTexture:
	var at := AtlasTexture.new()
	at.atlas = terrain_tex
	at.region = Rect2(0, id * 8, 8, 8)
	return at


# ---------------------------------------------------------------------------------------------- items

func icon(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var i: int = int(DB.item(id).get("icon", 0))
	var at := AtlasTexture.new()
	at.atlas = icons_tex
	at.region = Rect2((i % 16) * 16, (i / 16) * 16, 16, 16)
	_icons[id] = at
	return at


# ---------------------------------------------------------------------------------------------- creatures

## Animations for a creature: "idle", "walk", and as the art provides "attack", "alt" (grazing,
## pecking), "air" (a hop), "move" (the loop of fliers and swimmers), and for humanoids "swing" and "aim".
func creature_frames(key: String, variant: int) -> SpriteFrames:
	var ck: String = "%s:%d" % [key, variant]
	if _creatures.has(ck):
		return _creatures[ck]
	var m: Dictionary = DB.mob(key)
	var art: Dictionary = m["art"]
	var cell: Array = art["cell"]
	var vs: Array = art["variants"]
	var vi: int = clampi(variant, 0, vs.size() - 1)
	var v: Dictionary = vs[vi]
	var sheet: Texture2D = tex("res://assets/creatures/%s.png" % key)
	var frames: Array = []
	for f in range(int(v["frames"])):
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(f * int(cell[0]), vi * int(cell[1]), int(v["w"]), int(v["h"]))
		frames.append(at)
	var sf := SpriteFrames.new()
	var nf: int = frames.size()
	if bool(m["humanoid"]) and nf >= 7:
		_anim(sf, "idle", frames, [0], 2.0)
		_anim(sf, "walk", frames, [1, 2], 6.0)
		_anim(sf, "swing", frames, [3, 4], 8.0)
		_anim(sf, "attack", frames, [3, 4], 8.0)
		_anim(sf, "aim", frames, [6], 2.0)
		_anim(sf, "air", frames, [1], 2.0)
	else:
		var cyc: Array = v["cycle"]
		_anim(sf, "idle", frames, [0], 2.0)
		if cyc.size() > 0:
			_anim(sf, "move", frames, cyc, 8.0)
			_anim(sf, "walk", frames, cyc, 8.0)
		elif nf >= 3:
			_anim(sf, "walk", frames, [1, 2], 6.0)
		else:
			_anim(sf, "walk", frames, [0, nf - 1], 6.0)
		if int(v["attack"]) >= 0 and int(v["attack"]) < nf:
			_anim(sf, "attack", frames, [int(v["attack"])], 4.0)
		else:
			_anim(sf, "attack", frames, [mini(1, nf - 1)], 4.0)
		if int(v["idleAlt"]) >= 0 and int(v["idleAlt"]) < nf:
			_anim(sf, "alt", frames, [int(v["idleAlt"])], 2.0)
		_anim(sf, "air", frames, [nf - 1 if bool(v["hop"]) else mini(1, nf - 1)], 2.0)
		# bosses and big creatures: every frame in order, for their special moves
		_anim(sf, "all", frames, range(nf), 6.0)
	_creatures[ck] = sf
	return sf


func creature_meta(key: String, variant: int) -> Dictionary:
	var vs: Array = DB.mob(key)["art"]["variants"]
	return vs[clampi(variant, 0, vs.size() - 1)]


func _anim(sf: SpriteFrames, name: String, frames: Array, idx: Array, fps: float) -> void:
	if not sf.has_animation(name):
		sf.add_animation(name)
	sf.set_animation_speed(name, fps)
	sf.set_animation_loop(name, true)
	for i in idx:
		var k: int = clampi(int(i), 0, frames.size() - 1)
		sf.add_frame(name, frames[k])


# ---------------------------------------------------------------------------------------------- player

## The hero: 0 idle, 1-2 walking (1 also in the air), 3-4 a swing, 6 aiming a bow or a gun
func player_frames(hair: int, scarf: int) -> SpriteFrames:
	var key: String = "base:%d:%d" % [hair, scarf]
	if _player.has(key):
		return _player[key]
	var row: int = clampi(hair, 0, 4) * 5 + clampi(scarf, 0, 4)
	var sf: SpriteFrames = _humanoid_frames(player_tex, row)
	_player[key] = sf
	return sf


## Armour drawn over the hero: the same frames, only the pixels the armour changes
func armor_frames(slot: String, tier_id: int) -> SpriteFrames:
	var key: String = "%s:%d" % [slot, tier_id]
	if _player.has(key):
		return _player[key]
	var sf: SpriteFrames = _humanoid_frames(armor_tex[slot], clampi(tier_id, 1, 9) - 1)
	_player[key] = sf
	return sf


func _humanoid_frames(sheet: Texture2D, row: int) -> SpriteFrames:
	var p: Dictionary = MiscData.PLAYER
	var w: int = int(p["w"])
	var h: int = int(p["h"])
	var frames: Array = []
	for f in range(int(p["frames"])):
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(f * w, row * h, w, h)
		frames.append(at)
	var sf := SpriteFrames.new()
	_anim(sf, "idle", frames, [0], 2.0)
	_anim(sf, "walk", frames, [1, 2], 7.0)
	_anim(sf, "air", frames, [1], 2.0)
	_anim(sf, "swing", frames, [3, 4], 8.0)
	_anim(sf, "aim", frames, [6], 2.0)
	_anim(sf, "climb", frames, [1, 2], 6.0)
	return sf


func player_meta() -> Dictionary:
	return MiscData.PLAYER
