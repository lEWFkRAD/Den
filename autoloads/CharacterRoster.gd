extends Node

# Character and enemy data now loaded from data/*.json via DataLoader.
# This file just provides factory methods.

# ─── Factory: Build a Unit from roster data ───────────────────────────────────

func build_player_unit(char_id: String, grid_pos: Vector2i) -> Unit:
	var data: Dictionary = DataLoader.characters_data.get(char_id, {})
	if data.is_empty():
		push_error("CharacterRoster: unknown char_id " + char_id)
		return null

	var unit = Unit.new()
	unit.setup(grid_pos, true, data["class"], data["name"])
	unit.flavor_text = data.get("flavor", "")

	# Weapons
	for wid in data.get("weapons", []):
		var w = Weapon.make(wid)
		unit.weapons.append(w)
	if not unit.weapons.is_empty():
		unit.weapon = unit.weapons[0]

	# Items
	for iid in data.get("items", []):
		unit.items.append(Item.make(iid))

	# Kip
	var kip_id = data.get("kip", "")
	if kip_id != "":
		var kip = build_kip(kip_id)
		if kip:
			kip.bonded_unit = unit
			unit.bonded_kip  = kip
			unit.element     = kip.element

	return unit

func build_enemy_unit(enemy_type: String, grid_pos: Vector2i, suffix: String = "") -> Unit:
	var data: Dictionary = DataLoader.enemies_data.get(enemy_type, DataLoader.enemies_data.get("grunt", {}))
	var unit = Unit.new()
	var uname = data.get("name", "Enemy") + (" " + suffix if suffix != "" else "")
	unit.setup(grid_pos, false, data.get("class", "Enemy"), uname)
	unit.element = data.get("element", "")

	for wid in data.get("weapons", []):
		var w = Weapon.make(wid)
		unit.weapons.append(w)
	if not unit.weapons.is_empty():
		unit.weapon = unit.weapons[0]

	for iid in data.get("items", []):
		unit.items.append(Item.make(iid))

	return unit

func build_kip(kip_id: String) -> Kip:
	var kip = Kip.new()
	kip.load_kip(kip_id)
	return kip
