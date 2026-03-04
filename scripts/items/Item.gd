class_name Item
extends RefCounted

enum ItemType { HEAL, KIP_RESTORE, STAT_BOOST, ELIXIR, PROMOTION }

var item_id:     String   = ""
var item_name:   String   = ""
var item_type:   ItemType = ItemType.HEAL
var description: String   = ""
var uses:        int      = 1
var max_uses:    int      = 1
var value:       int      = 0    # Heal amount or boost amount
var stat_target: String   = ""   # For stat boosts: "def", "res", etc.
var duration:    int      = 0    # For temporary boosts (turns)

const TYPE_STR_MAP: Dictionary = {
	"heal": ItemType.HEAL, "kip_restore": ItemType.KIP_RESTORE,
	"stat_boost": ItemType.STAT_BOOST, "elixir": ItemType.ELIXIR,
	"promotion": ItemType.PROMOTION,
}

static func make(id: String) -> Item:
	var it = Item.new()
	it.item_id = id
	var data: Dictionary = DataLoader.items_data.get(id, {})
	if data.is_empty():
		it.item_name = "Unknown Item"
		return it
	it.item_name   = data.get("name", "Unknown Item")
	it.item_type   = TYPE_STR_MAP.get(data.get("type", "heal"), ItemType.HEAL)
	it.description = data.get("description", "")
	it.uses        = int(data.get("uses", 1))
	it.max_uses    = it.uses
	it.value       = int(data.get("value", 0))
	it.stat_target = data.get("stat_target", "")
	it.duration    = int(data.get("duration", 0))
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
