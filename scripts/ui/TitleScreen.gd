extends Control

var bg_time: float = 0.0
var particles: Array = []  # [{pos, vel, color, size, life}]

func _ready():
	# Spawn ambient particles
	for i in 40:
		_spawn_particle()
	_build_ui()

func _spawn_particle():
	particles.append({
		"pos": Vector2(randf() * 1280, randf() * 720),
		"vel": Vector2(randf_range(-8, 8), randf_range(-15, -5)),
		"color": [Color(0.85, 0.14, 0.28, 0.3), Color(0.55, 0.78, 1.0, 0.2),
				  Color(0.95, 0.85, 0.2, 0.25), Color(0.55, 0.15, 0.78, 0.2)].pick_random(),
		"size": randf_range(1.5, 4.0),
		"life": randf_range(3.0, 8.0),
		"max_life": 8.0
	})

func _process(delta: float):
	bg_time += delta
	var i = particles.size() - 1
	while i >= 0:
		particles[i].pos += particles[i].vel * delta
		particles[i].life -= delta
		if particles[i].life <= 0.0:
			particles.remove_at(i)
			_spawn_particle()
		i -= 1
	queue_redraw()

func _draw():
	# Dark background
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.02, 0.02, 0.04))

	# Subtle radial vignette effect (concentric rects getting darker)
	for ring in range(8, 0, -1):
		var alpha = 0.03 * ring
		var inset = 40.0 * (8 - ring)
		draw_rect(Rect2(0, 0, inset, 720), Color(0, 0, 0, alpha))
		draw_rect(Rect2(1280 - inset, 0, inset, 720), Color(0, 0, 0, alpha))

	# Particles
	for p in particles:
		var alpha = clampf(p.life / p.max_life * 2.0, 0.0, 1.0) * p.color.a
		var col = p.color
		col.a = alpha
		draw_circle(p.pos, p.size, col)

	# Horizontal accent lines
	var line_y = 280.0 + sin(bg_time * 0.3) * 5.0
	draw_rect(Rect2(200, line_y, 880, 1), Color(0.85, 0.14, 0.28, 0.15))
	draw_rect(Rect2(200, line_y + 200, 880, 1), Color(0.85, 0.14, 0.28, 0.15))

func _build_ui():
	# Center container
	var center = VBoxContainer.new()
	center.custom_minimum_size = Vector2(300, 400)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center)
	# Position after adding so we know the viewport size
	center.position = Vector2((1280 - 300) / 2.0, 160)

	# Title
	var title = Label.new()
	title.text = "D  E  N"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	# Subtitle
	var sub = Label.new()
	sub.text = "Magic. Robots. War."
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(sub)

	center.add_child(_spacer(40))

	# Menu buttons
	_add_menu_btn(center, "NEW GAME", Color(0.85, 0.14, 0.28), _on_new_game)
	_add_menu_btn(center, "START CAMPAIGN", Color(0.55, 0.15, 0.78), _on_start_campaign)
	_add_menu_btn(center, "SKIRMISH (2.5D)", Color(0.35, 0.35, 0.50), _on_new_game_3d)

	var has_save = FileAccess.file_exists("user://den_save.json")
	_add_menu_btn(center, "CONTINUE", Color(0.3, 0.5, 0.8), _on_continue, has_save)

	_add_menu_btn(center, "SETTINGS", Color(0.35, 0.35, 0.38), _on_settings)
	_add_menu_btn(center, "QUIT", Color(0.25, 0.25, 0.28), _on_quit)

	center.add_child(_spacer(60))

	# Version
	var ver = Label.new()
	ver.text = "v0.3 prototype"
	ver.add_theme_font_size_override("font_size", 11)
	ver.add_theme_color_override("font_color", Color(0.25, 0.25, 0.28))
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(ver)

func _add_menu_btn(parent: Control, label: String, col: Color, callback: Callable, enabled: bool = true):
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(300, 48)
	btn.disabled = not enabled
	btn.pressed.connect(callback)
	btn.add_theme_font_size_override("font_size", 16)

	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.7)
	style.border_color = col.darkened(0.3)
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_corner_radius_all(4)
	style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style)

	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.5)
	hover.border_color = col
	hover.set_border_width_all(1)
	hover.border_width_left = 4
	hover.set_corner_radius_all(4)
	hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover)

	var pressed = StyleBoxFlat.new()
	pressed.bg_color = col.darkened(0.3)
	pressed.border_color = col.lightened(0.2)
	pressed.set_border_width_all(1)
	pressed.border_width_left = 4
	pressed.set_corner_radius_all(4)
	pressed.set_content_margin_all(10)
	btn.add_theme_stylebox_override("pressed", pressed)

	var dis = StyleBoxFlat.new()
	dis.bg_color = Color(0.08, 0.08, 0.10)
	dis.border_color = Color(0.15, 0.15, 0.18)
	dis.set_border_width_all(1)
	dis.border_width_left = 4
	dis.set_corner_radius_all(4)
	dis.set_content_margin_all(10)
	btn.add_theme_stylebox_override("disabled", dis)
	btn.add_theme_color_override("font_disabled_color", Color(0.25, 0.25, 0.28))

	parent.add_child(btn)

func _spacer(h: int) -> Control:
	var s = Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

# ─── Callbacks ────────────────────────────────────────────────────────────────

func _on_new_game():
	GameState.chapter = 1
	GameState.army.clear()
	GameState.gold = 0
	GameState.kips_encountered.clear()
	get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")

func _on_start_campaign():
	GameState.chapter = 1
	GameState.army.clear()
	GameState.gold = 0
	GameState.kips_encountered.clear()
	# Find most recent campaign file
	var campaign_path: String = _find_latest_campaign()
	if campaign_path == "":
		push_warning("No campaign found — falling back to skirmish.")
		_on_new_game_3d()
		return
	if CampaignRunner.start_campaign(campaign_path):
		CampaignRunner.load_current_mission()
	else:
		push_warning("Campaign load failed — falling back to skirmish.")
		_on_new_game_3d()

func _find_latest_campaign() -> String:
	# Prefer seed 42 (dev default), then scan for any campaign
	if FileAccess.file_exists("res://output/campaigns/campaign_0042.json"):
		return "res://output/campaigns/campaign_0042.json"
	var dir := DirAccess.open("res://output/campaigns")
	if dir == null:
		return ""
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			return "res://output/campaigns/%s" % fname
		fname = dir.get_next()
	return ""

func _on_new_game_3d():
	GameState.chapter = 1
	GameState.army.clear()
	GameState.gold = 0
	GameState.kips_encountered.clear()
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene3D.tscn")

func _on_continue():
	if GameState.load_game():
		get_tree().change_scene_to_file("res://scenes/battle/Battle.tscn")

func _on_settings():
	pass  # TODO: settings screen

func _on_quit():
	get_tree().quit()
