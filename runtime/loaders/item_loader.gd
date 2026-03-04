class_name ItemLoader
extends RefCounted
## Converts generated ItemJSON dictionaries into the formats used by the
## existing Weapon and Item classes in the battle engine.


## Loads a loot JSON file (array of ItemJSON dicts) from disk.
## Returns an empty array on failure.
func load_items(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_error("ItemLoader: file not found at '%s'" % path)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ItemLoader: could not open '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return []

	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ItemLoader: JSON parse error in '%s': %s" % [path, json.get_error_message()])
		return []

	var data: Variant = json.data
	if data is Array:
		return data
	if data is Dictionary:
		# Some formats wrap items in a dict with an "items" key
		return data.get("items", [data])
	return []


## Converts an ItemJSON weapon dict to the format compatible with the existing
## Weapon class (Weapon.gd).
##
## Input ItemJSON stats: {mt, hit, crit, wt, rng:[min,max]}
## Output weapon dict:
##   {weapon_id, name, type, damage_type, attack, hit, crit,
##    min_range, max_range, weight, uses, element, affixes,
##    tier, rarity, faction, region, material, motif, imprint}
func to_weapon(item_json: Dictionary) -> Dictionary:
	var stats: Dictionary = item_json.get("stats", {})
	var weapon_type: String = item_json.get("weapon_type", "sword")

	# Determine range from stats.rng array
	var rng_arr: Array = stats.get("rng", [1])
	var min_range: int = int(rng_arr[0]) if rng_arr.size() > 0 else 1
	var max_range: int = int(rng_arr[rng_arr.size() - 1]) if rng_arr.size() > 0 else 1

	# Determine damage type based on weapon type
	var damage_type: String = "physical"
	if weapon_type in ["tome", "staff"]:
		damage_type = "magical"

	# Determine uses based on tier (higher tier = fewer uses)
	var tier: int = int(item_json.get("tier", 1))
	var uses: int = 40 - (tier * 5)
	if uses < 15:
		uses = 15

	return {
		"weapon_id": item_json.get("id", ""),
		"name": item_json.get("name", "Unknown Weapon"),
		"type": weapon_type,
		"damage_type": damage_type,
		"attack": int(stats.get("mt", 5)),
		"hit": int(stats.get("hit", 80)),
		"crit": int(stats.get("crit", 0)),
		"min_range": min_range,
		"max_range": max_range,
		"weight": int(stats.get("wt", 5)),
		"uses": uses,
		"element": item_json.get("element", ""),
		"affixes": item_json.get("affixes", []),
		"tier": tier,
		"rarity": item_json.get("rarity", "common"),
		"faction": item_json.get("faction", ""),
		"region": item_json.get("region", ""),
		"material": item_json.get("material", ""),
		"motif": item_json.get("motif", ""),
		"imprint": item_json.get("imprint", null),
	}


## Converts an ItemJSON armor dict to an armor-compatible format.
## Since the engine does not yet have a full Armor class, this passes
## through the data in a structured dict that can be consumed later.
##
## Input ItemJSON stats: {def, res, mov_mod}
## Output armor dict:
##   {armor_id, name, slot, defense, resistance, mov_mod,
##    tier, rarity, faction, region, material, motif, element, affixes, imprint}
func to_armor(item_json: Dictionary) -> Dictionary:
	var stats: Dictionary = item_json.get("stats", {})

	return {
		"armor_id": item_json.get("id", ""),
		"name": item_json.get("name", "Unknown Armor"),
		"slot": item_json.get("slot", "body"),
		"defense": int(stats.get("def", 0)),
		"resistance": int(stats.get("res", 0)),
		"mov_mod": int(stats.get("mov_mod", 0)),
		"tier": int(item_json.get("tier", 1)),
		"rarity": item_json.get("rarity", "common"),
		"faction": item_json.get("faction", ""),
		"region": item_json.get("region", ""),
		"material": item_json.get("material", ""),
		"motif": item_json.get("motif", ""),
		"element": item_json.get("element", ""),
		"affixes": item_json.get("affixes", []),
		"imprint": item_json.get("imprint", null),
	}


## Creates a Weapon object from an ItemJSON dict by feeding the converted
## data through the existing Weapon class pattern.
## Requires DataLoader to NOT have the weapon registered (procedural items).
func make_weapon(item_json: Dictionary) -> Weapon:
	var data: Dictionary = to_weapon(item_json)
	var w := Weapon.new()
	w.weapon_id = data.get("weapon_id", "")
	w.weapon_name = data.get("name", "Unknown Weapon")
	w.weapon_type = Weapon.TYPE_MAP.get(data.get("type", "sword"), Weapon.WeaponType.SWORD)
	w.damage_type = Weapon.DamageType.MAGICAL if data.get("damage_type", "physical") == "magical" else Weapon.DamageType.PHYSICAL
	w.attack = int(data.get("attack", 5))
	w.hit = int(data.get("hit", 80))
	w.crit = int(data.get("crit", 0))
	w.min_range = int(data.get("min_range", 1))
	w.max_range = int(data.get("max_range", 1))
	w.uses = int(data.get("uses", 30))
	w.max_uses = w.uses
	w.element = data.get("element", "")
	return w


## Convenience: categorizes loaded items by slot type.
## Returns: {weapons: [], armor: [], materials: [], scrolls: []}
func categorize(items: Array) -> Dictionary:
	var result: Dictionary = {
		"weapons": [],
		"armor": [],
		"materials": [],
		"scrolls": [],
	}
	for item in items:
		if not (item is Dictionary):
			continue
		var slot: String = item.get("slot", "")
		match slot:
			"weapon":
				result["weapons"].append(item)
			"body", "helm", "boots", "ring":
				result["armor"].append(item)
			"material":
				result["materials"].append(item)
			"scroll":
				result["scrolls"].append(item)
			_:
				# Unknown slot type, skip
				pass
	return result
