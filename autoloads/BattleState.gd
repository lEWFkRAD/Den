extends Node

var is_paused: bool = false
var is_player_phase: bool = true
var current_turn: int = 0
var grid = null   # Reference to Grid3D (set by Battle3D on startup)

## Get the Tile at a grid position, or null if invalid.
func get_tile_at(pos: Vector2i):
	if grid == null:
		return null
	if not grid.tiles.has(pos):
		return null
	return grid.tiles[pos]

signal battle_paused
signal battle_resumed
signal turn_changed(turn_num: int, player_phase: bool)
signal kip_speaks(kip_name: String, line: String)
signal unit_died(unit_name: String, was_player: bool)
signal kip_evolved(kip_name: String, evolution_name: String)
signal kip_memory_event(kip_id: String, event_key: String, amount: int)

func pause():
	is_paused = true
	battle_paused.emit()

func resume():
	is_paused = false
	battle_resumed.emit()
