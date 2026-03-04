class_name Kip
extends RefCounted

enum Phase { COMPANION, DEPLOYED, AWAKENED }

# ─── Identity ─────────────────────────────────────────────────────────────────
var kip_id:      String = ""
var kip_name:    String = "Unknown"
var element:     String = ""
var personality: Dictionary = {}
var lore:        String = ""

# ─── State ────────────────────────────────────────────────────────────────────
var current_phase:  Phase = Phase.COMPANION
var bonded_unit             = null
var hp:             int   = 20
var max_hp:         int   = 20
var has_acted:      bool  = false
var is_exhausted:   bool  = false
var awakening_used: bool  = false

# ─── Combat Stats ─────────────────────────────────────────────────────────────
var attack:      int = 6
var defense:     int = 3
var movement:    int = 4
var attack_range:int = 1    # Deployed phase range
var awakening_radius: int = 2

# ─── Evolution ───────────────────────────────────────────────────────────────
var is_evolved:      bool   = false
var evolution_name:  String = ""
var mutation_ability: String = ""
var mutation_description: String = ""

# Battle memory — persists across battles, tracks lifetime events
var battle_memory: Dictionary = {
	"kills_witnessed":      0,
	"damage_taken":         0,
	"damage_dealt":         0,
	"tiles_changed":        0,
	"allies_saved":         0,
	"allies_healed":        0,
	"total_hp_healed":      0,
	"turns_awakened":       0,
	"awakenings_survived":  0,
	"battles_fought":       0,
	"battles_witnessed":    0,
	"chain_hits":           0,
	"kip_kills":            0,
	"enemies_immobilized":  0,
	"enemies_debuffed":     0,
	"tiles_frozen":         0,
	"tiles_voided":         0,
	"plant_tiles_created":  0,
	"dark_tiles_created":   0,
	"radiant_tiles_created": 0,
	"charged_tiles_stood":  0,
	"blood_tiles_stood":    0,
	"frozen_tiles_stood":   0,
}

# ─── Load from JSON ──────────────────────────────────────────────────────────

func load_kip(id: String):
	kip_id = id
	var data: Dictionary = DataLoader.kips_data.get(id, {})
	if data.is_empty():
		kip_name = "Unknown Kip"
		return
	kip_name         = data.get("name", "Unknown")
	element          = data.get("element", "")
	hp               = int(data.get("hp", 20))
	max_hp           = hp
	attack           = int(data.get("attack", 6))
	defense          = int(data.get("defense", 3))
	movement         = int(data.get("movement", 4))
	attack_range     = int(data.get("attack_range", 1))
	awakening_radius = int(data.get("awakening_radius", 2))
	lore             = data.get("lore", "")
	personality      = data.get("personality", {})

# ─── Phase Transitions ────────────────────────────────────────────────────────

func deploy() -> bool:
	if current_phase != Phase.COMPANION: return false
	if is_exhausted:
		speak("collapse"); return false
	current_phase = Phase.DEPLOYED
	speak("deploy"); return true

func recall():
	if current_phase == Phase.DEPLOYED:
		current_phase = Phase.COMPANION
		speak("recall")

func awaken() -> bool:
	if current_phase != Phase.DEPLOYED: return false
	if awakening_used:
		speak("awaken_refused"); return false
	current_phase = Phase.AWAKENED
	awakening_used = true
	record_event("turns_awakened", 1)
	speak("awaken"); return true

# ─── Combat ───────────────────────────────────────────────────────────────────

func take_damage(amount: int, source_element: String) -> int:
	var modified = ElementRegistry.calculate_damage(amount, source_element, element)
	modified = max(1, modified)
	hp -= modified; hp = max(0, hp)
	record_event("damage_taken", modified)
	if hp <= 0:
		if current_phase == Phase.AWAKENED: _die()
		else: _collapse()
	elif hp < max_hp / 3:
		speak("low_hp")
	return modified

func _collapse():
	current_phase = Phase.COMPANION
	hp = max(1, max_hp / 4)
	is_exhausted = true
	has_acted    = true
	record_event("awakenings_survived", 1)
	speak("collapse")

func _die():
	speak("death")
	if bonded_unit and bonded_unit.has_method("on_kip_death"):
		bonded_unit.on_kip_death()

func is_alive() -> bool: return hp > 0

# ─── Personality ──────────────────────────────────────────────────────────────

func speak(context: String) -> String:
	if not personality.has(context): return ""
	var lines: Array = personality[context]
	if lines.is_empty(): return ""
	var line: String = lines[randi() % lines.size()]
	BattleState.kip_speaks.emit(kip_name, line)
	return line

# ─── Reset ────────────────────────────────────────────────────────────────────

func reset_battle():
	current_phase = Phase.COMPANION
	hp            = max_hp
	is_exhausted  = false
	awakening_used = false
	has_acted     = false
	battle_memory["battles_fought"] += 1

func get_phase_label() -> String:
	if is_evolved:
		match current_phase:
			Phase.COMPANION: return evolution_name
			Phase.DEPLOYED:  return evolution_name + " [Deployed]"
			Phase.AWAKENED:  return evolution_name + " [AWAKENED]"
	match current_phase:
		Phase.COMPANION: return "Companion"
		Phase.DEPLOYED:  return "Deployed"
		Phase.AWAKENED:  return "AWAKENED"
	return "?"

# ─── Awakening AoE Data ───────────────────────────────────────────────────────

func get_awakening_radius() -> int:
	return awakening_radius

func get_awakening_damage() -> int:
	return attack * 3

# ─── Battle Memory ───────────────────────────────────────────────────────────

func record_event(event_key: String, amount: int = 1):
	if battle_memory.has(event_key):
		battle_memory[event_key] += amount

func get_memory(key: String) -> int:
	return battle_memory.get(key, 0)

func get_memory_summary() -> String:
	var lines: Array = []
	lines.append("%s — %s" % [kip_name, "EVOLVED: %s" % evolution_name if is_evolved else element.to_upper()])
	lines.append("Battles: %d | Kills witnessed: %d" % [get_memory("battles_fought"), get_memory("kills_witnessed")])
	lines.append("Damage dealt: %d | Damage taken: %d" % [get_memory("damage_dealt"), get_memory("damage_taken")])
	lines.append("Tiles changed: %d | Awakenings survived: %d" % [get_memory("tiles_changed"), get_memory("awakenings_survived")])
	if get_memory("allies_saved") > 0:
		lines.append("Allies saved: %d" % get_memory("allies_saved"))
	return "\n".join(lines)

# ─── Evolution System ───────────────────────────────────────────────────────

func check_evolution() -> bool:
	if is_evolved: return false
	var evo_data: Dictionary = DataLoader.kip_evolutions_data.get(kip_id, {})
	if evo_data.is_empty(): return false

	var reqs: Dictionary = evo_data.get("requirements", {})
	for key in reqs:
		if get_memory(key) < int(reqs[key]):
			return false

	# All requirements met — evolve!
	_apply_evolution(evo_data)
	return true

func _apply_evolution(evo_data: Dictionary):
	is_evolved = true
	evolution_name = evo_data.get("evolution_name", kip_name)
	mutation_ability = evo_data.get("mutation_ability", "")
	mutation_description = evo_data.get("mutation_description", "")

	# Apply stat bonuses
	var bonuses: Dictionary = evo_data.get("stat_bonuses", {})
	max_hp           += int(bonuses.get("hp", 0))
	hp               += int(bonuses.get("hp", 0))
	attack           += int(bonuses.get("attack", 0))
	defense          += int(bonuses.get("defense", 0))
	movement         += int(bonuses.get("movement", 0))
	awakening_radius += int(bonuses.get("awakening_radius", 0))

	# Override personality lines
	var overrides: Dictionary = evo_data.get("personality_override", {})
	for key in overrides:
		personality[key] = overrides[key]

	lore = evo_data.get("description", lore)
	BattleState.kip_speaks.emit(kip_name, "...something has changed. I am %s now." % evolution_name)

func get_evolution_progress() -> Dictionary:
	var evo_data: Dictionary = DataLoader.kip_evolutions_data.get(kip_id, {})
	if evo_data.is_empty(): return {}
	var reqs: Dictionary = evo_data.get("requirements", {})
	var progress: Dictionary = {}
	for key in reqs:
		progress[key] = {
			"current": get_memory(key),
			"required": int(reqs[key]),
			"complete": get_memory(key) >= int(reqs[key])
		}
	return progress

func has_mutation(ability_name: String) -> bool:
	return is_evolved and mutation_ability == ability_name

# ─── Save / Load Memory ─────────────────────────────────────────────────────

func save_data() -> Dictionary:
	return {
		"kip_id": kip_id,
		"is_evolved": is_evolved,
		"evolution_name": evolution_name,
		"mutation_ability": mutation_ability,
		"battle_memory": battle_memory.duplicate()
	}

func load_save_data(data: Dictionary):
	battle_memory = data.get("battle_memory", battle_memory)
	is_evolved = data.get("is_evolved", false)
	if is_evolved:
		var evo_data: Dictionary = DataLoader.kip_evolutions_data.get(kip_id, {})
		if not evo_data.is_empty():
			_apply_evolution(evo_data)
