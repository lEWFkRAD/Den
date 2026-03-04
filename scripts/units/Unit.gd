class_name Unit
extends RefCounted

var grid_position:  Vector2i
var is_player_unit: bool   = true
var unit_class:     String = "Soldier"
var unit_name:      String = "Unit"
var flavor_text:    String = ""
var element:        String = ""

var stats:      UnitStats
var bonded_kip          = null   # Kip or null
var weapon: Weapon      = null   # Active weapon
var weapons:    Array   = []     # Weapon[]
var items:      Array   = []     # Item[]

var has_acted:  bool = false
var has_moved:  bool = false

# Temporary stat boosts (key = stat name, value = {amount, turns_remaining})
var temp_boosts: Dictionary = {}

func _init():
	stats = UnitStats.new()

func setup(pos: Vector2i, player: bool, uclass: String, uname: String):
	grid_position  = pos
	is_player_unit = player
	unit_class     = uclass
	unit_name      = uname
	stats.load_class(uclass)

# ─── Combat ──────────────────────────────────────────────────────────────────

func take_damage(amount: int, source_element: String) -> int:
	var modified = ElementRegistry.calculate_damage(amount, source_element, element)
	modified = max(0, modified)
	stats.hp -= modified
	stats.hp  = max(0, stats.hp)
	if stats.hp == 0:
		BattleState.unit_died.emit(unit_name, is_player_unit)
	return modified

func is_alive() -> bool:
	return stats.hp > 0

# ─── Actions ─────────────────────────────────────────────────────────────────

func reset_turn():
	has_acted = false
	has_moved = false
	if bonded_kip:
		bonded_kip.has_acted = false
	# Tick temp boosts
	var expired: Array = []
	for stat in temp_boosts:
		temp_boosts[stat]["turns"] -= 1
		if temp_boosts[stat]["turns"] <= 0:
			expired.append(stat)
			_remove_temp_boost(stat)
	for s in expired:
		temp_boosts.erase(s)

func cycle_weapon():
	if weapons.size() <= 1: return
	var idx = weapons.find(weapon)
	idx = (idx + 1) % weapons.size()
	weapon = weapons[idx]

func on_kip_death():
	element = ""
	stats.magic     = max(1, stats.magic - 3)
	stats.resistance = max(0, stats.resistance - 2)
	bonded_kip = null

# ─── Attack Range ────────────────────────────────────────────────────────────

func get_attack_range() -> Array:
	if weapon == null: return []
	var result: Array = []
	var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	# BFS up to max_range
	if weapon.max_range == 1:
		for d in dirs:
			result.append(grid_position + d)
	else:
		# For ranged: Manhattan distance within min..max range
		for x in range(-weapon.max_range, weapon.max_range + 1):
			for y in range(-weapon.max_range, weapon.max_range + 1):
				var dist = abs(x) + abs(y)
				if dist >= weapon.min_range and dist <= weapon.max_range:
					result.append(grid_position + Vector2i(x, y))
	return result

# ─── Visuals ─────────────────────────────────────────────────────────────────

func get_display_color() -> Color:
	if not is_player_unit:
		return Color(0.82, 0.14, 0.14)
	if has_acted:
		return Color(0.18, 0.18, 0.32)
	return Color(0.18, 0.48, 0.92)

func get_kip_color() -> Color:
	if bonded_kip == null: return Color(0,0,0,0)
	match bonded_kip.element:
		"light":    return Color(1.0, 0.95, 0.5)
		"dark":     return Color(0.35, 0.1, 0.45)
		"void":     return Color(0.18, 0.02, 0.28)
		"god":      return Color(0.95, 0.95, 0.85)
		"blood":    return Color(0.75, 0.04, 0.04)
		"plant":    return Color(0.15, 0.62, 0.15)
		"ice":      return Color(0.60, 0.85, 1.0)
		"electric": return Color(0.95, 0.95, 0.08)
	return Color(0.5, 0.5, 0.5)

func get_class_shape() -> String:
	match unit_class:
		"Soldier", "Enemy":          return "square"
		"Archer", "Enemy_Archer":    return "diamond"
		"Mage", "Enemy_Mage":        return "circle"
		"Knight", "Enemy_Heavy", "Enemy_Knight": return "square_thick"
		"Rogue", "Enemy_Rogue":      return "triangle"
		"Healer":                    return "cross"
		"Warden", "Enemy_Commander", "Enemy_Warden": return "star"
	return "square"

func get_info_text() -> String:
	var weapon_str = weapon.weapon_name if weapon else "—"
	var kip_info   = ""
	if bonded_kip:
		var k = bonded_kip
		var phases = ["Companion", "Deployed", "Awakened"]
		kip_info = "\n\nKip: %s  [%s]\nKip HP: %d/%d  |  %s%s" % [
			k.kip_name, k.element.to_upper(),
			k.hp, k.max_hp, phases[k.current_phase],
			"  EXHAUSTED" if k.is_exhausted else ""
		]

	var items_str = ""
	for it in items:
		items_str += "\n  %s (%d)" % [it.item_name, it.uses]

	return "%s\n%s  |  %s\n\nHP %d/%d   MOV %d\nSTR %d  MAG %d  SKL %d\nSPD %d  DEF %d  RES %d\n\nWeapon: %s\nAtk: %d  Hit: %d%%  Crit: %d%%\nRange: %d-%d\n\nItems:%s%s" % [
		unit_name, unit_class,
		("Element: " + element.to_upper()) if element != "" else "No element",
		stats.hp, stats.max_hp,
		stats.movement,
		stats.strength, stats.magic, stats.skill,
		stats.speed, stats.defense, stats.resistance,
		weapon_str,
		(weapon.attack if weapon else 0),
		(weapon.hit if weapon else 0),
		(weapon.crit if weapon else 0),
		(weapon.min_range if weapon else 0),
		(weapon.max_range if weapon else 0),
		items_str if items_str != "" else "\n  (none)",
		kip_info
	]

func _remove_temp_boost(stat: String):
	match stat:
		"resistance": stats.resistance -= temp_boosts[stat]["amount"]
		"strength":   pass  # Permanent
