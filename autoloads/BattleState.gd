extends Node

var is_paused: bool = false
var is_player_phase: bool = true
var current_turn: int = 0

signal battle_paused
signal battle_resumed
signal turn_changed(turn_num: int, player_phase: bool)
signal kip_speaks(kip_name: String, line: String)
signal unit_died(unit_name: String, was_player: bool)

func pause():
	is_paused = true
	battle_paused.emit()

func resume():
	is_paused = false
	battle_resumed.emit()
