class_name MissionBattleLoader
extends RefCounted
## Orchestrates loading a generated mission into the battle engine.
##
## Ties together MissionLoader, DoctrineMapLoader, and ItemLoader to:
## 1. Load mission + map + loot data from generated JSON files
## 2. Build the Grid3D terrain from map data
## 3. Inject the procedural height map
## 4. Place terrain objects from props
## 5. Spawn player units at map spawn points
## 6. Spawn enemy units from mission roster at map enemy spawns
## 7. Return a bundle dict ready for TurnManager setup
##
## Usage from Battle3D:
##   var loader = MissionBattleLoader.new()
##   var result = loader.load_mission_into_battle(mission_path, grid, player_chars)
##   if result.ok:
##       units = result.units
##       turn_manager.units = units
##       turn_manager.grid = grid

# Keyword → enemy archetype fallback mapping.
# When a faction-specific unit_def (e.g. "covenant_templar") isn't in enemies.json,
# we match keywords in the name to a generic archetype.
const _ARCHETYPE_KEYWORDS: Array = [
	["commander", "commander"],
	["captain", "commander"],
	["knight", "blood_knight"],
	["paladin", "paladin"],
	["warden", "heavy"],
	["bulwark", "heavy"],
	["ironhelm", "heavy"],
	["heavy", "heavy"],
	["templar", "heavy"],
	["pikeman", "heavy"],
	["archer", "archer"],
	["scout", "archer"],
	["slingman", "archer"],
	["bow", "archer"],
	["mage", "mage"],
	["hexblade", "mage"],
	["scholar", "mage"],
	["siege", "siege_mage"],
	["priest", "priest"],
	["acolyte", "priest"],
	["inquisitor", "mage"],
	["rogue", "rogue"],
	["cutthroat", "rogue"],
	["assassin", "assassin"],
	["duelist", "rogue"],
	["runner", "rogue"],
	["golem", "golem"],
	["guard", "heavy"],
	["spearman", "grunt"],
	["sword", "grunt"],
	["levy", "grunt"],
	["novice", "archer"],
]

const OUTPUT_ROOT: String = "res://output"


## Loads a mission and populates a Grid3D with terrain, height, objects, and units.
##
## mission_path: path to mission JSON file (e.g. "res://output/missions/ch01_m01.json")
## grid: an existing Grid3D node (already added to scene tree)
## player_char_ids: Array of player character IDs (e.g. ["aldric", "mira", ...])
##
## Returns: {ok: bool, units: Array[Unit], mission: Dictionary,
##           loot_items: Array, objective: String, error: String}
func load_mission_into_battle(mission_path: String, grid, player_char_ids: Array) -> Dictionary:
	DebugLogger.checkpoint_start("mbl_load", "MissionBattleLoader", "Load mission into battle")
	DebugLogger.audit("MissionBattleLoader", "Starting load", {"path": mission_path, "players": player_char_ids.size()})

	# Verify file exists
	if not FileAccess.file_exists(mission_path):
		DebugLogger.err("MissionBattleLoader", "Mission file does not exist", {"path": mission_path})
		DebugLogger.checkpoint_end("mbl_load", false, "File not found: %s" % mission_path)
		return {"ok": false, "error": "File not found: '%s'" % mission_path, "units": [], "mission": {}, "loot_items": [], "objective": "rout"}

	# 1. Load the mission bundle
	DebugLogger.checkpoint_start("mbl_bundle", "MissionLoader", "Load mission bundle")
	var ml := MissionLoader.new()
	var bundle: Dictionary = ml.load_mission_bundle(mission_path, OUTPUT_ROOT)
	if bundle.is_empty():
		DebugLogger.checkpoint_end("mbl_bundle", false, "Bundle is empty")
		DebugLogger.checkpoint_end("mbl_load", false, "Failed to load bundle")
		return {"ok": false, "error": "Failed to load mission bundle from '%s'" % mission_path, "units": [], "mission": {}, "loot_items": [], "objective": "rout"}
	DebugLogger.checkpoint_end("mbl_bundle", true)

	var mission: Dictionary = bundle["mission"]
	var map_data: Dictionary = bundle["map_data"]
	var loot_items: Array = bundle["loot_items"]

	DebugLogger.audit("MissionBattleLoader", "Bundle loaded", {
		"mission_id": str(mission.get("id", "?")),
		"map_width": map_data.get("width", 0),
		"map_height": map_data.get("height", 0),
		"has_terrain": map_data.has("terrain_data"),
		"has_height_map": map_data.has("height_map"),
		"has_props": map_data.has("props_raw"),
		"loot_count": loot_items.size(),
	})

	if map_data.is_empty():
		DebugLogger.checkpoint_end("mbl_load", false, "Map data is empty")
		return {"ok": false, "error": "Map data is empty for mission '%s'" % mission.get("id", "?"), "units": [], "mission": mission, "loot_items": loot_items, "objective": "rout"}

	# 2. Build grid terrain
	var terrain_data: Array = map_data["terrain_data"]
	var width: int = map_data["width"]
	var height: int = map_data["height"]
	grid.load_chapter_terrain(terrain_data, width, height)

	# 3. Inject procedural height map (overrides Grid3D's auto-generated one)
	var height_map: Dictionary = map_data.get("height_map", {})
	if not height_map.is_empty():
		grid.load_height_map(height_map)

	# 4. Place props — use place_props() for 3D prefab instancing if available,
	# otherwise fall back to place_terrain_object() for logic-only objects
	var props_raw: Array = map_data.get("props_raw", [])
	if not props_raw.is_empty() and grid.has_method("place_props"):
		grid.place_props(props_raw)
	else:
		var objects: Array = map_data.get("objects", [])
		for obj in objects:
			if obj is Dictionary:
				var pos = obj.get("pos", null)
				var obj_type: String = obj.get("type", "")
				if pos is Vector2i and obj_type != "":
					grid.place_terrain_object(pos, obj_type)

	# 4b. Apply tile anomalies (elemental states from biome generation)
	var tile_states: Array = map_data.get("tile_states", [])
	for ts in tile_states:
		if ts is Dictionary:
			var ts_pos: Array = ts.get("pos", [])
			var ts_state: String = ts.get("state", "")
			var ts_dur: int = int(ts.get("duration", 99))
			if ts_pos.size() >= 2 and ts_state != "":
				var tpos := Vector2i(int(ts_pos[0]), int(ts_pos[1]))
				if grid.tiles.has(tpos):
					grid.tiles[tpos].set_elemental_state(ts_state, ts_dur)
	# Refresh tile colors and show anomaly decals
	if not tile_states.is_empty():
		if grid.has_method("refresh_all_tiles"):
			grid.refresh_all_tiles()
		if grid.has_method("show_anomaly_decals"):
			grid.show_anomaly_decals()

	# 5. Spawn player units
	var units: Array = []
	var player_spawns: Array = map_data.get("player_spawns", [])
	for i in range(player_char_ids.size()):
		var char_id: String = player_char_ids[i]
		var spawn_pos: Vector2i
		if i < player_spawns.size():
			spawn_pos = player_spawns[i]
		else:
			spawn_pos = _fallback_spawn(i, 0, 0)
		spawn_pos = _open_tile(grid, spawn_pos)
		var u = CharacterRoster.build_player_unit(char_id, spawn_pos)
		if u:
			_register_unit(grid, units, u)

	# 6. Spawn enemy units from roster
	var roster: Array = ml.get_enemy_roster(mission)
	var enemy_spawns: Array = map_data.get("enemy_spawns", [])
	for i in range(roster.size()):
		var entry: Dictionary = roster[i]
		var unit_def: String = entry.get("unit_def", "grunt")
		var enemy_type: String = _resolve_enemy_type(unit_def)
		var spawn_pos: Vector2i
		if i < enemy_spawns.size():
			spawn_pos = enemy_spawns[i]
		else:
			spawn_pos = _fallback_spawn(i, grid.grid_width - 1, grid.grid_height - 1)
		spawn_pos = _open_tile(grid, spawn_pos)
		var suffix: String = str(i + 1) if i < 3 else ""
		var u = CharacterRoster.build_enemy_unit(enemy_type, spawn_pos, suffix)
		if u:
			_register_unit(grid, units, u)

	grid.units_ref = units

	# 7. Resolve objective
	var obj_raw: Variant = mission.get("objective", "rout")
	var objective: String = ""
	if obj_raw is Dictionary:
		objective = obj_raw.get("type", "rout")
	elif obj_raw is String:
		objective = obj_raw
	else:
		objective = "rout"

	DebugLogger.audit("MissionBattleLoader", "Battle assembled", {
		"units": units.size(),
		"player": units.filter(func(u): return u.is_player_unit).size(),
		"enemy": units.filter(func(u): return not u.is_player_unit).size(),
		"objective": objective,
		"tiles": grid.tiles.size(),
	})
	DebugLogger.checkpoint_end("mbl_load", true)

	return {
		"ok": true,
		"units": units,
		"mission": mission,
		"loot_items": loot_items,
		"objective": objective,
		"error": "",
	}


# ── Helpers ──────────────────────────────────────────────────────────────────

## Resolves a faction-specific unit_def to a generic enemy type from enemies.json.
func _resolve_enemy_type(unit_def: String) -> String:
	# Try exact match first
	if DataLoader.enemies_data.has(unit_def):
		return unit_def

	# Keyword fallback: check if any keyword appears in the unit_def
	var lower: String = unit_def.to_lower()
	for pair in _ARCHETYPE_KEYWORDS:
		if lower.contains(pair[0]):
			return pair[1]

	# Last resort: generic grunt
	return "grunt"


## Finds an open tile near the preferred position.
func _open_tile(grid, prefer: Vector2i) -> Vector2i:
	if grid.tiles.has(prefer) and grid.tiles[prefer].is_passable and grid.tiles[prefer].occupant == null:
		return prefer
	var dirs: Array = [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for d in dirs:
		var a: Vector2i = prefer + d
		if grid.tiles.has(a) and grid.tiles[a].is_passable and grid.tiles[a].occupant == null:
			return a
	# Expand search radius
	for r in range(2, 5):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var a: Vector2i = prefer + Vector2i(dx, dy)
				if grid.tiles.has(a) and grid.tiles[a].is_passable and grid.tiles[a].occupant == null:
					return a
	return prefer


## Registers a unit on the grid.
func _register_unit(grid, units: Array, u: Unit) -> void:
	if grid.tiles.has(u.grid_position):
		grid.tiles[u.grid_position].occupant = u
	units.append(u)


## Fallback spawn position when map doesn't have enough spawn points.
func _fallback_spawn(index: int, base_x: int, base_y: int) -> Vector2i:
	return Vector2i(base_x + (index % 3), base_y + (index / 3))
