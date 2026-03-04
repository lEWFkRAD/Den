class_name Tile
extends RefCounted

enum TerrainType {
	OPEN, FOREST, WATER, RUINS, ELEVATION, WALL, FORT, BRIDGE, VILLAGE,
	THRONE, SAND, LAVA, RIVER, ROAD,
	# Phase 3 additions
	GRASS, DIRT, STONE, SNOW, ROCK, ICE
}

enum ElementalState { NEUTRAL, FROZEN, OVERGROWN, CHARGED, BLOODSOAKED, VOIDED, RADIANT, DARKENED }

enum TerrainObject {
	NONE, TREE_PINE, TREE_OAK, TREE_DEAD, BUSH, HOUSE, TOWER, CHURCH,
	WELL, FENCE_H, FENCE_V, SIGNPOST, BARREL, CRATE, BRIDGE_H, BRIDGE_V,
	RUINS_PILLAR, RUINS_ARCH, STATUE,
	# Phase 3 additions
	ROCK_SMALL, ROCK_LARGE, LOG, ROOT, RUINS_WALL,
	WOOD_WALL, WOOD_CORNER, ROOF_PIECE, DOOR_PIECE, WINDOW_PIECE
}

var grid_pos:              Vector2i
var terrain_type:          TerrainType   = TerrainType.OPEN
var elemental_state:       ElementalState = ElementalState.NEUTRAL
var terrain_object:        TerrainObject = TerrainObject.NONE
var elemental_turns_remaining: int = 0
var occupant = null
var is_passable: bool = true
var defense_bonus: int = 0
var avoid_bonus:   int = 0
var heal_bonus:    int = 0   # HP restored per turn when standing on this tile
var blocks_los:    bool = false    # Blocks line of sight for ranged attacks
var object_hp:     int = 0        # Destructible HP (0 = indestructible or no object)
var object_max_hp: int = 0
var terrain_variant: int = 0      # 0-4, seeded from grid position for visual variation
var height_level: float = 0.0     # Height for slope/cliff visualization

func set_terrain(type_str: String):
	# Seed variant from position for consistent visual variation
	terrain_variant = (grid_pos.x * 7919 + grid_pos.y * 4391) % 5
	match type_str:
		"plain":     terrain_type = TerrainType.OPEN
		"grass":     terrain_type = TerrainType.GRASS
		"dirt":      terrain_type = TerrainType.DIRT
		"stone":     terrain_type = TerrainType.STONE;     defense_bonus = 1
		"snow":      terrain_type = TerrainType.SNOW
		"rock":      terrain_type = TerrainType.ROCK;      defense_bonus = 1; avoid_bonus = 10
		"ice":       terrain_type = TerrainType.ICE
		"forest":    terrain_type = TerrainType.FOREST;    defense_bonus = 1; avoid_bonus = 20
		"mountain":  terrain_type = TerrainType.ELEVATION; defense_bonus = 2; avoid_bonus = 30; is_passable = true
		"water":     terrain_type = TerrainType.WATER;     is_passable = false
		"wall":      terrain_type = TerrainType.WALL;      is_passable = false; blocks_los = true
		"fort":      terrain_type = TerrainType.FORT;      defense_bonus = 2; avoid_bonus = 20; heal_bonus = 2
		"ruins":     terrain_type = TerrainType.RUINS;     defense_bonus = 1; avoid_bonus = 10
		"bridge":    terrain_type = TerrainType.BRIDGE
		"village":   terrain_type = TerrainType.VILLAGE;   defense_bonus = 1; avoid_bonus = 10; heal_bonus = 1
		"throne":    terrain_type = TerrainType.THRONE;    defense_bonus = 3; avoid_bonus = 30; heal_bonus = 3
		"sand":      terrain_type = TerrainType.SAND
		"lava":      terrain_type = TerrainType.LAVA;      is_passable = false
		"river":     terrain_type = TerrainType.RIVER
		"road":      terrain_type = TerrainType.ROAD

func set_object(obj_str: String):
	match obj_str:
		"tree_pine":     terrain_object = TerrainObject.TREE_PINE
		"tree_oak":      terrain_object = TerrainObject.TREE_OAK
		"tree_dead":     terrain_object = TerrainObject.TREE_DEAD
		"bush":          terrain_object = TerrainObject.BUSH;    defense_bonus += 1; avoid_bonus += 5
		"house":         terrain_object = TerrainObject.HOUSE;   defense_bonus += 1; avoid_bonus += 10; blocks_los = true
		"tower":         terrain_object = TerrainObject.TOWER;   defense_bonus += 2; avoid_bonus += 15; blocks_los = true
		"church":        terrain_object = TerrainObject.CHURCH;  defense_bonus += 1; heal_bonus += 2; blocks_los = true
		"well":          terrain_object = TerrainObject.WELL;    heal_bonus += 1
		"fence_h":       terrain_object = TerrainObject.FENCE_H; defense_bonus += 1
		"fence_v":       terrain_object = TerrainObject.FENCE_V; defense_bonus += 1
		"signpost":      terrain_object = TerrainObject.SIGNPOST
		"barrel":        terrain_object = TerrainObject.BARREL;  _set_destructible(1)
		"crate":         terrain_object = TerrainObject.CRATE;   _set_destructible(2)
		"bridge_h":      terrain_object = TerrainObject.BRIDGE_H; is_passable = true
		"bridge_v":      terrain_object = TerrainObject.BRIDGE_V; is_passable = true
		"ruins_pillar":  terrain_object = TerrainObject.RUINS_PILLAR; defense_bonus += 1; blocks_los = true
		"ruins_arch":    terrain_object = TerrainObject.RUINS_ARCH;   avoid_bonus += 5
		"statue":        terrain_object = TerrainObject.STATUE;  blocks_los = true
		# Phase 3 new objects
		"rock_small":    terrain_object = TerrainObject.ROCK_SMALL;  defense_bonus += 1; avoid_bonus += 5
		"rock_large":    terrain_object = TerrainObject.ROCK_LARGE;  defense_bonus += 2; blocks_los = true
		"log":           terrain_object = TerrainObject.LOG;         defense_bonus += 1
		"root":          terrain_object = TerrainObject.ROOT
		"ruins_wall":    terrain_object = TerrainObject.RUINS_WALL;  defense_bonus += 2; blocks_los = true; _set_destructible(3)
		"wood_wall":     terrain_object = TerrainObject.WOOD_WALL;   defense_bonus += 2; blocks_los = true; _set_destructible(2)
		"wood_corner":   terrain_object = TerrainObject.WOOD_CORNER; defense_bonus += 2; blocks_los = true; _set_destructible(2)
		"roof":          terrain_object = TerrainObject.ROOF_PIECE
		"door":          terrain_object = TerrainObject.DOOR_PIECE;  avoid_bonus += 5
		"window":        terrain_object = TerrainObject.WINDOW_PIECE

func _set_destructible(hp: int) -> void:
	object_hp = hp
	object_max_hp = hp
	defense_bonus += 1  # Destructible objects provide light cover

func is_destructible() -> bool:
	return object_max_hp > 0 and object_hp > 0

## Damage the object on this tile. Returns true if the object was destroyed.
func damage_object(amount: int = 1) -> bool:
	if not is_destructible():
		return false
	object_hp = max(0, object_hp - amount)
	if object_hp == 0:
		# Object destroyed — revert bonuses
		terrain_object = TerrainObject.NONE
		defense_bonus = max(0, defense_bonus - 1)
		blocks_los = false
		return true
	return false

func set_elemental_state(elem: String, duration: int = 3):
	match elem:
		"ice":      elemental_state = ElementalState.FROZEN
		"plant":    elemental_state = ElementalState.OVERGROWN
		"electric": elemental_state = ElementalState.CHARGED
		"blood":    elemental_state = ElementalState.BLOODSOAKED
		"void":     elemental_state = ElementalState.VOIDED
		"light":    elemental_state = ElementalState.RADIANT
		"dark":     elemental_state = ElementalState.DARKENED
		_: return
	elemental_turns_remaining = duration

func tick_turn():
	if elemental_turns_remaining > 0:
		elemental_turns_remaining -= 1
		if elemental_turns_remaining == 0:
			elemental_state = ElementalState.NEUTRAL

func get_movement_cost(unit_element: String = "") -> int:
	var cost: int = 1
	match terrain_type:
		TerrainType.FOREST:    cost = 2
		TerrainType.WATER:     cost = 4
		TerrainType.RUINS:     cost = 2
		TerrainType.ELEVATION: cost = 3
		TerrainType.SAND:      cost = 2
		TerrainType.RIVER:     cost = 3
		TerrainType.ROAD:      cost = 1
		TerrainType.BRIDGE:    cost = 1
		TerrainType.FORT:      cost = 1
		TerrainType.VILLAGE:   cost = 1
		TerrainType.THRONE:    cost = 1
		TerrainType.ROCK:      cost = 2
		TerrainType.ICE:       cost = 2
		TerrainType.SNOW:      cost = 1
		TerrainType.DIRT:      cost = 1
		TerrainType.STONE:     cost = 1
		TerrainType.GRASS:     cost = 1
	# Objects can slow movement
	match terrain_object:
		TerrainObject.BUSH:    cost += 1
		TerrainObject.FENCE_H, TerrainObject.FENCE_V: cost += 1
		TerrainObject.BARREL, TerrainObject.CRATE:     cost += 1
		TerrainObject.ROOT:    cost += 1
		TerrainObject.LOG:     cost += 1
	match elemental_state:
		ElementalState.FROZEN:
			cost = 1 if unit_element == "ice" else cost + 2
		ElementalState.OVERGROWN:
			cost = 1 if unit_element == "plant" else cost + 1
		ElementalState.CHARGED:
			cost = 1 if unit_element == "electric" else cost
		ElementalState.VOIDED:
			cost = 1 if unit_element == "void" else cost + 1
		ElementalState.DARKENED:
			cost = 1 if unit_element == "dark" else cost + 1
	return cost

## Get effective cover bonuses including elemental state bonuses.
## OVERGROWN tiles grant cover (avoid + defense).
func get_effective_avoid() -> int:
	var total: int = avoid_bonus
	if elemental_state == ElementalState.OVERGROWN:
		total += 15  # Overgrown provides cover
	return total

func get_effective_defense() -> int:
	var total: int = defense_bonus
	if elemental_state == ElementalState.OVERGROWN:
		total += 1   # Light defense from overgrowth
	return total

## Returns on-entry effects for a unit stepping onto this tile.
## Called by Battle3D when a unit moves.
func get_entry_effects(unit_element: String = "") -> Dictionary:
	var effects: Dictionary = {
		"purge": false,       # Remove all buffs/debuffs
		"damage": 0,          # Damage on entry
		"heal": heal_bonus,   # Heal on turn start
		"message": "",        # Log message
	}
	match elemental_state:
		ElementalState.VOIDED:
			if unit_element != "void":
				effects["purge"] = true
				effects["message"] = "VOID SCAR purges all effects!"
		ElementalState.CHARGED:
			if unit_element != "electric":
				effects["damage"] = 3
				effects["message"] = "Shocked by CHARGED ground!"
		ElementalState.BLOODSOAKED:
			if unit_element != "blood":
				effects["damage"] = 2
				effects["message"] = "Bloodsoaked ground burns!"
		ElementalState.FROZEN:
			pass  # Movement penalty only (already handled)
		ElementalState.OVERGROWN:
			pass  # Cover + slow (already handled)
	# Ice terrain causes slip damage
	if terrain_type == TerrainType.ICE and unit_element != "ice":
		effects["damage"] += 1
		if effects["message"] == "":
			effects["message"] = "Slippery ice!"
	return effects

func get_color() -> Color:
	match elemental_state:
		ElementalState.FROZEN:     return Color(0.62, 0.82, 1.0)
		ElementalState.OVERGROWN:  return Color(0.12, 0.42, 0.12)
		ElementalState.CHARGED:    return Color(0.75, 0.75, 0.10)
		ElementalState.BLOODSOAKED:return Color(0.38, 0.04, 0.04)
		ElementalState.VOIDED:     return Color(0.05, 0.02, 0.09)
		ElementalState.RADIANT:    return Color(0.95, 0.90, 0.55)
		ElementalState.DARKENED:   return Color(0.09, 0.05, 0.14)
	# Variant-aware base colors — subtle variation per tile
	var v = terrain_variant
	match terrain_type:
		TerrainType.GRASS:
			var g = [Color(0.16, 0.28, 0.10), Color(0.14, 0.26, 0.09), Color(0.18, 0.30, 0.11),
					 Color(0.15, 0.27, 0.08), Color(0.17, 0.29, 0.12)]
			return g[v]
		TerrainType.DIRT:
			var d = [Color(0.28, 0.22, 0.14), Color(0.26, 0.20, 0.12), Color(0.30, 0.24, 0.15),
					 Color(0.27, 0.21, 0.13), Color(0.29, 0.23, 0.16)]
			return d[v]
		TerrainType.STONE:
			var s = [Color(0.30, 0.28, 0.26), Color(0.28, 0.26, 0.24), Color(0.32, 0.30, 0.28),
					 Color(0.29, 0.27, 0.25), Color(0.31, 0.29, 0.27)]
			return s[v]
		TerrainType.SNOW:
			var sn = [Color(0.82, 0.84, 0.88), Color(0.80, 0.82, 0.86), Color(0.84, 0.86, 0.90),
					  Color(0.81, 0.83, 0.87), Color(0.83, 0.85, 0.89)]
			return sn[v]
		TerrainType.ROCK:
			var r = [Color(0.24, 0.22, 0.20), Color(0.22, 0.20, 0.18), Color(0.26, 0.24, 0.22),
					 Color(0.23, 0.21, 0.19), Color(0.25, 0.23, 0.20)]
			return r[v]
		TerrainType.ICE:
			var ic = [Color(0.55, 0.72, 0.85), Color(0.53, 0.70, 0.83), Color(0.57, 0.74, 0.87),
					  Color(0.54, 0.71, 0.84), Color(0.56, 0.73, 0.86)]
			return ic[v]
		TerrainType.OPEN:
			var o = [Color(0.14, 0.16, 0.12), Color(0.15, 0.17, 0.11), Color(0.13, 0.15, 0.12),
					 Color(0.16, 0.18, 0.13), Color(0.14, 0.16, 0.11)]
			return o[v]
		TerrainType.FOREST:    return Color(0.10, 0.28, 0.08)
		TerrainType.WATER:     return Color(0.08, 0.18, 0.42)
		TerrainType.RUINS:     return Color(0.26, 0.23, 0.18)
		TerrainType.ELEVATION: return Color(0.40, 0.36, 0.26)
		TerrainType.WALL:      return Color(0.18, 0.16, 0.14)
		TerrainType.FORT:      return Color(0.22, 0.20, 0.16)
		TerrainType.BRIDGE:    return Color(0.30, 0.22, 0.12)
		TerrainType.VILLAGE:   return Color(0.20, 0.22, 0.14)
		TerrainType.THRONE:    return Color(0.45, 0.35, 0.15)
		TerrainType.SAND:      return Color(0.52, 0.45, 0.28)
		TerrainType.LAVA:      return Color(0.55, 0.12, 0.02)
		TerrainType.RIVER:     return Color(0.12, 0.28, 0.52)
		TerrainType.ROAD:      return Color(0.22, 0.20, 0.16)
	return Color(0.14, 0.16, 0.12)

func get_terrain_name() -> String:
	match terrain_type:
		TerrainType.OPEN:      return "Plain"
		TerrainType.GRASS:     return "Grass"
		TerrainType.DIRT:      return "Dirt"
		TerrainType.STONE:     return "Stone"
		TerrainType.SNOW:      return "Snow"
		TerrainType.ROCK:      return "Rock"
		TerrainType.ICE:       return "Ice"
		TerrainType.FOREST:    return "Forest"
		TerrainType.WATER:     return "Water"
		TerrainType.RUINS:     return "Ruins"
		TerrainType.ELEVATION: return "Mountain"
		TerrainType.WALL:      return "Wall"
		TerrainType.FORT:      return "Fort"
		TerrainType.BRIDGE:    return "Bridge"
		TerrainType.VILLAGE:   return "Village"
		TerrainType.THRONE:    return "Throne"
		TerrainType.SAND:      return "Sand"
		TerrainType.LAVA:      return "Lava"
		TerrainType.RIVER:     return "River"
		TerrainType.ROAD:      return "Road"
	return "?"
