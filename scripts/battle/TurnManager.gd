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
	if enemy.weapon == null: return

	var el        = enemy.element
	var reachable = grid.get_movement_range(enemy.grid_position, enemy.stats.movement, el)
	reachable.append(enemy.grid_position)  # Standing still is always an option

	# Score every (tile, target) combination to find the best action
	var best_score:  float    = -9999.0
	var best_tile:   Vector2i = enemy.grid_position
	var best_target            = null

	for tile_pos in reachable:
		var occ = grid.tiles[tile_pos].occupant
		if occ != null and occ != enemy: continue

		# Check which player units are attackable from this tile
		var can_attack_someone = false
		for player in units:
			if not player.is_player_unit or not player.is_alive(): continue
			var d = _dist(tile_pos, player.grid_position)
			if d < enemy.weapon.min_range - 0.1 or d > enemy.weapon.max_range + 0.1:
				continue

			var score = _score_attack(enemy, player, tile_pos)
			can_attack_someone = true
			if score > best_score:
				best_score  = score
				best_tile   = tile_pos
				best_target = player

		# If no one attackable from this tile, score it as an approach tile
		if not can_attack_someone:
			var approach_score = _score_approach(enemy, tile_pos)
			if approach_score > best_score:
				best_score  = approach_score
				best_tile   = tile_pos
				best_target = null

	# Move
	if best_tile != enemy.grid_position:
		grid.tiles[enemy.grid_position].occupant = null
		enemy.grid_position = best_tile
		grid.tiles[best_tile].occupant = enemy

	# Attack
	if best_target != null:
		grid.flash(enemy.grid_position,      Color(0.9, 0.1, 0.1, 0.7), 0.4)
		grid.flash(best_target.grid_position, Color(0.9, 0.1, 0.1, 0.8), 0.4)
		var h_diff: float = _get_height_diff(enemy, best_target)
		var log = CombatResolver.resolve_combat(enemy, best_target, h_diff)
		for entry in log: combat_log_entry.emit(entry)
		if not best_target.is_alive():
			grid.tiles[best_target.grid_position].occupant = null

func _get_height_diff(a, b) -> float:
	if grid and grid.has_method("get_tile_height"):
		return grid.get_tile_height(a.grid_position) - grid.get_tile_height(b.grid_position)
	return 0.0

# ─── AI Scoring ──────────────────────────────────────────────────────────────

func _score_attack(enemy: Unit, target: Unit, from_tile: Vector2i) -> float:
	var score: float = 0.0
	# Temporarily move enemy to candidate tile for accurate forecast
	var original_pos = enemy.grid_position
	enemy.grid_position = from_tile
	var h_diff: float = _get_height_diff(enemy, target)
	var fc = CombatResolver.get_forecast(enemy, target, h_diff)
	enemy.grid_position = original_pos

	# Can we kill? Highest priority
	var dmg = fc["atk_damage"]
	if fc["atk_double"]: dmg *= 2
	if dmg >= target.stats.hp:
		score += 200.0

	# Raw damage output (weighted by hit chance)
	score += dmg * (fc["atk_hit"] / 100.0) * 2.0

	# Prioritize soft targets (healers, mages, low DEF)
	match target.unit_class:
		"Healer": score += 40.0  # Kill the healer
		"Mage":   score += 20.0  # Fragile, dangerous
		"Archer": score += 15.0  # Fragile ranged
		"Rogue":  score += 10.0

	# Prioritize low-HP targets (finish them off)
	var hp_ratio = float(target.stats.hp) / float(target.stats.max_hp)
	score += (1.0 - hp_ratio) * 50.0

	# Weapon triangle advantage
	var tri = CombatResolver._get_triangle_bonus(enemy.weapon, target.weapon)
	score += tri * 10.0

	# Elemental advantage
	var atk_elem = enemy.weapon.element if enemy.weapon.element != "" else enemy.element
	if atk_elem != "" and target.element != "":
		var mult = ElementRegistry.get_multiplier(atk_elem, target.element)
		if mult > 1.0: score += 25.0
		elif mult < 1.0: score -= 15.0

	# Penalize if counter will hurt us badly
	if fc["def_can_counter"]:
		var counter_dmg = fc["def_damage"]
		if fc["def_double"]: counter_dmg *= 2
		var our_hp_after = enemy.stats.hp - int(counter_dmg * fc["def_hit"] / 100.0)
		if our_hp_after <= 0:
			score -= 80.0  # We'd likely die
		elif float(our_hp_after) / float(enemy.stats.max_hp) < 0.3:
			score -= 30.0  # We'd be very low

	# Ranged units prefer to stay at max range
	if enemy.weapon.min_range >= 2:
		var d = _dist(from_tile, target.grid_position)
		if d >= enemy.weapon.max_range - 0.1:
			score += 8.0  # Bonus for max range positioning

	return score

func _score_approach(enemy: Unit, tile_pos: Vector2i) -> float:
	# When we can't attack anyone, score approach tiles
	var best_player = _best_approach_target(enemy)
	if best_player == null: return -9999.0

	var d = _dist(tile_pos, best_player.grid_position)

	# Base: closer is better (negative distance)
	var score: float = -d * 10.0

	# Self-preservation: if low HP, slightly prefer staying back
	if float(enemy.stats.hp) / float(enemy.stats.max_hp) < 0.3:
		score += d * 3.0  # Partially counteract the approach urge

	return score

func _best_approach_target(enemy: Unit):
	# Pick the best unit to walk toward (not just nearest)
	var best = null
	var best_score: float = -9999.0
	for u in units:
		if not u.is_player_unit or not u.is_alive(): continue
		var score: float = 0.0
		# Prefer soft targets
		match u.unit_class:
			"Healer": score += 30.0
			"Mage":   score += 15.0
			"Archer": score += 10.0
		# Prefer wounded targets
		score += (1.0 - float(u.stats.hp) / float(u.stats.max_hp)) * 20.0
		# Closer is better
		score -= _dist(enemy.grid_position, u.grid_position) * 2.0
		if score > best_score:
			best_score = score
			best = u
	return best

func _dist(a: Vector2i, b: Vector2i) -> float:
	return float((a-b).length())
