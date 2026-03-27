# =========================================================
# ITEM MANAGER
# =========================================================
# Gestisce tutte le operazioni relative agli oggetti:
# - Recupero di nomi e icone per la UI.
# - Calcolo del danno del giocatore in base all'equipaggiamento.
# - Logica per l'utilizzo di oggetti consumabili (es. pozioni).
#
# Funziona come un "servizio" per gli altri manager e per Game.gd,
# centralizzando la logica degli oggetti in un unico posto.

class_name ItemManager
extends Node

# Riferimento al nodo principale del gioco per aggiornamenti UI e stati.
var game: Game

# --- Stato dell'Inventario e Equipaggiamento ---
# Elenco degli ID degli oggetti posseduti e non equipaggiati.
var inventory: Array = []
# Mappa che associa il nome dello slot (String) all'ID dell'oggetto (String).
var equipment: Dictionary = {}
# Elenco degli slot disponibili per l'equipaggiamento.
var equipment_slots: Array[String] = ["stats_hand_right", "stats_hand_left", "stats_body", "stats_head", "stats_accessory"]
# Database locale degli oggetti caricato da JSON.
var item_data: Dictionary = {}

## Carica le definizioni degli oggetti dal file JSON.
## Input: Nessuno (legge da res://data/items.json).
## Output: Nessuno (popola la variabile item_data).
func load_items():
	var items_json = StoryLoader.load_json_file("res://data/items.json")
	if items_json != null:
		item_data = items_json

## Aggiunge un oggetto all'inventario se non è già presente.
## Input: item_id (String) - L'identificatore univoco dell'oggetto.
## Output: bool - true se l'oggetto è stato aggiunto, false altrimenti.
func add_item(item_id: String) -> bool:
	if item_id == "" or item_id in inventory:
		return false
	inventory.append(item_id)
	return true

## Sposta un oggetto dall'inventario a uno slot di equipaggiamento.
## Input: item_id (String) - ID dell'oggetto; slot (String) - Nome dello slot di destinazione.
## Output: Nessuno (aggiorna lo stato interno e la UI).
func equip_item(item_id: String, slot: String):
	if slot in equipment:
		unequip_item(slot)
	
	if item_id in inventory:
		inventory.erase(item_id)
		equipment[slot] = item_id
		game.update_stats()

## Rimuove un oggetto da uno slot e lo riporta nell'inventario.
## Input: slot (String) - Il nome dello slot da liberare.
## Output: Nessuno (aggiorna lo stato interno e la UI).
func unequip_item(slot: String):
	if slot in equipment:
		var item_id = equipment[slot]
		equipment.erase(slot)
		inventory.append(item_id)
		game.update_stats()

## Svuota completamente inventario ed equipaggiamento.
## Input: Nessuno.
## Output: Nessuno.
func reset():
	inventory.clear()
	equipment.clear()

## Restituisce il nome localizzato di un oggetto.
## Input: item_id (String) - ID dell'oggetto.
## Output: String - Il nome tradotto o l'ID se l'oggetto non esiste nel database.
func get_item_name(item_id: String) -> String:
	if not item_data.has(item_id):
		return item_id
	
	var key = item_data[item_id].get("name", item_id)
	return tr(key)

## Restituisce l'icona (emoji o percorso risorsa) associata all'oggetto.
## Input: item_id (String) - ID dell'oggetto.
## Output: String - L'icona definita nel JSON o stringa vuota.
func get_item_icon(item_id: String) -> String:
	if item_data.has(item_id):
		return item_data[item_id].get("icon", "")
	return ""

## Restituisce una stringa formattata pronta per la UI (Icona + Nome).
## Input: item_id (String) - ID dell'oggetto.
## Output: String - Esempio: "🧪 Pozione".
func get_display_name(item_id: String) -> String:
	var icon = get_item_icon(item_id)
	var item_name = get_item_name(item_id)
	return ("%s " % icon if icon != "" else "") + item_name

## Trova il primo oggetto consumabile disponibile nell'inventario.
## Input: Nessuno.
## Output: String - L'ID dell'oggetto trovato o stringa vuota se non ci sono consumabili.
func get_first_consumable() -> String:
	for item_id in inventory:
		if item_data.has(item_id) and item_data[item_id].get("consumable", false):
			return item_id
	
	return ""

## Calcola il danno del giocatore analizzando l'arma migliore equipaggiata nelle mani.
## La logica sceglie l'arma con il dado di danno più alto (o qualità superiore a parità di dado).
## Input: Nessuno.
## Output: Array - [int totale, int dado, int bonus, String tipo, String nome_arma].
## Esempio: [7, 6, 1, "taglio", "Spada"]
func get_player_damage() -> Array:
	var damage_die = 2 # d2
	var damage_quality = 0
	var damage_type = "" # tipo di danno (es. "taglio"), vuoto per default
	var damage_source = tr("weapon_fists") # Fonte del danno (default: Pugni)
	
	# Controlliamo solo gli slot delle mani per le armi
	var hand_slots = ["stats_hand_right", "stats_hand_left"]
	
	for slot in hand_slots:
		if equipment.has(slot):
			var item_id = equipment[slot]
			
			if item_data.has(item_id):
				var item_stats = item_data[item_id]
				var item_die = int(item_stats.get("damage", 0))
				
				# Ignoriamo oggetti che non fanno danno (es. torcia se ha danno 0) o consumabili equipaggiati
				if item_die <= 0:
					continue

				var item_qual = int(item_stats.get("quality", 0))
				var item_type = item_stats.get("type", "")
				var item_name = get_item_name(item_id)
				
				# Logica per scegliere l'arma migliore tra le due mani
				if item_die > damage_die:
					damage_die = item_die
					damage_quality = item_qual
					damage_type = item_type
					damage_source = item_name
				elif item_die == damage_die:
					# A parità di dado, preferiamo quella con più qualità o che ha un tipo definito (es. Daga d2 vs Pugni d2)
					if item_qual > damage_quality or (damage_type == "" and item_type != ""):
						damage_quality = item_qual
						damage_type = item_type
						damage_source = item_name
	
	# Genera il danno casuale
	var damage_roll = randi_range(1, damage_die)
	var total_damage = damage_roll + damage_quality
	
	return [total_damage, damage_die, damage_quality, damage_type, damage_source]

## Esegue l'azione associata a un oggetto (es. cura) e lo rimuove se consumabile.
## Supporta sia il vecchio formato "heal" che il nuovo "restore".
## Input: item_id (String) - ID dell'oggetto da usare.
## Output: String - Messaggio di feedback localizzato per il log di gioco.
func use_item(item_id: String) -> String:
	if not item_data.has(item_id):
		return tr("item_use_error")
		
	var item_props = item_data[item_id]
	var translated_name = get_item_name(item_id)
	
	# Gestione "heal" (formato vecchio/semplice) o "restore" (formato avanzato)
	if item_props.has("heal") or item_props.has("restore"):
		var type = "life"
		var amount = 0
		
		if item_props.has("restore"):
			var restore_info = item_props["restore"]
			type = restore_info.get("type", "life")
			amount = int(restore_info.get("value", 0))
		else:
			amount = int(item_props.get("heal", 0)) + int(item_props.get("quality", 0))

		# Applica l'effetto
		game.modify_player_energy(type, amount)
		
		# Rimuovi se consumabile
		if item_props.get("consumable", false):
			inventory.erase(item_id)
			
		# Recupera nome energia per il log
		var energy_name = type
		var energy_defs = game.story_data.get("energy_types", {})
		if energy_defs.has(type):
			energy_name = tr(energy_defs[type].get("name", type))

		return tr("log_consumable_use") % [translated_name, amount, energy_name]

	# Oggetto senza effetti definiti
	return tr("item_use_no_effect")