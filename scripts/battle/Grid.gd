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

func _draw_terrain_detail(pos: Vector2i, tile: Tile, rx: int, ry: int):
	var seed_val = pos.x * 7919 + pos.y * 4391

	# Draw terrain-type details (unless overridden by elemental state)
	if tile.elemental_state == Tile.ElementalState.NEUTRAL:
		match tile.terrain_type:
			Tile.TerrainType.FOREST:
				var dark = Color(0.06, 0.24, 0.04, 0.6)
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

			Tile.TerrainType.WATER:
				var wave_col = Color(0.22, 0.38, 0.70, 0.25)
				for w in 2:
					var base_y = ry + 14 + w * 14
					var points = PackedVector2Array()
					for seg in 9:
						var px = rx + seg * 5
						var py = base_y + sin(float(seg + seed_val % 6) * 1.2) * 3.0
						points.append(Vector2(px, py))
					if points.size() > 1:
						draw_polyline(points, wave_col, 1.5)

			Tile.TerrainType.RUINS:
				var rubble = Color(0.44, 0.38, 0.30, 0.45)
				for i in 4:
					var ox = ((seed_val + i * 3137) % 28) + 5
					var oy = ((seed_val + i * 2269) % 28) + 5
					var sw = 3 + ((seed_val + i * 1093) % 5)
					var sh = 2 + ((seed_val + i * 2741) % 4)
					draw_rect(Rect2(rx + ox, ry + oy, sw, sh), rubble)

			Tile.TerrainType.RIVER:
				var river_col = Color(0.25, 0.45, 0.75, 0.35)
				var flow_col  = Color(0.35, 0.55, 0.85, 0.25)
				# Flowing water lines
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
				# Wooden planks
				var plank_col = Color(0.45, 0.32, 0.15, 0.5)
				for i in 4:
					var py = ry + 6 + i * 10
					draw_rect(Rect2(rx + 4, py, TILE_SIZE - 8, 3), plank_col)
				# Railings
				var rail_col = Color(0.35, 0.25, 0.10, 0.4)
				draw_rect(Rect2(rx + 2, ry + 2, 2, TILE_SIZE - 4), rail_col)
				draw_rect(Rect2(rx + TILE_SIZE - 4, ry + 2, 2, TILE_SIZE - 4), rail_col)

			Tile.TerrainType.ROAD:
				# Path markings
				var path_col = Color(0.28, 0.26, 0.20, 0.3)
				draw_rect(Rect2(rx + TILE_SIZE/2 - 1, ry + 4, 2, 6), path_col)
				draw_rect(Rect2(rx + TILE_SIZE/2 - 1, ry + 18, 2, 6), path_col)
				draw_rect(Rect2(rx + TILE_SIZE/2 - 1, ry + 32, 2, 6), path_col)

			Tile.TerrainType.VILLAGE:
				# Small house outline
				var house_col = Color(0.35, 0.30, 0.20, 0.4)
				draw_rect(Rect2(rx + 10, ry + 16, 24, 18), house_col)
				# Roof
				var roof_pts = PackedVector2Array([
					Vector2(rx + 8, ry + 16), Vector2(rx + 22, ry + 6), Vector2(rx + 36, ry + 16)
				])
				draw_colored_polygon(roof_pts, Color(0.45, 0.20, 0.10, 0.5))

			Tile.TerrainType.FORT:
				# Battlements
				var fort_col = Color(0.35, 0.32, 0.25, 0.4)
				draw_rect(Rect2(rx + 6, ry + 8, 32, 28), fort_col)
				# Crenellations
				for i in 4:
					draw_rect(Rect2(rx + 6 + i * 9, ry + 4, 5, 6), fort_col)

			Tile.TerrainType.THRONE:
				# Throne seat
				var throne_col = Color(0.65, 0.50, 0.15, 0.5)
				draw_rect(Rect2(rx + 14, ry + 12, 16, 22), throne_col)
				# Back
				draw_rect(Rect2(rx + 12, ry + 6, 20, 8), throne_col)
				# Gem
				draw_circle(Vector2(rx + 22, ry + 10), 3, Color(0.9, 0.2, 0.2, 0.6))

			Tile.TerrainType.SAND:
				# Sand dots
				var sand_col = Color(0.6, 0.52, 0.30, 0.25)
				for i in 5:
					var ox = ((seed_val + i * 1999) % 30) + 5
					var oy = ((seed_val + i * 3121) % 30) + 5
					draw_circle(Vector2(rx + ox, ry + oy), 1.5, sand_col)

			Tile.TerrainType.LAVA:
				# Lava glow bubbles
				var lava_col = Color(1.0, 0.4, 0.0, 0.4)
				for i in 3:
					var ox = ((seed_val + i * 2333) % 28) + 6
					var oy = ((seed_val + i * 1777) % 28) + 6
					draw_circle(Vector2(rx + ox, ry + oy), 3 + ((seed_val + i) % 3), lava_col)
				# Cracks
				var crack_col = Color(1.0, 0.6, 0.1, 0.35)
				draw_line(Vector2(rx + 8, ry + 12), Vector2(rx + 20, ry + 30), crack_col, 1.5)
				draw_line(Vector2(rx + 28, ry + 8), Vector2(rx + 18, ry + 25), crack_col, 1.5)

			Tile.TerrainType.WALL:
				# Stone blocks
				var stone_col = Color(0.28, 0.26, 0.22, 0.4)
				for row in 3:
					var off = 0 if row % 2 == 0 else 10
					for col in 3:
						draw_rect(Rect2(rx + 4 + off + col * 14, ry + 4 + row * 13, 12, 11), stone_col)

			Tile.TerrainType.ELEVATION:
				# Mountain ridges
				var mt_col = Color(0.50, 0.44, 0.32, 0.4)
				var peak_pts = PackedVector2Array([
					Vector2(rx + 10, ry + 32), Vector2(rx + 22, ry + 8), Vector2(rx + 34, ry + 32)
				])
				draw_colored_polygon(peak_pts, mt_col)
				# Snow cap
				var snow_pts = PackedVector2Array([
					Vector2(rx + 18, ry + 14), Vector2(rx + 22, ry + 8), Vector2(rx + 26, ry + 14)
				])
				draw_colored_polygon(snow_pts, Color(0.8, 0.82, 0.85, 0.5))

	# Draw terrain objects (always visible regardless of elemental state)
	_draw_terrain_object(tile, rx, ry, seed_val)

func _draw_terrain_object(tile: Tile, rx: int, ry: int, seed_val: int):
	match tile.terrain_object:
		Tile.TerrainObject.NONE: return

		Tile.TerrainObject.TREE_PINE:
			var trunk = Color(0.35, 0.22, 0.08, 0.7)
			var leaves = Color(0.08, 0.30, 0.06, 0.75)
			draw_rect(Rect2(rx + 20, ry + 26, 4, 12), trunk)
			for i in 3:
				var w = 16 - i * 4
				var h = 10
				var ty = ry + 6 + i * 7
				var pts = PackedVector2Array([
					Vector2(rx + 22, ty), Vector2(rx + 22 - w/2, ty + h), Vector2(rx + 22 + w/2, ty + h)
				])
				draw_colored_polygon(pts, leaves)

		Tile.TerrainObject.TREE_OAK:
			var trunk = Color(0.32, 0.20, 0.06, 0.7)
			var canopy = Color(0.12, 0.32, 0.08, 0.75)
			draw_rect(Rect2(rx + 19, ry + 24, 6, 14), trunk)
			draw_circle(Vector2(rx + 22, ry + 18), 12, canopy)
			draw_circle(Vector2(rx + 16, ry + 20), 8, canopy)
			draw_circle(Vector2(rx + 28, ry + 20), 8, canopy)

		Tile.TerrainObject.TREE_DEAD:
			var trunk = Color(0.28, 0.22, 0.16, 0.65)
			draw_rect(Rect2(rx + 20, ry + 14, 4, 24), trunk)
			# Bare branches
			draw_line(Vector2(rx + 22, ry + 18), Vector2(rx + 32, ry + 10), trunk, 2.0)
			draw_line(Vector2(rx + 22, ry + 22), Vector2(rx + 12, ry + 14), trunk, 2.0)
			draw_line(Vector2(rx + 22, ry + 16), Vector2(rx + 28, ry + 6), trunk, 1.5)

		Tile.TerrainObject.BUSH:
			var bush_col = Color(0.10, 0.30, 0.08, 0.6)
			draw_circle(Vector2(rx + 16, ry + 28), 7, bush_col)
			draw_circle(Vector2(rx + 28, ry + 26), 8, bush_col)
			draw_circle(Vector2(rx + 22, ry + 22), 6, bush_col)

		Tile.TerrainObject.HOUSE:
			var wall_col = Color(0.40, 0.35, 0.25, 0.7)
			var roof_col = Color(0.50, 0.22, 0.08, 0.7)
			var door_col = Color(0.25, 0.18, 0.08, 0.8)
			# Walls
			draw_rect(Rect2(rx + 8, ry + 18, 28, 18), wall_col)
			# Roof
			var roof_pts = PackedVector2Array([
				Vector2(rx + 5, ry + 18), Vector2(rx + 22, ry + 6), Vector2(rx + 39, ry + 18)
			])
			draw_colored_polygon(roof_pts, roof_col)
			# Door
			draw_rect(Rect2(rx + 18, ry + 26, 8, 10), door_col)
			# Window
			draw_rect(Rect2(rx + 12, ry + 22, 4, 4), Color(0.7, 0.65, 0.4, 0.6))

		Tile.TerrainObject.TOWER:
			var stone = Color(0.35, 0.32, 0.28, 0.75)
			var top   = Color(0.28, 0.25, 0.22, 0.7)
			draw_rect(Rect2(rx + 14, ry + 10, 16, 28), stone)
			# Battlements
			for i in 3:
				draw_rect(Rect2(rx + 12 + i * 7, ry + 6, 5, 6), top)
			# Window slit
			draw_rect(Rect2(rx + 20, ry + 18, 4, 8), Color(0.1, 0.1, 0.12, 0.6))

		Tile.TerrainObject.CHURCH:
			var wall = Color(0.42, 0.38, 0.30, 0.7)
			var roof = Color(0.30, 0.18, 0.08, 0.7)
			draw_rect(Rect2(rx + 10, ry + 18, 24, 18), wall)
			var roof_pts = PackedVector2Array([
				Vector2(rx + 7, ry + 18), Vector2(rx + 22, ry + 8), Vector2(rx + 37, ry + 18)
			])
			draw_colored_polygon(roof_pts, roof)
			# Cross
			draw_rect(Rect2(rx + 21, ry + 2, 2, 8), Color(0.8, 0.7, 0.3, 0.7))
			draw_rect(Rect2(rx + 18, ry + 4, 8, 2), Color(0.8, 0.7, 0.3, 0.7))

		Tile.TerrainObject.WELL:
			var stone = Color(0.38, 0.35, 0.28, 0.6)
			draw_circle(Vector2(rx + 22, ry + 24), 8, stone)
			draw_circle(Vector2(rx + 22, ry + 24), 5, Color(0.12, 0.22, 0.45, 0.5))
			# Post
			draw_rect(Rect2(rx + 28, ry + 14, 2, 14), stone)
			draw_rect(Rect2(rx + 16, ry + 14, 16, 2), stone)

		Tile.TerrainObject.FENCE_H:
			var fence = Color(0.38, 0.28, 0.12, 0.5)
			draw_rect(Rect2(rx + 2, ry + 20, TILE_SIZE - 4, 3), fence)
			for i in 4:
				draw_rect(Rect2(rx + 6 + i * 10, ry + 16, 2, 12), fence)

		Tile.TerrainObject.FENCE_V:
			var fence = Color(0.38, 0.28, 0.12, 0.5)
			draw_rect(Rect2(rx + 20, ry + 2, 3, TILE_SIZE - 4), fence)
			for i in 4:
				draw_rect(Rect2(rx + 16, ry + 6 + i * 10, 12, 2), fence)

		Tile.TerrainObject.SIGNPOST:
			var wood = Color(0.35, 0.25, 0.10, 0.6)
			draw_rect(Rect2(rx + 20, ry + 16, 3, 20), wood)
			draw_rect(Rect2(rx + 12, ry + 14, 20, 8), wood)

		Tile.TerrainObject.BARREL:
			var barrel = Color(0.38, 0.25, 0.10, 0.6)
			draw_circle(Vector2(rx + 22, ry + 24), 7, barrel)
			# Bands
			draw_arc(Vector2(rx + 22, ry + 24), 7, 0, TAU, 12, Color(0.3, 0.28, 0.22, 0.5), 1.5)

		Tile.TerrainObject.CRATE:
			var crate = Color(0.42, 0.32, 0.15, 0.6)
			draw_rect(Rect2(rx + 14, ry + 16, 16, 16), crate)
			# Cross mark
			draw_line(Vector2(rx + 14, ry + 16), Vector2(rx + 30, ry + 32), Color(0.3, 0.22, 0.08, 0.4), 1.5)
			draw_line(Vector2(rx + 30, ry + 16), Vector2(rx + 14, ry + 32), Color(0.3, 0.22, 0.08, 0.4), 1.5)

		Tile.TerrainObject.BRIDGE_H:
			var plank = Color(0.40, 0.28, 0.12, 0.6)
			for i in 5:
				draw_rect(Rect2(rx + 3 + i * 8, ry + 8, 6, TILE_SIZE - 16), plank)
			var rail = Color(0.30, 0.20, 0.08, 0.5)
			draw_rect(Rect2(rx + 2, ry + 6, TILE_SIZE - 4, 2), rail)
			draw_rect(Rect2(rx + 2, ry + TILE_SIZE - 8, TILE_SIZE - 4, 2), rail)

		Tile.TerrainObject.BRIDGE_V:
			var plank = Color(0.40, 0.28, 0.12, 0.6)
			for i in 5:
				draw_rect(Rect2(rx + 8, ry + 3 + i * 8, TILE_SIZE - 16, 6), plank)
			var rail = Color(0.30, 0.20, 0.08, 0.5)
			draw_rect(Rect2(rx + 6, ry + 2, 2, TILE_SIZE - 4), rail)
			draw_rect(Rect2(rx + TILE_SIZE - 8, ry + 2, 2, TILE_SIZE - 4), rail)

		Tile.TerrainObject.RUINS_PILLAR:
			var pillar = Color(0.42, 0.38, 0.32, 0.65)
			draw_rect(Rect2(rx + 18, ry + 10, 8, 26), pillar)
			# Capital
			draw_rect(Rect2(rx + 16, ry + 8, 12, 4), pillar)
			# Cracks
			draw_line(Vector2(rx + 20, ry + 16), Vector2(rx + 24, ry + 28), Color(0.2, 0.18, 0.14, 0.4), 1.0)

		Tile.TerrainObject.RUINS_ARCH:
			var arch = Color(0.40, 0.36, 0.28, 0.6)
			draw_rect(Rect2(rx + 8, ry + 12, 6, 26), arch)
			draw_rect(Rect2(rx + 30, ry + 12, 6, 26), arch)
			draw_arc(Vector2(rx + 22, ry + 14), 12, PI, TAU, 8, arch, 3.0)

		Tile.TerrainObject.STATUE:
			var stone = Color(0.45, 0.42, 0.38, 0.65)
			# Base
			draw_rect(Rect2(rx + 14, ry + 30, 16, 6), stone)
			# Figure
			draw_rect(Rect2(rx + 18, ry + 14, 8, 16), stone)
			# Head
			draw_circle(Vector2(rx + 22, ry + 12), 5, stone)

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
