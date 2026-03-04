class_name DoctrineMapLoader
extends RefCounted
## Converts MapJSON (from generated output) to the format the existing
## Grid3D / battle engine expects.
##
## Grid3D.load_chapter_terrain(terrain_data, width, height) expects:
##   terrain_data: 2D array indexed [z][x], each cell a terrain-type string
##                 that Tile.set_terrain() understands ("plain", "forest", etc.)
##   width:  number of columns (x)
##   height: number of rows (z)
##
## MapJSON from DoctrineMapGen has:
##   size: [width, height]
##   terrain: 2D array [y][x] of generator terrain strings
##   height:  2D array [y][x] of integer height values
##   spawns: {player: [[x,y],...], enemy: [[x,y],...]}
##   props: [{prefab, pos:[x,y], rot}, ...]

# Generator terrain → Tile.set_terrain() string mapping
const _TERRAIN_MAP: Dictionary = {
	"grass": "plain",
	"stone": "ruins",
	"dirt": "road",
	"water": "water",
	"wall": "wall",
	"bridge": "bridge",
	"sand": "sand",
	"ice": "water",
	"rock": "mountain",
	"snow": "plain",
	"mud": "plain",
	"forest": "forest",
	"lava": "lava",
	"road": "road",
	# Pass-through for already-correct strings
	"plain": "plain",
	"ruins": "ruins",
	"fort": "fort",
	"village": "village",
	"throne": "throne",
	"mountain": "mountain",
	"river": "river",
}

# Kit prefab → Tile.set_object() string mapping
const _PREFAB_MAP: Dictionary = {
	"crate": "crate",
	"barrel": "barrel",
	"tree_pine": "tree_pine",
	"tree_oak": "tree_oak",
	"tree_dead": "tree_dead",
	"rock_small": "bush",
	"rock_large": "ruins_pillar",
	"rubble_pile": "ruins_pillar",
	"pillar_broken": "ruins_pillar",
	"statue_broken": "statue",
	"banner_torn": "signpost",
	"bridge_post": "fence_v",
	"tower_1x1": "tower",
	"tower_2x2": "tower",
	"wall_straight": "fence_h",
	"wall_corner": "fence_h",
	"wall_broken": "ruins_arch",
	"wall_t_junction": "fence_h",
	"wall_endcap": "fence_h",
	"gate_open": "ruins_arch",
	"gate_closed": "fence_h",
	"well": "well",
	"campfire": "signpost",
	"grave_marker": "signpost",
	"ice_shard": "ruins_pillar",
	"frozen_tree": "tree_dead",
}


## Loads a MapJSON file and converts it into the dict format used by Grid3D.
## Returns: {terrain_data, width, height, height_map, objects, player_spawns,
##           enemy_spawns, biome, objective, props_raw}
## Returns an empty dict on failure.
func load_map(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DoctrineMapLoader: file not found at '%s'" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DoctrineMapLoader: could not open '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("DoctrineMapLoader: JSON parse error in '%s': %s" % [path, json.get_error_message()])
		return {}

	var map_json: Variant = json.data
	if not (map_json is Dictionary):
		push_error("DoctrineMapLoader: root JSON is not a Dictionary in '%s'" % path)
		return {}

	return _convert(map_json)


## Converts a MapJSON dictionary (already parsed) into the engine format.
func convert_map(map_json: Dictionary) -> Dictionary:
	return _convert(map_json)


# ── Internal conversion ───────────────────────────────────────────────────────

func _convert(map_json: Dictionary) -> Dictionary:
	# Resolve dimensions: support both "size": [w, h] and "width"/"height" keys
	var width: int = 0
	var height: int = 0
	var size_arr: Variant = map_json.get("size", null)
	if size_arr is Array and size_arr.size() >= 2:
		width = int(size_arr[0])
		height = int(size_arr[1])
	else:
		width = int(map_json.get("width", 0))
		# "height" may be the height_map array, so check type
		var h_val: Variant = map_json.get("height", 0)
		if h_val is Array:
			height = h_val.size()
		else:
			height = int(h_val)

	if width <= 0 or height <= 0:
		push_error("DoctrineMapLoader: invalid dimensions %dx%d" % [width, height])
		return {}

	# Convert terrain 2D array with string mapping
	var terrain_data: Array = _convert_terrain(map_json, width, height)

	# Extract height map as Dictionary[Vector2i → float]
	var height_map: Dictionary = _convert_height_map(map_json, width, height)

	# Convert props to objects list for Grid3D.place_terrain_object()
	var objects: Array = _convert_props(map_json)

	# Spawn points: support both "spawns" dict and flat keys
	var spawns: Dictionary = map_json.get("spawns", {})
	var player_spawns_raw: Array = spawns.get("player", map_json.get("player_spawns", []))
	var enemy_spawns_raw: Array = spawns.get("enemy", map_json.get("enemy_spawns", []))
	var player_spawns: Array = _convert_spawns(player_spawns_raw)
	var enemy_spawns: Array = _convert_spawns(enemy_spawns_raw)

	return {
		"terrain_data": terrain_data,
		"width": width,
		"height": height,
		"height_map": height_map,
		"objects": objects,
		"player_spawns": player_spawns,
		"enemy_spawns": enemy_spawns,
		"biome": map_json.get("biome", ""),
		"objective": map_json.get("objective", ""),
		"props_raw": map_json.get("props", []),
		"tile_states": map_json.get("tile_states", []),
	}


## Converts terrain strings from generator format to Tile.set_terrain() format.
func _convert_terrain(map_json: Dictionary, width: int, height: int) -> Array:
	var terrain_2d: Array = map_json.get("terrain", [])
	var result: Array = []
	result.resize(height)

	for z in range(height):
		var row: Array = []
		row.resize(width)
		var src_row: Array = terrain_2d[z] if z < terrain_2d.size() else []
		for x in range(width):
			var gen_str: String = str(src_row[x]) if x < src_row.size() else "plain"
			row[x] = _TERRAIN_MAP.get(gen_str, gen_str)
		result[z] = row

	return result


## Builds a Dictionary[Vector2i → float] height map from the MapJSON height grid.
## Generator height values are integer steps; we multiply by HEIGHT_STEP to get
## world-unit Y values that match Grid3D's expected scale.
const _HEIGHT_STEP: float = 0.5

func _convert_height_map(map_json: Dictionary, width: int, height: int) -> Dictionary:
	var height_val: Variant = map_json.get("height", [])
	var height_2d: Array = height_val if height_val is Array else []
	var result: Dictionary = {}

	for z in range(height):
		var src_row: Array = height_2d[z] if z < height_2d.size() else []
		for x in range(width):
			var h: float = 0.0
			if x < src_row.size():
				h = float(src_row[x]) * _HEIGHT_STEP
			result[Vector2i(x, z)] = h

	return result


## Converts props array to objects list for Grid3D.place_terrain_object().
## Each prop: {"prefab": "piece_id", "pos": [x, y], "rot": 0}
## Output: {"pos": Vector2i, "type": "tile_object_str"}
func _convert_props(map_json: Dictionary) -> Array:
	var props: Array = map_json.get("props", [])
	var result: Array = []

	for prop in props:
		if not (prop is Dictionary):
			continue
		var prefab: String = prop.get("prefab", "")
		var obj_str: String = _PREFAB_MAP.get(prefab, "")
		if obj_str == "":
			continue
		var pos: Array = prop.get("pos", [0, 0])
		if pos.size() >= 2:
			result.append({
				"pos": Vector2i(int(pos[0]), int(pos[1])),
				"type": obj_str,
			})

	return result


## Converts spawn point arrays to Array of Vector2i.
func _convert_spawns(spawns_raw: Array) -> Array:
	var result: Array = []
	for entry in spawns_raw:
		if entry is Array and entry.size() >= 2:
			result.append(Vector2i(int(entry[0]), int(entry[1])))
		elif entry is Dictionary:
			var x: int = int(entry.get("x", entry.get(0, 0)))
			var z: int = int(entry.get("z", entry.get("y", entry.get(1, 0))))
			result.append(Vector2i(x, z))
	return result
