class_name TurnManager
extends Node

var units: Array = []
var grid          = null
var turn_number:  int = 0

signal player_phase_started(turn: int)
signal kip_phase_started
signal kip_phase_ended
signal enemy_phase_started
signal enemy_phase_ended
signal combat_log_entry(text: String)

func start():
	_begin_player_phase()

func _begin_player_phase():
	BattleState.is_player_phase = true
	for u in units:
		if u.is_alive(): u.reset_turn()
	player_phase_started.emit(turn_number)

func end_player_phase():
	BattleState.is_player_phase = false
	grid.tick_all_tiles()
	_begin_kip_phase()

# ─── Kip Phase ────────────────────────────────────────────────────────────────

func _begin_kip_phase():
	kip_phase_started.emit()
	var had_kip_actions = false

	for unit in units:
		if not unit.is_player_unit or not unit.is_alive(): continue
		var kip = unit.bonded_kip
		if kip == null: continue
		if kip.current_phase != Kip.Phase.DEPLOYED: continue
		if kip.has_acted or kip.is_exhausted: continue

		var target = _find_kip_target(unit, kip)
		if target:
			await get_tree().create_timer(0.2).timeout
			var log = CombatResolver.resolve_kip_attack(kip, target)
			for entry in log:
				combat_log_entry.emit(entry)
			# Flash both tiles
			grid.flash(unit.grid_position, Color(1.0, 0.3, 0.1, 0.7), 0.5)
			grid.flash(target.grid_position, Color(0.9, 0.1, 0.1, 0.8), 0.4)
			grid.queue_redraw()
			had_kip_actions = true

			if not target.is_alive():
				grid.tiles[target.grid_position].occupant = null
				grid.queue_redraw()

	await get_tree().create_timer(0.15).timeout
	kip_phase_ended.emit()
	_begin_enemy_phase()

func _find_kip_target(unit, kip: Kip):
	var best = null
	var best_dist = 9999.0
	for other in units:
		if other.is_player_unit or not other.is_alive(): continue
		var dist = float((other.grid_position - unit.grid_position).length())
		if dist <= kip.attack_range + 0.1 and dist < best_dist:
			best_dist = dist
			best = other
	return best

# ─── Enemy Phase ──────────────────────────────────────────────────────────────

func _begin_enemy_phase():
	enemy_phase_started.emit()
	for unit in units:
		if not unit.is_player_unit and unit.is_alive():
			await get_tree().create_timer(0.18).timeout
			_run_enemy_ai(unit)
			grid.queue_redraw()
	await get_tree().create_timer(0.1).timeout
	enemy_phase_ended.emit()
	turn_number += 1
	_begin_player_phase()

func _run_enemy_ai(enemy: Unit):
	var target = _nearest_player(enemy)
	if not target: return

	var el       = enemy.element
	var reachable = grid.get_movement_range(enemy.grid_position, enemy.stats.movement, el)

	# Find best move tile
	var best_tile = enemy.grid_position
	var best_dist = _dist(enemy.grid_position, target.grid_position)
	for tp in reachable:
		var occ = grid.tiles[tp].occupant
		if occ != null and occ != enemy: continue
		var d = _dist(tp, target.grid_position)
		if d < best_dist:
			best_dist = d
			best_tile = tp

	# Move
	if best_tile != enemy.grid_position:
		grid.tiles[enemy.grid_position].occupant = null
		enemy.grid_position = best_tile
		grid.tiles[best_tile].occupant = enemy

	# Attack if in weapon range
	if enemy.weapon and best_dist <= enemy.weapon.max_range + 0.1 and best_dist >= enemy.weapon.min_range - 0.1:
		grid.flash(enemy.grid_position,   Color(0.9, 0.1, 0.1, 0.7), 0.4)
		grid.flash(target.grid_position,  Color(0.9, 0.1, 0.1, 0.8), 0.4)
		var log = CombatResolver.resolve_combat(enemy, target)
		for entry in log: combat_log_entry.emit(entry)
		if not target.is_alive():
			grid.tiles[target.grid_position].occupant = null

func _nearest_player(enemy: Unit):
	var nearest = null; var nd = 9999.0
	for u in units:
		if u.is_player_unit and u.is_alive():
			var d = _dist(u.grid_position, enemy.grid_position)
			if d < nd: nd = d; nearest = u
	return nearest

func _dist(a: Vector2i, b: Vector2i) -> float:
	return float((a-b).length())
