class_name MenuBackground
extends Control
## The scene behind the main menu: a sky that drifts through the day, clouds sailing over, a strip
## of grass and earth, a couple of trees, and your adventurer (in the chosen hair and scarf colours)
## standing there.

const MiscData = preload("res://scripts/data/misc_data.gd")

var hair: int = 0
var scarf: int = 0
var _t: float = 0.0
var _clouds: Array = []
var _hero: SpriteFrames = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in range(9):
		_clouds.append([randf() * 1600.0 - 160.0, randf_range(30.0, 300.0), randi() % 24, randf_range(8.0, 22.0), randf_range(2.5, 4.5)])
	refresh_hero()


func refresh_hero() -> void:
	_hero = Art.player_frames(hair, scarf)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	for c in _clouds:
		c[0] = float(c[0]) + float(c[3]) * delta
		if float(c[0]) > size.x + 40.0:
			c[0] = -float(int((MiscData.CLOUD_SIZES[int(c[2])] as Array)[0])) * float(c[4]) - 20.0
			c[1] = randf_range(30.0, 300.0)
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	# a slow day: blue noon, warm evening, back again
	var k: float = 0.5 + 0.5 * sin(_t * 0.05)
	var top: Color = Color(0.29, 0.53, 0.85).lerp(Color(0.33, 0.25, 0.5), 1.0 - k)
	var bottom: Color = Color(0.66, 0.83, 0.96).lerp(Color(0.98, 0.62, 0.42), 1.0 - k)
	var bands: int = 24
	for i in range(bands):
		var f: float = float(i) / float(bands - 1)
		draw_rect(Rect2(0, h * float(i) / float(bands), w, h / float(bands) + 1.0), top.lerp(bottom, f))
	draw_texture_rect(Art.tex("res://assets/sky/sun.png"), Rect2(w * 0.78, h * 0.12 + 40.0 * (1.0 - k), 64, 64), false)
	for c in _clouds:
		var ci: int = int(c[2])
		var tex: Texture2D = Art.tex("res://assets/sky/cloud_%02d.png" % ci)
		var s: float = float(c[4])
		draw_texture_rect(tex, Rect2(float(c[0]), float(c[1]), float(tex.get_width()) * s, float(tex.get_height()) * s), false, Color(1, 1, 1, 0.92))
	# the ground: a row of grass over dirt and stone, drawn with the game's own tiles
	var tile: float = 32.0
	var gy: float = h - tile * 3.0
	var grass: Texture2D = Art.tile_texture(T.GRASS)
	var dirt: Texture2D = Art.tile_texture(T.DIRT)
	var stone: Texture2D = Art.tile_texture(T.STONE)
	var x: float = 0.0
	while x < w:
		draw_texture_rect(grass, Rect2(x, gy, tile, tile), false)
		draw_texture_rect(dirt, Rect2(x, gy + tile, tile, tile), false)
		draw_texture_rect(stone, Rect2(x, gy + tile * 2.0, tile, tile), false)
		x += tile
	# two trees
	var trunk: Texture2D = Art.tile_texture(T.LOG)
	var leaves: Texture2D = Art.tile_texture(T.LEAVES)
	for tx in [w * 0.1, w * 0.86]:
		for j in range(4):
			draw_texture_rect(trunk, Rect2(float(tx), gy - tile * float(j + 1), tile, tile), false)
		for ly in range(3):
			for lx in range(-1, 2):
				if ly == 0 and lx != 0:
					continue
				draw_texture_rect(leaves, Rect2(float(tx) + float(lx) * tile, gy - tile * float(7 - ly), tile, tile), false)
	# the hero, standing on the grass
	if _hero != null:
		var frame: Texture2D = _hero.get_frame_texture("idle", 0)
		var px: float = 6.0
		var fw: float = float(frame.get_width()) * px
		var fh: float = float(frame.get_height()) * px
		var foot: float = float(int(MiscData.PLAYER["foot"])) * px
		draw_texture_rect(frame, Rect2(w * 0.2 - fw * 0.5, gy - foot, fw, fh), false)
