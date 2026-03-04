class_name MissionLoader
extends RefCounted
## Loads a mission JSON file and prepares its data for the battle engine.


## Loads a mission JSON file from disk and returns the parsed dictionary.
## Returns an empty dict on failure.
func load_mission(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("MissionLoader: file not found at '%s'" % path)
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("MissionLoader: could not open '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return {}

	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("MissionLoader: JSON parse error in '%s': %s" % [path, json.get_error_message()])
		return {}

	var data: Variant = json.data
	if not (data is Dictionary):
		push_error("MissionLoader: root JSON is not a Dictionary in '%s'" % path)
		return {}

	return data


## Extracts the enemy roster array from a mission dictionary.
## Each entry has: {unit_def: String, level: int, id: String (optional)}
## Returns an empty array if no roster is present.
func get_enemy_roster(mission: Dictionary) -> Array:
	var roster_raw: Array = mission.get("enemy_roster", [])
	var result: Array = []

	for entry in roster_raw:
		if not (entry is Dictionary):
			continue
		var unit_def: String = entry.get("unit_def", "")
		if unit_def == "":
			continue
		result.append({
			"unit_def": unit_def,
			"level": int(entry.get("level", 1)),
			"id": entry.get("id", ""),
		})

	return result


## Returns the mission objective type string (e.g. "rout", "seize", "survive").
func get_objective(mission: Dictionary) -> String:
	return mission.get("objective", "rout")


## Returns the mission title or id.
func get_title(mission: Dictionary) -> String:
	return mission.get("title", mission.get("id", "Unknown Mission"))


## Returns the mission rewards dictionary.
func get_rewards(mission: Dictionary) -> Dictionary:
	return mission.get("rewards", {})


## Returns the chapter number this mission belongs to.
func get_chapter(mission: Dictionary) -> int:
	return int(mission.get("chapter", 1))


## Returns the region id for the mission.
func get_region(mission: Dictionary) -> String:
	return mission.get("region", "")


## Returns the faction id for the mission.
func get_faction(mission: Dictionary) -> String:
	return mission.get("faction", "")


## Returns the map file path (relative filename) for the mission.
func get_map_file(mission: Dictionary) -> String:
	return mission.get("map_file", "")


## Returns the loot file path (relative filename) for the mission.
func get_loot_file(mission: Dictionary) -> String:
	return mission.get("loot_file", "")


## Convenience: loads a mission and its associated map data.
## base_dir: the directory where mission, map, and loot files reside
##           (e.g. "res://output").
## Returns {mission, map_data, loot_items} or empty dict on failure.
func load_mission_bundle(mission_path: String, base_dir: String) -> Dictionary:
	var mission: Dictionary = load_mission(mission_path)
	if mission.is_empty():
		return {}

	var map_file: String = get_map_file(mission)
	var loot_file: String = get_loot_file(mission)

	var map_data: Dictionary = {}
	if map_file != "":
		var map_path: String = "%s/maps/%s" % [base_dir, map_file]
		var map_loader := DoctrineMapLoader.new()
		map_data = map_loader.load_map(map_path)

	var loot_items: Array = []
	if loot_file != "":
		var loot_path: String = "%s/loot/%s" % [base_dir, loot_file]
		var item_loader := ItemLoader.new()
		loot_items = item_loader.load_items(loot_path)

	return {
		"mission": mission,
		"map_data": map_data,
		"loot_items": loot_items,
	}
