extends Control

## Mission Briefing screen — reads CampaignRunner state and displays
## mission info before transitioning to battle.
## Shows: region, biome, objective, enemy faction, intel, rewards.

var bg_time: float = 0.0
var particles: Array = []
var ready_to_launch: bool = false

func _ready():
	DebugLogger.checkpoint_start("mission_brief", "MissionBrief", "MissionBrief._ready()")
	DebugLogger.audit("MissionBrief", "Scene entered", {
		"campaign_active": CampaignRunner.is_campaign_active,
		"mission_path": CampaignRunner.current_mission_path,
		"mission_index": CampaignRunner.mission_index,
	})
	for i in 25:
		_spawn_particle()
	_build_ui()
	DebugLogger.checkpoint_end("mission_brief", true)

func _spawn_particle():
	particles.append({
		"pos": Vector2(randf() * 1280, randf() * 720),
		"vel": Vector2(randf_range(-5, 5), randf_range(-10, -3)),
		"color": [Color(0.55, 0.15, 0.78, 0.15), Color(0.85, 0.14, 0.28, 0.15),
				  Color(0.55, 0.78, 1.0, 0.12), Color(0.95, 0.85, 0.2, 0.12)].pick_random(),
		"size": randf_range(1.0, 3.0),
		"life": randf_range(4.0, 10.0),
		"max_life": 10.0
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
	# Subtle gradient overlay
	for ring in range(6, 0, -1):
		var alpha = 0.02 * ring
		var inset = 50.0 * (6 - ring)
		draw_rect(Rect2(0, 0, inset, 720), Color(0, 0, 0, alpha))
		draw_rect(Rect2(1280 - inset, 0, inset, 720), Color(0, 0, 0, alpha))
	# Particles
	for p in particles:
		var alpha = clampf(p.life / p.max_life * 2.0, 0.0, 1.0) * p.color.a
		var col = p.color
		col.a = alpha
		draw_circle(p.pos, p.size, col)
	# Accent line
	var line_y = 130.0 + sin(bg_time * 0.4) * 3.0
	draw_rect(Rect2(100, line_y, 1080, 1), Color(0.55, 0.15, 0.78, 0.12))

func _build_ui():
	# Gather data from CampaignRunner
	var info: Dictionary = CampaignRunner.get_mission_info()
	var mission_entry: Dictionary = {}
	if CampaignRunner.missions.size() > info.get("index", 0):
		mission_entry = CampaignRunner.missions[info.get("index", 0)]
	var campaign: Dictionary = CampaignRunner.campaign

	var region: String = str(info.get("region", "Unknown")).replace("_", " ").capitalize()
	var objective_data = info.get("objective", {"type": "rout"})
	var obj_type: String = str(objective_data.get("type", "rout")).capitalize()
	var chapter: int = info.get("chapter", 1)
	var act: int = info.get("act", 1)
	var mission_idx: int = info.get("index", 0)
	var total: int = info.get("total", 1)

	var faction_atk: String = str(mission_entry.get("faction_attacker", "unknown")).replace("_", " ").capitalize()
	var faction_def: String = str(mission_entry.get("faction_defender", "unknown")).replace("_", " ").capitalize()
	var template: String = str(mission_entry.get("template", "")).replace("_", " ").capitalize()

	var major_arc: String = str(campaign.get("major_arc", "")).replace("_", " ").capitalize()
	var minor_arc: String = str(campaign.get("minor_arc", "")).replace("_", " ").capitalize()

	var rewards: Dictionary = mission_entry.get("rewards", {})
	var gold: int = int(rewards.get("gold", 0))
	var xp: int = int(rewards.get("xp", 0))
	var enemy_roster: Array = mission_entry.get("enemy_roster", [])

	# ─── Layout ─────────────────────────────────────────────────────────────
	var center = VBoxContainer.new()
	center.custom_minimum_size = Vector2(700, 500)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center)
	center.position = Vector2((1280 - 700) / 2.0, 60)

	# Mission number header
	var header = Label.new()
	header.text = "ACT %d  —  CHAPTER %d" % [act, chapter]
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.55, 0.15, 0.78, 0.8))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(header)

	# Region title
	var title = Label.new()
	title.text = region
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(title)

	# Template / map style
	if template != "":
		var tmpl_lbl = Label.new()
		tmpl_lbl.text = "\"%s\"" % template
		tmpl_lbl.add_theme_font_size_override("font_size", 13)
		tmpl_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))
		tmpl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(tmpl_lbl)

	center.add_child(_spacer(20))

	# Objective
	var obj_row = HBoxContainer.new()
	obj_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(obj_row)
	var obj_icon = Label.new()
	obj_icon.text = _objective_icon(obj_type)
	obj_icon.add_theme_font_size_override("font_size", 20)
	obj_row.add_child(obj_icon)
	var obj_label = Label.new()
	obj_label.text = "  Objective: %s" % obj_type
	obj_label.add_theme_font_size_override("font_size", 18)
	obj_label.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	obj_row.add_child(obj_label)

	center.add_child(_spacer(12))

	# Faction info
	var faction_lbl = Label.new()
	faction_lbl.text = "%s  vs  %s" % [faction_def, faction_atk]
	faction_lbl.add_theme_font_size_override("font_size", 16)
	faction_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	faction_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(faction_lbl)

	# Enemy count
	var enemy_lbl = Label.new()
	enemy_lbl.text = "Enemy force: %d units" % enemy_roster.size()
	enemy_lbl.add_theme_font_size_override("font_size", 13)
	enemy_lbl.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35, 0.7))
	enemy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(enemy_lbl)

	center.add_child(_spacer(16))

	# Intel line
	if major_arc != "" or minor_arc != "":
		var sep1 = ColorRect.new()
		sep1.color = Color(0.25, 0.25, 0.3, 0.5)
		sep1.custom_minimum_size = Vector2(500, 1)
		center.add_child(sep1)
		center.add_child(_spacer(8))
		var intel = Label.new()
		var intel_text: String = "Intel: "
		if major_arc != "":
			intel_text += major_arc
		if minor_arc != "":
			intel_text += " — %s" % minor_arc
		intel.text = intel_text
		intel.add_theme_font_size_override("font_size", 13)
		intel.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0, 0.7))
		intel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(intel)
		center.add_child(_spacer(8))

	center.add_child(_spacer(8))

	# Rewards
	var sep2 = ColorRect.new()
	sep2.color = Color(0.25, 0.25, 0.3, 0.5)
	sep2.custom_minimum_size = Vector2(500, 1)
	center.add_child(sep2)
	center.add_child(_spacer(8))

	var reward_row = HBoxContainer.new()
	reward_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(reward_row)

	if gold > 0:
		var gold_lbl = Label.new()
		gold_lbl.text = "  %d Gold  " % gold
		gold_lbl.add_theme_font_size_override("font_size", 14)
		gold_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.2))
		reward_row.add_child(gold_lbl)

	if xp > 0:
		var xp_lbl = Label.new()
		xp_lbl.text = "  %d XP  " % xp
		xp_lbl.add_theme_font_size_override("font_size", 14)
		xp_lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		reward_row.add_child(xp_lbl)

	var loot_rolls: Array = rewards.get("loot_rolls", [])
	if not loot_rolls.is_empty():
		var loot_lbl = Label.new()
		var total_loot: int = 0
		for roll in loot_rolls:
			total_loot += int(roll.get("count", 0))
		loot_lbl.text = "  %d Loot Drops  " % total_loot
		loot_lbl.add_theme_font_size_override("font_size", 14)
		loot_lbl.add_theme_color_override("font_color", Color(0.7, 0.5, 1.0))
		reward_row.add_child(loot_lbl)

	center.add_child(_spacer(12))

	# Mission progress
	var progress_lbl = Label.new()
	progress_lbl.text = "Mission %d of %d" % [mission_idx + 1, total]
	progress_lbl.add_theme_font_size_override("font_size", 12)
	progress_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	progress_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(progress_lbl)

	center.add_child(_spacer(30))

	# Buttons
	var btn_row = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(btn_row)

	var deploy_btn = _make_btn("DEPLOY", Color(0.85, 0.14, 0.28), Vector2(220, 52))
	deploy_btn.pressed.connect(_on_deploy)
	btn_row.add_child(deploy_btn)

	var spacer_h = Control.new()
	spacer_h.custom_minimum_size = Vector2(20, 0)
	btn_row.add_child(spacer_h)

	var retreat_btn = _make_btn("RETREAT", Color(0.3, 0.3, 0.35), Vector2(160, 52))
	retreat_btn.pressed.connect(_on_retreat)
	btn_row.add_child(retreat_btn)

func _objective_icon(obj_type: String) -> String:
	match obj_type.to_lower():
		"seize":    return "⚑"
		"rout":     return "⚔"
		"defend":   return "⛨"
		"escort":   return "→"
		"survive":  return "⏳"
	return "●"

func _spacer(h: int) -> Control:
	var s = Control.new()
	s.custom_minimum_size = Vector2(0, h)
	return s

func _make_btn(label: String, col: Color, sz: Vector2) -> Button:
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = sz
	btn.add_theme_font_size_override("font_size", 16)
	var style = StyleBoxFlat.new()
	style.bg_color = col.darkened(0.6)
	style.border_color = col.darkened(0.2)
	style.set_border_width_all(1)
	style.border_width_bottom = 3
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	btn.add_theme_stylebox_override("normal", style)
	var hover = StyleBoxFlat.new()
	hover.bg_color = col.darkened(0.4)
	hover.border_color = col
	hover.set_border_width_all(1)
	hover.border_width_bottom = 3
	hover.set_corner_radius_all(6)
	hover.set_content_margin_all(10)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed = StyleBoxFlat.new()
	pressed.bg_color = col.darkened(0.2)
	pressed.border_color = col.lightened(0.2)
	pressed.set_border_width_all(1)
	pressed.border_width_bottom = 3
	pressed.set_corner_radius_all(6)
	pressed.set_content_margin_all(10)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn

# ─── Callbacks ─────────────────────────────────────────────────────────

func _on_deploy():
	if ready_to_launch:
		return
	ready_to_launch = true
	DebugLogger.audit("MissionBrief", "DEPLOY pressed — launching battle")
	# Transition to the battle
	CampaignRunner.launch_current_mission()

func _on_retreat():
	# Return to title screen, end campaign
	CampaignRunner.is_campaign_active = false
	get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
