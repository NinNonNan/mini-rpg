class_name SaveManager
extends Node

var game: Game

const SAVE_PATH = "user://savegame.json"

func save_game():
	if not game:
		return
	
	var data = {
		"current_scene": game.current_scene,
		"player_energy": game.player_energy,
		"player_max_energy": game.player_max_energy,
		"inventory": game.inventory,
		"equipment": game.equipment,
		"current_entity_id": game.current_entity_id,
		"was_in_combat": game.was_in_combat
	}
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
		
	var content = file.get_as_text()
	file.close()
	
	var data = JSON.parse_string(content)
	if data == null:
		return false
		
	if not game:
		return false
		
	# Ripristino stato
	if data.has("current_scene"): game.current_scene = data["current_scene"]
	if data.has("player_energy"): game.player_energy = data["player_energy"]
	if data.has("player_max_energy"): game.player_max_energy = data["player_max_energy"]
	if data.has("inventory"): game.inventory = data["inventory"]
	if data.has("equipment"): game.equipment = data["equipment"]
	if data.has("current_entity_id"): game.current_entity_id = data["current_entity_id"]
	if data.has("was_in_combat"): game.was_in_combat = data["was_in_combat"]
	
	return true

func delete_save():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
