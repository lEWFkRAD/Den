extends Node

var chapter: int = 1
var army: Array = []      # Array of unit save data
var gold: int = 0
var kips_encountered: Array = []

signal chapter_started(chapter_num: int)
signal unit_lost(unit_name: String)

const SAVE_PATH = "user://den_save.json"

func start_chapter(num: int):
	chapter = num
	chapter_started.emit(chapter)

func record_kip_encounter(kip_name: String):
	if not kip_name in kips_encountered:
		kips_encountered.append(kip_name)

# ─── Save ─────────────────────────────────────────────────────────────────────

func save_game(units: Array = []) -> bool:
	var data: Dictionary = {
		"version": 3,
		"chapter": chapter,
		"gold": gold,
		"kips_encountered": kips_encountered,
		"timestamp": Time.get_datetime_string_from_system(),
		"units": [],
	}

	# Serialize living units
	for u in units:
		if not u.is_alive():
			continue
		var ud: Dictionary = {
			"name": u.unit_name,
			"class": u.unit_class,
			"is_player": u.is_player_unit,
			"grid_pos": [u.grid_position.x, u.grid_position.y],
			"element": u.element,
			"hp": u.stats.hp,
			"max_hp": u.stats.max_hp,
			"strength": u.stats.strength,
			"magic": u.stats.magic,
			"skill": u.stats.skill,
			"speed": u.stats.speed,
			"defense": u.stats.defense,
			"resistance": u.stats.resistance,
			"movement": u.stats.movement,
			"luck": u.stats.luck,
			"weapons": [],
			"items": [],
		}
		# Weapons
		for w in u.weapons:
			ud["weapons"].append({
				"id": w.weapon_id,
				"uses": w.uses,
			})
		# Items
		for it in u.items:
			ud["items"].append({
				"id": it.item_id,
				"uses": it.uses,
			})
		# Kip
		if u.bonded_kip:
			var k = u.bonded_kip
			ud["kip"] = {
				"id": k.kip_id if "kip_id" in k else k.kip_name.to_lower().replace(" ", "_"),
				"hp": k.hp,
				"phase": k.current_phase,
				"is_exhausted": k.is_exhausted,
				"awakening_used": k.awakening_used,
			}
		data["units"].append(ud)

	# Also store army roster IDs for permadeath tracking
	data["army_roster"] = army

	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("GameState: Failed to save — %s" % FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

# ─── Load ─────────────────────────────────────────────────────────────────────

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text = file.get_as_text()
	file.close()

	var json = JSON.new()
	if json.parse(text) != OK:
		push_error("GameState: Failed to parse save file")
		return false

	var data = json.data
	chapter = data.get("chapter", 1)
	gold = data.get("gold", 0)
	kips_encountered = data.get("kips_encountered", [])
	army = data.get("army_roster", [])

	# Store unit data for Battle to restore
	_pending_load = data.get("units", [])
	return true

var _pending_load: Array = []

func has_pending_load() -> bool:
	return not _pending_load.is_empty()

func consume_pending_load() -> Array:
	var data = _pending_load.duplicate()
	_pending_load.clear()
	return data

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func get_save_info() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null: return {}
	var text = file.get_as_text()
	file.close()
	var json = JSON.new()
	if json.parse(text) != OK: return {}
	var data = json.data
	return {
		"chapter": data.get("chapter", 1),
		"timestamp": data.get("timestamp", ""),
		"unit_count": data.get("units", []).size(),
	}
