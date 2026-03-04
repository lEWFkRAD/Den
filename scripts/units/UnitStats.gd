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
	match unit_class:
		"Soldier":
			hp=24; strength=7; magic=2; skill=6; speed=6; luck=4; defense=6; resistance=2; movement=5
		"Archer":
			hp=20; strength=6; magic=3; skill=8; speed=7; luck=5; defense=4; resistance=3; movement=5
		"Mage":
			hp=18; strength=2; magic=9; skill=6; speed=5; luck=5; defense=2; resistance=7; movement=5
		"Knight":
			hp=32; strength=9; magic=1; skill=5; speed=2; luck=3; defense=11; resistance=2; movement=4
		"Rogue":
			hp=19; strength=5; magic=3; skill=9; speed=9; luck=7; defense=3; resistance=3; movement=6
		"Healer":
			hp=17; strength=1; magic=8; skill=6; speed=5; luck=6; defense=2; resistance=8; movement=5
		"Warden":
			hp=28; strength=10; magic=4; skill=7; speed=7; luck=5; defense=8; resistance=5; movement=5
		# ── Enemies ──────────────────────────────────────────────────────────
		"Enemy":
			hp=20; strength=5; magic=2; skill=4; speed=4; luck=2; defense=4; resistance=2; movement=4
		"Enemy_Archer":
			hp=17; strength=5; magic=2; skill=6; speed=5; luck=2; defense=3; resistance=2; movement=5
		"Enemy_Heavy":
			hp=30; strength=8; magic=1; skill=3; speed=2; luck=1; defense=8; resistance=1; movement=3
		"Enemy_Mage":
			hp=16; strength=1; magic=7; skill=5; speed=5; luck=2; defense=1; resistance=6; movement=4
		"Enemy_Rogue":
			hp=18; strength=4; magic=2; skill=7; speed=7; luck=3; defense=3; resistance=2; movement=6
		"Enemy_Knight":
			hp=28; strength=9; magic=1; skill=4; speed=3; luck=1; defense=10; resistance=1; movement=3
		"Enemy_Warden":
			hp=26; strength=9; magic=4; skill=6; speed=6; luck=2; defense=7; resistance=5; movement=5
		"Enemy_Commander":
			hp=38; strength=10; magic=3; skill=7; speed=6; luck=4; defense=9; resistance=4; movement=5
		_:
			hp=20; strength=5; magic=2; skill=4; speed=4; luck=2; defense=4; resistance=2; movement=4
	max_hp = hp
