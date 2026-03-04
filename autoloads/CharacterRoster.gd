extends Node

# ─── Player Characters ────────────────────────────────────────────────────────
# Each entry: { name, class, kip_id, weapon_ids, item_ids, flavor }

const PLAYER_CHARS: Dictionary = {
	"aldric": {
		"name": "Aldric", "class": "Soldier",
		"kip": "scar",
		"weapons": ["steel_sword", "iron_sword"],
		"items": ["vulnerary"],
		"flavor": "A grizzled veteran who says little and means all of it. Scar chose him three weeks ago. He hasn't asked why."
	},
	"mira": {
		"name": "Mira", "class": "Archer",
		"kip": "bolt",
		"weapons": ["steel_bow"],
		"items": ["vulnerary"],
		"flavor": "Precise, impatient, and verbally dangerous. Bolt is her perfect match — both of them act before they think and it somehow keeps working."
	},
	"voss": {
		"name": "Voss", "class": "Mage",
		"kip": "null_kip",
		"weapons": ["void_tome", "dark_tome"],
		"items": ["pure_water"],
		"flavor": "Cold scholar. Studies null. Studies Null. Not sure anymore where one ends and the other begins."
	},
	"seren": {
		"name": "Seren", "class": "Healer",
		"kip": "solen",
		"weapons": ["physic_staff", "heal_staff"],
		"items": ["vulnerary", "elixir"],
		"flavor": "Steady, warm, and terrifyingly competent under pressure. Solen has been awake for longer than living memory. It found Seren in a field. It waited. She sat down. They talked until dawn."
	},
	"bram": {
		"name": "Bram", "class": "Knight",
		"kip": "thorn",
		"weapons": ["steel_lance", "iron_lance"],
		"items": ["vulnerary"],
		"flavor": "Immovable. Not because he can't move but because he has decided not to. Thorn approves of this. They have never had an argument."
	},
	"corvin": {
		"name": "Corvin", "class": "Rogue",
		"kip": "dusk",
		"weapons": ["venomed_dagger", "iron_dagger"],
		"items": ["vulnerary", "kip_salve"],
		"flavor": "Sardonic thief who steals from people he dislikes, which is most people. Dusk finds him entertaining. This is either a good sign or a terrible one."
	},
	"yael": {
		"name": "Yael", "class": "Mage",
		"kip": "sleet",
		"weapons": ["ice_tome", "lightning_tome"],
		"items": ["pure_water"],
		"flavor": "Calculating strategist who approaches battle like a proof. Sleet pointed out three errors in her last plan before the fight started. She fixed all three. They are very good together."
	},
	"lorn": {
		"name": "Lorn", "class": "Warden",
		"kip": "the_first",
		"weapons": ["divine_blade", "greatsword"],
		"items": ["elixir"],
		"flavor": "Nobody knows where Lorn came from. The First does. It isn't saying."
	}
}

# ─── Enemy Templates ──────────────────────────────────────────────────────────

const ENEMY_TYPES: Dictionary = {
	"grunt": {
		"name": "Grunt", "class": "Enemy",
		"weapons": ["iron_sword"], "items": [],
		"element": ""
	},
	"archer": {
		"name": "Scout", "class": "Enemy_Archer",
		"weapons": ["iron_bow"], "items": [],
		"element": ""
	},
	"heavy": {
		"name": "Ironhelm", "class": "Enemy_Heavy",
		"weapons": ["iron_lance"], "items": [],
		"element": ""
	},
	"mage": {
		"name": "Hexblade", "class": "Enemy_Mage",
		"weapons": ["dark_tome"], "items": [],
		"element": "dark"
	},
	"rogue": {
		"name": "Cutthroat", "class": "Enemy_Rogue",
		"weapons": ["iron_dagger"], "items": [],
		"element": ""
	},
	"blood_knight": {
		"name": "Blood Knight", "class": "Enemy_Knight",
		"weapons": ["berserker_axe"], "items": [],
		"element": "blood"
	},
	"void_warden": {
		"name": "Void Warden", "class": "Enemy_Warden",
		"weapons": ["void_tome"], "items": [],
		"element": "void"
	},
	"commander": {
		"name": "Commander Varek", "class": "Enemy_Commander",
		"weapons": ["heavy_lance", "iron_axe"], "items": ["vulnerary"],
		"element": ""
	}
}

# ─── Factory: Build a Unit from roster data ───────────────────────────────────

func build_player_unit(char_id: String, grid_pos: Vector2i) -> Unit:
	var data = PLAYER_CHARS.get(char_id, null)
	if data == null:
		push_error("CharacterRoster: unknown char_id " + char_id)
		return null

	var unit = Unit.new()
	unit.setup(grid_pos, true, data["class"], data["name"])
	unit.flavor_text = data.get("flavor", "")

	# Weapons
	for wid in data["weapons"]:
		var w = Weapon.make(wid)
		unit.weapons.append(w)
	if not unit.weapons.is_empty():
		unit.weapon = unit.weapons[0]

	# Items
	for iid in data["items"]:
		unit.items.append(Item.make(iid))

	# Kip
	var kip = build_kip(data["kip"])
	if kip:
		kip.bonded_unit = unit
		unit.bonded_kip  = kip
		unit.element     = kip.element

	return unit

func build_enemy_unit(enemy_type: String, grid_pos: Vector2i, suffix: String = "") -> Unit:
	var data = ENEMY_TYPES.get(enemy_type, ENEMY_TYPES["grunt"])
	var unit = Unit.new()
	var uname = data["name"] + (" " + suffix if suffix != "" else "")
	unit.setup(grid_pos, false, data["class"], uname)
	unit.element = data.get("element", "")

	for wid in data["weapons"]:
		var w = Weapon.make(wid)
		unit.weapons.append(w)
	if not unit.weapons.is_empty():
		unit.weapon = unit.weapons[0]

	for iid in data["items"]:
		unit.items.append(Item.make(iid))

	return unit

func build_kip(kip_id: String) -> Kip:
	var kip = Kip.new()
	kip.load_kip(kip_id)
	return kip
