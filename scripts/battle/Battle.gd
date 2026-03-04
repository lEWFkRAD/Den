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
var info_rtl:        RichTextLabel
var kip_label:       Label
var log_label:       Label
var action_box:      VBoxContainer
var forecast_box:    VBoxContainer
var items_box:       VBoxContainer
var forecast_rtl:    RichTextLabel
var end_turn_btn:    Button
var hp_bar_bg:       ColorRect
var hp_bar_fill:     ColorRect
var hp_bar_label:    Label
var portrait_tex:    TextureRect
var kip_portrait_tex: TextureRect
var portrait_cache:  Dictionary = {}  # name_lower → Texture2D
var kip_portrait_cache: Dictionary = {}  # kip_name_lower → Texture2D

# Pause menu
var pause_overlay:   ColorRect
var pause_menu:      VBoxContainer
var is_pause_open:   bool = false

# Combat close-up
var combat_layer:    CanvasLayer
var combat_panel:    ColorRect
var combat_atk_portrait: TextureRect
var combat_def_portrait: TextureRect
var combat_atk_hp:   ColorRect
var combat_def_hp:   ColorRect
var combat_atk_name: Label
var combat_def_name: Label
var combat_vs:       Label

# Speech timer
var speech_timer:   float = 0.0
var log_timer:      float = 0.0
var log_queue:      Array = []

# ─── Ready ────────────────────────────────────────────────────────────────────

func _ready():
	_setup_camera()
	_load_portraits()
	_build_ui()
	_build_pause_menu()
	_build_combat_closeup()
	_start_battle()
	BattleState.kip_speaks.connect(_on_kip_speaks)
	BattleState.unit_died.connect(_on_unit_died)

func _load_portraits():
	var char_names = ["aldric", "mira", "voss", "seren", "bram", "corvin", "yael", "lorn"]
	for cname in char_names:
		var path = "res://assets/portraits/%s.png" % cname
		if ResourceLoader.exists(path):
			portrait_cache[cname] = load(path)
	var kip_names = ["scar", "thorn", "bolt", "null", "sleet", "dusk", "solen", "the_first"]
	for kname in kip_names:
		var path = "res://assets/kips/%s.png" % kname
		if ResourceLoader.exists(path):
			kip_portrait_cache[kname] = load(path)

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
	# Pause toggle always available
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_pause_open:
			_close_pause_menu()
			return
		elif state == State.IDLE and BattleState.is_player_phase:
			_open_pause_menu()
			return
		else:
			_cancel_action()
			return

	# Block all input while paused
	if is_pause_open: return

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
	_set_info_text("Select a unit.")
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
	btn.custom_minimum_size = Vector2(440, 40)
	btn.disabled = not enabled
	btn.pressed.connect(callback)
	btn.add_theme_font_size_override("font_size", 14)

	# Normal state
	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.6)
	style.border_color = col.darkened(0.15)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)

	# Hover state
	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.4)
	hover.border_color = col
	hover.set_border_width_all(1)
	hover.border_width_left = 3
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)

	# Pressed state
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = col.darkened(0.25)
	pressed.border_color = col.lightened(0.2)
	pressed.set_border_width_all(1)
	pressed.border_width_left = 3
	pressed.set_corner_radius_all(4)
	pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)

	# Disabled state
	var disabled_style = StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.12, 0.12, 0.14)
	disabled_style.border_color = Color(0.2, 0.2, 0.22)
	disabled_style.set_border_width_all(1)
	disabled_style.border_width_left = 3
	disabled_style.set_corner_radius_all(4)
	disabled_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.3, 0.32))

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
	var before_hp = target.stats.hp
	var msg = CombatResolver.resolve_heal(selected_unit, target)
	var healed_amt = target.stats.hp - before_hp
	# Record kip healing memory
	if selected_unit.bonded_kip and healed_amt > 0:
		selected_unit.bonded_kip.record_event("allies_healed", 1)
		selected_unit.bonded_kip.record_event("total_hp_healed", healed_amt)
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
		# Track tiles changed by element
		var tiles_affected = 0
		for x in range(selected_unit.grid_position.x - r, selected_unit.grid_position.x + r + 1):
			for y in range(selected_unit.grid_position.y - r, selected_unit.grid_position.y + r + 1):
				if abs(x - selected_unit.grid_position.x) + abs(y - selected_unit.grid_position.y) <= r:
					if grid.tiles.has(Vector2i(x, y)):
						tiles_affected += 1
		kip.record_event("tiles_changed", tiles_affected)
		# Track element-specific tile counts
		match kip.element:
			"ice":      kip.record_event("tiles_frozen", tiles_affected)
			"void":     kip.record_event("tiles_voided", tiles_affected)
			"plant":    kip.record_event("plant_tiles_created", tiles_affected)
			"dark":     kip.record_event("dark_tiles_created", tiles_affected)
			"light":    kip.record_event("radiant_tiles_created", tiles_affected)
			"electric": kip.record_event("charged_tiles_stood", tiles_affected)

		# Awakening deals damage to all enemies in radius
		var hit = 0
		for u in units:
			if not u.is_player_unit and u.is_alive():
				var dist = (u.grid_position - selected_unit.grid_position).length()
				if dist <= r + 0.5:
					var dmg = kip.get_awakening_damage()
					u.take_damage(dmg, kip.element)
					kip.record_event("damage_dealt", dmg)
					grid.flash(u.grid_position, Color(1.0, 0.5, 0.0, 0.9), 0.8)
					hit += 1
					if not u.is_alive():
						grid.tiles[u.grid_position].occupant = null
						kip.record_event("kills_witnessed", 1)
		kip.record_event("chain_hits", hit)
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
	forecast_rtl.clear()
	forecast_rtl.push_color(Color(0.85, 0.14, 0.28))
	forecast_rtl.append_text("COMBAT FORECAST\n")
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(0.75, 0.75, 0.75))
	forecast_rtl.append_text("────────────────────────────────\n")
	forecast_rtl.pop()

	# Attacker vs Defender header
	forecast_rtl.push_color(Color(0.55, 0.78, 1.0))
	forecast_rtl.append_text(fc["atk_name"])
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(0.5, 0.5, 0.5))
	forecast_rtl.append_text("  vs  ")
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(1.0, 0.45, 0.35))
	forecast_rtl.append_text(fc["def_name"] + "\n")
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(0.55, 0.55, 0.55))
	forecast_rtl.append_text("%s  vs  %s\n\n" % [fc["atk_weapon"], fc["def_weapon"]])
	forecast_rtl.pop()

	# Attacker stats
	forecast_rtl.push_color(Color(0.55, 0.78, 1.0))
	forecast_rtl.append_text("ATK  ")
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(0.9, 0.9, 0.9))
	forecast_rtl.append_text("DMG %d   HIT %d%%   CRIT %d%%" % [fc["atk_damage"], fc["atk_hit"], fc["atk_crit"]])
	forecast_rtl.pop()
	if fc["atk_double"]:
		forecast_rtl.push_color(Color(1.0, 0.85, 0.2))
		forecast_rtl.append_text("  x2")
		forecast_rtl.pop()
	forecast_rtl.append_text("\n")

	# Defender stats
	if fc["def_can_counter"]:
		forecast_rtl.push_color(Color(1.0, 0.45, 0.35))
		forecast_rtl.append_text("DEF  ")
		forecast_rtl.pop()
		forecast_rtl.push_color(Color(0.9, 0.9, 0.9))
		forecast_rtl.append_text("DMG %d   HIT %d%%   CRIT %d%%" % [fc["def_damage"], fc["def_hit"], fc["def_crit"]])
		forecast_rtl.pop()
		if fc["def_double"]:
			forecast_rtl.push_color(Color(1.0, 0.85, 0.2))
			forecast_rtl.append_text("  x2")
			forecast_rtl.pop()
		forecast_rtl.append_text("\n")
	else:
		forecast_rtl.push_color(Color(0.45, 0.45, 0.45))
		forecast_rtl.append_text("DEF  Cannot counter.\n")
		forecast_rtl.pop()

	# Element interaction
	var atk_elem = forecast_attacker.weapon.element if forecast_attacker.weapon and forecast_attacker.weapon.element != "" else forecast_attacker.element
	var wt = ElementRegistry.get_weakness_text(atk_elem, forecast_defender.element)
	if wt != "":
		forecast_rtl.push_color(_elem_ui_color(atk_elem))
		forecast_rtl.append_text("\n%s" % wt)
		forecast_rtl.pop()

	for c in forecast_box.get_children():
		if c is Button: c.queue_free()
	await get_tree().process_frame

	var confirm = _make_styled_btn("CONFIRM ATTACK", Color(0.8, 0.1, 0.1), 42)
	confirm.pressed.connect(_on_confirm_attack)
	forecast_box.add_child(confirm)

	var back = _make_styled_btn("Back", Color(0.25, 0.25, 0.4), 36)
	back.pressed.connect(func(): _enter_action_menu())
	forecast_box.add_child(back)

	state = State.COMBAT_FORECAST

func _on_confirm_attack():
	if forecast_attacker == null or forecast_defender == null: return
	state = State.ANIMATING
	_hide_all_panels()
	_show_combat_closeup(forecast_attacker, forecast_defender)

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
		grid.pop_damage(defender.grid_position, "MISS", Color(0.6, 0.6, 0.7))
		return

	var damage    = CombatResolver.get_damage(attacker, weapon, defender)
	var crit_roll = randi() % 100
	var is_crit   = crit_roll < CombatResolver.get_crit(attacker, weapon, defender)

	if is_crit:
		damage = int(damage * 3)
		_push_log("CRITICAL! %s → %s: %d damage" % [attacker.unit_name, defender.unit_name, damage])
		grid.flash(defender.grid_position, Color(1.0, 0.2, 0.0, 0.9), 0.5)
		grid.pop_damage(defender.grid_position, "%d!" % damage, Color(1.0, 0.3, 0.0), 1.2)
	else:
		_push_log("%s → %s: %d damage" % [attacker.unit_name, defender.unit_name, damage])
		grid.flash(defender.grid_position, Color(0.9, 0.1, 0.1, 0.8), 0.4)
		grid.pop_damage(defender.grid_position, "%d" % damage, Color(1.0, 1.0, 1.0))

	var elem = weapon.element if weapon.element != "" else attacker.element
	defender.take_damage(damage, elem)
	weapon.use_one()

	# Update combat close-up HP bars
	if forecast_attacker and forecast_defender:
		_update_combat_hp(forecast_attacker, forecast_defender)

	# Hit recoil on defender
	if defender.is_alive():
		await grid.animate_hit_recoil(defender)
	else:
		_push_log("%s fell." % defender.unit_name)

	grid.queue_redraw()

func _finish_combat(attacker):
	_hide_combat_closeup()
	attacker.has_acted = true
	# Record kip memory for kills
	_record_kip_combat_events(attacker, forecast_defender)
	_deselect()
	_check_all_acted()
	_check_battle_outcome()

# ─── Kip Memory Recording ───────────────────────────────────────────────────

func _record_kip_combat_events(attacker, defender):
	# When an enemy dies, all nearby player kips witness the kill
	if defender != null and not defender.is_alive() and not defender.is_player_unit:
		for u in units:
			if u.is_player_unit and u.is_alive() and u.bonded_kip:
				var dist = (u.grid_position - defender.grid_position).length()
				if dist <= 5.0:
					u.bonded_kip.record_event("kills_witnessed", 1)

	# When a player kills, their own kip records damage dealt
	if attacker.is_player_unit and attacker.bonded_kip:
		attacker.bonded_kip.record_event("battles_witnessed", 1)
		if defender and not defender.is_alive():
			attacker.bonded_kip.record_event("damage_dealt", defender.stats.max_hp)

	# When a player unit narrowly survives (saved by proximity), record ally saved
	if defender != null and defender.is_player_unit and defender.is_alive():
		var hpr = float(defender.stats.hp) / float(defender.stats.max_hp)
		if hpr < 0.25:
			for u in units:
				if u.is_player_unit and u.is_alive() and u != defender and u.bonded_kip:
					var dist = (u.grid_position - defender.grid_position).length()
					if dist <= 3.0:
						u.bonded_kip.record_event("allies_saved", 1)

func _record_kip_tile_events():
	# Called each turn — record what elemental tiles kips are standing on
	for u in units:
		if not u.is_player_unit or not u.is_alive() or u.bonded_kip == null: continue
		var tile = grid.tiles.get(u.grid_position)
		if tile == null: continue
		var kip = u.bonded_kip
		match tile.elemental_state:
			Tile.ElementalState.CHARGED:   kip.record_event("charged_tiles_stood", 1)
			Tile.ElementalState.BLOODSOAKED: kip.record_event("blood_tiles_stood", 1)
			Tile.ElementalState.FROZEN:    kip.record_event("frozen_tiles_stood", 1)

func _check_kip_evolutions():
	for u in units:
		if not u.is_player_unit or not u.is_alive() or u.bonded_kip == null: continue
		if u.bonded_kip.check_evolution():
			_push_log("%s has evolved into %s!" % [u.bonded_kip.kip_name, u.bonded_kip.evolution_name])
			BattleState.kip_evolved.emit(u.bonded_kip.kip_name, u.bonded_kip.evolution_name)
			grid.flash(u.grid_position, Color(1.0, 0.9, 0.3, 0.9), 1.5)

# ─── Turn / Phase Signals ────────────────────────────────────────────────────

func _on_player_phase(turn: int):
	phase_label.text = "Player Phase  —  Turn %d" % (turn + 1)
	turn_label.text  = "Turn %d" % (turn + 1)
	end_turn_btn.disabled = false
	# Record kip tile standing events and check evolutions each turn
	_record_kip_tile_events()
	_check_kip_evolutions()
	# Apply mutation effects
	_apply_kip_mutations()
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
		_set_info_text("All units lost.\nPress ESC.")
		state = State.BATTLE_OVER
	elif not e:
		phase_label.text = "— VICTORY —"
		# Check for kip evolutions on victory
		_check_kip_evolutions()
		_set_info_text("All enemies defeated.")
		state = State.BATTLE_OVER

func _apply_kip_mutations():
	for u in units:
		if not u.is_player_unit or not u.is_alive() or u.bonded_kip == null: continue
		var kip = u.bonded_kip
		if not kip.is_evolved: continue

		# Blood Drain: War Beast heals when nearby enemies died last turn
		if kip.has_mutation("blood_drain"):
			# Passive healing handled in _record_kip_combat_events
			pass

		# Chain Lightning / Permafrost: Spreading elemental tiles
		if kip.has_mutation("chain_lightning") or kip.has_mutation("permafrost"):
			var spread_elem = "electric" if kip.has_mutation("chain_lightning") else "ice"
			var spread_tiles: Array = []
			for pos in grid.tiles:
				var tile = grid.tiles[pos]
				var target_state = Tile.ElementalState.CHARGED if spread_elem == "electric" else Tile.ElementalState.FROZEN
				if tile.elemental_state == target_state:
					var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
					var chosen = dirs[randi() % dirs.size()]
					var adj = pos + chosen
					if grid.tiles.has(adj) and grid.tiles[adj].elemental_state == Tile.ElementalState.NEUTRAL:
						spread_tiles.append(adj)
			for sp in spread_tiles:
				grid.tiles[sp].set_elemental_state(spread_elem, 3 if kip.has_mutation("chain_lightning") else 5)
				grid.flash(sp, grid._elem_color(spread_elem), 0.5)

		# Sanctify: Heal allies on radiant tiles
		if kip.has_mutation("sanctify"):
			for ally in units:
				if ally.is_player_unit and ally.is_alive():
					var tile = grid.tiles.get(ally.grid_position)
					if tile and tile.elemental_state == Tile.ElementalState.RADIANT:
						var heal_amt = min(3, ally.stats.max_hp - ally.stats.hp)
						if heal_amt > 0:
							ally.stats.hp += heal_amt
							grid.pop_damage(ally.grid_position, "+%d" % heal_amt, Color(0.3, 1.0, 0.5))
							kip.record_event("total_hp_healed", heal_amt)

		# Entangle: Enemies on overgrown tiles lose movement (handled in movement calc)
		# Shroud: Enemies on dark tiles get hit penalty (handled in combat calc)
		# Annihilate: Voided tiles become permanent (extend duration)
		if kip.has_mutation("annihilate"):
			for pos in grid.tiles:
				var tile = grid.tiles[pos]
				if tile.elemental_state == Tile.ElementalState.VOIDED:
					tile.elemental_turns_remaining = max(tile.elemental_turns_remaining, 99)

		# Judgment: Applied during awakening, not per-turn
		# Blood Drain: heal on nearby enemy death
		if kip.has_mutation("blood_drain"):
			# Check if any enemy died last turn within 3 tiles
			for other in units:
				if not other.is_player_unit and not other.is_alive():
					var dist = (other.grid_position - u.grid_position).length()
					if dist <= 3.0:
						var heal = min(4, kip.max_hp - kip.hp)
						if heal > 0:
							kip.hp += heal
							grid.pop_damage(u.grid_position, "+%d" % heal, Color(0.8, 0.2, 0.2))

func _cancel_action():
	match state:
		State.SELECT_ATTACK:   _enter_action_menu()
		State.ACTION_MENU:     _on_action_back()
		State.COMBAT_FORECAST: _enter_action_menu()
		State.SELECT_ITEM:     _enter_action_menu()
		State.UNIT_SELECTED:   _deselect()

func _refresh_info(unit):
	_set_info_bbcode(unit)

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

	# Panel background with gradient effect
	var bg = ColorRect.new()
	bg.color = Color(0.04, 0.04, 0.07, 0.98)
	bg.position = Vector2(PANEL_X, 0); bg.size = Vector2(484, 720)
	ui_layer.add_child(bg)

	# Accent stripe on left edge
	var accent = ColorRect.new()
	accent.color = Color(0.85, 0.14, 0.28, 0.8)
	accent.position = Vector2(PANEL_X, 0); accent.size = Vector2(2, 720)
	ui_layer.add_child(accent)

	# Subtle gradient overlay at top
	var grad_top = ColorRect.new()
	grad_top.color = Color(0.10, 0.08, 0.14, 0.35)
	grad_top.position = Vector2(PANEL_X, 0); grad_top.size = Vector2(484, 80)
	ui_layer.add_child(grad_top)

	var root = VBoxContainer.new()
	root.position = Vector2(PANEL_X + 18, 12)
	root.custom_minimum_size = Vector2(448, 696)
	ui_layer.add_child(root)
	ui_panel = root

	# Title row
	var row = HBoxContainer.new(); row.custom_minimum_size = Vector2(448, 40)
	var title = Label.new(); title.text = "D E N"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	row.add_child(title)
	var spacer = Control.new(); spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	turn_label = Label.new(); turn_label.text = "Turn 1"
	turn_label.add_theme_font_size_override("font_size", 13)
	turn_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.42))
	row.add_child(turn_label)
	root.add_child(row)

	root.add_child(_divider())

	# Phase indicator (styled pill)
	var phase_container = PanelContainer.new()
	var phase_style = StyleBoxFlat.new()
	phase_style.bg_color = Color(0.14, 0.13, 0.08, 0.6)
	phase_style.border_color = Color(0.78, 0.72, 0.28, 0.3)
	phase_style.set_border_width_all(1)
	phase_style.set_corner_radius_all(4)
	phase_style.set_content_margin_all(6)
	phase_container.add_theme_stylebox_override("panel", phase_style)
	phase_label = Label.new(); phase_label.text = "Player Phase  —  Turn 1"
	phase_label.add_theme_font_size_override("font_size", 14)
	phase_label.add_theme_color_override("font_color", Color(0.82, 0.76, 0.30))
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_container.add_child(phase_label)
	root.add_child(phase_container)

	root.add_child(_spacer(6))

	# Portrait row (character + kip side by side)
	var portrait_row = HBoxContainer.new()
	portrait_row.custom_minimum_size = Vector2(448, 0)
	portrait_row.add_theme_constant_override("separation", 8)

	portrait_tex = TextureRect.new()
	portrait_tex.custom_minimum_size = Vector2(110, 100)
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	portrait_tex.visible = false
	portrait_row.add_child(portrait_tex)

	kip_portrait_tex = TextureRect.new()
	kip_portrait_tex.custom_minimum_size = Vector2(80, 80)
	kip_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	kip_portrait_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH
	kip_portrait_tex.visible = false
	portrait_row.add_child(kip_portrait_tex)

	root.add_child(portrait_row)
	root.add_child(_spacer(4))

	# Info panel (RichTextLabel in a card)
	var info_card = PanelContainer.new()
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.06, 0.06, 0.09, 0.7)
	info_style.border_color = Color(0.18, 0.18, 0.22)
	info_style.set_border_width_all(1)
	info_style.set_corner_radius_all(5)
	info_style.set_content_margin_all(10)
	info_card.add_theme_stylebox_override("panel", info_style)
	info_rtl = RichTextLabel.new()
	info_rtl.bbcode_enabled = true
	info_rtl.scroll_active = false
	info_rtl.fit_content = true
	info_rtl.custom_minimum_size = Vector2(428, 140)
	info_rtl.add_theme_font_size_override("normal_font_size", 13)
	info_rtl.add_theme_color_override("default_color", Color(0.80, 0.80, 0.80))
	info_card.add_child(info_rtl)
	root.add_child(info_card)
	_set_info_text("Select a unit.")

	root.add_child(_spacer(4))

	# Kip speech (styled)
	kip_label = Label.new(); kip_label.text = ""
	kip_label.custom_minimum_size = Vector2(448, 36)
	kip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	kip_label.add_theme_font_size_override("font_size", 12)
	kip_label.add_theme_color_override("font_color", Color(0.50, 0.82, 1.0))
	root.add_child(kip_label)

	# Combat log
	log_label = Label.new(); log_label.text = ""
	log_label.custom_minimum_size = Vector2(448, 24)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 12)
	log_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.38))
	root.add_child(log_label)

	root.add_child(_divider(Color(0.85, 0.14, 0.28, 0.2)))

	# ── Action Menu ───────────────────────────────────────────────────────────
	action_box = VBoxContainer.new()
	action_box.custom_minimum_size = Vector2(448, 0)
	action_box.add_theme_constant_override("separation", 4)
	action_box.visible = false
	root.add_child(action_box)

	# ── Forecast ─────────────────────────────────────────────────────────────
	forecast_box = VBoxContainer.new()
	forecast_box.custom_minimum_size = Vector2(448, 0)
	forecast_box.visible = false
	var fc_card = PanelContainer.new()
	var fc_style = StyleBoxFlat.new()
	fc_style.bg_color = Color(0.06, 0.06, 0.09, 0.7)
	fc_style.border_color = Color(0.18, 0.18, 0.22)
	fc_style.set_border_width_all(1)
	fc_style.set_corner_radius_all(5)
	fc_style.set_content_margin_all(10)
	fc_card.add_theme_stylebox_override("panel", fc_style)
	forecast_rtl = RichTextLabel.new()
	forecast_rtl.bbcode_enabled = true
	forecast_rtl.scroll_active = false
	forecast_rtl.fit_content = true
	forecast_rtl.custom_minimum_size = Vector2(420, 80)
	forecast_rtl.add_theme_font_size_override("normal_font_size", 13)
	forecast_rtl.add_theme_color_override("default_color", Color(0.80, 0.80, 0.80))
	fc_card.add_child(forecast_rtl)
	forecast_box.add_child(fc_card)
	root.add_child(forecast_box)

	# ── Items ─────────────────────────────────────────────────────────────────
	items_box = VBoxContainer.new()
	items_box.custom_minimum_size = Vector2(448, 0)
	items_box.visible = false
	root.add_child(items_box)

	root.add_child(_spacer(6))

	# End Turn button (prominent)
	end_turn_btn = Button.new()
	end_turn_btn.text = "END TURN"
	end_turn_btn.custom_minimum_size = Vector2(448, 44)
	end_turn_btn.add_theme_font_size_override("font_size", 15)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	var et_style = StyleBoxFlat.new()
	et_style.bg_color = Color(0.55, 0.09, 0.16)
	et_style.border_color = Color(0.85, 0.14, 0.28)
	et_style.set_border_width_all(1)
	et_style.set_corner_radius_all(5)
	et_style.set_content_margin_all(8)
	end_turn_btn.add_theme_stylebox_override("normal", et_style)
	var et_hover = StyleBoxFlat.new()
	et_hover.bg_color = Color(0.65, 0.12, 0.20)
	et_hover.border_color = Color(0.95, 0.25, 0.35)
	et_hover.set_border_width_all(1)
	et_hover.set_corner_radius_all(5)
	et_hover.set_content_margin_all(8)
	end_turn_btn.add_theme_stylebox_override("hover", et_hover)
	var et_pressed = StyleBoxFlat.new()
	et_pressed.bg_color = Color(0.75, 0.15, 0.22)
	et_pressed.border_color = Color(1.0, 0.3, 0.4)
	et_pressed.set_border_width_all(1)
	et_pressed.set_corner_radius_all(5)
	et_pressed.set_content_margin_all(8)
	end_turn_btn.add_theme_stylebox_override("pressed", et_pressed)
	var et_disabled = StyleBoxFlat.new()
	et_disabled.bg_color = Color(0.12, 0.08, 0.10)
	et_disabled.border_color = Color(0.22, 0.15, 0.18)
	et_disabled.set_border_width_all(1)
	et_disabled.set_corner_radius_all(5)
	et_disabled.set_content_margin_all(8)
	end_turn_btn.add_theme_stylebox_override("disabled", et_disabled)
	end_turn_btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.2, 0.22))
	root.add_child(end_turn_btn)

	# Legend
	root.add_child(_spacer(6))
	var leg = Label.new()
	leg.text = "Click unit  >  move/action   |   ESC = cancel\nShapes: Square=Soldier  Diamond=Archer  Circle=Mage\nTriangle=Rogue  Cross=Healer  Star=Warden"
	leg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	leg.add_theme_font_size_override("font_size", 10)
	leg.add_theme_color_override("font_color", Color(0.28, 0.28, 0.30))
	root.add_child(leg)

func _hide_all_panels():
	action_box.visible   = false
	forecast_box.visible = false
	items_box.visible    = false
	_set_end_turn_visible(true)

func _set_end_turn_visible(v: bool):
	end_turn_btn.visible  = v
	end_turn_btn.disabled = not BattleState.is_player_phase

func _divider(col: Color = Color(0.85, 0.14, 0.28, 0.4)) -> Control:
	var d = ColorRect.new()
	d.color = col; d.custom_minimum_size = Vector2(448, 1)
	return d

func _spacer(h: int) -> Control:
	var s = Control.new(); s.custom_minimum_size = Vector2(0, h)
	return s

# ─── Info Display Helpers ─────────────────────────────────────────────────────

func _set_info_text(text: String):
	info_rtl.clear()
	info_rtl.append_text(text)
	portrait_tex.visible = false
	kip_portrait_tex.visible = false

func _set_info_bbcode(unit):
	info_rtl.clear()

	# Show portrait
	var pkey = unit.unit_name.to_lower()
	if portrait_cache.has(pkey):
		portrait_tex.texture = portrait_cache[pkey]
		portrait_tex.visible = true
	else:
		portrait_tex.visible = false

	# Show kip portrait
	if unit.bonded_kip:
		var kip_key = unit.bonded_kip.kip_name.to_lower().replace(" ", "_")
		# Handle "Null" kip → file is "null.png"
		if kip_portrait_cache.has(kip_key):
			kip_portrait_tex.texture = kip_portrait_cache[kip_key]
			kip_portrait_tex.visible = true
		else:
			kip_portrait_tex.visible = false
	else:
		kip_portrait_tex.visible = false

	# Unit name (big, team-colored)
	var name_col = "#5588ee" if unit.is_player_unit else "#ee4433"
	info_rtl.push_color(Color(name_col))
	info_rtl.push_font_size(16)
	info_rtl.append_text(unit.unit_name)
	info_rtl.pop(); info_rtl.pop()
	info_rtl.append_text("\n")

	# Class + Element
	info_rtl.push_color(Color(0.55, 0.55, 0.55))
	info_rtl.append_text(unit.unit_class)
	info_rtl.pop()
	if unit.element != "":
		info_rtl.append_text("  ")
		info_rtl.push_color(_elem_ui_color(unit.element))
		info_rtl.append_text(unit.element.to_upper())
		info_rtl.pop()
	info_rtl.append_text("\n\n")

	# HP with color
	var hpr = float(unit.stats.hp) / float(unit.stats.max_hp)
	var hp_col = Color(0.2, 0.88, 0.2) if hpr > 0.5 else (Color(0.92, 0.6, 0.12) if hpr > 0.25 else Color(0.92, 0.15, 0.15))
	info_rtl.push_color(Color(0.5, 0.5, 0.5))
	info_rtl.append_text("HP ")
	info_rtl.pop()
	info_rtl.push_color(hp_col)
	info_rtl.append_text("%d" % unit.stats.hp)
	info_rtl.pop()
	info_rtl.push_color(Color(0.4, 0.4, 0.4))
	info_rtl.append_text("/%d" % unit.stats.max_hp)
	info_rtl.pop()
	info_rtl.push_color(Color(0.5, 0.5, 0.5))
	info_rtl.append_text("   MOV ")
	info_rtl.pop()
	info_rtl.push_color(Color(0.8, 0.8, 0.8))
	info_rtl.append_text("%d\n" % unit.stats.movement)
	info_rtl.pop()

	# Stats in compact grid
	var stats_text = "STR %2d   MAG %2d   SKL %2d\nSPD %2d   DEF %2d   RES %2d" % [
		unit.stats.strength, unit.stats.magic, unit.stats.skill,
		unit.stats.speed, unit.stats.defense, unit.stats.resistance]
	info_rtl.push_color(Color(0.65, 0.65, 0.65))
	info_rtl.append_text(stats_text + "\n")
	info_rtl.pop()

	# Weapon
	if unit.weapon:
		info_rtl.append_text("\n")
		info_rtl.push_color(Color(0.85, 0.14, 0.28, 0.6))
		info_rtl.append_text("────────────────────────────\n")
		info_rtl.pop()
		info_rtl.push_color(Color(0.88, 0.82, 0.68))
		info_rtl.append_text(unit.weapon.weapon_name)
		info_rtl.pop()
		if unit.weapon.element != "":
			info_rtl.append_text("  ")
			info_rtl.push_color(_elem_ui_color(unit.weapon.element))
			info_rtl.append_text(unit.weapon.element.to_upper())
			info_rtl.pop()
		info_rtl.append_text("\n")
		info_rtl.push_color(Color(0.55, 0.55, 0.55))
		info_rtl.append_text("Atk %d  Hit %d%%  Crit %d%%  Range %d-%d\n" % [
			unit.weapon.attack, unit.weapon.hit, unit.weapon.crit,
			unit.weapon.min_range, unit.weapon.max_range])
		info_rtl.pop()

	# Items
	if not unit.items.is_empty():
		info_rtl.push_color(Color(0.5, 0.5, 0.5))
		for it in unit.items:
			info_rtl.append_text("%s (%d) " % [it.item_name, it.uses])
		info_rtl.pop()
		info_rtl.append_text("\n")

	# Terrain info
	var tile = grid.tiles.get(unit.grid_position)
	if tile:
		var terrain_name = tile.get_terrain_name()
		if terrain_name != "Plain":
			info_rtl.append_text("\n")
			info_rtl.push_color(Color(0.5, 0.5, 0.5))
			info_rtl.append_text("Terrain: ")
			info_rtl.pop()
			info_rtl.push_color(Color(0.7, 0.7, 0.6))
			info_rtl.append_text(terrain_name)
			info_rtl.pop()
			if tile.defense_bonus > 0 or tile.avoid_bonus > 0:
				info_rtl.push_color(Color(0.4, 0.7, 0.4))
				info_rtl.append_text("  DEF+%d  AVO+%d" % [tile.defense_bonus, tile.avoid_bonus])
				info_rtl.pop()
			if tile.heal_bonus > 0:
				info_rtl.push_color(Color(0.4, 0.8, 0.5))
				info_rtl.append_text("  HEAL+%d" % tile.heal_bonus)
				info_rtl.pop()

	# Kip info
	if unit.bonded_kip:
		var k = unit.bonded_kip
		info_rtl.append_text("\n")
		info_rtl.push_color(Color(0.85, 0.14, 0.28, 0.6))
		info_rtl.append_text("────────────────────────────\n")
		info_rtl.pop()
		info_rtl.push_color(_elem_ui_color(k.element))
		if k.is_evolved:
			info_rtl.append_text("%s (%s)" % [k.kip_name, k.evolution_name])
		else:
			info_rtl.append_text(k.kip_name)
		info_rtl.pop()
		info_rtl.push_color(Color(0.5, 0.5, 0.5))
		info_rtl.append_text("  %s  HP %d/%d" % [k.get_phase_label(), k.hp, k.max_hp])
		if k.is_exhausted:
			info_rtl.push_color(Color(0.65, 0.35, 0.35))
			info_rtl.append_text("  EXHAUSTED")
			info_rtl.pop()
		info_rtl.pop()
		# Show evolution progress if not evolved
		if not k.is_evolved:
			var progress = k.get_evolution_progress()
			if not progress.is_empty():
				info_rtl.append_text("\n")
				info_rtl.push_color(Color(0.45, 0.40, 0.55))
				var done_count = 0
				var total_count = progress.size()
				for pkey in progress:
					var p = progress[pkey]
					if p["complete"]: done_count += 1
				info_rtl.append_text("Evolution: %d/%d" % [done_count, total_count])
				info_rtl.pop()
		elif k.mutation_ability != "":
			info_rtl.append_text("\n")
			info_rtl.push_color(Color(0.7, 0.55, 0.9))
			info_rtl.append_text("Mutation: %s" % k.mutation_description)
			info_rtl.pop()

func _make_styled_btn(label: String, col: Color, height: int = 40) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(440, height)
	btn.add_theme_font_size_override("font_size", 14)
	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.5)
	style.border_color = col.darkened(0.1)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.3)
	hover.border_color = col
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	return btn

func _elem_ui_color(elem: String) -> Color:
	match elem:
		"blood":    return Color(0.85, 0.15, 0.15)
		"electric": return Color(0.95, 0.95, 0.15)
		"void":     return Color(0.55, 0.15, 0.78)
		"light":    return Color(1.0, 0.95, 0.55)
		"dark":     return Color(0.5, 0.2, 0.6)
		"ice":      return Color(0.55, 0.85, 1.0)
		"plant":    return Color(0.25, 0.82, 0.25)
		"god":      return Color(1.0, 1.0, 0.9)
	return Color(0.7, 0.7, 0.7)

# ─── Pause Menu ───────────────────────────────────────────────────────────────

func _build_pause_menu():
	var pause_layer = CanvasLayer.new()
	pause_layer.layer = 20
	add_child(pause_layer)

	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.65)
	pause_overlay.position = Vector2.ZERO
	pause_overlay.size = Vector2(1280, 720)
	pause_overlay.visible = false
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_layer.add_child(pause_overlay)

	pause_menu = VBoxContainer.new()
	pause_menu.position = Vector2(440, 160)
	pause_menu.custom_minimum_size = Vector2(400, 0)
	pause_overlay.add_child(pause_menu)

	var title = Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_menu.add_child(title)

	pause_menu.add_child(_spacer(20))

	_add_pause_btn("RESUME", Color(0.3, 0.6, 0.3), _close_pause_menu)
	_add_pause_btn("SAVE GAME", Color(0.3, 0.5, 0.8), _on_pause_save)
	_add_pause_btn("LOAD GAME", Color(0.5, 0.4, 0.2), _on_pause_load, GameState.has_save())
	_add_pause_btn("QUIT TO TITLE", Color(0.6, 0.15, 0.15), _on_pause_quit)

func _add_pause_btn(label: String, col: Color, callback: Callable, enabled: bool = true):
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(400, 48)
	btn.disabled = not enabled
	btn.pressed.connect(callback)
	btn.add_theme_font_size_override("font_size", 16)

	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.65)
	style.border_color = col.darkened(0.2)
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(12)
	btn.add_theme_stylebox_override("normal", style)

	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.4)
	hover.border_color = col
	hover.set_border_width_all(1)
	hover.set_corner_radius_all(5)
	hover.set_content_margin_all(12)
	btn.add_theme_stylebox_override("hover", hover)

	var dis = StyleBoxFlat.new()
	dis.bg_color = Color(0.08, 0.08, 0.10)
	dis.border_color = Color(0.15, 0.15, 0.18)
	dis.set_border_width_all(1)
	dis.set_corner_radius_all(5)
	dis.set_content_margin_all(12)
	btn.add_theme_stylebox_override("disabled", dis)
	btn.add_theme_color_override("font_disabled_color", Color(0.3, 0.3, 0.32))

	pause_menu.add_child(btn)

func _open_pause_menu():
	is_pause_open = true
	pause_overlay.visible = true
	BattleState.pause()

func _close_pause_menu():
	is_pause_open = false
	pause_overlay.visible = false
	BattleState.resume()

func _on_pause_save():
	if GameState.save_game(units):
		_push_log("Game saved.")
	else:
		_push_log("Save failed!")
	_close_pause_menu()

func _on_pause_load():
	if GameState.load_game():
		_close_pause_menu()
		get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")

func _on_pause_quit():
	_close_pause_menu()
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")

# ─── Combat Close-Up ─────────────────────────────────────────────────────────

func _build_combat_closeup():
	combat_layer = CanvasLayer.new()
	combat_layer.layer = 15
	add_child(combat_layer)

	combat_panel = ColorRect.new()
	combat_panel.color = Color(0.02, 0.02, 0.05, 0.92)
	combat_panel.position = Vector2(140, 200)
	combat_panel.size = Vector2(1000, 320)
	combat_panel.visible = false
	combat_layer.add_child(combat_panel)

	# Top accent line
	var accent = ColorRect.new()
	accent.color = Color(0.85, 0.14, 0.28, 0.6)
	accent.position = Vector2(0, 0)
	accent.size = Vector2(1000, 2)
	combat_panel.add_child(accent)

	# Bottom accent
	var accent2 = ColorRect.new()
	accent2.color = Color(0.85, 0.14, 0.28, 0.6)
	accent2.position = Vector2(0, 318)
	accent2.size = Vector2(1000, 2)
	combat_panel.add_child(accent2)

	# Attacker side (left)
	combat_atk_portrait = TextureRect.new()
	combat_atk_portrait.position = Vector2(30, 30)
	combat_atk_portrait.custom_minimum_size = Vector2(200, 260)
	combat_atk_portrait.size = Vector2(200, 260)
	combat_atk_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	combat_atk_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	combat_panel.add_child(combat_atk_portrait)

	combat_atk_name = Label.new()
	combat_atk_name.position = Vector2(240, 40)
	combat_atk_name.add_theme_font_size_override("font_size", 22)
	combat_atk_name.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	combat_panel.add_child(combat_atk_name)

	# Attacker HP bar bg
	var atk_hp_bg = ColorRect.new()
	atk_hp_bg.position = Vector2(240, 75)
	atk_hp_bg.size = Vector2(200, 14)
	atk_hp_bg.color = Color(0.08, 0.08, 0.10)
	combat_panel.add_child(atk_hp_bg)

	combat_atk_hp = ColorRect.new()
	combat_atk_hp.position = Vector2(240, 75)
	combat_atk_hp.size = Vector2(200, 14)
	combat_atk_hp.color = Color(0.15, 0.88, 0.15)
	combat_panel.add_child(combat_atk_hp)

	# VS label
	combat_vs = Label.new()
	combat_vs.text = "VS"
	combat_vs.position = Vector2(465, 130)
	combat_vs.add_theme_font_size_override("font_size", 36)
	combat_vs.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28, 0.7))
	combat_panel.add_child(combat_vs)

	# Defender side (right)
	combat_def_portrait = TextureRect.new()
	combat_def_portrait.position = Vector2(770, 30)
	combat_def_portrait.custom_minimum_size = Vector2(200, 260)
	combat_def_portrait.size = Vector2(200, 260)
	combat_def_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	combat_def_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	combat_panel.add_child(combat_def_portrait)

	combat_def_name = Label.new()
	combat_def_name.position = Vector2(560, 40)
	combat_def_name.custom_minimum_size = Vector2(200, 0)
	combat_def_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	combat_def_name.add_theme_font_size_override("font_size", 22)
	combat_def_name.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	combat_panel.add_child(combat_def_name)

	# Defender HP bar
	var def_hp_bg = ColorRect.new()
	def_hp_bg.position = Vector2(560, 75)
	def_hp_bg.size = Vector2(200, 14)
	def_hp_bg.color = Color(0.08, 0.08, 0.10)
	combat_panel.add_child(def_hp_bg)

	combat_def_hp = ColorRect.new()
	combat_def_hp.position = Vector2(560, 75)
	combat_def_hp.size = Vector2(200, 14)
	combat_def_hp.color = Color(0.15, 0.88, 0.15)
	combat_panel.add_child(combat_def_hp)

func _show_combat_closeup(atk, def):
	# Set attacker portrait
	var atk_key = atk.unit_name.to_lower()
	if portrait_cache.has(atk_key):
		combat_atk_portrait.texture = portrait_cache[atk_key]
	else:
		combat_atk_portrait.texture = null

	# Set defender portrait
	var def_key = def.unit_name.to_lower()
	if portrait_cache.has(def_key):
		combat_def_portrait.texture = portrait_cache[def_key]
	else:
		combat_def_portrait.texture = null

	combat_atk_name.text = atk.unit_name
	combat_def_name.text = def.unit_name

	# Set name colors based on team
	combat_atk_name.add_theme_color_override("font_color",
		Color(0.55, 0.78, 1.0) if atk.is_player_unit else Color(1.0, 0.45, 0.35))
	combat_def_name.add_theme_color_override("font_color",
		Color(0.55, 0.78, 1.0) if def.is_player_unit else Color(1.0, 0.45, 0.35))

	_update_combat_hp(atk, def)
	combat_panel.visible = true

func _update_combat_hp(atk, def):
	var atk_ratio = clampf(float(atk.stats.hp) / float(atk.stats.max_hp), 0.0, 1.0)
	var def_ratio = clampf(float(def.stats.hp) / float(def.stats.max_hp), 0.0, 1.0)

	combat_atk_hp.size.x = 200.0 * atk_ratio
	combat_def_hp.size.x = 200.0 * def_ratio

	combat_atk_hp.color = Color(0.15, 0.88, 0.15) if atk_ratio > 0.5 else (Color(0.92, 0.58, 0.1) if atk_ratio > 0.25 else Color(0.92, 0.12, 0.12))
	combat_def_hp.color = Color(0.15, 0.88, 0.15) if def_ratio > 0.5 else (Color(0.92, 0.58, 0.1) if def_ratio > 0.25 else Color(0.92, 0.12, 0.12))

func _hide_combat_closeup():
	combat_panel.visible = false
