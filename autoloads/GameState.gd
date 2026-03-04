extends Node

var chapter: int = 1
var army: Array = []      # Array of unit save data
var gold: int = 0
var kips_encountered: Array = []

signal chapter_started(chapter_num: int)
signal unit_lost(unit_name: String)

func start_chapter(num: int):
	chapter = num
	chapter_started.emit(chapter)

func record_kip_encounter(kip_name: String):
	if not kip_name in kips_encountered:
		kips_encountered.append(kip_name)
