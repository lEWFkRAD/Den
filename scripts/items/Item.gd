class_name Item
extends RefCounted

enum ItemType { HEAL, KIP_RESTORE, STAT_BOOST, ELIXIR, PROMOTION }

var item_name:   String   = ""
var item_type:   ItemType = ItemType.HEAL
var description: String   = ""
var uses:        int      = 1
var max_uses:    int      = 1
var value:       int      = 0    # Heal amount or boost amount
var stat_target: String   = ""   # For stat boosts: "def", "res", etc.
var duration:    int      = 0    # For temporary boosts (turns)

static func make(id: String) -> Item:
	var it = Item.new()
	match id:
		"vulnerary":
			it.item_name = "Vulnerary"; it.item_type = ItemType.HEAL
			it.description = "Restores 10 HP. Three uses."
			it.uses = 3; it.max_uses = 3; it.value = 10
		"elixir":
			it.item_name = "Elixir"; it.item_type = ItemType.ELIXIR
			it.description = "Fully restores HP. One use."
			it.uses = 1; it.max_uses = 1; it.value = 9999
		"kip_salve":
			it.item_name = "Kip Salve"; it.item_type = ItemType.KIP_RESTORE
			it.description = "Restores exhausted Kip to Companion at 50% HP."
			it.uses = 1; it.max_uses = 1; it.value = 50
		"pure_water":
			it.item_name = "Pure Water"; it.item_type = ItemType.STAT_BOOST
			it.description = "Raises RES by 7 for 3 turns."
			it.uses = 3; it.max_uses = 3; it.value = 7
			it.stat_target = "resistance"; it.duration = 3
		"energy_drop":
			it.item_name = "Energy Drop"; it.item_type = ItemType.STAT_BOOST
			it.description = "Permanently raises STR by 2."
			it.uses = 1; it.max_uses = 1; it.value = 2
			it.stat_target = "strength"; it.duration = -1   # -1 = permanent
		_:
			it.item_name = "Unknown Item"
	return it

func use_on(unit) -> String:
	if uses <= 0:
		return "Out of uses."
	uses -= 1

	match item_type:
		ItemType.HEAL:
			var healed = min(unit.stats.max_hp - unit.stats.hp, value)
			unit.stats.hp = min(unit.stats.max_hp, unit.stats.hp + value)
			return "%s healed %d HP." % [unit.unit_name, healed]
		ItemType.ELIXIR:
			var healed = unit.stats.max_hp - unit.stats.hp
			unit.stats.hp = unit.stats.max_hp
			return "%s fully restored! (+%d HP)" % [unit.unit_name, healed]
		ItemType.KIP_RESTORE:
			if unit.bonded_kip == null:
				uses += 1  # refund
				return "No Kip to restore."
			var kip = unit.bonded_kip
			if not kip.is_exhausted:
				uses += 1
				return "%s is not exhausted." % kip.kip_name
			kip.is_exhausted = false
			kip.hp = max(1, kip.max_hp / 2)
			kip.current_phase = 0  # Back to companion
			return "%s restored!" % kip.kip_name
		ItemType.STAT_BOOST:
			if stat_target == "resistance":
				unit.stats.resistance += value
				return "RES +%d for %d turns." % [value, duration]
			elif stat_target == "strength":
				unit.stats.strength += value
				return "STR permanently +%d." % value
	return "Used %s." % item_name
