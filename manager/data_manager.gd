# =========================================================
class_name DataManager
extends Node

# =========================================================
# DATA MANAGER
# =========================================================
# Gestisce il caricamento, il database e l'integrità dei dati di gioco.
#
# Funzionalità principali:
# - Caricamento centralizzato di story.json, definitions.json ed entities.json.
# - Aggregazione e merging dei dati per l'accesso globale.
# - Fornisce una fonte di verità per scene, entità e tipi di danno.
#
# Scopo narrativo: Rappresenta l'archivio del mondo, contenente 
# le leggi della realtà (definizioni) e le cronache degli eventi (storie).

## Riferimento al gioco principale (Game.gd).
var game: Game

# --- Database Interno ---
## Dizionario completo dei dati della storia e del player.
var story_data: Dictionary = {}
## Tutte le scene caricate.
var story: Dictionary = {}
## Database di tutte le entità (nemici e player).
var entity_data: Dictionary = {}
## Definizioni dei tipi di danno e icone associate.
var damage_types_data: Dictionary = {}

## Carica tutti i file JSON necessari e popola il database interno.
## Input: Nessuno.
## Output: bool - true se il caricamento principale ha avuto successo.
func load_all_data() -> bool:
	# 1. Caricamento Story & Scenes (Percorsi fissi in res://data/)
	var json_data = StoryLoader.load_json_file("res://data/story.json")
	if json_data == null:
		push_error("DataManager: Impossibile caricare story.json")
		return false
	
	story_data = json_data
	story = json_data.get("scenes", {})
	
	# 2. Caricamento Definizioni (Tipi energia, danni, meteo, spell)
	var definitions_json = StoryLoader.load_json_file("res://data/definitions.json")
	if definitions_json != null:
		# Merge profondo per unire le definizioni a story_data per compatibilità HUD
		story_data.merge(definitions_json, true)
		damage_types_data = definitions_json.get("damage_types", {})
	else:
		push_error("DataManager: Impossibile caricare definitions.json")

	# 3. Caricamento Entities (Player e Nemici) da file separato
	var entities_json = StoryLoader.load_json_file("res://data/entities.json")
	if entities_json != null:
		entity_data = entities_json.get("entities", {})
		
		# Gestione speciale per i dati del Player
		var player_data = {}
		if entities_json.has("player"):
			player_data = entities_json.get("player", {})
		else:
			# Fallback su story.json se non presente in entities.json
			player_data = json_data.get("player", {})
			
		story_data["player"] = player_data
	else:
		push_error("DataManager: Impossibile caricare entities.json!")
		# Fallback parziale
		entity_data = json_data.get("entities", {}) 
		
	return true

## Restituisce i dati di un'entità specifica.
## Input: entity_id (String).
## Output: Dictionary.
func get_entity(entity_id: String) -> Dictionary:
	return entity_data.get(entity_id, {})