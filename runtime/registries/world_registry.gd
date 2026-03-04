class_name WorldRegistry
extends RefCounted
## Single source of truth that merges doctrine + kit_registry + archetype
## mappings at runtime. Prevents drift between generation and rendering.
##
## Usage:
##   var reg = WorldRegistry.new()
##   var scene_path = reg.resolve_prefab_scene("tower_1x1")
##   var palette    = reg.resolve_biome_palette("snow")
##   var enemy_type = reg.resolve_enemy_archetype("covenant_templar")
##   var tile_mat   = reg.resolve_terrain_material("grass")

# ── Cached data ──────────────────────────────────────────────────────────────
var _kit_pieces: Dictionary = {}      # piece_id → metadata dict
var _biome_palettes: Dictionary = {}  # biome_name → palette dict
var _doctrine: Dictionary = {}        # full world_doctrine
var _loaded: bool = false

# ── Terrain → Tile material mapping ──────────────────────────────────────────
const TERRAIN_MATERIAL_MAP: Dictionary = {
	"grass": "plain", "stone": "ruins", "dirt": "road",
	"water": "water", "wall": "wall", "bridge": "bridge",
	"sand": "sand", "ice": "water", "rock": "mountain",
	"snow": "plain", "mud": "plain", "forest": "forest",
	"lava": "lava", "road": "road", "plain": "plain",
	"ruins": "ruins", "fort": "fort", "village": "village",
	"throne": "throne", "mountain": "mountain", "river": "river",
}

# ── Prefab → scene path mapping ──────────────────────────────────────────────
const PREFAB_SCENE_DIR: String = "res://prefabs/kit/"

# ── Archetype keyword fallback (same as MissionBattleLoader) ─────────────────
const _ARCHETYPE_KEYWORDS: Array = [
	["commander", "commander"], ["captain", "commander"],
	["knight", "blood_knight"], ["paladin", "paladin"],
	["warden", "heavy"], ["bulwark", "heavy"], ["ironhelm", "heavy"],
	["heavy", "heavy"], ["templar", "heavy"], ["pikeman", "heavy"],
	["archer", "archer"], ["scout", "archer"], ["slingman", "archer"], ["bow", "archer"],
	["mage", "mage"], ["hexblade", "mage"], ["scholar", "mage"],
	["siege", "siege_mage"], ["priest", "priest"], ["acolyte", "priest"],
	["inquisitor", "mage"], ["rogue", "rogue"], ["cutthroat", "rogue"],
	["assassin", "assassin"], ["duelist", "rogue"], ["runner", "rogue"],
	["golem", "golem"], ["guard", "heavy"], ["spearman", "grunt"],
	["sword", "grunt"], ["levy", "grunt"], ["novice", "archer"],
]

# ── Tile object string mapping (prefab → Tile.set_object) ────────────────────
const PREFAB_OBJECT_MAP: Dictionary = {
	"crate": "crate", "barrel": "barrel",
	"tree_pine": "tree_pine", "tree_oak": "tree_oak", "tree_dead": "tree_dead",
	"rock_small": "bush", "rock_large": "ruins_pillar",
	"rubble_pile": "ruins_pillar", "pillar_broken": "ruins_pillar",
	"statue_broken": "statue", "banner_torn": "signpost",
	"bridge_post": "fence_v", "tower_1x1": "tower", "tower_2x2": "tower",
	"wall_straight": "fence_h", "wall_corner": "fence_h",
	"wall_broken": "ruins_arch", "wall_t_junction": "fence_h",
	"wall_endcap": "fence_h", "gate_open": "ruins_arch",
	"gate_closed": "fence_h", "well": "well",
	"campfire": "signpost", "grave_marker": "signpost",
	"ice_shard": "ruins_pillar", "frozen_tree": "tree_dead",
}


func _init() -> void:
	_load_all()


# ── Public API ───────────────────────────────────────────────────────────────

## Returns the Tile.set_terrain() string for a generator terrain type.
func resolve_terrain_material(gen_terrain: String) -> String:
	return TERRAIN_MATERIAL_MAP.get(gen_terrain, gen_terrain)


## Returns the scene path for a kit prefab ID (e.g. "res://prefabs/kit/tower_1x1.tscn").
## Returns "" if no scene file exists yet.
func resolve_prefab_scene(prefab_id: String) -> String:
	var path: String = PREFAB_SCENE_DIR + prefab_id + ".tscn"
	if ResourceLoader.exists(path):
		return path
	return ""


## Returns the Tile.set_object() string for a prefab ID. Used as fallback
## when no .tscn scene exists.
func resolve_prefab_object(prefab_id: String) -> String:
	return PREFAB_OBJECT_MAP.get(prefab_id, "")


## Returns the kit piece metadata dict from kit_registry.json.
func get_piece_metadata(prefab_id: String) -> Dictionary:
	return _kit_pieces.get(prefab_id, {})


## Returns the biome palette dict for a biome name.
## Contains: cover_props, scatter_props, ruin_props arrays.
func resolve_biome_palette(biome: String) -> Dictionary:
	return _biome_palettes.get(biome, _biome_palettes.get("forest", {}))


## Resolves a faction-specific enemy unit_def to a generic archetype
## that exists in DataLoader.enemies_data.
func resolve_enemy_archetype(unit_def: String) -> String:
	# Try exact match first
	if DataLoader.enemies_data.has(unit_def):
		return unit_def
	# Keyword fallback
	var lower: String = unit_def.to_lower()
	for pair in _ARCHETYPE_KEYWORDS:
		if lower.contains(pair[0]):
			return pair[1]
	return "grunt"


## Returns the full faction dict from doctrine (enemy_pools_by_tier, etc).
func get_faction_data(faction_id: String) -> Dictionary:
	var factions: Dictionary = _doctrine.get("factions", {})
	return factions.get(faction_id, {})


## Returns all kit piece IDs as an array.
func get_all_piece_ids() -> Array:
	return _kit_pieces.keys()


## Returns all biome names with palettes.
func get_all_biomes() -> Array:
	return _biome_palettes.keys()


# ── Loading ──────────────────────────────────────────────────────────────────

func _load_all() -> void:
	if _loaded:
		return
	_load_kit_registry()
	_load_doctrine()
	_loaded = true


func _load_kit_registry() -> void:
	var path: String = "res://doctrine/kit_registry.json"
	if not FileAccess.file_exists(path):
		push_warning("WorldRegistry: kit_registry.json not found")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("WorldRegistry: kit_registry.json parse error")
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		return

	# Index pieces by id
	for piece in data.get("pieces", []):
		if piece is Dictionary and piece.has("id"):
			_kit_pieces[piece["id"]] = piece

	# Index palettes by biome name
	for palette in data.get("biome_palettes", []):
		if palette is Dictionary and palette.has("biome"):
			_biome_palettes[palette["biome"]] = palette


func _load_doctrine() -> void:
	var path: String = "res://doctrine/world_doctrine.json"
	if not FileAccess.file_exists(path):
		push_warning("WorldRegistry: world_doctrine.json not found")
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_warning("WorldRegistry: world_doctrine.json parse error")
		return
	var data: Variant = json.data
	if data is Dictionary:
		_doctrine = data
