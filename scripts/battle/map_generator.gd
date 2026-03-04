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
	SNOW_FIELD,
	DESERT_RUINS,
	VILLAGE_DEFENSE,
	CLIFF_ASSAULT,
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
			row.append("grass")
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
		Template.SNOW_FIELD:          _gen_snow_field()
		Template.DESERT_RUINS:        _gen_desert_ruins()
		Template.VILLAGE_DEFENSE:     _gen_village_defense()
		Template.CLIFF_ASSAULT:       _gen_cliff_assault()

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
		terrain_grid[river_z - 1][x] = "water" if rng.randf() < 0.4 else "grass"
	# Bridge in the center
	var bridge_x = width / 2
	for bx in range(bridge_x - 1, bridge_x + 2):
		if bx >= 0 and bx < width:
			terrain_grid[river_z][bx] = "bridge"
			if river_z - 1 >= 0:
				terrain_grid[river_z - 1][bx] = "bridge"
	# Dirt near the bridge approaches
	for bx in range(bridge_x - 2, bridge_x + 3):
		for dz in [river_z - 2, river_z + 1, river_z + 2]:
			if bx >= 0 and bx < width and dz >= 0 and dz < height:
				if terrain_grid[dz][bx] == "grass":
					terrain_grid[dz][bx] = "dirt"
	# Road from bridge to fort
	if bridge_x < width and river_z + 2 < height:
		for rz in range(river_z + 1, min(river_z + 5, height)):
			if terrain_grid[rz][bridge_x] != "water":
				terrain_grid[rz][bridge_x] = "road"
	# Scatter forest on both sides
	_scatter_random_terrain(0, 0, width, river_z - 1, "forest", 0.12)
	_scatter_random_terrain(0, river_z + 1, width, height, "forest", 0.12)
	# Fort near bridge
	if bridge_x + 2 < width and river_z + 2 < height:
		terrain_grid[river_z + 2][bridge_x] = "fort"

func _gen_ruined_city():
	# Ruins scattered densely in the center with stone base
	var cx = width / 2
	var cz = height / 2
	for x in range(width):
		for z in range(height):
			var dist = absf(x - cx) + absf(z - cz)
			if dist < 5:
				terrain_grid[z][x] = "stone"
				if rng.randf() < 0.5:
					terrain_grid[z][x] = "ruins"
					if rng.randf() < 0.3:
						object_placements.append({"pos": Vector2i(x, z), "object": "ruins_pillar"})
					elif rng.randf() < 0.25:
						object_placements.append({"pos": Vector2i(x, z), "object": "ruins_wall"})
			elif dist < 8:
				if rng.randf() < 0.25:
					terrain_grid[z][x] = "ruins"
				elif rng.randf() < 0.15:
					object_placements.append({"pos": Vector2i(x, z), "object": "rock_small"})
	# Roads leading in
	for x in range(width):
		if absf(x - cx) < 2:
			for z in range(height):
				if terrain_grid[z][x] == "grass":
					terrain_grid[z][x] = "road"

func _gen_central_hill():
	# Elevated center with rock on hill and dirt transition
	var cx = width / 2
	var cz = height / 2
	for x in range(width):
		for z in range(height):
			var dist = sqrt(pow(x - cx, 2) + pow(z - cz, 2))
			if dist < 3:
				terrain_grid[z][x] = "rock"
				height_data[Vector2i(x, z)] = 2.0
			elif dist < 5:
				terrain_grid[z][x] = "dirt"
				height_data[Vector2i(x, z)] = 1.0
				if rng.randf() < 0.2:
					terrain_grid[z][x] = "forest"
			elif dist < 7:
				height_data[Vector2i(x, z)] = 0.5
	# Throne at peak
	terrain_grid[cz][cx] = "throne"
	height_data[Vector2i(cx, cz)] = 2.5

func _gen_valley_pass():
	# Rock mountain walls, grass floor, scattered rocks
	for x in range(width):
		for z in range(height):
			if z <= 2 or z >= height - 3:
				terrain_grid[z][x] = "rock"
				height_data[Vector2i(x, z)] = 2.0
			elif z == 3 or z == height - 4:
				if rng.randf() < 0.6:
					terrain_grid[z][x] = "rock"
					height_data[Vector2i(x, z)] = 1.0
	# Road through the pass
	for x in range(width):
		terrain_grid[height / 2][x] = "road"
	_scatter_random_terrain(0, 4, width, height - 4, "forest", 0.08)
	_scatter_objects(0, 4, width, height - 4, ["rock_small", "rock_large"], 0.06)

func _gen_fortress_approach():
	# Stone fort area, grass approach, wood_wall defenses
	for x in range(width - 4, width):
		for z in range(height - 4, height):
			terrain_grid[z][x] = "stone"
			height_data[Vector2i(x, z)] = 1.0
	# Wood walls around fort
	for x in range(width - 5, width):
		if height - 5 >= 0:
			terrain_grid[height - 5][x] = "stone"
			object_placements.append({"pos": Vector2i(x, height - 5), "object": "wood_wall"})
	for z in range(height - 5, height):
		if width - 5 >= 0:
			terrain_grid[z][width - 5] = "stone"
			object_placements.append({"pos": Vector2i(width - 5, z), "object": "wood_wall"})
	# Approach road
	for x in range(0, width - 5):
		terrain_grid[height - 3][x] = "road"
	# Scatter cover
	_scatter_random_terrain(0, 0, width - 5, height - 5, "forest", 0.1)
	_scatter_random_terrain(0, 0, width - 5, height - 5, "ruins", 0.05)

func _gen_open_field():
	# Grass base with scattered cover
	_scatter_random_terrain(0, 0, width, height, "forest", 0.08)
	_scatter_random_terrain(0, 0, width, height, "ruins", 0.03)
	_scatter_objects(0, 0, width, height, ["rock_small"], 0.04)
	# A few scattered water tiles
	for _i in range(3):
		var wx = rng.randi_range(3, width - 4)
		var wz = rng.randi_range(3, height - 4)
		terrain_grid[wz][wx] = "water"

func _gen_river_crossing():
	# Diagonal river with dirt banks and log objects
	for x in range(width):
		var z = int(float(x) / float(width) * float(height))
		if z >= 0 and z < height:
			terrain_grid[z][x] = "river"
			if z + 1 < height:
				terrain_grid[z + 1][x] = "river"
			# Dirt near river banks
			if z - 1 >= 0 and terrain_grid[z - 1][x] == "grass":
				terrain_grid[z - 1][x] = "dirt"
			if z + 2 < height and terrain_grid[z + 2][x] == "grass":
				terrain_grid[z + 2][x] = "dirt"
	# Log objects near water
	for x in range(width):
		var z = int(float(x) / float(width) * float(height))
		if rng.randf() < 0.15:
			var lz = z - 1 if z - 1 >= 0 else z + 2
			if lz >= 0 and lz < height:
				object_placements.append({"pos": Vector2i(x, lz), "object": "log"})
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
	# Dense forest with root and log objects scattered in forest areas
	for x in range(width):
		for z in range(height):
			if rng.randf() < 0.35:
				terrain_grid[z][x] = "forest"
				if rng.randf() < 0.5:
					object_placements.append({"pos": Vector2i(x, z), "object": "tree_pine"})
				elif rng.randf() < 0.5:
					object_placements.append({"pos": Vector2i(x, z), "object": "tree_oak"})
				elif rng.randf() < 0.4:
					object_placements.append({"pos": Vector2i(x, z), "object": "root"})
				elif rng.randf() < 0.3:
					object_placements.append({"pos": Vector2i(x, z), "object": "log"})
				elif rng.randf() < 0.3:
					object_placements.append({"pos": Vector2i(x, z), "object": "bush"})
	# Clear spawn corners
	for x in range(3):
		for z in range(3):
			terrain_grid[z][x] = "grass"
			terrain_grid[height - 1 - z][width - 1 - x] = "grass"
	# A few clearings
	for _c in range(2):
		var cx = rng.randi_range(4, width - 5)
		var cz = rng.randi_range(4, height - 5)
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				if cx + dx >= 0 and cx + dx < width and cz + dz >= 0 and cz + dz < height:
					terrain_grid[cz + dz][cx + dx] = "grass"

func _gen_snow_field():
	# Snow base terrain with ice patches, rock outcrops, dead trees
	for z in range(height):
		for x in range(width):
			terrain_grid[z][x] = "snow"
	# Ice patches
	var ice_count = rng.randi_range(3, 6)
	for _i in range(ice_count):
		var ix = rng.randi_range(2, width - 3)
		var iz = rng.randi_range(2, height - 3)
		var ice_size = rng.randi_range(1, 3)
		for dx in range(-ice_size, ice_size + 1):
			for dz in range(-ice_size, ice_size + 1):
				var px = ix + dx
				var pz = iz + dz
				if px >= 0 and px < width and pz >= 0 and pz < height:
					if rng.randf() < 0.7:
						terrain_grid[pz][px] = "ice"
	# Rock outcrops
	_scatter_objects(0, 0, width, height, ["rock_small", "rock_large"], 0.06)
	# Dead trees scattered around
	for x in range(width):
		for z in range(height):
			if terrain_grid[z][x] == "snow" and rng.randf() < 0.06:
				object_placements.append({"pos": Vector2i(x, z), "object": "tree_dead"})

func _gen_desert_ruins():
	# Sand base with stone ruins area, rock outcrops
	for z in range(height):
		for x in range(width):
			terrain_grid[z][x] = "sand"
	# Stone ruins cluster in center
	var cx = width / 2
	var cz = height / 2
	for x in range(width):
		for z in range(height):
			var dist = absf(x - cx) + absf(z - cz)
			if dist < 5:
				terrain_grid[z][x] = "stone"
				if rng.randf() < 0.35:
					terrain_grid[z][x] = "ruins"
					if rng.randf() < 0.3:
						object_placements.append({"pos": Vector2i(x, z), "object": "ruins_pillar"})
					elif rng.randf() < 0.25:
						object_placements.append({"pos": Vector2i(x, z), "object": "ruins_wall"})
			elif dist < 8 and rng.randf() < 0.1:
				object_placements.append({"pos": Vector2i(x, z), "object": "rock_small"})
	# Rock outcrops at edges
	_scatter_objects(0, 0, width, 3, ["rock_small", "rock_large"], 0.1)
	_scatter_objects(0, height - 3, width, height, ["rock_small", "rock_large"], 0.1)

func _gen_village_defense():
	# Grass base with a cluster of buildings, roads connecting them
	var cx = width / 2
	var cz = height / 2

	# Place a few buildings using modular pieces
	# Small house 1 - top-left of village center
	var hx1 = cx - 3
	var hz1 = cz - 2
	_place_building(hx1, hz1, [
		[0, 0, "wood_wall"], [1, 0, "door"],
		[0, 1, "wood_wall"], [1, 1, "window"],
		[0, -1, "roof"], [1, -1, "roof"],
	])

	# Large house - center-right
	var hx2 = cx + 1
	var hz2 = cz - 1
	_place_building(hx2, hz2, [
		[0, 0, "wood_wall"], [1, 0, "wood_wall"], [2, 0, "wood_wall"],
		[0, 1, "wood_wall"], [1, 1, "door"], [2, 1, "window"],
		[0, -1, "roof"], [1, -1, "roof"], [2, -1, "roof"],
	])

	# Guard post - bottom of village
	var hx3 = cx - 1
	var hz3 = cz + 3
	_place_building(hx3, hz3, [
		[0, 0, "wood_wall"], [1, 0, "wood_corner"],
		[0, 1, "wood_corner"], [1, 1, "window"],
	])

	# Roads connecting buildings
	for x in range(hx1, hx2 + 3):
		if x >= 0 and x < width:
			terrain_grid[cz][x] = "road"
	for z in range(hz1, hz3 + 2):
		if z >= 0 and z < height:
			if terrain_grid[z][cx] == "grass":
				terrain_grid[z][cx] = "road"

	# Scatter some objects around the village
	_scatter_random_terrain(0, 0, width, height, "forest", 0.04, ["rock_small"])

func _gen_cliff_assault():
	# Multi-height terrain with rock/stone, narrow paths
	# Bottom half is lower elevation, top half is the cliff
	var cliff_z = height / 2

	# Lower area - grass/dirt
	for x in range(width):
		for z in range(cliff_z + 1, height):
			terrain_grid[z][x] = "grass"

	# Cliff face - rock wall
	for x in range(width):
		terrain_grid[cliff_z][x] = "rock"
		height_data[Vector2i(x, cliff_z)] = 2.0
		if cliff_z - 1 >= 0:
			terrain_grid[cliff_z - 1][x] = "rock"
			height_data[Vector2i(x, cliff_z - 1)] = 2.5

	# Upper plateau - stone
	for x in range(width):
		for z in range(0, cliff_z - 1):
			terrain_grid[z][x] = "stone"
			height_data[Vector2i(x, z)] = 2.0

	# Narrow paths up the cliff (2-3 choke points)
	var path_count = rng.randi_range(2, 3)
	for pi in range(path_count):
		var px = int(float(pi + 1) / float(path_count + 1) * float(width))
		for pz in range(cliff_z - 1, cliff_z + 1):
			if px >= 0 and px < width and pz >= 0 and pz < height:
				terrain_grid[pz][px] = "dirt"
				height_data[Vector2i(px, pz)] = 1.0
		# Widen path slightly
		if px + 1 < width:
			for pz in range(cliff_z - 1, cliff_z + 1):
				if pz >= 0 and pz < height:
					terrain_grid[pz][px + 1] = "dirt"
					height_data[Vector2i(px + 1, pz)] = 1.0

	# Scatter rocks on both levels
	_scatter_objects(0, 0, width, cliff_z - 1, ["rock_small", "rock_large"], 0.08)
	_scatter_objects(0, cliff_z + 1, width, height, ["rock_small"], 0.05)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _scatter_random_terrain(x0: int, z0: int, x1: int, z1: int, terrain: String, probability: float, objects: Array = []):
	for x in range(x0, x1):
		for z in range(z0, z1):
			if x >= 0 and x < width and z >= 0 and z < height:
				if terrain_grid[z][x] == "grass" and rng.randf() < probability:
					terrain_grid[z][x] = terrain
				elif objects.size() > 0 and terrain_grid[z][x] == "grass" and rng.randf() < probability * 0.5:
					var obj = objects[rng.randi_range(0, objects.size() - 1)]
					object_placements.append({"pos": Vector2i(x, z), "object": obj})

func _scatter_objects(x0: int, z0: int, x1: int, z1: int, obj_list: Array, probability: float):
	for x in range(x0, x1):
		for z in range(z0, z1):
			if x >= 0 and x < width and z >= 0 and z < height:
				if rng.randf() < probability:
					var obj = obj_list[rng.randi_range(0, obj_list.size() - 1)]
					object_placements.append({"pos": Vector2i(x, z), "object": obj})

func _place_building(bx: int, bz: int, parts: Array):
	for part in parts:
		var px = bx + part[0]
		var pz = bz + part[1]
		if px >= 0 and px < width and pz >= 0 and pz < height:
			object_placements.append({"pos": Vector2i(px, pz), "object": part[2]})

func _place_spawns():
	# Player spawns: bottom-left corner
	for x in range(min(3, width)):
		for z in range(min(3, height)):
			if terrain_grid[z][x] in ["grass", "road", "fort", "snow", "sand", "dirt", "stone"]:
				player_spawns.append(Vector2i(x, z))
	# Enemy spawns: top-right corner
	for x in range(max(0, width - 3), width):
		for z in range(max(0, height - 3), height):
			if terrain_grid[z][x] in ["grass", "road", "fort", "ruins", "snow", "sand", "dirt", "stone"]:
				enemy_spawns.append(Vector2i(x, z))

# ─── Random Template Selection ──────────────────────────────────────────────

static func random_template(rng_inst: RandomNumberGenerator = null) -> Template:
	var values = Template.values()
	if rng_inst:
		return values[rng_inst.randi_range(0, values.size() - 1)]
	return values[randi() % values.size()]
