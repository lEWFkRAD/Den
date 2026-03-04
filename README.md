# DEN — Prototype v0.2
### A tactical RPG of magic, memory, and machine.

---

## Setup

1. Download **Godot Engine 4.x** → https://godotengine.org/download
2. Launch Godot → **Import** → select this folder's `project.godot`
3. Press **F5** or ▶ to run

---

## What's New in v0.2

**Player Attacks** — Full combat system. Click a unit, open the action menu, choose Attack. Select an enemy. See the combat forecast (damage, hit%, crit%, counterattack). Confirm and watch it resolve.

**Combat Forecast** — Before committing to an attack you see exactly what happens: your damage, hit rate, crit%, whether you double, whether they counter, whether they double you.

**Weapon System** — 20+ weapons across 8 types: Sword, Lance, Axe, Bow, Tome, Dagger, Staff, Greatsword. Each with attack, hit, crit, range, and durability. Elemental tomes carry an element. Staves heal.

**Weapon Triangle** — Sword beats Axe beats Lance beats Sword. +15 Hit and +1 damage when advantaged.

**Kip Combat** — Deployed Kips auto-attack during the Kip Phase between your turns and the enemy's. Bolt will chain from range. Scar will hit hard. Thorn will hold the line.

**Awakening Damage** — Awakening now deals real AoE damage to all enemies in radius, scales with the Kip's attack stat and element. Plus tile effects.

**Action Menu** — After moving, a full contextual action menu: Attack, Deploy/Recall Kip, Awaken, Items, Swap Weapon, Wait, Back.

**Back Action** — Changed your mind? Hit Back to undo your move and reselect.

**Items** — Vulnerary (heal 10HP, 3 uses), Elixir (full heal), Kip Salve (restore exhausted Kip), Pure Water (RES+7), Energy Drop (permanent STR+2).

**Healing Staves** — Seren (Healer) uses her Physic Staff to heal allies from range. Select Seren, choose Attack, then pick an ally to heal.

**7 Playable Characters** — Aldric (Soldier/Scar), Mira (Archer/Bolt), Voss (Mage/Null), Seren (Healer/Solen), Bram (Knight/Thorn), Corvin (Rogue/Dusk), Yael (Mage/Sleet)

**8 Distinct Enemies** — Grunt, Scout (archer), Ironhelm (heavy), Hexblade (dark mage), Cutthroat (rogue), Blood Knight, Void Warden, Commander Varek

**All 8 Kips Implemented** — Scar (Blood), Bolt (Electric), Null (Void), Solen (Light), Thorn (Plant), Dusk (Dark), Sleet (Ice), The First (God)

---

## How to Play

### Moving and Acting
1. **Click a blue unit** → see movement range (blue tiles)
2. **Click a blue tile** (or the unit's own tile) → action menu appears
3. **Choose an action** from the right panel

### Combat
1. Choose **Attack** → enemies in weapon range highlight red
2. Click an enemy → **Combat Forecast** shows damage/hit/crit for both sides
3. Click **Confirm** to resolve, or **Back** to reconsider

### Kip Actions
- **Deploy Kip** — Kip steps off unit, fights independently next Kip Phase
- **Recall Kip** — Bring Kip back to companion (safe)
- **Awaken Kip** — Kip transforms. Massive AoE damage + tile effects. One per battle.

### Healing
- Select Seren → Attack → choose ally to heal (green range shown)

### Turn Flow
```
Player Phase → [all units act] → Kip Phase → Enemy Phase → Player Phase
```

---

## Unit Roster

| Name | Class | Kip | Element | Weapon | Special |
|---|---|---|---|---|---|
| Aldric | Soldier | Scar | Blood | Steel Sword | Tank/striker |
| Mira | Archer | Bolt | Electric | Steel Bow | Ranged, 2-3 range |
| Voss | Mage | Null | Void | Void/Dark Tome | Magical damage |
| Seren | Healer | Solen | Light | Physic Staff | Heals allies at range |
| Bram | Knight | Thorn | Plant | Steel Lance | High DEF, low MOV |
| Corvin | Rogue | Dusk | Dark | Venomed Dagger | High SPD, high crit |
| Yael | Mage | Sleet | Ice | Ice/Lightning Tome | Area control |

---

## Weapon Triangle

```
Sword  ←beats← Axe
  ↓                ↑
Lance →beats→ Sword (wait, that's circular)

Actually:
Sword → Axe → Lance → Sword
```
+15 Hit and +1 damage when using the advantaged weapon.

---

## Shape Legend

| Shape | Class |
|---|---|
| ■ Square | Soldier / Enemy |
| ◆ Diamond | Archer |
| ● Circle | Mage |
| ■■ Thick Square | Knight / Heavy |
| ▲ Triangle | Rogue |
| + Cross | Healer |
| ★ Star | Warden / Commander |

| Dot Color | Kip Element |
|---|---|
| Red | Blood |
| Yellow | Electric |
| Dark Purple | Void |
| Gold | Light |
| Green | Plant |
| Smoky Purple | Dark |
| Blue-white | Ice |
| Near-white | God |

---

## Architecture

```
autoloads/
  ElementRegistry.gd   — Both rings, cross-ring, damage multipliers
  BattleState.gd       — Phase state, kip speech signal, unit death signal
  GameState.gd         — Persistent campaign state
  CombatResolver.gd    — Hit%, damage, crit%, forecasts, weapon triangle, kip attacks
  CharacterRoster.gd   — All character and enemy definitions, factory methods

scripts/
  battle/
    Battle.gd          — State machine: IDLE/SELECTED/ACTION/ATTACK/FORECAST/ITEMS
    Grid.gd            — Renders units, handles highlights, flash effects, pathfinding
    Tile.gd            — Per-tile state: terrain, elemental state, occupant
    TurnManager.gd     — Player/Kip/Enemy phase management, enemy AI
  units/
    Unit.gd            — Data: stats, weapon, items, Kip bond, attack range
    UnitStats.gd       — Stat blocks for all classes
  kips/
    Kip.gd             — All 8 Kips: personality, three-phase system, combat
  items/
    Weapon.gd          — 20+ weapons with full stats
    Item.gd            — Consumables with use() logic
```

---

*The world is called Den because it is where things go to survive.*
*The Kips survived. They are waking up.*
*What they find when they open their eyes — that is the story.*
