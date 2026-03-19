extends Node

# ---------------------------------------------------------
# RIFERIMENTO AL GAME
# ---------------------------------------------------------

# Riferimento alla classe principale Game.
# Viene assegnato in Game._ready() con:
# item_manager.game = self
#
# Serve per accedere a:
# - game.inventory   -> inventario del giocatore
# - game.item_data   -> database degli oggetti caricato dal JSON
# - game.health      -> salute del giocatore
# - game.tr()        -> sistema di traduzione
var game: Game


# ---------------------------------------------------------
# NOME OGGETTO
# ---------------------------------------------------------

# Restituisce il nome tradotto di un oggetto dato il suo ID.
# Gli ID degli oggetti provengono da:
# game.inventory
#
# Il nome vero dell'oggetto è salvato nel JSON item_data
# come chiave di traduzione.
func get_item_name(item_id: String) -> String:
	
	# Se l'oggetto non esiste nel database
	if not game.item_data.has(item_id):
		return item_id
	
	# Ottiene la chiave di traduzione
	# esempio: "item_potion"
	var key = game.item_data[item_id].get("name", item_id)
	
	# Usa il sistema di traduzione del Game
	return game.tr(key)


# ---------------------------------------------------------
# ICONA OGGETTO
# ---------------------------------------------------------

func get_item_icon(item_id: String) -> String:
	if game.item_data.has(item_id):
		return game.item_data[item_id].get("icon", "")
	return ""


# ---------------------------------------------------------
# RICERCA CONSUMABILI
# ---------------------------------------------------------

# Cerca nell'inventario del giocatore il primo oggetto
# che possiede la proprietà "consumable".
#
# Utile per azioni automatiche come:
# "usa la prima pozione disponibile".
#
# Restituisce:
# - item_id se trovato
# - "" se nessun consumabile è presente
func get_first_consumable() -> String:
	
	for item_id in game.inventory:
		if game.item_data.has(item_id) and game.item_data[item_id].get("consumable", false):
			return item_id
	
	return ""


# ---------------------------------------------------------
# CALCOLO DANNO GIOCATORE
# ---------------------------------------------------------

# Determina il danno del giocatore in base alle armi
# presenti nell'inventario.
#
# Ogni arma può avere nel JSON la proprietà:
# "damage"
#
# Il valore rappresenta il dado massimo di danno.
#
# Esempio:
# sword -> damage: 6  (d6)
#
# Se il giocatore non ha armi usa il danno base:
# pugni -> d2
#
# Restituisce:
# [danno_totale, dado_massimo, bonus_qualità, tipo_danno]
func get_player_damage() -> Array:
	
	var damage_die = 2 # danno base (pugni)
	var damage_quality = 0 # bonus fisso base
	var damage_type = "" # tipo di danno (es. "taglio"), vuoto per default
	
	for item_id in game.inventory:
		if game.item_data.has(item_id):
			
			var item_stats = game.item_data[item_id]
			var item_die = int(item_stats.get("damage", 0))
			var item_qual = int(item_stats.get("quality", 0))
			var item_type = item_stats.get("type", "")
			
			# Logica per scegliere l'arma migliore:
			# Privilegiamo il dado più alto. A parità di dado, chi ha più qualità.
			if item_die > damage_die:
				damage_die = item_die
				damage_quality = item_qual
				damage_type = item_type
			elif item_die == damage_die:
				if item_qual > damage_quality:
					damage_quality = item_qual
					damage_type = item_type
	
	# Genera il danno casuale
	var damage_roll = randi_range(1, damage_die)
	var total_damage = damage_roll + damage_quality
	
	return [total_damage, damage_die, damage_quality, damage_type]


# ---------------------------------------------------------
# UTILIZZO OGGETTO
# ---------------------------------------------------------

# Applica gli effetti di un oggetto.
#
# Attualmente supporta:
# - cura (heal)
#
# Se l'oggetto è consumabile viene rimosso
# dall'inventario del giocatore.
#
# Restituisce una stringa da mostrare nel testo di gioco.
func use_item(item_id: String) -> String:
	
	if not game.item_data.has(item_id):
		return "Errore: Oggetto non trovato."
		
	var item_props = game.item_data[item_id]
	var translated_name = get_item_name(item_id)
	
	
	# ---------------------------
	# OGGETTI DI CURA
	# ---------------------------
	
	if item_props.has("heal"):
		
		var heal_amount = int(item_props.get("heal", 0))
		var quality_bonus = int(item_props.get("quality", 0))
		var total_heal = heal_amount + quality_bonus
		
		# Cura il giocatore senza superare il limite
		# (in Game la salute iniziale è 10)
		game.health = min(game.health + total_heal, 10)
		
		
		# Se l'oggetto è consumabile lo rimuoviamo
		if item_props.get("consumable", false):
			game.inventory.erase(item_id)
		
		
		# Messaggio di feedback al giocatore
		return game.tr("combat_item_used") % [translated_name, total_heal]
	
	
	# Oggetto senza effetti definiti
	return "Non succede nulla."