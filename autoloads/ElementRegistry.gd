extends Node

# ─── The Two Rings ────────────────────────────────────────────────────────────
# Divine Ring:  light → dark → void → god → light
# Mortal Ring:  blood → plant → ice → electric → blood

const RING_DOMINANCE: Dictionary = {
	"light":    "dark",
	"dark":     "void",
	"void":     "god",
	"god":      "light",
	"blood":    "plant",
	"plant":    "ice",
	"ice":      "electric",
	"electric": "blood"
}

# Cross-ring interactions: "attacker:defender" → winner element (or "" for neutral)
const CROSS_RING: Dictionary = {
	"god:blood":      "god",
	"void:ice":       "ice",
	"dark:electric":  "dark",
	"light:plant":    ""       # Mutual neutral — growth needs light
}

# ─── API ──────────────────────────────────────────────────────────────────────

func get_multiplier(attacker_element: String, defender_element: String) -> float:
	if attacker_element == "" or defender_element == "":
		return 1.0
	if attacker_element == defender_element:
		return 1.0

	# Check cross-ring table first
	var cross_key = attacker_element + ":" + defender_element
	var cross_key_rev = defender_element + ":" + attacker_element
	if CROSS_RING.has(cross_key):
		var winner = CROSS_RING[cross_key]
		if winner == attacker_element:
			return 1.5
		elif winner == defender_element:
			return 0.7
		return 1.0
	if CROSS_RING.has(cross_key_rev):
		var winner = CROSS_RING[cross_key_rev]
		if winner == attacker_element:
			return 1.5
		elif winner == defender_element:
			return 0.7
		return 1.0

	# Check ring dominance
	if RING_DOMINANCE.get(attacker_element, "") == defender_element:
		return 1.5
	if RING_DOMINANCE.get(defender_element, "") == attacker_element:
		return 0.7

	return 1.0

func calculate_damage(base_damage: int, attacker_element: String, defender_element: String) -> int:
	return int(base_damage * get_multiplier(attacker_element, defender_element))

func dominates(attacker: String, defender: String) -> bool:
	return get_multiplier(attacker, defender) > 1.0

func get_weakness_text(attacker: String, defender: String) -> String:
	var m = get_multiplier(attacker, defender)
	if m > 1.0:
		return "EFFECTIVE"
	elif m < 1.0:
		return "RESISTED"
	return ""
