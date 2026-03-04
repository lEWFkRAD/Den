extends Node

# ─── Weapon Triangle ─────────────────────────────────────────────────────────
# Sword > Axe > Lance > Sword
const WEAPON_TRIANGLE: Dictionary = {
	"SWORD_AXE":   1,    # sword beats axe
	"AXE_LANCE":   1,
	"LANCE_SWORD": 1,
	"AXE_SWORD":   -1,   # axe loses to sword
	"LANCE_AXE":   -1,
	"SWORD_LANCE": -1,
}

# ─── Elevation Constants ─────────────────────────────────────────────────────
# height_diff = attacker_height - defender_height (in world units, HEIGHT_STEP=0.5)
const ELEV_HIT_PER_STEP: int  = 10    # +10 hit per elevation step above defender
const ELEV_DMG_THRESHOLD: int = 2     # Need 2+ steps above for damage bonus
const ELEV_DMG_BONUS: int     = 1     # +1 damage when above by threshold
const HEIGHT_STEP: float      = 0.5   # Must match Grid3D.HEIGHT_STEP

# ─── Hit / Damage / Crit Calculation ─────────────────────────────────────────

## Get tile cover bonuses for a unit's current position.
## Returns {avoid: int, defense: int} including elemental state bonuses.
func _get_tile_cover(unit) -> Dictionary:
	var tile = BattleState.get_tile_at(unit.grid_position)
	if tile == null:
		return {"avoid": 0, "defense": 0}
	return {"avoid": tile.get_effective_avoid(), "defense": tile.get_effective_defense()}

func get_hit(attacker, weapon: Weapon, defender, height_diff: float = 0.0) -> int:
	if weapon == null: return 0
	var base_hit = attacker.stats.skill * 2 + attacker.stats.luck / 2 + weapon.hit
	var evade    = defender.stats.speed * 2 + defender.stats.luck / 2
	var triangle = _get_triangle_bonus(weapon, defender.weapon)
	# Elevation: +/- hit per step of height difference
	var elev_steps: int = int(height_diff / HEIGHT_STEP)
	var elev_mod: int = elev_steps * ELEV_HIT_PER_STEP
	# Tile cover: defender's avoid bonus reduces hit
	var cover = _get_tile_cover(defender)
	return clampi(base_hit - evade + triangle * 15 + elev_mod - cover["avoid"], 0, 100)

func get_damage(attacker, weapon: Weapon, defender, height_diff: float = 0.0) -> int:
	if weapon == null: return 0
	var raw: int
	# Tile cover: defender's defense bonus adds to effective defense
	var cover = _get_tile_cover(defender)
	if weapon.damage_type == Weapon.DamageType.MAGICAL:
		raw = attacker.stats.magic + weapon.attack - defender.stats.resistance - cover["defense"]
	else:
		raw = attacker.stats.strength + weapon.attack - defender.stats.defense - cover["defense"]
	# Weapon triangle gives +1/-1 damage
	raw += _get_triangle_bonus(weapon, defender.weapon)
	# Elevation: +1 damage when 2+ steps above defender
	var elev_steps: int = int(height_diff / HEIGHT_STEP)
	if elev_steps >= ELEV_DMG_THRESHOLD:
		raw += ELEV_DMG_BONUS
	# Element multiplier
	var atk_elem = weapon.element if weapon.element != "" else attacker.element
	raw = ElementRegistry.calculate_damage(raw, atk_elem, defender.element)
	return max(0, raw)

func get_crit(attacker, weapon: Weapon, defender) -> int:
	if weapon == null: return 0
	var base = attacker.stats.skill / 2 + weapon.crit
	var guard = defender.stats.luck
	return clampi(base - guard, 0, 100)

func can_double(attacker, defender) -> bool:
	return attacker.stats.speed >= defender.stats.speed + 5

func can_counter(defender, attacker_pos: Vector2i) -> bool:
	if defender.weapon == null: return false
	var dist = (defender.grid_position - attacker_pos).length()
	return dist >= defender.weapon.min_range and dist <= defender.weapon.max_range

# ─── Full Combat Forecast ─────────────────────────────────────────────────────

func get_forecast(attacker, defender, height_diff: float = 0.0) -> Dictionary:
	var w_atk = attacker.weapon
	var w_def = defender.weapon
	var dist  = (attacker.grid_position - defender.grid_position).length()

	var fc = {
		"atk_name":    attacker.unit_name,
		"def_name":    defender.unit_name,
		"atk_weapon":  w_atk.weapon_name if w_atk else "—",
		"def_weapon":  w_def.weapon_name if w_def else "—",
		"atk_damage":  get_damage(attacker, w_atk, defender, height_diff),
		"def_damage":  0,
		"atk_hit":     get_hit(attacker, w_atk, defender, height_diff),
		"def_hit":     0,
		"atk_crit":    get_crit(attacker, w_atk, defender),
		"def_crit":    0,
		"atk_double":  can_double(attacker, defender),
		"def_double":  false,
		"def_can_counter": can_counter(defender, attacker.grid_position),
		"height_diff": height_diff,
	}

	# Defender counter uses negative height_diff (they attack back uphill/downhill)
	if fc["def_can_counter"] and w_def != null:
		fc["def_damage"]  = get_damage(defender, w_def, attacker, -height_diff)
		fc["def_hit"]     = get_hit(defender, w_def, attacker, -height_diff)
		fc["def_crit"]    = get_crit(defender, w_def, attacker)
		fc["def_double"]  = can_double(defender, attacker)

	return fc

# ─── Combat Resolution ────────────────────────────────────────────────────────

func resolve_combat(attacker, defender, height_diff: float = 0.0) -> Array:
	var log: Array = []
	var fc = get_forecast(attacker, defender, height_diff)

	# Attacker strikes first (positive height_diff = attacker above)
	_strike(attacker, attacker.weapon, defender, log, height_diff)
	if not defender.is_alive(): return log

	# Defender counters (negative height_diff = defender below, attacking up)
	if fc["def_can_counter"]:
		_strike(defender, defender.weapon, attacker, log, -height_diff)
		if not attacker.is_alive(): return log

	# Follow-up: attacker doubles
	if fc["atk_double"]:
		_strike(attacker, attacker.weapon, defender, log, height_diff)
		if not defender.is_alive(): return log

	# Follow-up: defender doubles
	if fc["def_double"] and fc["def_can_counter"]:
		_strike(defender, defender.weapon, attacker, log, -height_diff)

	return log

func _strike(attacker, weapon: Weapon, defender, log: Array, height_diff: float = 0.0):
	if weapon == null:
		log.append("%s has no weapon!" % attacker.unit_name)
		return

	var hit_roll = randi() % 100
	var hit_chance = get_hit(attacker, weapon, defender, height_diff)

	if hit_roll >= hit_chance:
		log.append("%s missed %s." % [attacker.unit_name, defender.unit_name])
		return

	var damage = get_damage(attacker, weapon, defender, height_diff)
	var crit_roll = randi() % 100
	var is_crit = crit_roll < get_crit(attacker, weapon, defender)

	if is_crit:
		damage = int(damage * 3)
		log.append("CRITICAL! %s → %s: %d damage" % [attacker.unit_name, defender.unit_name, damage])
	else:
		log.append("%s → %s: %d damage" % [attacker.unit_name, defender.unit_name, damage])

	var actual = defender.take_damage(damage, weapon.element if weapon.element != "" else attacker.element)
	weapon.use_one()

	if not defender.is_alive():
		log.append("%s fell." % defender.unit_name)

# ─── Kip Combat ──────────────────────────────────────────────────────────────

func resolve_kip_attack(kip, defender) -> Array:
	var log: Array = []
	var base_damage = kip.attack - defender.stats.defense
	base_damage = ElementRegistry.calculate_damage(base_damage, kip.element, defender.element)
	base_damage = max(1, base_damage)

	# Kips hit 75% of the time from deployed phase (can miss)
	if randi() % 100 < 75:
		defender.take_damage(base_damage, kip.element)
		log.append("%s [%s] struck %s for %d!" % [kip.kip_name, kip.element.to_upper(), defender.unit_name, base_damage])
		if not defender.is_alive():
			log.append("%s destroyed." % defender.unit_name)
	else:
		log.append("%s missed %s." % [kip.kip_name, defender.unit_name])

	kip.has_acted = true
	return log

# ─── Weapon Triangle Helper ───────────────────────────────────────────────────

func _get_triangle_bonus(atk_weapon: Weapon, def_weapon) -> int:
	if atk_weapon == null or def_weapon == null: return 0
	var key = "%s_%s" % [atk_weapon.get_type_name().to_upper(), def_weapon.get_type_name().to_upper()]
	return WEAPON_TRIANGLE.get(key, 0)

# ─── Healable Check ──────────────────────────────────────────────────────────

func can_heal_target(healer, target) -> bool:
	if healer.weapon == null: return false
	if not healer.weapon.is_healing: return false
	var dist = (healer.grid_position - target.grid_position).length()
	return dist <= healer.weapon.max_range and target.is_player_unit == healer.is_player_unit

func resolve_heal(healer, target) -> String:
	var w = healer.weapon
	var healed = min(target.stats.max_hp - target.stats.hp, w.heal_amount + healer.stats.magic / 2)
	target.stats.hp = min(target.stats.max_hp, target.stats.hp + healed)
	w.use_one()
	return "%s healed %s for %d HP." % [healer.unit_name, target.unit_name, healed]
