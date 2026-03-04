class_name MapGenerator
extends RefCounted

## Procedural map generator stub for Den.
## Generates terrain data that can be loaded into Grid3D.

enum Template {
	BRIDGE_CHOKEPOINT,
	RUINED_CITY,
	CENTRAL_HILL,
	VALLEY_PASS,
	FORTRESS_APPROACH,
	OPEN_FIELD,
	RIVER_CROSSING,
	FOREST_AMBUSH,
}

var rng: RandomNumberGenerator
var width: int
var height: int

# Output data
var terrain_grid: Array = []    # 2D array of terrain strings
var height_data: Dictionary = {} # Vector2i → float
var object_placements: Array = [] # [{pos, object}]
var player_spawns: Array = []   # Array of Vector2i
var enemy_spawns: Array = []    # Array of Vector2i

func generate_map(seed_val: int = -1, map_width: int = 16, map_height: int = 14, template: Template = Template.OPEN_FIELD):
	rng = RandomNumberGenerator.new()
	rng.seed = seed_val if seed_val >= 0 else randi()
	width = map_width
	height = map_height

	# Initialize empty grid
	terrain_grid = []
	height_data.clear()
	object_placements.clear()
	player_spawns.clear()
	enemy_spawns.clear()

	for z in range(height):
		var row: Array = []
		for x in range(width):
			row.append("plain")
		terrain_grid.append(row)

	# Apply template
	match template:
		Template.BRIDGE_CHOKEPOINT:   _gen_bridge_chokepoint()
		Template.RUINED_CITY:         _gen_ruined_city()
		Template.CENTRAL_HILL:        _gen_central_hill()
		Template.VALLEY_PASS:         _gen_valley_pass()
		Template.FORTRESS_APPROACH:   _gen_fortress_approach()
		Template.OPEN_FIELD:          _gen_open_field()
		Template.RIVER_CROSSING:      _gen_river_crossing()
		Template.FOREST_AMBUSH:       _gen_forest_ambush()

	# Always generate spawn points
	_place_spawns()

	return {
		"terrain": terrain_grid,
		"width": width,
		"height": height,
		"objects": object_placements,
		"player_spawns": player_spawns,
		"enemy_spawns": enemy_spawns,
		"height_data": height_data,
	}

# ─── Template Generators ─────────────────────────────────────────────────────

func _gen_bridge_chokepoint():
	# River across the middle, single bridge
	var river_z = height / 2
	for x in range(width):
		terrain_grid[river_z][x] = "water"
		terrain_grid[river_z - 1][x] = "water" if rng.randf() < 0.4 else "plain"
	# Bridge in the center
	var bridge_x = width / 2
	for bx in range(bridge_x - 1, bridge_x + 2):
		if bx >= 0 and bx < width:
			terrain_grid[river_z][bx] = "bridge"
			if river_z - 1 >= 0:
				terrain_grid[river_z - 1][bx] = "bridge"
	# Scatter forest on both sides
	_scatter_random_terrain(0, 0, width, river_z - 1, "forest", 0.12)
	_scatter_random_terrain(0, river_z + 1, width, height, "forest", 0.12)
	# Fort near bridge
	if bridge_x + 2 < width and river_z + 2 < height:
		terrain_grid[river_z + 2][bridge_x] = "fort"

func _gen_ruined_city():
	# Ruins scattered densely in the center
	var cx = width / 2
	var cz = height / 2
	for x in range(width):
		for z in range(height):
			var dist = absf(x - cx) + absf(z - cz)
			if dist < 5:
				if rng.randf() < 0.5:
					terrain_grid[z][x] = "ruins"
					if rng.randf() < 0.3:
						object_placements.append({"pos": Vector2i(x, z), "object": "ruins_pillar"})
			elif dist < 8:
				if rng.randf() < 0.25:
					terrain_grid[z][x] = "ruins"
	# Roads leading in
	for x in range(width):
		if absf(x - cx) < 2:
			for z in range(height):
				if terrain_grid[z][x] == "plain":
					terrain_grid[z][x] = "road"

func _gen_central_hill():
	# Elevated center with slopes
	var cx = width / 2
	var cz = height / 2
	for x in range(width):
		for z in range(height):
			var dist = sqrt(pow(x - cx, 2) + pow(z - cz, 2))
			if dist < 3:
				terrain_grid[z][x] = "mountain"
				height_data[Vector2i(x, z)] = 2.0
			elif dist < 5:
				height_data[Vector2i(x, z)] = 1.0
				if rng.randf() < 0.2:
					terrain_grid[z][x] = "forest"
			elif dist < 7:
				height_data[Vector2i(x, z)] = 0.5
	# Throne at peak
	terrain_grid[cz][cx] = "throne"
	height_data[Vector2i(cx, cz)] = 2.5

func _gen_valley_pass():
	# Walls/mountains on sides, narrow pass through middle
	for x in range(width):
		for z in range(height):
			if z <= 2 or z >= height - 3:
				terrain_grid[z][x] = "mountain"
				height_data[Vector2i(x, z)] = 2.0
			elif z == 3 or z == height - 4:
				if rng.randf() < 0.6:
					terrain_grid[z][x] = "mountain"
					height_data[Vector2i(x, z)] = 1.0
	# Road through the pass
	for x in range(width):
		terrain_grid[height / 2][x] = "road"
	_scatter_random_terrain(0, 4, width, height - 4, "forest", 0.08)

func _gen_fortress_approach():
	# Fort in the back-right corner, walls and defenses
	for x in range(width - 4, width):
		for z in range(height - 4, height):
			terrain_grid[z][x] = "fort"
			height_data[Vector2i(x, z)] = 1.0
	# Walls around fort
	for x in range(width - 5, width):
		if height - 5 >= 0:
			terrain_grid[height - 5][x] = "wall"
	for z in range(height - 5, height):
		if width - 5 >= 0:
			terrain_grid[z][width - 5] = "wall"
	# Approach road
	for x in range(0, width - 5):
		terrain_grid[height - 3][x] = "road"
	# Scatter cover
	_scatter_random_terrain(0, 0, width - 5, height - 5, "forest", 0.1)
	_scatter_random_terrain(0, 0, width - 5, height - 5, "ruins", 0.05)

func _gen_open_field():
	_scatter_random_terrain(0, 0, width, height, "forest", 0.08)
	_scatter_random_terrain(0, 0, width, height, "ruins", 0.03)
	# A few scattered water tiles
	for _i in range(3):
		var wx = rng.randi_range(3, width - 4)
		var wz = rng.randi_range(3, height - 4)
		terrain_grid[wz][wx] = "water"

func _gen_river_crossing():
	# Diagonal river
	for x in range(width):
		var z = int(float(x) / float(width) * float(height))
		if z >= 0 and z < height:
			terrain_grid[z][x] = "river"
			if z + 1 < height:
				terrain_grid[z + 1][x] = "river"
	# Multiple bridges
	var bridge_count = 2 + rng.randi_range(0, 1)
	for bi in range(bridge_count):
		var bx = int(float(bi + 1) / float(bridge_count + 1) * float(width))
		var bz = int(float(bx) / float(width) * float(height))
		if bx >= 0 and bx < width and bz >= 0 and bz < height:
			terrain_grid[bz][bx] = "bridge"
			if bz + 1 < height:
				terrain_grid[bz + 1][bx] = "bridge"
	_scatter_random_terrain(0, 0, width, height, "forest", 0.06)

func _gen_forest_ambush():
	# Dense forest everywhere except clearings
	for x in range(width):
		for z in range(height):
			if rng.randf() < 0.35:
				terrain_grid[z][x] = "forest"
				if rng.randf() < 0.5:
					object_placements.append({"pos": Vector2i(x, z), "object": "tree_pine"})
				elif rng.randf() < 0.5:
					object_placements.append({"pos": Vector2i(x, z), "object": "tree_oak"})
	# Clear spawn corners
	for x in range(3):
		for z in range(3):
			terrain_grid[z][x] = "plain"
			terrain_grid[height - 1 - z][width - 1 - x] = "plain"
	# A few clearings
	for _c in range(2):
		var cx = rng.randi_range(4, width - 5)
		var cz = rng.randi_range(4, height - 5)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if cx + dx >= 0 and cx + dx < width and cz + dz >= 0 and cz + dz < height:
					terrain_grid[cz + dz][cx + dx] = "plain"

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _scatter_random_terrain(x0: int, z0: int, x1: int, z1: int, terrain: String, probability: float):
	for x in range(x0, x1):
		for z in range(z0, z1):
			if x >= 0 and x < width and z >= 0 and z < height:
				if terrain_grid[z][x] == "plain" and rng.randf() < probability:
					terrain_grid[z][x] = terrain

func _place_spawns():
	# Player spawns: bottom-left corner
	for x in range(min(3, width)):
		for z in range(min(3, height)):
			if terrain_grid[z][x] in ["plain", "road", "fort"]:
				player_spawns.append(Vector2i(x, z))
	# Enemy spawns: top-right corner
	for x in range(max(0, width - 3), width):
		for z in range(max(0, height - 3), height):
			if terrain_grid[z][x] in ["plain", "road", "fort", "ruins"]:
				enemy_spawns.append(Vector2i(x, z))

# ─── Random Template Selection ──────────────────────────────────────────────

static func random_template(rng_inst: RandomNumberGenerator = null) -> Template:
	var values = Template.values()
	if rng_inst:
		return values[rng_inst.randi_range(0, values.size() - 1)]
	return values[randi() % values.size()]
