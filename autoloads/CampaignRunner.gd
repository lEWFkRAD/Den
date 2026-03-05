extends Node
## Manages campaign state and mission progression.
##
## Flow: Title Screen → start_campaign() → load_current_mission() → Battle3D
##       Battle3D completes → complete_mission() → next mission or campaign end.
##
## Battle3D reads `current_mission_path` on _ready() and loads through
## MissionBattleLoader. When battle ends, it calls complete_mission(victory).

const OUTPUT_ROOT: String = "res://output"

# ─── Campaign State ──────────────────────────────────────────────────────────

var campaign_id: String = ""
var campaign: Dictionary = {}
var missions: Array = []          # Array of mission dicts from campaign JSON
var mission_index: int = 0
var current_mission_path: String = ""   # Battle3D reads this
var is_campaign_active: bool = false

# ─── Signals ─────────────────────────────────────────────────────────────────

signal mission_started(mission_index: int, mission_id: String)
signal mission_completed(mission_index: int, victory: bool)
signal campaign_completed(campaign_id: String)


# ─── Public API ──────────────────────────────────────────────────────────────

## Starts a campaign from a campaign JSON file.
## Resets state and loads the first mission.
func start_campaign(campaign_path: String) -> bool:
	DebugLogger.checkpoint_start("campaign_start", "CampaignRunner", "Start campaign")
	DebugLogger.audit("CampaignRunner", "Loading campaign", {"path": campaign_path})
	var data: Dictionary = _read_json(campaign_path)
	if data.is_empty():
		DebugLogger.err("CampaignRunner", "Failed to load campaign JSON", {"path": campaign_path})
		DebugLogger.checkpoint_end("campaign_start", false, "JSON load failed: %s" % campaign_path)
		return false

	campaign = data
	campaign_id = str(data.get("id", data.get("campaign_id", "campaign")))
	missions = data.get("missions", [])
	mission_index = 0
	is_campaign_active = true

	if missions.is_empty():
		DebugLogger.err("CampaignRunner", "Campaign has no missions", {"id": campaign_id})
		DebugLogger.checkpoint_end("campaign_start", false, "No missions in campaign")
		is_campaign_active = false
		return false

	DebugLogger.checkpoint_end("campaign_start", true)
	DebugLogger.info("CampaignRunner", "Campaign started", {"id": campaign_id, "missions": missions.size()})
	return true


## Prepares the current mission and shows the Mission Brief screen.
## Call after start_campaign() or after advancing to a new mission.
func load_current_mission() -> void:
	if not is_campaign_active or mission_index >= missions.size():
		DebugLogger.err("CampaignRunner", "No active mission to load", {"active": is_campaign_active, "index": mission_index, "total": missions.size()})
		return

	var mission_entry: Dictionary = missions[mission_index] if missions[mission_index] is Dictionary else {}
	var mission_id: String = str(mission_entry.get("id", ""))
	current_mission_path = _resolve_mission_path(mission_entry)

	DebugLogger.audit("CampaignRunner", "Loading mission", {"index": mission_index, "id": mission_id, "path": current_mission_path})

	# Verify mission file exists
	if current_mission_path != "" and not FileAccess.file_exists(current_mission_path):
		DebugLogger.err("CampaignRunner", "Mission file NOT FOUND", {"path": current_mission_path})
	elif current_mission_path == "":
		DebugLogger.err("CampaignRunner", "Mission path is empty", {"entry": str(mission_entry)})

	mission_started.emit(mission_index, mission_id)

	DebugLogger.audit("CampaignRunner", "Transitioning to MissionBrief")
	# Show Mission Brief screen — player presses DEPLOY to continue to battle
	get_tree().change_scene_to_file("res://scenes/ui/MissionBrief.tscn")


## Called by MissionBrief when the player presses DEPLOY.
## Actually transitions to the 3D battle scene.
func launch_current_mission() -> void:
	DebugLogger.audit("CampaignRunner", "Launching battle scene", {"mission_index": mission_index, "path": current_mission_path})
	get_tree().change_scene_to_file("res://scenes/battle/BattleScene3D.tscn")


## Called by Battle3D when the battle ends.
## Advances to next mission or completes the campaign.
func complete_mission(victory: bool) -> void:
	var mission_id: String = ""
	if mission_index < missions.size() and missions[mission_index] is Dictionary:
		mission_id = str(missions[mission_index].get("id", ""))

	print("CampaignRunner: Mission '%s' %s." % [mission_id, "VICTORY" if victory else "DEFEAT"])
	mission_completed.emit(mission_index, victory)

	if not victory:
		# On defeat: replay same mission (could add retry logic later)
		print("CampaignRunner: Retrying mission '%s'..." % mission_id)
		load_current_mission()
		return

	# Advance to next mission
	mission_index += 1

	if mission_index >= missions.size():
		print("CampaignRunner: Campaign '%s' complete!" % campaign_id)
		is_campaign_active = false
		campaign_completed.emit(campaign_id)
		# Return to title screen (could go to a victory screen later)
		get_tree().change_scene_to_file("res://scenes/ui/TitleScreen.tscn")
		return

	# Load next mission
	load_current_mission()


## Returns a summary of the current mission for UI display.
func get_mission_info() -> Dictionary:
	if not is_campaign_active or mission_index >= missions.size():
		return {}
	var entry: Dictionary = missions[mission_index] if missions[mission_index] is Dictionary else {}
	return {
		"index": mission_index,
		"total": missions.size(),
		"id": str(entry.get("id", "")),
		"region": str(entry.get("region", "")),
		"objective": entry.get("objective", {"type": "rout"}),
		"act": int(entry.get("act", 1)),
		"chapter": int(entry.get("chapter", mission_index + 1)),
	}


# ─── Internal ────────────────────────────────────────────────────────────────

## Resolves a mission entry to a file path.
func _resolve_mission_path(entry: Dictionary) -> String:
	# Try direct path fields first
	if entry.has("path"):
		return _normalize_path(str(entry["path"]))

	# Convention: output/missions/<id>.json
	var mission_id: String = str(entry.get("id", ""))
	if mission_id != "":
		return "%s/missions/%s.json" % [OUTPUT_ROOT, mission_id]

	push_error("CampaignRunner: Cannot resolve mission path from entry: %s" % [entry])
	return ""


func _normalize_path(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return p
	if p.begins_with("output/"):
		return "res://%s" % p
	return "res://%s" % p


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("CampaignRunner: File not found: '%s'" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CampaignRunner: Cannot open: '%s'" % path)
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("CampaignRunner: JSON parse error in '%s': %s" % [path, json.get_error_message()])
		return {}
	if not (json.data is Dictionary):
		push_error("CampaignRunner: Root is not a Dictionary in '%s'" % path)
		return {}
	return json.data
