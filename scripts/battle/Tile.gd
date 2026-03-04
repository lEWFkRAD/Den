class_name Tile
extends RefCounted

enum TerrainType   { OPEN, FOREST, WATER, RUINS, ELEVATION }
enum ElementalState { NEUTRAL, FROZEN, OVERGROWN, CHARGED, BLOODSOAKED, VOIDED, RADIANT, DARKENED }

var grid_pos:              Vector2i
var terrain_type:          TerrainType   = TerrainType.OPEN
var elemental_state:       ElementalState = ElementalState.NEUTRAL
var elemental_turns_remaining: int = 0
var occupant = null
var is_passable: bool = true

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
		TerrainType.WATER:     cost = 3
		TerrainType.RUINS:     cost = 2
		TerrainType.ELEVATION: cost = 2
	match elemental_state:
		ElementalState.FROZEN:
			cost = 1 if unit_element == "ice" else cost + 2
		ElementalState.OVERGROWN:
			cost = 1 if unit_element == "plant" else cost + 1
		ElementalState.CHARGED:
			cost = 1 if unit_element == "electric" else cost
	return cost

func get_color() -> Color:
	match elemental_state:
		ElementalState.FROZEN:     return Color(0.62, 0.82, 1.0)
		ElementalState.OVERGROWN:  return Color(0.12, 0.42, 0.12)
		ElementalState.CHARGED:    return Color(0.75, 0.75, 0.10)
		ElementalState.BLOODSOAKED:return Color(0.38, 0.04, 0.04)
		ElementalState.VOIDED:     return Color(0.05, 0.02, 0.09)
		ElementalState.RADIANT:    return Color(0.95, 0.90, 0.55)
		ElementalState.DARKENED:   return Color(0.09, 0.05, 0.14)
	match terrain_type:
		TerrainType.FOREST:    return Color(0.10, 0.28, 0.08)
		TerrainType.WATER:     return Color(0.08, 0.18, 0.42)
		TerrainType.RUINS:     return Color(0.26, 0.23, 0.18)
		TerrainType.ELEVATION: return Color(0.40, 0.36, 0.26)
	return Color(0.14, 0.16, 0.12)
