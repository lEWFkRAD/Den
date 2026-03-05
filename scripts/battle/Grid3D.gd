class_name Grid3D
extends Node3D

## 3D tactical grid renderer — renders tiles as MeshInstance3D planes
## with height variation, unit Sprite3D billboards, and visual effects.
## Reuses Tile.gd data model from the 2D system.

const TILE_SCALE: float = 1.0   # World units per tile
const HEIGHT_STEP: float = 0.5  # Height increment

var grid_width:  int = 12
var grid_height: int = 12
var tiles:       Dictionary = {}   # Vector2i → Tile
var height_map:  Dictionary = {}   # Vector2i → float (Y offset)
var highlighted: Dictionary = {}   # Vector2i → Color
var units_ref:   Array      = []

# Node containers
var tiles_root:  Node3D
var units_root:  Node3D
var vfx_root:    Node3D
var props_root:  Node3D

# Caches
var tile_meshes:      Dictionary = {}  # Vector2i → MeshInstance3D
var highlight_meshes: Dictionary = {}  # Vector2i → MeshInstance3D
var unit_sprites:     Dictionary = {}  # Unit → Sprite3D
var sprite_cache:     Dictionary = {}  # name_lower → Texture2D
var kip_sprite_cache: Dictionary = {}  # kip_name_lower → Texture2D
var terrain_tex_cache: Dictionary = {} # terrain_key → Texture2D
var enemy_sprite_cache: Dictionary = {} # enemy_id_lower → Texture2D
var hp_bar_meshes:    Dictionary = {}  # Unit → MeshInstance3D
var prop_nodes:       Dictionary = {}  # Vector2i → Node3D (instanced prefab scenes)
var prop_scene_cache: Dictionary = {}  # scene_path → PackedScene

# Damage popups
var damage_pops: Array = []  # [{label, timer, max_timer}]

# Path preview
var path_line_meshes: Array = []       # Array of MeshInstance3D
var path_cost_label: Label3D = null    # Shows move cost at end of path
var move_cost_map: Dictionary = {}     # Vector2i → int (from last get_movement_range)
var move_prev_map: Dictionary = {}     # Vector2i → Vector2i (parent, for path reconstruction)

# Tile info overlay (always-on floating label for hovered tile)
var tile_info_label: Label3D = null
var tile_info_pos: Vector2i = Vector2i(-1, -1)

# Attack range forecast labels
var forecast_labels: Dictionary = {}   # Vector2i → Label3D

# ─── Initialization ──────────────────────────────────────────────────────────

func initialize(unit_count: int, _kip_count: int = 0):
	DebugLogger.checkpoint_start("grid3d_init", "Grid3D", "Grid3D.initialize()")
	grid_width  = 12 + unit_count
	grid_height = 12 + unit_count
	_setup_containers()
	_build_tiles()
	_scatter_terrain()
	_generate_height_map()
	_load_sprites()
	_render_all_tiles()
	DebugLogger.checkpoint_end("grid3d_init", tiles.size() > 0, "" if tiles.size() > 0 else "No tiles created")
	DebugLogger.audit("Grid3D", "Initialized", {"size": "%dx%d" % [grid_width, grid_height], "tiles": tiles.size()})

func _setup_containers():
	tiles_root = Node3D.new()
	tiles_root.name = "TilesRoot"
	add_child(tiles_root)
	units_root = Node3D.new()
	units_root.name = "UnitsRoot"
	add_child(units_root)
	vfx_root = Node3D.new()
	vfx_root.name = "VFXRoot"
	add_child(vfx_root)
	props_root = Node3D.new()
	props_root.name = "PropsRoot"
	add_child(props_root)

func _load_sprites():
	var char_names = ["aldric", "mira", "voss", "seren", "bram", "corvin", "yael", "lorn"]
	for cname in char_names:
		var path = "res://assets/portraits/%s_small.png" % cname
		if ResourceLoader.exists(path):
			sprite_cache[cname] = load(path)
	var kip_names = ["scar", "thorn", "bolt", "null", "sleet", "dusk", "solen", "the_first"]
	for kname in kip_names:
		var path = "res://assets/kips/%s_small.png" % kname
		if ResourceLoader.exists(path):
			kip_sprite_cache[kname] = load(path)
	# Enemy sprites — load by enemy type ID and also map display names
	var enemy_ids = ["grunt", "archer", "heavy", "mage", "rogue", "blood_knight",
		"void_warden", "commander", "priest", "paladin", "assassin", "golem",
		"siege_mage", "covenant_captain", "warden_corrupted", "varek_final"]
	for eid in enemy_ids:
		var path = "res://assets/enemies/%s_small.png" % eid
		if ResourceLoader.exists(path):
			var tex = load(path)
			enemy_sprite_cache[eid] = tex
			# Also map the display name (from DataLoader) so unit_name lookups work
			var edata: Dictionary = DataLoader.enemies_data.get(eid, {})
			var display_name: String = edata.get("name", "").to_lower()
			if display_name != "":
				enemy_sprite_cache[display_name] = tex
	# Terrain tile textures
	var terrain_tiles = ["grass", "dirt", "stone", "sand", "snow", "water",
		"lava", "void", "ice", "ruins", "road", "forest"]
	for tname in terrain_tiles:
		var path = "res://assets/tiles/%s.png" % tname
		if ResourceLoader.exists(path):
			terrain_tex_cache[tname] = load(path)

# ─── Tile Data ────────────────────────────────────────────────────────────────

func _build_tiles():
	tiles.clear()
	for x in range(grid_width):
		for z in range(grid_height):
			var t = Tile.new()
			t.grid_pos = Vector2i(x, z)
			tiles[Vector2i(x, z)] = t

func _scatter_terrain():
	var rng = RandomNumberGenerator.new()
	rng.seed = 99991
	for x in range(grid_width):
		for z in range(grid_height):
			if x <= 2 and z <= 2: continue
			if x >= grid_width - 3 and z >= grid_height - 3: continue
			var roll = rng.randf()
			if roll < 0.07:
				tiles[Vector2i(x, z)].terrain_type = Tile.TerrainType.FOREST
				var tree_roll = rng.randf()
				if tree_roll < 0.4:
					tiles[Vector2i(x, z)].terrain_object = Tile.TerrainObject.TREE_PINE
				elif tree_roll < 0.7:
					tiles[Vector2i(x, z)].terrain_object = Tile.TerrainObject.TREE_OAK
				elif tree_roll < 0.85:
					tiles[Vector2i(x, z)].terrain_object = Tile.TerrainObject.BUSH
			elif roll < 0.11:
				tiles[Vector2i(x, z)].terrain_type = Tile.TerrainType.WATER
				tiles[Vector2i(x, z)].is_passable = false
			elif roll < 0.14:
				tiles[Vector2i(x, z)].terrain_type = Tile.TerrainType.RUINS
				if rng.randf() < 0.4:
					tiles[Vector2i(x, z)].terrain_object = Tile.TerrainObject.RUINS_PILLAR

func _generate_height_map():
	var rng = RandomNumberGenerator.new()
	rng.seed = 77713
	for x in range(grid_width):
		for z in range(grid_height):
			var pos = Vector2i(x, z)
			var tile = tiles[pos]
			var h: float = 0.0
			match tile.terrain_type:
				Tile.TerrainType.ELEVATION:
					h = rng.randi_range(2, 4) * HEIGHT_STEP
				Tile.TerrainType.FOREST:
					h = rng.randi_range(0, 1) * HEIGHT_STEP
				Tile.TerrainType.WATER:
					h = -HEIGHT_STEP
				Tile.TerrainType.RUINS:
					h = rng.randi_range(0, 2) * HEIGHT_STEP
				Tile.TerrainType.FORT, Tile.TerrainType.VILLAGE:
					h = HEIGHT_STEP
				Tile.TerrainType.THRONE:
					h = 2.0 * HEIGHT_STEP
				_:
					h = rng.randi_range(0, 2) * HEIGHT_STEP
			# Keep spawn corners flat
			if (x <= 2 and z <= 2) or (x >= grid_width - 3 and z >= grid_height - 3):
				h = 0.0
			height_map[pos] = h

func load_chapter_terrain(terrain_data: Array, width: int, height: int):
	DebugLogger.checkpoint_start("grid3d_chapter", "Grid3D", "Load chapter terrain %dx%d" % [width, height])
	grid_width = width
	grid_height = height
	tiles.clear()
	if tiles_root == null:
		_setup_containers()
	_load_sprites()
	var terrain_misses: int = 0
	for x in range(width):
		for z in range(height):
			var t = Tile.new()
			t.grid_pos = Vector2i(x, z)
			if z < terrain_data.size() and x < terrain_data[z].size():
				t.set_terrain(terrain_data[z][x])
			else:
				terrain_misses += 1
			tiles[Vector2i(x, z)] = t
	if terrain_misses > 0:
		DebugLogger.warn("Grid3D", "Terrain data gaps", {"misses": terrain_misses, "expected": width * height, "data_rows": terrain_data.size()})
	_generate_height_map()
	DebugLogger.audit("Grid3D", "Height map generated", {"entries": height_map.size()})
	_render_all_tiles()
	DebugLogger.checkpoint_end("grid3d_chapter", tiles.size() > 0, "" if tiles.size() > 0 else "No tiles after load")
	DebugLogger.audit("Grid3D", "Chapter terrain loaded", {"tiles": tiles.size(), "tile_meshes": tile_meshes.size()})

## Overrides the auto-generated height map with procedural data.
## data: Dictionary[Vector2i → float] from DoctrineMapLoader.
## Call after load_chapter_terrain() but before render_units().
## Pins water/lava tiles to a consistent flat level so rivers don't undulate.
func load_height_map(data: Dictionary) -> void:
	height_map = data
	# Force liquid tiles to a flat consistent elevation
	var water_level: float = -HEIGHT_STEP
	for pos in tiles:
		var tile: Tile = tiles[pos]
		if tile.terrain_type == Tile.TerrainType.WATER or tile.terrain_type == Tile.TerrainType.LAVA:
			height_map[pos] = water_level
		elif tile.terrain_type == Tile.TerrainType.RIVER:
			height_map[pos] = water_level
	_render_all_tiles()

func place_terrain_object(pos: Vector2i, obj_str: String):
	if tiles.has(pos):
		tiles[pos].set_object(obj_str)

func place_object_template(origin: Vector2i, template_id: String):
	var tpl: Dictionary = DataLoader.terrain_objects_data.get(template_id, {})
	var objects: Array = tpl.get("objects", [])
	for obj in objects:
		var off = obj.get("offset", [0, 0])
		var pos = origin + Vector2i(int(off[0]), int(off[1]))
		var obj_type = obj.get("object", "")
		if obj_type != "":
			place_terrain_object(pos, obj_type)


## Places a kit prefab at a grid position. Tries to load the .tscn scene first;
## falls back to Tile.set_object() if no scene exists.
## rot_deg: rotation in degrees (0, 90, 180, 270)
func place_prefab(pos: Vector2i, prefab_id: String, rot_deg: int = 0) -> void:
	var scene_path: String = "res://prefabs/kit/%s.tscn" % prefab_id
	if ResourceLoader.exists(scene_path):
		var scene: PackedScene
		if prop_scene_cache.has(scene_path):
			scene = prop_scene_cache[scene_path]
		else:
			scene = ResourceLoader.load(scene_path) as PackedScene
			if scene:
				prop_scene_cache[scene_path] = scene
		if scene:
			var instance: Node3D = scene.instantiate() as Node3D
			if instance:
				var h: float = height_map.get(pos, 0.0)
				instance.position = Vector3(
					pos.x * TILE_SCALE,
					h,
					pos.y * TILE_SCALE
				)
				if rot_deg != 0:
					instance.rotation_degrees.y = float(rot_deg)
				if props_root == null:
					_setup_containers()
				props_root.add_child(instance)
				prop_nodes[pos] = instance
				# Also set the tile object for gameplay logic
				_set_tile_object_from_prefab(pos, prefab_id)
				return

	# Fallback: no scene found, use Tile.set_object()
	_set_tile_object_from_prefab(pos, prefab_id)


## Maps prefab IDs to Tile.set_object() strings for gameplay logic.
func _set_tile_object_from_prefab(pos: Vector2i, prefab_id: String) -> void:
	const MAP: Dictionary = {
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
	}
	var obj_str: String = MAP.get(prefab_id, "")
	if obj_str != "" and tiles.has(pos):
		tiles[pos].set_object(obj_str)


## Batch-places all props from a map data props array.
## Each prop: {prefab: string, pos: [x, y], rot: int}
func place_props(props: Array) -> void:
	for prop in props:
		if not (prop is Dictionary):
			continue
		var prefab_id: String = prop.get("prefab", "")
		if prefab_id == "":
			continue
		var pos_arr: Array = prop.get("pos", [0, 0])
		if pos_arr.size() < 2:
			continue
		var pos := Vector2i(int(pos_arr[0]), int(pos_arr[1]))
		var rot: int = int(prop.get("rot", 0))
		place_prefab(pos, prefab_id, rot)


# ─── 3D Tile Rendering ───────────────────────────────────────────────────────

func _render_all_tiles():
	# Clear existing
	for child in tiles_root.get_children():
		child.queue_free()
	tile_meshes.clear()
	highlight_meshes.clear()

	for pos in tiles:
		_create_tile_mesh(pos)

func _terrain_type_to_tex_key(tt) -> String:
	match tt:
		Tile.TerrainType.GRASS, Tile.TerrainType.OPEN:
			return "grass"
		Tile.TerrainType.DIRT:
			return "dirt"
		Tile.TerrainType.STONE, Tile.TerrainType.ROCK:
			return "stone"
		Tile.TerrainType.SAND:
			return "sand"
		Tile.TerrainType.SNOW:
			return "snow"
		Tile.TerrainType.WATER, Tile.TerrainType.RIVER:
			return "water"
		Tile.TerrainType.LAVA:
			return "lava"
		Tile.TerrainType.ICE:
			return "ice"
		Tile.TerrainType.RUINS:
			return "ruins"
		Tile.TerrainType.ROAD:
			return "road"
		Tile.TerrainType.FOREST:
			return "forest"
		Tile.TerrainType.ELEVATION, Tile.TerrainType.WALL:
			return "stone"
		Tile.TerrainType.FORT, Tile.TerrainType.VILLAGE, Tile.TerrainType.THRONE:
			return "stone"
		Tile.TerrainType.BRIDGE:
			return "dirt"
	return ""

func _create_tile_mesh(pos: Vector2i):
	var tile = tiles[pos]
	var h = height_map.get(pos, 0.0)

	# Main tile plane
	var mi = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(TILE_SCALE * 0.98, TILE_SCALE * 0.98)  # Narrow gap between tiles
	mi.mesh = plane

	# Material — use terrain texture if available, fallback to flat color
	var mat = StandardMaterial3D.new()
	var base_color: Color = tile.get_color()
	var tex_key: String = _terrain_type_to_tex_key(tile.terrain_type)
	if tex_key != "" and terrain_tex_cache.has(tex_key):
		mat.albedo_texture = terrain_tex_cache[tex_key]
		mat.albedo_color = Color.WHITE  # Let texture show through
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.uv1_scale = Vector3(1, 1, 1)
	else:
		# Fallback: flat color with variant offset
		var v: int = tile.terrain_variant
		match tile.terrain_type:
			Tile.TerrainType.FOREST, Tile.TerrainType.WATER, Tile.TerrainType.RUINS, \
			Tile.TerrainType.ELEVATION, Tile.TerrainType.WALL, Tile.TerrainType.FORT, \
			Tile.TerrainType.BRIDGE, Tile.TerrainType.VILLAGE, Tile.TerrainType.THRONE, \
			Tile.TerrainType.SAND, Tile.TerrainType.LAVA, Tile.TerrainType.RIVER, \
			Tile.TerrainType.ROAD:
				var offset: float = (v - 2) * 0.015
				base_color = Color(
					clampf(base_color.r + offset, 0.0, 1.0),
					clampf(base_color.g + offset * 0.8, 0.0, 1.0),
					clampf(base_color.b + offset * 0.6, 0.0, 1.0)
				)
		mat.albedo_color = base_color
	# Terrain-specific roughness and metallic
	match tile.terrain_type:
		Tile.TerrainType.DIRT, Tile.TerrainType.SAND:
			mat.roughness = 0.95
			mat.metallic = 0.0
		Tile.TerrainType.ICE:
			mat.roughness = 0.15
			mat.metallic = 0.35
		Tile.TerrainType.WATER, Tile.TerrainType.RIVER:
			mat.roughness = 0.2
			mat.metallic = 0.1
		Tile.TerrainType.STONE, Tile.TerrainType.ROCK:
			mat.roughness = 0.9
			mat.metallic = 0.02
		Tile.TerrainType.SNOW:
			mat.roughness = 0.75
			mat.metallic = 0.08
		Tile.TerrainType.LAVA:
			mat.roughness = 0.4
			mat.metallic = 0.0
			mat.emission_enabled = true
			mat.emission = Color(0.55, 0.12, 0.02)
			mat.emission_energy_multiplier = 0.4
		_:
			mat.roughness = 0.85
			mat.metallic = 0.05
	mi.material_override = mat

	mi.position = Vector3(pos.x * TILE_SCALE, h, pos.y * TILE_SCALE)
	mi.name = "Tile_%d_%d" % [pos.x, pos.y]
	tiles_root.add_child(mi)
	tile_meshes[pos] = mi

	# Road auto-tiling: curbs along non-road edges
	if tile.terrain_type == Tile.TerrainType.ROAD:
		# Override road surface material for smoother path look
		mat.roughness = 0.7
		mat.albedo_color = base_color.lightened(0.08)  # Slightly lighter gray-brown
		var road_dirs = [
			[Vector2i(0, -1), Vector3(0.0, 0.0, -0.45), 0.0],   # -Z edge
			[Vector2i(0,  1), Vector3(0.0, 0.0,  0.45), 0.0],   # +Z edge
			[Vector2i(-1, 0), Vector3(-0.45, 0.0, 0.0), PI/2],  # -X edge
			[Vector2i( 1, 0), Vector3( 0.45, 0.0, 0.0), PI/2],  # +X edge
		]
		for rd in road_dirs:
			if not _is_road_neighbor(pos, rd[0]):
				var curb = MeshInstance3D.new()
				var curb_mesh = BoxMesh.new()
				curb_mesh.size = Vector3(TILE_SCALE * 0.98, 0.04, 0.06)
				curb.mesh = curb_mesh
				var curb_mat = StandardMaterial3D.new()
				curb_mat.albedo_color = base_color.darkened(0.2)
				curb_mat.roughness = 0.85
				curb.material_override = curb_mat
				curb.position = Vector3(
					pos.x * TILE_SCALE + rd[1].x * TILE_SCALE,
					h + 0.02,
					pos.y * TILE_SCALE + rd[1].z * TILE_SCALE
				)
				curb.rotation.y = rd[2]
				tiles_root.add_child(curb)

	# Side faces only where this tile is higher than its neighbor (clean cliffs)
	_create_tile_sides(pos, h, tile.get_color())

	# Terrain object 3D representation
	if tile.terrain_object != Tile.TerrainObject.NONE:
		_create_terrain_object_3d(pos, tile, h)

	# Building warm lights for structures
	if tile.terrain_type in [Tile.TerrainType.FORT, Tile.TerrainType.VILLAGE] or \
		tile.terrain_object in [Tile.TerrainObject.HOUSE, Tile.TerrainObject.TOWER,
			Tile.TerrainObject.CHURCH]:
		_add_building_light(pos, h, tile)

func _create_tile_sides(pos: Vector2i, h: float, base_color: Color):
	var side_color = base_color.darkened(0.22)

	# Neighbor offsets: direction, face offset, face rotation
	var neighbors = [
		[Vector2i(0, 1),  Vector3(0, 0,  0.5), Vector3( PI/2, 0, 0)],   # front (+Z)
		[Vector2i(0, -1), Vector3(0, 0, -0.5), Vector3(-PI/2, 0, 0)],   # back  (-Z)
		[Vector2i(1, 0),  Vector3(0.5, 0, 0),  Vector3(0, 0, -PI/2)],   # right (+X)
		[Vector2i(-1, 0), Vector3(-0.5, 0, 0), Vector3(0, 0,  PI/2)],   # left  (-X)
	]

	for entry in neighbors:
		var n_pos: Vector2i = pos + entry[0]
		var n_h: float = height_map.get(n_pos, 0.0)
		var drop: float = h - n_h
		# Only draw a side face if this tile is taller than the neighbor
		if drop < 0.05:
			continue

		# Get neighbor color for lerping on slopes
		var n_color: Color = base_color
		if tiles.has(n_pos):
			n_color = tiles[n_pos].get_color()

		if drop > 0.05 and drop <= 0.5:
			# --- SLOPE: gentle height difference → angled plane ---
			var slope_mat = StandardMaterial3D.new()
			slope_mat.albedo_color = base_color.lerp(n_color, 0.5).darkened(0.08)
			slope_mat.roughness = 0.9
			var slope = MeshInstance3D.new()
			var slope_plane = PlaneMesh.new()
			# Slope connects the two heights across the tile edge
			var slope_length: float = sqrt(drop * drop + (TILE_SCALE * 0.475) * (TILE_SCALE * 0.475))
			slope_plane.size = Vector2(TILE_SCALE * 0.98, slope_length)
			slope.mesh = slope_plane
			slope.material_override = slope_mat
			# Position at midpoint between the two heights, at the edge
			slope.position = Vector3(
				pos.x * TILE_SCALE + entry[1].x * TILE_SCALE * 0.98,
				h - drop * 0.5,
				pos.y * TILE_SCALE + entry[1].z * TILE_SCALE * 0.98
			)
			# Angle the plane to connect the heights
			var slope_angle: float = atan2(drop, TILE_SCALE * 0.475)
			slope.rotation = entry[2]
			# Adjust rotation to tilt the plane along the slope
			if entry[0] == Vector2i(0, 1):
				slope.rotation.x = PI/2 - slope_angle
			elif entry[0] == Vector2i(0, -1):
				slope.rotation.x = -(PI/2 - slope_angle)
			elif entry[0] == Vector2i(1, 0):
				slope.rotation.z = -(PI/2 - slope_angle)
			elif entry[0] == Vector2i(-1, 0):
				slope.rotation.z = PI/2 - slope_angle
			tiles_root.add_child(slope)
		else:
			# --- CLIFF: large drop → vertical face with layered rock ledges ---
			var side_mat = StandardMaterial3D.new()
			side_mat.albedo_color = side_color
			side_mat.roughness = 0.9
			var side = MeshInstance3D.new()
			var side_plane = PlaneMesh.new()
			side_plane.size = Vector2(TILE_SCALE * 0.98, drop)
			side.mesh = side_plane
			side.material_override = side_mat
			side.position = Vector3(
				pos.x * TILE_SCALE + entry[1].x * TILE_SCALE * 0.98,
				h - drop * 0.5,
				pos.y * TILE_SCALE + entry[1].z * TILE_SCALE * 0.98
			)
			side.rotation = entry[2]
			tiles_root.add_child(side)

			# Horizontal ledge lines every 0.25 units for layered rock look
			var ledge_step: float = 0.25
			var current_y: float = n_h + ledge_step
			var v_offset: int = 0
			while current_y < h - 0.05:
				var ledge = MeshInstance3D.new()
				var ledge_mesh = PlaneMesh.new()
				ledge_mesh.size = Vector2(TILE_SCALE * 0.93, 0.06)
				ledge.mesh = ledge_mesh
				var ledge_mat = StandardMaterial3D.new()
				# Slight variation per ledge
				var ledge_darken: float = 0.15 + (v_offset % 3) * 0.04
				ledge_mat.albedo_color = side_color.darkened(ledge_darken)
				ledge_mat.roughness = 0.95
				ledge.material_override = ledge_mat
				ledge.position = Vector3(
					pos.x * TILE_SCALE + entry[1].x * TILE_SCALE * 0.96,
					current_y,
					pos.y * TILE_SCALE + entry[1].z * TILE_SCALE * 0.96
				)
				# Orient ledge flat, facing outward slightly
				ledge.rotation = entry[2]
				tiles_root.add_child(ledge)
				current_y += ledge_step
				v_offset += 1

			# Cliff edge trim: thin darkened strip along the top edge
			var trim = MeshInstance3D.new()
			var trim_mesh = PlaneMesh.new()
			trim_mesh.size = Vector2(TILE_SCALE * 0.98, 0.04)
			trim.mesh = trim_mesh
			var trim_mat = StandardMaterial3D.new()
			trim_mat.albedo_color = base_color.darkened(0.28)
			trim_mat.roughness = 0.9
			trim.material_override = trim_mat
			trim.position = Vector3(
				pos.x * TILE_SCALE + entry[1].x * TILE_SCALE * 0.98,
				h - 0.005,
				pos.y * TILE_SCALE + entry[1].z * TILE_SCALE * 0.98
			)
			trim.rotation = entry[2]
			tiles_root.add_child(trim)

func _create_terrain_object_3d(pos: Vector2i, tile: Tile, h: float):
	var obj_node = Node3D.new()
	obj_node.position = Vector3(pos.x * TILE_SCALE, h, pos.y * TILE_SCALE)

	match tile.terrain_object:
		Tile.TerrainObject.TREE_PINE, Tile.TerrainObject.TREE_OAK:
			# Trunk (cylinder approximated by box)
			var trunk = MeshInstance3D.new()
			var trunk_mesh = BoxMesh.new()
			trunk_mesh.size = Vector3(0.08, 0.4, 0.08)
			trunk.mesh = trunk_mesh
			var trunk_mat = StandardMaterial3D.new()
			trunk_mat.albedo_color = Color(0.35, 0.22, 0.08)
			trunk.material_override = trunk_mat
			trunk.position.y = 0.2
			obj_node.add_child(trunk)
			# Canopy (sphere)
			var canopy = MeshInstance3D.new()
			var canopy_mesh = SphereMesh.new()
			canopy_mesh.radius = 0.25 if tile.terrain_object == Tile.TerrainObject.TREE_OAK else 0.18
			canopy_mesh.height = 0.5 if tile.terrain_object == Tile.TerrainObject.TREE_OAK else 0.6
			canopy.mesh = canopy_mesh
			var canopy_mat = StandardMaterial3D.new()
			canopy_mat.albedo_color = Color(0.08, 0.30, 0.06)
			canopy.material_override = canopy_mat
			canopy.position.y = 0.5
			obj_node.add_child(canopy)

		Tile.TerrainObject.BUSH:
			var bush = MeshInstance3D.new()
			var bush_mesh = SphereMesh.new()
			bush_mesh.radius = 0.18
			bush_mesh.height = 0.25
			bush.mesh = bush_mesh
			var bush_mat = StandardMaterial3D.new()
			bush_mat.albedo_color = Color(0.10, 0.30, 0.08)
			bush.material_override = bush_mat
			bush.position.y = 0.12
			obj_node.add_child(bush)

		Tile.TerrainObject.RUINS_PILLAR:
			var pillar = MeshInstance3D.new()
			var pillar_mesh = BoxMesh.new()
			pillar_mesh.size = Vector3(0.12, 0.6, 0.12)
			pillar.mesh = pillar_mesh
			var pillar_mat = StandardMaterial3D.new()
			pillar_mat.albedo_color = Color(0.42, 0.38, 0.32)
			pillar.material_override = pillar_mat
			pillar.position.y = 0.3
			obj_node.add_child(pillar)

		Tile.TerrainObject.HOUSE:
			# Wall
			var wall = MeshInstance3D.new()
			var wall_mesh = BoxMesh.new()
			wall_mesh.size = Vector3(0.5, 0.35, 0.4)
			wall.mesh = wall_mesh
			var wall_mat = StandardMaterial3D.new()
			wall_mat.albedo_color = Color(0.40, 0.35, 0.25)
			wall.material_override = wall_mat
			wall.position.y = 0.175
			obj_node.add_child(wall)
			# Roof (using a prism approximated by rotated box)
			var roof = MeshInstance3D.new()
			var roof_mesh = PrismMesh.new()
			roof_mesh.size = Vector3(0.55, 0.2, 0.45)
			roof.mesh = roof_mesh
			var roof_mat = StandardMaterial3D.new()
			roof_mat.albedo_color = Color(0.50, 0.22, 0.08)
			roof.material_override = roof_mat
			roof.position.y = 0.45
			obj_node.add_child(roof)

		Tile.TerrainObject.TOWER:
			var tower = MeshInstance3D.new()
			var tower_mesh = BoxMesh.new()
			tower_mesh.size = Vector3(0.25, 0.8, 0.25)
			tower.mesh = tower_mesh
			var tower_mat = StandardMaterial3D.new()
			tower_mat.albedo_color = Color(0.35, 0.32, 0.28)
			tower.material_override = tower_mat
			tower.position.y = 0.4
			obj_node.add_child(tower)

		Tile.TerrainObject.STATUE:
			var base = MeshInstance3D.new()
			var base_mesh = BoxMesh.new()
			base_mesh.size = Vector3(0.2, 0.1, 0.2)
			base.mesh = base_mesh
			var base_mat = StandardMaterial3D.new()
			base_mat.albedo_color = Color(0.45, 0.42, 0.38)
			base.material_override = base_mat
			base.position.y = 0.05
			obj_node.add_child(base)
			var figure = MeshInstance3D.new()
			var fig_mesh = BoxMesh.new()
			fig_mesh.size = Vector3(0.1, 0.35, 0.1)
			figure.mesh = fig_mesh
			figure.material_override = base_mat
			figure.position.y = 0.275
			obj_node.add_child(figure)

		Tile.TerrainObject.ROCK_SMALL:
			# 2-3 small rocks at slightly different offsets
			var rock_offsets = [Vector3(-0.1, 0.0, 0.05), Vector3(0.08, 0.0, -0.06), Vector3(0.0, 0.0, 0.1)]
			var rock_radii = [0.08, 0.10, 0.12]
			var rock_count: int = 2 + (tile.terrain_variant % 2)  # 2 or 3
			for ri in range(rock_count):
				var rock = MeshInstance3D.new()
				var rock_mesh = SphereMesh.new()
				rock_mesh.radius = rock_radii[ri]
				rock_mesh.height = rock_radii[ri] * 1.6
				rock.mesh = rock_mesh
				var rock_mat = StandardMaterial3D.new()
				rock_mat.albedo_color = Color(0.38 + ri * 0.02, 0.36 + ri * 0.02, 0.34 + ri * 0.01)
				rock_mat.roughness = 0.92
				rock.material_override = rock_mat
				rock.position = rock_offsets[ri]
				rock.position.y = rock_radii[ri] * 0.6
				obj_node.add_child(rock)

		Tile.TerrainObject.ROCK_LARGE:
			var big_rock = MeshInstance3D.new()
			var big_rock_mesh = SphereMesh.new()
			big_rock_mesh.radius = 0.25
			big_rock_mesh.height = 0.3  # Squashed vertically
			big_rock.mesh = big_rock_mesh
			var big_rock_mat = StandardMaterial3D.new()
			big_rock_mat.albedo_color = Color(0.28, 0.26, 0.24)
			big_rock_mat.roughness = 0.95
			big_rock.material_override = big_rock_mat
			big_rock.position.y = 0.15
			obj_node.add_child(big_rock)

		Tile.TerrainObject.LOG:
			var log_mi = MeshInstance3D.new()
			var log_mesh = CylinderMesh.new()
			log_mesh.top_radius = 0.06
			log_mesh.bottom_radius = 0.06
			log_mesh.height = 0.6
			log_mi.mesh = log_mesh
			var log_mat = StandardMaterial3D.new()
			log_mat.albedo_color = Color(0.32, 0.22, 0.10)
			log_mat.roughness = 0.88
			log_mi.material_override = log_mat
			# Rotate to lie flat (horizontal)
			log_mi.rotation.z = PI / 2
			log_mi.position.y = 0.07  # Slightly elevated off ground
			obj_node.add_child(log_mi)

		Tile.TerrainObject.ROOT:
			# 3-4 thin box pieces radiating from center at ground level
			var root_count: int = 3 + (tile.terrain_variant % 2)  # 3 or 4
			var root_angles: Array = [0.0, PI * 0.6, PI * 1.2, PI * 1.7]
			var root_lengths: Array = [0.25, 0.3, 0.22, 0.18]
			for ri in range(root_count):
				var root_piece = MeshInstance3D.new()
				var root_mesh = BoxMesh.new()
				root_mesh.size = Vector3(root_lengths[ri], 0.02, 0.03)
				root_piece.mesh = root_mesh
				var root_mat = StandardMaterial3D.new()
				root_mat.albedo_color = Color(0.22, 0.14, 0.06)
				root_mat.roughness = 0.9
				root_piece.material_override = root_mat
				root_piece.position.y = 0.01
				root_piece.position.x = cos(root_angles[ri]) * root_lengths[ri] * 0.4
				root_piece.position.z = sin(root_angles[ri]) * root_lengths[ri] * 0.4
				root_piece.rotation.y = root_angles[ri]
				obj_node.add_child(root_piece)

		Tile.TerrainObject.RUINS_WALL:
			# Main wall section
			var rwall = MeshInstance3D.new()
			var rwall_mesh = BoxMesh.new()
			rwall_mesh.size = Vector3(0.7, 0.5, 0.1)
			rwall.mesh = rwall_mesh
			var rwall_mat = StandardMaterial3D.new()
			rwall_mat.albedo_color = Color(0.38, 0.36, 0.32)
			rwall_mat.roughness = 0.92
			rwall.material_override = rwall_mat
			rwall.position.y = 0.25
			obj_node.add_child(rwall)
			# Jagged top: 2-3 smaller boxes at different heights
			var jagged_pieces = [
				Vector3(-0.2, 0.55, 0.0), Vector3(0.12, 0.52, 0.0), Vector3(0.28, 0.48, 0.0)
			]
			var jagged_sizes = [
				Vector3(0.12, 0.1, 0.1), Vector3(0.15, 0.06, 0.1), Vector3(0.10, 0.08, 0.1)
			]
			var jagged_count: int = 2 + (tile.terrain_variant % 2)
			for ji in range(jagged_count):
				var jag = MeshInstance3D.new()
				var jag_mesh = BoxMesh.new()
				jag_mesh.size = jagged_sizes[ji]
				jag.mesh = jag_mesh
				jag.material_override = rwall_mat
				jag.position = jagged_pieces[ji]
				obj_node.add_child(jag)

		Tile.TerrainObject.WOOD_WALL:
			var wwall = MeshInstance3D.new()
			var wwall_mesh = BoxMesh.new()
			wwall_mesh.size = Vector3(0.8, 0.6, 0.08)
			wwall.mesh = wwall_mesh
			var wwall_mat = StandardMaterial3D.new()
			wwall_mat.albedo_color = Color(0.42, 0.30, 0.16)
			wwall_mat.roughness = 0.88
			wwall.material_override = wwall_mat
			wwall.position.y = 0.3
			obj_node.add_child(wwall)

		Tile.TerrainObject.WOOD_CORNER:
			# Two perpendicular walls meeting at right angle
			var wc_mat = StandardMaterial3D.new()
			wc_mat.albedo_color = Color(0.42, 0.30, 0.16)
			wc_mat.roughness = 0.88
			# Wall A along X
			var wc_a = MeshInstance3D.new()
			var wc_a_mesh = BoxMesh.new()
			wc_a_mesh.size = Vector3(0.45, 0.6, 0.08)
			wc_a.mesh = wc_a_mesh
			wc_a.material_override = wc_mat
			wc_a.position = Vector3(-0.2, 0.3, -0.2)
			obj_node.add_child(wc_a)
			# Wall B along Z
			var wc_b = MeshInstance3D.new()
			var wc_b_mesh = BoxMesh.new()
			wc_b_mesh.size = Vector3(0.08, 0.6, 0.45)
			wc_b.mesh = wc_b_mesh
			wc_b.material_override = wc_mat
			wc_b.position = Vector3(-0.2, 0.3, -0.2)
			obj_node.add_child(wc_b)

		Tile.TerrainObject.ROOF_PIECE:
			var roof_p = MeshInstance3D.new()
			var roof_p_mesh = PrismMesh.new()
			roof_p_mesh.size = Vector3(TILE_SCALE * 0.85, 0.3, TILE_SCALE * 0.85)
			roof_p.mesh = roof_p_mesh
			var roof_p_mat = StandardMaterial3D.new()
			roof_p_mat.albedo_color = Color(0.48, 0.20, 0.08)
			roof_p_mat.roughness = 0.85
			roof_p.material_override = roof_p_mat
			roof_p.position.y = 0.15
			obj_node.add_child(roof_p)

		Tile.TerrainObject.DOOR_PIECE:
			# Door frame
			var door_frame = MeshInstance3D.new()
			var door_frame_mesh = BoxMesh.new()
			door_frame_mesh.size = Vector3(0.3, 0.5, 0.08)
			door_frame.mesh = door_frame_mesh
			var door_frame_mat = StandardMaterial3D.new()
			door_frame_mat.albedo_color = Color(0.38, 0.26, 0.14)
			door_frame_mat.roughness = 0.85
			door_frame.material_override = door_frame_mat
			door_frame.position.y = 0.25
			obj_node.add_child(door_frame)
			# Dark center (opening)
			var door_center = MeshInstance3D.new()
			var door_center_mesh = BoxMesh.new()
			door_center_mesh.size = Vector3(0.22, 0.4, 0.085)
			door_center.mesh = door_center_mesh
			var door_center_mat = StandardMaterial3D.new()
			door_center_mat.albedo_color = Color(0.06, 0.04, 0.03)
			door_center_mat.roughness = 0.95
			door_center.material_override = door_center_mat
			door_center.position.y = 0.22
			door_center.position.z = 0.002  # Slightly in front
			obj_node.add_child(door_center)

		Tile.TerrainObject.WINDOW_PIECE:
			# Window frame
			var win_frame = MeshInstance3D.new()
			var win_frame_mesh = BoxMesh.new()
			win_frame_mesh.size = Vector3(0.25, 0.25, 0.05)
			win_frame.mesh = win_frame_mesh
			var win_frame_mat = StandardMaterial3D.new()
			win_frame_mat.albedo_color = Color(0.36, 0.28, 0.18)
			win_frame_mat.roughness = 0.85
			win_frame.material_override = win_frame_mat
			win_frame.position.y = 0.3
			obj_node.add_child(win_frame)
			# Cross-shaped mullion: vertical bar
			var mullion_v = MeshInstance3D.new()
			var mullion_v_mesh = BoxMesh.new()
			mullion_v_mesh.size = Vector3(0.015, 0.22, 0.055)
			mullion_v.mesh = mullion_v_mesh
			mullion_v.material_override = win_frame_mat
			mullion_v.position.y = 0.3
			obj_node.add_child(mullion_v)
			# Cross-shaped mullion: horizontal bar
			var mullion_h = MeshInstance3D.new()
			var mullion_h_mesh = BoxMesh.new()
			mullion_h_mesh.size = Vector3(0.22, 0.015, 0.055)
			mullion_h.mesh = mullion_h_mesh
			mullion_h.material_override = win_frame_mat
			mullion_h.position.y = 0.3
			obj_node.add_child(mullion_h)
			# Warm yellow emissive center pane
			var win_pane = MeshInstance3D.new()
			var win_pane_mesh = BoxMesh.new()
			win_pane_mesh.size = Vector3(0.20, 0.20, 0.04)
			win_pane.mesh = win_pane_mesh
			var win_pane_mat = StandardMaterial3D.new()
			win_pane_mat.albedo_color = Color(0.85, 0.70, 0.30)
			win_pane_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			win_pane_mat.emission_enabled = true
			win_pane_mat.emission = Color(0.90, 0.72, 0.25)
			win_pane_mat.emission_energy_multiplier = 0.6
			win_pane.material_override = win_pane_mat
			win_pane.position.y = 0.3
			win_pane.position.z = -0.005  # Behind mullion
			obj_node.add_child(win_pane)

	tiles_root.add_child(obj_node)

# ─── Road & Building Helpers ─────────────────────────────────────────────────

## Check if the tile in a given direction from pos is a road or bridge (for auto-tiling)
func _is_road_neighbor(pos: Vector2i, dir: Vector2i) -> bool:
	var n_pos: Vector2i = pos + dir
	if not tiles.has(n_pos):
		return false
	var n_tile: Tile = tiles[n_pos]
	return n_tile.terrain_type == Tile.TerrainType.ROAD or n_tile.terrain_type == Tile.TerrainType.BRIDGE

## Add a warm point light for building/structure tiles
func _add_building_light(pos: Vector2i, h: float, tile: Tile) -> void:
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.55)  # Warm yellow-orange
	light.omni_range = 1.5
	light.light_energy = 0.4
	# Slightly higher energy for larger structures
	if tile.terrain_object == Tile.TerrainObject.TOWER:
		light.light_energy = 0.5
		light.omni_range = 2.0
	elif tile.terrain_object == Tile.TerrainObject.CHURCH:
		light.light_energy = 0.45
		light.omni_range = 1.8
	light.position = Vector3(pos.x * TILE_SCALE, h + 0.5, pos.y * TILE_SCALE)
	light.name = "BuildingLight_%d_%d" % [pos.x, pos.y]
	tiles_root.add_child(light)

# ─── Tile Updates ────────────────────────────────────────────────────────────

func refresh_tile(pos: Vector2i):
	if not tile_meshes.has(pos): return
	var mi = tile_meshes[pos]
	var tile = tiles[pos]
	var mat = mi.material_override as StandardMaterial3D
	if mat:
		mat.albedo_color = tile.get_color()

func refresh_all_tiles():
	for pos in tile_meshes:
		refresh_tile(pos)
	# Update anomaly decals when elemental states change
	if not anomaly_decals.is_empty():
		refresh_anomaly_decals()

# ─── Unit Rendering ──────────────────────────────────────────────────────────

func render_units():
	# Clear old
	for child in units_root.get_children():
		child.queue_free()
	unit_sprites.clear()
	hp_bar_meshes.clear()

	for unit in units_ref:
		if unit.is_alive():
			_create_unit_sprite(unit)

func _create_unit_sprite(unit):
	var pos = unit.grid_position
	var h = height_map.get(pos, 0.0)

	var sprite = Sprite3D.new()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.pixel_size = 0.018  # Scale pixels to world units
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS

	# Try to load sprite texture — check player cache, then enemy cache (by name and stripped suffix)
	var sprite_key = unit.unit_name.to_lower()
	var tex = sprite_cache.get(sprite_key, null)
	if tex == null:
		tex = enemy_sprite_cache.get(sprite_key, null)
	if tex == null:
		# Strip numeric suffix: "Grunt 1" → "grunt"
		var stripped = sprite_key.rstrip("0123456789 ")
		tex = enemy_sprite_cache.get(stripped, null)

	if tex != null:
		sprite.texture = tex
		if unit.has_acted and unit.is_player_unit:
			sprite.modulate = Color(0.5, 0.5, 0.6, 0.7)
	else:
		# Fallback: create a colored placeholder texture
		var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
		var col = unit.get_display_color()
		img.fill(col)
		# Draw border
		for i in 32:
			img.set_pixel(i, 0, Color.BLACK)
			img.set_pixel(i, 31, Color.BLACK)
			img.set_pixel(0, i, Color.BLACK)
			img.set_pixel(31, i, Color.BLACK)
		var fallback_tex = ImageTexture.create_from_image(img)
		sprite.texture = fallback_tex

	sprite.position = Vector3(pos.x * TILE_SCALE, h + 0.45, pos.y * TILE_SCALE)
	sprite.name = "Unit_%s" % unit.unit_name

	# Team color outline via a second sprite behind
	var outline = Sprite3D.new()
	outline.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	outline.pixel_size = sprite.pixel_size * 1.15
	outline.shaded = false
	var outline_img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var team_col = Color(0.18, 0.48, 0.92) if unit.is_player_unit else Color(0.82, 0.14, 0.14)
	if unit.has_acted and unit.is_player_unit:
		team_col = Color(0.3, 0.3, 0.4)
	outline_img.fill(team_col)
	outline.texture = ImageTexture.create_from_image(outline_img)
	outline.position = Vector3(0, 0, 0.01)  # Slightly behind
	outline.name = "Outline"
	sprite.add_child(outline)

	units_root.add_child(sprite)
	unit_sprites[unit] = sprite

	# HP bar
	_create_hp_bar(unit, sprite)

func _create_hp_bar(unit, parent_sprite: Sprite3D):
	var hp_bg = MeshInstance3D.new()
	var bg_mesh = PlaneMesh.new()
	bg_mesh.size = Vector2(0.5, 0.06)
	hp_bg.mesh = bg_mesh
	var bg_mat = StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0, 0, 0, 0.8)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hp_bg.material_override = bg_mat
	hp_bg.rotation.x = -PI/2  # Face camera-ish
	hp_bg.position = Vector3(0, -0.35, 0)
	hp_bg.name = "HPBarBG"

	var hp_fill = MeshInstance3D.new()
	var fill_mesh = PlaneMesh.new()
	var hpr = float(unit.stats.hp) / float(unit.stats.max_hp)
	fill_mesh.size = Vector2(0.48 * hpr, 0.04)
	hp_fill.mesh = fill_mesh
	var fill_mat = StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.15, 0.88, 0.15) if hpr > 0.5 else (Color(0.92, 0.58, 0.1) if hpr > 0.25 else Color(0.92, 0.12, 0.12))
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hp_fill.material_override = fill_mat
	hp_fill.rotation.x = -PI/2
	hp_fill.position = Vector3((hpr - 1.0) * 0.24, -0.35, -0.005)
	hp_fill.name = "HPBarFill"

	parent_sprite.add_child(hp_bg)
	parent_sprite.add_child(hp_fill)
	hp_bar_meshes[unit] = hp_fill

func update_unit_positions():
	for unit in units_ref:
		if not unit.is_alive():
			if unit_sprites.has(unit):
				unit_sprites[unit].queue_free()
				unit_sprites.erase(unit)
			continue
		if unit_sprites.has(unit):
			var pos = unit.grid_position
			var h = height_map.get(pos, 0.0)
			unit_sprites[unit].position = Vector3(pos.x * TILE_SCALE, h + 0.45, pos.y * TILE_SCALE)
			# Update HP bar
			if hp_bar_meshes.has(unit):
				var hp_fill = hp_bar_meshes[unit]
				var hpr = float(unit.stats.hp) / float(unit.stats.max_hp)
				var fill_mesh = hp_fill.mesh as PlaneMesh
				fill_mesh.size = Vector2(0.48 * hpr, 0.04)
				hp_fill.position.x = (hpr - 1.0) * 0.24
				var fill_mat = hp_fill.material_override as StandardMaterial3D
				if fill_mat:
					fill_mat.albedo_color = Color(0.15, 0.88, 0.15) if hpr > 0.5 else (Color(0.92, 0.58, 0.1) if hpr > 0.25 else Color(0.92, 0.12, 0.12))
			# Dim acted units
			if unit.has_acted and unit.is_player_unit:
				unit_sprites[unit].modulate = Color(0.5, 0.5, 0.6, 0.7)
			else:
				unit_sprites[unit].modulate = Color.WHITE
		else:
			_create_unit_sprite(unit)

# ─── Highlights ──────────────────────────────────────────────────────────────

func highlight_move(tiles_arr: Array):
	for p in tiles_arr:
		highlighted[p] = Color(0.20, 0.50, 1.0, 0.35)
	_refresh_highlights()

func highlight_selected(pos: Vector2i):
	highlighted[pos] = Color(1.0, 0.85, 0.0, 0.5)
	_refresh_highlights()

func highlight_attack(tiles_arr: Array):
	for p in tiles_arr:
		highlighted[p] = Color(0.90, 0.15, 0.15, 0.4)
	_refresh_highlights()

func highlight_heal(tiles_arr: Array):
	for p in tiles_arr:
		highlighted[p] = Color(0.20, 1.0, 0.50, 0.35)
	_refresh_highlights()

func clear_highlights():
	highlighted.clear()
	for pos in highlight_meshes:
		highlight_meshes[pos].queue_free()
	highlight_meshes.clear()

func _refresh_highlights():
	# Remove stale
	var to_remove: Array = []
	for pos in highlight_meshes:
		if not highlighted.has(pos):
			highlight_meshes[pos].queue_free()
			to_remove.append(pos)
	for pos in to_remove:
		highlight_meshes.erase(pos)

	# Add/update
	for pos in highlighted:
		var color = highlighted[pos]
		var h = height_map.get(pos, 0.0)
		if highlight_meshes.has(pos):
			var mi = highlight_meshes[pos]
			mi.position.y = h + 0.01
			(mi.material_override as StandardMaterial3D).albedo_color = color
		else:
			var mi = MeshInstance3D.new()
			var plane = PlaneMesh.new()
			plane.size = Vector2(TILE_SCALE * 0.92, TILE_SCALE * 0.92)
			mi.mesh = plane
			var mat = StandardMaterial3D.new()
			mat.albedo_color = color
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			mi.material_override = mat
			mi.position = Vector3(pos.x * TILE_SCALE, h + 0.01, pos.y * TILE_SCALE)
			tiles_root.add_child(mi)
			highlight_meshes[pos] = mi

# ─── Hover Highlight ─────────────────────────────────────────────────────────

var hover_mesh: MeshInstance3D = null
var hover_pos: Vector2i = Vector2i(-1, -1)

func highlight_hover(pos: Vector2i) -> void:
	var h: float = height_map.get(pos, 0.0)
	if hover_mesh == null:
		hover_mesh = MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(TILE_SCALE * 0.96, TILE_SCALE * 0.96)
		hover_mesh.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.25)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		hover_mesh.material_override = mat
		tiles_root.add_child(hover_mesh)
	hover_mesh.position = Vector3(pos.x * TILE_SCALE, h + 0.02, pos.y * TILE_SCALE)
	hover_mesh.visible = true
	hover_pos = pos

func clear_hover() -> void:
	if hover_mesh:
		hover_mesh.visible = false
	hover_pos = Vector2i(-1, -1)


# ─── Elevation Labels ───────────────────────────────────────────────────────

var elev_labels: Dictionary = {}  # Vector2i → Label3D
var elev_visible: bool = false

func toggle_elevation_labels(show: bool) -> void:
	elev_visible = show
	if show:
		_create_elevation_labels()
	else:
		_clear_elevation_labels()

func _create_elevation_labels() -> void:
	_clear_elevation_labels()
	for pos in tiles:
		var h: float = height_map.get(pos, 0.0)
		var steps: int = int(h / HEIGHT_STEP)
		if steps == 0:
			continue
		var lbl := Label3D.new()
		lbl.text = "%+d" % steps
		lbl.font_size = 32
		lbl.pixel_size = 0.01
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.modulate = Color(1.0, 0.9, 0.3, 0.85) if steps > 0 else Color(0.4, 0.7, 1.0, 0.85)
		lbl.position = Vector3(pos.x * TILE_SCALE, h + 0.3, pos.y * TILE_SCALE)
		tiles_root.add_child(lbl)
		elev_labels[pos] = lbl

func _clear_elevation_labels() -> void:
	for pos in elev_labels:
		elev_labels[pos].queue_free()
	elev_labels.clear()


# ─── Path Preview Line ─────────────────────────────────────────────────

## Draw a glowing path line from unit to target tile
func show_path_preview(path: Array, move_cost: int) -> void:
	clear_path_preview()
	if path.size() < 2:
		return
	# Draw line segments between consecutive tiles
	for i in range(path.size() - 1):
		var from_pos: Vector2i = path[i]
		var to_pos: Vector2i = path[i + 1]
		var from_h: float = height_map.get(from_pos, 0.0) + 0.04
		var to_h: float = height_map.get(to_pos, 0.0) + 0.04
		var from_3d := Vector3(from_pos.x * TILE_SCALE, from_h, from_pos.y * TILE_SCALE)
		var to_3d := Vector3(to_pos.x * TILE_SCALE, to_h, to_pos.y * TILE_SCALE)
		var segment := _create_line_segment(from_3d, to_3d, Color(0.3, 0.85, 1.0, 0.7), 0.06)
		vfx_root.add_child(segment)
		path_line_meshes.append(segment)
	# Show cost label at end of path
	var end_pos: Vector2i = path[path.size() - 1]
	var end_h: float = height_map.get(end_pos, 0.0)
	path_cost_label = Label3D.new()
	path_cost_label.text = "MOV %d" % move_cost
	path_cost_label.font_size = 36
	path_cost_label.pixel_size = 0.008
	path_cost_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	path_cost_label.no_depth_test = true
	path_cost_label.modulate = Color(0.3, 0.85, 1.0, 0.95)
	path_cost_label.position = Vector3(end_pos.x * TILE_SCALE, end_h + 0.55, end_pos.y * TILE_SCALE)
	vfx_root.add_child(path_cost_label)

func clear_path_preview() -> void:
	for mi in path_line_meshes:
		if is_instance_valid(mi):
			mi.queue_free()
	path_line_meshes.clear()
	if path_cost_label != null and is_instance_valid(path_cost_label):
		path_cost_label.queue_free()
		path_cost_label = null

func _create_line_segment(from: Vector3, to: Vector3, color: Color, width: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	# Build a flat quad strip along the path segment
	var dir := (to - from).normalized()
	var up := Vector3.UP
	var right := dir.cross(up).normalized() * width * 0.5
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, mat)
	im.surface_add_vertex(from - right)
	im.surface_add_vertex(from + right)
	im.surface_add_vertex(to - right)
	im.surface_add_vertex(to + right)
	im.surface_end()
	return mi


# ─── Tile Info Overlay (floating label on hovered tile) ─────────────────

## Show a floating info label on a tile with height, cover, terrain info
func show_tile_info(pos: Vector2i, extra_text: String = "") -> void:
	clear_tile_info()
	if not tiles.has(pos):
		return
	var tile: Tile = tiles[pos]
	var h: float = height_map.get(pos, 0.0)
	var steps: int = int(h / HEIGHT_STEP)
	# Build info string
	var parts: Array = []
	# Elevation
	if steps != 0:
		parts.append("H:%+d" % steps)
	# Terrain name
	parts.append(tile.get_terrain_name())
	# Cover/bonuses
	if tile.defense_bonus > 0:
		parts.append("DEF+%d" % tile.defense_bonus)
	if tile.avoid_bonus > 0:
		parts.append("AVO+%d" % tile.avoid_bonus)
	if tile.heal_bonus > 0:
		parts.append("HEAL+%d" % tile.heal_bonus)
	# Elemental state
	if tile.elemental_state != Tile.ElementalState.NEUTRAL:
		parts.append(_elemental_state_name(tile.elemental_state))
	if extra_text != "":
		parts.append(extra_text)
	var text: String = "  ".join(parts)
	tile_info_label = Label3D.new()
	tile_info_label.text = text
	tile_info_label.font_size = 28
	tile_info_label.pixel_size = 0.007
	tile_info_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tile_info_label.no_depth_test = true
	tile_info_label.outline_size = 8
	tile_info_label.outline_modulate = Color(0, 0, 0, 0.85)
	# Color based on content
	if tile.defense_bonus > 0 or tile.avoid_bonus > 0:
		tile_info_label.modulate = Color(0.3, 0.9, 1.0, 0.95)
	elif tile.elemental_state != Tile.ElementalState.NEUTRAL:
		tile_info_label.modulate = _anomaly_decal_color(tile.elemental_state)
		tile_info_label.modulate.a = 0.95
	else:
		tile_info_label.modulate = Color(0.85, 0.85, 0.85, 0.85)
	tile_info_label.position = Vector3(pos.x * TILE_SCALE, h + 0.40, pos.y * TILE_SCALE)
	vfx_root.add_child(tile_info_label)
	tile_info_pos = pos

func clear_tile_info() -> void:
	if tile_info_label != null and is_instance_valid(tile_info_label):
		tile_info_label.queue_free()
		tile_info_label = null
	tile_info_pos = Vector2i(-1, -1)

func _elemental_state_name(state: Tile.ElementalState) -> String:
	match state:
		Tile.ElementalState.FROZEN:      return "FROZEN"
		Tile.ElementalState.OVERGROWN:   return "OVERGROWN"
		Tile.ElementalState.CHARGED:     return "CHARGED"
		Tile.ElementalState.BLOODSOAKED: return "BLOODSOAKED"
		Tile.ElementalState.VOIDED:      return "VOIDED"
		Tile.ElementalState.RADIANT:     return "RADIANT"
		Tile.ElementalState.DARKENED:    return "DARKENED"
	return ""


# ─── Attack Forecast Labels ───────────────────────────────────────────

## Show mini forecast (hit%/dmg) on each valid attack target tile
func show_attack_forecast_labels(forecasts: Array) -> void:
	clear_attack_forecast_labels()
	for fc in forecasts:
		var pos: Vector2i = fc["pos"]
		var h: float = height_map.get(pos, 0.0)
		var lbl := Label3D.new()
		lbl.text = "%d%% %ddmg" % [fc["hit"], fc["dmg"]]
		lbl.font_size = 30
		lbl.pixel_size = 0.007
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.outline_size = 8
		lbl.outline_modulate = Color(0, 0, 0, 0.9)
		lbl.modulate = Color(1.0, 0.4, 0.35, 0.95)
		lbl.position = Vector3(pos.x * TILE_SCALE, h + 0.45, pos.y * TILE_SCALE)
		vfx_root.add_child(lbl)
		forecast_labels[pos] = lbl

func clear_attack_forecast_labels() -> void:
	for pos in forecast_labels:
		if is_instance_valid(forecast_labels[pos]):
			forecast_labels[pos].queue_free()
	forecast_labels.clear()


# ─── Cover Indicators ───────────────────────────────────────────────────────

var cover_indicators: Dictionary = {}  # Vector2i → MeshInstance3D
var anomaly_decals: Dictionary = {}    # Vector2i → MeshInstance3D

func show_cover_indicators() -> void:
	clear_cover_indicators()
	for pos in tiles:
		var tile: Tile = tiles[pos]
		if tile.defense_bonus > 0 and tile.terrain_object != Tile.TerrainObject.NONE:
			var h: float = height_map.get(pos, 0.0)
			var mi := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(0.15, 0.15)
			mi.mesh = plane
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.2, 0.8, 1.0, 0.7)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			mi.material_override = mat
			mi.position = Vector3(pos.x * TILE_SCALE + 0.35, h + 0.03, pos.y * TILE_SCALE - 0.35)
			tiles_root.add_child(mi)
			cover_indicators[pos] = mi

func clear_cover_indicators() -> void:
	for pos in cover_indicators:
		cover_indicators[pos].queue_free()
	cover_indicators.clear()


# ─── Anomaly Decals ──────────────────────────────────────────────────────

## Shows semi-transparent colored overlays on tiles with active elemental states.
func show_anomaly_decals() -> void:
	clear_anomaly_decals()
	for pos in tiles:
		var tile: Tile = tiles[pos]
		if tile.elemental_state == Tile.ElementalState.NEUTRAL:
			continue
		var h: float = height_map.get(pos, 0.0)
		var mi := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(TILE_SCALE * 0.90, TILE_SCALE * 0.90)
		mi.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color = _anomaly_decal_color(tile.elemental_state)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.no_depth_test = true
		mi.material_override = mat
		mi.position = Vector3(pos.x * TILE_SCALE, h + 0.015, pos.y * TILE_SCALE)
		mi.name = "Anomaly_%d_%d" % [pos.x, pos.y]
		tiles_root.add_child(mi)
		anomaly_decals[pos] = mi

func clear_anomaly_decals() -> void:
	for pos in anomaly_decals:
		if is_instance_valid(anomaly_decals[pos]):
			anomaly_decals[pos].queue_free()
	anomaly_decals.clear()

func refresh_anomaly_decals() -> void:
	# Update existing decals or add/remove as elemental states change
	var to_remove: Array = []
	for pos in anomaly_decals:
		var tile: Tile = tiles[pos]
		if tile.elemental_state == Tile.ElementalState.NEUTRAL:
			if is_instance_valid(anomaly_decals[pos]):
				anomaly_decals[pos].queue_free()
			to_remove.append(pos)
		else:
			if is_instance_valid(anomaly_decals[pos]):
				var mat = anomaly_decals[pos].material_override as StandardMaterial3D
				if mat:
					mat.albedo_color = _anomaly_decal_color(tile.elemental_state)
	for pos in to_remove:
		anomaly_decals.erase(pos)
	# Check for new anomalies not yet decaled
	for pos in tiles:
		var tile: Tile = tiles[pos]
		if tile.elemental_state != Tile.ElementalState.NEUTRAL and not anomaly_decals.has(pos):
			var h: float = height_map.get(pos, 0.0)
			var mi := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(TILE_SCALE * 0.90, TILE_SCALE * 0.90)
			mi.mesh = plane
			var mat := StandardMaterial3D.new()
			mat.albedo_color = _anomaly_decal_color(tile.elemental_state)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mat.no_depth_test = true
			mi.material_override = mat
			mi.position = Vector3(pos.x * TILE_SCALE, h + 0.015, pos.y * TILE_SCALE)
			mi.name = "Anomaly_%d_%d" % [pos.x, pos.y]
			tiles_root.add_child(mi)
			anomaly_decals[pos] = mi

func _anomaly_decal_color(state: Tile.ElementalState) -> Color:
	match state:
		Tile.ElementalState.FROZEN:      return Color(0.5, 0.8, 1.0, 0.35)
		Tile.ElementalState.OVERGROWN:   return Color(0.1, 0.6, 0.15, 0.30)
		Tile.ElementalState.CHARGED:     return Color(0.9, 0.85, 0.1, 0.30)
		Tile.ElementalState.BLOODSOAKED: return Color(0.7, 0.05, 0.05, 0.30)
		Tile.ElementalState.VOIDED:      return Color(0.3, 0.0, 0.5, 0.35)
		Tile.ElementalState.RADIANT:     return Color(1.0, 0.95, 0.6, 0.25)
		Tile.ElementalState.DARKENED:    return Color(0.1, 0.02, 0.15, 0.35)
	return Color(1.0, 1.0, 1.0, 0.0)


# ─── Flash Effects ───────────────────────────────────────────────────────────

var flash_tiles: Dictionary = {}  # Vector2i → {mesh, timer, max_timer}

func flash(pos: Vector2i, color: Color, duration: float = 0.4):
	var h = height_map.get(pos, 0.0)
	# Remove existing flash
	if flash_tiles.has(pos) and is_instance_valid(flash_tiles[pos]["mesh"]):
		flash_tiles[pos]["mesh"].queue_free()

	var mi = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(TILE_SCALE * 0.94, TILE_SCALE * 0.94)
	mi.mesh = plane
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mi.material_override = mat
	mi.position = Vector3(pos.x * TILE_SCALE, h + 0.02, pos.y * TILE_SCALE)
	vfx_root.add_child(mi)
	flash_tiles[pos] = {"mesh": mi, "timer": duration, "max_timer": duration}

func pop_damage(pos: Vector2i, text: String, color: Color = Color.WHITE, duration: float = 0.9):
	var h = height_map.get(pos, 0.0)
	var label = Label3D.new()
	label.text = text
	label.font_size = 48
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(pos.x * TILE_SCALE, h + 0.8, pos.y * TILE_SCALE)
	label.no_depth_test = true
	vfx_root.add_child(label)
	damage_pops.append({"label": label, "timer": duration, "max_timer": duration})

func _process(delta: float):
	# Flash decay
	var flash_expired: Array = []
	for pos in flash_tiles:
		var data = flash_tiles[pos]
		data["timer"] -= delta
		if is_instance_valid(data["mesh"]):
			var mat = data["mesh"].material_override as StandardMaterial3D
			if mat:
				mat.albedo_color.a = clampf(data["timer"] / data["max_timer"], 0.0, 0.8)
		if data["timer"] <= 0.0:
			flash_expired.append(pos)
	for p in flash_expired:
		if is_instance_valid(flash_tiles[p]["mesh"]):
			flash_tiles[p]["mesh"].queue_free()
		flash_tiles.erase(p)

	# Damage pop decay
	var i = damage_pops.size() - 1
	while i >= 0:
		var pop = damage_pops[i]
		pop["timer"] -= delta
		if is_instance_valid(pop["label"]):
			var progress = 1.0 - pop["timer"] / pop["max_timer"]
			pop["label"].position.y += delta * 1.5  # Float upward
			pop["label"].modulate.a = clampf(pop["timer"] / pop["max_timer"] * 1.5, 0.0, 1.0)
		if pop["timer"] <= 0.0:
			if is_instance_valid(pop["label"]):
				pop["label"].queue_free()
			damage_pops.remove_at(i)
		i -= 1

# ─── Attack Animations ──────────────────────────────────────────────────────

func animate_attack(attacker, defender) -> void:
	if not unit_sprites.has(attacker): return
	var sprite = unit_sprites[attacker]
	var start_pos = sprite.position
	var def_pos = unit_sprites[defender].position if unit_sprites.has(defender) else start_pos
	var direction = (def_pos - start_pos).normalized()
	var slide_dist = 0.4

	var tween = create_tween()
	tween.tween_property(sprite, "position", start_pos + direction * slide_dist, 0.12)
	await tween.finished

	flash(defender.grid_position, Color(1.0, 1.0, 1.0, 0.9), 0.15)
	await get_tree().create_timer(0.08).timeout

	var tween2 = create_tween()
	tween2.tween_property(sprite, "position", start_pos, 0.1)
	await tween2.finished

func animate_hit_recoil(unit) -> void:
	if not unit_sprites.has(unit): return
	var sprite = unit_sprites[unit]
	var base = sprite.position
	var recoil = Vector3(0.06, 0, 0)
	var tween = create_tween()
	tween.tween_property(sprite, "position", base + recoil, 0.04)
	tween.tween_property(sprite, "position", base - recoil, 0.04)
	tween.tween_property(sprite, "position", base, 0.04)
	await tween.finished

# ─── Movement Range (Dijkstra) — same logic as 2D ────────────────────────────

func get_movement_range(start: Vector2i, move_range: int, unit_element: String = "") -> Array:
	var reachable: Array = []
	var cost_map: Dictionary = {start: 0}
	var prev_map: Dictionary = {}           # parent tracking for path reconstruction
	var queue: Array = [{pos = start, cost = 0}]
	var DIRS = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while not queue.is_empty():
		queue.sort_custom(func(a, b): return a.cost < b.cost)
		var cur = queue.pop_front()
		if cur.pos != start:
			reachable.append(cur.pos)
		for d in DIRS:
			var nxt: Vector2i = cur.pos + d
			if not tiles.has(nxt): continue
			var t: Tile = tiles[nxt]
			if not t.is_passable: continue
			if t.occupant != null:
				if not t.occupant.is_player_unit: continue
			var step = t.get_movement_cost(unit_element)
			# Height penalty: climbing costs extra
			var h_diff = absf(height_map.get(nxt, 0.0) - height_map.get(cur.pos, 0.0))
			if h_diff > HEIGHT_STEP + 0.01:
				step += int(h_diff / HEIGHT_STEP)
			var new_cost = cur.cost + step
			if new_cost <= move_range:
				if not cost_map.has(nxt) or cost_map[nxt] > new_cost:
					cost_map[nxt] = new_cost
					prev_map[nxt] = cur.pos
					queue.append({pos = nxt, cost = new_cost})
	# Store for path reconstruction
	move_cost_map = cost_map
	move_prev_map = prev_map
	return reachable

## Reconstruct shortest path from start to target using stored prev_map
func get_tile_path_to(target: Vector2i) -> Array:
	if not move_prev_map.has(target):
		return []
	var path: Array = [target]
	var cur = target
	while move_prev_map.has(cur):
		cur = move_prev_map[cur]
		path.push_front(cur)
	return path

## Get the movement cost to reach a tile (from last get_movement_range call)
func get_move_cost(pos: Vector2i) -> int:
	return move_cost_map.get(pos, -1)

# ─── Elemental Effects ───────────────────────────────────────────────────────

func apply_elemental_effect(origin: Vector2i, radius: int, element: String, duration: int = 3):
	for x in range(origin.x - radius, origin.x + radius + 1):
		for z in range(origin.y - radius, origin.y + radius + 1):
			if abs(x - origin.x) + abs(z - origin.y) <= radius:
				var p = Vector2i(x, z)
				if tiles.has(p):
					tiles[p].set_elemental_state(element, duration)
					flash(p, _elem_color(element), 0.8)
	refresh_all_tiles()

func tick_all_tiles():
	for p in tiles:
		tiles[p].tick_turn()
	refresh_all_tiles()
	refresh_anomaly_decals()

func _elem_color(elem: String) -> Color:
	match elem:
		"blood":    return Color(0.8, 0.1, 0.1, 0.7)
		"electric": return Color(1.0, 1.0, 0.2, 0.7)
		"void":     return Color(0.3, 0.0, 0.5, 0.7)
		"light":    return Color(1.0, 0.95, 0.5, 0.7)
		"dark":     return Color(0.2, 0.0, 0.3, 0.7)
		"ice":      return Color(0.6, 0.9, 1.0, 0.7)
		"plant":    return Color(0.2, 0.8, 0.2, 0.7)
		"god":      return Color(1.0, 1.0, 0.9, 0.9)
	return Color(1.0, 1.0, 1.0, 0.5)

# ─── Coordinate Helpers ─────────────────────────────────────────────────────

func world_to_tile(world_pos: Vector3) -> Vector2i:
	return Vector2i(int(round(world_pos.x / TILE_SCALE)), int(round(world_pos.z / TILE_SCALE)))

func tile_to_world(pos: Vector2i) -> Vector3:
	var h = height_map.get(pos, 0.0)
	return Vector3(pos.x * TILE_SCALE, h, pos.y * TILE_SCALE)

func is_valid_tile(pos: Vector2i) -> bool:
	return tiles.has(pos) and pos.x >= 0 and pos.y >= 0

## Check if line of sight exists between two tiles (Bresenham walk).
## Returns false if any intermediate tile has blocks_los == true.
## Adjacent tiles (dist 1) always have LoS. Start/end tiles ignored.
## Damage the destructible object at a tile. Returns true if destroyed.
## Removes the prop visual if the object breaks.
func damage_object_at(pos: Vector2i, amount: int = 1) -> bool:
	if not tiles.has(pos):
		return false
	var tile: Tile = tiles[pos]
	if not tile.is_destructible():
		return false
	var destroyed: bool = tile.damage_object(amount)
	if destroyed:
		# Remove prop visual
		if prop_nodes.has(pos):
			prop_nodes[pos].queue_free()
			prop_nodes.erase(pos)
		# Flash effect
		flash(pos, Color(0.8, 0.5, 0.1, 0.8), 0.5)
		pop_damage(pos, "BREAK", Color(0.9, 0.6, 0.2))
	return destroyed

func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var dist = abs(to.x - from.x) + abs(to.y - from.y)
	if dist <= 1:
		return true
	# Bresenham line walk
	var dx: int = abs(to.x - from.x)
	var dz: int = abs(to.y - from.y)
	var sx: int = 1 if from.x < to.x else -1
	var sz: int = 1 if from.y < to.y else -1
	var err: int = dx - dz
	var cx: int = from.x
	var cz: int = from.y
	while true:
		if cx == to.x and cz == to.y:
			break
		var pos := Vector2i(cx, cz)
		# Skip start tile
		if pos != from:
			if tiles.has(pos) and tiles[pos].blocks_los:
				return false
		var e2: int = 2 * err
		if e2 > -dz:
			err -= dz
			cx += sx
		if e2 < dx:
			err += dx
			cz += sz
	return true

func get_tile_height(pos: Vector2i) -> float:
	return height_map.get(pos, 0.0)

# Compatibility: queue_redraw equivalent for 3D (update units)
func queue_redraw():
	update_unit_positions()
