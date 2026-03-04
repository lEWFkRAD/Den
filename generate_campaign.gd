extends SceneTree
## CLI entry point: generates a full campaign, maps, and loot from doctrine.
##
## Usage:
##   godot --headless -s generate_campaign.gd [-- --seed 12345]
##
## Outputs are written to res://output/{campaigns,missions,maps,loot}/.

# Preload all dependencies explicitly (class_name may not resolve in --script mode)
const _DenRNG             = preload("res://data_gen/rng.gd")
const _DoctrineLoader     = preload("res://data_gen/doctrine_loader.gd")
const _CampaignGenerator  = preload("res://data_gen/campaign_gen/campaign_generator.gd")
const _DoctrineMapGen     = preload("res://data_gen/map_gen/doctrine_map_gen.gd")
const _LootGenerator      = preload("res://data_gen/loot_gen/loot_generator.gd")

const DOCTRINE_PATH: String = "res://doctrine/world_doctrine.json"
const OUTPUT_ROOT: String = "res://output"


func _init() -> void:
	print("=== Den Campaign Generator ===")

	# ── Parse optional seed from CLI args ─────────────────────────────────
	var seed_val: int = _parse_seed()
	if seed_val == 0:
		seed_val = randi()  # random if not specified
	print("Seed: %d" % seed_val)

	# ── 1. Load doctrine ──────────────────────────────────────────────────
	var loader = _DoctrineLoader.new()
	if not loader.load_doctrine(DOCTRINE_PATH):
		push_error("Failed to load doctrine from '%s'. Aborting." % DOCTRINE_PATH)
		quit(1)
		return
	print("Doctrine loaded.")

	# ── 2. Generate campaign ──────────────────────────────────────────────
	var campaign_gen = _CampaignGenerator.new()
	var campaign: Dictionary = campaign_gen.generate_campaign(seed_val, loader)
	if campaign.is_empty():
		push_error("CampaignGenerator returned empty campaign. Aborting.")
		quit(1)
		return
	var campaign_id: String = campaign.get("id", "campaign_%d" % seed_val)
	var missions: Array = campaign.get("missions", [])
	print("Campaign '%s' generated with %d missions." % [campaign_id, missions.size()])

	# ── 3. Prepare sub-generators ─────────────────────────────────────────
	var map_gen = _DoctrineMapGen.new()
	var loot_gen = _LootGenerator.new()
	var master_rng = _DenRNG.new(seed_val)

	# ── 4. Ensure output directories exist ────────────────────────────────
	_ensure_dir(OUTPUT_ROOT + "/campaigns")
	_ensure_dir(OUTPUT_ROOT + "/missions")
	_ensure_dir(OUTPUT_ROOT + "/maps")
	_ensure_dir(OUTPUT_ROOT + "/loot")

	# ── 5. Process each mission ───────────────────────────────────────────
	var total_items: int = 0
	for i in range(missions.size()):
		var mission: Dictionary = missions[i]
		var mission_id: String = mission.get("id", "mission_%02d" % i)
		var mission_rng = master_rng.fork("mission_%d" % i)

		# 5a. Generate map
		var map_rng = mission_rng.fork("map")
		var map_data: Dictionary = map_gen.generate(mission, loader.doctrine, map_rng)

		# 5b. Generate loot
		var loot_rng = mission_rng.fork("loot")
		var loot_items: Array = loot_gen.generate_loot(mission, loader.doctrine, loot_rng)
		total_items += loot_items.size()

		# 5c. Save map JSON
		var map_path: String = "%s/maps/%s_map.json" % [OUTPUT_ROOT, mission_id]
		_save_json(map_path, map_data)

		# 5d. Save loot JSON
		var loot_path: String = "%s/loot/%s_loot.json" % [OUTPUT_ROOT, mission_id]
		_save_json(loot_path, loot_items)

		# 5e. Attach references to the mission and save mission JSON
		mission["map_file"] = "%s_map.json" % mission_id
		mission["loot_file"] = "%s_loot.json" % mission_id
		var mission_path: String = "%s/missions/%s.json" % [OUTPUT_ROOT, mission_id]
		_save_json(mission_path, mission)

		var map_size: Array = map_data.get("size", [0, 0])
		print("  [%d/%d] %s  map:%dx%d  loot:%d items" % [
			i + 1,
			missions.size(),
			mission_id,
			map_size[0] if map_size.size() >= 1 else 0,
			map_size[1] if map_size.size() >= 2 else 0,
			loot_items.size(),
		])

	# ── 6. Save campaign JSON ─────────────────────────────────────────────
	var campaign_path: String = "%s/campaigns/%s.json" % [OUTPUT_ROOT, campaign_id]
	_save_json(campaign_path, campaign)

	# ── 7. Summary ────────────────────────────────────────────────────────
	print("")
	print("=== Generation Complete ===")
	print("  Campaign:  %s" % campaign_id)
	print("  Seed:      %d" % seed_val)
	print("  Missions:  %d" % missions.size())
	print("  Items:     %d total" % total_items)
	print("  Output:    %s/" % OUTPUT_ROOT)
	print("")

	quit(0)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _parse_seed() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--seed" and i + 1 < args.size():
			return int(args[i + 1])
	return 0


func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		var err: Error = DirAccess.make_dir_recursive_absolute(path)
		if err != OK:
			push_error("Failed to create directory '%s' (error %d)" % [path, err])


func _save_json(path: String, data: Variant) -> void:
	var json_text: String = JSON.stringify(data, "  ")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to write '%s' (error %d)" % [path, FileAccess.get_open_error()])
		return
	file.store_string(json_text)
	file.close()
