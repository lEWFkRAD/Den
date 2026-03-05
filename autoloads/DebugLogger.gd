extends CanvasLayer

## DebugLogger — Global error capture, audit trail, and on-screen overlay.
##
## Toggle overlay:  F1  (or backtick)
## Scroll log:      MouseWheel when overlay is visible
## Filter:          Type in the filter bar (top of overlay)
##
## Usage from any script:
##   DebugLogger.audit("Battle3D", "Camera created", {"zoom": 12.0})
##   DebugLogger.err("Grid3D", "Tile missing at %s" % pos)
##   DebugLogger.warn("Loader", "No loot table found")
##   DebugLogger.info("TurnManager", "Phase started: PLAYER")
##
## Checkpoints (timed audit with pass/fail):
##   DebugLogger.checkpoint_start("battle_init")
##   ... do work ...
##   DebugLogger.checkpoint_end("battle_init", true)   # pass
##   DebugLogger.checkpoint_end("battle_init", false, "Grid was null")  # fail

# ─── Constants ──────────────────────────────────────────────────────────────

const MAX_ENTRIES: int = 500
const LOG_FILE_PATH: String = "user://debug_log.txt"

enum Level { AUDIT, INFO, WARN, ERROR, CHECKPOINT }

const LEVEL_LABELS: Dictionary = {
	Level.AUDIT:      "AUDIT",
	Level.INFO:       "INFO",
	Level.WARN:       "WARN",
	Level.ERROR:      "ERROR",
	Level.CHECKPOINT: "CHECK",
}

const LEVEL_COLORS: Dictionary = {
	Level.AUDIT:      Color(0.5, 0.5, 0.6),
	Level.INFO:       Color(0.55, 0.78, 1.0),
	Level.WARN:       Color(0.95, 0.85, 0.2),
	Level.ERROR:      Color(1.0, 0.35, 0.3),
	Level.CHECKPOINT: Color(0.3, 0.9, 0.5),
}

# ─── Data ───────────────────────────────────────────────────────────────────

var entries: Array = []   # [{time, level, system, message, data}]
var checkpoints: Dictionary = {}  # id → {system, start_ms, label}
var checkpoint_results: Array = []  # [{id, system, label, passed, elapsed_ms, error}]

var _log_file: FileAccess = null
var _overlay_visible: bool = false
var _scroll_offset: int = 0
var _filter_text: String = ""
var _startup_ms: int = 0

# ─── UI Nodes ───────────────────────────────────────────────────────────────

var _panel: ColorRect
var _rtl: RichTextLabel
var _filter_input: LineEdit
var _checkpoint_panel: ColorRect
var _checkpoint_rtl: RichTextLabel
var _stats_label: Label
var _close_btn: Button

# ─── Lifecycle ──────────────────────────────────────────────────────────────

func _ready():
	layer = 99  # Above everything
	_startup_ms = Time.get_ticks_msec()
	_open_log_file()
	_build_overlay()
	_hide_overlay()
	# Capture Godot's built-in error output
	# We'll also hook into the logger
	info("DebugLogger", "Initialized — press F1 to toggle overlay")

func _open_log_file():
	_log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
	if _log_file:
		_log_file.store_line("=== DEN Debug Log — %s ===" % Time.get_datetime_string_from_system())
		_log_file.store_line("")

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_QUOTELEFT:
			_toggle_overlay()
			get_viewport().set_input_as_handled()
		elif _overlay_visible and event.keycode == KEY_ESCAPE:
			_hide_overlay()
			get_viewport().set_input_as_handled()
	if _overlay_visible and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll_offset = mini(_scroll_offset + 3, maxi(0, _filtered_entries().size() - 20))
			_refresh_log()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll_offset = maxi(0, _scroll_offset - 3)
			_refresh_log()

# ─── Public API ─────────────────────────────────────────────────────────────

func audit(system: String, message: String, data: Dictionary = {}):
	_add_entry(Level.AUDIT, system, message, data)

func info(system: String, message: String, data: Dictionary = {}):
	_add_entry(Level.INFO, system, message, data)

func warn(system: String, message: String, data: Dictionary = {}):
	_add_entry(Level.WARN, system, message, data)

func err(system: String, message: String, data: Dictionary = {}):
	_add_entry(Level.ERROR, system, message, data)

func checkpoint_start(id: String, system: String = "", label: String = ""):
	var display_label: String = label if label != "" else id
	checkpoints[id] = {
		"system": system,
		"start_ms": Time.get_ticks_msec(),
		"label": display_label,
	}
	_add_entry(Level.CHECKPOINT, system, "▶ START: %s" % display_label)

func checkpoint_end(id: String, passed: bool = true, error_msg: String = ""):
	if not checkpoints.has(id):
		err("DebugLogger", "checkpoint_end called for unknown id: %s" % id)
		return
	var cp: Dictionary = checkpoints[id]
	var elapsed: int = Time.get_ticks_msec() - cp["start_ms"]
	var status: String = "✓ PASS" if passed else "✗ FAIL"
	var msg: String = "%s: %s (%dms)" % [status, cp["label"], elapsed]
	if not passed and error_msg != "":
		msg += " — %s" % error_msg

	checkpoint_results.append({
		"id": id,
		"system": cp["system"],
		"label": cp["label"],
		"passed": passed,
		"elapsed_ms": elapsed,
		"error": error_msg,
	})
	checkpoints.erase(id)

	var level: Level = Level.CHECKPOINT if passed else Level.ERROR
	_add_entry(level, cp["system"], msg)

	if _overlay_visible:
		_refresh_checkpoints()

## Returns a summary dictionary for external tools / save files.
func get_summary() -> Dictionary:
	var errors: int = 0
	var warnings: int = 0
	for e in entries:
		if e["level"] == Level.ERROR:
			errors += 1
		elif e["level"] == Level.WARN:
			warnings += 1
	return {
		"total_entries": entries.size(),
		"errors": errors,
		"warnings": warnings,
		"checkpoints_passed": checkpoint_results.filter(func(c): return c["passed"]).size(),
		"checkpoints_failed": checkpoint_results.filter(func(c): return not c["passed"]).size(),
		"uptime_ms": Time.get_ticks_msec() - _startup_ms,
	}

## Dump the full log to the file and return the path.
func flush_to_file() -> String:
	if _log_file:
		_log_file.flush()
	return LOG_FILE_PATH

# ─── Internal ───────────────────────────────────────────────────────────────

func _add_entry(level: Level, system: String, message: String, data: Dictionary = {}):
	var elapsed_ms: int = Time.get_ticks_msec() - _startup_ms
	var entry: Dictionary = {
		"time": elapsed_ms,
		"level": level,
		"system": system,
		"message": message,
		"data": data,
	}
	entries.append(entry)
	if entries.size() > MAX_ENTRIES:
		entries.pop_front()

	# Console output
	var prefix: String = "[%s] [%s] %s" % [LEVEL_LABELS[level], system, message]
	if not data.is_empty():
		prefix += " | %s" % str(data)
	match level:
		Level.ERROR:
			push_error(prefix)
		Level.WARN:
			push_warning(prefix)
		_:
			print(prefix)

	# File output
	if _log_file:
		var time_str: String = "%d.%03d" % [elapsed_ms / 1000, elapsed_ms % 1000]
		_log_file.store_line("[%ss] %s" % [time_str, prefix])

	# Update overlay if visible
	if _overlay_visible:
		_refresh_log()
		_refresh_stats()

# ─── Overlay UI ─────────────────────────────────────────────────────────────

func _build_overlay():
	# Main panel — semi-transparent dark background
	_panel = ColorRect.new()
	_panel.name = "DebugPanel"
	_panel.color = Color(0.02, 0.02, 0.04, 0.92)
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_panel)

	# Title bar
	var title_bar = HBoxContainer.new()
	title_bar.position = Vector2(12, 8)
	title_bar.custom_minimum_size = Vector2(1256, 30)
	_panel.add_child(title_bar)

	var title = Label.new()
	title.text = "DEN DEBUG LOGGER"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.85, 0.14, 0.28))
	title_bar.add_child(title)

	var spacer1 = Control.new()
	spacer1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_bar.add_child(spacer1)

	# Filter
	var filter_label = Label.new()
	filter_label.text = "Filter:"
	filter_label.add_theme_font_size_override("font_size", 12)
	filter_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	title_bar.add_child(filter_label)

	_filter_input = LineEdit.new()
	_filter_input.custom_minimum_size = Vector2(200, 24)
	_filter_input.placeholder_text = "system or text..."
	_filter_input.add_theme_font_size_override("font_size", 12)
	var filter_style = StyleBoxFlat.new()
	filter_style.bg_color = Color(0.08, 0.08, 0.10)
	filter_style.border_color = Color(0.25, 0.25, 0.3)
	filter_style.set_border_width_all(1)
	filter_style.set_corner_radius_all(3)
	filter_style.set_content_margin_all(4)
	_filter_input.add_theme_stylebox_override("normal", filter_style)
	_filter_input.text_changed.connect(_on_filter_changed)
	title_bar.add_child(_filter_input)

	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(12, 0)
	title_bar.add_child(spacer2)

	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.add_theme_font_size_override("font_size", 14)
	_close_btn.custom_minimum_size = Vector2(28, 28)
	_close_btn.pressed.connect(_hide_overlay)
	title_bar.add_child(_close_btn)

	# Separator
	var sep = ColorRect.new()
	sep.color = Color(0.25, 0.25, 0.3, 0.5)
	sep.position = Vector2(12, 42)
	sep.size = Vector2(1256, 1)
	_panel.add_child(sep)

	# Checkpoint summary panel (left column)
	_checkpoint_panel = ColorRect.new()
	_checkpoint_panel.color = Color(0.04, 0.04, 0.06, 0.8)
	_checkpoint_panel.position = Vector2(12, 48)
	_checkpoint_panel.size = Vector2(300, 620)
	_panel.add_child(_checkpoint_panel)

	var cp_title = Label.new()
	cp_title.text = "CHECKPOINTS"
	cp_title.add_theme_font_size_override("font_size", 12)
	cp_title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	cp_title.position = Vector2(8, 4)
	_checkpoint_panel.add_child(cp_title)

	_checkpoint_rtl = RichTextLabel.new()
	_checkpoint_rtl.bbcode_enabled = true
	_checkpoint_rtl.scroll_following = true
	_checkpoint_rtl.position = Vector2(4, 24)
	_checkpoint_rtl.size = Vector2(292, 590)
	_checkpoint_rtl.add_theme_font_size_override("normal_font_size", 11)
	_checkpoint_panel.add_child(_checkpoint_rtl)

	# Main log panel (right side)
	_rtl = RichTextLabel.new()
	_rtl.bbcode_enabled = true
	_rtl.scroll_following = true
	_rtl.position = Vector2(320, 48)
	_rtl.size = Vector2(948, 590)
	_rtl.add_theme_font_size_override("normal_font_size", 11)
	_panel.add_child(_rtl)

	# Stats bar at bottom
	_stats_label = Label.new()
	_stats_label.position = Vector2(12, 672)
	_stats_label.add_theme_font_size_override("font_size", 11)
	_stats_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	_panel.add_child(_stats_label)

func _toggle_overlay():
	if _overlay_visible:
		_hide_overlay()
	else:
		_show_overlay()

func _show_overlay():
	_overlay_visible = true
	_panel.visible = true
	_scroll_offset = 0
	_refresh_log()
	_refresh_checkpoints()
	_refresh_stats()

func _hide_overlay():
	_overlay_visible = false
	_panel.visible = false

func _on_filter_changed(new_text: String):
	_filter_text = new_text.to_lower()
	_scroll_offset = 0
	_refresh_log()

func _filtered_entries() -> Array:
	if _filter_text == "":
		return entries
	var result: Array = []
	for e in entries:
		var haystack: String = (e["system"] + " " + e["message"]).to_lower()
		if haystack.contains(_filter_text):
			result.append(e)
	return result

func _refresh_log():
	if _rtl == null:
		return
	_rtl.clear()
	var filtered: Array = _filtered_entries()
	var total: int = filtered.size()
	var start: int = maxi(0, total - 40 - _scroll_offset)
	var end_idx: int = mini(total, start + 40)

	for i in range(start, end_idx):
		var e: Dictionary = filtered[i]
		var level: Level = e["level"] as Level
		var col: Color = LEVEL_COLORS.get(level, Color.WHITE)
		var time_s: float = e["time"] / 1000.0
		var hex: String = col.to_html(false)
		var line: String = "[color=#666666]%6.1fs[/color] [color=#%s][%s][/color] [color=#888888][%s][/color] %s" % [
			time_s, hex, LEVEL_LABELS[level], e["system"], e["message"]
		]
		if not e.get("data", {}).is_empty():
			line += " [color=#555555]%s[/color]" % str(e["data"])
		_rtl.append_text(line + "\n")

func _refresh_checkpoints():
	if _checkpoint_rtl == null:
		return
	_checkpoint_rtl.clear()

	# Show in-progress checkpoints
	if not checkpoints.is_empty():
		_checkpoint_rtl.append_text("[color=#ffcc00]⟳ IN PROGRESS[/color]\n")
		for id in checkpoints:
			var cp: Dictionary = checkpoints[id]
			var elapsed: int = Time.get_ticks_msec() - cp["start_ms"]
			_checkpoint_rtl.append_text("  ⏳ %s (%dms)\n" % [cp["label"], elapsed])
		_checkpoint_rtl.append_text("\n")

	# Show completed checkpoints
	if checkpoint_results.is_empty():
		_checkpoint_rtl.append_text("[color=#555555]No checkpoints recorded yet.[/color]\n")
		return

	for cp in checkpoint_results:
		if cp["passed"]:
			_checkpoint_rtl.append_text("[color=#2ecc71]✓[/color] %s [color=#555555]%dms[/color]\n" % [cp["label"], cp["elapsed_ms"]])
		else:
			_checkpoint_rtl.append_text("[color=#e74c3c]✗[/color] %s [color=#555555]%dms[/color]\n" % [cp["label"], cp["elapsed_ms"]])
			if cp["error"] != "":
				_checkpoint_rtl.append_text("  [color=#e74c3c]↳ %s[/color]\n" % cp["error"])

func _refresh_stats():
	if _stats_label == null:
		return
	var s: Dictionary = get_summary()
	_stats_label.text = "Entries: %d  |  Errors: %d  |  Warnings: %d  |  Checks: %d✓ %d✗  |  Uptime: %.1fs  |  F1 to toggle  |  Log: %s" % [
		s["total_entries"], s["errors"], s["warnings"],
		s["checkpoints_passed"], s["checkpoints_failed"],
		s["uptime_ms"] / 1000.0, LOG_FILE_PATH,
	]
