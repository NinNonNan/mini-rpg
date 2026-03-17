# d:/___SVILUPPO/mini-rpg/mini-rpg/story_loader.gd
class_name StoryLoader
extends RefCounted

# Carica un file JSON e restituisce un Dizionario.
# Restituisce null se c'è un errore.
static func load_json_file(file_path: String):
	if not FileAccess.file_exists(file_path):
		push_error("StoryLoader: File non trovato in " + file_path)
		return null

	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_string = file.get_as_text()
	var json_data = JSON.parse_string(json_string)
	
	if json_data == null:
		push_error("StoryLoader: Errore nel parsing del JSON (formato non valido).")
		return null
		
	if typeof(json_data) != TYPE_DICTIONARY:
		push_error("StoryLoader: Il JSON non contiene un dizionario principale.")
		return null

	return json_data
