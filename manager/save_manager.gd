class_name SaveManager
extends Node

var game: Game

const SAVE_PATH = "user://savegame.json"

func save_game():
	if not game:
		return
	
	var data = {
		"current_scene": game.current_scene,
		"player_energy": game.stats_manager.player_energy if game.stats_manager else {},
		"player_max_energy": game.stats_manager.player_max_energy if game.stats_manager else {},
		"inventory": game.item_manager.inventory if game.item_manager else [],
		"equipment": game.item_manager.equipment if game.item_manager else {},
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

	if game.stats_manager:
		if data.has("player_energy"): game.stats_manager.player_energy = data["player_energy"]
		if data.has("player_max_energy"): game.stats_manager.player_max_energy = data["player_max_energy"]
		game.stats_manager.stats_changed.emit()
	
	if game.item_manager:
		if data.has("inventory"): game.item_manager.inventory = data["inventory"]
		if data.has("equipment"): game.item_manager.equipment = data["equipment"]
	
	if data.has("current_entity_id"): game.current_entity_id = data["current_entity_id"]
	if data.has("was_in_combat"): game.was_in_combat = data["was_in_combat"]
	
	return true

func delete_save():
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
