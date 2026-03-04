class_name Weapon
extends RefCounted

enum WeaponType { SWORD, LANCE, AXE, BOW, TOME, DAGGER, STAFF, GREATSWORD }
enum DamageType { PHYSICAL, MAGICAL }

var weapon_name:  String     = "Iron Sword"
var weapon_type:  WeaponType = WeaponType.SWORD
var damage_type:  DamageType = DamageType.PHYSICAL
var attack:       int        = 5
var hit:          int        = 90
var crit:         int        = 0
var min_range:    int        = 1
var max_range:    int        = 1
var uses:         int        = 30
var max_uses:     int        = 30
var element:      String     = ""   # Elemental tomes carry an element
var is_healing:   bool       = false
var heal_amount:  int        = 0

static func make(id: String) -> Weapon:
	var w = Weapon.new()
	match id:
		# ── Swords ───────────────────────────────────────────────────────────
		"iron_sword":
			w.weapon_name = "Iron Sword"; w.weapon_type = WeaponType.SWORD
			w.attack = 5; w.hit = 90; w.crit = 0; w.uses = 40
		"steel_sword":
			w.weapon_name = "Steel Sword"; w.weapon_type = WeaponType.SWORD
			w.attack = 8; w.hit = 80; w.crit = 0; w.uses = 30
		"silver_sword":
			w.weapon_name = "Silver Sword"; w.weapon_type = WeaponType.SWORD
			w.attack = 12; w.hit = 85; w.crit = 5; w.uses = 20

		# ── Lances ───────────────────────────────────────────────────────────
		"iron_lance":
			w.weapon_name = "Iron Lance"; w.weapon_type = WeaponType.LANCE
			w.attack = 7; w.hit = 80; w.crit = 0; w.uses = 35
		"steel_lance":
			w.weapon_name = "Steel Lance"; w.weapon_type = WeaponType.LANCE
			w.attack = 10; w.hit = 72; w.crit = 0; w.uses = 25
		"heavy_lance":
			w.weapon_name = "Heavy Lance"; w.weapon_type = WeaponType.LANCE
			w.attack = 14; w.hit = 60; w.crit = 0; w.uses = 20

		# ── Axes ─────────────────────────────────────────────────────────────
		"iron_axe":
			w.weapon_name = "Iron Axe"; w.weapon_type = WeaponType.AXE
			w.attack = 8; w.hit = 70; w.crit = 5; w.uses = 35
		"hand_axe":
			w.weapon_name = "Hand Axe"; w.weapon_type = WeaponType.AXE
			w.attack = 6; w.hit = 65; w.crit = 0
			w.min_range = 1; w.max_range = 2; w.uses = 20
		"berserker_axe":
			w.weapon_name = "Berserker Axe"; w.weapon_type = WeaponType.AXE
			w.attack = 16; w.hit = 55; w.crit = 10; w.uses = 15

		# ── Bows ─────────────────────────────────────────────────────────────
		"iron_bow":
			w.weapon_name = "Iron Bow"; w.weapon_type = WeaponType.BOW
			w.attack = 6; w.hit = 85; w.crit = 5
			w.min_range = 2; w.max_range = 3; w.uses = 35
		"steel_bow":
			w.weapon_name = "Steel Bow"; w.weapon_type = WeaponType.BOW
			w.attack = 9; w.hit = 78; w.crit = 5
			w.min_range = 2; w.max_range = 3; w.uses = 25
		"longbow":
			w.weapon_name = "Longbow"; w.weapon_type = WeaponType.BOW
			w.attack = 7; w.hit = 75; w.crit = 0
			w.min_range = 2; w.max_range = 4; w.uses = 20

		# ── Daggers ──────────────────────────────────────────────────────────
		"iron_dagger":
			w.weapon_name = "Iron Dagger"; w.weapon_type = WeaponType.DAGGER
			w.attack = 4; w.hit = 95; w.crit = 10; w.uses = 35
		"venomed_dagger":
			w.weapon_name = "Venomed Dagger"; w.weapon_type = WeaponType.DAGGER
			w.attack = 5; w.hit = 90; w.crit = 15; w.uses = 20

		# ── Tomes ────────────────────────────────────────────────────────────
		"fire_tome":
			w.weapon_name = "Fire Tome"; w.weapon_type = WeaponType.TOME
			w.damage_type = DamageType.MAGICAL; w.element = "blood"
			w.attack = 5; w.hit = 88; w.crit = 5
			w.min_range = 1; w.max_range = 2; w.uses = 30
		"void_tome":
			w.weapon_name = "Void Tome"; w.weapon_type = WeaponType.TOME
			w.damage_type = DamageType.MAGICAL; w.element = "void"
			w.attack = 7; w.hit = 80; w.crit = 5
			w.min_range = 1; w.max_range = 2; w.uses = 25
		"ice_tome":
			w.weapon_name = "Ice Tome"; w.weapon_type = WeaponType.TOME
			w.damage_type = DamageType.MAGICAL; w.element = "ice"
			w.attack = 6; w.hit = 85; w.crit = 5
			w.min_range = 1; w.max_range = 2; w.uses = 30
		"lightning_tome":
			w.weapon_name = "Lightning Tome"; w.weapon_type = WeaponType.TOME
			w.damage_type = DamageType.MAGICAL; w.element = "electric"
			w.attack = 5; w.hit = 90; w.crit = 10
			w.min_range = 1; w.max_range = 3; w.uses = 25
		"dark_tome":
			w.weapon_name = "Dark Tome"; w.weapon_type = WeaponType.TOME
			w.damage_type = DamageType.MAGICAL; w.element = "dark"
			w.attack = 8; w.hit = 75; w.crit = 5
			w.min_range = 1; w.max_range = 2; w.uses = 20

		# ── Staves ───────────────────────────────────────────────────────────
		"heal_staff":
			w.weapon_name = "Heal Staff"; w.weapon_type = WeaponType.STAFF
			w.damage_type = DamageType.MAGICAL; w.is_healing = true
			w.heal_amount = 12; w.attack = 0; w.hit = 100
			w.min_range = 1; w.max_range = 2; w.uses = 30
		"mend_staff":
			w.weapon_name = "Mend Staff"; w.weapon_type = WeaponType.STAFF
			w.damage_type = DamageType.MAGICAL; w.is_healing = true
			w.heal_amount = 20; w.attack = 0; w.hit = 100
			w.min_range = 1; w.max_range = 2; w.uses = 20
		"physic_staff":
			w.weapon_name = "Physic Staff"; w.weapon_type = WeaponType.STAFF
			w.damage_type = DamageType.MAGICAL; w.is_healing = true
			w.heal_amount = 10; w.attack = 0; w.hit = 100
			w.min_range = 1; w.max_range = 5; w.uses = 15

		# ── Greatswords ──────────────────────────────────────────────────────
		"greatsword":
			w.weapon_name = "Greatsword"; w.weapon_type = WeaponType.GREATSWORD
			w.attack = 14; w.hit = 75; w.crit = 5; w.uses = 25
		"divine_blade":
			w.weapon_name = "Divine Blade"; w.weapon_type = WeaponType.GREATSWORD
			w.element = "god"
			w.attack = 18; w.hit = 80; w.crit = 10; w.uses = 15

		_: # Default fallback
			w.weapon_name = "Broken Sword"; w.attack = 2; w.hit = 70

	w.max_uses = w.uses
	return w

func get_type_name() -> String:
	return ["Sword","Lance","Axe","Bow","Tome","Dagger","Staff","Greatsword"][weapon_type]

func is_out_of_uses() -> bool:
	return uses <= 0

func use_one():
	uses = max(0, uses - 1)

func get_color() -> Color:
	match weapon_type:
		WeaponType.SWORD:      return Color(0.4, 0.6, 1.0)
		WeaponType.LANCE:      return Color(0.4, 1.0, 0.5)
		WeaponType.AXE:        return Color(1.0, 0.45, 0.2)
		WeaponType.BOW:        return Color(0.9, 0.9, 0.2)
		WeaponType.TOME:       return Color(0.8, 0.3, 1.0)
		WeaponType.DAGGER:     return Color(0.5, 0.9, 0.9)
		WeaponType.STAFF:      return Color(1.0, 0.9, 0.4)
		WeaponType.GREATSWORD: return Color(0.9, 0.8, 0.6)
	return Color(1,1,1)
