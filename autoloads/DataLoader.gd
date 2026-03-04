extends Node

# Centralized JSON data loader — all game content comes from data/*.json
# Dashboard edits these files, game reads them at startup.

var weapons_data:        Dictionary = {}
var items_data:          Dictionary = {}
var classes_data:        Dictionary = {}
var characters_data:     Dictionary = {}
var enemies_data:        Dictionary = {}
var kips_data:           Dictionary = {}
var dialogue_data:       Dictionary = {}
var chapters_data:       Dictionary = {}
var kip_evolutions_data: Dictionary = {}
var terrain_objects_data: Dictionary = {}

func _ready():
	_load_all()

func _load_all():
	weapons_data        = _load_json("res://data/weapons.json")
	items_data          = _load_json("res://data/items.json")
	classes_data        = _load_json("res://data/classes.json")
	characters_data     = _load_json("res://data/characters.json")
	enemies_data        = _load_json("res://data/enemies.json")
	kips_data           = _load_json("res://data/kips.json")
	dialogue_data       = _load_json("res://data/dialogue.json")
	chapters_data       = _load_json("res://data/chapters.json")
	kip_evolutions_data = _load_json("res://data/kip_evolutions.json")
	terrain_objects_data = _load_json("res://data/terrain_objects.json")
	print("DataLoader: Loaded %d weapons, %d items, %d classes, %d chars, %d enemies, %d kips, %d evolutions" % [
		weapons_data.size(), items_data.size(), classes_data.size(),
		characters_data.size(), enemies_data.size(), kips_data.size(),
		kip_evolutions_data.size()
	])

func reload():
	_load_all()

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DataLoader: Missing %s" % path)
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: Can't open %s" % path)
		return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("DataLoader: Parse error in %s — %s" % [path, json.get_error_message()])
		return {}
	var data = json.data
	if data is Dictionary:
		# Strip schema entries
		data.erase("_schema")
		return data
	return {}

# ─── Convenience: get a dialogue conversation ────────────────────────────────

func get_dialogue(id: String) -> Array:
	return dialogue_data.get(id, [])

# ─── Convenience: get chapter data ───────────────────────────────────────────

func get_chapter(id: String) -> Dictionary:
	return chapters_data.get(id, {})

# ─── List helpers for dashboard ──────────────────────────────────────────────

func get_weapon_ids() -> Array:
	return weapons_data.keys()

func get_item_ids() -> Array:
	return items_data.keys()

func get_kip_ids() -> Array:
	return kips_data.keys()

func get_character_ids() -> Array:
	return characters_data.keys()

func get_enemy_ids() -> Array:
	return enemies_data.keys()
