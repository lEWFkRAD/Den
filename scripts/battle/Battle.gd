extends Node2D

# ─── State Machine ────────────────────────────────────────────────────────────
enum State {
	IDLE,
	UNIT_SELECTED,
	ACTION_MENU,
	SELECT_ATTACK,
	COMBAT_FORECAST,
	SELECT_ITEM,
	ANIMATING,
	BATTLE_OVER
}

var state: State = State.IDLE

# ─── Core ────────────────────────────────────────────────────────────────────
var grid:         Grid
var turn_manager: TurnManager
var units:        Array = []

# ─── Camera ──────────────────────────────────────────────────────────────────
var camera: Camera2D
var cam_zoom: float = 1.0
const CAM_ZOOM_MIN: float = 0.4
const CAM_ZOOM_MAX: float = 2.0
const CAM_ZOOM_STEP: float = 0.1
var cam_dragging: bool = false
var cam_drag_last: Vector2

# ─── Selection ───────────────────────────────────────────────────────────────
var selected_unit  = null
var pre_move_pos:  Vector2i
var movement_tiles: Array = []
var attack_targets: Array = []   # Enemy units in range
var forecast_attacker = null
var forecast_defender = null

# ─── UI Nodes ────────────────────────────────────────────────────────────────
var ui_panel:        Control
var phase_label:     Label
var turn_label:      Label
var info_label:      Label
var kip_label:       Label
var log_label:       Label
var action_box:      VBoxContainer
var forecast_box:    VBoxContainer
var items_box:       VBoxContainer
var forecast_label:  Label
var bottom_box:      VBoxContainer
var end_turn_btn:    Button

# Speech timer
var speech_timer:   float = 0.0
var log_timer:      float = 0.0
var log_queue:      Array = []

# ─── Ready ────────────────────────────────────────────────────────────────────

func _ready():
	_setup_camera()
	_build_ui()
	_start_battle()
	BattleState.kip_speaks.connect(_on_kip_speaks)
	BattleState.unit_died.connect(_on_unit_died)

func _setup_camera():
	camera = Camera2D.new()
	camera.enabled = true
	camera.zoom = Vector2(cam_zoom, cam_zoom)
	add_child(camera)

func _start_battle():
	var player_units = ["aldric","mira","voss","seren","bram","corvin","yael"]
	var unit_count   = player_units.size()

	grid = Grid.new()
	grid.initialize(unit_count)
	add_child(grid)

	# ── Player units ──────────────────────────────────────────────────────────
	var spawn_pos = [
		Vector2i(0,0), Vector2i(1,0), Vector2i(2,0),
		Vector2i(0,1), Vector2i(1,1), Vector2i(2,1), Vector2i(0,2)
	]
	for i in player_units.size():
		var u = CharacterRoster.build_player_unit(player_units[i], _open_tile(spawn_pos[i]))
		if u: _register_unit(u)

	# ── Enemies ───────────────────────────────────────────────────────────────
	var ew = grid.grid_width  - 1
	var eh = grid.grid_height - 1
	var enemy_spawns = [
		["heavy",        Vector2i(ew,   eh)],
		["grunt",        Vector2i(ew-1, eh)],
		["grunt",        Vector2i(ew,   eh-1)],
		["archer",       Vector2i(ew-2, eh)],
		["mage",         Vector2i(ew,   eh-2)],
		["rogue",        Vector2i(ew-1, eh-1)],
		["blood_knight", Vector2i(ew-3, eh-1)],
		["commander",    Vector2i(ew-2, eh-2)],
	]
	for i in enemy_spawns.size():
		var es  = enemy_spawns[i]
		var u   = CharacterRoster.build_enemy_unit(es[0], _open_tile(es[1]), str(i+1) if i < 3 else "")
		if u: _register_unit(u)

	grid.units_ref = units

	# Center camera on the grid
	_center_camera()

	# ── Turn Manager ──────────────────────────────────────────────────────────
	turn_manager = TurnManager.new()
	turn_manager.units = units
	turn_manager.grid  = grid
	turn_manager.player_phase_started.connect(_on_player_phase)
	turn_manager.kip_phase_started.connect(_on_kip_phase_start)
	turn_manager.kip_phase_ended.connect(_on_kip_phase_end)
	turn_manager.enemy_phase_started.connect(_on_enemy_phase_start)
	turn_manager.enemy_phase_ended.connect(_on_enemy_phase_end)
	turn_manager.combat_log_entry.connect(_push_log)
	add_child(turn_manager)
	turn_manager.start()

func _register_unit(u: Unit):
	if grid.tiles.has(u.grid_position):
		grid.tiles[u.grid_position].occupant = u
	units.append(u)

func _open_tile(prefer: Vector2i) -> Vector2i:
	if grid.tiles.has(prefer) and grid.tiles[prefer].is_passable and grid.tiles[prefer].occupant == null:
		return prefer
	var dirs = [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,0),Vector2i(0,-1),
				Vector2i(1,1),Vector2i(-1,1),Vector2i(1,-1),Vector2i(-1,-1)]
	for d in dirs:
		var a = prefer+d
		if grid.tiles.has(a) and grid.tiles[a].is_passable and grid.tiles[a].occupant == null:
			return a
	return prefer

# ─── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent):
	# Camera controls always active
	_handle_camera_input(event)

	if BattleState.is_paused: return
	if not BattleState.is_player_phase: return
	if state == State.BATTLE_OVER: return
	if state == State.ANIMATING: return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not cam_dragging:
			var tp = grid.world_to_tile(get_global_mouse_position())
			if grid.is_valid_tile(tp):
				_handle_tile_click(tp)

	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_action()

func _handle_camera_input(event: InputEvent):
	# Scroll wheel zoom
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom = clampf(cam_zoom + CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			camera.zoom = Vector2(cam_zoom, cam_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom = clampf(cam_zoom - CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			camera.zoom = Vector2(cam_zoom, cam_zoom)
		# Middle-click or right-click drag to pan
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				cam_dragging = true
				cam_drag_last = event.position
			else:
				cam_dragging = false

	if event is InputEventMouseMotion and cam_dragging:
		var delta = cam_drag_last - event.position
		camera.position += delta / cam_zoom
		cam_drag_last = event.position

func _handle_tile_click(tp: Vector2i):
	match state:
		State.IDLE:
			_try_select(tp)

		State.UNIT_SELECTED:
			if tp in movement_tiles:
				_move_unit(selected_unit, tp)
				_enter_action_menu()
			elif tp == selected_unit.grid_position:
				_enter_action_menu()  # Don't move, open menu in place
			else:
				_try_select(tp)  # Click another unit

		State.SELECT_ATTACK:
			var target = _unit_at(tp)
			if target != null and not target.is_player_unit and target.is_alive():
				forecast_attacker = selected_unit
				forecast_defender = target
				_show_forecast()
			else:
				_enter_action_menu()  # Click elsewhere = back to menu

		State.COMBAT_FORECAST:
			pass  # Handled by buttons

		State.SELECT_ITEM:
			pass  # Handled by buttons

		State.ACTION_MENU:
			pass  # Handled by buttons

# ─── Selection ────────────────────────────────────────────────────────────────

func _try_select(tp: Vector2i):
	var occ = _unit_at(tp)
	if occ != null and occ.is_player_unit and occ.is_alive() and not occ.has_acted:
		_select(occ)

func _select(unit):
	selected_unit  = unit
	pre_move_pos   = unit.grid_position
	var el         = unit.element
	movement_tiles = grid.get_movement_range(unit.grid_position, unit.stats.movement, el)
	grid.clear_highlights()
	grid.highlight_selected(unit.grid_position)
	grid.highlight_move(movement_tiles)
	_refresh_info(unit)
	_hide_all_panels()
	if unit.bonded_kip:
		unit.bonded_kip.speak("idle")
	state = State.UNIT_SELECTED

func _deselect():
	selected_unit  = null
	movement_tiles = []
	attack_targets = []
	grid.clear_highlights()
	info_label.text = "Select a unit."
	_hide_all_panels()
	_set_end_turn_visible(true)
	state = State.IDLE

# ─── Movement ────────────────────────────────────────────────────────────────

func _move_unit(unit, target: Vector2i):
	if target == unit.grid_position: return
	grid.tiles[unit.grid_position].occupant = null
	unit.grid_position = target
	unit.has_moved     = true
	grid.tiles[target].occupant = unit
	grid.clear_highlights()
	grid.highlight_selected(target)
	grid.queue_redraw()

# ─── Action Menu ─────────────────────────────────────────────────────────────

func _enter_action_menu():
	if selected_unit == null: return
	grid.clear_highlights()
	grid.highlight_selected(selected_unit.grid_position)
	_refresh_info(selected_unit)
	_show_action_menu()
	state = State.ACTION_MENU

func _show_action_menu():
	_hide_all_panels()
	_set_end_turn_visible(false)
	action_box.visible = true

	# Clear old buttons
	for child in action_box.get_children():
		child.queue_free()
	await get_tree().process_frame

	var u   = selected_unit
	var kip = u.bonded_kip if u else null

	_add_action_btn("⚔  ATTACK",  Color(0.8, 0.1, 0.1), _on_action_attack,
		u.weapon != null)

	if kip:
		if kip.current_phase == Kip.Phase.COMPANION and not kip.is_exhausted:
			_add_action_btn("◆  Deploy %s" % kip.kip_name, Color(0.1, 0.5, 0.9), _on_action_deploy, true)
		elif kip.current_phase == Kip.Phase.DEPLOYED:
			_add_action_btn("◆  Recall %s" % kip.kip_name,  Color(0.3, 0.3, 0.7), _on_action_recall, true)
			if not kip.awakening_used:
				_add_action_btn("✦  AWAKEN %s" % kip.kip_name, Color(0.7, 0.5, 0.0), _on_action_awaken, true)

	var has_items = not u.items.is_empty()
	_add_action_btn("⊕  Items",     Color(0.2, 0.6, 0.3), _on_action_items, has_items)

	if u.weapons.size() > 1:
		_add_action_btn("↻  Swap Weapon", Color(0.4, 0.4, 0.4), _on_action_swap_weapon, true)

	_add_action_btn("·  Wait",      Color(0.35, 0.35, 0.35), _on_action_wait, true)
	_add_action_btn("←  Back",      Color(0.25, 0.25, 0.45), _on_action_back, u.has_moved == false)

func _add_action_btn(label: String, col: Color, callback: Callable, enabled: bool):
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(440, 38)
	btn.disabled = not enabled
	btn.pressed.connect(callback)
	# Style tint
	var style = StyleBoxFlat.new()
	style.bg_color    = col.darkened(0.5)
	style.border_color = col
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", style)
	action_box.add_child(btn)

# ─── Action Handlers ─────────────────────────────────────────────────────────

func _on_action_attack():
	if selected_unit == null or selected_unit.weapon == null: return
	_hide_all_panels()

	# Is this a healing staff?
	if selected_unit.weapon.is_healing:
		_show_heal_targets()
		return

	attack_targets = []
	var atk_range  = selected_unit.get_attack_range()
	var valid_tiles: Array = []

	for tp in atk_range:
		if not grid.is_valid_tile(tp): continue
		var occ = _unit_at(tp)
		if occ != null and not occ.is_player_unit and occ.is_alive():
			attack_targets.append(occ)
			valid_tiles.append(tp)

	if attack_targets.is_empty():
		_push_log("No enemies in range.")
		_enter_action_menu()
		return

	grid.clear_highlights()
	grid.highlight_selected(selected_unit.grid_position)
	grid.highlight_attack(valid_tiles)
	state = State.SELECT_ATTACK

func _show_heal_targets():
	var heal_tiles: Array = []
	for u in units:
		if u.is_player_unit and u.is_alive() and u != selected_unit:
			if CombatResolver.can_heal_target(selected_unit, u):
				heal_tiles.append(u.grid_position)

	if heal_tiles.is_empty():
		_push_log("No allies in staff range.")
		_enter_action_menu()
		return

	_hide_all_panels()
	# Build heal target buttons
	items_box.visible = true
	for c in items_box.get_children(): c.queue_free()
	await get_tree().process_frame
	var lbl = Label.new()
	lbl.text = "Choose target to heal:"
	lbl.add_theme_font_size_override("font_size", 13)
	items_box.add_child(lbl)
	for u in units:
		if u.is_player_unit and u.is_alive() and u != selected_unit:
			if CombatResolver.can_heal_target(selected_unit, u):
				var tgt = u
				var b = Button.new()
				b.text = "%s  HP: %d/%d" % [tgt.unit_name, tgt.stats.hp, tgt.stats.max_hp]
				b.custom_minimum_size = Vector2(440, 36)
				b.pressed.connect(func(): _heal_target(tgt))
				items_box.add_child(b)
	var back_b = Button.new()
	back_b.text = "← Back"; back_b.custom_minimum_size = Vector2(440, 36)
	back_b.pressed.connect(_enter_action_menu)
	items_box.add_child(back_b)
	grid.clear_highlights()
	grid.highlight_selected(selected_unit.grid_position)
	grid.highlight_heal(heal_tiles)
	state = State.SELECT_ITEM

func _heal_target(target):
	var msg = CombatResolver.resolve_heal(selected_unit, target)
	_push_log(msg)
	grid.flash(target.grid_position, Color(0.3, 1.0, 0.5, 0.7), 0.6)
	selected_unit.has_acted = true
	_deselect()
	grid.queue_redraw()
	_check_all_acted()

func _on_action_deploy():
	if selected_unit == null or selected_unit.bonded_kip == null: return
	selected_unit.bonded_kip.deploy()
	_push_log("%s deployed." % selected_unit.bonded_kip.kip_name)
	_enter_action_menu()
	grid.queue_redraw()

func _on_action_recall():
	if selected_unit == null or selected_unit.bonded_kip == null: return
	selected_unit.bonded_kip.recall()
	_push_log("%s recalled." % selected_unit.bonded_kip.kip_name)
	_enter_action_menu()
	grid.queue_redraw()

func _on_action_awaken():
	if selected_unit == null or selected_unit.bonded_kip == null: return
	var kip = selected_unit.bonded_kip
	if kip.awaken():
		var r = kip.get_awakening_radius()
		grid.apply_elemental_effect(selected_unit.grid_position, r, kip.element, 4)
		# Awakening deals damage to all enemies in radius
		var hit = 0
		for u in units:
			if not u.is_player_unit and u.is_alive():
				var dist = (u.grid_position - selected_unit.grid_position).length()
				if dist <= r + 0.5:
					var dmg = kip.get_awakening_damage()
					u.take_damage(dmg, kip.element)
					grid.flash(u.grid_position, Color(1.0, 0.5, 0.0, 0.9), 0.8)
					hit += 1
					if not u.is_alive():
						grid.tiles[u.grid_position].occupant = null
		_push_log("%s AWAKENED! %s hit %d enemies." % [kip.kip_name, kip.get_phase_label(), hit])
		kip.is_exhausted = true
		selected_unit.has_acted = true
		grid.queue_redraw()
		_deselect()
		_check_all_acted()

func _on_action_items():
	if selected_unit == null: return
	_hide_all_panels()
	items_box.visible = true
	for c in items_box.get_children(): c.queue_free()
	await get_tree().process_frame

	var lbl = Label.new()
	lbl.text = "Use an item:"
	lbl.add_theme_font_size_override("font_size", 13)
	items_box.add_child(lbl)

	if selected_unit.items.is_empty():
		var lbl2 = Label.new(); lbl2.text = "(No items)"
		items_box.add_child(lbl2)
	else:
		for it in selected_unit.items:
			var item = it
			var b = Button.new()
			b.text = "%s  (%d/%d)  — %s" % [item.item_name, item.uses, item.max_uses, item.description]
			b.custom_minimum_size = Vector2(440, 38)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.disabled = item.uses <= 0
			b.pressed.connect(func(): _use_item(item))
			items_box.add_child(b)

	var back_b = Button.new()
	back_b.text = "← Back"; back_b.custom_minimum_size = Vector2(440, 36)
	back_b.pressed.connect(_enter_action_menu)
	items_box.add_child(back_b)
	state = State.SELECT_ITEM

func _use_item(item: Item):
	var msg = item.use_on(selected_unit)
	_push_log(msg)
	grid.flash(selected_unit.grid_position, Color(0.3, 1.0, 0.5, 0.7), 0.5)
	selected_unit.has_acted = true
	grid.queue_redraw()
	_deselect()
	_check_all_acted()

func _on_action_swap_weapon():
	if selected_unit == null: return
	selected_unit.cycle_weapon()
	_push_log("Swapped to %s." % selected_unit.weapon.weapon_name)
	_enter_action_menu()

func _on_action_wait():
	if selected_unit == null: return
	selected_unit.has_acted = true
	_deselect()
	_check_all_acted()

func _on_action_back():
	if selected_unit == null: return
	# Return unit to pre-move position
	if selected_unit.has_moved:
		grid.tiles[selected_unit.grid_position].occupant = null
		selected_unit.grid_position = pre_move_pos
		selected_unit.has_moved = false
		grid.tiles[pre_move_pos].occupant = selected_unit
		grid.queue_redraw()
	_select(selected_unit)

# ─── Combat Forecast ─────────────────────────────────────────────────────────

func _show_forecast():
	if forecast_attacker == null or forecast_defender == null: return
	_hide_all_panels()
	forecast_box.visible = true

	var fc  = CombatResolver.get_forecast(forecast_attacker, forecast_defender)
	var txt = "══ COMBAT FORECAST ══\n\n"
	txt += "%s  →  %s\n" % [fc["atk_name"], fc["def_name"]]
	txt += "%s  vs  %s\n\n" % [fc["atk_weapon"], fc["def_weapon"]]
	txt += "ATK  DMG: %d   HIT: %d%%   CRIT: %d%%\n" % [fc["atk_damage"], fc["atk_hit"], fc["atk_crit"]]
	if fc["atk_double"]: txt += "  (DOUBLES)\n"

	if fc["def_can_counter"]:
		txt += "\nDEF  DMG: %d   HIT: %d%%   CRIT: %d%%\n" % [fc["def_damage"], fc["def_hit"], fc["def_crit"]]
		if fc["def_double"]: txt += "  (DOUBLES)\n"
	else:
		txt += "\nDEF  Cannot counter.\n"

	# Element interaction
	var atk_elem = forecast_attacker.weapon.element if forecast_attacker.weapon and forecast_attacker.weapon.element != "" else forecast_attacker.element
	var wt = ElementRegistry.get_weakness_text(atk_elem, forecast_defender.element)
	if wt != "":
		txt += "\n[%s]" % wt

	forecast_label.text = txt

	for c in forecast_box.get_children():
		if c is Button: c.queue_free()
	await get_tree().process_frame

	var confirm = Button.new()
	confirm.text = "CONFIRM ATTACK"
	confirm.custom_minimum_size = Vector2(440, 42)
	confirm.pressed.connect(_on_confirm_attack)
	forecast_box.add_child(confirm)

	var back = Button.new()
	back.text = "← Back"
	back.custom_minimum_size = Vector2(440, 36)
	back.pressed.connect(func(): _enter_action_menu())
	forecast_box.add_child(back)

	state = State.COMBAT_FORECAST

func _on_confirm_attack():
	if forecast_attacker == null or forecast_defender == null: return
	state = State.ANIMATING
	_hide_all_panels()

	var atk = forecast_attacker
	var def = forecast_defender
	var fc  = CombatResolver.get_forecast(atk, def)

	# Animate and resolve each strike individually
	# Strike 1: Attacker hits
	await _animate_strike(atk, def, atk.weapon)
	if not def.is_alive():
		grid.tiles[def.grid_position].occupant = null
		grid.queue_redraw()
		_finish_combat(atk); return

	# Counter: Defender strikes back
	if fc["def_can_counter"]:
		await get_tree().create_timer(0.15).timeout
		await _animate_strike(def, atk, def.weapon)
		if not atk.is_alive():
			grid.tiles[atk.grid_position].occupant = null
			grid.queue_redraw()
			_finish_combat(atk); return

	# Follow-up: Attacker doubles
	if fc["atk_double"] and def.is_alive():
		await get_tree().create_timer(0.15).timeout
		await _animate_strike(atk, def, atk.weapon)
		if not def.is_alive():
			grid.tiles[def.grid_position].occupant = null
			grid.queue_redraw()
			_finish_combat(atk); return

	# Follow-up: Defender doubles
	if fc["def_double"] and fc["def_can_counter"] and atk.is_alive():
		await get_tree().create_timer(0.15).timeout
		await _animate_strike(def, atk, def.weapon)
		if not atk.is_alive():
			grid.tiles[atk.grid_position].occupant = null
			grid.queue_redraw()

	_finish_combat(atk)

func _animate_strike(attacker, defender, weapon: Weapon):
	# Slide toward target
	await grid.animate_attack(attacker, defender)

	# Resolve this single strike
	var hit_roll    = randi() % 100
	var hit_chance  = CombatResolver.get_hit(attacker, weapon, defender)

	if hit_roll >= hit_chance:
		_push_log("%s missed %s." % [attacker.unit_name, defender.unit_name])
		return

	var damage    = CombatResolver.get_damage(attacker, weapon, defender)
	var crit_roll = randi() % 100
	var is_crit   = crit_roll < CombatResolver.get_crit(attacker, weapon, defender)

	if is_crit:
		damage = int(damage * 3)
		_push_log("CRITICAL! %s → %s: %d damage" % [attacker.unit_name, defender.unit_name, damage])
		grid.flash(defender.grid_position, Color(1.0, 0.2, 0.0, 0.9), 0.5)
	else:
		_push_log("%s → %s: %d damage" % [attacker.unit_name, defender.unit_name, damage])
		grid.flash(defender.grid_position, Color(0.9, 0.1, 0.1, 0.8), 0.4)

	var elem = weapon.element if weapon.element != "" else attacker.element
	defender.take_damage(damage, elem)
	weapon.use_one()

	# Hit recoil on defender
	if defender.is_alive():
		await grid.animate_hit_recoil(defender)
	else:
		_push_log("%s fell." % defender.unit_name)

	grid.queue_redraw()

func _finish_combat(attacker):
	attacker.has_acted = true
	_deselect()
	_check_all_acted()
	_check_battle_outcome()

# ─── Turn / Phase Signals ────────────────────────────────────────────────────

func _on_player_phase(turn: int):
	phase_label.text = "Player Phase  —  Turn %d" % (turn + 1)
	turn_label.text  = "Turn %d" % (turn + 1)
	end_turn_btn.disabled = false
	grid.queue_redraw()
	_check_battle_outcome()

func _on_kip_phase_start():
	phase_label.text = "— Kip Phase —"
	_deselect()
	end_turn_btn.disabled = true

func _on_kip_phase_end():
	grid.queue_redraw()

func _on_enemy_phase_start():
	phase_label.text = "— Enemy Phase —"
	end_turn_btn.disabled = true

func _on_enemy_phase_end():
	grid.queue_redraw()

func _on_end_turn_pressed():
	if not BattleState.is_player_phase: return
	_deselect()
	end_turn_btn.disabled = true
	turn_manager.end_player_phase()

func _on_unit_died(uname: String, _was_player: bool):
	for u in units:
		if u.unit_name == uname and not u.is_alive():
			if grid.tiles.has(u.grid_position):
				grid.tiles[u.grid_position].occupant = null
	grid.queue_redraw()

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _unit_at(tp: Vector2i):
	if not grid.tiles.has(tp): return null
	return grid.tiles[tp].occupant

func _center_camera():
	var grid_pixel_w = grid.grid_width  * Grid.TILE_SIZE
	var grid_pixel_h = grid.grid_height * Grid.TILE_SIZE
	var grid_cx = grid_pixel_w / 2.0
	var grid_cy = grid_pixel_h / 2.0
	# Fit the grid into the left panel area (PANEL_X wide, 720 tall)
	var fit_zoom = minf(float(PANEL_X) / float(grid_pixel_w), 720.0 / float(grid_pixel_h))
	cam_zoom = clampf(fit_zoom * 0.92, CAM_ZOOM_MIN, CAM_ZOOM_MAX)  # Slight margin
	camera.zoom = Vector2(cam_zoom, cam_zoom)
	# Camera position = world point that appears at screen center (640, 360)
	# We want grid center to appear at screen x = PANEL_X/2 = 398
	# Offset from screen center: 640 - 398 = 242 pixels right
	# In world space: 242 / zoom
	camera.position = Vector2(grid_cx + 242.0 / cam_zoom, grid_cy)

func _pan_to_tile(tp: Vector2i):
	camera.position = Vector2(tp.x * Grid.TILE_SIZE + Grid.TILE_SIZE / 2.0,
							  tp.y * Grid.TILE_SIZE + Grid.TILE_SIZE / 2.0)

func _check_all_acted():
	var any_left = false
	for u in units:
		if u.is_player_unit and u.is_alive() and not u.has_acted:
			any_left = true; break
	if not any_left:
		end_turn_btn.disabled = true
		turn_manager.end_player_phase()

func _check_battle_outcome():
	var p = false; var e = false
	for u in units:
		if u.is_alive():
			if u.is_player_unit: p = true
			else: e = true
	if not p:
		phase_label.text = "— DEFEAT —"
		info_label.text  = "All units lost.\nPress ESC."
		state = State.BATTLE_OVER
	elif not e:
		phase_label.text = "— VICTORY —"
		info_label.text  = "All enemies defeated."
		state = State.BATTLE_OVER

func _cancel_action():
	match state:
		State.SELECT_ATTACK:   _enter_action_menu()
		State.ACTION_MENU:     _on_action_back()
		State.COMBAT_FORECAST: _enter_action_menu()
		State.SELECT_ITEM:     _enter_action_menu()
		State.UNIT_SELECTED:   _deselect()

func _refresh_info(unit):
	info_label.text = unit.get_info_text()

func _push_log(text: String):
	log_queue.append(text)

func _process(delta: float):
	# Speech fade
	if speech_timer > 0.0:
		speech_timer -= delta
		kip_label.modulate.a = minf(1.0, speech_timer)
		if speech_timer <= 0.0:
			kip_label.text = ""
			kip_label.modulate.a = 1.0

	# Log queue
	if log_timer > 0.0:
		log_timer -= delta
	elif not log_queue.is_empty():
		log_label.text  = log_queue.pop_front()
		log_timer       = 1.8

func _on_kip_speaks(kname: String, line: String):
	kip_label.text    = "%s:  \"%s\"" % [kname, line]
	speech_timer      = 4.5

# ─── UI Builder ───────────────────────────────────────────────────────────────

const PANEL_X = 796

func _build_ui():
	# Put UI on a CanvasLayer so it stays fixed when camera pans/zooms
	var ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.09, 0.97)
	bg.position = Vector2(PANEL_X, 0); bg.size = Vector2(484, 720)
	ui_layer.add_child(bg)

	var root = VBoxContainer.new()
	root.position = Vector2(PANEL_X + 16, 10)
	root.custom_minimum_size = Vector2(452, 700)
	ui_layer.add_child(root)
	ui_panel = root

	# Title row
	var row = HBoxContainer.new(); row.custom_minimum_size = Vector2(452, 44)
	var title = Label.new(); title.text = "D E N"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	row.add_child(title)
	var spacer = Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	turn_label = Label.new(); turn_label.text = "Turn 1"
	turn_label.add_theme_font_size_override("font_size", 14)
	turn_label.add_theme_color_override("font_color", Color(0.45,0.45,0.45))
	row.add_child(turn_label)
	root.add_child(row)

	# Divider
	root.add_child(_divider())

	# Phase
	phase_label = Label.new(); phase_label.text = "Player Phase — Turn 1"
	phase_label.add_theme_font_size_override("font_size", 15)
	phase_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.28))
	root.add_child(phase_label)

	root.add_child(_spacer(4))

	# Info
	info_label = Label.new(); info_label.text = "Select a unit."
	info_label.custom_minimum_size = Vector2(452, 180)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_color", Color(0.82,0.82,0.82))
	root.add_child(info_label)

	root.add_child(_divider(Color(0.85, 0.14, 0.28, 0.25)))

	# Kip speech
	kip_label = Label.new(); kip_label.text = ""
	kip_label.custom_minimum_size = Vector2(452, 46)
	kip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kip_label.add_theme_font_size_override("font_size", 13)
	kip_label.add_theme_color_override("font_color", Color(0.50, 0.82, 1.0))
	root.add_child(kip_label)

	# Combat log
	log_label = Label.new(); log_label.text = ""
	log_label.custom_minimum_size = Vector2(452, 28)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 12)
	log_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.35))
	root.add_child(log_label)

	root.add_child(_divider(Color(0.85, 0.14, 0.28, 0.25)))

	# ── Action Menu ───────────────────────────────────────────────────────────
	action_box = VBoxContainer.new()
	action_box.custom_minimum_size = Vector2(452, 0)
	action_box.visible = false
	root.add_child(action_box)

	# ── Forecast ─────────────────────────────────────────────────────────────
	forecast_box = VBoxContainer.new()
	forecast_box.custom_minimum_size = Vector2(452, 0)
	forecast_box.visible = false
	forecast_label = Label.new()
	forecast_label.add_theme_font_size_override("font_size", 13)
	forecast_label.add_theme_color_override("font_color", Color(0.88,0.88,0.88))
	forecast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	forecast_box.add_child(forecast_label)
	root.add_child(forecast_box)

	# ── Items ─────────────────────────────────────────────────────────────────
	items_box = VBoxContainer.new()
	items_box.custom_minimum_size = Vector2(452, 0)
	items_box.visible = false
	root.add_child(items_box)

	root.add_child(_spacer(6))

	# End Turn
	end_turn_btn = Button.new()
	end_turn_btn.text = "END TURN →"
	end_turn_btn.custom_minimum_size = Vector2(452, 46)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	root.add_child(end_turn_btn)

	# Legend
	root.add_child(_spacer(4))
	var leg = Label.new()
	leg.text = "Click unit → move/action  |  ESC = cancel\n△=Archer  ○=Mage  ▷=Rogue  +=Healer  ★=Warden\nDot = Kip element  Ring = Deployed  Gold = Awakened"
	leg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leg.add_theme_font_size_override("font_size", 11)
	leg.add_theme_color_override("font_color", Color(0.35,0.35,0.35))
	root.add_child(leg)

func _hide_all_panels():
	action_box.visible   = false
	forecast_box.visible = false
	items_box.visible    = false
	_set_end_turn_visible(true)

func _set_end_turn_visible(v: bool):
	end_turn_btn.visible  = v
	end_turn_btn.disabled = not BattleState.is_player_phase

func _divider(col: Color = Color(0.85, 0.14, 0.28, 0.5)) -> Control:
	var d = ColorRect.new()
	d.color = col; d.custom_minimum_size = Vector2(452, 1)
	return d

func _spacer(h: int) -> Control:
	var s = Control.new(); s.custom_minimum_size = Vector2(0, h)
	return s
