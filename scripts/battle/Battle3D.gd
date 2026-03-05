extends Node3D

## 2.5D Tactical Battle Scene — Triangle Strategy / Tactics Ogre style
## Uses Grid3D for tile rendering, Sprite3D for units, orthographic camera.
## All combat logic reuses existing autoloads (CombatResolver, TurnManager, etc.)

const _MissionBattleLoader = preload("res://runtime/mission_battle_loader.gd")

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
var grid: Grid3D
var turn_manager: TurnManager
var units: Array = []

# ─── Camera ──────────────────────────────────────────────────────────────────
var camera: Camera3D
var cam_zoom: float = 12.0
const CAM_ZOOM_MIN: float = 5.0
const CAM_ZOOM_MAX: float = 25.0
const CAM_ZOOM_STEP: float = 0.5
var cam_dragging: bool = false
var cam_drag_last: Vector2
var cam_target: Vector3 = Vector3.ZERO
var cam_yaw: float = 45.0           # Orbital yaw around target (degrees)
const CAM_PITCH: float = -60.0      # Fixed pitch angle
const CAM_YAW_STEP: float = 45.0    # Q/E snap rotation step
const CAM_DISTANCE: float = 15.0
var cam_rotating: bool = false       # Shift+drag rotation active

# ─── Selection ───────────────────────────────────────────────────────────────
var selected_unit  = null
var pre_move_pos:  Vector2i
var movement_tiles: Array = []
var attack_targets: Array = []
var forecast_attacker = null
var forecast_defender = null
var hovered_tile: Vector2i = Vector2i(-1, -1)
var show_elevation: bool = false

# ─── UI Nodes ────────────────────────────────────────────────────────────────
const PANEL_X: int = 960
var ui_layer:        CanvasLayer
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
var portrait_cache:  Dictionary = {}
var kip_portrait_cache: Dictionary = {}

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

# Speech / log
var speech_timer: float = 0.0
var log_timer:    float = 0.0
var log_queue:    Array = []

# Map generator
var map_gen: MapGenerator

# ─── Mission Loading ─────────────────────────────────────────────────────────
## Set mission_path before adding to scene tree to use generated mission data.
## Leave empty to use the default hard-coded battle.
var mission_path: String = ""
var player_characters: Array = ["aldric", "mira", "voss", "seren", "bram", "corvin", "yael"]
var current_objective: String = "rout"
var mission_loot: Array = []
var mission_data: Dictionary = {}

# ─── Ready ────────────────────────────────────────────────────────────────────

func _ready():
	DebugLogger.checkpoint_start("battle3d_ready", "Battle3D", "Battle3D._ready()")
	DebugLogger.audit("Battle3D", "Scene entered", {"mission_path": mission_path, "campaign_active": CampaignRunner.is_campaign_active})

	DebugLogger.checkpoint_start("b3d_env", "Battle3D", "3D environment setup")
	_setup_3d_environment()
	DebugLogger.checkpoint_end("b3d_env", true)

	DebugLogger.checkpoint_start("b3d_cam", "Battle3D", "Camera setup")
	_setup_camera()
	DebugLogger.checkpoint_end("b3d_cam", camera != null, "" if camera != null else "Camera is null")

	_load_portraits()

	DebugLogger.checkpoint_start("b3d_ui", "Battle3D", "UI build")
	_build_ui()
	_build_pause_menu()
	_build_combat_closeup()
	DebugLogger.checkpoint_end("b3d_ui", true)

	# Check CampaignRunner for a mission path if we don't already have one
	if mission_path == "" and CampaignRunner.is_campaign_active:
		mission_path = CampaignRunner.current_mission_path
		DebugLogger.audit("Battle3D", "Got mission path from CampaignRunner", {"path": mission_path})
	if mission_path != "":
		DebugLogger.audit("Battle3D", "Starting MISSION battle", {"path": mission_path})
		_start_mission_battle()
	else:
		DebugLogger.audit("Battle3D", "Starting DEFAULT battle (no mission path)")
		_start_battle()
	BattleState.kip_speaks.connect(_on_kip_speaks)
	BattleState.unit_died.connect(_on_unit_died)
	DebugLogger.checkpoint_end("battle3d_ready", true)

# ─── 3D Environment Setup ───────────────────────────────────────────────────

var world_environment: WorldEnvironment
var sun_light: DirectionalLight3D
var fill_light: DirectionalLight3D

func _setup_3d_environment():
	# World environment for atmosphere
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.04, 0.04, 0.06)
	env.ambient_light_color = Color(0.25, 0.22, 0.3)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.1
	env.fog_enabled = true
	env.fog_light_color = Color(0.08, 0.06, 0.12)
	env.fog_density = 0.005
	env.fog_aerial_perspective = 0.3

	world_environment = WorldEnvironment.new()
	world_environment.environment = env
	world_environment.name = "WorldEnvironment"
	add_child(world_environment)

	# Directional light — dramatic angle for shadows
	sun_light = DirectionalLight3D.new()
	sun_light.name = "SunLight"
	sun_light.rotation_degrees = Vector3(-55, -35, 0)
	sun_light.light_color = Color(1.0, 0.92, 0.8)
	sun_light.light_energy = 1.2
	sun_light.shadow_enabled = true
	sun_light.shadow_bias = 0.02
	sun_light.directional_shadow_max_distance = 50.0
	add_child(sun_light)

	# Subtle fill light from opposite side
	fill_light = DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation_degrees = Vector3(-30, 145, 0)
	fill_light.light_color = Color(0.4, 0.45, 0.7)
	fill_light.light_energy = 0.3
	fill_light.shadow_enabled = false
	add_child(fill_light)


## Apply biome-specific lighting, fog, and ambient presets.
## Call after _setup_3d_environment() with the region or biome string.
func _apply_biome_lighting(region: String) -> void:
	var env: Environment = world_environment.environment
	match region.to_lower():
		"frostmarch", "snow":
			# Cold blue fog, sharper contrast, icy feel
			env.background_color = Color(0.06, 0.08, 0.14)
			env.ambient_light_color = Color(0.3, 0.35, 0.55)
			env.ambient_light_energy = 0.5
			env.fog_light_color = Color(0.2, 0.25, 0.45)
			env.fog_density = 0.008
			env.fog_aerial_perspective = 0.5
			sun_light.light_color = Color(0.85, 0.9, 1.0)
			sun_light.light_energy = 1.4
			fill_light.light_color = Color(0.3, 0.4, 0.8)
			fill_light.light_energy = 0.4
		"thornwild", "forest":
			# Green-ish ambient, softer fog, lush
			env.background_color = Color(0.03, 0.05, 0.03)
			env.ambient_light_color = Color(0.2, 0.3, 0.15)
			env.ambient_light_energy = 0.45
			env.fog_light_color = Color(0.05, 0.1, 0.04)
			env.fog_density = 0.006
			env.fog_aerial_perspective = 0.4
			sun_light.light_color = Color(1.0, 0.95, 0.7)
			sun_light.light_energy = 1.0
			fill_light.light_color = Color(0.3, 0.5, 0.25)
			fill_light.light_energy = 0.35
		"black_ruins", "ruins":
			# Desaturated, heavier fog, slight purple/black tint
			env.background_color = Color(0.03, 0.02, 0.05)
			env.ambient_light_color = Color(0.2, 0.15, 0.25)
			env.ambient_light_energy = 0.35
			env.fog_light_color = Color(0.06, 0.04, 0.1)
			env.fog_density = 0.01
			env.fog_aerial_perspective = 0.6
			sun_light.light_color = Color(0.8, 0.7, 0.85)
			sun_light.light_energy = 1.0
			fill_light.light_color = Color(0.35, 0.25, 0.5)
			fill_light.light_energy = 0.3
		_:
			# Default — keep the base setup
			pass

func _setup_camera():
	camera = Camera3D.new()
	camera.name = "TacticsCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = cam_zoom
	camera.far = 100.0
	camera.near = 0.1
	add_child(camera)
	camera.make_current()

func _center_camera_on_grid():
	var cx = grid.grid_width * Grid3D.TILE_SCALE * 0.5
	var cz = grid.grid_height * Grid3D.TILE_SCALE * 0.5
	cam_target = Vector3(cx, 0, cz)
	# Position camera at offset from target along its viewing direction
	_update_camera_position()

func _update_camera_position():
	# Orbital camera: rotate around cam_target at fixed pitch + variable yaw
	var yaw_rad = deg_to_rad(cam_yaw)
	var pitch_rad = deg_to_rad(CAM_PITCH)
	# Spherical offset from target
	var offset = Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		-sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	) * CAM_DISTANCE
	camera.global_position = cam_target + offset
	camera.look_at(cam_target, Vector3.UP)
	camera.size = cam_zoom

# ─── Mission Battle Startup ──────────────────────────────────────────────────

func _start_mission_battle():
	DebugLogger.checkpoint_start("mission_battle", "Battle3D", "Mission battle startup")

	DebugLogger.audit("Battle3D", "Creating Grid3D")
	grid = Grid3D.new()
	grid.name = "Grid3D"
	add_child(grid)
	BattleState.grid = grid

	DebugLogger.checkpoint_start("mission_load", "MissionLoader", "Load mission bundle")
	var loader := _MissionBattleLoader.new()
	var result: Dictionary = loader.load_mission_into_battle(mission_path, grid, player_characters)
	DebugLogger.checkpoint_end("mission_load", result.get("ok", false), result.get("error", ""))

	if not result.get("ok", false):
		DebugLogger.err("Battle3D", "Mission load failed — falling back to default", {"error": result.get("error", "unknown"), "path": mission_path})
		remove_child(grid)
		grid.queue_free()
		_start_battle()
		return

	units = result["units"]
	mission_data = result["mission"]
	mission_loot = result["loot_items"]
	current_objective = result["objective"]

	DebugLogger.audit("Battle3D", "Mission loaded", {
		"id": str(mission_data.get("id", "?")),
		"grid": "%dx%d" % [grid.grid_width, grid.grid_height],
		"units": units.size(),
		"objective": current_objective,
		"tiles": grid.tiles.size(),
	})

	DebugLogger.checkpoint_start("render_units", "Battle3D", "Render units")
	grid.render_units()
	DebugLogger.checkpoint_end("render_units", true)

	_center_camera_on_grid()
	DebugLogger.audit("Battle3D", "Camera centered", {"target": str(cam_target)})

	# Apply biome lighting based on mission region
	var region: String = str(mission_data.get("region", ""))
	if region != "":
		_apply_biome_lighting(region)
		DebugLogger.audit("Battle3D", "Biome lighting applied", {"region": region})

	# Turn Manager
	DebugLogger.checkpoint_start("turn_mgr", "Battle3D", "Turn manager setup")
	turn_manager = TurnManager.new()
	turn_manager.units = units
	turn_manager.grid = grid
	turn_manager.player_phase_started.connect(_on_player_phase)
	turn_manager.kip_phase_started.connect(_on_kip_phase_start)
	turn_manager.kip_phase_ended.connect(_on_kip_phase_end)
	turn_manager.enemy_phase_started.connect(_on_enemy_phase_start)
	turn_manager.enemy_phase_ended.connect(_on_enemy_phase_end)
	turn_manager.combat_log_entry.connect(_push_log)
	add_child(turn_manager)
	turn_manager.start()
	DebugLogger.checkpoint_end("turn_mgr", true)

	DebugLogger.checkpoint_end("mission_battle", true)
	DebugLogger.info("Battle3D", "Mission '%s' loaded: %dx%d, %d units, objective=%s, region=%s" % [
		mission_data.get("id", "?"),
		grid.grid_width, grid.grid_height,
		units.size(), current_objective, region
	])


# ─── Default Battle Startup ─────────────────────────────────────────────────

func _start_battle():
	DebugLogger.checkpoint_start("default_battle", "Battle3D", "Default battle startup")
	var player_units = ["aldric", "mira", "voss", "seren", "bram", "corvin", "yael"]
	var unit_count = player_units.size()

	grid = Grid3D.new()
	grid.name = "Grid3D"
	BattleState.grid = grid

	# Use map generator for a random map
	DebugLogger.checkpoint_start("map_gen", "MapGenerator", "Generate random map")
	map_gen = MapGenerator.new()
	var template = MapGenerator.random_template()
	DebugLogger.audit("MapGenerator", "Using template", {"template": template})
	var map_data = map_gen.generate_map(randi(), 14 + unit_count, 12 + unit_count, template)
	DebugLogger.checkpoint_end("map_gen", not map_data.is_empty(), "generate_map returned empty" if map_data.is_empty() else "")

	DebugLogger.checkpoint_start("load_terrain", "Grid3D", "Load chapter terrain")
	grid.load_chapter_terrain(map_data["terrain"], map_data["width"], map_data["height"])
	DebugLogger.checkpoint_end("load_terrain", grid.tiles.size() > 0, "" if grid.tiles.size() > 0 else "No tiles created")
	DebugLogger.audit("Grid3D", "Terrain loaded", {"tiles": grid.tiles.size(), "size": "%dx%d" % [grid.grid_width, grid.grid_height]})

	# Place terrain objects from generator
	for obj in map_data["objects"]:
		grid.place_terrain_object(obj["pos"], obj["object"])
	DebugLogger.audit("Grid3D", "Objects placed", {"count": map_data["objects"].size()})

	add_child(grid)

	# ── Player units ──────────────────────────────────────────────────────────
	var p_spawns = map_data["player_spawns"]
	for i in player_units.size():
		var spawn = p_spawns[i] if i < p_spawns.size() else _open_tile(Vector2i(i % 3, i / 3))
		var u = CharacterRoster.build_player_unit(player_units[i], _open_tile(spawn))
		if u:
			_register_unit(u)

	# ── Enemies ───────────────────────────────────────────────────────────────
	var e_spawns = map_data["enemy_spawns"]
	var enemy_types = ["heavy", "grunt", "grunt", "archer", "mage", "rogue", "blood_knight", "commander"]
	for i in enemy_types.size():
		var spawn = e_spawns[i] if i < e_spawns.size() else _open_tile(Vector2i(grid.grid_width - 1 - (i % 3), grid.grid_height - 1 - (i / 3)))
		var u = CharacterRoster.build_enemy_unit(enemy_types[i], _open_tile(spawn), str(i + 1) if i < 3 else "")
		if u:
			_register_unit(u)

	grid.units_ref = units
	DebugLogger.audit("Battle3D", "Units spawned", {"player": units.filter(func(u): return u.is_player_unit).size(), "enemy": units.filter(func(u): return not u.is_player_unit).size()})

	grid.render_units()
	_center_camera_on_grid()

	# ── Turn Manager ──────────────────────────────────────────────────────────
	turn_manager = TurnManager.new()
	turn_manager.units = units
	turn_manager.grid = grid
	turn_manager.player_phase_started.connect(_on_player_phase)
	turn_manager.kip_phase_started.connect(_on_kip_phase_start)
	turn_manager.kip_phase_ended.connect(_on_kip_phase_end)
	turn_manager.enemy_phase_started.connect(_on_enemy_phase_start)
	turn_manager.enemy_phase_ended.connect(_on_enemy_phase_end)
	turn_manager.combat_log_entry.connect(_push_log)
	add_child(turn_manager)
	turn_manager.start()
	DebugLogger.checkpoint_end("default_battle", true)

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
		var a = prefer + d
		if grid.tiles.has(a) and grid.tiles[a].is_passable and grid.tiles[a].occupant == null:
			return a
	return prefer

# ─── Input ────────────────────────────────────────────────────────────────────

func _input(event: InputEvent):
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

	if is_pause_open: return
	_handle_camera_input(event)
	if BattleState.is_paused: return
	if not BattleState.is_player_phase: return
	if state == State.BATTLE_OVER: return
	if state == State.ANIMATING: return

	# Hover highlight on mouse move
	if event is InputEventMouseMotion and not cam_dragging:
		var hp = _screen_to_tile(event.position)
		if hp != null and hp is Vector2i and grid.is_valid_tile(hp):
			if hp != hovered_tile:
				_update_hover(hp)
		elif hovered_tile != Vector2i(-1, -1):
			_clear_hover()

	# H key toggles elevation + cover overlay
	if event is InputEventKey and event.pressed and event.keycode == KEY_H:
		show_elevation = not show_elevation
		grid.toggle_elevation_labels(show_elevation)
		if show_elevation:
			grid.show_cover_indicators()
		else:
			grid.clear_cover_indicators()

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not cam_dragging:
			var tp = _screen_to_tile(event.position)
			if tp != null and grid.is_valid_tile(tp):
				_handle_tile_click(tp)

func _handle_camera_input(event: InputEvent):
	# Q/E — snap rotate 45 degrees
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			_tween_camera_yaw(cam_yaw - CAM_YAW_STEP)
			return
		elif event.keycode == KEY_E:
			_tween_camera_yaw(cam_yaw + CAM_YAW_STEP)
			return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_zoom = clampf(cam_zoom - CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_zoom = clampf(cam_zoom + CAM_ZOOM_STEP, CAM_ZOOM_MIN, CAM_ZOOM_MAX)
			_update_camera_position()
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if event.shift_pressed:
					cam_rotating = true
				else:
					cam_rotating = false
				cam_dragging = true
				cam_drag_last = event.position
			else:
				cam_dragging = false
				cam_rotating = false

	if event is InputEventMouseMotion and cam_dragging:
		var delta = cam_drag_last - event.position
		if cam_rotating:
			# Shift+drag — smooth orbital rotation
			cam_yaw += delta.x * 0.3
			_update_camera_position()
		else:
			# Normal drag — pan in the ground plane
			var right = camera.global_transform.basis.x
			var forward = Vector3(camera.global_transform.basis.z.x, 0, camera.global_transform.basis.z.z).normalized()
			cam_target += right * delta.x * cam_zoom * 0.002
			cam_target += forward * delta.y * cam_zoom * 0.002
			_update_camera_position()
		cam_drag_last = event.position

func _tween_camera_yaw(target_yaw: float):
	var tw = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_method(_set_cam_yaw, cam_yaw, target_yaw, 0.25)

func _set_cam_yaw(value: float):
	cam_yaw = value
	_update_camera_position()

func _screen_to_tile(screen_pos: Vector2):
	# Raycast from camera through mouse position to ground plane
	var from = camera.project_ray_origin(screen_pos)
	var dir  = camera.project_ray_normal(screen_pos)

	# Intersect with y=0 plane (approximate — ignores height map for picking)
	if absf(dir.y) < 0.001: return null
	var t = -from.y / dir.y
	if t < 0: return null
	var hit = from + dir * t

	var tile_pos = Vector2i(int(round(hit.x / Grid3D.TILE_SCALE)), int(round(hit.z / Grid3D.TILE_SCALE)))

	# Refine: check nearby tiles and pick the one closest considering height
	var best_pos = tile_pos
	var best_dist = 999.0
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var check = tile_pos + Vector2i(dx, dz)
			if not grid.tiles.has(check): continue
			var h = grid.get_tile_height(check)
			# Re-intersect at this height
			var th = -((from.y - h) / dir.y)
			if th < 0: continue
			var tile_hit = from + dir * th
			var tile_center = Vector3(check.x * Grid3D.TILE_SCALE, h, check.y * Grid3D.TILE_SCALE)
			var d = (tile_hit - tile_center).length()
			if d < best_dist and d < Grid3D.TILE_SCALE * 0.7:
				best_dist = d
				best_pos = check
	return best_pos

# ─── Tile Click Handling (same state machine as 2D) ──────────────────────────

func _handle_tile_click(tp: Vector2i):
	match state:
		State.IDLE:
			_try_select(tp)
		State.UNIT_SELECTED:
			if tp in movement_tiles:
				_move_unit(selected_unit, tp)
				_enter_action_menu()
			elif tp == selected_unit.grid_position:
				_enter_action_menu()
			else:
				_try_select(tp)
		State.SELECT_ATTACK:
			var target = _unit_at(tp)
			if target != null and not target.is_player_unit and target.is_alive():
				forecast_attacker = selected_unit
				forecast_defender = target
				_show_forecast()
			else:
				_enter_action_menu()
		State.COMBAT_FORECAST, State.SELECT_ITEM, State.ACTION_MENU:
			pass

# ─── Selection ────────────────────────────────────────────────────────────────

func _try_select(tp: Vector2i):
	var occ = _unit_at(tp)
	if occ != null and occ.is_player_unit and occ.is_alive() and not occ.has_acted:
		_select(occ)

func _select(unit):
	selected_unit = unit
	pre_move_pos = unit.grid_position
	var el = unit.element
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
	selected_unit = null
	movement_tiles = []
	attack_targets = []
	grid.clear_highlights()
	grid.clear_path_preview()
	grid.clear_tile_info()
	grid.clear_attack_forecast_labels()
	_set_info_text("Select a unit.")
	_hide_all_panels()
	_set_end_turn_visible(true)
	state = State.IDLE

func _cancel_action():
	if state == State.UNIT_SELECTED or state == State.ACTION_MENU or state == State.SELECT_ATTACK or state == State.COMBAT_FORECAST or state == State.SELECT_ITEM:
		_deselect()

# ─── Movement ────────────────────────────────────────────────────────────────

func _move_unit(unit, target: Vector2i):
	if target == unit.grid_position: return
	grid.tiles[unit.grid_position].occupant = null
	unit.grid_position = target
	unit.has_moved = true
	grid.tiles[target].occupant = unit
	grid.clear_highlights()
	grid.clear_path_preview()
	grid.clear_tile_info()
	grid.highlight_selected(target)
	grid.update_unit_positions()
	# Apply tile entry effects
	_apply_tile_entry_effects(unit, target)

func _apply_tile_entry_effects(unit, pos: Vector2i) -> void:
	var tile = grid.tiles.get(pos)
	if tile == null:
		return
	var effects: Dictionary = tile.get_entry_effects(unit.element)
	# Damage on entry (charged, bloodsoaked)
	if effects["damage"] > 0:
		unit.take_damage(effects["damage"], "")
		grid.flash(pos, Color(1.0, 0.3, 0.0, 0.6), 0.4)
		grid.pop_damage(pos, "%d" % effects["damage"], Color(1.0, 0.5, 0.2))
		_push_log(effects["message"])
		grid.update_unit_positions()
	# Purge buffs/debuffs (VOID_SCAR)
	if effects["purge"]:
		# Reset all temporary stat modifiers
		if unit.has_method("purge_effects"):
			unit.purge_effects()
		# Also clear tile state from the tile the unit came from if any
		grid.flash(pos, Color(0.3, 0.0, 0.5, 0.7), 0.6)
		_push_log(effects["message"])

# ─── Action Menu ─────────────────────────────────────────────────────────────

func _enter_action_menu():
	if selected_unit == null: return
	grid.clear_highlights()
	grid.clear_path_preview()
	grid.clear_tile_info()
	grid.clear_attack_forecast_labels()
	grid.highlight_selected(selected_unit.grid_position)
	_refresh_info(selected_unit)
	_show_action_menu()
	state = State.ACTION_MENU

func _show_action_menu():
	_hide_all_panels()
	_set_end_turn_visible(false)
	action_box.visible = true
	for child in action_box.get_children():
		child.queue_free()
	await get_tree().process_frame

	var u = selected_unit
	var kip = u.bonded_kip if u else null

	_add_action_btn("ATTACK", Color(0.8, 0.1, 0.1), _on_action_attack, u.weapon != null)

	if kip:
		if kip.current_phase == Kip.Phase.COMPANION and not kip.is_exhausted:
			_add_action_btn("Deploy %s" % kip.kip_name, Color(0.1, 0.5, 0.9), _on_action_deploy, true)
		elif kip.current_phase == Kip.Phase.DEPLOYED:
			_add_action_btn("Recall %s" % kip.kip_name, Color(0.3, 0.3, 0.7), _on_action_recall, true)
			if not kip.awakening_used:
				_add_action_btn("AWAKEN %s" % kip.kip_name, Color(0.7, 0.5, 0.0), _on_action_awaken, true)

	_add_action_btn("Items", Color(0.2, 0.6, 0.3), _on_action_items, not u.items.is_empty())
	if u.weapons.size() > 1:
		_add_action_btn("Swap Weapon", Color(0.4, 0.4, 0.4), _on_action_swap_weapon, true)
	_add_action_btn("Wait", Color(0.35, 0.35, 0.35), _on_action_wait, true)
	_add_action_btn("Back", Color(0.25, 0.25, 0.45), _on_action_back, u.has_moved == false)

func _add_action_btn(label: String, col: Color, callback: Callable, enabled: bool):
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(290, 36)
	btn.disabled = not enabled
	btn.pressed.connect(callback)
	btn.add_theme_font_size_override("font_size", 14)
	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.6)
	style.border_color = col.darkened(0.15)
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.4)
	hover.border_color = col
	hover.set_border_width_all(1)
	hover.border_width_left = 3
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = col.darkened(0.25)
	pressed.border_color = col.lightened(0.2)
	pressed.set_border_width_all(1)
	pressed.border_width_left = 3
	pressed.set_corner_radius_all(4)
	pressed.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed)
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
	if selected_unit.weapon.is_healing:
		_show_heal_targets()
		return
	attack_targets = []
	var atk_range = selected_unit.get_attack_range()
	var valid_tiles: Array = []
	var is_ranged: bool = selected_unit.weapon.max_range > 1
	var mini_forecasts: Array = []
	for tp in atk_range:
		if not grid.is_valid_tile(tp): continue
		# LoS check for ranged attacks
		if is_ranged and not grid.has_line_of_sight(selected_unit.grid_position, tp):
			continue
		var occ = _unit_at(tp)
		if occ != null and not occ.is_player_unit and occ.is_alive():
			attack_targets.append(occ)
			valid_tiles.append(tp)
			# Compute mini forecast for this target
			var h_diff: float = _get_height_diff(selected_unit, occ)
			var hit: int = CombatResolver.get_hit(selected_unit, selected_unit.weapon, occ, h_diff)
			var dmg: int = CombatResolver.get_damage(selected_unit, selected_unit.weapon, occ, h_diff)
			mini_forecasts.append({"pos": tp, "hit": hit, "dmg": dmg})
	if attack_targets.is_empty():
		_push_log("No enemies in range.")
		_enter_action_menu()
		return
	grid.clear_highlights()
	grid.highlight_selected(selected_unit.grid_position)
	grid.highlight_attack(valid_tiles)
	# Show hit%/dmg on each target tile
	grid.show_attack_forecast_labels(mini_forecasts)
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
				b.custom_minimum_size = Vector2(290, 32)
				b.pressed.connect(func(): _heal_target(tgt))
				items_box.add_child(b)
	var back_b = Button.new()
	back_b.text = "Back"
	back_b.custom_minimum_size = Vector2(290, 32)
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
	if selected_unit.bonded_kip and healed_amt > 0:
		selected_unit.bonded_kip.record_event("allies_healed", 1)
		selected_unit.bonded_kip.record_event("total_hp_healed", healed_amt)
	_push_log(msg)
	grid.flash(target.grid_position, Color(0.3, 1.0, 0.5, 0.7), 0.6)
	selected_unit.has_acted = true
	_deselect()
	grid.update_unit_positions()
	_check_all_acted()

func _on_action_deploy():
	if selected_unit == null or selected_unit.bonded_kip == null: return
	selected_unit.bonded_kip.deploy()
	_push_log("%s deployed." % selected_unit.bonded_kip.kip_name)
	_enter_action_menu()
	grid.update_unit_positions()

func _on_action_recall():
	if selected_unit == null or selected_unit.bonded_kip == null: return
	selected_unit.bonded_kip.recall()
	_push_log("%s recalled." % selected_unit.bonded_kip.kip_name)
	_enter_action_menu()
	grid.update_unit_positions()

func _on_action_awaken():
	if selected_unit == null or selected_unit.bonded_kip == null: return
	var kip = selected_unit.bonded_kip
	if kip.awaken():
		var r = kip.get_awakening_radius()
		grid.apply_elemental_effect(selected_unit.grid_position, r, kip.element, 4)
		var tiles_affected = 0
		for x in range(selected_unit.grid_position.x - r, selected_unit.grid_position.x + r + 1):
			for z in range(selected_unit.grid_position.y - r, selected_unit.grid_position.y + r + 1):
				if abs(x - selected_unit.grid_position.x) + abs(z - selected_unit.grid_position.y) <= r:
					if grid.tiles.has(Vector2i(x, z)):
						tiles_affected += 1
		kip.record_event("tiles_changed", tiles_affected)
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
		_push_log("%s AWAKENED! Hit %d enemies." % [kip.kip_name, hit])
		kip.is_exhausted = true
		selected_unit.has_acted = true
		grid.update_unit_positions()
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
		var lbl2 = Label.new()
		lbl2.text = "(No items)"
		items_box.add_child(lbl2)
	else:
		for it in selected_unit.items:
			var item = it
			var b = Button.new()
			b.text = "%s  (%d/%d)  — %s" % [item.item_name, item.uses, item.max_uses, item.description]
			b.custom_minimum_size = Vector2(290, 34)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.disabled = item.uses <= 0
			b.pressed.connect(func(): _use_item(item))
			items_box.add_child(b)
	var back_b = Button.new()
	back_b.text = "Back"
	back_b.custom_minimum_size = Vector2(290, 32)
	back_b.pressed.connect(_enter_action_menu)
	items_box.add_child(back_b)
	state = State.SELECT_ITEM

func _use_item(item: Item):
	var msg = item.use_on(selected_unit)
	_push_log(msg)
	grid.flash(selected_unit.grid_position, Color(0.3, 1.0, 0.5, 0.7), 0.5)
	selected_unit.has_acted = true
	grid.update_unit_positions()
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
	if selected_unit.has_moved:
		grid.tiles[selected_unit.grid_position].occupant = null
		selected_unit.grid_position = pre_move_pos
		selected_unit.has_moved = false
		grid.tiles[pre_move_pos].occupant = selected_unit
		grid.update_unit_positions()
	_select(selected_unit)

# ─── Hover Highlight ─────────────────────────────────────────────────────────

func _update_hover(pos: Vector2i) -> void:
	if hovered_tile != Vector2i(-1, -1):
		grid.clear_hover()
	hovered_tile = pos
	grid.highlight_hover(pos)

	# ── Path preview when a unit is selected and tile is in range ──
	if state == State.UNIT_SELECTED and selected_unit != null:
		if pos in movement_tiles:
			var path: Array = grid.get_tile_path_to(pos)
			var cost: int = grid.get_move_cost(pos)
			if path.size() >= 2 and cost >= 0:
				grid.show_path_preview(path, cost)
			else:
				grid.clear_path_preview()
		else:
			grid.clear_path_preview()

	# ── Attack mode: show hit/dmg preview for hovered enemy ──
	if state == State.SELECT_ATTACK and selected_unit != null:
		var target = _unit_at(pos)
		if target != null and not target.is_player_unit and target.is_alive():
			var h_diff: float = _get_height_diff(selected_unit, target)
			var hit: int = CombatResolver.get_hit(selected_unit, selected_unit.weapon, target, h_diff)
			var dmg: int = CombatResolver.get_damage(selected_unit, selected_unit.weapon, target, h_diff)
			var crit: int = CombatResolver.get_crit(selected_unit, selected_unit.weapon, target)
			grid.show_tile_info(pos, "HIT:%d%%  DMG:%d  CRIT:%d%%" % [hit, dmg, crit])
		else:
			grid.clear_tile_info()
	else:
		# ── Tile info overlay for any hovered tile ──
		grid.show_tile_info(pos)

	# ── Side panel info ──
	_update_hover_info_panel(pos)

func _update_hover_info_panel(pos: Vector2i) -> void:
	if info_rtl == null:
		return
	var tile = grid.tiles.get(pos, null)
	if tile == null:
		return
	# When a unit is selected, don't overwrite the unit info panel in the side bar
	if state == State.UNIT_SELECTED or state == State.ACTION_MENU or state == State.COMBAT_FORECAST:
		return
	var h: float = grid.get_tile_height(pos)
	var elev_str: String = " Elev:%+d" % int(h / grid.HEIGHT_STEP) if abs(h) > 0.01 else ""
	var obj_str: String = ""
	if tile.terrain_object != Tile.TerrainObject.NONE:
		obj_str = "  [cover]"
	if tile.defense_bonus > 0 or tile.avoid_bonus > 0:
		obj_str += "  DEF+%d AVD+%d" % [tile.defense_bonus, tile.avoid_bonus]
	# Show occupant info if unit on tile
	if tile.occupant != null:
		var u = tile.occupant
		info_rtl.clear()
		info_rtl.push_color(Color(0.55, 0.78, 1.0) if u.is_player_unit else Color(1.0, 0.45, 0.35))
		info_rtl.append_text("%s\n" % u.unit_name)
		info_rtl.pop()
		info_rtl.append_text("HP: %d/%d\n" % [u.stats.hp, u.stats.max_hp])
		info_rtl.append_text("Class: %s%s\n" % [u.unit_class, elev_str])
		if u.weapon:
			info_rtl.push_color(Color(0.75, 0.65, 0.45))
			info_rtl.append_text("Wpn: %s  ATK %d  Rng %d-%d\n" % [
				u.weapon.weapon_name, u.weapon.attack,
				u.weapon.min_range, u.weapon.max_range])
			info_rtl.pop()
	else:
		info_rtl.clear()
		info_rtl.append_text("%s (%d,%d)%s%s\n" % [tile.get_terrain_name(), pos.x, pos.y, elev_str, obj_str])

func _clear_hover() -> void:
	grid.clear_hover()
	grid.clear_path_preview()
	grid.clear_tile_info()
	hovered_tile = Vector2i(-1, -1)

# ─── Combat Forecast ─────────────────────────────────────────────────────────

func _get_height_diff(a, b) -> float:
	return grid.get_tile_height(a.grid_position) - grid.get_tile_height(b.grid_position)

func _show_forecast():
	if forecast_attacker == null or forecast_defender == null: return
	_hide_all_panels()
	forecast_box.visible = true
	var h_diff: float = _get_height_diff(forecast_attacker, forecast_defender)
	var fc = CombatResolver.get_forecast(forecast_attacker, forecast_defender, h_diff)
	forecast_rtl.clear()
	forecast_rtl.push_color(Color(0.85, 0.14, 0.28))
	forecast_rtl.append_text("COMBAT FORECAST\n")
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(0.55, 0.78, 1.0))
	forecast_rtl.append_text(fc["atk_name"])
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(0.5, 0.5, 0.5))
	forecast_rtl.append_text("  vs  ")
	forecast_rtl.pop()
	forecast_rtl.push_color(Color(1.0, 0.45, 0.35))
	forecast_rtl.append_text(fc["def_name"] + "\n\n")
	forecast_rtl.pop()

	# Height advantage indicator
	var atk_h = grid.get_tile_height(forecast_attacker.grid_position)
	var def_h = grid.get_tile_height(forecast_defender.grid_position)
	if atk_h > def_h + 0.1:
		forecast_rtl.push_color(Color(0.3, 1.0, 0.3))
		forecast_rtl.append_text("HEIGHT ADVANTAGE\n")
		forecast_rtl.pop()
	elif def_h > atk_h + 0.1:
		forecast_rtl.push_color(Color(1.0, 0.3, 0.3))
		forecast_rtl.append_text("HEIGHT DISADVANTAGE\n")
		forecast_rtl.pop()

	forecast_rtl.push_color(Color(0.55, 0.78, 1.0))
	forecast_rtl.append_text("ATK  ")
	forecast_rtl.pop()
	forecast_rtl.append_text("DMG %d   HIT %d%%   CRIT %d%%" % [fc["atk_damage"], fc["atk_hit"], fc["atk_crit"]])
	if fc["atk_double"]:
		forecast_rtl.push_color(Color(1.0, 0.85, 0.2))
		forecast_rtl.append_text("  x2")
		forecast_rtl.pop()
	forecast_rtl.append_text("\n")

	if fc["def_can_counter"]:
		forecast_rtl.push_color(Color(1.0, 0.45, 0.35))
		forecast_rtl.append_text("DEF  ")
		forecast_rtl.pop()
		forecast_rtl.append_text("DMG %d   HIT %d%%   CRIT %d%%" % [fc["def_damage"], fc["def_hit"], fc["def_crit"]])
		if fc["def_double"]:
			forecast_rtl.push_color(Color(1.0, 0.85, 0.2))
			forecast_rtl.append_text("  x2")
			forecast_rtl.pop()
		forecast_rtl.append_text("\n")
	else:
		forecast_rtl.push_color(Color(0.45, 0.45, 0.45))
		forecast_rtl.append_text("DEF  Cannot counter.\n")
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
	grid.clear_attack_forecast_labels()
	grid.clear_tile_info()
	_show_combat_closeup(forecast_attacker, forecast_defender)
	var atk = forecast_attacker
	var def = forecast_defender
	var h_diff: float = _get_height_diff(atk, def)
	var fc = CombatResolver.get_forecast(atk, def, h_diff)

	await _animate_strike(atk, def, atk.weapon)
	if not def.is_alive():
		grid.tiles[def.grid_position].occupant = null
		grid.update_unit_positions()
		_finish_combat(atk)
		return

	if fc["def_can_counter"]:
		await get_tree().create_timer(0.15).timeout
		await _animate_strike(def, atk, def.weapon)
		if not atk.is_alive():
			grid.tiles[atk.grid_position].occupant = null
			grid.update_unit_positions()
			_finish_combat(atk)
			return

	if fc["atk_double"] and def.is_alive():
		await get_tree().create_timer(0.15).timeout
		await _animate_strike(atk, def, atk.weapon)
		if not def.is_alive():
			grid.tiles[def.grid_position].occupant = null
			grid.update_unit_positions()
			_finish_combat(atk)
			return

	if fc["def_double"] and fc["def_can_counter"] and atk.is_alive():
		await get_tree().create_timer(0.15).timeout
		await _animate_strike(def, atk, def.weapon)
		if not atk.is_alive():
			grid.tiles[atk.grid_position].occupant = null
			grid.update_unit_positions()

	_finish_combat(atk)

func _animate_strike(attacker, defender, weapon: Weapon):
	await grid.animate_attack(attacker, defender)
	var hit_roll = randi() % 100
	var hit_chance = CombatResolver.get_hit(attacker, weapon, defender)
	if hit_roll >= hit_chance:
		_push_log("%s missed %s." % [attacker.unit_name, defender.unit_name])
		grid.pop_damage(defender.grid_position, "MISS", Color(0.6, 0.6, 0.7))
		return
	var damage = CombatResolver.get_damage(attacker, weapon, defender)
	var crit_roll = randi() % 100
	var is_crit = crit_roll < CombatResolver.get_crit(attacker, weapon, defender)
	if is_crit:
		damage = int(damage * 3)
		_push_log("CRITICAL! %s %d dmg" % [attacker.unit_name, damage])
		grid.flash(defender.grid_position, Color(1.0, 0.2, 0.0, 0.9), 0.5)
		grid.pop_damage(defender.grid_position, "%d!" % damage, Color(1.0, 0.3, 0.0), 1.2)
	else:
		_push_log("%s %d dmg" % [attacker.unit_name, damage])
		grid.flash(defender.grid_position, Color(0.9, 0.1, 0.1, 0.8), 0.4)
		grid.pop_damage(defender.grid_position, "%d" % damage, Color(1.0, 1.0, 1.0))
	var elem = weapon.element if weapon.element != "" else attacker.element
	defender.take_damage(damage, elem)
	weapon.use_one()
	if forecast_attacker and forecast_defender:
		_update_combat_hp(forecast_attacker, forecast_defender)
	if defender.is_alive():
		await grid.animate_hit_recoil(defender)
	else:
		_push_log("%s fell." % defender.unit_name)
	grid.update_unit_positions()

func _finish_combat(attacker):
	_hide_combat_closeup()
	attacker.has_acted = true
	_record_kip_combat_events(attacker, forecast_defender)
	_deselect()
	_check_all_acted()
	_check_battle_outcome()

# ─── Kip Memory Recording ───────────────────────────────────────────────────

func _record_kip_combat_events(attacker, defender):
	if defender != null and not defender.is_alive() and not defender.is_player_unit:
		for u in units:
			if u.is_player_unit and u.is_alive() and u.bonded_kip:
				var dist = (u.grid_position - defender.grid_position).length()
				if dist <= 5.0:
					u.bonded_kip.record_event("kills_witnessed", 1)
	if attacker.is_player_unit and attacker.bonded_kip:
		attacker.bonded_kip.record_event("battles_witnessed", 1)
		if defender and not defender.is_alive():
			attacker.bonded_kip.record_event("damage_dealt", defender.stats.max_hp)
	if defender != null and defender.is_player_unit and defender.is_alive():
		var hpr = float(defender.stats.hp) / float(defender.stats.max_hp)
		if hpr < 0.25:
			for u in units:
				if u.is_player_unit and u.is_alive() and u != defender and u.bonded_kip:
					var dist = (u.grid_position - defender.grid_position).length()
					if dist <= 3.0:
						u.bonded_kip.record_event("allies_saved", 1)

func _record_kip_tile_events():
	for u in units:
		if not u.is_player_unit or not u.is_alive() or u.bonded_kip == null: continue
		var tile = grid.tiles.get(u.grid_position)
		if tile == null: continue
		var kip = u.bonded_kip
		match tile.elemental_state:
			Tile.ElementalState.CHARGED:    kip.record_event("charged_tiles_stood", 1)
			Tile.ElementalState.BLOODSOAKED: kip.record_event("blood_tiles_stood", 1)
			Tile.ElementalState.FROZEN:     kip.record_event("frozen_tiles_stood", 1)

func _check_kip_evolutions():
	for u in units:
		if not u.is_player_unit or not u.is_alive() or u.bonded_kip == null: continue
		if u.bonded_kip.check_evolution():
			_push_log("%s evolved into %s!" % [u.bonded_kip.kip_name, u.bonded_kip.evolution_name])
			BattleState.kip_evolved.emit(u.bonded_kip.kip_name, u.bonded_kip.evolution_name)
			grid.flash(u.grid_position, Color(1.0, 0.9, 0.3, 0.9), 1.5)

func _apply_kip_mutations():
	for u in units:
		if not u.is_player_unit or not u.is_alive() or u.bonded_kip == null: continue
		u.bonded_kip.apply_mutations(u)

# ─── Turn / Phase Signals ────────────────────────────────────────────────────

func _on_player_phase(turn: int):
	phase_label.text = "Player Phase  —  Turn %d" % (turn + 1)
	turn_label.text = "Turn %d" % (turn + 1)
	end_turn_btn.disabled = false
	_record_kip_tile_events()
	_check_kip_evolutions()
	_apply_kip_mutations()
	grid.update_unit_positions()
	_check_battle_outcome()

func _on_kip_phase_start():
	phase_label.text = "— Kip Phase —"
	_deselect()
	end_turn_btn.disabled = true

func _on_kip_phase_end():
	grid.update_unit_positions()

func _on_enemy_phase_start():
	phase_label.text = "— Enemy Phase —"
	end_turn_btn.disabled = true

func _on_enemy_phase_end():
	grid.update_unit_positions()
	_check_battle_outcome()

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
	grid.update_unit_positions()
	# Check if the battle just ended
	_check_battle_outcome()

# ─── Battle Outcome ─────────────────────────────────────────────────────────

func _check_all_acted():
	if not BattleState.is_player_phase: return
	var all_done = true
	for u in units:
		if u.is_player_unit and u.is_alive() and not u.has_acted:
			all_done = false
			break
	if all_done:
		_deselect()
		end_turn_btn.disabled = true
		turn_manager.end_player_phase()

func _check_battle_outcome():
	if state == State.BATTLE_OVER:
		return  # Already resolved
	var players_alive = false
	var enemies_alive = false
	for u in units:
		if u.is_alive():
			if u.is_player_unit:
				players_alive = true
			else:
				enemies_alive = true
	if not players_alive:
		state = State.BATTLE_OVER
		phase_label.text = "DEFEAT"
		_set_info_text("Your forces have fallen.")
		_on_battle_end(false)
	elif not enemies_alive:
		state = State.BATTLE_OVER
		phase_label.text = "VICTORY"
		_set_info_text("All enemies eliminated!")
		_on_battle_end(true)


func _on_battle_end(victory: bool) -> void:
	if not CampaignRunner.is_campaign_active:
		return
	# Delay slightly so the player sees the result text
	await get_tree().create_timer(3.0).timeout
	CampaignRunner.complete_mission(victory)

# ─── Helpers ─────────────────────────────────────────────────────────────────

func _unit_at(tp: Vector2i):
	if not grid.tiles.has(tp): return null
	return grid.tiles[tp].occupant

func _elem_ui_color(elem: String) -> Color:
	match elem:
		"blood":    return Color(0.9, 0.2, 0.2)
		"electric": return Color(1.0, 0.9, 0.1)
		"void":     return Color(0.6, 0.2, 0.9)
		"light":    return Color(1.0, 0.95, 0.5)
		"dark":     return Color(0.4, 0.2, 0.6)
		"ice":      return Color(0.5, 0.8, 1.0)
		"plant":    return Color(0.3, 0.9, 0.3)
		"god":      return Color(1.0, 1.0, 0.8)
	return Color.WHITE

# ─── Kip Speech ──────────────────────────────────────────────────────────────

func _on_kip_speaks(kip_name: String, msg: String):
	kip_label.text = "%s: \"%s\"" % [kip_name, msg]
	speech_timer = 3.5

func _process(delta: float):
	if speech_timer > 0:
		speech_timer -= delta
		if speech_timer <= 0:
			kip_label.text = ""
	if log_timer > 0:
		log_timer -= delta
		if log_timer <= 0:
			if log_queue.size() > 0:
				log_label.text = log_queue.pop_front()
				log_timer = 2.5
			else:
				log_label.text = ""

func _push_log(text: String):
	if log_timer > 0:
		log_queue.append(text)
	else:
		log_label.text = text
		log_timer = 2.5

# ─── UI Building ────────────────────────────────────────────────────────────

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

func _build_ui():
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	# Right-side panel
	ui_panel = Control.new()
	ui_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(ui_panel)

	var panel_bg = ColorRect.new()
	panel_bg.color = Color(0.06, 0.06, 0.08, 0.92)
	panel_bg.position = Vector2(PANEL_X, 0)
	panel_bg.size = Vector2(1280 - PANEL_X, 720)
	ui_panel.add_child(panel_bg)

	var px = PANEL_X + 12
	var py = 10

	# Phase label
	phase_label = Label.new()
	phase_label.text = "Player Phase  —  Turn 1"
	phase_label.position = Vector2(px, py)
	phase_label.add_theme_font_size_override("font_size", 16)
	phase_label.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	ui_panel.add_child(phase_label)
	py += 28

	# Turn label
	turn_label = Label.new()
	turn_label.text = "Turn 1"
	turn_label.position = Vector2(px, py)
	turn_label.add_theme_font_size_override("font_size", 12)
	turn_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	ui_panel.add_child(turn_label)
	py += 22

	# Separator
	var sep = ColorRect.new()
	sep.color = Color(0.25, 0.25, 0.3)
	sep.position = Vector2(px, py)
	sep.size = Vector2(290, 1)
	ui_panel.add_child(sep)
	py += 8

	# Portrait row
	portrait_tex = TextureRect.new()
	portrait_tex.position = Vector2(px, py)
	portrait_tex.custom_minimum_size = Vector2(48, 48)
	portrait_tex.size = Vector2(48, 48)
	portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ui_panel.add_child(portrait_tex)

	kip_portrait_tex = TextureRect.new()
	kip_portrait_tex.position = Vector2(px + 56, py + 4)
	kip_portrait_tex.custom_minimum_size = Vector2(36, 36)
	kip_portrait_tex.size = Vector2(36, 36)
	kip_portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	kip_portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	ui_panel.add_child(kip_portrait_tex)
	py += 68

	# HP bar
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0.08, 0.08, 0.1)
	hp_bar_bg.position = Vector2(px, py)
	hp_bar_bg.size = Vector2(200, 14)
	ui_panel.add_child(hp_bar_bg)

	hp_bar_fill = ColorRect.new()
	hp_bar_fill.color = Color(0.15, 0.88, 0.15)
	hp_bar_fill.position = Vector2(px + 1, py + 1)
	hp_bar_fill.size = Vector2(198, 12)
	ui_panel.add_child(hp_bar_fill)

	hp_bar_label = Label.new()
	hp_bar_label.text = ""
	hp_bar_label.position = Vector2(px + 210, py - 2)
	hp_bar_label.add_theme_font_size_override("font_size", 12)
	ui_panel.add_child(hp_bar_label)
	py += 22

	# Info
	info_rtl = RichTextLabel.new()
	info_rtl.position = Vector2(px, py)
	info_rtl.size = Vector2(290, 120)
	info_rtl.bbcode_enabled = true
	info_rtl.scroll_active = false
	info_rtl.add_theme_font_size_override("normal_font_size", 13)
	ui_panel.add_child(info_rtl)
	py += 145

	# Action box
	action_box = VBoxContainer.new()
	action_box.position = Vector2(px, py)
	action_box.visible = false
	ui_panel.add_child(action_box)

	# Forecast box
	forecast_box = VBoxContainer.new()
	forecast_box.position = Vector2(px, py)
	forecast_box.visible = false
	ui_panel.add_child(forecast_box)

	forecast_rtl = RichTextLabel.new()
	forecast_rtl.size = Vector2(290, 160)
	forecast_rtl.bbcode_enabled = true
	forecast_rtl.scroll_active = false
	forecast_rtl.add_theme_font_size_override("normal_font_size", 13)
	forecast_box.add_child(forecast_rtl)

	# Items box
	items_box = VBoxContainer.new()
	items_box.position = Vector2(px, py)
	items_box.visible = false
	ui_panel.add_child(items_box)

	# Kip speech
	kip_label = Label.new()
	kip_label.text = ""
	kip_label.position = Vector2(px, 620)
	kip_label.add_theme_font_size_override("font_size", 12)
	kip_label.add_theme_color_override("font_color", Color(0.6, 0.75, 1.0))
	ui_panel.add_child(kip_label)

	# Log label
	log_label = Label.new()
	log_label.text = ""
	log_label.position = Vector2(px, 645)
	log_label.add_theme_font_size_override("font_size", 11)
	log_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	ui_panel.add_child(log_label)

	# End turn button
	end_turn_btn = _make_styled_btn("END TURN", Color(0.65, 0.50, 0.15), 44)
	end_turn_btn.position = Vector2(px, 670)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	ui_panel.add_child(end_turn_btn)

	_set_info_text("Select a unit.")

func _make_styled_btn(text: String, col: Color, h: int = 40) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(440, h)
	btn.add_theme_font_size_override("font_size", 14)
	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.5)
	style.border_color = col
	style.set_border_width_all(1)
	style.border_width_left = 3
	style.set_corner_radius_all(4)
	style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", style)
	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.3)
	hover.border_color = col.lightened(0.2)
	hover.set_border_width_all(1)
	hover.border_width_left = 3
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover)
	return btn

func _refresh_info(unit):
	if unit == null: return
	var name_key = unit.unit_name.to_lower()
	portrait_tex.texture = portrait_cache.get(name_key, null)
	if unit.bonded_kip:
		kip_portrait_tex.texture = kip_portrait_cache.get(unit.bonded_kip.kip_name.to_lower(), null)
	else:
		kip_portrait_tex.texture = null

	# HP bar
	var hpr = float(unit.stats.hp) / float(unit.stats.max_hp)
	hp_bar_fill.size.x = 198.0 * hpr
	hp_bar_fill.color = Color(0.15, 0.88, 0.15) if hpr > 0.5 else (Color(0.92, 0.58, 0.1) if hpr > 0.25 else Color(0.92, 0.12, 0.12))
	hp_bar_label.text = "%d/%d" % [unit.stats.hp, unit.stats.max_hp]

	# Height info
	var tile_h = grid.get_tile_height(unit.grid_position)
	var height_text = " [Elev: %0.1f]" % tile_h if tile_h > 0.1 else ""

	info_rtl.clear()
	info_rtl.push_color(Color(0.9, 0.9, 0.95))
	info_rtl.append_text("%s  [%s]%s\n" % [unit.unit_name, unit.unit_class, height_text])
	info_rtl.pop()
	info_rtl.push_color(Color(0.6, 0.6, 0.65))
	info_rtl.append_text("HP %d/%d   STR %d  MAG %d  SPD %d  DEF %d  RES %d  MOV %d\n" % [
		unit.stats.hp, unit.stats.max_hp,
		unit.stats.strength, unit.stats.magic,
		unit.stats.speed, unit.stats.defense, unit.stats.resistance,
		unit.stats.movement
	])
	info_rtl.pop()
	if unit.weapon:
		info_rtl.push_color(Color(0.75, 0.65, 0.45))
		info_rtl.append_text("Wpn: %s  ATK %d  HIT %d  CRIT %d  Rng %d-%d" % [
			unit.weapon.weapon_name, unit.weapon.attack,
			unit.weapon.hit, unit.weapon.crit,
			unit.weapon.min_range, unit.weapon.max_range
		])
		if unit.weapon.element != "":
			info_rtl.append_text("  [%s]" % unit.weapon.element.capitalize())
		info_rtl.append_text("\n")
		info_rtl.pop()
	# Terrain info
	var tile = grid.tiles.get(unit.grid_position)
	if tile:
		info_rtl.push_color(Color(0.45, 0.55, 0.45))
		info_rtl.append_text("Terrain: %s" % tile.get_terrain_name())
		if tile.defense_bonus > 0: info_rtl.append_text("  DEF+%d" % tile.defense_bonus)
		if tile.avoid_bonus > 0:   info_rtl.append_text("  AVO+%d" % tile.avoid_bonus)
		if tile.heal_bonus > 0:    info_rtl.append_text("  HEAL+%d" % tile.heal_bonus)
		info_rtl.append_text("\n")
		info_rtl.pop()
	if unit.bonded_kip:
		var kip = unit.bonded_kip
		info_rtl.push_color(_elem_ui_color(kip.element))
		info_rtl.append_text("Kip: %s [%s] — %s\n" % [kip.kip_name, kip.element.capitalize(), kip.get_phase_label()])
		info_rtl.pop()

func _set_info_text(text: String):
	info_rtl.clear()
	info_rtl.push_color(Color(0.5, 0.5, 0.55))
	info_rtl.append_text(text)
	info_rtl.pop()
	portrait_tex.texture = null
	kip_portrait_tex.texture = null
	hp_bar_fill.size.x = 0
	hp_bar_label.text = ""

func _hide_all_panels():
	action_box.visible = false
	forecast_box.visible = false
	items_box.visible = false

func _set_end_turn_visible(v: bool):
	end_turn_btn.visible = v

# ─── Pause Menu ──────────────────────────────────────────────────────────────

func _build_pause_menu():
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.6)
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	ui_layer.add_child(pause_overlay)

	pause_menu = VBoxContainer.new()
	pause_menu.position = Vector2(440, 250)
	pause_overlay.add_child(pause_menu)

	var title = Label.new()
	title.text = "PAUSED"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	pause_menu.add_child(title)

	var resume_btn = _make_styled_btn("Resume", Color(0.2, 0.6, 0.3), 44)
	resume_btn.pressed.connect(_close_pause_menu)
	pause_menu.add_child(resume_btn)

	var quit_btn = _make_styled_btn("Return to Title", Color(0.5, 0.2, 0.2), 44)
	quit_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn"))
	pause_menu.add_child(quit_btn)

func _open_pause_menu():
	pause_overlay.visible = true
	is_pause_open = true
	BattleState.is_paused = true

func _close_pause_menu():
	pause_overlay.visible = false
	is_pause_open = false
	BattleState.is_paused = false

# ─── Combat Close-up ────────────────────────────────────────────────────────

func _build_combat_closeup():
	combat_layer = CanvasLayer.new()
	combat_layer.layer = 15
	add_child(combat_layer)

	combat_panel = ColorRect.new()
	combat_panel.color = Color(0.03, 0.03, 0.05, 0.9)
	combat_panel.position = Vector2(140, 15)
	combat_panel.size = Vector2(520, 80)
	combat_panel.visible = false
	combat_layer.add_child(combat_panel)

	combat_atk_portrait = TextureRect.new()
	combat_atk_portrait.position = Vector2(10, 8)
	combat_atk_portrait.size = Vector2(60, 60)
	combat_atk_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	combat_panel.add_child(combat_atk_portrait)

	combat_atk_name = Label.new()
	combat_atk_name.position = Vector2(75, 10)
	combat_atk_name.add_theme_font_size_override("font_size", 14)
	combat_atk_name.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	combat_panel.add_child(combat_atk_name)

	combat_atk_hp = ColorRect.new()
	combat_atk_hp.position = Vector2(75, 35)
	combat_atk_hp.size = Vector2(150, 10)
	combat_atk_hp.color = Color(0.15, 0.88, 0.15)
	combat_panel.add_child(combat_atk_hp)

	combat_vs = Label.new()
	combat_vs.text = "VS"
	combat_vs.position = Vector2(240, 25)
	combat_vs.add_theme_font_size_override("font_size", 18)
	combat_vs.add_theme_color_override("font_color", Color(0.8, 0.2, 0.2))
	combat_panel.add_child(combat_vs)

	combat_def_portrait = TextureRect.new()
	combat_def_portrait.position = Vector2(450, 8)
	combat_def_portrait.size = Vector2(60, 60)
	combat_def_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	combat_panel.add_child(combat_def_portrait)

	combat_def_name = Label.new()
	combat_def_name.position = Vector2(300, 10)
	combat_def_name.add_theme_font_size_override("font_size", 14)
	combat_def_name.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
	combat_panel.add_child(combat_def_name)

	combat_def_hp = ColorRect.new()
	combat_def_hp.position = Vector2(300, 35)
	combat_def_hp.size = Vector2(150, 10)
	combat_def_hp.color = Color(0.15, 0.88, 0.15)
	combat_panel.add_child(combat_def_hp)

func _show_combat_closeup(atk, def):
	combat_panel.visible = true
	combat_atk_name.text = atk.unit_name
	combat_def_name.text = def.unit_name
	combat_atk_portrait.texture = portrait_cache.get(atk.unit_name.to_lower(), null)
	combat_def_portrait.texture = portrait_cache.get(def.unit_name.to_lower(), null)
	_update_combat_hp(atk, def)

func _update_combat_hp(atk, def):
	var atk_hpr = clampf(float(atk.stats.hp) / float(atk.stats.max_hp), 0.0, 1.0)
	var def_hpr = clampf(float(def.stats.hp) / float(def.stats.max_hp), 0.0, 1.0)
	combat_atk_hp.size.x = 150.0 * atk_hpr
	combat_def_hp.size.x = 150.0 * def_hpr
	combat_atk_hp.color = Color(0.15, 0.88, 0.15) if atk_hpr > 0.5 else (Color(0.92, 0.58, 0.1) if atk_hpr > 0.25 else Color(0.92, 0.12, 0.12))
	combat_def_hp.color = Color(0.15, 0.88, 0.15) if def_hpr > 0.5 else (Color(0.92, 0.58, 0.1) if def_hpr > 0.25 else Color(0.92, 0.12, 0.12))

func _hide_combat_closeup():
	combat_panel.visible = false
