class_name CampaignState
extends RefCounted
## Tracks the active campaign: which missions are done, current mission index,
## inventory from loot, currency, and experience totals.


## Unique identifier for this campaign run
var campaign_id: String = ""

## Master seed used to generate this campaign
var campaign_seed: int = 0

## Active major story arc id
var major_arc: String = ""

## Active minor story arc id
var minor_arc: String = ""

## Ordered list of region id strings used in this run
var regions: Array = []

## All mission dictionaries in order
var missions: Array = []

## Index into missions array for the next/current mission
var current_mission_index: int = 0

## Array of mission id strings that have been completed
var completed_missions: Array = []

## Array of ItemJSON dictionaries collected from loot
var inventory: Array = []

## Current gold balance
var gold: int = 0

## Total accumulated experience points
var total_xp: int = 0


## Populates all fields from a campaign data dictionary (as returned by
## CampaignGenerator.generate_campaign).
func load_campaign(campaign_data: Dictionary) -> void:
	campaign_id = campaign_data.get("id", "")
	campaign_seed = campaign_data.get("seed", 0)
	major_arc = campaign_data.get("major_arc", "")
	minor_arc = campaign_data.get("minor_arc", "")
	regions = campaign_data.get("regions", []).duplicate()
	missions = campaign_data.get("missions", []).duplicate(true)
	current_mission_index = 0
	completed_missions.clear()
	inventory.clear()
	gold = 0
	total_xp = 0


## Returns the current mission dictionary, or an empty dictionary if all
## missions are complete or the index is out of range.
func get_current_mission() -> Dictionary:
	if current_mission_index >= 0 and current_mission_index < missions.size():
		return missions[current_mission_index]
	return {}


## Marks the current mission as complete and processes its rewards.
## won: Whether the player won the mission.
## loot_items: Array of ItemJSON dictionaries awarded as loot.
func complete_mission(won: bool, loot_items: Array) -> void:
	if current_mission_index < 0 or current_mission_index >= missions.size():
		return

	var mission: Dictionary = missions[current_mission_index]
	var mission_id: String = mission.get("id", "")

	if mission_id != "" and mission_id not in completed_missions:
		completed_missions.append(mission_id)

	# Add loot items to inventory
	for item: Dictionary in loot_items:
		inventory.append(item.duplicate(true))

	# Process rewards if the player won
	if won:
		var rewards: Dictionary = mission.get("rewards", {})
		gold += rewards.get("gold", 0)
		total_xp += rewards.get("xp", 0)

	# Advance to the next mission
	current_mission_index += 1


## Returns true if all missions in the campaign have been completed.
func is_campaign_complete() -> bool:
	return current_mission_index >= missions.size() and not missions.is_empty()


## Serializes the full campaign state to a dictionary for JSON persistence.
func serialize() -> Dictionary:
	return {
		"campaign_id": campaign_id,
		"campaign_seed": campaign_seed,
		"major_arc": major_arc,
		"minor_arc": minor_arc,
		"regions": regions.duplicate(),
		"missions": missions.duplicate(true),
		"current_mission_index": current_mission_index,
		"completed_missions": completed_missions.duplicate(),
		"inventory": inventory.duplicate(true),
		"gold": gold,
		"total_xp": total_xp,
	}


## Loads campaign state from a previously serialized dictionary.
func deserialize(data: Dictionary) -> void:
	campaign_id = data.get("campaign_id", "")
	campaign_seed = data.get("campaign_seed", 0)
	major_arc = data.get("major_arc", "")
	minor_arc = data.get("minor_arc", "")
	regions = data.get("regions", []).duplicate()
	missions = data.get("missions", []).duplicate(true)
	current_mission_index = data.get("current_mission_index", 0)
	completed_missions = data.get("completed_missions", []).duplicate()
	inventory = data.get("inventory", []).duplicate(true)
	gold = data.get("gold", 0)
	total_xp = data.get("total_xp", 0)
