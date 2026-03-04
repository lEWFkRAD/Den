extends SceneTree
## Headless test: exercises DoctrineMapLoader + MissionLoader parsing.
## Note: MissionBattleLoader requires autoloads (CharacterRoster, DataLoader)
## and can only be tested in a full game scene, not --script mode.
##
## Usage: godot --headless -s test_mission_loader.gd

const _DoctrineMapLoader = preload("res://runtime/loaders/map_loader.gd")
const _MissionLoader     = preload("res://runtime/loaders/mission_loader.gd")

# Known enemy types from data/enemies.json
const KNOWN_ENEMIES: Array = [
	"grunt", "archer", "heavy", "mage", "rogue", "blood_knight",
	"void_warden", "commander", "priest", "paladin", "assassin",
	"golem", "siege_mage", "covenant_captain", "warden_corrupted", "varek_final"
]

# Keyword mapping duplicated from MissionBattleLoader for testing
const _ARCHETYPE_KEYWORDS: Array = [
	["commander", "commander"], ["captain", "commander"],
	["knight", "blood_knight"], ["paladin", "paladin"],
	["warden", "heavy"], ["bulwark", "heavy"], ["ironhelm", "heavy"],
	["heavy", "heavy"], ["templar", "heavy"], ["pikeman", "heavy"],
	["archer", "archer"], ["scout", "archer"], ["slingman", "archer"], ["bow", "archer"],
	["mage", "mage"], ["hexblade", "mage"], ["scholar", "mage"],
	["siege", "siege_mage"], ["priest", "priest"], ["acolyte", "priest"],
	["inquisitor", "mage"], ["rogue", "rogue"], ["cutthroat", "rogue"],
	["assassin", "assassin"], ["duelist", "rogue"], ["runner", "rogue"],
	["golem", "golem"], ["guard", "heavy"], ["spearman", "grunt"],
	["sword", "grunt"], ["levy", "grunt"], ["novice", "archer"],
]


func _resolve_type(unit_def: String) -> String:
	if KNOWN_ENEMIES.has(unit_def):
		return unit_def
	var lower: String = unit_def.to_lower()
	for pair in _ARCHETYPE_KEYWORDS:
		if lower.contains(pair[0]):
			return pair[1]
	return "grunt"


func _init() -> void:
	print("=== Mission Loader Test ===")
	var pass_count: int = 0
	var fail_count: int = 0

	var map_loader := _DoctrineMapLoader.new()
	var ml := _MissionLoader.new()

	# Test all 6 missions
	var mission_ids: Array = ["ch01_m01", "ch02_m02", "ch03_m03", "ch04_m04", "ch05_m05", "ch06_m06"]
	var valid_terrains: Array = ["plain", "forest", "mountain", "water", "wall", "fort", "ruins", "bridge", "village", "throne", "sand", "lava", "river", "road"]

	for mid in mission_ids:
		print("\n--- %s ---" % mid)
		var m: Dictionary = ml.load_mission("res://output/missions/%s.json" % mid)
		if m.is_empty():
			print("  FAIL: Mission load failed")
			fail_count += 1
			continue

		var map_file: String = ml.get_map_file(m)
		var md: Dictionary = map_loader.load_map("res://output/maps/%s" % map_file)
		if md.is_empty():
			print("  FAIL: Map load failed")
			fail_count += 1
			continue

		# Verify dimensions
		var w: int = md["width"]
		var h: int = md["height"]
		print("  map: %dx%d  template=%s  biome=%s" % [w, h, m.get("template", "?"), md.get("biome", "?")])

		# Verify terrain grid size matches
		if md["terrain_data"].size() != h:
			print("  FAIL: Terrain rows %d != height %d" % [md["terrain_data"].size(), h])
			fail_count += 1
			continue

		# Verify all terrain strings valid
		var bad: Dictionary = {}
		for row in md["terrain_data"]:
			for cell in row:
				if not valid_terrains.has(cell):
					bad[cell] = bad.get(cell, 0) + 1
		if not bad.is_empty():
			print("  FAIL: Unknown terrain: %s" % str(bad))
			fail_count += 1
			continue

		# Verify height map size
		if md["height_map"].size() != w * h:
			print("  FAIL: Height map size mismatch")
			fail_count += 1
			continue

		# Verify spawns
		var ps: int = md["player_spawns"].size()
		var es: int = md["enemy_spawns"].size()
		print("  spawns: %d player, %d enemy" % [ps, es])
		if ps == 0 or es == 0:
			print("  FAIL: Missing spawns")
			fail_count += 1
			continue

		# Verify objects (converted from props)
		print("  objects: %d (from %d props)" % [md["objects"].size(), md.get("props_raw", []).size()])

		# Verify enemy roster resolution
		var roster: Array = ml.get_enemy_roster(m)
		var all_resolved: bool = true
		for e in roster:
			var unit_def: String = e.get("unit_def", "")
			var resolved: String = _resolve_type(unit_def)
			if not KNOWN_ENEMIES.has(resolved):
				print("  WARN: %s -> %s (unknown)" % [unit_def, resolved])
				all_resolved = false
			else:
				print("  enemy: %s -> %s" % [unit_def, resolved])
		print("  roster: %d enemies, all_resolved=%s" % [roster.size(), str(all_resolved)])

		print("  PASS")
		pass_count += 1

	print("\n=== Results: %d/%d missions passed ===" % [pass_count, mission_ids.size()])
	quit(1 if fail_count > 0 else 0)
