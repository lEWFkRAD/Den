class_name Grid
extends Node2D

const TILE_SIZE:     int = 44
const BASE_WIDTH:    int = 12
const BASE_HEIGHT:   int = 12
const TILES_PER_UNIT:int = 1

var grid_width:  int = BASE_WIDTH
var grid_height: int = BASE_HEIGHT
var tiles:       Dictionary = {}
var highlighted: Dictionary = {}   # Vector2i → Color
var flash_tiles: Dictionary = {}   # Vector2i → {color, timer}
var damage_pops: Array      = []   # [{pos, text, color, timer, max_timer}]
var units_ref:   Array       = []
var unit_offsets: Dictionary = {}  # Unit → Vector2 (pixel offset for attack animations)
var sprite_cache: Dictionary = {}  # unit_name_lower → Texture2D
var kip_sprite_cache: Dictionary = {}  # kip_name_lower → Texture2D

func initialize(unit_count: int, _kip_count: int = 0):
	grid_width  = BASE_WIDTH  + unit_count * TILES_PER_UNIT
	grid_height = BASE_HEIGHT + unit_count * TILES_PER_UNIT
	_build_tiles()
	_scatter_terrain()
	_load_sprites()
	queue_redraw()

func _load_sprites():
	# Player character sprites
	var char_names = ["aldric", "mira", "voss", "seren", "bram", "corvin", "yael", "lorn"]
	for cname in char_names:
		var path = "res://assets/portraits/%s_small.png" % cname
		if ResourceLoader.exists(path):
			sprite_cache[cname] = load(path)
	# Kip sprites
	var kip_names = ["scar", "thorn", "bolt", "null", "sleet", "dusk", "solen", "the_first"]
	for kname in kip_names:
		var path = "res://assets/kips/%s_small.png" % kname
		if ResourceLoader.exists(path):
			kip_sprite_cache[kname] = load(path)

func _build_tiles():
	tiles.clear()
	for x in range(grid_width):
		for y in range(grid_height):
			var t     = Tile.new()
			t.grid_pos = Vector2i(x, y)
			tiles[Vector2i(x, y)] = t

func _scatter_terrain():
	var rng = RandomNumberGenerator.new(); rng.seed = 99991
	for x in range(grid_width):
		for y in range(grid_height):
			if x <= 2 and y <= 2:   continue
			if x >= grid_width-3 and y >= grid_height-3: continue
			var roll = rng.randf()
			if   roll < 0.07:
				tiles[Vector2i(x,y)].terrain_type = Tile.TerrainType.FOREST
				# Scatter tree objects on forest tiles
				var tree_roll = rng.randf()
				if tree_roll < 0.4:
					tiles[Vector2i(x,y)].terrain_object = Tile.TerrainObject.TREE_PINE
				elif tree_roll < 0.7:
					tiles[Vector2i(x,y)].terrain_object = Tile.TerrainObject.TREE_OAK
				elif tree_roll < 0.85:
					tiles[Vector2i(x,y)].terrain_object = Tile.TerrainObject.BUSH
			elif roll < 0.11:
				tiles[Vector2i(x,y)].terrain_type = Tile.TerrainType.WATER
				tiles[Vector2i(x,y)].is_passable   = false
			elif roll < 0.14:
				tiles[Vector2i(x,y)].terrain_type = Tile.TerrainType.RUINS
				if rng.randf() < 0.4:
					tiles[Vector2i(x,y)].terrain_object = Tile.TerrainObject.RUINS_PILLAR

func load_chapter_terrain(terrain_data: Array, width: int, height: int):
	# Load terrain from chapter JSON 2D array
	grid_width = width
	grid_height = height
	tiles.clear()
	for x in range(width):
		for y in range(height):
			var t = Tile.new()
			t.grid_pos = Vector2i(x, y)
			if y < terrain_data.size() and x < terrain_data[y].size():
				t.set_terrain(terrain_data[y][x])
			tiles[Vector2i(x, y)] = t

func place_terrain_object(pos: Vector2i, obj_str: String):
	if tiles.has(pos):
		tiles[pos].set_object(obj_str)

func place_object_template(origin: Vector2i, template_id: String):
	var tpl = DataLoader.terrain_objects_data.get(template_id, {})
	var objects: Array = tpl.get("objects", [])
	for obj in objects:
		var off = obj.get("offset", [0, 0])
		var pos = origin + Vector2i(int(off[0]), int(off[1]))
		var obj_type = obj.get("object", "")
		if obj_type != "":
			place_terrain_object(pos, obj_type)

# ─── Drawing ──────────────────────────────────────────────────────────────────

func _draw():
	var font = ThemeDB.fallback_font

	for pos in tiles:
		var tile = tiles[pos]
		var rx   = pos.x * TILE_SIZE + 1
		var ry   = pos.y * TILE_SIZE + 1
		var rect = Rect2(rx, ry, TILE_SIZE - 2, TILE_SIZE - 2)
		draw_rect(rect, tile.get_color())

		# Terrain detail overlay (trees, waves, rubble)
		_draw_terrain_detail(pos, tile, rx, ry)

		# Subtle tile depth: top highlight, bottom shadow
		draw_rect(Rect2(rx, ry, TILE_SIZE - 2, 1), Color(1, 1, 1, 0.04))
		draw_rect(Rect2(rx, ry + TILE_SIZE - 3, TILE_SIZE - 2, 1), Color(0, 0, 0, 0.06))

		# Elemental flash overlay
		if flash_tiles.has(pos):
			draw_rect(rect, flash_tiles[pos]["color"])

		# Highlights (move range, attack range, etc.)
		if highlighted.has(pos):
			draw_rect(rect, highlighted[pos])

	# Grid lines
	var lc = Color(0.0, 0.0, 0.0, 0.25)
	for x in range(grid_width  + 1):
		draw_line(Vector2(x*TILE_SIZE, 0), Vector2(x*TILE_SIZE, grid_height*TILE_SIZE), lc, 1.0)
	for y in range(grid_height + 1):
		draw_line(Vector2(0, y*TILE_SIZE), Vector2(grid_width*TILE_SIZE, y*TILE_SIZE), lc, 1.0)

	# Unit shadows (drawn first, behind everything)
	for unit in units_ref:
		if unit.is_alive():
			_draw_unit_shadow(unit)

	# Units
	for unit in units_ref:
		if unit.is_alive():
			_draw_unit(unit, font)

	# Floating damage numbers
	for pop in damage_pops:
		var alpha = clampf(pop.timer / pop.max_timer * 1.5, 0.0, 1.0)
		var rise  = (1.0 - pop.timer / pop.max_timer) * 18.0
		var px    = pop.pos.x * TILE_SIZE + TILE_SIZE / 2 - 8
		var py    = pop.pos.y * TILE_SIZE - rise
		var col   = pop.color
		col.a     = alpha
		# Shadow
		draw_string(font, Vector2(px + 1, py + 1), pop.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0, 0, 0, alpha * 0.7))
		draw_string(font, Vector2(px, py), pop.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)

func _draw_unit(unit, font):
	var p   = unit.grid_position
	var offset = unit_offsets.get(unit, Vector2.ZERO)
	var ux  = p.x * TILE_SIZE + int(offset.x)
	var uy  = p.y * TILE_SIZE + int(offset.y)
	var pad = 6

	# Try sprite-based rendering first
	var sprite_key = unit.unit_name.to_lower()
	var tex = sprite_cache.get(sprite_key, null)

	if tex != null:
		# Draw sprite scaled into tile with small padding
		var sp = 2  # sprite padding
		var sprite_rect = Rect2(ux + sp, uy + sp, TILE_SIZE - sp * 2, TILE_SIZE - sp * 2)
		# Dim if acted
		if unit.has_acted and unit.is_player_unit:
			draw_texture_rect(tex, sprite_rect, false, Color(0.5, 0.5, 0.6, 0.7))
		else:
			draw_texture_rect(tex, sprite_rect, false)
		# Team color border
		var border_col = Color(0.18, 0.48, 0.92, 0.7) if unit.is_player_unit else Color(0.82, 0.14, 0.14, 0.7)
		if unit.has_acted and unit.is_player_unit:
			border_col = Color(0.3, 0.3, 0.4, 0.5)
		draw_rect(sprite_rect, border_col, false, 1.5)
	else:
		# Fallback: shape-based rendering for enemies / missing sprites
		var col = unit.get_display_color()
		var shape = unit.get_class_shape()
		_draw_unit_shape(ux, uy, pad, col, shape)
		# Unit initial (only for shape-rendered units)
		draw_string(font, Vector2(ux+TILE_SIZE/2-5, uy+TILE_SIZE/2+5),
			unit.unit_name.substr(0,1).to_upper(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1,1,1,0.9))

	# HP bar (improved with border and gradient)
	var hpr  = float(unit.stats.hp) / float(unit.stats.max_hp)
	var bw   = TILE_SIZE - pad*2
	var bh   = 5
	var by   = uy + TILE_SIZE - bh - 3
	draw_rect(Rect2(ux+pad-1, by-1, bw+2, bh+2), Color(0, 0, 0, 0.7))
	draw_rect(Rect2(ux+pad, by, bw, bh), Color(0.06, 0.06, 0.06))
	var bc = Color(0.15, 0.88, 0.15) if hpr > 0.5 else (Color(0.92, 0.58, 0.1) if hpr > 0.25 else Color(0.92, 0.12, 0.12))
	var fill_w = int(bw * hpr)
	if fill_w > 0:
		draw_rect(Rect2(ux+pad, by, fill_w, bh), bc)
		draw_rect(Rect2(ux+pad, by, fill_w, int(bh / 2)), Color(1, 1, 1, 0.15))

	# Kip indicator
	if unit.bonded_kip != null:
		var kip     = unit.bonded_kip
		var dot_pos = Vector2(ux+TILE_SIZE-pad-1, uy+pad+2)
		draw_circle(dot_pos, 5, unit.get_kip_color())
		draw_circle(dot_pos, 5, Color(0,0,0,0.5), false)
		if kip.current_phase == Kip.Phase.DEPLOYED:
			draw_circle(dot_pos, 7, Color(1,1,1,0.55), false)
		elif kip.current_phase == Kip.Phase.AWAKENED:
			draw_circle(dot_pos, 8,  Color(1.0,0.9,0.2,0.9),  false)
			draw_circle(dot_pos, 11, Color(1.0,0.6,0.1,0.45), false)

func _draw_unit_shape(ux: int, uy: int, pad: int, col: Color, shape: String):
	match shape:
		"square":
			var r = Rect2(ux+pad, uy+pad, TILE_SIZE-pad*2, TILE_SIZE-pad*2)
			draw_rect(r, col)
			draw_rect(r, Color(0,0,0,0.6), false, 1.5)
		"square_thick":
			var r = Rect2(ux+pad-2, uy+pad-2, TILE_SIZE-pad*2+4, TILE_SIZE-pad*2+4)
			draw_rect(r, col)
			draw_rect(r, Color(0,0,0,0.7), false, 2.5)
		"diamond":
			var cx = ux + TILE_SIZE/2
			var cy = uy + TILE_SIZE/2
			var pts = PackedVector2Array([
				Vector2(cx, uy+pad),
				Vector2(ux+TILE_SIZE-pad, cy),
				Vector2(cx, uy+TILE_SIZE-pad),
				Vector2(ux+pad, cy)
			])
			draw_colored_polygon(pts, col)
			draw_polyline(PackedVector2Array([pts[0],pts[1],pts[2],pts[3],pts[0]]), Color(0,0,0,0.6), 1.5)
		"circle":
			var cx = ux + TILE_SIZE/2
			var cy = uy + TILE_SIZE/2
			draw_circle(Vector2(cx, cy), TILE_SIZE/2 - pad, col)
			draw_arc(Vector2(cx, cy), TILE_SIZE/2 - pad, 0, TAU, 16, Color(0,0,0,0.6), 1.5)
		"triangle":
			var cx = ux + TILE_SIZE/2
			var pts = PackedVector2Array([
				Vector2(cx, uy+pad),
				Vector2(ux+TILE_SIZE-pad, uy+TILE_SIZE-pad),
				Vector2(ux+pad, uy+TILE_SIZE-pad)
			])
			draw_colored_polygon(pts, col)
			draw_polyline(PackedVector2Array([pts[0],pts[1],pts[2],pts[0]]), Color(0,0,0,0.6), 1.5)
		"cross":
			var t = 10
			var cx = ux+TILE_SIZE/2; var cy = uy+TILE_SIZE/2
			draw_rect(Rect2(cx-t/2, uy+pad, t, TILE_SIZE-pad*2), col)
			draw_rect(Rect2(ux+pad, cy-t/2, TILE_SIZE-pad*2, t), col)
		"star":
			var cx = ux+TILE_SIZE/2; var cy = uy+TILE_SIZE/2
			var ro = TILE_SIZE/2-pad; var ri = ro*0.45
			var pts = PackedVector2Array()
			for i in 10:
				var angle = PI/2 + i * TAU/10
				var r = ro if i%2==0 else ri
				pts.append(Vector2(cx + cos(angle)*r, cy + sin(angle)*r))
			draw_colored_polygon(pts, col)

# ─── Terrain Detail Drawing ───────────────────────────────────────────────────

func _get_road_neighbors(pos: Vector2i) -> Dictionary:
	var result = {"n": false, "s": false, "e": false, "w": false}
	var n = pos + Vector2i(0, -1)
	var s = pos + Vector2i(0, 1)
	var e = pos + Vector2i(1, 0)
	var w = pos + Vector2i(-1, 0)
	if tiles.has(n):
		var tt = tiles[n].terrain_type
		if tt == Tile.TerrainType.ROAD or tt == Tile.TerrainType.BRIDGE:
			result["n"] = true
	if tiles.has(s):
		var tt = tiles[s].terrain_type
		if tt == Tile.TerrainType.ROAD or tt == Tile.TerrainType.BRIDGE:
			result["s"] = true
	if tiles.has(e):
		var tt = tiles[e].terrain_type
		if tt == Tile.TerrainType.ROAD or tt == Tile.TerrainType.BRIDGE:
			result["e"] = true
	if tiles.has(w):
		var tt = tiles[w].terrain_type
		if tt == Tile.TerrainType.ROAD or tt == Tile.TerrainType.BRIDGE:
			result["w"] = true
	return result

func _draw_height_indicator(pos: Vector2i, tile: Tile, rx: int, ry: int):
	var h = tile.height_level
	if h <= 0.0:
		return
	var DIRS = [
		{"d": Vector2i(0, -1), "edge": "top"},
		{"d": Vector2i(0, 1),  "edge": "bottom"},
		{"d": Vector2i(-1, 0), "edge": "left"},
		{"d": Vector2i(1, 0),  "edge": "right"}
	]
	var tw = TILE_SIZE - 2
	for info in DIRS:
		var np = pos + info["d"]
		var nh: float = 0.0
		if tiles.has(np):
			nh = tiles[np].height_level
		var diff = h - nh
		if diff >= 1.0:
			# Draw cliff edge — rocky line along that edge
			var cliff_col = Color(0.15, 0.12, 0.08, 0.55)
			var shadow_col = Color(0.0, 0.0, 0.0, 0.2)
			match info["edge"]:
				"top":
					draw_rect(Rect2(rx, ry, tw, 3), cliff_col)
					draw_rect(Rect2(rx, ry + 3, tw, 2), shadow_col)
					# Rocky texture
					for i in 5:
						var ox = ((pos.x * 3911 + i * 1301) % (tw - 4)) + 2
						draw_rect(Rect2(rx + ox, ry, 2, 2), Color(0.22, 0.18, 0.12, 0.4))
				"bottom":
					draw_rect(Rect2(rx, ry + tw - 3, tw, 3), cliff_col)
					for i in 5:
						var ox = ((pos.x * 3911 + i * 1301) % (tw - 4)) + 2
						draw_rect(Rect2(rx + ox, ry + tw - 2, 2, 2), Color(0.22, 0.18, 0.12, 0.4))
				"left":
					draw_rect(Rect2(rx, ry, 3, tw), cliff_col)
					draw_rect(Rect2(rx + 3, ry, 2, tw), shadow_col)
					for i in 5:
						var oy = ((pos.y * 2731 + i * 1301) % (tw - 4)) + 2
						draw_rect(Rect2(rx, ry + oy, 2, 2), Color(0.22, 0.18, 0.12, 0.4))
				"right":
					draw_rect(Rect2(rx + tw - 3, ry, 3, tw), cliff_col)
					for i in 5:
						var oy = ((pos.y * 2731 + i * 1301) % (tw - 4)) + 2
						draw_rect(Rect2(rx + tw - 2, ry + oy, 2, 2), Color(0.22, 0.18, 0.12, 0.4))
		elif diff <= -1.0:
			# Lower tile — draw shadow along that edge
			var shad = Color(0.0, 0.0, 0.0, 0.15)
			match info["edge"]:
				"top":    draw_rect(Rect2(rx, ry, tw, 3), shad)
				"bottom": draw_rect(Rect2(rx, ry + tw - 3, tw, 3), shad)
				"left":   draw_rect(Rect2(rx, ry, 3, tw), shad)
				"right":  draw_rect(Rect2(rx + tw - 3, ry, 3, tw), shad)
	# Draw uphill chevrons pointing toward higher neighbors
	for info in DIRS:
		var np = pos + info["d"]
		if not tiles.has(np):
			continue
		var nh2 = tiles[np].height_level
		if nh2 > h + 0.5:
			var chev_col = Color(0.4, 0.35, 0.25, 0.35)
			var cx = rx + tw / 2
			var cy = ry + tw / 2
			match info["edge"]:
				"top":
					draw_line(Vector2(cx - 4, cy - 6), Vector2(cx, cy - 10), chev_col, 1.5)
					draw_line(Vector2(cx, cy - 10), Vector2(cx + 4, cy - 6), chev_col, 1.5)
				"bottom":
					draw_line(Vector2(cx - 4, cy + 6), Vector2(cx, cy + 10), chev_col, 1.5)
					draw_line(Vector2(cx, cy + 10), Vector2(cx + 4, cy + 6), chev_col, 1.5)
				"left":
					draw_line(Vector2(cx - 6, cy - 4), Vector2(cx - 10, cy), chev_col, 1.5)
					draw_line(Vector2(cx - 10, cy), Vector2(cx - 6, cy + 4), chev_col, 1.5)
				"right":
					draw_line(Vector2(cx + 6, cy - 4), Vector2(cx + 10, cy), chev_col, 1.5)
					draw_line(Vector2(cx + 10, cy), Vector2(cx + 6, cy + 4), chev_col, 1.5)

func _draw_terrain_detail(pos: Vector2i, tile: Tile, rx: int, ry: int):
	var seed_val = pos.x * 7919 + pos.y * 4391
	var v = tile.terrain_variant

	# Height indicators (always drawn)
	_draw_height_indicator(pos, tile, rx, ry)

	# Draw terrain-type details (unless overridden by elemental state)
	if tile.elemental_state == Tile.ElementalState.NEUTRAL:
		match tile.terrain_type:
			Tile.TerrainType.GRASS:
				match v:
					0: # Short grass tufts — small V-shaped marks
						var c = Color(0.10, 0.20, 0.04, 0.45)
						for i in 6:
							var ox = ((seed_val + i * 2917) % 30) + 4
							var oy = ((seed_val + i * 1723) % 30) + 4
							draw_line(Vector2(rx+ox, ry+oy+4), Vector2(rx+ox+2, ry+oy), c, 1.0)
							draw_line(Vector2(rx+ox+2, ry+oy), Vector2(rx+ox+4, ry+oy+4), c, 1.0)
					1: # Tall grass blades — vertical lines with lean
						var c = Color(0.08, 0.22, 0.04, 0.5)
						for i in 7:
							var ox = ((seed_val + i * 3301) % 32) + 4
							var oy = ((seed_val + i * 1847) % 16) + 20
							var lean = ((seed_val + i * 997) % 5) - 2
							draw_line(Vector2(rx+ox, ry+oy), Vector2(rx+ox+lean, ry+oy-12), c, 1.0)
					2: # Wildflowers — colored dots among green strokes
						var gc = Color(0.10, 0.22, 0.04, 0.4)
						for i in 5:
							var ox = ((seed_val + i * 2917) % 30) + 4
							var oy = ((seed_val + i * 1723) % 28) + 6
							draw_line(Vector2(rx+ox, ry+oy+5), Vector2(rx+ox+1, ry+oy), gc, 1.0)
						var flower_cols = [Color(0.9, 0.85, 0.2, 0.6), Color(0.95, 0.95, 0.9, 0.6), Color(0.6, 0.3, 0.7, 0.6)]
						for i in 4:
							var ox = ((seed_val + i * 4111) % 28) + 6
							var oy = ((seed_val + i * 2339) % 28) + 6
							var fc = flower_cols[i % 3]
							draw_circle(Vector2(rx+ox, ry+oy), 1.5, fc)
					3: # Clover — triple-circle clusters
						var c = Color(0.06, 0.24, 0.06, 0.45)
						for i in 4:
							var ox = ((seed_val + i * 3571) % 28) + 6
							var oy = ((seed_val + i * 2111) % 28) + 6
							draw_circle(Vector2(rx+ox-2, ry+oy), 2.5, c)
							draw_circle(Vector2(rx+ox+2, ry+oy), 2.5, c)
							draw_circle(Vector2(rx+ox, ry+oy-2), 2.5, c)
					4: # Mixed pebbles with short grass
						var gc = Color(0.10, 0.20, 0.04, 0.35)
						for i in 4:
							var ox = ((seed_val + i * 2917) % 30) + 4
							var oy = ((seed_val + i * 1723) % 30) + 4
							draw_line(Vector2(rx+ox, ry+oy+3), Vector2(rx+ox+1, ry+oy), gc, 1.0)
						var pc = Color(0.32, 0.30, 0.26, 0.4)
						for i in 3:
							var ox = ((seed_val + i * 4793) % 28) + 6
							var oy = ((seed_val + i * 3109) % 28) + 6
							draw_rect(Rect2(rx+ox, ry+oy, 3, 2), pc)

			Tile.TerrainType.DIRT:
				match v:
					0: # Packed earth with thin cracks
						var c = Color(0.18, 0.14, 0.08, 0.35)
						draw_line(Vector2(rx+10, ry+12), Vector2(rx+22, ry+20), c, 1.0)
						draw_line(Vector2(rx+22, ry+20), Vector2(rx+18, ry+32), c, 1.0)
						draw_line(Vector2(rx+22, ry+20), Vector2(rx+34, ry+26), c, 1.0)
					1: # Loose soil with tiny pebble dots
						var c = Color(0.22, 0.18, 0.10, 0.35)
						for i in 8:
							var ox = ((seed_val + i * 2477) % 32) + 4
							var oy = ((seed_val + i * 1913) % 32) + 4
							draw_circle(Vector2(rx+ox, ry+oy), 1.0, c)
					2: # Cart wheel tracks
						var c = Color(0.20, 0.16, 0.09, 0.3)
						var pts1 = PackedVector2Array()
						var pts2 = PackedVector2Array()
						for seg in 8:
							var px = rx + 4 + seg * 5
							var py1 = ry + 16 + sin(float(seg) * 0.5) * 2.0
							var py2 = ry + 26 + sin(float(seg) * 0.5) * 2.0
							pts1.append(Vector2(px, py1))
							pts2.append(Vector2(px, py2))
						if pts1.size() > 1:
							draw_polyline(pts1, c, 1.5)
							draw_polyline(pts2, c, 1.5)
					3: # Muddy patches — darker ovals
						var c = Color(0.18, 0.14, 0.08, 0.35)
						for i in 3:
							var ox = ((seed_val + i * 3733) % 24) + 6
							var oy = ((seed_val + i * 2099) % 24) + 8
							var sw = 6 + ((seed_val + i * 1571) % 4)
							var sh = 4 + ((seed_val + i * 1031) % 3)
							draw_rect(Rect2(rx+ox, ry+oy, sw, sh), c)
					4: # Rocky earth — small angular shapes
						var c = Color(0.24, 0.20, 0.14, 0.4)
						for i in 5:
							var ox = ((seed_val + i * 3137) % 28) + 5
							var oy = ((seed_val + i * 2269) % 28) + 5
							var sw = 3 + ((seed_val + i * 1093) % 3)
							var sh = 2 + ((seed_val + i * 2741) % 3)
							draw_rect(Rect2(rx+ox, ry+oy, sw, sh), c)

			Tile.TerrainType.STONE:
				match v:
					0: # Flagstone grid — rectangles in offset rows
						var c = Color(0.22, 0.20, 0.18, 0.3)
						for row in 3:
							var off = 0 if row % 2 == 0 else 7
							for col_i in 3:
								draw_rect(Rect2(rx+3+off+col_i*13, ry+3+row*13, 11, 11), c, false, 1.0)
					1: # Cobblestones — small rounded rectangles
						var c = Color(0.24, 0.22, 0.20, 0.3)
						for i in 8:
							var ox = ((seed_val + i * 2917) % 28) + 4
							var oy = ((seed_val + i * 1723) % 28) + 4
							draw_rect(Rect2(rx+ox, ry+oy, 5, 4), c)
							draw_rect(Rect2(rx+ox, ry+oy, 5, 4), Color(0.18, 0.16, 0.14, 0.25), false, 1.0)
					2: # Cracked stone — random crack lines from center
						var c = Color(0.18, 0.16, 0.14, 0.35)
						var cx = rx + 21; var cy = ry + 21
						for i in 4:
							var angle = float((seed_val + i * 1571) % 628) / 100.0
							var len_v = 8 + ((seed_val + i * 997) % 8)
							var ex = cx + int(cos(angle) * len_v)
							var ey = cy + int(sin(angle) * len_v)
							draw_line(Vector2(cx, cy), Vector2(ex, ey), c, 1.0)
					3: # Mossy stone — green-tinted circles on gray
						var mc = Color(0.15, 0.28, 0.10, 0.35)
						for i in 5:
							var ox = ((seed_val + i * 3301) % 28) + 6
							var oy = ((seed_val + i * 1847) % 28) + 6
							draw_circle(Vector2(rx+ox, ry+oy), 3 + ((seed_val + i) % 2), mc)
					4: # Worn smooth — lighter oval in center
						var c = Color(0.38, 0.36, 0.34, 0.25)
						draw_rect(Rect2(rx+12, ry+14, 18, 14), c)
						draw_rect(Rect2(rx+14, ry+12, 14, 18), c)

			Tile.TerrainType.SNOW:
				match v:
					0: # Fresh snow with sparkle dots
						for i in 6:
							var ox = ((seed_val + i * 2477) % 30) + 4
							var oy = ((seed_val + i * 1913) % 30) + 4
							var sc = Color(1.0, 1.0, 1.0, 0.3) if i % 2 == 0 else Color(0.75, 0.85, 1.0, 0.25)
							draw_circle(Vector2(rx+ox, ry+oy), 1.0, sc)
					1: # Packed snow — subtle horizontal lines
						var c = Color(0.75, 0.78, 0.82, 0.2)
						for i in 4:
							var py = ry + 8 + i * 9
							draw_line(Vector2(rx+4, py), Vector2(rx+TILE_SIZE-6, py), c, 1.0)
					2: # Snow with ice patches — blue-white ovals
						var c = Color(0.65, 0.78, 0.92, 0.3)
						for i in 3:
							var ox = ((seed_val + i * 3571) % 22) + 8
							var oy = ((seed_val + i * 2111) % 22) + 8
							draw_rect(Rect2(rx+ox, ry+oy, 8, 5), c)
					3: # Windblown snow — diagonal streaks
						var c = Color(0.88, 0.90, 0.95, 0.25)
						for i in 5:
							var ox = ((seed_val + i * 2917) % 26) + 4
							var oy = ((seed_val + i * 1723) % 20) + 8
							draw_line(Vector2(rx+ox, ry+oy), Vector2(rx+ox+8, ry+oy-4), c, 1.0)
					4: # Snowdrift — curved mound with shadow
						var mound = Color(0.90, 0.92, 0.96, 0.3)
						var shad = Color(0.60, 0.65, 0.72, 0.2)
						var pts = PackedVector2Array([
							Vector2(rx+6, ry+32), Vector2(rx+12, ry+22),
							Vector2(rx+22, ry+18), Vector2(rx+32, ry+22),
							Vector2(rx+38, ry+32)
						])
						draw_colored_polygon(pts, mound)
						draw_line(Vector2(rx+6, ry+32), Vector2(rx+38, ry+32), shad, 1.5)

			Tile.TerrainType.ROCK:
				match v:
					0: # Solid dark rock face — layered rectangles
						var c = Color(0.16, 0.14, 0.12, 0.4)
						draw_rect(Rect2(rx+4, ry+6, 34, 10), c)
						draw_rect(Rect2(rx+6, ry+16, 30, 10), Color(0.14, 0.12, 0.10, 0.35))
						draw_rect(Rect2(rx+4, ry+26, 34, 10), c)
					1: # Layered sediment — horizontal parallel lines
						var c = Color(0.18, 0.16, 0.14, 0.35)
						for i in 6:
							var py = ry + 5 + i * 6
							var c2 = c if i % 2 == 0 else Color(0.20, 0.18, 0.15, 0.3)
							draw_line(Vector2(rx+4, py), Vector2(rx+TILE_SIZE-6, py), c2, 1.5)
					2: # Fractured rock — angular crack patterns
						var c = Color(0.12, 0.10, 0.08, 0.4)
						draw_line(Vector2(rx+8, ry+6), Vector2(rx+22, ry+22), c, 1.0)
						draw_line(Vector2(rx+22, ry+22), Vector2(rx+36, ry+14), c, 1.0)
						draw_line(Vector2(rx+22, ry+22), Vector2(rx+14, ry+36), c, 1.0)
						draw_line(Vector2(rx+22, ry+22), Vector2(rx+34, ry+34), c, 1.0)
					3: # Lichen-covered — colored patches
						var cols = [Color(0.45, 0.55, 0.15, 0.35), Color(0.65, 0.45, 0.10, 0.30)]
						for i in 5:
							var ox = ((seed_val + i * 3301) % 26) + 6
							var oy = ((seed_val + i * 1847) % 26) + 6
							draw_circle(Vector2(rx+ox, ry+oy), 3, cols[i % 2])
					4: # Volcanic/porous — small holes
						var c = Color(0.08, 0.06, 0.04, 0.45)
						for i in 7:
							var ox = ((seed_val + i * 2477) % 30) + 4
							var oy = ((seed_val + i * 1913) % 30) + 4
							var r = 1.5 + float((seed_val + i * 997) % 3) * 0.5
							draw_circle(Vector2(rx+ox, ry+oy), r, c)

			Tile.TerrainType.ICE:
				match v:
					0: # Smooth ice — thin reflection lines at angles
						var c = Color(0.70, 0.85, 1.0, 0.25)
						draw_line(Vector2(rx+6, ry+10), Vector2(rx+18, ry+16), c, 1.0)
						draw_line(Vector2(rx+24, ry+8), Vector2(rx+36, ry+14), c, 1.0)
						draw_line(Vector2(rx+10, ry+28), Vector2(rx+28, ry+34), c, 1.0)
					1: # Cracked ice — web of thin cracks from center
						var c = Color(0.40, 0.55, 0.70, 0.35)
						var cx = rx + 21; var cy = ry + 21
						for i in 5:
							var angle = float((seed_val + i * 1259) % 628) / 100.0
							var len_v = 8 + ((seed_val + i * 743) % 10)
							var ex = cx + int(cos(angle) * len_v)
							var ey = cy + int(sin(angle) * len_v)
							draw_line(Vector2(cx, cy), Vector2(ex, ey), c, 1.0)
					2: # Frozen bubbles — small circles trapped
						var c = Color(0.65, 0.80, 0.95, 0.25)
						for i in 6:
							var ox = ((seed_val + i * 3571) % 28) + 6
							var oy = ((seed_val + i * 2111) % 28) + 6
							var r = 1.5 + float((seed_val + i * 997) % 3) * 0.5
							draw_circle(Vector2(rx+ox, ry+oy), r, c)
					3: # Ice crystals — small star/asterisk shapes
						var c = Color(0.70, 0.85, 1.0, 0.35)
						for i in 4:
							var ox = ((seed_val + i * 4111) % 26) + 8
							var oy = ((seed_val + i * 2339) % 26) + 8
							var cx2 = rx + ox; var cy2 = ry + oy
							draw_line(Vector2(cx2-3, cy2), Vector2(cx2+3, cy2), c, 1.0)
							draw_line(Vector2(cx2, cy2-3), Vector2(cx2, cy2+3), c, 1.0)
							draw_line(Vector2(cx2-2, cy2-2), Vector2(cx2+2, cy2+2), c, 1.0)
							draw_line(Vector2(cx2+2, cy2-2), Vector2(cx2-2, cy2+2), c, 1.0)
					4: # Frosted — edge frost pattern, clear center
						var c = Color(0.80, 0.90, 1.0, 0.3)
						for i in 10:
							var side = i % 4
							var off_v = ((seed_val + i * 1301) % 30) + 4
							match side:
								0: draw_circle(Vector2(rx+off_v, ry+3), 2, c)
								1: draw_circle(Vector2(rx+off_v, ry+TILE_SIZE-5), 2, c)
								2: draw_circle(Vector2(rx+3, ry+off_v), 2, c)
								3: draw_circle(Vector2(rx+TILE_SIZE-5, ry+off_v), 2, c)

			Tile.TerrainType.WATER:
				# Enhanced water with multiple wave layers and foam
				var deep_col = Color(0.15, 0.28, 0.58, 0.3)
				var wave_col = Color(0.22, 0.38, 0.70, 0.25)
				var foam_col = Color(0.55, 0.65, 0.80, 0.3)
				# Darker center
				draw_rect(Rect2(rx+8, ry+8, TILE_SIZE-18, TILE_SIZE-18), deep_col)
				# Wave layers
				for w in 3:
					var base_y = ry + 8 + w * 11
					var points = PackedVector2Array()
					for seg in 9:
						var px = rx + seg * 5
						var py = base_y + sin(float(seg + seed_val % 6 + w) * 1.2) * 3.0
						points.append(Vector2(px, py))
					if points.size() > 1:
						draw_polyline(points, wave_col if w != 1 else foam_col, 1.5)
				# Edge detection — draw foam where adjacent to non-water
				var edge_dirs = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
				for d in edge_dirs:
					var np = pos + d
					if tiles.has(np) and tiles[np].terrain_type != Tile.TerrainType.WATER:
						var shore = Color(0.45, 0.58, 0.75, 0.35)
						if d == Vector2i(0, -1):   draw_rect(Rect2(rx, ry, TILE_SIZE-2, 3), shore)
						elif d == Vector2i(0, 1):  draw_rect(Rect2(rx, ry+TILE_SIZE-5, TILE_SIZE-2, 3), shore)
						elif d == Vector2i(-1, 0): draw_rect(Rect2(rx, ry, 3, TILE_SIZE-2), shore)
						elif d == Vector2i(1, 0):  draw_rect(Rect2(rx+TILE_SIZE-5, ry, 3, TILE_SIZE-2), shore)

			Tile.TerrainType.OPEN:
				# Sparse muted grass-like details
				var c = Color(0.10, 0.14, 0.06, 0.25)
				for i in 4:
					var ox = ((seed_val + i * 2917) % 30) + 4
					var oy = ((seed_val + i * 1723) % 30) + 4
					draw_line(Vector2(rx+ox, ry+oy+3), Vector2(rx+ox+1, ry+oy), c, 1.0)

			Tile.TerrainType.FOREST:
				var dark = Color(0.06, 0.24, 0.04, 0.6)
				var under = Color(0.04, 0.16, 0.02, 0.35)
				# Ground cover
				for i in 5:
					var ox = ((seed_val + i * 4793) % 32) + 3
					var oy = ((seed_val + i * 3109) % 32) + 3
					draw_circle(Vector2(rx+ox, ry+oy), 2, under)
				# Tree canopy shadows
				for i in 3:
					var ox = ((seed_val + i * 2917) % 26) + 5
					var oy = ((seed_val + i * 1723) % 22) + 6
					var sz = 5 + ((seed_val + i * 3571) % 4)
					var pts = PackedVector2Array([
						Vector2(rx + ox, ry + oy),
						Vector2(rx + ox - sz / 2, ry + oy + sz),
						Vector2(rx + ox + sz / 2, ry + oy + sz)
					])
					draw_colored_polygon(pts, dark)

			Tile.TerrainType.RUINS:
				var rubble = Color(0.44, 0.38, 0.30, 0.45)
				var crack = Color(0.30, 0.26, 0.20, 0.3)
				for i in 4:
					var ox = ((seed_val + i * 3137) % 28) + 5
					var oy = ((seed_val + i * 2269) % 28) + 5
					var sw = 3 + ((seed_val + i * 1093) % 5)
					var sh = 2 + ((seed_val + i * 2741) % 4)
					draw_rect(Rect2(rx + ox, ry + oy, sw, sh), rubble)
				# Cracks in ground
				draw_line(Vector2(rx+8, ry+14), Vector2(rx+20, ry+28), crack, 1.0)
				draw_line(Vector2(rx+26, ry+10), Vector2(rx+34, ry+22), crack, 1.0)

			Tile.TerrainType.RIVER:
				var river_col = Color(0.25, 0.45, 0.75, 0.35)
				var flow_col  = Color(0.35, 0.55, 0.85, 0.25)
				for w in 3:
					var base_y = ry + 8 + w * 12
					var pts = PackedVector2Array()
					for seg in 9:
						var px = rx + seg * 5
						var py = base_y + sin(float(seg + seed_val % 5) * 0.9 + float(w)) * 2.5
						pts.append(Vector2(px, py))
					if pts.size() > 1:
						draw_polyline(pts, river_col if w != 1 else flow_col, 1.5)

			Tile.TerrainType.BRIDGE:
				var plank_col = Color(0.45, 0.32, 0.15, 0.5)
				var grain_col = Color(0.35, 0.24, 0.10, 0.3)
				for i in 4:
					var py = ry + 6 + i * 10
					draw_rect(Rect2(rx + 4, py, TILE_SIZE - 8, 3), plank_col)
					# Wood grain
					draw_line(Vector2(rx+6, py+1), Vector2(rx+TILE_SIZE-8, py+1), grain_col, 1.0)
				var rail_col = Color(0.35, 0.25, 0.10, 0.4)
				draw_rect(Rect2(rx + 2, ry + 2, 2, TILE_SIZE - 4), rail_col)
				draw_rect(Rect2(rx + TILE_SIZE - 4, ry + 2, 2, TILE_SIZE - 4), rail_col)

			Tile.TerrainType.ROAD:
				_draw_road_autotile(pos, rx, ry)

			Tile.TerrainType.VILLAGE:
				# Enhanced village with shadows and window glow
				var house_col = Color(0.35, 0.30, 0.20, 0.4)
				var shadow_col = Color(0.0, 0.0, 0.0, 0.15)
				# Ground shadow
				draw_rect(Rect2(rx + 12, ry + 34, 24, 3), shadow_col)
				# Walls with brick texture
				draw_rect(Rect2(rx + 10, ry + 16, 24, 18), house_col)
				var brick = Color(0.30, 0.25, 0.16, 0.25)
				for row in 3:
					var off = 0 if row % 2 == 0 else 4
					for col_i in 3:
						draw_rect(Rect2(rx+11+off+col_i*8, ry+17+row*6, 6, 4), brick, false, 1.0)
				# Roof with gradient
				var roof_pts = PackedVector2Array([
					Vector2(rx + 8, ry + 16), Vector2(rx + 22, ry + 6), Vector2(rx + 36, ry + 16)
				])
				draw_colored_polygon(roof_pts, Color(0.45, 0.20, 0.10, 0.5))
				# Roof ridge highlight
				draw_line(Vector2(rx+15, ry+11), Vector2(rx+22, ry+7), Color(0.55, 0.30, 0.15, 0.4), 1.0)
				# Window glow
				draw_rect(Rect2(rx + 12, ry + 22, 4, 4), Color(0.85, 0.75, 0.35, 0.55))

			Tile.TerrainType.FORT:
				# Enhanced fort with brick texture and shadows
				var fort_col = Color(0.35, 0.32, 0.25, 0.4)
				var shadow_col = Color(0.0, 0.0, 0.0, 0.15)
				# Ground shadow
				draw_rect(Rect2(rx + 8, ry + 36, 32, 3), shadow_col)
				# Main wall
				draw_rect(Rect2(rx + 6, ry + 8, 32, 28), fort_col)
				# Stone blocks
				var stone = Color(0.28, 0.25, 0.20, 0.25)
				for row in 3:
					var off = 0 if row % 2 == 0 else 5
					for col_i in 3:
						draw_rect(Rect2(rx+7+off+col_i*10, ry+9+row*9, 8, 7), stone, false, 1.0)
				# Crenellations
				for i in 4:
					draw_rect(Rect2(rx + 6 + i * 9, ry + 4, 5, 6), fort_col)
				# Window glow
				draw_rect(Rect2(rx + 18, ry + 18, 4, 6), Color(0.85, 0.75, 0.35, 0.45))
				draw_rect(Rect2(rx + 26, ry + 18, 4, 6), Color(0.85, 0.75, 0.35, 0.45))

			Tile.TerrainType.THRONE:
				var throne_col = Color(0.65, 0.50, 0.15, 0.5)
				draw_rect(Rect2(rx + 14, ry + 12, 16, 22), throne_col)
				draw_rect(Rect2(rx + 12, ry + 6, 20, 8), throne_col)
				# Ornate top
				draw_rect(Rect2(rx + 11, ry + 4, 2, 6), Color(0.70, 0.55, 0.20, 0.5))
				draw_rect(Rect2(rx + 31, ry + 4, 2, 6), Color(0.70, 0.55, 0.20, 0.5))
				# Gem
				draw_circle(Vector2(rx + 22, ry + 10), 3, Color(0.9, 0.2, 0.2, 0.6))
				# Cushion
				draw_rect(Rect2(rx + 16, ry + 24, 12, 6), Color(0.5, 0.12, 0.12, 0.45))

			Tile.TerrainType.SAND:
				var sand_col = Color(0.6, 0.52, 0.30, 0.25)
				for i in 5:
					var ox = ((seed_val + i * 1999) % 30) + 5
					var oy = ((seed_val + i * 3121) % 30) + 5
					draw_circle(Vector2(rx + ox, ry + oy), 1.5, sand_col)
				# Wind ripples
				var ripple = Color(0.55, 0.48, 0.28, 0.2)
				for i in 3:
					var py = ry + 10 + i * 10
					draw_line(Vector2(rx+6, py), Vector2(rx+TILE_SIZE-8, py + 2), ripple, 1.0)

			Tile.TerrainType.LAVA:
				var lava_col = Color(1.0, 0.4, 0.0, 0.4)
				for i in 3:
					var ox = ((seed_val + i * 2333) % 28) + 6
					var oy = ((seed_val + i * 1777) % 28) + 6
					draw_circle(Vector2(rx + ox, ry + oy), 3 + ((seed_val + i) % 3), lava_col)
				var crack_col = Color(1.0, 0.6, 0.1, 0.35)
				draw_line(Vector2(rx + 8, ry + 12), Vector2(rx + 20, ry + 30), crack_col, 1.5)
				draw_line(Vector2(rx + 28, ry + 8), Vector2(rx + 18, ry + 25), crack_col, 1.5)
				# Glow around cracks
				var glow = Color(1.0, 0.8, 0.2, 0.15)
				draw_line(Vector2(rx + 7, ry + 11), Vector2(rx + 19, ry + 29), glow, 3.0)

			Tile.TerrainType.WALL:
				var stone_col = Color(0.28, 0.26, 0.22, 0.4)
				var mortar = Color(0.20, 0.18, 0.15, 0.25)
				for row in 3:
					var off = 0 if row % 2 == 0 else 10
					for col_i in 3:
						var bx = rx + 4 + off + col_i * 14
						var by = ry + 4 + row * 13
						draw_rect(Rect2(bx, by, 12, 11), stone_col)
						draw_rect(Rect2(bx, by, 12, 11), mortar, false, 1.0)

			Tile.TerrainType.ELEVATION:
				var mt_col = Color(0.50, 0.44, 0.32, 0.4)
				var peak_pts = PackedVector2Array([
					Vector2(rx + 10, ry + 32), Vector2(rx + 22, ry + 8), Vector2(rx + 34, ry + 32)
				])
				draw_colored_polygon(peak_pts, mt_col)
				# Rock texture lines
				draw_line(Vector2(rx+14, ry+26), Vector2(rx+20, ry+18), Color(0.40, 0.35, 0.25, 0.3), 1.0)
				draw_line(Vector2(rx+24, ry+20), Vector2(rx+30, ry+28), Color(0.40, 0.35, 0.25, 0.3), 1.0)
				# Snow cap
				var snow_pts = PackedVector2Array([
					Vector2(rx + 18, ry + 14), Vector2(rx + 22, ry + 8), Vector2(rx + 26, ry + 14)
				])
				draw_colored_polygon(snow_pts, Color(0.8, 0.82, 0.85, 0.5))

	# Draw terrain objects (always visible regardless of elemental state)
	_draw_terrain_object(tile, rx, ry, seed_val)

func _draw_road_autotile(pos: Vector2i, rx: int, ry: int):
	var nb = _get_road_neighbors(pos)
	var count = 0
	if nb["n"]: count += 1
	if nb["s"]: count += 1
	if nb["e"]: count += 1
	if nb["w"]: count += 1

	var road_fill = Color(0.28, 0.26, 0.20, 0.3)
	var road_edge = Color(0.20, 0.18, 0.14, 0.4)
	var dash_col = Color(0.34, 0.32, 0.26, 0.3)
	var cx = rx + TILE_SIZE / 2 - 1
	var cy = ry + TILE_SIZE / 2 - 1
	var rw = 14  # road half-width from center
	var tw = TILE_SIZE - 2

	if count == 0:
		# Isolated — square patch
		draw_rect(Rect2(cx - 8, cy - 8, 16, 16), road_fill)
		draw_rect(Rect2(cx - 8, cy - 8, 16, 16), road_edge, false, 1.0)
	elif count == 4:
		# Crossroads
		draw_rect(Rect2(rx, cy - rw/2, tw, rw), road_fill)
		draw_rect(Rect2(cx - rw/2, ry, rw, tw), road_fill)
		# Edge lines
		draw_line(Vector2(rx, cy - rw/2), Vector2(cx - rw/2, cy - rw/2), road_edge, 1.0)
		draw_line(Vector2(cx + rw/2, cy - rw/2), Vector2(rx + tw, cy - rw/2), road_edge, 1.0)
		draw_line(Vector2(rx, cy + rw/2), Vector2(cx - rw/2, cy + rw/2), road_edge, 1.0)
		draw_line(Vector2(cx + rw/2, cy + rw/2), Vector2(rx + tw, cy + rw/2), road_edge, 1.0)
		# Center marking
		draw_circle(Vector2(cx, cy), 2, dash_col)
	else:
		# Draw road segments toward each connected neighbor
		if nb["n"]:
			draw_rect(Rect2(cx - rw/2, ry, rw, tw/2 + rw/2), road_fill)
			draw_line(Vector2(cx - rw/2, ry), Vector2(cx - rw/2, cy), road_edge, 1.0)
			draw_line(Vector2(cx + rw/2, ry), Vector2(cx + rw/2, cy), road_edge, 1.0)
		if nb["s"]:
			draw_rect(Rect2(cx - rw/2, cy - rw/2, rw, tw/2 + rw/2), road_fill)
			draw_line(Vector2(cx - rw/2, cy), Vector2(cx - rw/2, ry + tw), road_edge, 1.0)
			draw_line(Vector2(cx + rw/2, cy), Vector2(cx + rw/2, ry + tw), road_edge, 1.0)
		if nb["e"]:
			draw_rect(Rect2(cx - rw/2, cy - rw/2, tw/2 + rw/2, rw), road_fill)
			draw_line(Vector2(cx, cy - rw/2), Vector2(rx + tw, cy - rw/2), road_edge, 1.0)
			draw_line(Vector2(cx, cy + rw/2), Vector2(rx + tw, cy + rw/2), road_edge, 1.0)
		if nb["w"]:
			draw_rect(Rect2(rx, cy - rw/2, tw/2 + rw/2, rw), road_fill)
			draw_line(Vector2(rx, cy - rw/2), Vector2(cx, cy - rw/2), road_edge, 1.0)
			draw_line(Vector2(rx, cy + rw/2), Vector2(cx, cy + rw/2), road_edge, 1.0)

		# Center junction fill
		draw_rect(Rect2(cx - rw/2, cy - rw/2, rw, rw), road_fill)

		# Dead end — rounded terminus on unconnected side
		if count == 1:
			if not nb["n"]:
				draw_line(Vector2(cx - rw/2, cy - rw/2), Vector2(cx + rw/2, cy - rw/2), road_edge, 1.0)
			if not nb["s"]:
				draw_line(Vector2(cx - rw/2, cy + rw/2), Vector2(cx + rw/2, cy + rw/2), road_edge, 1.0)
			if not nb["e"]:
				draw_line(Vector2(cx + rw/2, cy - rw/2), Vector2(cx + rw/2, cy + rw/2), road_edge, 1.0)
			if not nb["w"]:
				draw_line(Vector2(cx - rw/2, cy - rw/2), Vector2(cx - rw/2, cy + rw/2), road_edge, 1.0)

		# Center dashes for straight sections
		if count == 2:
			if nb["n"] and nb["s"]:
				for i in 3:
					draw_rect(Rect2(cx - 1, ry + 4 + i * 14, 2, 6), dash_col)
			elif nb["e"] and nb["w"]:
				for i in 3:
					draw_rect(Rect2(rx + 4 + i * 14, cy - 1, 6, 2), dash_col)

func _draw_terrain_object(tile: Tile, rx: int, ry: int, seed_val: int):
	match tile.terrain_object:
		Tile.TerrainObject.NONE: return

		Tile.TerrainObject.TREE_PINE:
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			draw_circle(Vector2(rx + 24, ry + 34), 8, shadow)
			var trunk = Color(0.35, 0.22, 0.08, 0.7)
			var bark = Color(0.28, 0.18, 0.06, 0.5)
			var leaves = Color(0.08, 0.30, 0.06, 0.75)
			var light_leaves = Color(0.12, 0.38, 0.10, 0.6)
			draw_rect(Rect2(rx + 20, ry + 26, 4, 12), trunk)
			# Bark texture
			draw_line(Vector2(rx+21, ry+28), Vector2(rx+21, ry+36), bark, 1.0)
			for i in 3:
				var w = 16 - i * 4
				var h = 10
				var ty = ry + 6 + i * 7
				var pts = PackedVector2Array([
					Vector2(rx + 22, ty), Vector2(rx + 22 - w/2, ty + h), Vector2(rx + 22 + w/2, ty + h)
				])
				draw_colored_polygon(pts, leaves)
				# Light highlight on left side
				if w > 8:
					var hpts = PackedVector2Array([
						Vector2(rx + 22, ty + 1), Vector2(rx + 22 - w/4, ty + h - 1), Vector2(rx + 22, ty + h - 1)
					])
					draw_colored_polygon(hpts, light_leaves)

		Tile.TerrainObject.TREE_OAK:
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			draw_circle(Vector2(rx + 24, ry + 34), 10, shadow)
			var trunk = Color(0.32, 0.20, 0.06, 0.7)
			var canopy = Color(0.12, 0.32, 0.08, 0.75)
			var highlight = Color(0.18, 0.40, 0.14, 0.5)
			draw_rect(Rect2(rx + 19, ry + 24, 6, 14), trunk)
			# Bark detail
			draw_line(Vector2(rx+20, ry+26), Vector2(rx+20, ry+36), Color(0.25, 0.16, 0.04, 0.4), 1.0)
			draw_line(Vector2(rx+23, ry+25), Vector2(rx+23, ry+36), Color(0.25, 0.16, 0.04, 0.4), 1.0)
			draw_circle(Vector2(rx + 22, ry + 18), 12, canopy)
			draw_circle(Vector2(rx + 16, ry + 20), 8, canopy)
			draw_circle(Vector2(rx + 28, ry + 20), 8, canopy)
			# Light highlights
			draw_circle(Vector2(rx + 18, ry + 15), 5, highlight)
			draw_circle(Vector2(rx + 26, ry + 17), 4, highlight)

		Tile.TerrainObject.TREE_DEAD:
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			draw_rect(Rect2(rx + 22, ry + 36, 10, 2), shadow)
			var trunk = Color(0.28, 0.22, 0.16, 0.65)
			var bark = Color(0.22, 0.18, 0.12, 0.45)
			draw_rect(Rect2(rx + 20, ry + 14, 4, 24), trunk)
			# Bark texture
			draw_line(Vector2(rx+21, ry+16), Vector2(rx+21, ry+36), bark, 1.0)
			# Bare branches
			draw_line(Vector2(rx + 22, ry + 18), Vector2(rx + 32, ry + 10), trunk, 2.0)
			draw_line(Vector2(rx + 22, ry + 22), Vector2(rx + 12, ry + 14), trunk, 2.0)
			draw_line(Vector2(rx + 22, ry + 16), Vector2(rx + 28, ry + 6), trunk, 1.5)
			# Twig ends
			draw_line(Vector2(rx + 32, ry + 10), Vector2(rx + 35, ry + 8), bark, 1.0)
			draw_line(Vector2(rx + 12, ry + 14), Vector2(rx + 9, ry + 12), bark, 1.0)

		Tile.TerrainObject.BUSH:
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			draw_circle(Vector2(rx + 23, ry + 30), 8, shadow)
			var bush_col = Color(0.10, 0.30, 0.08, 0.6)
			var highlight = Color(0.16, 0.38, 0.12, 0.4)
			draw_circle(Vector2(rx + 16, ry + 28), 7, bush_col)
			draw_circle(Vector2(rx + 28, ry + 26), 8, bush_col)
			draw_circle(Vector2(rx + 22, ry + 22), 6, bush_col)
			# Highlights
			draw_circle(Vector2(rx + 20, ry + 21), 3, highlight)
			# Berry dots
			if seed_val % 3 == 0:
				draw_circle(Vector2(rx + 18, ry + 26), 1.5, Color(0.7, 0.15, 0.1, 0.5))
				draw_circle(Vector2(rx + 26, ry + 24), 1.5, Color(0.7, 0.15, 0.1, 0.5))

		Tile.TerrainObject.HOUSE:
			var wall_col = Color(0.40, 0.35, 0.25, 0.7)
			var roof_col = Color(0.50, 0.22, 0.08, 0.7)
			var roof_light = Color(0.58, 0.28, 0.12, 0.5)
			var door_col = Color(0.25, 0.18, 0.08, 0.8)
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			# Ground shadow
			draw_rect(Rect2(rx + 10, ry + 36, 28, 3), shadow)
			# Walls
			draw_rect(Rect2(rx + 8, ry + 18, 28, 18), wall_col)
			# Brick texture
			var brick = Color(0.35, 0.28, 0.18, 0.25)
			for row in 3:
				var off = 0 if row % 2 == 0 else 5
				for col_i in 3:
					draw_rect(Rect2(rx+9+off+col_i*9, ry+19+row*6, 7, 4), brick, false, 1.0)
			# Roof
			var roof_pts = PackedVector2Array([
				Vector2(rx + 5, ry + 18), Vector2(rx + 22, ry + 6), Vector2(rx + 39, ry + 18)
			])
			draw_colored_polygon(roof_pts, roof_col)
			# Roof ridge highlight
			draw_line(Vector2(rx+13, ry+12), Vector2(rx+22, ry+7), roof_light, 1.5)
			# Door
			draw_rect(Rect2(rx + 18, ry + 26, 8, 10), door_col)
			# Door handle
			draw_circle(Vector2(rx + 24, ry + 31), 1, Color(0.6, 0.55, 0.3, 0.6))
			# Window glow
			draw_rect(Rect2(rx + 12, ry + 22, 4, 4), Color(0.85, 0.75, 0.35, 0.55))
			draw_rect(Rect2(rx + 30, ry + 22, 4, 4), Color(0.85, 0.75, 0.35, 0.55))

		Tile.TerrainObject.TOWER:
			var stone = Color(0.35, 0.32, 0.28, 0.75)
			var top = Color(0.28, 0.25, 0.22, 0.7)
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			# Ground shadow
			draw_rect(Rect2(rx + 16, ry + 38, 16, 3), shadow)
			# Main body
			draw_rect(Rect2(rx + 14, ry + 10, 16, 28), stone)
			# Stone block texture
			var block = Color(0.30, 0.27, 0.22, 0.25)
			for row in 4:
				var off = 0 if row % 2 == 0 else 4
				for col_i in 2:
					draw_rect(Rect2(rx+15+off+col_i*7, ry+11+row*7, 5, 5), block, false, 1.0)
			# Battlements
			for i in 3:
				draw_rect(Rect2(rx + 12 + i * 7, ry + 6, 5, 6), top)
			# Window slit with glow
			draw_rect(Rect2(rx + 20, ry + 18, 4, 8), Color(0.1, 0.1, 0.12, 0.6))
			draw_rect(Rect2(rx + 21, ry + 19, 2, 6), Color(0.85, 0.75, 0.35, 0.35))

		Tile.TerrainObject.CHURCH:
			var wall = Color(0.42, 0.38, 0.30, 0.7)
			var roof = Color(0.30, 0.18, 0.08, 0.7)
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			# Ground shadow
			draw_rect(Rect2(rx + 12, ry + 36, 24, 3), shadow)
			# Walls
			draw_rect(Rect2(rx + 10, ry + 18, 24, 18), wall)
			# Stone detail
			var block = Color(0.36, 0.32, 0.24, 0.25)
			for row in 3:
				var off = 0 if row % 2 == 0 else 4
				for col_i in 3:
					draw_rect(Rect2(rx+11+off+col_i*7, ry+19+row*6, 5, 4), block, false, 1.0)
			# Roof
			var roof_pts = PackedVector2Array([
				Vector2(rx + 7, ry + 18), Vector2(rx + 22, ry + 8), Vector2(rx + 37, ry + 18)
			])
			draw_colored_polygon(roof_pts, roof)
			# Roof highlight
			draw_line(Vector2(rx+14, ry+13), Vector2(rx+22, ry+9), Color(0.38, 0.24, 0.12, 0.4), 1.0)
			# Cross
			draw_rect(Rect2(rx + 21, ry + 2, 2, 8), Color(0.8, 0.7, 0.3, 0.7))
			draw_rect(Rect2(rx + 18, ry + 4, 8, 2), Color(0.8, 0.7, 0.3, 0.7))
			# Stained glass window
			draw_rect(Rect2(rx + 19, ry + 22, 6, 6), Color(0.6, 0.5, 0.8, 0.5))
			draw_rect(Rect2(rx + 21, ry + 22, 2, 6), Color(0.8, 0.7, 0.3, 0.4))

		Tile.TerrainObject.WELL:
			var stone = Color(0.38, 0.35, 0.28, 0.6)
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			draw_circle(Vector2(rx + 24, ry + 28), 6, shadow)
			draw_circle(Vector2(rx + 22, ry + 24), 8, stone)
			draw_circle(Vector2(rx + 22, ry + 24), 7, Color(0.32, 0.30, 0.24, 0.4), false, 1.0)
			draw_circle(Vector2(rx + 22, ry + 24), 5, Color(0.12, 0.22, 0.45, 0.5))
			# Water shimmer
			draw_circle(Vector2(rx + 21, ry + 23), 2, Color(0.25, 0.35, 0.55, 0.3))
			# Post and roof
			draw_rect(Rect2(rx + 28, ry + 14, 2, 14), stone)
			draw_rect(Rect2(rx + 16, ry + 14, 16, 2), stone)
			# Rope
			draw_line(Vector2(rx+22, ry+16), Vector2(rx+22, ry+22), Color(0.45, 0.38, 0.20, 0.4), 1.0)

		Tile.TerrainObject.FENCE_H:
			var fence = Color(0.38, 0.28, 0.12, 0.5)
			var grain = Color(0.32, 0.22, 0.08, 0.3)
			draw_rect(Rect2(rx + 2, ry + 20, TILE_SIZE - 4, 3), fence)
			draw_line(Vector2(rx+3, ry+21), Vector2(rx+TILE_SIZE-5, ry+21), grain, 1.0)
			for i in 4:
				draw_rect(Rect2(rx + 6 + i * 10, ry + 16, 2, 12), fence)

		Tile.TerrainObject.FENCE_V:
			var fence = Color(0.38, 0.28, 0.12, 0.5)
			var grain = Color(0.32, 0.22, 0.08, 0.3)
			draw_rect(Rect2(rx + 20, ry + 2, 3, TILE_SIZE - 4), fence)
			draw_line(Vector2(rx+21, ry+3), Vector2(rx+21, ry+TILE_SIZE-5), grain, 1.0)
			for i in 4:
				draw_rect(Rect2(rx + 16, ry + 6 + i * 10, 12, 2), fence)

		Tile.TerrainObject.SIGNPOST:
			var wood = Color(0.35, 0.25, 0.10, 0.6)
			var shadow = Color(0.0, 0.0, 0.0, 0.1)
			draw_rect(Rect2(rx + 22, ry + 34, 6, 2), shadow)
			draw_rect(Rect2(rx + 20, ry + 16, 3, 20), wood)
			draw_rect(Rect2(rx + 12, ry + 14, 20, 8), wood)
			draw_rect(Rect2(rx + 12, ry + 14, 20, 8), Color(0.28, 0.20, 0.06, 0.3), false, 1.0)
			# Arrow indicator
			draw_line(Vector2(rx+28, ry+18), Vector2(rx+32, ry+18), Color(0.25, 0.18, 0.06, 0.5), 1.5)

		Tile.TerrainObject.BARREL:
			var barrel = Color(0.38, 0.25, 0.10, 0.6)
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			draw_circle(Vector2(rx + 24, ry + 28), 6, shadow)
			draw_circle(Vector2(rx + 22, ry + 24), 7, barrel)
			# Metal bands
			draw_arc(Vector2(rx + 22, ry + 24), 7, 0, TAU, 12, Color(0.3, 0.28, 0.22, 0.5), 1.5)
			draw_arc(Vector2(rx + 22, ry + 24), 5, 0, TAU, 12, Color(0.3, 0.28, 0.22, 0.35), 1.0)
			# Stave lines
			draw_line(Vector2(rx+22, ry+17), Vector2(rx+22, ry+31), Color(0.30, 0.20, 0.06, 0.3), 1.0)
			draw_line(Vector2(rx+18, ry+18), Vector2(rx+18, ry+30), Color(0.30, 0.20, 0.06, 0.3), 1.0)

		Tile.TerrainObject.CRATE:
			var crate = Color(0.42, 0.32, 0.15, 0.6)
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			draw_rect(Rect2(rx + 16, ry + 32, 16, 2), shadow)
			draw_rect(Rect2(rx + 14, ry + 16, 16, 16), crate)
			# Plank lines
			draw_line(Vector2(rx+14, ry+21), Vector2(rx+30, ry+21), Color(0.35, 0.25, 0.10, 0.3), 1.0)
			draw_line(Vector2(rx+14, ry+27), Vector2(rx+30, ry+27), Color(0.35, 0.25, 0.10, 0.3), 1.0)
			# Cross mark
			draw_line(Vector2(rx + 14, ry + 16), Vector2(rx + 30, ry + 32), Color(0.3, 0.22, 0.08, 0.4), 1.5)
			draw_line(Vector2(rx + 30, ry + 16), Vector2(rx + 14, ry + 32), Color(0.3, 0.22, 0.08, 0.4), 1.5)
			# Highlight edge
			draw_rect(Rect2(rx + 14, ry + 16, 16, 16), Color(0.35, 0.26, 0.10, 0.35), false, 1.0)

		Tile.TerrainObject.BRIDGE_H:
			var plank = Color(0.40, 0.28, 0.12, 0.6)
			var grain = Color(0.32, 0.22, 0.08, 0.3)
			for i in 5:
				var px = rx + 3 + i * 8
				draw_rect(Rect2(px, ry + 8, 6, TILE_SIZE - 16), plank)
				draw_line(Vector2(px+3, ry+9), Vector2(px+3, ry+TILE_SIZE-9), grain, 1.0)
			var rail = Color(0.30, 0.20, 0.08, 0.5)
			draw_rect(Rect2(rx + 2, ry + 6, TILE_SIZE - 4, 2), rail)
			draw_rect(Rect2(rx + 2, ry + TILE_SIZE - 8, TILE_SIZE - 4, 2), rail)

		Tile.TerrainObject.BRIDGE_V:
			var plank = Color(0.40, 0.28, 0.12, 0.6)
			var grain = Color(0.32, 0.22, 0.08, 0.3)
			for i in 5:
				var py = ry + 3 + i * 8
				draw_rect(Rect2(rx + 8, py, TILE_SIZE - 16, 6), plank)
				draw_line(Vector2(rx+9, py+3), Vector2(rx+TILE_SIZE-9, py+3), grain, 1.0)
			var rail = Color(0.30, 0.20, 0.08, 0.5)
			draw_rect(Rect2(rx + 6, ry + 2, 2, TILE_SIZE - 4), rail)
			draw_rect(Rect2(rx + TILE_SIZE - 8, ry + 2, 2, TILE_SIZE - 4), rail)

		Tile.TerrainObject.RUINS_PILLAR:
			var pillar = Color(0.42, 0.38, 0.32, 0.65)
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			draw_rect(Rect2(rx + 20, ry + 36, 8, 2), shadow)
			draw_rect(Rect2(rx + 18, ry + 10, 8, 26), pillar)
			# Capital
			draw_rect(Rect2(rx + 16, ry + 8, 12, 4), pillar)
			# Fluting lines
			draw_line(Vector2(rx+20, ry+12), Vector2(rx+20, ry+34), Color(0.35, 0.30, 0.24, 0.3), 1.0)
			draw_line(Vector2(rx+24, ry+12), Vector2(rx+24, ry+34), Color(0.35, 0.30, 0.24, 0.3), 1.0)
			# Cracks
			draw_line(Vector2(rx + 20, ry + 16), Vector2(rx + 24, ry + 28), Color(0.2, 0.18, 0.14, 0.4), 1.0)
			draw_line(Vector2(rx + 22, ry + 20), Vector2(rx + 26, ry + 24), Color(0.2, 0.18, 0.14, 0.3), 1.0)

		Tile.TerrainObject.RUINS_ARCH:
			var arch = Color(0.40, 0.36, 0.28, 0.6)
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			draw_rect(Rect2(rx + 10, ry + 38, 6, 2), shadow)
			draw_rect(Rect2(rx + 32, ry + 38, 6, 2), shadow)
			draw_rect(Rect2(rx + 8, ry + 12, 6, 26), arch)
			draw_rect(Rect2(rx + 30, ry + 12, 6, 26), arch)
			draw_arc(Vector2(rx + 22, ry + 14), 12, PI, TAU, 8, arch, 3.0)
			# Stone detail on pillars
			draw_rect(Rect2(rx + 9, ry + 18, 4, 3), Color(0.35, 0.30, 0.22, 0.3), false, 1.0)
			draw_rect(Rect2(rx + 31, ry + 18, 4, 3), Color(0.35, 0.30, 0.22, 0.3), false, 1.0)

		Tile.TerrainObject.STATUE:
			var stone = Color(0.45, 0.42, 0.38, 0.65)
			var highlight = Color(0.55, 0.52, 0.48, 0.4)
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			# Ground shadow
			draw_rect(Rect2(rx + 16, ry + 36, 16, 3), shadow)
			# Base
			draw_rect(Rect2(rx + 14, ry + 30, 16, 6), stone)
			draw_rect(Rect2(rx + 14, ry + 30, 16, 1), highlight)
			# Figure
			draw_rect(Rect2(rx + 18, ry + 14, 8, 16), stone)
			# Arms
			draw_rect(Rect2(rx + 14, ry + 18, 4, 3), stone)
			draw_rect(Rect2(rx + 26, ry + 18, 4, 3), stone)
			# Head
			draw_circle(Vector2(rx + 22, ry + 12), 5, stone)
			# Highlight
			draw_circle(Vector2(rx + 20, ry + 11), 2, highlight)

		Tile.TerrainObject.ROCK_SMALL:
			# Cluster of 2-3 small angular rocks with shadow
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			var rock1 = Color(0.32, 0.28, 0.24, 0.65)
			var rock2 = Color(0.28, 0.25, 0.20, 0.6)
			var highlight = Color(0.42, 0.38, 0.34, 0.4)
			# Shadows
			draw_rect(Rect2(rx+14, ry+30, 8, 2), shadow)
			draw_rect(Rect2(rx+26, ry+28, 6, 2), shadow)
			# Rock 1
			var r1 = PackedVector2Array([
				Vector2(rx+12, ry+28), Vector2(rx+14, ry+22),
				Vector2(rx+20, ry+22), Vector2(rx+22, ry+28)
			])
			draw_colored_polygon(r1, rock1)
			draw_line(Vector2(rx+16, ry+23), Vector2(rx+18, ry+27), highlight, 1.0)
			# Rock 2
			var r2 = PackedVector2Array([
				Vector2(rx+24, ry+26), Vector2(rx+26, ry+20),
				Vector2(rx+32, ry+21), Vector2(rx+32, ry+26)
			])
			draw_colored_polygon(r2, rock2)
			# Rock 3
			draw_rect(Rect2(rx+18, ry+26, 5, 4), Color(0.30, 0.26, 0.22, 0.55))

		Tile.TerrainObject.ROCK_LARGE:
			# Single large boulder ~60% of tile
			var shadow = Color(0.0, 0.0, 0.0, 0.18)
			var rock = Color(0.30, 0.26, 0.22, 0.7)
			var dark_side = Color(0.22, 0.18, 0.14, 0.6)
			var highlight = Color(0.42, 0.38, 0.34, 0.45)
			# Shadow
			draw_circle(Vector2(rx+24, ry+34), 10, shadow)
			# Main body
			var pts = PackedVector2Array([
				Vector2(rx+10, ry+32), Vector2(rx+8, ry+22), Vector2(rx+12, ry+14),
				Vector2(rx+22, ry+10), Vector2(rx+32, ry+12), Vector2(rx+36, ry+22),
				Vector2(rx+34, ry+32)
			])
			draw_colored_polygon(pts, rock)
			# Dark right side
			var dark_pts = PackedVector2Array([
				Vector2(rx+24, ry+11), Vector2(rx+32, ry+12), Vector2(rx+36, ry+22),
				Vector2(rx+34, ry+32), Vector2(rx+24, ry+32)
			])
			draw_colored_polygon(dark_pts, dark_side)
			# Highlight top-left
			draw_line(Vector2(rx+12, ry+16), Vector2(rx+20, ry+12), highlight, 2.0)
			# Surface crack
			draw_line(Vector2(rx+18, ry+18), Vector2(rx+26, ry+26), Color(0.18, 0.14, 0.10, 0.35), 1.0)

		Tile.TerrainObject.LOG:
			# Fallen tree trunk lying diagonally
			var shadow = Color(0.0, 0.0, 0.0, 0.12)
			var bark = Color(0.35, 0.24, 0.10, 0.65)
			var bark_dark = Color(0.28, 0.18, 0.06, 0.5)
			var cut_face = Color(0.50, 0.40, 0.22, 0.6)
			# Shadow
			draw_line(Vector2(rx+10, ry+34), Vector2(rx+36, ry+22), shadow, 8.0)
			# Main trunk
			draw_line(Vector2(rx+8, ry+32), Vector2(rx+34, ry+20), bark, 6.0)
			# Bark texture lines
			draw_line(Vector2(rx+10, ry+31), Vector2(rx+32, ry+20), bark_dark, 1.0)
			draw_line(Vector2(rx+12, ry+33), Vector2(rx+34, ry+22), bark_dark, 1.0)
			# Cut face on one end
			draw_circle(Vector2(rx+34, ry+20), 3, cut_face)
			# Ring detail
			draw_circle(Vector2(rx+34, ry+20), 2, Color(0.42, 0.34, 0.18, 0.4), false, 1.0)

		Tile.TerrainObject.ROOT:
			# Network of thin brown lines spreading from an edge
			var root_col = Color(0.35, 0.24, 0.10, 0.55)
			var knot_col = Color(0.30, 0.20, 0.08, 0.6)
			# Main roots from left edge
			draw_line(Vector2(rx+2, ry+18), Vector2(rx+20, ry+22), root_col, 2.0)
			draw_line(Vector2(rx+2, ry+24), Vector2(rx+22, ry+28), root_col, 2.0)
			draw_line(Vector2(rx+2, ry+30), Vector2(rx+18, ry+34), root_col, 1.5)
			# Branch roots
			draw_line(Vector2(rx+14, ry+20), Vector2(rx+28, ry+16), root_col, 1.0)
			draw_line(Vector2(rx+16, ry+26), Vector2(rx+32, ry+24), root_col, 1.0)
			draw_line(Vector2(rx+20, ry+22), Vector2(rx+30, ry+30), root_col, 1.0)
			# Fine roots
			draw_line(Vector2(rx+28, ry+16), Vector2(rx+36, ry+14), Color(0.32, 0.22, 0.08, 0.35), 1.0)
			draw_line(Vector2(rx+32, ry+24), Vector2(rx+38, ry+22), Color(0.32, 0.22, 0.08, 0.35), 1.0)
			# Knots
			draw_circle(Vector2(rx+14, ry+20), 2, knot_col)
			draw_circle(Vector2(rx+16, ry+26), 2, knot_col)

		Tile.TerrainObject.RUINS_WALL:
			# Partial stone wall section, broken top edge
			var wall = Color(0.38, 0.34, 0.28, 0.7)
			var shadow = Color(0.0, 0.0, 0.0, 0.15)
			# Ground shadow
			draw_rect(Rect2(rx+8, ry+36, 28, 3), shadow)
			# Main wall body
			draw_rect(Rect2(rx+6, ry+10, 32, 26), wall)
			# Broken top edge (jagged)
			var bg = Color(0.0, 0.0, 0.0, 0.0)  # Clear out the top
			var break_pts = PackedVector2Array([
				Vector2(rx+6, ry+10), Vector2(rx+10, ry+8), Vector2(rx+16, ry+12),
				Vector2(rx+22, ry+6), Vector2(rx+28, ry+10), Vector2(rx+34, ry+8),
				Vector2(rx+38, ry+10), Vector2(rx+38, ry+10), Vector2(rx+6, ry+10)
			])
			# Stone block detail
			var block = Color(0.32, 0.28, 0.22, 0.3)
			for row in 3:
				var off = 0 if row % 2 == 0 else 5
				for col_i in 3:
					draw_rect(Rect2(rx+7+off+col_i*10, ry+14+row*8, 8, 6), block, false, 1.0)
			# Cracks
			draw_line(Vector2(rx+14, ry+16), Vector2(rx+20, ry+30), Color(0.24, 0.20, 0.16, 0.35), 1.0)

		Tile.TerrainObject.WOOD_WALL:
			# Vertical wooden planks with grain
			var plank = Color(0.40, 0.30, 0.14, 0.7)
			var grain = Color(0.32, 0.24, 0.10, 0.4)
			var gap = Color(0.20, 0.14, 0.06, 0.5)
			for i in 5:
				var px = rx + 4 + i * 7
				draw_rect(Rect2(px, ry + 4, 6, TILE_SIZE - 8), plank)
				# Grain lines
				draw_line(Vector2(px+2, ry+6), Vector2(px+2, ry+TILE_SIZE-6), grain, 1.0)
				draw_line(Vector2(px+4, ry+8), Vector2(px+4, ry+TILE_SIZE-8), grain, 1.0)
				# Gap between planks
				if i > 0:
					draw_line(Vector2(px, ry+4), Vector2(px, ry+TILE_SIZE-4), gap, 1.0)
			# Nails
			for i in range(0, 5, 2):
				draw_circle(Vector2(rx+7+i*7, ry+10), 1, Color(0.25, 0.22, 0.18, 0.5))
				draw_circle(Vector2(rx+7+i*7, ry+32), 1, Color(0.25, 0.22, 0.18, 0.5))

		Tile.TerrainObject.WOOD_CORNER:
			# Two perpendicular plank walls meeting at corner
			var plank = Color(0.40, 0.30, 0.14, 0.7)
			var grain = Color(0.32, 0.24, 0.10, 0.4)
			var gap = Color(0.20, 0.14, 0.06, 0.5)
			# Vertical wall (left side)
			for i in 2:
				var px = rx + 4 + i * 7
				draw_rect(Rect2(px, ry + 4, 6, TILE_SIZE - 8), plank)
				draw_line(Vector2(px+3, ry+6), Vector2(px+3, ry+TILE_SIZE-6), grain, 1.0)
			# Horizontal wall (top)
			for i in 3:
				var py = ry + 4 + i * 7
				draw_rect(Rect2(rx + 16, py, TILE_SIZE - 20, 6), plank)
				draw_line(Vector2(rx+18, py+3), Vector2(rx+TILE_SIZE-6, py+3), grain, 1.0)
			# Corner joint
			draw_rect(Rect2(rx+14, ry+4, 4, 18), Color(0.35, 0.26, 0.10, 0.6))

		Tile.TerrainObject.ROOF_PIECE:
			# Overlapping shingle/thatch pattern
			var shingle1 = Color(0.45, 0.22, 0.08, 0.65)
			var shingle2 = Color(0.50, 0.25, 0.10, 0.55)
			for row in 5:
				var off = 0 if row % 2 == 0 else 5
				var sc = shingle1 if row % 2 == 0 else shingle2
				for col_i in 4:
					var sx = rx + 3 + off + col_i * 10
					var sy = ry + 3 + row * 8
					draw_rect(Rect2(sx, sy, 8, 7), sc)
					# Shingle bottom edge
					draw_line(Vector2(sx, sy+6), Vector2(sx+8, sy+6), Color(0.35, 0.16, 0.04, 0.4), 1.0)

		Tile.TerrainObject.DOOR_PIECE:
			# Wooden door frame with dark interior
			var frame = Color(0.35, 0.25, 0.10, 0.7)
			var door_wood = Color(0.40, 0.30, 0.14, 0.65)
			var interior = Color(0.06, 0.04, 0.02, 0.75)
			# Frame
			draw_rect(Rect2(rx+8, ry+4, 28, TILE_SIZE-8), frame)
			# Door opening
			draw_rect(Rect2(rx+12, ry+6, 20, TILE_SIZE-12), interior)
			# Door panels
			draw_rect(Rect2(rx+12, ry+6, 9, TILE_SIZE-12), door_wood)
			# Plank grain
			draw_line(Vector2(rx+15, ry+8), Vector2(rx+15, ry+TILE_SIZE-8), Color(0.32, 0.22, 0.08, 0.35), 1.0)
			draw_line(Vector2(rx+18, ry+8), Vector2(rx+18, ry+TILE_SIZE-8), Color(0.32, 0.22, 0.08, 0.35), 1.0)
			# Handle
			draw_circle(Vector2(rx+20, ry+22), 1.5, Color(0.55, 0.48, 0.25, 0.6))
			# Threshold
			draw_rect(Rect2(rx+10, ry+TILE_SIZE-6, 24, 2), Color(0.30, 0.26, 0.20, 0.5))

		Tile.TerrainObject.WINDOW_PIECE:
			# Window frame with mullion cross, lighter interior
			var frame = Color(0.35, 0.25, 0.10, 0.7)
			var glass = Color(0.55, 0.65, 0.80, 0.45)
			var mullion = Color(0.30, 0.22, 0.08, 0.65)
			var sill = Color(0.32, 0.28, 0.22, 0.6)
			# Wall around window
			draw_rect(Rect2(rx+4, ry+4, TILE_SIZE-10, TILE_SIZE-10), Color(0.38, 0.34, 0.26, 0.5))
			# Window frame
			draw_rect(Rect2(rx+10, ry+8, 24, 24), frame)
			# Glass panes
			draw_rect(Rect2(rx+12, ry+10, 20, 20), glass)
			# Mullion cross
			draw_rect(Rect2(rx+21, ry+10, 2, 20), mullion)
			draw_rect(Rect2(rx+12, ry+19, 20, 2), mullion)
			# Light reflection
			draw_line(Vector2(rx+14, ry+12), Vector2(rx+18, ry+16), Color(0.85, 0.90, 1.0, 0.35), 1.5)
			# Sill
			draw_rect(Rect2(rx+8, ry+30, 28, 3), sill)

func _draw_unit_shadow(unit):
	var p = unit.grid_position
	var offset = unit_offsets.get(unit, Vector2.ZERO)
	var ux = p.x * TILE_SIZE + int(offset.x) + 2
	var uy = p.y * TILE_SIZE + int(offset.y) + 2
	var pad = 6
	var sc = Color(0, 0, 0, 0.25)

	# Sprite units get a simple rect shadow
	var sprite_key = unit.unit_name.to_lower()
	if sprite_cache.has(sprite_key):
		var sp = 2
		draw_rect(Rect2(ux + sp, uy + sp, TILE_SIZE - sp * 2, TILE_SIZE - sp * 2), sc)
		return

	var shape = unit.get_class_shape()
	_draw_unit_shape(ux, uy, pad, sc, shape)

# ─── Highlights ───────────────────────────────────────────────────────────────

func highlight_move(tiles_arr: Array):
	for p in tiles_arr:
		highlighted[p] = Color(0.20, 0.50, 1.0, 0.35)
	queue_redraw()

func highlight_selected(pos: Vector2i):
	highlighted[pos] = Color(1.0, 0.85, 0.0, 0.55)
	queue_redraw()

func highlight_attack(tiles_arr: Array):
	for p in tiles_arr:
		highlighted[p] = Color(0.90, 0.15, 0.15, 0.40)
	queue_redraw()

func highlight_heal(tiles_arr: Array):
	for p in tiles_arr:
		highlighted[p] = Color(0.20, 1.0, 0.50, 0.35)
	queue_redraw()

func clear_highlights():
	highlighted.clear()
	queue_redraw()

# ─── Flash Effects ────────────────────────────────────────────────────────────

func flash(pos: Vector2i, color: Color, duration: float = 0.4):
	flash_tiles[pos] = {"color": color, "timer": duration}

func pop_damage(pos: Vector2i, text: String, color: Color = Color(1, 1, 1), duration: float = 0.9):
	damage_pops.append({"pos": pos, "text": text, "color": color, "timer": duration, "max_timer": duration})

func _process(delta: float):
	var needs_redraw = false

	if not flash_tiles.is_empty():
		var expired: Array = []
		for pos in flash_tiles:
			flash_tiles[pos]["timer"] -= delta
			flash_tiles[pos]["color"].a = clampf(flash_tiles[pos]["timer"] * 2.5, 0.0, 0.8)
			if flash_tiles[pos]["timer"] <= 0.0:
				expired.append(pos)
		for p in expired: flash_tiles.erase(p)
		needs_redraw = true

	if not damage_pops.is_empty():
		var i = damage_pops.size() - 1
		while i >= 0:
			damage_pops[i].timer -= delta
			if damage_pops[i].timer <= 0.0:
				damage_pops.remove_at(i)
			i -= 1
		needs_redraw = true

	if needs_redraw:
		queue_redraw()

# ─── Movement Range (Dijkstra) ────────────────────────────────────────────────

func get_movement_range(start: Vector2i, move_range: int, unit_element: String = "") -> Array:
	var reachable:  Array      = []
	var cost_map:   Dictionary = {start: 0}
	var queue:      Array      = [{pos=start, cost=0}]
	var DIRS = [Vector2i(1,0),Vector2i(-1,0),Vector2i(0,1),Vector2i(0,-1)]

	while not queue.is_empty():
		queue.sort_custom(func(a,b): return a.cost < b.cost)
		var cur = queue.pop_front()
		if cur.pos != start: reachable.append(cur.pos)
		for d in DIRS:
			var nxt: Vector2i = cur.pos + d
			if not tiles.has(nxt): continue
			var t: Tile = tiles[nxt]
			if not t.is_passable: continue
			if t.occupant != null:
				if not t.occupant.is_player_unit: continue
			var step     = t.get_movement_cost(unit_element)
			var new_cost = cur.cost + step
			if new_cost <= move_range:
				if not cost_map.has(nxt) or cost_map[nxt] > new_cost:
					cost_map[nxt] = new_cost
					queue.append({pos=nxt, cost=new_cost})
	return reachable

# ─── Elemental Effects ────────────────────────────────────────────────────────

func apply_elemental_effect(origin: Vector2i, radius: int, element: String, duration: int = 3):
	for x in range(origin.x - radius, origin.x + radius + 1):
		for y in range(origin.y - radius, origin.y + radius + 1):
			if abs(x-origin.x)+abs(y-origin.y) <= radius:
				var p = Vector2i(x,y)
				if tiles.has(p):
					tiles[p].set_elemental_state(element, duration)
					flash(p, _elem_color(element), 0.8)
	queue_redraw()

func tick_all_tiles():
	for p in tiles: tiles[p].tick_turn()
	queue_redraw()

func _elem_color(elem: String) -> Color:
	match elem:
		"blood":    return Color(0.8, 0.1, 0.1, 0.7)
		"electric": return Color(1.0, 1.0, 0.2, 0.7)
		"void":     return Color(0.3, 0.0, 0.5, 0.7)
		"light":    return Color(1.0, 0.95, 0.5, 0.7)
		"dark":     return Color(0.2, 0.0, 0.3, 0.7)
		"ice":      return Color(0.6, 0.9, 1.0, 0.7)
		"plant":    return Color(0.2, 0.8, 0.2, 0.7)
		"god":      return Color(1.0, 1.0, 0.9, 0.9)
	return Color(1.0, 1.0, 1.0, 0.5)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func world_to_tile(wp: Vector2) -> Vector2i:
	return Vector2i(int(wp.x / TILE_SIZE), int(wp.y / TILE_SIZE))

func is_valid_tile(pos: Vector2i) -> bool:
	return tiles.has(pos) and pos.x >= 0 and pos.y >= 0

# ─── Attack Animations ──────────────────────────────────────────────────────

var _anim_unit = null  # Unit currently being animated

func _set_anim_offset(v: Vector2) -> void:
	if _anim_unit != null:
		unit_offsets[_anim_unit] = v
		queue_redraw()

func animate_attack(attacker, defender) -> void:
	var atk_pos = Vector2(attacker.grid_position.x * TILE_SIZE, attacker.grid_position.y * TILE_SIZE)
	var def_pos = Vector2(defender.grid_position.x * TILE_SIZE, defender.grid_position.y * TILE_SIZE)
	var direction = (def_pos - atk_pos).normalized()
	var slide_dist = TILE_SIZE * 0.6

	# Slide attacker toward defender
	_anim_unit = attacker
	unit_offsets[attacker] = Vector2.ZERO
	var tween = create_tween()
	tween.tween_method(_set_anim_offset, Vector2.ZERO, direction * slide_dist, 0.12)
	await tween.finished

	# Impact flash on defender
	flash(defender.grid_position, Color(1.0, 1.0, 1.0, 0.9), 0.15)
	queue_redraw()
	await get_tree().create_timer(0.08).timeout

	# Slide attacker back
	var tween2 = create_tween()
	tween2.tween_method(_set_anim_offset, direction * slide_dist, Vector2.ZERO, 0.1)
	await tween2.finished

	unit_offsets.erase(attacker)
	_anim_unit = null
	queue_redraw()

func animate_hit_recoil(unit) -> void:
	var recoil = Vector2(4, 0)
	_anim_unit = unit
	unit_offsets[unit] = Vector2.ZERO
	var tween = create_tween()
	tween.tween_method(_set_anim_offset, Vector2.ZERO, recoil, 0.04)
	tween.tween_method(_set_anim_offset, recoil, -recoil, 0.04)
	tween.tween_method(_set_anim_offset, -recoil, Vector2.ZERO, 0.04)
	await tween.finished
	unit_offsets.erase(unit)
	_anim_unit = null
	queue_redraw()
