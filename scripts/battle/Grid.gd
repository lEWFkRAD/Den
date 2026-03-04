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

func initialize(unit_count: int, _kip_count: int = 0):
	grid_width  = BASE_WIDTH  + unit_count * TILES_PER_UNIT
	grid_height = BASE_HEIGHT + unit_count * TILES_PER_UNIT
	_build_tiles()
	_scatter_terrain()
	queue_redraw()

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
			if   roll < 0.07: tiles[Vector2i(x,y)].terrain_type = Tile.TerrainType.FOREST
			elif roll < 0.11:
				tiles[Vector2i(x,y)].terrain_type = Tile.TerrainType.WATER
				tiles[Vector2i(x,y)].is_passable   = false
			elif roll < 0.14: tiles[Vector2i(x,y)].terrain_type = Tile.TerrainType.RUINS

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
	var col = unit.get_display_color()
	var shape = unit.get_class_shape()

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
			var half = TILE_SIZE/2 - pad
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

	# HP bar (improved with border and gradient)
	var hpr  = float(unit.stats.hp) / float(unit.stats.max_hp)
	var bw   = TILE_SIZE - pad*2
	var bh   = 5
	var by   = uy + TILE_SIZE - bh - 5
	draw_rect(Rect2(ux+pad-1, by-1, bw+2, bh+2), Color(0, 0, 0, 0.6))
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

	# Unit initial
	draw_string(font, Vector2(ux+TILE_SIZE/2-5, uy+TILE_SIZE/2+5),
		unit.unit_name.substr(0,1).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1,1,1,0.9))

# ─── Terrain Detail Drawing ───────────────────────────────────────────────────

func _draw_terrain_detail(pos: Vector2i, tile: Tile, rx: int, ry: int):
	if tile.elemental_state != Tile.ElementalState.NEUTRAL: return
	var seed_val = pos.x * 7919 + pos.y * 4391

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

func _draw_unit_shadow(unit):
	var p = unit.grid_position
	var offset = unit_offsets.get(unit, Vector2.ZERO)
	var ux = p.x * TILE_SIZE + int(offset.x) + 2
	var uy = p.y * TILE_SIZE + int(offset.y) + 2
	var pad = 6
	var sc = Color(0, 0, 0, 0.25)
	var shape = unit.get_class_shape()

	match shape:
		"square":
			draw_rect(Rect2(ux + pad, uy + pad, TILE_SIZE - pad * 2, TILE_SIZE - pad * 2), sc)
		"square_thick":
			draw_rect(Rect2(ux + pad - 2, uy + pad - 2, TILE_SIZE - pad * 2 + 4, TILE_SIZE - pad * 2 + 4), sc)
		"diamond":
			var cx = ux + TILE_SIZE / 2; var cy = uy + TILE_SIZE / 2
			var pts = PackedVector2Array([
				Vector2(cx, uy + pad), Vector2(ux + TILE_SIZE - pad, cy),
				Vector2(cx, uy + TILE_SIZE - pad), Vector2(ux + pad, cy)])
			draw_colored_polygon(pts, sc)
		"circle":
			draw_circle(Vector2(ux + TILE_SIZE / 2, uy + TILE_SIZE / 2), TILE_SIZE / 2 - pad, sc)
		"triangle":
			var cx = ux + TILE_SIZE / 2
			var pts = PackedVector2Array([
				Vector2(cx, uy + pad),
				Vector2(ux + TILE_SIZE - pad, uy + TILE_SIZE - pad),
				Vector2(ux + pad, uy + TILE_SIZE - pad)])
			draw_colored_polygon(pts, sc)
		"cross":
			var t = 10; var cx = ux + TILE_SIZE / 2; var cy = uy + TILE_SIZE / 2
			draw_rect(Rect2(cx - t / 2, uy + pad, t, TILE_SIZE - pad * 2), sc)
			draw_rect(Rect2(ux + pad, cy - t / 2, TILE_SIZE - pad * 2, t), sc)
		"star":
			var cx = ux + TILE_SIZE / 2; var cy = uy + TILE_SIZE / 2
			var ro = TILE_SIZE / 2 - pad; var ri = ro * 0.45
			var pts = PackedVector2Array()
			for i in 10:
				var angle = PI / 2 + i * TAU / 10
				var r = ro if i % 2 == 0 else ri
				pts.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
			draw_colored_polygon(pts, sc)

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
