class_name UnitStats
extends RefCounted

var hp:         int = 20
var max_hp:     int = 20
var strength:   int = 5
var magic:      int = 3
var skill:      int = 4
var speed:      int = 4
var luck:       int = 3
var defense:    int = 4
var resistance: int = 2
var movement:   int = 5
var level:      int = 1

func load_class(unit_class: String):
	var data: Dictionary = DataLoader.classes_data.get(unit_class, {})
	if data.is_empty():
		# Fallback defaults
		hp=20; strength=5; magic=2; skill=4; speed=4; luck=2; defense=4; resistance=2; movement=4
	else:
		hp         = int(data.get("hp", 20))
		strength   = int(data.get("strength", 5))
		magic      = int(data.get("magic", 2))
		skill      = int(data.get("skill", 4))
		speed      = int(data.get("speed", 4))
		luck       = int(data.get("luck", 2))
		defense    = int(data.get("defense", 4))
		resistance = int(data.get("resistance", 2))
		movement   = int(data.get("movement", 4))
	max_hp = hp
