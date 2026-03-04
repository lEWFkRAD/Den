class_name Weapon
extends RefCounted

enum WeaponType { SWORD, LANCE, AXE, BOW, TOME, DAGGER, STAFF, GREATSWORD }
enum DamageType { PHYSICAL, MAGICAL }

var weapon_id:    String     = ""
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

const TYPE_MAP: Dictionary = {
	"sword": WeaponType.SWORD, "lance": WeaponType.LANCE, "axe": WeaponType.AXE,
	"bow": WeaponType.BOW, "tome": WeaponType.TOME, "dagger": WeaponType.DAGGER,
	"staff": WeaponType.STAFF, "greatsword": WeaponType.GREATSWORD,
}

static func make(id: String) -> Weapon:
	var w = Weapon.new()
	w.weapon_id = id
	var data: Dictionary = DataLoader.weapons_data.get(id, {})
	if data.is_empty():
		w.weapon_name = "Broken Sword"; w.attack = 2; w.hit = 70
		w.max_uses = w.uses
		return w
	w.weapon_name = data.get("name", "Unknown")
	w.weapon_type = TYPE_MAP.get(data.get("type", "sword"), WeaponType.SWORD)
	w.damage_type = DamageType.MAGICAL if data.get("damage_type", "physical") == "magical" else DamageType.PHYSICAL
	w.attack    = int(data.get("attack", 5))
	w.hit       = int(data.get("hit", 80))
	w.crit      = int(data.get("crit", 0))
	w.min_range = int(data.get("min_range", 1))
	w.max_range = int(data.get("max_range", 1))
	w.uses      = int(data.get("uses", 30))
	w.element   = data.get("element", "")
	w.is_healing  = data.get("is_healing", false)
	w.heal_amount = int(data.get("heal_amount", 0))
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
