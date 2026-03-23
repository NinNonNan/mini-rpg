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

extends Node

# Riferimento al gioco principale.
# Iniettato da Game.gd in _ready().
# Serve per accedere a dati globali come:
# - game.equipment: Oggetti equipaggiati.
# - game.item_data: Database degli oggetti caricato da JSON.
# - game.health / game.max_health: Statistiche del giocatore.
# - game.tr(): Sistema di traduzione.
var game: Game


# =========================================================
# FUNZIONI HELPER (GETTERS)
# =========================================================

# Restituisce il nome localizzato di un oggetto dato il suo ID.
# Esempio: "pozione" -> "item_potion" (dal JSON) -> "Pozione" (da it.json).
func get_item_name(item_id: String) -> String:
	
	# Se l'oggetto non esiste nel database, restituisce l'ID grezzo.
	if not game.item_data.has(item_id):
		return item_id
	
	# Ottiene la chiave di traduzione (es. "item_potion").
	var key = game.item_data[item_id].get("name", item_id)
	
	# Usa il sistema di traduzione globale.
	return game.tr(key)

# Restituisce l'icona (emoji o percorso) di un oggetto.
func get_item_icon(item_id: String) -> String:
	if game.item_data.has(item_id):
		return game.item_data[item_id].get("icon", "")
	return ""

# Cerca nell'inventario del giocatore il primo oggetto che ha la proprietà
# `"consumable": true` nel file items.json.
# Utile per azioni automatiche come "Usa Oggetto" in combattimento.
func get_first_consumable() -> String:
	
	for item_id in game.inventory:
		if game.item_data.has(item_id) and game.item_data[item_id].get("consumable", false):
			return item_id
	
	return ""


# =========================================================
# LOGICA DI GIOCO
# =========================================================

# Calcola il danno fisico del giocatore per un attacco.
# 1. Controlla le armi equipaggiate nelle mani.
# 2. Se ci sono più armi, sceglie la "migliore" (dado più alto, poi qualità).
# 3. Se non ci sono armi, usa il danno base dei pugni (d2).
# 4. Calcola il danno finale sommando il tiro del dado al bonus di qualità.
#
# Restituisce un Array:
# [danno_totale, dado_massimo, bonus_qualità, tipo_danno, nome_arma]
func get_player_damage() -> Array:
	
	# Valori di default (attacco a mani nude)
	var damage_die = 2 # d2
	var damage_quality = 0
	var damage_type = "" # tipo di danno (es. "taglio"), vuoto per default
	var damage_source = game.tr("weapon_fists") # Fonte del danno (default: Pugni)
	
	# Controlliamo solo gli slot delle mani per le armi
	var hand_slots = ["Mano Destra", "Mano Sinistra"]
	
	for slot in hand_slots:
		if game.equipment.has(slot):
			var item_id = game.equipment[slot]
			
			if game.item_data.has(item_id):
				var item_stats = game.item_data[item_id]
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


# Applica gli effetti di un oggetto (es. una pozione).
# - Legge le proprietà dell'oggetto da `item_data`.
# - Applica l'effetto (es. cura).
# - Se l'oggetto è consumabile, lo rimuove dall'inventario.
# - Restituisce una stringa di feedback per la UI.
func use_item(item_id: String) -> String:
	
	if not game.item_data.has(item_id):
		return game.tr("item_use_error")
		
	var item_props = game.item_data[item_id]
	var translated_name = get_item_name(item_id)
	
	
	# ---------------------------
	# OGGETTI DI CURA
	# ---------------------------
	
	if item_props.has("heal"):
		
		var heal_amount = int(item_props.get("heal", 0))
		var quality_bonus = int(item_props.get("quality", 0))
		var total_heal = heal_amount + quality_bonus
		
		# Cura il giocatore senza superare la sua salute massima.
		# NOTA: `game.health` è una proprietà che chiama `modify_player_energy`.
		game.health += total_heal
		
		# Se l'oggetto è consumabile lo rimuoviamo
		if item_props.get("consumable", false):
			game.inventory.erase(item_id)
		
		
		# Messaggio di feedback al giocatore
		return game.tr("combat_item_used") % [translated_name, total_heal]
	
	
	# Oggetto senza effetti definiti
	return game.tr("item_use_no_effect")