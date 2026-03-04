class_name Kip
extends RefCounted

enum Phase { COMPANION, DEPLOYED, AWAKENED }

# ─── Identity ─────────────────────────────────────────────────────────────────
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

# ─── Load All 8 Kips ──────────────────────────────────────────────────────────

func load_kip(id: String):
	match id:

		"scar":
			kip_name = "Scar"; element = "blood"
			hp = 24; max_hp = 24; attack = 10; defense = 4; movement = 4; attack_range = 1
			lore = "Built for the front lines. It remembers the front lines. Still figuring out if it liked them."
			personality = {
				"deploy":  ["Let's go.", "Finally.", "Don't fall behind."],
				"recall":  ["Fine. Not done though.", "As you say."],
				"awaken":  ["CRIMSON TIDE."],
				"awaken_refused": ["Wrong angle.", "The timing isn't right."],
				"collapse": ["...That hurt. I'll remember that.", "Down. Not out."],
				"death":   ["Worth it."],
				"idle":    ["I can smell their fear.",
							"Your grip is wrong. Fix it.",
							"Tell me when you're ready. I've been ready.",
							"Good ground. Defensible. Not great.",
							"They're hesitating. Hit them now."],
				"kip_attack": ["Mine.", "Stay down.", "Back off.", "There."],
				"low_hp":  ["Not done.", "Keep moving.", "I don't stop."]
			}

		"bolt":
			kip_name = "Bolt"; element = "electric"
			hp = 17; max_hp = 17; attack = 8; defense = 2; movement = 5; attack_range = 2
			lore = "The most excitable Kip ever documented. Researchers who tried to study it were exhausted in under an hour."
			personality = {
				"deploy":  ["YES! Okay! Let's GO!", "Oh oh oh this is GOOD!",
							"I've been waiting since the LAST TURN!"],
				"recall":  ["Aw. Okay. That's fine. I'm fine."],
				"awaken":  ["FULL DISCHARGE!!!!"],
				"awaken_refused": ["Oh wait no the angle is wrong I see it."],
				"collapse": ["Ow. Ow ow ow. I'm okay! I'm okay."],
				"death":   ["Tell them I was very fast."],
				"idle":    ["Did you see that? That was me. I did that.",
							"Can we go faster? We could go faster.",
							"I counted eleven enemies. Then I stopped counting.",
							"I have SO many ideas right now.",
							"The static is SO good today.",
							"Wait do you hear that? That humming? That's me. I do that."],
				"kip_attack": ["ZAP!", "Gotcha!", "Again again!", "CONDUCTIVITY!"],
				"low_hp":  ["I'm fine! I'm totally fine! A bit on fire but fine!"]
			}

		"null_kip":
			kip_name = "Null"; element = "void"
			hp = 19; max_hp = 19; attack = 7; defense = 3; movement = 4; attack_range = 2
			lore = "Void Kips were not supposed to exist. Someone made them anyway. The Covenant considers them evidence of sin. Null considers the Covenant."
			personality = {
				"deploy":  ["Do you know what you're asking?", "Why this tile?",
							"Does it matter if I'm here or there?"],
				"recall":  ["Does it matter?", "Where would I go?"],
				"awaken":  ["NOTHING."],
				"awaken_refused": ["What would it change?", "Would it matter?"],
				"collapse": ["Is this pain?", "Interesting.", "...I felt that."],
				"death":   ["Was any of it real?", "Were you?"],
				"idle":    ["What do you want?", "Are you afraid of me?",
							"How do you know you exist right now?",
							"What are you looking at?",
							"What is the difference between an enemy and a stranger?",
							"I've been counting your heartbeats. Do you want to know the number?"],
				"kip_attack": ["Gone.", "Erased.", "What were you?"],
				"low_hp":  ["Does it matter?", "Interesting sensation."]
			}

		"solen":
			kip_name = "Solen"; element = "light"
			hp = 19; max_hp = 19; attack = 6; defense = 3; movement = 5; attack_range = 1
			lore = "One of the oldest active Kips. Has watched more tragedy than almost any living thing. Still warm. This is either the bravest thing imaginable or a form of armor."
			personality = {
				"deploy":  ["I'm here.", "Together then.", "I've got you."],
				"recall":  ["I'll be right here."],
				"awaken":  ["RADIANT HERALD."],
				"awaken_refused": ["There's still another way.", "Wait — I see an opening."],
				"collapse": ["It's okay. I'm okay.", "Still here. Still here."],
				"death":   ["It was worth it. All of it."],
				"idle":    ["The light holds.", "I believe in you.",
							"We can do this. I know we can.",
							"Stay close. Both of you.",
							"You're doing better than you think.",
							"I've seen worse. We made it through worse."],
				"kip_attack": ["Hold.", "Back.", "Not today.", "Stand firm."],
				"low_hp":  ["Still here.", "Don't worry about me.", "Keep fighting."]
			}

		"thorn":
			kip_name = "Thorn"; element = "plant"
			hp = 26; max_hp = 26; attack = 6; defense = 7; movement = 3; attack_range = 1
			lore = "Has stood on land that became three different kingdoms. Does not consider any of them its business."
			personality = {
				"deploy":  ["I will hold here.", "The ground knows me.", "Root down."],
				"recall":  ["I'll come back. The roots stay."],
				"awaken":  ["OVERGROWTH."],
				"awaken_refused": ["Wait. Not yet. Watch.", "The moment isn't here."],
				"collapse": ["...patience.", "It's not over. It's never over."],
				"death":   ["I've seen longer winters.", "Something always grows back."],
				"idle":    ["This soil is older than your kingdom.",
							"I've stood on worse ground.",
							"They'll regret pushing through the growth.",
							"Be still. Listen.",
							"The slow things win in the end.",
							"Your enemy is impatient. Let them be."],
				"kip_attack": ["Stay.", "Still.", "Down.", "Roots hold."],
				"low_hp":  ["...patience.", "I don't break easily."]
			}

		"dusk":
			kip_name = "Dusk"; element = "dark"
			hp = 21; max_hp = 21; attack = 9; defense = 3; movement = 5; attack_range = 2
			lore = "Sardonic, ancient, and watching. Has more context for current events than any historian alive. Shares it strategically."
			personality = {
				"deploy":  ["Oh, now you need me.", "As expected.", "Fine."],
				"recall":  ["Retreating already. How novel."],
				"awaken":  ["COLLAPSE."],
				"awaken_refused": ["Patience. They'll make a mistake. They always do."],
				"collapse": ["Hm. Well. That's irritating.", "Don't look so worried."],
				"death":   ["I remember everything. Even this."],
				"idle":    ["You're going to lose someone today. I can tell.",
							"I've seen this battlefield before. Different names.",
							"Don't get sentimental. It costs you.",
							"They're more afraid than they look. Everyone always is.",
							"The commander makes the same mistake every time.",
							"History rhymes. You'd know if you'd been paying attention."],
				"kip_attack": ["Predictable.", "Fading.", "Shadow takes you.", "As expected."],
				"low_hp":  ["Irritating.", "I've survived worse centuries."]
			}

		"sleet":
			kip_name = "Sleet"; element = "ice"
			hp = 21; max_hp = 21; attack = 8; defense = 5; movement = 4; attack_range = 2
			lore = "Precise. Correct. Unfailingly honest about both of those things."
			personality = {
				"deploy":  ["I'll hold the line.", "Positions confirmed."],
				"recall":  ["Efficient."],
				"awaken":  ["GLACIAL SEAL."],
				"awaken_refused": ["Not optimal. Noted for next time."],
				"collapse": ["...Recalibrating.", "Error margin exceeded. Adjusting."],
				"death":   ["The cold always wins. Eventually."],
				"idle":    ["Three enemy units within range. I've counted twice.",
							"You telegraphed that move. They saw it.",
							"Temperature's dropping. Good.",
							"Your footwork is improving. Marginally.",
							"The optimal path is two tiles left. I've run the numbers.",
							"Your instinct was correct. You ignored it. Don't."],
				"kip_attack": ["Contained.", "Frozen.", "Calculated.", "Immobilized."],
				"low_hp":  ["Suboptimal.", "Damage within acceptable range."]
			}

		"the_first":
			kip_name = "The First"; element = "god"
			hp = 30; max_hp = 30; attack = 15; defense = 8; movement = 4; attack_range = 1
			lore = "The last thing the Age of Making built. A record. A witness. A judge that hasn't given its verdict yet."
			personality = {
				"deploy":  ["..."],
				"recall":  ["..."],
				"awaken":  ["DIVINE DESCENT."],
				"awaken_refused": ["Not yet."],
				"collapse": ["Noted."],
				"death":   ["The record is incomplete."],
				"idle":    ["...", "...", "I remember you.", "...watching."],
				"kip_attack": [".", "..", "..."],
				"low_hp":  ["I have seen worse."]
			}

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
	match element:
		"blood":    return 3
		"plant":    return 3
		"ice":      return 3
		"electric": return 4
		"void":     return 2
		"light":    return 3
		"dark":     return 3
		"god":      return 1   # God's is a single massive hit — small AoE, enormous damage
	return 2

func get_awakening_damage() -> int:
	return attack * 3
