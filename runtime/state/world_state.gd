class_name WorldState
extends RefCounted
## Tracks world state across a campaign run, including faction control per region,
## mission progress, and arc-driven counters.


## Maps region_id -> { faction_id: int (control value) }
var faction_control: Dictionary = {}

## Array of completed mission id strings
var missions_completed: Array = []

## Current chapter number (1-indexed)
var current_chapter: int = 1

## Number of relics discovered during the run
var relics_found: int = 0

## Accumulated Kip faction activity level
var kip_activity: int = 0


## Loads initial faction pressure from doctrine for each region.
## regions: Array of region id strings.
## doctrine: The full doctrine dictionary (used via DoctrineLoader-style access).
func initialize(regions: Array, doctrine: Dictionary) -> void:
	faction_control.clear()
	missions_completed.clear()
	current_chapter = 1
	relics_found = 0
	kip_activity = 0

	for region_id: String in regions:
		var region_data: Dictionary = _get_region_from_doctrine(region_id, doctrine)
		var pressure: Dictionary = region_data.get("faction_pressure", {})
		var control_copy: Dictionary = {}
		for faction_id: String in pressure:
			control_copy[faction_id] = pressure[faction_id]
		faction_control[region_id] = control_copy


## Applies the result of a completed mission to the world state.
## mission_id: The id of the completed mission.
## won: Whether the player won.
## arc_effects: The world_state_effects dict from the active major arc.
func apply_mission_result(mission_id: String, won: bool, arc_effects: Dictionary) -> void:
	if mission_id not in missions_completed:
		missions_completed.append(mission_id)

	if won:
		var control_shift: int = arc_effects.get("control_shift_on_win", 0)
		var pressure_shift: int = arc_effects.get("pressure_shift", 0)

		# Apply control shift: boost defender faction control in all regions
		if control_shift > 0:
			for region_id: String in faction_control:
				var region_factions: Dictionary = faction_control[region_id]
				var dominant: String = get_dominant_faction(region_id)
				if dominant != "" and region_factions.has(dominant):
					region_factions[dominant] = region_factions[dominant] + pressure_shift

		# Apply relic and kip effects
		var relic_spawn: int = arc_effects.get("relic_sites_spawn", 0)
		if relic_spawn > 0:
			relics_found += relic_spawn

		var kip_increase: int = arc_effects.get("kip_activity_increase", 0)
		if kip_increase > 0:
			kip_activity += kip_increase

	current_chapter += 1


## Returns the faction id with the highest control value in the given region.
## Returns "" if the region has no faction data.
func get_dominant_faction(region_id: String) -> String:
	if not faction_control.has(region_id):
		return ""

	var factions: Dictionary = faction_control[region_id]
	var best_faction: String = ""
	var best_value: int = -1

	for faction_id: String in factions:
		var value: int = factions[faction_id]
		if value > best_value:
			best_value = value
			best_faction = faction_id

	return best_faction


## Serializes the full world state to a dictionary for JSON persistence.
func serialize() -> Dictionary:
	return {
		"faction_control": faction_control.duplicate(true),
		"missions_completed": missions_completed.duplicate(),
		"current_chapter": current_chapter,
		"relics_found": relics_found,
		"kip_activity": kip_activity,
	}


## Loads world state from a previously serialized dictionary.
func deserialize(data: Dictionary) -> void:
	faction_control = data.get("faction_control", {}).duplicate(true)
	missions_completed = data.get("missions_completed", []).duplicate()
	current_chapter = data.get("current_chapter", 1)
	relics_found = data.get("relics_found", 0)
	kip_activity = data.get("kip_activity", 0)


## Internal helper: extracts a region dict from raw doctrine data.
func _get_region_from_doctrine(region_id: String, doctrine: Dictionary) -> Dictionary:
	var regions: Dictionary = doctrine.get("regions", {})
	if regions.has(region_id):
		return regions[region_id]
	return {}
