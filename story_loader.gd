# d:/___SVILUPPO/mini-rpg/mini-rpg/story_loader.gd
# =========================================================
# STORY LOADER
# =========================================================
# Utility per il caricamento di file JSON dal filesystem.
#
# Funzionalità:
# - Verifica esistenza file.
# - Parsing JSON sicuro.
# - Validazione tipo dati (deve essere un Dizionario).
#
# Essendo una classe 'static', non necessita di essere istanziata.
# Usato da Game.gd per caricare story.json, items.json, ecc.

class_name StoryLoader
extends RefCounted

# Carica un file JSON e restituisce un Dizionario.
# Restituisce null se c'è un errore.
static func load_json_file(file_path: String):
	# 1. Verifica esistenza file
	if not FileAccess.file_exists(file_path):
		push_error(TranslationServer.translate("error_story_loader_file_not_found") + " " + file_path)
		return null

	var file = FileAccess.open(file_path, FileAccess.READ)
	var json_string = file.get_as_text()
	
	# 2. Parsing
	# JSON.parse_string restituisce null se il parsing fallisce
	var json_data = JSON.parse_string(json_string)
	
	if json_data == null:
		push_error(TranslationServer.translate("error_story_loader_parse") + " " + file_path)
		return null
		
	# 3. Validazione Tipo
	# Ci aspettiamo sempre un Dizionario {} come root, non un Array []
	if typeof(json_data) != TYPE_DICTIONARY:
		push_error(TranslationServer.translate("error_story_loader_type"))
		return null

	return json_data
