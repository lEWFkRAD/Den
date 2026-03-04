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
	speak("awaken"); return true

# ─── Combat ───────────────────────────────────────────────────────────────────

func take_damage(amount: int, source_element: String) -> int:
	var modified = ElementRegistry.calculate_damage(amount, source_element, element)
	modified = max(1, modified)
	hp -= modified; hp = max(0, hp)
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

func get_phase_label() -> String:
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
