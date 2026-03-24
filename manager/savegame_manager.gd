class_name SaveGame extends Node

# Path del file di salvataggio.  Usare "user://" per la cartella dati dell'utente.
const SAVE_PATH = "user://savegame.json"
const SAVE_ERROR_MESSAGE_KEY = "error_save_file_writing" # Chiave di traduzione per l'errore di salvataggio

signal save_completed
signal load_completed

var game

func _ready():
	game = get_node("/root/Game")


func save_game():
	var data = game.save_game_data()
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)

	if file == null:
		printerr(tr("error_save_file_writing"))
		return

	var json_string = JSON.stringify(data, "\t")
	file.store_string(json_string)
	file.close()
	print("Game saved successfully to: ", SAVE_PATH)
	print("Data saved: ", data)
	
	print("[SAVEGAME] Salvataggio completato.")
	
	emit_signal("save_completed")

func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save file found. Starting new game.")
		game.show_scene("start")
		return

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		printerr("Error opening save file for reading.")
		return

	var json_string = file.get_as_text()
	file.close()

	var data = JSON.parse_string(json_string)
	if data == null or typeof(data) != TYPE_DICTIONARY:
		printerr("Error parsing save file.")
		return

	game.load_game_data(data)
	print("Game loaded successfully from: ", SAVE_PATH)
	
	
	emit_signal("load_completed")
	